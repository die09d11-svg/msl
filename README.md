# MSL Process

Sistema de Análisis de Imágenes Médicas - Radiómicas y Estadísticas

## Instalación Rápida

### Windows (Escritorio)
```powershell
# Como administrador
cd MSL_Process_Installer\installers\desktop
.\install-windows.ps1
```

### Linux (Escritorio)
```bash
cd MSL_Process_Installer/installers/desktop
sudo bash install-linux.sh
```

### Ubuntu Server (Red Local)
```bash
cd MSL_Process_Installer/installers/server
sudo bash install-ubuntu-server.sh
```

## Requisitos

- **Julia** 1.9+ ([Descargar](https://julialang.org/downloads/))
- **Node.js** 18+ LTS ([Descargar](https://nodejs.org/))
- **RAM:** Mínimo 4 GB (recomendado 8 GB)
- **Disco:** 2 GB libres

## Uso - Modo Escritorio

1. Doble clic en **"MSL Process"** en el Escritorio
2. Se abrirá automáticamente en el navegador
3. Para cerrar: Ctrl+C en la terminal

**O desde terminal:**
```bash
cd launcher
node launcher-desktop.js
```

## Uso - Modo Servidor

El servidor inicia automáticamente como servicio systemd.

**Ver estado:**
```bash
sudo systemctl status msl-process
```

**Acceso desde otros dispositivos:**
```
http://[IP-DEL-SERVIDOR]:3000
```

## Estructura del Proyecto
```
MSL_Process_Installer/
├── backend/          # Servidor Julia
├── frontend/         # Aplicación React
├── launcher/         # Scripts de inicio
└── installers/       # Instaladores automáticos
```

## Solución de Problemas

### Julia no inicia
```bash
julia -t auto backend/server.jl
```

### Puerto ocupado
Cambia los puertos en `server.jl` y `App.js`

### Firewall bloquea conexiones
```bash
# Windows
netsh advfirewall firewall add rule name="MSL Process" dir=in action=allow protocol=TCP localport=8000,3000

# Linux
sudo ufw allow 8000/tcp
sudo ufw allow 3000/tcp
```

## Características

- Visualización de imágenes NIfTI y DICOM
- Análisis radiómico (100+ features)
- Análisis estadístico paramétrico/no paramétrico
- Procesamiento paralelo
- Exportación a Excel

## Licencia
 Ver LICENSE para detalles

## Reportar Problemas

GitHub Issues: *no disponible por el momento

---

**Desarrollado por: Laboratorio de Fisica Medica FCFM BUAP y LarkDsc**  
**Versión:** 1.0.0
