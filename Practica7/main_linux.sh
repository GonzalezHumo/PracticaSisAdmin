#!/bin/bash
# ============================================================
#  main_linux.sh  -  Practica 6 - Administracion de Sistemas
#  Rosa Karina Rosas Burgueno
#  Script principal - solo llamadas a funciones
# ============================================================

# Verificar ejecucion como root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

# Cargar funciones
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCIONES="$SCRIPT_DIR/http_functions.sh"

if [ ! -f "$FUNCIONES" ]; then
    echo "[!] No se encontro http_functions.sh en: $FUNCIONES" >&2
    exit 1
fi

# shellcheck source=./http_functions.sh
source "$FUNCIONES"

# ── Flujo principal ──────────────────────────────────────────

mostrar_banner

while true; do
    opcion=$(mostrar_menu)

    case "$opcion" in
        1)
            versiones=$(obtener_versiones_apache)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Apache")
            puerto=$(pedir_puerto)
            instalar_apache "$version" "$puerto"
            echo ""
            echo -e "\033[0;36m=================================================\033[0m"
            echo -e "\033[0;32m Aprovisionamiento completado.\033[0m"
            echo -e "\033[0;36m Verifica con: curl -I http://localhost:$puerto\033[0m"
            echo -e "\033[0;36m=================================================\033[0m"
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            ;;
        2)
            versiones=$(obtener_versiones_nginx)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Nginx")
            puerto=$(pedir_puerto)
            instalar_nginx "$version" "$puerto"
            echo ""
            echo -e "\033[0;36m=================================================\033[0m"
            echo -e "\033[0;32m Aprovisionamiento completado.\033[0m"
            echo -e "\033[0;36m Verifica con: curl -I http://localhost:$puerto\033[0m"
            echo -e "\033[0;36m=================================================\033[0m"
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            ;;
        3)
            versiones=$(obtener_versiones_tomcat)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Tomcat")
            puerto=$(pedir_puerto)
            instalar_tomcat "$version" "$puerto"
            echo ""
            echo -e "\033[0;36m=================================================\033[0m"
            echo -e "\033[0;32m Aprovisionamiento completado.\033[0m"
            echo -e "\033[0;36m Verifica con: curl -I http://localhost:$puerto\033[0m"
            echo -e "\033[0;36m=================================================\033[0m"
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            ;;
        4)
            echo "Saliendo..."
            exit 0
            ;;
    esac
done
