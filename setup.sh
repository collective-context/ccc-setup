#!/bin/bash
##########################################################
# CCC Commander Bootstrap Script
# Inspiriert von WordOps (https://wordops.net)
# 
# Installation:
#   curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | sudo -E bash
#
# Unterstützte Systeme:
#   - Ubuntu 22.04/24.04 LTS
#   - Debian 11/12/13
##########################################################

# Strict Mode
set -euo pipefail

# Standardwerte setzen
TEST_MODE=${TEST_MODE:-false}

# Prüfe Root-Rechte
if [ "$(id -u)" != "0" ]; then
    echo "Dieses Script muss als root ausgeführt werden!"
    exit 1
fi

# Git installieren falls nicht vorhanden
if ! command -v git >/dev/null 2>&1; then
    apt-get update
    apt-get install -y git
fi

# Farbdefinitionen
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Log-Verzeichnis erstellen
mkdir -p /var/log/ccc
chown root:adm /var/log/ccc
chmod 750 /var/log/ccc

# Logging Funktionen mit Test-Modus
log_info() { 
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $(date +%Y-%m-%d\ %H:%M:%S) $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST] $1" >> "$LOG_FILE"
}
log_success() { 
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $(date +%Y-%m-%d\ %H:%M:%S) $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-SUCCESS] $1" >> "$LOG_FILE"
}
log_warning() { 
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "[WARNING] $(date +%Y-%m-%d\ %H:%M:%S) $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-WARNING] $1" >> "$LOG_FILE"
}
log_error() { 
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date +%Y-%m-%d\ %H:%M:%S) $1" >> "/var/log/ccc/setup.log"
    [ "$TEST_MODE" = "true" ] && echo "[TEST-ERROR] $1" >> "$LOG_FILE"
}

# Banner anzeigen
echo -e "${GREEN}"
echo "   ____      _ _           _   _              ____            _            _   "
echo "  / ___|___ | | | ___  ___| |_(_)_   _____   / ___|___  _ __ | |_ _____  _| |_ "
echo " | |   / _ \| | |/ _ \/ __| __| \ \ / / _ \ | |   / _ \| '_ \| __/ _ \ \/ / __|"
echo " | |__| (_) | | |  __/ (__| |_| |\ V /  __/ | |__| (_) | | | | ||  __/>  <| |_ "
echo "  \____\___/|_|_|\___|\___|\__|_| \_/ \___|  \____\___/|_| |_|\__\___/_/\_\\__|"
echo "                                                                                "
echo "                    Collective Context Commander - Installation"
echo "                         Version 2.0 - CCC Code"
echo -e "${NC}"

# CCC Repository herunterladen oder aktualisieren
if [ ! -d "/root/ccc" ]; then
    log_info "Lade CCC Commander herunter..."
    # Verzeichnis erstellen falls es nicht existiert
    mkdir -p /root/ccc
    
    # Repository klonen
    if git clone https://github.com/collective-context/ccc-setup.git /root/ccc; then
        log_success "Download erfolgreich"
        # Ausführbare Rechte setzen
        chmod 700 /root/ccc/setup.sh
        chmod 700 /root/ccc/setup/*.sh
        chmod 700 /root/ccc/setup/modules/*.sh
    else
        log_error "Download fehlgeschlagen"
        exit 1
    fi
else
    log_info "CCC Repository existiert bereits - aktualisiere..."
    cd /root/ccc && git pull origin main
    # Ausführbare Rechte erneuern
    chmod 700 /root/ccc/setup.sh
    chmod 700 /root/ccc/setup/*.sh
    chmod 700 /root/ccc/setup/modules/*.sh
fi

# Berechtigungen für alle Skripte setzen
find /root/ccc -type f -name "*.sh" -exec chmod 700 {} \;

# Prüfe ob Setup-Verzeichnis existiert
if [ ! -d "/root/ccc/setup" ]; then
    log_error "Setup-Verzeichnis nicht gefunden"
    exit 1
fi

# Modus erkennen und start.sh entsprechend aufrufen
if [ -t 0 ]; then
    # Interaktiver Modus (Terminal vorhanden)
    log_info "Starte interaktive Installation..."
    cd /root/ccc/setup || exit 1
    log_info "In setup-Verzeichnis gewechselt"
    
    # Prüfe ob start.sh existiert und ausführbar ist
    if [ ! -f "./start.sh" ]; then
        log_error "start.sh nicht gefunden"
        exit 1
    fi
    log_info "start.sh gefunden"
    
    if [ ! -x "./start.sh" ]; then
        log_error "start.sh ist nicht ausführbar"
        chmod 700 ./start.sh
    fi
    log_info "start.sh ist ausführbar"
    
    # Führe start.sh direkt aus
    ./start.sh
else
    # Pipeline-Modus (curl | bash) - nicht-interaktiv mit Standardwerten
    log_info "Pipeline-Modus erkannt - verwende Standardkonfiguration..."
    
    # Standardwerte setzen
    export PRIMARY_HOSTNAME=$(hostname -f 2>/dev/null || hostname || echo "localhost")
    export ADMIN_EMAIL="admin@${PRIMARY_HOSTNAME}"
    export INSTALL_MODE="nginx"
    export INSTALL_COMPONENTS="nginx,ssl,site-manager"
    
    log_info "Verwende Standardwerte:"
    log_info "  Hostname: $PRIMARY_HOSTNAME"
    log_info "  Admin Email: $ADMIN_EMAIL"
    log_info "  Modus: $INSTALL_MODE"
    log_info "  Komponenten: $INSTALL_COMPONENTS"
    
    # Wechsle ins Setup-Verzeichnis
    cd /root/ccc/setup || exit 1
    log_info "In setup-Verzeichnis gewechselt"
    
    # Prüfe ob start.sh existiert und ausführbar ist
    if [ ! -f "./start.sh" ]; then
        log_error "start.sh nicht gefunden"
        exit 1
    fi
    log_info "start.sh gefunden"
    
    if [ ! -x "./start.sh" ]; then
        log_error "start.sh ist nicht ausführbar"
        chmod 700 ./start.sh
    fi
    log_info "start.sh ist ausführbar"
    
    # Führe start.sh im nicht-interaktiven Modus aus
    ./start.sh --non-interactive
fi
log_info "Setup abgeschlossen"
