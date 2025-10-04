#!/bin/bash
##########################################################
# Finale Konfiguration - CCC CODE Pattern
# Abschließende Setup-Schritte
# setup/modules/finalize.sh
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} Finale Konfiguration..."

# Firewall aktivieren (jetzt wo alles installiert ist)
log_info "Aktiviere Firewall..."
ufw --force enable

# CCC Management Scripts
log_info "Erstelle CCC Management Scripts..."

# Status Script
cat > /usr/local/bin/ccc-status << 'STATUS_EOF'
#!/bin/bash
##########################################################
# CCC Status Script
# Zeigt Status aller CCC Komponenten
##########################################################

source /etc/ccc.conf

echo "=== CCC Status ==="
echo "Storage Root: $STORAGE_ROOT"
echo "Hostname: $PRIMARY_HOSTNAME"
echo ""

# Services prüfen
echo "=== Services ==="
for service in nginx mysql php8.3-fpm; do
    if systemctl is-active --quiet $service; then
        echo "✅ $service: ACTIVE"
    else
        echo "❌ $service: INACTIVE"
    fi
done

# Ghost prüfen
if systemctl is-active --quiet ghost_*; then
    echo "✅ Ghost CMS: ACTIVE"
else
    echo "❌ Ghost CMS: INACTIVE"
fi

# Ports prüfen
echo ""
echo "=== Ports ==="
for port in 80 443 22; do
    if netstat -tuln | grep ":$port " &> /dev/null; then
        echo "✅ Port $port: LISTENING"
    else
        echo "❌ Port $port: CLOSED"
    fi
done

# Storage Usage
echo ""
echo "=== Storage ==="
df -h $STORAGE_ROOT

# Recent Logs
echo ""
echo "=== Recent Logs ==="
tail -5 /var/log/ccc-*.log 2>/dev/null || echo "No CCC logs found"
STATUS_EOF
chmod +x /usr/local/bin/ccc-status

# Update Script
cat > /usr/local/bin/ccc-update << 'UPDATE_EOF'
#!/bin/bash
##########################################################
# CCC Update Script
# Aktualisiert CCC und alle Komponenten
##########################################################

echo "🔄 CCC Update gestartet..."

# Backup erstellen
echo "📦 Erstelle Sicherungs-Backup..."
/usr/local/bin/ccc-backup

# Repository updaten
cd /root/ccc
echo "🔄 Aktualisiere CCC Repository..."
git pull

# Setup erneut ausführen
echo "🚀 Starte erneutes Setup..."
/root/ccc/setup/start.sh

echo "✅ CCC Update abgeschlossen!"
UPDATE_EOF
chmod +x /usr/local/bin/ccc-update

# Installation Info speichern
cat > $STORAGE_ROOT/install-info.txt << INFO
========================================
CC COMMANDER INSTALLATION
========================================
Version: $(git describe --tags 2>/dev/null || echo "main")
Datum: $(date)
Hostname: $PRIMARY_HOSTNAME
Storage: $STORAGE_ROOT
Mode: $INSTALL_MODE
Components: $INSTALL_COMPONENTS
========================================
INFO

# Finale Berechtigungen
log_info "Setze finale Berechtigungen..."
chown -R $STORAGE_USER:$STORAGE_USER $STORAGE_ROOT
find $STORAGE_ROOT -type d -exec chmod 750 {} \;
find $STORAGE_ROOT -type f -exec chmod 640 {} \;

# Cron Jobs für Wartung
log_info "Richte Wartungs-Cronjobs ein..."

# Tägliche Systemupdates
cat > /etc/cron.d/ccc-maintenance << 'CRON_EOF'
# CCC Maintenance Cronjobs
0 4 * * * root apt-get update && apt-get upgrade -y >> /var/log/ccc-update.log 2>&1
0 5 * * * root /usr/local/bin/ccc-backup >> /var/log/ccc-backup.log 2>&1
CRON_EOF

log_success "Finale Konfiguration abgeschlossen"
