/**
 * Linkage tab (uplifted).
 *  - scanLinkage -> richer sortable / filterable table of every library item.
 *  - "missing linkage" highlight + a coverage summary bar.
 *  - a D3 coverage chart (exported vs missing, by item type) that doubles as a
 *    type filter (click a row to scope the table).
 *  - a "folder name convention" input drives the generated identifier:
 *      pattern tokens: {name} = item name, {base} = name without folder path,
 *      {dir} = the convention prefix you type. e.g. "avatars/{base}".
 *  - batch applyLinkage with the generated identifiers (flow unchanged).
 *
 * Bridge contract is untouched: still host.scanLinkage() / host.applyLinkage().
 */
import { useCallback, useMemo, useRef, useState } from 'react';
import { authoring } from '@cf7-animate-kit/core';
import type { LinkageItem as CoreLinkageItem, LintFinding } from '@cf7-animate-kit/core';
import {
  host,
  type LinkageItem,
  type LinkageAssignment,
  type ApplyLinkageResult,
} from '../bridge.js';
import LinkageCoverageChart, { type CoverageRow } from './LinkageCoverageChart.js';
import ResultChips, { type ResultChip } from './ResultChips.js';
import ResizeHandle from './ResizeHandle.js';
import { useStoredString, useStoredNumber } from '../hooks/useLocalStorage.js';
import { useLayoutResize } from '../hooks/useLayoutResize.js';
import { getMotionProfile } from './motion-utils.js';

/** Symbol item types that can carry AS linkage. */
const LINKABLE = new Set(['movie clip', 'graphic', 'button', 'bitmap', 'sound', 'font']);

/** Item types that come from the "media" source (vs symbol) for core's lint. */
const MEDIA_TYPES = new Set(['bitmap', 'sound', 'video', 'font']);

type SortKey = 'name' | 'itemType' | 'linkage';
type SortDir = 'asc' | 'desc';
type RowFilter = 'all' | 'missing' | 'exported';

function baseName(name: string): string {
  const i = name.lastIndexOf('/');
  return i >= 0 ? name.slice(i + 1) : name;
}

/** Apply the folder convention pattern to a single item name. */
function makeIdentifier(pattern: string, dir: string, name: string): string {
  const id = pattern
    .replace(/\{name\}/g, name)
    .replace(/\{base\}/g, baseName(name))
    .replace(/\{dir\}/g, dir);
  return id.replace(/[\\/\s]+/g, '_').replace(/[^A-Za-z0-9_$]/g, '');
}

export function LinkageTab({ motionMs = 140 }: { motionMs?: number }) {
  const [items, setItems] = useState<LinkageItem[]>([]);
  const [checked, setChecked] = useState<Record<string, boolean>>({});
  const [dir, setDir] = useStoredString('cf7ak:linkage:dir', 'avatars');
  const [pattern, setPattern] = useStoredString('cf7ak:linkage:pattern', '{dir}_{base}');
  const [busy, setBusy] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [applied, setApplied] = useState<ApplyLinkageResult[] | null>(null);

  // Table view state (persisted where it makes sense).
  const [query, setQuery] = useState('');
  const [rowFilter, setRowFilter] = useStoredString<RowFilter>('cf7ak:linkage:filter', 'all');
  const [typeFilter, setTypeFilter] = useState<string | null>(null);
  const [sortKey, setSortKey] = useStoredString<SortKey>('cf7ak:linkage:sortKey', 'linkage');
  const [sortDir, setSortDir] = useStoredString<SortDir>('cf7ak:linkage:sortDir', 'asc');

  // Resizable split between the table and the coverage chart.
  const splitRef = useRef<HTMLDivElement>(null);
  const motionProfile = useMemo(() => getMotionProfile(motionMs > 0 ? 'light' : 'off'), [motionMs]);
  const { isLayoutResizing, activeResizeHandle, beginResize } = useLayoutResize(motionProfile);
  const [tableSplit, setTableSplit] = useStoredNumber(
    'cf7ak:linkage:tableSplit',
    0.62,
    !isLayoutResizing,
  );

  const scan = useCallback(async () => {
    setBusy(true);
    setStatus(null);
    setApplied(null);
    const res = await host.scanLinkage();
    if (res.ok) {
      setItems(res.data.items);
      const next: Record<string, boolean> = {};
      for (const it of res.data.items) {
        if (LINKABLE.has(it.itemType) && !it.linkageExportForAS) next[it.name] = true;
      }
      setChecked(next);
      setStatus(`scanned ${res.data.count} library items`);
    } else {
      setItems([]);
      setStatus(`scan failed: ${res.error}`);
    }
    setBusy(false);
  }, []);

  const toggle = useCallback((name: string) => {
    setChecked((c) => ({ ...c, [name]: !c[name] }));
  }, []);

  // ---- Coverage summary + chart data -------------------------------------
  const linkableItems = useMemo(
    () => items.filter((it) => LINKABLE.has(it.itemType)),
    [items],
  );

  const coverage = useMemo(() => {
    const total = linkableItems.length;
    const exported = linkableItems.filter((it) => it.linkageExportForAS).length;
    return { total, exported, missing: total - exported };
  }, [linkableItems]);

  const coverageRows = useMemo<CoverageRow[]>(() => {
    const byType = new Map<string, CoverageRow>();
    for (const it of linkableItems) {
      const row = byType.get(it.itemType) ?? { type: it.itemType, exported: 0, missing: 0 };
      if (it.linkageExportForAS) row.exported += 1;
      else row.missing += 1;
      byType.set(it.itemType, row);
    }
    return [...byType.values()].sort((a, b) => b.exported + b.missing - (a.exported + a.missing));
  }, [linkableItems]);

  // ---- Selection-bulk helpers --------------------------------------------
  const selectableNames = useMemo(
    () => linkableItems.filter((it) => !it.linkageExportForAS).map((it) => it.name),
    [linkableItems],
  );
  const selectAllMissing = useCallback(() => {
    setChecked(() => {
      const next: Record<string, boolean> = {};
      for (const n of selectableNames) next[n] = true;
      return next;
    });
  }, [selectableNames]);
  const clearSelection = useCallback(() => setChecked({}), []);

  // ---- Filter + sort the visible rows ------------------------------------
  const visibleItems = useMemo(() => {
    const q = query.trim().toLowerCase();
    let rows = items.filter((it) => {
      if (typeFilter && it.itemType !== typeFilter) return false;
      if (rowFilter === 'missing' && (it.linkageExportForAS || !LINKABLE.has(it.itemType))) return false;
      if (rowFilter === 'exported' && !it.linkageExportForAS) return false;
      if (q && !it.name.toLowerCase().includes(q)) return false;
      return true;
    });
    const dirMul = sortDir === 'asc' ? 1 : -1;
    rows = rows.slice().sort((a, b) => {
      if (sortKey === 'name') return a.name.localeCompare(b.name) * dirMul;
      if (sortKey === 'itemType') {
        const t = a.itemType.localeCompare(b.itemType);
        return (t !== 0 ? t : a.name.localeCompare(b.name)) * dirMul;
      }
      // "linkage": missing (0) before exported (1), then by name.
      const la = a.linkageExportForAS ? 1 : 0;
      const lb = b.linkageExportForAS ? 1 : 0;
      const c = la - lb;
      return (c !== 0 ? c : a.name.localeCompare(b.name)) * dirMul;
    });
    return rows;
  }, [items, query, rowFilter, typeFilter, sortKey, sortDir]);

  const toggleSort = useCallback(
    (key: SortKey) => {
      if (sortKey === key) {
        setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'));
      } else {
        setSortKey(key);
        setSortDir('asc');
      }
    },
    [sortKey, setSortDir, setSortKey],
  );

  const sortArrow = (key: SortKey) => (sortKey === key ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '');

  // ---- Apply preview + lint ----------------------------------------------
  const selected = useMemo(() => items.filter((it) => checked[it.name]), [items, checked]);

  const preview = useMemo<LinkageAssignment[]>(
    () =>
      selected.map((it) => ({
        name: it.name,
        linkageIdentifier: makeIdentifier(pattern, dir, it.name),
        exportForAS: true,
      })),
    [selected, pattern, dir],
  );

  const lint = useMemo<LintFinding[]>(() => {
    const pendingById = new Map(preview.map((a) => [a.name, a.linkageIdentifier]));
    const projected: CoreLinkageItem[] = items
      .filter((it) => LINKABLE.has(it.itemType))
      .map((it) => {
        const pendingId = pendingById.get(it.name);
        const source: CoreLinkageItem['source'] = MEDIA_TYPES.has(it.itemType) ? 'media' : 'symbol';
        if (pendingId != null) {
          return { name: it.name, source, linkageExportForAS: true, linkageIdentifier: pendingId };
        }
        return {
          name: it.name,
          source,
          linkageExportForAS: it.linkageExportForAS,
          linkageIdentifier: it.linkageIdentifier,
        };
      });
    return authoring.lintLinkage(projected);
  }, [items, preview]);

  const lintSummary = useMemo(() => authoring.summarizeLint(lint), [lint]);

  const apply = useCallback(async () => {
    if (preview.length === 0) {
      setStatus('nothing selected');
      return;
    }
    setBusy(true);
    setStatus(null);
    const res = await host.applyLinkage(preview);
    if (res.ok) {
      setApplied(res.data.applied);
      const okN = res.data.applied.filter((a) => a.ok).length;
      setStatus(`applied linkage to ${okN}/${res.data.count}`);
      void scan();
    } else {
      setStatus(`apply failed: ${res.error}`);
    }
    setBusy(false);
  }, [preview, scan]);

  const appliedChips = useMemo<ResultChip[]>(
    () =>
      (applied ?? []).map((a) => ({
        key: a.name,
        state: a.ok ? 'ok' : 'err',
        label: a.name,
        detail: a.linkageIdentifier
          ? `→ ${a.linkageIdentifier}`
          : a.error
            ? a.error
            : undefined,
      })),
    [applied],
  );

  const coveragePct = coverage.total > 0 ? Math.round((coverage.exported / coverage.total) * 100) : 0;

  return (
    <div className="tab-body">
      <div className="row">
        <button className="btn" onClick={() => void scan()} disabled={busy}>
          {busy ? 'Scanning…' : 'Scan linkage'}
        </button>
        <span className="muted">{status}</span>
      </div>

      {coverage.total > 0 && (
        <div className="coverage-summary">
          <div className="coverage-meter" title={`${coverage.exported} of ${coverage.total} linkable items export for ActionScript`}>
            <div className="coverage-fill" style={{ width: `${coveragePct}%` }} />
          </div>
          <div className="coverage-legend">
            <span className="cov-stat cov-pct">{coveragePct}% covered</span>
            <span className="cov-stat cov-ok">{coverage.exported} exported</span>
            <span className="cov-stat cov-missing">{coverage.missing} missing</span>
            <span className="cov-stat muted">{coverage.total} linkable</span>
          </div>
        </div>
      )}

      <div className="row wrap">
        <label className="field">
          <span>Folder / dir</span>
          <input value={dir} onChange={(e) => setDir(e.target.value)} placeholder="avatars" />
        </label>
        <label className="field grow">
          <span>Identifier pattern</span>
          <input
            value={pattern}
            onChange={(e) => setPattern(e.target.value)}
            placeholder="{dir}_{base}"
          />
        </label>
      </div>
      <div className="hint">
        Tokens: <code>{'{name}'}</code> full name, <code>{'{base}'}</code> leaf,{' '}
        <code>{'{dir}'}</code> the field above.
      </div>

      {/* Table + chart, vertically resizable. */}
      <div className="linkage-split" ref={splitRef}>
        <section
          className="linkage-pane"
          style={{ flexBasis: `${tableSplit * 100}%`, flexGrow: 0, flexShrink: 0 }}
        >
          <div className="table-toolbar">
            <input
              className="search-input"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Filter by name…"
            />
            <div className="seg" role="group" aria-label="Linkage filter">
              {(['all', 'missing', 'exported'] as RowFilter[]).map((f) => (
                <button
                  key={f}
                  className={`seg-btn ${rowFilter === f ? 'active' : ''}`}
                  onClick={() => setRowFilter(f)}
                >
                  {f}
                </button>
              ))}
            </div>
            <div className="table-bulk">
              <button className="btn-mini" onClick={selectAllMissing} disabled={selectableNames.length === 0}>
                Select missing
              </button>
              <button className="btn-mini" onClick={clearSelection} disabled={selected.length === 0}>
                Clear
              </button>
            </div>
          </div>

          {typeFilter && (
            <div className="active-filter">
              type = <strong>{typeFilter}</strong>
              <button className="chip-x" onClick={() => setTypeFilter(null)} title="Clear type filter">
                ✕
              </button>
            </div>
          )}

          <div className="table-scroll table-scroll-grow">
            <table className="grid">
              <thead>
                <tr>
                  <th className="th-check" />
                  <th className="sortable" onClick={() => toggleSort('name')}>
                    Item{sortArrow('name')}
                  </th>
                  <th className="sortable" onClick={() => toggleSort('itemType')}>
                    Type{sortArrow('itemType')}
                  </th>
                  <th className="sortable" onClick={() => toggleSort('linkage')}>
                    Identifier →{sortArrow('linkage')}
                  </th>
                </tr>
              </thead>
              <tbody>
                {visibleItems.map((it) => {
                  const linkable = LINKABLE.has(it.itemType);
                  const isMissing = linkable && !it.linkageExportForAS;
                  const id =
                    checked[it.name] && linkable
                      ? makeIdentifier(pattern, dir, it.name)
                      : it.linkageExportForAS
                        ? (it.linkageIdentifier ?? '')
                        : '';
                  const rowCls = [
                    it.linkageExportForAS ? 'has-linkage' : '',
                    isMissing ? 'is-missing' : '',
                    checked[it.name] ? 'is-checked' : '',
                  ]
                    .filter(Boolean)
                    .join(' ');
                  return (
                    <tr key={it.name} className={rowCls}>
                      <td className="td-check">
                        <input
                          type="checkbox"
                          checked={!!checked[it.name]}
                          disabled={!linkable}
                          onChange={() => toggle(it.name)}
                        />
                      </td>
                      <td className="ellipsis" title={it.name}>
                        {isMissing && <span className="missing-dot" title="missing AS linkage" />}
                        {it.name}
                      </td>
                      <td className="muted">{it.itemType}</td>
                      <td className="ellipsis mono" title={id}>
                        {id}
                      </td>
                    </tr>
                  );
                })}
                {visibleItems.length === 0 && (
                  <tr>
                    <td colSpan={4} className="muted center">
                      {items.length === 0
                        ? 'No items — run a scan with a FLA open.'
                        : 'No items match the current filter.'}
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>
          <div className="table-footnote muted">
            {visibleItems.length} shown / {items.length} total · {selected.length} selected
          </div>
        </section>

        {coverageRows.length > 0 && (
          <>
            <ResizeHandle
              orientation="horizontal"
              title="Drag to resize table vs coverage chart"
              isActive={activeResizeHandle === 'linkageTable'}
              onStartResize={(clientX, clientY) =>
                beginResize(clientX, clientY, {
                  handleId: 'linkageTable',
                  container: splitRef,
                  axis: 'y',
                  min: 0.3,
                  max: 0.82,
                  setValue: setTableSplit,
                })
              }
            />
            <section className="linkage-pane chart-pane">
              <div className="pane-title">
                <span>Coverage by type</span>
                <span className="muted pane-hint">click a bar to filter</span>
              </div>
              <LinkageCoverageChart
                rows={coverageRows}
                motionDurationMs={motionMs}
                activeType={typeFilter}
                onSelectType={setTypeFilter}
              />
            </section>
          </>
        )}
      </div>

      {lintSummary.errors > 0 && (
        <div className="results lint-block">
          <div className="res-err">
            ⚠ {lintSummary.errors} linkage error{lintSummary.errors === 1 ? '' : 's'} would result —
            fix before applying:
          </div>
          {lint
            .filter((f) => f.level === 'error')
            .map((f, i) => (
              <div key={`${f.code}-${i}`} className="res-err">
                • {f.message}
              </div>
            ))}
        </div>
      )}

      <div className="row sticky-actions">
        <button
          className="btn btn-primary"
          onClick={() => void apply()}
          disabled={busy || preview.length === 0 || lintSummary.errors > 0}
        >
          Apply linkage to {preview.length} selected
        </button>
      </div>

      {applied && <ResultChips chips={appliedChips} motionMs={motionMs} title="Applied" />}
    </div>
  );
}
