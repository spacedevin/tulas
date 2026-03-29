#!/usr/bin/env python3
"""
Download a pre-built Uzu bundle from the Mirai registry (same source as
trymirai/uzu tools/helpers main.py). These checkpoints are already in
language_model format — not raw Hugging Face mlx-community layouts.

Usage:
  python3 scripts/download-uzu-registry-model.py [REPO_ID] [DEST_DIR]

Env:
  UZU_ENGINE_VERSION — must match the `uzu` crate version in Cargo.lock
                       (default: parsed from Cargo.lock).
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path


def read_uzu_version_from_lock(root: Path) -> str:
    text = (root / "Cargo.lock").read_text(encoding="utf-8")
    lines = text.splitlines()
    for i, line in enumerate(lines):
        if line.strip() == 'name = "uzu"':
            for j in range(i + 1, min(i + 12, len(lines))):
                ln = lines[j]
                if ln.startswith("version = "):
                    return ln.split('"')[1]
    raise SystemExit("Could not find uzu package version in Cargo.lock")


def fetch_registry(version: str) -> list[dict]:
    url = (
        "https://sdk.trymirai.com/api/v1/models/list/uzu/"
        f"{version}?includeTraces=true&type=language_model"
    )
    req = urllib.request.Request(url, headers={"User-Agent": "tish-mlx-burn-download"})
    with urllib.request.urlopen(req, timeout=120) as r:
        data = json.load(r)
    return data.get("models", [])


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": "tish-mlx-burn-download"})
    with urllib.request.urlopen(req, timeout=None) as resp, open(dest, "wb") as f:
        while True:
            chunk = resp.read(8 * 1024 * 1024)
            if not chunk:
                break
            f.write(chunk)


def main() -> None:
    root = Path(__file__).resolve().parent.parent
    repo_id = (
        sys.argv[1]
        if len(sys.argv) > 1
        else os.environ.get("UZU_REGISTRY_REPO_ID", "mlx-community/Llama-3.2-1B-Instruct-8bit")
    )
    dest = Path(sys.argv[2] if len(sys.argv) > 2 else os.environ.get("UZU_MODEL_DEST", ""))
    if not dest or dest == Path("."):
        dest = root / "models" / "Llama-3.2-1B-Instruct-8bit"
    if not dest.is_absolute():
        dest = (root / dest).resolve()

    version = os.environ.get("UZU_ENGINE_VERSION") or read_uzu_version_from_lock(root)
    print(f"Mirai Uzu registry API version={version!r} model={repo_id!r} -> {dest}/")

    models = fetch_registry(version)
    model = next((m for m in models if m.get("repoId") == repo_id), None)
    if model is None:
        raise SystemExit(
            f"Model {repo_id!r} not found for uzu/{version}. "
            "Try UZU_ENGINE_VERSION matching Cargo.lock or pick another repoId from the registry."
        )

    name = model.get("name", repo_id.split("/")[-1])
    dest = dest.resolve()
    dest.mkdir(parents=True, exist_ok=True)

    for f in model.get("files", []):
        fp = dest / f["name"]
        if fp.exists():
            print(f"  skip (exists): {f['name']}")
            continue
        print(f"  fetch: {f['name']}")
        download_file(f["url"], fp)

    for spec in model.get("speculators", []):
        uc = spec.get("useCase", "default")
        for f in spec.get("files", []):
            fp = dest / "speculators" / uc / f["name"]
            if fp.exists():
                print(f"  skip (exists): speculators/{uc}/{f['name']}")
                continue
            print(f"  fetch: speculators/{uc}/{f['name']}")
            download_file(f["url"], fp)

    print("Done.")


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as e:
        raise SystemExit(f"HTTP {e.code}: {e.reason}") from e
