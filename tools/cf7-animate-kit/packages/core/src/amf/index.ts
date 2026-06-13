export type { Amf0Element, Amf0Value, Amf0Kind, SolFile } from './ast.js';
export { isComplex } from './ast.js';
export { AMF0, SOL } from './markers.js';
export { ByteReader, ByteWriter, utf8ByteLength } from './byte-io.js';
export { readSol, readValue } from './reader.js';
export { writeSol, writeValue } from './writer.js';
export { solToJson, solBodyToJson, jsonToValue, jsonToBody } from './json.js';
export type { Json } from './json.js';

import { readSol } from './reader.js';
import { solToJson } from './json.js';
import type { Json } from './json.js';

/** Convenience: parse .sol bytes straight to the canonical JSON projection. */
export function parseSolToJson(buf: Buffer): { [k: string]: Json } {
  return solToJson(readSol(buf));
}
