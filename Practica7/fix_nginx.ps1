$nginxConf = @"
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

    server {
        listen 80;
        server_name www.reprobados.com;
        return 301 https://`$host`$request_uri;
    }

    server {
        listen 443 ssl;
        server_name www.reprobados.com;

        ssl_certificate     C:/SSL/reprobados/Nginx/server_pem.crt;
        ssl_certificate_key C:/SSL/reprobados/Nginx/server.key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        location / {
            root   C:/tools/nginx-1.29.8/html;
            index  index.html index.htm;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root C:/tools/nginx-1.29.8/html;
        }
    }
}
"@

Set-Content -Path "C:\tools\nginx-1.29.8\conf\nginx.conf" -Value $nginxConf -Encoding ASCII
Write-Host "[+] nginx.conf actualizado correctamente." -ForegroundColor Green

# Convertir certificado DER a PEM si no existe
$pem = "C:\SSL\reprobados\Nginx\server_pem.crt"
$der = "C:\SSL\reprobados\Nginx\server.crt"
$openssl = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"

if (-not (Test-Path $pem)) {
    if (Test-Path $openssl) {
        & $openssl x509 -inform DER -in $der -out $pem
        Write-Host "[+] Certificado convertido a PEM." -ForegroundColor Green
    }
}

# Iniciar Nginx
$svc = Get-Service | Where-Object { $_.Name -like "*nginx*" -or $_.DisplayName -like "*nginx*" } | Select-Object -First 1
if ($svc) {
    Restart-Service $svc.Name -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    if ((Get-Service $svc.Name).Status -eq "Running") {
        Write-Host "[+] Nginx con SSL activo en puerto 443." -ForegroundColor Green
    } else {
        # Intentar iniciar directamente
        Start-Process "C:\tools\nginx-1.29.8\nginx.exe" -WorkingDirectory "C:\tools\nginx-1.29.8" -WindowStyle Hidden
        Start-Sleep -Seconds 3
        Write-Host "[+] Nginx iniciado directamente." -ForegroundColor Green
    }
} else {
    Start-Process "C:\tools\nginx-1.29.8\nginx.exe" -WorkingDirectory "C:\tools\nginx-1.29.8" -WindowStyle Hidden
    Start-Sleep -Seconds 3
    Write-Host "[+] Nginx iniciado directamente." -ForegroundColor Green
}
