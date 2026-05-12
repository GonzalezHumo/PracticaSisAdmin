# ============================================================
#  funciones_SSL.ps1  -  Practica 7 - Administracion de Sistemas
#  Funciones SSL/TLS, cliente FTP dinamico y validacion de hash
#  Windows (IIS, Apache, Nginx, IIS-FTP)
# ============================================================

# ── Directorio base de certificados ──────────────────────────
$CERT_DIR = "C:\SSL\reprobados"

# ============================================================
#  SECCION 1 - UTILIDADES GENERALES
# ============================================================

function Preguntar-SSL {
    param([string]$Servicio)
    do {
        $resp = Read-Host "¿Desea activar SSL en $Servicio? [S/N]"
        $resp = $resp.Trim().ToUpper()
    } while ($resp -ne "S" -and $resp -ne "N")
    return $resp -eq "S"
}

function Mostrar-Banner-P7 {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Practica 7 - Infraestructura de Despliegue Seguro        " -ForegroundColor Cyan
    Write-Host "  Instalacion Hibrida (FTP/Web) + SSL/TLS - WINDOWS        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
#  SECCION 2 - GENERACION DE CERTIFICADOS AUTOFIRMADOS
# ============================================================

function Generar-Certificado {
    param([string]$Servicio)

    $certPath = "$CERT_DIR\$Servicio"
    if (-not (Test-Path $certPath)) {
        New-Item -Path $certPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "[*] Generando certificado autofirmado para $Servicio..." -ForegroundColor Cyan

    # Generar con PowerShell nativo
    $cert = New-SelfSignedCertificate `
        -DnsName "www.reprobados.com" `
        -CertStoreLocation "Cert:\LocalMachine\My" `
        -NotAfter (Get-Date).AddDays(365) `
        -KeyAlgorithm RSA `
        -KeyLength 2048 `
        -KeyUsage DigitalSignature, KeyEncipherment `
        -FriendlyName "reprobados-$Servicio"

    # Exportar .pfx (con clave privada) para IIS/Apache/Nginx
    $pfxPath  = "$certPath\server.pfx"
    $crtPath  = "$certPath\server.crt"
    $password = ConvertTo-SecureString "reprobados123" -AsPlainText -Force

    Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $password | Out-Null

    # Exportar solo el certificado publico (.crt) para Apache/Nginx
    Export-Certificate -Cert $cert -FilePath $crtPath -Type CERT | Out-Null

    Write-Host "[+] Certificado generado:" -ForegroundColor Green
    Write-Host "    PFX : $pfxPath"
    Write-Host "    CRT : $crtPath"
    Write-Host "    Thumbprint: $($cert.Thumbprint)"

    return $cert.Thumbprint
}

# ============================================================
#  SECCION 3 - SSL EN IIS (HTTPS puerto 443 + redireccion)
# ============================================================

function Activar-SSL-IIS {
    param([int]$PuertoHTTP = 80)

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $thumb = Generar-Certificado -Servicio "IIS"

    Write-Host "[*] Configurando SSL en IIS..." -ForegroundColor Cyan

    $sitio = "Default Web Site"

    # Agregar binding HTTPS en puerto 443
    $bindingExiste = Get-WebBinding -Name $sitio -Protocol https -ErrorAction SilentlyContinue
    if (-not $bindingExiste) {
        New-WebBinding -Name $sitio -Protocol https -Port 443 -IPAddress "*" -SslFlags 0 | Out-Null
    }

    # Asociar certificado al binding 443
    $binding = Get-WebBinding -Name $sitio -Protocol https
    $binding.AddSslCertificate($thumb, "My")

    # Redireccion HTTP -> HTTPS via web.config en wwwroot
    $webConfigPath = "C:\inetpub\wwwroot\web.config"
    $webConfigContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP to HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions>
            <add input="{HTTPS}" pattern="^OFF$" />
          </conditions>
          <action type="Redirect" url="https://{HTTP_HOST}/{R:1}" redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security" value="max-age=31536000; includeSubDomains" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
    Set-Content -Path $webConfigPath -Value $webConfigContent -Encoding UTF8

    # Habilitar modulo URL Rewrite si esta disponible
    $rewriteModule = Get-WebGlobalModule -Name "RewriteModule" -ErrorAction SilentlyContinue
    if (-not $rewriteModule) {
        Write-Host "[!] Instala URL Rewrite para IIS desde: https://www.iis.net/downloads/microsoft/url-rewrite" -ForegroundColor Yellow
    }

    # Abrir puerto 443 en firewall
    if (-not (Get-NetFirewallRule -DisplayName "HTTPS-443" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "HTTPS-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null
    }

    Restart-Service W3SVC -Force
    Write-Host "[+] IIS con SSL activo en puerto 443. HTTP redirige a HTTPS." -ForegroundColor Green
}

# ============================================================
#  SECCION 4 - SSL EN APACHE WINDOWS (httpd.conf)
# ============================================================

function Activar-SSL-Apache {
    param([int]$PuertoHTTP = 80)

    $thumb = Generar-Certificado -Servicio "Apache"

    # Detectar ruta de Apache
    $apacheBase = "C:\Apache24\Apache24"
    if (-not (Test-Path $apacheBase)) { $apacheBase = "C:\Apache24" }
    $conf = "$apacheBase\conf\httpd.conf"

    if (-not (Test-Path $conf)) {
        Write-Host "[!] No se encontro httpd.conf en $conf" -ForegroundColor Red
        return
    }

    Write-Host "[*] Configurando SSL en Apache Windows..." -ForegroundColor Cyan

    $pfxPath  = "$CERT_DIR\Apache\server.pfx"
    $crtPath  = "$CERT_DIR\Apache\server.crt"

    # Extraer .key desde el certificado usando openssl (si esta disponible via choco)
    $keyPath = "$CERT_DIR\Apache\server.key"
    $opensslPaths = @(
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe",
        "C:\ProgramData\chocolatey\bin\openssl.exe"
    )
    $opensslCmd = Get-Command openssl -ErrorAction SilentlyContinue
    $opensslExe = if ($opensslCmd) { $opensslCmd.Source } else {
        $opensslPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($opensslExe) {
        & $opensslExe pkcs12 -in $pfxPath -nocerts -nodes -out $keyPath -passin pass:reprobados123 2>$null
    } else {
        Write-Host "[!] openssl no encontrado. Instala con: choco install openssl" -ForegroundColor Yellow
        Write-Host "[!] Usando solo el .pfx. Configura manualmente server.key si es necesario." -ForegroundColor Yellow
        $keyPath = $pfxPath
    }

    # Habilitar modulos SSL en httpd.conf
    $contenido = Get-Content $conf -Raw
    $contenido = $contenido -replace '#LoadModule ssl_module',     'LoadModule ssl_module'
    $contenido = $contenido -replace '#LoadModule socache_shmcb_module', 'LoadModule socache_shmcb_module'
    $contenido = $contenido -replace '#LoadModule rewrite_module',  'LoadModule rewrite_module'
    $contenido = $contenido -replace '#Include conf/extra/httpd-ssl.conf', 'Include conf/extra/httpd-ssl.conf'
    Set-Content $conf $contenido

    # Configurar httpd-ssl.conf
    $sslConf = "$apacheBase\conf\extra\httpd-ssl.conf"
    if (Test-Path $sslConf) {
        $ssl = Get-Content $sslConf -Raw
        $ssl = $ssl -replace 'SSLCertificateFile ".*"',    "SSLCertificateFile `"$crtPath`""
        $ssl = $ssl -replace 'SSLCertificateKeyFile ".*"', "SSLCertificateKeyFile `"$keyPath`""
        $ssl = $ssl -replace 'ServerName .*:443',          'ServerName www.reprobados.com:443'
        Set-Content $sslConf $ssl
    }

    # Agregar redireccion HTTP -> HTTPS al final de httpd.conf
    if ((Get-Content $conf -Raw) -notmatch "reprobados-redirect") {
        Add-Content $conf @"

# Redireccion HTTP -> HTTPS
<VirtualHost *:$PuertoHTTP>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}`$1 [R=301,L]
</VirtualHost>
"@
    }

    # HSTS en ssl.conf
    if ((Get-Content $conf -Raw) -notmatch "Strict-Transport-Security") {
        Add-Content $conf "`nHeader always set Strict-Transport-Security `"max-age=31536000; includeSubDomains`""
    }

    if (-not (Get-NetFirewallRule -DisplayName "HTTPS-Apache-443" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "HTTPS-Apache-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null
    }

    # Detectar nombre correcto del servicio Apache
    $apacheSvc = Get-Service | Where-Object { 
        ($_.Name -like "Apache*" -or $_.DisplayName -like "Apache*") -and $_.Status -eq "Running"
    } | Select-Object -First 1

    if (-not $apacheSvc) {
        $apacheSvc = Get-Service | Where-Object { 
            $_.Name -like "Apache*" -or $_.DisplayName -like "Apache*"
        } | Select-Object -First 1
    }

    if ($apacheSvc) {
        Restart-Service $apacheSvc.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        if ((Get-Service $apacheSvc.Name).Status -eq "Running") {
            Write-Host "[+] Apache con SSL activo en puerto 443." -ForegroundColor Green
        } else {
            Write-Host "[!] Error al reiniciar Apache. Revisa los logs en $apacheBase\logs\" -ForegroundColor Red
        }
    } else {
        Write-Host "[!] No se encontro el servicio Apache." -ForegroundColor Red
    }
}

# ============================================================
#  SECCION 5 - SSL EN NGINX WINDOWS
# ============================================================

function Activar-SSL-Nginx {
    param([int]$PuertoHTTP = 80)

    $thumb = Generar-Certificado -Servicio "Nginx"

    # Detectar ruta de Nginx
    $nginxBase = (Get-ChildItem "C:\tools" -Filter "nginx*" -Directory -ErrorAction SilentlyContinue |
                  Sort-Object Name -Descending | Select-Object -First 1).FullName
    if (-not $nginxBase) {
        $nginxBase = (Get-ChildItem "C:\ProgramData\chocolatey\lib\nginx" -Recurse -Filter "nginx.exe" -ErrorAction SilentlyContinue |
                      Select-Object -First 1).DirectoryName
    }
    if (-not $nginxBase) {
        Write-Host "[!] No se encontro directorio de Nginx." -ForegroundColor Red
        return
    }

    $conf    = "$nginxBase\conf\nginx.conf"
    $crtPath = "$CERT_DIR\Nginx\server.crt"

    # Extraer .key si openssl disponible
    $pfxPath = "$CERT_DIR\Nginx\server.pfx"
    $keyPath = "$CERT_DIR\Nginx\server.key"
    $opensslPaths = @(
        "C:\Program Files\OpenSSL-Win64\bin\openssl.exe",
        "C:\Program Files (x86)\OpenSSL-Win32\bin\openssl.exe",
        "C:\ProgramData\chocolatey\bin\openssl.exe"
    )
    $opensslCmd = Get-Command openssl -ErrorAction SilentlyContinue
    $opensslExe = if ($opensslCmd) { $opensslCmd.Source } else {
        $opensslPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    }
    if ($opensslExe) {
        & $opensslExe pkcs12 -in $pfxPath -nocerts -nodes -out $keyPath -passin pass:reprobados123 2>$null
    } else {
        Write-Host "[!] openssl no encontrado. Instala con: choco install openssl" -ForegroundColor Yellow
        $keyPath = $pfxPath
    }

    Write-Host "[*] Configurando SSL en Nginx Windows..." -ForegroundColor Cyan

    $webroot = "$nginxBase\html"

    $nginxSSL = @"
worker_processes  1;

events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server_tokens off;

    # Redireccion HTTP -> HTTPS
    server {
        listen $PuertoHTTP;
        server_name www.reprobados.com;
        return 301 https://`$host`$request_uri;
    }

    # HTTPS
    server {
        listen 443 ssl;
        server_name www.reprobados.com;

        ssl_certificate     $crtPath;
        ssl_certificate_key $keyPath;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        if (`$request_method ~ ^(TRACE|DELETE|TRACK)`$) {
            return 405;
        }

        location / {
            root   $webroot;
            index  index.html index.htm;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root $webroot;
        }
    }
}
"@
    Set-Content -Path $conf -Value $nginxSSL

    if (-not (Get-NetFirewallRule -DisplayName "HTTPS-Nginx-443" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "HTTPS-Nginx-443" -Direction Inbound -Protocol TCP -LocalPort 443 -Action Allow | Out-Null
    }

    Restart-Service Nginx -ErrorAction SilentlyContinue
    if ((Get-Service Nginx -ErrorAction SilentlyContinue).Status -eq "Running") {
        Write-Host "[+] Nginx con SSL activo en puerto 443." -ForegroundColor Green
    } else {
        Write-Host "[!] Error al reiniciar Nginx." -ForegroundColor Red
    }
}

# ============================================================
#  SECCION 6 - FTPS EN IIS-FTP (SSL Settings)
# ============================================================

function Activar-SSL-IISFTP {

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $thumb = Generar-Certificado -Servicio "IIS-FTP"

    Write-Host "[*] Configurando FTPS en IIS-FTP..." -ForegroundColor Cyan

    # Aplicar certificado al sitio FTP
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.serverCertHash" `
        -Value $thumb

    # Forzar SSL en canal de control y datos
    # 0=Allow, 1=Require, 2=Deny
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" `
        -Value 1   # Require SSL

    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.dataChannelPolicy" `
        -Value 1   # Require SSL

    # Abrir puerto 990 (FTPS implicito) en firewall
    if (-not (Get-NetFirewallRule -DisplayName "FTPS-990" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTPS-990" -Direction Inbound -Protocol TCP -LocalPort 990 -Action Allow | Out-Null
    }

    Restart-WebItem "IIS:\Sites\FTP"
    Write-Host "[+] FTPS activado en IIS-FTP. Canal de control y datos cifrados." -ForegroundColor Green
}

# ============================================================
#  SECCION 7 - VERIFICACION AUTOMATIZADA DE SSL
# ============================================================

function Verificar-SSL-Servicio {
    param(
        [string]$Nombre,
        [string]$Servidor  = "localhost",
        [int]   $Puerto,
        [string]$Protocolo = "https"
    )

    Write-Host "[*] Verificando SSL en $Nombre ($Servidor`:$Puerto)..." -ForegroundColor Cyan

    $tcpClient = $null
    $sslStream = $null

    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($Servidor, $Puerto)

        $callback = [System.Net.Security.RemoteCertificateValidationCallback]{
            param($sender, $certificate, $chain, $errors)
            return $true
        }

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(), $false, $callback
        )

        if ($Protocolo -eq "ftp") {
            $netStream = $tcpClient.GetStream()
            $reader = New-Object System.IO.StreamReader($netStream)
            $writer = New-Object System.IO.StreamWriter($netStream)
            $writer.AutoFlush = $true
            $banner = $reader.ReadLine()
            $writer.WriteLine("AUTH TLS")
            $reader.ReadLine() | Out-Null
        }

        $sslStream.AuthenticateAsClient("www.reprobados.com")
        $cert = $sslStream.RemoteCertificate

        Write-Host "  [OK] $Nombre - Certificado valido:" -ForegroundColor Green
        Write-Host "       Subject : $($cert.Subject)"
        Write-Host "       Expira  : $($cert.GetExpirationDateString())"
        return $true
    }
    catch {
        Write-Host "  [FALLO] $Nombre - No se pudo verificar SSL en $Servidor`:$Puerto" -ForegroundColor Red
        Write-Host "          $($_.Exception.Message)" -ForegroundColor DarkRed
        return $false
    }
    finally {
        if ($sslStream) { $sslStream.Close() }
        if ($tcpClient) { $tcpClient.Close() }
    }
}

function Resumen-Verificacion-Windows {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  RESUMEN DE VERIFICACION SSL - WINDOWS                    " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $ok    = 0
    $fallo = 0

    if (Verificar-SSL-Servicio -Nombre "IIS"     -Puerto 443  -Protocolo "https") { $ok++ } else { $fallo++ }
    if (Verificar-SSL-Servicio -Nombre "Apache"  -Puerto 443  -Protocolo "https") { $ok++ } else { $fallo++ }
    if (Verificar-SSL-Servicio -Nombre "Nginx"   -Puerto 443  -Protocolo "https") { $ok++ } else { $fallo++ }
    if (Verificar-SSL-Servicio -Nombre "IIS-FTP" -Puerto 21   -Protocolo "ftp"  ) { $ok++ } else { $fallo++ }

    Write-Host ""
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host "  Servicios verificados : 4"
    Write-Host "  OK     : $ok"    -ForegroundColor Green
    Write-Host "  Fallos : $fallo" -ForegroundColor Red
    Write-Host "------------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

# ============================================================
#  SECCION 8 - CLIENTE FTP DINAMICO
# ============================================================

function Listar-Directorio-FTP {
    param(
        [string]$Usuario,
        [string]$Password,
        [string]$IP,
        [string]$Ruta = "/"
    )

    $uri  = "ftp://$IP$Ruta"
    $cred = New-Object System.Net.NetworkCredential($Usuario, $Password)

    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $req.EnableSsl   = $true

        $resp   = $req.GetResponse()
        $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lista  = $reader.ReadToEnd()
        $reader.Close()
        $resp.Close()

        # El servidor puede devolver rutas completas o solo nombres
        # Extraer solo el nombre del archivo (ultima parte despues de /)
        $resultados = $lista -split "`n" | ForEach-Object {
            $linea = $_.Trim()
            if ($linea -ne "") {
                # Si tiene slashes, tomar la ultima parte
                if ($linea -match "/") {
                    $linea.Split("/")[-1]
                } else {
                    $linea
                }
            }
        } | Where-Object { $_ -ne "" -and $_ -ne "." -and $_ -ne ".." }

        return $resultados
    }
    catch {
        Write-Host "[!] Error al listar FTP $uri : $_" -ForegroundColor Red
        return @()
    }
}

function Descargar-FTP {
    param(
        [string]$Usuario,
        [string]$Password,
        [string]$IP,
        [string]$RutaRemota,
        [string]$Destino
    )

    $uri  = "ftp://$IP$RutaRemota"
    $cred = New-Object System.Net.NetworkCredential($Usuario, $Password)

    # Aceptar certificados autofirmados
    [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }

    Write-Host "[*] Descargando $RutaRemota..." -ForegroundColor Cyan

    try {
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method      = [System.Net.WebRequestMethods+Ftp]::DownloadFile
        $req.Credentials = $cred
        $req.UsePassive  = $true
        $req.UseBinary   = $true
        $req.EnableSsl   = $true

        $resp       = $req.GetResponse()
        $ftpStream  = $resp.GetResponseStream()
        $fileStream = [System.IO.File]::Create($Destino)
        $ftpStream.CopyTo($fileStream)
        $fileStream.Close()
        $ftpStream.Close()
        $resp.Close()

        Write-Host "[+] Descargado en: $Destino" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "[!] Error al descargar $uri : $_" -ForegroundColor Red
        return $false
    }
}

# ============================================================
#  SECCION 9 - VALIDACION DE INTEGRIDAD (SHA256)
# ============================================================

function Verificar-Hash-FTP {
    param(
        [string]$Usuario,
        [string]$Password,
        [string]$IP,
        [string]$RutaSHA256,
        [string]$ArchivoLocal
    )

    $hashFile = "$env:TEMP\$(Split-Path $RutaSHA256 -Leaf)"

    Write-Host "[*] Verificando integridad de $(Split-Path $ArchivoLocal -Leaf)..." -ForegroundColor Cyan

    $ok = Descargar-FTP -Usuario $Usuario -Password $Password -IP $IP -RutaRemota $RutaSHA256 -Destino $hashFile

    if (-not $ok -or -not (Test-Path $hashFile)) {
        Write-Host "[!] No se pudo obtener el archivo .sha256 del servidor." -ForegroundColor Red
        return $false
    }

    $hashEsperado  = (Get-Content $hashFile -Raw).Trim().Split(" ")[0].ToLower()
    $hashCalculado = (Get-FileHash -Path $ArchivoLocal -Algorithm SHA256).Hash.ToLower()

    Write-Host "  Esperado  : $hashEsperado"
    Write-Host "  Calculado : $hashCalculado"

    Remove-Item $hashFile -Force -ErrorAction SilentlyContinue

    if ($hashEsperado -eq $hashCalculado) {
        Write-Host "[+] Integridad verificada correctamente. Archivo sin corrupcion." -ForegroundColor Green
        return $true
    } else {
        Write-Host "[!] FALLO DE INTEGRIDAD: el archivo esta corrupto o fue modificado." -ForegroundColor Red
        return $false
    }
}

# ============================================================
#  SECCION 10 - INSTALACION DESDE FTP (navegacion dinamica)
# ============================================================

function Instalar-Desde-FTP {
    $os      = "Windows"
    $baseFTP = "/http/$os"
    $tmpDir  = "$env:TEMP\p7_ftp"
    if (-not (Test-Path $tmpDir)) { New-Item -Path $tmpDir -ItemType Directory -Force | Out-Null }

    Write-Host ""
    Write-Host "--- Instalacion via Repositorio FTP Privado ---" -ForegroundColor Cyan

    $ftpIP   = Read-Host "IP del servidor FTP"
    $ftpUser = Read-Host "Usuario FTP"
    $ftpPass = Read-Host "Password FTP"

    # 1. Listar servicios disponibles
    Write-Host "[*] Listando servicios disponibles en $baseFTP ..." -ForegroundColor Cyan
    $servicios = @(Listar-Directorio-FTP -Usuario $ftpUser -Password $ftpPass -IP $ftpIP -Ruta "$baseFTP/")

    if ($servicios.Count -eq 0) {
        Write-Host "[!] No se pudo conectar al FTP o la ruta esta vacia." -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Servicios disponibles:" -ForegroundColor Cyan
    for ($i = 0; $i -lt $servicios.Count; $i++) {
        Write-Host "  [$($i+1)] $($servicios[$i])"
    }

    do {
        $selSvc = Read-Host "Selecciona un servicio [1-$($servicios.Count)]"
    } while ($selSvc -notmatch '^\d+$' -or [int]$selSvc -lt 1 -or [int]$selSvc -gt $servicios.Count)

    $servicioElegido = $servicios[[int]$selSvc - 1]
    $rutaServicio    = "$baseFTP/$servicioElegido"

    # 2. Listar archivos binarios en la carpeta del servicio
    Write-Host "[*] Listando versiones disponibles en $rutaServicio ..." -ForegroundColor Cyan
    $todosArchivos = Listar-Directorio-FTP -Usuario $ftpUser -Password $ftpPass -IP $ftpIP -Ruta "$rutaServicio/"

    # Filtrar solo binarios (excluir .sha256)
    $archivos = @($todosArchivos | Where-Object { $_ -match '\.(msi|zip|exe)$' })

    if ($archivos.Count -eq 0) {
        Write-Host "[!] No se encontraron instaladores en $rutaServicio" -ForegroundColor Red
        return
    }

    Write-Host ""
    Write-Host "Versiones disponibles para $($servicioElegido):" -ForegroundColor Cyan
    for ($i = 0; $i -lt $archivos.Count; $i++) {
        Write-Host "  [$($i+1)] $($archivos[$i])"
    }

    do {
        $selArch = Read-Host "Selecciona una version [1-$($archivos.Count)]"
    } while ($selArch -notmatch '^\d+$' -or [int]$selArch -lt 1 -or [int]$selArch -gt $archivos.Count)

    $archivoElegido  = $archivos[[int]$selArch - 1]
    $rutaBinario     = "$rutaServicio/$archivoElegido"
    $rutaSHA256      = "$rutaServicio/$archivoElegido.sha256"
    $destinoLocal    = "$tmpDir\$archivoElegido"

    # 3. Descargar binario
    $ok = Descargar-FTP -Usuario $ftpUser -Password $ftpPass -IP $ftpIP -RutaRemota $rutaBinario -Destino $destinoLocal
    if (-not $ok) { return }

    # 4. Verificar hash SHA256
    $integro = Verificar-Hash-FTP -Usuario $ftpUser -Password $ftpPass -IP $ftpIP -RutaSHA256 $rutaSHA256 -ArchivoLocal $destinoLocal
    if (-not $integro) {
        Write-Host "[!] Instalacion cancelada por fallo de integridad." -ForegroundColor Red
        return
    }

    # 5. Instalar el binario descargado
    Write-Host "[*] Instalando $archivoElegido ..." -ForegroundColor Cyan

    if ($archivoElegido -match '\.msi$') {
        Start-Process msiexec.exe -ArgumentList "/i `"$destinoLocal`" /qn /norestart" -Wait
        Write-Host "[+] Instalacion .msi completada." -ForegroundColor Green

    } elseif ($archivoElegido -match '\.exe$') {
        Start-Process $destinoLocal -ArgumentList "/S /silent /quiet" -Wait
        Write-Host "[+] Instalacion .exe completada." -ForegroundColor Green

    } elseif ($archivoElegido -match '\.zip$') {
        $extractDir = "$tmpDir\$($archivoElegido -replace '\.zip$','')"
        Expand-Archive -Path $destinoLocal -DestinationPath $extractDir -Force
        Write-Host "[+] Archivo extraido en $extractDir" -ForegroundColor Green
        Write-Host "[!] Instalacion manual: revisa $extractDir para continuar." -ForegroundColor Yellow

    } else {
        Write-Host "[!] Formato no reconocido. Archivo en: $destinoLocal" -ForegroundColor Yellow
    }
}
