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

# Erweiterte Firewall-Konfiguration mit Systemhärtung
ufw --force disable  # Erstmal aus für Installation
ufw default deny incoming
ufw default allow outgoing

# SSH Härtung
ufw limit 22/tcp comment 'SSH with rate limiting'
sed -i 's/#PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
systemctl restart ssh

# Web-Dienste mit Rate-Limiting
ufw limit 80/tcp comment 'HTTP with rate limiting'
ufw limit 443/tcp comment 'HTTPS with rate limiting'

# Fail2ban erweiterte Integration
ufw allow from 127.0.0.1 comment 'Allow Fail2ban'

# Erweiterte Logging-Konfiguration
ufw logging on
sed -i 's/LOGLEVEL=low/LOGLEVEL=medium/' /etc/ufw/ufw.conf

# Zusätzliche Sicherheitsregeln
for port in 21 23 25 110 143 445 3306 3389 5432 6379 27017; do
    ufw deny $port/tcp comment "Block port $port"
done

# Fail2ban Konfiguration mit erweiterten Sicherheitsregeln
cat > /etc/fail2ban/jail.d/ccc.conf << 'F2B_EOF'
[DEFAULT]
bantime = 48h
findtime = 10m
maxretry = 3
banaction = ufw
banaction_allports = ufw

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 72h
findtime = 10m

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 48h
findtime = 10m

[nginx-limit-req]
enabled = true
filter = nginx-limit-req
port = http,https
logpath = /var/log/nginx/error.log
maxretry = 3
bantime = 48h
findtime = 10m

[nginx-botsearch]
enabled = true
filter = nginx-botsearch
port = http,https
logpath = /var/log/nginx/access.log
maxretry = 2
bantime = 72h
findtime = 5m
F2B_EOF

# Fail2ban Service neu starten
systemctl restart fail2ban

systemctl restart fail2ban

echo -e "${GREEN}[OK]${NC} System Basis konfiguriert"
