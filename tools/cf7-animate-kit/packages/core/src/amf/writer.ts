import { AMF0, SOL } from './markers.js';
import { ByteWriter, utf8ByteLength } from './byte-io.js';
import type { Amf0Element, Amf0Value, SolFile } from './ast.js';

/** Write a single AMF0 value (marker + payload). */
export function writeValue(w: ByteWriter, v: Amf0Value): void {
  switch (v.kind) {
    case 'number':
      w.u8(AMF0.NUMBER).double(v.value);
      return;
    case 'boolean':
      w.u8(AMF0.BOOLEAN).u8(v.value ? 1 : 0);
      return;
    case 'string': {
      const len = utf8ByteLength(v.value);
      if (v.long || len > 0xffff) {
        w.u8(AMF0.LONG_STRING).u32(len).utf8(v.value);
      } else {
        w.u8(AMF0.STRING).u16(len).utf8(v.value);
      }
      return;
    }
    case 'object':
      w.u8(AMF0.OBJECT);
      writeMembers(w, v.entries);
      return;
    case 'typedObject':
      w.u8(AMF0.TYPED_OBJECT).u16(utf8ByteLength(v.className)).utf8(v.className);
      writeMembers(w, v.entries);
      return;
    case 'ecmaArray':
      w.u8(AMF0.ECMA_ARRAY).u32(v.lengthAttr);
      writeMembers(w, v.entries);
      return;
    case 'strictArray':
      w.u8(AMF0.STRICT_ARRAY).u32(v.items.length);
      for (const item of v.items) writeValue(w, item);
      return;
    case 'date':
      w.u8(AMF0.DATE).double(v.epochMs).i16(v.timezoneMinutes);
      return;
    case 'null':
      w.u8(AMF0.NULL);
      return;
    case 'undefined':
      w.u8(AMF0.UNDEFINED);
      return;
    case 'unsupported':
      w.u8(AMF0.UNSUPPORTED);
      return;
    case 'reference':
      w.u8(AMF0.REFERENCE).u16(v.index);
      return;
    case 'xml':
      w.u8(AMF0.XML_DOCUMENT).u32(utf8ByteLength(v.value)).utf8(v.value);
      return;
    default: {
      const exhaustive: never = v;
      throw new Error(`Unknown AMF0 value kind: ${JSON.stringify(exhaustive)}`);
    }
  }
}

function writeMembers(w: ByteWriter, entries: Amf0Element[]): void {
  for (const e of entries) {
    w.u16(utf8ByteLength(e.name)).utf8(e.name);
    writeValue(w, e.value);
  }
  // Terminator: empty name + OBJECT_END.
  w.u16(0).u8(AMF0.OBJECT_END);
}

/** Serialize a `SolFile` back to bytes. Byte-exact for losslessly-read files. */
export function writeSol(sol: SolFile): Buffer {
  // Body: each element = u16 nameLen + name + value + 0x00 trailer.
  const bodyW = new ByteWriter();
  for (const el of sol.body) {
    bodyW.u16(utf8ByteLength(el.name)).utf8(el.name);
    writeValue(bodyW, el.value);
    bodyW.u8(0x00);
  }
  const body = bodyW.toBuffer();

  // Region after the 4-byte length field: TCSO + pad + name + amfVersion + body.
  const region = new ByteWriter();
  region.utf8(SOL.MAGIC);
  region.raw(sol.headerPad ?? SOL.HEADER_PAD);
  region.u16(utf8ByteLength(sol.name)).utf8(sol.name);
  region.u32(sol.amfVersion);
  region.raw(body);
  const regionBuf = region.toBuffer();

  const out = new ByteWriter();
  out.u16(sol.signature ?? SOL.SIGNATURE);
  out.u32(regionBuf.length);
  out.raw(regionBuf);
  return out.toBuffer();
}
