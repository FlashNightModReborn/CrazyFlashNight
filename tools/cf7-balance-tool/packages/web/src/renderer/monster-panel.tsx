import { useCallback, useEffect, useState } from "react";
import {
  buildMonsterCsvText,
  countMonsterChanges,
  createMonsterRows,
  isEditableColumn,
  isMonsterRowChanged,
  parseMonsterCsv,
  revertMonsterRow,
  updateMonsterCell,
  type MonsterRowState
} from "./monster-table-model";

type TableKey = "full" | "outOfRange" | "highError" | "human";
type BusyAction = "load" | "refresh" | "save" | "applyDry" | "applyWrite" | "solve" | null;

const TABLE_TABS: { key: TableKey; label: string; editable: boolean }[] = [
  { key: "full", label: "全量表（可改）", editable: true },
  { key: "outOfRange", label: "超范围表", editable: false },
  { key: "highError", label: "偏差大表", editable: false },
  { key: "human", label: "人工表", editable: false }
];

export function MonsterPanel() {
  const [tables, setTables] = useState<MonsterTablesResult | undefined>();
  const [activeTab, setActiveTab] = useState<TableKey>("full");
  const [editRows, setEditRows] = useState<MonsterRowState[]>([]);
  const [busy, setBusy] = useState<BusyAction>(null);
  const [log, setLog] = useState("");
  const [solveTemplate, setSolveTemplate] = useState("");
  const [writeArmed, setWriteArmed] = useState(false);

  const bridge = window.cf7Balance;
  const available = typeof bridge?.monsterGetTables === "function";

  const loadTables = useCallback(async () => {
    if (!bridge?.monsterGetTables) return;
    const result = await bridge.monsterGetTables();
    setTables(result);
    if (result.full.exists) {
      // 盘上现值是写回基准：任何重读（含保存/普查后回读）都以盘上为准重置，
      // 避免已落盘或已过期的暂存格继续冒充变更。
      setEditRows(createMonsterRows(result.full.rows));
    }
  }, [bridge]);

  useEffect(() => {
    if (available) {
      setBusy("load");
      void loadTables().catch((e) => setLog(String(e))).finally(() => setBusy(null));
    }
  }, [available, loadTables]);

  if (!available) {
    return (
      <article className="panel">
        <div className="panel-header">
          <p>怪物标识</p>
          <h3>Electron 桥未连接</h3>
        </div>
        <p className="report-note">渲染器预览模式下怪物工作流不可用，需以 Electron 桌面模式启动。</p>
      </article>
    );
  }

  const activeTable = tables?.[activeTab];
  const headers = activeTable?.headers ?? [];
  const changes = countMonsterChanges(editRows);

  function handleCellChange(rowId: string, colIndex: number, value: string): void {
    const header = headers[colIndex] ?? "";
    setEditRows((current) => {
      const { rows, error } = updateMonsterCell(current, headers, rowId, colIndex, value);
      if (error) setLog(`单元格校验失败 [${header}]: ${error}`);
      return rows;
    });
  }

  async function runAction(action: BusyAction, fn: () => Promise<{ output?: string } | void>): Promise<void> {
    setBusy(action);
    try {
      const result = await fn();
      if (result && "output" in result && result.output) {
        setLog(result.output);
      }
      await loadTables();
    } catch (e) {
      setLog(String(e));
    } finally {
      setBusy(null);
      setWriteArmed(false);
    }
  }

  const handleRefresh = () => runAction("refresh", () => bridge.monsterRefresh!());
  const handleSaveTable = () => runAction("save", async () => {
    const text = buildMonsterCsvText(headers, editRows);
    const parsed = parseMonsterCsv(text);
    await bridge.monsterSaveTable!({ headers: parsed.headers, rows: parsed.rows });
  });
  const handleApplyDry = () => runAction("applyDry", () => bridge.monsterTableApply!({ write: false }));
  const handleApplyWrite = () => {
    if (!writeArmed) {
      setWriteArmed(true);
      setLog("写回将直接修改 data/enemy_properties/*.xml 的 <标识> 块。再点一次确认执行。");
      return;
    }
    return runAction("applyWrite", () => bridge.monsterTableApply!({ write: true }));
  };
  const handleSolve = () => runAction("solve", () => bridge.monsterSolve!({ template: solveTemplate.trim() }));

  return (
    <article className="panel">
      <div className="panel-header">
        <p>怪物标识</p>
        <h3>四张查验表与 CLI 工作流</h3>
      </div>
      <p className="report-note">
        全量表是唯一可改面：空格=该项不改，填数=按填的写；阶段=0 是整行排除标记。
        写回只动 data/enemy_properties 各模板的 &lt;标识&gt; 块。
      </p>

      <div className="monster-tabs">
        {TABLE_TABS.map((tab) => (
          <button
            key={tab.key}
            type="button"
            className={`monster-tab ${activeTab === tab.key ? "monster-tab-active" : ""}`}
            onClick={() => setActiveTab(tab.key)}
          >
            {tab.label}
            <span className="monster-tab-count">
              {tables?.[tab.key]?.exists ? `${tables[tab.key].rows.length}行` : "未生成"}
            </span>
          </button>
        ))}
      </div>

      {activeTable && !activeTable.exists && (
        <p className="report-note">该表尚未生成：先跑「刷新普查」产出 reports/monster-flag-census.json + 四张表。</p>
      )}

      {activeTab === "full" && editRows.length > 0 && (
        <div className="monster-table-wrap">
          <table className="monster-table">
            <thead>
              <tr>
                <th className="monster-rownum">#</th>
                {headers.map((h, i) => (
                  <th key={i} className={isEditableColumn(h) ? "monster-col-edit" : ""}>{h}</th>
                ))}
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {editRows.map((row, ri) => (
                <tr key={row.id} className={isMonsterRowChanged(row) ? "monster-row-changed" : ""}>
                  <td className="monster-rownum">{ri + 1}</td>
                  {headers.map((h, ci) => {
                    const editable = isEditableColumn(h);
                    const val = row.cells[ci] ?? "";
                    const orig = row.original[ci] ?? "";
                    return (
                      <td key={ci} className={editable && val !== orig ? "monster-cell-changed" : ""}>
                        {editable ? (
                          <input
                            className="monster-cell-input"
                            value={val}
                            onChange={(e) => handleCellChange(row.id, ci, e.currentTarget.value)}
                            title={orig !== val ? `原值: ${orig}` : ""}
                          />
                        ) : (
                          <span className="monster-cell-read">{val}</span>
                        )}
                      </td>
                    );
                  })}
                  <td>
                    {isMonsterRowChanged(row) && (
                      <button type="button" className="monster-revert" onClick={() => setEditRows((c) => revertMonsterRow(c, row.id))}>
                        回退
                      </button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {activeTab !== "full" && activeTable && activeTable.exists && (
        <div className="monster-table-wrap">
          <table className="monster-table">
            <thead>
              <tr>
                <th className="monster-rownum">#</th>
                {activeTable.headers.map((h, i) => <th key={i}>{h}</th>)}
              </tr>
            </thead>
            <tbody>
              {activeTable.rows.map((row, ri) => (
                <tr key={ri}>
                  <td className="monster-rownum">{ri + 1}</td>
                  {activeTable.headers.map((_, ci) => (
                    <td key={ci}><span className="monster-cell-read">{row[ci] ?? ""}</span></td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <div className="monster-actions">
        <button type="button" disabled={busy !== null} onClick={() => void handleRefresh()}>
          {busy === "refresh" ? "普查中…" : "刷新普查（census + 四表）"}
        </button>
        <button type="button" disabled={busy !== null || changes === 0} onClick={() => void handleSaveTable()}>
          {busy === "save" ? "保存中…" : `保存全量表${changes > 0 ? `（${changes} 格）` : ""}`}
        </button>
        <button type="button" disabled={busy !== null} onClick={() => void handleApplyDry()}>
          {busy === "applyDry" ? "预演中…" : "读回预演（dry-run）"}
        </button>
        <button
          type="button"
          className={writeArmed ? "monster-write-armed" : ""}
          disabled={busy !== null}
          onClick={() => void handleApplyWrite()}
        >
          {busy === "applyWrite" ? "写回中…" : writeArmed ? "确认写回 XML" : "写回 XML（--write）"}
        </button>
        <span className="monster-solve-group">
          <input
            value={solveTemplate}
            onChange={(e) => setSolveTemplate(e.currentTarget.value)}
            placeholder="单怪复算：敌人-体育老师"
          />
          <button type="button" disabled={busy !== null || !solveTemplate.trim()} onClick={() => void handleSolve()}>
            {busy === "solve" ? "复算中…" : "复算"}
          </button>
        </span>
      </div>

      {log && <pre className="monster-log">{log}</pre>}
    </article>
  );
}
