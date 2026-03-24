# funciones_dns.ps1
# Funciones para la gestion del servidor DNS (Windows Server)

. "$PSScriptRoot\funciones_comunes.ps1"

# Verifica si el rol DNS esta instalado y el estado del servicio
function Test-DNS {
    Write-Host "Verificando servidor DNS..."

    $servicio = Get-Service -Name "DNS" -ErrorAction SilentlyContinue

    if ($null -eq $servicio) {
        Write-Host "Servicio DNS: NO ENCONTRADO"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    Write-Host "Servicio DNS: ENCONTRADO"
    Write-Host ""

    if ($servicio.Status -eq "Running") {
        Write-Host "Estado: ACTIVO"
    } else {
        Write-Host "Estado: INACTIVO"
    }

    Write-Host "Inicio automatico: $($servicio.StartType)"
}

# Instala el rol DNS y lo inicia con arranque automatico
function Install-DNS {
    Write-Host "Instalacion del servidor DNS..."

    $feature = Get-WindowsFeature -Name "DNS" -ErrorAction SilentlyContinue

    if ($null -ne $feature -and $feature.Installed) {
        Write-Host "El servidor DNS ya esta instalado"
        return
    }

    Write-Host "Instalando rol DNS..."
    Install-WindowsFeature -Name DNS -IncludeManagementTools | Out-Null

    $check = Get-WindowsFeature -Name "DNS"

    if ($check.Installed) {
        Write-Host ""
        Write-Host "DNS instalado correctamente"
        Start-Service -Name "DNS"
        Set-Service -Name "DNS" -StartupType Automatic
        Write-Host "Servicio iniciado y configurado para arranque automatico"
    } else {
        Write-Host "Error: la instalacion fallo"
    }
}

# Crea una zona DNS primaria con registro A y CNAME para www
function Add-Zona {
    Write-Host "Agregar zona DNS"

    $servicio = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
    if ($null -eq $servicio -or $servicio.Status -ne "Running") {
        Write-Host "Error: el servicio DNS no esta activo"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    # Pedir dominio
    do {
        $dominio = Read-Host "Ingrese el dominio (ejemplo: reprobados.com)"

        if ([string]::IsNullOrEmpty($dominio)) {
            Write-Host "Error: el dominio no puede estar vacio"
            continue
        }

        if ($dominio -notmatch '^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$') {
            Write-Host "Error: formato invalido, ejemplo: reprobados.com"
            continue
        }

        $zona_existente = Get-DnsServerZone -Name $dominio -ErrorAction SilentlyContinue
        if ($null -ne $zona_existente) {
            Write-Host "Error: la zona $dominio ya existe"
            continue
        }

        break
    } while ($true)

    # Pedir IP destino
    do {
        $ip_destino = Read-Host "Ingrese la IP destino del dominio"

        if ([string]::IsNullOrEmpty($ip_destino)) {
            Write-Host "Error: la IP no puede estar vacia"
            continue
        }

        if (-not (Test-IPCompleta $ip_destino)) { continue }

        break
    } while ($true)

    Write-Host ""
    Write-Host "Creando zona $dominio..."

    Add-DnsServerPrimaryZone -Name $dominio -ZoneFile "$dominio.dns" -ErrorAction Stop
    Add-DnsServerResourceRecordA -ZoneName $dominio -Name "@" -IPv4Address $ip_destino
    Add-DnsServerResourceRecordCName -ZoneName $dominio -Name "www" -HostNameAlias "$dominio."

    Write-Host ""
    Write-Host "Zona configurada exitosamente"
    Write-Host "  Dominio   : $dominio"
    Write-Host "  IP destino: $ip_destino"
}

# Lista todas las zonas DNS primarias configuradas
function Get-Zonas {
    Write-Host "Zonas DNS configuradas"

    $servicio = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
    if ($null -eq $servicio) {
        Write-Host "Error: el servicio DNS no esta instalado"
        return
    }

    $zonas = Get-DnsServerZone | Where-Object {
        $_.IsAutoCreated -eq $false -and $_.ZoneType -eq "Primary"
    }

    if ($null -eq $zonas -or $zonas.Count -eq 0) {
        Write-Host "No hay zonas configuradas"
        Write-Host "Use la opcion 3 para agregar una"
        return
    }

    Write-Host ""
    $contador = 1

    foreach ($zona in $zonas) {
        $registro_a = Get-DnsServerResourceRecord -ZoneName $zona.ZoneName -RRType A -Name "@" -ErrorAction SilentlyContinue
        $ip = if ($registro_a) { $registro_a.RecordData.IPv4Address } else { "(sin registro A)" }
        Write-Host "  $contador) $($zona.ZoneName) -> $ip"
        $contador++
    }

    Write-Host ""
    Write-Host "Total de zonas: $($contador - 1)"
}

# Verifica la resolucion DNS de una zona con Resolve-DnsName y Test-Connection
function Test-Configuracion {
    Write-Host "Validacion de configuracion DNS"

    $servicio = Get-Service -Name "DNS" -ErrorAction SilentlyContinue
    if ($null -eq $servicio -or $servicio.Status -ne "Running") {
        Write-Host "Error: el servicio DNS no esta activo"
        return
    }

    $zonas = Get-DnsServerZone | Where-Object {
        $_.IsAutoCreated -eq $false -and $_.ZoneType -eq "Primary"
    }

    if ($null -eq $zonas -or $zonas.Count -eq 0) {
        Write-Host "No hay zonas configuradas"
        return
    }

    Write-Host "Zonas disponibles:"
    Write-Host ""

    $lista    = @()
    $contador = 1

    foreach ($zona in $zonas) {
        Write-Host "  $contador) $($zona.ZoneName)"
        $lista += $zona.ZoneName
        $contador++
    }

    Write-Host ""

    do {
        $sel = Read-Host "Seleccione el numero del dominio a probar"
        if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $lista.Count) {
            Write-Host "Error: seleccione un numero entre 1 y $($lista.Count)"
            continue
        }
        break
    } while ($true)

    $dominio_elegido = $lista[[int]$sel - 1]

    $registro_a  = Get-DnsServerResourceRecord -ZoneName $dominio_elegido -RRType A -Name "@" -ErrorAction SilentlyContinue
    $ip_esperada = $registro_a.RecordData.IPv4Address.ToString()
    $ip_servidor = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notlike "*Loopback*" } | Select-Object -First 1).IPAddress

    Write-Host ""
    Write-Host "Probando resolucion DNS..."
    Write-Host ""

    # Probar sin www
    $resultado     = Resolve-DnsName -Name $dominio_elegido -Server $ip_servidor -ErrorAction SilentlyContinue
    $ip_obtenida   = ($resultado | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress

    if ($ip_obtenida -eq $ip_esperada) {
        Write-Host "nslookup $dominio_elegido -> $ip_obtenida OK"
    } else {
        Write-Host "nslookup $dominio_elegido -> FALLO (esperada: $ip_esperada, obtenida: $ip_obtenida)"
    }

    # Probar con www
    $resultado_www = Resolve-DnsName -Name "www.$dominio_elegido" -Server $ip_servidor -ErrorAction SilentlyContinue
    $ip_www        = ($resultado_www | Where-Object { $_.Type -eq "A" } | Select-Object -First 1).IPAddress

    if ($ip_www -eq $ip_esperada) {
        Write-Host "nslookup www.$dominio_elegido -> $ip_www OK"
    } else {
        Write-Host "nslookup www.$dominio_elegido -> FALLO (esperada: $ip_esperada, obtenida: $ip_www)"
    }

    Write-Host ""
    Write-Host "Probando ping..."
    Write-Host ""

    if (Test-Connection -ComputerName $dominio_elegido -Count 3 -Quiet) {
        Write-Host "ping $dominio_elegido -> OK"
    } else {
        Write-Host "ping $dominio_elegido -> FALLO"
        Write-Host "Nota: puede fallar si el host destino no responde ICMP"
    }

    if (Test-Connection -ComputerName "www.$dominio_elegido" -Count 3 -Quiet) {
        Write-Host "ping www.$dominio_elegido -> OK"
    } else {
        Write-Host "ping www.$dominio_elegido -> FALLO"
        Write-Host "Nota: puede fallar si el host destino no responde ICMP"
    }

    Write-Host ""
    Write-Host "Validacion completada"
}

# Muestra el estado actual del servicio DNS
function Get-EstadoDNS {
    Write-Host "Estado del servidor DNS"

    $servicio = Get-Service -Name "DNS" -ErrorAction SilentlyContinue

    if ($null -eq $servicio) {
        Write-Host "El servidor DNS no esta instalado"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    Write-Host "Servicio DNS: ENCONTRADO"
    Write-Host ""

    if ($servicio.Status -eq "Running") {
        Write-Host "Estado: ACTIVO"
    } else {
        Write-Host "Estado: INACTIVO"
    }

    Write-Host "Inicio automatico: $($servicio.StartType)"
    Write-Host ""
    Get-Service -Name "DNS" | Format-List Name, Status, StartType
}