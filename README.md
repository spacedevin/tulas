# tish-mlx-burn

Local LLM inference on Apple Silicon using **Burn** (burn-lm Metal), **Uzu**, and **Candle**. Uzu focuses on MLX models with **no conversion** – models are already MLX on HuggingFace.

## Model and format equivalents

| Runtime | Format     | Source | Notes |
|---------|------------|--------|-------|
| **Candle** | GGUF Q8_0 | [lmstudio-community/Llama-3.2-1B-Instruct-GGUF](https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF) | Ungated |
| **Burn** | Burn pretrained | [burn-lm](https://github.com/tracel-ai/burn-lm) downloads meta-llama/Llama-3.2-1B-Instruct | **Gated** – requires HF approval |
| **Uzu** | MLX | [mlx-community](https://huggingface.co/mlx-community) | Pass model path |

**Note:** burn-mlx has no LLM inference support. Burn uses [burn-lm](https://github.com/tracel-ai/burn-lm) with Metal backend for full text generation.

## Examples

### basic_mlx (no model)

Minimal Burn-MLX tensor demo:

```bash
cargo run --example basic_mlx --features burn-mlx
```

### Candle (GGUF Q8_0)

Uses [Candle](https://github.com/huggingface/candle) with Metal on Apple Silicon.

```bash
# Download model (Q8_0, ~1.32 GB)
# From https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF

cargo run --example llm_candle --features candle --release -- \
  --model ./Llama-3.2-1B-Instruct-Q8_0.gguf \
  --prompt "Tell me about London" \
  -n 64
```

The tokenizer is downloaded from `mlx-community/Llama-3.2-1B-Instruct-MLXTuned` and placed next to the GGUF file by `just download`.

### Burn (Metal) – full LLM inference

Uses [burn-lm](https://github.com/tracel-ai/burn-lm) with Burn's Metal backend (Apple Silicon GPU).

```bash
just build-burn-lm     # Build (one-time)
just download-burn-lm  # Download model (gated; requires HF approval + login)
just burn-lm           # Run Llama 3.2 1B inference
```

`download-burn-lm` fetches `meta-llama/Llama-3.2-1B-Instruct` (**gated**; requires [Hugging Face approval](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct) and `huggingface-cli login`).

### Burn-MLX (tensor demo only)

Optional: loads safetensors and runs tensor ops (no LLM generation). burn-mlx has no LLM support.

```bash
cargo run --example llm_burn_mlx --features burn-mlx --release -- \
  ./models/Llama-3.2-1B-Instruct/model.safetensors
```

### Uzu

Uses [Uzu](https://github.com/trymirai/uzu). Pass a model directory:

```bash
just uzu ./lalamo/models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

Or with cargo:

```bash
cargo run --example llm_uzu --features uzu --release -- \
  ./lalamo/models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

**Note:** Uzu requires **Rust 1.93+**. Run `rustup update` if the build fails.

## Justfile

[just](https://github.com/casey/just) recipes for common tasks:

```bash
just run                  # One-shot: download, build burn-lm, run benchmarks
just download             # Download models (safetensors, GGUF)
just build-burn-lm        # Build burn-lm with Metal
just download-burn-lm     # Download burn-lm model (gated)
just candle               # Run Candle example
just uzu [path] [prompt] [tokens]  # Run Uzu
just burn-lm              # Run Burn-LM (Metal) for full LLM inference
just burn-mlx             # Run Burn-MLX tensor demo (no LLM)
just benchmark            # Run all 3 LLM backends and save report
just benchmark-uzu        # Uzu benchmark
```

## Requirements

- **macOS** on Apple Silicon (M1/M2/M3/M4)
- **Xcode** and Metal toolchain for Burn-MLX and Uzu
- **Rust** 1.75+ (1.93+ for Uzu)

## License

MIT OR Apache-2.0
