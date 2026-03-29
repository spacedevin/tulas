//! Candle LLM Runner (GGUF weights — bring your own file)
//!
//! This repo’s **`just download` only fetches** [`mlx-community/Llama-3.2-1B-Instruct-MLXTuned`](https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-MLXTuned) (safetensors + tokenizer).
//! Candle needs a **separate GGUF** on disk; use `--tokenizer` pointing at
//! `models/Llama-3.2-1B-Instruct-MLXTuned/tokenizer.json` from that tree so the tokenizer matches MLXTuned.

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
    /// Path to GGUF weights (not downloaded by `just download`; obtain separately if you use Candle)
    #[arg(long)]
    model: PathBuf,

    /// `tokenizer.json` from MLXTuned tree (`just download` → models/...-MLXTuned/tokenizer.json)
    #[arg(long)]
    tokenizer: Option<PathBuf>,

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
            "GGUF not found: {}\nThis repo only auto-downloads mlx-community/Llama-3.2-1B-Instruct-MLXTuned (safetensors). Candle expects a GGUF path you supply plus --tokenizer from that MLXTuned tree.",
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

    // Tokenizer: only MLXTuned file or explicit --tokenizer (no other Hub repos).
    let tokenizer_path = args
        .tokenizer
        .filter(|p| p.exists())
        .or_else(|| {
            args.model.parent().and_then(|p| {
                let t = p.join("tokenizer.json");
                t.exists().then_some(t)
            })
        })
        .or_else(|| {
            let api = hf_hub::api::sync::Api::new().ok()?;
            api.model("mlx-community/Llama-3.2-1B-Instruct-MLXTuned".to_string())
                .get("tokenizer.json")
                .ok()
        });

    let tokenizer = match tokenizer_path {
        Some(p) => Tokenizer::from_file(p).map_err(|e| anyhow::anyhow!("Tokenizer: {}", e))?,
        None => anyhow::bail!(
            "tokenizer.json not found. Pass --tokenizer /path/to/models/Llama-3.2-1B-Instruct-MLXTuned/tokenizer.json (from `just download`) or place tokenizer.json next to the GGUF."
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

    let start = std::time::Instant::now();
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

    let elapsed = start.elapsed();
    let generated = all_tokens.len();
    println!();
    if generated > 0 {
        let tok_per_sec = generated as f64 / elapsed.as_secs_f64();
        eprintln!("[bench] generated {} tokens in {:.2?} ({:.1} tok/s)", generated, elapsed, tok_per_sec);
    }
    Ok(())
}
