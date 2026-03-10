//! Count tokens for a string using Llama 3.2 tokenizer.
//! Used by benchmarks to compute tok/s when backends don't report token count.
//!
//! Usage: cargo run --example count_tokens --features candle --release -- <path/to/tokenizer.json> <text>
//!    or: echo "text" | cargo run --example count_tokens --features candle --release -- <path/to/tokenizer.json> -

use std::io::{self, Read};
use std::path::Path;

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = std::env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: count_tokens <tokenizer.json> <text>");
        eprintln!("   or: count_tokens <tokenizer.json> -  # read text from stdin");
        std::process::exit(1);
    }
    let tokenizer_path = Path::new(&args[1]);
    let text = if args[2] == "-" {
        let mut s = String::new();
        io::stdin().read_to_string(&mut s)?;
        s
    } else {
        args[2].clone()
    };
    let tokenizer = tokenizers::Tokenizer::from_file(tokenizer_path)
        .map_err(|e| format!("Failed to load tokenizer: {}", e))?;
    let encoding = tokenizer.encode(text, true).map_err(|e| format!("Encode: {}", e))?;
    println!("{}", encoding.get_ids().len());
    Ok(())
}
