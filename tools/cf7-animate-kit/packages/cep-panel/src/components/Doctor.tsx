/**
 * Doctor strip — calls `probe` and shows flVersion + capability flags as a
 * compact capability strip pinned in the panel header. Re-probes on mount and
 * on demand. The status dot reflects "host reachable AND a document is open".
 *
 * Contract: read-only consumer of bridge.host.probe() — no protocol changes.
 */
import { useCallback, useEffect, useState } from 'react';
import { host, hasHostBridge, hostLabel, type ProbeData } from '../bridge.js';

function Flag({ on, label }: { on: boolean; label: string }) {
  return (
    <span className={`flag ${on ? 'flag-on' : 'flag-off'}`} title={`${label}: ${on ? 'available' : 'unavailable'}`}>
      {on ? '✓' : '✕'} {label}
    </span>
  );
}

export function Doctor({ onStatus }: { onStatus?: (ready: boolean) => void } = {}) {
  const [probe, setProbe] = useState<ProbeData | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [open, setOpen] = useState(false);

  const bridge = hasHostBridge();

  const run = useCallback(async () => {
    setBusy(true);
    setError(null);
    const res = await host.probe();
    if (res.ok) {
      setProbe(res.data);
      onStatus?.(res.data.hasDocument && bridge);
    } else {
      setProbe(null);
      setError(res.error);
      onStatus?.(false);
    }
    setBusy(false);
  }, [bridge, onStatus]);

  useEffect(() => {
    void run();
  }, [run]);

  const ready = bridge && !!probe?.hasDocument;

  return (
    <div className="doctor">
      <div className="doctor-row">
        <span className={`dot ${ready ? 'dot-ok' : 'dot-warn'}`} aria-hidden />
        <strong>Doctor</strong>
        <span className="muted doctor-host">{hostLabel()}</span>
        {probe && <span className="flag flag-info">FL {probe.flVersion}</span>}
        <button
          className="btn-mini doctor-toggle"
          onClick={() => setOpen((o) => !o)}
          title="Show capability detail"
        >
          {open ? 'Hide' : 'Detail'}
        </button>
        <button className="btn-mini" onClick={() => void run()} disabled={busy} title="Re-run probe">
          {busy ? '…' : 'Re-probe'}
        </button>
      </div>

      {/* Always-visible compact capability strip. */}
      {probe && (
        <div className="doctor-flags">
          <Flag on={probe.hasDocument} label="document" />
          <Flag on={probe.hasSpriteSheetExporter} label="spritesheet" />
          <Flag on={probe.hasFLfile} label="FLfile" />
          <Flag on={probe.hasJSON} label="JSON" />
        </div>
      )}

      {open && (
        <div className="doctor-detail">
          {error && <div className="doctor-error">{error}</div>}
          {!bridge && (
            <div className="doctor-note">
              Not inside a CEP host — this is a browser preview. Host calls return errors
              until you load the panel in Animate.
            </div>
          )}
          {bridge && probe && !probe.hasDocument && (
            <div className="doctor-note">
              Host reachable, but no FLA document is open. Open or create a document, then
              re-probe.
            </div>
          )}
          {bridge && ready && (
            <div className="doctor-note doctor-note-ok">
              Ready. {probe?.hasSpriteSheetExporter ? 'Export pipeline available.' : 'SpriteSheetExporter missing — Export tab may fail.'}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
