/**
 * Typed IPC contract between the Electron main process and the React renderer.
 *
 * The renderer NEVER imports @cf7-animate-kit/an-host or node:fs. It reaches the
 * machine ONLY through `window.ankit.*`, which the preload contextBridge wires to
 * `ipcRenderer.invoke(...)` against the channels registered in src/electron.
 *
 * These types intentionally mirror (a structural subset of) the an-host / core
 * return shapes so the renderer can stay decoupled from those packages' module
 * graphs. They are kept in `shared/` so both sides compile against one source.
 */

// ---------------------------------------------------------------------------
// AN maintenance (Tab A) — mirrors @cf7-animate-kit/an-host OpResult family
// ---------------------------------------------------------------------------

export type FileAction = "create" | "overwrite" | "delete" | "clear" | "noop";

export interface FileChange {
  path: string;
  action: FileAction;
  backup?: string | null;
  note?: string;
}

export interface OpResult {
  ok: boolean;
  applied: boolean;
  summary: string;
  changes: FileChange[];
  warnings: string[];
}

export interface JvmOpResult extends OpResult {
  previousXmxMb: number | null;
  newXmxMb: number;
  newXmsMb: number;
}

/** One discovered Adobe Animate install (paths + existence flags). */
export interface AnimateInstall {
  windowSwfDir: string;
  configurationDir: string;
  commandsDir: string;
  jvmIniPath: string;
  cacheDir: string;
  windowSwfExists: boolean;
  jvmIniExists: boolean;
  commandsExists: boolean;
}

/** Clean diagnostic report (NO machine id / MAC / activation). */
export interface MachineInfo {
  platform: string;
  osRelease: string;
  nodeVersion: string;
  resolvedWindowSwf: string[];
  cepExtensionsDirs: string[];
  sharedObjectsBase: string | null;
}

export interface Diagnostics {
  machine: MachineInfo;
  installs: AnimateInstall[];
  sharedObjectsBase: string | null;
  sharedObjectsExists: boolean;
}

/** Result of a native file dialog. `path` absent when canceled. */
export interface PickResult {
  canceled: boolean;
  path?: string;
}

/** A target install + the WindowSWF dir to act on (passed by index from the renderer). */
export interface InstallTargetRequest {
  /** Index into the last `doctor()` install list. */
  installIndex: number;
}

export interface InstallSwfRequest extends InstallTargetRequest {
  /** Absolute path to the source .swf chosen via picker. */
  srcSwf: string;
  apply: boolean;
}

export interface ClearCacheRequest extends InstallTargetRequest {
  apply: boolean;
}

export interface JvmMemoryRequest extends InstallTargetRequest {
  xmxMb: number;
  apply: boolean;
}

export interface TightenSidebarRequest {
  /** Absolute path to the sidebar dictionary .dat chosen via picker. */
  datPath: string;
  apply: boolean;
}

export type OpenFolderKind = "windowSwf" | "commands" | "configuration" | "cache";

export interface OpenFolderRequest extends InstallTargetRequest {
  kind: OpenFolderKind;
}

// ---------------------------------------------------------------------------
// SOL inspector / editor (Tab B)
// ---------------------------------------------------------------------------

/** AMF0 leaf kinds that the editor can edit in place (others are read-only). */
export type SolLeafKind =
  | "number"
  | "boolean"
  | "string"
  | "null"
  | "undefined"
  | "date"
  | "unsupported"
  | "reference"
  | "xml";

export type SolContainerKind = "root" | "object" | "typedObject" | "ecmaArray" | "strictArray";

export type SolNodeKind = SolLeafKind | SolContainerKind;

/**
 * One node of the SOL AST projected for the renderer tree view. `path` is the
 * canonical addressing string the editor sends back to mutate a leaf in place.
 * Containers carry `children`; editable primitives carry `editable: true`.
 */
export interface SolTreeNode {
  /** Display key (member name, or array index as string). Empty for root. */
  key: string;
  /** Slash-joined address from the body root, e.g. "玩家/血量". */
  path: string;
  kind: SolNodeKind;
  /** Type label for display, e.g. "string (long)" / "ecmaArray[3]". */
  typeLabel: string;
  /** Primitive value for leaves (string/number/boolean); undefined for containers. */
  value?: string | number | boolean;
  /** True if this leaf can be edited + saved. */
  editable: boolean;
  /** Child nodes for containers. */
  children?: SolTreeNode[];
}

export interface SolMeta {
  name: string;
  amfVersion: number;
  signature: number;
  /** Top-level element count of the SharedObject body. */
  elementCount: number;
  /** Total leaf count (recursive), for the header. */
  leafCount: number;
  fileSize: number;
}

export interface SolDocument {
  /** Absolute path of the opened .sol file. */
  filePath: string;
  meta: SolMeta;
  tree: SolTreeNode[];
}

export interface OpenSolResult {
  canceled: boolean;
  doc?: SolDocument;
  error?: string;
}

/** An edit: set the primitive leaf at `path` to `value` (coerced to its kind). */
export interface SolEdit {
  path: string;
  /** New raw value as typed by the user; coerced in main per the leaf's kind. */
  value: string | number | boolean | null;
}

/** Preview of a pending save: the recomputed tree + a textual diff of edits. */
export interface SolSavePreview {
  ok: boolean;
  error?: string;
  /** Human-readable per-edit diff lines (oldValue -> newValue). */
  diff: SolDiffLine[];
  /** Size of the rebuilt file in bytes (for the preview). */
  newFileSize: number;
}

export interface SolDiffLine {
  path: string;
  oldValue: string;
  newValue: string;
  /** True if this edit could not be applied (bad path / non-editable). */
  error?: string;
}

export interface SolSaveResult {
  ok: boolean;
  error?: string;
  /** Path of the backup written before overwrite (null if none / dry run). */
  backupPath?: string | null;
  /** The reloaded document after a successful save. */
  doc?: SolDocument;
}

export interface SolSaveRequest {
  filePath: string;
  edits: SolEdit[];
  apply: boolean;
}

// ---------------------------------------------------------------------------
// The bridge surface exposed as window.ankit.*
// ---------------------------------------------------------------------------

export interface AnkitApi {
  runtime: string;
  /** Electron / Chrome / Node versions, for the about line. */
  versions: Record<string, string>;

  // --- Tab A: AN maintenance ---
  /** Run `collectDiagnostics` and cache the install list for index-addressed ops. */
  doctor: () => Promise<Diagnostics>;
  pickSwf: () => Promise<PickResult>;
  pickDat: () => Promise<PickResult>;
  installSwf: (req: InstallSwfRequest) => Promise<OpResult>;
  clearCache: (req: ClearCacheRequest) => Promise<OpResult>;
  setJvmMemory: (req: JvmMemoryRequest) => Promise<JvmOpResult>;
  tightenSidebar: (req: TightenSidebarRequest) => Promise<OpResult>;
  openFolder: (req: OpenFolderRequest) => Promise<{ ok: boolean; summary: string }>;

  // --- Tab B: SOL inspector / editor ---
  openSol: () => Promise<OpenSolResult>;
  previewSolSave: (req: SolSaveRequest) => Promise<SolSavePreview>;
  saveSol: (req: SolSaveRequest) => Promise<SolSaveResult>;
}
