Confirmed still present at commit `4b049ff3`. I think this thread already has
everything needed to land a fix — here's a self-contained repro of what
`Amf0Writer` actually emits, the exact rule it breaks (your comment above
pins it down nicely), the matching flaw on the read side, and a precise fix.

### `Amf0Writer` emits unresolvable reference indices

Minimal repro using only the public writer API:

```rust
use flash_lso::amf0::writer::{Amf0Writer, CacheKey, ObjWriter};
use flash_lso::write::write_to_bytes;

fn main() {
    let mut w = Amf0Writer::default();

    // A — 1st complex object — with two string members.
    let (a, ref_a) = w.object(CacheKey::from_ptr(1usize as *const u8));
    let mut a = a.unwrap();
    a.string("m1", "alpha-1");
    a.string("m2", "alpha-2");
    a.commit("A");

    // B — 2nd complex object.
    let (b, ref_b) = w.object(CacheKey::from_ptr(2usize as *const u8));
    let b = b.unwrap();
    b.commit("B");

    // C — 3rd complex object — references B.
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

So `C.ptr_to_B` is written as `Reference(3)`. The file has exactly three
complex objects (`A`, `B`, `C` → indices 0, 1, 2), so **index 3 is out of
range** — that reference cannot be resolved at all. It should be
`Reference(1)` (B is the 2nd complex object, 0-based). The two `String`
members of `A` each advanced the counter.

### The rule being broken

Your comment-2 dump pins the correct behaviour down precisely: `d`, `a`, `b`,
`c` get indices 0–3 and the `Date` gets 4, while every `String` (`"date1"`,
`"date2"`, the three `"abc"`, and the inner `"a"`/`"b"`/`"c"`) gets no index.
Two things follow:

- Strings / numbers / bools / null / undefined must **not** advance the counter.
- `Date` **must** — it's index 4 in your dump and `d[9]` resolves to it — even
  though the spec's "complex object" wording (anonymous object, typed object,
  array, ecma-array) doesn't list Date. A fix that counts only those four
  types would still mis-encode Date.

### Root cause

`src/amf0/writer/obj_writer.rs` — every default value method passes
`inc_ref: true` except `reference`:

| `ObjWriter` method | current `inc_ref` | correct |
|---|---|---|
| `string` `number` `undefined` `null` `bool` `xml` | `true` | **`false`** |
| `date` | `true` | `true` (keep — Date is reference-counted) |
| `reference` | `false` | `false` ✓ |
| `object` / `array` / typed object | increment inside `amf0_writer.rs` | ✓ |

`Amf0Writer::add_element` (`src/amf0/writer/amf0_writer.rs`) then does
`if inc_ref { self.ref_num += 1; }`, and `object()` / `array()` hand out
`Reference(self.ref_num)` from the inflated counter.

### Same flaw on the read side

`src/amf0/read.rs::parse_single_element` does `self.cache.push(...)` for
*every* element, and only `Object` / `ECMAArray` / `StrictArray` /
`TypedObject` overwrite their slot afterwards. `cache` therefore holds one
entry per value rather than one per complex object, so
`AMF0Decoder::as_reference()` returns indices with the same inflation.

(Plain *reading* is unaffected — `parse_element_reference` passes the raw
`u16` straight through without resolving against `cache` — so this only bites
`as_reference()` and the writer.)

### Suggested fix

In `obj_writer.rs`, change `string` / `number` / `undefined` / `null` /
`bool` / `xml` to pass `inc_ref: false`; leave `date` at `true`;
`object` / `array` / typed object already increment correctly. Apply the same
"complex + Date only" condition to the `cache.push` in `parse_single_element`
so the reader and `as_reference()` agree with the spec.

(Orthogonal, not blocking a fix here: the writer has no `cache_add` path for
`Date`, so a repeated `Date` instance is re-encoded inline instead of as a
reference — real Flash does dedup it, per `d[9]` in your dump. Probably worth
its own issue.)

### Happy to send a PR

If the direction above looks right, I'm glad to open a PR: flip the `inc_ref`
flags in `obj_writer.rs`, apply the matching "complex + Date only" condition
to `parse_single_element`, and add a regression test (writer reference
indices for an object with primitive members, plus a read-back round-trip).

<details>
<summary>Side note — reference numbering inside SharedObject (.sol) files</summary>

Recording this since `flash-lso` also reads/writes `.sol`. In your comment-2
example `d` is the top-level value, so it's index `0`. A `.sol` file differs:
its body is the flattened members of the implicit `SharedObject.data` object,
and that root object occupies index `0` — so the first *body-level* complex
object is index `1`.

We verified this against real Adobe Flash Player `.sol` output — the genuine
Adobe runtime, not Ruffle or any reimplementation: one 174-object save from a
shipping AVM1/AS2 game, plus controlled saves written by the Flash Player that
Adobe Flash Professional CS6 drives for `testMovie` (self-reference,
references nested multiple levels deep, references inside arrays). AMF0's
`SharedObject` serialisation has been stable across Flash Player versions, so
this is not version-specific. Body references are uniformly the spec index
`+ 1`, the offset is a constant, and a child pointing back at the root
`.data` is emitted as `Unsupported (0x0D)` rather than a reference. This is not a `flash-lso` bug — the AMF0 reader
passes the raw `u16` through untouched — but a writer that targets `.sol`
output needs the root object to occupy slot 0.

</details>
