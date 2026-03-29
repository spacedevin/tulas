//! Count tokens with a tokenizer.json (for benchmark tok/s fallback).
//! Uses `encode(..., false)` — raw subwords, no added BOS/EOS.
//!
//! Usage: cargo run --example count_tokens --release -- <tokenizer.json> <text>
//!    or: echo "text" | cargo run --example count_tokens --release -- <tokenizer.json> -

use std::io::{self, Read};
use std::path::Path;

use tish_mlx_burn::count_tokens;

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
    let n = count_tokens(tokenizer_path, &text).map_err(|e| -> Box<dyn std::error::Error> {
        e.into()
    })?;
    println!("{n}");
    Ok(())
}
