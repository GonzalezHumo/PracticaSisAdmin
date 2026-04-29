# ============================================================
#  http_functions.ps1  -  Practica 6 - Administracion de Sistemas
#  Funciones para aprovisionamiento de servidores web en Windows
# ============================================================

# ── Utilidades generales ─────────────────────────────────────

function Mostrar-Banner {
    Clear-Host
    Write-Host "-----------------------------------------------------" -ForegroundColor Cyan
    Write-Host " Despliegue Dinamico de Servicios HTTP Multi-Version " -ForegroundColor Cyan
    Write-Host "-----------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

function Validar-Puerto {
    param([string]$Puerto)
    $reservados = @(
        20, 21,       # FTP
        22,           # SSH
        23,           # Telnet
        25, 587,      # SMTP
        53,           # DNS
        67, 68,       # DHCP
        110, 995,     # POP3
        143, 993,     # IMAP
        443,          # HTTPS
        445,          # SMB
        3306,         # MySQL
        3389,         # RDP
        5985, 5986,   # WinRM
        27017         # MongoDB
    )
    if ($Puerto -notmatch '^\d+$') { return $false }
    $p = [int]$Puerto
    if ($p -lt 1 -or $p -gt 65535) { return $false }
    if ($reservados -contains $p) {
        Write-Host "[!] Puerto $p reservado para otro servicio." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Puerto-EnUso {
    param([int]$Puerto)
    $resultado = Test-NetConnection -ComputerName localhost -Port $Puerto -WarningAction SilentlyContinue
    return $resultado.TcpTestSucceeded
}

function Pedir-Puerto {
    do {
        $puerto = Read-Host "Ingresa el puerto de escucha (ej. 80, 8080, 8888)"
        $puerto = $puerto.Trim()
        if (-not (Validar-Puerto $puerto)) {
            Write-Host "[!] Puerto invalido. Intenta de nuevo." -ForegroundColor Red
            continue
        }
        if (Puerto-EnUso ([int]$puerto)) {
            Write-Host "[!] El puerto $puerto ya esta en uso." -ForegroundColor Red
            continue
        }
        break
    } while ($true)
    return [int]$puerto
}

function Verificar-Chocolatey {
    # Siempre recargar PATH para que choco este disponible en la sesion actual
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Host "[*] Instalando Chocolatey..." -ForegroundColor Yellow
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    }
}

function Configurar-Firewall {
    param([int]$Puerto, [string]$Nombre)
    $regla = Get-NetFirewallRule -DisplayName "HTTP-$Nombre-$Puerto" -ErrorAction SilentlyContinue
    if (-not $regla) {
        New-NetFirewallRule -DisplayName "HTTP-$Nombre-$Puerto" `
            -Direction Inbound -Protocol TCP -LocalPort $Puerto `
            -Action Allow | Out-Null
        Write-Host "[+] Firewall: puerto $Puerto abierto." -ForegroundColor Green
    }
    if ($Puerto -ne 80) {
        $regla80 = Get-NetFirewallRule -DisplayName "HTTP-Default-80" -ErrorAction SilentlyContinue
        if ($regla80) {
            Remove-NetFirewallRule -DisplayName "HTTP-Default-80" | Out-Null
            Write-Host "[+] Firewall: puerto 80 cerrado." -ForegroundColor Green
        }
    }
}

function Crear-IndexHtml {
    param([string]$Ruta, [string]$Servicio, [string]$Version, [int]$Puerto, [string]$Webroot, [string]$Usuario)
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm"
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>$Servicio</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: Arial, sans-serif;
      min-height: 100vh;
      background: linear-gradient(135deg, #ffb6c1, #ff69b4, #ffcdd2, #f48fb1);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .card {
      background: rgba(255,255,255,0.88);
      border-radius: 16px;
      padding: 50px 60px;
      max-width: 600px;
      width: 90%;
      box-shadow: 0 8px 32px rgba(255,105,180,0.3);
    }
    h1 { font-size: 2rem; color: #2c3e50; margin-bottom: 8px; }
    .subtitle { color: #888; margin-bottom: 30px; font-size: 0.95rem; }
    hr { border: none; border-top: 2px solid #f48fb1; margin-bottom: 30px; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 10px 8px; font-size: 0.97rem; color: #333; }
    td:first-child { font-weight: bold; color: #c2185b; width: 110px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>$Servicio</h1>
    <p class="subtitle">Despliegue exitoso &mdash; Windows Server 2022</p>
    <hr>
    <table>
      <tr><td>Version</td><td>$Version</td></tr>
      <tr><td>Puerto</td><td>$($Puerto)/tcp</td></tr>
      <tr><td>Webroot</td><td>$Webroot</td></tr>
      <tr><td>Usuario</td><td>$Usuario</td></tr>
      <tr><td>Fecha</td><td>$fecha</td></tr>
    </table>
  </div>
</body>
</html>
"@
    Set-Content -Path $Ruta -Value $html -Encoding UTF8
    Write-Host "[+] index.html creado en $Ruta" -ForegroundColor Green
}

# ── IIS ──────────────────────────────────────────────────────

function Obtener-VersionIIS {
    $build = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue)
    if ($build) {
        return @("$($build.MajorVersion).$($build.MinorVersion) (Instalada)", "LTS-Sistema")
    }
    return @("10.0 (Win Server 2022 - LTS)", "10.0-dev (Latest)")
}

function Instalar-IIS {
    param([int]$Puerto)
    Write-Host "[*] Instalando IIS..." -ForegroundColor Yellow

    Install-WindowsFeature -Name Web-Server -IncludeManagementTools | Out-Null
    Install-WindowsFeature -Name Web-Static-Content, Web-Default-Doc, Web-Http-Errors | Out-Null
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $sitio = "Default Web Site"
    $binding = Get-WebBinding -Name $sitio -Protocol http
    if ($binding) { Remove-WebBinding -Name $sitio -Protocol http }
    New-WebBinding -Name $sitio -Protocol http -Port $Puerto -IPAddress "*" | Out-Null
    Write-Host "[+] IIS configurado en puerto $Puerto" -ForegroundColor Green

    Set-WebConfigurationProperty -Filter "system.webServer/security/requestFiltering" `
        -Name "removeServerHeader" -Value $true -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Remove-WebConfigurationProperty -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." -AtElement @{name="X-Powered-By"} -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." -Value @{name="X-Frame-Options";value="SAMEORIGIN"} -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "system.webServer/httpProtocol/customHeaders" `
        -Name "." -Value @{name="X-Content-Type-Options";value="nosniff"} -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -Value @{verb="TRACE";allowed="false"} -PSPath "IIS:\" -ErrorAction SilentlyContinue
    Add-WebConfigurationProperty -Filter "system.webServer/security/requestFiltering/verbs" `
        -Name "." -Value @{verb="DELETE";allowed="false"} -PSPath "IIS:\" -ErrorAction SilentlyContinue

    $wwwPath = "C:\inetpub\wwwroot"
    $acl = Get-Acl $wwwPath
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("IUSR","ReadAndExecute","Allow")
    $acl.SetAccessRule($rule)
    Set-Acl $wwwPath $acl | Out-Null

    $version = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue)
    $ver = if ($version) { "Version $($version.MajorVersion).$($version.MinorVersion)" } else { "Version 10.0" }
    Crear-IndexHtml -Ruta "$wwwPath\index.html" -Servicio "IIS (Internet Information Services)" -Version $ver -Puerto $Puerto -Webroot $wwwPath -Usuario "IUSR"

    Configurar-Firewall -Puerto $Puerto -Nombre "IIS"
    Start-Service W3SVC | Out-Null
    Write-Host "[+] IIS instalado y corriendo en puerto $Puerto" -ForegroundColor Green
}

# ── Apache (Win64) ───────────────────────────────────────────

function Obtener-VersionesApache {
    Write-Host "[*] Consultando versiones de Apache disponibles..." -ForegroundColor Yellow
    Verificar-Chocolatey
    $output = choco info apache-httpd --all 2>$null | Select-String "apache-httpd\s+\d+\.\d+"
    $versiones = @()
    foreach ($linea in $output) {
        $v = ($linea.ToString().Trim() -split "\s+")[1]
        if ($v -match '^\d+\.\d+') { $versiones += $v }
    }
    if ($versiones.Count -eq 0) {
        $versiones = @("2.4.62 (LTS-Estable)", "2.5.1 (Latest-Desarrollo)")
    } else {
        $versiones = @("$($versiones[0]) (LTS-Estable)", "$($versiones[-1]) (Latest-Desarrollo)")
    }
    return $versiones
}

function Instalar-Apache {
    param([string]$Version, [int]$Puerto)
    Write-Host "[*] Instalando Apache $Version..." -ForegroundColor Yellow
    Verificar-Chocolatey

    # Instalar Apache via Chocolatey con ruta y puerto correctos
    if ($Version -match "LTS") {
        choco install apache-httpd -y --no-progress --params "/installLocation:C:\Apache24 /Port:$Puerto" --force 2>&1 | Out-Null
    } else {
        choco install apache-httpd -y --no-progress --pre --params "/installLocation:C:\Apache24 /Port:$Puerto" --force 2>&1 | Out-Null
    }

    # Detectar ruta real (Chocolatey instala en C:\Apache24\Apache24)
    $apacheBase = "C:\Apache24\Apache24"
    if (-not (Test-Path $apacheBase)) { $apacheBase = "C:\Apache24" }
    $conf = "$apacheBase\conf\httpd.conf"

    if (Test-Path $conf) {
        # Habilitar mod_headers (necesario para Header always set)
        (Get-Content $conf) -replace '#LoadModule headers_module', 'LoadModule headers_module' | Set-Content $conf

        # Cambiar puerto
        (Get-Content $conf) -replace 'Listen 80', "Listen $Puerto" | Set-Content $conf

        # Comentar Listen 443 en httpd.conf y todos los archivos extra
        Get-ChildItem "$apacheBase\conf" -Recurse -Filter "*.conf" | ForEach-Object {
            $c = Get-Content $_.FullName -Raw
            if ($c -match "^Listen 443") {
                $c -replace "(?m)^Listen 443", "#Listen 443" | Set-Content $_.FullName
            }
        }
        Write-Host "[+] Apache configurado en puerto $Puerto" -ForegroundColor Green

        # Ocultar version
        $secConf = "$apacheBase\conf\extra\httpd-security.conf"
        if (-not (Test-Path $secConf)) { New-Item $secConf -Force | Out-Null }
        Add-Content $secConf "`nServerTokens Prod`nServerSignature Off"

        # Encabezados de seguridad y metodos
        Add-Content $conf "`nHeader always set X-Frame-Options SAMEORIGIN"
        Add-Content $conf "Header always set X-Content-Type-Options nosniff"
        Add-Content $conf "`nTraceEnable Off"

        # Permisos
        $wwwPath = "$apacheBase\htdocs"
        $acl = Get-Acl $wwwPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("NETWORK SERVICE","ReadAndExecute","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $wwwPath $acl | Out-Null

        # Crear index.html
        $ver = ($Version -split " ")[0]
        Crear-IndexHtml -Ruta "$wwwPath\index.html" -Servicio "Apache HTTP Server" -Version "Version $ver" -Puerto $Puerto -Webroot $wwwPath -Usuario "NETWORK SERVICE"
    }

    # Registrar e iniciar servicio
    & "$apacheBase\bin\httpd.exe" -k install 2>&1 | Out-Null
    Start-Service Apache -ErrorAction SilentlyContinue
    if ((Get-Service Apache -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Host "[+] Apache corriendo en puerto $Puerto" -ForegroundColor Green
    }

    Configurar-Firewall -Puerto $Puerto -Nombre "Apache"
}

# ── Nginx (Windows) ──────────────────────────────────────────

function Obtener-VersionesNginx {
    Write-Host "[*] Consultando versiones de Nginx disponibles..." -ForegroundColor Yellow
    Verificar-Chocolatey
    $output = choco info nginx --all 2>$null | Select-String "nginx\s+\d+\.\d+"
    $versiones = @()
    foreach ($linea in $output) {
        $v = ($linea.ToString().Trim() -split "\s+")[1]
        if ($v -match '^\d+\.\d+') { $versiones += $v }
    }
    if ($versiones.Count -eq 0) {
        $versiones = @("1.26.2 (LTS-Estable)", "1.27.3 (Latest-Desarrollo)")
    } else {
        $versiones = @("$($versiones[0]) (LTS-Estable)", "$($versiones[-1]) (Latest-Desarrollo)")
    }
    return $versiones
}

function Instalar-Nginx {
    param([string]$Version, [int]$Puerto)
    Write-Host "[*] Instalando Nginx $Version..." -ForegroundColor Yellow
    Verificar-Chocolatey

    if ($Version -match "LTS") {
        choco install nginx -y --no-progress 2>&1 | Out-Null
    } else {
        choco install nginx -y --no-progress --pre 2>&1 | Out-Null
    }

    # Detectar ruta real dinamicamente
    $nginxBase = (Get-ChildItem "C:\tools" -Filter "nginx*" -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1).FullName
    if (-not $nginxBase) {
        $nginxBase = (Get-ChildItem "C:\ProgramData\chocolatey\lib\nginx" -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue | Select-Object -First 1).DirectoryName
    }
    if (-not $nginxBase) { Write-Host "[!] No se encontro directorio de Nginx." -ForegroundColor Red; return }

    $conf = "$nginxBase\conf\nginx.conf"

    if (Test-Path $conf) {
        # Cambiar puerto
        (Get-Content $conf) -replace "listen\s+\d+;", "listen $Puerto;" | Set-Content $conf

        # Ocultar version
        $contenido = Get-Content $conf -Raw
        if ($contenido -notmatch "server_tokens off") {
            (Get-Content $conf) -replace "http \{", "http {`n    server_tokens off;" | Set-Content $conf
        }

        # Encabezados de seguridad
        $serverBlock = @'

    add_header X-Frame-Options SAMEORIGIN;
    add_header X-Content-Type-Options nosniff;

    # Bloquear metodos peligrosos
    if ($request_method ~ ^(TRACE|DELETE|TRACK)$) {
        return 405;
    }
'@
        (Get-Content $conf -Raw) -replace "http \{", "http {$serverBlock" | Set-Content $conf
        Write-Host "[+] Nginx configurado en puerto $Puerto" -ForegroundColor Green

        # Permisos
        $wwwPath = "$nginxBase\html"
        $acl = Get-Acl $wwwPath
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("NETWORK SERVICE","ReadAndExecute","Allow")
        $acl.SetAccessRule($rule)
        Set-Acl $wwwPath $acl | Out-Null

        # Crear index.html
        $ver = ($Version -split " ")[0]
        Crear-IndexHtml -Ruta "$wwwPath\index.html" -Servicio "Nginx for Windows" -Version "Version $ver" -Puerto $Puerto -Webroot $wwwPath -Usuario "NETWORK SERVICE"
    }

    # Instalar y arrancar como servicio
    $nssm = Get-Command nssm -ErrorAction SilentlyContinue
    if (-not $nssm) { choco install nssm -y --no-progress | Out-Null }
    Stop-Service Nginx -ErrorAction SilentlyContinue
    nssm remove Nginx confirm 2>&1 | Out-Null
    nssm install Nginx "$nginxBase\nginx.exe" 2>&1 | Out-Null
    nssm set Nginx AppDirectory "$nginxBase" 2>&1 | Out-Null
    Start-Service Nginx -ErrorAction SilentlyContinue
    if ((Get-Service Nginx -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Host "[+] Nginx corriendo en puerto $Puerto" -ForegroundColor Green
    }

    Configurar-Firewall -Puerto $Puerto -Nombre "Nginx"
}

# ── Menu de seleccion de version ─────────────────────────────

function Seleccionar-Version {
    param([string[]]$Versiones, [string]$Servidor)
    Write-Host ""
    Write-Host "Versiones disponibles para $($Servidor):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Versiones.Count; $i++) {
        Write-Host "  [$($i+1)] $($Versiones[$i])"
    }
    do {
        $sel = Read-Host "Selecciona una version (1-$($Versiones.Count))"
        $sel = $sel.Trim()
    } while ($sel -notmatch '^\d+$' -or [int]$sel -lt 1 -or [int]$sel -gt $Versiones.Count)
    return $Versiones[[int]$sel - 1]
}

# ── Menu principal ───────────────────────────────────────────

function Mostrar-Menu {
    Write-Host "Selecciona el servidor web a instalar:" -ForegroundColor Cyan
    Write-Host "  [1] IIS (Internet Information Services)"
    Write-Host "  [2] Apache para Windows (Win64)"
    Write-Host "  [3] Nginx para Windows"
    Write-Host "  [4] Salir"
    Write-Host ""
    do {
        $op = Read-Host "Opcion"
        $op = $op.Trim()
    } while ($op -notmatch '^[1-4]$')
    return $op
}