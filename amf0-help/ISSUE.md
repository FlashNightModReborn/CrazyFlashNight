# `Amf0Writer` reference numbering counts non-complex values (AMF0 §2.9 violation)

## Summary

`Amf0Writer` advances its reference counter (`ref_num`) for **every** value it
writes — including simple types such as strings, numbers, booleans and nulls.
Per the AMF0 specification only **complex objects** participate in the
reference table, so the indices `Amf0Writer` assigns are too large whenever a
complex object is preceded by any simple value. References produced this way
are not resolvable by a spec-compliant AMF0 decoder, and the resulting `.sol`
files do not round-trip through real Adobe Flash Player.

The AMF0 *reader* (`AMF0Decoder`) has the mirror-image issue: its `cache`
pushes a slot for every element, not only for complex objects.

## flash-lso version

- Crate `flash-lso` `0.6.0`, git `ruffle-rs/rust-flash-lso` rev
  `4b049ff30eed307fc6add6ede25f364ec7f45e87`
- `rustc 1.95.0`

## Reproduction

Drop this into `examples/` and `cargo run`:

```rust
use flash_lso::amf0::writer::{Amf0Writer, CacheKey, ObjWriter};
use flash_lso::write::write_to_bytes;

fn main() {
    let mut w = Amf0Writer::default();

    // Object A — first complex object — with two string members.
    let (a, ref_a) = w.object(CacheKey::from_ptr(1usize as *const u8));
    let mut a = a.unwrap();
    a.string("m1", "alpha-1");
    a.string("m2", "alpha-2");
    a.commit("A");

    // Object B — second complex object.
    let (b, ref_b) = w.object(CacheKey::from_ptr(2usize as *const u8));
    let b = b.unwrap();
    b.commit("B");

    // Object C — third complex object — referencing B.
    let (c, ref_c) = w.object(CacheKey::from_ptr(3usize as *const u8));
    let mut c = c.unwrap();
    c.reference("ptr_to_B", ref_b);
    c.commit("C");

    println!("A (1st complex object) -> {:?}", ref_a);
    println!("B (2nd complex object) -> {:?}", ref_b);
    println!("C (3rd complex object) -> {:?}", ref_c);

    let mut lso = w.commit_lso("repro");
    let _ = write_to_bytes(&mut lso).unwrap();
}
```

Output:

```
A (1st complex object) -> Reference(0)
B (2nd complex object) -> Reference(3)
C (3rd complex object) -> Reference(4)
```

## Expected vs. actual

The body has three complex objects, `A`, `B`, `C`. A reference to `B` (the
2nd complex object) should carry index **1** (0-based, complex objects only).

| | reference index for `B` |
|---|---|
| AMF0 spec §2.9 (0-based, complex objects only) | `1` |
| `Amf0Writer` (this crate) | **`3`** |

`Amf0Writer` produced `3` because it counted the two `String` members of `A`
as reference-table entries.

## Why this is a bug

The AMF0 specification, §2.9 (Reference Type), defines the reference table as
holding **complex objects only** — anonymous objects, typed objects, ECMA
arrays and strict arrays. Simple types (number, boolean, string, null,
undefined, date, …) are *not* reference-countable and must not advance the
counter.

Because `Amf0Writer` counts them, the reference indices it emits are
unresolvable by any spec-compliant consumer, and a `.sol` written with
`Amf0Writer` cannot be read back correctly by Adobe Flash Player. The output is
self-consistent only with this crate's own `AMF0Decoder` (whose `cache` has the
same flaw — see below).

## Root cause

Writer — `src/amf0/writer/amf0_writer.rs`:

```rust
fn add_element(&mut self, name: &str, s: Value, inc_ref: bool) {
    if inc_ref {
        self.ref_num += 1;   // bumped for primitives too
    }
    self.elements.push(Element::new(name, Rc::new(s)))
}
```

The default `ObjWriter` methods in `src/amf0/writer/obj_writer.rs` —
`string`, `number`, `bool`, `null`, `undefined`, `date`, `xml` — all call
`add_element(.., inc_ref = true)`, so every simple value increments `ref_num`.
`object()` / `array()` / `make_reference()` then hand out `Reference(ref_num)`
with that inflated counter.

Reader — `src/amf0/read.rs`, `parse_single_element`:

```rust
let cache_idx = self.cache.len();
self.cache.push(Rc::new(Value::Undefined));   // pushed for EVERY element
// ... only Object / ECMAArray / StrictArray / TypedObject overwrite cache[cache_idx]
```

`cache` therefore holds one slot per AMF0 value, not one per complex object.
`as_reference()` (which resolves against `cache`) consequently returns
spec-noncompliant indices. (Reference *resolution* on the read path is not
done by this crate — `parse_element_reference` passes the raw `u16` through
untouched — so plain reading is unaffected; the issue surfaces via
`Amf0Writer` and `as_reference`.)

## Suggested fix

Only advance the reference counter for complex values. Concretely: have the
simple-type `ObjWriter` methods call `add_element` with `inc_ref = false`, and
keep the increment solely in `object()` / `array()` (and the typed-object
path). Apply the same "complex only" rule to the `AMF0Decoder.cache` push so
the reader and `as_reference()` agree with the spec.

## Secondary note (separate, for awareness)

Independently of the primitive-counting bug above: `.sol` files written by
**real Adobe Flash Player** are effectively **1-based** for body-level objects
— Flash reserves reference index `0` for the SharedObject's implicit root, so
the first body complex object is referenced as `1`. We verified this with an
independent byte-level AMF0 decoder against both a real 174-object game save
and several controlled saves produced by Flash Player itself (self-reference,
nested references at depth, array-element references — the offset is a
constant `+1` everywhere; a child referencing the root `.data` is emitted as
`Unsupported 0x0D` rather than `Reference(0)`).

So even a spec-correct 0-based `Amf0Writer` would still be off by one from real
Flash SOL output. This is a deeper SOL-container quirk and may be out of scope
for a pure AMF0 fix — mentioning it only so the numbering is documented:
`Amf0Writer` currently matches **neither** the AMF0 spec (`1`) **nor** real
Flash (`2`); it emits `3`.
