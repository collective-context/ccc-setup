# CCC Commander (CCC) - Complete Bundle

## 🚀 Installation

```bash
# Einzeiler-Installation
curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | sudo -E bash

# Oder manuell
git clone https://github.com/collective-context/ccc
cd ccc
./setup.sh
```

### 📦 Enthaltene Komponenten
* 🤖 AI & Developer Tools
* Aider: AI Coding Assistant mit OpenRouter
* MCP: Model Context Protocol (Anthropic)
* FastMCP: High-performance MCP Framework
* LangGraph: Agent Orchestration Framework
* libtmux: Python ORM für TMUX

### 🖥️ System & Infrastructure
* TMUX: Terminal Multiplexer mit Plugins
* MySQL 8: Database Server
* NGINX: Web Server
* Node.js: Runtime für Ghost CMS

### 🌐 Web Applications
* Ghost CMS: Moderne Publishing Platform
* BookStack: Wiki & Documentation System

### 🏗️ Architecture
```bash
/home/user-data/           # ALLE Daten (MiaB Pattern)
├── tools/                 # Developer Tools
├── config/                # Konfigurationen
├── mysql/                 # Datenbank
├── www/                   # Web Apps
└── backups/               # Automatische Backups
```

### 🔧 Verwendung
```bash
# AI Coding
aider example.py

# TMUX Management
tmux
ccc-libtmux list-sessions

# MCP Development
ccc-mcp --help

# Agent Orchestration
python /home/user-data/tools/langgraph/agents/basic_agent.py
```

### 🎯 Features
* ✅ MiaB Pattern: Einfache Migration durch /home/user-data
* ✅ Idempotent: Script kann beliebig oft ausgeführt werden
* ✅ Modular: Einzelne Komponenten können upgedatet werden
* ✅ Production Ready: Fehlerbehandlung, Logging, Backup

### 📋 System Requirements
* OS: Ubuntu 24.04, Debian 12, Ubuntu 22.04
* RAM: 2GB+ (4GB empfohlen für alle Komponenten)
* Storage: 20GB+ freier Speicher
* Network: Internet für Paket-Downloads

### 🆘 Support
* Bei Problemen:
* Logs prüfen: /var/log/ccc-*.log
* Konfiguration: /etc/ccc.conf
* Storage: /home/user-data/

### 📄 Lizenz
* MIT License - Siehe LICENSE Datei für Details.
* Viel Erfolg mit deiner neuen Developer Workstation! 🎉


### 📁 1. GITHUB_SETUP.md (GitHub Anleitung)
* 🚀 So pushen Sie dieses Repository zu GitHub:

### 1. GitHub Repository erstellen
```bash
# Auf GitHub.com:
# - Repository erstellen: collective-context/ccc-setup
# - Keine README/Lizenz/etc. hinzufügen (leeres Repo)
```

### 2. Repository zu GitHub pushen
```bash
# Remote Origin hinzufügen
git remote add origin https://github.com/collective-context/ccc-setup.git

# Zu main Branch pushen
git branch -M main
git push -u origin main
```

### 3. Installationstest
```bash
# Test-Installation
curl -sL https://raw.githubusercontent.com/collective-context/ccc-setup/main/setup.sh | sudo -E bash
```

### 📊 Repository Struktur
```bash
ccc/
├── setup.sh                 # Bootstrap Script
├── setup/
│   ├── start.sh            # Haupt-Setup
│   ├── functions.sh        # Hilfsfunktionen
│   ├── questions.sh        # Interaktive Fragen
│   ├── preflight.sh        # Preflight Checks
│   └── modules/            # Alle Installations-Module
│       ├── system.sh       # System Basis
│       ├── mysql8.sh       # MySQL Database
│       ├── nodejs.sh       # Node.js Runtime
│       ├── nginx.sh        # Web Server
│       ├── ssl.sh          # SSL Zertifikate
│       ├── tmux.sh         # Terminal Multiplexer
│       ├── aider.sh        # AI Coding Assistant
│       ├── mcp.sh          # Model Context Protocol
│       ├── fastmcp.sh      # FastMCP Framework
│       ├── langgraph.sh    # LangGraph Agents
│       ├── libtmux.sh      # libtmux Python ORM
│       ├── ghost.sh        # Ghost CMS
│       ├── bookstack.sh    # BookStack Wiki
│       └── finalize.sh     # Abschluss
├── README.md               # Dokumentation
└── GITHUB_SETUP.md        # Diese Anleitung
```
