#!/bin/bash
set -euo pipefail
##########################################################
# Preflight Checks - Systemvoraussetzungen prüfen
# setup/preflight.sh
##########################################################

source /root/ccc/setup/functions.sh

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
