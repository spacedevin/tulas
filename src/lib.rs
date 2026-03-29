//! Tish native module (`tish:mlx-burn`) and shared helpers for Uzu + tokenizers.
//! Rust binaries and `mlx_burn_object()` are gated behind the `uzu` feature (enabled by default).

#[cfg(feature = "uzu")]
use tishlang_core::NativeFn;
use tishlang_core::{tish_module, Value};

#[cfg(feature = "uzu")]
mod uzu_api;
#[cfg(feature = "uzu")]
pub use uzu_api::{
    count_completion_tokens, count_tokens, generate, generate_stream, generate_stream_to_writer,
};

/// Namespace object for `import { … } from "tish:mlx-burn"`.
#[cfg(feature = "uzu")]
pub fn mlx_burn_object() -> Value {
    use std::path::Path;

    tish_module! {
        "countTokens" => |args: &[Value]| {
            let Some(tok_path) = args.first() else {
                eprintln!("countTokens: expected (tokenizerPath, text)");
                return Value::Null;
            };
            let Some(text_v) = args.get(1) else {
                eprintln!("countTokens: expected (tokenizerPath, text)");
                return Value::Null;
            };
            let path = tok_path.to_display_string();
            let text = text_v.to_display_string();
            match count_tokens(Path::new(&path), &text) {
                Ok(n) => Value::Number(n as f64),
                Err(e) => {
                    eprintln!("countTokens: {e}");
                    Value::Null
                }
            }
        },
        "benchCompletionTokens" => |args: &[Value]| {
            let Some(tok_path) = args.first() else {
                eprintln!("benchCompletionTokens: expected (tokenizerPath, prompt, fullText)");
                return Value::Null;
            };
            let Some(prompt_v) = args.get(1) else {
                eprintln!("benchCompletionTokens: expected (tokenizerPath, prompt, fullText)");
                return Value::Null;
            };
            let Some(full_v) = args.get(2) else {
                eprintln!("benchCompletionTokens: expected (tokenizerPath, prompt, fullText)");
                return Value::Null;
            };
            let path = tok_path.to_display_string();
            let prompt = prompt_v.to_display_string();
            let full = full_v.to_display_string();
            match count_completion_tokens(Path::new(&path), &prompt, &full) {
                Ok(n) => Value::Number(n as f64),
                Err(e) => {
                    eprintln!("benchCompletionTokens: {e}");
                    Value::Null
                }
            }
        },
        "generate" => |args: &[Value]| {
            let Some(model_v) = args.first() else {
                eprintln!("generate: expected (modelPath, prompt, tokensLimit)");
                return Value::Null;
            };
            let Some(prompt_v) = args.get(1) else {
                eprintln!("generate: expected (modelPath, prompt, tokensLimit)");
                return Value::Null;
            };
            let limit = parse_tokens_limit(args.get(2));
            let model_path = model_v.to_display_string();
            let prompt = prompt_v.to_display_string();
            match generate(Path::new(&model_path), &prompt, limit) {
                Ok(s) => Value::String(std::sync::Arc::from(s)),
                Err(e) => {
                    eprintln!("generate: {e}");
                    Value::Null
                }
            }
        },
        "generateStream" => |args: &[Value]| {
            let Some(model_v) = args.first() else {
                eprintln!("generateStream: expected (modelPath, prompt, tokensLimit, onChunk)");
                return Value::Null;
            };
            let Some(prompt_v) = args.get(1) else {
                eprintln!("generateStream: expected (modelPath, prompt, tokensLimit, onChunk)");
                return Value::Null;
            };
            let Some(cb_v) = args.get(3) else {
                eprintln!("generateStream: expected (modelPath, prompt, tokensLimit, onChunk)");
                return Value::Null;
            };
            let Value::Function(f) = cb_v else {
                eprintln!("generateStream: onChunk must be a function");
                return Value::Null;
            };
            let limit = parse_tokens_limit(args.get(2));
            let model_path = model_v.to_display_string();
            let prompt = prompt_v.to_display_string();
            let f: NativeFn = f.clone();
            match generate_stream(
                Path::new(&model_path),
                &prompt,
                limit,
                move |delta: &str| {
                    let _ = f(&[Value::String(std::sync::Arc::from(delta))]);
                },
            ) {
                Ok(_) => Value::Null,
                Err(e) => {
                    eprintln!("generateStream: {e}");
                    Value::Null
                }
            }
        },
    }
}

#[cfg(not(feature = "uzu"))]
pub fn mlx_burn_object() -> Value {
    tish_module! {
        "countTokens" => |_args: &[Value]| {
            eprintln!("countTokens: tish-mlx-burn was built without the \"uzu\" feature");
            Value::Null
        },
        "benchCompletionTokens" => |_args: &[Value]| {
            eprintln!("benchCompletionTokens: tish-mlx-burn was built without the \"uzu\" feature");
            Value::Null
        },
        "generate" => |_args: &[Value]| {
            eprintln!("generate: tish-mlx-burn was built without the \"uzu\" feature");
            Value::Null
        },
        "generateStream" => |_args: &[Value]| {
            eprintln!("generateStream: tish-mlx-burn was built without the \"uzu\" feature");
            Value::Null
        },
    }
}

#[cfg(feature = "uzu")]
fn parse_tokens_limit(v: Option<&Value>) -> u64 {
    let Some(v) = v else {
        return 128;
    };
    let n = v.as_number().unwrap_or(128.0);
    if n <= 0.0 || n.is_nan() || n.is_infinite() {
        return 128;
    }
    n.clamp(1.0, u64::MAX as f64) as u64
}
