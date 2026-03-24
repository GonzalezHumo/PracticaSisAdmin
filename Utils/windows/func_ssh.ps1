# funciones_ssh.ps1
# Funciones para la gestion del servidor SSH (Windows Server Core)

. "$PSScriptRoot\funciones_comunes.ps1"

# Verifica si OpenSSH esta instalado y el estado del servicio sshd
function Test-SSH {
    Write-Host "Verificando servidor SSH..."

    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if ($null -eq $ssh -or $ssh.State -ne "Installed") {
        Write-Host "OpenSSH Server: NO INSTALADO"
        Write-Host "Use la opcion 16 para instalarlo"
        return
    }

    Write-Host "OpenSSH Server: INSTALADO"
    Write-Host ""

    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($servicio -and $servicio.Status -eq "Running") {
        Write-Host "Servicio sshd: ACTIVO"
    } else {
        Write-Host "Servicio sshd: INACTIVO"
    }

    if ($servicio -and $servicio.StartType -eq "Automatic") {
        Write-Host "Inicio automatico: HABILITADO"
    } else {
        Write-Host "Inicio automatico: DESHABILITADO"
    }

    Write-Host ""

    # Verificar regla de firewall para el puerto 22
    $regla = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($regla -and $regla.Enabled -eq "True") {
        Write-Host "Firewall puerto 22: ABIERTO"
    } else {
        Write-Host "Firewall puerto 22: CERRADO"
    }
}

# Instala OpenSSH Server, abre el puerto 22 y habilita el servicio
function Install-SSH {
    Write-Host "Instalacion del servidor SSH..."

    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if ($ssh -and $ssh.State -eq "Installed") {
        Write-Host "OpenSSH Server ya esta instalado"
        return
    }

    Write-Host "Instalando OpenSSH Server..."
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 | Out-Null

    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if (-not $ssh -or $ssh.State -ne "Installed") {
        Write-Host "Error: la instalacion fallo"
        return
    }

    Write-Host "OpenSSH Server instalado"
    Write-Host ""

    # Configurar inicio automatico y arrancar el servicio
    Write-Host "Configurando servicio sshd..."
    Set-Service -Name sshd -StartupType Automatic
    Start-Service sshd
    Start-Sleep -Seconds 2

    # Abrir puerto 22 en el firewall
    Write-Host "Abriendo puerto 22 en el firewall..."
    $regla = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue

    if (-not $regla) {
        New-NetFirewallRule -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server (sshd)" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22 | Out-Null
        Write-Host "Regla de firewall creada"
    } else {
        Write-Host "Regla de firewall ya existe"
    }

    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($servicio -and $servicio.Status -eq "Running") {
        # Obtener IP del servidor para mostrar como conectarse
        $ip_servidor = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object {
            $_.InterfaceAlias -notlike "*Loopback*"
        } | Select-Object -First 1).IPAddress

        Write-Host ""
        Write-Host "SSH instalado y configurado"
        Write-Host "  Servicio sshd: ACTIVO"
        Write-Host "  Puerto: 22"
        if ($ip_servidor) { Write-Host "  Conectarse con: ssh Administrator@$ip_servidor" }
    } else {
        Write-Host "Error: el servicio sshd no inicio"
    }
}

# Muestra el estado actual del servicio sshd
function Get-EstadoSSH {
    Write-Host "Estado del servidor SSH"

    $ssh = Get-WindowsCapability -Online | Where-Object { $_.Name -like "OpenSSH.Server*" }

    if ($null -eq $ssh -or $ssh.State -ne "Installed") {
        Write-Host "El servidor SSH no esta instalado"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    Write-Host "OpenSSH Server: INSTALADO"
    Write-Host ""

    $servicio = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if ($servicio -and $servicio.Status -eq "Running") {
        Write-Host "Estado: ACTIVO"
    } else {
        Write-Host "Estado: INACTIVO"
    }

    if ($servicio -and $servicio.StartType -eq "Automatic") {
        Write-Host "Inicio automatico: HABILITADO"
    } else {
        Write-Host "Inicio automatico: DESHABILITADO"
    }

    Write-Host ""

    $regla = Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue
    if ($regla -and $regla.Enabled -eq "True") {
        Write-Host "Firewall puerto 22: ABIERTO"
    } else {
        Write-Host "Firewall puerto 22: CERRADO"
    }

    Write-Host ""
    if ($servicio) {
        $servicio | Format-List Name, Status, StartType
    }
}