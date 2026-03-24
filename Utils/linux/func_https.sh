#!/bin/bash

declare -A TOMCAT_RAMAS
TOMCAT_TOTAL=0
export TOMCAT_RAMAS
export TOMCAT_TOTAL

#!/bin/bash

# ── Firewall ──

get_firewall() {
    if command -v ufw &>/dev/null; then
        echo "ufw"
    elif command -v firewall-cmd &>/dev/null; then
        echo "firewalld"
    elif command -v iptables &>/dev/null; then
        echo "iptables"
    else
        echo "none"
    fi
}

set_firewall_rule() {
    local puerto=$1
    local fw
    fw=$(get_firewall)

    case $fw in
        ufw)
            ufw allow "$puerto"/tcp &>/dev/null
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="$puerto"/tcp &>/dev/null
            firewall-cmd --reload &>/dev/null
            ;;
        iptables)
            iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT
            ;;
        none)
            echo "[WARN] No se detecto firewall activo"
            ;;
    esac
}

remove_firewall_rule() {
    local puerto=$1
    local fw
    fw=$(get_firewall)

    case $fw in
        ufw)
            ufw delete allow "$puerto"/tcp &>/dev/null
            ;;
        firewalld)
            firewall-cmd --permanent --remove-port="$puerto"/tcp &>/dev/null
            firewall-cmd --reload &>/dev/null
            ;;
        iptables)
            iptables -D INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null
            ;;
    esac
}

# ── Validaciones ──

check_input() {
    local valor=$1
    local tipo=$2

    if [[ -z "$valor" ]]; then
        echo "[ERROR] El valor no puede estar vacio"
        return 1
    fi

    if [[ "$tipo" == "numero" && ! "$valor" =~ ^[0-9]+$ ]]; then
        echo "[ERROR] Solo se permiten numeros"
        return 1
    fi

    if [[ "$tipo" == "texto" && "$valor" =~ [^a-zA-Z0-9._-] ]]; then
        echo "[ERROR] Caracteres especiales no permitidos"
        return 1
    fi

    return 0
}

check_port() {
    local puerto=$1

    if ! check_input "$puerto" "numero"; then
        return 1
    fi

    if [[ "$puerto" -lt 1 || "$puerto" -gt 65535 ]]; then
        echo "[ERROR] Puerto fuera de rango (1-65535)"
        return 1
    fi

    local reservados=(22 25 53 443 3306 5432 6379 27017)
    for r in "${reservados[@]}"; do
        if [[ "$puerto" -eq "$r" ]]; then
            echo "[ERROR] Puerto $puerto reservado para otro servicio"
            return 1
        fi
    done

    if ss -tlnp | grep -q ":$puerto "; then
        local proceso
        proceso=$(ss -tlnp | grep ":$puerto " | awk '{print $NF}' | head -1)
        echo "[ERROR] Puerto $puerto en uso por: $proceso"
        return 1
    fi

    return 0
}

get_port() {
    local puerto
    while true; do
        read -rp "  Puerto de escucha [1-65535]: " puerto
        if check_port "$puerto"; then
            echo "$puerto"
            return 0
        fi
    done
}

# ── Usuario dedicado ──

create_service_user() {
    local usuario=$1
    local directorio=$2

    if ! id "$usuario" &>/dev/null; then
        useradd -r -s /sbin/nologin -d "$directorio" "$usuario"
    fi

    chown -R "$usuario":"$usuario" "$directorio"
    chmod -R 750 "$directorio"
}

# ── Apache ──

get_apache_versions() {
    echo "  Consultando versiones en repositorio..."
    local versiones
    versiones=$(pacman -Si apache 2>/dev/null | grep -E "^Version" | awk '{print $3}')

    if [[ -z "$versiones" ]]; then
        echo "[ERROR] No se pudo obtener versiones de apache"
        return 1
    fi

    echo "  Versiones disponibles:"
    local i=1
    while IFS= read -r v; do
        echo "  [ $i ] $v"
        ((i++))
    done <<< "$versiones"
}

install_apache() {
    local puerto=$1

    echo "  Instalando apache..."
    pacman -S --noconfirm apache &>/dev/null

    if ! pacman -Q apache &>/dev/null; then
        echo "[ERROR] Fallo la instalacion de apache"
        return 1
    fi

    set_apache_port "$puerto"
    set_apache_security
    create_service_user http /srv/http
    create_apache_index "$puerto"
    set_firewall_rule "$puerto"

    systemctl enable --now httpd &>/dev/null
    echo "[OK] Apache activo en puerto $puerto"
}

set_apache_port() {
    local puerto=$1
    local conf="/etc/httpd/conf/httpd.conf"

    sed -i "s/^Listen .*/Listen $puerto/" "$conf"
    sed -i "s/^ServerName .*/ServerName localhost:$puerto/" "$conf"
}

set_apache_security() {
    local conf="/etc/httpd/conf/httpd.conf"

    grep -q "ServerTokens" "$conf" || echo "ServerTokens Prod" >> "$conf"
    grep -q "ServerSignature" "$conf" || echo "ServerSignature Off" >> "$conf"

    sed -i "s/^ServerTokens.*/ServerTokens Prod/" "$conf"
    sed -i "s/^ServerSignature.*/ServerSignature Off/" "$conf"

    cat >> "$conf" <<'EOF'

<IfModule mod_headers.c>
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"
</IfModule>

<Location />
    <LimitExcept GET POST HEAD>
        Require all denied
    </LimitExcept>
</Location>
EOF
}

create_apache_index() {
    local puerto=$1
    local version
    version=$(pacman -Q apache 2>/dev/null | awk '{print $2}')
    local webroot="/srv/http"

    mkdir -p "$webroot"
    cat > "$webroot/index.html" <<HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Apache</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: sans-serif; background: #f0f4f8; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .card { background: white; border-radius: 12px; padding: 2.5rem 3rem; max-width: 480px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.08); text-align: center; }
  .logo { font-size: 3rem; margin-bottom: 1rem; }
  h1 { font-size: 1.5rem; color: #1a202c; margin-bottom: 0.25rem; }
  .version { color: #718096; font-size: 0.95rem; margin-bottom: 1.5rem; }
  .status { display: inline-block; background: #c6f6d5; color: #276749; padding: 0.3rem 1rem; border-radius: 99px; font-size: 0.85rem; font-weight: 600; margin-bottom: 1.5rem; }
  .info { background: #f7fafc; border-radius: 8px; padding: 1rem 1.5rem; text-align: left; }
  .info-row { display: flex; justify-content: space-between; padding: 0.4rem 0; font-size: 0.9rem; border-bottom: 1px solid #e2e8f0; }
  .info-row:last-child { border-bottom: none; }
  .label { color: #718096; }
  .value { color: #2d3748; font-weight: 500; }
</style>
</head>
<body>
<div class="card">
  <div class="logo">🪶</div>
  <h1>Apache HTTP Server</h1>
  <div class="version">Version APACHE_VERSION</div>
  <div class="status">ACTIVO</div>
  <div class="info">
    <div class="info-row"><span class="label">Servidor</span><span class="value">Apache</span></div>
    <div class="info-row"><span class="label">Version</span><span class="value">APACHE_VERSION</span></div>
    <div class="info-row"><span class="label">Puerto</span><span class="value">APACHE_PUERTO</span></div>
    <div class="info-row"><span class="label">Sistema</span><span class="value">Arch Linux</span></div>
  </div>
</div>
</body>
</html>
HTMLEOF
    sed -i "s/APACHE_VERSION/$version/g; s/APACHE_PUERTO/$puerto/g" "$webroot/index.html"
    chown http:http "$webroot/index.html"
    chmod 644 "$webroot/index.html"
}

# ── Nginx ──

get_nginx_versions() {
    echo "  Consultando versiones en repositorio..."
    local versiones
    versiones=$(pacman -Si nginx 2>/dev/null | grep -E "^Version" | awk '{print $3}')

    if [[ -z "$versiones" ]]; then
        echo "[ERROR] No se pudo obtener versiones de nginx"
        return 1
    fi

    echo "  Versiones disponibles:"
    local i=1
    while IFS= read -r v; do
        echo "  [ $i ] $v"
        ((i++))
    done <<< "$versiones"
}

install_nginx() {
    local puerto=$1

    echo "  Instalando nginx..."
    pacman -S --noconfirm nginx &>/dev/null

    if ! pacman -Q nginx &>/dev/null; then
        echo "[ERROR] Fallo la instalacion de nginx"
        return 1
    fi

    create_service_user nginx /usr/share/nginx/html
    chmod 755 /usr/share/nginx/html
    set_nginx_port "$puerto"
    set_nginx_security
    create_nginx_index "$puerto"
    set_firewall_rule "$puerto"

    systemctl enable --now nginx &>/dev/null
    echo "[OK] Nginx activo en puerto $puerto"
}

set_nginx_config() {
    local puerto=$1
    local webroot="/usr/share/nginx/html"

    cat > /etc/nginx/nginx.conf << NGINXEOF
user http;
worker_processes 1;

events {
    worker_connections 1024;
}

http {
    server_tokens off;
    include       mime.types;
    default_type  application/octet-stream;
    sendfile      on;
    keepalive_timeout 65;

    server {
        listen ${puerto};
        server_name localhost;

        location / {
            root ${webroot};
            index index.html;
            limit_except GET POST HEAD { deny all; }
            add_header X-Frame-Options "SAMEORIGIN" always;
            add_header X-Content-Type-Options "nosniff" always;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            root ${webroot};
        }
    }
}
NGINXEOF
}

set_nginx_port() {
    local puerto=$1
    set_nginx_config "$puerto"
}

set_nginx_security() {
    :
}

create_nginx_index() {
    local puerto=$1
    local version
    version=$(pacman -Q nginx 2>/dev/null | awk '{print $2}')
    local webroot="/usr/share/nginx/html"

    mkdir -p "$webroot"
    cat > "$webroot/index.html" <<HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Nginx</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: sans-serif; background: #f0f9f0; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .card { background: white; border-radius: 12px; padding: 2.5rem 3rem; max-width: 480px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.08); text-align: center; }
  .logo { font-size: 3rem; margin-bottom: 1rem; }
  h1 { font-size: 1.5rem; color: #1a202c; margin-bottom: 0.25rem; }
  .version { color: #718096; font-size: 0.95rem; margin-bottom: 1.5rem; }
  .status { display: inline-block; background: #c6f6d5; color: #276749; padding: 0.3rem 1rem; border-radius: 99px; font-size: 0.85rem; font-weight: 600; margin-bottom: 1.5rem; }
  .info { background: #f7fafc; border-radius: 8px; padding: 1rem 1.5rem; text-align: left; }
  .info-row { display: flex; justify-content: space-between; padding: 0.4rem 0; font-size: 0.9rem; border-bottom: 1px solid #e2e8f0; }
  .info-row:last-child { border-bottom: none; }
  .label { color: #718096; }
  .value { color: #2d3748; font-weight: 500; }
</style>
</head>
<body>
<div class="card">
  <div class="logo">⚡</div>
  <h1>Nginx Web Server</h1>
  <div class="version">Version NGINX_VERSION</div>
  <div class="status">ACTIVO</div>
  <div class="info">
    <div class="info-row"><span class="label">Servidor</span><span class="value">Nginx</span></div>
    <div class="info-row"><span class="label">Version</span><span class="value">NGINX_VERSION</span></div>
    <div class="info-row"><span class="label">Puerto</span><span class="value">NGINX_PUERTO</span></div>
    <div class="info-row"><span class="label">Sistema</span><span class="value">Arch Linux</span></div>
  </div>
</div>
</body>
</html>
HTMLEOF
    sed -i "s/NGINX_VERSION/$version/g; s/NGINX_PUERTO/$puerto/g" "$webroot/index.html"
    chown nginx:nginx "$webroot/index.html"
    chmod 644 "$webroot/index.html"
}

# ── Tomcat ──

declare -A TOMCAT_RAMAS
TOMCAT_TOTAL=0

get_tomcat_versions() {
    echo "  Consultando versiones en Apache oficial..."

    local url="https://downloads.apache.org/tomcat/"
    local versiones

    versiones=$(curl -s "$url" | grep -oP 'tomcat-\K[0-9]+' | sort -un)

    if [[ -z "$versiones" ]]; then
        echo "[ERROR] No se pudo conectar a downloads.apache.org"
        return 1
    fi

    TOMCAT_RAMAS=()
    local i=1

    echo "  Versiones disponibles:"
    while IFS= read -r rama; do
        local ultima
        ultima=$(curl -s "${url}tomcat-${rama}/" | grep -oP "v\K[0-9]+\.[0-9]+\.[0-9]+" | sort -V | tail -1)
        echo "  [ $i ] Tomcat $rama  ->  $ultima"
        TOMCAT_RAMAS[$i]="$rama:$ultima"
        ((i++))
    done <<< "$versiones"

    TOMCAT_TOTAL=$((i - 1))
}

install_tomcat() {
    local rama=$1
    local version=$2
    local puerto=$3

    local directorio="/opt/tomcat"
    local url="https://downloads.apache.org/tomcat/tomcat-${rama}/v${version}/bin/apache-tomcat-${version}.tar.gz"

    echo "  Descargando Tomcat $version..."
    mkdir -p "$directorio"
    curl -sL "$url" -o /tmp/tomcat.tar.gz

    if [[ ! -s /tmp/tomcat.tar.gz ]]; then
        echo "[ERROR] Fallo la descarga de Tomcat"
        return 1
    fi

    tar -xzf /tmp/tomcat.tar.gz -C "$directorio" --strip-components=1
    rm -f /tmp/tomcat.tar.gz

    create_service_user tomcat "$directorio"
    set_tomcat_port "$puerto" "$directorio"
    set_tomcat_security "$directorio"
    create_tomcat_index "$version" "$puerto" "$directorio"
    create_tomcat_service tomcat "$directorio"
    set_firewall_rule "$puerto"

    systemctl enable --now tomcat &>/dev/null
    echo "[OK] Tomcat activo en puerto $puerto"
}

set_tomcat_port() {
    local puerto=$1
    local directorio=$2
    local conf="$directorio/conf/server.xml"

    sed -i "s/port=\"8080\"/port=\"$puerto\"/" "$conf"
    sed -i "s/port=\"8005\"/port=\"8006\"/" "$conf"
}

set_tomcat_security() {
    local directorio=$1
    local conf="$directorio/conf/server.xml"
    local webxml="$directorio/conf/web.xml"

    sed -i 's/<Connector/<Connector server="Apache" /' "$conf"

    sed -i 's|</web-app>||' "$webxml"
    cat >> "$webxml" <<'EOF'

<filter>
    <filter-name>httpHeaderSecurity</filter-name>
    <filter-class>org.apache.catalina.filters.HttpHeaderSecurityFilter</filter-class>
    <init-param>
        <param-name>antiClickJackingOption</param-name>
        <param-value>SAMEORIGIN</param-value>
    </init-param>
</filter>
<filter-mapping>
    <filter-name>httpHeaderSecurity</filter-name>
    <url-pattern>/*</url-pattern>
</filter-mapping>
</web-app>
EOF
}

create_tomcat_index() {
    local version=$1
    local puerto=$2
    local directorio=$3
    local webroot="$directorio/webapps/ROOT"

    mkdir -p "$webroot"
    cat > "$webroot/index.html" <<HTMLEOF
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Tomcat</title>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body { font-family: sans-serif; background: #fff8f0; display: flex; align-items: center; justify-content: center; min-height: 100vh; }
  .card { background: white; border-radius: 12px; padding: 2.5rem 3rem; max-width: 480px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.08); text-align: center; }
  .logo { font-size: 3rem; margin-bottom: 1rem; }
  h1 { font-size: 1.5rem; color: #1a202c; margin-bottom: 0.25rem; }
  .version { color: #718096; font-size: 0.95rem; margin-bottom: 1.5rem; }
  .status { display: inline-block; background: #c6f6d5; color: #276749; padding: 0.3rem 1rem; border-radius: 99px; font-size: 0.85rem; font-weight: 600; margin-bottom: 1.5rem; }
  .info { background: #f7fafc; border-radius: 8px; padding: 1rem 1.5rem; text-align: left; }
  .info-row { display: flex; justify-content: space-between; padding: 0.4rem 0; font-size: 0.9rem; border-bottom: 1px solid #e2e8f0; }
  .info-row:last-child { border-bottom: none; }
  .label { color: #718096; }
  .value { color: #2d3748; font-weight: 500; }
</style>
</head>
<body>
<div class="card">
  <div class="logo">🐱</div>
  <h1>Apache Tomcat</h1>
  <div class="version">Version TOMCAT_VERSION</div>
  <div class="status">ACTIVO</div>
  <div class="info">
    <div class="info-row"><span class="label">Servidor</span><span class="value">Tomcat</span></div>
    <div class="info-row"><span class="label">Version</span><span class="value">TOMCAT_VERSION</span></div>
    <div class="info-row"><span class="label">Puerto</span><span class="value">TOMCAT_PUERTO</span></div>
    <div class="info-row"><span class="label">Sistema</span><span class="value">Arch Linux</span></div>
  </div>
</div>
</body>
</html>
HTMLEOF
    sed -i "s/TOMCAT_VERSION/$version/g; s/TOMCAT_PUERTO/$puerto/g" "$webroot/index.html"
    chown -R tomcat:tomcat "$webroot"
    chmod 644 "$webroot/index.html"
}

create_tomcat_service() {
    local usuario=$1
    local directorio=$2

    # Dar permisos de ejecucion a los scripts de Tomcat
    chmod +x "$directorio"/bin/*.sh

    # Detectar JAVA_HOME real
    local java_home
    local java_home
    java_home=$(find /usr/lib/jvm -maxdepth 1 -type d -name "java-*-openjdk" -print0 2>/dev/null | sort -zV | tr "\0" "\n" | tail -1)
    [[ -z "$java_home" ]] && java_home=$(find /usr/lib/jvm -maxdepth 1 -type l -name "default" -exec readlink -f {} \; 2>/dev/null | tail -1)
    [[ -z "$java_home" ]] && java_home="/usr/lib/jvm/default"

    cat > /etc/systemd/system/tomcat.service <<EOF
[Unit]
Description=Apache Tomcat
After=network.target

[Service]
Type=forking
User=$usuario
Group=$usuario
Environment=JAVA_HOME=$java_home
Environment=CATALINA_HOME=$directorio
Environment=CATALINA_PID=$directorio/temp/tomcat.pid
ExecStart=$directorio/bin/startup.sh
ExecStop=$directorio/bin/shutdown.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
}