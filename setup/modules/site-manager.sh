#!/bin/bash
# WordOps-inspiriertes Site Management
set -euo pipefail

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

# Site Management Konfiguration
SITES_AVAILABLE="/etc/nginx/sites-available"
SITES_ENABLED="/etc/nginx/sites-enabled"
NGINX_CUSTOM="/etc/nginx/custom"
PHP_VERSIONS=("7.4" "8.0" "8.1" "8.2" "8.3")

# Verzeichnisse erstellen
mkdir -p "$SITES_AVAILABLE" "$SITES_ENABLED" "$NGINX_CUSTOM"

# Site Management Funktionen (WordOps-Style)
site_create() {
    local domain=$1
    shift
    local php_version="8.3"
    local use_ssl=0
    local cache_type=""
    local site_type=""
    
    # Parameter validieren
    if [ "$#" -lt 1 ]; then
        log_error "Verwendung: ccc site create <domain> [--php <version>] [--ssl] [--wp|--html|--php]"
        return 1
    fi

    # Domain validieren
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        log_error "Ungültige Domain: $domain"
        return 1
    fi

    # Prüfen ob Domain bereits existiert
    if [ -f "$SITES_AVAILABLE/$domain" ]; then
        log_error "Site $domain existiert bereits"
        return 1
    fi
    
    # Parameter parsen (WordOps-Style)
    while [[ $# -gt 0 ]]; do
        case $1 in
            --php*)
                php_version="${1#--php}"
                shift
                ;;
            --ssl|--le)
                use_ssl=1
                shift
                ;;
            --wp)
                site_type="wordpress"
                shift
                ;;
            --wpsubdir)
                site_type="wordpress-subdir"
                shift
                ;;
            --wpsubdomain)
                site_type="wordpress-subdomain"
                shift
                ;;
            --wpfc)
                site_type="wordpress"
                cache_type="fastcgi"
                shift
                ;;
            --wpredis)
                site_type="wordpress"
                cache_type="redis"
                shift
                ;;
            --wpsc)
                site_type="wordpress"
                cache_type="supercache"
                shift
                ;;
            --html)
                site_type="html"
                shift
                ;;
            --php)
                site_type="php"
                shift
                ;;
            --mysql)
                site_type="mysql"
                shift
                ;;
            --proxy=*)
                site_type="proxy"
                proxy_url="${1#*=}"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done

    # Domain validieren
    if [[ ! "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        log_error "Ungültige Domain: $domain"
        return 1
    fi

    # Basis NGINX Konfiguration erstellen
    generate_nginx_config "$domain" "$php_version" "$cache_type"
    
    # SSL konfigurieren wenn gewünscht
    if [ "$use_ssl" = 1 ]; then
        configure_ssl "$domain"
    fi
    
    # Site aktivieren
    ln -sf "$SITES_AVAILABLE/$domain" "$SITES_ENABLED/$domain"
    
    # NGINX neu laden
    systemctl reload nginx
    
    log_success "Site $domain wurde erstellt"
}

site_update() {
    local domain=$1
    shift
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --php*)
                local new_version="${1#--php}"
                update_php_version "$domain" "$new_version"
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Hilfsfunktionen
generate_nginx_config() {
    local domain=$1
    local php_version=$2
    local cache_type=$3
    
    # Basis Konfiguration
    cat > "$SITES_AVAILABLE/$domain" << NGINX_CONF
server {
    listen 80;
    listen [::]:80;
    server_name $domain www.$domain;
    
    root /var/www/$domain;
    index index.php index.html;

    # Security Headers
    include /etc/nginx/custom/security-headers.conf;
    
    # PHP-FPM
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php$php_version-fpm.sock;
    }
NGINX_CONF

    # Cache Konfiguration hinzufügen
    if [ -n "$cache_type" ]; then
        case $cache_type in
            fastcgi)
                cat >> "$SITES_AVAILABLE/$domain" << 'FASTCGI_CACHE'
    # FastCGI Cache
    fastcgi_cache_path /var/cache/nginx/fastcgi levels=1:2 keys_zone=WORDPRESS:100m inactive=60m max_size=10g;
    fastcgi_cache_key "$scheme$request_method$host$request_uri";
    fastcgi_cache_use_stale error timeout http_500 http_503;
    fastcgi_cache_valid 200 60m;
FASTCGI_CACHE
                ;;
            redis)
                cat >> "$SITES_AVAILABLE/$domain" << 'REDIS_CACHE'
    # Redis Cache
    set $skip_cache 0;
    include /etc/nginx/custom/redis-cache.conf;
REDIS_CACHE
                ;;
        esac
    fi

    # Konfiguration abschließen
    cat >> "$SITES_AVAILABLE/$domain" << 'NGINX_END'
}
NGINX_END
}

update_php_version() {
    local domain=$1
    local new_version=$2
    
    # Prüfen ob PHP Version installiert ist
    if ! command -v php$new_version &> /dev/null; then
        install_php_version "$new_version"
    fi
    
    # NGINX Konfiguration anpassen
    sed -i "s/php[0-9]\.[0-9]-fpm.sock/php$new_version-fpm.sock/" "$SITES_AVAILABLE/$domain"
    
    systemctl reload nginx
    systemctl reload php$new_version-fpm
    
    log_success "PHP Version für $domain auf $new_version aktualisiert"
}

install_php_version() {
    local version=$1
    
    add-apt-repository -y ppa:ondrej/php
    install_package php$version-fpm php$version-common php$version-mysql \
        php$version-xml php$version-xmlrpc php$version-curl php$version-gd \
        php$version-imagick php$version-cli php$version-dev php$version-imap \
        php$version-mbstring php$version-opcache php$version-redis \
        php$version-soap php$version-zip
}

configure_ssl() {
    local domain=$1
    
    # Let's Encrypt Zertifikat erstellen
    certbot --nginx -d "$domain" -d "www.$domain" --non-interactive --agree-tos --email "$ADMIN_EMAIL"
}

# CLI Interface
case "${1:-}" in
    create)
        shift
        site_create "$@"
        ;;
    update)
        shift
        site_update "$@"
        ;;
    *)
        echo "Verwendung: $0 {create|update} domain [--php VERSION] [--ssl] [--wpfc|--wpredis]"
        exit 1
        ;;
esac
