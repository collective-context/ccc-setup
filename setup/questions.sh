#!/bin/bash
##########################################################
# Interaktive Fragen - Erweitert für Developer Tools
##########################################################

source /root/ccc/setup/functions.sh

# Hostname Abfrage
if [ -z "$PRIMARY_HOSTNAME" ]; then
    echo ""
    echo -e "${YELLOW}Hostname Konfiguration:${NC}"
    echo "Bitte geben Sie den primären Hostname für diese Installation ein:"
    echo "(z.B. mein-server.de oder eine IP-Adresse)"
    read -r PRIMARY_HOSTNAME
    
    if [ -z "$PRIMARY_HOSTNAME" ]; then
        log_error "Hostname ist erforderlich"
        exit 1
    fi
fi

# IP Adressen ermitteln
PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "127.0.0.1")
PUBLIC_IPV6=$(curl -s http://checkipv6.amazonaws.com || echo "")

# Installationsmodus
if [ -z "$INSTALL_MODE" ]; then
    echo ""
    echo -e "${YELLOW}Installationsmodus:${NC}"
    echo "Welche Komponenten möchten Sie installieren?"
    select mode in "Developer-Workstation" "Web-Server" "Beides" "Custom"; do
        case $mode in
            "Developer-Workstation" )
                INSTALL_MODE="dev"
                INSTALL_COMPONENTS="tmux,aider,mcp,fastmcp,langgraph,libtmux"
                break
                ;;
            "Web-Server" )
                INSTALL_MODE="web"
                INSTALL_COMPONENTS="ghost,bookstack"
                break
                ;;
            "Beides" )
                INSTALL_MODE="full"
                INSTALL_COMPONENTS="ghost,bookstack,tmux,aider,mcp,fastmcp,langgraph,libtmux"
                break
                ;;
            "Custom" )
                INSTALL_MODE="custom"
                echo "Verfügbare Komponenten: ghost, bookstack, tmux, aider, mcp, fastmcp, langgraph, libtmux"
                echo "Bitte Komponenten komma-separiert eingeben:"
                read -r INSTALL_COMPONENTS
                break
                ;;
        esac
    done
fi

# Database Konfiguration
if [ -z "$DB_NAME" ]; then
    DB_NAME="ccc_$(openssl rand -hex 3)"
    DB_USER="ccc_user_$(openssl rand -hex 3)"
    DB_PASS=$(openssl rand -base64 16)
fi

# Admin Email
if [ -z "$ADMIN_EMAIL" ]; then
    echo ""
    echo -e "${YELLOW}Admin E-Mail:${NC}"
    echo "Bitte geben Sie eine Admin E-Mail Adresse ein:"
    read -r ADMIN_EMAIL
    
    if [ -z "$ADMIN_EMAIL" ]; then
        ADMIN_EMAIL="admin@$PRIMARY_HOSTNAME"
    fi
fi

# Developer Tools Abfrage
if [ -z "$INSTALL_DEV_TOOLS" ]; then
    echo ""
    echo -e "${YELLOW}Developer Tools Installation:${NC}"
    echo "Möchten Sie Developer Tools (TMUX, Aider, MCP, LangGraph, etc.) installieren?"
    echo "Dies ist empfohlen für Entwicklung und System-Administration."
    select dev_choice in "Ja" "Nein"; do
        case $dev_choice in
            Ja )
                INSTALL_DEV_TOOLS=1
                break
                ;;
            Nein )
                INSTALL_DEV_TOOLS=0
                break
                ;;
        esac
    done
fi

# OpenRouter API Key Abfrage falls Aider installiert wird
if [[ "$INSTALL_COMPONENTS" == *"aider"* ]] && [ -z "$OPENROUTER_API_KEY" ]; then
    echo ""
    echo -e "${YELLOW}OpenRouter AI Configuration:${NC}"
    echo "Möchten Sie einen OpenRouter API Key für Aider konfigurieren?"
    echo "(Optional - kann später in $STORAGE_ROOT/config/aider/openrouter-api-key eingetragen werden)"
    select api_choice in "Jetzt" "Später"; do
        case $api_choice in
            Jetzt )
                echo -n "OpenRouter API Key: "
                read -s OPENROUTER_API_KEY
                echo ""
                if [ -n "$OPENROUTER_API_KEY" ]; then
                    log_success "OpenRouter API Key wird konfiguriert"
                fi
                break
                ;;
            Später )
                log_info "API Key kann später konfiguriert werden"
                break
                ;;
        esac
    done
fi

# Umgebungsvariablen exportieren
export INSTALL_DEV_TOOLS
export OPENROUTER_API_KEY
export PRIMARY_HOSTNAME
export PUBLIC_IP
export PUBLIC_IPV6
export INSTALL_MODE
export INSTALL_COMPONENTS
export DB_NAME
export DB_USER
export DB_PASS
export ADMIN_EMAIL
