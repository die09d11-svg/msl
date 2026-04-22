# MSL Process - Instalador Windows (Modo Escritorio)
# Requiere PowerShell 5.1+ y permisos de administrador

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "    MSL Process - Instalador Windows" -ForegroundColor Cyan
Write-Host "    Modo: Escritorio (Local)" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Rutas
$INSTALLER_DIR = $PSScriptRoot
$ROOT_DIR = Split-Path (Split-Path $INSTALLER_DIR -Parent) -Parent
$BACKEND_DIR = Join-Path $ROOT_DIR "backend"
$FRONTEND_DIR = Join-Path $ROOT_DIR "frontend"
$LAUNCHER_DIR = Join-Path $ROOT_DIR "launcher"

Write-Host "📁 Directorio de instalación: $ROOT_DIR" -ForegroundColor Gray
Write-Host ""

# ============================================================================
# PASO 1: Verificar Julia
# ============================================================================
Write-Host "🔍 PASO 1/6: Verificando Julia..." -ForegroundColor Yellow

$juliaPath = Get-Command julia -ErrorAction SilentlyContinue

if (-not $juliaPath) {
    Write-Host "❌ Julia no está instalado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor instala Julia 1.9+ desde:" -ForegroundColor White
    Write-Host "https://julialang.org/downloads/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Después de instalar, reinicia esta terminal y ejecuta de nuevo." -ForegroundColor Yellow
    pause
    exit 1
}

$juliaVersion = julia --version
Write-Host "✅ Julia encontrado: $juliaVersion" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PASO 2: Verificar Node.js
# ============================================================================
Write-Host "🔍 PASO 2/6: Verificando Node.js..." -ForegroundColor Yellow

$nodePath = Get-Command node -ErrorAction SilentlyContinue

if (-not $nodePath) {
    Write-Host "❌ Node.js no está instalado" -ForegroundColor Red
    Write-Host ""
    Write-Host "Por favor instala Node.js LTS desde:" -ForegroundColor White
    Write-Host "https://nodejs.org/" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Después de instalar, reinicia esta terminal y ejecuta de nuevo." -ForegroundColor Yellow
    pause
    exit 1
}

$nodeVersion = node --version
$npmVersion = npm --version
Write-Host "✅ Node.js encontrado: $nodeVersion" -ForegroundColor Green
Write-Host "✅ npm encontrado: v$npmVersion" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PASO 3: Instalar dependencias de Julia
# ============================================================================
Write-Host "📦 PASO 3/6: Instalando dependencias de Julia..." -ForegroundColor Yellow

Push-Location $BACKEND_DIR

# Activar proyecto e instalar dependencias
julia --project=. -e "using Pkg; Pkg.instantiate()"

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error instalando dependencias de Julia" -ForegroundColor Red
    Pop-Location
    pause
    exit 1
}

Pop-Location
Write-Host "✅ Dependencias de Julia instaladas" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PASO 4: Instalar dependencias de Node.js (launcher)
# ============================================================================
Write-Host "📦 PASO 4/6: Instalando dependencias del launcher..." -ForegroundColor Yellow

Push-Location $LAUNCHER_DIR
npm install --silent

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error instalando dependencias del launcher" -ForegroundColor Red
    Pop-Location
    pause
    exit 1
}

Pop-Location
Write-Host "✅ Dependencias del launcher instaladas" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PASO 5: Compilar frontend (modo escritorio)
# ============================================================================
Write-Host "🔨 PASO 5/6: Compilando frontend..." -ForegroundColor Yellow

Push-Location $FRONTEND_DIR

# Instalar dependencias si no existen
if (-not (Test-Path "node_modules")) {
    Write-Host "   Instalando dependencias de React..." -ForegroundColor Gray
    npm install --silent
}

# Copiar .env.desktop a .env
Copy-Item ".env.desktop" -Destination ".env" -Force

# Compilar
Write-Host "   Compilando aplicación React (esto puede tardar 1-2 minutos)..." -ForegroundColor Gray
npm run build --silent

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Error compilando frontend" -ForegroundColor Red
    Pop-Location
    pause
    exit 1
}

Pop-Location
Write-Host "✅ Frontend compilado correctamente" -ForegroundColor Green
Write-Host ""

# ============================================================================
# PASO 6: Crear acceso directo
# ============================================================================
Write-Host "📌 PASO 6/6: Creando acceso directo..." -ForegroundColor Yellow

$desktopPath = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktopPath "MSL Process.lnk"
$launcherScript = Join-Path $LAUNCHER_DIR "launcher-desktop.js"

$WScriptShell = New-Object -ComObject WScript.Shell
$shortcut = $WScriptShell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = "node"
$shortcut.Arguments = "`"$launcherScript`""
$shortcut.WorkingDirectory = $LAUNCHER_DIR
$shortcut.IconLocation = "shell32.dll,13"  # Icono de computadora
$shortcut.Description = "MSL Process - Sistema de Análisis de Imágenes Médicas"
$shortcut.Save()

Write-Host "✅ Acceso directo creado en el Escritorio" -ForegroundColor Green
Write-Host ""

# ============================================================================
# INSTALACIÓN COMPLETADA
# ============================================================================
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
Write-Host "    ✅ INSTALACIÓN COMPLETADA EXITOSAMENTE" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "Para iniciar MSL Process:" -ForegroundColor White
Write-Host "  1. Haz doble clic en 'MSL Process' en tu Escritorio" -ForegroundColor Cyan
Write-Host "  2. O ejecuta desde terminal:" -ForegroundColor Cyan
Write-Host "     cd $LAUNCHER_DIR" -ForegroundColor Gray
Write-Host "     node launcher-desktop.js" -ForegroundColor Gray
Write-Host ""
Write-Host "📚 Documentación: README.md" -ForegroundColor Yellow
Write-Host "🐛 Reportar problemas: [tu GitHub issues URL]" -ForegroundColor Yellow
Write-Host ""
pause