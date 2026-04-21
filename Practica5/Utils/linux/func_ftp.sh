#!/bin/bash

# funciones_ftp.sh
# Funciones para instalar y configurar el servidor FTP con vsftpd

FTP_ROOT="/srv/ftp"

# Verifica si vsftpd está instalado y muestra su estado
verificar_vsftpd() {
    if pacman -Q vsftpd &> /dev/null; then
        echo "vsftpd está instalado."
        systemctl status vsftpd --no-pager
    else
        echo "vsftpd no está instalado."
    fi
}

# Instala vsftpd solo si no está instalado
instalar_vsftpd() {
    if pacman -Q vsftpd &> /dev/null; then
        echo "vsftpd ya está instalado, continuando..."
        return 0
    fi

    echo "Instalando vsftpd..."
    pacman -Sy --noconfirm vsftpd
    systemctl enable vsftpd
    echo "vsftpd instalado."
}

configurar_vsftpd() {
    echo "Configurando vsftpd..."

    # /bin/false debe estar en /etc/shells para que PAM permita el login
    grep -q "/bin/false" /etc/shells || echo "/bin/false" >> /etc/shells

    # Persiste /var/run/vsftpd/empty tras reinicios
    echo "d /var/run/vsftpd/empty 0755 root root -" > /etc/tmpfiles.d/vsftpd.conf
    mkdir -p /var/run/vsftpd/empty

    # Usuario ftp requerido para acceso anónimo
    id ftp > /dev/null 2>&1 || useradd -r -d "$FTP_ROOT" -s /bin/false ftp

    cat > /etc/vsftpd.conf << EOF
# Acceso anónimo solo lectura a /anonimo (ve carpeta general dentro)
anonymous_enable=YES
anon_root=$FTP_ROOT/anonimo
no_anon_password=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
anon_other_write_enable=NO

# Acceso usuarios locales
local_enable=YES
write_enable=YES
local_umask=002

# Encierra a cada usuario en su home (jaula)
chroot_local_user=YES
allow_writeable_chroot=YES

# Solo usuarios en la lista pueden conectarse
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO

listen=YES
listen_ipv6=NO
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd
EOF

    # PAM sin pam_shells.so para permitir acceso anónimo con /bin/false
    cat > /etc/pam.d/vsftpd << EOF
#%PAM-1.0
auth    required    /lib/security/pam_listfile.so item=user sense=deny file=/etc/ftpusers onerr=succeed
auth    required    /lib/security/pam_unix.so shadow nullok
account required    /lib/security/pam_unix.so
session required    /lib/security/pam_unix.so
EOF

    # Agrega anonymous al userlist para permitir acceso anónimo
    touch /etc/vsftpd.userlist
    grep -q "^anonymous$" /etc/vsftpd.userlist || echo "anonymous" >> /etc/vsftpd.userlist

    crear_grupos
    crear_estructura_base
    systemctl restart vsftpd
    echo "vsftpd configurado y reiniciado."
}

crear_estructura_base() {
    echo "Creando estructura base..."

    mkdir -p "$FTP_ROOT/general"
    mkdir -p "$FTP_ROOT/reprobados"
    mkdir -p "$FTP_ROOT/recursadores"

    # Carpeta intermedia para anónimo: solo verá general dentro
    mkdir -p "$FTP_ROOT/anonimo"
    mkdir -p "$FTP_ROOT/anonimo/general"

    # general: 755 obligatorio, vsftpd rechaza anon_root con permisos de escritura de grupo
    chown root:ftp "$FTP_ROOT/general"
    chmod 775 "$FTP_ROOT/general"

    # grupos: solo miembros del grupo escriben
    chown root:reprobados "$FTP_ROOT/reprobados"
    chmod 770 "$FTP_ROOT/reprobados"

    chown root:recursadores "$FTP_ROOT/recursadores"
    chmod 770 "$FTP_ROOT/recursadores"

    # anonimo: root lo posee, nadie escribe
    chown root:root "$FTP_ROOT/anonimo"
    chmod 755 "$FTP_ROOT/anonimo"

    # Bind mount de general dentro de anonimo
    if ! mountpoint -q "$FTP_ROOT/anonimo/general"; then
        mount --bind "$FTP_ROOT/general" "$FTP_ROOT/anonimo/general"
    fi

    # Persiste el mount en fstab
    if ! grep -q "$FTP_ROOT/anonimo/general" /etc/fstab; then
        echo "$FTP_ROOT/general $FTP_ROOT/anonimo/general none bind 0 0" >> /etc/fstab
    fi

    echo "Estructura base creada."
}
# Crea los grupos del sistema si no existen
crear_grupos() {
    for grupo in reprobados recursadores; do
        if ! getent group "$grupo" > /dev/null 2>&1; then
            groupadd "$grupo"
            echo "Grupo $grupo creado."
        else
            echo "Grupo $grupo ya existe, continuando..."
        fi
    done
}

# Solicita datos y crea n usuarios
gestionar_usuarios() {
    read -p "¿Cuántos usuarios deseas crear? " n

    if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -eq 0 ]; then
        echo "Número inválido."
        return 1
    fi

    for (( i=1; i<=n; i++ )); do
        echo "--- Usuario $i de $n ---"

        read -p "Nombre de usuario: " usuario
        read -s -p "Contraseña: " password
        echo

        while true; do
            read -p "Grupo (reprobados/recursadores): " grupo
            if [[ "$grupo" == "reprobados" || "$grupo" == "recursadores" ]]; then
                break
            fi
            echo "Grupo inválido, escribe reprobados o recursadores."
        done

        crear_usuario "$usuario" "$password" "$grupo"
    done
}

# Crea el usuario con su jaula y bind mounts
crear_usuario() {
    local usuario=$1
    local password=$2
    local grupo=$3
    local jaula="$FTP_ROOT/$usuario"

    if id "$usuario" > /dev/null 2>&1; then
        echo "Usuario $usuario ya existe, actualizando..."
        usermod -g "$grupo" -G ftp -d "$jaula" "$usuario"
    else
        # home apunta a su jaula en /srv/ftp/usuario
        # -s /bin/false: sin acceso SSH
        useradd -s /bin/false -g "$grupo" -G ftp -d "$jaula" -M "$usuario"
        echo "$usuario:$password" | chpasswd
        echo "Usuario $usuario creado."
    fi

    # Agrega al userlist si no está
    if ! grep -q "^$usuario$" /etc/vsftpd.userlist 2>/dev/null; then
        echo "$usuario" >> /etc/vsftpd.userlist
    fi

    crear_jaula_usuario "$usuario" "$grupo"
}

# Crea la jaula del usuario con sus 3 carpetas visibles
crear_jaula_usuario() {
    local usuario=$1
    local grupo=$2
    local jaula="$FTP_ROOT/$usuario"

    # Raíz de la jaula: debe ser root:root 755, vsftpd lo exige
    mkdir -p "$jaula"
    chown root:root "$jaula"
    chmod 755 "$jaula"

    # Carpeta personal dentro de la jaula
    mkdir -p "$jaula/$usuario"
    chown "$usuario":"$grupo" "$jaula/$usuario"
    chmod 755 "$jaula/$usuario"

    # Puntos de montaje para general y grupo
    mkdir -p "$jaula/general"
    mkdir -p "$jaula/$grupo"

    # Bind mount de general si no está montado
    if ! mountpoint -q "$jaula/general"; then
        mount --bind "$FTP_ROOT/general" "$jaula/general"
    fi

    # Bind mount de la carpeta del grupo si no está montado
    if ! mountpoint -q "$jaula/$grupo"; then
        mount --bind "$FTP_ROOT/$grupo" "$jaula/$grupo"
    fi

    # Persiste los mounts en fstab para que sobrevivan reinicios
    persistir_mounts "$usuario" "$grupo"

    echo "Jaula de $usuario configurada."
}

# Persiste bind mounts en /etc/fstab
persistir_mounts() {
    local usuario=$1
    local grupo=$2
    local jaula="$FTP_ROOT/$usuario"

    if ! grep -q "$jaula/general" /etc/fstab; then
        echo "$FTP_ROOT/general $jaula/general none bind 0 0" >> /etc/fstab
    fi

    if ! grep -q "$jaula/$grupo" /etc/fstab; then
        echo "$FTP_ROOT/$grupo $jaula/$grupo none bind 0 0" >> /etc/fstab
    fi
}

# Elimina un usuario, su jaula y sus bind mounts
eliminar_usuario() {
    read -p "Nombre de usuario a eliminar: " usuario

    if ! id "$usuario" > /dev/null 2>&1; then
        echo "El usuario $usuario no existe."
        return 1
    fi

    local grupo_actual
    grupo_actual=$(id -gn "$usuario")
    local jaula="$FTP_ROOT/$usuario"

    # Desmonta bind mounts activos
    if mountpoint -q "$jaula/general"; then
        umount "$jaula/general"
    fi

    if mountpoint -q "$jaula/$grupo_actual"; then
        umount "$jaula/$grupo_actual"
    fi

    # Elimina entradas de fstab
    sed -i "\|$jaula|d" /etc/fstab

    # Elimina la jaula
    rm -rf "${jaula:?}"

    # Elimina del userlist
    sed -i "/^$usuario$/d" /etc/vsftpd.userlist

    # Elimina el usuario del sistema
    userdel "$usuario"

    echo "Usuario $usuario eliminado."
}

cambiar_grupo_usuario() {
    read -p "Nombre de usuario a cambiar de grupo: " usuario

    if ! id "$usuario" > /dev/null 2>&1; then
        echo "El usuario $usuario no existe."
        return 1
    fi

    while true; do
        read -p "Nuevo grupo (reprobados/recursadores): " nuevo_grupo
        if [[ "$nuevo_grupo" == "reprobados" || "$nuevo_grupo" == "recursadores" ]]; then
            break
        fi
        echo "Grupo inválido."
    done

    local grupo_actual
    grupo_actual=$(id -gn "$usuario")
    local jaula="$FTP_ROOT/$usuario"

    # Matar sesiones activas del usuario antes de cambiar grupo
    pkill -u "$usuario" -9 2>/dev/null
    sleep 1

    # Desmonta la carpeta del grupo anterior si está montada
    if mountpoint -q "$jaula/$grupo_actual"; then
        umount "$jaula/$grupo_actual"
    fi

    # Elimina la carpeta del grupo anterior siempre
    rm -rf "${jaula:?}/${grupo_actual:?}"

    # Elimina el mount anterior de fstab
    sed -i "\|$jaula/$grupo_actual|d" /etc/fstab

    # Cambia el grupo principal del usuario
    usermod -g "$nuevo_grupo" -G ftp "$usuario"

    # Monta la carpeta del nuevo grupo
    mkdir -p "$jaula/$nuevo_grupo"
    mount --bind "$FTP_ROOT/$nuevo_grupo" "$jaula/$nuevo_grupo"

    # Persiste el nuevo mount
    persistir_mounts "$usuario" "$nuevo_grupo"

    echo "Usuario $usuario cambiado a grupo $nuevo_grupo."
}