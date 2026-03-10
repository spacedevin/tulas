//! Uzu LLM Runner
//!
//! Runs Llama 3.2 1B Instruct using the Uzu inference engine on Apple Silicon.
//! Model must be converted to Uzu format first via lalamo:
//!
//!   uv run lalamo convert meta-llama/Llama-3.2-1B-Instruct
//!
//! Then point this example at the converted model directory (e.g. ./models/{VERSION}/Llama-3.2-1B-Instruct/).

use std::path::PathBuf;

use uzu::session::{
    config::{DecodingConfig, RunConfig},
    types::{Input, Output},
    Session,
};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();

    let (model_path, prompt, tokens_limit) = match args.len() {
        1 => {
            eprintln!("Usage: cargo run --example llm_uzu --features uzu -- <MODEL_PATH> [PROMPT] [TOKENS_LIMIT]");
            eprintln!();
            eprintln!("Example:");
            eprintln!("  cargo run --example llm_uzu --features uzu -- ./models/v1/Llama-3.2-1B-Instruct 'Tell me about London' 128");
            eprintln!();
            eprintln!("To convert a model to Uzu format:");
            eprintln!("  git clone https://github.com/trymirai/lalamo && cd lalamo");
            eprintln!("  uv run lalamo convert meta-llama/Llama-3.2-1B-Instruct");
            std::process::exit(1);
        }
        2 => (
            PathBuf::from(&args[1]),
            "Tell me about London.".to_string(),
            128,
        ),
        3 => (
            PathBuf::from(&args[1]),
            args[2].clone(),
            128,
        ),
        _ => (
            PathBuf::from(&args[1]),
            args[2].clone(),
            args[3].parse().unwrap_or(128),
        ),
    };

    if !model_path.exists() {
        return Err(format!("Model path does not exist: {}", model_path.display()).into());
    }

    println!("Loading model from {}...", model_path.display());
    let mut session = Session::new(model_path, DecodingConfig::default())?;

    println!("Prompt: {}", prompt);
    println!("Generating (max {} tokens)...\n", tokens_limit);

    let input = Input::Text(prompt);
    let output = session.run(
        input,
        RunConfig::default().tokens_limit(tokens_limit),
        Some(|_: Output| true),
    )?;

    println!("{}", output.text.original);
    Ok(())
}
