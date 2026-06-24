import os
import json
import re
import time
import urllib.request
from urllib.parse import urlparse

JSON_FILE = "tft_items.json"
OUTPUT_FOLDER = "items"
DELAY_BETWEEN_DOWNLOADS = 0.1


def sanitize_filename(name):
    sanitized = re.sub(r'[\\/*?:"<>|]', "", name)
    return sanitized.strip().strip(".")


def get_extension(url):
    parsed = urlparse(url)
    _, ext = os.path.splitext(parsed.path)
    return ext.lower() if ext else ".png"


def download_images():
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)

    if not os.path.exists(JSON_FILE):
        print(f"Error: Could not find '{JSON_FILE}' in the current directory.")
        return

    try:
        with open(JSON_FILE, "r", encoding="utf-8") as f:
            items = json.load(f)
    except Exception as e:
        print(f"Error reading JSON file: {e}")
        return

    total_items = len(items)
    print(f"Found {total_items} items. Starting downloads...")

    success_count = 0
    fail_count = 0

    for idx, item in enumerate(items, 1):
        name = item.get("Name")
        url = item.get("ImageUrl")

        if not name or not url:
            continue

        safe_name = sanitize_filename(name)
        ext = get_extension(url)
        filepath = os.path.join(OUTPUT_FOLDER, f"{safe_name}{ext}")

        print(f"[{idx}/{total_items}] Downloading {name}...")

        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                },
            )
            with urllib.request.urlopen(req, timeout=10) as response:
                data = response.read()
                with open(filepath, "wb") as f:
                    f.write(data)
            success_count += 1
        except Exception:
            fail_count += 1

        time.sleep(DELAY_BETWEEN_DOWNLOADS)

    print(f"Complete. Success: {success_count}, Failed: {fail_count}")


if __name__ == "__main__":
    download_images()
