#!/bin/bash
##########################################################
# MySQL 8 Installation - Strict CCC CODE Pattern
# ALLE Daten in $STORAGE_ROOT/mysql
# setup/modules/mysql8.sh
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} MySQL 8 Installation (CCC CODE Style)..."

# MySQL Data Directory in Storage Root
MYSQL_DATA_DIR="$STORAGE_ROOT/mysql"
MYSQL_RUN_DIR="/var/run/mysqld"

# MySQL Root Password setzen/lesen
if [ -z "$DB_ROOT_PASS" ]; then
    if [ -f "$STORAGE_ROOT/mysql/root-pass.txt" ]; then
        DB_ROOT_PASS=$(cat "$STORAGE_ROOT/mysql/root-pass.txt")
    else
        DB_ROOT_PASS=$(openssl rand -base64 32)
        mkdir -p "$STORAGE_ROOT/mysql"
        echo "$DB_ROOT_PASS" > "$STORAGE_ROOT/mysql/root-pass.txt"
        chmod 600 "$STORAGE_ROOT/mysql/root-pass.txt"
    fi
fi

# MySQL Repository hinzufügen (nur bei erster Installation)
if [ ! -f /etc/apt/sources.list.d/mysql.list ] && ! command -v mysql &> /dev/null; then
    log_info "Füge MySQL Repository hinzu..."
    wget -O /tmp/mysql-apt-config.deb https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
    dpkg -i /tmp/mysql-apt-config.deb || apt-get install -f -y
    rm -f /tmp/mysql-apt-config.deb
    apt-get update -qq
fi

# MySQL Server installieren falls nicht vorhanden
if ! command -v mysql &> /dev/null; then
    log_info "Installiere MySQL Server..."
    
    # Non-interactive Installation
    debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password $DB_ROOT_PASS"
    debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password $DB_ROOT_PASS"
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        mysql-server \
        mysql-client \
        mysql-common
    
    if [ $? -ne 0 ]; then
        log_error "MySQL Installation fehlgeschlagen"
        exit 1
    fi
else
    log_info "MySQL ist bereits installiert"
fi

# MySQL stoppen bevor wir Konfiguration ändern
log_info "Stoppe MySQL für Konfiguration..."
systemctl stop mysql 2>/dev/null || true
sleep 3

# MySQL Data Directory in unserer Storage Root sicherstellen
if [ ! -f "$MYSQL_DATA_DIR/mysql.installed" ]; then
    log_info "Konfiguriere MySQL Data Directory..."
    
    # Data Directory erstellen mit korrekten Berechtigungen
    mkdir -p "$MYSQL_DATA_DIR"
    
    # KRITISCH: MySQL Benutzer muss Besitzer des Data Directories sein
    chown -R mysql:mysql "$MYSQL_DATA_DIR"
    chmod 750 "$MYSQL_DATA_DIR"
    
    # Run Directory erstellen mit korrekten Berechtigungen
    mkdir -p "$MYSQL_RUN_DIR"
    chown -R mysql:mysql "$MYSQL_RUN_DIR"
    chmod 755 "$MYSQL_RUN_DIR"
    
    # Falls Daten in /var/lib/mysql existieren, migrieren wir sie
    if [ -d "/var/lib/mysql" ] && [ ! -L "/var/lib/mysql" ] && [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
        log_info "Migriere existierende MySQL-Daten nach $MYSQL_DATA_DIR"
        
        # MySQL Daten sichern und migrieren
        rsync -av /var/lib/mysql/ "$MYSQL_DATA_DIR/" || {
            log_error "Datenmigration fehlgeschlagen"
            exit 1
        }
        
        # Original-Daten sichern
        mv /var/lib/mysql /var/lib/mysql.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Symlink von /var/lib/mysql zu unserem Storage (für Kompatibilität)
    if [ ! -L "/var/lib/mysql" ]; then
        ln -sf "$MYSQL_DATA_DIR" /var/lib/mysql
        chown -R mysql:mysql /var/lib/mysql
    fi
    
    # Haupt-my.cnf konfigurieren - WICHTIG: datadir muss auf /var/lib/mysql zeigen für Kompatibilität
    mkdir -p /etc/mysql/conf.d
    cat > /etc/mysql/conf.d/ccc-code.cnf << MYSQLCCC
[mysqld]
# CCC CODE Pattern: Daten in Storage Root, aber Kompatibilität mit Standard-Pfaden
datadir = /var/lib/mysql
socket = /var/run/mysqld/mysqld.sock
log-error = /var/log/mysql/error.log
pid-file = /var/run/mysqld/mysqld.pid

# Ghost & BookStack Optimizations
innodb_buffer_pool_size = 256M
innodb_log_file_size = 128M
max_connections = 100

# UTF-8 Settings
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
default_authentication_plugin = mysql_native_password

# Performance
skip-name-resolve

[client]
socket = /var/run/mysqld/mysqld.sock
MYSQLCCC
    
    # MySQL System initialisieren falls Data Directory leer ist
    if [ -z "$(ls -A "$MYSQL_DATA_DIR")" ]; then
        log_info "Initialisiere MySQL Data Directory..."
        mysqld --initialize-insecure --user=mysql --datadir="$MYSQL_DATA_DIR"
        # Nach Initialisierung erneut Berechtigungen setzen
        chown -R mysql:mysql "$MYSQL_DATA_DIR"
    fi
    
    # Markiere als konfiguriert
    touch "$MYSQL_DATA_DIR/mysql.installed"
fi

# MySQL Service sicherstellen
log_info "Konfiguriere MySQL Service..."
systemctl daemon-reload

# AppArmor für MySQL anpassen falls nötig (für /home/user-data/mysql Zugriff)
if [ -d "/etc/apparmor.d" ] && [ -f "/etc/apparmor.d/usr.sbin.mysqld" ]; then
    log_info "Passe AppArmor für MySQL an..."
    if ! grep -q "$MYSQL_DATA_DIR" /etc/apparmor.d/usr.sbin.mysqld 2>/dev/null; then
        sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $MYSQL_DATA_DIR/** rwk," /etc/apparmor.d/usr.sbin.mysqld
        systemctl reload apparmor
    fi
fi

# MySQL Service starten mit Retry-Logic
log_info "Starte MySQL Service..."
for attempt in {1..3}; do
    systemctl enable mysql
    systemctl start mysql
    
    # Warten und prüfen ob MySQL läuft
    sleep 5
    if systemctl is-active --quiet mysql; then
        log_success "MySQL Service erfolgreich gestartet"
        break
    else
        log_warning "MySQL Start Versuch $attempt fehlgeschlagen"
        
        # Debug-Informationen
        echo -e "${YELLOW}=== MySQL Service Status ===${NC}"
        systemctl status mysql --no-pager -l
        
        if [ $attempt -eq 3 ]; then
            log_error "MySQL konnte nicht gestartet werden"
            log_info "Prüfe Berechtigungen für $MYSQL_DATA_DIR:"
            ls -la "$MYSQL_DATA_DIR" | head -10
            log_info "MySQL Logs:"
            journalctl -u mysql --no-pager -n 20
            exit 1
        fi
        
        # Vor nächstem Versuch stoppen
        systemctl stop mysql 2>/dev/null
        sleep 3
    fi
done

# Warten bis MySQL ready ist und Verbindung akzeptiert
log_info "Warte auf MySQL Verfügbarkeit..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        log_success "MySQL ist bereit"
        break
    elif [ $i -eq 30 ]; then
        log_warning "MySQL antwortet nicht, aber fahre fort..."
        break
    fi
    sleep 2
done

# Root Passwort setzen falls nicht gesetzt (bei neuer Installation)
if mysql -uroot -e "SELECT 1;" &>/dev/null 2>/dev/null; then
    log_info "MySQL root Zugriff ohne Passwort möglich - setze Passwort..."
    mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;" 2>/dev/null
fi

# MySQL Secure Installation (idempotent)
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL 2>/dev/null
    DELETE FROM mysql.user WHERE User='' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;
EOSQL

# Ghost Database erstellen (falls nicht existiert)
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL
        CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
        GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
        FLUSH PRIVILEGES;
EOSQL
else
    log_warning "Konnte keine Verbindung zu MySQL herstellen - überspringe Datenbank-Erstellung"
fi

# Root Password in ccc.conf speichern
if ! grep -q "DB_ROOT_PASS" /etc/ccc.conf; then
    echo "DB_ROOT_PASS=$DB_ROOT_PASS" >> /etc/ccc.conf
fi

# Finaler Health Check
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    log_success "MySQL 8 Installation abgeschlossen (CCC CODE Style)"
    log_info "MySQL Data: $MYSQL_DATA_DIR"
    log_info "MySQL Socket: /var/run/mysqld/mysqld.sock"
else
    log_warning "MySQL Installation abgeschlossen, aber Health Check fehlgeschlagen"
fi
