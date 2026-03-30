//! Tish native module (`tish:tulas`) and shared helpers for Uzu + tokenizers.
//! `tulas_object()` is gated behind the `uzu` feature (enabled by default).

#[cfg(feature = "uzu")]
use tishlang_core::NativeFn;
use tishlang_core::{tish_module, Value};

#[cfg(feature = "uzu")]
mod uzu_api;
#[cfg(feature = "uzu")]
pub use uzu_api::{
    count_completion_tokens, count_tokens, generate, generate_bench, generate_stream,
    generate_stream_to_writer,
};

/// Namespace object for `import { … } from "tish:tulas"`.
#[cfg(feature = "uzu")]
pub fn tulas_object() -> Value {
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
        "generateBench" => |args: &[Value]| {
            let Some(model_v) = args.first() else {
                eprintln!("generateBench: expected (modelPath, prompt, tokensLimit)");
                return Value::Null;
            };
            let Some(prompt_v) = args.get(1) else {
                eprintln!("generateBench: expected (modelPath, prompt, tokensLimit)");
                return Value::Null;
            };
            let limit = parse_tokens_limit(args.get(2));
            let model_path = model_v.to_display_string();
            let prompt = prompt_v.to_display_string();
            match generate_bench(Path::new(&model_path), &prompt, limit) {
                Ok((text, elapsed_ms, tokens)) => {
                    let mut map = ObjectMap::default();
                    map.insert(std::sync::Arc::from("text"), Value::String(std::sync::Arc::from(text)));
                    map.insert(std::sync::Arc::from("elapsed_ms"), Value::Number(elapsed_ms as f64));
                    map.insert(std::sync::Arc::from("tokens"), Value::Number(tokens as f64));
                    Value::object(map)
                }
                Err(e) => {
                    eprintln!("generateBench: {e}");
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
pub fn tulas_object() -> Value {
    tish_module! {
        "countTokens" => |_args: &[Value]| {
            eprintln!("countTokens: tish-tulas was built without the \"uzu\" feature");
            Value::Null
        },
        "benchCompletionTokens" => |_args: &[Value]| {
            eprintln!("benchCompletionTokens: tish-tulas was built without the \"uzu\" feature");
            Value::Null
        },
        "generate" => |_args: &[Value]| {
            eprintln!("generate: tish-tulas was built without the \"uzu\" feature");
            Value::Null
        },
        "generateBench" => |_args: &[Value]| {
            eprintln!("generateBench: tish-tulas was built without the \"uzu\" feature");
            Value::Null
        },
        "generateStream" => |_args: &[Value]| {
            eprintln!("generateStream: tish-tulas was built without the \"uzu\" feature");
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
