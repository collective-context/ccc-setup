#!/bin/bash
set -euo pipefail
##########################################################
# System Basis Konfiguration - CCC CODE Pattern
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} System Konfiguration..."

# Hostname setzen
echo "$PRIMARY_HOSTNAME" > /etc/hostname
hostname "$PRIMARY_HOSTNAME"

# Hosts-Datei
echo "127.0.0.1 localhost" > /etc/hosts
echo "$PUBLIC_IP $PRIMARY_HOSTNAME" >> /etc/hosts

# Zeitzone konsistent setzen
if [ -n "$TIMEZONE" ]; then
    timedatectl set-timezone "$TIMEZONE"
elif command -v tzupdate >/dev/null; then
    log_warning "Automatische Zeitzonenkonfiguration mit tzupdate"
    tzupdate
else
    ln -fs /usr/share/zoneinfo/Europe/Berlin /etc/localtime
    dpkg-reconfigure -f noninteractive tzdata
fi

# Swap nur bei Bedarf erstellen (Idempotenter)
TOTAL_MEMORY=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEMORY_MB=$((TOTAL_MEMORY / 1024))

if [ $TOTAL_MEMORY_MB -lt 2000 ]; then
    if [ ! -f /swapfile ]; then
        echo -e "${BLUE}[INFO]${NC} Erstelle 2GB Swap..."
        fallocate -l 2G /swapfile
        chmod 600 /swapfile
        mkswap /swapfile
        swapon /swapfile
        echo "/swapfile none swap sw 0 0" >> /etc/fstab
    fi
fi

# Zentrale Paketinstallation (nur einmal update)
log_info "Systemaktualisierung durchführen..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# Basis-Pakete installieren mit idempotenter Funktion
source functions.sh
install_package \
    curl wget git unzip \
    software-properties-common \
    apt-transport-https \
    ca-certificates \
    lsb-release \
    gnupg2 \
    sudo \
    htop \
    net-tools \
    ufw \
    fail2ban \
    rsync \
    cron

# Erweiterte Firewall-Konfiguration
ufw --force disable  # Erstmal aus für Installation
ufw default deny incoming
ufw default allow outgoing

# SSH mit Rate-Limiting
ufw limit 22/tcp comment 'SSH with rate limiting'

# Web-Dienste
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'

# Fail2ban Integration
ufw allow from 127.0.0.1 comment 'Allow Fail2ban'

# Logging aktivieren
ufw logging on

# Zusätzliche Sicherheitsregeln
ufw deny 23/tcp comment 'Block Telnet'
ufw deny 3389/tcp comment 'Block RDP'

# Fail2ban Konfiguration (CCC CODE)
cat > /etc/fail2ban/jail.d/ccc.conf << 'F2B_EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true

[nginx-http-auth]
enabled = true
F2B_EOF

systemctl restart fail2ban

echo -e "${GREEN}[OK]${NC} System Basis konfiguriert"
