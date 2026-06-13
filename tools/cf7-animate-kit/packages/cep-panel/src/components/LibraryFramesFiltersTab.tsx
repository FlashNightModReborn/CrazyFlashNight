/**
 * 库/帧/滤镜 (Library / Frames / Filters) tab — surfaces the wave-2 host
 * functions in three grouped sections:
 *
 *  • 库治理 (Library): batch-rename (find/replace + regex toggle), make a new
 *    folder by path, move items into a folder, and delete items. The mutating /
 *    destructive ops (move, delete) require an explicit Apply / confirm step.
 *  • 帧 (Frames): insert / remove (with a count input), reverse,
 *    convert-to-keyframes, clear-keyframes — all operate on the CURRENT main
 *    timeline frame selection (made in Animate), noted in the UI.
 *  • 滤镜 (Filters): apply a filter (glow / dropShadow / blur with minimal
 *    params) to, or clear all filters from, the CURRENT stage selection.
 *
 * Every action goes through the existing bridge (host.* → cf7ak dispatcher); the
 * protocol is untouched. Inputs persist via useLocalStorage under cf7ak:w2:*.
 * Per-item outcomes reuse ResultChips for a consistent UX.
 */
import { useCallback, useMemo, useState } from 'react';
import {
  host,
  type ApplyFilterRow,
  type FilterType,
  type LibBatchRenameArgs,
  type LibDeleteRow,
  type LibMoveRow,
  type LibMoveToFolderArgs,
  type LibRenameRow,
} from '../bridge.js';
import ResultChips, { type ResultChip } from './ResultChips.js';
import { useStoredString, useStoredBool } from '../hooks/useLocalStorage.js';

const FILTER_TYPES: ReadonlyArray<{ value: FilterType; label: string; documented: boolean }> = [
  { value: 'glow', label: 'Glow', documented: true },
  { value: 'dropShadow', label: 'Drop shadow', documented: true },
  { value: 'blur', label: 'Blur', documented: true },
  { value: 'bevel', label: 'Bevel', documented: false },
  { value: 'gradientGlow', label: 'Gradient glow', documented: false },
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

/** Parse a positive int count field; blank/NaN/<1 -> undefined (host default). */
function parseCount(raw: string): number | undefined {
  const t = raw.trim();
  if (!t) return undefined;
  const n = Number(t);
  if (!Number.isFinite(n)) return undefined;
  const i = Math.trunc(n);
  return i >= 1 ? i : undefined;
}

export function LibraryFramesFiltersTab({ motionMs = 140 }: { motionMs?: number }) {
  // ---- persisted inputs (cf7ak:w2:*) ------------------------------------
  const [find, setFind] = useStoredString('cf7ak:w2:rnFind', '');
  const [replace, setReplace] = useStoredString('cf7ak:w2:rnReplace', '');
  const [useRegex, setUseRegex] = useStoredBool('cf7ak:w2:rnRegex', false);
  const [renameNames, setRenameNames] = useStoredString('cf7ak:w2:rnNames', '');

  const [newFolder, setNewFolder] = useStoredString('cf7ak:w2:newFolder', '');

  const [moveFolder, setMoveFolder] = useStoredString('cf7ak:w2:moveFolder', '');
  const [moveNames, setMoveNames] = useStoredString('cf7ak:w2:moveNames', '');

  const [deleteNames, setDeleteNames] = useStoredString('cf7ak:w2:deleteNames', '');

  const [frameCount, setFrameCount] = useStoredString('cf7ak:w2:frameCount', '1');
  const [insertAtEnd, setInsertAtEnd] = useStoredBool('cf7ak:w2:insertAtEnd', false);

  const [filterType, setFilterType] = useStoredString<FilterType>('cf7ak:w2:filterType', 'glow');
  const [filterColor, setFilterColor] = useStoredString('cf7ak:w2:filterColor', '#ffffff');
  const [filterBlur, setFilterBlur] = useStoredString('cf7ak:w2:filterBlur', '8');
  const [filterStrength, setFilterStrength] = useStoredString('cf7ak:w2:filterStrength', '1');

  // ---- transient run state ----------------------------------------------
  const [busy, setBusy] = useState<string | null>(null);
  const [status, setStatus] = useState<string | null>(null);

  const [renameRows, setRenameRows] = useState<LibRenameRow[] | null>(null);
  const [moveRows, setMoveRows] = useState<LibMoveRow[] | null>(null);
  const [deleteRows, setDeleteRows] = useState<LibDeleteRow[] | null>(null);
  const [filterRows, setFilterRows] = useState<ApplyFilterRow[] | null>(null);

  // Explicit-confirm gates for destructive library ops.
  const [confirmMove, setConfirmMove] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);

  const isBusy = busy !== null;

  // ---- 库治理 -------------------------------------------------------------
  const runBatchRename = useCallback(async () => {
    const f = find.trim();
    if (!f) {
      setStatus('find pattern required');
      return;
    }
    const names = parseNames(renameNames);
    setBusy('rename');
    setStatus(null);
    setRenameRows(null);
    const args: LibBatchRenameArgs = {
      find: f,
      replace,
      ...(useRegex ? { useRegex: true } : {}),
      ...(names.length > 0 ? { names } : {}),
    };
    const res = await host.libBatchRename(args);
    if (res.ok) {
      setRenameRows(res.data.renamed);
      const okN = res.data.renamed.filter((r) => r.ok).length;
      setStatus(`renamed ${okN}/${res.data.count} item${res.data.count === 1 ? '' : 's'}`);
    } else {
      setStatus(`batch rename failed: ${res.error}`);
    }
    setBusy(null);
  }, [find, replace, useRegex, renameNames]);

  const runNewFolder = useCallback(async () => {
    const path = newFolder.trim();
    if (!path) {
      setStatus('folder path required');
      return;
    }
    setBusy('newFolder');
    setStatus(null);
    const res = await host.libNewFolder(path);
    setStatus(
      res.ok
        ? res.data.created
          ? `created folder → ${res.data.path}`
          : `folder exists → ${res.data.path}`
        : `new folder failed: ${res.error}`,
    );
    setBusy(null);
  }, [newFolder]);

  const runMoveToFolder = useCallback(async () => {
    const folder = moveFolder.trim();
    if (!folder) {
      setStatus('target folder required');
      return;
    }
    const names = parseNames(moveNames);
    setBusy('move');
    setStatus(null);
    setMoveRows(null);
    const args: LibMoveToFolderArgs = {
      folder,
      ...(names.length > 0 ? { names } : {}),
    };
    const res = await host.libMoveToFolder(args);
    if (res.ok) {
      setMoveRows(res.data.moved);
      const okN = res.data.moved.filter((r) => r.ok).length;
      setStatus(`moved ${okN}/${res.data.count} item${res.data.count === 1 ? '' : 's'} → ${folder}`);
    } else {
      setStatus(`move failed: ${res.error}`);
    }
    setConfirmMove(false);
    setBusy(null);
  }, [moveFolder, moveNames]);

  const runDeleteItems = useCallback(async () => {
    const names = parseNames(deleteNames);
    if (names.length === 0) {
      setStatus('at least one item name required');
      return;
    }
    setBusy('delete');
    setStatus(null);
    setDeleteRows(null);
    const res = await host.libDeleteItems(names);
    if (res.ok) {
      setDeleteRows(res.data.deleted);
      const okN = res.data.deleted.filter((r) => r.ok).length;
      setStatus(`deleted ${okN}/${res.data.count} item${res.data.count === 1 ? '' : 's'}`);
    } else {
      setStatus(`delete failed: ${res.error}`);
    }
    setConfirmDelete(false);
    setBusy(null);
  }, [deleteNames]);

  // ---- 帧 (current selection) --------------------------------------------
  const runFramesInsert = useCallback(async () => {
    setBusy('fInsert');
    setStatus(null);
    const count = parseCount(frameCount);
    const res = await host.framesInsert({
      ...(count !== undefined ? { count } : {}),
      ...(insertAtEnd ? { atEnd: true } : {}),
    });
    setStatus(res.ok ? `inserted; frameCount = ${res.data.frameCount}` : `insert failed: ${res.error}`);
    setBusy(null);
  }, [frameCount, insertAtEnd]);

  const runFramesRemove = useCallback(async () => {
    setBusy('fRemove');
    setStatus(null);
    const count = parseCount(frameCount);
    const res = await host.framesRemove(count !== undefined ? { count } : {});
    setStatus(res.ok ? `removed; frameCount = ${res.data.frameCount}` : `remove failed: ${res.error}`);
    setBusy(null);
  }, [frameCount]);

  const runFramesReverse = useCallback(async () => {
    setBusy('fReverse');
    setStatus(null);
    const res = await host.framesReverse();
    setStatus(res.ok ? 'reversed selected frames' : `reverse failed: ${res.error}`);
    setBusy(null);
  }, []);

  const runFramesConvert = useCallback(async () => {
    setBusy('fConvert');
    setStatus(null);
    const res = await host.framesConvertToKeyframes();
    setStatus(res.ok ? 'converted to keyframes' : `convert failed: ${res.error}`);
    setBusy(null);
  }, []);

  const runFramesClear = useCallback(async () => {
    setBusy('fClear');
    setStatus(null);
    const res = await host.framesClearKeyframes();
    setStatus(res.ok ? 'cleared keyframes' : `clear failed: ${res.error}`);
    setBusy(null);
  }, []);

  // ---- 滤镜 (current stage selection) ------------------------------------
  const runApplyFilter = useCallback(async () => {
    setBusy('applyFilter');
    setStatus(null);
    setFilterRows(null);
    const params: Record<string, unknown> = {};
    const blur = Number(filterBlur);
    if (Number.isFinite(blur)) {
      params['blurX'] = blur;
      params['blurY'] = blur;
    }
    const strength = Number(filterStrength);
    if (Number.isFinite(strength)) params['strength'] = strength;
    if (filterColor.trim()) params['color'] = filterColor.trim();
    const res = await host.applyFilter({
      type: filterType,
      ...(Object.keys(params).length > 0 ? { params } : {}),
    });
    if (res.ok) {
      setFilterRows(res.data.applied);
      const okN = res.data.applied.filter((r) => r.ok).length;
      setStatus(`applied ${filterType} to ${okN}/${res.data.count} element${res.data.count === 1 ? '' : 's'}`);
    } else {
      setStatus(`apply filter failed: ${res.error}`);
    }
    setBusy(null);
  }, [filterType, filterBlur, filterStrength, filterColor]);

  const runClearFilters = useCallback(async () => {
    setBusy('clearFilters');
    setStatus(null);
    setFilterRows(null);
    const res = await host.clearFilters();
    setStatus(res.ok ? `cleared filters on ${res.data.count} element${res.data.count === 1 ? '' : 's'}` : `clear filters failed: ${res.error}`);
    setBusy(null);
  }, []);

  // ---- chips --------------------------------------------------------------
  const renameChips = useMemo<ResultChip[]>(
    () =>
      (renameRows ?? []).map((r, i) => ({
        key: `${r.from}→${r.to}#${i}`,
        state: r.ok ? 'ok' : 'err',
        label: `${r.from} → ${r.to}`,
        detail: r.error ?? undefined,
      })),
    [renameRows],
  );

  const moveChips = useMemo<ResultChip[]>(
    () =>
      (moveRows ?? []).map((r, i) => ({
        key: `${r.name}#${i}`,
        state: r.ok ? 'ok' : 'err',
        label: r.name,
        detail: r.error ?? undefined,
      })),
    [moveRows],
  );

  const deleteChips = useMemo<ResultChip[]>(
    () =>
      (deleteRows ?? []).map((r, i) => ({
        key: `${r.name}#${i}`,
        state: r.ok ? 'ok' : 'err',
        label: r.name,
        detail: r.error ?? undefined,
      })),
    [deleteRows],
  );

  const filterChips = useMemo<ResultChip[]>(
    () =>
      (filterRows ?? []).map((r, i) => ({
        key: `${r.name ?? 'el'}#${i}`,
        state: r.ok ? 'ok' : 'err',
        label: r.name ?? `element ${i + 1}`,
        detail: r.error ?? undefined,
      })),
    [filterRows],
  );

  return (
    <div className="tab-body">
      {/* ============================ 库治理 ============================ */}
      <section className="adv-section">
        <div className="adv-section-head">库治理 · Library</div>
        <div className="hint">
          Batch-rename, foldering, and deletion operate on the open FLA's library by item
          path. Leaf names are recomputed on rename; <strong>move</strong> and{' '}
          <strong>delete</strong> require an explicit confirm.
        </div>

        {/* batch rename */}
        <div className="row wrap">
          <label className="field grow">
            <span>Find</span>
            <input value={find} onChange={(e) => setFind(e.target.value)} placeholder="old" />
          </label>
          <label className="field grow">
            <span>Replace</span>
            <input
              value={replace}
              onChange={(e) => setReplace(e.target.value)}
              placeholder="new"
            />
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={useRegex}
              onChange={(e) => setUseRegex(e.target.checked)}
            />
            <span>Regex</span>
          </label>
        </div>
        <label className="field">
          <span>Limit to items (optional, comma / newline separated; blank = all matches)</span>
          <textarea
            className="w2-textarea"
            value={renameNames}
            onChange={(e) => setRenameNames(e.target.value)}
            placeholder="folder/itemA, folder/itemB"
            rows={2}
          />
        </label>
        <div className="row">
          <button className="btn btn-primary" onClick={() => void runBatchRename()} disabled={isBusy}>
            {busy === 'rename' ? 'Renaming…' : 'Batch rename'}
          </button>
        </div>
        {renameRows && <ResultChips chips={renameChips} motionMs={motionMs} title="Rename" />}

        {/* new folder */}
        <label className="field">
          <span>New folder path</span>
          <input
            value={newFolder}
            onChange={(e) => setNewFolder(e.target.value)}
            placeholder="enemies/boss"
          />
        </label>
        <div className="row">
          <button className="btn" onClick={() => void runNewFolder()} disabled={isBusy}>
            {busy === 'newFolder' ? 'Creating…' : 'New folder'}
          </button>
        </div>

        {/* move to folder (confirm) */}
        <label className="field">
          <span>Move to folder</span>
          <input
            value={moveFolder}
            onChange={(e) => setMoveFolder(e.target.value)}
            placeholder="enemies/boss"
          />
        </label>
        <label className="field">
          <span>Items to move (comma / newline separated; blank = all items)</span>
          <textarea
            className="w2-textarea"
            value={moveNames}
            onChange={(e) => setMoveNames(e.target.value)}
            placeholder="itemA, itemB"
            rows={2}
          />
        </label>
        {!confirmMove ? (
          <div className="row">
            <button
              className="btn w2-danger"
              onClick={() => setConfirmMove(true)}
              disabled={isBusy}
            >
              Move to folder…
            </button>
          </div>
        ) : (
          <div className="row w2-confirm">
            <span className="w2-confirm-text">
              Move {parseNames(moveNames).length || 'ALL'} item(s) into{' '}
              <strong>{moveFolder.trim() || '(unset)'}</strong>?
            </span>
            <button className="btn w2-danger" onClick={() => void runMoveToFolder()} disabled={isBusy}>
              {busy === 'move' ? 'Moving…' : 'Confirm move'}
            </button>
            <button className="btn" onClick={() => setConfirmMove(false)} disabled={isBusy}>
              Cancel
            </button>
          </div>
        )}
        {moveRows && <ResultChips chips={moveChips} motionMs={motionMs} title="Move" />}

        {/* delete (confirm) */}
        <label className="field">
          <span>Delete items (comma / newline separated)</span>
          <textarea
            className="w2-textarea"
            value={deleteNames}
            onChange={(e) => setDeleteNames(e.target.value)}
            placeholder="itemA, folder/itemB"
            rows={2}
          />
        </label>
        {!confirmDelete ? (
          <div className="row">
            <button
              className="btn w2-danger"
              onClick={() => setConfirmDelete(true)}
              disabled={isBusy}
            >
              Delete items…
            </button>
          </div>
        ) : (
          <div className="row w2-confirm">
            <span className="w2-confirm-text">
              Permanently delete <strong>{parseNames(deleteNames).length}</strong> item(s)? This
              cannot be undone via this panel.
            </span>
            <button className="btn w2-danger" onClick={() => void runDeleteItems()} disabled={isBusy}>
              {busy === 'delete' ? 'Deleting…' : 'Confirm delete'}
            </button>
            <button className="btn" onClick={() => setConfirmDelete(false)} disabled={isBusy}>
              Cancel
            </button>
          </div>
        )}
        {deleteRows && <ResultChips chips={deleteChips} motionMs={motionMs} title="Delete" />}
      </section>

      {/* ============================== 帧 ============================== */}
      <section className="adv-section">
        <div className="adv-section-head">帧 · Frames</div>
        <div className="hint">
          These operate on the <strong>current main-timeline frame selection</strong> in
          Animate — select frames there first. Insert/remove use the count below; reverse /
          convert / clear act on the selected span.
        </div>
        <div className="row wrap">
          <label className="field">
            <span>Count</span>
            <input
              className="adv-input-sm"
              value={frameCount}
              onChange={(e) => setFrameCount(e.target.value)}
              placeholder="1"
              inputMode="numeric"
            />
          </label>
          <label className="check">
            <input
              type="checkbox"
              checked={insertAtEnd}
              onChange={(e) => setInsertAtEnd(e.target.checked)}
            />
            <span>Insert at end</span>
          </label>
        </div>
        <div className="row wrap">
          <button className="btn btn-primary" onClick={() => void runFramesInsert()} disabled={isBusy}>
            {busy === 'fInsert' ? 'Inserting…' : 'Insert frames'}
          </button>
          <button className="btn w2-danger" onClick={() => void runFramesRemove()} disabled={isBusy}>
            {busy === 'fRemove' ? 'Removing…' : 'Remove frames'}
          </button>
          <button className="btn" onClick={() => void runFramesReverse()} disabled={isBusy}>
            {busy === 'fReverse' ? 'Reversing…' : 'Reverse'}
          </button>
          <button className="btn" onClick={() => void runFramesConvert()} disabled={isBusy}>
            {busy === 'fConvert' ? 'Converting…' : 'Convert to keyframes'}
          </button>
          <button className="btn w2-danger" onClick={() => void runFramesClear()} disabled={isBusy}>
            {busy === 'fClear' ? 'Clearing…' : 'Clear keyframes'}
          </button>
        </div>
      </section>

      {/* ============================= 滤镜 ============================= */}
      <section className="adv-section">
        <div className="adv-section-head">滤镜 · Filters</div>
        <div className="hint">
          Apply a filter to, or clear all filters from, the <strong>current stage
          selection</strong> (movie clip / button / text instances). Glow / drop shadow / blur
          are best-documented; bevel / gradient glow may report{' '}
          <span className="adv-experimental">unsupported</span> per host.
        </div>
        <div className="row wrap">
          <label className="field">
            <span>Type</span>
            <select
              value={filterType}
              onChange={(e) => setFilterType(e.target.value as FilterType)}
            >
              {FILTER_TYPES.map((f) => (
                <option key={f.value} value={f.value}>
                  {f.label}
                  {f.documented ? '' : ' (实验性)'}
                </option>
              ))}
            </select>
          </label>
          <label className="field">
            <span>Blur</span>
            <input
              className="adv-input-sm"
              value={filterBlur}
              onChange={(e) => setFilterBlur(e.target.value)}
              placeholder="8"
              inputMode="numeric"
            />
          </label>
          <label className="field">
            <span>Strength</span>
            <input
              className="adv-input-sm"
              value={filterStrength}
              onChange={(e) => setFilterStrength(e.target.value)}
              placeholder="1"
              inputMode="numeric"
            />
          </label>
          <label className="field">
            <span>Color</span>
            <input
              className="adv-input-sm"
              value={filterColor}
              onChange={(e) => setFilterColor(e.target.value)}
              placeholder="#ffffff"
            />
          </label>
        </div>
        <div className="row wrap">
          <button className="btn btn-primary" onClick={() => void runApplyFilter()} disabled={isBusy}>
            {busy === 'applyFilter' ? 'Applying…' : 'Apply filter'}
          </button>
          <button className="btn w2-danger" onClick={() => void runClearFilters()} disabled={isBusy}>
            {busy === 'clearFilters' ? 'Clearing…' : 'Clear filters'}
          </button>
        </div>
        {filterRows && <ResultChips chips={filterChips} motionMs={motionMs} title="Filter" />}
      </section>

      <div className="row sticky-actions">
        <span className="muted">{status}</span>
      </div>
    </div>
  );
}
