#!/bin/bash
##########################################################
# MySQL 8 Installation - Strict CCC CODE Pattern
# OPTIMIERT für Ubuntu 24.04 - Verbesserte Berechtigungen
# setup/modules/mysql8.sh
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} MySQL 8 Installation (CCC CODE Style - Optimierte Berechtigungen)..."

# MySQL Data Directory in Storage Root
MYSQL_DATA_DIR="$STORAGE_ROOT/mysql"
MYSQL_RUN_DIR="/var/run/mysqld"

# MySQL Root Password setzen
if [ -z "$DB_ROOT_PASS" ]; then
    DB_ROOT_PASS=$(openssl rand -base64 32)
    mkdir -p "$STORAGE_ROOT/mysql"
    echo "$DB_ROOT_PASS" > "$STORAGE_ROOT/mysql/root-pass.txt"
    chmod 660 "$STORAGE_ROOT/mysql/root-pass.txt"  # 660 für ccc-data:mysql
    log_info "MySQL Root-Passwort generiert und gespeichert"
fi

# Schritt 1: Verzeichnisstruktur mit optimierten Berechtigungen vorbereiten
log_info "Bereite Verzeichnisstruktur mit optimierten Berechtigungen vor..."
mkdir -p "$MYSQL_DATA_DIR"
mkdir -p "$MYSQL_RUN_DIR"

# OPTIMIERT: ccc-data:mysql mit 770 Berechtigungen
chown -R ccc-data:mysql "$MYSQL_DATA_DIR"
chmod -R 770 "$MYSQL_DATA_DIR"

# Run Directory bleibt bei mysql:mysql für Service-Kompatibilität
chown -R mysql:mysql "$MYSQL_RUN_DIR"
chmod 755 "$MYSQL_RUN_DIR"

# Alte Flag-Dateien entfernen
rm -f "$MYSQL_DATA_DIR/debian-5.7.flag"

# Schritt 2: MySQL aus Ubuntu Repository installieren
log_info "Installiere MySQL Server aus Ubuntu Repositorys..."

# MySQL Benutzer und Gruppe sicherstellen
if ! id "mysql" &>/dev/null; then
    log_info "Erstelle mysql Benutzer..."
    groupadd -r mysql 2>/dev/null || true
    useradd -r -g mysql -s /bin/false -d /nonexistent mysql 2>/dev/null || true
fi

# ccc-data zur mysql Gruppe hinzufügen für Backup-Zugriff
if id "ccc-data" &>/dev/null; then
    usermod -a -G mysql ccc-data
    log_info "ccc-data zur mysql Gruppe hinzugefügt"
fi

# Non-interactive Installation
debconf-set-selections <<< "mysql-server mysql-server/root-pass password $DB_ROOT_PASS"
debconf-set-selections <<< "mysql-server mysql-server/re-root-pass password $DB_ROOT_PASS"

apt-get update -qq

# MySQL installieren
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    mysql-server-8.0 \
    mysql-client-8.0

if [ $? -ne 0 ]; then
    log_error "MySQL Installation fehlgeschlagen"
    exit 1
fi

# Schritt 3: MySQL stoppen und Datenverzeichnis vorbereiten
log_info "Stoppe MySQL für Konfiguration..."
systemctl stop mysql 2>/dev/null || true
sleep 3

# Prüfen ob Daten in /var/lib/mysql existieren und migrieren
if [ -d "/var/lib/mysql" ] && [ ! -L "/var/lib/mysql" ] && [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
    log_info "Migriere MySQL-Daten nach $MYSQL_DATA_DIR"
    
    # MySQL sicher stoppen
    systemctl stop mysql 2>/dev/null || true
    sleep 5
    
    # Daten migrieren mit korrekten Berechtigungen
    rsync -av /var/lib/mysql/ "$MYSQL_DATA_DIR/" || {
        log_error "Datenmigration fehlgeschlagen"
        exit 1
    }
    
    # Berechtigungen auf migrierte Daten setzen
    chown -R ccc-data:mysql "$MYSQL_DATA_DIR"
    chmod -R 770 "$MYSQL_DATA_DIR"
    
    # Original-Daten sichern
    mv /var/lib/mysql /var/lib/mysql.backup.$(date +%Y%m%d_%H%M%S)
fi

# Symlink erstellen
log_info "Erstelle Symlink-Struktur..."
rm -rf /var/lib/mysql  # Falls leeres Verzeichnis existiert
ln -sf "$MYSQL_DATA_DIR" /var/lib/mysql

# Schritt 4: Konfiguration anpassen
log_info "Konfiguriere MySQL..."

# Custom Konfiguration
mkdir -p /etc/mysql/conf.d
cat > /etc/mysql/conf.d/ccc-code.cnf << MYSQLCCC
[mysqld]
# CCC CODE Pattern: Daten in Storage Root
datadir = /var/lib/mysql
socket = /var/run/mysqld/mysqld.sock

# Performance Optimierungen
innodb_buffer_pool_size = 256M
innodb_log_file_size = 128M
max_connections = 100

# UTF-8 Settings
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# Security & Performance
skip-name-resolve
local-infile = 0

[client]
socket = /var/run/mysqld/mysqld.sock
default-character-set = utf8mb4
MYSQLCCC

# Schritt 5: AppArmor anpassen
log_info "Passe AppArmor an..."
if [ -d "/etc/apparmor.d" ] && [ -f "/etc/apparmor.d/usr.sbin.mysqld" ]; then
    # AppArmor-Profil für MySQL anpassen
    if ! grep -q "$MYSQL_DATA_DIR" /etc/apparmor.d/usr.sbin.mysqld; then
        sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $MYSQL_DATA_DIR/** rwk," /etc/apparmor.d/usr.sbin.mysqld
        sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $STORAGE_ROOT/mysql/** rwk," /etc/apparmor.d/usr.sbin.mysqld
    fi
    
    systemctl reload apparmor
    log_success "AppArmor angepasst"
fi

# Schritt 6: MySQL Service starten
log_info "Starte MySQL Service..."
systemctl daemon-reload
systemctl enable mysql

# MySQL initialisieren falls Data Directory leer ist
if [ -z "$(ls -A "$MYSQL_DATA_DIR")" ]; then
    log_info "Initialisiere MySQL Data Directory..."
    
    # MySQL sicher stoppen
    systemctl stop mysql 2>/dev/null || true
    sleep 3
    
    # TEMPORÄR: Berechtigungen für Initialisierung auf mysql:mysql setzen
    chown -R mysql:mysql "$MYSQL_DATA_DIR"
    chmod 750 "$MYSQL_DATA_DIR"
    
    # Data Directory initialisieren
    mysqld --initialize-insecure --user=mysql --datadir="$MYSQL_DATA_DIR"
    
    # NACH Initialisierung: Optimierte Berechtigungen setzen
    chown -R ccc-data:mysql "$MYSQL_DATA_DIR"
    chmod -R 770 "$MYSQL_DATA_DIR"
    
    log_success "MySQL Data Directory initialisiert mit optimierten Berechtigungen"
fi

# MySQL starten mit Retry
for attempt in {1..3}; do
    systemctl start mysql
    
    sleep 5
    if systemctl is-active --quiet mysql; then
        log_success "MySQL Service erfolgreich gestartet"
        break
    else
        log_warning "MySQL Start Versuch $attempt fehlgeschlagen"
        
        # Debug-Informationen
        log_info "Berechtigungen prüfen:"
        ls -la "$MYSQL_DATA_DIR" | head -5
        
        if [ $attempt -eq 3 ]; then
            log_error "MySQL konnte nicht gestartet werden"
            journalctl -u mysql --no-pager -n 20
            exit 1
        fi
        sleep 3
    fi
done

# Auf MySQL Verfügbarkeit warten
log_info "Warte auf MySQL Verfügbarkeit..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        log_success "MySQL ist bereit"
        break
    fi
    sleep 2
done

# Schritt 7: Root Passwort setzen (falls bei Initialisierung gesetzt)
if mysql -uroot -e "SELECT 1;" &>/dev/null 2>/dev/null; then
    log_info "Setze MySQL Root-Passwort..."
    mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;" 2>/dev/null || {
        log_warning "Konnte root Passwort nicht setzen - verwende vorhandenes"
    }
fi

# Schritt 8: Datenbanken und Benutzer einrichten
log_info "Richte Datenbanken und Benutzer ein..."

# MySQL Secure Installation
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL 2>/dev/null
    DELETE FROM mysql.user WHERE User='' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;
EOSQL

# Ghost Database erstellen
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES;
EOSQL

# Schritt 9: Finale Konfiguration
log_info "Finalisiere Installation..."

# Root Password in ccc.conf speichern
if ! grep -q "DB_ROOT_PASS" /etc/ccc.conf; then
    echo "DB_ROOT_PASS=$DB_ROOT_PASS" >> /etc/ccc.conf
fi

# Berechtigungen final prüfen und anpassen
log_info "Finalisiere Berechtigungen..."
find "$MYSQL_DATA_DIR" -type f -name "*.cnf" -exec chmod 660 {} \;
find "$MYSQL_DATA_DIR" -type f -name "*.pem" -exec chmod 600 {} \;

# Markiere Installation als abgeschlossen
touch "$MYSQL_DATA_DIR/mysql.installed"
chown ccc-data:mysql "$MYSQL_DATA_DIR/mysql.installed"
chmod 660 "$MYSQL_DATA_DIR/mysql.installed"

# Health Check
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    log_success "✅ MySQL 8 Installation erfolgreich abgeschlossen"
    log_info "📊 MySQL Data: $MYSQL_DATA_DIR"
    log_info "👤 Besitzer: ccc-data:mysql"
    log_info "🔒 Berechtigungen: 770"
    log_info "🔌 MySQL Socket: /var/run/mysqld/mysqld.sock"
    log_info "🐬 MySQL Version: $(mysql --version)"
    
    # Berechtigungs-Info
    echo -e "${GREEN}Berechtigungsstruktur:${NC}"
    ls -la "$MYSQL_DATA_DIR" | head -10
else
    log_error "❌ MySQL Health Check fehlgeschlagen"
    exit 1
fi
