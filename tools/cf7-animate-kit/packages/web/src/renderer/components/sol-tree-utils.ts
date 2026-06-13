import type { SolTreeNode, SolNodeKind } from "../../shared/ipc-types.js";

/**
 * Node kinds that hold children (vs. editable/leaf primitives). Mirrors the
 * an-host projection so the renderer can decide "container vs leaf" locally.
 */
export const CONTAINER_KINDS: ReadonlyArray<SolNodeKind> = [
  "root", "object", "typedObject", "ecmaArray", "strictArray"
];

export function isContainerKind(kind: SolNodeKind): boolean {
  return CONTAINER_KINDS.indexOf(kind) !== -1;
}

export function isContainerNode(node: SolTreeNode): boolean {
  return (Array.isArray(node.children) && node.children.length > 0) || isContainerKind(node.kind);
}

/**
 * Short type badge label + colour family per node kind. Kept coarse so the
 * legend stays readable; the precise typeLabel ("string (long)") is shown
 * separately in the row.
 */
export interface BadgeSpec {
  short: string;
  family: BadgeFamily;
}

export type BadgeFamily =
  | "object" | "array" | "number" | "string" | "boolean"
  | "null" | "date" | "xml" | "other";

export function badgeFor(kind: SolNodeKind): BadgeSpec {
  switch (kind) {
    case "root": return { short: "root", family: "object" };
    case "object": return { short: "obj", family: "object" };
    case "typedObject": return { short: "type", family: "object" };
    case "ecmaArray": return { short: "ecma", family: "array" };
    case "strictArray": return { short: "arr", family: "array" };
    case "number": return { short: "num", family: "number" };
    case "string": return { short: "str", family: "string" };
    case "boolean": return { short: "bool", family: "boolean" };
    case "null": return { short: "null", family: "null" };
    case "undefined": return { short: "undef", family: "null" };
    case "date": return { short: "date", family: "date" };
    case "xml": return { short: "xml", family: "xml" };
    case "reference": return { short: "ref", family: "other" };
    case "unsupported":
    default: return { short: "?", family: "other" };
  }
}

/** Colours used by both the badges and the treemap (by family). */
export const FAMILY_PALETTE: Record<BadgeFamily, string> = {
  object: "#3498db",
  array: "#9b59b6",
  number: "#2ecc71",
  string: "#e8d5b8",
  boolean: "#1abc9c",
  null: "#7f8fa6",
  date: "#e67e22",
  xml: "#f39c12",
  other: "#e74c3c"
};

/** Number of editable/leaf descendants under `node` (>=1 for a leaf itself). */
export function leafCount(node: SolTreeNode): number {
  if (!node.children || node.children.length === 0) return 1;
  let total = 0;
  for (const child of node.children) total += leafCount(child);
  return total;
}

/** Total descendant node count (containers + leaves), excluding `node`. */
export function descendantCount(node: SolTreeNode): number {
  if (!node.children || node.children.length === 0) return 0;
  let total = 0;
  for (const child of node.children) total += 1 + descendantCount(child);
  return total;
}

// ---------------------------------------------------------------------------
// d3 hierarchy projection — value = subtree leaf-count
// ---------------------------------------------------------------------------

export interface SolHierNode {
  /** Display name (key, or "(root)"). */
  name: string;
  /** Canonical path (for tooltip / focus). */
  path: string;
  kind: SolNodeKind;
  family: BadgeFamily;
  /** Leaf count assigned at the leaf level; containers aggregate via d3 .sum(). */
  value: number;
  children?: SolHierNode[];
}

/**
 * Project the SOL tree into a shape d3.hierarchy can consume, where each leaf
 * carries value=1 and containers derive their size from the sum of descendant
 * leaves. A synthetic "(root)" wraps the top-level nodes.
 */
export function buildSolHierarchy(tree: SolTreeNode[]): SolHierNode {
  return {
    name: "(root)",
    path: "",
    kind: "root",
    family: "object",
    value: 0,
    children: tree.map(toHier)
  };
}

function toHier(node: SolTreeNode): SolHierNode {
  const badge = badgeFor(node.kind);
  const name = node.key === "" ? "(root)" : node.key;
  if (node.children && node.children.length > 0) {
    return {
      name,
      path: node.path,
      kind: node.kind,
      family: badge.family,
      value: 0,
      children: node.children.map(toHier)
    };
  }
  return {
    name,
    path: node.path,
    kind: node.kind,
    family: badge.family,
    value: 1
  };
}

// ---------------------------------------------------------------------------
// Filtering
// ---------------------------------------------------------------------------

export interface FilterResult {
  /** Paths that match the query directly. */
  matched: Set<string>;
  /** Paths on the ancestor chain of a match (kept visible + expanded). */
  ancestors: Set<string>;
}

/**
 * Case-insensitive substring filter over keys and stringified values. Returns
 * the set of matching paths plus their ancestor paths (so a match deep in the
 * tree stays reachable). Empty query => empty sets (caller treats as "show all").
 */
export function filterTree(tree: SolTreeNode[], rawQuery: string): FilterResult {
  const query = rawQuery.trim().toLowerCase();
  const matched = new Set<string>();
  const ancestors = new Set<string>();
  if (!query) return { matched, ancestors };

  const visit = (node: SolTreeNode, chain: string[]): boolean => {
    const valueText = node.value === undefined ? "" : String(node.value).toLowerCase();
    const selfMatch =
      node.key.toLowerCase().indexOf(query) !== -1 ||
      valueText.indexOf(query) !== -1 ||
      node.typeLabel.toLowerCase().indexOf(query) !== -1;

    let childMatch = false;
    if (node.children) {
      const nextChain = chain.concat(node.path);
      for (const child of node.children) {
        if (visit(child, nextChain)) childMatch = true;
      }
    }

    if (selfMatch) matched.add(node.path);
    if (selfMatch || childMatch) {
      for (const ancestorPath of chain) ancestors.add(ancestorPath);
      return true;
    }
    return false;
  };

  for (const node of tree) visit(node, []);
  return { matched, ancestors };
}
