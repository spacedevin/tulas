# tish-mlx-burn

Local LLM inference on Apple Silicon using **Uzu** (MLX), **Burn-MLX** (tensor demo), and optional **Candle** (GGUF you supply) / **burn-lm** (separate gated download).

## Model policy

**`just download` only fetches** [`mlx-community/Llama-3.2-1B-Instruct-MLXTuned`](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-MLXTuned) into `models/Llama-3.2-1B-Instruct-MLXTuned/` (safetensors + tokenizer). Nothing from lmstudio or meta-llama is pulled by that recipe.

| Piece | Source |
|-------|--------|
| **Default weights + tokenizer** | `mlx-community/Llama-3.2-1B-Instruct-MLXTuned` via `just download` |
| **Uzu** | **Pre-built** bundles from the [Mirai registry](https://github.com/trymirai/uzu#models) (same IDs as [HF](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-8bit) / [Mirai library](https://trymirai.com/local-models/mlx-community-llama-3-2-1b-instruct-8bit), but served as Uzu-ready files on Mirai’s CDN). Run **`just download-uzu`** → `models/Llama-3.2-1B-Instruct-8bit/`. Do **not** use plain `hf download` into that folder (old HF `llama` config breaks Uzu — delete the folder and re-run **`just download-uzu`**). Override repo with **`UZU_REGISTRY_REPO_ID`** / path with **`UZU_MODEL_PATH`**. Engine version follows **`uzu` in `Cargo.lock`** (`UZU_ENGINE_VERSION` to override). |
| **Burn-MLX demo** | Same MLXTuned safetensors path as above |
| **Candle** (optional) | You provide a GGUF path; pass `--tokenizer` pointing at `models/...-MLXTuned/tokenizer.json` |
| **burn-lm** (optional) | `just download-burn-lm` — uses burn-lm’s **meta-llama** weights; not part of `just run` |

## Examples

### basic_mlx (no model)

```bash
cargo run --example basic_mlx --features burn-mlx
```

### Uzu

```bash
just download     # MLXTuned (Burn-MLX / Candle tokenizer baseline)
just download-uzu # Mirai registry → models/Llama-3.2-1B-Instruct-8bit/ (pre-exported for Uzu)
just uzu "Tell me about London" 128
# Or pass the bundle path explicitly:
just uzu ./models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

Or with cargo:

```bash
cargo run --example llm_uzu --features uzu --release -- \
  ./models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

**Note:** Uzu requires **Rust 1.93+**. Run `rustup update` if the build fails.

### Burn-MLX (tensor demo only)

```bash
just download
just burn-mlx
```

### Candle (optional GGUF)

Candle is not wired to MLXTuned safetensors. If you have a GGUF file, run with the MLXTuned tokenizer from `just download`:

```bash
just download
just candle -- --model /path/to/your.gguf
```

(`just candle` passes `--tokenizer` to `models/Llama-3.2-1B-Instruct-MLXTuned/tokenizer.json` automatically.)

### Burn (Metal) – full LLM via burn-lm

Uses [burn-lm](https://github.com/tracel-ai/burn-lm) with Burn’s Metal backend. **Not** the MLXTuned Hub repo; separate gated download:

```bash
just build-burn-lm
just download-burn-lm   # meta-llama/Llama-3.2-1B-Instruct — requires HF approval + login
just burn-lm
```

## Justfile

```bash
just run                  # MLXTuned download + Uzu benchmark only
just download             # ONLY mlx-community/...-MLXTuned
just burn-mlx             # Tensor demo using MLXTuned safetensors
just benchmark            # Uzu at uzu_model_path (see justfile)
just benchmark-uzu        # same single model as `just benchmark`
# Overrides: UZU_MODEL_PATH=/abs/path  or  UZU_MODEL_DIR=… UZU_MODEL_BUNDLE=folder
just candle -- --model /path/to/model.gguf   # optional; MLXTuned tokenizer from download
just build-burn-lm        # optional burn-lm
just download-burn-lm     # optional; gated meta-llama weights
just burn-lm              # optional
just uzu [path] [prompt] [tokens]
```

## Requirements

- **macOS** on Apple Silicon (M1/M2/M3/M4)
- **Xcode** and Metal toolchain for Burn-MLX and Uzu
- **Rust** 1.75+ (1.93+ for Uzu)

## License

MIT OR Apache-2.0
