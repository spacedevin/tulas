# tish-mlx-burn justfile
# Run: just --list

# Default prompt for benchmarks (consistent across runs)
prompt := "Tell me about London in three sentences."
tokens := "64"
benchmark_prompt := "Recite the poem 'The Road Not Taken' by Robert Frost in full."
benchmark_tokens := "256"

# Model paths — ONLY mlx-community/Llama-3.2-1B-Instruct-MLXTuned is downloaded by `just download`.
#
#   safetensors_dir  ← full HF tree: hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned
#   tokenizer_json   ← always inside that tree (never another model directory)
#
# Uzu: **pre-built bundles** from the Mirai registry ([same listing](https://trymirai.com/local-models/mlx-community-llama-3-2-1b-instruct-8bit) / [HF id](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-8bit)), via `just download-uzu` → `models/<uzu_model_folder>/`. Not raw `hf download` (wrong config).
# Resolver: `scripts/resolve-uzu-model-path.sh` — `UZU_MODEL_PATH`, or `UZU_MODEL_DIR` + `UZU_MODEL_BUNDLE`, else `models/<uzu_model_folder>` then optional `lalamo/_models/...`.
#
# Optional elsewhere: `just candle` needs a GGUF you supply yourself; `just burn-lm` uses burn-lm’s
# own (meta-llama) download — neither is invoked by `just run` / `just benchmark`.
models_dir := "models"
safetensors_dir := models_dir + "/Llama-3.2-1B-Instruct-MLXTuned"
uzu_model_dir := env_var_or_default("UZU_MODEL_DIR", models_dir)
uzu_model_folder := "Llama-3.2-1B-Instruct-8bit"
# Mirai registry repoId (pre-exported Uzu weights on CDN), not `hf download` of the HF tree
uzu_registry_repo_id := "mlx-community/Llama-3.2-1B-Instruct-8bit"
uzu_model_bundle := env_var_or_default("UZU_MODEL_BUNDLE", uzu_model_folder)
uzu_model_path := uzu_model_dir + "/" + uzu_model_bundle

burn_lm_dir := "burn-lm"
burn_lm_bin := burn_lm_dir + "/target/release/burn-lm-cli"
benchmarks_dir := "benchmarks"
tokenizer_json := safetensors_dir + "/tokenizer.json"

# One-shot: MLXTuned download + Uzu benchmark (no lmstudio GGUF, no burn-lm)
run:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    NEED_DOWNLOAD=false
    [ ! -f {{safetensors_dir}}/model.safetensors ] && [ ! -f {{safetensors_dir}}/model-00001-of-00001.safetensors ] && NEED_DOWNLOAD=true
    [ ! -f {{tokenizer_json}} ] && NEED_DOWNLOAD=true
    if [ "$NEED_DOWNLOAD" = true ]; then
        echo "MLXTuned model missing, running download..."
        just download
    else
        echo "MLXTuned model present."
    fi
    UZU_PATH="$(bash scripts/resolve-uzu-model-path.sh)"
    if [ -n "$UZU_PATH" ] && [ -d "$UZU_PATH" ]; then
        echo "Uzu model present ($UZU_PATH)."
    else
        echo "Uzu: missing directory: $UZU_PATH"
        echo "  Run: just download-uzu  (Mirai registry → models/{{uzu_model_folder}}/) or set UZU_MODEL_PATH."
        p="$(dirname "$UZU_PATH")"
        if [ -d "$p" ]; then echo "  Subdirs of $p:"; ls -1 "$p" 2>/dev/null | sed 's/^/    /' || true; fi
    fi
    echo "Running benchmarks..."
    just benchmark

# Download ONLY mlx-community/Llama-3.2-1B-Instruct-MLXTuned (no lmstudio, no meta-llama)
download:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    mkdir -p {{models_dir}}
    echo "Downloading mlx-community/Llama-3.2-1B-Instruct-MLXTuned only..."
    if [ -d "{{models_dir}}/Llama-3.2-1B-Instruct" ] && [ ! -f "{{safetensors_dir}}/model.safetensors" ] && [ ! -f "{{safetensors_dir}}/model-00001-of-00001.safetensors" ]; then
        echo "WARNING: Legacy models/Llama-3.2-1B-Instruct/ exists. If that is MLXTuned data, run:"
        echo "  mv \"{{models_dir}}/Llama-3.2-1B-Instruct\" \"{{safetensors_dir}}\""
    fi
    if [ ! -f {{safetensors_dir}}/model.safetensors ] && [ ! -f {{safetensors_dir}}/model-00001-of-00001.safetensors ]; then
        hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned --local-dir {{safetensors_dir}}
    else
        echo "Weights already at {{safetensors_dir}}"
    fi
    if [ ! -f "{{tokenizer_json}}" ]; then
        echo "Fetching tokenizer.json into {{safetensors_dir}} (same MLXTuned repo only)..."
        mkdir -p {{safetensors_dir}}
        hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned tokenizer.json --local-dir {{safetensors_dir}}
    fi
    echo "Done. MLXTuned tree: {{safetensors_dir}}/"

# Pre-built Uzu bundle from Mirai CDN (registry API; matches trymirai/uzu tools/helpers download-model).
download-uzu:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    mkdir -p {{models_dir}}
    DEST="{{models_dir}}/{{uzu_model_folder}}"
    REPO="${UZU_REGISTRY_REPO_ID:-{{uzu_registry_repo_id}}}"
    echo "Downloading registry model $REPO into $DEST ..."
    python3 scripts/download-uzu-registry-model.py "$REPO" "$DEST"
    echo "Done. Uzu path: $DEST/"

# Download burn-lm Llama 3.2 1B model (meta-llama, gated; requires HF approval)
download-burn-lm:
    ./{{burn_lm_bin}} download llama32

# Build burn-lm CLI with Metal backend (full LLM inference via Burn)
# burn-mlx has no LLM support; burn-lm uses Burn's Metal backend on Apple Silicon
build-burn-lm:
    #!/usr/bin/env bash
    set -e
    if [ ! -d {{burn_lm_dir}} ]; then
        echo "Cloning burn-lm..."
        git clone --depth 1 https://github.com/tracel-ai/burn-lm.git {{burn_lm_dir}}
    fi
    echo "Building burn-lm-cli with metal..."
    cd {{burn_lm_dir}} && cargo build -p burn-lm-cli --features metal --release
    echo "Done. Run: just burn-lm"
    echo "Note: First run downloads meta-llama/Llama-3.2-1B-Instruct (gated; requires HF approval)."

# Candle (optional): pass --model /path/to/your.gguf; tokenizer from MLXTuned tree only
candle *ARGS:
    cargo run --example llm_candle --features candle --release -- \
        --tokenizer "{{tokenizer_json}}" \
        --prompt "{{prompt}}" \
        -n {{tokens}} \
        {{ARGS}}

# Run Uzu LLM example (default path = uzu_model_path in this file)
# Usage: just uzu [MODEL_PATH] [PROMPT] [TOKENS]  — if $1 is a directory, it is the model; else default model + $1 as prompt
uzu *ARGS:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    if [ -n "${1:-}" ] && [ -d "$1" ]; then
        MODEL_PATH="$1"
        shift
        PROMPT="${1:-{{prompt}}}"
        TOKENS="${2:-{{tokens}}}"
    else
        MODEL_PATH="$(bash scripts/resolve-uzu-model-path.sh)"
        PROMPT="${1:-{{prompt}}}"
        TOKENS="${2:-{{tokens}}}"
    fi
    if [ ! -d "$MODEL_PATH" ]; then
        echo "No Uzu bundle at: $MODEL_PATH — run just download-uzu or set UZU_MODEL_PATH"
        exit 1
    fi
    cargo run --example llm_uzu --features uzu --release -- --stream \
        "$MODEL_PATH" "$PROMPT" "$TOKENS"

# Run Burn-LM (Metal) for full LLM inference
# burn-mlx has no LLM; burn-lm uses Burn's Metal backend
burn-lm *ARGS:
    #!/usr/bin/env bash
    set -e
    if [ ! -f {{burn_lm_bin}} ]; then
        echo "Burn-LM not built. Run: just build-burn-lm"
        exit 1
    fi
    ./{{burn_lm_bin}} run llama32 "{{prompt}}" --sample-len {{tokens}} --no-stats "$@"

# Run Burn-MLX tensor demo (no LLM; kept for burn-mlx pipeline demo)
# MLXTuned is often sharded: prefer model.safetensors, else first shard (same as `just download` checks).
burn-mlx *ARGS:
    #!/usr/bin/env bash
    set -e
    ST="{{safetensors_dir}}"
    MODEL=""
    if [ -f "$ST/model.safetensors" ]; then
        MODEL="$ST/model.safetensors"
    elif [ -f "$ST/model-00001-of-00001.safetensors" ]; then
        MODEL="$ST/model-00001-of-00001.safetensors"
    else
        echo "No safetensors in $ST (expected MLXTuned tree). Run: just download"
        echo "If weights are still under models/Llama-3.2-1B-Instruct/, rename that folder to: $ST"
        exit 1
    fi
    cargo run --example llm_burn_mlx --features burn-mlx --release -- \
        "$MODEL" \
        {{ARGS}}

# Uzu benchmark (tokenizer: model dir if present, else MLXTuned)
benchmark:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    mkdir -p {{benchmarks_dir}}
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORT="{{benchmarks_dir}}/report-${TIMESTAMP}.md"
    TMPD=$(mktemp -d)
    trap "rm -rf $TMPD" EXIT

    echo "# LLM Benchmark Report" > "$REPORT"
    echo "Date: $(date -Iseconds)" >> "$REPORT"
    echo "Prompt: {{benchmark_prompt}}" >> "$REPORT"
    echo "Max tokens: {{benchmark_tokens}}" >> "$REPORT"
    echo "" >> "$REPORT"

    MODEL_PATH="$(bash scripts/resolve-uzu-model-path.sh)"
    if [ -f "$MODEL_PATH/tokenizer.json" ]; then
        BENCH_TOK="$MODEL_PATH/tokenizer.json"
    elif [ -f "{{tokenizer_json}}" ]; then
        BENCH_TOK="{{tokenizer_json}}"
    else
        echo "No tokenizer: need $MODEL_PATH/tokenizer.json (Uzu bundle) or {{tokenizer_json}} (just download)."
        exit 1
    fi

    echo "Running Uzu at $MODEL_PATH (override with UZU_MODEL_PATH / UZU_MODEL_DIR + UZU_MODEL_BUNDLE)..."
    UZU_OUT="$TMPD/uzu.txt"
    if [ -d "$MODEL_PATH" ]; then
        BENCH_TOKENIZER="$BENCH_TOK" cargo run --example llm_uzu --features uzu --release -- --stream \
            "$MODEL_PATH" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1 | tee "$UZU_OUT" || true
    else
        echo "Uzu: no bundle at $MODEL_PATH — run just download-uzu (Mirai registry) or set UZU_MODEL_PATH." | tee "$UZU_OUT"
    fi

    TOKENIZER="$BENCH_TOK"
    UZU_GEN=$(awk '/Generating \(max/{n=NR+2} NR>=n' "$UZU_OUT" 2>/dev/null)

    count_tok() { printf '%s' "$1" | cargo run --example count_tokens --features candle --release -- "$TOKENIZER" - 2>/dev/null || echo "0"; }
    to_sec() {
        echo "$1" | awk '{
            if ($0 ~ /ms$/) { sub(/ms$/,""); print ($0+0)/1000; next }
            sub(/s$/,""); print ($0+0)
        }'
    }

    U_TOK_N=$(grep -oE '\[bench\] generated [0-9]+ tokens' "$UZU_OUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
    U_MS=$(grep -oE '\[bench\] generated [0-9]+ tokens in [0-9.]+(ms|s)' "$UZU_OUT" 2>/dev/null | head -1 | grep -oE '[0-9.]+(ms|s)' | head -1)
    if [ -z "$U_MS" ]; then
        U_MS=$(grep -oE '\[bench\] completed in [0-9.]+(ms|s)' "$UZU_OUT" 2>/dev/null | grep -oE '[0-9.]+(ms|s)' | head -1)
        U_TOK_N=$(count_tok "$UZU_GEN")
    fi

    U_SEC=$(to_sec "$U_MS")
    U_TOKS=$(awk -v n="$U_TOK_N" -v s="$U_SEC" 'BEGIN {if(s>0 && n>0) printf "%.1f", n/s}' 2>/dev/null || echo "")

    echo "## Summary" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "_Burn-MLX / Candle tokenizer: [mlx-community/Llama-3.2-1B-Instruct-MLXTuned](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-MLXTuned) (\`just download\`). Uzu: pre-built [registry](https://sdk.trymirai.com) bundle (\`just download-uzu\`). Bench tokenizer: \`$TOKENIZER\`._" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "| Backend | Load | Answer | Tok/s |" >> "$REPORT"
    echo "|---------|------|--------|-------|" >> "$REPORT"
    echo "| Uzu | - | ${U_MS:--} | ${U_TOKS:--} |" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "Benchmark report: $REPORT"

# Uzu-only benchmark
benchmark-uzu:
    #!/usr/bin/env bash
    set -e
    cd "{{ justfile_directory() }}"
    mkdir -p {{benchmarks_dir}}
    TIMESTAMP=$(date +%Y%m%d-%H%M%S)
    REPORT="{{benchmarks_dir}}/uzu-report-${TIMESTAMP}.md"
    TMPD=$(mktemp -d)
    trap "rm -rf $TMPD" EXIT

    echo "# Uzu Benchmark Report" > "$REPORT"
    echo "Date: $(date -Iseconds)" >> "$REPORT"
    echo "Prompt: {{benchmark_prompt}}" >> "$REPORT"
    echo "Max tokens: {{benchmark_tokens}}" >> "$REPORT"
    echo "" >> "$REPORT"

    MODEL_PATH="$(bash scripts/resolve-uzu-model-path.sh)"
    if [ -f "$MODEL_PATH/tokenizer.json" ]; then
        BENCH_TOK="$MODEL_PATH/tokenizer.json"
    elif [ -f "{{tokenizer_json}}" ]; then
        BENCH_TOK="{{tokenizer_json}}"
    else
        echo "No tokenizer: need $MODEL_PATH/tokenizer.json or {{tokenizer_json}}."
        exit 1
    fi
    to_sec_uzu() {
        echo "$1" | awk '{
            if ($0 ~ /ms$/) { sub(/ms$/,""); print ($0+0)/1000; next }
            sub(/s$/,""); print ($0+0)
        }'
    }
    if [ -d "$MODEL_PATH" ]; then
        MODEL_ID=$(basename "$MODEL_PATH")
        echo "Running Uzu with $MODEL_ID..."
        OUT="$TMPD/$MODEL_ID.txt"
        BENCH_TOKENIZER="$BENCH_TOK" cargo run --example llm_uzu --features uzu --release -- --stream \
            "$MODEL_PATH" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1 | tee "$OUT" || true
        GEN=$(awk '/Generating \(max/{n=NR+2} NR>=n' "$OUT" 2>/dev/null)
        U_TOK_N=$(grep -oE '\[bench\] generated [0-9]+ tokens' "$OUT" 2>/dev/null | head -1 | grep -oE '[0-9]+' | head -1)
        U_TIME=$(grep -oE '\[bench\] generated [0-9]+ tokens in [0-9.]+(ms|s)' "$OUT" 2>/dev/null | head -1 | grep -oE '[0-9.]+(ms|s)' | head -1)
        if [ -z "$U_TIME" ]; then
            U_TIME=$(grep -oE '\[bench\] completed in [0-9.]+(ms|s)' "$OUT" 2>/dev/null | grep -oE '[0-9.]+(ms|s)' | head -1)
        fi
        if [ -z "$U_TOK_N" ]; then
            U_TOK_N=$(printf '%s' "$GEN" | cargo run --example count_tokens --features candle --release -- "$BENCH_TOK" - 2>/dev/null || echo "0")
        fi
        U_SEC=$(to_sec_uzu "$U_TIME")
        U_TOKS=$(awk -v n="$U_TOK_N" -v s="$U_SEC" 'BEGIN {if(s>0 && n>0) printf "%.1f", n/s}' 2>/dev/null || echo "")
        echo "## $MODEL_ID" >> "$REPORT"
        echo "" >> "$REPORT"
        echo "| Gen time | Tokens | Tok/s |" >> "$REPORT"
        echo "|----------|--------|-------|" >> "$REPORT"
        echo "| ${U_TIME:--} | ${U_TOK_N:--} | ${U_TOKS:--} |" >> "$REPORT"
        echo "" >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "$GEN" >> "$REPORT"
        echo '```' >> "$REPORT"
        echo "" >> "$REPORT"
    else
        echo "## (no model)" >> "$REPORT"
        echo "" >> "$REPORT"
        echo "No Uzu bundle at $MODEL_PATH — run just download-uzu or set UZU_MODEL_PATH." >> "$REPORT"
    fi
    echo "Uzu benchmark report: $REPORT"
