#!/bin/bash

# ================================================
#  CONFIGURACION INICIAL DEL SERVIDOR FTP (vsftpd)
# ================================================

source "$(dirname "$0")/funciones_ftp.sh"

echo "=================================================="
echo " CONFIGURACION INICIAL DEL SERVIDOR FTP (vsftpd)"
echo "=================================================="

# 1. Instalar vsftpd si no está instalado
echo "Verificando instalacion de vsftpd..."
if ! command -v vsftpd &> /dev/null; then
    pacman -Sy --noconfirm vsftpd
    echo "vsftpd instalado correctamente."
else
    echo "vsftpd ya esta instalado."
fi

# 2. Crear estructura de directorios
echo "Creando estructura de directorios..."
RUTAS=(
    "/srv/ftp"
    "/srv/ftp/general"
    "/srv/ftp/grupos"
    "/srv/ftp/grupos/reprobados"
    "/srv/ftp/grupos/recursadores"
    "/srv/ftp/usuarios"
    "/var/run/vsftpd/empty"
)
for ruta in "${RUTAS[@]}"; do
    if [ ! -d "$ruta" ]; then
        mkdir -p "$ruta"
    fi
done
echo "Estructura de directorios creada."

# 3. Crear grupos del sistema si no existen
echo "Verificando grupos del sistema..."
for grupo in reprobados recursadores; do
    if ! getent group "$grupo" > /dev/null 2>&1; then
        groupadd "$grupo"
        echo "Grupo $grupo creado."
    else
        echo "Grupo $grupo ya existe."
    fi
done

# 4. Permisos de carpetas
echo "Configurando permisos..."
chmod 755 /srv/ftp
chmod 755 /srv/ftp/general
chown root:root /srv/ftp/general

chmod 775 /srv/ftp/grupos/reprobados
chown root:reprobados /srv/ftp/grupos/reprobados

chmod 775 /srv/ftp/grupos/recursadores
chown root:recursadores /srv/ftp/grupos/recursadores

# 5. Configurar vsftpd.conf
echo "Configurando vsftpd..."
cat > /etc/vsftpd.conf << 'EOF'
listen=YES
listen_ipv6=NO
background=NO
local_enable=YES
write_enable=YES
local_umask=022
anonymous_enable=YES
anon_upload_enable=NO
anon_mkdir_write_enable=NO
no_anon_password=YES
anon_root=/srv/ftp/general
chroot_local_user=YES
allow_writeable_chroot=NO
user_sub_token=$USER
local_root=/srv/ftp/usuarios/$USER
userlist_enable=YES
userlist_file=/etc/vsftpd.userlist
userlist_deny=NO
pasv_enable=YES
pasv_min_port=40000
pasv_max_port=40100
hide_ids=YES
secure_chroot_dir=/var/run/vsftpd/empty
xferlog_enable=YES
xferlog_file=/var/log/vsftpd.log
pam_service_name=vsftpd
EOF

# Crear userlist si no existe
touch /etc/vsftpd.userlist

# 6. Habilitar e iniciar vsftpd
echo "Iniciando vsftpd..."
systemctl enable vsftpd
systemctl restart vsftpd

if systemctl is-active --quiet vsftpd; then
    echo "vsftpd iniciado correctamente."
else
    echo "Error al iniciar vsftpd. Revisa los logs con: journalctl -xe"
fi

echo "Servidor FTP configurado exitosamente."
echo "=================================================="

# 7. Menu interactivo
while true; do
    echo ""
    echo "--- GESTOR DE USUARIOS FTP (LINUX) ---"
    echo "1. Agregar Usuarios"
    echo "2. Cambiar de Grupo"
    echo "3. Eliminar Usuario"
    echo "4. Salir"
    read -rp "Elige una opcion (1-4): " opcion

    case "$opcion" in
        1)
            read -rp "Cuantos usuarios deseas agregar? " num
            for ((i=1; i<=num; i++)); do
                echo "--- Creando usuario $i de $num ---"
                nombre=$(capturar_usuario_valido "Coloque el nombre del usuario: ")
                contra=$(capturar_contra)
                grupo=$(capturar_grupo)
                crear_usuario_ftp "$nombre" "$contra" "$grupo"
            done
            ;;
        2)
            cambiar_grupo_ftp
            ;;
        3)
            eliminar_usuario_ftp
            ;;
        4)
            echo "Cerrando el script. Exito con la practica."
            exit 0
            ;;
        *)
            echo "Opcion no valida. Intenta de nuevo."
            ;;
    esac
done
