import type { Amf0Element, Amf0Value, SolFile } from './ast.js';

/**
 * JSON projection of an AMF0 SOL body, byte-for-byte semantically identical to
 * the project's Rust `flash_lso` reader (`amf0-help/sol_parser`) which feeds the
 * C# launcher. Critically this includes the project's verified real-Flash
 * reference semantics:
 *
 *  - Only complex values (Object / TypedObject / ECMA array / Strict array)
 *    occupy a reference-table slot, indexed in DFS pre-order over the body.
 *  - Real Flash Player occupies reference index 0 with the implicit
 *    SharedObject `data` root, which we never hold, so a body Reference(raw)
 *    resolves to `byIndex[raw - 1]`. Reference(0) -> null. A child pointing back
 *    at the root is emitted by Flash as Unsupported (0x0d) -> null.
 *  - Cycles resolve to null (cycle guard).
 *  - ECMA array with lengthAttr > 0 projects to a JSON array (sparse-padded with
 *    null); lengthAttr == 0 projects to a JSON object.
 *  - Non-finite numbers (NaN / +/-Inf) and null/undefined/unsupported -> null.
 *  - Date projects to its epoch-ms number.
 */
export type Json =
  | null
  | number
  | boolean
  | string
  | Json[]
  | { [k: string]: Json };

class Projection {
  private readonly byIndex: Amf0Value[] = [];

  constructor(body: Amf0Element[]) {
    for (const el of body) this.indexValue(el.value);
  }

  private indexValue(v: Amf0Value): void {
    switch (v.kind) {
      case 'object':
      case 'typedObject':
        this.byIndex.push(v);
        for (const e of v.entries) this.indexValue(e.value);
        return;
      case 'ecmaArray':
        this.byIndex.push(v);
        for (const e of v.entries) this.indexValue(e.value);
        return;
      case 'strictArray':
        this.byIndex.push(v);
        for (const item of v.items) this.indexValue(item);
        return;
      default:
        // Primitives, dates and references do not advance the reference counter.
        return;
    }
  }

  toJson(v: Amf0Value, visiting: Set<number>): Json {
    switch (v.kind) {
      case 'number':
        return Number.isFinite(v.value) ? v.value : null;
      case 'boolean':
        return v.value;
      case 'string':
      case 'xml':
        return v.value;
      case 'null':
      case 'undefined':
      case 'unsupported':
        return null;
      case 'date':
        return Number.isFinite(v.epochMs) ? v.epochMs : null;
      case 'object':
      case 'typedObject':
        return this.entriesToMap(v.entries, visiting);
      case 'strictArray':
        return v.items.map((it) => this.toJson(it, visiting));
      case 'ecmaArray': {
        if (v.lengthAttr > 0) {
          const len = v.lengthAttr;
          const arr: Json[] = new Array<Json>(len).fill(null);
          for (const e of v.entries) {
            const k = Number.parseInt(e.name, 10);
            if (Number.isInteger(k) && k >= 0 && k < len) {
              arr[k] = this.toJson(e.value, visiting);
            }
          }
          return arr;
        }
        return this.entriesToMap(v.entries, visiting);
      }
      case 'reference':
        return this.resolveRef(v.index, visiting);
      default: {
        const exhaustive: never = v;
        throw new Error(`Unknown AMF0 value kind: ${JSON.stringify(exhaustive)}`);
      }
    }
  }

  private entriesToMap(entries: Amf0Element[], visiting: Set<number>): { [k: string]: Json } {
    const obj: { [k: string]: Json } = {};
    for (const e of entries) obj[e.name] = this.toJson(e.value, visiting);
    return obj;
  }

  private resolveRef(raw: number, visiting: Set<number>): Json {
    if (raw === 0) return null;
    const idx = raw - 1;
    if (visiting.has(idx)) return null;
    const target = this.byIndex[idx];
    if (target === undefined) return null;
    visiting.add(idx);
    const j = this.toJson(target, visiting);
    visiting.delete(idx);
    return j;
  }
}

/** Project a parsed SOL into the canonical JSON object (matches the Rust oracle). */
export function solBodyToJson(body: Amf0Element[]): { [k: string]: Json } {
  const proj = new Projection(body);
  const root: { [k: string]: Json } = {};
  for (const el of body) root[el.name] = proj.toJson(el.value, new Set<number>());
  return root;
}

export function solToJson(sol: SolFile): { [k: string]: Json } {
  return solBodyToJson(sol.body);
}

/**
 * Build an AMF0 value from plain JSON (for editor write-back). Arrays become
 * ECMA arrays with a length attribute (AS2 `Array` semantics, which the C#
 * resolver expects); objects become AMF0 objects. NOT byte-preserving vs an
 * original file — intended for re-synthesizing edited data, not round-tripping.
 */
export function jsonToValue(j: Json): Amf0Value {
  if (j === null) return { kind: 'null' };
  switch (typeof j) {
    case 'number':
      return { kind: 'number', value: j };
    case 'boolean':
      return { kind: 'boolean', value: j };
    case 'string':
      return { kind: 'string', value: j, long: false };
    case 'object':
      break;
    default:
      throw new Error(`Cannot encode ${typeof j} as AMF0`);
  }
  if (Array.isArray(j)) {
    return {
      kind: 'ecmaArray',
      lengthAttr: j.length,
      entries: j.map((v, i) => ({ name: String(i), value: jsonToValue(v) })),
    };
  }
  return {
    kind: 'object',
    entries: Object.entries(j).map(([name, v]) => ({ name, value: jsonToValue(v) })),
  };
}

export function jsonToBody(obj: { [k: string]: Json }): Amf0Element[] {
  return Object.entries(obj).map(([name, v]) => ({ name, value: jsonToValue(v) }));
}
