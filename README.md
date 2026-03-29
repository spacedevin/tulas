# tish-mlx-burn

**Uzu** on Apple Silicon: run and benchmark [Mirai](https://github.com/trymirai/uzu)’s Rust inference engine with **pre-built registry bundles** (no local conversion).

## Requirements

- Rust **1.93+** (see `rustup update`)
- **Tish** CLI with **`fs`** and **`process`** (registry + weights are fetched with `curl`). Example build from a Tish workspace checkout:

  ```bash
  cargo build -p tishlang --release --features fs,process
  export PATH="/path/to/tish/target/release:$PATH"   # or set TISH to the full path to `tish`
  ```

- **`curl`** on `PATH` (used by the download script)

## Model

Weights are **not** plain `huggingface-cli download` MLX trees (wrong `config.json` for Uzu). Use the Mirai CDN via this repo:

```bash
just download-uzu
```

Defaults live in the `justfile` (`registry_repo`, `model_folder`). Override download with **`UZU_REGISTRY_REPO_ID`**. The script reads **`uzu`’s version from `Cargo.lock`** for the API (set **`UZU_ENGINE_VERSION`** to override). **`just download-uzu`** runs **`scripts/download-uzu-registry-model.tish`**; set **`TISH`** if the `tish` binary is not on your `PATH`.

## Commands

| Command | Purpose |
|---------|---------|
| `just download-uzu` | Fetch pre-built Uzu bundle into `models/…` |
| `just uzu` | Stream generation (default: `models/<model_folder>/`) |
| `just benchmark` | Run Uzu on the benchmark prompt → `benchmarks/report-*.md` |
| `just build` | `cargo build --release` |
| `just` | Lists recipes (default target) |

Override the default model directory with **`UZU_MODEL_PATH`** (absolute or repo-relative), or pass a path as the first argument to **`just uzu`**.

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
