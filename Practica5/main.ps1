# ============================================================
# main.ps1 - Practica 5: Automatizacion de Servidor FTP
#            Windows Server 2022 + IIS FTP Service
# ============================================================

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# --- Ruta base del servidor FTP ---
$RUTA_FTP = "C:\FTP"

# --- Cargar modulos ---
$libPath = Join-Path $PSScriptRoot "lib"
. "$libPath\instalar.ps1"
. "$libPath\directorios.ps1"
. "$libPath\usuarios.ps1"
. "$libPath\ftp-config.ps1"
. "$libPath\cam-grupo.ps1"

# ============================================================
function Mostrar-Banner {
    Clear-Host
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host "   PRACTICA 5 - SERVIDOR FTP AUTOMATIZADO   " -ForegroundColor Cyan
    Write-Host "   Windows Server 2022 + IIS FTP Service    " -ForegroundColor Cyan
    Write-Host "=============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Mostrar-Menu {
    Write-Host "`n--- MENU PRINCIPAL ---" -ForegroundColor White
    Write-Host "  1. Instalar y configurar servidor FTP (primera vez)" -ForegroundColor Yellow
    Write-Host "  2. Crear nuevos usuarios" -ForegroundColor Yellow
    Write-Host "  3. Cambiar grupo de un usuario" -ForegroundColor Yellow
    Write-Host "  4. Listar usuarios y grupos" -ForegroundColor Yellow
    Write-Host "  5. Salir" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Seleccione una opcion: " -NoNewline
}

# ============================================================
# INICIO
# ============================================================
Mostrar-Banner

# Crear carpeta raiz si no existe
if (-not (Test-Path $RUTA_FTP)) {
    New-Item -ItemType Directory -Path $RUTA_FTP -Force | Out-Null
    Write-Host "[+] Carpeta raiz FTP creada en $RUTA_FTP" -ForegroundColor Green
}
if (-not (Test-Path "$RUTA_FTP\usuarios")) {
    New-Item -ItemType Directory -Path "$RUTA_FTP\usuarios" -Force | Out-Null
}

# Bucle principal
do {
    Mostrar-Banner
    Mostrar-Menu
    $opcion = Read-Host

    switch ($opcion) {
        "1" {
            Write-Host "`n[PASO 1] Instalando IIS y FTP Service..." -ForegroundColor Cyan
            $ok = Instalar-FTP
            if ($ok) {
                Write-Host "`n[PASO 2] Inicializando grupos del sistema..." -ForegroundColor Cyan
                Inicializar-Grupos

                Write-Host "`n[PASO 3] Creando estructura de directorios..." -ForegroundColor Cyan
                Inicializar-CarpetaRaiz -RutaFTP $RUTA_FTP

                Write-Host "`n[PASO 4] Configurando sitio FTP en IIS..." -ForegroundColor Cyan
                Configurar-SitioFTP -RutaFTP $RUTA_FTP -Puerto 21

                Write-Host "`n[OK] Servidor FTP listo." -ForegroundColor Green
            }
            Pause
        }
        "2" {
            Crear-Usuarios -RutaFTP $RUTA_FTP
            Pause
        }
        "3" {
            Cambiar-GrupoUsuario -RutaFTP $RUTA_FTP
            Pause
        }
        "4" {
            Listar-Usuarios
            Pause
        }
        "5" {
            Write-Host "`nSaliendo..." -ForegroundColor Gray
        }
        default {
            Write-Host "`n[!] Opcion no valida." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($opcion -ne "5")