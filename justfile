# `just`          — compile + run llm-uzu-tish (streaming, default model/prompt).
# `just download` — fetch the model bundle.
# `just benchmark`— compile + run benchmark-tish, write a timing report.

default:
    @just run

models_dir    := "models"
model_folder  := "Llama-3.2-1B-Instruct-8bit"
benchmarks_dir := "benchmarks"
tish_manifest := "../tish/Cargo.toml"

llm_bin   := "examples/llm-uzu-tish/dist/llm-uzu-tish"
tok_bin   := "examples/count-tokens-tish/dist/count-tokens-tish"
bench_bin := "examples/benchmark-tish/dist/benchmark-tish"

_tish_compile src out:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    mkdir -p "$(dirname "{{out}}")"
    cargo run --manifest-path "{{tish_manifest}}" -q -p tishlang -- \
        compile --target native --native-backend rust "{{src}}" -o "{{out}}"

# Fetch model bundle (defaults in scripts/download-uzu-registry-model.tish).
download:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    "${TISH:-tish}" run scripts/download-uzu-registry-model.tish --backend vm

download-uzu:
    @just download

# Compile all Tish examples.
build-tish:
    @just _tish_compile examples/llm-uzu-tish/src/main.tish     "{{llm_bin}}"
    @just _tish_compile examples/count-tokens-tish/src/main.tish "{{tok_bin}}"
    @just _tish_compile examples/benchmark-tish/src/main.tish   "{{bench_bin}}"

# Compile + run the streaming LLM example.
run:
    @just _tish_compile examples/llm-uzu-tish/src/main.tish "{{llm_bin}}"
    cd "{{justfile_directory()}}" && "{{llm_bin}}"

uzu:
    @just run

# Compile + run the token-counting example.
tish-count-tokens:
    @just _tish_compile examples/count-tokens-tish/src/main.tish "{{tok_bin}}"
    cd "{{justfile_directory()}}" && "{{tok_bin}}"

# Compile + run the benchmark example, write a timing report.
benchmark:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{justfile_directory()}}"
    just _tish_compile examples/benchmark-tish/src/main.tish "{{bench_bin}}"
    mkdir -p "{{benchmarks_dir}}"
    REPORT="{{benchmarks_dir}}/report-$(date +%Y%m%d-%H%M%S).md"
    TMP=$(mktemp -d)
    trap 'rm -rf "$TMP"' EXIT

    "{{bench_bin}}" >"$TMP/out.txt" 2>"$TMP/err.txt" || true

    if [[ -s "$TMP/err.txt" ]]; then
        echo "--- stderr ---" >&2; cat "$TMP/err.txt" >&2; echo "---" >&2
    fi

    BENCH_LINE=$(head -1 "$TMP/out.txt")
    ELAPSED_MS=$(echo "$BENCH_LINE" | grep -oE 'elapsed_ms=[0-9]+' | cut -d= -f2)
    N=$(echo "$BENCH_LINE" | grep -oE 'tokens=[0-9]+' | cut -d= -f2)
    tail -n +2 "$TMP/out.txt"

    if [[ -z "${ELAPSED_MS:-}" || -z "${N:-}" ]]; then
        echo "Warning: missing bench data — check stderr above"; ELAPSED_MS=0; N=0
    fi
    SEC=$(awk -v ms="${ELAPSED_MS}" 'BEGIN { printf "%.3f", ms/1000 }')
    TPS=$(awk -v n="${N}" -v s="${SEC}" 'BEGIN { if (s+0>0 && n+0>0) printf "%.1f", n/s; else print "-" }')

    { echo "# Uzu benchmark"
      echo "Date: $(date -Iseconds)"
      echo "Model: {{models_dir}}/{{model_folder}}"
      echo ""
      echo "## Summary"
      echo ""
      echo "| Gen time | Tokens | Tok/s |"
      echo "|----------|--------|-------|"
      echo "| ${SEC}s | ${N} | ${TPS} |"
    } >"$REPORT"

    echo "Gen time: ${SEC}s | Tokens: ${N} | Tok/s: ${TPS}"
    echo "Wrote $REPORT"
