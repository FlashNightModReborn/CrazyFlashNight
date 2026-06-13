import type { OpResult, JvmOpResult } from "../../shared/ipc-types.js";

const ACTION_LABEL: Record<string, string> = {
  create: "新建",
  overwrite: "覆盖",
  delete: "删除",
  clear: "清空",
  noop: "无变化",
};

function isJvm(r: OpResult): r is JvmOpResult {
  return "newXmxMb" in r;
}

/**
 * Renders an an-host OpResult plan. The `applied` flag drives the heading:
 * a dry-run shows "计划 (Plan)"; an applied result shows "已执行 (Applied)".
 */
export default function OpResultView({ result }: { result: OpResult | null }) {
  if (!result) return null;

  const heading = result.applied ? "已执行" : result.ok ? "计划 (待应用)" : "失败";
  const headingClass = result.applied ? "op-applied" : result.ok ? "op-plan" : "op-error";

  return (
    <div className="op-result op-result-enter">
      <div className={`op-heading ${headingClass}`}>
        <span className="op-heading-tag">{heading}</span>
        <span className="op-summary">{result.summary}</span>
      </div>

      {isJvm(result) && (
        <div className="op-jvm">
          -Xmx {result.previousXmxMb ?? "?"}m → <strong>{result.newXmxMb}m</strong> · -Xms {result.newXmsMb}m
        </div>
      )}

      {result.changes.length > 0 && (
        <table className="op-table">
          <thead>
            <tr>
              <th>动作</th>
              <th>路径</th>
              <th>备份</th>
            </tr>
          </thead>
          <tbody>
            {result.changes.map((c, i) => (
              <tr key={`${c.path}-${i}`}>
                <td>
                  <span className={`op-action op-action-${c.action}`}>
                    {ACTION_LABEL[c.action] ?? c.action}
                  </span>
                </td>
                <td className="op-path" title={c.path}>
                  {c.path}
                </td>
                <td className="op-backup" title={c.backup ?? ""}>
                  {c.backup ? "✓" : "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}

      {result.warnings.length > 0 && (
        <ul className="op-warnings">
          {result.warnings.map((w, i) => (
            <li key={i}>⚠ {w}</li>
          ))}
        </ul>
      )}
    </div>
  );
}
