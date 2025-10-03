#!/bin/bash
##########################################################
# MySQL 8 Installation - Strict CCC CODE Pattern
# ALLE Daten in $STORAGE_ROOT/mysql
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
if [ ! -f /etc/apt/sources.list.d/mysql.list ]; then
    log_info "Füge MySQL Repository hinzu..."
    wget -O /tmp/mysql-apt-config.deb https://dev.mysql.com/get/mysql-apt-config_0.8.29-1_all.deb
    dpkg -i /tmp/mysql-apt-config.deb
    rm -f /tmp/mysql-apt-config.deb
    apt-get update -qq
fi

# MySQL Server installieren falls nicht vorhanden
if ! command -v mysql &> /dev/null; then
    log_info "Installiere MySQL Server..."
    
    # MySQL Data Directory vorbereiten
    mkdir -p "$MYSQL_DATA_DIR"
    chown mysql:mysql "$MYSQL_DATA_DIR"
    
    # MySQL Systemd Service anpassen für custom data directory
    mkdir -p /etc/systemd/system/mysql.service.d/
    cat > /etc/systemd/system/mysql.service.d/override.conf << 'MYSQLSERVICE'
[Service]
ExecStartPre=/bin/bash -c "[ -d /var/run/mysqld ] || mkdir -p /var/run/mysqld"
ExecStartPre=/bin/bash -c "[ -f /var/run/mysqld/mysqld.sock ] || touch /var/run/mysqld/mysqld.sock"
ExecStartPre=/bin/chown mysql:mysql /var/run/mysqld
ExecStartPre=/bin/chown mysql:mysql /var/run/mysqld/mysqld.sock
MYSQLSERVICE
    
    # Temporär my.cnf für Erstinstallation
    cat > /etc/mysql/conf.d/ccc-temp.cnf << MYSQLTEMP
[mysqld]
datadir=$MYSQL_DATA_DIR
socket=/var/run/mysqld/mysqld.sock
MYSQLTEMP
    
    # Non-interactive Installation
    debconf-set-selections <<< "mysql-community-server mysql-community-server/root-pass password $DB_ROOT_PASS"
    debconf-set-selections <<< "mysql-community-server mysql-community-server/re-root-pass password $DB_ROOT_PASS"
    
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        mysql-server \
        mysql-client
else
    log_info "MySQL ist bereits installiert"
fi

# MySQL Data Directory in unserer Storage Root sicherstellen
if [ ! -f "$MYSQL_DATA_DIR/mysql.installed" ]; then
    log_info "Konfiguriere MySQL Data Directory..."
    
    # MySQL stoppen
    systemctl stop mysql 2>/dev/null || true
    
    # Falls Daten in /var/lib/mysql existieren, migrieren wir sie
    if [ -d "/var/lib/mysql" ] && [ ! -L "/var/lib/mysql" ]; then
        if [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
            log_info "Migriere existierende MySQL-Daten nach $MYSQL_DATA_DIR"
            rsync -av /var/lib/mysql/ "$MYSQL_DATA_DIR/"
        fi
    fi
    
    # Haupt-my.cnf konfigurieren
    cat > /etc/mysql/conf.d/ccc-code.cnf << MYSQLCCC
[mysqld]
# CCC CODE Pattern: Alles in Storage Root
datadir = $MYSQL_DATA_DIR
socket = /var/run/mysqld/mysqld.sock
log-error = /var/log/mysql/error.log

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
MYSQLCCC
    
    # Data Directory Ownership
    chown -R mysql:mysql "$MYSQL_DATA_DIR"
    
    # Markiere als konfiguriert
    touch "$MYSQL_DATA_DIR/mysql.installed"
fi

# MySQL Service sicherstellen
systemctl daemon-reload
systemctl enable mysql
systemctl start mysql

# Warten bis MySQL ready ist
for i in {1..30}; do
    if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
        break
    fi
    sleep 1
done

# MySQL Secure Installation (idempotent)
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL 2>/dev/null
    DELETE FROM mysql.user WHERE User='';
    DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
    DROP DATABASE IF EXISTS test;
    DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
    FLUSH PRIVILEGES;
EOSQL

# Ghost Database erstellen (falls nicht existiert)
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL
    CREATE DATABASE IF NOT EXISTS $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
    CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
    GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
    FLUSH PRIVILEGES;
EOSQL

# Root Password in ccc.conf speichern
if ! grep -q "DB_ROOT_PASS" /etc/ccc.conf; then
    echo "DB_ROOT_PASS=$DB_ROOT_PASS" >> /etc/ccc.conf
fi

log_success "MySQL 8 installation abgeschlossen (MiaB Style)"
