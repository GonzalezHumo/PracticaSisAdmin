#!/bin/bash

# funciones_dhcp.sh
# Funciones para la gestion del servidor DHCP (Arch Linux)
# Depende de: funciones_comunes.sh

# Valida que ip_inicial sea menor que ip_final
source "$(dirname "$0")/funciones_comunes.sh"

validar_rango(){
    local ip_inicial="$1"
    local ip_final="$2"

    local o1_1 o1_2 o1_3 o1_4
    local o2_1 o2_2 o2_3 o2_4

    o1_1=$(echo "$ip_inicial" | cut -d'.' -f1)
    o1_2=$(echo "$ip_inicial" | cut -d'.' -f2)
    o1_3=$(echo "$ip_inicial" | cut -d'.' -f3)
    o1_4=$(echo "$ip_inicial" | cut -d'.' -f4)

    o2_1=$(echo "$ip_final" | cut -d'.' -f1)
    o2_2=$(echo "$ip_final" | cut -d'.' -f2)
    o2_3=$(echo "$ip_final" | cut -d'.' -f3)
    o2_4=$(echo "$ip_final" | cut -d'.' -f4)

    local num_inicial num_final
    num_inicial=$(( o1_1 * 16777216 + o1_2 * 65536 + o1_3 * 256 + o1_4 ))
    num_final=$(( o2_1 * 16777216 + o2_2 * 65536 + o2_3 * 256 + o2_4 ))

    if [ "$num_inicial" -ge "$num_final" ]; then
        echo "Error: la IP inicial debe ser menor que la IP final"
        echo "   IP inicial: $ip_inicial"
        echo "   IP final: $ip_final"
        return 1
    fi

    return 0
}

# Valida que el gateway este en el mismo segmento y fuera del rango DHCP
validar_gateway(){
    local gateway="$1"
    local ip_inicial="$2"
    local ip_final="$3"

    local segmento_gateway segmento_rango
    segmento_gateway=$(echo "$gateway" | cut -d'.' -f1-3)
    segmento_rango=$(echo "$ip_inicial" | cut -d'.' -f1-3)

    if [ "$segmento_gateway" != "$segmento_rango" ]; then
        echo "Error: el gateway debe estar en el mismo segmento de red"
        echo "   Gateway: $gateway (segmento: $segmento_gateway.X)"
        echo "   Rango: $segmento_rango.X"
        return 1
    fi

    local octeto_gw octeto_ini octeto_fin
    octeto_gw=$(echo "$gateway" | cut -d'.' -f4)
    octeto_ini=$(echo "$ip_inicial" | cut -d'.' -f4)
    octeto_fin=$(echo "$ip_final" | cut -d'.' -f4)

    if [ "$octeto_gw" -ge "$octeto_ini" ] && [ "$octeto_gw" -le "$octeto_fin" ]; then
        echo "Error: el gateway no debe estar dentro del rango DHCP"
        echo "   Gateway: $gateway"
        echo "   Rango DHCP: $ip_inicial - $ip_final"
        return 1
    fi

    return 0
}

# Valida que dos IPs pertenezcan al mismo segmento /24
validar_mismo_segmento(){
    local ip1=$1
    local ip2=$2

    local segmento1 segmento2
    segmento1=$(echo "$ip1" | cut -d'.' -f1-3)
    segmento2=$(echo "$ip2" | cut -d'.' -f1-3)

    if [ "$segmento1" != "$segmento2" ]; then
        echo "Error: las IPs deben estar en el mismo segmento de red"
        echo "   IP1: $ip1 (segmento: $segmento1.X)"
        echo "   IP2: $ip2 (segmento: $segmento2.X)"
        return 1
    fi

    return 0
}

# Calcula mascara, cidr y red base comparando los octetos de ambas IPs
calcular_mascara(){
    local ip1="$1"
    local ip2="$2"

    local o1_1 o1_2 o1_3
    local o2_1 o2_2 o2_3

    o1_1=$(echo "$ip1" | cut -d'.' -f1)
    o1_2=$(echo "$ip1" | cut -d'.' -f2)
    o1_3=$(echo "$ip1" | cut -d'.' -f3)

    o2_1=$(echo "$ip2" | cut -d'.' -f1)
    o2_2=$(echo "$ip2" | cut -d'.' -f2)
    o2_3=$(echo "$ip2" | cut -d'.' -f3)

    if [ "$o1_1" = "$o2_1" ] && [ "$o1_2" = "$o2_2" ] && [ "$o1_3" = "$o2_3" ]; then
        mascara="255.255.255.0"
        cidr="24"
        red_base="$o1_1.$o1_2.$o1_3.0"
    elif [ "$o1_1" = "$o2_1" ] && [ "$o1_2" = "$o2_2" ]; then
        mascara="255.255.0.0"
        cidr="16"
        red_base="$o1_1.$o1_2.0.0"
    elif [ "$o1_1" = "$o2_1" ]; then
        mascara="255.0.0.0"
        cidr="8"
        red_base="$o1_1.0.0.0"
    else
        echo "Error: las IPs no estan en la misma red"
        return 1
    fi

    export mascara cidr red_base
    return 0
}

# Pide el nombre del scope al usuario
solicitar_scope_name(){
    echo ""
    read -rp "Ingrese el nombre del scope: " scope_name

    while [ -z "$scope_name" ]; do
        echo "El nombre del scope no puede estar vacio"
        read -rp "Ingrese el nombre del scope: " scope_name
    done

    echo "Scope: $scope_name"
}

# Pide y valida el rango de IPs inicial y final
solicitar_rango_ips(){
    echo ""
    echo "Configuracion de rango"

    while true; do
        read -rp "Ingrese la IP inicial del rango: " ip_inicial

        if [ -z "$ip_inicial" ]; then
            echo "La IP inicial no puede estar vacia"
            continue
        fi

        if ! validar_ip_completa "$ip_inicial"; then continue; fi

        echo "IP inicial: $ip_inicial"
        break
    done

    while true; do
        read -rp "Ingrese la IP final del rango: " ip_final

        if [ -z "$ip_final" ]; then
            echo "La IP final no puede estar vacia"
            continue
        fi

        if ! validar_ip_completa "$ip_final"; then continue; fi
        if ! validar_mismo_segmento "$ip_inicial" "$ip_final"; then continue; fi
        if ! validar_rango "$ip_inicial" "$ip_final"; then continue; fi

        echo "IP final: $ip_final"
        break
    done
}

# Pide y valida el tiempo de concesion en segundos
solicitar_lease_time(){
    echo ""
    echo "Tiempo de concesion (lease time)"

    while true; do
        read -rp "Ingrese el tiempo en segundos: " lease_time

        if [ -z "$lease_time" ]; then
            echo "Error: el tiempo no puede estar vacio"
            continue
        fi

        if ! [[ "$lease_time" =~ ^[0-9]+$ ]]; then
            echo "Error: debe ingresar un numero valido"
            continue
        fi

        if [ "$lease_time" -le 0 ]; then
            echo "Error: el tiempo debe ser mayor a 0"
            continue
        fi

        echo "Lease time: $lease_time segundos"
        break
    done
}

# Pide y valida el gateway (opcional)
solicitar_gateway(){
    echo ""
    echo "Gateway (opcional)"

    while true; do
        read -rp "Ingrese la IP del gateway [Enter para omitir]: " gateway

        if [ -z "$gateway" ]; then
            gateway=""
            break
        fi

        if ! validar_ip_completa "$gateway"; then continue; fi
        if ! validar_gateway "$gateway" "$ip_inicial" "$ip_final"; then continue; fi

        echo "Gateway: $gateway"
        break
    done
}

# Pide y valida hasta 2 servidores DNS (opcionales)
solicitar_dns(){
    echo ""
    echo "Servidores DNS (opcionales, maximo 2)"

    while true; do
        read -rp "Ingrese DNS primario [Enter para omitir]: " dns1

        if [ -z "$dns1" ]; then
            dns1=""
            dns2=""
            echo "Sin DNS configurado"
            break
        fi

        if ! validar_ip_completa "$dns1"; then continue; fi

        echo "DNS primario: $dns1"
        break
    done

    if [ -n "$dns1" ]; then
        while true; do
            read -rp "Ingrese DNS secundario [Enter para omitir]: " dns2

            if [ -z "$dns2" ]; then
                dns2=""
                break
            fi

            if ! validar_ip_completa "$dns2"; then continue; fi

            if [ "$dns2" = "$dns1" ]; then
                echo "Error: el DNS secundario debe ser diferente al primario"
                continue
            fi

            echo "DNS secundario: $dns2"
            break
        done
    fi
}

# Verifica si el servidor DHCP esta instalado y ofrece reinstalarlo
verificar_dhcp(){
    echo "Verificando servidor DHCP..."

    if pacman -Q dhcp >/dev/null 2>&1; then
        echo "El servidor DHCP esta instalado"
        echo ""
        read -rp "Desea reinstalarlo y eliminar la configuracion actual? (s/n): " respuesta

        if [[ "$respuesta" != "s" && "$respuesta" != "S" ]]; then
            echo "Reinstalacion cancelada"
            return 0
        fi

        echo "Procediendo con la reinstalacion..."
        systemctl stop dhcpd4.service >/dev/null 2>&1
        pacman -Rns --noconfirm --noprogressbar dhcp >/dev/null 2>&1
        rm -f /etc/dhcp/dhcpd.conf
        rm -f /var/lib/dhcp/dhcpd.leases
        echo "Desinstalacion completada"
    else
        echo "El servidor DHCP no esta instalado"
    fi
}

# Instala el paquete dhcp si no esta presente
instalar_dhcp(){
    echo "Instalacion del servidor DHCP..."

    if pacman -Q dhcp >/dev/null 2>&1; then
        echo "El servidor DHCP ya esta instalado"
        return 0
    fi

    echo "Instalando..."
    pacman -S --noconfirm --noprogressbar dhcp >/dev/null 2>&1

    if pacman -Q dhcp >/dev/null 2>&1; then
        echo "Instalacion completada"
    else
        echo "Error: instalacion fallida"
        return 1
    fi
}

# Crea o actualiza un scope DHCP con los datos ingresados por el usuario
configurar_reconfigurar_scope(){
    echo "Configurar o reconfigurar scope DHCP"

    if ! pacman -Q dhcp >/dev/null 2>&1; then
        echo "Error: el servidor DHCP no esta instalado"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    solicitar_scope_name
    solicitar_rango_ips
    solicitar_lease_time
    solicitar_gateway
    solicitar_dns

    if ! calcular_mascara "$ip_inicial" "$ip_final"; then
        echo "Error al calcular la mascara de red"
        return 1
    fi

    # Mostrar resumen antes de aplicar
    echo ""
    echo "Resumen de configuracion:"
    echo "  Scope: $scope_name"
    echo "  IP del servidor: $ip_inicial/$cidr"
    echo "  Mascara: $mascara"
    echo "  Red base: $red_base"
    echo "  Rango DHCP: $ip_inicial - $ip_final"
    echo "  Lease time: $lease_time segundos"
    [ -n "$gateway" ] && echo "  Gateway: $gateway" || echo "  Gateway: (no configurado)"
    [ -n "$dns1" ] && echo "  DNS primario: $dns1" || echo "  DNS: (no configurado)"
    [ -n "$dns2" ] && echo "  DNS secundario: $dns2"
    echo ""

    read -rp "Desea aplicar esta configuracion? (s/n): " confirmar
    if [[ "$confirmar" != "s" && "$confirmar" != "S" ]]; then
        echo "Configuracion cancelada"
        return 0
    fi

    aplicar_configuracion
}

# Aplica la configuracion al sistema (interfaz, dhcpd.conf, servicio)
# Funcion interna llamada desde configurar_reconfigurar_scope
aplicar_configuracion(){
    echo ""
    echo "Aplicando configuracion..."

    mkdir -p /etc/dhcp /var/lib/dhcp /etc/systemd/network /run/dhcpd4
    chmod 755 /run/dhcpd4

    # Configurar IP estatica en la interfaz
    cat > /etc/systemd/network/20-wired.network << EOF
[Match]
Name=enp0s8

[Network]
Address=$ip_inicial/$cidr
EOF

    systemctl restart systemd-networkd
    echo "Interfaz configurada: $ip_inicial/$cidr"

    # Calcular inicio del rango (ip_inicial + 1)
    local octeto4_inicial segmento rango_inicio
    octeto4_inicial=$(echo "$ip_inicial" | cut -d'.' -f4)
    segmento=$(echo "$ip_inicial" | cut -d'.' -f1-3)
    rango_inicio="$segmento.$((octeto4_inicial + 1))"

    # Crear dhcpd.conf
    cat > /etc/dhcp/dhcpd.conf << EOF
# Scope: $scope_name
default-lease-time $lease_time;
max-lease-time $lease_time;

subnet $red_base netmask $mascara {
    range $rango_inicio $ip_final;
EOF

    [ -n "$gateway" ] && echo "    option routers $gateway;" >> /etc/dhcp/dhcpd.conf

    if [ -n "$dns1" ] && [ -n "$dns2" ]; then
        echo "    option domain-name-servers $dns1, $dns2;" >> /etc/dhcp/dhcpd.conf
    elif [ -n "$dns1" ]; then
        echo "    option domain-name-servers $dns1;" >> /etc/dhcp/dhcpd.conf
    else
        echo "    option domain-name-servers $ip_inicial;" >> /etc/dhcp/dhcpd.conf
    fi

    echo '}' >> /etc/dhcp/dhcpd.conf

    touch /var/lib/dhcp/dhcpd.leases
    chmod 644 /var/lib/dhcp/dhcpd.leases

    # Configurar interfaz para dhcpd
    mkdir -p /etc/systemd/system/dhcpd4.service.d
    cat > /etc/systemd/system/dhcpd4.service.d/interface.conf << EOF
[Service]
PIDFile=
ExecStart=
ExecStart=/usr/bin/dhcpd -4 -q -cf /etc/dhcp/dhcpd.conf enp0s8
EOF

    systemctl daemon-reload
    systemctl enable dhcpd4.service
    systemctl restart dhcpd4.service
    sleep 3

    if systemctl is-active --quiet dhcpd4.service; then
        echo ""
        echo "Configuracion aplicada exitosamente"
        echo "  Interfaz: enp0s8"
        echo "  IP del servidor: $ip_inicial/$cidr"
        echo "  Rango DHCP: $rango_inicio - $ip_final"
        echo "  Mascara: $mascara"
    else
        echo ""
        echo "Error: el servicio DHCP no inicio"
        journalctl -xeu dhcpd4.service -n 30 --no-pager
        return 1
    fi
}

# Lista todos los scopes configurados en dhcpd.conf con su estado
listar_scopes(){
    echo "Scopes configurados"

    if [ ! -f /etc/dhcp/dhcpd.conf ]; then
        echo "No hay scopes configurados"
        echo "Use la opcion 3 para agregar uno"
        return 0
    fi

    echo ""
    grep "# Scope:" /etc/dhcp/dhcpd.conf | sed 's/# Scope: /  - /'

    echo ""
    if systemctl is-active --quiet dhcpd4.service; then
        echo "Estado del servicio: ACTIVO"
    else
        echo "Estado del servicio: INACTIVO"
    fi
}

# Activa o desactiva el servicio DHCP
activar_desactivar_scope(){
    echo "Activar o desactivar servidor DHCP"

    if ! pacman -Q dhcp >/dev/null 2>&1; then
        echo "Error: el servidor DHCP no esta instalado"
        return 1
    fi

    echo ""
    if systemctl is-active --quiet dhcpd4.service; then
        echo "El servidor esta activo"
        read -rp "Desea desactivarlo? (s/n): " resp
        if [[ "$resp" = "s" || "$resp" = "S" ]]; then
            systemctl stop dhcpd4.service
            echo "Servidor desactivado"
        fi
    else
        echo "El servidor esta inactivo"
        read -rp "Desea activarlo? (s/n): " resp
        if [[ "$resp" = "s" || "$resp" = "S" ]]; then
            systemctl start dhcpd4.service
            sleep 2
            if systemctl is-active --quiet dhcpd4.service; then
                echo "Servidor activado"
            else
                echo "Error: no se pudo activar el servidor"
                journalctl -xeu dhcpd4.service -n 10 --no-pager
            fi
        fi
    fi
}

# Elimina la configuracion del scope actual
eliminar_scope(){
    echo "Eliminar scope DHCP"

    if [ ! -f /etc/dhcp/dhcpd.conf ]; then
        echo "No hay scope configurado"
        return 0
    fi

    echo ""
    grep "# Scope:" /etc/dhcp/dhcpd.conf | sed 's/# Scope: /Scope actual: /'
    echo ""
    read -rp "Desea eliminar este scope? (s/n): " confirmar

    if [[ "$confirmar" != "s" && "$confirmar" != "S" ]]; then
        echo "Operacion cancelada"
        return 0
    fi

    systemctl stop dhcpd4.service >/dev/null 2>&1
    rm -f /etc/dhcp/dhcpd.conf
    rm -f /var/lib/dhcp/dhcpd.leases
    echo "Scope eliminado"
}

# Muestra las concesiones activas del servidor DHCP
monitorear_concesiones(){
    echo "Concesiones activas"

    if ! systemctl is-active --quiet dhcpd4.service 2>/dev/null; then
        echo "Error: el servicio DHCP no esta activo"
        return 1
    fi

    if [ ! -f /var/lib/dhcp/dhcpd.leases ]; then
        echo "No hay archivo de concesiones disponible"
        return 1
    fi

    if ! grep -q "^lease" /var/lib/dhcp/dhcpd.leases 2>/dev/null; then
        echo "No hay concesiones activas en este momento"
        return 0
    fi

    echo ""
    grep "^lease" /var/lib/dhcp/dhcpd.leases | awk '{print "  IP asignada: "$2}' | sort -u

    local total
    total=$(grep "^lease" /var/lib/dhcp/dhcpd.leases | awk '{print $2}' | sort -u | wc -l)
    echo ""
    echo "Total de concesiones: $total"
}

# Muestra el estado actual del servicio DHCP
monitorear_estado_dhcp(){
    echo "Estado del servidor DHCP"

    if ! pacman -Q dhcp >/dev/null 2>&1; then
        echo "El servidor DHCP no esta instalado"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    echo "Paquete dhcp: INSTALADO"
    echo ""

    if systemctl is-active --quiet dhcpd4.service; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi

    if systemctl is-enabled --quiet dhcpd4.service 2>/dev/null; then
        echo "Inicio automatico: HABILITADO"
    else
        echo "Inicio automatico: DESHABILITADO"
    fi

    echo ""
    systemctl status dhcpd4.service --no-pager
}