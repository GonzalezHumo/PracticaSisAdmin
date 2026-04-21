# funciones_dhcp.ps1
# Funciones para la gestion del servidor DHCP (Windows Server)

. "$PSScriptRoot\funciones_comunes.ps1"

# Valida que ip_inicial sea menor que ip_final
function Test-Rango {
    param([string]$ip_inicial, [string]$ip_final)

    $o1 = $ip_inicial -split '\.'
    $o2 = $ip_final -split '\.'

    $num1 = ([int]$o1[0] * 16777216) + ([int]$o1[1] * 65536) + ([int]$o1[2] * 256) + [int]$o1[3]
    $num2 = ([int]$o2[0] * 16777216) + ([int]$o2[1] * 65536) + ([int]$o2[2] * 256) + [int]$o2[3]

    if ($num1 -ge $num2) {
        Write-Host "Error: la IP inicial debe ser menor que la IP final"
        Write-Host "   IP inicial: $ip_inicial"
        Write-Host "   IP final: $ip_final"
        return $false
    }

    return $true
}

# Valida que el gateway este en el mismo segmento y fuera del rango DHCP
function Test-Gateway {
    param([string]$gateway, [string]$ip_inicial, [string]$ip_final)

    $segmento_gateway = ($gateway -split '\.')[0..2] -join '.'
    $segmento_rango   = ($ip_inicial -split '\.')[0..2] -join '.'

    if ($segmento_gateway -ne $segmento_rango) {
        Write-Host "Error: el gateway debe estar en el mismo segmento de red"
        Write-Host "   Gateway: $gateway (segmento: $segmento_gateway.X)"
        Write-Host "   Rango: $segmento_rango.X"
        return $false
    }

    $octeto_gw  = [int]($gateway -split '\.')[-1]
    $octeto_ini = [int]($ip_inicial -split '\.')[-1]
    $octeto_fin = [int]($ip_final -split '\.')[-1]

    if ($octeto_gw -ge $octeto_ini -and $octeto_gw -le $octeto_fin) {
        Write-Host "Error: el gateway no debe estar dentro del rango DHCP"
        Write-Host "   Gateway: $gateway"
        Write-Host "   Rango DHCP: $ip_inicial - $ip_final"
        return $false
    }

    return $true
}

# Valida que dos IPs pertenezcan al mismo segmento
function Test-MismoSegmento {
    param([string]$ip1, [string]$ip2)

    $segmento1 = ($ip1 -split '\.')[0..2] -join '.'
    $segmento2 = ($ip2 -split '\.')[0..2] -join '.'

    if ($segmento1 -ne $segmento2) {
        Write-Host "Error: las IPs deben estar en el mismo segmento de red"
        Write-Host "   IP1: $ip1 (segmento: $segmento1.X)"
        Write-Host "   IP2: $ip2 (segmento: $segmento2.X)"
        return $false
    }

    return $true
}

# Calcula mascara, cidr y red base comparando los octetos de ambas IPs
function Get-Mascara {
    param([string]$ip1, [string]$ip2)

    $o1 = $ip1 -split '\.'
    $o2 = $ip2 -split '\.'

    if ($o1[0] -eq $o2[0] -and $o1[1] -eq $o2[1] -and $o1[2] -eq $o2[2]) {
        $script:mascara  = "255.255.255.0"
        $script:cidr     = "24"
        $script:red_base = "$($o1[0]).$($o1[1]).$($o1[2]).0"
    } elseif ($o1[0] -eq $o2[0] -and $o1[1] -eq $o2[1]) {
        $script:mascara  = "255.255.0.0"
        $script:cidr     = "16"
        $script:red_base = "$($o1[0]).$($o1[1]).0.0"
    } elseif ($o1[0] -eq $o2[0]) {
        $script:mascara  = "255.0.0.0"
        $script:cidr     = "8"
        $script:red_base = "$($o1[0]).0.0.0"
    } else {
        Write-Host "Error: las IPs no estan en la misma red"
        return $false
    }

    return $true
}

# Pide el nombre del scope al usuario
function Read-ScopeName {
    Write-Host ""
    $script:scope_name = Read-Host "Ingrese el nombre del scope"

    while ([string]::IsNullOrWhiteSpace($script:scope_name)) {
        Write-Host "El nombre del scope no puede estar vacio"
        $script:scope_name = Read-Host "Ingrese el nombre del scope"
    }

    Write-Host "Scope: $script:scope_name"
}

# Pide y valida el rango de IPs inicial y final
function Read-RangoIPs {
    Write-Host ""
    Write-Host "Configuracion de rango"

    while ($true) {
        $script:ip_inicial = Read-Host "Ingrese la IP inicial del rango"

        if ([string]::IsNullOrWhiteSpace($script:ip_inicial)) {
            Write-Host "La IP inicial no puede estar vacia"
            continue
        }

        if (-not (Test-IPCompleta $script:ip_inicial)) { continue }

        Write-Host "IP inicial: $script:ip_inicial"
        break
    }

    while ($true) {
        $script:ip_final = Read-Host "Ingrese la IP final del rango"

        if ([string]::IsNullOrWhiteSpace($script:ip_final)) {
            Write-Host "La IP final no puede estar vacia"
            continue
        }

        if (-not (Test-IPCompleta $script:ip_final)) { continue }
        if (-not (Test-MismoSegmento $script:ip_inicial $script:ip_final)) { continue }
        if (-not (Test-Rango $script:ip_inicial $script:ip_final)) { continue }

        Write-Host "IP final: $script:ip_final"
        break
    }
}

# Pide y valida el tiempo de concesion en segundos
function Read-LeaseTime {
    Write-Host ""
    Write-Host "Tiempo de concesion (lease time)"

    while ($true) {
        $valor = Read-Host "Ingrese el tiempo en segundos"

        if ([string]::IsNullOrWhiteSpace($valor)) {
            Write-Host "Error: el tiempo no puede estar vacio"
            continue
        }

        if ($valor -notmatch '^\d+$') {
            Write-Host "Error: debe ingresar un numero valido"
            continue
        }

        $script:lease_time = [int]$valor

        if ($script:lease_time -le 0) {
            Write-Host "Error: el tiempo debe ser mayor a 0"
            continue
        }

        Write-Host "Lease time: $script:lease_time segundos"
        break
    }
}

# Pide y valida el gateway (opcional)
function Read-Gateway {
    Write-Host ""
    Write-Host "Gateway (opcional)"

    while ($true) {
        $script:gateway = Read-Host "Ingrese la IP del gateway [Enter para omitir]"

        if ([string]::IsNullOrWhiteSpace($script:gateway)) {
            $script:gateway = ""
            break
        }

        if (-not (Test-IPCompleta $script:gateway)) { continue }
        if (-not (Test-Gateway $script:gateway $script:ip_inicial $script:ip_final)) { continue }

        Write-Host "Gateway: $script:gateway"
        break
    }
}

# Pide y valida hasta 2 servidores DNS (opcionales)
function Read-DNS {
    Write-Host ""
    Write-Host "Servidores DNS (opcionales, maximo 2)"

    while ($true) {
        $script:dns1 = Read-Host "Ingrese DNS primario [Enter para omitir]"

        if ([string]::IsNullOrWhiteSpace($script:dns1)) {
            $script:dns1 = ""
            $script:dns2 = ""
            Write-Host "Sin DNS configurado"
            break
        }

        if (-not (Test-IPCompleta $script:dns1)) { continue }

        Write-Host "DNS primario: $script:dns1"
        break
    }

    if (-not [string]::IsNullOrWhiteSpace($script:dns1)) {
        while ($true) {
            $script:dns2 = Read-Host "Ingrese DNS secundario [Enter para omitir]"

            if ([string]::IsNullOrWhiteSpace($script:dns2)) {
                $script:dns2 = ""
                break
            }

            if (-not (Test-IPCompleta $script:dns2)) { continue }

            if ($script:dns2 -eq $script:dns1) {
                Write-Host "Error: el DNS secundario debe ser diferente al primario"
                continue
            }

            Write-Host "DNS secundario: $script:dns2"
            break
        }
    }
}

# Verifica si el servidor DHCP esta instalado y ofrece reinstalarlo
function Test-DHCP {
    Write-Host "Verificando servidor DHCP..."

    $dhcp = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue

    if ($dhcp -and $dhcp.Installed) {
        Write-Host "El servidor DHCP esta instalado"
        Write-Host ""
        $respuesta = Read-Host "Desea reinstalarlo y eliminar la configuracion actual? (s/n)"

        if ($respuesta -ne "s" -and $respuesta -ne "S") {
            Write-Host "Reinstalacion cancelada"
            return
        }

        Write-Host "Procediendo con la reinstalacion..."
        Stop-Service -Name DHCPServer -Force -ErrorAction SilentlyContinue
        Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
        Uninstall-WindowsFeature -Name DHCP -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
        Write-Host "Desinstalacion completada"
    } else {
        Write-Host "El servidor DHCP no esta instalado"
    }
}

# Instala el rol DHCP si no esta presente
function Install-DHCP {
    Write-Host "Instalacion del servidor DHCP..."

    $dhcp = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue

    if ($dhcp -and $dhcp.Installed) {
        Write-Host "El servidor DHCP ya esta instalado"
        return
    }

    Write-Host "Instalando..."
    Install-WindowsFeature -Name DHCP -IncludeManagementTools | Out-Null

    $dhcp = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue

    if ($dhcp -and $dhcp.Installed) {
        Write-Host "Instalacion completada"
    } else {
        Write-Host "Error: instalacion fallida"
    }
}

# Crea o actualiza un scope DHCP con los datos ingresados por el usuario
function Set-Scope {
    Write-Host "Configurar o reconfigurar scope DHCP"

    $dhcp = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue
    if (-not $dhcp -or -not $dhcp.Installed) {
        Write-Host "Error: el servidor DHCP no esta instalado"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    Read-ScopeName
    Read-RangoIPs
    Read-LeaseTime
    Read-Gateway
    Read-DNS

    if (-not (Get-Mascara $script:ip_inicial $script:ip_final)) {
        Write-Host "Error al calcular la mascara de red"
        return
    }

    Write-Host ""
    Write-Host "Resumen de configuracion:"
    Write-Host "  Scope: $script:scope_name"
    Write-Host "  IP del servidor: $script:ip_inicial/$script:cidr"
    Write-Host "  Mascara: $script:mascara"
    Write-Host "  Red base: $script:red_base"
    Write-Host "  Rango DHCP: $script:ip_inicial - $script:ip_final"
    Write-Host "  Lease time: $script:lease_time segundos"

    if (-not [string]::IsNullOrWhiteSpace($script:gateway)) {
        Write-Host "  Gateway: $script:gateway"
    } else {
        Write-Host "  Gateway: (no configurado)"
    }

    if (-not [string]::IsNullOrWhiteSpace($script:dns1)) {
        Write-Host "  DNS primario: $script:dns1"
        if (-not [string]::IsNullOrWhiteSpace($script:dns2)) {
            Write-Host "  DNS secundario: $script:dns2"
        }
    } else {
        Write-Host "  DNS: (no configurado)"
    }

    Write-Host ""
    $confirmar = Read-Host "Desea aplicar esta configuracion? (s/n)"

    if ($confirmar -ne "s" -and $confirmar -ne "S") {
        Write-Host "Configuracion cancelada"
        return
    }

    Invoke-AplicarConfiguracion
}

# Aplica la configuracion al sistema (interfaz, scope, servicio)
# Funcion interna llamada desde Set-Scope
function Invoke-AplicarConfiguracion {
    Write-Host ""
    Write-Host "Aplicando configuracion..."

    try {
        # Configurar interfaz de red
        $adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" -and $_.Name -like "*Ethernet*2*" }
        if (-not $adapter) {
            $adapter = (Get-NetAdapter | Where-Object { $_.Status -eq "Up" })[1]
        }

        if (-not $adapter) {
            Write-Host "Error: no se encontro un adaptador de red valido"
            return
        }

        Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction SilentlyContinue
        Remove-NetIPAddress -InterfaceAlias $adapter.Name -AddressFamily IPv4 -Confirm:$false -ErrorAction SilentlyContinue
        New-NetIPAddress -InterfaceAlias $adapter.Name -IPAddress ([ipaddress]$script:ip_inicial) -PrefixLength $script:cidr -ErrorAction Stop | Out-Null

        Write-Host "Interfaz configurada: $script:ip_inicial/$script:cidr"

        # Calcular inicio del rango (ip_inicial + 1)
        $octetos      = $script:ip_inicial -split '\.'
        $rango_inicio = [ipaddress]("$($octetos[0..2] -join '.').$([int]$octetos[-1] + 1)")
        $scope_id     = [ipaddress]$script:red_base

        # Deshabilitar validacion de AD para ambientes sin dominio
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Services\DHCPServer\Parameters" -Name "DisableRogueDetection" -Value 1 -ErrorAction SilentlyContinue
        Restart-Service DHCPServer -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        $scope_existente = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object { $_.ScopeId -eq $scope_id }

        if ($scope_existente) {
            Set-DhcpServerv4Scope -ScopeId $scope_id -State Active -LeaseDuration (New-TimeSpan -Seconds $script:lease_time) -ErrorAction Stop
        } else {
            Add-DhcpServerv4Scope -Name $script:scope_name `
                -StartRange $rango_inicio `
                -EndRange ([ipaddress]$script:ip_final) `
                -SubnetMask $script:mascara `
                -State Active `
                -LeaseDuration (New-TimeSpan -Seconds $script:lease_time) `
                -ErrorAction Stop
        }

        # Configurar DNS del scope
        if (-not [string]::IsNullOrWhiteSpace($script:dns1) -and -not [string]::IsNullOrWhiteSpace($script:dns2)) {
            Set-DhcpServerv4OptionValue -ScopeId $scope_id -DnsServer ([ipaddress]$script:dns1), ([ipaddress]$script:dns2) -Force -ErrorAction Stop
        } elseif (-not [string]::IsNullOrWhiteSpace($script:dns1)) {
            Set-DhcpServerv4OptionValue -ScopeId $scope_id -DnsServer ([ipaddress]$script:dns1) -Force -ErrorAction Stop
        } else {
            Set-DhcpServerv4OptionValue -ScopeId $scope_id -DnsServer ([ipaddress]$script:ip_inicial) -Force -ErrorAction Stop
        }

        # Desactivar otros scopes
        Get-DhcpServerv4Scope -ErrorAction SilentlyContinue | Where-Object {
            $_.ScopeId -ne $scope_id -and $_.State -eq 'Active'
        } | ForEach-Object {
            Set-DhcpServerv4Scope -ScopeId $_.ScopeId -State Inactive -ErrorAction SilentlyContinue
            Write-Host "Scope desactivado: $($_.ScopeId)"
        }

        Start-Sleep -Seconds 3
        $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

        if ($service -and $service.Status -eq 'Running') {
            Write-Host ""
            Write-Host "Configuracion aplicada exitosamente"
            Write-Host "  Interfaz: $($adapter.Name)"
            Write-Host "  IP del servidor: $script:ip_inicial/$script:cidr"
            Write-Host "  Rango DHCP: $($rango_inicio.IPAddressToString) - $script:ip_final"
            Write-Host "  Mascara: $script:mascara"
        } else {
            Write-Host "Error: el servicio DHCP no inicio"
        }
    } catch {
        Write-Host "Error: $($_.Exception.Message)"
    }
}

# Lista todos los scopes configurados con su estado
function Get-Scopes {
    Write-Host "Scopes configurados"

    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue
    if (-not $service) {
        Write-Host "El servidor DHCP no esta instalado"
        return
    }

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes -or $scopes.Count -eq 0) {
        Write-Host "No hay scopes configurados"
        Write-Host "Use la opcion 3 para agregar uno"
        return
    }

    Write-Host ""
    $contador = 1
    foreach ($scope in $scopes) {
        Write-Host "  $contador) $($scope.Name) - $($scope.ScopeId) [$($scope.State)]"
        $contador++
    }
}

# Activa o desactiva un scope seleccionado por el usuario
function Switch-Scope {
    Write-Host "Activar o desactivar scope"

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes -or $scopes.Count -eq 0) {
        Write-Host "No hay scopes configurados"
        return
    }

    Write-Host ""
    $lista  = @()
    $contador = 1
    foreach ($scope in $scopes) {
        Write-Host "  $contador) $($scope.Name) - $($scope.ScopeId) [$($scope.State)]"
        $lista += $scope
        $contador++
    }

    Write-Host ""
    $sel = Read-Host "Seleccione el numero del scope"

    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $lista.Count) {
        Write-Host "Seleccion invalida"
        return
    }

    $scope_elegido = $lista[[int]$sel - 1]

    if ($scope_elegido.State -eq 'Active') {
        Set-DhcpServerv4Scope -ScopeId $scope_elegido.ScopeId -State Inactive
        Write-Host "Scope desactivado: $($scope_elegido.Name)"
    } else {
        # Al activar uno, desactiva los demas
        Get-DhcpServerv4Scope | Where-Object { $_.State -eq 'Active' } | ForEach-Object {
            Set-DhcpServerv4Scope -ScopeId $_.ScopeId -State Inactive
        }
        Set-DhcpServerv4Scope -ScopeId $scope_elegido.ScopeId -State Active
        Write-Host "Scope activado: $($scope_elegido.Name)"
    }
}

# Elimina un scope seleccionado por el usuario
function Remove-Scope {
    Write-Host "Eliminar scope"

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes -or $scopes.Count -eq 0) {
        Write-Host "No hay scopes configurados"
        return
    }

    Write-Host ""
    $lista    = @()
    $contador = 1
    foreach ($scope in $scopes) {
        Write-Host "  $contador) $($scope.Name) - $($scope.ScopeId)"
        $lista += $scope
        $contador++
    }

    Write-Host ""
    $sel = Read-Host "Seleccione el numero del scope a eliminar"

    if ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $lista.Count) {
        Write-Host "Seleccion invalida"
        return
    }

    $scope_elegido = $lista[[int]$sel - 1]

    $confirmar = Read-Host "Desea eliminar el scope '$($scope_elegido.Name)'? (s/n)"

    if ($confirmar -ne "s" -and $confirmar -ne "S") {
        Write-Host "Operacion cancelada"
        return
    }

    Remove-DhcpServerv4Scope -ScopeId $scope_elegido.ScopeId -Force
    Write-Host "Scope eliminado: $($scope_elegido.Name)"
}

# Muestra las concesiones activas del servidor DHCP
function Get-Concesiones {
    Write-Host "Concesiones activas"

    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

    if (-not $service -or $service.Status -ne 'Running') {
        Write-Host "Error: el servicio DHCP no esta activo"
        return
    }

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if (-not $scopes -or $scopes.Count -eq 0) {
        Write-Host "No hay concesiones activas"
        return
    }

    Write-Host ""
    $total = 0

    foreach ($scope in $scopes) {
        $leases = Get-DhcpServerv4Lease -ScopeId $scope.ScopeId -ErrorAction SilentlyContinue
        foreach ($lease in $leases) {
            Write-Host "  IP asignada: $($lease.IPAddress)"
            $total++
        }
    }

    Write-Host ""
    Write-Host "Total de concesiones: $total"
}

# Muestra el estado actual del servicio DHCP
function Get-EstadoDHCP {
    Write-Host "Estado del servidor DHCP"

    $dhcp = Get-WindowsFeature -Name DHCP -ErrorAction SilentlyContinue

    if (-not $dhcp -or -not $dhcp.Installed) {
        Write-Host "El servidor DHCP no esta instalado"
        Write-Host "Use la opcion 2 para instalarlo"
        return
    }

    Write-Host "Rol DHCP: INSTALADO"
    Write-Host ""

    $service = Get-Service -Name DHCPServer -ErrorAction SilentlyContinue

    if ($service -and $service.Status -eq 'Running') {
        Write-Host "Estado: ACTIVO"
    } else {
        Write-Host "Estado: INACTIVO"
    }

    if ($service -and $service.StartType -eq 'Automatic') {
        Write-Host "Inicio automatico: HABILITADO"
    } else {
        Write-Host "Inicio automatico: DESHABILITADO"
    }

    Write-Host ""
    if ($service) {
        $service | Format-List Name, Status, StartType
    }
}

# Variables globales del modulo
$script:scope_name = ""
$script:ip_inicial = ""
$script:ip_final   = ""
$script:lease_time = 0
$script:gateway    = ""
$script:dns1       = ""
$script:dns2       = ""
$script:mascara    = ""
$script:cidr       = ""
$script:red_base   = ""