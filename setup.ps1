<#
.SYNOPSIS
    Script de configuracion para el Sistema de Reconocimiento Facial.
.DESCRIPTION
    Verifica prerequisitos, crea entorno virtual de Python,
    instala dependencias y descarga modelos de IA necesarios.
#>

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# -- Colores y utilidades --
function Write-Step {
    param([string]$Message)
    Write-Host "`n>> " -ForegroundColor Cyan -NoNewline
    Write-Host $Message -ForegroundColor White
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] " -ForegroundColor Green -NoNewline
    Write-Host $Message -ForegroundColor Gray
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [X]  " -ForegroundColor Red -NoNewline
    Write-Host $Message -ForegroundColor Gray
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [i]  " -ForegroundColor Yellow -NoNewline
    Write-Host $Message -ForegroundColor Gray
}

# -- Banner --
Clear-Host
Write-Host ""
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host "  |                                                      |" -ForegroundColor Cyan
Write-Host "  |     SETUP - Reconocimiento Facial                    |" -ForegroundColor Cyan
Write-Host "  |                                                      |" -ForegroundColor Cyan
Write-Host "  |     Configuracion e instalacion de dependencias      |" -ForegroundColor Cyan
Write-Host "  |                                                      |" -ForegroundColor Cyan
Write-Host "  +====================================================+" -ForegroundColor Cyan
Write-Host ""

$projectRoot = $PSScriptRoot

# -- 1. Verificar Python --
Write-Step "Verificando instalacion de Python..."

$pythonCmd = $null
foreach ($cmd in @("python", "python3", "py")) {
    try {
        $version = & $cmd --version 2>&1
        if ($version -match "Python (\d+\.\d+)") {
            $major, $minor = $Matches[1] -split '\.'
            if ([int]$major -ge 3 -and [int]$minor -ge 8) {
                $pythonCmd = $cmd
                Write-Success "Python encontrado: $version (comando: $cmd)"
                break
            }
        }
    }
    catch {
        continue
    }
}

if (-not $pythonCmd) {
    Write-Fail "Python 3.8+ no encontrado en el PATH."
    Write-Info "Por favor instala Python desde: https://www.python.org/downloads/"
    Write-Info "Asegurate de marcar 'Add Python to PATH' durante la instalacion."
    exit 1
}

# -- 2. Crear estructura de directorios --
Write-Step "Creando estructura de directorios..."

$directories = @(
    "$projectRoot\python",
    "$projectRoot\database",
    "$projectRoot\faces",
    "$projectRoot\models"
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Success "Creado: $($dir.Replace($projectRoot, '.'))"
    }
    else {
        Write-Info "Ya existe: $($dir.Replace($projectRoot, '.'))"
    }
}

# -- 3. Inicializar base de datos --
Write-Step "Inicializando base de datos..."

$dbPath = "$projectRoot\database\users.json"
if (-not (Test-Path $dbPath)) {
    $initialDb = @{
        users    = @()
        metadata = @{
            version    = "1.0.0"
            created_at = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss")
            app_name   = "FacialRecognition System"
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path $dbPath -Value $initialDb -Encoding UTF8
    Write-Success "Base de datos inicializada: database\users.json"
}
else {
    Write-Info "Base de datos ya existe: database\users.json"
}

# -- 4. Crear entorno virtual --
Write-Step "Configurando entorno virtual de Python..."

$venvPath = "$projectRoot\venv"
if (-not (Test-Path "$venvPath\Scripts\python.exe")) {
    Write-Info "Creando entorno virtual..."
    & $pythonCmd -m venv $venvPath
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Error al crear el entorno virtual."
        exit 1
    }
    Write-Success "Entorno virtual creado en: venv\"
}
else {
    Write-Info "Entorno virtual ya existe."
}

$venvPython = "$venvPath\Scripts\python.exe"
$venvPip = "$venvPath\Scripts\pip.exe"

# -- 5. Instalar dependencias --
Write-Step "Instalando dependencias de Python..."
Write-Info "Usando OpenCV puro (sin dlib) para maxima compatibilidad..."

# Actualizar pip primero
Write-Info "Actualizando pip..."
try {
    $ErrorActionPreference = "SilentlyContinue"
    & $venvPython -m pip install --upgrade pip 2>&1 | Out-Null
    $ErrorActionPreference = "Continue"
} catch { $ErrorActionPreference = "Continue" }

$packages = @(
    @{ Name = "numpy"; Desc = "Computacion numerica" },
    @{ Name = "opencv-python"; Desc = "Vision por computadora + reconocimiento facial" }
)

$allInstalled = $true
foreach ($pkg in $packages) {
    Write-Info "Instalando $($pkg.Name) ($($pkg.Desc))..."
    try {
        $ErrorActionPreference = "SilentlyContinue"
        $pipOutput = & $venvPip install $pkg.Name 2>&1
        $pipExitCode = $LASTEXITCODE
        $ErrorActionPreference = "Continue"
    } catch {
        $pipExitCode = 1
        $ErrorActionPreference = "Continue"
    }
    if ($pipExitCode -ne 0) {
        Write-Fail "Error al instalar $($pkg.Name)"
        $allInstalled = $false
    }
    else {
        Write-Success "$($pkg.Name) instalado correctamente"
    }
}

# -- 6. Descargar modelos de IA --
Write-Step "Descargando modelos de reconocimiento facial..."
Write-Info "Modelos de OpenCV Zoo (YuNet + SFace)..."

$models = @(
    @{
        Name = "face_detection_yunet_2023mar.onnx"
        Desc = "Deteccion facial (YuNet)"
        Url  = "https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx"
    },
    @{
        Name = "face_recognition_sface_2021dec.onnx"
        Desc = "Reconocimiento facial (SFace)"
        Url  = "https://github.com/opencv/opencv_zoo/raw/main/models/face_recognition_sface/face_recognition_sface_2021dec.onnx"
    }
)

foreach ($model in $models) {
    $modelPath = "$projectRoot\models\$($model.Name)"
    if (-not (Test-Path $modelPath)) {
        Write-Info "Descargando $($model.Desc)..."
        try {
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri $model.Url -OutFile $modelPath -UseBasicParsing
            if (Test-Path $modelPath) {
                $size = [math]::Round((Get-Item $modelPath).Length / 1MB, 1)
                Write-Success "$($model.Name) descargado ($($size) MB)"
            }
            else {
                Write-Fail "No se pudo descargar $($model.Name)"
                $allInstalled = $false
            }
        }
        catch {
            Write-Fail "Error descargando $($model.Name): $($_.Exception.Message)"
            $allInstalled = $false
        }
    }
    else {
        $size = [math]::Round((Get-Item $modelPath).Length / 1MB, 1)
        Write-Info "Ya existe: $($model.Name) ($($size) MB)"
    }
}

# -- 7. Verificacion final --
Write-Step "Verificacion final..."

# Escribir script de test temporal
$testScriptPath = "$projectRoot\_verify_test.py"
@"
import sys
try:
    import cv2
    import numpy as np
    assert hasattr(cv2, 'FaceDetectorYN'), 'FaceDetectorYN not available'
    assert hasattr(cv2, 'FaceRecognizerSF'), 'FaceRecognizerSF not available'
    print('OK|OpenCV=' + cv2.__version__ + '|NumPy=' + np.__version__)
except Exception as e:
    print('ERROR|' + str(e))
    sys.exit(1)
"@ | Set-Content -Path $testScriptPath -Encoding UTF8

$ErrorActionPreference = "SilentlyContinue"
$testResult = & $venvPython $testScriptPath 2>$null
$ErrorActionPreference = "Continue"

# Limpiar script temporal
Remove-Item $testScriptPath -Force -ErrorAction SilentlyContinue

# Buscar la linea que empieza con OK
$okLine = $null
if ($testResult) {
    foreach ($line in $testResult) {
        $lineStr = "$line".Trim()
        if ($lineStr.StartsWith("OK|")) {
            $okLine = $lineStr
            break
        }
    }
}

if ($okLine) {
    $parts = ($okLine -split '\|')
    Write-Success "Todas las dependencias verificadas:"
    Write-Success "  $($parts[1])"
    Write-Success "  $($parts[2])"
    Write-Success "  FaceDetectorYN OK"
    Write-Success "  FaceRecognizerSF OK"
}
else {
    Write-Fail "Algunas dependencias no se pudieron verificar: $testResult"
    $allInstalled = $false
}

# Verificar modelos
$modelsOk = $true
foreach ($model in $models) {
    $modelPath = "$projectRoot\models\$($model.Name)"
    if (-not (Test-Path $modelPath) -or (Get-Item $modelPath).Length -lt 1000) {
        Write-Fail "Modelo faltante o corrupto: $($model.Name)"
        $modelsOk = $false
        $allInstalled = $false
    }
}
if ($modelsOk) {
    Write-Success "Modelos de IA verificados"
}

# -- Resumen --
Write-Host ""
Write-Host "  +----------------------------------------------------+" -ForegroundColor Cyan
if ($allInstalled) {
    Write-Host "  |  [OK] CONFIGURACION COMPLETADA EXITOSAMENTE        |" -ForegroundColor Green
    Write-Host "  |                                                      |" -ForegroundColor Cyan
    Write-Host "  |  Ejecuta el programa con:                            |" -ForegroundColor Cyan
    Write-Host "  |  .\FacialRecognition.ps1                             |" -ForegroundColor Yellow
}
else {
    Write-Host "  |  [!] CONFIGURACION INCOMPLETA                       |" -ForegroundColor Yellow
    Write-Host "  |                                                      |" -ForegroundColor Cyan
    Write-Host "  |  Revisa los errores anteriores e intenta             |" -ForegroundColor Cyan
    Write-Host "  |  instalar las dependencias manualmente.              |" -ForegroundColor Cyan
}
Write-Host "  +----------------------------------------------------+" -ForegroundColor Cyan
Write-Host ""
