#!/bin/bash
# ============================================================
#  http_functions.sh  -  Practica 6 - Administracion de Sistema
#  Funciones para aprovisionamiento de servidores web en Linux
# ============================================================

# ── Colores ──────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Detectar gestor de paquetes ───────────────────────────────
detectar_gestor() {
    if command -v apt-get &>/dev/null; then
        echo "apt"
    elif command -v pacman &>/dev/null; then
        echo "pacman"
    else
        echo "unknown"
    fi
}

PKG_MANAGER=$(detectar_gestor)

# ── Utilidades generales ──────────────────────────────────────

mostrar_banner() {
    clear
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo -e "${CYAN} Despliegue Dinamico de Servicios HTTP Multi-Version ${NC}"
    echo -e "${CYAN}        Linux - Practica 6                           ${NC}"
    echo -e "${CYAN}-----------------------------------------------------${NC}"
    echo ""
}

validar_puerto() {
    local puerto=$1
    local reservados=(20 21 22 23 25 53 67 68 110 143 443 445 587 993 995 3306 3389 5985 5986 27017)

    if ! [[ "$puerto" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}[!] El puerto debe ser un numero.${NC}" >&2
        return 1
    fi

    if [ "$puerto" -lt 1 ] || [ "$puerto" -gt 65535 ]; then
        echo -e "${RED}[!] Puerto fuera de rango (1-65535).${NC}" >&2
        return 1
    fi

    for r in "${reservados[@]}"; do
        if [ "$puerto" -eq "$r" ]; then
            echo -e "${YELLOW}[!] Puerto $puerto reservado para otro servicio.${NC}" >&2
            return 1
        fi
    done

    if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
        echo -e "${RED}[!] El puerto $puerto ya esta en uso.${NC}" >&2
        return 1
    fi

    return 0
}

pedir_puerto() {
    local puerto
    while true; do
        read -rp "Ingresa el puerto de escucha (ej. 80, 8080, 8888): " puerto >&2
        puerto=$(echo "$puerto" | tr -d '[:space:]')
        if validar_puerto "$puerto"; then
            echo "$puerto"
            return 0
        fi
    done
}

configurar_firewall() {
    local puerto=$1

    if command -v ufw &>/dev/null; then
        ufw allow "$puerto"/tcp &>/dev/null
        echo -e "${GREEN}[+] Firewall UFW: puerto $puerto abierto.${NC}"
        if [ "$puerto" -ne 80 ]; then
            ufw deny 80/tcp &>/dev/null 2>&1 || true
            echo -e "${GREEN}[+] Firewall UFW: puerto 80 cerrado.${NC}"
        fi
    else
        iptables -A INPUT -p tcp --dport "$puerto" -j ACCEPT 2>/dev/null || true
        echo -e "${GREEN}[+] iptables: puerto $puerto abierto.${NC}"
        if [ "$puerto" -ne 80 ]; then
            iptables -A INPUT -p tcp --dport 80 -j DROP 2>/dev/null || true
        fi
    fi
}

crear_index_html() {
    local ruta=$1
    local servicio=$2
    local version=$3
    local puerto=$4
    local webroot=$5
    local usuario=$6
    local fecha
    fecha=$(date '+%Y-%m-%d %H:%M')

    mkdir -p "$(dirname "$ruta")"

    cat > "$ruta" << HTML
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>$servicio</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: Arial, sans-serif;
      min-height: 100vh;
      background: linear-gradient(135deg, #b2f0e8, #80deea, #e0f7fa, #b2ebf2);
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
      box-shadow: 0 8px 32px rgba(0,188,212,0.3);
    }
    h1 { font-size: 2rem; color: #2c3e50; margin-bottom: 8px; }
    .subtitle { color: #888; margin-bottom: 30px; font-size: 0.95rem; }
    hr { border: none; border-top: 2px solid #80deea; margin-bottom: 30px; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 10px 8px; font-size: 0.97rem; color: #333; }
    td:first-child { font-weight: bold; color: #00838f; width: 110px; }
  </style>
</head>
<body>
  <div class="card">
    <h1>$servicio</h1>
    <p class="subtitle">Despliegue exitoso &mdash; Linux</p>
    <hr>
    <table>
      <tr><td>Version</td><td>$version</td></tr>
      <tr><td>Puerto</td><td>${puerto}/tcp</td></tr>
      <tr><td>Webroot</td><td>$webroot</td></tr>
      <tr><td>Usuario</td><td>$usuario</td></tr>
      <tr><td>Fecha</td><td>$fecha</td></tr>
    </table>
  </div>
</body>
</html>
HTML
    echo -e "${GREEN}[+] index.html creado en $ruta${NC}"
}

# ── APACHE ────────────────────────────────────────────────────

obtener_versiones_apache() {
    echo -e "${CYAN}[*] Consultando versiones de Apache disponibles...${NC}" >&2
    local lts latest

    if [ "$PKG_MANAGER" = "apt" ]; then
        # Ubuntu/Debian: consulta dinámica al repositorio
        lts=$(apt-cache madison apache2 2>/dev/null | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="2.4.58-1ubuntu8"
        latest=$(apt-cache madison apache2 2>/dev/null | awk '{print $3}' | tail -1)
        [ -z "$latest" ] && latest="2.4.62-1ubuntu1"
    else
        # Arch Linux
        lts=$(pacman -Si apache 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="2.4.62-1"
        latest=$(pacman -Si apache 2>/dev/null | grep "^Version" | awk '{print $3}' | tail -1)
        [ -z "$latest" ] && latest="2.4.63-1"
    fi

    echo "${lts}|${latest}"
}

instalar_apache() {
    local version=$1
    local puerto=$2

    echo -e "${CYAN}[*] Instalando Apache...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        apt-get update -qq &>/dev/null
        apt-get install -y apache2 &>/dev/null
        local conf="/etc/apache2/ports.conf"
        local conf_main="/etc/apache2/apache2.conf"
        local sec_conf="/etc/apache2/conf-available/security.conf"
        local webroot="/var/www/html"
        local svc="apache2"

        # Cambiar puerto
        sed -i "s/Listen 80/Listen $puerto/g" "$conf"
        sed -i "s/Listen 443/# Listen 443/g" "$conf" 2>/dev/null || true
        # Cambiar VirtualHost
        sed -i "s/<VirtualHost \*:80>/<VirtualHost *:$puerto>/g" /etc/apache2/sites-enabled/000-default.conf 2>/dev/null || true

        # Ocultar version en security.conf
        if [ -f "$sec_conf" ]; then
            sed -i "s/^ServerTokens.*/ServerTokens Prod/" "$sec_conf"
            sed -i "s/^ServerSignature.*/ServerSignature Off/" "$sec_conf"
        else
            echo "ServerTokens Prod" >> "$conf_main"
            echo "ServerSignature Off" >> "$conf_main"
        fi

        # Habilitar mod_headers
        a2enmod headers &>/dev/null || true

        # Encabezados de seguridad y metodos
        if ! grep -q "X-Frame-Options" "$conf_main"; then
            cat >> "$conf_main" << 'EOF'

# Seguridad - Encabezados
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
TraceEnable Off

<Directory "/var/www/html">
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Directory>
EOF
        fi

    else
        # Arch Linux
        pacman -Sy --noconfirm apache &>/dev/null
        local conf="/etc/httpd/conf/httpd.conf"
        local webroot="/srv/http"
        local svc="httpd"

        sed -i "s/^Listen .*/Listen $puerto/" "$conf"

        if ! grep -q "ServerTokens" "$conf"; then
            echo "ServerTokens Prod" >> "$conf"
            echo "ServerSignature Off" >> "$conf"
        else
            sed -i "s/^ServerTokens.*/ServerTokens Prod/" "$conf"
            sed -i "s/^ServerSignature.*/ServerSignature Off/" "$conf"
        fi

        sed -i 's/#LoadModule headers_module/LoadModule headers_module/' "$conf"

        if ! grep -q "X-Frame-Options" "$conf"; then
            cat >> "$conf" << 'EOF'

# Seguridad - Encabezados
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-Content-Type-Options "nosniff"
TraceEnable Off

<Directory "/srv/http">
    <LimitExcept GET POST HEAD OPTIONS>
        Require all denied
    </LimitExcept>
</Directory>
EOF
        fi
    fi

    echo -e "${GREEN}[+] Apache configurado en puerto $puerto.${NC}"

    # Usuario y permisos
    local usuario_apache
    if id www-data &>/dev/null; then
        usuario_apache="www-data"
    elif id http &>/dev/null; then
        usuario_apache="http"
    else
        useradd -r -s /sbin/nologin -d /var/www www-data 2>/dev/null || true
        usuario_apache="www-data"
    fi

    mkdir -p "$webroot"
    chown -R "$usuario_apache:$usuario_apache" "$webroot"
    chmod 755 "$webroot"

    crear_index_html "$webroot/index.html" \
        "Apache HTTP Server" \
        "Version $version" \
        "$puerto" \
        "$webroot" \
        "$usuario_apache"

    configurar_firewall "$puerto"

    systemctl enable "$svc" &>/dev/null
    systemctl restart "$svc"

    if systemctl is-active --quiet "$svc"; then
        echo -e "${GREEN}[+] Apache corriendo en puerto $puerto.${NC}"
    else
        echo -e "${RED}[!] Error al iniciar Apache. Revisa: journalctl -xe${NC}"
    fi
}

# ── NGINX ─────────────────────────────────────────────────────

obtener_versiones_nginx() {
    echo -e "${CYAN}[*] Consultando versiones de Nginx disponibles...${NC}" >&2
    local lts latest

    if [ "$PKG_MANAGER" = "apt" ]; then
        lts=$(apt-cache madison nginx 2>/dev/null | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="1.24.0-2ubuntu7"
        latest=$(apt-cache policy nginx 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        [ -z "$latest" ] && latest="1.26.0-1ubuntu1"
    else
        lts=$(pacman -Si nginx 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="1.26.2-1"
        latest=$(pacman -Si nginx-mainline 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        [ -z "$latest" ] && latest="1.27.3-1"
    fi

    echo "${lts}|${latest}"
}

instalar_nginx() {
    local version=$1
    local puerto=$2
    local webroot

    echo -e "${CYAN}[*] Instalando Nginx...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        apt-get update -qq &>/dev/null
        apt-get install -y nginx &>/dev/null
        webroot="/var/www/html"
    else
        local paquete="nginx"
        if echo "$version" | grep -q "1\.27\|1\.29\|mainline"; then
            paquete="nginx-mainline"
        fi
        pacman -Sy --noconfirm "$paquete" &>/dev/null
        webroot="/usr/share/nginx/html"
    fi

    echo -e "${GREEN}[+] Nginx instalado.${NC}"

    local conf="/etc/nginx/nginx.conf"

    cat > "$conf" << NGINXCONF
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
        listen       $puerto;
        server_name  localhost;

        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        if (\$request_method ~ ^(TRACE|DELETE|TRACK)\$) {
            return 405;
        }

        location / {
            root   $webroot;
            index  index.html index.htm;
        }

        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   $webroot;
        }
    }
}
NGINXCONF

    echo -e "${GREEN}[+] Nginx configurado en puerto $puerto.${NC}"

    # Usuario dedicado
    if ! id nginx &>/dev/null; then
        useradd -r -s /sbin/nologin -d /var/www nginx 2>/dev/null || true
    fi
    local usuario_nginx="nginx"
    if id www-data &>/dev/null && [ "$PKG_MANAGER" = "apt" ]; then
        usuario_nginx="www-data"
        # Actualizar user en nginx.conf para Debian/Ubuntu
        sed -i "1s/^/user www-data;\n/" "$conf" 2>/dev/null || true
    fi

    mkdir -p "$webroot"
    chown -R "$usuario_nginx:$usuario_nginx" "$webroot"
    chmod 755 "$webroot"

    crear_index_html "$webroot/index.html" \
        "Nginx" \
        "Version $version" \
        "$puerto" \
        "$webroot" \
        "$usuario_nginx"

    configurar_firewall "$puerto"

    systemctl enable nginx &>/dev/null
    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}[+] Nginx corriendo en puerto $puerto.${NC}"
    else
        echo -e "${RED}[!] Error al iniciar Nginx. Revisa: journalctl -xe${NC}"
    fi
}

# ── TOMCAT ────────────────────────────────────────────────────

obtener_versiones_tomcat() {
    echo -e "${CYAN}[*] Consultando versiones de Tomcat disponibles...${NC}" >&2
    local lts latest

    if [ "$PKG_MANAGER" = "apt" ]; then
        lts=$(apt-cache madison tomcat10 2>/dev/null | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="10.1.28-1ubuntu1"
        latest=$(apt-cache policy tomcat10 2>/dev/null | grep "Candidate:" | awk '{print $2}')
        [ -z "$latest" ] && latest="10.1.33-1ubuntu1"
    else
        lts=$(pacman -Si tomcat10 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        [ -z "$lts" ] && lts="10.1.28-1"
        latest=$(pacman -Si tomcat11 2>/dev/null | grep "^Version" | awk '{print $3}' | head -1)
        [ -z "$latest" ] && latest="11.0.2-1"
    fi

    echo "${lts}|${latest}"
}

instalar_tomcat() {
    local version=$1
    local puerto=$2
    local tomcat_home
    local paquete
    local svc

    echo -e "${CYAN}[*] Instalando Tomcat...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        if echo "$version" | grep -q "11\."; then
            paquete="tomcat11"
        else
            paquete="tomcat10"
        fi
        apt-get update -qq &>/dev/null
        apt-get install -y "$paquete" &>/dev/null
        tomcat_home="/usr/share/$paquete"
        svc="$paquete"
    else
        if echo "$version" | grep -q "11\."; then
            paquete="tomcat11"
        else
            paquete="tomcat10"
        fi
        pacman -Sy --noconfirm "$paquete" &>/dev/null
        tomcat_home="/usr/share/$paquete"
        svc="$paquete"
    fi

    echo -e "${GREEN}[+] Tomcat instalado.${NC}"

    # ── Matar procesos jsvc/tomcat zombis antes de reconfigurar ──
    pkill -9 -f jsvc   2>/dev/null || true
    pkill -9 -f "$paquete" 2>/dev/null || true
    sleep 2
    rm -f "/var/run/${paquete}.pid"

    local conf="$tomcat_home/conf/server.xml"

    # Restaurar server.xml limpio desde el paquete para evitar corrupcion acumulada
    if pacman -Ql "$paquete" 2>/dev/null | grep -q "server.xml"; then
        pacman -S --noconfirm "$paquete" &>/dev/null || true
    fi

    # Webroot real en Arch esta en /var/lib/
    local webroot_real
    if [ -d "/var/lib/$paquete/webapps/ROOT" ]; then
        webroot_real="/var/lib/$paquete/webapps/ROOT"
    else
        webroot_real="$tomcat_home/webapps/ROOT"
    fi

    if [ -f "$conf" ]; then
        # BUG FIX: un solo sed para cambiar puerto del Connector HTTP
        # El sed anterior hacia dos pasadas y duplicaba el atributo port=""
        sed -i "s|<Connector port=\"8080\" protocol=\"HTTP/1.1\"|<Connector port=\"$puerto\" protocol=\"HTTP/1.1\"|" "$conf"

        # Ocultar version del servidor (server="" vacio en el elemento <Server>)
        sed -i 's|<Server port="8005" shutdown="SHUTDOWN">|<Server port="8005" shutdown="SHUTDOWN" server="">|' "$conf"

        echo -e "${GREEN}[+] Tomcat configurado en puerto $puerto.${NC}"
    else
        echo -e "${YELLOW}[!] No se encontro server.xml en $conf${NC}"
    fi

    # Crear directorios necesarios
    mkdir -p "$webroot_real"
    mkdir -p "/var/lib/$paquete/work"
    mkdir -p "/var/lib/$paquete/logs"
    mkdir -p "/var/tmp/$paquete/temp"

    # web.xml para servir index.html como bienvenida
    mkdir -p "$webroot_real/WEB-INF"
    cat > "$webroot_real/WEB-INF/web.xml" << 'WEBXML'
<?xml version="1.0" encoding="UTF-8"?>
<web-app xmlns="https://jakarta.ee/xml/ns/jakartaee"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
  xsi:schemaLocation="https://jakarta.ee/xml/ns/jakartaee
                      https://jakarta.ee/xml/ns/jakartaee/web-app_6_0.xsd"
  version="6.0"
  metadata-complete="true">
  <display-name>Practica 6</display-name>
  <welcome-file-list>
    <welcome-file>index.html</welcome-file>
  </welcome-file-list>
</web-app>
WEBXML

    rm -f "$webroot_real/index.jsp"

    crear_index_html "$webroot_real/index.html" \
        "Apache Tomcat" \
        "Version $version" \
        "$puerto" \
        "$webroot_real" \
        "$paquete"

    # Permisos para el usuario del servicio
    chown -R "$paquete:$paquete" "/var/lib/$paquete"
    chown -R "$paquete:$paquete" "/var/tmp/$paquete"
    chmod -R 750 "/var/lib/$paquete"

    configurar_firewall "$puerto"

    systemctl enable "$svc" &>/dev/null
    systemctl restart "$svc"

    # Esperar hasta 30s a que levante realmente
    local intentos=0
    while [ $intentos -lt 6 ]; do
        sleep 5
        if ss -tlnp 2>/dev/null | grep -q ":${puerto} "; then
            echo -e "${GREEN}[+] Tomcat corriendo en puerto $puerto.${NC}"
            return 0
        fi
        intentos=$((intentos + 1))
        echo -e "${YELLOW}[*] Esperando que Tomcat levante... ($((intentos*5))s)${NC}"
    done

    echo -e "${RED}[!] Tomcat no levanto en 30s. Revisa: journalctl -u $svc -n 20${NC}"
}

# ── Seleccion de version ──────────────────────────────────────

seleccionar_version() {
    local lts=$1
    local latest=$2
    local servidor=$3

    echo "" >&2
    echo -e "${CYAN}Versiones disponibles para $servidor:${NC}" >&2
    echo "  [1] LTS/Estable : $lts" >&2
    echo "  [2] Latest/Dev  : $latest" >&2
    echo "" >&2

    local sel
    while true; do
        read -rp "Selecciona una version [1-2]: " sel >&2
        sel=$(echo "$sel" | tr -d '[:space:]')
        if [[ "$sel" == "1" ]]; then
            echo "$lts"
            return 0
        elif [[ "$sel" == "2" ]]; then
            echo "$latest"
            return 0
        else
            echo -e "${RED}[!] Opcion invalida. Elige 1 o 2.${NC}" >&2
        fi
    done
}

# ── Menu principal ────────────────────────────────────────────

mostrar_menu() {
    echo "" >&2
    echo -e "${CYAN}Selecciona el servidor web a instalar:${NC}" >&2
    echo "  [1] Apache HTTP Server" >&2
    echo "  [2] Nginx" >&2
    echo "  [3] Tomcat" >&2
    echo "  [4] Salir" >&2
    echo "" >&2

    local op
    while true; do
        read -rp "Opcion: " op >&2
        op=$(echo "$op" | tr -d '[:space:]')
        if [[ "$op" =~ ^[1-4]$ ]]; then
            echo "$op"
            return 0
        else
            echo -e "${RED}[!] Opcion invalida. Elige entre 1 y 4.${NC}" >&2
        fi
    done
}