//! Empirical AMF0 Reference round-trip tests.
//!
//! Outside the sol_parser crate, `flash_lso::types::Reference` has a
//! crate-private inner u16, so we hand-craft raw AMF0 byte streams here.
//! That lets us probe Reference(0) / Reference(1) / Reference(out-of-range)
//! without fighting the public API.
//!
//! The test assumes AMF0 spec §2.9 semantics: the reference index is 0-based
//! and counts only complex objects (Object / ECMAArray / StrictArray /
//! TypedObject). flash-lso's own writer (amf0/writer/amf0_writer.rs) is also
//! 0-based — the first cached complex object is stored with Reference(0).

use serde_json::Value as Json;

/// Build a valid SOL byte stream containing a hand-written AMF0 body.
fn wrap_sol(body: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    // HEADER_VERSION
    out.extend_from_slice(&[0x00, 0xBF]);
    // length placeholder
    let len_pos = out.len();
    out.extend_from_slice(&[0, 0, 0, 0]);
    // HEADER_SIGNATURE
    out.extend_from_slice(&[0x54, 0x43, 0x53, 0x4F, 0x00, 0x04, 0x00, 0x00, 0x00, 0x00]);
    // name: u16 "test"
    out.extend_from_slice(&[0x00, 0x04]);
    out.extend_from_slice(b"test");
    // 3 × PADDING
    out.extend_from_slice(&[0x00, 0x00, 0x00]);
    // FORMAT_VERSION_AMF0
    out.push(0x00);
    // body
    out.extend_from_slice(body);
    // fix up length field: total_len - 6 (matches flash-lso's Writer)
    let total_len = (out.len() - 6) as u32;
    let be = total_len.to_be_bytes();
    out[len_pos..len_pos + 4].copy_from_slice(&be);
    out
}

/// Write `<u16 len BE><utf8>` prefixed string (AMF0 short-string format).
fn push_str(buf: &mut Vec<u8>, s: &str) {
    let bytes = s.as_bytes();
    buf.extend_from_slice(&(bytes.len() as u16).to_be_bytes());
    buf.extend_from_slice(bytes);
}

/// AMF0 Object with a single `{marker: value}` field, no class def.
/// Type marker 0x03, ObjectEnd sequence 0x00 0x00 0x09.
fn write_object_marker(buf: &mut Vec<u8>, value: &str) {
    buf.push(0x03); // Object marker
    // inner element name
    push_str(buf, "marker");
    // String value: 0x02 <u16 len> <bytes>
    buf.push(0x02);
    push_str(buf, value);
    // ObjectEnd
    buf.extend_from_slice(&[0x00, 0x00, 0x09]);
}

/// AMF0 Reference: 0x07 <u16 index BE>
fn write_reference(buf: &mut Vec<u8>, index: u16) {
    buf.push(0x07);
    buf.extend_from_slice(&index.to_be_bytes());
}

/// SOL body element: <u16 name len + name><amf0 value><0x00 padding>
fn push_named<F: FnOnce(&mut Vec<u8>)>(buf: &mut Vec<u8>, name: &str, write_value: F) {
    push_str(buf, name);
    write_value(buf);
    buf.push(0x00);
}

#[test]
fn reference_zero_resolves_to_first_cached_object() {
    // Body:
    //   "a" = Object{marker:"AA"}     → cached as index 0
    //   "b" = Object{marker:"BB"}     → cached as index 1
    //   "r0" = Reference(0)            → must equal "a" (0-based)
    //   "r1" = Reference(1)            → must equal "b" (0-based)
    let mut body = Vec::new();
    push_named(&mut body, "a", |b| write_object_marker(b, "AA"));
    push_named(&mut body, "b", |b| write_object_marker(b, "BB"));
    push_named(&mut body, "r0", |b| write_reference(b, 0));
    push_named(&mut body, "r1", |b| write_reference(b, 1));

    let bytes = wrap_sol(&body);
    let json = sol_parser::parse_sol_bytes(&bytes).expect("parse_sol_bytes");
    let obj = json.as_object().expect("root object");

    let r0 = obj.get("r0").and_then(Json::as_object)
        .and_then(|m| m.get("marker"))
        .and_then(Json::as_str);
    let r1 = obj.get("r1").and_then(Json::as_object)
        .and_then(|m| m.get("marker"))
        .and_then(Json::as_str);

    assert_eq!(r0, Some("AA"),
        "Reference(0) must resolve to the FIRST cached complex object \
         (per AMF0 spec §2.9 and flash-lso writer convention). \
         Got: {:?}", obj.get("r0"));
    assert_eq!(r1, Some("BB"),
        "Reference(1) must resolve to the SECOND cached complex object. \
         Got: {:?}", obj.get("r1"));
}

#[test]
fn reference_out_of_range_is_null() {
    // Only one cached complex object, so Reference(5) is out of range.
    let mut body = Vec::new();
    push_named(&mut body, "only", |b| write_object_marker(b, "X"));
    push_named(&mut body, "oob", |b| write_reference(b, 5));

    let bytes = wrap_sol(&body);
    let json = sol_parser::parse_sol_bytes(&bytes).expect("parse_sol_bytes");
    let obj = json.as_object().expect("root object");

    assert!(obj.get("oob").map(Json::is_null).unwrap_or(false),
        "Out-of-range reference should emit JSON null. Got: {:?}", obj.get("oob"));
}
