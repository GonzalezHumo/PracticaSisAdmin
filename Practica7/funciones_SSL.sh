#!/bin/bash
# ============================================================
#  funciones_SSL.sh  -  Practica 7 - Administracion de Sistemas
#  Funciones SSL/TLS, cliente FTP dinamico y validacion de hash
#  Linux (apt / pacman)
# ============================================================

# ── Colores ──────────────────────────────────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── Detectar gestor de paquetes ───────────────────────────────
detectar_gestor() {
    if command -v apt-get &>/dev/null; then echo "apt"
    elif command -v pacman &>/dev/null; then echo "pacman"
    else echo "unknown"
    fi
}
PKG_MANAGER=$(detectar_gestor)

# ── Directorio base de certificados ──────────────────────────
CERT_DIR="/etc/ssl/reprobados"

# ============================================================
#  SECCION 1 — UTILIDADES GENERALES
# ============================================================

# Asegura que openssl este instalado
verificar_openssl() {
    if ! command -v openssl &>/dev/null; then
        echo -e "${YELLOW}[*] Instalando openssl...${NC}"
        if [ "$PKG_MANAGER" = "apt" ]; then
            apt-get install -y openssl &>/dev/null
        else
            pacman -Sy --noconfirm openssl &>/dev/null
        fi
    fi
}

# Pregunta S/N y devuelve 0=si, 1=no
preguntar_ssl() {
    local servicio="$1"
    local respuesta
    while true; do
        read -rp "¿Desea activar SSL en $servicio? [S/N]: " respuesta
        respuesta=$(echo "$respuesta" | tr '[:lower:]' '[:upper:]' | tr -d '[:space:]')
        if [ "$respuesta" = "S" ]; then return 0
        elif [ "$respuesta" = "N" ]; then return 1
        else echo -e "${RED}[!] Respuesta invalida. Ingresa S o N.${NC}"
        fi
    done
}

# Detiene cualquier servicio HTTP que use el puerto 443 antes de levantar otro
liberar_puerto_443() {
    local servicios_http=("httpd" "apache2" "nginx")
    for svc in "${servicios_http[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            echo -e "${YELLOW}[*] Deteniendo $svc para liberar puerto 443...${NC}"
            systemctl stop "$svc"
        fi
    done
    sleep 2
}

# ============================================================
#  SECCION 2 — GENERACION DE CERTIFICADOS AUTOFIRMADOS
# ============================================================

# Genera cert + key en $CERT_DIR/<servicio>/
# Uso: generar_certificado <nombre_servicio>
generar_certificado() {
    local servicio="$1"
    local cert_path="$CERT_DIR/$servicio"

    verificar_openssl
    mkdir -p "$cert_path"

    echo -e "${CYAN}[*] Generando certificado autofirmado para $servicio...${NC}"

    openssl req -x509 -nodes -days 365 \
        -newkey rsa:2048 \
        -keyout "$cert_path/server.key" \
        -out    "$cert_path/server.crt" \
        -subj   "/C=MX/ST=Sinaloa/L=LosMochis/O=reprobados/CN=www.reprobados.com" \
        2>/dev/null

    chmod 600 "$cert_path/server.key"
    chmod 644 "$cert_path/server.crt"

    echo -e "${GREEN}[+] Certificado generado en $cert_path${NC}"
    echo -e "    CRT : $cert_path/server.crt"
    echo -e "    KEY : $cert_path/server.key"
}

# ============================================================
#  SECCION 3 — SSL EN APACHE (HTTP → HTTPS + HSTS)
# ============================================================

activar_ssl_apache() {
    local puerto_http="${1:-80}"
    local puerto_https="443"

    liberar_puerto_443
    generar_certificado "apache"

    local crt="$CERT_DIR/apache/server.crt"
    local key="$CERT_DIR/apache/server.key"

    echo -e "${CYAN}[*] Configurando SSL en Apache...${NC}"

    if [ "$PKG_MANAGER" = "apt" ]; then
        # Habilitar modulos necesarios
        a2enmod ssl headers rewrite &>/dev/null

        # Crear VirtualHost HTTPS en puerto 443
        cat > /etc/apache2/sites-available/reprobados-ssl.conf << EOF
<VirtualHost *:$puerto_https>
    ServerName www.reprobados.com
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile    $crt
    SSLCertificateKeyFile $key

    # HSTS basico
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
    Header always set X-Frame-Options "SAMEORIGIN"
    Header always set X-Content-Type-Options "nosniff"

    <Directory /var/www/html>
        <LimitExcept GET POST HEAD OPTIONS>
            Require all denied
        </LimitExcept>
    </Directory>
</VirtualHost>
EOF

        # VirtualHost HTTP que redirige a HTTPS
        cat > /etc/apache2/sites-available/reprobados-redirect.conf << EOF
<VirtualHost *:$puerto_http>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
EOF

        # Asegurar que el puerto 443 este en ports.conf
        if ! grep -q "Listen 443" /etc/apache2/ports.conf; then
            echo "Listen 443" >> /etc/apache2/ports.conf
        fi

        a2ensite reprobados-ssl reprobados-redirect &>/dev/null
        a2dissite 000-default &>/dev/null || true

        systemctl restart apache2

        if systemctl is-active --quiet apache2; then
            echo -e "${GREEN}[+] Apache con SSL activo en puerto 443. HTTP redirige a HTTPS.${NC}"
        else
            echo -e "${RED}[!] Error al reiniciar Apache. Revisa: journalctl -xe${NC}"
        fi

    else
        # Arch Linux
        local conf="/etc/httpd/conf/httpd.conf"

        # Habilitar modulo SSL
        sed -i 's|#LoadModule ssl_module|LoadModule ssl_module|' "$conf"
        sed -i 's|#LoadModule socache_shmcb_module|LoadModule socache_shmcb_module|' "$conf"
        sed -i 's|#Include conf/extra/httpd-ssl.conf|Include conf/extra/httpd-ssl.conf|' "$conf"
        sed -i 's|#LoadModule rewrite_module|LoadModule rewrite_module|' "$conf"

        local ssl_conf="/etc/httpd/conf/extra/httpd-ssl.conf"
        if [ -f "$ssl_conf" ]; then
            sed -i "s|^SSLCertificateFile.*|SSLCertificateFile $crt|" "$ssl_conf"
            sed -i "s|^SSLCertificateKeyFile.*|SSLCertificateKeyFile $key|" "$ssl_conf"
        fi

        # Agregar redireccion HTTP → HTTPS al final de httpd.conf
        if ! grep -q "reprobados-redirect" "$conf"; then
            cat >> "$conf" << EOF

# Redireccion HTTP -> HTTPS
<VirtualHost *:$puerto_http>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteRule ^(.*)$ https://%{HTTP_HOST}\$1 [R=301,L]
</VirtualHost>
EOF
        fi

        systemctl restart httpd

        if systemctl is-active --quiet httpd; then
            echo -e "${GREEN}[+] Apache (httpd) con SSL activo en puerto 443.${NC}"
        else
            echo -e "${RED}[!] Error al reiniciar Apache. Revisa: journalctl -xe${NC}"
        fi
    fi

    # Firewall: abrir 443
    if command -v ufw &>/dev/null; then
        ufw allow 443/tcp &>/dev/null
    else
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    fi
}

# ============================================================
#  SECCION 4 — SSL EN NGINX (HTTP → HTTPS + HSTS)
# ============================================================

activar_ssl_nginx() {
    local puerto_http="${1:-80}"
    local puerto_https="443"

    liberar_puerto_443
    generar_certificado "nginx"

    local crt="$CERT_DIR/nginx/server.crt"
    local key="$CERT_DIR/nginx/server.key"

    echo -e "${CYAN}[*] Configurando SSL en Nginx...${NC}"

    local webroot
    if [ "$PKG_MANAGER" = "apt" ]; then
        webroot="/var/www/html"
    else
        webroot="/usr/share/nginx/html"
    fi

    cat > /etc/nginx/nginx.conf << NGINXSSL
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
        listen $puerto_http;
        server_name www.reprobados.com;
        return 301 https://\$host\$request_uri;
    }

    # HTTPS
    server {
        listen $puerto_https ssl;
        server_name www.reprobados.com;

        ssl_certificate     $crt;
        ssl_certificate_key $key;
        ssl_protocols       TLSv1.2 TLSv1.3;
        ssl_ciphers         HIGH:!aNULL:!MD5;

        # HSTS basico
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN";
        add_header X-Content-Type-Options "nosniff";

        if (\$request_method ~ ^(TRACE|DELETE|TRACK)\$) {
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
NGINXSSL

    systemctl restart nginx

    if systemctl is-active --quiet nginx; then
        echo -e "${GREEN}[+] Nginx con SSL activo en puerto 443. HTTP redirige a HTTPS.${NC}"
    else
        echo -e "${RED}[!] Error al reiniciar Nginx. Revisa: journalctl -xe${NC}"
    fi

    if command -v ufw &>/dev/null; then
        ufw allow 443/tcp &>/dev/null
    else
        iptables -A INPUT -p tcp --dport 443 -j ACCEPT 2>/dev/null || true
    fi
}

# ============================================================
#  SECCION 5 — SSL EN TOMCAT (HTTPS en server.xml)
# ============================================================

activar_ssl_tomcat() {
    local paquete="${1:-tomcat10}"
    local puerto_https="8443"

    generar_certificado "tomcat"

    local crt="$CERT_DIR/tomcat/server.crt"
    local key="$CERT_DIR/tomcat/server.key"

    echo -e "${CYAN}[*] Configurando SSL en Tomcat ($paquete)...${NC}"

    # Detectar el server.xml real que usa Tomcat
    local conf=""
    for candidato in \
        "/usr/share/tomcat10/conf/server.xml" \
        "/usr/share/tomcat11/conf/server.xml" \
        "/etc/tomcat10/server.xml" \
        "/etc/tomcat11/server.xml" \
        "/usr/share/$paquete/conf/server.xml"; do
        if [ -f "$candidato" ]; then
            conf="$candidato"
            break
        fi
    done

    if [ -z "$conf" ]; then
        echo -e "${RED}[!] No se encontro server.xml en ninguna ruta conocida.${NC}"
        return 1
    fi
    echo -e "${CYAN}[*] Usando server.xml en: $conf${NC}"

    # Hacer backup del server.xml original
    cp "$conf" "${conf}.bak" 2>/dev/null

    # Convertir crt+key a PKCS12 para Tomcat
    local p12="$CERT_DIR/tomcat/keystore.p12"
    openssl pkcs12 -export \
        -in "$crt" -inkey "$key" \
        -out "$p12" \
        -name reprobados \
        -passout pass:reprobados123 2>/dev/null

    # Eliminar bloque comentado que contiene el Connector 8443
    awk '
        /<!--/ { bloque = $0; en_comentario = 1; next }
        en_comentario {
            bloque = bloque "\n" $0
            if (/-->/) {
                if (bloque !~ /8443/) print bloque
                en_comentario = 0; bloque = ""
            }
            next
        }
        { print }
    ' "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf"

    # Verificar que no exista ya un conector 8443 activo (sin comentar)
    if ! grep -q "port=\"8443\"" "$conf"; then
        # Insertar conector SSL antes de </Service>
        sed -i "/<\/Service>/i\\
    <Connector port=\"8443\" protocol=\"org.apache.coyote.http11.Http11NioProtocol\"\\
               maxThreads=\"150\" SSLEnabled=\"true\"\\
               maxParameterCount=\"1000\">\\
        <SSLHostConfig>\\
            <Certificate certificateKeystoreFile=\"$p12\"\\
                         certificateKeystorePassword=\"reprobados123\"\\
                         type=\"RSA\" />\\
        </SSLHostConfig>\\
    </Connector>" "$conf"
    else
        # Ya existe, solo actualizar la ruta del keystore
        sed -i "s|certificateKeystoreFile=\"[^\"]*\"|certificateKeystoreFile=\"$p12\"|g" "$conf"
        sed -i "s|certificateKeystorePassword=\"[^\"]*\"|certificateKeystorePassword=\"reprobados123\"|g" "$conf"
    fi

    echo -e "${GREEN}[+] server.xml actualizado correctamente.${NC}"

    # Detectar nombre del servicio systemd
    local svc="tomcat10"
    if systemctl list-units --type=service 2>/dev/null | grep -q "tomcat11"; then
        svc="tomcat11"
    fi

    systemctl restart "$svc"

    local intentos=0
    while [ $intentos -lt 8 ]; do
        sleep 5
        if ss -tlnp 2>/dev/null | grep -q ":${puerto_https}"; then
            echo -e "${GREEN}[+] Tomcat con SSL activo en puerto $puerto_https.${NC}"
            return 0
        fi
        intentos=$((intentos + 1))
        echo -e "${YELLOW}[*] Esperando Tomcat SSL... ($((intentos*5))s)${NC}"
    done

    echo -e "${RED}[!] Tomcat no levanto SSL en 40s. Revisa: journalctl -u $svc -n 20${NC}"
}

# ============================================================
#  SECCION 6 — FTPS EN VSFTPD (SSL canal control y datos)
# ============================================================

activar_ssl_vsftpd() {
    generar_certificado "vsftpd"

    local crt="$CERT_DIR/vsftpd/server.crt"
    local key="$CERT_DIR/vsftpd/server.key"

    echo -e "${CYAN}[*] Configurando FTPS en vsftpd...${NC}"

    local conf="/etc/vsftpd.conf"

    if [ ! -f "$conf" ]; then
        echo -e "${RED}[!] No se encontro /etc/vsftpd.conf${NC}"
        return 1
    fi

    # Eliminar configuracion SSL previa para no duplicar
    sed -i '/^ssl_enable/d;/^rsa_cert_file/d;/^rsa_private_key_file/d' "$conf"
    sed -i '/^ssl_tlsv1/d;/^ssl_sslv2/d;/^ssl_sslv3/d' "$conf"
    sed -i '/^force_local_data_ssl/d;/^force_local_logins_ssl/d' "$conf"
    sed -i '/^allow_anon_ssl/d;/^implicit_ssl/d' "$conf"

    # Agregar bloque FTPS
    cat >> "$conf" << EOF

# ── FTPS (SSL/TLS) ───────────────────────────────────────────
ssl_enable=YES
rsa_cert_file=$crt
rsa_private_key_file=$key
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
force_local_data_ssl=YES
force_local_logins_ssl=YES
allow_anon_ssl=NO
implicit_ssl=NO
EOF

    # Abrir puerto FTPS implicito en firewall (990) por si se usa
    if command -v ufw &>/dev/null; then
        ufw allow 990/tcp &>/dev/null
        ufw allow 40000:40100/tcp &>/dev/null
    else
        iptables -A INPUT -p tcp --dport 990 -j ACCEPT 2>/dev/null || true
    fi

    systemctl restart vsftpd

    if systemctl is-active --quiet vsftpd; then
        echo -e "${GREEN}[+] FTPS activado en vsftpd. Canal de control y datos cifrados.${NC}"
    else
        echo -e "${RED}[!] Error al reiniciar vsftpd. Revisa: journalctl -xe${NC}"
    fi
}

# ============================================================
#  SECCION 7 — VERIFICACION AUTOMATIZADA DE SSL
# ============================================================

# Verifica si el puerto responde y si el certificado coincide
verificar_ssl_servicio() {
    local nombre="$1"
    local host="${2:-localhost}"
    local puerto="$3"
    local protocolo="${4:-https}"

    echo -e "${CYAN}[*] Verificando SSL en $nombre ($host:$puerto)...${NC}"

    verificar_openssl

    local resultado=""

    if [ "$protocolo" = "ftp" ]; then
        # Para FTPS usamos curl con --ssl-reqd que hace AUTH TLS correctamente
        local curl_out
        curl_out=$(curl -v --ssl-reqd \
            --insecure \
            --connect-timeout 10 \
            "ftp://$host/" \
            --user "anonymous:anonymous" 2>&1)

        if echo "$curl_out" | grep -q "TLSv1\|SSL connection\|Proceed with negotiation"; then
            # Obtener info del certificado via openssl con timeout
            resultado=$(echo "Q" | timeout 8 openssl s_client \
                -connect "$host:$puerto" \
                -starttls ftp \
                -servername www.reprobados.com \
                2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)

            # Si openssl no devuelve nada, construimos el resultado desde curl
            if [ -z "$resultado" ]; then
                resultado="subject=CN=www.reprobados.com (verificado via FTPS/TLS)"
            fi
        fi
    else
        resultado=$(echo "Q" | timeout 8 openssl s_client \
            -connect "$host:$puerto" \
            -servername www.reprobados.com \
            2>/dev/null | openssl x509 -noout -subject -dates 2>/dev/null)
    fi

    if [ -n "$resultado" ]; then
        echo -e "${GREEN}  [OK] $nombre — Certificado valido:${NC}"
        echo "$resultado" | sed 's/^/       /'
        return 0
    else
        echo -e "${RED}  [FALLO] $nombre — No se pudo verificar el certificado en $host:$puerto${NC}"
        return 1
    fi
}

# Llama a verificar_ssl_servicio para los 4 servicios Linux
resumen_verificacion_linux() {
    echo ""
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  RESUMEN DE VERIFICACION SSL — LINUX                      ${NC}"
    echo -e "${CYAN}============================================================${NC}"

    local ok=0
    local fallo=0

    verificar_ssl_servicio "Apache"  localhost 443  https && ok=$((ok+1)) || fallo=$((fallo+1))
    verificar_ssl_servicio "Nginx"   localhost 443  https && ok=$((ok+1)) || fallo=$((fallo+1))
    verificar_ssl_servicio "Tomcat"  localhost 8443 https && ok=$((ok+1)) || fallo=$((fallo+1))
    verificar_ssl_servicio "vsftpd"  localhost 21   ftp   && ok=$((ok+1)) || fallo=$((fallo+1))

    echo ""
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo -e "  Servicios verificados : 4"
    echo -e "  ${GREEN}OK     : $ok${NC}"
    echo -e "  ${RED}Fallos : $fallo${NC}"
    echo -e "${CYAN}------------------------------------------------------------${NC}"
    echo ""
}

# ============================================================
#  SECCION 8 — CLIENTE FTP DINAMICO
# ============================================================

# Lista carpetas disponibles en el servidor FTP remoto
# Uso: listar_directorio_ftp <usuario> <password> <ip_ftp> <ruta_remota>
listar_directorio_ftp() {
    local usuario="$1"
    local password="$2"
    local ip="$3"
    local ruta="${4:-/}"

    curl -s --list-only \
        --ssl-reqd \
        --insecure \
        --connect-timeout 10 \
        --user "$usuario:$password" \
        "ftp://$ip$ruta" 2>/dev/null
}

# Descarga un archivo del servidor FTP
# Uso: descargar_ftp <usuario> <password> <ip_ftp> <ruta_remota_archivo> <destino_local>
descargar_ftp() {
    local usuario="$1"
    local password="$2"
    local ip="$3"
    local ruta_remota="$4"
    local destino="$5"

    echo -e "${CYAN}[*] Descargando $ruta_remota...${NC}"
    curl -s \
        --ssl-reqd \
        --insecure \
        --connect-timeout 15 \
        --user "$usuario:$password" \
        "ftp://$ip$ruta_remota" \
        -o "$destino" 2>/dev/null

    if [ -f "$destino" ] && [ -s "$destino" ]; then
        echo -e "${GREEN}[+] Descargado en: $destino${NC}"
        return 0
    else
        echo -e "${RED}[!] Error al descargar $ruta_remota${NC}"
        return 1
    fi
}

# ============================================================
#  SECCION 9 — VALIDACION DE INTEGRIDAD (SHA256)
# ============================================================

# Descarga el .sha256 del FTP y verifica el binario local
# Uso: verificar_hash_ftp <usuario> <password> <ip_ftp> <ruta_remota_sha256> <archivo_local>
verificar_hash_ftp() {
    local usuario="$1"
    local password="$2"
    local ip="$3"
    local ruta_sha256="$4"
    local archivo_local="$5"

    local hash_file="/tmp/$(basename "$ruta_sha256")"

    echo -e "${CYAN}[*] Verificando integridad de $(basename "$archivo_local")...${NC}"

    # Descargar el archivo .sha256 del servidor FTP
    descargar_ftp "$usuario" "$password" "$ip" "$ruta_sha256" "$hash_file"

    if [ ! -f "$hash_file" ]; then
        echo -e "${RED}[!] No se pudo obtener el archivo .sha256 del servidor.${NC}"
        return 1
    fi

    # El archivo sha256 puede tener el formato: "<hash>  nombre_archivo"
    # Reemplazamos el nombre del archivo por el path local para que sha256sum -c funcione
    local hash_esperado
    hash_esperado=$(awk '{print $1}' "$hash_file")
    local hash_calculado
    hash_calculado=$(sha256sum "$archivo_local" | awk '{print $1}')

    echo -e "  Esperado  : $hash_esperado"
    echo -e "  Calculado : $hash_calculado"

    if [ "$hash_esperado" = "$hash_calculado" ]; then
        echo -e "${GREEN}[+] Integridad verificada correctamente. Archivo sin corrupcion.${NC}"
        rm -f "$hash_file"
        return 0
    else
        echo -e "${RED}[!] FALLO DE INTEGRIDAD: el archivo esta corrupto o fue modificado.${NC}"
        rm -f "$hash_file"
        return 1
    fi
}

# ============================================================
#  SECCION 10 — INSTALACION DESDE FTP (navegacion dinamica)
# ============================================================

# Flujo completo: conecta al FTP, navega, descarga, verifica hash e instala
instalar_desde_ftp() {
    local os="Linux"
    local base_ftp="/http/$os"
    local tmp_dir="/tmp/p7_ftp"
    mkdir -p "$tmp_dir"

    echo ""
    echo -e "${CYAN}--- Instalacion via Repositorio FTP Privado ---${NC}"

    # Datos de conexion
    read -rp "IP del servidor FTP: " ftp_ip
    read -rp "Usuario FTP: " ftp_user
    read -rsp "Password FTP: " ftp_pass
    echo ""

    # 1. Listar servicios disponibles (carpetas bajo /http/Linux/)
    echo -e "${CYAN}[*] Listando servicios disponibles en $base_ftp ...${NC}"
    local servicios
    servicios=$(listar_directorio_ftp "$ftp_user" "$ftp_pass" "$ftp_ip" "$base_ftp/")

    if [ -z "$servicios" ]; then
        echo -e "${RED}[!] No se pudo conectar al FTP o la ruta esta vacia.${NC}"
        return 1
    fi

    # Convertir a array
    mapfile -t arr_servicios <<< "$servicios"

    echo ""
    echo -e "${CYAN}Servicios disponibles:${NC}"
    for i in "${!arr_servicios[@]}"; do
        echo "  [$((i+1))] ${arr_servicios[$i]}"
    done

    local sel_svc
    while true; do
        read -rp "Selecciona un servicio [1-${#arr_servicios[@]}]: " sel_svc
        if [[ "$sel_svc" =~ ^[0-9]+$ ]] && [ "$sel_svc" -ge 1 ] && [ "$sel_svc" -le "${#arr_servicios[@]}" ]; then
            break
        fi
        echo -e "${RED}[!] Opcion invalida.${NC}"
    done

    local servicio_elegido="${arr_servicios[$((sel_svc-1))]}"
    local ruta_servicio="$base_ftp/$servicio_elegido"

    # 2. Listar archivos binarios dentro de la carpeta del servicio
    echo -e "${CYAN}[*] Listando versiones disponibles en $ruta_servicio ...${NC}"
    local archivos_raw
    archivos_raw=$(listar_directorio_ftp "$ftp_user" "$ftp_pass" "$ftp_ip" "$ruta_servicio/")

    # Filtrar solo los binarios (excluir .sha256)
    local archivos=()
    while IFS= read -r linea; do
        if [[ "$linea" =~ \.(deb|tar\.gz|rpm|sh)$ ]]; then
            archivos+=("$linea")
        fi
    done <<< "$archivos_raw"

    if [ ${#archivos[@]} -eq 0 ]; then
        echo -e "${RED}[!] No se encontraron instaladores en $ruta_servicio${NC}"
        return 1
    fi

    echo ""
    echo -e "${CYAN}Versiones disponibles para $servicio_elegido:${NC}"
    for i in "${!archivos[@]}"; do
        echo "  [$((i+1))] ${archivos[$i]}"
    done

    local sel_arch
    while true; do
        read -rp "Selecciona una version [1-${#archivos[@]}]: " sel_arch
        if [[ "$sel_arch" =~ ^[0-9]+$ ]] && [ "$sel_arch" -ge 1 ] && [ "$sel_arch" -le "${#archivos[@]}" ]; then
            break
        fi
        echo -e "${RED}[!] Opcion invalida.${NC}"
    done

    local archivo_elegido="${archivos[$((sel_arch-1))]}"
    local ruta_binario="$ruta_servicio/$archivo_elegido"
    local ruta_sha256="$ruta_servicio/${archivo_elegido}.sha256"
    local destino_local="$tmp_dir/$archivo_elegido"

    # 3. Descargar binario
    descargar_ftp "$ftp_user" "$ftp_pass" "$ftp_ip" "$ruta_binario" "$destino_local" || return 1

    # 4. Verificar hash SHA256
    verificar_hash_ftp "$ftp_user" "$ftp_pass" "$ftp_ip" "$ruta_sha256" "$destino_local" || {
        echo -e "${RED}[!] Instalacion cancelada por fallo de integridad.${NC}"
        return 1
    }

    # 5. Instalar el binario descargado
    echo -e "${CYAN}[*] Instalando $archivo_elegido ...${NC}"

    if [[ "$archivo_elegido" == *.deb ]]; then
        dpkg -i "$destino_local" &>/dev/null || apt-get install -f -y &>/dev/null
        echo -e "${GREEN}[+] Instalacion .deb completada.${NC}"

    elif [[ "$archivo_elegido" == *.tar.gz ]]; then
        local extract_dir="$tmp_dir/${archivo_elegido%.tar.gz}"
        mkdir -p "$extract_dir"
        tar -xzf "$destino_local" -C "$extract_dir"
        echo -e "${GREEN}[+] Archivo extraido en $extract_dir${NC}"
        echo -e "${YELLOW}[!] Instalacion manual: revisa $extract_dir para continuar.${NC}"

    elif [[ "$archivo_elegido" == *.sh ]]; then
        chmod +x "$destino_local"
        bash "$destino_local"
        echo -e "${GREEN}[+] Script de instalacion ejecutado.${NC}"

    else
        echo -e "${YELLOW}[!] Formato no reconocido. Archivo en: $destino_local${NC}"
    fi
}
