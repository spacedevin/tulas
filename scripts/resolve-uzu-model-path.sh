#!/usr/bin/env bash
# Print absolute path to Uzu bundle (config must be Mirai language_model format).
# Env: UZU_MODEL_PATH, UZU_MODEL_DIR + UZU_MODEL_BUNDLE, UZU_MODEL_BUNDLE.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="${UZU_MODEL_BUNDLE:-Llama-3.2-1B-Instruct-8bit}"

abs_dir() { [[ -d "$1" ]] && (cd "$1" && pwd); }

ok() {
  [[ -f "$1/config.json" ]] && grep -q '"model_type"[[:space:]]*:[[:space:]]*"language_model"' "$1/config.json" 2>/dev/null
}

if [[ -n "${UZU_MODEL_PATH:-}" ]]; then
  mp="${UZU_MODEL_PATH}"
  [[ "$mp" = /* ]] || mp="$ROOT/$mp"
  p="$(abs_dir "$mp" 2>/dev/null || true)"
  [[ -n "$p" ]] && { printf '%s\n' "$p"; exit 0; }
fi

if [[ -n "${UZU_MODEL_DIR:-}" ]]; then
  cand="${UZU_MODEL_DIR%/}/$BUNDLE"
  p="$(abs_dir "$cand" 2>/dev/null || true)"
  [[ -z "$p" ]] && p="$(abs_dir "$ROOT/$cand" 2>/dev/null || true)"
  [[ -n "$p" ]] && { printf '%s\n' "$p"; exit 0; }
  [[ "$cand" = /* ]] && printf '%s\n' "$cand" || printf '%s\n' "$ROOT/$cand"
  exit 0
fi

try="$ROOT/models/$BUNDLE"
if [[ -d "$try" ]] && ok "$try"; then
  abs_dir "$try"
  exit 0
fi

printf '%s\n' "$try"
