import { useCallback, useState } from "react";

const TEXT = {
  title: "数据校验",
  subtitle: "检查基线数据中的异常值",
  run: "运行校验",
  running: "校验中...",
  empty: "点击「运行校验」检查基线数据。",
  noIssues: "所有检查通过，无异常。"
} as const;

export function ValidationPanel() {
  const [report, setReport] = useState<ValidationReport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const canRun = typeof window.cf7Balance?.runValidation === "function";

  const handleRun = useCallback(async () => {
    if (!window.cf7Balance?.runValidation) return;
    setLoading(true);
    setError(null);
    try {
      const result = await window.cf7Balance.runValidation();
      setReport(result);
    } catch (err) {
      setError(String(err));
    } finally {
      setLoading(false);
    }
  }, []);

  return (
    <section className="detail-section">
      <div className="detail-section-header history-header">
        <div>
          <h4>{TEXT.title}</h4>
          <p className="panel-caption">{TEXT.subtitle}</p>
        </div>
        <button
          className="mini-button"
          disabled={!canRun || loading}
          onClick={() => void handleRun()}
          type="button"
        >
          {loading ? TEXT.running : TEXT.run}
        </button>
      </div>

      {error && <div className="validation-error">{error}</div>}

      {report == null ? (
        <div className="empty-state">{TEXT.empty}</div>
      ) : report.issues.length === 0 ? (
        <div className="validation-pass">{TEXT.noIssues}</div>
      ) : (
        <>
          <div className="validation-summary">
            {report.summary.errors > 0 && (
              <span className="validation-badge validation-badge-error">
                {report.summary.errors} 错误
              </span>
            )}
            {report.summary.warnings > 0 && (
              <span className="validation-badge validation-badge-warning">
                {report.summary.warnings} 警告
              </span>
            )}
            <span className="validation-badge">
              共 {report.summary.total} 项
            </span>
          </div>
          <div className="artifact-list">
            {report.issues.map((issue: ValidationIssue, i: number) => (
              <article
                className={`artifact-card ${
                  issue.severity === "error"
                    ? "validation-card-error"
                    : "validation-card-warning"
                }`}
                key={`${issue.name}-${issue.field}-${i}`}
              >
                <div className="detail-card-topline">
                  <strong>{issue.name}</strong>
                  <span className={`validation-severity-${issue.severity}`}>
                    {issue.severity === "error" ? "错误" : "警告"}
                  </span>
                </div>
                <div className="artifact-meta">
                  <span>字段: {issue.field}</span>
                  <span>
                    值: {formatNum(issue.value)} / 阈值: {formatNum(issue.threshold)}
                  </span>
                </div>
                <p className="validation-message">{issue.message}</p>
              </article>
            ))}
          </div>
        </>
      )}
    </section>
  );
}

function formatNum(value: number): string {
  return Number.isInteger(value)
    ? value.toLocaleString("zh-CN")
    : value.toLocaleString("zh-CN", { maximumFractionDigits: 2 });
}
