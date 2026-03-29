#!/usr/bin/env bash
# Prints an absolute path to the Uzu model directory.
# The Rust `uzu` crate needs a Mirai registry bundle: config.json with "model_type": "language_model".
# Raw `hf download` of mlx-community repos (HF `llama` config) is skipped — use `just download-uzu`.
#
# Env: UZU_MODEL_PATH, UZU_MODEL_DIR + UZU_MODEL_BUNDLE, UZU_MODEL_BUNDLE.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${UZU_MODEL_BUNDLE:-Llama-3.2-1B-Instruct-8bit}"

abs_dir() {
  local p="$1"
  [[ -d "$p" ]] || return 1
  (cd "$p" && pwd)
}

# Uzu-ready bundle (not HF transformers model_type).
uzu_config_ok() {
  local d="$1"
  [[ -f "$d/config.json" ]] || return 1
  grep -q '"model_type"[[:space:]]*:[[:space:]]*"language_model"' "$d/config.json" 2>/dev/null
}

if [[ -n "${UZU_MODEL_PATH:-}" ]]; then
  mp="$UZU_MODEL_PATH"
  [[ "$mp" = /* ]] || mp="$ROOT/$mp"
  if p="$(abs_dir "$mp" 2>/dev/null)"; then
    printf '%s\n' "$p"
    exit 0
  fi
fi

if [[ -n "${UZU_MODEL_DIR:-}" ]]; then
  cand="${UZU_MODEL_DIR%/}/$BUNDLE"
  if p="$(abs_dir "$cand" 2>/dev/null)"; then
    printf '%s\n' "$p"
    exit 0
  fi
  if p="$(abs_dir "$ROOT/$cand" 2>/dev/null)"; then
    printf '%s\n' "$p"
    exit 0
  fi
  if [[ "$cand" = /* ]]; then printf '%s\n' "$cand"; else printf '%s\n' "$ROOT/$cand"; fi
  exit 0
fi

for try in "$ROOT/models/$BUNDLE" "$ROOT/lalamo/_models/$BUNDLE"; do
  if [[ -d "$try" ]] && uzu_config_ok "$try"; then
    abs_dir "$try"
    exit 0
  fi
done

printf '%s\n' "$ROOT/models/$BUNDLE"
