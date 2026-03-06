import { useCallback, useEffect, useMemo, useState } from "react";

type FieldType =
  | "numericFields"
  | "stringFields"
  | "booleanFields"
  | "passthroughFields"
  | "nestedNumericFields"
  | "itemLevelFields"
  | "attributeFields"
  | "computedFields"
  | "numericSuffixes";

const FIELD_TYPE_LABELS: Record<FieldType, string> = {
  numericFields: "数值",
  stringFields: "字符串",
  booleanFields: "布尔",
  passthroughFields: "透传",
  nestedNumericFields: "嵌套数值",
  itemLevelFields: "等级字段",
  attributeFields: "属性",
  computedFields: "计算",
  numericSuffixes: "数值后缀",
};

const FIELD_TYPES = Object.keys(FIELD_TYPE_LABELS) as FieldType[];

interface FlatEntry {
  field: string;
  type: FieldType;
}

function flattenConfig(config: FieldRegistryData): FlatEntry[] {
  const entries: FlatEntry[] = [];
  for (const ft of FIELD_TYPES) {
    const arr = config[ft];
    if (!Array.isArray(arr)) continue;
    for (const field of arr) {
      entries.push({ field, type: ft });
    }
  }
  entries.sort((a, b) => a.field.localeCompare(b.field));
  return entries;
}

export function FieldConfigPanel() {
  const [config, setConfig] = useState<FieldRegistryData | null>(null);
  const [loading, setLoading] = useState(false);
  const [filterText, setFilterText] = useState("");
  const [filterType, setFilterType] = useState<FieldType | "">("");
  const [newField, setNewField] = useState("");
  const [newType, setNewType] = useState<FieldType>("numericFields");
  const [dirty, setDirty] = useState(false);

  const canLoad = typeof window.cf7Balance?.getFieldConfig === "function";
  const canSave = typeof window.cf7Balance?.saveFieldConfig === "function";

  const loadConfig = useCallback(async () => {
    if (!window.cf7Balance?.getFieldConfig) return;
    setLoading(true);
    try {
      const data = await window.cf7Balance.getFieldConfig();
      setConfig(data);
      setDirty(false);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (canLoad) void loadConfig();
  }, [canLoad, loadConfig]);

  const entries = useMemo(() => (config ? flattenConfig(config) : []), [config]);

  const filtered = useMemo(() => {
    let list = entries;
    if (filterText) {
      const lower = filterText.toLowerCase();
      list = list.filter((e) => e.field.toLowerCase().includes(lower));
    }
    if (filterType) {
      list = list.filter((e) => e.type === filterType);
    }
    return list;
  }, [entries, filterText, filterType]);

  const stats = useMemo(() => {
    const counts: Partial<Record<FieldType, number>> = {};
    for (const e of entries) {
      counts[e.type] = (counts[e.type] ?? 0) + 1;
    }
    return counts;
  }, [entries]);

  const handleAdd = useCallback(() => {
    if (!config || !newField.trim()) return;
    const field = newField.trim();
    // Check if already exists
    if (config[newType].includes(field)) return;
    const updated = { ...config, [newType]: [...config[newType], field] };
    setConfig(updated);
    setNewField("");
    setDirty(true);
  }, [config, newField, newType]);

  const handleRemove = useCallback(
    (field: string, type: FieldType) => {
      if (!config) return;
      const updated = {
        ...config,
        [type]: config[type].filter((f: string) => f !== field),
      };
      setConfig(updated);
      setDirty(true);
    },
    [config]
  );

  const handleChangeType = useCallback(
    (field: string, oldType: FieldType, newType: FieldType) => {
      if (!config || oldType === newType) return;
      const updated = {
        ...config,
        [oldType]: config[oldType].filter((f: string) => f !== field),
        [newType]: [...config[newType], field],
      };
      setConfig(updated);
      setDirty(true);
    },
    [config]
  );

  const handleSave = useCallback(async () => {
    if (!config || !window.cf7Balance?.saveFieldConfig) return;
    await window.cf7Balance.saveFieldConfig(config);
    setDirty(false);
  }, [config]);

  return (
    <section className="detail-section">
      <div className="detail-section-header history-header">
        <div>
          <h4>字段分类管理</h4>
          <p className="panel-caption">
            管理 field-config.json 中的字段分类
          </p>
        </div>
        <div style={{ display: "flex", gap: "0.4rem" }}>
          <button
            className="mini-button"
            disabled={!canLoad || loading}
            onClick={() => void loadConfig()}
            type="button"
          >
            刷新
          </button>
          {dirty && (
            <button
              className="mini-button"
              disabled={!canSave}
              onClick={() => void handleSave()}
              type="button"
            >
              保存
            </button>
          )}
        </div>
      </div>

      {config == null ? (
        <div className="empty-state">
          {loading ? "加载中..." : "点击刷新加载字段配置"}
        </div>
      ) : (
        <>
          <div className="plugin-crud-stats">
            <span>共 {entries.length} 字段</span>
            {FIELD_TYPES.filter((t) => stats[t]).map((t) => (
              <span key={t}>
                {FIELD_TYPE_LABELS[t]}: {stats[t]}
              </span>
            ))}
          </div>

          <div className="plugin-crud-add-form">
            <input
              className="plugin-crud-input"
              placeholder="新字段名..."
              value={newField}
              onChange={(e) => setNewField(e.currentTarget.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") handleAdd();
              }}
            />
            <select
              className="plugin-crud-select"
              value={newType}
              onChange={(e) => setNewType(e.currentTarget.value as FieldType)}
            >
              {FIELD_TYPES.map((t) => (
                <option key={t} value={t}>
                  {FIELD_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
            <button
              className="mini-button"
              onClick={handleAdd}
              disabled={!newField.trim()}
              type="button"
            >
              添加
            </button>
          </div>

          <div className="plugin-crud-filter">
            <input
              className="plugin-crud-input"
              placeholder="搜索字段..."
              value={filterText}
              onChange={(e) => setFilterText(e.currentTarget.value)}
            />
            <select
              className="plugin-crud-select"
              value={filterType}
              onChange={(e) => setFilterType(e.currentTarget.value as FieldType | "")}
            >
              <option value="">全部类型</option>
              {FIELD_TYPES.map((t) => (
                <option key={t} value={t}>
                  {FIELD_TYPE_LABELS[t]}
                </option>
              ))}
            </select>
          </div>

          <div className="plugin-crud-list">
            {filtered.slice(0, 200).map((entry) => (
              <div className="plugin-crud-row" key={`${entry.type}-${entry.field}`}>
                <span className="plugin-crud-field" title={entry.field}>
                  {entry.field}
                </span>
                <select
                  className="plugin-crud-select"
                  value={entry.type}
                  onChange={(e) =>
                    handleChangeType(entry.field, entry.type, e.currentTarget.value as FieldType)
                  }
                  style={{ fontSize: "0.72rem", padding: "0.1rem 0.2rem" }}
                >
                  {FIELD_TYPES.map((t) => (
                    <option key={t} value={t}>
                      {FIELD_TYPE_LABELS[t]}
                    </option>
                  ))}
                </select>
                <div className="plugin-crud-actions">
                  <button
                    className="plugin-crud-btn plugin-crud-btn-danger"
                    onClick={() => handleRemove(entry.field, entry.type)}
                    type="button"
                  >
                    删除
                  </button>
                </div>
              </div>
            ))}
            {filtered.length > 200 && (
              <div className="empty-state">
                显示前200项，共 {filtered.length} 项。请使用搜索缩小范围。
              </div>
            )}
          </div>
        </>
      )}
    </section>
  );
}
