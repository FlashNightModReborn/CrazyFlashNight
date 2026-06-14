/**
 * bridge.ts — typed wrapper over the JSFL host (../jsfl-host/host/index.jsfl).
 *
 * Contract (see ../../jsfl-host/README.md):
 *   - The panel calls ONE dispatcher: `cf7ak(fnName, argJson)`.
 *   - `argJson` is a JSON *string* — we double-encode the argument object.
 *   - The host returns a JSON *string*: `{ ok:true, data }` | `{ ok:false, error }`.
 *   - On a host-side throw, CSInterface yields the literal `"EvalScript error."`.
 *
 * Everything network-facing is intentionally absent: this only talks to the
 * local Animate scripting VM through CSInterface.evalScript.
 */

import { CSInterface } from './lib/CSInterface.js';

// ---------------------------------------------------------------------------
// Host result shapes (mirror host/index.jsfl return payloads).
// ---------------------------------------------------------------------------

export interface PingData {
  pong: boolean;
  flVersion: string;
}

export interface ProbeData {
  flVersion: string;
  hasDocument: boolean;
  hasSpriteSheetExporter: boolean;
  hasFLfile: boolean;
  hasJSON: boolean;
}

export interface LinkageItem {
  name: string;
  itemType: string;
  linkageExportForAS: boolean;
  /** Present only when linkageExportForAS is true. */
  linkageIdentifier?: string;
  /** Present only when linkageExportForAS is true. */
  linkageClassName?: string;
}

export interface ScanLinkageData {
  count: number;
  items: LinkageItem[];
}

export interface LinkageAssignment {
  name: string;
  linkageIdentifier: string;
  exportForAS?: boolean;
  className?: string;
}

export interface ApplyLinkageArgs {
  assignments: LinkageAssignment[];
}

export interface ApplyLinkageResult {
  name: string;
  ok: boolean;
  linkageIdentifier?: string | null;
  error?: string;
}

export interface ApplyLinkageData {
  count: number;
  applied: ApplyLinkageResult[];
}

export interface FrameLabelRow {
  layer: string;
  index: number;
  name: string;
  labelType: string;
  duration: number;
}

export interface ListFrameLabelsArgs {
  symbolName?: string;
}

export interface ListFrameLabelsData {
  timeline: string;
  count: number;
  labels: FrameLabelRow[];
}

export interface ExportSelectedArgs {
  outDir: string;
  layoutFormat?: string;
  algorithm?: string;
  trim?: boolean;
  borderPadding?: number;
  shapePadding?: number;
}

export interface ExportResultRow {
  name: string;
  ok: boolean;
  png?: string;
  error?: string;
  skipped?: boolean;
  reason?: string;
}

export interface ExportSelectedData {
  outDir: string;
  count: number;
  results: ExportResultRow[];
}

export interface PublishArgs {
  profile?: string;
}

export interface PublishData {
  published: boolean;
  doc: string;
  profile: string;
}

// ---------------------------------------------------------------------------
// Wave 1 "高阶 / Advanced" host functions (mirror host/index.jsfl payloads).
// All paths are platform paths (Windows "C:/..."); the host converts to
// file:// URIs internally. The bridge contract (single cf7ak dispatcher,
// double-encoded argJson) is unchanged — these are just new fn names.
// ---------------------------------------------------------------------------

/** One row from `listLibrary` — a flattened view of a dom.library item. */
export interface LibraryItemRow {
  name: string;
  itemType: string;
  /** Present for symbol items: 'movie clip' | 'graphic' | 'button'. */
  symbolType?: string;
  exportForAS: boolean;
  linkageIdentifier: string;
}

export interface ListLibraryData {
  count: number;
  items: LibraryItemRow[];
}

export interface ExportStagePNGArgs {
  outFile: string;
  currentFrameOnly?: boolean;
  exactBounds?: boolean;
}

export interface ExportStagePNGData {
  file: string;
}

export interface ExportFrameSequenceArgs {
  outDir: string;
  prefix?: string;
  from?: number;
  to?: number;
}

export interface ExportFrameSequenceData {
  outDir: string;
  count: number;
  files: string[];
}

export interface BatchExportSymbolsArgs {
  outDir: string;
  /** Omit to export the currently selected library symbols. */
  names?: string[];
  layoutFormat?: string;
  algorithm?: string;
}

export interface BatchExportSymbolRow {
  name: string;
  ok: boolean;
  png?: string;
  error?: string;
}

export interface BatchExportSymbolsData {
  outDir: string;
  count: number;
  results: BatchExportSymbolRow[];
}

export interface ExportLibraryBitmapsArgs {
  outDir: string;
  /** Omit to export selected bitmaps, or all bitmaps if nothing is selected. */
  names?: string[];
}

export interface ExportLibraryMediaRow {
  name: string;
  ok: boolean;
  file?: string;
  error?: string;
  skipped?: boolean;
  reason?: string;
}

export interface ExportLibraryBitmapsData {
  outDir: string;
  count: number;
  results: ExportLibraryMediaRow[];
}

export interface ExportLibrarySoundsArgs {
  outDir: string;
  names?: string[];
}

export interface ExportLibrarySoundsData {
  outDir: string;
  count: number;
  results: ExportLibraryMediaRow[];
}

export interface SafeSaveArgs {
  backupDir?: string;
}

export interface SafeSaveData {
  saved: boolean;
  backupFile?: string;
}

export interface OpenDocumentArgs {
  file: string;
}

export interface OpenDocumentData {
  opened: boolean;
  name: string;
}

// ---------------------------------------------------------------------------
// Wave 2 "库 / 帧 / 滤镜" host functions (mirror host/index.jsfl payloads).
// Same single-dispatcher contract — these are just new fn names on cf7ak().
// Library ops mutate dom.library; frame ops operate on the current timeline /
// frame selection; filter ops operate on the current stage selection.
// ---------------------------------------------------------------------------

// ---- 库治理 (library) ----

export interface LibBatchRenameArgs {
  find: string;
  replace: string;
  /** Treat `find` as a RegExp (new RegExp(find)) instead of a substring. */
  useRegex?: boolean;
  /** Restrict to these item paths; omit to target all matching items. */
  names?: string[];
}

export interface LibRenameRow {
  from: string;
  to: string;
  ok: boolean;
  error?: string;
}

export interface LibBatchRenameData {
  count: number;
  renamed: LibRenameRow[];
}

export interface LibNewFolderArgs {
  path: string;
}

export interface LibNewFolderData {
  created: boolean;
  path: string;
}

export interface LibMoveToFolderArgs {
  folder: string;
  /** Restrict to these item paths; omit to move all items. */
  names?: string[];
}

export interface LibMoveRow {
  name: string;
  ok: boolean;
  error?: string;
}

export interface LibMoveToFolderData {
  count: number;
  moved: LibMoveRow[];
}

export interface LibDeleteItemsArgs {
  names: string[];
}

export interface LibDeleteRow {
  name: string;
  ok: boolean;
  error?: string;
}

export interface LibDeleteItemsData {
  count: number;
  deleted: LibDeleteRow[];
}

// ---- 帧 (frames) — operate on the current main timeline / frame selection ----

export interface FramesInsertArgs {
  count?: number;
  atEnd?: boolean;
}

export interface FramesRemoveArgs {
  count?: number;
}

/** Insert/remove report the resulting frame count; reverse/convert/clear are bare ok. */
export interface FramesCountData {
  ok: boolean;
  frameCount: number;
}

export interface FramesOkData {
  ok: boolean;
}

// ---- 滤镜 (filters) — operate on the current stage selection ----

export type FilterType = 'glow' | 'dropShadow' | 'blur' | 'bevel' | 'gradientGlow';

export interface ApplyFilterArgs {
  type: FilterType;
  /** Per-type overrides merged onto the host's sane defaults. */
  params?: Record<string, unknown>;
}

export interface ApplyFilterRow {
  name?: string;
  ok: boolean;
  error?: string;
}

export interface ApplyFilterData {
  count: number;
  applied: ApplyFilterRow[];
}

export interface ClearFiltersData {
  count: number;
}

// ---------------------------------------------------------------------------
// Wave 3 "预设 / 位图 / 诊断" host functions (mirror host/index.jsfl payloads).
// Same single-dispatcher contract — these are just new fn names on cf7ak().
//   • presets  — file-backed CRUD at <Configuration>/Commands/cf7ak/presets.json.
//     A preset = { name, fn, args } so ANY cf7ak op + its args can be re-applied.
//   • bitmap   — traceBitmap on the current stage selection; set BitmapItem
//     compression on library bitmaps.
//   • diagnostics — read-only environment / active-doc dump.
// ---------------------------------------------------------------------------

// ---- 预设 (presets) ----

/** A saved operation: a host fn name + the (already-parsed) args object. */
export interface Preset {
  name: string;
  fn: string;
  args: unknown;
}

export interface PresetSaveArgs {
  name: string;
  fn: string;
  args: unknown;
}

export interface PresetSaveData {
  ok: boolean;
  count: number;
}

export interface PresetListData {
  count: number;
  presets: Preset[];
}

export interface PresetApplyArgs {
  name: string;
}

export interface PresetApplyData {
  applied: string;
  /** The parsed result of the re-applied fn (host envelope's `data` or whole). */
  result: unknown;
}

export interface PresetDeleteArgs {
  name: string;
}

export interface PresetDeleteData {
  deleted: boolean;
  count: number;
}

// ---- 位图 (bitmap) ----

export type CurveFit =
  | 'pixels'
  | 'very tight'
  | 'tight'
  | 'normal'
  | 'smooth'
  | 'very smooth';

export interface BitmapTraceArgs {
  threshold?: number;
  minArea?: number;
  curveFit?: CurveFit;
  cornerThreshold?: CurveFit;
}

export interface BitmapTraceData {
  ok: boolean;
}

export type BitmapCompressionType = 'photo' | 'lossless';

export interface BitmapSetCompressionArgs {
  /** Omit to target the selected bitmaps, or all bitmaps if nothing selected. */
  names?: string[];
  compressionType?: BitmapCompressionType;
  /** Only meaningful for 'photo' (0-100). */
  quality?: number;
  allowSmoothing?: boolean;
}

export interface BitmapSetCompressionRow {
  name: string;
  ok: boolean;
  error?: string;
  skipped?: boolean;
}

export interface BitmapSetCompressionData {
  count: number;
  applied: BitmapSetCompressionRow[];
}

// ---- 诊断 (diagnostics) ----

export interface DiagnosticsActiveDoc {
  name: string;
  pathURI?: string;
  sceneCount: number;
  libraryItemCount: number;
  timelineFrameCount: number;
}

export interface DiagnosticsReport {
  flVersion: string;
  platform: string;
  openDocCount: number;
  activeDoc: DiagnosticsActiveDoc | null;
  configURI: string;
  hasSpriteSheetExporter: boolean;
  hasFLfile: boolean;
}

export interface CrashDiagnosticsData {
  report: DiagnosticsReport;
}

/** Maps each host function name to its argument and `data` payload types. */
export interface HostFnMap {
  ping: { args: Record<string, never>; data: PingData };
  probe: { args: Record<string, never>; data: ProbeData };
  scanLinkage: { args: Record<string, never>; data: ScanLinkageData };
  applyLinkage: { args: ApplyLinkageArgs; data: ApplyLinkageData };
  listFrameLabels: { args: ListFrameLabelsArgs; data: ListFrameLabelsData };
  exportSelected: { args: ExportSelectedArgs; data: ExportSelectedData };
  publish: { args: PublishArgs; data: PublishData };
  // Wave 1 advanced functions.
  listLibrary: { args: Record<string, never>; data: ListLibraryData };
  exportStagePNG: { args: ExportStagePNGArgs; data: ExportStagePNGData };
  exportFrameSequence: { args: ExportFrameSequenceArgs; data: ExportFrameSequenceData };
  batchExportSymbols: { args: BatchExportSymbolsArgs; data: BatchExportSymbolsData };
  exportLibraryBitmaps: { args: ExportLibraryBitmapsArgs; data: ExportLibraryBitmapsData };
  exportLibrarySounds: { args: ExportLibrarySoundsArgs; data: ExportLibrarySoundsData };
  safeSave: { args: SafeSaveArgs; data: SafeSaveData };
  openDocument: { args: OpenDocumentArgs; data: OpenDocumentData };
  // Wave 2 — 库治理 (library).
  libBatchRename: { args: LibBatchRenameArgs; data: LibBatchRenameData };
  libNewFolder: { args: LibNewFolderArgs; data: LibNewFolderData };
  libMoveToFolder: { args: LibMoveToFolderArgs; data: LibMoveToFolderData };
  libDeleteItems: { args: LibDeleteItemsArgs; data: LibDeleteItemsData };
  // Wave 2 — 帧 (frames, current selection).
  framesInsert: { args: FramesInsertArgs; data: FramesCountData };
  framesRemove: { args: FramesRemoveArgs; data: FramesCountData };
  framesReverse: { args: Record<string, never>; data: FramesOkData };
  framesConvertToKeyframes: { args: Record<string, never>; data: FramesOkData };
  framesClearKeyframes: { args: Record<string, never>; data: FramesOkData };
  // Wave 2 — 滤镜 (filters, current stage selection).
  applyFilter: { args: ApplyFilterArgs; data: ApplyFilterData };
  clearFilters: { args: Record<string, never>; data: ClearFiltersData };
  // Wave 3 — 预设 (presets, file-backed CRUD; no open doc required for CRUD).
  presetSave: { args: PresetSaveArgs; data: PresetSaveData };
  presetList: { args: Record<string, never>; data: PresetListData };
  presetApply: { args: PresetApplyArgs; data: PresetApplyData };
  presetDelete: { args: PresetDeleteArgs; data: PresetDeleteData };
  // Wave 3 — 位图 (bitmap, stage selection / library bitmaps).
  bitmapTrace: { args: BitmapTraceArgs; data: BitmapTraceData };
  bitmapSetCompression: { args: BitmapSetCompressionArgs; data: BitmapSetCompressionData };
  // Wave 3 — 诊断 (diagnostics, read-only environment dump).
  crashDiagnostics: { args: Record<string, never>; data: CrashDiagnosticsData };
}

export type HostFn = keyof HostFnMap;

/** Discriminated result. `ok:false` carries a human-readable `error`. */
export type HostResult<T> =
  | { ok: true; data: T }
  | { ok: false; error: string };

// ---------------------------------------------------------------------------
// Low-level call.
// ---------------------------------------------------------------------------

const cs = new CSInterface();

/** True when running inside a real CEP host (vs a plain browser preview). */
export function hasHostBridge(): boolean {
  return cs.hasHostBridge();
}

/** Best-effort host-app label for the Doctor strip. */
export function hostLabel(): string {
  const env = cs.getHostEnvironment();
  if (!env) return 'no CEP host (browser preview)';
  return `${env.appName} ${env.appVersion}`;
}

/**
 * Escape a JSON string for safe embedding inside the `cf7ak('fn', '<here>')`
 * single-quoted JSFL string literal. We JSON.stringify the object, then
 * JSON.stringify *that* string — which produces a correctly-escaped,
 * double-quoted JS string literal the host's `JSON.parse` round-trips. This is
 * the "double-encode" the contract describes and it sidesteps quote-injection.
 */
function encodeArg(argObj: unknown): string {
  const inner = JSON.stringify(argObj ?? {});
  // JSON.stringify of a string yields a valid JS string literal (with quotes),
  // e.g.  {"a":1}  ->  "{\"a\":1}". Embeds cleanly into evalScript.
  return JSON.stringify(inner);
}

/**
 * Call a host function. Resolves to a `HostResult`; never rejects for host or
 * parse errors — those become `{ ok:false, error }` so callers branch on one
 * shape. (It can still reject only if `evalScript` itself is missing, which
 * `hasHostBridge()` already guards.)
 */
export function callHost<K extends HostFn>(
  fn: K,
  argObj: HostFnMap[K]['args'],
): Promise<HostResult<HostFnMap[K]['data']>> {
  return new Promise((resolve) => {
    const argLiteral = encodeArg(argObj);
    const expr = `cf7ak('${fn}', ${argLiteral})`;
    cs.evalScript(expr, (raw: string) => {
      // 1) Host-side throw / CEP eval failure sentinel.
      if (raw === 'EvalScript error.') {
        resolve({
          ok: false,
          error:
            'EvalScript error (host threw or JSFL host not loaded). ' +
            'Is a FLA open and is host/index.jsfl wired via the manifest ScriptPath?',
        });
        return;
      }
      // 2) Empty / undefined result (no host, dev preview, or unknown fn path).
      if (raw == null || raw === '' || raw === 'undefined') {
        resolve({ ok: false, error: `empty host result for "${fn}"` });
        return;
      }
      // 3) Parse the host's JSON string.
      let parsed: unknown;
      try {
        parsed = JSON.parse(raw);
      } catch (e) {
        resolve({
          ok: false,
          error: `could not parse host result for "${fn}": ${String(e)} — raw: ${raw.slice(0, 200)}`,
        });
        return;
      }
      // 4) Validate the { ok, data|error } envelope.
      if (
        typeof parsed === 'object' &&
        parsed !== null &&
        'ok' in parsed &&
        typeof (parsed as { ok: unknown }).ok === 'boolean'
      ) {
        const env = parsed as
          | { ok: true; data: HostFnMap[K]['data'] }
          | { ok: false; error: string };
        if (env.ok) {
          resolve({ ok: true, data: env.data });
        } else {
          resolve({ ok: false, error: String(env.error ?? 'unknown host error') });
        }
        return;
      }
      resolve({
        ok: false,
        error: `malformed host envelope for "${fn}": ${raw.slice(0, 200)}`,
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Thin, named convenience wrappers (nicer call-sites in components).
// ---------------------------------------------------------------------------

export const host = {
  ping: () => callHost('ping', {}),
  probe: () => callHost('probe', {}),
  scanLinkage: () => callHost('scanLinkage', {}),
  applyLinkage: (assignments: LinkageAssignment[]) =>
    callHost('applyLinkage', { assignments }),
  listFrameLabels: (symbolName?: string) =>
    callHost(
      'listFrameLabels',
      symbolName ? { symbolName } : {},
    ),
  exportSelected: (args: ExportSelectedArgs) => callHost('exportSelected', args),
  publish: (profile?: string) =>
    callHost('publish', profile ? { profile } : {}),
  // ---- Wave 1 advanced wrappers ----
  listLibrary: () => callHost('listLibrary', {}),
  exportStagePNG: (args: ExportStagePNGArgs) => callHost('exportStagePNG', args),
  exportFrameSequence: (args: ExportFrameSequenceArgs) =>
    callHost('exportFrameSequence', args),
  batchExportSymbols: (args: BatchExportSymbolsArgs) =>
    callHost('batchExportSymbols', args),
  exportLibraryBitmaps: (args: ExportLibraryBitmapsArgs) =>
    callHost('exportLibraryBitmaps', args),
  exportLibrarySounds: (args: ExportLibrarySoundsArgs) =>
    callHost('exportLibrarySounds', args),
  safeSave: (backupDir?: string) =>
    callHost('safeSave', backupDir ? { backupDir } : {}),
  openDocument: (file: string) => callHost('openDocument', { file }),
  // ---- Wave 2: 库治理 (library) ----
  libBatchRename: (args: LibBatchRenameArgs) => callHost('libBatchRename', args),
  libNewFolder: (path: string) => callHost('libNewFolder', { path }),
  libMoveToFolder: (args: LibMoveToFolderArgs) => callHost('libMoveToFolder', args),
  libDeleteItems: (names: string[]) => callHost('libDeleteItems', { names }),
  // ---- Wave 2: 帧 (frames, current selection) ----
  framesInsert: (args: FramesInsertArgs = {}) => callHost('framesInsert', args),
  framesRemove: (args: FramesRemoveArgs = {}) => callHost('framesRemove', args),
  framesReverse: () => callHost('framesReverse', {}),
  framesConvertToKeyframes: () => callHost('framesConvertToKeyframes', {}),
  framesClearKeyframes: () => callHost('framesClearKeyframes', {}),
  // ---- Wave 2: 滤镜 (filters, current stage selection) ----
  applyFilter: (args: ApplyFilterArgs) => callHost('applyFilter', args),
  clearFilters: () => callHost('clearFilters', {}),
  // ---- Wave 3: 预设 (presets, file-backed CRUD) ----
  presetSave: (args: PresetSaveArgs) => callHost('presetSave', args),
  presetList: () => callHost('presetList', {}),
  presetApply: (name: string) => callHost('presetApply', { name }),
  presetDelete: (name: string) => callHost('presetDelete', { name }),
  // ---- Wave 3: 位图 (bitmap) ----
  bitmapTrace: (args: BitmapTraceArgs = {}) => callHost('bitmapTrace', args),
  bitmapSetCompression: (args: BitmapSetCompressionArgs = {}) =>
    callHost('bitmapSetCompression', args),
  // ---- Wave 3: 诊断 (diagnostics, read-only) ----
  crashDiagnostics: () => callHost('crashDiagnostics', {}),
} as const;
