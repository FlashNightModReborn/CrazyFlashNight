//! Empirical probe of flash-lso's *own* AMF0 writer (`Amf0Writer` builder),
//! at the pinned commit. Builds: root object A (two string members), root
//! object B, root object C referencing B. Prints the Reference index the
//! builder assigns to each, and dumps the bytes so they can be decoded.
//!
//! Compare three conventions for "Reference to B" (B = 2nd complex object):
//!   - AMF0 spec (0-based, complex objects only)      => 1
//!   - real Adobe Flash SOL (complex only + root slot) => 2
//!   - flash-lso Amf0Writer (counts every value)       => printed below

use flash_lso::amf0::writer::{Amf0Writer, CacheKey, ObjWriter};
use flash_lso::write::write_to_bytes;

fn main() {
    let mut w = Amf0Writer::default();

    let (a, ref_a) = w.object(CacheKey::from_ptr(1usize as *const u8));
    let mut a = a.unwrap();
    a.string("m1", "alpha-1");
    a.string("m2", "alpha-2");
    a.commit("A");

    let (b, ref_b) = w.object(CacheKey::from_ptr(2usize as *const u8));
    let b = b.unwrap();
    b.commit("B");

    let (c, ref_c) = w.object(CacheKey::from_ptr(3usize as *const u8));
    let mut c = c.unwrap();
    c.reference("ptr_to_B", ref_b);
    c.commit("C");

    println!("flash-lso Amf0Writer assigned reference indices:");
    println!("  A (1st complex object) -> {:?}", ref_a);
    println!("  B (2nd complex object) -> {:?}", ref_b);
    println!("  C (3rd complex object) -> {:?}", ref_c);
    println!();
    println!("AMF0 spec wants B (2nd complex obj, 0-based) -> 1");
    println!("real Flash SOL writes B                      -> 2  (complex-only + index-0 root)");

    let mut lso = w.commit_lso("flwriter_probe");
    let bytes = write_to_bytes(&mut lso).expect("serialize");
    std::fs::write("flwriter_probe.sol", &bytes).expect("write file");
    println!();
    println!("wrote flwriter_probe.sol ({} bytes)", bytes.len());
}
