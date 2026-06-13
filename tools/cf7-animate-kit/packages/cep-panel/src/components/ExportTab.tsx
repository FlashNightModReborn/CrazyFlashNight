/**
 * Export tab (uplifted) — outDir input with memory + recent-dirs, layout/trim
 * options persisted, and per-item result chips with subtle motion.
 *
 * Exports whatever is selected in Animate's Library to PNG + atlas data via the
 * host's SpriteSheetExporter. Bridge contract is untouched: host.exportSelected.
 */
import { useCallback, useMemo, useState } from 'react';
import { host, type ExportResultRow } from '../bridge.js';
import ResultChips, { type ResultChip } from './ResultChips.js';
import { useStoredString, useStoredBool } from '../hooks/useLocalStorage.js';

const LAYOUT_FORMATS = ['JSON', 'Easel.JS', 'Starling', 'cocos2D'] as const;
const RECENT_KEY = 'cf7ak:export:recentDirs';
const MAX_RECENT = 5;

function readRecent(): string[] {
  try {
    const raw = window.localStorage?.getItem(RECENT_KEY);
    if (!raw) return [];
    const arr: unknown = JSON.parse(raw);
    return Array.isArray(arr) ? arr.filter((x): x is string => typeof x === 'string') : [];
  } catch {
    return [];
  }
}

function pushRecent(dir: string): string[] {
  const next = [dir, ...readRecent().filter((d) => d !== dir)].slice(0, MAX_RECENT);
  try {
    window.localStorage?.setItem(RECENT_KEY, JSON.stringify(next));
  } catch {
    /* ignore */
  }
  return next;
}

export function ExportTab({ motionMs = 140 }: { motionMs?: number }) {
  const [outDir, setOutDir] = useStoredString('cf7ak:export:outDir', 'C:/temp/cf7-export');
  const [trim, setTrim] = useStoredBool('cf7ak:export:trim', true);
  const [layoutFormat, setLayoutFormat] = useStoredString('cf7ak:export:layout', 'JSON');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [results, setResults] = useState<ExportResultRow[] | null>(null);
  const [recent, setRecent] = useState<string[]>(() => readRecent());

  const run = useCallback(async () => {
    const trimmedDir = outDir.trim();
    if (!trimmedDir) {
      setStatus('outDir required');
      return;
    }
    setBusy(true);
    setStatus(null);
    setResults(null);
    const res = await host.exportSelected({ outDir: trimmedDir, layoutFormat, trim });
    if (res.ok) {
      setResults(res.data.results);
      const okN = res.data.results.filter((r) => r.ok).length;
      setStatus(`exported ${okN}/${res.data.count} to ${res.data.outDir}`);
      setRecent(pushRecent(trimmedDir));
    } else {
      setStatus(`export failed: ${res.error}`);
    }
    setBusy(false);
  }, [outDir, layoutFormat, trim, setRecent]);

  const chips = useMemo<ResultChip[]>(
    () =>
      (results ?? []).map((r) => ({
        key: r.name,
        state: r.ok ? 'ok' : r.skipped ? 'skip' : 'err',
        label: r.name,
        detail: r.png ?? r.reason ?? r.error ?? undefined,
      })),
    [results],
  );

  const okCount = results ? results.filter((r) => r.ok).length : 0;
  const total = results?.length ?? 0;

  return (
    <div className="tab-body">
      <div className="hint">
        Select one or more symbols in Animate's <strong>Library</strong>, then export. Movie clips /
        graphics / buttons only.
      </div>

      <label className="field">
        <span>Output folder</span>
        <input
          value={outDir}
          onChange={(e) => setOutDir(e.target.value)}
          placeholder="C:/temp/cf7-export"
        />
      </label>

      {recent.length > 0 && (
        <div className="recent-dirs">
          <span className="muted recent-label">Recent:</span>
          {recent.map((d) => (
            <button
              key={d}
              className={`recent-chip ${d === outDir ? 'active' : ''}`}
              title={d}
              onClick={() => setOutDir(d)}
            >
              {d}
            </button>
          ))}
        </div>
      )}

      <div className="row wrap">
        <label className="field">
          <span>Layout format</span>
          <select value={layoutFormat} onChange={(e) => setLayoutFormat(e.target.value)}>
            {LAYOUT_FORMATS.map((f) => (
              <option key={f} value={f}>
                {f}
              </option>
            ))}
          </select>
        </label>
        <label className="check">
          <input type="checkbox" checked={trim} onChange={(e) => setTrim(e.target.checked)} />
          <span>Trim transparent borders</span>
        </label>
      </div>

      <div className="row sticky-actions">
        <button className="btn btn-primary" onClick={() => void run()} disabled={busy}>
          {busy ? 'Exporting…' : 'Export selected'}
        </button>
        <span className="muted">{status}</span>
      </div>

      {results && total > 0 && (
        <div className="export-progress" title={`${okCount} of ${total} exported`}>
          <div className="export-progress-fill" style={{ width: `${(okCount / total) * 100}%` }} />
        </div>
      )}

      {results && <ResultChips chips={chips} motionMs={motionMs} title="Export results" />}
    </div>
  );
}
