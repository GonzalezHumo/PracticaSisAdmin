# ============================================================
#  mainSSL.ps1  -  Practica 7 - Administracion de Sistemas
#  Orquestador principal Windows
#  Infraestructura de Despliegue Seguro e Instalacion Hibrida
# ============================================================

# Verificar ejecucion como Administrador
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[!] Este script debe ejecutarse como Administrador." -ForegroundColor Red
    exit 1
}

# Cargar funciones P7
$scriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Definition
$funcionesP7  = Join-Path $scriptDir "funciones_SSL.ps1"

if (-not (Test-Path $funcionesP7)) {
    Write-Host "[!] No se encontro funciones_SSL.ps1 en: $funcionesP7" -ForegroundColor Red
    exit 1
}
. $funcionesP7

# ============================================================
#  MENU PRINCIPAL
# ============================================================

function Mostrar-Menu-P7 {
    Write-Host "¿Que deseas hacer?" -ForegroundColor Cyan
    Write-Host "  [1] Instalar servicio via WEB  (gestor de paquetes)"
    Write-Host "  [2] Instalar servicio via FTP  (repositorio privado)"
    Write-Host "  [3] Activar SSL/TLS en un servicio instalado"
    Write-Host "  [4] Verificar estado SSL de todos los servicios"
    Write-Host "  [5] Salir"
    Write-Host ""

    do {
        $op = Read-Host "Opcion"
        $op = $op.Trim()
    } while ($op -notmatch '^[1-5]$')

    return $op
}

# ============================================================
#  SUBMENU - ELEGIR SERVICIO PARA SSL
# ============================================================

function Elegir-Servicio-SSL {
    Write-Host ""
    Write-Host "¿En que servicio deseas activar SSL?" -ForegroundColor Cyan
    Write-Host "  [1] IIS     (HTTP -> HTTPS, puerto 443)"
    Write-Host "  [2] Apache  (HTTP -> HTTPS, puerto 443)"
    Write-Host "  [3] Nginx   (HTTP -> HTTPS, puerto 443)"
    Write-Host "  [4] IIS-FTP (FTPS, canal control y datos cifrados)"
    Write-Host "  [5] Todos los anteriores"
    Write-Host ""

    do {
        $op = Read-Host "Opcion"
        $op = $op.Trim()
    } while ($op -notmatch '^[1-5]$')

    return $op
}

# ============================================================
#  SUBMENU - INSTALACION VIA WEB (reutiliza funciones P6)
# ============================================================

function Instalar-Via-Web {
    $funcP6 = Join-Path $scriptDir "http_functions.ps1"

    if (-not (Test-Path $funcP6)) {
        Write-Host "[!] No se encontro http_functions.ps1 (Practica 6)." -ForegroundColor Red
        Write-Host "[!] Coloca http_functions.ps1 en el mismo directorio." -ForegroundColor Yellow
        return
    }

    . $funcP6

    Write-Host ""
    Write-Host "--- Instalacion via Gestor de Paquetes (WEB) ---" -ForegroundColor Cyan
    Write-Host "Selecciona el servidor a instalar:" -ForegroundColor Cyan
    Write-Host "  [1] IIS"
    Write-Host "  [2] Apache"
    Write-Host "  [3] Nginx"
    Write-Host ""

    do {
        $op = Read-Host "Opcion"
        $op = $op.Trim()
    } while ($op -notmatch '^[1-3]$')

    switch ($op) {
        "1" {
            $versiones = Obtener-VersionIIS
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "IIS"
            $puerto    = Pedir-Puerto
            Instalar-IIS -Puerto $puerto
        }
        "2" {
            $versiones = Obtener-VersionesApache
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "Apache"
            $puerto    = Pedir-Puerto
            Instalar-Apache -Version $version -Puerto $puerto
        }
        "3" {
            $versiones = Obtener-VersionesNginx
            $version   = Seleccionar-Version -Versiones $versiones -Servidor "Nginx"
            $puerto    = Pedir-Puerto
            Instalar-Nginx -Version $version -Puerto $puerto
        }
    }

    # Preguntar si desea activar SSL inmediatamente
    Write-Host ""
    if (Preguntar-SSL -Servicio "el servicio recien instalado") {
        switch ($op) {
            "1" { Activar-SSL-IIS    }
            "2" { Activar-SSL-Apache }
            "3" { Activar-SSL-Nginx  }
        }
    }
}

# ============================================================
#  FLUJO - ACTIVAR SSL (opcion 3 del menu principal)
# ============================================================

function Flujo-Activar-SSL {
    $svc = Elegir-Servicio-SSL

    switch ($svc) {
        "1" {
            if (Preguntar-SSL -Servicio "IIS") {
                Activar-SSL-IIS
            }
        }
        "2" {
            if (Preguntar-SSL -Servicio "Apache") {
                Activar-SSL-Apache
            }
        }
        "3" {
            if (Preguntar-SSL -Servicio "Nginx") {
                Activar-SSL-Nginx
            }
        }
        "4" {
            if (Preguntar-SSL -Servicio "IIS-FTP (FTPS)") {
                Activar-SSL-IISFTP
            }
        }
        "5" {
            Write-Host "[*] Activando SSL en todos los servicios..." -ForegroundColor Cyan
            Activar-SSL-IIS
            Activar-SSL-Apache
            Activar-SSL-Nginx
            Activar-SSL-IISFTP
        }
    }
}

# ============================================================
#  FLUJO PRINCIPAL
# ============================================================

Mostrar-Banner-P7

do {
    $opcion = Mostrar-Menu-P7

    switch ($opcion) {
        "1" {
            Instalar-Via-Web
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
            Mostrar-Banner-P7
        }
        "2" {
            Instalar-Desde-FTP
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
            Mostrar-Banner-P7
        }
        "3" {
            Flujo-Activar-SSL
            Write-Host ""
            Read-Host "Presiona ENTER para volver al menu"
            Mostrar-Banner-P7
        }
        "4" {
            Resumen-Verificacion-Windows
            Read-Host "Presiona ENTER para volver al menu"
            Mostrar-Banner-P7
        }
        "5" {
            Write-Host "Cerrando el script. Exito con la practica." -ForegroundColor Green
        }
    }

} while ($opcion -ne "5")
