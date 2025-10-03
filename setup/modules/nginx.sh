#!/bin/bash
##########################################################
# NGINX Installation - Strict CCC CODE Pattern
# Konfigurationen aus $STORAGE_ROOT/nginx laden
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} NGINX Installation (CCC CODE Style)..."

# NGINX installieren falls nicht vorhanden
if ! command -v nginx &> /dev/null; then
    log_info "Installiere NGINX..."
    apt-get install -y -qq nginx
fi

# NGINX Service sicherstellen
systemctl enable nginx
systemctl start nginx

# CCC Haupt-Konfiguration erstellen die includes aus Storage Root lädt
cat > /etc/nginx/sites-available/ccc << 'NGINXMAIN'
# CCC Commander Haupt-Konfiguration - CCC CODE Pattern
server {
    listen 80;
    listen [::]:80;
    
    server_name _;
    root /var/www/html;
    
    index index.html;
    
    # CCC CODE Magic: Include aller Konfigs aus Storage Root
    include /home/user-data/nginx/conf.d/*.conf;
    
    # Default deny
    location / {
        return 404;
    }
}
NGINXMAIN

# CCC Site aktivieren
if [ ! -f /etc/nginx/sites-enabled/ccc ]; then
    ln -s /etc/nginx/sites-available/ccc /etc/nginx/sites-enabled/
fi

# Standard NGINX Site deaktivieren
if [ -f /etc/nginx/sites-enabled/default ]; then
    rm /etc/nginx/sites-enabled/default
fi

# Nginx Verzeichnis in Storage Root erstellen
mkdir -p "$STORAGE_ROOT/nginx/conf.d"
mkdir -p "$STORAGE_ROOT/nginx/ssl"

# Basis Nginx Konfigurationen in Storage Root
if [ ! -f "$STORAGE_ROOT/nginx/conf.d/basic.conf" ]; then
    cat > "$STORAGE_ROOT/nginx/conf.d/basic.conf" << 'NGINXBASIC'
# Basic Nginx Configuration
client_max_body_size 32M;
keepalive_timeout 300;

# Security headers
add_header X-Frame-Options "SAMEORIGIN" always;
add_header X-XSS-Protection "1; mode=block" always;
add_header X-Content-Type-Options "nosniff" always;
NGINXBASIC
fi

# NGINX Konfiguration testen
if nginx -t; then
    systemctl reload nginx
    log_success "NGINX Konfiguration erfolgreich"
else
    log_error "NGINX Konfigurationsfehler"
    exit 1
fi

log_success "NGINX installation abgeschlossen (CCC CODE Style)"
