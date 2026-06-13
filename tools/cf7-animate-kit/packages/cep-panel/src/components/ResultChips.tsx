/**
 * ResultChips — a compact, animated list of per-item operation outcomes used by
 * the Linkage / Export tabs. Each chip carries a state (ok / err / skip) and an
 * optional detail line. Motion is purely CSS (a stagger-in via index delay);
 * disabled when `motionMs <= 0`.
 */
export type ChipState = 'ok' | 'err' | 'skip';

export interface ResultChip {
  key: string;
  state: ChipState;
  label: string;
  detail?: string | undefined;
}

const ICON: Record<ChipState, string> = { ok: '✓', err: '✕', skip: '∅' };

export default function ResultChips({
  chips,
  motionMs = 140,
  title,
}: {
  chips: ResultChip[];
  motionMs?: number;
  title?: string | undefined;
}) {
  if (chips.length === 0) return null;
  const okN = chips.filter((c) => c.state === 'ok').length;
  const errN = chips.filter((c) => c.state === 'err').length;
  const skipN = chips.filter((c) => c.state === 'skip').length;

  return (
    <div className="results-block">
      <div className="results-head">
        <span className="results-title">{title ?? 'Results'}</span>
        <span className="results-tally">
          <span className="tally tally-ok">{okN} ok</span>
          {errN > 0 && <span className="tally tally-err">{errN} failed</span>}
          {skipN > 0 && <span className="tally tally-skip">{skipN} skipped</span>}
        </span>
      </div>
      <div className="chips">
        {chips.map((c, i) => (
          <div
            key={c.key}
            className={`chip chip-${c.state} ${motionMs > 0 ? 'chip-enter' : ''}`}
            style={motionMs > 0 ? { animationDelay: `${Math.min(i, 12) * 18}ms` } : undefined}
            title={c.detail ? `${c.label} — ${c.detail}` : c.label}
          >
            <span className="chip-icon">{ICON[c.state]}</span>
            <span className="chip-label ellipsis">{c.label}</span>
            {c.detail && <span className="chip-detail ellipsis">{c.detail}</span>}
          </div>
        ))}
      </div>
    </div>
  );
}
