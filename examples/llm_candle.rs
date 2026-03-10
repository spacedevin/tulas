//! Candle LLM Runner (GGUF Q8_0)
//!
//! Loads Llama-3.2-1B-Instruct-Q8_0.gguf and runs text generation on Apple Silicon (Metal).
//! Model: https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF
//! File: Llama-3.2-1B-Instruct-Q8_0.gguf (~1.32 GB)

use std::path::PathBuf;

use anyhow::Result;
use candle_core::quantized::gguf_file;
use candle_core::{Device, Tensor};
use candle_transformers::generation::{LogitsProcessor, Sampling};
use candle_transformers::models::quantized_llama as model;
use clap::Parser;
use model::ModelWeights;
use tokenizers::Tokenizer;

const DEFAULT_PROMPT: &str = "My favorite theorem is ";

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
    /// Path to GGUF file (e.g. Llama-3.2-1B-Instruct-Q8_0.gguf)
    #[arg(long)]
    model: PathBuf,

    /// Prompt to generate from
    #[arg(long, default_value = DEFAULT_PROMPT)]
    prompt: String,

    /// Max tokens to generate
    #[arg(short = 'n', long, default_value = "64")]
    sample_len: usize,

    /// Temperature (0 = greedy)
    #[arg(long, default_value = "0.8")]
    temperature: f64,

    /// Use CPU instead of Metal
    #[arg(long)]
    cpu: bool,

    /// Seed for sampling
    #[arg(long, default_value = "299792458")]
    seed: u64,
}

fn main() -> Result<()> {
    let args = Args::parse();

    if !args.model.exists() {
        anyhow::bail!(
            "Model file not found: {}\nDownload from: https://huggingface.co/lmstudio-community/Llama-3.2-1B-Instruct-GGUF (file: Llama-3.2-1B-Instruct-Q8_0.gguf)",
            args.model.display()
        );
    }

    let device = if args.cpu {
        Device::Cpu
    } else if let Ok(device) = Device::new_metal(0) {
        device
    } else {
        println!("Metal not available, using CPU");
        Device::Cpu
    };

    println!("Loading model from {}...", args.model.display());
    let mut file = std::fs::File::open(&args.model)?;
    let model_content = gguf_file::Content::read(&mut file)
        .map_err(|e| anyhow::anyhow!("Failed to read GGUF: {}", e))?;

    let mut model = ModelWeights::from_gguf(model_content, &mut file, &device)?;
    println!("Model loaded.");

    // Load tokenizer from same directory or meta-llama/Llama-3.2-1B-Instruct
    let tokenizer_path = args
        .model
        .parent()
        .and_then(|p| {
            let t = p.join("tokenizer.json");
            if t.exists() {
                Some(t)
            } else {
                None
            }
        })
        .or_else(|| {
            let api = hf_hub::api::sync::Api::new().ok()?;
            api.model("meta-llama/Llama-3.2-1B-Instruct".to_string())
                .get("tokenizer.json")
                .ok()
        });

    let tokenizer = match tokenizer_path {
        Some(p) => Tokenizer::from_file(p).map_err(|e| anyhow::anyhow!("Tokenizer: {}", e))?,
        None => anyhow::bail!(
            "tokenizer.json not found. Place it next to the model or ensure meta-llama/Llama-3.2-1B-Instruct is accessible."
        ),
    };

    let tokens = tokenizer
        .encode(args.prompt.clone(), true)
        .map_err(|e| anyhow::anyhow!("Encode: {}", e))?;
    let prompt_tokens = tokens.get_ids().to_vec();

    let mut logits_processor = LogitsProcessor::from_sampling(
        args.seed,
        if args.temperature <= 0. {
            Sampling::ArgMax
        } else {
            Sampling::All {
                temperature: args.temperature,
            }
        },
    );

    print!("{}", args.prompt);
    std::io::Write::flush(&mut std::io::stdout())?;

    let mut next_token = {
        let input = Tensor::new(prompt_tokens.as_slice(), &device)?.unsqueeze(0)?;
        let logits = model.forward(&input, 0)?;
        let logits = logits.squeeze(0)?;
        logits_processor.sample(&logits)?
    };

    let mut all_tokens = vec![];
    let to_sample = args.sample_len.saturating_sub(1);
    let decode = |t: u32| -> Result<String> {
        let ids = [t];
        tokenizer
            .decode(ids.as_slice(), false)
            .map_err(|e| anyhow::anyhow!("Decode: {}", e))
    };

    for _ in 0..to_sample {
        if let Ok(s) = decode(next_token) {
            print!("{}", s);
            std::io::Write::flush(&mut std::io::stdout())?;
        }
        all_tokens.push(next_token);

        let input = Tensor::new(&[next_token], &device)?.unsqueeze(0)?;
        let logits = model.forward(&input, prompt_tokens.len() + all_tokens.len() - 1)?;
        let logits = logits.squeeze(0)?;
        next_token = logits_processor.sample(&logits)?;

        // Llama 3.2 EOS
        if next_token == 128001 {
            break;
        }
    }

    println!();
    Ok(())
}
