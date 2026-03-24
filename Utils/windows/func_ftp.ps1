$FtpRaiz     = "C:\inetpub\ftproot"
$SitioNombre = "SitioFTP"
$SitioPuerto = 21

# instala el rol FTP si no está presente
function Install-RolFtp {
    foreach ($c in @("Web-FTP-Server", "Web-Mgmt-Console", "Web-Scripting-Tools")) {
        if (-not (Get-WindowsFeature -Name $c).Installed) {
            Write-Host "Instalando $c..."
            Install-WindowsFeature -Name $c -IncludeManagementTools | Out-Null
        }
    }
    Import-Module WebAdministration -ErrorAction Stop
}

# crea carpetas base y aplica permisos NTFS iniciales
function Set-EstructuraBase {
    foreach ($carpeta in @("general", "reprobados", "recursadores", "LocalUser")) {
        $ruta = Join-Path $FtpRaiz $carpeta
        if (-not (Test-Path $ruta)) {
            New-Item -ItemType Directory -Path $ruta -Force | Out-Null
        }
    }

    # general: anónimo lee, usuarios autenticados escriben
    icacls "$FtpRaiz\general" /inheritance:r               | Out-Null
    icacls "$FtpRaiz\general" /grant "IUSR:(OI)(CI)R"      | Out-Null
    icacls "$FtpRaiz\general" /grant "Usuarios:(OI)(CI)M"  | Out-Null

    # cada carpeta de grupo solo la escribe ese grupo
    foreach ($grupo in @("reprobados", "recursadores")) {
        icacls "$FtpRaiz\$grupo" /inheritance:r               | Out-Null
        icacls "$FtpRaiz\$grupo" /grant "SYSTEM:(OI)(CI)F"   | Out-Null
        icacls "$FtpRaiz\$grupo" /grant "${grupo}:(OI)(CI)M" | Out-Null
    }
}

# crea y configura el sitio FTP en IIS
function New-SitioFtp {
    if (-not (Get-WebSite -Name $SitioNombre -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name $SitioNombre -Port $SitioPuerto -PhysicalPath $FtpRaiz -Force | Out-Null
    }

    # sin SSL para entorno de laboratorio
    Set-ItemProperty "IIS:\Sites\$SitioNombre" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
    Set-ItemProperty "IIS:\Sites\$SitioNombre" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0

    Set-ItemProperty "IIS:\Sites\$SitioNombre" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$SitioNombre" -Name ftpServer.security.authentication.basicAuthentication.enabled    -Value $true

    # anónimo: solo lectura
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users="?"; permissions="Read"} `
        -PSPath "IIS:\" -Location $SitioNombre -Force

    # autenticados: lectura y escritura
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users="*"; permissions="Read,Write"} `
        -PSPath "IIS:\" -Location $SitioNombre -Force

    # modo 3 = IsolateAllDirectories (chroot por usuario)
    Set-ItemProperty "IIS:\Sites\$SitioNombre" -Name ftpServer.userIsolation.mode -Value 3

    Start-WebSite -Name $SitioNombre -ErrorAction SilentlyContinue
}

# crea los grupos locales requeridos si no existen
function New-GruposLocales {
    foreach ($grupo in @("reprobados", "recursadores")) {
        if (-not (Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) {
            New-LocalGroup -Name $grupo | Out-Null
            Write-Host "Grupo '$grupo' creado."
        }
    }
}

# aplica permisos a la raíz aislada y carpeta personal del usuario
function Set-PermisosUsuario {
    param([string]$Nombre)

    $raizUsuario = Join-Path $FtpRaiz "LocalUser\$Nombre"
    if (-not (Test-Path $raizUsuario)) {
        New-Item -ItemType Directory -Path $raizUsuario -Force | Out-Null
    }

    # raíz del chroot: solo RX para el usuario, escritura aquí causa error 530
    icacls $raizUsuario /inheritance:r                      | Out-Null
    icacls $raizUsuario /grant "SYSTEM:(OI)(CI)F"           | Out-Null
    icacls $raizUsuario /grant "Administradores:(OI)(CI)F"  | Out-Null
    icacls $raizUsuario /grant "${Nombre}:(OI)(CI)RX"       | Out-Null

    # carpeta personal: el usuario puede escribir
    $personal = Join-Path $raizUsuario $Nombre
    if (-not (Test-Path $personal)) {
        New-Item -ItemType Directory -Path $personal -Force | Out-Null
    }

    icacls $personal /inheritance:r                         | Out-Null
    icacls $personal /grant "SYSTEM:(OI)(CI)F"              | Out-Null
    icacls $personal /grant "Administradores:(OI)(CI)F"     | Out-Null
    icacls $personal /grant "${Nombre}:(OI)(CI)M"           | Out-Null
}

# registra los directorios virtuales visibles al conectarse por FTP
function Register-DirectoriosVirtuales {
    param([string]$Nombre, [string]$Grupo)

    $mapeo = @{
        "general" = "$FtpRaiz\general"
        $Grupo    = "$FtpRaiz\$Grupo"
        $Nombre   = "$FtpRaiz\LocalUser\$Nombre\$Nombre"
    }

    foreach ($vd in $mapeo.GetEnumerator()) {
        $rutaIis = "IIS:\Sites\$SitioNombre\LocalUser\$Nombre\$($vd.Key)"
        if (-not (Test-Path $rutaIis -ErrorAction SilentlyContinue)) {
            New-WebVirtualDirectory -Site $SitioNombre -Application "/" `
                -Name "LocalUser/$Nombre/$($vd.Key)" `
                -PhysicalPath $vd.Value | Out-Null
        }
    }
}

# crea el usuario local, lo asigna al grupo y prepara su estructura completa
function New-UsuarioFtp {
    param([string]$Nombre, [string]$Contrasena, [string]$Grupo)

    if (Get-LocalUser -Name $Nombre -ErrorAction SilentlyContinue) {
        $resp = Read-Host "El usuario '$Nombre' ya existe. ¿Sobreescribir? (s/n)"
        if ($resp -notmatch '^[sS]$') {
            Write-Host "Usuario '$Nombre' omitido."
            return
        }
        Remove-UsuarioFtp -Nombre $Nombre
    }

    $securePass = ConvertTo-SecureString $Contrasena -AsPlainText -Force
    New-LocalUser -Name $Nombre -Password $securePass `
        -PasswordNeverExpires $true `
        -UserMayNotChangePassword $false `
        -AccountNeverExpires | Out-Null

    Add-LocalGroupMember -Group $Grupo -Member $Nombre -ErrorAction SilentlyContinue

    Set-PermisosUsuario          -Nombre $Nombre
    Register-DirectoriosVirtuales -Nombre $Nombre -Grupo $Grupo

    Write-Host "Usuario '$Nombre' creado en el grupo '$Grupo'."
}

# cambia al usuario de grupo y actualiza su directorio virtual
function Set-GrupoUsuario {
    param([string]$Nombre, [string]$NuevoGrupo)

    $grupoAnterior = if ($NuevoGrupo -eq "reprobados") { "recursadores" } else { "reprobados" }

    Remove-LocalGroupMember -Group $grupoAnterior -Member $Nombre -ErrorAction SilentlyContinue
    Add-LocalGroupMember    -Group $NuevoGrupo    -Member $Nombre -ErrorAction SilentlyContinue

    $vdAnterior = "IIS:\Sites\$SitioNombre\LocalUser\$Nombre\$grupoAnterior"
    if (Test-Path $vdAnterior -ErrorAction SilentlyContinue) {
        Remove-WebVirtualDirectory -Site $SitioNombre -Application "/" `
            -Name "LocalUser/$Nombre/$grupoAnterior" | Out-Null
    }

    $vdNuevo = "IIS:\Sites\$SitioNombre\LocalUser\$Nombre\$NuevoGrupo"
    if (-not (Test-Path $vdNuevo -ErrorAction SilentlyContinue)) {
        New-WebVirtualDirectory -Site $SitioNombre -Application "/" `
            -Name "LocalUser/$Nombre/$NuevoGrupo" `
            -PhysicalPath "$FtpRaiz\$NuevoGrupo" | Out-Null
    }

    Write-Host "Usuario '$Nombre' movido de '$grupoAnterior' a '$NuevoGrupo'."
}

# elimina el usuario, lo quita de grupos y borra su carpeta aislada
function Remove-UsuarioFtp {
    param([string]$Nombre)

    foreach ($g in @("reprobados", "recursadores")) {
        Remove-LocalGroupMember -Group $g -Member $Nombre -ErrorAction SilentlyContinue
    }

    Remove-LocalUser -Name $Nombre -ErrorAction SilentlyContinue

    $raiz = Join-Path $FtpRaiz "LocalUser\$Nombre"
    if (Test-Path $raiz) {
        Remove-Item -Path $raiz -Recurse -Force | Out-Null
    }

    Write-Host "Usuario '$Nombre' eliminado."
}

# reinicia el sitio FTP
function Restart-SitioFtp {
    Restart-WebSite -Name $SitioNombre
    Write-Host "Sitio FTP reiniciado."
}

# solicita y valida cantidad de usuarios
function Read-CantidadUsuarios {
    do {
        $entrada = Read-Host "¿Cuántos usuarios desea crear?"
    } while (-not ($entrada -match '^\d+$') -or [int]$entrada -le 0)
    return [int]$entrada
}

# recorre la cantidad solicitada y crea cada usuario
function Invoke-CreacionUsuarios {
    $n = Read-CantidadUsuarios
    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`nUsuario $i de $n"
        $nombre     = Read-Host "Nombre de usuario"
        $contrasena = Read-Host "Contraseña"
        do {
            $grupo = Read-Host "Grupo (reprobados / recursadores)"
        } while ($grupo -notin @("reprobados", "recursadores"))

        New-UsuarioFtp -Nombre $nombre -Contrasena $contrasena -Grupo $grupo
    }
}

# solicita usuario y nuevo grupo para el cambio
function Invoke-CambioGrupo {
    $nombre = Read-Host "Nombre de usuario"
    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario '$nombre' no existe."
        return
    }
    do {
        $nuevoGrupo = Read-Host "Nuevo grupo (reprobados / recursadores)"
    } while ($nuevoGrupo -notin @("reprobados", "recursadores"))

    Set-GrupoUsuario -Nombre $nombre -NuevoGrupo $nuevoGrupo
}

# solicita confirmación y elimina el usuario
function Invoke-EliminacionUsuario {
    $nombre = Read-Host "Nombre de usuario a eliminar"
    if (-not (Get-LocalUser -Name $nombre -ErrorAction SilentlyContinue)) {
        Write-Host "El usuario '$nombre' no existe."
        return
    }
    $confirmar = Read-Host "¿Confirma eliminar '$nombre'? (s/n)"
    if ($confirmar -match '^[sS]$') {
        Remove-UsuarioFtp -Nombre $nombre
    } else {
        Write-Host "Operación cancelada."
    }
}