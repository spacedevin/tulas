# `just` alone = same as `just run` (default model + prompt + token cap from variables below).
# Tish samples: `just tish-llm` / `just tish-count-tokens` (optional; needs `../tish`).

default:
    @just run

# Default bundle directory (must match defaultModelRelPath in scripts/download-uzu-registry-model.tish).
models_dir := "models"
model_folder := "Llama-3.2-1B-Instruct-8bit"
benchmarks_dir := "benchmarks"
tish_manifest := "../tish/Cargo.toml"

prompt := "Tell me about London in three sentences."
tokens := "64"
benchmark_prompt := "Recite the poem 'The Road Not Taken' by Robert Frost in full."
benchmark_tokens := "256"

# Fetch bundle: defaults live in scripts/download-uzu-registry-model.tish (optional: UZU_REGISTRY_REPO_ID, UZU_MODEL_DEST, UZU_ENGINE_VERSION).
download:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    "${TISH:-tish}" run scripts/download-uzu-registry-model.tish --backend vm

download-uzu:
    @just download

build:
    cargo build --release

# Stream tokens to stdout (default model: models/<model_folder>/).
run *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    if [[ -n "${1:-}" && -d "$1" ]]; then
        MODEL=$1; shift
        P="${1:-{{prompt}}}"; T="${2:-{{tokens}}}"
    else
        if [[ -n "${UZU_MODEL_PATH:-}" ]]; then
            MODEL="$UZU_MODEL_PATH"
            [[ "$MODEL" == /* ]] || MODEL="$PWD/$MODEL"
        else
            MODEL="$PWD/{{models_dir}}/{{model_folder}}"
        fi
        P="${1:-{{prompt}}}"; T="${2:-{{tokens}}}"
    fi
    [[ -d "$MODEL" ]] || { echo "No bundle at $MODEL — run: just download"; exit 1; }
    cargo run --example llm_uzu --release -- --stream "$MODEL" "$P" "$T"

uzu *ARGS:
    @just run {{ARGS}}

# Same defaults as `just run`: default model dir, {{prompt}}, {{tokens}}; extra args replace/extend.
tish-llm *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    mkdir -p examples/llm-uzu-tish/dist
    cargo run --manifest-path "{{tish_manifest}}" -q -p tishlang -- compile --target native --native-backend rust --feature process examples/llm-uzu-tish/src/main.tish -o examples/llm-uzu-tish/dist/llm-uzu-tish
    BIN=./examples/llm-uzu-tish/dist/llm-uzu-tish
    if [ "$#" -eq 0 ]; then
      MODEL="${UZU_MODEL_PATH:-$PWD/{{models_dir}}/{{model_folder}}}"
      [[ "$MODEL" == /* ]] || MODEL="$PWD/$MODEL"
      [[ -d "$MODEL" ]] || { echo "No bundle at $MODEL — run: just download"; exit 1; }
      exec "$BIN" --stream "$MODEL" "{{prompt}}" "{{tokens}}"
    fi
    exec "$BIN" "$@"

# With no args: default tokenizer under the default model dir + short sample text.
tish-count-tokens *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    mkdir -p examples/count-tokens-tish/dist
    cargo run --manifest-path "{{tish_manifest}}" -q -p tishlang -- compile --target native --native-backend rust --feature process examples/count-tokens-tish/src/main.tish -o examples/count-tokens-tish/dist/count-tokens-tish
    BIN=./examples/count-tokens-tish/dist/count-tokens-tish
    if [ "$#" -eq 0 ]; then
      MODEL="${UZU_MODEL_PATH:-$PWD/{{models_dir}}/{{model_folder}}}"
      [[ "$MODEL" == /* ]] || MODEL="$PWD/$MODEL"
      TOK="$MODEL/tokenizer.json"
      [[ -f "$TOK" ]] || { echo "Missing $TOK — run: just download"; exit 1; }
      exec "$BIN" "$TOK" "{{prompt}}"
    fi
    exec "$BIN" "$@"

benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    mkdir -p "{{benchmarks_dir}}"
    REPORT="{{benchmarks_dir}}/report-$(date +%Y%m%d-%H%M%S).md"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    if [[ -n "${UZU_MODEL_PATH:-}" ]]; then
        MODEL="$UZU_MODEL_PATH"
        [[ "$MODEL" == /* ]] || MODEL="$PWD/$MODEL"
    else
        MODEL="$PWD/{{models_dir}}/{{model_folder}}"
    fi
    TOK="$MODEL/tokenizer.json"
    [[ -f "$TOK" ]] || { echo "Missing $TOK — run: just download"; exit 1; }

    echo "# Uzu benchmark" >"$REPORT"
    echo "Date: $(date -Iseconds)" >>"$REPORT"
    echo "Prompt: {{benchmark_prompt}}" >>"$REPORT"
    echo "Max tokens: {{benchmark_tokens}}" >>"$REPORT"
    echo >>"$REPORT"

    echo "Model: $MODEL"
    BENCH_TOKENIZER="$TOK" cargo run --example llm_uzu --release -- --stream \
        "$MODEL" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1 | tee "$TMP/out.txt" || true

    to_sec() { awk '{ if ($0 ~ /ms$/) { sub(/ms$/,""); print ($0+0)/1000; next } sub(/s$/,""); print ($0+0) }'; }
    count_tok() { printf '%s' "$1" | cargo run --example count_tokens --release -- "$TOK" - 2>/dev/null || echo 0; }

    GEN=$(awk '/Generating \(max/{n=NR+2} NR>=n' "$TMP/out.txt" 2>/dev/null)
    N=$(grep -oE '\[bench\] generated [0-9]+ tokens' "$TMP/out.txt" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    MS=$(grep -oE '\[bench\] generated [0-9]+ tokens in [0-9.]+(ms|s)' "$TMP/out.txt" 2>/dev/null | head -1 | grep -oE '[0-9.]+(ms|s)' | head -1)
    if [[ -z "$MS" ]]; then
        MS=$(grep -oE '\[bench\] completed in [0-9.]+(ms|s)' "$TMP/out.txt" 2>/dev/null | head -1 | grep -oE '[0-9.]+(ms|s)' | head -1)
        N=$(count_tok "$GEN")
    fi
    SEC=$(to_sec <<<"$MS")
    TPS=$(awk -v n="$N" -v s="$SEC" 'BEGIN { if (s>0 && n>0) printf "%.1f", n/s }')

    echo "## Summary" >>"$REPORT"
    echo >>"$REPORT"
    echo "_Tokenizer: \`$TOK\`_" >>"$REPORT"
    echo >>"$REPORT"
    echo "| Gen time | Tokens | Tok/s |" >>"$REPORT"
    echo "|----------|--------|-------|" >>"$REPORT"
    echo "| ${MS:--} | ${N:--} | ${TPS:--} |" >>"$REPORT"
    echo >>"$REPORT"
    echo "Wrote $REPORT"
