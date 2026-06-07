"""
register_face.py - Registro de nuevos usuarios con captura facial.

Usa OpenCV FaceRecognizerSF (modelo SFace) para generar embeddings faciales.
No requiere dlib ni face_recognition.

Uso:
    python register_face.py --username <usuario> --fullname <nombre> --db <ruta_db> --faces-dir <ruta>

Salida (JSON a stdout):
    {"status": "success", "username": "...", "message": "..."}
    {"status": "error", "message": "..."}
"""

import argparse
import json
import os
import sys
import uuid
from datetime import datetime

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capture_face import capture_face_from_webcam

# Rutas a los modelos
MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
DETECTION_MODEL = os.path.join(MODELS_DIR, "face_detection_yunet_2023mar.onnx")
RECOGNITION_MODEL = os.path.join(MODELS_DIR, "face_recognition_sface_2021dec.onnx")


def get_face_recognizer():
    """Crea el reconocedor facial SFace."""
    if not os.path.exists(RECOGNITION_MODEL):
        raise FileNotFoundError(
            f"Modelo de reconocimiento no encontrado: {RECOGNITION_MODEL}\n"
            "Ejecuta setup.ps1 para descargar los modelos."
        )
    return cv2.FaceRecognizerSF.create(
        model=RECOGNITION_MODEL,
        config=""
    )


def generate_face_embedding(image, face_data):
    """
    Genera el embedding facial usando SFace.

    Args:
        image: Imagen BGR de OpenCV
        face_data: Datos de deteccion facial de YuNet (1 fila)

    Returns:
        tuple: (success: bool, embedding: list or None, message: str)
    """
    try:
        recognizer = get_face_recognizer()

        # Alinear el rostro usando los landmarks de YuNet
        aligned_face = recognizer.alignCrop(image, face_data)

        # Generar embedding (vector de 128 dimensiones)
        embedding = recognizer.feature(aligned_face)

        return True, embedding.flatten().tolist(), "Embedding generado exitosamente."
    except Exception as e:
        return False, None, f"Error al generar embedding: {str(e)}"


def save_face_image(image, username, faces_dir):
    """Guarda la imagen del rostro en el directorio del usuario."""
    user_dir = os.path.join(faces_dir, username)
    os.makedirs(user_dir, exist_ok=True)

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"face_{timestamp}.jpg"
    filepath = os.path.join(user_dir, filename)

    cv2.imwrite(filepath, image)
    return filepath


def load_database(db_path):
    """Carga la base de datos JSON."""
    if not os.path.exists(db_path):
        return {"users": [], "metadata": {"version": "1.0.0"}}

    with open(db_path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_database(db_path, data):
    """Guarda la base de datos JSON."""
    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def check_username_exists(db, username):
    """Verifica si un nombre de usuario ya existe."""
    for user in db.get("users", []):
        if user["username"].lower() == username.lower():
            return True
    return False


def check_face_already_registered(db, embedding, threshold=0.5):
    """
    Verifica si el rostro ya esta registrado usando cosine similarity.
    SFace embeddings se comparan con cosine score (mayor = mas similar).
    """
    recognizer = get_face_recognizer()
    new_emb = np.array(embedding, dtype=np.float32).reshape(1, -1)

    for user in db.get("users", []):
        stored_emb = np.array(user["face_encoding"], dtype=np.float32).reshape(1, -1)
        # cosine similarity: 1.0 = identico, 0.0 = diferente
        score = recognizer.match(new_emb, stored_emb, cv2.FaceRecognizerSF_FR_COSINE)
        if score >= threshold:
            return True, user["username"]

    return False, None


def register_user(username, full_name, db_path, faces_dir):
    """
    Flujo completo de registro de usuario.

    Returns:
        dict: Resultado del registro en formato JSON-serializable
    """
    result = {"status": "error", "message": ""}

    # Verificar que el username no exista
    db = load_database(db_path)
    if check_username_exists(db, username):
        result["message"] = f"El nombre de usuario '{username}' ya esta registrado."
        return result

    # Capturar rostro
    success, frame, faces = capture_face_from_webcam(
        window_title=f"Registro - {full_name}"
    )

    if not success or frame is None or faces is None:
        result["message"] = "Captura cancelada por el usuario."
        result["status"] = "cancelled"
        return result

    if len(faces) == 0:
        result["message"] = "No se detecto ningun rostro en la imagen capturada."
        return result

    if len(faces) > 1:
        result["message"] = "Se detectaron multiples rostros. Solo debe haber un rostro."
        return result

    # Generar embedding con la primera (unica) cara
    face_data = faces[0]
    success, embedding, message = generate_face_embedding(frame, face_data)
    if not success:
        result["message"] = message
        return result

    # Verificar que el rostro no este ya registrado
    if len(db.get("users", [])) > 0:
        is_duplicate, existing_user = check_face_already_registered(db, embedding)
        if is_duplicate:
            result["message"] = (
                f"Este rostro ya esta registrado bajo el usuario '{existing_user}'. "
                "No se puede registrar el mismo rostro con otro usuario."
            )
            return result

    # Guardar imagen
    image_path = save_face_image(frame, username, faces_dir)

    # Crear registro de usuario
    user_record = {
        "id": str(uuid.uuid4()),
        "username": username,
        "full_name": full_name,
        "face_encoding": embedding,
        "face_image_path": os.path.relpath(image_path, os.path.dirname(db_path) + "/.."),
        "registered_at": datetime.now().isoformat(),
        "consent_given": True,
        "consent_timestamp": datetime.now().isoformat(),
    }

    # Guardar en base de datos
    db["users"].append(user_record)
    save_database(db_path, db)

    result["status"] = "success"
    result["username"] = username
    result["full_name"] = full_name
    result["user_id"] = user_record["id"]
    result["message"] = f"Usuario '{full_name}' registrado exitosamente."

    return result


def main():
    parser = argparse.ArgumentParser(description="Registro facial de usuario")
    parser.add_argument("--username", required=True, help="Nombre de usuario")
    parser.add_argument("--fullname", required=True, help="Nombre completo")
    parser.add_argument("--db", required=True, help="Ruta a la base de datos JSON")
    parser.add_argument("--faces-dir", required=True, help="Directorio de imagenes")

    args = parser.parse_args()

    result = register_user(
        username=args.username,
        full_name=args.fullname,
        db_path=args.db,
        faces_dir=args.faces_dir,
    )

    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0 if result["status"] == "success" else 1)


if __name__ == "__main__":
    main()
