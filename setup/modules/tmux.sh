#!/bin/bash
set -euo pipefail
##########################################################
# TMUX Installation - CCC CODE Pattern
##########################################################

source /etc/ccc.conf
source /root/ccc/setup/functions.sh

echo -e "${BLUE}[MODULE]${NC} TMUX Installation (CCC CODE Style)..."

# TMUX Configuration in Storage Root
TMUX_CONFIG_DIR="$STORAGE_ROOT/config/tmux"
TMUX_PLUGINS_DIR="$STORAGE_ROOT/tools/tmux/plugins"

# Verzeichnisse erstellen
mkdir -p "$TMUX_CONFIG_DIR"
mkdir -p "$TMUX_PLUGINS_DIR"
chown -R "$STORAGE_USER:$STORAGE_USER" "$TMUX_CONFIG_DIR" "$TMUX_PLUGINS_DIR"

# TMUX installieren mit idempotenter Funktion
install_package tmux git curl wget

# TMUX Konfiguration erstellen
cat > "$TMUX_CONFIG_DIR/tmux.conf" << TMUXCONF
# CCC TMUX Configuration - CCC CODE Style
# Generated: $(date)

# Basic Settings
set -g default-terminal "screen-256color"
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g history-limit 10000

# Mouse Support
set -g mouse on

# Key Bindings
unbind C-b
set -g prefix C-a
bind C-a send-prefix

# Split Windows
bind | split-window -h
bind - split-window -v
unbind '"'
unbind %

# Vim-like pane navigation
bind -r h select-pane -L
bind -r j select-pane -D
bind -r k select-pane -U
bind -r l select-pane -R

# Resize panes with Vim keys
bind -r H resize-pane -L 5
bind -r J resize-pane -D 5
bind -r K resize-pane -U 5
bind -r L resize-pane -R 5

# Window Navigation
bind -r C-h select-window -t :-
bind -r C-l select-window -t :+

# Status Bar
set -g status-style bg=black,fg=white
set -g status-left-length 100
set -g status-right-length 100
set -g status-left "#[fg=green]#H #[fg=white]| #S "
set -g status-right "#[fg=white]%Y-%m-%d %H:%M"

# Window Status
setw -g window-status-format "#I:#W#F"
setw -g window-status-current-format "#[fg=cyan]#I:#W#F"

# CCC Specific - Storage Root Info
set -g status-left-length 150
set -g status-left "#[fg=green]CCC#[fg=white] | #S | SR: #[fg=yellow]${STORAGE_ROOT}#[fg=white] | "
TMUXCONF

# TPM (Tmux Plugin Manager) installieren
if [ ! -d "$TMUX_PLUGINS_DIR/tpm" ]; then
    log_info "Installiere TMUX Plugin Manager..."
    sudo -u "$STORAGE_USER" git clone https://github.com/tmux-plugins/tpm "$TMUX_PLUGINS_DIR/tpm"
else
    log_info "TMUX Plugin Manager existiert bereits - Update..."
    sudo -u "$STORAGE_USER" git -C "$TMUX_PLUGINS_DIR/tpm" pull
fi

# Plugin Konfiguration zu tmux.conf hinzufügen
cat >> "$TMUX_CONFIG_DIR/tmux.conf" << 'TMUXPLUGINS'

# TPM Plugins
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Tmux Resurrect Configuration
set -g @resurrect-dir '$STORAGE_ROOT/tools/tmux/resurrect'
set -g @resurrect-capture-pane-contents 'on'

# Tmux Continuum Configuration
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'

# Initialize TPM (keep this line at the very bottom of tmux.conf)
run '$TMUX_PLUGINS_DIR/tpm/tpm'
TMUXPLUGINS

# Globales TMUX Wrapper Script erstellen
cat > /usr/local/bin/ccc-tmux << 'TMUXSCRIPT'
#!/bin/bash
##########################################################
# CCC TMUX Wrapper - CCC CODE Style
# Lädt Konfiguration aus Storage Root
##########################################################

source /etc/ccc.conf
TMUX_CONFIG="$STORAGE_ROOT/config/tmux/tmux.conf"

# TMUX mit custom config starten
exec tmux -f "$TMUX_CONFIG" "$@"
TMUXSCRIPT
chmod +x /usr/local/bin/ccc-tmux

# User-friendly Symlinks
ln -sf /usr/local/bin/ccc-tmux /usr/local/bin/ctmux

# Bash Completion für Storage User
if [ -f /home/$STORAGE_USER/.bashrc ] && ! grep -q "ccc-tmux" /home/$STORAGE_USER/.bashrc; then
    cat >> /home/$STORAGE_USER/.bashrc << BASHRC

# CCC TMUX Integration
alias tmux='ccc-tmux'
alias ctmux='ccc-tmux'
export TMUX_CONFIG="$STORAGE_ROOT/config/tmux/tmux.conf"

# TMUX Plugin Manager
export TMUX_PLUGIN_MANAGER_PATH="$STORAGE_ROOT/tools/tmux/plugins"
BASHRC
fi

# TMUX Session für CCC Management erstellen
if ! sudo -u "$STORAGE_USER" tmux has-session -t ccc 2>/dev/null; then
    log_info "Erstelle CCC Management TMUX Session..."
    sudo -u "$STORAGE_USER" ccc-tmux new-session -d -s ccc -c "$STORAGE_ROOT"
    sudo -u "$STORAGE_USER" ccc-tmux rename-window -t ccc:1 'main'
    sudo -u "$STORAGE_USER" ccc-tmux send-keys -t ccc:1 'cd $STORAGE_ROOT && ls -la' C-m
fi

# TMUX Plugins installieren
log_info "Installiere TMUX Plugins..."
sudo -u "$STORAGE_USER" bash -c "source $TMUX_PLUGINS_DIR/tpm/bin/install_plugins"

# Usage Information
echo ""
echo -e "${GREEN}✅ TMUX Installation abgeschlossen${NC}"
echo ""
echo -e "${BLUE}Verwendung:${NC}"
echo "  tmux                      # TMUX starten"
echo "  tmux new -s sessionname   # Neue Session"
echo "  tmux attach -t sessionname # Session attachen"
echo "  ctmux                     # Kurzform mit CCC Config"
echo ""
echo -e "${YELLOW}CCC Management Session:${NC}"
echo "  tmux attach -t ccc        # CCC Management Session"
echo ""
echo -e "${GREEN}TMUX Cheat Sheet:${NC}"
echo "  Ctrl+a |                  # Horizontal split"
echo "  Ctrl+a -                  # Vertical split"
echo "  Ctrl+a h/j/k/l            # Pane navigation"
echo "  Ctrl+a d                  # Detach session"
echo "  Ctrl+a c                  # New window"
echo "  Ctrl+a n/p                # Next/previous window"
echo ""
echo -e "${BLUE}Konfiguration:${NC}"
echo "  Config: $TMUX_CONFIG_DIR/tmux.conf"
echo "  Plugins: $TMUX_PLUGINS_DIR"
echo ""

log_success "TMUX installation abgeschlossen (CCC CODE Style)"
