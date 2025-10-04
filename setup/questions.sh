#!/bin/bash
##########################################################
# Interaktive Fragen - Erweitert für Developer Tools 
# setup/questions.sh - Mit whiptail Dialogen
##########################################################

source /root/ccc/setup/functions.sh

ask_primary_hostname() {
    if command -v whiptail &> /dev/null; then
        PRIMARY_HOSTNAME=$(whiptail \
            --title "CCC Commander - Hostname Konfiguration" \
            --inputbox "\nBitte geben Sie den primären Hostname für diese Installation ein:\n\nBeispiele:\n- mein-server.de\n- 192.168.1.100\n- localhost (nur für Tests)" \
            14 60 \
            "$(hostname -f 2>/dev/null || hostname 2>/dev/null || echo 'localhost')" \
            3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Installation abgebrochen vom Benutzer.${NC}"
            exit 1
        fi
    else
        # Fallback ohne whiptail
        echo ""
        echo -e "${YELLOW}Hostname Konfiguration:${NC}"
        echo "Bitte geben Sie den primären Hostname für diese Installation ein:"
        echo "(z.B. mein-server.de oder eine IP-Adresse)"
        read -r PRIMARY_HOSTNAME
    fi
    
    if [ -z "$PRIMARY_HOSTNAME" ]; then
        if command -v whiptail &> /dev/null; then
            whiptail --msgbox "Hostname ist erforderlich! Bitte versuchen Sie es erneut." 8 60
            ask_primary_hostname
        else
            log_error "Hostname ist erforderlich"
            exit 1
        fi
    fi
}

ask_installation_mode() {
    if command -v whiptail &> /dev/null; then
        MODE=$(whiptail \
            --title "Installationsmodus" \
            --menu "\nWelche Komponenten möchten Sie installieren?" \
            15 60 4 \
            "dev" "Developer-Workstation (TMUX, Aider, MCP, etc.)" \
            "web" "Web-Server (Ghost CMS, BookStack)" \
            "full" "Beides (Developer + Web Tools)" \
            "custom" "Benutzerdefinierte Auswahl" \
            3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Installation abgebrochen vom Benutzer.${NC}"
            exit 1
        fi
        
        INSTALL_MODE="$MODE"
    else
        # Fallback ohne whiptail
        echo ""
        echo -e "${YELLOW}Installationsmodus:${NC}"
        echo "Welche Komponenten möchten Sie installieren?"
        select mode in "Developer-Workstation" "Web-Server" "Beides" "Custom"; do
            case $mode in
                "Developer-Workstation" )
                    INSTALL_MODE="dev"
                    break
                    ;;
                "Web-Server" )
                    INSTALL_MODE="web"
                    break
                    ;;
                "Beides" )
                    INSTALL_MODE="full"
                    break
                    ;;
                "Custom" )
                    INSTALL_MODE="custom"
                    break
                    ;;
            esac
        done
    fi
    
    # Komponenten basierend auf Modus setzen
    case $INSTALL_MODE in
        "dev" )
            INSTALL_COMPONENTS="tmux,aider,mcp,fastmcp,langgraph,libtmux"
            ;;
        "web" )
            INSTALL_COMPONENTS="ghost,bookstack"
            ;;
        "full" )
            INSTALL_COMPONENTS="ghost,bookstack,tmux,aider,mcp,fastmcp,langgraph,libtmux"
            ;;
        "custom" )
            ask_custom_components
            ;;
    esac
}

ask_custom_components() {
    if command -v whiptail &> /dev/null; then
        COMPONENTS=$(whiptail \
            --title "Benutzerdefinierte Komponenten" \
            --checklist "\nWählen Sie die zu installierenden Komponenten:" \
            18 60 9 \
            "ghost" "Ghost CMS" OFF \
            "bookstack" "BookStack Wiki" OFF \
            "tmux" "TMUX Terminal Multiplexer" ON \
            "aider" "Aider AI Coding Assistant" ON \
            "mcp" "Model Context Protocol" ON \
            "fastmcp" "FastMCP Framework" ON \
            "langgraph" "LangGraph Agents" ON \
            "libtmux" "libtmux Python ORM" ON \
            3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Installation abgebrochen vom Benutzer.${NC}"
            exit 1
        fi
        
        # Whiptail gibt Komponenten in Quotes zurück - bereinigen
        INSTALL_COMPONENTS=$(echo "$COMPONENTS" | tr -d '"' | sed 's/ /,/g')
    else
        # Fallback ohne whiptail
        echo ""
        echo -e "${YELLOW}Benutzerdefinierte Komponenten:${NC}"
        echo "Verfügbare Komponenten: ghost, bookstack, tmux, aider, mcp, fastmcp, langgraph, libtmux"
        echo "Bitte Komponenten komma-separiert eingeben:"
        read -r INSTALL_COMPONENTS
    fi
}

ask_admin_email() {
    local DEFAULT_EMAIL="admin@${PRIMARY_HOSTNAME}"
    
    if command -v whiptail &> /dev/null; then
        ADMIN_EMAIL=$(whiptail \
            --title "Admin E-Mail Adresse" \
            --inputbox "\nBitte geben Sie die Admin E-Mail Adresse ein:\n\n(Wird für System-Benachrichtigungen verwendet)" \
            11 60 \
            "$DEFAULT_EMAIL" \
            3>&1 1>&2 2>&3)
        
        if [ $? -ne 0 ]; then
            echo -e "${YELLOW}Installation abgebrochen vom Benutzer.${NC}"
            exit 1
        fi
    else
        # Fallback ohne whiptail
        echo ""
        echo -e "${YELLOW}Admin E-Mail:${NC}"
        echo "Bitte geben Sie eine Admin E-Mail Adresse ein:"
        read -r ADMIN_EMAIL
        ADMIN_EMAIL=${ADMIN_EMAIL:-$DEFAULT_EMAIL}
    fi
    
    # Einfache E-Mail Validierung
    if ! echo "$ADMIN_EMAIL" | grep -q "@"; then
        if command -v whiptail &> /dev/null; then
            whiptail --msgbox "Ungültige E-Mail Adresse! Bitte versuchen Sie es erneut." 8 60
            ask_admin_email
        else
            echo -e "${RED}Ungültige E-Mail Adresse! Bitte versuchen Sie es erneut.${NC}"
            ask_admin_email
        fi
    fi
}

ask_openrouter_api_key() {
    if [[ "$INSTALL_COMPONENTS" == *"aider"* ]]; then
        if command -v whiptail &> /dev/null; then
            if whiptail --yesno "Möchten Sie einen OpenRouter API Key für Aider konfigurieren?" 10 60; then
                OPENROUTER_API_KEY=$(whiptail \
                    --title "OpenRouter API Key" \
                    --passwordbox "\nBitte geben Sie Ihren OpenRouter API Key ein:\n\n(Optional - kann später konfiguriert werden)" \
                    12 60 \
                    3>&1 1>&2 2>&3)
                
                if [ $? -eq 0 ] && [ -n "$OPENROUTER_API_KEY" ]; then
                    log_success "OpenRouter API Key wird konfiguriert"
                else
                    log_info "OpenRouter API Key wird übersprungen"
                    OPENROUTER_API_KEY=""
                fi
            else
                OPENROUTER_API_KEY=""
                log_info "OpenRouter API Key kann später konfiguriert werden"
            fi
        else
            # Fallback ohne whiptail
            echo ""
            echo -e "${YELLOW}OpenRouter AI Configuration:${NC}"
            echo "Möchten Sie einen OpenRouter API Key für Aider konfigurieren?"
            echo "(Optional - kann später in \$STORAGE_ROOT/config/aider/openrouter-api-key eingetragen werden)"
            select api_choice in "Jetzt" "Später"; do
                case $api_choice in
                    "Jetzt" )
                        echo -n "OpenRouter API Key: "
                        read -s OPENROUTER_API_KEY
                        echo ""
                        if [ -n "$OPENROUTER_API_KEY" ]; then
                            log_success "OpenRouter API Key wird konfiguriert"
                        fi
                        break
                        ;;
                    "Später" )
                        log_info "API Key kann später konfiguriert werden"
                        OPENROUTER_API_KEY=""
                        break
                        ;;
                esac
            done
        fi
    else
        OPENROUTER_API_KEY=""
    fi
}

show_installation_summary() {
    # IP Adressen ermitteln
    PUBLIC_IP=$(curl -s http://checkip.amazonaws.com || echo "127.0.0.1")
    PUBLIC_IPV6=$(curl -s http://checkipv6.amazonaws.com || echo "")
    
    # Database Konfiguration generieren
    DB_NAME="ccc_$(openssl rand -hex 3)"
    DB_USER="ccc_user_$(openssl rand -hex 3)"
    DB_PASS=$(openssl rand -base64 16)
    
    local SUMMARY="Installations-Zusammenfassung:

• Hostname: $PRIMARY_HOSTNAME
• Admin E-Mail: $ADMIN_EMAIL
• Installationsmodus: $INSTALL_MODE
• Komponenten: $INSTALL_COMPONENTS
• Datenbank: $DB_NAME
• Öffentliche IP: $PUBLIC_IP"

    if command -v whiptail &> /dev/null; then
        whiptail \
            --title "Installations-Zusammenfassung" \
            --msgbox "$SUMMARY\n\nDie Installation beginnt jetzt..." \
            18 60
    else
        echo ""
        echo -e "${GREEN}Installations-Zusammenfassung:${NC}"
        echo "• Hostname: $PRIMARY_HOSTNAME"
        echo "• Admin E-Mail: $ADMIN_EMAIL"
        echo "• Installationsmodus: $INSTALL_MODE"
        echo "• Komponenten: $INSTALL_COMPONENTS"
        echo "• Datenbank: $DB_NAME"
        echo "• Öffentliche IP: $PUBLIC_IP"
        echo ""
        read -p "Installation starten? [Enter]"
    fi
}

# Hauptfunktion um alle Fragen zu stellen
ask_questions() {
    echo -e "${GREEN}Starte interaktive Konfiguration...${NC}"
    
    ask_primary_hostname
    ask_installation_mode
    ask_admin_email
    ask_openrouter_api_key
    show_installation_summary
    
    # Umgebungsvariablen exportieren
    export INSTALL_DEV_TOOLS=1  # Immer aktiv für Developer Tools
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
}

# Hauptaufruf nur wenn Script direkt ausgeführt wird
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    ask_questions
fi
