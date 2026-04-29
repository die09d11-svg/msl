#!/bin/bash

# MSL Process - Instalador Ubuntu Server (Modo Red)
# Para uso en servidor dedicado con acceso de múltiples usuarios

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

echo "═══════════════════════════════════════════════"
echo "    MSL Process - Instalador Servidor Ubuntu"
echo "    Modo: Servidor (Red Local)"
echo "═══════════════════════════════════════════════"
echo ""

# Verificar que se ejecuta como sudo
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Este script debe ejecutarse como root (sudo)${NC}"
    exit 1
fi

# Rutas
INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$INSTALLER_DIR")")"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
LAUNCHER_DIR="$ROOT_DIR/launcher"

echo "📁 Directorio de instalación: $ROOT_DIR"
echo ""

# Detectar IP local
LOCAL_IP=$(hostname -I | awk '{print $1}')
echo -e "${CYAN}🌐 IP del servidor: $LOCAL_IP${NC}"
echo -e "${CYAN}📡 URL de acceso: http://$LOCAL_IP:3000${NC}"
echo ""

# ============================================================================
# Verificar e instalar dependencias (igual que desktop)
# ============================================================================
# ... [Mismo código que install-linux.sh para pasos 1-4] ...

# ============================================================================
# PASO 5: Compilar frontend (MODO SERVIDOR)
# ============================================================================
echo -e "${YELLOW}🔨 PASO 5/7: Compilando frontend (modo servidor)...${NC}"

cd "$FRONTEND_DIR"

if [ ! -d "node_modules" ]; then
    npm install --silent
fi

# Copiar .env.server a .env (IMPORTANTE)
cp .env.server .env

npm run build --silent

# Mover build a build-server
mv build build-server

echo -e "${GREEN}✅ Frontend compilado para modo servidor${NC}"
echo ""

# ============================================================================
# PASO 6: Configurar firewall
# ============================================================================
echo -e "${YELLOW}🔥 PASO 6/7: Configurando firewall...${NC}"

if command -v ufw &> /dev/null; then
    ufw allow 8000/tcp comment "MSL Process - Backend Julia"
    ufw allow 3000/tcp comment "MSL Process - Frontend React"
    echo -e "${GREEN}✅ Puertos 8000 y 3000 abiertos en firewall${NC}"
else
    echo -e "${YELLOW}⚠️  UFW no encontrado, configura el firewall manualmente${NC}"
fi
echo ""

# ============================================================================
# PASO 7: Crear servicio systemd
# ============================================================================
echo -e "${YELLOW}📌 PASO 7/7: Creando servicio systemd...${NC}"

cat > /etc/systemd/system/msl-process.service << EOF
[Unit]
Description=MSL Process - Medical Imaging Analysis Server
After=network.target

[Service]
Type=simple
User=$SUDO_USER
WorkingDirectory=$LAUNCHER_DIR
ExecStart=/usr/bin/node $LAUNCHER_DIR/launcher-server.js
Restart=on-failure
RestartSec=10
Environment="NODE_ENV=production"
Environment="MSL_SERVER_MODE=server"

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable msl-process.service
systemctl start msl-process.service

echo -e "${GREEN}✅ Servicio systemd creado y iniciado${NC}"
echo ""

# ============================================================================
# INSTALACIÓN COMPLETADA
# ============================================================================
echo "═══════════════════════════════════════════════"
echo -e "${GREEN}    ✅ INSTALACIÓN COMPLETADA${NC}"
echo "═══════════════════════════════════════════════"
echo ""
echo -e "${CYAN}Servidor iniciado en: http://$LOCAL_IP:3000${NC}"
echo ""
echo "Comandos útiles:"
echo -e "  ${YELLOW}Ver estado:${NC}  sudo systemctl status msl-process"
echo -e "  ${YELLOW}Detener:${NC}     sudo systemctl stop msl-process"
echo -e "  ${YELLOW}Reiniciar:${NC}   sudo systemctl restart msl-process"
echo -e "  ${YELLOW}Ver logs:${NC}    sudo journalctl -u msl-process -f"
echo ""