/**
 * Advanced / 高阶 tab — surfaces wave-1 host functions in four grouped sections:
 *
 *  • 预览图 (Previews): export the stage to a single PNG, a per-frame PNG
 *    sequence (the "输出动态图" precursor — assemble into a GIF outside Animate),
 *    and batch-export the selected library symbols to one sprite sheet each.
 *  • 库导出 (Library export): dump every BitmapItem to a file; try the same for
 *    SoundItems (labelled 实验性 — many Animate builds can't re-export sound).
 *  • 存档 (Doc): backup-then-save the current FLA, and open a FLA by path.
 *  • Library: list every library item in a compact name / type / linkage table.
 *
 * Every action goes through the existing bridge (host.* → cf7ak dispatcher);
 * the protocol is untouched. Inputs are plain text paths (no CEP file dialog),
 * mirroring ExportTab's outDir field, and last-used paths persist via
 * useLocalStorage. Per-item outcomes reuse ResultChips for a consistent UX.
 */
import { useCallback, useMemo, useState } from 'react';
import {
  host,
  type BatchExportSymbolRow,
  type ExportFrameSequenceArgs,
  type ExportLibraryMediaRow,
  type LibraryItemRow,
} from '../bridge.js';
import ResultChips, { type ResultChip } from './ResultChips.js';
import { useStoredString } from '../hooks/useLocalStorage.js';

type MediaResults = { kind: 'bitmaps' | 'sounds'; rows: ExportLibraryMediaRow[] } | null;

export function AdvancedTab({ motionMs = 140 }: { motionMs?: number }) {
  // ---- persisted path inputs --------------------------------------------
  const [stageOut, setStageOut] = useStoredString(
    'cf7ak:adv:stageOut',
    'C:/temp/cf7-stage.png',
  );
  const [seqDir, setSeqDir] = useStoredString('cf7ak:adv:seqDir', 'C:/temp/cf7-frames');
  const [seqPrefix, setSeqPrefix] = useStoredString('cf7ak:adv:seqPrefix', 'frame_');
  const [seqFrom, setSeqFrom] = useStoredString('cf7ak:adv:seqFrom', '');
  const [seqTo, setSeqTo] = useStoredString('cf7ak:adv:seqTo', '');
  const [symbolsDir, setSymbolsDir] = useStoredString(
    'cf7ak:adv:symbolsDir',
    'C:/temp/cf7-symbols',
  );
  const [libDir, setLibDir] = useStoredString('cf7ak:adv:libDir', 'C:/temp/cf7-library');
  const [backupDir, setBackupDir] = useStoredString('cf7ak:adv:backupDir', '');
  const [openFile, setOpenFile] = useStoredString('cf7ak:adv:openFile', '');

  // ---- transient run state ----------------------------------------------
  const [busy, setBusy] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const [batchResults, setBatchResults] = useState<BatchExportSymbolRow[] | null>(null);
  const [seqFiles, setSeqFiles] = useState<string[] | null>(null);
  const [mediaResults, setMediaResults] = useState<MediaResults>(null);
  const [library, setLibrary] = useState<LibraryItemRow[] | null>(null);

  const isBusy = busy !== null;

  /** Parse a frame text field to an int (1-based); blank/NaN -> undefined. */
  const parseFrame = (raw: string): number | undefined => {
    const t = raw.trim();
    if (!t) return undefined;
    const n = Number(t);
    return Number.isFinite(n) ? Math.trunc(n) : undefined;
  };

  // ---- 预览图 -------------------------------------------------------------
  const runStagePNG = useCallback(async () => {
    const out = stageOut.trim();
    if (!out) {
      setStatus('outFile required');
      return;
    }
    setBusy('stage');
    setStatus(null);
    const res = await host.exportStagePNG({ outFile: out });
    setStatus(res.ok ? `stage → ${res.data.file}` : `stage export failed: ${res.error}`);
    setBusy(null);
  }, [stageOut]);

  const runFrameSequence = useCallback(async () => {
    const dir = seqDir.trim();
    if (!dir) {
      setStatus('outDir required');
      return;
    }
    setBusy('sequence');
    setStatus(null);
    setSeqFiles(null);
    const prefix = seqPrefix.trim();
    const from = parseFrame(seqFrom);
    const to = parseFrame(seqTo);
    const args: ExportFrameSequenceArgs = {
      outDir: dir,
      ...(prefix ? { prefix } : {}),
      ...(from !== undefined ? { from } : {}),
      ...(to !== undefined ? { to } : {}),
    };
    const res = await host.exportFrameSequence(args);
    if (res.ok) {
      setSeqFiles(res.data.files);
      setStatus(`exported ${res.data.count} frames → ${res.data.outDir}`);
    } else {
      setStatus(`frame sequence failed: ${res.error}`);
    }
    setBusy(null);
  }, [seqDir, seqPrefix, seqFrom, seqTo]);

  const runBatchSymbols = useCallback(async () => {
    const dir = symbolsDir.trim();
    if (!dir) {
      setStatus('outDir required');
      return;
    }
    setBusy('batch');
    setStatus(null);
    setBatchResults(null);
    // names omitted -> host exports the currently selected library symbols.
    const res = await host.batchExportSymbols({ outDir: dir });
    if (res.ok) {
      setBatchResults(res.data.results);
      const okN = res.data.results.filter((r) => r.ok).length;
      setStatus(`exported ${okN}/${res.data.count} symbols → ${res.data.outDir}`);
    } else {
      setStatus(`batch export failed: ${res.error}`);
    }
    setBusy(null);
  }, [symbolsDir]);

  // ---- 库导出 -------------------------------------------------------------
  const runLibraryBitmaps = useCallback(async () => {
    const dir = libDir.trim();
    if (!dir) {
      setStatus('outDir required');
      return;
    }
    setBusy('bitmaps');
    setStatus(null);
    setMediaResults(null);
    const res = await host.exportLibraryBitmaps({ outDir: dir });
    if (res.ok) {
      setMediaResults({ kind: 'bitmaps', rows: res.data.results });
      const okN = res.data.results.filter((r) => r.ok).length;
      setStatus(`exported ${okN}/${res.data.count} bitmaps → ${res.data.outDir}`);
    } else {
      setStatus(`bitmap export failed: ${res.error}`);
    }
    setBusy(null);
  }, [libDir]);

  const runLibrarySounds = useCallback(async () => {
    const dir = libDir.trim();
    if (!dir) {
      setStatus('outDir required');
      return;
    }
    setBusy('sounds');
    setStatus(null);
    setMediaResults(null);
    const res = await host.exportLibrarySounds({ outDir: dir });
    if (res.ok) {
      setMediaResults({ kind: 'sounds', rows: res.data.results });
      const okN = res.data.results.filter((r) => r.ok).length;
      setStatus(`exported ${okN}/${res.data.count} sounds → ${res.data.outDir} (experimental)`);
    } else {
      setStatus(`sound export failed: ${res.error}`);
    }
    setBusy(null);
  }, [libDir]);

  // ---- 存档 ---------------------------------------------------------------
  const runSafeSave = useCallback(async () => {
    setBusy('save');
    setStatus(null);
    const res = await host.safeSave(backupDir.trim() || undefined);
    if (res.ok) {
      setStatus(
        res.data.backupFile
          ? `saved (backup → ${res.data.backupFile})`
          : 'saved',
      );
    } else {
      setStatus(`save failed: ${res.error}`);
    }
    setBusy(null);
  }, [backupDir]);

  const runOpenDocument = useCallback(async () => {
    const file = openFile.trim();
    if (!file) {
      setStatus('file path required');
      return;
    }
    setBusy('open');
    setStatus(null);
    const res = await host.openDocument(file);
    setStatus(res.ok ? `opened ${res.data.name}` : `open failed: ${res.error}`);
    setBusy(null);
  }, [openFile]);

  // ---- Library list -------------------------------------------------------
  const runListLibrary = useCallback(async () => {
    setBusy('library');
    setStatus(null);
    const res = await host.listLibrary();
    if (res.ok) {
      setLibrary(res.data.items);
      setStatus(`${res.data.count} library items`);
    } else {
      setLibrary(null);
      setStatus(`list library failed: ${res.error}`);
    }
    setBusy(null);
  }, []);

  // ---- chips --------------------------------------------------------------
  const batchChips = useMemo<ResultChip[]>(
    () =>
      (batchResults ?? []).map((r) => ({
        key: r.name,
        state: r.ok ? 'ok' : 'err',
        label: r.name,
        detail: r.png ?? r.error ?? undefined,
      })),
    [batchResults],
  );

  const mediaChips = useMemo<ResultChip[]>(
    () =>
      (mediaResults?.rows ?? []).map((r) => ({
        key: r.name,
        state: r.ok ? 'ok' : r.skipped ? 'skip' : 'err',
        label: r.name,
        detail: r.file ?? r.reason ?? r.error ?? undefined,
      })),
    [mediaResults],
  );

  return (
    <div className="tab-body">
      {/* ============================ 预览图 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">预览图 · Previews</div>
        <div className="hint">
          Export the stage to a single PNG, a per-frame PNG sequence (assemble into a GIF
          outside Animate), or batch the <strong>selected</strong> library symbols to one
          sprite sheet each.
        </div>

        <label className="field">
          <span>Stage PNG output file</span>
          <input
            value={stageOut}
            onChange={(e) => setStageOut(e.target.value)}
            placeholder="C:/temp/cf7-stage.png"
          />
        </label>
        <div className="row">
          <button
            className="btn btn-primary"
            onClick={() => void runStagePNG()}
            disabled={isBusy}
          >
            {busy === 'stage' ? 'Exporting…' : 'Export stage PNG'}
          </button>
        </div>

        <label className="field">
          <span>Frame sequence output folder</span>
          <input
            value={seqDir}
            onChange={(e) => setSeqDir(e.target.value)}
            placeholder="C:/temp/cf7-frames"
          />
        </label>
        <div className="row wrap">
          <label className="field">
            <span>Prefix</span>
            <input
              className="adv-input-sm"
              value={seqPrefix}
              onChange={(e) => setSeqPrefix(e.target.value)}
              placeholder="frame_"
            />
          </label>
          <label className="field">
            <span>From (blank = 1)</span>
            <input
              className="adv-input-sm"
              value={seqFrom}
              onChange={(e) => setSeqFrom(e.target.value)}
              placeholder="1"
              inputMode="numeric"
            />
          </label>
          <label className="field">
            <span>To (blank = end)</span>
            <input
              className="adv-input-sm"
              value={seqTo}
              onChange={(e) => setSeqTo(e.target.value)}
              placeholder="end"
              inputMode="numeric"
            />
          </label>
        </div>
        <div className="row">
          <button className="btn" onClick={() => void runFrameSequence()} disabled={isBusy}>
            {busy === 'sequence' ? 'Exporting…' : 'Export frame sequence'}
          </button>
        </div>
        {seqFiles && seqFiles.length > 0 && (
          <div className="hint adv-seq-note">
            {seqFiles.length} frame{seqFiles.length === 1 ? '' : 's'} written, e.g.{' '}
            <code>{seqFiles[0]}</code>
            {seqFiles.length > 1 && <> … <code>{seqFiles[seqFiles.length - 1]}</code></>}
          </div>
        )}

        <label className="field">
          <span>Batch symbols output folder</span>
          <input
            value={symbolsDir}
            onChange={(e) => setSymbolsDir(e.target.value)}
            placeholder="C:/temp/cf7-symbols"
          />
        </label>
        <div className="row">
          <button className="btn" onClick={() => void runBatchSymbols()} disabled={isBusy}>
            {busy === 'batch' ? 'Exporting…' : 'Batch export selected symbols'}
          </button>
        </div>
        {batchResults && (
          <ResultChips chips={batchChips} motionMs={motionMs} title="Batch export" />
        )}
      </section>

      {/* ============================ 库导出 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">库导出 · Library export</div>
        <div className="hint">
          Export each library bitmap to a file. Sound re-export is{' '}
          <span className="adv-experimental">实验性 / experimental</span> — many Animate
          builds can't re-export sound; unsupported items report per-item.
        </div>
        <label className="field">
          <span>Media output folder</span>
          <input
            value={libDir}
            onChange={(e) => setLibDir(e.target.value)}
            placeholder="C:/temp/cf7-library"
          />
        </label>
        <div className="row wrap">
          <button className="btn btn-primary" onClick={() => void runLibraryBitmaps()} disabled={isBusy}>
            {busy === 'bitmaps' ? 'Exporting…' : 'Export bitmaps'}
          </button>
          <button className="btn" onClick={() => void runLibrarySounds()} disabled={isBusy}>
            {busy === 'sounds' ? 'Exporting…' : 'Export sounds'}
            <span className="adv-badge">实验性</span>
          </button>
        </div>
        {mediaResults && (
          <ResultChips
            chips={mediaChips}
            motionMs={motionMs}
            title={mediaResults.kind === 'bitmaps' ? 'Bitmap export' : 'Sound export (experimental)'}
          />
        )}
      </section>

      {/* ============================= 存档 ============================= */}
      <section className="adv-section">
        <div className="adv-section-head">存档 · Document</div>
        <div className="hint">
          Save backs up the current FLA first (copy-before-save). Open loads a FLA by full
          path. The document must already be saved once (Save As) for safe-save to work.
        </div>
        <label className="field">
          <span>Backup folder (blank = sibling 'cf7ak-backup')</span>
          <input
            value={backupDir}
            onChange={(e) => setBackupDir(e.target.value)}
            placeholder="(optional) C:/temp/cf7-backup"
          />
        </label>
        <div className="row">
          <button className="btn btn-primary" onClick={() => void runSafeSave()} disabled={isBusy}>
            {busy === 'save' ? 'Saving…' : 'Backup & save'}
          </button>
        </div>

        <label className="field">
          <span>Open document (FLA path)</span>
          <input
            value={openFile}
            onChange={(e) => setOpenFile(e.target.value)}
            placeholder="C:/path/to/file.fla"
          />
        </label>
        <div className="row">
          <button className="btn" onClick={() => void runOpenDocument()} disabled={isBusy}>
            {busy === 'open' ? 'Opening…' : 'Open document'}
          </button>
        </div>
      </section>

      {/* ============================ Library ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">Library</div>
        <div className="row">
          <button className="btn" onClick={() => void runListLibrary()} disabled={isBusy}>
            {busy === 'library' ? 'Listing…' : 'List library'}
          </button>
          {library && <span className="muted">{library.length} items</span>}
        </div>
        {library && (
          <div className="table-scroll">
            <table className="grid">
              <thead>
                <tr>
                  <th>Item</th>
                  <th>Type</th>
                  <th>Linkage →</th>
                </tr>
              </thead>
              <tbody>
                {library.map((it) => (
                  <tr key={it.name} className={it.exportForAS ? 'has-linkage' : ''}>
                    <td className="ellipsis" title={it.name}>
                      {it.name}
                    </td>
                    <td className="muted">{it.symbolType ?? it.itemType}</td>
                    <td className="ellipsis mono" title={it.linkageIdentifier}>
                      {it.exportForAS ? it.linkageIdentifier : ''}
                    </td>
                  </tr>
                ))}
                {library.length === 0 && (
                  <tr>
                    <td colSpan={3} className="muted center">
                      No items — open a FLA, then list the library.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}
      </section>

      <div className="row sticky-actions">
        <span className="muted">{status}</span>
      </div>
    </div>
  );
}
