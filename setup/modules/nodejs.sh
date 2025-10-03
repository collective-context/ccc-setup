#!/bin/bash
##########################################################
# Node.js Installation - Idempotent  
# Für Ghost CMS
##########################################################

source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} Node.js Installation..."

# Node.js Version checken
NODE_REQUIRED="18"
if command -v node &> /dev/null; then
    CURRENT_NODE=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$CURRENT_NODE" -ge "$NODE_REQUIRED" ]; then
        log_info "Node.js v$(node -v) ist bereits installiert"
        exit 0
    else
        log_warning "Node.js Version $CURRENT_NODE zu alt, aktualisiere auf v$NODE_REQUIRED+"
    fi
fi

# NodeSource Repository hinzufügen
if [ ! -f /etc/apt/sources.list.d/nodesource.list ]; then
    log_info "Füge NodeSource Repository hinzu..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
fi

# Node.js installieren
if ! command -v node &> /dev/null; then
    log_info "Installiere Node.js..."
    apt-get install -y -qq nodejs
else
    log_info "Node.js aktualisieren..."
    apt-get install -y -qq nodejs
fi

# PM2 für Process Management installieren
if ! command -v pm2 &> /dev/null; then
    log_info "Installiere PM2..."
    npm install -g pm2
    # PM2 Startup Script generieren
    pm2 startup 2>/dev/null || true
else
    log_info "PM2 ist bereits installiert"
fi

# NPM Cache bereinigen
npm cache clean --force

log_success "Node.js $(node -v) installation abgeschlossen"
