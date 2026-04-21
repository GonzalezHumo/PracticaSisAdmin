# funciones_http.ps1 - Funciones HTTP: IIS, Apache Win64, Nginx para Windows

# Variables globales
$Global:LogFile        = "C:\http_provision\provision.log"
$Global:ServicioActual = $null

# Puertos reservados que NO se permiten
$Global:PuertosReservados = @(21, 22, 25, 53, 110, 143, 443, 3306, 3389, 5432, 8443)

# Rutas de instalacion
$Global:RutaApache = "C:\Apache24"
$Global:RutaNginx  = "C:\tools\nginx"   # CORRECCION: choco instala nginx en C:\tools\nginx
$Global:RutaIIS    = "C:\inetpub\wwwroot"

# ─────────────────────────────────────────
# UTILIDADES DE LOG Y PRESENTACION
# ─────────────────────────────────────────

function Write-Log {
    param([string]$Nivel, [string]$Mensaje)
    $ts    = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $linea = "[$ts] [$Nivel] $Mensaje"
    New-Item -ItemType Directory -Path "C:\http_provision" -Force | Out-Null
    Add-Content -Path $Global:LogFile -Value $linea -ErrorAction SilentlyContinue
}

function Write-OK   { param([string]$m) Write-Host "[OK]   $m" -ForegroundColor Green;  Write-Log "OK"    $m }
function Write-Err  { param([string]$m) Write-Host "[ERR]  $m" -ForegroundColor Red;    Write-Log "ERROR" $m }
function Write-Info { param([string]$m) Write-Host "[INFO] $m" -ForegroundColor Cyan;   Write-Log "INFO"  $m }
function Write-Warn { param([string]$m) Write-Host "[WARN] $m" -ForegroundColor Yellow; Write-Log "WARN"  $m }

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host "|    PRACTICA 6 - Aprovisionamiento Web Automatizado       |" -ForegroundColor Cyan
    Write-Host "|         Sistema Windows Server 2019 Core                 |" -ForegroundColor Cyan
    Write-Host "+==========================================================+" -ForegroundColor Cyan
    Write-Host ""
    New-Item -ItemType Directory -Path "C:\http_provision" -Force | Out-Null
}

# ─────────────────────────────────────────
# VALIDACIONES
# ─────────────────────────────────────────

function Test-EntradaValida {
    param([string]$Valor, [string]$Campo)
    if ([string]::IsNullOrWhiteSpace($Valor)) {
        Write-Err "El campo '$Campo' no puede estar vacio."
        return $false
    }
    if ($Valor -match '[;<>&|`$"''\\]') {
        Write-Err "El campo '$Campo' contiene caracteres no permitidos."
        return $false
    }
    return $true
}

function Test-Puerto {
    param([string]$Puerto)

    if ($Puerto -notmatch '^\d+$') {
        Write-Err "El puerto debe ser un numero entero."
        return $false
    }

    $p = [int]$Puerto

    if ($p -lt 1 -or $p -gt 65535) {
        Write-Err "El puerto debe estar entre 1 y 65535."
        return $false
    }

    if ($Global:PuertosReservados -contains $p) {
        Write-Err "El puerto $p esta reservado para otro servicio del sistema."
        return $false
    }

    $enUso = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
    if ($enUso) {
        $procesoPid = $enUso[0].OwningProcess
        $proceso    = (Get-Process -Id $procesoPid -ErrorAction SilentlyContinue).Name
        Write-Err "El puerto $p ya esta en uso por: $proceso (PID $procesoPid)."
        Write-Err "Elija un puerto diferente."
        return $false
    }

    return $true
}

function Get-PuertoUsuario {
    while ($true) {
        Write-Host ""
        Write-Host "Ingrese el puerto de escucha (ej: 80, 8080, 8888): " -ForegroundColor White -NoNewline
        $puerto = Read-Host
        if (-not (Test-EntradaValida -Valor $puerto -Campo "Puerto")) { continue }
        if (Test-Puerto -Puerto $puerto) { return [int]$puerto }
        Write-Warn "Intente con un puerto diferente."
    }
}

# ─────────────────────────────────────────
# CHOCOLATEY
# ─────────────────────────────────────────

function Install-Chocolatey {
    if (Get-Command choco -ErrorAction SilentlyContinue) {
        Write-OK "Chocolatey ya esta instalado."
        return
    }

    Write-Info "Instalando Chocolatey..."
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

    try {
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                    [System.Environment]::GetEnvironmentVariable("Path","User")

        $chocoPath = "C:\ProgramData\chocolatey\bin"
        if ($env:Path -notlike "*$chocoPath*") { $env:Path += ";$chocoPath" }

        if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
            Write-Err "choco no responde tras la instalacion. Reinicie la sesion SSH y vuelva a ejecutar."
            exit 1
        }
        Write-OK "Chocolatey instalado correctamente."
    } catch {
        Write-Err "No se pudo instalar Chocolatey: $_"
        exit 1
    }
}

# ─────────────────────────────────────────
# FIREWALL
# ─────────────────────────────────────────

function Set-Firewall {
    param([int]$Puerto)

    Write-Info "Configurando Windows Firewall..."

    # Abrir el puerto elegido (sin bloquear otros, varios servidores pueden coexistir)
    New-NetFirewallRule -DisplayName "HTTP-Practica6-$Puerto" `
        -Direction Inbound -Protocol TCP -LocalPort $Puerto `
        -Action Allow -ErrorAction SilentlyContinue | Out-Null

    Write-OK "Puerto $Puerto/TCP habilitado en el Firewall."
    Write-Log "INFO" "Firewall: puerto $Puerto abierto."
}

# ─────────────────────────────────────────
# PAGINA INDEX.HTML PERSONALIZADA
# ─────────────────────────────────────────

function New-IndexHtml {
    param(
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto,
        [string]$WebRoot
    )

    New-Item -ItemType Directory -Path $WebRoot -Force | Out-Null

    $fecha     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $contenido = @"
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>$Servicio - Practica 6</title>
    <style>
        * { margin:0; padding:0; box-sizing:border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, sans-serif;
            background: linear-gradient(135deg,#1a1a2e 0%,#16213e 50%,#0f3460 100%);
            color: #e0e0e0;
            display: flex; justify-content: center; align-items: center; min-height: 100vh;
        }
        .card {
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 20px; padding: 50px; text-align: center; max-width: 600px; width: 90%;
        }
        h1 { font-size:2rem; color:#4fc3f7; margin-bottom:20px; }
        .badge {
            display:inline-block; background:rgba(79,195,247,0.15);
            border:1px solid #4fc3f7; border-radius:50px; padding:10px 24px; margin:8px;
        }
        .label { color:#90caf9; font-size:0.8rem; }
        .value { color:#ffffff; font-weight:bold; font-size:1.1rem; }
        footer { margin-top:30px; color:#546e7a; font-size:0.8rem; }
    </style>
</head>
<body>
<div class="card">
    <h1>$Servicio</h1>
    <p style="color:#90caf9;margin-bottom:25px;">Servidor HTTP desplegado exitosamente</p>
    <div class="badge"><div class="label">SERVIDOR</div><div class="value">$Servicio</div></div>
    <div class="badge"><div class="label">VERSION</div><div class="value">$Version</div></div>
    <div class="badge"><div class="label">PUERTO</div><div class="value">:$Puerto</div></div>
    <footer>
        <p>Practica 6 - Aprovisionamiento Web Automatizado</p>
        <p>Desplegado: $fecha</p>
    </footer>
</div>
</body>
</html>
"@

    Set-Content -Path "$WebRoot\index.html" -Value $contenido -Encoding UTF8
    Write-OK "Pagina index.html creada en $WebRoot."
}

# ─────────────────────────────────────────
# DESINSTALACION - garantiza un solo servidor activo
# ─────────────────────────────────────────

function Remove-ServidoresAnteriores {
    Write-Info "Deteniendo y removiendo servidores HTTP previos..."

    # IIS
    $iis = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($iis -and $iis.Installed) {
        Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
        Uninstall-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue | Out-Null
        Write-Info "IIS desinstalado."
    }

    # Apache
    $apacheSvc = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    if ($apacheSvc) {
        Stop-Service "Apache2.4" -Force -ErrorAction SilentlyContinue
        if (Test-Path "$Global:RutaApache\bin\httpd.exe") {
            & "$Global:RutaApache\bin\httpd.exe" -k uninstall 2>$null
        }
        Write-Info "Apache desinstalado."
    }

    # Nginx
    $nginxSvc = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($nginxSvc) {
        Stop-Service "nginx" -Force -ErrorAction SilentlyContinue
        if (Get-Command nssm -ErrorAction SilentlyContinue) {
            & nssm remove nginx confirm 2>$null
        }
        Write-Info "Nginx desinstalado."
    }
}

# ─────────────────────────────────────────
# IIS
# ─────────────────────────────────────────

function Install-IIS {
    Write-Info "=== Instalacion de IIS ==="

    Write-Host ""
    Write-Host "Versiones disponibles de IIS en Windows Server 2019:" -ForegroundColor White
    Write-Host "  [1] IIS 10.0 (Estable / Incluido en Windows Server 2019)" -ForegroundColor Gray
    Write-Host "  [2] IIS 10.0 con caracteristicas adicionales (WebSockets, HTTP/2)" -ForegroundColor Gray
    Write-Host ""

    $seleccion = ""
    while ($seleccion -notmatch '^[12]$') {
        Write-Host "Seleccione version [1-2]: " -ForegroundColor White -NoNewline
        $seleccion = Read-Host
        if ($seleccion -notmatch '^[12]$') { Write-Err "Seleccion invalida. Ingrese 1 o 2." }
    }

    $puerto = Get-PuertoUsuario

    Write-Info "Instalando IIS en silencio..."

    $features = @(
        "Web-Server","Web-Common-Http","Web-Default-Doc","Web-Static-Content",
        "Web-Http-Errors","Web-Http-Logging","Web-Security","Web-Filtering",
        "Web-Performance","Web-Stat-Compression","Web-Mgmt-Tools"
    )

    if ($seleccion -eq "2") { $features += @("Web-WebSockets","Web-Http-Redirect") }

    Install-WindowsFeature -Name $features -IncludeManagementTools | Out-Null
    Write-OK "IIS instalado correctamente."

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    Set-PuertoIIS      -Puerto $puerto
    Set-SeguridadIIS
    Set-MetodosHttpIIS

    $version = "10.0 (Windows Server 2019)"
    New-IndexHtml -Servicio "IIS" -Version $version -Puerto $puerto -WebRoot $Global:RutaIIS

    Set-Firewall -Puerto $puerto

    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Set-Service   -Name W3SVC -StartupType Automatic

    Write-OK "IIS activo en el puerto $puerto."
    Show-VerificacionHTTP -Puerto $puerto
}

function Set-PuertoIIS {
    param([int]$Puerto)
    Write-Info "Configurando puerto $Puerto en IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Remove-WebBinding -Name "Default Web Site" -ErrorAction SilentlyContinue
    New-WebBinding    -Name "Default Web Site" -Protocol "http" -Port $Puerto -IPAddress "*"
    Write-OK "Puerto $Puerto configurado en IIS."
}

function Set-SeguridadIIS {
    Write-Info "Aplicando seguridad en IIS (ocultando version del servidor)..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Eliminar X-Powered-By si existe
    $xpb = Get-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -ErrorAction SilentlyContinue |
        Where-Object { $_.name -eq "X-Powered-By" }
    if ($xpb) {
        Remove-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
    }

    # Ocultar version del servidor
    Set-WebConfigurationProperty -PSPath "IIS:\" `
        -Filter "system.webServer/security/requestFiltering" `
        -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue

    # Encabezados de seguridad
    $headers = @(
        @{ name="X-Frame-Options";        value="SAMEORIGIN"     },
        @{ name="X-Content-Type-Options"; value="nosniff"        },
        @{ name="X-XSS-Protection";       value="1; mode=block"  }
    )

    foreach ($h in $headers) {
        # Evitar duplicados: eliminar si ya existe, luego agregar
        $existe = Get-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" -Name "." -ErrorAction SilentlyContinue |
            Where-Object { $_.name -eq $h.name }
        if ($existe) {
            Remove-WebConfigurationProperty -PSPath "IIS:\" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -AtElement @{name=$h.name} -ErrorAction SilentlyContinue
        }
        Add-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -Value $h -ErrorAction SilentlyContinue
    }

    Write-OK "Encabezados de seguridad aplicados en IIS."
}

function Set-MetodosHttpIIS {
    Write-Info "Restringiendo metodos HTTP peligrosos en IIS..."
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $verbosBloquear = @("TRACE","TRACK","DELETE","PUT","PATCH")
    foreach ($verbo in $verbosBloquear) {
        # Evitar duplicados
        $existe = Get-WebConfigurationProperty -PSPath "IIS:\" `
            -Filter "system.webServer/security/requestFiltering/verbs" -Name "." -ErrorAction SilentlyContinue |
            Where-Object { $_.verb -eq $verbo }
        if (-not $existe) {
            Add-WebConfigurationProperty -PSPath "IIS:\" `
                -Filter "system.webServer/security/requestFiltering/verbs" `
                -Name "." -Value @{ verb=$verbo; allowed=$false } -ErrorAction SilentlyContinue
        }
    }

    Write-OK "Metodos TRACE, TRACK, DELETE, PUT, PATCH bloqueados en IIS."
}

# ─────────────────────────────────────────
# APACHE WIN64
# CORRECCION PRINCIPAL: descarga directa desde Apache Lounge
# en lugar de Chocolatey (que falla con URLs 404)
# ─────────────────────────────────────────

# ─────────────────────────────────────────
# APACHE WIN64
# ─────────────────────────────────────────

function Get-VersionesApache {
    Write-Info "Consultando versiones de Apache disponibles en Chocolatey.org..."

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $raw = choco search apache-httpd --exact --all-versions --limit-output 2>$null

        $versiones = @()
        foreach ($linea in $raw) {
            $partes = $linea -split '\|'
            if ($partes.Count -eq 2 -and $partes[1] -match '^\d+\.\d+\.\d+$') {
                $versiones += $partes[1].Trim()
            }
        }

        $versiones = @($versiones | Sort-Object { [Version]$_ } -Unique)

        if ($versiones.Count -ge 2) {
            return @($versiones[0], $versiones[-1])
        } elseif ($versiones.Count -eq 1) {
            return @($versiones[0], $versiones[0])
        }
    } catch {}

    Write-Warn "Usando versiones de respaldo conocidas."
    return @("2.4.52", "2.4.55")
}


function Install-Apache {
    Write-Info "=== Instalacion de Apache Win64 ==="

    $versiones = Get-VersionesApache

    Write-Host ""
    Write-Host "Versiones disponibles de Apache:" -ForegroundColor White
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        $etiqueta = if ($i -eq 0) { "(Estable / LTS)" } else { "(Latest / Desarrollo)" }
        Write-Host "  [$($i+1)] $($versiones[$i]) $etiqueta" -ForegroundColor Gray
    }

    Write-Host ""
    $seleccion = ""
    while ($true) {
        Write-Host "Seleccione version [1-$($versiones.Count)]: " -ForegroundColor White -NoNewline
        $seleccion = Read-Host
        if ($seleccion -match '^\d+$' -and [int]$seleccion -ge 1 -and [int]$seleccion -le $versiones.Count) { break }
        Write-Err "Seleccion invalida."
    }

    $versionElegida = $versiones[[int]$seleccion - 1]
    $puerto = Get-PuertoUsuario

    New-Item -ItemType Directory -Path "C:\http_provision" -Force | Out-Null

    # ── Descargar .nupkg directamente desde Chocolatey.org ────────────────────
    # El .nupkg contiene el ZIP de Apache embebido - sin pasar por apachehaus.com
    $nupkgUrl  = "https://community.chocolatey.org/api/v2/package/apache-httpd/$versionElegida"
    $nupkgPath = "C:\http_provision\apache-httpd-$versionElegida.nupkg"
    $zipPath   = "C:\http_provision\apache-httpd-$versionElegida.zip"
    $extraccionNupkg = "C:\http_provision\nupkg_$versionElegida"

    Write-Info "Descargando paquete Apache $versionElegida desde Chocolatey.org..."
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $nupkgUrl -OutFile $nupkgPath -UseBasicParsing -ErrorAction Stop

        $tamano = (Get-Item $nupkgPath).Length
        if ($tamano -lt 5MB) {
            Write-Err "El paquete descargado es invalido ($([math]::Round($tamano/1KB)) KB)."
            Remove-Item $nupkgPath -Force -ErrorAction SilentlyContinue
            return
        }
        Write-OK "Paquete descargado: $([math]::Round($tamano/1MB,1)) MB"
    } catch {
        Write-Err "No se pudo descargar el paquete desde Chocolatey.org: $_"
        return
    }

    # ── Extraer el .nupkg (es un ZIP renombrado) ──────────────────────────────
    Write-Info "Extrayendo paquete..."
    Copy-Item $nupkgPath $zipPath -Force
    if (Test-Path $extraccionNupkg) { Remove-Item $extraccionNupkg -Recurse -Force }
    Expand-Archive -Path $zipPath -DestinationPath $extraccionNupkg -Force
    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    Remove-Item $nupkgPath -Force -ErrorAction SilentlyContinue

    # ── Encontrar el ZIP de Apache dentro del nupkg ───────────────────────────
    $apacheZip = Get-ChildItem -Path $extraccionNupkg -Filter "*x64*.zip" -Recurse -ErrorAction SilentlyContinue |
                 Select-Object -First 1

    if (-not $apacheZip) {
        # Intentar cualquier ZIP si no hay x64 especifico
        $apacheZip = Get-ChildItem -Path $extraccionNupkg -Filter "*.zip" -Recurse -ErrorAction SilentlyContinue |
                     Select-Object -First 1
    }

    if (-not $apacheZip) {
        Write-Err "No se encontro el ZIP de Apache dentro del paquete."
        Remove-Item $extraccionNupkg -Recurse -Force -ErrorAction SilentlyContinue
        return
    }

    Write-Info "ZIP de Apache encontrado: $($apacheZip.Name)"

    # ── Extraer el ZIP de Apache a C:\ ────────────────────────────────────────
    Write-Info "Instalando Apache en C:\..."
    if (Test-Path $Global:RutaApache) { Remove-Item $Global:RutaApache -Recurse -Force }
    Expand-Archive -Path $apacheZip.FullName -DestinationPath "C:\" -Force
    Remove-Item $extraccionNupkg -Recurse -Force -ErrorAction SilentlyContinue

    # Buscar httpd.exe donde quedo
    $exe = [System.IO.Path]::Combine($Global:RutaApache, "bin", "httpd.exe")
    if (-not [System.IO.File]::Exists($exe)) {
        $found = Get-ChildItem -Path "C:\" -Filter "httpd.exe" -Recurse -ErrorAction SilentlyContinue |
                 Where-Object { $_.FullName -notlike "*system32*" } | Select-Object -First 1
        if ($found) {
            $Global:RutaApache = $found.Directory.Parent.FullName
        } else {
            Write-Err "No se encontro httpd.exe tras la extraccion."
            return
        }
    }

    Write-OK "Apache $versionElegida instalado en $Global:RutaApache."

    # ORDEN CORRECTO: primero configurar todo, luego registrar e iniciar servicio

    # 1. Instalar Visual C++ Redistributable (requerido por Apache antes de iniciarlo)
    $vcRedist = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64" `
                    -ErrorAction SilentlyContinue
    if (-not $vcRedist) {
        Write-Info "Instalando Visual C++ Redistributable (requerido por Apache)..."
        $vcUrl  = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcPath = "C:\http_provision\vc_redist.x64.exe"
        try {
            Invoke-WebRequest -Uri $vcUrl -OutFile $vcPath -UseBasicParsing -ErrorAction Stop
            & $vcPath /install /quiet /norestart 2>$null
            Remove-Item $vcPath -Force -ErrorAction SilentlyContinue
            Write-OK "Visual C++ Redistributable instalado."
        } catch {
            Write-Warn "No se pudo instalar VC++ Redistributable: $_"
        }
    }

    # 2. Configurar httpd.conf (ServerRoot, puerto, seguridad) ANTES de registrar servicio
    Set-PuertoApache    -Puerto $puerto
    Set-SeguridadApache
    Set-MetodosHttpApache

    # 3. Crear usuario dedicado y pagina index
    Set-UsuarioDedicado -Servicio "Apache" -Ruta "$Global:RutaApache\htdocs"
    New-IndexHtml -Servicio "Apache Win64" -Version $versionElegida -Puerto $puerto `
                  -WebRoot "$Global:RutaApache\htdocs"

    # 4. Registrar servicio DESPUES de que httpd.conf este correcto
    $svc = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    if ($svc) {
        # Desinstalar servicio anterior si existe para evitar conflictos
        & "$Global:RutaApache\bin\httpd.exe" -k uninstall -n "Apache2.4" 2>$null
        Start-Sleep -Seconds 2
    }
    & "$Global:RutaApache\bin\httpd.exe" -k install -n "Apache2.4" 2>$null
    Set-Service -Name "Apache2.4" -StartupType Automatic -ErrorAction SilentlyContinue

    # 5. Iniciar servicio
    Start-Sleep -Seconds 2
    Start-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    $svcStatus = (Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue).Status
    if ($svcStatus -eq "Running") {
        Write-OK "Servicio Apache2.4 corriendo correctamente."
    } else {
        Write-Warn "Servicio no inicio. Verifique con: Start-Service -Name Apache2.4"
    }

    Set-Firewall -Puerto $puerto
    Write-OK "Apache activo en el puerto $puerto."
    Show-VerificacionHTTP -Puerto $puerto
}


function Set-PuertoApache {
    param([int]$Puerto)
    $httpdConf = "$Global:RutaApache\conf\httpd.conf"
    if (-not (Test-Path $httpdConf)) { Write-Err "No se encontro httpd.conf"; return }
    Write-Info "Configurando puerto $Puerto y ServerRoot en httpd.conf..."

    # Convertir ruta de Windows a formato Unix para Apache (C:\Apache24 -> C:/Apache24)
    $serverRoot = $Global:RutaApache -replace '\\', '/'

    $contenido = Get-Content $httpdConf
    # Corregir ServerRoot a la ruta real de instalacion
    $contenido = $contenido -replace 'ServerRoot\s+"[^"]*"', "ServerRoot `"$serverRoot`""
    $contenido = $contenido -replace "ServerRoot\s+'[^']*'",  "ServerRoot `"$serverRoot`""
    # Corregir puerto y ServerName
    $contenido = $contenido -replace 'Listen \d+',        "Listen $Puerto"
    $contenido = $contenido -replace 'ServerName .*:\d+', "ServerName localhost:$Puerto"
    Set-Content -Path $httpdConf -Value $contenido -Encoding UTF8
    Write-OK "ServerRoot y puerto $Puerto configurados en httpd.conf."
}

function Set-SeguridadApache {
    $httpdConf = "$Global:RutaApache\conf\httpd.conf"
    Write-Info "Aplicando seguridad en Apache..."
    $contenido = Get-Content $httpdConf
    if ($contenido -match 'ServerTokens') {
        $contenido = $contenido -replace 'ServerTokens.*', 'ServerTokens Prod'
    } else { $contenido += "`nServerTokens Prod" }
    if ($contenido -match 'ServerSignature') {
        $contenido = $contenido -replace 'ServerSignature.*', 'ServerSignature Off'
    } else { $contenido += "`nServerSignature Off" }
    $contenido = $contenido -replace '#LoadModule headers_module', 'LoadModule headers_module'
    if (($contenido -join "`n") -notmatch 'X-Frame-Options') {
        $contenido += @"

# Encabezados de seguridad - Practica 6
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
Header always set X-XSS-Protection "1; mode=block"
Header always unset X-Powered-By
"@
    }
    Set-Content -Path $httpdConf -Value $contenido -Encoding UTF8
    Write-OK "Seguridad aplicada en Apache."
}

function Set-MetodosHttpApache {
    $httpdConf = "$Global:RutaApache\conf\httpd.conf"
    Write-Info "Restringiendo metodos HTTP peligrosos en Apache..."
    $contenido = Get-Content $httpdConf -Raw
    if ($contenido -notmatch 'TraceEnable Off') {
        $restriccion = @"

# Restriccion de metodos HTTP - Practica 6
TraceEnable Off
<Directory "$($Global:RutaApache -replace '\\','/')/htdocs">
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Directory>
"@
        Add-Content -Path $httpdConf -Value $restriccion -Encoding UTF8
    }
    Write-OK "Metodos peligrosos bloqueados en Apache."
}


function Get-VersionesNginx {
    Write-Info "Consultando versiones de Nginx disponibles en nginx.org..."

    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        $pagina = Invoke-WebRequest -Uri "https://nginx.org/en/download.html" `
                      -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop

        # Buscar versiones estables y mainline
        $stable  = [regex]::Match($pagina.Content, 'Stable version.*?nginx-([\d\.]+)\.zip').Groups[1].Value
        $mainline = [regex]::Match($pagina.Content, 'Mainline version.*?nginx-([\d\.]+)\.zip').Groups[1].Value

        if ($stable -and $mainline) {
            return @($stable, $mainline)
        }
    } catch {
        Write-Warn "No se pudo consultar nginx.org: $_"
    }

    Write-Warn "Usando versiones de respaldo conocidas."
    return @("1.26.3", "1.27.4")
}


function Install-Nginx {
    Write-Info "=== Instalacion de Nginx para Windows ==="

    $versiones = Get-VersionesNginx

    Write-Host ""
    Write-Host "Versiones disponibles de Nginx:" -ForegroundColor White
    for ($i = 0; $i -lt $versiones.Count; $i++) {
        $etiqueta = if ($i -eq 0) { "(Estable / LTS)" } else { "(Latest / Desarrollo)" }
        Write-Host "  [$($i+1)] $($versiones[$i]) $etiqueta" -ForegroundColor Gray
    }

    Write-Host ""
    $seleccion = ""
    while ($true) {
        Write-Host "Seleccione version [1-$($versiones.Count)]: " -ForegroundColor White -NoNewline
        $seleccion = Read-Host
        if ($seleccion -match '^\d+$' -and [int]$seleccion -ge 1 -and [int]$seleccion -le $versiones.Count) { break }
        Write-Err "Seleccion invalida."
    }

    $versionElegida = $versiones[[int]$seleccion - 1]
    $puerto = Get-PuertoUsuario

    New-Item -ItemType Directory -Path "C:\http_provision" -Force | Out-Null

    # Descargar ZIP directamente desde nginx.org (sin bloqueos de bots)
    $nombreZip  = "nginx-$versionElegida.zip"
    $urlDescarga = "https://nginx.org/download/$nombreZip"
    $zipDestino  = "C:\http_provision\$nombreZip"

    Write-Info "Descargando Nginx $versionElegida desde nginx.org..."
    try {
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $urlDescarga -OutFile $zipDestino -UseBasicParsing -ErrorAction Stop

        $tamano = (Get-Item $zipDestino).Length
        if ($tamano -lt 1MB) {
            Write-Err "Descarga invalida ($([math]::Round($tamano/1KB)) KB)."
            Remove-Item $zipDestino -Force -ErrorAction SilentlyContinue
            return
        }
        Write-OK "Descarga completada: $([math]::Round($tamano/1MB,1)) MB"
    } catch {
        Write-Err "No se pudo descargar Nginx desde nginx.org: $_"
        return
    }

    # Extraer ZIP a C:\tools\
    Write-Info "Extrayendo Nginx..."
    $destino = "C:\tools"
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    Expand-Archive -Path $zipDestino -DestinationPath $destino -Force
    Remove-Item $zipDestino -Force -ErrorAction SilentlyContinue

    # Buscar nginx.exe dinamicamente (el nombre de carpeta puede variar)
    $nginxExe = Get-ChildItem -Path $destino -Filter "nginx.exe" -Recurse -ErrorAction SilentlyContinue |
                Select-Object -First 1

    if (-not $nginxExe) {
        Write-Err "No se encontro nginx.exe tras la extraccion en $destino"
        return
    }

    $Global:RutaNginx = $nginxExe.DirectoryName
    Write-Info "Nginx encontrado en: $Global:RutaNginx"
    Write-OK "Nginx $versionElegida instalado en $Global:RutaNginx."

    Set-UsuarioDedicado -Servicio "Nginx" -Ruta "$Global:RutaNginx\html"
    Set-PuertoNginx    -Puerto $puerto
    Set-SeguridadNginx -Puerto $puerto

    New-IndexHtml -Servicio "Nginx" -Version $versionElegida -Puerto $puerto `
                  -WebRoot "$Global:RutaNginx\html"

    # Iniciar Nginx directamente como proceso (mas confiable que NSSM en Server Core)
    # Detener instancias previas
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force

    Write-Info "Iniciando Nginx en $Global:RutaNginx..."
    $proc = Start-Process -FilePath "$Global:RutaNginx\nginx.exe" `
                -WorkingDirectory "$Global:RutaNginx" `
                -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3

    # Verificar que esta corriendo
    $nginxRunning = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($nginxRunning) {
        Write-OK "Nginx corriendo (PID: $($nginxRunning[0].Id))."

        # Registrar como tarea programada para que inicie con Windows
        $action   = New-ScheduledTaskAction -Execute "$Global:RutaNginx\nginx.exe" -WorkingDirectory "$Global:RutaNginx"
        $trigger  = New-ScheduledTaskTrigger -AtStartup
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0
        Register-ScheduledTask -TaskName "Nginx-Practica6" -Action $action `
            -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
        Write-OK "Nginx registrado como tarea de inicio automatico."
    } else {
        Write-Err "Nginx no pudo iniciarse. Verifique el archivo de log en $Global:RutaNginx\logs\error.log"
    }

    Set-Firewall -Puerto $puerto
    Write-OK "Nginx activo en el puerto $puerto."
    Show-VerificacionHTTP -Puerto $puerto
}


function Set-PuertoNginx {
    param([int]$Puerto)

    $nginxConf = "$Global:RutaNginx\conf\nginx.conf"
    if (-not (Test-Path $nginxConf)) { Write-Err "No se encontro nginx.conf en $Global:RutaNginx\conf\"; return }

    Write-Info "Configurando puerto $Puerto en nginx.conf..."

    $contenido = Get-Content $nginxConf -Raw
    $contenido = $contenido -replace 'listen\s+\d+;', "listen $Puerto;"

    # Escribir sin BOM - nginx no acepta BOM en su archivo de configuracion
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($nginxConf, $contenido, $utf8NoBom)

    Write-OK "Puerto $Puerto configurado en nginx.conf."
}

function Set-SeguridadNginx {
    param([int]$Puerto)

    $nginxConf = "$Global:RutaNginx\conf\nginx.conf"
    Write-Info "Aplicando seguridad en Nginx..."

    # CORRECCION: usar backtick para escapar $ en here-string de PowerShell
    $serverBloque = @"
    server {
        listen $Puerto;
        server_name  localhost;

        server_tokens off;

        root   html;
        index  index.html index.htm;

        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        location / {
            limit_except GET POST HEAD {
                deny all;
            }
            try_files `$uri `$uri/ =404;
        }

        if (`$request_method = TRACE) {
            return 405;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
    }
"@

    $contenido = Get-Content $nginxConf -Raw
    # Reemplazar bloque server existente (regex multilinea)
    $contenido = $contenido -replace '(?s)server\s*\{.*\}(?=\s*\})', $serverBloque
    # Escribir sin BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($nginxConf, $contenido, $utf8NoBom)

    Write-OK "Seguridad y encabezados configurados en Nginx."
}

# ─────────────────────────────────────────
# USUARIO DEDICADO CON PERMISOS LIMITADOS
# ─────────────────────────────────────────

function Set-UsuarioDedicado {
    param([string]$Servicio, [string]$Ruta)

    $usuario = "svc_$($Servicio.ToLower())"
    Write-Info "Configurando usuario dedicado '$usuario' para $Servicio..."

    # Generar contrasena sin depender de System.Web (no disponible en Server Core)
    $chars   = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%'
    $passwd  = -join ((1..16) | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    $securePasswd = ConvertTo-SecureString $passwd -AsPlainText -Force

    $existeUsuario = Get-LocalUser -Name $usuario -ErrorAction SilentlyContinue
    if (-not $existeUsuario) {
        try {
            New-LocalUser -Name $usuario -Password $securePasswd `
                -PasswordNeverExpires -UserMayNotChangePassword `
                -Description "Cuenta de servicio para $Servicio - Practica 6" | Out-Null
            Write-OK "Usuario '$usuario' creado."
        } catch {
            Write-Warn "No se pudo crear usuario '$usuario': $_"
            return
        }
    } else {
        Write-Info "Usuario '$usuario' ya existe."
    }

    # Asignar permisos NTFS con manejo de error de identidad
    New-Item -ItemType Directory -Path $Ruta -Force | Out-Null
    try {
        $acl  = Get-Acl $Ruta
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $usuario, "ReadAndExecute,Write",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($rule)
        Set-Acl -Path $Ruta -AclObject $acl
        Write-OK "Permisos NTFS configurados para '$usuario' en $Ruta."
    } catch {
        Write-Warn "No se pudieron aplicar permisos NTFS: $_"
        Write-Warn "Continuando sin permisos dedicados."
    }
}


function Show-VerificacionHTTP {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "--- Verificacion del servicio ---" -ForegroundColor Cyan
    Write-Host "Desde su PC cliente ejecute:" -ForegroundColor White
    Write-Host "  curl.exe -I http://<IP-del-servidor>:$Puerto" -ForegroundColor Yellow
    Write-Host ""

    Start-Sleep -Seconds 3

    try {
        Invoke-WebRequest -Uri "http://localhost:$Puerto" `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop | Out-Null
        Write-OK "El servidor responde correctamente en el puerto $Puerto."
    } catch {
        Write-Warn "El servicio aun no responde en localhost:$Puerto"
        Write-Warn "Intente desde el cliente: curl.exe -I http://<IP>:$Puerto"
    }
}

function Show-EstadoServicios {
    Write-Host ""
    Write-Host "=== Estado de Servicios HTTP ===" -ForegroundColor Cyan

    # IIS
    $iis = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if ($iis -and $iis.Installed) {
        $svc    = Get-Service -Name W3SVC -ErrorAction SilentlyContinue
        $estado = if ($svc.Status -eq "Running") { "ACTIVO" } else { "DETENIDO" }
        Write-Host "[IIS]    $estado" -ForegroundColor $(if ($estado -eq "ACTIVO") {"Green"} else {"Red"})
    } else {
        Write-Host "[IIS]    No instalado" -ForegroundColor DarkGray
    }

    # Apache
    $apache = Get-Service -Name "Apache2.4" -ErrorAction SilentlyContinue
    if ($apache) {
        Write-Host "[Apache] $($apache.Status)" -ForegroundColor $(if ($apache.Status -eq "Running") {"Green"} else {"Red"})
    } else {
        Write-Host "[Apache] No instalado" -ForegroundColor DarkGray
    }

    # Nginx
    $nginx = Get-Service -Name "nginx" -ErrorAction SilentlyContinue
    if ($nginx) {
        Write-Host "[Nginx]  $($nginx.Status)" -ForegroundColor $(if ($nginx.Status -eq "Running") {"Green"} else {"Red"})
    } else {
        Write-Host "[Nginx]  No instalado" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Puertos en escucha:" -ForegroundColor White
    Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -gt 79 -and $_.LocalPort -lt 65535 } |
        Select-Object LocalPort, OwningProcess |
        Sort-Object LocalPort -Unique |
        Format-Table -AutoSize
}