import { useState, useEffect, useRef } from "react";
import type { SolTreeNode } from "../../shared/ipc-types.js";
import { badgeFor, isContainerNode } from "./sol-tree-utils.js";

interface Props {
  node: SolTreeNode;
  depth: number;
  /** Pending edits map: path -> new raw value (string|number|boolean|null). */
  edits: Map<string, string | number | boolean | null>;
  onEdit: (path: string, value: string | number | boolean | null) => void;
  /** Selecting any row reports its path (drives treemap highlight + focus). */
  onSelect?: (path: string) => void;
  /** Currently selected/focused path. */
  focusPath?: string | null;
  /** Lowercased active filter query (""/undefined = no filter). */
  query?: string;
  /** Paths that matched the filter directly. */
  matched?: Set<string>;
  /** Ancestor paths of matches (kept visible, force-expanded). */
  ancestors?: Set<string>;
  /** Monotonic counter: bump to expand all; negative parity collapses all. */
  expandSignal?: number;
}

function displayValue(node: SolTreeNode): string {
  if (node.value === undefined) return "";
  return typeof node.value === "string" ? node.value : String(node.value);
}

/** One collapsible AMF0 node with a type badge and inline editor for leaves. */
export default function SolTreeView({
  node, depth, edits, onEdit, onSelect, focusPath, query, matched, ancestors, expandSignal
}: Props) {
  const hasChildren = Array.isArray(node.children) && node.children.length > 0;
  const isContainer = isContainerNode(node);
  const [open, setOpen] = useState(depth < 1);
  const rowRef = useRef<HTMLDivElement>(null);

  const filtering = Boolean(query);
  const isMatch = matched?.has(node.path) ?? false;
  const onAncestorPath = ancestors?.has(node.path) ?? false;

  // Expand/collapse-all signal: even = expand, odd = collapse.
  useEffect(() => {
    if (expandSignal === undefined) return;
    setOpen(expandSignal % 2 === 0);
  }, [expandSignal]);

  // Auto-expand ancestors of matches while filtering.
  useEffect(() => {
    if (filtering && onAncestorPath) setOpen(true);
  }, [filtering, onAncestorPath]);

  // Scroll the focused row into view.
  const isFocus = focusPath != null && focusPath === node.path;
  useEffect(() => {
    if (isFocus && rowRef.current) {
      rowRef.current.scrollIntoView({ block: "nearest" });
    }
  }, [isFocus]);

  // While filtering, hide branches with no match in their subtree.
  if (filtering && !isMatch && !onAncestorPath) return null;

  const edited = edits.has(node.path);
  const editedValue = edited ? edits.get(node.path)! : undefined;
  const badge = badgeFor(node.kind);

  const rowClass = [
    "sol-row",
    edited ? "sol-row-edited" : "",
    isFocus ? "sol-row-focus" : "",
    filtering && isMatch ? "sol-row-match" : ""
  ].filter(Boolean).join(" ");

  return (
    <div className="sol-node" style={{ paddingLeft: depth === 0 ? 0 : 12 }}>
      <div
        ref={rowRef}
        className={rowClass}
        onClick={() => onSelect?.(node.path)}
      >
        {isContainer ? (
          <button
            className="sol-toggle"
            onClick={(e) => { e.stopPropagation(); setOpen((o) => !o); }}
            aria-label={open ? "collapse" : "expand"}
          >
            {open ? "▾" : "▸"}
          </button>
        ) : (
          <span className="sol-toggle sol-toggle-leaf" />
        )}

        <span className={`sol-badge sol-badge-${badge.family}`} title={node.typeLabel}>
          {badge.short}
        </span>

        <span className="sol-key" title={node.path}>
          {node.key === "" ? "(root)" : node.key}
        </span>
        <span className="sol-type">{node.typeLabel}</span>

        {!isContainer && (
          <span className="sol-value-cell" onClick={(e) => e.stopPropagation()}>
            {node.editable ? (
              node.kind === "boolean" ? (
                <select
                  className="sol-input sol-input-bool"
                  value={String(editedValue ?? node.value)}
                  onChange={(e) => onEdit(node.path, e.target.value === "true")}
                >
                  <option value="true">true</option>
                  <option value="false">false</option>
                </select>
              ) : (
                <input
                  className="sol-input"
                  type={node.kind === "number" ? "number" : "text"}
                  value={editedValue !== undefined ? String(editedValue) : displayValue(node)}
                  onChange={(e) =>
                    onEdit(
                      node.path,
                      node.kind === "number"
                        ? e.target.value === ""
                          ? ""
                          : Number(e.target.value)
                        : e.target.value
                    )
                  }
                />
              )
            ) : (
              <span className="sol-readonly" title="只读 (引用/复杂/空值)">
                {displayValue(node) || "—"}
              </span>
            )}
          </span>
        )}
      </div>

      {isContainer && open && hasChildren && (
        <div className="sol-children">
          {node.children!.map((child) => (
            <SolTreeView
              key={child.path}
              node={child}
              depth={depth + 1}
              edits={edits}
              onEdit={onEdit}
              {...(onSelect ? { onSelect } : {})}
              focusPath={focusPath ?? null}
              {...(query !== undefined ? { query } : {})}
              {...(matched ? { matched } : {})}
              {...(ancestors ? { ancestors } : {})}
              {...(expandSignal !== undefined ? { expandSignal } : {})}
            />
          ))}
        </div>
      )}
    </div>
  );
}
