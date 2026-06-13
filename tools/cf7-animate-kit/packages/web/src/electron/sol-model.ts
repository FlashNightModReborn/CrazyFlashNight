/**
 * SOL <-> renderer tree projection + in-place leaf editing (main process only).
 *
 * The renderer's tree view is built from the lossless AMF0 AST (`SolFile.body`),
 * NOT from `parseSolToJson` — because we must keep a stable, reversible address
 * for every editable primitive so a Save can mutate that exact node and rewrite
 * byte-faithfully via `writeSol`. We deliberately do NOT follow `reference`
 * values (they are shown as read-only leaves) to avoid aliasing two paths onto
 * one node; only direct primitive leaves are editable.
 */
import type { Amf0Element, Amf0Value, SolFile } from "@cf7-animate-kit/core";
import type {
  SolTreeNode,
  SolNodeKind,
  SolMeta,
  SolEdit,
  SolDiffLine,
} from "../shared/ipc-types.js";

// --- path segment escaping (so member names containing "/" stay addressable) ---
// "~" -> "~0", "/" -> "~1" (JSON-Pointer style, applied per segment).
function escapeSeg(seg: string): string {
  return seg.replace(/~/g, "~0").replace(/\//g, "~1");
}
function joinPath(parent: string, seg: string): string {
  const esc = escapeSeg(seg);
  return parent === "" ? esc : `${parent}/${esc}`;
}

function leafKindOf(v: Amf0Value): SolNodeKind {
  switch (v.kind) {
    case "number":
    case "boolean":
    case "string":
    case "null":
    case "undefined":
    case "date":
    case "unsupported":
    case "reference":
    case "xml":
      return v.kind;
    case "object":
      return "object";
    case "typedObject":
      return "typedObject";
    case "ecmaArray":
      return "ecmaArray";
    case "strictArray":
      return "strictArray";
    default: {
      const exhaustive: never = v;
      return exhaustive;
    }
  }
}

function typeLabelOf(v: Amf0Value): string {
  switch (v.kind) {
    case "string":
      return v.long ? "string (long)" : "string";
    case "ecmaArray":
      return `ecmaArray[${v.lengthAttr}]`;
    case "strictArray":
      return `strictArray[${v.items.length}]`;
    case "typedObject":
      return `typedObject<${v.className}>`;
    case "object":
      return "object";
    case "date":
      return "date";
    case "reference":
      return `reference(${v.index})`;
    default:
      return v.kind;
  }
}

/** Editable primitives: number / boolean / string. Everything else is read-only. */
function isEditable(v: Amf0Value): boolean {
  return v.kind === "number" || v.kind === "boolean" || v.kind === "string";
}

function primitiveValue(v: Amf0Value): string | number | boolean | undefined {
  switch (v.kind) {
    case "number":
      return v.value;
    case "boolean":
      return v.value;
    case "string":
    case "xml":
      return v.value;
    case "date":
      return v.epochMs;
    case "reference":
      return v.index;
    case "null":
      return "null";
    case "undefined":
      return "undefined";
    case "unsupported":
      return "unsupported";
    default:
      return undefined;
  }
}

function valueToNode(key: string, path: string, v: Amf0Value): SolTreeNode {
  const node: SolTreeNode = {
    key,
    path,
    kind: leafKindOf(v),
    typeLabel: typeLabelOf(v),
    editable: isEditable(v),
  };
  const pv = primitiveValue(v);
  if (pv !== undefined) node.value = pv;

  if (v.kind === "object" || v.kind === "typedObject" || v.kind === "ecmaArray") {
    node.children = v.entries.map((e) => valueToNode(e.name, joinPath(path, e.name), e.value));
  } else if (v.kind === "strictArray") {
    node.children = v.items.map((it, i) => valueToNode(String(i), joinPath(path, String(i)), it));
  }
  return node;
}

/** Project the SOL body into renderer tree nodes (top-level members as roots). */
export function buildSolTree(sol: SolFile): SolTreeNode[] {
  return sol.body.map((e) => valueToNode(e.name, escapeSeg(e.name), e.value));
}

function countLeaves(nodes: SolTreeNode[]): number {
  let n = 0;
  for (const node of nodes) {
    if (node.children && node.children.length > 0) n += countLeaves(node.children);
    else n += 1;
  }
  return n;
}

export function buildSolMeta(sol: SolFile, fileSize: number): SolMeta {
  const tree = buildSolTree(sol);
  return {
    name: sol.name,
    amfVersion: sol.amfVersion,
    signature: sol.signature,
    elementCount: sol.body.length,
    leafCount: countLeaves(tree),
    fileSize,
  };
}

// --- path resolution against the AST (returns the parent container + accessor) ---

interface LeafRef {
  /** The current value at the path. */
  current: Amf0Value;
  /** Replace the value at the path within the AST. */
  set: (next: Amf0Value) => void;
}

function decodeSeg(seg: string): string {
  return seg.replace(/~1/g, "/").replace(/~0/g, "~");
}

/** Walk the AST to the value addressed by `path`, returning a setter. */
function resolvePath(body: Amf0Element[], path: string): LeafRef | null {
  const segs = path.split("/").map(decodeSeg);
  if (segs.length === 0) return null;

  // First segment indexes into the body's top-level elements (by name).
  const first = segs[0];
  if (first === undefined) return null;
  const topIdx = body.findIndex((e) => e.name === first);
  if (topIdx === -1) return null;

  let current: Amf0Value = body[topIdx]!.value;
  let set: (next: Amf0Value) => void = (next) => {
    body[topIdx]!.value = next;
  };

  for (let i = 1; i < segs.length; i++) {
    const seg = segs[i];
    if (seg === undefined) return null;
    if (current.kind === "object" || current.kind === "typedObject" || current.kind === "ecmaArray") {
      const entries = current.entries;
      const idx = entries.findIndex((e) => e.name === seg);
      if (idx === -1) return null;
      current = entries[idx]!.value;
      set = (next) => {
        entries[idx]!.value = next;
      };
    } else if (current.kind === "strictArray") {
      const items = current.items;
      const k = Number.parseInt(seg, 10);
      if (!Number.isInteger(k) || k < 0 || k >= items.length) return null;
      current = items[k]!;
      set = (next) => {
        items[k] = next;
      };
    } else {
      return null; // cannot descend into a primitive
    }
  }
  return { current, set };
}

/** Coerce a user-supplied value to the AST leaf's existing kind. Throws on type mismatch. */
function coerceEdit(current: Amf0Value, raw: string | number | boolean | null): Amf0Value {
  switch (current.kind) {
    case "number": {
      const n = typeof raw === "number" ? raw : Number(raw);
      if (!Number.isFinite(n)) throw new Error(`不是有效数字: ${String(raw)}`);
      return { kind: "number", value: n };
    }
    case "boolean": {
      let b: boolean;
      if (typeof raw === "boolean") b = raw;
      else if (typeof raw === "string") b = raw.trim().toLowerCase() === "true" || raw.trim() === "1";
      else b = Boolean(raw);
      return { kind: "boolean", value: b };
    }
    case "string": {
      const s = raw === null ? "" : String(raw);
      return { kind: "string", value: s, long: current.long };
    }
    default:
      throw new Error(`不可编辑的类型: ${current.kind}`);
  }
}

function displayLeaf(v: Amf0Value): string {
  const pv = primitiveValue(v);
  if (pv === undefined) return `<${v.kind}>`;
  return typeof pv === "string" ? pv : String(pv);
}

export interface ApplyEditsOutcome {
  ok: boolean;
  diff: SolDiffLine[];
}

/**
 * Apply edits in place onto a freshly-read SolFile's body. Returns a per-edit
 * diff. Mutates `sol.body`. An individual bad path produces a diff line with
 * `error` set but does not abort the others.
 */
export function applyEdits(sol: SolFile, edits: SolEdit[]): ApplyEditsOutcome {
  const diff: SolDiffLine[] = [];
  let ok = true;
  for (const edit of edits) {
    const ref = resolvePath(sol.body, edit.path);
    if (!ref) {
      ok = false;
      diff.push({ path: edit.path, oldValue: "", newValue: String(edit.value), error: "找不到该路径" });
      continue;
    }
    if (!isEditable(ref.current)) {
      ok = false;
      diff.push({
        path: edit.path,
        oldValue: displayLeaf(ref.current),
        newValue: String(edit.value),
        error: `不可编辑 (${ref.current.kind})`,
      });
      continue;
    }
    const oldValue = displayLeaf(ref.current);
    try {
      const next = coerceEdit(ref.current, edit.value);
      ref.set(next);
      diff.push({ path: edit.path, oldValue, newValue: displayLeaf(next) });
    } catch (err) {
      ok = false;
      diff.push({ path: edit.path, oldValue, newValue: String(edit.value), error: String(err) });
    }
  }
  return { ok, diff };
}
