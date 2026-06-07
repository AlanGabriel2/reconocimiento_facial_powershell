# Reconocimiento Facial - PowerShell + OpenCV

Sistema de autenticacion biometrica por reconocimiento facial. Usa **PowerShell** como interfaz interactiva y **Python con OpenCV** (YuNet + SFace) como motor de procesamiento facial.

## Caracteristicas

- **Registro de usuarios** con consentimiento informado explicito
- **Captura facial** en vivo con webcam y deteccion en tiempo real
- **Reconocimiento facial** para inicio de sesion (comparacion con base de datos)
- **Gestion de usuarios** (listar, consultar, eliminar)
- **Base de datos local** en JSON (sin dependencias externas)
- **Sin dlib** - Usa OpenCV puro para maxima compatibilidad

## Requisitos

- Windows 10/11
- Python 3.8+
- Webcam

## Instalacion

```powershell
# 1. Clonar el repositorio
git clone https://github.com/TU_USUARIO/facial-recognition.git
cd facial-recognition

# 2. Ejecutar el setup (instala dependencias y descarga modelos de IA)
powershell -ExecutionPolicy Bypass -File .\setup.ps1

# 3. Ejecutar el programa
powershell -ExecutionPolicy Bypass -File .\FacialRecognition.ps1
```

## Estructura del Proyecto

```
facial-recognition/
├── FacialRecognition.ps1    # Script principal (menu interactivo)
├── setup.ps1                # Instalacion de dependencias y modelos
├── python/
│   ├── capture_face.py      # Captura facial con webcam (YuNet)
│   ├── register_face.py     # Registro: captura + embedding + BD
│   ├── recognize_face.py    # Login: captura + comparacion
│   └── manage_users.py      # CRUD de usuarios
├── database/
│   └── users.json           # Base de datos (se genera automaticamente)
├── models/                  # Modelos ONNX (se descargan con setup.ps1)
└── faces/                   # Imagenes de referencia por usuario
```

## Tecnologias

| Componente | Tecnologia |
|------------|------------|
| Interfaz | PowerShell |
| Deteccion facial | OpenCV FaceDetectorYN (YuNet) |
| Reconocimiento facial | OpenCV FaceRecognizerSF (SFace) |
| Base de datos | JSON local |
| Modelos | ONNX (OpenCV Zoo) |

## Uso

1. **Registrar usuario**: Ingresa nombre, acepta el consentimiento, y captura tu rostro con la webcam
2. **Iniciar sesion**: La camara escanea tu rostro y lo compara con los usuarios registrados
3. **Gestionar**: Lista, consulta detalles o elimina usuarios

## Licencia

MIT
