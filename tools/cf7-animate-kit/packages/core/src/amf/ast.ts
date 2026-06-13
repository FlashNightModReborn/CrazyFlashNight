/**
 * Rich AMF0 value AST.
 *
 * This is a *lossless* representation of an AMF0 value tree: it preserves the
 * exact marker used (e.g. short vs long string, ECMA-array length attribute,
 * member order, date timezone, raw reference index) so that
 * `readSol -> writeSol` is byte-exact for real Flash Player output. A separate
 * JSON projection (see ./json.ts) collapses this tree into plain JSON the way
 * the project's Rust `flash_lso` reader does for the C# launcher.
 */

/** A named member of an object / typed object / ECMA array. */
export interface Amf0Element {
  name: string;
  value: Amf0Value;
}

export type Amf0Value =
  | { kind: 'number'; value: number }
  | { kind: 'boolean'; value: boolean }
  /** `long=true` means it was/should be written as a 0x0c long string. */
  | { kind: 'string'; value: string; long: boolean }
  | { kind: 'object'; entries: Amf0Element[] }
  | { kind: 'typedObject'; className: string; entries: Amf0Element[] }
  /** ECMA (associative) array; `lengthAttr` is the AS Array `.length` (0 for plain objects-as-array). */
  | { kind: 'ecmaArray'; lengthAttr: number; entries: Amf0Element[] }
  | { kind: 'strictArray'; items: Amf0Value[] }
  | { kind: 'date'; epochMs: number; timezoneMinutes: number }
  | { kind: 'null' }
  | { kind: 'undefined' }
  | { kind: 'unsupported' }
  | { kind: 'reference'; index: number }
  | { kind: 'xml'; value: string };

export type Amf0Kind = Amf0Value['kind'];

/** A parsed SharedObject (.sol) file. */
export interface SolFile {
  /** Always 0x00bf for valid files. */
  signature: number;
  /** The 6 fixed bytes between "TCSO" and the name (normally 0x000400000000). Preserved for byte-exactness. */
  headerPad: Uint8Array;
  /** The SharedObject name (e.g. "crazyflasher7_saves"). */
  name: string;
  /** AMF version of the body: 0 = AMF0, 3 = AMF3. This codec handles AMF0 bodies. */
  amfVersion: number;
  /** The flattened members of the implicit SharedObject `data` object. */
  body: Amf0Element[];
}

/** The kinds that occupy an AMF0 reference-table slot (per the project's verified Flash semantics). */
export function isComplex(v: Amf0Value): boolean {
  return (
    v.kind === 'object' ||
    v.kind === 'typedObject' ||
    v.kind === 'ecmaArray' ||
    v.kind === 'strictArray'
  );
}
