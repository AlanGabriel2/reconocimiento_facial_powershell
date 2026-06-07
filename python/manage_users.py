"""
manage_users.py - Gestión de usuarios registrados.

Permite listar, ver detalles y eliminar usuarios de la base de datos.

Uso:
    python manage_users.py --action list --db <ruta_db>
    python manage_users.py --action detail --db <ruta_db> --username <usuario>
    python manage_users.py --action delete --db <ruta_db> --username <usuario> --faces-dir <ruta_faces>

Salida (JSON a stdout):
    {"status": "success", "data": [...]}
    {"status": "error", "message": "..."}
"""

import argparse
import json
import os
import shutil
import sys
from datetime import datetime


def load_database(db_path):
    """Carga la base de datos JSON."""
    if not os.path.exists(db_path):
        return {"users": [], "metadata": {}}

    with open(db_path, "r", encoding="utf-8-sig") as f:
        return json.load(f)


def save_database(db_path, data):
    """Guarda la base de datos JSON."""
    with open(db_path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def list_users(db_path):
    """Lista todos los usuarios registrados (sin encodings)."""
    db = load_database(db_path)
    users = []

    for user in db.get("users", []):
        users.append({
            "id": user.get("id", "N/A"),
            "username": user.get("username", "N/A"),
            "full_name": user.get("full_name", "N/A"),
            "registered_at": user.get("registered_at", "N/A"),
            "consent_given": user.get("consent_given", False),
        })

    return {
        "status": "success",
        "total_users": len(users),
        "users": users,
    }


def get_user_detail(db_path, username):
    """Obtiene los detalles de un usuario específico (sin encoding)."""
    db = load_database(db_path)

    for user in db.get("users", []):
        if user["username"].lower() == username.lower():
            return {
                "status": "success",
                "user": {
                    "id": user.get("id"),
                    "username": user.get("username"),
                    "full_name": user.get("full_name"),
                    "registered_at": user.get("registered_at"),
                    "consent_given": user.get("consent_given"),
                    "consent_timestamp": user.get("consent_timestamp"),
                    "face_image_path": user.get("face_image_path"),
                    "encoding_dimensions": len(user.get("face_encoding", [])),
                },
            }

    return {
        "status": "error",
        "message": f"Usuario '{username}' no encontrado.",
    }


def delete_user(db_path, username, faces_dir):
    """Elimina un usuario de la base de datos y sus imágenes."""
    db = load_database(db_path)
    user_found = False
    full_name = ""

    # Buscar y eliminar usuario
    updated_users = []
    for user in db.get("users", []):
        if user["username"].lower() == username.lower():
            user_found = True
            full_name = user.get("full_name", username)
        else:
            updated_users.append(user)

    if not user_found:
        return {
            "status": "error",
            "message": f"Usuario '{username}' no encontrado.",
        }

    # Actualizar base de datos
    db["users"] = updated_users
    save_database(db_path, db)

    # Eliminar directorio de imágenes
    user_faces_dir = os.path.join(faces_dir, username)
    if os.path.exists(user_faces_dir):
        shutil.rmtree(user_faces_dir)

    return {
        "status": "success",
        "message": f"Usuario '{full_name}' ({username}) eliminado exitosamente.",
        "username": username,
        "full_name": full_name,
    }


def main():
    parser = argparse.ArgumentParser(description="Gestión de usuarios")
    parser.add_argument(
        "--action",
        required=True,
        choices=["list", "detail", "delete"],
        help="Acción a realizar",
    )
    parser.add_argument("--db", required=True, help="Ruta a la base de datos JSON")
    parser.add_argument("--username", help="Nombre de usuario (requerido para detail/delete)")
    parser.add_argument("--faces-dir", help="Directorio de imágenes (requerido para delete)")

    args = parser.parse_args()

    if args.action == "list":
        result = list_users(args.db)

    elif args.action == "detail":
        if not args.username:
            result = {"status": "error", "message": "Se requiere --username para esta acción."}
        else:
            result = get_user_detail(args.db, args.username)

    elif args.action == "delete":
        if not args.username:
            result = {"status": "error", "message": "Se requiere --username para esta acción."}
        elif not args.faces_dir:
            result = {"status": "error", "message": "Se requiere --faces-dir para esta acción."}
        else:
            result = delete_user(args.db, args.username, args.faces_dir)

    # Salida JSON para PowerShell
    print(json.dumps(result, ensure_ascii=False))
    sys.exit(0 if result["status"] == "success" else 1)


if __name__ == "__main__":
    main()
