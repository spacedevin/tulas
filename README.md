# tish-mlx-burn

**Uzu** on Apple Silicon: run and benchmark [Mirai](https://github.com/trymirai/uzu)’s Rust inference engine with **pre-built registry bundles** (no local conversion).

## Requirements

- Rust **1.93+** (see `rustup update`)
- Python **3** for `scripts/download-uzu-registry-model.py`

## Model

Weights are **not** plain `huggingface-cli download` MLX trees (wrong `config.json` for Uzu). Use the Mirai CDN via this repo:

```bash
just download-uzu
```

Defaults live in the `justfile` (`registry_repo`, `model_folder`). Override download with **`UZU_REGISTRY_REPO_ID`**. The script reads **`uzu`’s version from `Cargo.lock`** for the API (set **`UZU_ENGINE_VERSION`** to override).

## Commands

| Command | Purpose |
|---------|---------|
| `just download-uzu` | Fetch pre-built Uzu bundle into `models/…` |
| `just uzu` | Stream generation (default model path from resolver) |
| `just benchmark` | Run Uzu on the benchmark prompt → `benchmarks/report-*.md` |
| `just build` | `cargo build --release` |
| `just` | Lists recipes (default target) |

Paths: **`UZU_MODEL_PATH`**, or **`UZU_MODEL_DIR`** + **`UZU_MODEL_BUNDLE`**, else `scripts/resolve-uzu-model-path.sh` (see script header).

## Examples

```bash
just download-uzu
just uzu "Tell me about London" 128
just uzu ./models/Llama-3.2-1B-Instruct-8bit "Hello" 64
```

```bash
cargo run --example llm_uzu --release -- --stream \
  ./models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

More models: [Mirai Uzu README — Models](https://github.com/trymirai/uzu#models) (`list-models` / registry IDs).

## License

MIT OR Apache-2.0 (see repository).
