# main.ps1
# Punto de entrada principal - carga modulos y muestra el menu

# Ruta base de los modulos relativa a este script
$modulos = "$PSScriptRoot\..\Utils\windows"

. "$modulos\func_comunes.ps1"
. "$modulos\func_dhcp.ps1"
. "$modulos\func_dns.ps1"
. "$modulos\func_ssh.ps1"

# Verificar permisos de administrador antes de continuar
Test-Admin

function Show-Menu {
    Clear-Host
    Write-Host "____________________________________________"
    Write-Host "        Administracion de Servidores        "
    Write-Host "____________________________________________"
    Write-Host ""
    Write-Host "  DHCP"
    Write-Host "   1. Verificar instalacion"
    Write-Host "   2. Instalar servidor"
    Write-Host "   3. Configurar o reconfigurar scope"
    Write-Host "   4. Activar o desactivar scope"
    Write-Host "   5. Eliminar scope"
    Write-Host "   6. Listar scopes"
    Write-Host "   7. Monitorear concesiones"
    Write-Host "   8. Monitorear estado"
    Write-Host ""
    Write-Host "  DNS"
    Write-Host "   9.  Verificar instalacion"
    Write-Host "   10. Instalar servidor"
    Write-Host "   11. Agregar zona"
    Write-Host "   12. Listar zonas"
    Write-Host "   13. Validar configuracion"
    Write-Host "   14. Monitorear estado"
    Write-Host ""
    Write-Host "  SSH"
    Write-Host "   15. Verificar instalacion"
    Write-Host "   16. Instalar servidor"
    Write-Host "   17. Monitorear estado"
    Write-Host ""
    Write-Host "   0. Salir"
    Write-Host "____________________________________________"
}

while ($true) {
    Show-Menu
    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        "1"  { Test-DHCP }
        "2"  { Install-DHCP }
        "3"  { Set-Scope }
        "4"  { Switch-Scope }
        "5"  { Remove-Scope }
        "6"  { Get-Scopes }
        "7"  { Get-Concesiones }
        "8"  { Get-EstadoDHCP }
        "9"  { Test-DNS }
        "10" { Install-DNS }
        "11" { Add-Zona }
        "12" { Get-Zonas }
        "13" { Test-Configuracion }
        "14" { Get-EstadoDNS }
        "15" { Test-SSH }
        "16" { Install-SSH }
        "17" { Get-EstadoSSH }
        "0"  { Write-Host "Saliendo..."; exit 0 }
        default { Write-Host "Opcion invalida" }
    }

    Read-Host "Presiona Enter para continuar"
}