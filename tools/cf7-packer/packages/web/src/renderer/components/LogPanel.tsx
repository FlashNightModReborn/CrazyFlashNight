import type { LogEntry } from "../hooks/usePackerEvents.js";

interface LogPanelProps {
  logs: LogEntry[];
  logEndRef: React.RefObject<HTMLDivElement | null>;
}

export default function LogPanel({ logs, logEndRef }: LogPanelProps) {
  return (
    <section className="section log-section motion-surface">
      <h2>日志</h2>
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
