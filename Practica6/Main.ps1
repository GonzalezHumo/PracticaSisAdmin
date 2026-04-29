# ============================================================
#  Practica 6 - Administracion de Sistemas
#  Rosa Karina Rosas Burgueno
# ============================================================

# Verificar ejecucion como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    exit 1
}

# Cargar funciones
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$funcionesPath = Join-Path $scriptDir "http_functions.ps1"
if (-not (Test-Path $funcionesPath)) {
    Write-Host "[!] No se encontro http_functions.ps1 en: $funcionesPath" -ForegroundColor Red
    exit 1
}
. $funcionesPath

# ── Flujo principal ──────────────────────────────────────────

Mostrar-Banner

do {
    $opcion = Mostrar-Menu

    switch ($opcion) {

        "1" {
            # IIS - instalacion forzosa, version del sistema
            $versiones = Obtener-VersionIIS
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "IIS"
            $puerto    = Pedir-Puerto
            Instalar-IIS -Puerto $puerto
            Write-Host ""
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host " Aprovisionamiento completado." -ForegroundColor Green
            Write-Host " Verifica con: curl -I http://localhost:$puerto" -ForegroundColor Cyan
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
        }

        "2" {
            # Apache Win64
            $versiones = Obtener-VersionesApache
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "Apache"
            $puerto    = Pedir-Puerto
            Instalar-Apache -Version $version -Puerto $puerto
            Write-Host ""
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host " Aprovisionamiento completado." -ForegroundColor Green
            Write-Host " Verifica con: curl -I http://localhost:$puerto" -ForegroundColor Cyan
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
        }

        "3" {
            # Nginx Windows
            $versiones = Obtener-VersionesNginx
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "Nginx"
            $puerto    = Pedir-Puerto
            Instalar-Nginx -Version $version -Puerto $puerto
            Write-Host ""
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host " Aprovisionamiento completado." -ForegroundColor Green
            Write-Host " Verifica con: curl -I http://localhost:$puerto" -ForegroundColor Cyan
            Write-Host "=================================================" -ForegroundColor Cyan
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
        }

        "4" {
            Write-Host "Saliendo..." -ForegroundColor Gray
        }
    }

} while ($opcion -ne "4")