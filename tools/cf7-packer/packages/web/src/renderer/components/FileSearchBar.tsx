import { useState, useMemo, useRef, useEffect } from "react";
import type { FileEntry } from "../../shared/ipc-types.js";
import { formatSize } from "./tree-utils.js";

interface Props {
  files: FileEntry[];
}

const LAYER_COLORS: Record<string, string> = {
  data: "#3498db",
  scripts: "#2ecc71",
  flashswf: "#e67e22",
  sounds: "#9b59b6",
  config: "#1abc9c",
  "root-files": "#e74c3c",
  "root-dirs": "#f39c12"
};

export default function FileSearchBar({ files }: Props) {
  const [query, setQuery] = useState("");
  const [debouncedQuery, setDebouncedQuery] = useState("");
  const timerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => setDebouncedQuery(query), 200);
    return () => clearTimeout(timerRef.current);
  }, [query]);

  const results = useMemo(() => {
    if (!debouncedQuery || debouncedQuery.length < 2) return [];
    const q = debouncedQuery.toLowerCase();
    const matched: FileEntry[] = [];
    for (const f of files) {
      if (f.path.toLowerCase().includes(q)) {
        matched.push(f);
        if (matched.length >= 100) break;
      }
    }
    return matched;
  }, [files, debouncedQuery]);

  return (
    <div className="file-search">
      <div className="file-search-input-row">
        <span className="file-search-icon">🔍</span>
        <input
          type="text"
          placeholder="搜索文件名或路径..."
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          className="file-search-input"
        />
        {query && (
          <button className="file-search-clear" onClick={() => setQuery("")}>✕</button>
        )}
      </div>
      {debouncedQuery.length >= 2 && (
        <div className="file-search-results">
          <div className="file-search-count">
            {results.length >= 100 ? "100+ 条结果" : `${results.length} 条结果`}
          </div>
          {results.map((f) => (
            <div key={f.path} className="file-search-item">
              <span
                className="file-search-layer"
                style={{ background: LAYER_COLORS[f.layer] ?? "#555" }}
              >
                {f.layer}
              </span>
              <span className="file-search-path">{highlightMatch(f.path, debouncedQuery)}</span>
              <span className="file-search-size">{formatSize(f.size ?? 0)}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function highlightMatch(text: string, query: string): React.ReactNode {
  const lower = text.toLowerCase();
  const idx = lower.indexOf(query.toLowerCase());
  if (idx < 0) return text;
  return (
    <>
      {text.slice(0, idx)}
      <mark className="file-search-highlight">{text.slice(idx, idx + query.length)}</mark>
      {text.slice(idx + query.length)}
    </>
  );
}
