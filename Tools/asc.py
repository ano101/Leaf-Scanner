"""Обращения к App Store Connect.

Ключ и издатель берутся из окружения, а не зашиты в файл: ключ даёт полный
доступ к кабинету, и хранить его в репозитории нельзя.
"""
import json
import os
import sys
import time
from pathlib import Path

import jwt
import requests

KEY_ID = os.environ.get("ASC_KEY_ID", "BSUYSN9882")
ISSUER_ID = os.environ["ASC_ISSUER_ID"]
KEY_PATH = Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{KEY_ID}.p8"
BASE = "https://api.appstoreconnect.apple.com/v1"


def token() -> str:
    now = int(time.time())
    return jwt.encode(
        {"iss": ISSUER_ID, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        KEY_PATH.read_text(),
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(method: str, path: str, body: dict | None = None) -> dict:
    response = requests.request(
        method,
        path if path.startswith("http") else f"{BASE}{path}",
        headers={
            "Authorization": f"Bearer {token()}",
            "Content-Type": "application/json",
        },
        json=body,
        timeout=60,
    )

    if response.status_code >= 400:
        # Ошибка Apple печатается целиком:она содержит причину отказа,
        # без которой непонятно, что именно поправить.
        print(f"HTTP {response.status_code}", file=sys.stderr)
        print(response.text[:3000], file=sys.stderr)
        response.raise_for_status()

    return response.json() if response.text else {}


if __name__ == "__main__":
    method, path = sys.argv[1], sys.argv[2]
    body = json.loads(sys.argv[3]) if len(sys.argv) > 3 else None
    print(json.dumps(call(method, path, body), ensure_ascii=False, indent=2))
