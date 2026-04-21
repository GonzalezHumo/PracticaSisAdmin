# funciones_comunes.ps1
# Funciones compartidas entre todos los servicios (DHCP, DNS, SSH)

# Verifica que el script se ejecute como administrador
function Test-Admin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Este script debe ejecutarse como Administrador"
        Write-Host "Haz clic derecho en PowerShell y selecciona 'Ejecutar como administrador'"
        exit 1
    }
}

# Verifica formato X.X.X.X y que cada octeto este entre 0 y 255
function Test-IP {
    param([string]$ip)

    if ($ip -notmatch '^\d+\.\d+\.\d+\.\d+$') {
        Write-Host "Formato invalido, debe ser: X.X.X.X (ejemplo: 192.168.1.1)"
        return $false
    }

    $octetos = $ip -split '\.'
    foreach ($oct in $octetos) {
        $val = [int]$oct
        if ($val -lt 0 -or $val -gt 255) {
            Write-Host "Error: cada octeto debe estar entre 0 y 255"
            return $false
        }
    }

    return $true
}

# El rango 127.x.x.x esta reservado para la interfaz local
function Test-NoLoopback {
    param([string]$ip)

    $primerOcteto = ($ip -split '\.')[0]
    if ([int]$primerOcteto -eq 127) {
        Write-Host "Error: no se puede usar la IP loopback (127.x.x.x)"
        return $false
    }

    return $true
}

# 255.255.255.255 es la direccion de broadcast general, no asignable
function Test-NoBroadcast {
    param([string]$ip)

    if ($ip -eq "255.255.255.255") {
        Write-Host "Error: no se puede usar la IP de broadcast"
        return $false
    }

    return $true
}

# 0.0.0.0 representa una ruta por defecto, no una IP valida de host
function Test-NoCero {
    param([string]$ip)

    if ($ip -eq "0.0.0.0") {
        Write-Host "Error: no se puede usar la IP 0.0.0.0"
        return $false
    }

    return $true
}

# Agrupa las 4 validaciones basicas para no repetirlas en cada funcion
function Test-IPCompleta {
    param([string]$ip)

    if (-not (Test-IP $ip))          { return $false }
    if (-not (Test-NoLoopback $ip))  { return $false }
    if (-not (Test-NoBroadcast $ip)) { return $false }
    if (-not (Test-NoCero $ip))      { return $false }

    return $true
}