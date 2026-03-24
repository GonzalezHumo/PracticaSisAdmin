#!/bin/bash

# funciones_dns.sh
# Funciones para la gestion del servidor DNS - BIND9 (Arch Linux)

source "$(dirname "$0")/funciones_comunes.sh"

# Verifica si BIND9 esta instalado y el estado del servicio named
verificar_bind(){
    echo "Verificando BIND9..."

    if pacman -Q bind >/dev/null 2>&1; then
        echo "Paquete bind: INSTALADO"
    else
        echo "Paquete bind: NO INSTALADO"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    echo ""

    if systemctl is-active --quiet named; then
        echo "Servicio named: ACTIVO"
    else
        echo "Servicio named: INACTIVO"
    fi

    if systemctl is-enabled --quiet named 2>/dev/null; then
        echo "Inicio automatico: HABILITADO"
    else
        echo "Inicio automatico: DESHABILITADO"
    fi
}

# Instala y configura BIND9 con la zona raiz y el fix de jemalloc
instalar_bind(){
    echo "Instalacion de BIND9..."

    if pacman -Q bind >/dev/null 2>&1; then
        echo "BIND9 ya esta instalado"
        return 0
    fi

    echo "Instalando..."
    pacman -S --noconfirm bind >/dev/null 2>&1

    if ! pacman -Q bind >/dev/null 2>&1; then
        echo "Error: la instalacion fallo"
        return 1
    fi

    echo "Paquete bind instalado"
    echo ""

    # Detectar IP del servidor en enp0s8
    local ip_servidor
    ip_servidor=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')

    if [ -z "$ip_servidor" ]; then
        echo "Error: enp0s8 no tiene IP asignada"
        return 1
    fi

    echo "IP detectada: $ip_servidor"
    echo ""

    mkdir -p /var/named
    chown named:named /var/named
    chmod 770 /var/named

    # Descargar zona raiz
    echo "Descargando zona raiz..."
    curl -o /var/named/root.hints https://www.internic.net/domain/named.root 2>/dev/null
    chown named:named /var/named/root.hints
    echo "Zona raiz descargada"
    echo ""

    # Generar named.conf
    echo "Generando named.conf..."
    cat > /etc/named.conf << EOF
options {
    listen-on { 127.0.0.1; $ip_servidor; };
    listen-on-v6 { none; };
    directory "/var/named";
    allow-query { any; };
    allow-query-cache { any; };
    recursion yes;
};

zone "." IN {
    type hint;
    file "root.hints";
};
EOF

    # Fix para jemalloc en Arch Linux
    mkdir -p /etc/systemd/system/named.service.d
    cat > /etc/systemd/system/named.service.d/fix.conf << EOF
[Service]
LD_PRELOAD=
Environment=MALLOC_CONF=
ExecStart=
ExecStart=/usr/bin/named -f -4 -u named
EOF

    systemctl daemon-reload
    echo ""

    echo "Habilitando e iniciando named..."
    systemctl enable named >/dev/null 2>&1
    systemctl start named
    sleep 2

    if systemctl is-active --quiet named; then
        echo ""
        echo "BIND9 instalado y configurado"
        echo "  Servicio named: ACTIVO"
        echo "  IP del servidor: $ip_servidor"
    else
        echo ""
        echo "Error: el servicio named no inicio"
        journalctl -xeu named -n 20 --no-pager
        return 1
    fi
}

# Agrega una zona DNS primaria con registro A, NS y CNAME para www
agregar_zona(){
    echo "Agregar zona DNS"

    if ! pacman -Q bind >/dev/null 2>&1; then
        echo "Error: BIND9 no esta instalado"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    local ip_servidor
    ip_servidor=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')

    if [ -z "$ip_servidor" ]; then
        echo "Error: enp0s8 no tiene IP asignada"
        return 1
    fi

    echo "IP del servidor: $ip_servidor"
    echo ""

    # Pedir dominio
    while true; do
        read -rp "Ingrese el dominio (ejemplo: reprobados.com): " dominio

        if [ -z "$dominio" ]; then
            echo "Error: el dominio no puede estar vacio"
            continue
        fi

        if [[ ! "$dominio" =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
            echo "Error: formato invalido, ejemplo: reprobados.com"
            continue
        fi

        if [ -f "/var/named/db.$dominio" ]; then
            echo "Error: la zona $dominio ya existe"
            continue
        fi

        break
    done

    echo ""

    # Pedir IP destino
    while true; do
        read -rp "Ingrese la IP destino del dominio: " ip_destino

        if [ -z "$ip_destino" ]; then
            echo "Error: la IP no puede estar vacia"
            continue
        fi

        if ! validar_ip_completa "$ip_destino"; then continue; fi

        break
    done

    echo ""
    echo "Creando archivo de zona /var/named/db.$dominio..."

    cat > "/var/named/db.$dominio" << EOF
\$TTL 86400
@   IN  SOA ns1.$dominio. admin.$dominio. (
            2024010101  ; Serial
            3600        ; Refresh
            1800        ; Retry
            604800      ; Expire
            86400 )     ; Minimum TTL

@   IN  NS  ns1.$dominio.
ns1 IN  A   $ip_servidor
@   IN  A   $ip_destino
www IN  CNAME   @
EOF

    echo "Archivo de zona creado"
    echo ""

    # Agregar zona al named.conf
    cat >> /etc/named.conf << EOF

zone "$dominio" {
    type master;
    file "/var/named/db.$dominio";
};
EOF

    echo "Zona agregada al named.conf"
    echo ""

    systemctl restart named
    sleep 2

    if systemctl is-active --quiet named; then
        echo "Zona configurada exitosamente"
        echo "  Dominio: $dominio"
        echo "  IP destino: $ip_destino"
        echo "  Servidor DNS: $ip_servidor"
    else
        echo "Error: named no reinicio"
        journalctl -xeu named -n 20 --no-pager
        return 1
    fi
}

# Lista todas las zonas configuradas en /var/named
listar_zonas(){
    echo "Zonas DNS configuradas"

    if ! pacman -Q bind >/dev/null 2>&1; then
        echo "Error: BIND9 no esta instalado"
        return 1
    fi

    if [ ! -d "/var/named" ]; then
        echo "No hay zonas configuradas"
        return 0
    fi

    local zonas
    zonas=$(ls /var/named/db.* 2>/dev/null)

    if [ -z "$zonas" ]; then
        echo "No hay zonas configuradas"
        echo "Use la opcion 3 para agregar una"
        return 0
    fi

    echo ""
    local contador=1

    for archivo in /var/named/db.*; do
        local dominio ip_destino
        dominio=$(basename "$archivo" | sed 's/db\.//')
        ip_destino=$(grep "^@" "$archivo" | grep "IN  A" | awk '{print $4}')
        echo "  $contador) $dominio -> $ip_destino"
        contador=$((contador + 1))
    done

    echo ""
    echo "Total de zonas: $((contador - 1))"
}

# Verifica la sintaxis de named.conf y prueba la resolucion de una zona
validar_configuracion(){
    echo "Validacion de configuracion DNS"

    if ! pacman -Q bind >/dev/null 2>&1; then
        echo "Error: BIND9 no esta instalado"
        return 1
    fi

    # Verificar sintaxis de named.conf
    echo "Verificando sintaxis de named.conf..."
    if named-checkconf /etc/named.conf; then
        echo "named.conf: OK"
    else
        echo "Error: named.conf tiene errores de sintaxis"
        return 1
    fi

    echo ""

    local zonas
    zonas=$(ls /var/named/db.* 2>/dev/null)

    if [ -z "$zonas" ]; then
        echo "No hay zonas configuradas"
        return 0
    fi

    echo "Zonas disponibles:"
    echo ""

    declare -a lista_dominios
    local contador=1

    for archivo in /var/named/db.*; do
        local dominio
        dominio=$(basename "$archivo" | sed 's/db\.//')
        lista_dominios[$contador]=$dominio
        echo "  $contador) $dominio"
        contador=$((contador + 1))
    done

    echo ""

    while true; do
        read -rp "Seleccione el numero del dominio a probar: " seleccion

        if [ -z "$seleccion" ]; then
            echo "Error: debe seleccionar una opcion"
            continue
        fi

        if ! [[ "$seleccion" =~ ^[0-9]+$ ]]; then
            echo "Error: ingrese un numero valido"
            continue
        fi

        if [ "$seleccion" -lt 1 ] || [ "$seleccion" -ge "$contador" ]; then
            echo "Error: seleccione un numero entre 1 y $((contador - 1))"
            continue
        fi

        break
    done

    local dominio_elegido=${lista_dominios[$seleccion]}
    echo "Dominio seleccionado: $dominio_elegido"
    echo ""

    # Verificar sintaxis del archivo de zona
    echo "Verificando sintaxis del archivo de zona..."
    if named-checkzone "$dominio_elegido" "/var/named/db.$dominio_elegido"; then
        echo "Archivo de zona: OK"
    else
        echo "Error: el archivo de zona tiene errores"
        return 1
    fi

    echo ""

    local ip_esperada ip_servidor
    ip_esperada=$(grep "^@" "/var/named/db.$dominio_elegido" | grep "IN  A" | awk '{print $4}')
    ip_servidor=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')

    echo "Probando resolucion DNS..."
    echo ""

    # Probar sin www
    local resultado_sin_www
    resultado_sin_www=$(nslookup "$dominio_elegido" "$ip_servidor" 2>/dev/null | grep "Address" | tail -1 | awk '{print $2}')

    if [ "$resultado_sin_www" = "$ip_esperada" ]; then
        echo "nslookup $dominio_elegido -> $resultado_sin_www OK"
    else
        echo "nslookup $dominio_elegido -> FALLO (esperada: $ip_esperada, obtenida: $resultado_sin_www)"
    fi

    # Probar con www
    local resultado_con_www
    resultado_con_www=$(nslookup "www.$dominio_elegido" "$ip_servidor" 2>/dev/null | grep "Address" | tail -1 | awk '{print $2}')

    if [ "$resultado_con_www" = "$ip_esperada" ]; then
        echo "nslookup www.$dominio_elegido -> $resultado_con_www OK"
    else
        echo "nslookup www.$dominio_elegido -> FALLO (esperada: $ip_esperada, obtenida: $resultado_con_www)"
    fi

    echo ""
    echo "Probando ping..."
    echo ""

    if ping -c 3 "$dominio_elegido" >/dev/null 2>&1; then
        echo "ping $dominio_elegido -> OK"
    else
        echo "ping $dominio_elegido -> FALLO"
        echo "Nota: puede fallar si el cliente no esta encendido"
    fi

    if ping -c 3 "www.$dominio_elegido" >/dev/null 2>&1; then
        echo "ping www.$dominio_elegido -> OK"
    else
        echo "ping www.$dominio_elegido -> FALLO"
        echo "Nota: puede fallar si el cliente no esta encendido"
    fi

    echo ""
    echo "Validacion completada"
}

# Muestra el estado actual del servicio named
monitorear_estado_dns(){
    echo "Estado del servidor DNS"

    if ! pacman -Q bind >/dev/null 2>&1; then
        echo "El servidor DNS no esta instalado"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    echo "Paquete bind: INSTALADO"
    echo ""

    if systemctl is-active --quiet named; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi

    if systemctl is-enabled --quiet named 2>/dev/null; then
        echo "Inicio automatico: HABILITADO"
    else
        echo "Inicio automatico: DESHABILITADO"
    fi

    echo ""
    systemctl status named --no-pager
}