"""
recognize_face.py - Reconocimiento facial para inicio de sesion.

Usa OpenCV FaceRecognizerSF (modelo SFace) para comparar embeddings faciales.
No requiere dlib ni face_recognition.

Uso:
    python recognize_face.py --db <ruta_db> [--threshold 0.363]

Salida (JSON a stdout):
    {"status": "match", "username": "...", "full_name": "...", "confidence": 0.85}
    {"status": "no_match", "message": "..."}
    {"status": "error", "message": "..."}
    {"status": "cancelled", "message": "..."}
"""

import argparse
import json
import os
import sys
from datetime import datetime

import cv2
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from capture_face import capture_face_from_webcam

# Rutas a modelos
MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
RECOGNITION_MODEL = os.path.join(MODELS_DIR, "face_recognition_sface_2021dec.onnx")


def get_face_recognizer():
    """Crea el reconocedor facial SFace."""
    if not os.path.exists(RECOGNITION_MODEL):
        raise FileNotFoundError(
            f"Modelo de reconocimiento no encontrado: {RECOGNITION_MODEL}"
        )
    return cv2.FaceRecognizerSF.create(
        model=RECOGNITION_MODEL,
        config=""
    )


def load_database(db_path):
    """Carga la base de datos JSON."""
    if not os.path.exists(db_path):
        return {"users": []}

    with open(db_path, "r", encoding="utf-8") as f:
        return json.load(f)


def find_matching_user(embedding, db, threshold=0.363):
    """
    Compara un embedding facial contra todos los usuarios usando cosine similarity.

    SFace cosine similarity:
    - >= 0.363: match (umbral recomendado por OpenCV)
    - < 0.363: no match

    Args:
        embedding: Embedding facial (lista de floats)
        db: Base de datos cargada
        threshold: Umbral de cosine similarity para match

    Returns:
        tuple: (matched: bool, user: dict or None, confidence: float)
    """
    if not db.get("users"):
        return False, None, 0.0

    recognizer = get_face_recognizer()
    new_emb = np.array(embedding, dtype=np.float32).reshape(1, -1)

    best_match = None
    best_score = -1.0

    for user in db["users"]:
        stored_emb = np.array(user["face_encoding"], dtype=np.float32).reshape(1, -1)
        score = recognizer.match(new_emb, stored_emb, cv2.FaceRecognizerSF_FR_COSINE)

        if score > best_score:
            best_score = score
            best_match = user

    if best_score >= threshold and best_match is not None:
        # Normalizar confianza a 0-1 (threshold..1.0 -> 0..1)
        confidence = min(1.0, (best_score - threshold) / (1.0 - threshold))
        return True, best_match, round(confidence, 4)

    return False, None, 0.0


def recognize_user(db_path, threshold=0.363):
    """
    Flujo completo de reconocimiento facial.

    Returns:
        dict: Resultado del reconocimiento en formato JSON-serializable
    """
    result = {"status": "error", "message": ""}

    # Cargar base de datos
    db = load_database(db_path)

    if not db.get("users"):
        result["message"] = "No hay usuarios registrados en la base de datos."
        return result

    user_count = len(db["users"])

    # Capturar rostro
    success, frame, faces = capture_face_from_webcam(
        window_title="Inicio de Sesion - Reconocimiento Facial"
    )

    if not success or frame is None:
        result["status"] = "cancelled"
        result["message"] = "Inicio de sesion cancelado por el usuario."
        return result

    if faces is None or len(faces) == 0:
        result["message"] = "No se detecto ningun rostro en la imagen capturada."
        return result

    if len(faces) > 1:
        result["message"] = (
            "Se detectaron multiples rostros. "
            "Solo debe haber una persona frente a la camara."
        )
        return result

    # Generar embedding
    try:
        recognizer = get_face_recognizer()
        face_data = faces[0]

        # Alinear y extraer embedding
        aligned_face = recognizer.alignCrop(frame, face_data)
        embedding = recognizer.feature(aligned_face)
        current_embedding = embedding.flatten().tolist()
    except Exception as e:
        result["message"] = f"Error al generar embedding: {str(e)}"
        return result

    # Buscar coincidencia
    matched, user, confidence = find_matching_user(
        current_embedding, db, threshold
    )

    if matched and user:
        result["status"] = "match"
        result["username"] = user["username"]
        result["full_name"] = user["full_name"]
        result["user_id"] = user["id"]
        result["confidence"] = confidence
        result["registered_at"] = user["registered_at"]
        result["message"] = f"Usuario identificado: {user['full_name']}"
        result["users_compared"] = user_count
    else:
        result["status"] = "no_match"
        result["message"] = "Rostro no reconocido. No se encontro coincidencia en la base de datos."
        result["users_compared"] = user_count

    return result


def main():
    parser = argparse.ArgumentParser(description="Reconocimiento facial - Login")
    parser.add_argument("--db", required=True, help="Ruta a la base de datos JSON")
    parser.add_argument(
        "--tolerance",
        type=float,
        default=0.363,
        help="Umbral de cosine similarity (0.0-1.0, default: 0.363)",
    )

    args = parser.parse_args()

    try:
        result = recognize_user(db_path=args.db, threshold=args.tolerance)
    except Exception as e:
        result = {
            "status": "error",
            "message": f"Error inesperado: {str(e)}"
        }
        print(str(e), file=sys.stderr)

    print(json.dumps(result, ensure_ascii=False))

    if result["status"] == "match":
        sys.exit(0)
    elif result["status"] == "cancelled":
        sys.exit(2)
    else:
        sys.exit(1)


if __name__ == "__main__":
    main()
