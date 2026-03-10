# tish-mlx-burn justfile
# Run: just --list

# Default prompt for benchmarks (consistent across runs)
prompt := "Tell me about London in three sentences."
tokens := "64"
benchmark_prompt := "The quick brown fox"
benchmark_tokens := "32"

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
    echo "# LLM Benchmark Report" > "$REPORT"
    echo "Date: $(date -Iseconds)" >> "$REPORT"
    echo "Prompt: {{benchmark_prompt}}" >> "$REPORT"
    echo "Max tokens: {{benchmark_tokens}}" >> "$REPORT"
    echo "" >> "$REPORT"
    echo "## Results" >> "$REPORT"
    echo "" >> "$REPORT"

    echo "Running Candle..."
    echo "### Candle" >> "$REPORT"
    echo '```' >> "$REPORT"
    { cargo run --example llm_candle --features candle --release -- \
        --model {{gguf_file}} --prompt "{{benchmark_prompt}}" -n {{benchmark_tokens}} 2>&1; } \
        | tee -a "$REPORT" || true
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"

    echo "Running Uzu..."
    echo "### Uzu" >> "$REPORT"
    echo '```' >> "$REPORT"
    MODEL_PATH=$(ls -d {{uzu_model_dir}}/Llama-3.2-1B-Instruct* {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct* 2>/dev/null | head -1)
    if [ -n "$MODEL_PATH" ]; then
        { cargo run --example llm_uzu --features uzu --release -- \
            "$MODEL_PATH" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1; } \
            | tee -a "$REPORT" || true
    else
        echo "Uzu model not found. Run: just convert-uzu" | tee -a "$REPORT"
    fi
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"

    echo "Running Burn-LM (Metal)..."
    echo "### Burn-LM (Metal)" >> "$REPORT"
    echo '```' >> "$REPORT"
    if [ -f {{burn_lm_bin}} ]; then
        { ./{{burn_lm_bin}} run llama32 "{{benchmark_prompt}}" --sample-len {{benchmark_tokens}} --no-stats 2>&1; } \
            | tee -a "$REPORT" || true
    else
        echo "Burn-LM not built. Run: just build-burn-lm" | tee -a "$REPORT"
    fi
    echo '```' >> "$REPORT"

    echo ""
    echo "Benchmark report: $REPORT"
