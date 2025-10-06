#!/bin/bash
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

# Zeitzone
if [ -z "$TIMEZONE" ]; then
    dpkg-reconfigure -f noninteractive tzdata
else
    timedatectl set-timezone "$TIMEZONE"
fi

# Swap erstellen wenn wenig RAM (CCC CODE)
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

# System Update
apt-get update -qq
apt-get upgrade -y -qq

# Basis-Pakete
apt-get install -y -qq \
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

# Firewall Basis
ufw --force disable  # Erstmal aus für Installation
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp    # SSH
ufw allow 80/tcp    # HTTP
ufw allow 443/tcp   # HTTPS

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
