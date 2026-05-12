#!/bin/bash

# ================================================
#  FUNCIONES DEL SERVIDOR FTP (vsftpd) - LINUX
# ================================================

validar_contra() {
    local contra="$1"

    if [ ${#contra} -lt 8 ]; then
        echo "La contrasena debe tener al menos 8 caracteres."
        return 1
    fi
    if [ ${#contra} -gt 15 ]; then
        echo "La contrasena no puede tener mas de 15 caracteres."
        return 1
    fi
    if ! echo "$contra" | grep -q '[A-Z]'; then
        echo "La contrasena debe contener al menos una letra mayuscula."
        return 1
    fi
    if ! echo "$contra" | grep -q '[a-z]'; then
        echo "La contrasena debe contener al menos una letra minuscula."
        return 1
    fi
    if ! echo "$contra" | grep -q '[0-9]'; then
        echo "La contrasena debe contener al menos un numero."
        return 1
    fi
    if ! echo "$contra" | grep -q '[^a-zA-Z0-9]'; then
        echo "La contrasena debe contener al menos un caracter especial."
        return 1
    fi
    return 0
}

capturar_contra() {
    local contra=""
    local valida=false
    while [ "$valida" = false ]; do
        read -rp "Ingrese la contrasena (min. 8, max 15, mayuscula, minuscula, numero, especial): " contra
        if validar_contra "$contra"; then
            valida=true
        else
            echo "La contrasena no cumple con los requisitos. Intentelo de nuevo."
        fi
    done
    echo "$contra"
}

capturar_usuario_valido() {
    local mensaje="$1"
    local cadena=""
    local valida=false
    while [ "$valida" = false ]; do
        read -rp "$mensaje" cadena
        if [ -z "$cadena" ]; then
            echo "El nombre no puede estar vacio."
        elif ! echo "$cadena" | grep -qE '^[a-zA-Z0-9]+$'; then
            echo "El nombre solo puede contener letras y numeros."
        elif echo "$cadena" | grep -qE '^[0-9]'; then
            echo "El nombre no puede comenzar con un numero."
        elif [ ${#cadena} -gt 15 ]; then
            echo "El nombre no puede exceder 15 caracteres."
        elif usuario_existe "$cadena"; then
            echo "El usuario '$cadena' ya existe. Elija otro nombre."
        else
            valida=true
        fi
    done
    echo "$cadena"
}

usuario_existe() {
    local nombre="$1"
    if id "$nombre" &>/dev/null; then
        return 0
    else
        return 1
    fi
}

capturar_grupo() {
    local grupo=""
    while true; do
        read -rp "Ingrese el grupo del usuario 1)Reprobados  2)Recursadores: " grupo
        if [ "$grupo" = "1" ]; then
            echo "reprobados"
            return
        elif [ "$grupo" = "2" ]; then
            echo "recursadores"
            return
        else
            echo "Opcion no valida. Por favor, ingrese 1 o 2."
        fi
    done
}

crear_usuario_ftp() {
    local nombre="$1"
    local contra="$2"
    local grupo="$3"

    # Crear usuario del sistema
    useradd -m -s /bin/bash -G "$grupo" "$nombre"
    echo "$nombre:$contra" | chpasswd

    # Crear estructura de carpetas
    local user_path="/srv/ftp/usuarios/$nombre"
    mkdir -p "$user_path/$nombre"

    # Crear enlaces simbolicos
    ln -sfn /srv/ftp/general "$user_path/general"
    ln -sfn "/srv/ftp/grupos/$grupo" "$user_path/$grupo"

    # Permisos
    chown -R "$nombre:$grupo" "$user_path/$nombre"
    chmod 755 "$user_path/$nombre"
    chmod a-w "$user_path"

    # Agregar usuario a vsftpd.userlist
    if ! grep -q "^$nombre$" /etc/vsftpd.userlist 2>/dev/null; then
        echo "$nombre" >> /etc/vsftpd.userlist
    fi

    echo "Usuario $nombre creado correctamente en el grupo $grupo."
}

cambiar_grupo_ftp() {
    read -rp "Ingrese el nombre del usuario a modificar: " nombre

    if ! usuario_existe "$nombre"; then
        echo "El usuario no existe."
        return
    fi

    # Identificar grupo actual
    local viejo_grupo=""
    if id -nG "$nombre" | grep -qw "reprobados"; then
        viejo_grupo="reprobados"
    elif id -nG "$nombre" | grep -qw "recursadores"; then
        viejo_grupo="recursadores"
    fi

    echo "El usuario pertenece actualmente a: $viejo_grupo"
    local nuevo_grupo
    nuevo_grupo=$(capturar_grupo)

    if [ "$viejo_grupo" = "$nuevo_grupo" ]; then
        echo "El usuario ya pertenece a ese grupo."
        return
    fi

    # Cambiar grupo
    gpasswd -d "$nombre" "$viejo_grupo" 2>/dev/null
    usermod -aG "$nuevo_grupo" "$nombre"

    # Actualizar enlace simbolico
    local user_path="/srv/ftp/usuarios/$nombre"
    rm -f "$user_path/$viejo_grupo"
    ln -sfn "/srv/ftp/grupos/$nuevo_grupo" "$user_path/$nuevo_grupo"

    echo "Cambio completado. El usuario $nombre ahora tiene acceso a $nuevo_grupo."
}

eliminar_usuario_ftp() {
    read -rp "Ingrese el nombre del usuario a eliminar: " nombre

    if ! usuario_existe "$nombre"; then
        echo "El usuario no existe."
        return
    fi

    # Eliminar usuario del sistema
    userdel -r "$nombre" 2>/dev/null

    # Eliminar carpeta FTP
    local user_path="/srv/ftp/usuarios/$nombre"
    if [ -d "$user_path" ]; then
        rm -rf "$user_path"
    fi

    # Eliminar de vsftpd.userlist
    sed -i "/^$nombre$/d" /etc/vsftpd.userlist 2>/dev/null

    echo "Usuario $nombre eliminado completamente del servidor."
}
