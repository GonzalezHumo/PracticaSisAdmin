#!/bin/bash

# main.sh
# Punto de entrada principal - carga modulos y muestra el menu

# Ruta base de los modulos relativa a este script
MODULOS="$(dirname "$0")/../Utils/linux"

source "$MODULOS/func_comunes.sh"
source "$MODULOS/func_dhcp.sh"
source "$MODULOS/func_dns.sh"
source "$MODULOS/func_ssh.sh"

# Verificar permisos de root antes de continuar
verificar_root

menu(){
    clear
    echo "____________________________________________"
    echo "        Administracion de Servidores        "
    echo "____________________________________________"
    echo ""
    echo "  DHCP"
    echo "   1. Verificar instalacion"
    echo "   2. Instalar servidor"
    echo "   3. Configurar o reconfigurar scope"
    echo "   4. Activar o desactivar scope"
    echo "   5. Eliminar scope"
    echo "   6. Listar scopes"
    echo "   7. Monitorear concesiones"
    echo "   8. Monitorear estado"
    echo ""
    echo "  DNS"
    echo "   9.  Verificar instalacion"
    echo "   10. Instalar servidor"
    echo "   11. Agregar zona"
    echo "   12. Listar zonas"
    echo "   13. Validar configuracion"
    echo "   14. Monitorear estado"
    echo ""
    echo "  SSH"
    echo "   15. Verificar instalacion"
    echo "   16. Instalar servidor"
    echo "   17. Monitorear estado"
    echo ""
    echo "   0. Salir"
    echo "____________________________________________"
}

while true; do
    menu
    read -rp "Seleccione una opcion: " opcion

    case $opcion in
        1)  verificar_dhcp ;;
        2)  instalar_dhcp ;;
        3)  configurar_reconfigurar_scope ;;
        4)  activar_desactivar_scope ;;
        5)  eliminar_scope ;;
        6)  listar_scopes ;;
        7)  monitorear_concesiones ;;
        8)  monitorear_estado_dhcp ;;
        9)  verificar_bind ;;
        10) instalar_bind ;;
        11) agregar_zona ;;
        12) listar_zonas ;;
        13) validar_configuracion ;;
        14) monitorear_estado_dns ;;
        15) verificar_ssh ;;
        16) instalar_ssh ;;
        17) monitorear_estado_ssh ;;
        0)  echo "Saliendo..."; exit 0 ;;
        *)  echo "Opcion invalida" ;;
    esac

    read -rp "Presiona Enter para continuar..."
done