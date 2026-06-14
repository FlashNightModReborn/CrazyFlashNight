/**
 * 预设/位图/诊断 (Presets / Bitmap / Diagnostics) tab — surfaces the wave-3
 * host functions in three grouped sections:
 *
 *  • 预设 (Presets): a preset manager backed by a JSON file the host reads/writes
 *    under <Configuration>/Commands/cf7ak/presets.json. List every saved preset
 *    (presetList) with per-row Apply / Delete; a save form lets you name a preset,
 *    pick any known cf7ak fn from a dropdown, and supply its args as JSON. Re-apply
 *    replays the stored fn + args through the same dispatcher. CRUD needs no open
 *    document; Apply may, depending on which fn the preset replays.
 *  • 位图 (Bitmap): traceBitmap on the CURRENT stage selection (a bitmap must be
 *    selected first), and set BitmapItem compression (photo / lossless + quality +
 *    smoothing) on selected / named / all library bitmaps.
 *  • 诊断 (Diagnostics): a read-only "what's my environment" dump (Animate version,
 *    platform, open-doc count, active-doc stats, capability flags).
 *
 * Every action goes through the existing bridge (host.* → cf7ak dispatcher); the
 * protocol is untouched. Inputs persist via useLocalStorage under cf7ak:w3:*.
 * Per-item outcomes reuse ResultChips for a consistent UX.
 */
import { useCallback, useMemo, useState } from 'react';
import {
  host,
  type BitmapCompressionType,
  type BitmapSetCompressionArgs,
  type BitmapSetCompressionRow,
  type CurveFit,
  type DiagnosticsReport,
  type Preset,
} from '../bridge.js';
import ResultChips, { type ResultChip } from './ResultChips.js';
import { useStoredString, useStoredBool } from '../hooks/useLocalStorage.js';

/**
 * The known cf7ak fn names a preset can wrap, grouped for the save-form dropdown.
 * These mirror HostFnMap keys; a preset can replay any of them with stored args.
 */
const KNOWN_FNS: ReadonlyArray<{ group: string; fns: readonly string[] }> = [
  { group: '核心', fns: ['ping', 'probe', 'scanLinkage', 'applyLinkage', 'listFrameLabels', 'exportSelected', 'publish'] },
  {
    group: '高阶 (wave 1)',
    fns: [
      'listLibrary',
      'exportStagePNG',
      'exportFrameSequence',
      'batchExportSymbols',
      'exportLibraryBitmaps',
      'exportLibrarySounds',
      'safeSave',
      'openDocument',
    ],
  },
  {
    group: '库/帧/滤镜 (wave 2)',
    fns: [
      'libBatchRename',
      'libNewFolder',
      'libMoveToFolder',
      'libDeleteItems',
      'framesInsert',
      'framesRemove',
      'framesReverse',
      'framesConvertToKeyframes',
      'framesClearKeyframes',
      'applyFilter',
      'clearFilters',
    ],
  },
  { group: '位图/诊断 (wave 3)', fns: ['bitmapTrace', 'bitmapSetCompression', 'crashDiagnostics'] },
];

const CURVE_FITS: ReadonlyArray<CurveFit> = [
  'pixels',
  'very tight',
  'tight',
  'normal',
  'smooth',
  'very smooth',
];

/** Split a textarea/comma blob into a clean, de-duped name list. */
function parseNames(raw: string): string[] {
  const seen: Record<string, true> = {};
  const out: string[] = [];
  for (const part of raw.split(/[\n,]+/)) {
    const t = part.trim();
    if (t && !seen[t]) {
      seen[t] = true;
      out.push(t);
    }
  }
  return out;
}

/** Parse a number field; blank/NaN -> undefined (host default). */
function parseNum(raw: string): number | undefined {
  const t = raw.trim();
  if (!t) return undefined;
  const n = Number(t);
  return Number.isFinite(n) ? n : undefined;
}

export function PresetsBitmapDiagTab({ motionMs = 140 }: { motionMs?: number }) {
  // ---- persisted inputs (cf7ak:w3:*) ------------------------------------
  // 预设 save form
  const [psName, setPsName] = useStoredString('cf7ak:w3:psName', '');
  const [psFn, setPsFn] = useStoredString('cf7ak:w3:psFn', 'crashDiagnostics');
  const [psArgs, setPsArgs] = useStoredString('cf7ak:w3:psArgs', '{}');

  // 位图 trace
  const [btThreshold, setBtThreshold] = useStoredString('cf7ak:w3:btThreshold', '100');
  const [btMinArea, setBtMinArea] = useStoredString('cf7ak:w3:btMinArea', '8');
  const [btCurveFit, setBtCurveFit] = useStoredString<CurveFit>('cf7ak:w3:btCurveFit', 'normal');
  const [btCornerThreshold, setBtCornerThreshold] = useStoredString<CurveFit>(
    'cf7ak:w3:btCornerThreshold',
    'normal',
  );

  // 位图 compression
  const [bcNames, setBcNames] = useStoredString('cf7ak:w3:bcNames', '');
  const [bcType, setBcType] = useStoredString<BitmapCompressionType>('cf7ak:w3:bcType', 'lossless');
  const [bcQuality, setBcQuality] = useStoredString('cf7ak:w3:bcQuality', '80');
  const [bcSmoothing, setBcSmoothing] = useStoredBool('cf7ak:w3:bcSmoothing', false);
  const [bcSetSmoothing, setBcSetSmoothing] = useStoredBool('cf7ak:w3:bcSetSmoothing', false);

  // ---- transient run state ----------------------------------------------
  const [busy, setBusy] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const [presets, setPresets] = useState<Preset[] | null>(null);
  const [applyResult, setApplyResult] = useState<{ name: string; result: unknown } | null>(null);
  const [compRows, setCompRows] = useState<BitmapSetCompressionRow[] | null>(null);
  const [report, setReport] = useState<DiagnosticsReport | null>(null);

  const isBusy = busy !== null;

  // ---- 预设 ---------------------------------------------------------------
  const runPresetList = useCallback(async () => {
    setBusy('psList');
    setStatus(null);
    const res = await host.presetList();
    if (res.ok) {
      setPresets(res.data.presets);
      setStatus(`${res.data.count} preset${res.data.count === 1 ? '' : 's'}`);
    } else {
      setStatus(`list presets failed: ${res.error}`);
    }
    setBusy(null);
  }, []);

  const runPresetSave = useCallback(async () => {
    const name = psName.trim();
    if (!name) {
      setStatus('preset name required');
      return;
    }
    const fn = psFn.trim();
    if (!fn) {
      setStatus('fn required');
      return;
    }
    let args: unknown;
    try {
      const raw = psArgs.trim();
      args = raw ? JSON.parse(raw) : {};
    } catch (e) {
      setStatus(`args is not valid JSON: ${String(e)}`);
      return;
    }
    setBusy('psSave');
    setStatus(null);
    const res = await host.presetSave({ name, fn, args });
    if (res.ok) {
      setStatus(`saved "${name}" (${res.data.count} total)`);
      await runPresetList();
    } else {
      setStatus(`save preset failed: ${res.error}`);
      setBusy(null);
    }
  }, [psName, psFn, psArgs, runPresetList]);

  const runPresetApply = useCallback(
    async (name: string) => {
      setBusy(`psApply:${name}`);
      setStatus(null);
      setApplyResult(null);
      const res = await host.presetApply(name);
      if (res.ok) {
        setApplyResult({ name: res.data.applied, result: res.data.result });
        setStatus(`applied "${res.data.applied}"`);
      } else {
        setStatus(`apply "${name}" failed: ${res.error}`);
      }
      setBusy(null);
    },
    [],
  );

  const runPresetDelete = useCallback(
    async (name: string) => {
      setBusy(`psDelete:${name}`);
      setStatus(null);
      const res = await host.presetDelete(name);
      if (res.ok) {
        setStatus(
          res.data.deleted
            ? `deleted "${name}" (${res.data.count} remain)`
            : `"${name}" not found (${res.data.count} presets)`,
        );
        await runPresetList();
      } else {
        setStatus(`delete "${name}" failed: ${res.error}`);
        setBusy(null);
      }
    },
    [runPresetList],
  );

  /** Fill the save form from an existing preset row, for tweak-and-resave. */
  const loadPresetIntoForm = useCallback(
    (p: Preset) => {
      setPsName(p.name);
      setPsFn(p.fn);
      try {
        setPsArgs(JSON.stringify(p.args ?? {}, null, 2));
      } catch {
        setPsArgs('{}');
      }
    },
    [setPsName, setPsFn, setPsArgs],
  );

  // ---- 位图: trace -------------------------------------------------------
  const runBitmapTrace = useCallback(async () => {
    setBusy('btTrace');
    setStatus(null);
    const threshold = parseNum(btThreshold);
    const minArea = parseNum(btMinArea);
    const res = await host.bitmapTrace({
      ...(threshold !== undefined ? { threshold } : {}),
      ...(minArea !== undefined ? { minArea } : {}),
      curveFit: btCurveFit,
      cornerThreshold: btCornerThreshold,
    });
    setStatus(
      res.ok
        ? 'traced bitmap → vector shape (check stage)'
        : `trace failed: ${res.error}`,
    );
    setBusy(null);
  }, [btThreshold, btMinArea, btCurveFit, btCornerThreshold]);

  // ---- 位图: compression -------------------------------------------------
  const runBitmapCompression = useCallback(async () => {
    setBusy('bcSet');
    setStatus(null);
    setCompRows(null);
    const names = parseNames(bcNames);
    const quality = parseNum(bcQuality);
    const args: BitmapSetCompressionArgs = {
      ...(names.length > 0 ? { names } : {}),
      compressionType: bcType,
      ...(bcType === 'photo' && quality !== undefined ? { quality } : {}),
      ...(bcSetSmoothing ? { allowSmoothing: bcSmoothing } : {}),
    };
    const res = await host.bitmapSetCompression(args);
    if (res.ok) {
      setCompRows(res.data.applied);
      const okN = res.data.applied.filter((r) => r.ok).length;
      setStatus(
        `set ${bcType} on ${okN}/${res.data.count} bitmap${res.data.count === 1 ? '' : 's'}`,
      );
    } else {
      setStatus(`set compression failed: ${res.error}`);
    }
    setBusy(null);
  }, [bcNames, bcType, bcQuality, bcSmoothing, bcSetSmoothing]);

  // ---- 诊断 ---------------------------------------------------------------
  const runDiagnostics = useCallback(async () => {
    setBusy('diag');
    setStatus(null);
    const res = await host.crashDiagnostics();
    if (res.ok) {
      setReport(res.data.report);
      setStatus('diagnostics collected');
    } else {
      setReport(null);
      setStatus(`diagnostics failed: ${res.error}`);
    }
    setBusy(null);
  }, []);

  // ---- chips --------------------------------------------------------------
  const compChips = useMemo<ResultChip[]>(
    () =>
      (compRows ?? []).map((r, i) => ({
        key: `${r.name}#${i}`,
        state: r.ok ? 'ok' : r.skipped ? 'skip' : 'err',
        label: r.name,
        detail: r.error ?? (r.skipped ? 'skipped (not a bitmap)' : undefined),
      })),
    [compRows],
  );

  const applyJson = useMemo(() => {
    if (!applyResult) return '';
    try {
      return JSON.stringify(applyResult.result, null, 2);
    } catch {
      return String(applyResult.result);
    }
  }, [applyResult]);

  return (
    <div className="tab-body">
      {/* ============================ 预设 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">预设 · Presets</div>
        <div className="hint">
          Presets are stored as JSON in the host's{' '}
          <code>Commands/cf7ak/presets.json</code>. A preset wraps any cf7ak fn + its
          args so you can re-apply an operation later. CRUD needs no open document;{' '}
          <strong>Apply</strong> may, depending on the wrapped fn.
        </div>

        <div className="row wrap">
          <button className="btn" onClick={() => void runPresetList()} disabled={isBusy}>
            {busy === 'psList' ? 'Loading…' : 'Refresh list'}
          </button>
          {presets && (
            <span className="muted">
              {presets.length} preset{presets.length === 1 ? '' : 's'}
            </span>
          )}
        </div>

        {presets && (
          <div className="table-scroll">
            <table className="grid">
              <thead>
                <tr>
                  <th>Name</th>
                  <th>Fn</th>
                  <th className="w3-actions-col">Actions</th>
                </tr>
              </thead>
              <tbody>
                {presets.map((p) => {
                  const applying = busy === `psApply:${p.name}`;
                  const deleting = busy === `psDelete:${p.name}`;
                  return (
                    <tr key={p.name}>
                      <td className="ellipsis" title={p.name}>
                        {p.name}
                      </td>
                      <td className="mono ellipsis" title={p.fn}>
                        {p.fn}
                      </td>
                      <td className="w3-actions-cell">
                        <button
                          className="btn btn-mini"
                          onClick={() => void runPresetApply(p.name)}
                          disabled={isBusy}
                          title="Re-apply this preset's fn + args"
                        >
                          {applying ? '…' : 'Apply'}
                        </button>
                        <button
                          className="btn btn-mini"
                          onClick={() => loadPresetIntoForm(p)}
                          disabled={isBusy}
                          title="Load into the save form to tweak"
                        >
                          Edit
                        </button>
                        <button
                          className="btn btn-mini w2-danger"
                          onClick={() => void runPresetDelete(p.name)}
                          disabled={isBusy}
                          title="Delete this preset"
                        >
                          {deleting ? '…' : 'Delete'}
                        </button>
                      </td>
                    </tr>
                  );
                })}
                {presets.length === 0 && (
                  <tr>
                    <td colSpan={3} className="muted center">
                      No presets yet — save one below.
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
        )}

        {applyResult && (
          <div className="w3-result">
            <div className="w3-result-head">
              Applied <strong>{applyResult.name}</strong> — result
            </div>
            <pre className="w3-pre">{applyJson || '(no data)'}</pre>
          </div>
        )}

        {/* save form */}
        <div className="adv-section-head w3-subhead">Save preset</div>
        <div className="row wrap">
          <label className="field grow">
            <span>Name</span>
            <input
              value={psName}
              onChange={(e) => setPsName(e.target.value)}
              placeholder="my-export-preset"
            />
          </label>
          <label className="field">
            <span>Fn</span>
            <select value={psFn} onChange={(e) => setPsFn(e.target.value)}>
              {KNOWN_FNS.map((g) => (
                <optgroup key={g.group} label={g.group}>
                  {g.fns.map((fn) => (
                    <option key={fn} value={fn}>
                      {fn}
                    </option>
                  ))}
                </optgroup>
              ))}
            </select>
          </label>
        </div>
        <label className="field">
          <span>Args (JSON object; blank = {'{}'})</span>
          <textarea
            className="w2-textarea w3-args"
            value={psArgs}
            onChange={(e) => setPsArgs(e.target.value)}
            placeholder='{ "outDir": "C:/temp/out" }'
            rows={4}
            spellCheck={false}
          />
        </label>
        <div className="row">
          <button
            className="btn btn-primary"
            onClick={() => void runPresetSave()}
            disabled={isBusy}
          >
            {busy === 'psSave' ? 'Saving…' : 'Save preset'}
          </button>
        </div>
      </section>

      {/* ============================ 位图 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">位图 · Bitmap</div>
        <div className="hint">
          <strong>Trace</strong> converts a bitmap to a vector shape — select a bitmap on
          stage first. <strong>Compression</strong> sets the library BitmapItem export
          mode: <em>lossless</em> (PNG/GIF) or <em>photo</em> (JPEG, with quality).
        </div>

        {/* trace */}
        <div className="row wrap">
          <label className="field">
            <span>Threshold</span>
            <input
              className="adv-input-sm"
              value={btThreshold}
              onChange={(e) => setBtThreshold(e.target.value)}
              placeholder="100"
              inputMode="numeric"
            />
          </label>
          <label className="field">
            <span>Min area</span>
            <input
              className="adv-input-sm"
              value={btMinArea}
              onChange={(e) => setBtMinArea(e.target.value)}
              placeholder="8"
              inputMode="numeric"
            />
          </label>
          <label className="field">
            <span>Curve fit</span>
            <select value={btCurveFit} onChange={(e) => setBtCurveFit(e.target.value as CurveFit)}>
              {CURVE_FITS.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>Corner threshold</span>
            <select
              value={btCornerThreshold}
              onChange={(e) => setBtCornerThreshold(e.target.value as CurveFit)}
            >
              {CURVE_FITS.map((c) => (
                <option key={c} value={c}>
                  {c}
                </option>
              ))}
            </select>
          </label>
        </div>
        <div className="row">
          <button className="btn btn-primary" onClick={() => void runBitmapTrace()} disabled={isBusy}>
            {busy === 'btTrace' ? 'Tracing…' : 'Trace bitmap'}
          </button>
          <span className="muted">select a bitmap on stage first</span>
        </div>

        {/* compression */}
        <label className="field">
          <span>
            Bitmaps (optional, comma / newline separated; blank = selected, or all)
          </span>
          <textarea
            className="w2-textarea"
            value={bcNames}
            onChange={(e) => setBcNames(e.target.value)}
            placeholder="sprite.png, folder/bg.png"
            rows={2}
          />
        </label>
        <div className="row wrap">
          <label className="field">
            <span>Compression</span>
            <select
              value={bcType}
              onChange={(e) => setBcType(e.target.value as BitmapCompressionType)}
            >
              <option value="lossless">lossless</option>
              <option value="photo">photo (JPEG)</option>
            </select>
          </label>
          <label className="field">
            <span>Quality (photo, 0-100)</span>
            <input
              className="adv-input-sm"
              value={bcQuality}
              onChange={(e) => setBcQuality(e.target.value)}
              placeholder="80"
              inputMode="numeric"
              disabled={bcType !== 'photo'}
            />
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={bcSetSmoothing}
              onChange={(e) => setBcSetSmoothing(e.target.checked)}
            />
            <span>Set smoothing</span>
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={bcSmoothing}
              onChange={(e) => setBcSmoothing(e.target.checked)}
              disabled={!bcSetSmoothing}
            />
            <span>Allow smoothing</span>
          </label>
        </div>
        <div className="row">
          <button
            className="btn btn-primary"
            onClick={() => void runBitmapCompression()}
            disabled={isBusy}
          >
            {busy === 'bcSet' ? 'Applying…' : 'Set compression'}
          </button>
        </div>
        {compRows && <ResultChips chips={compChips} motionMs={motionMs} title="Compression" />}
      </section>

      {/* ============================ 诊断 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">诊断 · Diagnostics</div>
        <div className="hint">
          A read-only environment dump — Animate version, platform, open documents, the
          active document's stats, and capability flags. Useful when reporting an issue.
        </div>
        <div className="row">
          <button className="btn btn-primary" onClick={() => void runDiagnostics()} disabled={isBusy}>
            {busy === 'diag' ? 'Collecting…' : 'Run diagnostics'}
          </button>
        </div>
        {report && (
          <div className="table-scroll">
            <table className="grid">
              <tbody>
                <tr>
                  <td className="muted">Animate version</td>
                  <td className="mono">{report.flVersion || '—'}</td>
                </tr>
                <tr>
                  <td className="muted">Platform</td>
                  <td className="mono">{report.platform || '—'}</td>
                </tr>
                <tr>
                  <td className="muted">Open documents</td>
                  <td className="mono">{report.openDocCount}</td>
                </tr>
                <tr>
                  <td className="muted">SpriteSheetExporter</td>
                  <td className={report.hasSpriteSheetExporter ? 'has-linkage' : 'muted'}>
                    {report.hasSpriteSheetExporter ? 'yes' : 'no'}
                  </td>
                </tr>
                <tr>
                  <td className="muted">FLfile</td>
                  <td className={report.hasFLfile ? 'has-linkage' : 'muted'}>
                    {report.hasFLfile ? 'yes' : 'no'}
                  </td>
                </tr>
                <tr>
                  <td className="muted">Config URI</td>
                  <td className="mono ellipsis" title={report.configURI}>
                    {report.configURI || '—'}
                  </td>
                </tr>
                {report.activeDoc ? (
                  <>
                    <tr className="w3-diag-divider">
                      <td className="muted">Active doc</td>
                      <td className="mono ellipsis" title={report.activeDoc.name}>
                        {report.activeDoc.name}
                      </td>
                    </tr>
                    {report.activeDoc.pathURI && (
                      <tr>
                        <td className="muted">· path</td>
                        <td className="mono ellipsis" title={report.activeDoc.pathURI}>
                          {report.activeDoc.pathURI}
                        </td>
                      </tr>
                    )}
                    <tr>
                      <td className="muted">· scenes</td>
                      <td className="mono">{report.activeDoc.sceneCount}</td>
                    </tr>
                    <tr>
                      <td className="muted">· library items</td>
                      <td className="mono">{report.activeDoc.libraryItemCount}</td>
                    </tr>
                    <tr>
                      <td className="muted">· timeline frames</td>
                      <td className="mono">{report.activeDoc.timelineFrameCount}</td>
                    </tr>
                  </>
                ) : (
                  <tr className="w3-diag-divider">
                    <td className="muted">Active doc</td>
                    <td className="muted">none (no FLA open)</td>
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
