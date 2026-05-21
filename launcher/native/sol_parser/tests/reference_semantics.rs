//! AMF0 Reference resolution — pinned against a **real Flash Player-written
//! SOL fixture**, not synthetic bytes.
//!
//! Why a real fixture: an earlier refactor changed `resolve_ref` to a pure
//! 0-based lookup citing the AMF0 spec text, and silently regressed every
//! dual-write top-level key. Synthetic AMF0 fixtures cannot catch that class
//! of bug — whoever hand-writes the fixture bytes also picks the indexing
//! convention, so such a test just re-asserts its own assumption. Real Flash
//! Player SOL output carries an implicit-root offset (Flash occupies
//! reference index 0 with the SharedObject root) that only a real SOL
//! exposes; `resolve_ref` corrects it with `raw - 1`.
//!
//! Ground-truth invariant: CF7:ME's `SaveManager.saveAll` dual-writes the
//! *same object instance* both into `mydata.{tasks,pets,shop}` (nested under
//! the `test` key) and as a top-level SOL key. Flash encodes the second
//! occurrence as an AMF0 Reference. After a correct parse, each top-level
//! dual-write key MUST deep-equal its nested counterpart; a reference
//! off-by-one makes them diverge onto a neighbouring object.

use serde_json::Value as Json;
use std::path::PathBuf;

fn fixture(name: &str) -> PathBuf {
    let mut p = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    p.push("tests");
    p.push("fixtures");
    p.push(name);
    p
}

/// THE regression test: a real v3.0 game SOL, dual-write top-level keys must
/// resolve to exactly the same value as their nested `test.*` counterparts.
#[test]
fn real_flash_sol_dual_write_keys_resolve_correctly() {
    let json = sol_parser::parse_sol_path(&fixture("real_flash_v3.sol"))
        .expect("parse real_flash_v3.sol fixture");
    let root = json.as_object().expect("root is an object");
    let test = root
        .get("test")
        .and_then(Json::as_object)
        .expect("soData.test present");

    // (top-level SOL key, nested bundle under `test`, key inside the bundle).
    // Mirrors SaveManager.saveAll dual-write + the 3.0 mydata.{tasks,pets,shop}.
    let pairs: [(&str, &str, &str); 7] = [
        ("tasks_to_do", "tasks", "tasks_to_do"),
        ("tasks_finished", "tasks", "tasks_finished"),
        ("task_chains_progress", "tasks", "task_chains_progress"),
        ("战宠", "pets", "宠物信息"),
        ("宠物领养限制", "pets", "宠物领养限制"),
        ("商城已购买物品", "shop", "商城已购买物品"),
        ("商城购物车", "shop", "商城购物车"),
    ];

    for (top_key, bundle, nested_key) in pairs.iter() {
        let top = root
            .get(*top_key)
            .unwrap_or_else(|| panic!("top-level key `{}` missing", top_key));
        let nested = test
            .get(*bundle)
            .and_then(Json::as_object)
            .unwrap_or_else(|| panic!("test.{} bundle missing", bundle))
            .get(*nested_key)
            .unwrap_or_else(|| panic!("test.{}.{} missing", bundle, nested_key));

        assert_eq!(
            top, nested,
            "dual-write mismatch: top-level `{}` != `test.{}.{}` — AMF0 \
             Reference resolution is off in resolve_ref. top={:?} nested={:?}",
            top_key, bundle, nested_key, top, nested
        );
    }
}

// ── Synthetic byte-level tests: unresolvable-input guards only. ──
// These hand-build AMF0 streams. They deliberately do NOT assert positive
// reference *semantics* — the real fixture above is the sole authority for
// that. They only pin the convention-agnostic guards (index 0 / out-of-range
// both yield JSON null).

/// Build a valid SOL byte stream wrapping a hand-written AMF0 body.
fn wrap_sol(body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(&[0x00, 0xBF]); // HEADER_VERSION
    let len_pos = out.len();
    out.extend_from_slice(&[0, 0, 0, 0]); // length placeholder
    // HEADER_SIGNATURE "TCSO" + padding
    out.extend_from_slice(&[0x54, 0x43, 0x53, 0x4F, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);
    out.extend_from_slice(&[0x00, 0x04]); // name length
    out.extend_from_slice(b"test");
    out.extend_from_slice(&[0x00, 0x00, 0x00]); // 3 × PADDING
    out.push(0x00); // FORMAT_VERSION_AMF0
    out.extend_from_slice(body);
    let total_len = (out.len() - 6) as u32;
    out[len_pos..len_pos + 4].copy_from_slice(&total_len.to_be_bytes());
    out
}

/// AMF0 short string: `<u16 len BE><utf8>`.
fn push_str(buf: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    buf.extend_from_slice(&(bytes.len() as u16).to_be_bytes());
    buf.extend_from_slice(bytes);
}

/// AMF0 Object with a single `{marker: <value>}` field (marker 0x03, end 0009).
fn write_object_marker(buf: &mut Vec<u8>, value: &str) {
    buf.push(0x03);
    push_str(buf, "marker");
    buf.push(0x02); // String marker
    push_str(buf, value);
    buf.extend_from_slice(&[0x00, 0x00, 0x09]); // ObjectEnd
}

/// AMF0 Reference: `0x07 <u16 index BE>`.
fn write_reference(buf: &mut Vec<u8>, index: u16) {
    buf.push(0x07);
    buf.extend_from_slice(&index.to_be_bytes());
}

/// SOL body element: `<u16 name len + name><amf0 value><0x00 padding>`.
fn push_named<F: FnOnce(&mut Vec<u8>)>(buf: &mut Vec<u8>, name: &str, write_value: F) {
    push_str(buf, name);
    write_value(buf);
    buf.push(0x00);
}

#[test]
fn reference_index_zero_is_null() {
    // Index 0 = Flash's implicit SharedObject root, not a body-level value
    // sol_parser holds → unresolvable → JSON null.
    let mut body = Vec::new();
    push_named(&mut body, "only", |b| write_object_marker(b, "X"));
    push_named(&mut body, "r0", |b| write_reference(b, 0));

    let bytes = wrap_sol(&body);
    let json = sol_parser::parse_sol_bytes(&bytes).expect("parse_sol_bytes");
    let obj = json.as_object().expect("root object");

    assert!(
        obj.get("r0").map(Json::is_null).unwrap_or(false),
        "Reference(0) must resolve to JSON null. Got: {:?}",
        obj.get("r0")
    );
}

#[test]
fn reference_out_of_range_is_null() {
    // Only one body-level complex object; Reference(99) is far out of range.
    let mut body = Vec::new();
    push_named(&mut body, "only", |b| write_object_marker(b, "X"));
    push_named(&mut body, "oob", |b| write_reference(b, 99));

    let bytes = wrap_sol(&body);
    let json = sol_parser::parse_sol_bytes(&bytes).expect("parse_sol_bytes");
    let obj = json.as_object().expect("root object");

    assert!(
        obj.get("oob").map(Json::is_null).unwrap_or(false),
        "Out-of-range reference must resolve to JSON null. Got: {:?}",
        obj.get("oob")
    );
}
