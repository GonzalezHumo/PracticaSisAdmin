#!/bin/bash
# ============================================================
# main.sh - Practica 5: Automatizacion de Servidor FTP
#           Arch Linux + vsftpd
# ============================================================

# Verificar root
if [[ $EUID -ne 0 ]]; then
    echo "[ERROR] Este script debe ejecutarse como root (sudo)."
    exit 1
fi

# Ruta base del servidor FTP
RUTA_FTP="/srv/ftp"

MODULOS="$(dirname "$0")/../Utils/linux"

source "$MODULOS/instalar.sh"
source "$MODULOS/directorios.sh"
source "$MODULOS/usuarios.sh"
source "$MODULOS/ftp-config.sh"
source "$MODULOS/cam-grupo.sh"


# ============================================================
mostrar_banner() {
    clear
    echo "============================================="
    echo "   PRACTICA 5 - SERVIDOR FTP AUTOMATIZADO   "
    echo "   Arch Linux + vsftpd                      "
    echo "============================================="
    echo ""
}

mostrar_menu() {
    echo ""
    echo "--- MENU PRINCIPAL ---"
    echo "  1. Instalar y configurar servidor FTP (primera vez)"
    echo "  2. Crear nuevos usuarios"
    echo "  3. Cambiar grupo de un usuario"
    echo "  4. Listar usuarios y grupos"
    echo "  5. Salir"
    echo ""
    echo -n "Seleccione una opcion: "
}

# ============================================================
# INICIO
# ============================================================
mostrar_banner

# Crear carpeta raiz si no existe
mkdir -p "$RUTA_FTP"

# Bucle principal
while true; do
    mostrar_banner
    mostrar_menu
    read opcion

    case $opcion in
        1)
            echo ""
            echo "[PASO 1] Instalando vsftpd..."
            instalar_ftp
            echo ""
            echo "[PASO 2] Inicializando grupos del sistema..."
            inicializar_grupos
            echo ""
            echo "[PASO 3] Creando estructura de directorios..."
            inicializar_carpeta_raiz "$RUTA_FTP"
            echo ""
            echo "[PASO 4] Configurando vsftpd..."
            configurar_ftp "$RUTA_FTP"
            echo ""
            echo "[OK] Servidor FTP listo."
            read -p "Presione Enter para continuar..."
            ;;
        2)
            crear_usuarios "$RUTA_FTP"
            read -p "Presione Enter para continuar..."
            ;;
        3)
            cambiar_grupo_usuario "$RUTA_FTP"
            read -p "Presione Enter para continuar..."
            ;;
        4)
            listar_usuarios
            read -p "Presione Enter para continuar..."
            ;;
        5)
            echo ""
            echo "Saliendo..."
            exit 0
            ;;
        *)
            echo "[!] Opcion no valida."
            sleep 1
            ;;
    esac
done