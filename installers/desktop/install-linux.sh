#!/bin/bash

# MSL Process - Instalador Linux (Modo Escritorio)
# Compatible con Ubuntu/Debian y derivados

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "═══════════════════════════════════════════════"
echo "    MSL Process - Instalador Linux"
echo "    Modo: Escritorio (Local)"
echo "═══════════════════════════════════════════════"
echo ""

# Rutas
INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$(dirname "$INSTALLER_DIR")")"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
LAUNCHER_DIR="$ROOT_DIR/launcher"

echo "📁 Directorio de instalación: $ROOT_DIR"
echo ""

# ============================================================================
# PASO 1: Verificar Julia
# ============================================================================
echo -e "${YELLOW}🔍 PASO 1/6: Verificando Julia...${NC}"

if command -v julia &> /dev/null; then
    JULIA_VERSION=$(julia --version)
    echo -e "${GREEN}✅ Julia encontrado: $JULIA_VERSION${NC}"
else
    echo -e "${RED}❌ Julia no está instalado${NC}"
    echo ""
    echo "Instalando Julia..."
    
    ARCH=$(uname -m)
    if [ "$ARCH" == "x86_64" ]; then
        JULIA_URL="https://julialang-s3.julialang.org/bin/linux/x64/1.10/julia-1.10.0-linux-x86_64.tar.gz"
    else
        echo -e "${RED}Arquitectura no soportada: $ARCH${NC}"
        exit 1
    fi
    
    cd /tmp
    wget -q --show-progress $JULIA_URL -O julia.tar.gz
    tar -xzf julia.tar.gz
    sudo mv julia-* /opt/julia
    sudo ln -sf /opt/julia/bin/julia /usr/local/bin/julia
    
    echo -e "${GREEN}✅ Julia instalado${NC}"
fi
echo ""

# ============================================================================
# PASO 2: Verificar Node.js
# ============================================================================
echo -e "${YELLOW}🔍 PASO 2/6: Verificando Node.js...${NC}"

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    NPM_VERSION=$(npm --version)
    echo -e "${GREEN}✅ Node.js encontrado: $NODE_VERSION${NC}"
    echo -e "${GREEN}✅ npm encontrado: v$NPM_VERSION${NC}"
else
    echo -e "${RED}❌ Node.js no está instalado${NC}"
    echo ""
    echo "Instalando Node.js..."
    
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    
    echo -e "${GREEN}✅ Node.js instalado${NC}"
fi
echo ""

# ============================================================================
# PASO 3: Instalar dependencias de Julia
# ============================================================================
echo -e "${YELLOW}📦 PASO 3/6: Instalando dependencias de Julia...${NC}"

cd "$BACKEND_DIR"
julia --project=. -e "using Pkg; Pkg.instantiate()"

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error instalando dependencias de Julia${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Dependencias de Julia instaladas${NC}"
echo ""

# ============================================================================
# PASO 4: Instalar dependencias del launcher
# ============================================================================
echo -e "${YELLOW}📦 PASO 4/6: Instalando dependencias del launcher...${NC}"

cd "$LAUNCHER_DIR"
npm install --silent

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error instalando dependencias del launcher${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Dependencias del launcher instaladas${NC}"
echo ""

# ============================================================================
# PASO 5: Compilar frontend
# ============================================================================
echo -e "${YELLOW}🔨 PASO 5/6: Compilando frontend...${NC}"

cd "$FRONTEND_DIR"

# Instalar dependencias si no existen
if [ ! -d "node_modules" ]; then
    echo "   Instalando dependencias de React..."
    npm install --silent
fi

# Copiar .env.desktop a .env
cp .env.desktop .env

# Compilar
echo "   Compilando aplicación React (esto puede tardar 1-2 minutos)..."
npm run build --silent

if [ $? -ne 0 ]; then
    echo -e "${RED}❌ Error compilando frontend${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Frontend compilado correctamente${NC}"
echo ""

# ============================================================================
# PASO 6: Crear acceso directo (.desktop file)
# ============================================================================
echo -e "${YELLOW}📌 PASO 6/6: Creando acceso directo...${NC}"

DESKTOP_FILE="$HOME/.local/share/applications/msl-process.desktop"
mkdir -p "$HOME/.local/share/applications"

cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=MSL Process
Comment=Sistema de Análisis de Imágenes Médicas
Exec=node "$LAUNCHER_DIR/launcher-desktop.js"
Path=$LAUNCHER_DIR
Icon=utilities-terminal
Terminal=true
Type=Application
Categories=Science;Medical;Education;
EOF

chmod +x "$DESKTOP_FILE"

# Crear también symlink en Desktop si existe
if [ -d "$HOME/Desktop" ]; then
    ln -sf "$DESKTOP_FILE" "$HOME/Desktop/msl-process.desktop"
    echo -e "${GREEN}✅ Acceso directo creado en el Escritorio${NC}"
else
    echo -e "${GREEN}✅ Acceso directo creado en el menú de aplicaciones${NC}"
fi
echo ""

# ============================================================================
# INSTALACIÓN COMPLETADA
# ============================================================================
echo "═══════════════════════════════════════════════"
echo -e "${GREEN}    ✅ INSTALACIÓN COMPLETADA EXITOSAMENTE${NC}"
echo "═══════════════════════════════════════════════"
echo ""
echo "Para iniciar MSL Process:"
echo -e "  ${CYAN}1. Busca 'MSL Process' en el menú de aplicaciones${NC}"
echo -e "  ${CYAN}2. O ejecuta desde terminal:${NC}"
echo -e "     ${NC}cd $LAUNCHER_DIR${NC}"
echo -e "     ${NC}node launcher-desktop.js${NC}"
echo ""
echo -e "${YELLOW}📚 Documentación: README.md${NC}"
echo ""