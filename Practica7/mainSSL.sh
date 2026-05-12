#!/bin/bash
# ============================================================
#  mainSSL.sh  -  Practica 7 - Administracion de Sistemas
#  Orquestador principal Linux
#  Infraestructura de Despliegue Seguro e Instalacion Hibrida
# ============================================================

# Verificar ejecucion como root
if [ "$EUID" -ne 0 ]; then
    echo "[!] Este script debe ejecutarse como root (sudo)." >&2
    exit 1
fi

# Cargar funciones
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FUNCIONES="$SCRIPT_DIR/funciones_SSL.sh"

if [ ! -f "$FUNCIONES" ]; then
    echo "[!] No se encontro funciones_SSL.sh en: $FUNCIONES" >&2
    exit 1
fi

source "$FUNCIONES"

# ── Colores (por si se sourcea de nuevo) ─────────────────────
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ============================================================
#  BANNER
# ============================================================

mostrar_banner_p7() {
    clear
    echo -e "${CYAN}============================================================${NC}"
    echo -e "${CYAN}  Practica 7 — Infraestructura de Despliegue Seguro        ${NC}"
    echo -e "${CYAN}  Instalacion Hibrida (FTP/Web) + SSL/TLS — LINUX          ${NC}"
    echo -e "${CYAN}============================================================${NC}"
    echo ""
}

# ============================================================
#  MENU PRINCIPAL
# ============================================================

mostrar_menu_p7() {
    echo -e "${CYAN}¿Que deseas hacer?${NC}"
    echo "  [1] Instalar servicio via WEB  (gestor de paquetes)"
    echo "  [2] Instalar servicio via FTP  (repositorio privado)"
    echo "  [3] Activar SSL/TLS en un servicio instalado"
    echo "  [4] Verificar estado SSL de todos los servicios"
    echo "  [5] Salir"
    echo ""
    while true; do
        read -rp "Opcion: " MENU_OPCION
        MENU_OPCION=$(echo "$MENU_OPCION" | tr -d '[:space:]')
        if [[ "$MENU_OPCION" =~ ^[1-5]$ ]]; then
            return 0
        else
            echo -e "${RED}[!] Opcion invalida. Elige entre 1 y 5.${NC}"
        fi
    done
}

# ============================================================
#  SUBMENU — ELEGIR SERVICIO PARA SSL
# ============================================================

elegir_servicio_ssl() {
    echo ""
    echo -e "${CYAN}¿En que servicio deseas activar SSL?${NC}"
    echo "  [1] Apache  (HTTP -> HTTPS, puerto 443)"
    echo "  [2] Nginx   (HTTP -> HTTPS, puerto 443)"
    echo "  [3] Tomcat  (HTTPS, puerto 8443)"
    echo "  [4] vsftpd  (FTPS, canal control y datos cifrados)"
    echo "  [5] Todos los anteriores"
    echo ""

    while true; do
        read -rp "Opcion: " SSL_OPCION
        SSL_OPCION=$(echo "$SSL_OPCION" | tr -d '[:space:]')
        if [[ "$SSL_OPCION" =~ ^[1-5]$ ]]; then
            return 0
        else
            echo -e "${RED}[!] Opcion invalida. Elige entre 1 y 5.${NC}"
        fi
    done
}

# ============================================================
#  SUBMENU — INSTALACION VIA WEB (reutiliza funciones P6)
# ============================================================

instalar_via_web() {
    # Cargar funciones de la P6 si existen
    local func_p6="$SCRIPT_DIR/http_functions.sh"
    if [ ! -f "$func_p6" ]; then
        echo -e "${RED}[!] No se encontro http_functions.sh (Practica 6).${NC}"
        echo -e "${YELLOW}[!] Coloca http_functions.sh en el mismo directorio que este script.${NC}"
        return 1
    fi

    source "$func_p6"

    echo ""
    echo -e "${CYAN}--- Instalacion via Gestor de Paquetes (WEB) ---${NC}"
    echo -e "${CYAN}Selecciona el servidor a instalar:${NC}"
    echo "  [1] Apache"
    echo "  [2] Nginx"
    echo "  [3] Tomcat"
    echo ""

    local op
    while true; do
        read -rp "Opcion: " op
        op=$(echo "$op" | tr -d '[:space:]')
        if [[ "$op" =~ ^[1-3]$ ]]; then break
        else echo -e "${RED}[!] Opcion invalida.${NC}"
        fi
    done

    case "$op" in
        1)
            local versiones lts latest version puerto
            versiones=$(obtener_versiones_apache)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Apache")
            puerto=$(pedir_puerto)
            instalar_apache "$version" "$puerto"
            ;;
        2)
            local versiones lts latest version puerto
            versiones=$(obtener_versiones_nginx)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Nginx")
            puerto=$(pedir_puerto)
            instalar_nginx "$version" "$puerto"
            ;;
        3)
            local versiones lts latest version puerto
            versiones=$(obtener_versiones_tomcat)
            lts=$(echo "$versiones" | cut -d'|' -f1)
            latest=$(echo "$versiones" | cut -d'|' -f2)
            version=$(seleccionar_version "$lts" "$latest" "Tomcat")
            puerto=$(pedir_puerto)
            instalar_tomcat "$version" "$puerto"
            ;;
    esac

    # Preguntar si desea activar SSL inmediatamente
    echo ""
    if preguntar_ssl "el servicio recien instalado"; then
        activar_ssl_segun_opcion "$op"
    fi
}

# Activa SSL segun el numero de servicio (1=Apache, 2=Nginx, 3=Tomcat)
activar_ssl_segun_opcion() {
    local op="$1"
    case "$op" in
        1) activar_ssl_apache ;;
        2) activar_ssl_nginx  ;;
        3)
            # Detectar paquete tomcat instalado
            local pkg="tomcat10"
            command -v tomcat11 &>/dev/null && pkg="tomcat11"
            activar_ssl_tomcat "$pkg"
            ;;
        4) activar_ssl_vsftpd ;;
    esac
}

# ============================================================
#  FLUJO — ACTIVAR SSL (opcion 3 del menu principal)
# ============================================================

flujo_activar_ssl() {
    elegir_servicio_ssl

    case "$SSL_OPCION" in
        1)
            if preguntar_ssl "Apache"; then
                activar_ssl_apache
            fi
            ;;
        2)
            if preguntar_ssl "Nginx"; then
                activar_ssl_nginx
            fi
            ;;
        3)
            if preguntar_ssl "Tomcat"; then
                local pkg="tomcat10"
                command -v tomcat11 &>/dev/null && pkg="tomcat11"
                activar_ssl_tomcat "$pkg"
            fi
            ;;
        4)
            if preguntar_ssl "vsftpd (FTPS)"; then
                activar_ssl_vsftpd
            fi
            ;;
        5)
            echo -e "${CYAN}[*] Activando SSL en todos los servicios...${NC}"
            activar_ssl_apache
            activar_ssl_nginx
            local pkg="tomcat10"
            command -v tomcat11 &>/dev/null && pkg="tomcat11"
            activar_ssl_tomcat "$pkg"
            activar_ssl_vsftpd
            ;;
    esac
}

# ============================================================
#  FLUJO PRINCIPAL
# ============================================================

mostrar_banner_p7

while true; do
    mostrar_menu_p7

    case "$MENU_OPCION" in
        1)
            instalar_via_web
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            mostrar_banner_p7
            ;;
        2)
            instalar_desde_ftp
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            mostrar_banner_p7
            ;;
        3)
            flujo_activar_ssl
            echo ""
            read -rp "Presiona ENTER para volver al menu..."
            mostrar_banner_p7
            ;;
        4)
            resumen_verificacion_linux
            read -rp "Presiona ENTER para volver al menu..."
            mostrar_banner_p7
            ;;
        5)
            echo -e "${GREEN}Cerrando el script. Exito con la practica.${NC}"
            exit 0
            ;;
    esac
done
