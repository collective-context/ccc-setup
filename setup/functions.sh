#!/bin/bash
set -euo pipefail
##########################################################
# CCC Commander Hilfsfunktionen | CCC CODE
# setup/functions.sh
##########################################################

# Farben und Logging-Konfiguration
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Erweiterte Sicherheits-Konfiguration
readonly LOG_FILE="/var/log/ccc-setup.log"
readonly ERROR_LOG="/var/log/ccc-errors.log"
readonly AUDIT_LOG="/var/log/ccc-audit.log"
readonly SECURITY_LOG="/var/log/ccc-security.log"
readonly INCIDENT_LOG="/var/log/ccc-incident.log"
readonly MAX_RETRIES=3
readonly SECURE_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
readonly SECURE_UMASK=0027
readonly SECURE_FILE_MODE=0640
readonly SECURE_DIR_MODE=0750
readonly BACKUP_RETENTION=7
readonly CRITICAL_SERVICES="nginx mysql php-fpm"
readonly MONITORING_INTERVAL=300

# Sicherheits-Limits
readonly MAX_LOGIN_ATTEMPTS=5
readonly PASSWORD_MIN_LENGTH=12
readonly SESSION_TIMEOUT=3600
readonly ALLOWED_HOSTS="localhost,127.0.0.1"
readonly BLOCKED_IPS="/etc/ccc/blocked_ips.txt"

# Sicherheits-Checks
readonly MIN_PASSWORD_LENGTH=12
readonly REQUIRED_PACKAGES="ufw fail2ban apparmor"
readonly BLOCKED_PORTS="21,23,25,110,143"

# Sichere Umgebung erzwingen
umask $SECURE_UMASK
export PATH="$SECURE_PATH"

# Strict Mode für bessere Fehlerbehandlung
set -euo pipefail
IFS=$'\n\t'

# Trap für Fehlerbehandlung
trap 'error_handler $? $LINENO $BASH_LINENO "$BASH_COMMAND" $(printf "::%s" ${FUNCNAME[@]:-})' ERR

# Erweiterte Fehlerbehandlung mit Backup, Wiederherstellung, Sicherheitsprotokollierung, Incident Response und Audit
error_handler() {
    local exit_code=$1
    local line_no=$2
    local bash_lineno=$3
    local last_command=$4
    local func_trace=$5
    local script_name=$(basename "${BASH_SOURCE[1]}")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local incident_id=$(openssl rand -hex 8)
    local user_id=$(id -u)
    local user_name=$(id -un)
    local host_info=$(hostname -f)
    
    # Detaillierte Fehlerinformationen
    echo -e "${RED}[FATAL ERROR]${NC} in ${BASH_SOURCE[1]}:$line_no" >&2
    echo -e "${RED}Letzter Befehl:${NC} $last_command" >&2
    echo -e "${RED}Stacktrace:${NC} $func_trace" >&2
    echo -e "${RED}Exit Code:${NC} $exit_code" >&2
    
    # System Status sammeln
    local disk_space=$(df -h / | awk 'NR==2 {print $4}')
    local memory_free=$(free -h | awk '/^Mem:/ {print $4}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}')
    
    # Erweiterte Logging
    {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] Exit $exit_code in ${BASH_SOURCE[1]}:$line_no"
        echo "Command: $last_command"
        echo "Trace: $func_trace"
        echo "System Status:"
        echo "- Disk Space: $disk_space"
        echo "- Free Memory: $memory_free"
        echo "- Load Average: $load_avg"
        echo "Environment:"
        env | grep -E '^(PATH|STORAGE_ROOT|USER|PWD)='
    } >> "$ERROR_LOG"
    
    # Automatisches Backup und Wiederherstellung
    if [ -d "$STORAGE_ROOT" ]; then
        echo -e "${YELLOW}[WARN]${NC} Erstelle Notfall-Backup..." >&2
        
        # Backup mit Zeitstempel
        local backup_name="emergency_$(date +%Y%m%d_%H%M%S)"
        if /usr/local/bin/ccc-backup "$backup_name"; then
            echo -e "${GREEN}[OK]${NC} Backup erstellt: $backup_name" >&2
            
            # Wiederherstellungshinweise
            echo -e "${YELLOW}[INFO]${NC} Wiederherstellung mit:" >&2
            echo "ccc-restore $STORAGE_ROOT/backups/ccc-$backup_name.tar.gz" >&2
        else
            echo -e "${RED}[ERROR]${NC} Backup fehlgeschlagen!" >&2
        fi
    fi
    
    # Stack Trace in separate Datei
    echo "$func_trace" > "$ERROR_LOG.trace"
    
    exit $exit_code
}

# Erweitertes Logging-Format mit Trace-ID
log() {
    local level=$1
    shift
    local color="$NC"
    case $level in
        INFO) color="$BLUE";;
        OK) color="$GREEN";;
        WARN) color="$YELLOW";;
        ERROR) color="$RED";;
        FATAL) color="$RED";;
    esac
    
    # Trace-ID für bessere Nachverfolgbarkeit
    TRACE_ID=${TRACE_ID:-$(openssl rand -hex 8)}
    
    # Hostname und PID für bessere Diagnose
    local hostname=$(hostname -s)
    local pid=$$
    
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo -e "[${timestamp}] ${color}[$level]${NC} [$hostname:$pid] [$TRACE_ID] $*" >&2
    
    # Kritische Fehler in separate Datei loggen
    if [[ "$level" == "ERROR" || "$level" == "FATAL" ]]; then
        echo "[${timestamp}] [$level] [$hostname:$pid] [$TRACE_ID] $*" >> "/var/log/ccc-errors.log"
    fi
}

# Konsistente Wrapper für Logging
log_info() { log INFO "$*"; }
log_success() { log OK "$*"; }
log_error() { log ERROR "$*"; }
log_warning() { log WARN "$*"; }

# Erweiterte Paketinstallation mit Fehlerbehandlung und Retry
install_package() {
    local max_retries=3
    local exit_code=0
    
    for pkg in "$@"; do
        local retries=0
        while [ $retries -lt $max_retries ]; do
            if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                log_info "Installiere $pkg (Versuch $((retries+1))/$max_retries)..."
                
                # Apt-Cache aktualisieren bei Retry
                if [ $retries -gt 0 ]; then
                    apt-get update -qq
                fi
                
                if DEBIAN_FRONTEND=noninteractive apt-get install -y \
                    -qq -o Dpkg::Options::="--force-confold" \
                    --no-install-recommends "$pkg"; then
                    break
                else
                    retries=$((retries+1))
                    if [ $retries -eq $max_retries ]; then
                        log_error "Installation von $pkg fehlgeschlagen nach $max_retries Versuchen"
                        exit_code=1
                        break
                    fi
                    log_warning "Installation fehlgeschlagen, versuche erneut in 5 Sekunden..."
                    sleep 5
                fi
            else
                log_info "$pkg ist bereits installiert"
                # Erweiterte Paketvalidierung
                if ! dpkg -l "$pkg" | grep -q '^ii'; then
                    log_error "$pkg ist beschädigt oder nur teilweise installiert"
                    if ! apt-get install -y --fix-broken; then
                        log_error "Automatische Reparatur fehlgeschlagen"
                        exit_code=1
                    fi
                fi
                break
            fi
        done
    done
    return $exit_code
}

# Log-Verzeichnis erstellen
mkdir -p /var/log/ccc
chown root:adm /var/log/ccc
chmod 750 /var/log/ccc

# Logging Funktionen mit Test-Modus
log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST] $1" >> "$LOG_FILE"
}
log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-SUCCESS] $1" >> "$LOG_FILE"
}
log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-WARNING] $1" >> "$LOG_FILE"
}
log_error() { 
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-ERROR] $1" >> "$LOG_FILE"
}

# Log-Verzeichnis erstellen
mkdir -p /var/log/ccc
chown root:adm /var/log/ccc
chmod 750 /var/log/ccc

# Erweiterte Sicherheitsfunktionen mit umfassender Validierung
check_root() {
    # Prüfe effektive UID
    if [ "$(id -u)" != "0" ]; then
        log_error "Dieses Script muss als root ausgeführt werden"
        exit 1
    fi
    
    # Zusätzliche Sicherheitsprüfungen für sudo
    if [ -n "$SUDO_USER" ]; then
        log_warning "Script wurde mit sudo ausgeführt - führe erweiterte Prüfungen durch"
        
        # Prüfe sudo Gruppe
        if ! groups "$SUDO_USER" | grep -qw sudo; then
            log_error "Benutzer $SUDO_USER ist nicht in der sudo Gruppe"
            exit 1
        fi
        
        # Prüfe sudo Konfiguration
        if ! sudo -n true 2>/dev/null; then
            log_error "Sudo Konfiguration ist nicht korrekt"
            exit 1
        fi
    fi
    
    # Umfassende Verzeichnisprüfung
    for dir in /root /etc /var/log /usr/local/bin /var/lib; do
        if [ ! -d "$dir" ]; then
            log_error "Kritisches Verzeichnis fehlt: $dir"
            exit 1
        fi
        
        # Prüfe Berechtigungen
        perms=$(stat -c "%a" "$dir")
        owner=$(stat -c "%U" "$dir")
        group=$(stat -c "%G" "$dir")
        
        case "$dir" in
            /root)
                if [ "$perms" != "700" ] || [ "$owner" != "root" ]; then
                    log_error "Unsichere Root-Verzeichnis Berechtigungen: $dir ($perms)"
                    exit 1
                fi
                ;;
            /etc|/usr/local/bin)
                if [ "$perms" != "755" ] || [ "$owner" != "root" ]; then
                    log_warning "Ungewöhnliche Systemverzeichnis Berechtigungen: $dir ($perms)"
                fi
                ;;
            *)
                if [ "$perms" != "755" ] && [ "$perms" != "750" ]; then
                    log_warning "Potenziell unsichere Berechtigungen: $dir ($perms)"
                fi
                ;;
        esac
    done
    
    # SELinux/AppArmor Check
    if command -v getenforce >/dev/null 2>&1; then
        if [ "$(getenforce)" != "Enforcing" ]; then
            log_warning "SELinux ist nicht im Enforcing Modus"
        fi
    fi
    
    if command -v aa-status >/dev/null 2>&1; then
        if ! aa-status --enabled 2>/dev/null; then
            log_warning "AppArmor ist nicht aktiv"
        fi
    fi
    
    # Systemintegritätsprüfung
    if [ ! -f "/etc/shadow" ] || [ ! -f "/etc/passwd" ]; then
        log_error "Kritische Systemdateien fehlen"
        exit 1
    fi
    
    log_success "Sicherheitsprüfungen erfolgreich"
}

secure_directory() {
    local dir="$1"
    local owner="${2:-root}"
    local group="${3:-root}"
    local perms="${4:-750}"
    
    if [ ! -d "$dir" ]; then
        mkdir -p "$dir"
    fi
    
    chown "$owner:$group" "$dir"
    chmod "$perms" "$dir"
    
    # Setze sichere Verzeichnisattribute
    if command -v chattr >/dev/null 2>&1; then
        chattr +a "$dir" 2>/dev/null || true  # Nur anhängen erlauben
    fi
}

validate_input() {
    local input="$1"
    local pattern="$2"
    if [[ ! "$input" =~ $pattern ]]; then
        log_error "Ungültige Eingabe: $input"
        return 1
    fi
    return 0
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
