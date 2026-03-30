# TULAS — Tish and Uzu with LLama on Apple Silicon

> 🚧 Experimental

**Run a model**

```bash
just download    # once: fetch bundle (needs `tish` + fs,process; see below)
just             # same as `just run`: default model, prompt, and token cap from the justfile
just run "Your prompt" 128
just run ./models/Llama-3.2-1B-Instruct-8bit "Hello" 64
```

Override model dir with `UZU_MODEL_PATH`, or pass the bundle directory as the first argument to `just run`.

**Requirements**

- Rust **1.93+**
- **`tish`** with **`fs`** and **`process`** for download only:

  ```bash
  cargo build -p tishlang --release --features fs,process
  export PATH="/path/to/tish/target/release:$PATH"   # or TISH=/path/to/tishlang
  ```

- **`curl`** (used by the download script)

Weights must be Mirai/Uzu registry bundles (not arbitrary MLX trees). Default **repo id** and **install folder** are set in [`scripts/download-uzu-registry-model.tish`](scripts/download-uzu-registry-model.tish) (`defaultRegistryRepoId`, `defaultModelRelPath`). The `justfile` **`model_folder`** must stay aligned with that path so `just run` finds the bundle. Override download with **`UZU_REGISTRY_REPO_ID`** / **`UZU_MODEL_DEST`** / **`UZU_ENGINE_VERSION`** in the environment.

**Other `just` recipes**

| Recipe | Purpose |
|--------|---------|
| `just --list` | List recipes |
| `just build` | `cargo build --release` |
| `just benchmark` | Longer run + `benchmarks/report-*.md` |
| `just tish-llm` / `just tish-count-tokens` | Optional Tish demos: same defaults as `just run` when given no args; else args go to the binary |

`download-uzu` and `uzu` still work as aliases for `download` and `run`.

**Cargo (without `just`)**

```bash
cargo run --example llm_uzu --release -- --stream ./models/Llama-3.2-1B-Instruct-8bit "Tell me about London" 128
```

More models: [Mirai Uzu — Models](https://github.com/trymirai/uzu#models).