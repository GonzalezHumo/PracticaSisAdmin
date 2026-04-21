#!/bin/bash

# funciones_comunes.sh
# Funciones compartidas entre todos los servicios (DHCP, DNS, SSH)

# Verifica que el script se ejecute como root
verificar_root(){
    if [ "$EUID" -ne 0 ]; then
        echo "Este script debe ejecutarse como root"
        echo "Usa: sudo bash $0"
        exit 1
    fi
}

# Verifica formato X.X.X.X y que cada octeto este entre 0 y 255
validar_ip(){
    local ip=$1

    if [[ ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "Formato invalido, debe ser: X.X.X.X (ejemplo: 192.168.1.1)"
        return 1
    fi

    IFS='.' read -r octeto1 octeto2 octeto3 octeto4 <<< "$ip"

    for octeto in $octeto1 $octeto2 $octeto3 $octeto4; do
        if [ "$octeto" -lt 0 ] || [ "$octeto" -gt 255 ]; then
            echo "Error: cada octeto debe estar entre 0 y 255"
            return 1
        fi
    done

    return 0
}

# El rango 127.x.x.x esta reservado para la interfaz local
validar_no_loopback(){
    local ip=$1
    local primer_octeto
    primer_octeto=$(echo "$ip" | cut -d'.' -f1)

    if [ "$primer_octeto" -eq 127 ]; then
        echo "Error: no se puede usar la IP loopback (127.x.x.x)"
        return 1
    fi

    return 0
}

# 255.255.255.255 es la direccion de broadcast general, no asignable
validar_no_broadcast(){
    local ip=$1

    if [ "$ip" = "255.255.255.255" ]; then
        echo "Error: no se puede usar la IP de broadcast"
        return 1
    fi

    return 0
}

# 0.0.0.0 representa una ruta por defecto, no una IP valida de host
validar_no_cero(){
    local ip=$1

    if [ "$ip" = "0.0.0.0" ]; then
        echo "Error: no se puede usar la IP 0.0.0.0"
        return 1
    fi

    return 0
}

# Agrupa las 4 validaciones basicas para no repetirlas en cada funcion
validar_ip_completa(){
    local ip=$1

    if ! validar_ip "$ip"; then return 1; fi
    if ! validar_no_loopback "$ip"; then return 1; fi
    if ! validar_no_broadcast "$ip"; then return 1; fi
    if ! validar_no_cero "$ip"; then return 1; fi

    return 0
}