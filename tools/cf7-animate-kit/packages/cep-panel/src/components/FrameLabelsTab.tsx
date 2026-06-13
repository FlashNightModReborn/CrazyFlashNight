/**
 * Frame labels tab (uplifted) — listFrameLabels -> a tidy list grouped by layer.
 * Optional symbol name targets a library symbol's timeline; blank = the
 * current/scene timeline. Symbol name is remembered across sessions.
 *
 * Bridge contract is untouched: still host.listFrameLabels(symbolName?).
 */
import { useCallback, useMemo, useState } from 'react';
import { host, type FrameLabelRow } from '../bridge.js';
import { useStoredString } from '../hooks/useLocalStorage.js';

interface LayerGroup {
  layer: string;
  rows: FrameLabelRow[];
}

const LABEL_BADGE: Record<string, string> = {
  name: 'badge-name',
  comment: 'badge-comment',
  anchor: 'badge-anchor',
};

export function FrameLabelsTab({ motionMs = 140 }: { motionMs?: number }) {
  const [symbolName, setSymbolName] = useStoredString('cf7ak:labels:symbol', '');
  const [timeline, setTimeline] = useState<string | null>(null);
  const [labels, setLabels] = useState<FrameLabelRow[] | null>(null);
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);

  const run = useCallback(async () => {
    setBusy(true);
    setStatus(null);
    const res = await host.listFrameLabels(symbolName.trim() || undefined);
    if (res.ok) {
      setTimeline(res.data.timeline);
      setLabels(res.data.labels);
      setStatus(`${res.data.count} labels on "${res.data.timeline}"`);
    } else {
      setLabels(null);
      setTimeline(null);
      setStatus(`failed: ${res.error}`);
    }
    setBusy(false);
  }, [symbolName]);

  const groups = useMemo<LayerGroup[]>(() => {
    if (!labels) return [];
    const byLayer = new Map<string, FrameLabelRow[]>();
    for (const row of labels) {
      const arr = byLayer.get(row.layer) ?? [];
      arr.push(row);
      byLayer.set(row.layer, arr);
    }
    return [...byLayer.entries()]
      .map(([layer, rows]) => ({
        layer,
        rows: rows.slice().sort((a, b) => a.index - b.index),
      }))
      .sort((a, b) => a.layer.localeCompare(b.layer));
  }, [labels]);

  return (
    <div className="tab-body">
      <label className="field">
        <span>Symbol name (blank = current timeline)</span>
        <input
          value={symbolName}
          onChange={(e) => setSymbolName(e.target.value)}
          placeholder="e.g. mc_hero"
        />
      </label>

      <div className="row sticky-actions">
        <button className="btn btn-primary" onClick={() => void run()} disabled={busy}>
          {busy ? 'Reading…' : 'List frame labels'}
        </button>
        <span className="muted">{status}</span>
      </div>

      {labels && labels.length === 0 && (
        <div className="empty-note muted center">
          No named labels on {timeline ? `"${timeline}"` : 'this timeline'}.
        </div>
      )}

      {groups.length > 0 && (
        <div className="labels-groups">
          {groups.map((g) => (
            <section key={g.layer} className={`layer-group ${motionMs > 0 ? 'group-enter' : ''}`}>
              <div className="layer-group-head">
                <span className="layer-group-name ellipsis" title={g.layer}>
                  {g.layer}
                </span>
                <span className="layer-group-count">{g.rows.length}</span>
              </div>
              <ul className="label-list">
                {g.rows.map((l, i) => (
                  <li key={`${l.index}-${i}`} className="label-row">
                    <span className="label-index mono">{l.index}</span>
                    <span className={`label-badge ${LABEL_BADGE[l.labelType] ?? 'badge-other'}`}>
                      {l.labelType}
                    </span>
                    <span className="label-name mono ellipsis" title={l.name}>
                      {l.name || <span className="muted">(unnamed)</span>}
                    </span>
                    {l.duration > 1 && <span className="label-dur muted">×{l.duration}</span>}
                  </li>
                ))}
              </ul>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
