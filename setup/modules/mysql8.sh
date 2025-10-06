#!/bin/bash
##########################################################
# MySQL 8 Installation - CCC CODE Pattern
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} MySQL 8 Installation (CCC CODE Style - Mit Passwort-Validation)..."

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
        chmod 660 "$STORAGE_ROOT/mysql/root-pass.txt"
        log_info "MySQL Root-Passwort generiert und gespeichert"
    fi
fi

# Schritt 0: PRÜFE OB PASSWORT BEREITS FUNKTIONIERT
log_info "Prüfe ob MySQL Root-Passwort bereits funktioniert..."
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" 2>/dev/null; then
    log_success "✅ MySQL Root-Passwort ist KORREKT - keine Änderungen nötig"
    
    # Nur Health Check durchführen
    if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" &>/dev/null; then
        log_success "✅ MySQL ist betriebsbereit"
        log_info "📊 MySQL Data: $MYSQL_DATA_DIR"
        log_info "🔌 MySQL Socket: /var/run/mysqld/mysqld.sock"
        log_info "🐬 MySQL Version: $(mysql --version)"
        exit 0
    else
        log_warning "⚠️  Passwort stimmt, aber Health Check fehlgeschlagen"
    fi
else
    log_warning "MySQL Root-Passwort funktioniert nicht - fahre fort mit Installation..."
fi

# Schritt 1: Verzeichnisstruktur mit optimierten Berechtigungen vorbereiten
log_info "Bereite Verzeichnisstruktur mit optimierten Berechtigungen vor..."
mkdir -p "$MYSQL_DATA_DIR"
mkdir -p "$MYSQL_RUN_DIR"

# ccc-data zur mysql Gruppe hinzufügen für Backup-Zugriff
if id "ccc-data" &>/dev/null; then
    usermod -a -G mysql ccc-data 2>/dev/null || true
    log_info "ccc-data zur mysql Gruppe hinzugefügt"
fi

# Schritt 2: MySQL aus Ubuntu Repository installieren
log_info "Installiere MySQL Server aus Ubuntu Repositorys..."

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

# Prüfen ob MySQL-Systemdatenbank existiert
MYSQL_INITIALIZED=false
if [ -d "$MYSQL_DATA_DIR/mysql" ] && [ -f "$MYSQL_DATA_DIR/ibdata1" ]; then
    log_info "MySQL-Systemdatenbank wurde bereits initialisiert"
    MYSQL_INITIALIZED=true
else
    log_info "MySQL-Systemdatenbank muss initialisiert werden"
fi

# Prüfen ob Daten in /var/lib/mysql existieren und migrieren
if [ -d "/var/lib/mysql" ] && [ ! -L "/var/lib/mysql" ] && [ -n "$(ls -A /var/lib/mysql 2>/dev/null)" ]; then
    log_info "Migriere MySQL-Daten nach $MYSQL_DATA_DIR"
    
    # MySQL sicher stoppen
    systemctl stop mysql 2>/dev/null || true
    sleep 5
    
    # Alte Daten entfernen falls vorhanden
    rm -rf "$MYSQL_DATA_DIR"/*
    
    # Daten migrieren
    rsync -av /var/lib/mysql/ "$MYSQL_DATA_DIR/" || {
        log_error "Datenmigration fehlgeschlagen"
        exit 1
    }
    
    MYSQL_INITIALIZED=true
    
    # Original-Daten sichern
    mv /var/lib/mysql /var/lib/mysql.backup.$(date +%Y%m%d_%H%M%S)
fi

# Symlink erstellen
log_info "Erstelle Symlink-Struktur..."
rm -rf /var/lib/mysql  # Falls leeres Verzeichnis existiert
ln -sf "$MYSQL_DATA_DIR" /var/lib/mysql

# Schritt 4: MySQL Initialisierung falls nötig
if [ "$MYSQL_INITIALIZED" = false ]; then
    log_info "Initialisiere MySQL Data Directory..."
    
    # TEMPORÄR: Berechtigungen für Initialisierung auf mysql:mysql setzen
    chown -R mysql:mysql "$MYSQL_DATA_DIR"
    chmod 750 "$MYSQL_DATA_DIR"
    
    # Run Directory Berechtigungen
    chown -R mysql:mysql "$MYSQL_RUN_DIR"
    chmod 755 "$MYSQL_RUN_DIR"
    
    # MySQL Data Directory initialisieren
    log_info "Führe mysqld --initialize aus..."
    mysqld --initialize-insecure --user=mysql --datadir="$MYSQL_DATA_DIR"
    
    if [ $? -eq 0 ]; then
        log_success "MySQL Initialisierung erfolgreich"
        MYSQL_INITIALIZED=true
    else
        log_error "MySQL Initialisierung fehlgeschlagen"
        # Versuche es mit secure initialization
        log_info "Versuche secure initialization..."
        mysqld --initialize --user=mysql --datadir="$MYSQL_DATA_DIR" 2>/tmp/mysql-init.log
        
        if [ $? -eq 0 ]; then
            log_success "MySQL Secure Initialisierung erfolgreich"
            MYSQL_INITIALIZED=true
            # Temporäres Root-Passwort aus Log extrahieren
            TEMP_ROOT_PASS=$(grep "A temporary password" /tmp/mysql-init.log | awk '{print $NF}')
            if [ -n "$TEMP_ROOT_PASS" ]; then
                log_info "Temporäres Root-Passwort: $TEMP_ROOT_PASS"
            fi
        else
            log_error "MySQL Initialisierung komplett fehlgeschlagen"
            cat /tmp/mysql-init.log
            exit 1
        fi
    fi
fi

# Schritt 5: Optimierte Berechtigungen setzen
log_info "Setze optimierte Berechtigungen (ccc-data:mysql)..."
chown -R ccc-data:mysql "$MYSQL_DATA_DIR"
chmod -R 770 "$MYSQL_DATA_DIR"

# Wichtige MySQL-Dateien mit speziellen Berechtigungen
find "$MYSQL_DATA_DIR" -name "*.pem" -exec chmod 600 {} \; 2>/dev/null || true
find "$MYSQL_DATA_DIR" -name "*.key" -exec chmod 600 {} \; 2>/dev/null || true

# Schritt 6: Konfiguration anpassen
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

# Schritt 7: AppArmor anpassen (nur wenn verfügbar und aktiv)
log_info "Prüfe AppArmor Verfügbarkeit..."

# Robuste Prüfung auf AppArmor Verfügbarkeit
APPARMOR_AVAILABLE=false
if [ -f "/etc/apparmor.d/usr.sbin.mysqld" ]; then
    # Verschiedene Methoden um AppArmor Verfügbarkeit zu prüfen
    if command -v apparmor_status >/dev/null 2>&1; then
        APPARMOR_AVAILABLE=true
    elif systemctl list-unit-files | grep -q apparmor.service; then
        APPARMOR_AVAILABLE=true
    elif [ -f "/sys/kernel/security/apparmor/profiles" ]; then
        APPARMOR_AVAILABLE=true
    fi
fi

if [ "$APPARMOR_AVAILABLE" = true ]; then
    log_info "AppArmor ist verfügbar - passe MySQL Profil an..."
    
    # Sicherstellen dass das Profil existiert
    if [ ! -f "/etc/apparmor.d/usr.sbin.mysqld" ]; then
        log_warning "AppArmor MySQL Profil nicht gefunden"
    else
        # AppArmor-Profil für MySQL anpassen
        if ! grep -q "$MYSQL_DATA_DIR" /etc/apparmor.d/usr.sbin.mysqld; then
            # Backup der originalen Config
            cp /etc/apparmor.d/usr.sbin.mysqld /etc/apparmor.d/usr.sbin.mysqld.backup
            
            # Unsere Pfade hinzufügen
            sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $MYSQL_DATA_DIR/** rwk," /etc/apparmor.d/usr.sbin.mysqld
            sed -i "/\/var\/lib\/mysql\/\*\* rwk,/a\  $STORAGE_ROOT/mysql/** rwk," /etc/apparmor.d/usr.sbin.mysqld
            
            log_success "AppArmor Profil angepasst"
        else
            log_info "AppArmor Profil wurde bereits angepasst"
        fi
        
        # AppArmor Dienst neu laden falls möglich
        if systemctl is-active apparmor --quiet 2>/dev/null; then
            systemctl reload apparmor
            log_success "AppArmor Dienst neu geladen"
        else
            log_info "AppArmor Dienst nicht aktiv - Profil wird bei nächster Aktivierung übernommen"
        fi
    fi
else
    log_info "AppArmor nicht verfügbar - überspringe Konfiguration (normal in LXC Containern)"
fi

# Schritt 8: MySQL Service starten
log_info "Starte MySQL Service..."
systemctl daemon-reload
systemctl enable mysql

# MySQL starten mit Retry
for attempt in {1..5}; do
    log_info "Startversuch $attempt von 5..."
    systemctl start mysql
    
    sleep 5
    if systemctl is-active --quiet mysql; then
        log_success "MySQL Service erfolgreich gestartet"
        break
    else
        log_warning "MySQL Start Versuch $attempt fehlgeschlagen"
        
        # Debug-Informationen
        log_info "Prüfe MySQL Logs:"
        journalctl -u mysql --no-pager -n 10
        
        if [ $attempt -eq 5 ]; then
            log_error "MySQL konnte nach 5 Versuchen nicht gestartet werden"
            log_info "Letzte Berechtigungen:"
            ls -la "$MYSQL_DATA_DIR" | head -10
            log_info "Prüfe ob MySQL-Datenbank existiert:"
            ls -la "$MYSQL_DATA_DIR/mysql" 2>/dev/null | head -5 || echo "MySQL-Datenbank nicht gefunden"
            exit 1
        fi
        
        # Vor nächstem Versuch stoppen
        systemctl stop mysql 2>/dev/null
        sleep 3
    fi
done

# Auf MySQL Verfügbarkeit warten
log_info "Warte auf MySQL Verfügbarkeit..."
for i in {1..30}; do
    if mysqladmin ping -h localhost --silent 2>/dev/null; then
        log_success "MySQL ist bereit und akzeptiert Verbindungen"
        break
    else
        if [ $i -eq 30 ]; then
            log_warning "MySQL antwortet nicht nach 60 Sekunden, aber fahre fort..."
            break
        fi
    fi
    sleep 2
done

# Schritt 9: Root Passwort NUR SETZEN WENN ES NOCH NICHT FUNKTIONIERT
log_info "Prüfe erneut ob MySQL Root-Passwort funktioniert..."
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" 2>/dev/null; then
    log_success "✅ MySQL Root-Passwort ist KORREKT - keine Änderungen nötig"
else
    log_warning "MySQL Root-Passwort funktioniert nicht - setze es jetzt..."
    
    # Prüfen ob wir ohne Passwort verbinden können
    if mysql -uroot -e "SELECT 1;" 2>/dev/null; then
        log_info "Setze Root-Passwort (ohne aktuelles Passwort)..."
        mysql -uroot -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;"
    elif [ -n "$TEMP_ROOT_PASS" ]; then
        log_info "Setze Root-Passwort (mit temporärem Passwort)..."
        mysql -uroot -p"$TEMP_ROOT_PASS" --connect-expired-password -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$DB_ROOT_PASS'; FLUSH PRIVILEGES;"
    else
        log_warning "Konnte Root-Passwort nicht setzen - manuelle Intervention nötig"
    fi
fi

# Schritt 10: Datenbanken und Benutzer NUR EINRICHTEN WENN NOCH NICHT VORHANDEN
log_info "Prüfe ob Datenbank-Initialisierung benötigt wird..."

if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" 2>/dev/null; then
    # Prüfe ob die Datenbank bereits existiert
    if mysql -uroot -p"$DB_ROOT_PASS" -e "USE $DB_NAME;" 2>/dev/null; then
        log_info "Datenbank $DB_NAME existiert bereits - überspringe Erstellung"
    else
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
    fi
else
    log_warning "Konnte keine Verbindung zu MySQL herstellen - überspringe Datenbank-Erstellung"
fi

# Schritt 11: Finale Konfiguration
log_info "Finalisiere Installation..."

# Root Password in ccc.conf speichern
if ! grep -q "DB_ROOT_PASS" /etc/ccc.conf; then
    echo "DB_ROOT_PASS=$DB_ROOT_PASS" >> /etc/ccc.conf
fi

# Markiere Installation als abgeschlossen
touch "$MYSQL_DATA_DIR/mysql.installed"
chown ccc-data:mysql "$MYSQL_DATA_DIR/mysql.installed"
chmod 660 "$MYSQL_DATA_DIR/mysql.installed"

# Health Check
if mysql -uroot -p"$DB_ROOT_PASS" -e "SELECT 1;" 2>/dev/null; then
    log_success "✅ MySQL 8 Installation erfolgreich abgeschlossen"
    log_info "📊 MySQL Data: $MYSQL_DATA_DIR"
    log_info "👤 Besitzer: ccc-data:mysql"
    log_info "🔒 Berechtigungen: 770"
    log_info "🔌 MySQL Socket: /var/run/mysqld/mysqld.sock"
    log_info "🐬 MySQL Version: $(mysql --version)"
else
    log_error "❌ MySQL Health Check fehlgeschlagen"
    log_info "⚠️  Bitte prüfen Sie:"
    log_info "   - MySQL Logs: journalctl -u mysql"
    log_info "   - Berechtigungen: ls -la $MYSQL_DATA_DIR"
    log_info "   - AppArmor Status: aa-status | grep mysql 2>/dev/null || echo 'AppArmor nicht verfügbar'"
    exit 1
fi
