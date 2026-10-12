//! `np_llama` — safe Rust wrapper around llama.cpp for the NP offline backend.
//!
//! # INTERFACE SKETCH — NOT A WORKING BUILD ON ITS OWN
//!
//! Every method on [`LlamaModel`] / [`LlamaContext`] below forwards to the
//! native llama.cpp C API declared in the `extern "C"` block. The bodies are
//! honest about this: they contain only the FFI call plus the minimal safety
//! plumbing (null checks, CString conversion, length handling).
//!
//! To actually use this crate you must link the compiled llama.cpp static
//! library (see the note in Cargo.toml). On Android this is shipped inside
//! the Flutter FFI plugin's `.so` instead of being linked at cargo time.

use std::ffi::{CStr, CString};
use std::os::raw::{c_char, c_float, c_int, c_void};

// ---------------------------------------------------------------------------
// llama.cpp C ABI (real function names from llama.h / common.h).
// Opaque handles are represented as c_void; we never dereference them.
// ---------------------------------------------------------------------------
#[link(name = "llama")]
extern "C" {
    fn llama_model_load_from_file(path: *const c_char, params: *mut c_void)
        -> *mut c_void;
    fn llama_model_free(model: *mut c_void);
    fn llama_init_from_model(
        model: *mut c_void,
        params: *mut c_void,
    ) -> *mut c_void;
    fn llama_free(ctx: *mut c_void);
    fn llama_tokenize(
        model: *const c_void,
        text: *const c_char,
        text_len: c_int,
        tokens: *mut c_int,
        n_tokens_max: c_int,
        add_special: bool,
        parse_special: bool,
    ) -> c_int;
    fn llama_decode(ctx: *mut c_void, batch: *mut c_void) -> c_int;
    fn llama_get_logits(ctx: *mut c_void) -> *mut c_float;
    fn llama_n_vocab(model: *const c_void) -> c_int;
}

/// Error type for fallible wrapper operations.
#[derive(Debug)]
pub enum LlamaError {
    /// `path` contained an interior NUL or the file could not be opened.
    LoadFailed(String),
    /// Tokenizer reported the output buffer was too small / input invalid.
    TokenizeFailed,
    /// `llama_decode` returned a non-zero status.
    DecodeFailed(c_int),
}

impl std::fmt::Display for LlamaError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            LlamaError::LoadFailed(p) => write!(f, "failed to load model: {p}"),
            LlamaError::TokenizeFailed => write!(f, "tokenization failed"),
            LlamaError::DecodeFailed(code) => {
                write!(f, "llama_decode failed with code {code}")
            }
        }
    }
}

impl std::error::Error for LlamaError {}

/// An owned GGUF model handle. `Send` but not `Sync`: llama.cpp models may be
/// shared across threads only with external synchronization.
pub struct LlamaModel {
    // Calls into native llama.cpp via extern "C" (see load/free below).
    handle: *mut c_void,
}

// SAFETY: the raw handle is only touched through the llama.cpp API, which is
// thread-safe for distinct model objects; we keep !Sync to be conservative.
unsafe impl Send for LlamaModel {}

impl LlamaModel {
    /// Load a GGUF model from `path`.
    /// Calls into native llama.cpp via `llama_model_load_from_file`.
    pub fn load(path: &str) -> Result<Self, LlamaError> {
        let c_path = CString::new(path)
            .map_err(|_| LlamaError::LoadFailed(path.to_owned()))?;
        // Calls into native llama.cpp via extern "C".
        let handle = unsafe {
            llama_model_load_from_file(c_path.as_ptr(), std::ptr::null_mut())
        };
        if handle.is_null() {
            return Err(LlamaError::LoadFailed(path.to_owned()));
        }
        Ok(Self { handle })
    }

    /// Tokenize `text` into token ids.
    /// Calls into native llama.cpp via `llama_tokenize`.
    pub fn tokenize(&self, text: &str) -> Result<Vec<i32>, LlamaError> {
        let mut buf = vec![0 as c_int; text.len().max(8) + 8];
        // Calls into native llama.cpp via extern "C".
        let n = unsafe {
            llama_tokenize(
                self.handle as *const c_void,
                text.as_ptr() as *const c_char,
                text.len() as c_int,
                buf.as_mut_ptr(),
                buf.len() as c_int,
                true,  // add_special (BOS)
                false, // parse_special
            )
        };
        if n < 0 {
            return Err(LlamaError::TokenizeFailed);
        }
        buf.truncate(n as usize);
        Ok(buf.into_iter().map(|t| t as i32).collect())
    }

    /// Vocabulary size, via `llama_n_vocab`. Useful for sizing logit buffers.
    /// Calls into native llama.cpp via extern "C".
    pub fn vocab_size(&self) -> usize {
        unsafe { llama_n_vocab(self.handle as *const c_void) as usize }
    }
}

impl Drop for LlamaModel {
    fn drop(&mut self) {
        // Calls into native llama.cpp via extern "C".
        unsafe { llama_model_free(self.handle) };
    }
}

/// An inference context bound to a [`LlamaModel`].
pub struct LlamaContext {
    // Calls into native llama.cpp via extern "C" (see new/decode_step).
    handle: *mut c_void,
    vocab_size: usize,
}

// SAFETY: same reasoning as LlamaModel; contexts must not be shared.
unsafe impl Send for LlamaContext {}

impl LlamaContext {
    /// Create a context from a loaded model.
    /// Calls into native llama.cpp via `llama_init_from_model`.
    pub fn new(model: &LlamaModel) -> Result<Self, LlamaError> {
        // Calls into native llama.cpp via extern "C".
        let handle =
            unsafe { llama_init_from_model(model.handle, std::ptr::null_mut()) };
        if handle.is_null() {
            return Err(LlamaError::LoadFailed(
                "llama_init_from_model returned null".into(),
            ));
        }
        Ok(Self { handle, vocab_size: model.vocab_size() })
    }

    /// Run one decode step over a single-token batch and return the logits
    /// for the last position as a Rust Vec.
    ///
    /// NOTE: a real implementation must build a `llama_batch` and manage
    /// the KV cache / `n_past` bookkeeping. That batching logic is elided
    /// here; the FFI boundary shown is `llama_decode` + `llama_get_logits`.
    /// Calls into native llama.cpp via extern "C".
    pub fn decode_step(
        &mut self,
        _batch: *mut c_void,
    ) -> Result<Vec<f32>, LlamaError> {
        // Calls into native llama.cpp via extern "C".
        let rc = unsafe { llama_decode(self.handle, _batch) };
        if rc != 0 {
            return Err(LlamaError::DecodeFailed(rc));
        }
        // Calls into native llama.cpp via extern "C".
        let logits = unsafe { llama_get_logits(self.handle) };
        if logits.is_null() {
            return Err(LlamaError::DecodeFailed(-1));
        }
        let slice =
            unsafe { std::slice::from_raw_parts(logits, self.vocab_size) };
        Ok(slice.to_vec())
    }

    /// Pool the last hidden state into an embedding vector.
    ///
    /// NOTE: real embedding support requires building llama.cpp with the
    /// embedding flag and calling `llama_get_embeddings*`; this sketch
    /// reuses the logits path to show the FFI shape honestly. Do not use
    /// these numbers as embeddings without fixing that.
    /// Calls into native llama.cpp via extern "C".
    pub fn embedding(&mut self) -> Result<Vec<f32>, LlamaError> {
        // Calls into native llama.cpp via extern "C" (logits stand-in).
        let logits = unsafe { llama_get_logits(self.handle) };
        if logits.is_null() {
            return Err(LlamaError::DecodeFailed(-1));
        }
        let slice =
            unsafe { std::slice::from_raw_parts(logits, self.vocab_size) };
        Ok(slice.to_vec())
    }

    /// Decode a C string returned by llama.cpp helpers (e.g. detokenized
    /// piece buffers) into a Rust String. Pure-Rust helper, no FFI inside.
    pub fn cstr_to_string(ptr: *const c_char) -> String {
        if ptr.is_null() {
            return String::new();
        }
        unsafe { CStr::from_ptr(ptr) }.to_string_lossy().into_owned()
    }
}

impl Drop for LlamaContext {
    fn drop(&mut self) {
        // Calls into native llama.cpp via extern "C".
        unsafe { llama_free(self.handle) };
    }
}
