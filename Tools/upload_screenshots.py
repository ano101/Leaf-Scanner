"""Загрузка снимков экрана в App Store Connect.

Загрузка идёт в три приёма: заводится место под файл, файл кладётся по
выданной ссылке, затем подтверждается контрольной суммой. Пропуск любого
шага оставляет в кабинете пустую запись, которую видно только там.
"""
import hashlib
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from asc import call, token  # noqa: E402

import requests  # noqa: E402

VERSION_ID = sys.argv[1]
LOCALE = sys.argv[2]
DISPLAY_TYPE = sys.argv[3]
FILES = [Path(p) for p in sys.argv[4:]]


def screenshot_set() -> str:
    existing = call("GET", f"/appStoreVersionLocalizations/{LOCALE}/appScreenshotSets")
    for item in existing["data"]:
        if item["attributes"]["screenshotDisplayType"] == DISPLAY_TYPE:
            return item["id"]

    created = call("POST", "/appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
            "relationships": {
                "appStoreVersionLocalization": {
                    "data": {"type": "appStoreVersionLocalizations", "id": LOCALE}
                }
            },
        }
    })
    return created["data"]["id"]


def upload(set_id: str, path: Path) -> None:
    data = path.read_bytes()

    reserved = call("POST", "/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileSize": len(data), "fileName": path.name},
            "relationships": {
                "appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}
            },
        }
    })

    screenshot_id = reserved["data"]["id"]
    for operation in reserved["data"]["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in operation["requestHeaders"]}
        chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
        response = requests.request(operation["method"], operation["url"], headers=headers, data=chunk, timeout=300)
        response.raise_for_status()

    call("PATCH", f"/appScreenshots/{screenshot_id}", {
        "data": {
            "type": "appScreenshots",
            "id": screenshot_id,
            "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
        }
    })
    print("загружен:", path.name)


set_id = screenshot_set()
for file in FILES:
    upload(set_id, file)
