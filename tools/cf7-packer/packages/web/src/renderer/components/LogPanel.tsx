import type { LogEntry } from "../hooks/usePackerEvents.js";

interface LogPanelProps {
  logs: LogEntry[];
  logEndRef: React.RefObject<HTMLDivElement | null>;
}

export default function LogPanel({ logs, logEndRef }: LogPanelProps) {
  return (
    <section className="section log-section motion-surface">
      <div className="panel-title-row">
        <h2>日志</h2>
        <span className="panel-hint" title="蓝色=正常信息 橙色=警告 红色=错误">INFO / WARN / ERROR</span>
      </div>
      <div className="log-panel">
        {logs.map((entry) => (
          <div key={entry.id} className={`log-line log-${entry.event.level}`}>
            [{entry.event.level.toUpperCase()}] {entry.event.layer}: {entry.event.message}
          </div>
        ))}
        <div ref={logEndRef} />
      </div>
    </section>
  );
}
