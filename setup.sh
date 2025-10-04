#!/bin/bash
##########################################################
# CCC Commander Bootstrap Script
# GitHub: https://github.com/collective-context/ccc-setup/
# 
# Installation:
#   curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | sudo -E bash
#
# Basiert auf Mail-in-a-Box Installation Pattern
##########################################################

set -e

# Farben für Output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# CCC Banner
echo -e "${GREEN}"
cat << "EOF"
   ____      _ _           _   _              ____            _            _   
  / ___|___ | | | ___  ___| |_(_)_   _____   / ___|___  _ __ | |_ _____  _| |_ 
 | |   / _ \| | |/ _ \/ __| __| \ \ / / _ \ | |   / _ \| '_ \| __/ _ \ \/ / __|
 | |__| (_) | | |  __/ (__| |_| |\ V /  __/ | |__| (_) | | | | ||  __/>  <| |_ 
  \____\___/|_|_|\___|\___|\__|_| \_/ \___|  \____\___/|_| |_|\__\___/_/\_\\__|
                                                                                
                    Collective Context Commander - Installation
                         Version 2.0 - CCC Code
EOF
echo -e "${NC}"

# Versions-Tags
if [ -z "$TAG" ]; then
    # Wenn keine Version angegeben, nimm die neueste
    TAG="main"
fi

# Betriebssystem Check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    
    if [[ ! "$OS" =~ ^(Debian|Ubuntu)$ ]]; then
        echo -e "${RED}[ERROR]${NC} Dieses System benötigt Debian 12 oder Ubuntu 22.04"
        exit 1
    fi
    
    if [[ "$OS" == "Debian" && "$VER" != "12" ]]; then
        echo -e "${RED}[ERROR]${NC} Debian 12 (bookworm) benötigt. Du hast: $VER"
        exit 1
    fi
    
    if [[ "$OS" == "Ubuntu" && ! "$VER" =~ ^(22.04|24.04)$ ]]; then
        echo -e "${RED}[ERROR]${NC} Ubuntu 22.04 oder 24.04 benötigt. Du hast: $VER"
        exit 1
    fi
else
    echo -e "${RED}[ERROR]${NC} Kann Betriebssystem nicht erkennen"
    exit 1
fi

# Root Check
if [[ $EUID -ne 0 ]]; then 
   echo -e "${RED}[ERROR]${NC} Dieses Script muss als root ausgeführt werden."
   echo "Hast du 'sudo' vergessen?"
   exit 1
fi

# GitHub Repository klonen wenn es noch nicht existiert
if [ ! -d "/root/ccc/" ]; then
    # Git installieren falls nötig
    if [ ! -f /usr/bin/git ]; then
        echo -e "${BLUE}[INFO]${NC} Installiere git..."
        apt-get -q -q update
        DEBIAN_FRONTEND=noninteractive apt-get -q -q install -y git < /dev/null
    fi
    
    # Repository klonen
    SOURCE=${CCC_REPO:-https://github.com/collective-context/ccc-setup}
    echo -e "${BLUE}[INFO]${NC} Lade CCC Commander $TAG herunter..."
    git clone \
        -b "$TAG" --depth 1 \
        "$SOURCE" \
        "/root/ccc" \
        < /dev/null 2> /dev/null || {
            echo -e "${RED}[ERROR]${NC} Git clone fehlgeschlagen"
            exit 1
        }
fi

# Ins Repository-Verzeichnis wechseln
cd /root/ccc || exit

# Repository updaten wenn es schon existiert
if [ "$TAG" != "$(git describe --tags 2>/dev/null || echo 'main')" ]; then
    echo -e "${BLUE}[INFO]${NC} Update CCC Commander auf $TAG..."
    git fetch --depth 1 --force --prune origin tag "$TAG"
    if ! git checkout -q "$TAG"; then
        echo -e "${RED}[ERROR]${NC} Update fehlgeschlagen. Hast du lokale Änderungen in /root/ccc?"
        exit 1
    fi
fi

# Globales Start-Script erstellen (CCC Code)
cat > /usr/local/bin/ccc << 'SCRIPT_EOF'
#!/bin/bash
cd /root/ccc
source setup/start.sh
SCRIPT_EOF
chmod +x /usr/local/bin/ccc

# Haupt-Setup starten
echo -e "${GREEN}[START]${NC} Starte CCC Commander Installation..."
exec setup/start.sh
