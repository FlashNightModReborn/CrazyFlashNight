import { AMF0, SOL } from './markers.js';
import { ByteReader } from './byte-io.js';
import type { Amf0Element, Amf0Value, SolFile } from './ast.js';

/** Read a single AMF0 value (marker + payload) at the reader's cursor. */
export function readValue(r: ByteReader): Amf0Value {
  const marker = r.u8();
  return readValueWithMarker(r, marker);
}

function readValueWithMarker(r: ByteReader, marker: number): Amf0Value {
  switch (marker) {
    case AMF0.NUMBER:
      return { kind: 'number', value: r.double() };
    case AMF0.BOOLEAN:
      return { kind: 'boolean', value: r.u8() !== 0 };
    case AMF0.STRING:
      return { kind: 'string', value: r.utf8(r.u16()), long: false };
    case AMF0.LONG_STRING:
      return { kind: 'string', value: r.utf8(r.u32()), long: true };
    case AMF0.OBJECT:
      return { kind: 'object', entries: readMembers(r) };
    case AMF0.TYPED_OBJECT: {
      const className = r.utf8(r.u16());
      return { kind: 'typedObject', className, entries: readMembers(r) };
    }
    case AMF0.ECMA_ARRAY: {
      const lengthAttr = r.u32();
      return { kind: 'ecmaArray', lengthAttr, entries: readMembers(r) };
    }
    case AMF0.STRICT_ARRAY: {
      const count = r.u32();
      const items: Amf0Value[] = [];
      for (let i = 0; i < count; i++) items.push(readValue(r));
      return { kind: 'strictArray', items };
    }
    case AMF0.DATE: {
      const epochMs = r.double();
      const timezoneMinutes = r.i16();
      return { kind: 'date', epochMs, timezoneMinutes };
    }
    case AMF0.NULL:
      return { kind: 'null' };
    case AMF0.UNDEFINED:
      return { kind: 'undefined' };
    case AMF0.UNSUPPORTED:
      return { kind: 'unsupported' };
    case AMF0.REFERENCE:
      return { kind: 'reference', index: r.u16() };
    case AMF0.XML_DOCUMENT:
      return { kind: 'xml', value: r.utf8(r.u32()) };
    default:
      throw new Error(
        `Unsupported AMF0 marker 0x${marker.toString(16).padStart(2, '0')} at offset ${r.pos - 1}`,
      );
  }
}

/**
 * Read object/typed-object/ECMA-array members until the `0x00 0x00 0x09`
 * (empty name + object-end) terminator.
 */
function readMembers(r: ByteReader): Amf0Element[] {
  const entries: Amf0Element[] = [];
  for (;;) {
    const nameLen = r.u16();
    if (nameLen === 0) {
      const marker = r.u8();
      if (marker === AMF0.OBJECT_END) break;
      // Empty-named member carrying a real value (rare, but valid).
      entries.push({ name: '', value: readValueWithMarker(r, marker) });
      continue;
    }
    const name = r.utf8(nameLen);
    entries.push({ name, value: readValue(r) });
  }
  return entries;
}

/**
 * Parse a Flash SharedObject (.sol) file into a lossless `SolFile`.
 *
 * Layout: `00 BF | u32 length | "TCSO" | 6 pad bytes | u16 nameLen + name |
 * u32 amfVersion | body`. The body is a sequence of
 * `u16 nameLen + name + AMF0 value + 0x00 trailer` elements until EOF.
 */
export function readSol(buf: Buffer): SolFile {
  const r = new ByteReader(buf);
  const signature = r.u16();
  if (signature !== SOL.SIGNATURE) {
    throw new Error(
      `Not a .sol file: signature 0x${signature.toString(16)} (expected 0x${SOL.SIGNATURE.toString(16)})`,
    );
  }
  const declaredLen = r.u32();
  const magic = r.utf8(4);
  if (magic !== SOL.MAGIC) {
    throw new Error(`Bad SOL magic ${JSON.stringify(magic)} (expected "TCSO")`);
  }
  const headerPad = r.raw(6);
  const name = r.utf8(r.u16());
  const amfVersion = r.u32();
  if (amfVersion !== 0) {
    throw new Error(
      `SOL body AMF version ${amfVersion} is not supported (only AMF0 / version 0). ` +
        `CF7 AS2 saves are AMF0.`,
    );
  }

  const body: Amf0Element[] = [];
  while (!r.eof) {
    const nameLen = r.u16();
    const elName = r.utf8(nameLen);
    const value = readValue(r);
    r.u8(); // per-element 0x00 trailer
    body.push({ name: elName, value });
  }

  // declaredLen is informational; the body loop is driven by EOF.
  void declaredLen;
  return { signature, headerPad, name, amfVersion, body };
}
