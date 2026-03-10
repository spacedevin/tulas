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
benchmarks_dir := "benchmarks"

# One-shot: ensure models + conversion, then run benchmarks
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
    UZU_PATH=$(ls -d {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct 2>/dev/null | head -1)
    if [ -z "$UZU_PATH" ]; then
        echo "Uzu conversion missing, running convert-uzu..."
        just convert-uzu
    else
        echo "Uzu model present."
    fi
    echo "Running benchmarks..."
    just benchmark

# Download all models needed for LLM text generation
download:
    #!/usr/bin/env bash
    set -e
    mkdir -p {{models_dir}}
    echo "Downloading models..."
    # Safetensors for Burn-MLX (and base for Uzu conversion)
    if [ ! -f {{safetensors_dir}}/model.safetensors ] && [ ! -f {{safetensors_dir}}/model-00001-of-00001.safetensors ]; then
        echo "Downloading meta-llama/Llama-3.2-1B-Instruct (safetensors)..."
        huggingface-cli download meta-llama/Llama-3.2-1B-Instruct --local-dir {{safetensors_dir}}
    else
        echo "Safetensors already at {{safetensors_dir}}"
    fi
    # GGUF Q8_0 for Candle
    if [ ! -f {{gguf_file}} ]; then
        echo "Downloading Llama-3.2-1B-Instruct-Q8_0.gguf..."
        mkdir -p {{gguf_dir}}
        huggingface-cli download lmstudio-community/Llama-3.2-1B-Instruct-GGUF \
            Llama-3.2-1B-Instruct-Q8_0.gguf --local-dir {{gguf_dir}}
        # Tokenizer for Candle (from meta-llama)
        if [ ! -f {{gguf_dir}}/tokenizer.json ]; then
            huggingface-cli download meta-llama/Llama-3.2-1B-Instruct tokenizer.json --local-dir {{gguf_dir}}
        fi
    else
        echo "GGUF already at {{gguf_file}}"
    fi
    echo "Done. Models in {{models_dir}}/"

# Convert meta-llama model to Uzu format (requires lalamo)
convert-uzu:
    #!/usr/bin/env bash
    set -e
    if [ ! -d {{lalamo_dir}} ]; then
        echo "Cloning lalamo..."
        git clone https://github.com/trymirai/lalamo.git {{lalamo_dir}}
        cd {{lalamo_dir}} && git checkout v0.6.0 2>/dev/null || true
    fi
    echo "Converting meta-llama/Llama-3.2-1B-Instruct to Uzu format..."
    cd {{lalamo_dir}} && uv run lalamo convert meta-llama/Llama-3.2-1B-Instruct
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
    MODEL_PATH=$(ls -d {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct 2>/dev/null | head -1)
    if [ -z "$MODEL_PATH" ]; then
        echo "Uzu model not found. Run: just convert-uzu"
        exit 1
    fi
    cargo run --example llm_uzu --features uzu --release -- \
        "$MODEL_PATH" "{{prompt}}" {{tokens}} "$@"

# Run Burn-MLX example (safetensors load + tensor demo; no full text generation)
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
    MODEL_PATH=$(ls -d {{uzu_model_dir}}/*/Llama-3.2-1B-Instruct 2>/dev/null | head -1)
    if [ -n "$MODEL_PATH" ]; then
        { cargo run --example llm_uzu --features uzu --release -- \
            "$MODEL_PATH" "{{benchmark_prompt}}" {{benchmark_tokens}} 2>&1; } \
            | tee -a "$REPORT" || true
    else
        echo "Uzu model not found. Run: just convert-uzu" | tee -a "$REPORT"
    fi
    echo '```' >> "$REPORT"
    echo "" >> "$REPORT"

    echo "Running Burn-MLX..."
    echo "### Burn-MLX (safetensors load + tensor; no text generation)" >> "$REPORT"
    echo '```' >> "$REPORT"
    { cargo run --example llm_burn_mlx --features burn-mlx --release -- \
        {{safetensors_dir}}/model.safetensors 2>&1; } \
        | tee -a "$REPORT" || true
    echo '```' >> "$REPORT"

    echo ""
    echo "Benchmark report: $REPORT"
