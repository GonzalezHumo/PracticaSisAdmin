#!/bin/bash

# funciones_ssh.sh
# Funciones para la gestion del servidor SSH (Arch Linux)

source "$(dirname "$0")/funciones_comunes.sh"

# Verifica si openssh esta instalado y el estado del servicio sshd
verificar_ssh(){
    echo "Verificando servidor SSH..."

    if pacman -Q openssh >/dev/null 2>&1; then
        echo "Paquete openssh: INSTALADO"
    else
        echo "Paquete openssh: NO INSTALADO"
        echo "Use la opcion 16 para instalarlo"
        return 1
    fi

    echo ""

    if systemctl is-active --quiet sshd; then
        echo "Servicio sshd: ACTIVO"
    else
        echo "Servicio sshd: INACTIVO"
    fi

    if systemctl is-enabled --quiet sshd 2>/dev/null; then
        echo "Inicio automatico: HABILITADO"
    else
        echo "Inicio automatico: DESHABILITADO"
    fi

    echo ""

    # Verificar si root puede conectarse
    if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Login como root: PERMITIDO"
    else
        echo "Login como root: NO CONFIGURADO"
    fi
}

# Instala openssh, permite login root y habilita el servicio
instalar_ssh(){
    echo "Instalacion del servidor SSH..."

    if pacman -Q openssh >/dev/null 2>&1; then
        echo "OpenSSH ya esta instalado"
        return 0
    fi

    echo "Instalando openssh..."
    pacman -S --noconfirm openssh >/dev/null 2>&1

    if ! pacman -Q openssh >/dev/null 2>&1; then
        echo "Error: la instalacion fallo"
        return 1
    fi

    echo "Paquete openssh instalado"
    echo ""

    # Permitir login como root
    echo "Configurando acceso root..."

    # Si la linea existe la reemplaza, si no la agrega
    if grep -q "^#PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    elif grep -q "^PermitRootLogin" /etc/ssh/sshd_config; then
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
    else
        echo "PermitRootLogin yes" >> /etc/ssh/sshd_config
    fi

    echo "Login root: PERMITIDO"
    echo ""

    # Habilitar e iniciar el servicio
    echo "Habilitando e iniciando sshd..."
    systemctl enable sshd >/dev/null 2>&1
    systemctl start sshd
    sleep 2

    if systemctl is-active --quiet sshd; then
        # Obtener IP del servidor para mostrar como conectarse
        local ip_servidor
        ip_servidor=$(ip -4 addr show enp0s8 | grep -oP '(?<=inet\s)\d+\.\d+\.\d+\.\d+')

        echo ""
        echo "SSH instalado y configurado"
        echo "  Servicio sshd: ACTIVO"
        echo "  Puerto: 22"
        [ -n "$ip_servidor" ] && echo "  Conectarse con: ssh root@$ip_servidor"
    else
        echo ""
        echo "Error: el servicio sshd no inicio"
        journalctl -xeu sshd -n 20 --no-pager
        return 1
    fi
}

# Muestra el estado actual del servicio sshd
monitorear_estado_ssh(){
    echo "Estado del servidor SSH"

    if ! pacman -Q openssh >/dev/null 2>&1; then
        echo "El servidor SSH no esta instalado"
        echo "Use la opcion 2 para instalarlo"
        return 1
    fi

    echo "Paquete openssh: INSTALADO"
    echo ""

    if systemctl is-active --quiet sshd; then
        echo "Estado: ACTIVO"
    else
        echo "Estado: INACTIVO"
    fi

    if systemctl is-enabled --quiet sshd 2>/dev/null; then
        echo "Inicio automatico: HABILITADO"
    else
        echo "Inicio automatico: DESHABILITADO"
    fi

    echo ""
    systemctl status sshd --no-pager
}