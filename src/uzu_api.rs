//! Uzu session + tokenizers (feature `uzu`).

use std::cell::RefCell;
use std::io::Write;
use std::path::Path;
use std::rc::Rc;
use std::sync::atomic::{AtomicUsize, Ordering};

use tokenizers::Tokenizer;
use uzu::session::{
    config::{DecodingConfig, RunConfig},
    types::{Input, Output},
    Session,
};

fn uzu_err(e: uzu::prelude::Error) -> String {
    e.to_string()
}

pub fn count_tokens(tokenizer_path: &Path, text: &str) -> Result<usize, String> {
    let tokenizer =
        Tokenizer::from_file(tokenizer_path).map_err(|e| format!("Tokenizer: {e}"))?;
    let encoding = tokenizer
        .encode(text, false)
        .map_err(|e| format!("Encode: {e}"))?;
    Ok(encoding.get_ids().len())
}

pub fn count_completion_tokens(
    tokenizer_path: &Path,
    prompt: &str,
    full_text: &str,
) -> Result<usize, String> {
    let tokenizer =
        Tokenizer::from_file(tokenizer_path).map_err(|e| format!("Tokenizer: {e}"))?;
    let completion = if full_text.starts_with(prompt) {
        &full_text[prompt.len()..]
    } else {
        full_text
    };
    let encoding = tokenizer
        .encode(completion, false)
        .map_err(|e| format!("Encode: {e}"))?;
    Ok(encoding.get_ids().len())
}

pub fn generate(model_path: &Path, prompt: &str, tokens_limit: u64) -> Result<String, String> {
    let mut session =
        Session::new(model_path.to_path_buf(), DecodingConfig::default()).map_err(uzu_err)?;
    let input = Input::Text(prompt.to_string());
    let out = session
        .run(
            input,
            RunConfig::default().tokens_limit(tokens_limit),
            Some(|_: Output| true),
        )
        .map_err(uzu_err)?;
    Ok(out.text.original)
}

/// Hot path for CLI / benchmarks: one `RefCell` borrow per chunk (matches pre–crate-split `llm_uzu`).
pub fn generate_stream_to_writer<W: Write + 'static>(
    model_path: &Path,
    prompt: &str,
    tokens_limit: u64,
    writer: Rc<RefCell<W>>,
) -> Result<String, String> {
    let w = Rc::clone(&writer);
    let last_len = AtomicUsize::new(0);
    let mut session =
        Session::new(model_path.to_path_buf(), DecodingConfig::default()).map_err(uzu_err)?;
    let input = Input::Text(prompt.to_string());
    let out = session
        .run(
            input,
            RunConfig::default().tokens_limit(tokens_limit),
            Some(move |output: Output| {
                let text = &output.text.original;
                let prev = last_len.load(Ordering::Relaxed);
                if text.len() > prev {
                    let _ = w.borrow_mut().write_all(text[prev..].as_bytes());
                    last_len.store(text.len(), Ordering::Relaxed);
                }
                true
            }),
        )
        .map_err(uzu_err)?;
    Ok(out.text.original)
}

/// For Tish / custom callbacks: extra `RefCell` around `FnMut` so the Uzu progress hook stays `Fn`.
pub fn generate_stream<F>(
    model_path: &Path,
    prompt: &str,
    tokens_limit: u64,
    on_delta: F,
) -> Result<String, String>
where
    F: FnMut(&str) + 'static,
{
    let on_delta = Rc::new(RefCell::new(on_delta));
    let od = Rc::clone(&on_delta);
    let last_len = AtomicUsize::new(0);
    let mut session =
        Session::new(model_path.to_path_buf(), DecodingConfig::default()).map_err(uzu_err)?;
    let input = Input::Text(prompt.to_string());
    let out = session
        .run(
            input,
            RunConfig::default().tokens_limit(tokens_limit),
            Some(move |output: Output| {
                let text = &output.text.original;
                let prev = last_len.load(Ordering::Relaxed);
                if text.len() > prev {
                    od.borrow_mut()(&text[prev..]);
                    last_len.store(text.len(), Ordering::Relaxed);
                }
                true
            }),
        )
        .map_err(uzu_err)?;
    Ok(out.text.original)
}
