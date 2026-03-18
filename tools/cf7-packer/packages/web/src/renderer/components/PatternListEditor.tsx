import { useState, useCallback } from "react";

interface PatternListEditorProps {
  patterns: string[];
  onAdd: (pattern: string) => void;
  onRemove: (index: number) => void;
  disabled?: boolean | undefined;
  placeholder?: string | undefined;
}

export default function PatternListEditor({
  patterns, onAdd, onRemove, disabled, placeholder
}: PatternListEditorProps) {
  const [draft, setDraft] = useState("");

  const handleAdd = useCallback(() => {
    const trimmed = draft.trim();
    if (!trimmed) return;
    onAdd(trimmed);
    setDraft("");
  }, [draft, onAdd]);

  const handleKeyDown = useCallback((e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      handleAdd();
    }
  }, [handleAdd]);

  return (
    <div className="pattern-list">
      {patterns.map((p, i) => (
        <div key={`${i}-${p}`} className="pattern-item">
          <span className="pattern-text">{p}</span>
          {!disabled && (
            <button
              className="pattern-remove"
              onClick={() => onRemove(i)}
              title="移除"
            >
              x
            </button>
          )}
        </div>
      ))}
      {!disabled && (
        <div className="pattern-add-row">
          <input
            className="pattern-input"
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder={placeholder ?? "输入 glob 模式，回车添加"}
          />
          <button
            className="btn-small pattern-add-btn"
            onClick={handleAdd}
            disabled={!draft.trim()}
          >
            +
          </button>
        </div>
      )}
    </div>
  );
}
