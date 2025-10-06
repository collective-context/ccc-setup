#!/bin/bash
# NGINX Installationstest (erweitert für WordOps-Features)

# Relativer Pfad zur Projektwurzel
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Konfiguration laden
if [ -f "${PROJECT_ROOT}/config/ccc.conf" ]; then
    source "${PROJECT_ROOT}/config/ccc.conf"
else
    echo "Fehler: Konfigurationsdatei nicht gefunden"
    exit 1
fi

# Funktionen laden
if [ -f "${PROJECT_ROOT}/setup/functions.sh" ]; then
    source "${PROJECT_ROOT}/setup/functions.sh"
else
    echo "Fehler: Funktionsdatei nicht gefunden"
    exit 1
fi

# NGINX Modul laden
if [ -f "${PROJECT_ROOT}/setup/modules/nginx.sh" ]; then
    source "${PROJECT_ROOT}/setup/modules/nginx.sh"
else
    echo "Fehler: NGINX Modul nicht gefunden"
    exit 1
fi

test_nginx_installation() {
    log_info "Teste NGINX Installation..."
    
    # Prüfe NGINX Service
    if ! systemctl is-active --quiet nginx; then
        log_error "NGINX Service läuft nicht"
        return 1
    fi
    
    # Prüfe HTTP Response
    if ! curl -I http://localhost >/dev/null 2>&1; then
        log_error "NGINX antwortet nicht auf HTTP Anfragen"
        return 1
    fi
    
    # Prüfe WordOps-spezifische Verzeichnisse
    for dir in "$NGINX_SNIPPETS" "$NGINX_CACHE_FASTCGI" "$NGINX_CACHE_PROXY" "$STORAGE_ROOT/nginx/conf.d"; do
        if [ ! -d "$dir" ]; then
            log_error "Verzeichnis fehlt: $dir"
            return 1
        fi
    done
    
    # Prüfe Security Headers in Konfiguration
    if ! grep -q "X-Frame-Options" "$STORAGE_ROOT/nginx/conf.d/security-headers.conf"; then
        log_error "Security Headers fehlen in Konfiguration"
        return 1
    fi
    
    # Prüfe Brotli Modul (Beispiel: Überprüfung auf Existenz)
    if ! nginx -V 2>&1 | grep -q "ngx_brotli"; then
        log_warning "Brotli Modul nicht kompiliert"
    fi
    
    # Prüfe PageSpeed Modul
    if ! nginx -V 2>&1 | grep -q "ngx_pagespeed"; then
        log_warning "PageSpeed Modul nicht kompiliert"
    fi
    
    log_success "NGINX Tests erfolgreich"
    return 0
}

# Tests ausführen
test_nginx_installation
