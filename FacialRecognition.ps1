<#
.SYNOPSIS
    Sistema de Reconocimiento Facial - Script Principal
.DESCRIPTION
    Programa interactivo en PowerShell para registro de usuarios
    con reconocimiento facial, autenticacion biometrica y gestion
    de usuarios.    Utiliza Python con OpenCV (YuNet + SFace) como
    motor de procesamiento facial.
.NOTES
    Version: 1.0.0
    Requiere: Python 3.8+, OpenCV
#>

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ======================================================================
# CONFIGURACION
# ======================================================================
$script:ProjectRoot = $PSScriptRoot
$script:PythonDir = Join-Path $ProjectRoot "python"
$script:DatabasePath = Join-Path $ProjectRoot "database\users.json"
$script:FacesDir = Join-Path $ProjectRoot "faces"
$script:VenvPython = Join-Path $ProjectRoot "venv\Scripts\python.exe"
$script:Tolerance = 0.363

# ======================================================================
# FUNCIONES DE UTILIDAD - INTERFAZ
# ======================================================================

function Show-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ######  #######  #####  #####  #   #  #####  #####  #####  #   #" -ForegroundColor Cyan
    Write-Host "  #    #  #       #       #   #  ##  #  #   #  #        #    ## ##" -ForegroundColor Cyan
    Write-Host "  ######  #####   #       #   #  # # #  #   #  #        #    # # #" -ForegroundColor DarkCyan
    Write-Host "  #  #    #       #       #   #  #  ##  #   #  #        #    #   #" -ForegroundColor DarkCyan
    Write-Host "  #   #   #######  #####  #####  #   #  #####  #####  #####  #   #" -ForegroundColor Blue
    Write-Host ""
    Write-Host "              #######  #####  #####  #####  #####  #     " -ForegroundColor Magenta
    Write-Host "              #       #   #  #        #    #   #  #     " -ForegroundColor Magenta
    Write-Host "              #####   #####  #        #    #####  #     " -ForegroundColor DarkMagenta
    Write-Host "              #       #   #  #        #    #   #  #     " -ForegroundColor DarkMagenta
    Write-Host "              #       #   #  #####  #####  #   #  #####" -ForegroundColor DarkMagenta
    Write-Host ""
    Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host "   Sistema de Autenticacion Biometrica por Reconocimiento Facial v1.0" -ForegroundColor Gray
    Write-Host "  -----------------------------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-ColorMessage {
    param(
        [string]$Message,
        [string]$Type = "info"  # info, success, error, warning, header, prompt
    )

    switch ($Type) {
        "success" {
            Write-Host "  [OK] " -ForegroundColor Green -NoNewline
            Write-Host $Message -ForegroundColor Green
        }
        "error" {
            Write-Host "  [X]  " -ForegroundColor Red -NoNewline
            Write-Host $Message -ForegroundColor Red
        }
        "warning" {
            Write-Host "  [!]  " -ForegroundColor Yellow -NoNewline
            Write-Host $Message -ForegroundColor Yellow
        }
        "info" {
            Write-Host "  [i]  " -ForegroundColor Cyan -NoNewline
            Write-Host $Message -ForegroundColor Gray
        }
        "header" {
            Write-Host ""
            Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host "  |  $($Message.PadRight(52))|" -ForegroundColor Cyan
            Write-Host "  +------------------------------------------------------+" -ForegroundColor Cyan
            Write-Host ""
        }
        "prompt" {
            Write-Host ""
            Write-Host "  > " -ForegroundColor Yellow -NoNewline
            Write-Host $Message -ForegroundColor White -NoNewline
        }
        "detail" {
            Write-Host "     $Message" -ForegroundColor DarkGray
        }
    }
}

function Write-Separator {
    Write-Host "  ------------------------------------------------------" -ForegroundColor DarkGray
}

function Show-LoadingAnimation {
    param(
        [string]$Message = "Procesando",
        [int]$DurationMs = 1500
    )

    $frames = @("|", "/", "-", "\")
    $endTime = (Get-Date).AddMilliseconds($DurationMs)
    $i = 0

    while ((Get-Date) -lt $endTime) {
        $frame = $frames[$i % $frames.Count]
        Write-Host "`r  $frame $Message..." -ForegroundColor Cyan -NoNewline
        Start-Sleep -Milliseconds 150
        $i++
    }
    Write-Host "`r  $(' ' * ($Message.Length + 10))" -NoNewline
    Write-Host "`r" -NoNewline
}

function Read-UserInput {
    param(
        [string]$Prompt,
        [switch]$Required
    )

    do {
        Write-ColorMessage $Prompt "prompt"
        $input_value = Read-Host
        $input_value = $input_value.Trim()

        if ($Required -and [string]::IsNullOrEmpty($input_value)) {
            Write-ColorMessage "Este campo es obligatorio. Intenta de nuevo." "warning"
        }
    } while ($Required -and [string]::IsNullOrEmpty($input_value))

    return $input_value
}

# ======================================================================
# FUNCIONES DE UTILIDAD - PYTHON
# ======================================================================

function Test-Prerequisites {
    <#
    .SYNOPSIS
        Verifica que Python y las dependencias esten instalados.
    #>
    $issues = @()

    # Verificar Python del entorno virtual
    if (-not (Test-Path $script:VenvPython)) {
        # Intentar Python del sistema
        $systemPython = Get-Command python -ErrorAction SilentlyContinue
        if ($systemPython) {
            $script:VenvPython = "python"
            Write-ColorMessage "Usando Python del sistema (no se encontro entorno virtual)" "warning"
        }
        else {
            $issues += "Python no encontrado. Ejecuta setup.ps1 primero."
        }
    }

    # Verificar base de datos
    if (-not (Test-Path $script:DatabasePath)) {
        $issues += "Base de datos no encontrada en: $($script:DatabasePath)"
    }

    # Verificar scripts de Python
    $requiredScripts = @("capture_face.py", "register_face.py", "recognize_face.py", "manage_users.py")
    foreach ($scriptFile in $requiredScripts) {
        $scriptPath = Join-Path $script:PythonDir $scriptFile
        if (-not (Test-Path $scriptPath)) {
            $issues += "Script faltante: python\$scriptFile"
        }
    }

    # Verificar modelos de IA
    $modelsDir = Join-Path $ProjectRoot "models"
    $requiredModels = @("face_detection_yunet_2023mar.onnx", "face_recognition_sface_2021dec.onnx")
    foreach ($model in $requiredModels) {
        $modelPath = Join-Path $modelsDir $model
        if (-not (Test-Path $modelPath)) {
            $issues += "Modelo faltante: models\$model"
        }
    }

    # Verificar dependencias de Python
    if ($issues.Count -eq 0) {
        $ErrorActionPreference = "SilentlyContinue"
        $testResult = & $script:VenvPython -c "import cv2; print('OK')" 2>&1
        $ErrorActionPreference = "Continue"
        $testStr = ($testResult | Where-Object { $_ -is [string] }) -join ''
        if ($testStr -ne "OK") {
            $issues += "Dependencias de Python no instaladas. Ejecuta setup.ps1"
        }
    }

    return $issues
}

function Invoke-PythonScript {
    <#
    .SYNOPSIS
        Ejecuta un script de Python y retorna la salida parseada como JSON.
    .PARAMETER ScriptName
        Nombre del script (sin ruta, se busca en python/)
    .PARAMETER Arguments
        Argumentos para pasar al script
    #>
    param(
        [string]$ScriptName,
        [string[]]$Arguments = @()
    )

    $scriptPath = Join-Path $script:PythonDir $ScriptName

    if (-not (Test-Path $scriptPath)) {
        return @{
            status  = "error"
            message = "Script no encontrado: $ScriptName"
        }
    }

    try {
        $fullArgs = @($scriptPath) + $Arguments
        $output = & $script:VenvPython @fullArgs 2>&1

        # Separar stdout de stderr
        $stdout = ($output | Where-Object { $_ -is [string] -or $_.GetType().Name -ne 'ErrorRecord' }) -join "`n"
        $stderr = ($output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }) -join "`n"

        # Intentar parsear JSON del stdout
        if ($stdout) {
            # Buscar la ultima linea que sea JSON valido
            $lines = $stdout -split "`n"
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i].Trim()
                if ($line.StartsWith("{") -or $line.StartsWith("[")) {
                    try {
                        $result = $line | ConvertFrom-Json
                        return $result
                    }
                    catch {
                        continue
                    }
                }
            }
        }

        # Si no se pudo parsear JSON
        return @{
            status  = "error"
            message = "No se recibio respuesta valida del script."
            stdout  = $stdout
            stderr  = $stderr
        }
    }
    catch {
        return @{
            status  = "error"
            message = "Error al ejecutar script: $($_.Exception.Message)"
        }
    }
}

# ======================================================================
# FUNCIONES PRINCIPALES
# ======================================================================

function Show-ConsentForm {
    <#
    .SYNOPSIS
        Muestra el formulario de consentimiento para captura facial.
    .OUTPUTS
        bool - True si el usuario acepta, False si rechaza.
    #>
    param([string]$FullName)

    Write-Host ""
    Write-Host "  +==============================================================+" -ForegroundColor Yellow
    Write-Host "  |              AVISO DE CONSENTIMIENTO INFORMADO                |" -ForegroundColor Yellow
    Write-Host "  +==============================================================+" -ForegroundColor Yellow
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  |  Estimado/a: $($FullName.PadRight(48))|" -ForegroundColor Yellow
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  |  Este sistema recopilara los siguientes datos:               |" -ForegroundColor Yellow
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  |  " -ForegroundColor Yellow -NoNewline
    Write-Host "[1] Imagen facial" -ForegroundColor White -NoNewline
    Write-Host " - Fotografia de su rostro               |" -ForegroundColor Gray
    Write-Host "  |  " -ForegroundColor Yellow -NoNewline
    Write-Host "[2] Encoding facial" -ForegroundColor White -NoNewline
    Write-Host " - Vector numerico de 128 dimensiones |" -ForegroundColor Gray
    Write-Host "  |  " -ForegroundColor Yellow -NoNewline
    Write-Host "[3] Datos de perfil" -ForegroundColor White -NoNewline
    Write-Host " - Nombre y nombre de usuario         |" -ForegroundColor Gray
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  |  Almacenamiento:                                             |" -ForegroundColor Yellow
    Write-Host "  |  * Los datos se almacenan LOCALMENTE en este equipo          |" -ForegroundColor Gray
    Write-Host "  |  * No se transmiten a servidores externos                    |" -ForegroundColor Gray
    Write-Host "  |  * Los datos se guardan en formato JSON sin encriptacion     |" -ForegroundColor Gray
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  |  Derechos del usuario:                                       |" -ForegroundColor Yellow
    Write-Host "  |  * Puede solicitar la eliminacion de sus datos en cualquier  |" -ForegroundColor Gray
    Write-Host "  |    momento desde el menu 'Gestionar Usuarios'                |" -ForegroundColor Gray
    Write-Host "  |  * Puede rechazar este consentimiento sin consecuencias      |" -ForegroundColor Gray
    Write-Host "  |                                                              |" -ForegroundColor Yellow
    Write-Host "  +==============================================================+" -ForegroundColor Yellow
    Write-Host ""

    Write-Host "  Para continuar, escriba " -ForegroundColor Gray -NoNewline
    Write-Host "ACEPTO" -ForegroundColor Green -NoNewline
    Write-Host " (o cualquier otra cosa para cancelar)" -ForegroundColor Gray
    Write-Host ""

    Write-ColorMessage "Su respuesta: " "prompt"
    $response = Read-Host

    return ($response.Trim().ToUpper() -eq "ACEPTO")
}

function Invoke-UserRegistration {
    <#
    .SYNOPSIS
        Flujo completo de registro de un nuevo usuario.
    #>
    Write-ColorMessage "REGISTRO DE NUEVO USUARIO" "header"

    # Solicitar datos del usuario
    $fullName = Read-UserInput "Nombre completo: " -Required
    $username = Read-UserInput "Nombre de usuario (sin espacios): " -Required

    # Validar username
    if ($username -match '\s') {
        Write-ColorMessage "El nombre de usuario no puede contener espacios." "error"
        return
    }

    if ($username.Length -lt 3) {
        Write-ColorMessage "El nombre de usuario debe tener al menos 3 caracteres." "error"
        return
    }

    # Mostrar formulario de consentimiento
    $consented = Show-ConsentForm -FullName $fullName

    if (-not $consented) {
        Write-Host ""
        Write-ColorMessage "Registro cancelado. No se recopilaron datos." "warning"
        Write-ColorMessage "Puede volver a intentar cuando lo desee." "info"
        return
    }

    Write-Host ""
    Write-ColorMessage "Consentimiento aceptado. Preparando camara..." "success"
    Write-Host ""
    Write-ColorMessage "Se abrira una ventana con la camara." "info"
    Write-ColorMessage "Posicione su rostro frente a la camara y presione ESPACIO." "info"
    Write-ColorMessage "Presione ESC para cancelar." "info"
    Write-Host ""

    Start-Sleep -Seconds 2

    # Ejecutar script de registro
    Show-LoadingAnimation "Iniciando camara" 1000

    $result = Invoke-PythonScript -ScriptName "register_face.py" -Arguments @(
        "--username", $username,
        "--fullname", $fullName,
        "--db", $script:DatabasePath,
        "--faces-dir", $script:FacesDir
    )

    Write-Host ""

    switch ($result.status) {
        "success" {
            Write-Host ""
            Write-Host "  +======================================================+" -ForegroundColor Green
            Write-Host "  |        [OK] REGISTRO COMPLETADO EXITOSAMENTE          |" -ForegroundColor Green
            Write-Host "  +------------------------------------------------------+" -ForegroundColor Green
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  |  Nombre:   $($result.full_name.PadRight(44))|" -ForegroundColor White
            Write-Host "  |  Usuario:  $($result.username.PadRight(44))|" -ForegroundColor White
            Write-Host "  |  ID:       $($result.user_id.Substring(0,8).PadRight(44))|" -ForegroundColor Gray
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  |  Ya puede usar el inicio de sesion facial.             |" -ForegroundColor Gray
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  +======================================================+" -ForegroundColor Green
            Write-Host ""
        }
        "cancelled" {
            Write-ColorMessage "Registro cancelado por el usuario." "warning"
        }
        default {
            Write-ColorMessage "Error en el registro: $($result.message)" "error"
        }
    }
}

function Invoke-FacialLogin {
    <#
    .SYNOPSIS
        Flujo completo de inicio de sesion por reconocimiento facial.
    #>
    Write-ColorMessage "INICIO DE SESION - RECONOCIMIENTO FACIAL" "header"

    # Verificar que haya usuarios registrados
    $dbContent = Get-Content $script:DatabasePath -Raw | ConvertFrom-Json
    $userCount = ($dbContent.users | Measure-Object).Count

    if ($userCount -eq 0) {
        Write-ColorMessage "No hay usuarios registrados en el sistema." "warning"
        Write-ColorMessage "Registre un usuario primero (opcion 1 del menu)." "info"
        return
    }

    Write-ColorMessage "Usuarios registrados en la base de datos: $userCount" "info"
    Write-Host ""
    Write-ColorMessage "Se abrira la camara para escanear su rostro." "info"
    Write-ColorMessage "Posicione su rostro frente a la camara y presione ESPACIO." "info"
    Write-ColorMessage "Presione ESC para cancelar." "info"
    Write-Host ""

    Start-Sleep -Seconds 1

    Show-LoadingAnimation "Preparando reconocimiento facial" 1000

    $result = Invoke-PythonScript -ScriptName "recognize_face.py" -Arguments @(
        "--db", $script:DatabasePath,
        "--tolerance", $script:Tolerance.ToString()
    )

    Write-Host ""

    switch ($result.status) {
        "match" {
            $confidencePct = [math]::Round($result.confidence * 100, 1)
            $regDate = if ($result.registered_at) {
                try { [datetime]::Parse($result.registered_at).ToString("dd/MM/yyyy HH:mm") } catch { $result.registered_at }
            }
            else { "N/A" }

            # Barra de confianza visual
            $barLength = 30
            $filled = [math]::Floor($confidencePct / 100 * $barLength)
            $empty = $barLength - $filled
            $bar = ("#" * $filled) + ("-" * $empty)

            $barColor = if ($confidencePct -ge 80) { "Green" }
                        elseif ($confidencePct -ge 60) { "Yellow" }
                        else { "Red" }

            Write-Host ""
            Write-Host "  +======================================================+" -ForegroundColor Green
            Write-Host "  |          ACCESO CONCEDIDO - BIENVENIDO                 |" -ForegroundColor Green
            Write-Host "  +------------------------------------------------------+" -ForegroundColor Green
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  |  Nombre:    $($result.full_name.PadRight(43))|" -ForegroundColor White
            Write-Host "  |  Usuario:   $($result.username.PadRight(43))|" -ForegroundColor White
            Write-Host "  |  Registro:  $($regDate.PadRight(43))|" -ForegroundColor Gray
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  |  Confianza: " -ForegroundColor Green -NoNewline
            Write-Host "[$bar]" -ForegroundColor $barColor -NoNewline
            Write-Host " $($confidencePct.ToString().PadRight(5))%  |" -ForegroundColor White
            Write-Host "  |                                                        |" -ForegroundColor Green
            Write-Host "  +======================================================+" -ForegroundColor Green
            Write-Host ""

            Write-ColorMessage "Sesion iniciada exitosamente." "success"
        }
        "no_match" {
            Write-Host ""
            Write-Host "  +======================================================+" -ForegroundColor Red
            Write-Host "  |             ACCESO DENEGADO                            |" -ForegroundColor Red
            Write-Host "  +------------------------------------------------------+" -ForegroundColor Red
            Write-Host "  |                                                        |" -ForegroundColor Red
            Write-Host "  |  No se encontro coincidencia en la base de datos.      |" -ForegroundColor White
            Write-Host "  |  Usuarios comparados: $($result.users_compared.ToString().PadRight(33))|" -ForegroundColor Gray
            Write-Host "  |                                                        |" -ForegroundColor Red
            Write-Host "  |  Si es un usuario nuevo, registrese primero.           |" -ForegroundColor Gray
            Write-Host "  |                                                        |" -ForegroundColor Red
            Write-Host "  +======================================================+" -ForegroundColor Red
            Write-Host ""
        }
        "cancelled" {
            Write-ColorMessage "Inicio de sesion cancelado." "warning"
        }
        default {
            Write-ColorMessage "Error en el reconocimiento: $($result.message)" "error"
        }
    }
}

function Invoke-UserManagement {
    <#
    .SYNOPSIS
        Menu de gestion de usuarios registrados.
    #>
    $continue = $true

    while ($continue) {
        Write-ColorMessage "GESTION DE USUARIOS" "header"

        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  |   [1]  Listar usuarios registrados                |" -ForegroundColor White
        Write-Host "  |   [2]  Ver detalles de un usuario                 |" -ForegroundColor White
        Write-Host "  |   [3]  Eliminar un usuario                        |" -ForegroundColor White
        Write-Host "  |   [4]  Volver al menu principal                   |" -ForegroundColor White
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan

        Write-ColorMessage "Seleccione una opcion: " "prompt"
        $option = Read-Host

        switch ($option.Trim()) {
            "1" { Show-UserList }
            "2" { Show-UserDetail }
            "3" { Remove-RegisteredUser }
            "4" { $continue = $false }
            default {
                Write-ColorMessage "Opcion no valida." "warning"
            }
        }

        if ($continue) {
            Write-Host ""
            Write-Host "  Presione ENTER para continuar..." -ForegroundColor DarkGray
            Read-Host | Out-Null
        }
    }
}

function Show-UserList {
    <#
    .SYNOPSIS
        Muestra la lista de todos los usuarios registrados.
    #>
    $result = Invoke-PythonScript -ScriptName "manage_users.py" -Arguments @(
        "--action", "list",
        "--db", $script:DatabasePath
    )

    if ($result.status -eq "success") {
        $total = $result.total_users

        if ($total -eq 0) {
            Write-ColorMessage "No hay usuarios registrados." "info"
            return
        }

        Write-Host ""
        Write-Host "  Usuarios registrados: $total" -ForegroundColor Cyan
        Write-Separator
        Write-Host ""

        # Encabezado de tabla
        Write-Host "  " -NoNewline
        Write-Host "  #  " -ForegroundColor DarkGray -NoNewline
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host "Usuario".PadRight(18) -ForegroundColor Cyan -NoNewline
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host "Nombre Completo".PadRight(28) -ForegroundColor Cyan -NoNewline
        Write-Host "| " -ForegroundColor DarkGray -NoNewline
        Write-Host "Fecha Registro" -ForegroundColor Cyan
        Write-Host "  -----+-------------------+-----------------------------+--------------------" -ForegroundColor DarkGray

        $i = 1
        foreach ($user in $result.users) {
            $regDate = if ($user.registered_at -and $user.registered_at -ne "N/A") {
                try { [datetime]::Parse($user.registered_at).ToString("dd/MM/yyyy HH:mm") } catch { $user.registered_at }
            }
            else { "N/A" }

            $num = $i.ToString().PadLeft(3)
            Write-Host "  " -NoNewline
            Write-Host "$num  " -ForegroundColor DarkGray -NoNewline
            Write-Host "| " -ForegroundColor DarkGray -NoNewline
            Write-Host "$($user.username.PadRight(18))" -ForegroundColor White -NoNewline
            Write-Host "| " -ForegroundColor DarkGray -NoNewline

            $displayName = if ($user.full_name.Length -gt 27) {
                $user.full_name.Substring(0, 24) + "..."
            } else {
                $user.full_name
            }
            Write-Host "$($displayName.PadRight(28))" -ForegroundColor White -NoNewline
            Write-Host "| " -ForegroundColor DarkGray -NoNewline
            Write-Host "$regDate" -ForegroundColor Gray
            $i++
        }

        Write-Host ""
    }
    else {
        Write-ColorMessage "Error al listar usuarios: $($result.message)" "error"
    }
}

function Show-UserDetail {
    <#
    .SYNOPSIS
        Muestra los detalles de un usuario especifico.
    #>
    $username = Read-UserInput "Nombre de usuario a consultar: " -Required

    $result = Invoke-PythonScript -ScriptName "manage_users.py" -Arguments @(
        "--action", "detail",
        "--db", $script:DatabasePath,
        "--username", $username
    )

    if ($result.status -eq "success") {
        $user = $result.user

        $regDate = if ($user.registered_at) {
            try { [datetime]::Parse($user.registered_at).ToString("dd/MM/yyyy HH:mm:ss") } catch { $user.registered_at }
        }
        else { "N/A" }

        $consentDate = if ($user.consent_timestamp) {
            try { [datetime]::Parse($user.consent_timestamp).ToString("dd/MM/yyyy HH:mm:ss") } catch { $user.consent_timestamp }
        }
        else { "N/A" }

        Write-Host ""
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |  DETALLES DEL USUARIO                             |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |  ID:              $($user.id.Substring(0,8).PadRight(30))|" -ForegroundColor Gray
        Write-Host "  |  Usuario:         $($user.username.PadRight(30))|" -ForegroundColor White
        Write-Host "  |  Nombre:          $($user.full_name.PadRight(30))|" -ForegroundColor White
        Write-Host "  |  Registrado:      $($regDate.PadRight(30))|" -ForegroundColor Gray
        Write-Host "  |  Consentimiento:  $($consentDate.PadRight(30))|" -ForegroundColor Gray
        Write-Host "  |  Dimensiones:     $("$($user.encoding_dimensions)D".PadRight(30))|" -ForegroundColor Gray

        $consentText = if ($user.consent_given) { "Si [OK]" } else { "No [X]" }
        Write-Host "  |  Acepto terminos: $($consentText.PadRight(30))|" -ForegroundColor $(if ($user.consent_given) { "Green" } else { "Red" })
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host ""
    }
    else {
        Write-ColorMessage "$($result.message)" "error"
    }
}

function Remove-RegisteredUser {
    <#
    .SYNOPSIS
        Elimina un usuario registrado con confirmacion doble.
    #>
    $username = Read-UserInput "Nombre de usuario a eliminar: " -Required

    # Verificar que existe
    $detail = Invoke-PythonScript -ScriptName "manage_users.py" -Arguments @(
        "--action", "detail",
        "--db", $script:DatabasePath,
        "--username", $username
    )

    if ($detail.status -ne "success") {
        Write-ColorMessage "$($detail.message)" "error"
        return
    }

    # Confirmacion
    Write-Host ""
    Write-ColorMessage "Esta seguro de eliminar al usuario '$($detail.user.full_name)' ($username)?" "warning"
    Write-ColorMessage "Esta accion eliminara todos los datos faciales asociados." "warning"
    Write-Host ""
    Write-Host "  Escriba " -ForegroundColor Gray -NoNewline
    Write-Host "ELIMINAR" -ForegroundColor Red -NoNewline
    Write-Host " para confirmar: " -ForegroundColor Gray -NoNewline
    $confirm = Read-Host

    if ($confirm.Trim().ToUpper() -ne "ELIMINAR") {
        Write-ColorMessage "Eliminacion cancelada." "info"
        return
    }

    # Ejecutar eliminacion
    $result = Invoke-PythonScript -ScriptName "manage_users.py" -Arguments @(
        "--action", "delete",
        "--db", $script:DatabasePath,
        "--username", $username,
        "--faces-dir", $script:FacesDir
    )

    if ($result.status -eq "success") {
        Write-ColorMessage "$($result.message)" "success"
        Write-ColorMessage "Todos los datos faciales han sido eliminados." "info"
    }
    else {
        Write-ColorMessage "Error: $($result.message)" "error"
    }
}

# ======================================================================
# MENU PRINCIPAL
# ======================================================================

function Show-MainMenu {
    <#
    .SYNOPSIS
        Muestra y maneja el menu principal del programa.
    #>

    # Verificar prerequisitos
    Show-Banner
    Write-ColorMessage "Verificando sistema..." "info"
    $issues = Test-Prerequisites

    if ($issues.Count -gt 0) {
        Write-Host ""
        Write-ColorMessage "Se encontraron problemas:" "error"
        foreach ($issue in $issues) {
            Write-Host "     * $issue" -ForegroundColor Red
        }
        Write-Host ""
        Write-ColorMessage "Ejecute .\setup.ps1 para configurar el sistema." "info"
        Write-Host ""
        return
    }

    Write-ColorMessage "Sistema listo." "success"
    Start-Sleep -Milliseconds 800

    $running = $true

    while ($running) {
        Show-Banner

        # Mostrar conteo de usuarios
        try {
            $dbContent = Get-Content $script:DatabasePath -Raw | ConvertFrom-Json
            $userCount = ($dbContent.users | Measure-Object).Count
            Write-Host "  Usuarios registrados: " -ForegroundColor Gray -NoNewline
            Write-Host $userCount -ForegroundColor Cyan
            Write-Host ""
        }
        catch {
            # Ignorar si no se puede leer la BD
        }

        # Menu
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |                  MENU PRINCIPAL                    |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  |   [1]  Registrar nuevo usuario                    |" -ForegroundColor White
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  |   [2]  Iniciar sesion (reconocimiento facial)     |" -ForegroundColor White
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  |   [3]  Gestionar usuarios                         |" -ForegroundColor White
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  |   [4]  Salir                                      |" -ForegroundColor White
        Write-Host "  |                                                    |" -ForegroundColor Cyan
        Write-Host "  +--------------------------------------------------+" -ForegroundColor Cyan

        Write-ColorMessage "Seleccione una opcion: " "prompt"
        $option = Read-Host

        switch ($option.Trim()) {
            "1" {
                Invoke-UserRegistration
                Write-Host ""
                Write-Host "  Presione ENTER para continuar..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "2" {
                Invoke-FacialLogin
                Write-Host ""
                Write-Host "  Presione ENTER para continuar..." -ForegroundColor DarkGray
                Read-Host | Out-Null
            }
            "3" {
                Invoke-UserManagement
            }
            "4" {
                Show-Banner
                Write-Host "  Hasta luego!" -ForegroundColor Cyan
                Write-Host ""
                $running = $false
            }
            default {
                Write-ColorMessage "Opcion no valida. Seleccione 1-4." "warning"
                Start-Sleep -Seconds 1
            }
        }
    }
}

# ======================================================================
# PUNTO DE ENTRADA
# ======================================================================

Show-MainMenu
