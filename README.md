# tish-mlx-burn

Local LLM inference on Apple Silicon using Burn-MLX, Uzu, and Candle. All examples target **Llama 3.2 1B Instruct** with format-specific sources per runtime.

## Model and format equivalents

| Runtime   | Format               | Source                                                                 | File / path                                        |
|----------|----------------------|-------------------------------------------------------------------------|----------------------------------------------------|
| **Candle**   | GGUF Q8_0           | [lmstudio-community/Llama-3.2-1B-Instruct-GGUF](https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF) | `Llama-3.2-1B-Instruct-Q8_0.gguf` (~1.32 GB)       |
| **Burn-mlx** | Safetensors (fp16)  | [meta-llama/Llama-3.2-1B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)           | `model.safetensors`                                |
| **Uzu**      | Uzu native          | [meta-llama/Llama-3.2-1B-Instruct](https://huggingface.co/meta-llama/Llama-3.2-1B-Instruct)           | Convert via `lalamo convert meta-llama/Llama-3.2-1B-Instruct` |

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

The tokenizer is loaded from the same directory as the model (`tokenizer.json`) or from Hugging Face (`meta-llama/Llama-3.2-1B-Instruct`). For GGUF-only downloads, place `tokenizer.json` next to the model or ensure Hugging Face access.

### Burn-MLX (safetensors)

Loads safetensors and runs on burn-mlx (Apple Silicon GPU).

```bash
# Download model
huggingface-cli download meta-llama/Llama-3.2-1B-Instruct --local-dir ./models/Llama-3.2-1B-Instruct

cargo run --example llm_burn_mlx --features burn-mlx --release -- \
  ./models/Llama-3.2-1B-Instruct/model.safetensors
```

**Note:** Full LLM text generation requires [burn-lm](https://github.com/tracel-ai/burn-lm) with MLX backend. This example shows safetensors loading and the burn-mlx tensor pipeline.

### Uzu (native format)

Uses [Uzu](https://github.com/trymirai/uzu) with its native model format.

**Converting models to Uzu format:**

1. Clone and set up [lalamo](https://github.com/trymirai/lalamo):
   ```bash
   git clone https://github.com/trymirai/lalamo.git && cd lalamo
   uv run lalamo list-models   # list supported models
   uv run lalamo convert meta-llama/Llama-3.2-1B-Instruct
   ```

2. Run the example:
   ```bash
   cargo run --example llm_uzu --features uzu --release -- \
     ./models/v1/Llama-3.2-1B-Instruct \
     "Tell me about London" \
     128
   ```

**Note:** Uzu requires **Rust 1.93+** due to its dependencies. Run `rustup update` if the build fails.

## Justfile

[just](https://github.com/casey/just) recipes for common tasks:

```bash
just run           # One-shot: download if needed, convert if needed, run benchmarks
just download      # Download all models (safetensors, GGUF)
just convert-uzu   # Convert to Uzu format via lalamo
just candle        # Run Candle example
just uzu           # Run Uzu example
just burn-mlx      # Run Burn-MLX example
just benchmark     # Run all 3 and save report to benchmarks/
```

## Requirements

- **macOS** on Apple Silicon (M1/M2/M3/M4)
- **Xcode** and Metal toolchain for Burn-MLX and Uzu
- **Rust** 1.75+ (1.93+ for Uzu)

## License

MIT OR Apache-2.0
