//! sol_parser: FFI cdylib for parsing AS2 SOL files into JSON.
//!
//! Consumed by the C# Launcher (SolParserNative.cs). Returns full soData
//! (top-level keys intact — dual-write / backrefs resolved) as a UTF-8 JSON
//! object, which the C# SolResolver then migrates + validates.

use std::collections::HashMap;
use std::ffi::OsString;
use std::fs;
use std::os::windows::ffi::OsStringExt;
use std::path::PathBuf;
use std::rc::Rc;
use std::slice;

use flash_lso::read::Reader;
use flash_lso::types::{Element, Reference, Value};
use serde_json::{Map as JsonMap, Number as JsonNum, Value as Json};

/// Return codes. Must stay in sync with SolParserNative.cs.
pub const RC_OK: i32 = 0;
pub const RC_NOT_FOUND: i32 = 1;
pub const RC_IO_ERROR: i32 = 2;
pub const RC_PARSE_ERROR: i32 = 3;
pub const RC_INVALID_ARGS: i32 = 4;
pub const RC_SERIALIZE_ERROR: i32 = 5;

/// Safe public API: parse a SOL file into a JSON object.
/// Oracle harness and integration tests call this directly.
pub fn parse_sol_path(path: &std::path::Path) -> Result<Json, i32> {
    let bytes = fs::read(path).map_err(|e| {
        if e.kind() == std::io::ErrorKind::NotFound {
            RC_NOT_FOUND
        } else {
            RC_IO_ERROR
        }
    })?;
    parse_sol_bytes(&bytes)
}

/// Safe public API: parse SOL bytes into a JSON object.
pub fn parse_sol_bytes(bytes: &[u8]) -> Result<Json, i32> {
    let mut reader = Reader::default();
    let lso = reader.parse(bytes).map_err(|_| RC_PARSE_ERROR)?;

    let mut ctx = Ctx::default();
    for el in &lso.body {
        ctx.index_value(&el.value);
    }

    let mut root = JsonMap::new();
    let mut visiting: Vec<u16> = Vec::new();
    for el in &lso.body {
        let j = ctx.to_json(&el.value, &mut visiting);
        root.insert(el.name.clone(), j);
    }
    Ok(Json::Object(root))
}

/// Debug helper: dump by_index snapshot. Returns a list of (index, tag,
/// first-3-keys-or-value) entries for inspection.
pub fn debug_index(bytes: &[u8]) -> Result<Vec<(u16, String, String)>, i32> {
    let mut reader = Reader::default();
    let lso = reader.parse(bytes).map_err(|_| RC_PARSE_ERROR)?;
    let mut ctx = Ctx::default();
    for el in &lso.body {
        ctx.index_value(&el.value);
    }
    let mut out = Vec::new();
    for (i, v) in ctx.by_index.iter().enumerate() {
        let (tag, preview) = match v.as_ref() {
            Value::Object(_, elems, _) | Value::Custom(_, elems, _) => (
                "Object",
                elems
                    .iter()
                    .take(3)
                    .map(|e| e.name.as_str())
                    .collect::<Vec<_>>()
                    .join(","),
            ),
            Value::ECMAArray(_, _, assoc, len) => (
                "ECMAArray",
                format!(
                    "len_attr={} keys=[{}]",
                    len,
                    assoc
                        .iter()
                        .take(3)
                        .map(|e| e.name.as_str())
                        .collect::<Vec<_>>()
                        .join(",")
                ),
            ),
            Value::StrictArray(_, items) => ("StrictArray", format!("count={}", items.len())),
            _ => ("?", String::new()),
        };
        out.push((i as u16, tag.to_string(), preview));
    }
    Ok(out)
}

/// Parse a SOL file at `path_ptr` (UTF-16, `path_len` code units) and emit
/// its full body as a UTF-8 JSON object at `*out_json_ptr` (length in
/// `*out_json_len`). Caller owns the resulting buffer and MUST release it
/// via `sol_free`.
///
/// # Safety
/// - `path_ptr` must point to `path_len` valid u16 code units.
/// - `out_json_ptr` and `out_json_len` must be valid out-pointers.
#[no_mangle]
pub unsafe extern "C" fn sol_parse_file(
    path_ptr: *const u16,
    path_len: u32,
    out_json_ptr: *mut *mut u8,
    out_json_len: *mut u32,
) -> i32 {
    if path_ptr.is_null() || out_json_ptr.is_null() || out_json_len.is_null() {
        return RC_INVALID_ARGS;
    }
    *out_json_ptr = std::ptr::null_mut();
    *out_json_len = 0;

    let wide = slice::from_raw_parts(path_ptr, path_len as usize);
    let os: OsString = OsString::from_wide(wide);
    let path = PathBuf::from(os);

    let json = match parse_sol_path(&path) {
        Ok(j) => j,
        Err(rc) => return rc,
    };

    let s = match serde_json::to_string(&json) {
        Ok(s) => s,
        Err(_) => return RC_SERIALIZE_ERROR,
    };

    let bytes_out = s.into_bytes();
    let len = bytes_out.len();
    let mut boxed = bytes_out.into_boxed_slice();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);
    *out_json_ptr = ptr;
    *out_json_len = len as u32;
    RC_OK
}

/// Release a buffer returned by `sol_parse_file`.
///
/// # Safety
/// `ptr`/`len` must match exactly what `sol_parse_file` returned.
#[no_mangle]
pub unsafe extern "C" fn sol_free(ptr: *mut u8, len: u32) {
    if ptr.is_null() {
        return;
    }
    let slice = slice::from_raw_parts_mut(ptr, len as usize);
    drop(Box::from_raw(slice as *mut [u8]));
}

/// Parse/encode scratch state: tracks parser cache order (for Reference
/// resolution) and Rc identity → cache index reverse map.
#[derive(Default)]
struct Ctx {
    by_index: Vec<Rc<Value>>,
    by_ptr: HashMap<usize, u16>,
}

impl Ctx {
    /// Walk in DFS pre-order, indexing **only AMF0 complex types** (Object,
    /// ECMAArray, StrictArray, TypedObject). Per AMF0 spec §2.9 the reference
    /// counter increments for complex objects only — simple types (Number,
    /// Bool, String, Null, Date, etc.) and References themselves do not
    /// advance the counter. flash-lso passes the raw file-level u16 index
    /// through without translating, so consumer-side resolution must use the
    /// spec counter.
    ///
    /// AMF3 containers live in a separate reference pool; they never resolve
    /// into the AMF0 cache and are not indexed here.
    fn index_value(&mut self, v: &Rc<Value>) {
        match v.as_ref() {
            Value::Object(_, elems, _) | Value::Custom(_, elems, _) => {
                let idx = self.by_index.len() as u16;
                self.by_index.push(Rc::clone(v));
                let key = Rc::as_ptr(v) as usize;
                self.by_ptr.entry(key).or_insert(idx);
                for e in elems {
                    self.index_value(&e.value);
                }
            }
            Value::ECMAArray(_, dense, assoc, _) => {
                let idx = self.by_index.len() as u16;
                self.by_index.push(Rc::clone(v));
                let key = Rc::as_ptr(v) as usize;
                self.by_ptr.entry(key).or_insert(idx);
                for item in dense {
                    self.index_value(item);
                }
                for e in assoc {
                    self.index_value(&e.value);
                }
            }
            Value::StrictArray(_, items) => {
                let idx = self.by_index.len() as u16;
                self.by_index.push(Rc::clone(v));
                let key = Rc::as_ptr(v) as usize;
                self.by_ptr.entry(key).or_insert(idx);
                for item in items {
                    self.index_value(item);
                }
            }
            // AMF3 structural traversal (not indexed into AMF0 cache, but we
            // still descend to visit any nested AMF0 compound values that
            // might have been embedded via the AMF3→AMF0 bridge).
            Value::VectorObject(_, items, _, _) => {
                for item in items {
                    self.index_value(item);
                }
            }
            Value::Dictionary(_, pairs, _) => {
                for (k, vv) in pairs {
                    self.index_value(k);
                    self.index_value(vv);
                }
            }
            Value::AMF3(inner) => {
                self.index_value(inner);
            }
            _ => {}
        }
    }

    fn to_json(&self, v: &Rc<Value>, visiting: &mut Vec<u16>) -> Json {
        match v.as_ref() {
            Value::Number(n) => number_or_null(*n),
            Value::Bool(b) => Json::Bool(*b),
            Value::String(s) => Json::String(s.clone()),
            Value::Null | Value::Undefined | Value::Unsupported => Json::Null,
            Value::Object(_, elems, _) => Json::Object(self.elements_to_map(elems, visiting)),
            Value::ECMAArray(_, dense, assoc, len_attr) => {
                // AMF0 ECMAArray carries the AS2 Array's `.length` in
                // `len_attr`. If the source was an AS2 Array, len_attr is its
                // length and all pairs are `"0".."N-1"`. If the source was an
                // AS2 Object, `.length` is 0 → len_attr == 0.
                //
                // C#-side ValidateResolvedSnapshot expects mydata[0..7] as
                // JArray. Matching the AS2 encoding semantics: len_attr > 0
                // → emit JSON Array (sparse-padded with nulls). Otherwise
                // fall back to JSON Object. The dense vec is always empty
                // for AMF0 but populated for AMF3, so include it too.
                if *len_attr > 0 {
                    let len = *len_attr as usize;
                    let mut arr: Vec<Json> = vec![Json::Null; len];
                    for e in assoc {
                        if let Ok(k) = e.name.parse::<usize>() {
                            if k < len {
                                arr[k] = self.to_json(&e.value, visiting);
                                continue;
                            }
                        }
                        // Non-numeric / out-of-range assoc key on an
                        // Array-shaped ECMAArray is unusual but possible
                        // (AS2 Array with extra named properties). Silently
                        // drop to preserve JArray-ness; the corresponding
                        // data would have been lost in AS2 loadFromMydata
                        // anyway.
                    }
                    for (i, item) in dense.iter().enumerate() {
                        if i < len {
                            arr[i] = self.to_json(item, visiting);
                        }
                    }
                    Json::Array(arr)
                } else {
                    let mut map = self.elements_to_map(assoc, visiting);
                    for (i, item) in dense.iter().enumerate() {
                        map.insert(i.to_string(), self.to_json(item, visiting));
                    }
                    Json::Object(map)
                }
            }
            Value::StrictArray(_, items) => Json::Array(
                items.iter().map(|v| self.to_json(v, visiting)).collect(),
            ),
            Value::Date(ts, _) => number_or_null(*ts),
            Value::XML(s, _) => Json::String(s.clone()),
            Value::Reference(r) => self.resolve_ref(r, visiting),
            Value::AMF3(inner) => self.to_json(inner, visiting),
            Value::Integer(i) => Json::Number(JsonNum::from(*i)),
            Value::ByteArray(bytes) => Json::Array(
                bytes
                    .iter()
                    .map(|b| Json::Number(JsonNum::from(u64::from(*b))))
                    .collect(),
            ),
            Value::VectorInt(v, _) => Json::Array(
                v.iter().map(|n| Json::Number(JsonNum::from(*n))).collect(),
            ),
            Value::VectorUInt(v, _) => Json::Array(
                v.iter()
                    .map(|n| Json::Number(JsonNum::from(u64::from(*n))))
                    .collect(),
            ),
            Value::VectorDouble(v, _) => {
                Json::Array(v.iter().map(|n| number_or_null(*n)).collect())
            }
            Value::VectorObject(_, items, _, _) => Json::Array(
                items.iter().map(|v| self.to_json(v, visiting)).collect(),
            ),
            Value::Dictionary(_, pairs, _) => {
                let mut map = JsonMap::new();
                for (k, vv) in pairs {
                    let key = match k.as_ref() {
                        Value::String(s) => s.clone(),
                        Value::Integer(i) => i.to_string(),
                        Value::Number(n) => n.to_string(),
                        _ => continue,
                    };
                    map.insert(key, self.to_json(vv, visiting));
                }
                Json::Object(map)
            }
            Value::Custom(custom_elems, regular_elems, _) => {
                let mut map = self.elements_to_map(regular_elems, visiting);
                for e in custom_elems {
                    map.entry(e.name.clone())
                        .or_insert_with(|| self.to_json(&e.value, visiting));
                }
                Json::Object(map)
            }
            Value::Amf3ObjectReference(_) => Json::Null,
        }
    }

    fn elements_to_map(&self, elems: &[Element], visiting: &mut Vec<u16>) -> JsonMap<String, Json> {
        let mut map = JsonMap::with_capacity(elems.len());
        for e in elems {
            map.insert(e.name.clone(), self.to_json(&e.value, visiting));
        }
        map
    }

    fn resolve_ref(&self, r: &Reference, visiting: &mut Vec<u16>) -> Json {
        // Flash Player writes reference indexes as 1-based (an artifact of
        // its internal HashMap behavior: the first complex object is stored
        // when the table already holds one entry — typically the root or a
        // sentinel). Empirically, `Reference(N)` in the byte stream maps to
        // our 0-based cache at position N-1. Guard against the edge where
        // a Reference(0) somehow appears (it should not in valid AMF0).
        let raw = reference_index(r);
        if raw == 0 {
            return Json::Null;
        }
        let idx = raw - 1;
        if visiting.contains(&idx) {
            return Json::Null;
        }
        let target = match self.by_index.get(idx as usize) {
            Some(v) => v,
            None => return Json::Null,
        };
        visiting.push(idx);
        let j = self.to_json(target, visiting);
        visiting.pop();
        j
    }
}

/// Extract the u16 index from a flash-lso `Reference` without relying on a
/// public accessor (field is pub(crate)). With `serde` feature enabled on
/// flash-lso, the newtype tuple-struct serializes transparently as the inner
/// u16, giving us a stable extraction path.
fn reference_index(r: &Reference) -> u16 {
    match serde_json::to_value(r) {
        Ok(Json::Number(n)) => n.as_u64().unwrap_or(0) as u16,
        _ => 0,
    }
}

fn number_or_null(n: f64) -> Json {
    JsonNum::from_f64(n).map(Json::Number).unwrap_or(Json::Null)
}
