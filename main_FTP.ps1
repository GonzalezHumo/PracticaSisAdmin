Import-Module "$PSScriptRoot\funciones_FTP.ps1" -ErrorAction Stop

Write-Host "=================================================="
Write-Host " CONFIGURACION INICIAL DEL SERVIDOR FTP (IIS)"
Write-Host "=================================================="

# 1. Instalar FTP de forma silenciosa e idempotente
Write-Host "Instalando IIS y Servicio FTP..."
Install-WindowsFeature Web-Server, Web-FTP-Server -IncludeManagementTools | Out-Null

# 2. Crear carpetas base si no existen
Write-Host "Creando estructura de directorios..."
$rutas = @(
    "C:\FTP",
    "C:\FTP\grupos",
    "C:\FTP\grupos\recursadores",
    "C:\FTP\grupos\reprobados",
    "C:\FTP\LocalUser",
    "C:\FTP\LocalUser\Public",
    "C:\FTP\LocalUser\Public\general"
)
foreach ($ruta in $rutas) {
    if (-not (Test-Path $ruta)) {
        New-Item -Path $ruta -ItemType Directory -Force | Out-Null
    }
}

Write-Host "Configurando llaves de acceso para los grupos..."
$grupos = @("reprobados", "recursadores")

foreach ($g in $grupos) {
    $rutaGrupo = "C:\FTP\grupos\$g"
    $acl = Get-Acl $rutaGrupo
    $acl.SetAccessRuleProtection($true, $false)
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($adminRule)
    
    $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule($g, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.AddAccessRule($groupRule)
    
    Set-Acl $rutaGrupo $acl
}
Write-Host "Seguridad NTFS aplicada correctamente."

# Asignar permisos NTFS a la carpeta general para que todos puedan leer y escribir
$AclGeneral = Get-Acl "C:\FTP\LocalUser\Public\general"
$AccessRuleGen = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
$AclGeneral.SetAccessRule($AccessRuleGen)
Set-Acl "C:\FTP\LocalUser\Public\general" $AclGeneral

# 3. Configurar firewall para FTP
Write-Host "Configurando Firewall..."
if (-not (Get-NetFirewallRule -DisplayName "FTP_Practica" -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -DisplayName "FTP_Practica" -Direction Inbound -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
}

# 4. Crear sitio FTP y aislar usuarios
Write-Host "Configurando Sitio FTP en IIS..."
Import-Module WebAdministration
if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
    New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP" -Force | Out-Null
}

# Configurar User Isolation
Set-WebConfigurationProperty -Filter "/system.applicationHost/sites/siteDefaults/ftpServer/userIsolation" -Name "mode" -Value "IsolateAllDirectories"

# 5. Grupos locales en Windows
Write-Host "Verificando grupos del sistema..."
$ADSI = [ADSI]"WinNT://$env:ComputerName"
$gruposNecesarios = @("reprobados", "recursadores")
foreach ($g in $gruposNecesarios) {
    if (-not ($ADSI.Children | Where-Object { $_.SchemaClassName -eq 'Group' -and $_.Name -eq $g })) {
        $nuevoGrupo = $ADSI.Create("Group", $g)
        $nuevoGrupo.SetInfo()
    }
}

# 6. Reglas de Autorizacion y Autenticacion IIS
Write-Host "Aplicando reglas de seguridad IIS..."

# Limpiar reglas existentes para evitar duplicados
Remove-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" -Name "." -Location "FTP" -ErrorAction SilentlyContinue

# Permitir lectura a usuarios Anonimos (IUSR)
Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{ accessType = "Allow"; users = "IUSR"; permissions = 1 } -Location "FTP"

# Permitir Lectura y Escritura a los grupos
Add-WebConfiguration "/system.ftpServer/security/authorization" -PSPath "IIS:\" -Value @{ accessType = "Allow"; roles = "reprobados,recursadores"; permissions = 3 } -Location "FTP"

# Habilitar cuenta Anonima
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""

# Habilitar Autenticacion Basica y quitar SSL obligatorio
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
Set-ItemProperty -Path "IIS:\Sites\FTP" -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0

# Reiniciar el sitio para aplicar cambios
Restart-WebItem "IIS:\Sites\FTP"
Write-Host "Servidor FTP configurado exitosamente."
Write-Host "=================================================="

# 7. Menu interactivo
while ($true) {
    Write-Host ""
    Write-Host "--- GESTOR DE USUARIOS FTP (WINDOWS) ---"
    Write-Host "1. Agregar Usuarios"
    Write-Host "2. Cambiar de Grupo"
    Write-Host "3. Eliminar Usuario"
    Write-Host "4. Salir"
    $opcion = Read-Host "Elige una opcion (1-4)"

    switch ($opcion) {
        "1" {
            $num = Read-Host "Cuantos usuarios deseas agregar?"
            for ($i = 1; $i -le [int]$num; $i++) {
                Write-Host "--- Creando usuario $i de $num ---"
                $FTPUserName = capturarUsuarioFTPValido "Coloque el nombre del usuario: "
                $FTPPassword = capturarContra
                $FTPUserGroupName = capturarGrupoFTP
                CrearUsuarioFTP -FTPUserName $FTPUserName -FTPPassword $FTPPassword -FTPUserGroupName $FTPUserGroupName
            }
        }
        "2" {
            CambiarGrupoFTP
        }
        "3" {
            EliminarUsuarioFTP
        }
        "4" {
            Write-Host "Cerrando el script. Exito con la practica."
            exit
        }
        default {
            Write-Host "Opcion no valida. Intenta de nuevo."
        }
    }
}
