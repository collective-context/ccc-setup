#!/bin/bash
##########################################################
# CCC Commander Main Setup Script - STRICT CCC CODE
# setup/start.sh
##########################################################

# Setup-Verzeichnis ist unser Arbeitsverzeichnis
cd /root/ccc/setup || exit

# Umgebungsvariablen setzen (CCC Code)
export LANGUAGE=de_DE.UTF-8
export LC_ALL=de_DE.UTF-8
export LANG=de_DE.UTF-8
export LC_TYPE=de_DE.UTF-8
export NCURSES_NO_UTF8_ACS=1

# Parameter verarbeiten
NON_INTERACTIVE=0
if [ "$1" = "--non-interactive" ]; then
    NON_INTERACTIVE=1
    echo -e "${BLUE}[INFO]${NC} Nicht-interaktiver Modus..."
fi

# Funktionen laden
source functions.sh

# Preflight Checks zuerst
source preflight.sh

# Konfigurationsdatei checken (zweiter Durchlauf)
if [ -f /etc/ccc.conf ]; then
    echo -e "${BLUE}[INFO]${NC} Existierende Installation gefunden. Update-Modus..."
    
    # Vorherige Konfiguration sicher laden (nur Variablen, keine Kommentare)
    if grep -E '^[A-Za-z_][A-Za-z0-9_]*=' /etc/ccc.conf > /tmp/ccc.prev.conf 2>/dev/null; then
        while IFS='=' read -r key value; do
            # Sicherstellen dass es eine gültige Variable ist
            if [[ $key =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
                eval "DEFAULT_$key=\"$value\""
                export "DEFAULT_$key"
            fi
        done < /tmp/ccc.prev.conf
        rm -f /tmp/ccc.prev.conf
    else
        echo -e "${YELLOW}[WARN]${NC} Konfigurationsdatei konnte nicht geladen werden"
    fi
    
    UPDATE_MODE=1
else
    echo -e "${BLUE}[INFO]${NC} Neue Installation..."
    FIRST_TIME_SETUP=1
fi

# Fragen nur im interaktiven Modus
if [ $NON_INTERACTIVE -eq 0 ]; then
    source questions.sh
    ask_questions
else
    # Im nicht-interaktiven Modus: Logging der verwendeten Werte
    echo -e "${GREEN}[INFO]${NC} Verwende Standard-Konfiguration:"
    echo "  Hostname: $PRIMARY_HOSTNAME"
    echo "  Admin Email: $ADMIN_EMAIL" 
    echo "  Modus: $INSTALL_MODE"
    echo "  Komponenten: $INSTALL_COMPONENTS"
    
    # Zusätzliche Variablen setzen die in questions.sh gesetzt werden
    PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "127.0.0.1")
    PUBLIC_IPV6=$(curl -s http://checkipv6.amazonaws.com || echo "")
    DB_NAME="ccc_$(openssl rand -hex 3)"
    DB_USER="ccc_user_$(openssl rand -hex 3)"
    DB_PASS=$(openssl rand -base64 16)
fi

# ✅✅✅ CCC CODE MAGIE: User-Data Verzeichnis erstellen ✅✅✅
STORAGE_USER=${STORAGE_USER:-ccc-data}
STORAGE_ROOT=${STORAGE_ROOT:-/home/user-data}

# Storage User erstellen wenn nötig
if ! id -u $STORAGE_USER > /dev/null 2>&1; then
    echo -e "${BLUE}[INFO]${NC} Erstelle Storage User: $STORAGE_USER"
    useradd -m -s /bin/bash -d /home/$STORAGE_USER $STORAGE_USER
fi

# Storage Root erstellen - DAS HERZSTÜCK VON CCC CODE!
if [ ! -d "$STORAGE_ROOT" ]; then
    echo -e "${BLUE}[INFO]${NC} Erstelle Storage Root: $STORAGE_ROOT"
    mkdir -p $STORAGE_ROOT
    chown $STORAGE_USER:$STORAGE_USER $STORAGE_ROOT
    chmod 750 $STORAGE_ROOT
    
    # CCC CODE Subdirectory Struktur
    mkdir -p $STORAGE_ROOT/{mysql,www,nginx,ssl,backups,config,logs,tools}
    chown -R $STORAGE_USER:$STORAGE_USER $STORAGE_ROOT
fi

# Konfiguration speichern (CCC CODE's /etc/ccc.conf)
cat > /etc/ccc.conf << EOF
# CCC Commander Konfiguration - CCC CODE
# Generiert: $(date)
STORAGE_USER=$STORAGE_USER
STORAGE_ROOT=$STORAGE_ROOT
PRIMARY_HOSTNAME=$PRIMARY_HOSTNAME
PUBLIC_IP=$PUBLIC_IP
PUBLIC_IPV6=$PUBLIC_IPV6
INSTALL_MODE=$INSTALL_MODE
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
INSTALL_COMPONENTS=$INSTALL_COMPONENTS
EOF

# Installationsfortschritt
echo -e "${GREEN}[INSTALL]${NC} Starte modulare Installation..."

# System Basis
source modules/system.sh

# ✅ CCC-CODE MODULE: Alles landet in $STORAGE_ROOT
source modules/mysql8.sh          # → $STORAGE_ROOT/mysql
source modules/nodejs.sh          # Node.js für Ghost
source modules/nginx.sh           # → $STORAGE_ROOT/nginx
source modules/ssl.sh             # → $STORAGE_ROOT/ssl

# Developer Tools
source modules/tmux.sh           # TMUX Terminal Multiplexer
source modules/aider.sh          # AI Coding Assistant
source modules/mcp.sh            # Model Context Protocol
source modules/fastmcp.sh        # FastMCP Framework
source modules/langgraph.sh      # LangGraph Agent Orchestration
source modules/libtmux.sh        # libtmux Python ORM

# Anwendungen
if [[ "$INSTALL_COMPONENTS" == *"ghost"* ]]; then
    source modules/ghost.sh       # → $STORAGE_ROOT/www/ghost
fi

if [[ "$INSTALL_COMPONENTS" == *"bookstack"* ]]; then
    source modules/bookstack.sh   # → $STORAGE_ROOT/www/bookstack
fi

# Finale Konfiguration
source modules/finalize.sh

# ✅✅✅ CCC CODE BACKUP MAGIE: Backup-Script das NUR $STORAGE_ROOT sichert
create_backup_script

# Success Message
echo -e "${GREEN}"
echo "========================================="
echo "   CCC Commander Installation Komplett!"
echo "========================================="
echo -e "${NC}"
echo ""
echo -e "${YELLOW}🎉 CCC CODE MAGIE AKTIVIERT: 🎉${NC}"
echo "✅ Alle Daten in: $STORAGE_ROOT"
echo "✅ Einfache Migration: Backup → Neue Box → Restore → Fertig!"
echo ""
echo "Dashboard: https://$PRIMARY_HOSTNAME/admin"
echo "Login: $ADMIN_EMAIL"
echo ""
echo -e "${YELLOW}CCC CODE Migration:${NC}"
echo "1. Backup: ccc-backup"
echo "2. Auf neuer Box: tar -xzf backup.tar.gz -C /"
echo "3. Setup: curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | bash"
echo "4. Fertig! 🚀"
echo ""
echo -e "${BLUE}User-Daten Verzeichnis:${NC} $STORAGE_ROOT"
echo -e "${BLUE}Konfiguration:${NC} /etc/ccc.conf"
echo ""
