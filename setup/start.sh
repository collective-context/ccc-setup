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

# Funktionen laden
source functions.sh

# Willkommen-Nachricht mit whiptail falls verfügbar
if command -v whiptail &> /dev/null; then
    whiptail \
        --title "CCC Commander Installation" \
        --msgbox "\nWillkommen zur CCC Commander Installation!\n\nDiese Installation wird alle notwendigen Komponenten für Ihre Developer-Workstation einrichten." \
        12 60
fi

echo -e "${GREEN}"
echo "   ____      _ _           _   _              ____            _            _   "
echo "  / ___|___ | | | ___  ___| |_(_)_   _____   / ___|___  _ __ | |_ _____  _| |_ "
echo " | |   / _ \| | |/ _ \/ __| __| \ \ / / _ \ | |   / _ \| '_ \| __/ _ \ \/ / __|"
echo " | |__| (_) | | |  __/ (__| |_| |\ V /  __/ | |__| (_) | | | | ||  __/>  <| |_ "
echo "  \____\___/|_|_|\___|\___|\__|_| \_/ \___|  \____\___/|_| |_|\__\___/_/\_\\__|"
echo "                                                                                "
echo "                    Collective Context Commander - Installation"
echo "                         Version 2.0 - CCC Code"
echo -e "${NC}"

# Konfigurationsdatei checken (zweiter Durchlauf)
if [ -f /etc/ccc.conf ]; then
    echo -e "${BLUE}[INFO]${NC} Existierende Installation gefunden. Update-Modus..."
    # Vorherige Konfiguration laden
    cat /etc/ccc.conf | sed 's/^/DEFAULT_/' > /tmp/ccc.prev.conf
    source /tmp/ccc.prev.conf
    rm -f /tmp/ccc.prev.conf
    UPDATE_MODE=1
    
    if command -v whiptail &> /dev/null; then
        whiptail \
            --title "Update-Modus" \
            --msgbox "\nExistierende CCC Installation gefunden.\n\nUpdate-Modus wird gestartet..." \
            10 60
    fi
else
    echo -e "${BLUE}[INFO]${NC} Neue Installation..."
    FIRST_TIME_SETUP=1
fi

# Preflight Checks zuerst (für whiptail Installation)
source preflight.sh

# Interaktive Fragen (oder Umgebungsvariablen nutzen)
source questions.sh
ask_questions

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
    
    if command -v whiptail &> /dev/null; then
        whiptail \
            --title "CCC Storage erstellt" \
            --msgbox "\nCCC Storage Verzeichnis erstellt:\n\n$STORAGE_ROOT\n\nAlle Daten werden hier gespeichert für einfache Migration." \
            12 60
    fi
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
DOMAIN=$DOMAIN
DB_NAME=$DB_NAME
DB_USER=$DB_USER
DB_PASS=$DB_PASS
ADMIN_EMAIL=$ADMIN_EMAIL
INSTALL_COMPONENTS=$INSTALL_COMPONENTS
EOF

# Installationsfortschritt mit whiptail anzeigen
if command -v whiptail &> /dev/null; then
    {
        echo "10"
        echo -e "${GREEN}[INSTALL]${NC} Starte modulare Installation..."
        
        # System Basis
        source modules/system.sh
        echo "20"
        
        # ✅ CCC-CODE MODULE: Alles landet in $STORAGE_ROOT
        source modules/mysql8.sh          # → $STORAGE_ROOT/mysql
        echo "30"
        
        source modules/nodejs.sh          # Node.js für Ghost
        echo "40"
        
        source modules/nginx.sh           # → $STORAGE_ROOT/nginx
        echo "50"
        
        source modules/ssl.sh             # → $STORAGE_ROOT/ssl
        echo "60"
        
        # Developer Tools
        source modules/tmux.sh           # TMUX Terminal Multiplexer
        echo "65"
        
        source modules/aider.sh          # AI Coding Assistant
        echo "70"
        
        source modules/mcp.sh            # Model Context Protocol
        echo "75"
        
        source modules/fastmcp.sh        # FastMCP Framework
        echo "80"
        
        source modules/langgraph.sh      # LangGraph Agent Orchestration
        echo "85"
        
        source modules/libtmux.sh        # libtmux Python ORM
        echo "90"
        
        # Anwendungen
        if [[ "$INSTALL_COMPONENTS" == *"ghost"* ]]; then
            source modules/ghost.sh       # → $STORAGE_ROOT/www/ghost
        fi
        
        if [[ "$INSTALL_COMPONENTS" == *"bookstack"* ]]; then
            source modules/bookstack.sh   # → $STORAGE_ROOT/www/bookstack
        fi
        echo "95"
        
        # Finale Konfiguration
        source modules/finalize.sh
        echo "100"
        
    } | whiptail \
        --title "CCC Installation" \
        --gauge "Installiere CCC Komponenten..." \
        8 60 0
else
    # Fallback ohne whiptail Progress-Bar
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
fi

# ✅✅✅ CCC CODE BACKUP MAGIE: Backup-Script das NUR $STORAGE_ROOT sichert
create_backup_script

# Success Message mit whiptail
if command -v whiptail &> /dev/null; then
    whiptail \
        --title "CCC Installation Komplett!" \
        --msgbox "\n🎉 CCC Commander Installation erfolgreich abgeschlossen! 🎉\n\n• Alle Daten in: $STORAGE_ROOT\n• Dashboard: https://$PRIMARY_HOSTNAME/admin\n• Login: $ADMIN_EMAIL\n\nCCC CODE Migration:\n1. Backup: ccc-backup\n2. Neue Box: tar -xzf backup.tar.gz -C /\n3. Setup: curl -sL ... | bash\n4. Fertig! 🚀" \
        16 60
fi

# Success Message mit CCC CODE HINWEIS
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
