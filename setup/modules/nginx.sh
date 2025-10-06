#!/bin/bash
set -euo pipefail
##########################################################
# NGINX Installation - CCC CODE Pattern
# Basiert auf WordOps (https://wordops.net)
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} NGINX Installation (CCC CODE Style)..."

# NGINX Version und Build-Optionen (WordOps-Style)
NGINX_VERSION="1.28.0"

# WordOps Repository für NGINX hinzufügen
if [ ! -f /etc/apt/sources.list.d/wordops.list ]; then
    curl -sL https://mirrors.wordops.eu/pub.key | apt-key add -
    echo "deb https://mirrors.wordops.eu/debian $(lsb_release -sc) main" > /etc/apt/sources.list.d/wordops.list
fi

# NGINX aus WordOps Repository installieren
apt-get update
install_package nginx-custom nginx-extras

# NGINX Module und Konfigurationen von WordOps übernehmen
cp -r /usr/share/wordops/nginx/* /etc/nginx/

# NGINX Kompilierungsoptionen
CFLAGS="-g -O2 -fstack-protector-strong -Wformat -Werror=format-security -Wp,-D_FORTIFY_SOURCE=2 -fPIC"
LDFLAGS="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie"

# NGINX Verzeichnisstruktur (WordOps-inspiriert)
NGINX_CUSTOM="/etc/nginx/custom"
NGINX_SITES="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled" 
NGINX_CONF="/etc/nginx/conf.d"
NGINX_CACHE="/var/cache/nginx"
NGINX_SSL="/etc/nginx/ssl"
NGINX_SNIPPETS="/etc/nginx/snippets"

# Cache Verzeichnisse
NGINX_CACHE_FASTCGI="/var/cache/nginx/fastcgi"
NGINX_CACHE_PROXY="/var/cache/nginx/proxy"

# Verzeichnisse erstellen
mkdir -p $NGINX_CUSTOM $NGINX_SITES $NGINX_SITES_ENABLED $NGINX_CONF $NGINX_CACHE

# NGINX installieren mit idempotenter Funktion
install_package nginx

# NGINX Service sicherstellen
systemctl enable nginx
systemctl start nginx

# CCC Haupt-Konfiguration mit erweiterten Sicherheitseinstellungen
cat > /etc/nginx/sites-available/ccc << 'NGINXMAIN'
# CCC Commander Haupt-Konfiguration - CCC CODE Pattern mit Sicherheitsoptimierung
server {
    listen 80;
    listen [::]:80;
    
    # Strict Transport Security
    add_header Strict-Transport-Security "max-age=63072000" always;
    
    # Security Headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline';" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), midi=(), sync-xhr=(), microphone=(), camera=(), magnetometer=(), gyroscope=(), fullscreen=(self), payment=()" always;
    
    server_name _;
    root /var/www/html;
    
    # Buffer Size
    client_body_buffer_size 10K;
    client_header_buffer_size 1k;
    client_max_body_size 32m;
    large_client_header_buffers 2 1k;
    
    # Timeouts
    client_body_timeout 12;
    client_header_timeout 12;
    keepalive_timeout 15;
    send_timeout 10;
    
    # Gzip Kompression
    gzip on;
    gzip_vary on;
    gzip_min_length 10240;
    gzip_proxied expired no-cache no-store private auth;
    gzip_types text/plain text/css text/xml text/javascript application/x-javascript application/xml;
    gzip_disable "MSIE [1-6]\.";
    
    index index.html;
    
    # CCC CODE Magic: Include aller Konfigs aus Storage Root mit Sicherheitsprüfung
    include /home/user-data/nginx/conf.d/*.conf;
    
    # Default deny mit Logging
    location / {
        return 404;
        access_log /var/log/nginx/blocked.log combined;
    }
    
    # Verhindern des Zugriffs auf versteckte Dateien
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
    
    # PHP-FPM Konfiguration sichern
    location ~ \.php$ {
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
