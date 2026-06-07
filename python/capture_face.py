"""
capture_face.py - Modulo utilitario para captura facial con webcam.

Usa OpenCV FaceDetectorYN (modelo YuNet) para deteccion facial en tiempo real.
No requiere dlib ni face_recognition.
"""

import cv2
import sys
import os
import numpy as np


# Ruta al modelo de deteccion facial
MODELS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "models")
DETECTION_MODEL = os.path.join(MODELS_DIR, "face_detection_yunet_2023mar.onnx")


def get_face_detector(width, height):
    """Crea un detector facial YuNet configurado para el tamanio del frame."""
    if not os.path.exists(DETECTION_MODEL):
        raise FileNotFoundError(
            f"Modelo de deteccion no encontrado: {DETECTION_MODEL}\n"
            "Ejecuta setup.ps1 para descargar los modelos."
        )

    detector = cv2.FaceDetectorYN.create(
        model=DETECTION_MODEL,
        config="",
        input_size=(width, height),
        score_threshold=0.7,
        nms_threshold=0.3,
        top_k=5000,
    )
    return detector


def detect_faces_in_frame(detector, frame):
    """
    Detecta rostros usando YuNet.

    Returns:
        faces: Array de detecciones. Cada fila contiene:
               [x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_rcm, y_rcm, x_lcm, y_lcm, score]
               donde re=right eye, le=left eye, nt=nose tip, rcm/lcm=right/left corner mouth
    """
    _, faces = detector.detect(frame)
    return faces if faces is not None else np.array([])


def draw_face_overlay(frame, faces, status_text="Buscando rostro..."):
    """Dibuja rectangulos y overlay sobre los rostros detectados."""
    display = frame.copy()
    h, w = display.shape[:2]

    # Overlay semi-transparente en la parte superior
    overlay = display.copy()
    cv2.rectangle(overlay, (0, 0), (w, 50), (20, 20, 20), -1)
    cv2.addWeighted(overlay, 0.7, display, 0.3, 0, display)

    has_face = len(faces) > 0

    if has_face:
        for face in faces:
            x, y, fw, fh = int(face[0]), int(face[1]), int(face[2]), int(face[3])
            score = face[14]

            # Color basado en la confianza
            color = (0, 220, 100) if score > 0.8 else (0, 180, 255)
            thickness = 2
            corner_len = 20

            # Esquinas estilizadas
            cv2.line(display, (x, y), (x + corner_len, y), color, thickness + 1)
            cv2.line(display, (x, y), (x, y + corner_len), color, thickness + 1)
            cv2.line(display, (x + fw, y), (x + fw - corner_len, y), color, thickness + 1)
            cv2.line(display, (x + fw, y), (x + fw, y + corner_len), color, thickness + 1)
            cv2.line(display, (x, y + fh), (x + corner_len, y + fh), color, thickness + 1)
            cv2.line(display, (x, y + fh), (x, y + fh - corner_len), color, thickness + 1)
            cv2.line(display, (x + fw, y + fh), (x + fw - corner_len, y + fh), color, thickness + 1)
            cv2.line(display, (x + fw, y + fh), (x + fw, y + fh - corner_len), color, thickness + 1)

            # Rectangulo exterior tenue
            cv2.rectangle(display, (x, y), (x + fw, y + fh), (0, 180, 80), 1)

            # Puntos de referencia faciales (ojos, nariz, boca)
            for i in range(5):
                px = int(face[4 + i * 2])
                py = int(face[5 + i * 2])
                cv2.circle(display, (px, py), 2, (255, 255, 0), -1)

            # Confianza
            conf_text = f"{score:.0%}"
            cv2.putText(display, conf_text, (x, y - 5),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.45, color, 1, cv2.LINE_AA)

        status_text = "Rostro detectado - Presiona ESPACIO para capturar"
        status_color = (0, 220, 100)
    else:
        status_color = (0, 150, 255)

    # Texto de estado
    cv2.putText(
        display, status_text, (15, 35),
        cv2.FONT_HERSHEY_SIMPLEX, 0.6, status_color, 1, cv2.LINE_AA
    )

    # Instruccion inferior
    overlay2 = display.copy()
    cv2.rectangle(overlay2, (0, h - 35), (w, h), (20, 20, 20), -1)
    cv2.addWeighted(overlay2, 0.7, display, 0.3, 0, display)
    cv2.putText(
        display, "ESC = Cancelar | ESPACIO = Capturar",
        (15, h - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (180, 180, 180), 1, cv2.LINE_AA
    )

    return display


def capture_face_from_webcam(window_title="Captura Facial", camera_index=0):
    """
    Abre la webcam, muestra vista previa con deteccion facial en vivo,
    y captura el frame cuando el usuario presiona ESPACIO.

    Returns:
        tuple: (success: bool, frame: np.ndarray or None, faces: np.ndarray or None)
    """
    cap = cv2.VideoCapture(camera_index, cv2.CAP_DSHOW)

    if not cap.isOpened():
        cap = cv2.VideoCapture(camera_index)
        if not cap.isOpened():
            return False, None, None

    # Configurar resolucion
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    cap.set(cv2.CAP_PROP_FPS, 30)

    # Leer un frame para obtener dimensiones reales
    ret, test_frame = cap.read()
    if not ret:
        cap.release()
        return False, None, None

    h, w = test_frame.shape[:2]
    detector = get_face_detector(w, h)

    captured_frame = None
    captured_faces = None

    while True:
        ret, frame = cap.read()
        if not ret:
            break

        # Voltear horizontalmente (efecto espejo)
        frame = cv2.flip(frame, 1)

        # Detectar rostros
        faces = detect_faces_in_frame(detector, frame)
        has_face = len(faces) > 0

        # Dibujar overlay
        display = draw_face_overlay(frame, faces)
        cv2.imshow(window_title, display)

        key = cv2.waitKey(1) & 0xFF

        # ESC para cancelar
        if key == 27:
            break

        # ESPACIO para capturar (solo si hay rostro detectado)
        if key == 32 and has_face:
            captured_frame = frame.copy()
            captured_faces = faces.copy()

            # Flash visual
            flash = frame.copy()
            cv2.rectangle(flash, (0, 0), (w, h), (255, 255, 255), -1)
            cv2.addWeighted(flash, 0.3, frame, 0.7, 0, flash)
            cv2.imshow(window_title, flash)
            cv2.waitKey(200)
            break

    cap.release()
    cv2.destroyAllWindows()
    for _ in range(5):
        cv2.waitKey(1)

    if captured_frame is not None:
        return True, captured_frame, captured_faces
    return False, None, None


if __name__ == "__main__":
    success, frame, faces = capture_face_from_webcam("Test - Captura Facial")
    if success:
        cv2.imwrite("test_capture.jpg", frame)
        print(f"Captura guardada. Rostros detectados: {len(faces)}")
    else:
        print("Captura cancelada.")
