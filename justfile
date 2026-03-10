# tish-mlx-burn justfile
# Run: just --list

# Default prompt for benchmarks (consistent across runs)
prompt := "Tell me about London in three sentences."
tokens := "64"
benchmark_prompt := "Recite the poem 'The Road Not Taken' by Robert Frost in full."
benchmark_tokens := "256"

# Model paths
models_dir := "models"
safetensors_dir := models_dir + "/Llama-3.2-1B-Instruct"
gguf_dir := models_dir + "/Llama-3.2-1B-Instruct-GGUF"
gguf_file := gguf_dir + "/Llama-3.2-1B-Instruct-Q8_0.gguf"
lalamo_dir := "lalamo"
uzu_model_dir := lalamo_dir + "/models"
burn_lm_dir := "burn-lm"
burn_lm_bin := burn_lm_dir + "/target/release/burn-lm-cli"
benchmarks_dir := "benchmarks"
tokenizer_json := gguf_dir + "/tokenizer.json"

# One-shot: ensure models + conversion + burn-lm, then run benchmarks
run:
    #!/usr/bin/env bash
    set -e
    NEED_DOWNLOAD=false
    [ ! -f {{safetensors_dir}}/model.safetensors ] && [ ! -f {{safetensors_dir}}/model-00001-of-00001.safetensors ] && NEED_DOWNLOAD=true
    [ ! -f {{gguf_file}} ] && NEED_DOWNLOAD=true
    if [ "$NEED_DOWNLOAD" = true ]; then
        echo "Models missing, running download..."
        just download
    else
        echo "Models present."
    fi
    UZU_PATH=$(ls -d {{uzu_model_dir}}/Llama-3.2-1B-Instruct* {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct* 2>/dev/null | head -1)
    if [ -z "$UZU_PATH" ]; then
        echo "Uzu conversion missing, running convert-uzu..."
        just convert-uzu
    else
        echo "Uzu model present."
    fi
    if [ ! -f {{burn_lm_bin}} ]; then
        echo "Burn-LM missing, running build-burn-lm..."
        just build-burn-lm
    else
        echo "Burn-LM present."
    fi
    echo "Ensuring Burn-LM model downloaded..."
    just download-burn-lm
    echo "Running benchmarks..."
    just benchmark

# Download all models needed for LLM text generation (ungated sources)
download:
    #!/usr/bin/env bash
    set -e
    mkdir -p {{models_dir}}
    echo "Downloading models..."
    # Safetensors for Burn-MLX (ungated)
    if [ ! -f {{safetensors_dir}}/model.safetensors ] && [ ! -f {{safetensors_dir}}/model-00001-of-00001.safetensors ]; then
        echo "Downloading mlx-community/Llama-3.2-1B-Instruct-MLXTuned (safetensors)..."
        hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned --local-dir {{safetensors_dir}}
    else
        echo "Safetensors already at {{safetensors_dir}}"
    fi
    # GGUF Q8_0 for Candle
    if [ ! -f {{gguf_file}} ]; then
        echo "Downloading Llama-3.2-1B-Instruct-Q8_0.gguf..."
        mkdir -p {{gguf_dir}}
        hf download lmstudio-community/Llama-3.2-1B-Instruct-GGUF \
            Llama-3.2-1B-Instruct-Q8_0.gguf --local-dir {{gguf_dir}}
        # Tokenizer for Candle (ungated)
        if [ ! -f {{gguf_dir}}/tokenizer.json ]; then
            hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned tokenizer.json --local-dir {{gguf_dir}}
        fi
    else
        echo "GGUF already at {{gguf_file}}"
    fi
    echo "Done. Models in {{models_dir}}/"

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

# Convert model to Uzu format via lalamo (ungated mlx-community 8bit)
# Uses uvx to run published lalamo; avoids dev deps (cartesia-metal) that fail to build
convert-uzu:
    #!/usr/bin/env bash
    set -e
    mkdir -p {{lalamo_dir}}
    echo "Converting mlx-community/Llama-3.2-1B-Instruct-8bit to Uzu format..."
    cd {{lalamo_dir}} && uvx lalamo convert mlx-community/Llama-3.2-1B-Instruct-8bit
    echo "Done. Uzu model in {{uzu_model_dir}}/"

# Run Candle LLM example (full text generation)
candle *ARGS:
    cargo run --example llm_candle --features candle --release -- \
        --model {{gguf_file}} \
        --prompt "{{prompt}}" \
        -n {{tokens}} \
        {{ARGS}}

# Run Uzu LLM example (full text generation)
uzu *ARGS:
    #!/usr/bin/env bash
    set -e
    MODEL_PATH=$(ls -d {{uzu_model_dir}}/Llama-3.2-1B-Instruct* {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct* 2>/dev/null | head -1)
    if [ -z "$MODEL_PATH" ]; then
        echo "Uzu model not found. Run: just convert-uzu"
        exit 1
    fi
    cargo run --example llm_uzu --features uzu --release -- \
        "$MODEL_PATH" "{{prompt}}" {{tokens}} "$@"

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
burn-mlx *ARGS:
    cargo run --example llm_burn_mlx --features burn-mlx --release -- \
        {{safetensors_dir}}/model.safetensors \
        {{ARGS}}

# Run all 3 LLM examples and record benchmarks
benchmark:
    #!/usr/bin/env bash
    set -e
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

    if [ ! -f {{tokenizer_json}} ]; then
        echo "Tokenizer not found at {{tokenizer_json}}. Run 'just download' first."
        exit 1
    fi
    echo "Running Candle..."
    CANDLE_OUT="$TMPD/candle.txt"
    cargo run --example llm_candle --features candle --release -- \
        --model {{gguf_file}} --prompt "{{benchmark_prompt}}" -n {{benchmark_tokens}} 2>&1 | tee "$CANDLE_OUT" || true

    echo "Running Uzu..."
    UZU_OUT="$TMPD/uzu.txt"
    MODEL_PATH=$(ls -d {{uzu_model_dir}}/Llama-3.2-1B-Instruct* {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct* 2>/dev/null | head -1)
    if [ -n "$MODEL_PATH" ]; then
        cargo run --example llm_uzu --features uzu --release -- \
            "$MODEL_PATH" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1 | tee "$UZU_OUT" || true
    else
        echo "Uzu model not found. Run: just convert-uzu" | tee "$UZU_OUT"
    fi

    echo "Running Burn-LM (Metal)..."
    BURN_OUT="$TMPD/burn.txt"
    if [ -f {{burn_lm_bin}} ]; then
        TERM=dumb ./{{burn_lm_bin}} run llama32 "{{benchmark_prompt}}" --sample-len {{benchmark_tokens}} --no-stats 2>&1 \
            | sed $'s/\033\\[[0-9;]*[a-zA-Z]//g' | tee "$BURN_OUT" || true
    else
        echo "Burn-LM not built. Run: just build-burn-lm" | tee "$BURN_OUT"
    fi

    # Extract generated text and count tokens (same tokenizer for all → comparable tok/s)
    TOKENIZER="{{tokenizer_json}}"
    PROMPT="{{benchmark_prompt}}"

    # Candle: last line of stdout is prompt+generated (strip prompt)
    CANDLE_FULL=$(grep -v "Loading model" "$CANDLE_OUT" | grep -v "Model loaded" | grep -v "^\[bench\]" | tail -1)
    CANDLE_GEN="${CANDLE_FULL#$PROMPT}"
    # Uzu: generated text is after "Generating..." and a blank line
    UZU_GEN=$(awk '/Generating \(max/{n=NR+2} NR>=n' "$UZU_OUT" 2>/dev/null)
    # Burn-LM: "The answer is: \"...\""
    BURN_GEN=$(grep "The answer is:" "$BURN_OUT" 2>/dev/null | sed -n 's/.*The answer is: "\(.*\)".*/\1/p')

    count_tok() { printf '%s' "$1" | cargo run --example count_tokens --features candle --release -- "$TOKENIZER" - 2>/dev/null || echo "0"; }
    to_sec() { echo "$1" | awk '{if(/ms/){gsub(/ms/,""); print $0/1000}else{gsub(/s/,""); print $0+0}}'; }

    C_TOK_N=$(count_tok "$CANDLE_GEN")
    U_TOK_N=$(count_tok "$UZU_GEN")
    B_TOK_N=$(count_tok "$BURN_GEN")

    # Parse times and compute tok/s
    C_TIME=$(grep -oE '\[bench\] generated [0-9]+ tokens in [0-9.]+(ms|s)' "$CANDLE_OUT" 2>/dev/null | grep -oE '[0-9.]+(ms|s)' | head -1)
    U_MS=$(grep -oE '\[bench\] completed in [0-9.]+(ms|s)' "$UZU_OUT" 2>/dev/null | grep -oE '[0-9.]+(ms|s)')
    B_LOAD=$(grep -oE 'model loaded! \([0-9.]+s\)' "$BURN_OUT" 2>/dev/null | grep -oE '[0-9.]+s')
    B_ANSWER=$(grep -oE 'answer generated! \([0-9.]+s\)' "$BURN_OUT" 2>/dev/null | grep -oE '[0-9.]+s')

    C_SEC=$(to_sec "$C_TIME")
    U_SEC=$(to_sec "$U_MS")
    B_SEC=$(to_sec "$B_ANSWER")

    C_TOKS=$(awk -v n="$C_TOK_N" -v s="$C_SEC" 'BEGIN {if(s>0 && n>0) printf "%.1f", n/s}' 2>/dev/null || echo "")
    U_TOKS=$(awk -v n="$U_TOK_N" -v s="$U_SEC" 'BEGIN {if(s>0 && n>0) printf "%.1f", n/s}' 2>/dev/null || echo "")
    B_TOKS=$(awk -v n="$B_TOK_N" -v s="$B_SEC" 'BEGIN {if(s>0 && n>0) printf "%.1f", n/s}' 2>/dev/null || echo "")

    echo "## Summary" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "| Backend | Load | Answer | Tok/s |" >> "$REPORT"
    echo "|---------|------|--------|-------|" >> "$REPORT"
    echo "| Candle | - | ${C_TIME:--} | ${C_TOKS:--} |" >> "$REPORT"
    echo "| Uzu | - | ${U_MS:--} | ${U_TOKS:--} |" >> "$REPORT"
    echo "| Burn-LM | ${B_LOAD:--} | ${B_ANSWER:--} | ${B_TOKS:--} |" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "Benchmark report: $REPORT"
