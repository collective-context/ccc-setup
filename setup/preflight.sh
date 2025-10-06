#!/bin/bash
set -euo pipefail
##########################################################
# Preflight Checks - Systemvoraussetzungen und Sicherheit prüfen
# setup/preflight.sh
##########################################################

source /root/ccc/setup/functions.sh

# Sicherheits-Checks aktivieren
set -euo pipefail
IFS=$'\n\t'

# Sicherheits-Audit durchführen
security_audit() {
    local issues=0
    
    # Root-Check
    if [ "$(id -u)" != "0" ]; then
        log_error "Script muss als root ausgeführt werden"
        exit 1
    fi
    
    # Systemintegrität prüfen
    for file in /etc/passwd /etc/shadow /etc/group; do
        if [ ! -f "$file" ] || [ ! -r "$file" ]; then
            log_error "Kritische Systemdatei nicht verfügbar: $file"
            ((issues++))
        fi
    done
    
    # Berechtigungen prüfen
    for dir in /etc /root /var/log; do
        perms=$(stat -c "%a" "$dir")
        if [ "$perms" != "755" ] && [ "$perms" != "750" ] && [ "$perms" != "700" ]; then
            log_warning "Unsichere Berechtigungen: $dir ($perms)"
            ((issues++))
        fi
    done
    
    # Offene Ports prüfen
    local open_ports=$(netstat -tuln | grep LISTEN | awk '{print $4}' | cut -d: -f2)
    for port in $open_ports; do
        if [[ ! "$port" =~ ^(22|80|443)$ ]]; then
            log_warning "Unerwarteter offener Port: $port"
            ((issues++))
        fi
    done
    
    # SELinux/AppArmor Status
    if command -v getenforce >/dev/null 2>&1; then
        if [ "$(getenforce)" != "Enforcing" ]; then
            log_warning "SELinux ist nicht im Enforcing Modus"
            ((issues++))
        fi
    elif command -v aa-status >/dev/null 2>&1; then
        if ! aa-status --enabled 2>/dev/null; then
            log_warning "AppArmor ist nicht aktiv"
            ((issues++))
        fi
    else
        log_warning "Kein MAC (SELinux/AppArmor) System gefunden"
        ((issues++))
    fi
    
    return $issues
}

echo -e "${BLUE}[PREFLIGHT]${NC} System-Checks..."

# RAM Check
TOTAL_MEMORY=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEMORY_GB=$((TOTAL_MEMORY / 1024 / 1024))

if [ $TOTAL_MEMORY_GB -lt 2 ]; then
    log_warning "Weniger als 2GB RAM - Performance könnte beeinträchtigt sein"
else
    log_success "RAM: ${TOTAL_MEMORY_GB}GB - OK"
fi

# Disk Space Check
DISK_SPACE=$(df / | awk 'NR==2 {print $4}')
DISK_SPACE_GB=$((DISK_SPACE / 1024 / 1024))

if [ $DISK_SPACE_GB -lt 10 ]; then
    log_error "Weniger als 10GB freier Speicherplatz - Installation nicht empfohlen"
    exit 1
else
    log_success "Disk Space: ${DISK_SPACE_GB}GB - OK"
fi

# Internet Connectivity
if ping -c 1 -W 3 8.8.8.8 &> /dev/null; then
    log_success "Internet Connectivity - OK"
else
    log_warning "Eingeschränkte Internet-Konnektivität"
fi

# Docker Check (warn if exists)
if command -v docker &> /dev/null; then
    log_warning "Docker ist installiert - könnte Konflikte verursachen"
fi

# Port Availability
for port in 80 443 22; do
    if netstat -tuln | grep ":$port " &> /dev/null; then
        log_warning "Port $port ist bereits belegt"
    fi
done

# Whiptail für Terminal-Dialoge installieren
echo -e "${GREEN}Installiere Terminal-Dialog-Tools...${NC}"
if ! command -v whiptail &> /dev/null; then
    apt-get update > /dev/null 2>&1
    apt-get install -y whiptail dialog > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_success "Whiptail installiert - OK"
    else
        log_warning "Whiptail konnte nicht installiert werden - verwende Text-Modus"
    fi
else
    log_success "Whiptail bereits installiert - OK"
fi

# Final Check ob whiptail verfügbar ist
if ! command -v whiptail &> /dev/null; then
    log_warning "Whiptail nicht verfügbar - Installation verwendet Text-Modus"
else
    log_success "Terminal-Dialoge verfügbar - OK"
fi

log_success "Preflight Checks abgeschlossen"
