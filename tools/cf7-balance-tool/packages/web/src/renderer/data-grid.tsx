import { useCallback, useEffect, useRef, useState, type ChangeEvent } from "react";
import { isRowChanged, type EditorRow } from "./editor-model";

export type SortKey =
  | "file"
  | "xmlPath"
  | "before"
  | "suggested"
  | "staged"
  | "line";
export type SortDir = "asc" | "desc";

export interface DataGridProps {
  rows: EditorRow[];
  selectedRowId: string | undefined;
  sortKey: SortKey;
  sortDir: SortDir;
  onSelect: (rowId: string) => void;
  onValueChange: (rowId: string, value: string) => void;
  onSortChange: (key: SortKey) => void;
}

const HEADERS: Array<{ key: SortKey; label: string; width: string }> = [
  { key: "file", label: "文件", width: "18%" },
  { key: "xmlPath", label: "路径", width: "22%" },
  { key: "line", label: "行", width: "5%" },
  { key: "before", label: "原值", width: "15%" },
  { key: "suggested", label: "建议值", width: "15%" },
  { key: "staged", label: "暂存值", width: "25%" }
];

export function sortRows(
  rows: EditorRow[],
  key: SortKey,
  dir: SortDir
): EditorRow[] {
  const sorted = [...rows];
  const mul = dir === "asc" ? 1 : -1;

  sorted.sort((a, b) => {
    let cmp = 0;
    switch (key) {
      case "file":
        cmp = a.sourceFile.localeCompare(b.sourceFile);
        break;
      case "xmlPath":
        cmp = a.xmlPath.localeCompare(b.xmlPath);
        break;
      case "line":
        cmp = a.sourceLine - b.sourceLine;
        break;
      case "before":
        cmp = compareValues(a.beforeValue, b.beforeValue);
        break;
      case "suggested":
        cmp = compareValues(a.suggestedValue, b.suggestedValue);
        break;
      case "staged":
        cmp = compareValues(a.stagedValue, b.stagedValue);
        break;
    }
    return cmp * mul;
  });

  return sorted;
}

export function DataGrid({
  rows,
  selectedRowId,
  sortKey,
  sortDir,
  onSelect,
  onValueChange,
  onSortChange
}: DataGridProps) {
  const PAGE_SIZE = 100;
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);
  const visibleRows = rows.slice(0, visibleCount);
  const hasMore = visibleCount < rows.length;

  return (
    <div className="datagrid-wrapper">
      <table className="datagrid">
        <thead>
          <tr>
            {HEADERS.map((h) => (
              <th
                key={h.key}
                style={{ width: h.width }}
                onClick={() => onSortChange(h.key)}
                className={sortKey === h.key ? "datagrid-th-active" : ""}
              >
                {h.label}
                {sortKey === h.key && (
                  <span className="datagrid-sort-icon">
                    {sortDir === "asc" ? " ▲" : " ▼"}
                  </span>
                )}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {visibleRows.map((row) => (
            <DataGridRow
              key={row.id}
              row={row}
              selected={row.id === selectedRowId}
              onSelect={onSelect}
              onValueChange={onValueChange}
            />
          ))}
        </tbody>
      </table>
      {hasMore && (
        <button
          className="datagrid-load-more"
          onClick={() => setVisibleCount((c) => c + PAGE_SIZE)}
          type="button"
        >
          加载更多 ({rows.length - visibleCount} 剩余)
        </button>
      )}
      <div className="datagrid-footer">
        共 {rows.length} 行
        {visibleCount < rows.length && ` (显示 ${visibleCount})`}
      </div>
    </div>
  );
}

function DataGridRow({
  row,
  selected,
  onSelect,
  onValueChange
}: {
  row: EditorRow;
  selected: boolean;
  onSelect: (rowId: string) => void;
  onValueChange: (rowId: string, value: string) => void;
}) {
  const changed = isRowChanged(row);
  const inputRef = useRef<HTMLInputElement>(null);
  const [localValue, setLocalValue] = useState(row.stagedValue);
  const [editing, setEditing] = useState(false);

  // Sync external changes when not actively editing
  useEffect(() => {
    if (!editing) {
      setLocalValue(row.stagedValue);
    }
  }, [row.stagedValue, editing]);

  const handleChange = useCallback(
    (e: ChangeEvent<HTMLInputElement>) => {
      setLocalValue(e.currentTarget.value);
    },
    []
  );

  const handleFocus = useCallback(() => {
    setEditing(true);
  }, []);

  const handleBlur = useCallback(() => {
    setEditing(false);
    if (localValue !== row.stagedValue) {
      onValueChange(row.id, localValue);
    }
  }, [localValue, row.stagedValue, row.id, onValueChange]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent<HTMLInputElement>) => {
      if (e.key === "Enter") {
        inputRef.current?.blur();
      }
      if (e.key === "Escape") {
        setLocalValue(row.stagedValue);
        setEditing(false);
        inputRef.current?.blur();
      }
      // Stop Ctrl+Z/Y from propagating to global undo when editing
      if ((e.key === "z" || e.key === "y") && (e.ctrlKey || e.metaKey)) {
        e.stopPropagation();
      }
    },
    [row.stagedValue]
  );

  const shortFile = shortenFile(row.sourceFile);
  const pathLabel = row.attribute
    ? `${row.xmlPath}@${row.attribute}`
    : row.xmlPath;

  return (
    <tr
      className={`datagrid-row ${selected ? "datagrid-row-selected" : ""} ${changed ? "datagrid-row-changed" : ""}`}
      onClick={() => onSelect(row.id)}
    >
      <td className="datagrid-cell-file" title={row.sourceFile}>
        {shortFile}
      </td>
      <td className="datagrid-cell-path" title={pathLabel}>
        {pathLabel}
      </td>
      <td className="datagrid-cell-line">{row.sourceLine}</td>
      <td className="datagrid-cell-value">{row.beforeValue}</td>
      <td
        className={`datagrid-cell-value ${
          row.suggestedValue !== row.beforeValue
            ? "datagrid-cell-diff"
            : ""
        }`}
      >
        {row.suggestedValue}
      </td>
      <td className="datagrid-cell-staged" onClick={(e) => e.stopPropagation()}>
        <input
          ref={inputRef}
          className="datagrid-input"
          value={editing ? localValue : row.stagedValue}
          onChange={handleChange}
          onFocus={handleFocus}
          onBlur={handleBlur}
          onKeyDown={handleKeyDown}
        />
      </td>
    </tr>
  );
}

function compareValues(a: string, b: string): number {
  const numA = Number(a);
  const numB = Number(b);

  if (!Number.isNaN(numA) && !Number.isNaN(numB)) {
    return numA - numB;
  }

  return a.localeCompare(b);
}

function shortenFile(path: string): string {
  const normalized = path.replaceAll("\\", "/");
  const lastSlash = normalized.lastIndexOf("/");
  return lastSlash >= 0 ? normalized.slice(lastSlash + 1) : normalized;
}
