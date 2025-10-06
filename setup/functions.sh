#!/bin/bash
set -euo pipefail
##########################################################
# CCC Commander Hilfsfunktionen | CCC CODE
# setup/functions.sh
##########################################################

# Farben
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Einheitliches Logging-Format
log() {
    local level=$1
    shift
    local color="$NC"
    case $level in
        INFO) color="$BLUE";;
        OK) color="$GREEN";;
        WARN) color="$YELLOW";;
        ERROR) color="$RED";;
    esac
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] ${color}[$level]${NC} $*" >&2
}

# Konsistente Wrapper für Logging
log_info() { log INFO "$*"; }
log_success() { log OK "$*"; }
log_error() { log ERROR "$*"; }
log_warning() { log WARN "$*"; }

# Idempotente Paketinstallation
install_package() {
    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            log_info "$pkg ist bereits installiert"
        else
            log_info "Installiere $pkg..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y \
                -qq -o Dpkg::Options::="--force-confold" \
                --no-install-recommends "$pkg"
        fi
    done
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Service Management
restart_service() {
    if systemctl is-active --quiet $1; then
        systemctl restart $1
    else
        systemctl start $1
    fi
    systemctl enable $1
}

# Backup-Script erstellen (CCC CODE PUR!)
create_backup_script() {
    cat > /usr/local/bin/ccc-backup << 'BACKUP_EOF'
#!/bin/bash
##########################################################
# CCC Commander Backup Script - CCC CODE STYLE
# Sichert NUR /home/user-data für einfache Migration
##########################################################

source /etc/ccc.conf

# Backup Directory IN Storage Root (CCC CODE)
BACKUP_DIR="$STORAGE_ROOT/backups"
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="$BACKUP_DIR/ccc-$DATE.tar.gz"

# Backup-Verzeichnis mit Storage User erstellen
mkdir -p $BACKUP_DIR
chown "$STORAGE_USER:$STORAGE_USER" "$BACKUP_DIR"

echo "🎯 CCC CODE STYLE BACKUP: Sichere $STORAGE_ROOT..."
echo "📍 Backup-Ziel: $BACKUP_FILE"

# Dienste stoppen für konsistentes Backup
systemctl stop nginx
systemctl stop mysql
systemctl stop ghost_* 2>/dev/null || true

# ✅✅✅ CCC CODE MAGIE: Nur Storage Root + Konfiguration
tar -czf $BACKUP_FILE \
    -C / \
    ${STORAGE_ROOT#/} \
    /etc/ccc.conf \
    /root/ccc/custom \
    /etc/nginx/sites-available/ccc \
    2>/dev/null || true

# Dienste wieder starten
systemctl start mysql
systemctl start nginx
systemctl start ghost_* 2>/dev/null || true

# Alte Backups löschen (behalte letzte 7)
ls -t $BACKUP_DIR/ccc-*.tar.gz 2>/dev/null | tail -n +8 | xargs -r rm

echo "✅ Backup komplett: $BACKUP_FILE"
echo "📦 Größe: $(du -h $BACKUP_FILE | cut -f1)"

# CCC CODE Migration Info
echo ""
echo "🚀 CCC CODE MIGRATION:"
echo "scp $BACKUP_FILE user@neue-box:/tmp/"
echo "Auf neuer Box:"
echo "  tar -xzf /tmp/ccc-*.tar.gz -C /"
echo "  curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | bash"
echo "  FERTIG! 🎉"
BACKUP_EOF
    chmod +x /usr/local/bin/ccc-backup
    
    # Cron-Job für tägliches Backup
    cat > /etc/cron.d/ccc-backup << 'CRON_EOF'
# CCC Commander Daily Backup - CCC CODE Style
0 3 * * * root /usr/local/bin/ccc-backup >> /var/log/ccc-backup.log 2>&1
CRON_EOF
}

# Restore-Script
create_restore_script() {
    cat > /usr/local/bin/ccc-restore << 'RESTORE_EOF'
#!/bin/bash
##########################################################
# CCC Commander Restore Script
# Stellt /home/user-data aus Backup wieder her
##########################################################

BACKUP_FILE=$1

if [ -z "$BACKUP_FILE" ]; then
    echo "Usage: ccc-restore <backup-file.tar.gz>"
    echo ""
    echo "Verfügbare Backups:"
    ls -lh /backup/ccc/user-data-*.tar.gz 2>/dev/null
    exit 1
fi

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Fehler: Backup-Datei nicht gefunden: $BACKUP_FILE"
    exit 1
fi

echo "WARNUNG: Dies überschreibt alle aktuellen Daten!"
read -p "Fortfahren? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Abgebrochen."
    exit 1
fi

echo "Stoppe Dienste..."
systemctl stop nginx mariadb

echo "Extrahiere Backup..."
tar -xzf $BACKUP_FILE -C /

echo "Starte Dienste..."
systemctl start mariadb nginx

echo "Restore abgeschlossen!"
echo "Bitte System neu starten: reboot"
RESTORE_EOF
    chmod +x /usr/local/bin/ccc-restore
}

# DNS Check
check_dns() {
    local hostname=$1
    local expected_ip=$2
    
    actual_ip=$(dig +short $hostname @8.8.8.8)
    if [ "$actual_ip" == "$expected_ip" ]; then
        return 0
    else
        return 1
    fi
}

# SSL Certificate Check
check_ssl_cert() {
    local domain=$1
    if [ -f "/etc/letsencrypt/live/$domain/fullchain.pem" ]; then
        # Check expiry
        expiry=$(openssl x509 -enddate -noout -in "/etc/letsencrypt/live/$domain/fullchain.pem" | cut -d= -f2)
        echo "SSL Cert gültig bis: $expiry"
        return 0
    else
        return 1
    fi
}
