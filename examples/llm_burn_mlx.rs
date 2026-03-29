//! Burn-MLX LLM Runner (safetensors loading + MLX backend)
//!
//! Demonstrates loading safetensors metadata and running on Apple Silicon via burn-mlx.
//! Model: `mlx-community/Llama-3.2-1B-Instruct-MLXTuned` (ungated safetensors; same as `just download`).
//!
//! Full LLM text generation requires burn-lm with MLX backend (burn-lm-llama uses Burn 0.18;
//! burn-mlx targets Burn 0.16). This example shows the MLX backend and safetensors pipeline.
//!
//! Download: `just download` (recommended) or
//! `hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned --local-dir ./models/Llama-3.2-1B-Instruct-MLXTuned`

use std::path::PathBuf;

use burn::tensor::backend::Backend;
use burn::tensor::Tensor;
use burn_mlx::{Mlx, MlxDevice};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    let model_path = match args.get(1) {
        Some(p) => PathBuf::from(p),
        None => {
            eprintln!("Usage: cargo run --example llm_burn_mlx --features burn-mlx -- <PATH_TO_MODEL_SAFETENSORS>");
            eprintln!();
            eprintln!("Example:");
            eprintln!("  cargo run --example llm_burn_mlx --features burn-mlx -- ./models/Llama-3.2-1B-Instruct-MLXTuned/model.safetensors");
            eprintln!();
            eprintln!("Download model:");
            eprintln!("  just download");
            eprintln!("  # or: hf download mlx-community/Llama-3.2-1B-Instruct-MLXTuned --local-dir ./models/Llama-3.2-1B-Instruct-MLXTuned");
            std::process::exit(1);
        }
    };

    let device = MlxDevice::Gpu;
    let start = std::time::Instant::now();
    println!("Burn-MLX on device: {:?}", device);

    if model_path.exists() {
        let data = std::fs::read(&model_path)?;
        let tensors = safetensors::SafeTensors::deserialize(&data)?;
        println!("Loaded {} tensors from {}", tensors.len(), model_path.display());
    } else {
        println!("Model path not found ({}). Proceeding with MLX demo.", model_path.display());
    }

    println!("\nRunning MLX tensor computation...");
    run_mlx_demo::<Mlx>(&device);
    eprintln!("[bench] load+compute in {:.2?} (no text generation)", start.elapsed());

    println!("\nNote: Full LLM text generation requires burn-lm with MLX backend.");
    println!("See: https://github.com/tracel-ai/burn-lm");
    Ok(())
}

fn run_mlx_demo<B: Backend>(device: &B::Device) {
    let a: Tensor<B, 2> = Tensor::from_floats([[1.0, 2.0], [3.0, 4.0]], device);
    let b: Tensor<B, 2> = Tensor::from_floats([[5.0, 6.0], [7.0, 8.0]], device);
    let c = a.matmul(b);
    println!("Matrix multiply result:\n{}", c);
}
