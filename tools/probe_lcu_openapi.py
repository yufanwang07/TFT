#!/usr/bin/env python3
"""Print TFT-adjacent League Client API endpoints from the local OpenAPI spec."""

from __future__ import annotations

import argparse
import base64
import json
import os
import ssl
import sys
import urllib.error
import urllib.request
from pathlib import Path


DEFAULT_TERMS = (
    "tft",
    "teamfight",
    "augment",
    "inventory",
    "bench",
    "shop",
    "board",
    "unit",
    "champion",
    "companion",
    "regalia",
    "gameflow",
    "session",
)


def default_lockfile_paths() -> list[Path]:
    home = Path.home()
    return [
        Path("/Applications/League of Legends.app/Contents/LoL/lockfile"),
        home / "Applications/League of Legends.app/Contents/LoL/lockfile",
        home / "Library/Application Support/Riot Games/League of Legends/lockfile",
    ]


def find_lockfile(explicit: str | None) -> Path:
    if explicit:
        path = Path(explicit).expanduser()
        if path.exists():
            return path
        raise SystemExit(f"Lockfile not found: {path}")

    env_path = os.environ.get("LCU_LOCKFILE")
    if env_path:
        path = Path(env_path).expanduser()
        if path.exists():
            return path

    for path in default_lockfile_paths():
        if path.exists():
            return path
    raise SystemExit("League lockfile not found. Start League/TFT or pass --lockfile.")


def read_lockfile(path: Path) -> dict[str, str]:
    raw = path.read_text(encoding="utf-8").strip()
    parts = raw.split(":")
    if len(parts) < 5:
        raise SystemExit(f"Unexpected lockfile format: {path}")
    return {
        "process": parts[0],
        "pid": parts[1],
        "port": parts[2],
        "password": parts[3],
        "protocol": parts[4],
    }


def get_json(url: str, password: str) -> dict:
    auth = base64.b64encode(f"riot:{password}".encode("utf-8")).decode("ascii")
    request = urllib.request.Request(url, headers={"Authorization": f"Basic {auth}"})
    context = ssl._create_unverified_context()
    try:
        with urllib.request.urlopen(request, context=context, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"HTTP {exc.code} for {url}: {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise SystemExit(f"Could not reach League Client API at {url}: {exc.reason}") from exc


def matching_paths(spec: dict, terms: tuple[str, ...]) -> list[tuple[str, str, str]]:
    matches: list[tuple[str, str, str]] = []
    paths = spec.get("paths") if isinstance(spec, dict) else {}
    if not isinstance(paths, dict):
        return matches

    for path, methods in sorted(paths.items()):
        if not isinstance(methods, dict):
            continue
        haystack = path.lower()
        for method, details in sorted(methods.items()):
            if not isinstance(details, dict):
                continue
            summary = details.get("summary") or details.get("operationId") or ""
            text = f"{haystack} {summary}".lower()
            if any(term in text for term in terms):
                matches.append((method.upper(), path, str(summary)))
    return matches


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lockfile", help="Path to League lockfile. Defaults to common install locations or LCU_LOCKFILE.")
    parser.add_argument("--terms", nargs="*", default=DEFAULT_TERMS, help="Lowercase filter terms.")
    parser.add_argument("--json", action="store_true", help="Emit JSON instead of text.")
    args = parser.parse_args()

    lockfile = find_lockfile(args.lockfile)
    info = read_lockfile(lockfile)
    base = f"{info['protocol']}://127.0.0.1:{info['port']}"
    spec = get_json(f"{base}/swagger/v3/openapi.json", info["password"])
    rows = matching_paths(spec, tuple(term.lower() for term in args.terms))

    if args.json:
        print(json.dumps({"lockfile": str(lockfile), "count": len(rows), "endpoints": rows}, indent=2))
        return 0

    print(f"Lockfile: {lockfile}")
    print(f"Matched endpoints: {len(rows)}")
    for method, path, summary in rows:
        suffix = f"  # {summary}" if summary else ""
        print(f"{method:7} {path}{suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
