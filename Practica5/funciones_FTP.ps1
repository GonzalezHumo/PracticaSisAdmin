function validarContra {
    param (
        [string]$contra
    )

    if ($contra.Length -lt 8) {
        Write-Host "La contrasena debe tener al menos 8 caracteres."
        return $false
    }
    if ($contra.Length -gt 15) {
        Write-Host "La contrasena no puede tener mas de 15 caracteres."
        return $false
    }
    if ($contra -notmatch "[A-Z]") {
        Write-Host "La contrasena debe contener al menos una letra mayuscula."
        return $false
    }
    if ($contra -notmatch "[a-z]") {
        Write-Host "La contrasena debe contener al menos una letra minuscula."
        return $false
    }
    if ($contra -notmatch "\d") {
        Write-Host "La contrasena debe contener al menos un numero."
        return $false
    }
    if ($contra -notmatch "[^a-zA-Z0-9]") {
        Write-Host "La contrasena debe contener al menos un caracter especial."
        return $false
    }
    return $true
}

function capturarContra {
    $esValida = $false
    do {
        $contra = Read-Host "Ingrese la contrasena (min. 8, max 15, mayuscula, minuscula, numero, especial)"
        $esValida = validarContra -contra $contra
        if (-not $esValida) {
            Write-Host "La contrasena no cumple con los requisitos. Intentelo de nuevo."
        }
    } while (-not $esValida)
    
    return $contra
}

function capturarUsuarioFTPValido {
    param (
        [string]$mensaje
    )

    $caracteresPermitidos = '^[a-zA-Z0-9]+$'
    $longitudMaxima = 15
    $cadenaValida = $false

    do {
        $cadena = Read-Host $mensaje

        if (-not $cadena) {
            Write-Host "La cadena no puede estar vacia. Intentalo de nuevo." 
        }
        elseif ($cadena -notmatch $caracteresPermitidos) {
            Write-Host "El nombre de usuario solo puede contener letras y numeros."
        }
        elseif ($cadena -match '^[0-9]') {
            Write-Host "El nombre de usuario no puede comenzar con un numero."
        }
        elseif ($cadena.Length -gt $longitudMaxima) {
            Write-Host "La cadena no puede exceder los $longitudMaxima caracteres." 
        }
        elseif (UsuarioExiste -nombreUsuario $cadena) {
            Write-Host "El usuario '$cadena' ya existe. Por favor, elija otro nombre."
        }
        else {
            $cadenaValida = $true
        }
    } while (-not $cadenaValida)

    return $cadena
}

function UsuarioExiste {
    param (
        [string]$nombreUsuario
    )
    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    $usuario = $ADSI.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $nombreUsuario }

    if ($usuario) { return $true } else { return $false }
}

function capturarGrupoFTP {
    do {
        Write-Host "Ingrese el grupo del usuario 1)Reprobados  2)Recursadores: "
        $grupo = Read-Host

        if ($grupo -eq "1") {
            return "reprobados"
        } elseif ($grupo -eq "2") {
            return "recursadores"
        } else {
            Write-Host "Opcion no valida. Por favor, ingrese 1 o 2."
        }
    } while ($true)
}

function CrearUsuarioFTP {
    param (
        [string]$FTPUserName,
        [string]$FTPPassword,
        [string]$FTPUserGroupName
    )

    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    
    # Crear el usuario en Windows
    $CreateUserFTPUser = $ADSI.Create("User", "$FTPUserName")
    $CreateUserFTPUser.SetPassword("$FTPPassword")  
    $CreateUserFTPUser.SetInfo()    

    # Asignar el usuario al grupo
    $group = [ADSI]"WinNT://$env:ComputerName/$FTPUserGroupName,group"
    $group.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Crear jerarquia de carpetas
    $UserPath = "C:\FTP\LocalUser\$FTPUserName"
    mkdir $UserPath -Force | Out-Null
    mkdir "$UserPath\$FTPUserName" -Force | Out-Null

    # Permisos NTFS para que el usuario pueda escribir en su carpeta personal
    $Acl = Get-Acl "$UserPath\$FTPUserName"
    $AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($FTPUserName, "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    $Acl.SetAccessRule($AccessRule)
    Set-Acl "$UserPath\$FTPUserName" $Acl

    # Enlaces simbolicos
    cmd /c mklink /D "$UserPath\general" "C:\FTP\LocalUser\Public\general" | Out-Null
    cmd /c mklink /D "$UserPath\$FTPUserGroupName" "C:\FTP\grupos\$FTPUserGroupName" | Out-Null
    
    Write-Host "Usuario $FTPUserName creado correctamente en el grupo $FTPUserGroupName."
}

function CambiarGrupoFTP {
    $FTPUserName = Read-Host "Ingrese el nombre del usuario a modificar"
    
    if (-not (UsuarioExiste -nombreUsuario $FTPUserName)) {
        Write-Host "El usuario no existe."
        return
    }

    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    $userADSI = [ADSI]"WinNT://$env:ComputerName/$FTPUserName,user"
    
    # Identificar el grupo actual
    $gruposActuales = $userADSI.Groups() | ForEach-Object { $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null) }
    $viejoGrupo = ""
    if ($gruposActuales -contains "reprobados") { $viejoGrupo = "reprobados" }
    elseif ($gruposActuales -contains "recursadores") { $viejoGrupo = "recursadores" }

    Write-Host "El usuario pertenece actualmente a: $viejoGrupo"
    $nuevoGrupo = capturarGrupoFTP

    if ($viejoGrupo -eq $nuevoGrupo) {
        Write-Host "El usuario ya pertenece a ese grupo."
        return
    }

    # Cambio de membresia
    if ($viejoGrupo -ne "") {
        $oldGroupADSI = [ADSI]"WinNT://$env:ComputerName/$viejoGrupo,group"
        $oldGroupADSI.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
    }
    $newGroupADSI = [ADSI]"WinNT://$env:ComputerName/$nuevoGrupo,group"
    $newGroupADSI.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Limpieza de enlace simbolico viejo
    $UserPath = "C:\FTP\LocalUser\$FTPUserName"
    if ($viejoGrupo -ne "") {
        cmd /c "rmdir /S /Q `"$UserPath\$viejoGrupo`"" 2>$null
    }

    # Crear nuevo enlace simbolico
    cmd /c mklink /D "$UserPath\$nuevoGrupo" "C:\FTP\grupos\$nuevoGrupo" | Out-Null

    # Reiniciar servicio FTP
    Write-Host "Actualizando permisos en tiempo real..."
    Restart-Service ftpsvc -Force
    
    Write-Host "Cambio completado. El usuario $FTPUserName ahora tiene acceso a $nuevoGrupo."
}

function EliminarUsuarioFTP {
    $FTPUserName = Read-Host "Ingrese el nombre del usuario a eliminar"
    
    if (-not (UsuarioExiste -nombreUsuario $FTPUserName)) {
        Write-Host "El usuario no existe."
        return
    }

    # Eliminar usuario de Windows
    $ADSI = [ADSI]"WinNT://$env:ComputerName"
    $ADSI.Delete("User", $FTPUserName)

    # Eliminar estructura de carpetas y enlaces
    $UserPath = "C:\FTP\LocalUser\$FTPUserName"
    if (Test-Path $UserPath) {
        Remove-Item $UserPath -Recurse -Force
    }

    Write-Host "Usuario $FTPUserName eliminado completamente del servidor."
}
