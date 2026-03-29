//! Uzu LLM Runner
//!
//! Runs models using the Uzu inference engine on Apple Silicon.
//! Pass path to a model directory. Use --stream to print tokens as they arrive.
//!
//! For benchmarks, set `BENCH_TOKENIZER` to a `tokenizer.json` path to emit
//! `[bench] generated N tokens in …` for benchmark scripts.

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicUsize, Ordering};

use tokenizers::Tokenizer;
use uzu::session::{
    config::{DecodingConfig, RunConfig},
    types::{Input, Output},
    Session,
};

fn count_completion_tokens(
    tokenizer_path: &Path,
    prompt: &str,
    full_text: &str,
) -> Result<usize, Box<dyn std::error::Error>> {
    let tokenizer = Tokenizer::from_file(tokenizer_path)
        .map_err(|e| format!("Tokenizer: {}", e))?;
    let completion = if full_text.starts_with(prompt) {
        &full_text[prompt.len()..]
    } else {
        full_text
    };
    let encoding = tokenizer
        .encode(completion, false)
        .map_err(|e| format!("Encode: {}", e))?;
    Ok(encoding.get_ids().len())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut args: Vec<String> = std::env::args().collect();
    let stream = if args.get(1).map(|s| s.as_str()) == Some("--stream") {
        args.remove(1);
        true
    } else {
        false
    };

    let (model_path, prompt, tokens_limit) = match args.len() {
        1 => {
            eprintln!("Usage: cargo run --example llm_uzu --features uzu -- [--stream] <MODEL_PATH> [PROMPT] [TOKENS_LIMIT]");
            eprintln!();
            eprintln!("Example:");
            eprintln!("  cargo run --example llm_uzu --features uzu -- ./models/Llama-3.2-1B-Instruct-8bit 'Tell me about London' 128");
            std::process::exit(1);
        }
        2 => (
            PathBuf::from(&args[1]),
            "Tell me about London.".to_string(),
            128,
        ),
        3 => (PathBuf::from(&args[1]), args[2].clone(), 128),
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

    let prompt_str = prompt.clone();
    let start = std::time::Instant::now();
    let input = Input::Text(prompt);

    let output = if stream {
        let last_len = AtomicUsize::new(0);
        session.run(
            input,
            RunConfig::default().tokens_limit(tokens_limit),
            Some(move |output: Output| {
                let text = &output.text.original;
                let prev = last_len.load(Ordering::SeqCst);
                if text.len() > prev {
                    print!("{}", &text[prev..]);
                    let _ = std::io::stdout().flush();
                    last_len.store(text.len(), Ordering::SeqCst);
                }
                true
            }),
        )?
    } else {
        session.run(
            input,
            RunConfig::default().tokens_limit(tokens_limit),
            Some(|_: Output| true),
        )?
    };

    let elapsed = start.elapsed();
    if !stream {
        println!("{}", output.text.original);
    } else {
        println!();
    }

    match std::env::var("BENCH_TOKENIZER") {
        Ok(path) if !path.is_empty() => {
            match count_completion_tokens(Path::new(&path), &prompt_str, &output.text.original) {
                Ok(n) => {
                    let tok_per_sec = n as f64 / elapsed.as_secs_f64().max(f64::EPSILON);
                    eprintln!(
                        "[bench] generated {} tokens in {:.2?} ({:.1} tok/s)",
                        n, elapsed, tok_per_sec
                    );
                }
                Err(e) => {
                    eprintln!("BENCH_TOKENIZER: {e}");
                    eprintln!("[bench] completed in {:.2?}", elapsed);
                }
            }
        }
        _ => eprintln!("[bench] completed in {:.2?}", elapsed),
    }
    Ok(())
}
