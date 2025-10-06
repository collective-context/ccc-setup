#!/bin/bash
# NGINX Installationstest

source /etc/ccc.conf
source /root/ccc/setup/functions.sh
source /root/ccc/setup/modules/nginx.sh

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
    
    # Prüfe Verzeichnisse
    for dir in "${NGINX_DIRS[@]}"; do
        if [ ! -d "$dir" ]; then
            log_error "Verzeichnis fehlt: $dir"
            return 1
        fi
    done
    
    log_success "NGINX Tests erfolgreich"
    return 0
}

# Tests ausführen
test_nginx_installation
