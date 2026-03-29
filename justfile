# Uzu + Mirai registry bundles. `just` → list recipes.

default:
    @just --list

models_dir := "models"
model_folder := "Llama-3.2-1B-Instruct-8bit"
registry_repo := "mlx-community/Llama-3.2-1B-Instruct-8bit"
benchmarks_dir := "benchmarks"

prompt := "Tell me about London in three sentences."
tokens := "64"
benchmark_prompt := "Recite the poem 'The Road Not Taken' by Robert Frost in full."
benchmark_tokens := "256"

download-uzu:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    mkdir -p "{{models_dir}}"
    DEST="{{models_dir}}/{{model_folder}}"
    REPO="${UZU_REGISTRY_REPO_ID:-{{registry_repo}}}"
    python3 scripts/download-uzu-registry-model.py "$REPO" "$DEST"
    echo "Model directory: $DEST"

build:
    cargo build --release

uzu *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    if [[ -n "${1:-}" && -d "$1" ]]; then
        MODEL=$1; shift
        P="${1:-{{prompt}}}"; T="${2:-{{tokens}}}"
    else
        MODEL="$(bash scripts/resolve-uzu-model-path.sh)"
        P="${1:-{{prompt}}}"; T="${2:-{{tokens}}}"
    fi
    [[ -d "$MODEL" ]] || { echo "No bundle at $MODEL — run just download-uzu"; exit 1; }
    cargo run --example llm_uzu --release -- --stream "$MODEL" "$P" "$T"

benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{ justfile_directory() }}"
    mkdir -p "{{benchmarks_dir}}"
    REPORT="{{benchmarks_dir}}/report-$(date +%Y%m%d-%H%M%S).md"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    MODEL="$(bash scripts/resolve-uzu-model-path.sh)"
    TOK="$MODEL/tokenizer.json"
    [[ -f "$TOK" ]] || { echo "Missing $TOK — run just download-uzu"; exit 1; }

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
