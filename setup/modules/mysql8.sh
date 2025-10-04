#!/bin/bash
##########################################################
# MySQL 8 Installation - Strict CCC CODE Pattern
# OPTIMIERT für Ubuntu 24.04 - Fresh Installation
# setup/modules/mysql8.sh
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} MySQL 8 Installation (CCC CODE Style - Fresh System)..."

# MySQL Data Directory in Storage Root
MYSQL_DATA_DIR="$STORAGE_ROOT/mysql"
MYSQL_RUN_DIR="/var/run/mysqld"

# MySQL Root Password setzen
if [ -z "$DB_ROOT_PASS" ]; then
    DB_ROOT_PASS=$(openssl rand -base64 32)
    mkdir -p "$STORAGE_ROOT/mysql"
    echo "$DB_ROOT_PASS" > "$STORAGE_ROOT/mysql/root-pass.txt"
    chmod 600 "$STORAGE_ROOT/mysql/root-pass.txt"
    log_info "MySQL Root-Passwort generiert und gespeichert"
fi

# Schritt 1: Verzeichnisstruktur vorbereiten (BEVOR MySQL installiert wird)
log_info "Bereite Verzeichnisstruktur vor..."
mkdir -p "$MYSQL_DATA_DIR"
mkdir -p "$MYSQL_RUN_DIR"

# Berechtigungen setzen bevor MySQL installiert wird
chown -R mysql:mysql "$MYSQL_DATA_DIR"
chown -R mysql:mysql "$MYSQL_RUN_DIR"
chmod 750 "$MYSQL_DATA_DIR"
chmod 755 "$MYSQL_RUN_DIR"

# Symlink erstellen bevor Installation
log_info "Erstelle Symlink-Struktur..."
rm -rf /var/lib/mysql  # Falls existiert (sollte bei fresh system nicht)
ln -sf "$MYSQL_DATA_DIR" /var/lib/mysql
chown -R mysql:mysql /var/lib/mysql

# Schritt 2: MySQL aus Ubuntu Repository installieren
log_info "Installiere MySQL Server aus Ubuntu Repositorys..."

# Non-interactive Installation für Ubuntu 24.04
debconf-set-selections <<< "mysql-server mysql-server/root-pass password $DB_ROOT_PASS"
debconf-set-selections <<< "mysql-server mysql-server/re-root-pass password $DB_ROOT_PASS"

apt-get update -qq

DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    mysql-server-8.0 \
    mysql-client-8.0

if [ $? -ne 0 ]; then
    log_error "MySQL Installation fehlgeschlagen"
    exit 1
fi

# Schritt 3: Konfiguration anpassen
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

# Schritt 4: AppArmor anpassen
log_info "Passe AppArmor an..."
if [ -d "/etc/apparmor.d" ] && [ -f "/etc/apparmor.d/usr.sbin.mysqld" ]; then
    # Backup der originalen Config
    cp /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/usr.sbin.mysqld.backup
    
    # Unsere Pfade hinzufügen
    if ! grep -q "$MYSQL_DATA_DIR" /etc/apparmor.d/usr.sbin.mysqld; then
        sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $MYSQL_DATA_DIR/** rwk," /etc/apparmor.d/usr.sbin.mysqld
    fi
    
    systemctl reload apparmor
    log_success "AppArmor angepasst"
fi

# Schritt 5: MySQL Service starten
log_info "Starte MySQL Service..."
systemctl daemon-reload
systemctl enable mysql

# Berechtigungen final prüfen
chown -R mysql:mysql "$MYSQL_DATA_DIR"
chown -R mysql:mysql /var/lib/mysql

systemctl start mysql

# Auf MySQL Verfügbarkeit warten
log_info "Warte auf MySQL Verfügbarkeit..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        log_success "MySQL ist bereit"
        break
    fi
    sleep 2
done

# Schritt 6: Datenbanken und Benutzer einrichten
log_info "Richte Datenbanken und Benutzer ein..."

# MySQL Secure Installation
mysql -uroot -p"$DB_ROOT_PASS" <<-EOSQL
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

# Schritt 7: Finale Konfiguration
log_info "Finalisiere Installation..."

# Root Password in ccc.conf speichern
if ! grep -q "DB_ROOT_PASS" /etc/ccc.conf; then
    echo "DB_ROOT_PASS=$DB_ROOT_PASS" >> /etc/ccc.conf
fi

# Markiere Installation als abgeschlossen
touch "$MYSQL_DATA_DIR/mysql.installed"

# Health Check
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
    log_success "✅ MySQL 8 Installation erfolgreich abgeschlossen"
    log_info "📊 MySQL Data: $MYSQL_DATA_DIR"
    log_info "🔌 MySQL Socket: /var/run/mysqld/mysqld.sock"
    log_info "🐬 MySQL Version: $(mysql --version)"
else
    log_error "❌ MySQL Health Check fehlgeschlagen"
    exit 1
fi
