/**
 * AnEnv — pure resolvers and transforms for the Adobe Animate install layout
 * and config files. NO I/O: every function takes an explicit environment
 * snapshot (or file content) and returns path templates / plans / new content.
 * The on-disk discovery and read/modify/write live in `@cf7-animate-kit/an-host`.
 *
 * Clean-room note: this module contains NO machine-id / MAC / activation logic.
 * `machineInfoSafe` is a plain human-readable diagnostic and is asserted by a
 * test to contain no hardware identifier.
 */
import path from 'node:path';

export interface EnvSnapshot {
  platform: NodeJS.Platform | string;
  /** %APPDATA% (Windows roaming). */
  appData?: string;
  /** %LOCALAPPDATA% (Windows). */
  localAppData?: string;
  /** %ProgramFiles%. */
  programFiles?: string;
  /** %ProgramFiles(x86)%. */
  programFilesX86?: string;
  /** User home (macOS / fallback). */
  home?: string;
}

const isWin = (env: EnvSnapshot): boolean => env.platform === 'win32';
const isMac = (env: EnvSnapshot): boolean => env.platform === 'darwin';

/**
 * Glob patterns (single `*` wildcard, native separators) for Adobe Animate
 * `Configuration/WindowSWF` directories. Mirrors the locations a paid AN
 * extension would be installed into.
 */
export function windowSwfGlobs(env: EnvSnapshot): string[] {
  const globs: string[] = [];
  if (isWin(env)) {
    if (env.localAppData) {
      globs.push(path.join(env.localAppData, 'Adobe', 'Animate*', '*', 'Configuration', 'WindowSWF'));
    }
    for (const pf of [env.programFiles, env.programFilesX86]) {
      if (!pf) continue;
      globs.push(path.join(pf, 'Adobe', 'Adobe Animate*', 'Configuration', 'WindowSWF'));
      globs.push(path.join(pf, 'Adobe', 'Adobe Animate*', 'zh_CN', 'Configuration', 'WindowSWF'));
    }
  } else if (isMac(env) && env.home) {
    globs.push(
      path.join(env.home, 'Library', 'Application Support', 'Adobe', 'Animate*', '*', 'Configuration', 'WindowSWF'),
    );
  }
  return globs;
}

/** Candidate CEP extensions directories (where this tool's own panel installs in P4). */
export function cepExtensionsDirs(env: EnvSnapshot): string[] {
  const dirs: string[] = [];
  if (isWin(env)) {
    if (env.appData) dirs.push(path.join(env.appData, 'Adobe', 'CEP', 'extensions'));
    for (const pf of [env.programFilesX86, env.programFiles]) {
      if (pf) dirs.push(path.join(pf, 'Common Files', 'Adobe', 'CEP', 'extensions'));
    }
  } else if (isMac(env) && env.home) {
    dirs.push(path.join(env.home, 'Library', 'Application Support', 'Adobe', 'CEP', 'extensions'));
  }
  return dirs;
}

/** Base directory of Flash Player SharedObjects (.sol live under */ /* /localhost). */
export function sharedObjectsBase(env: EnvSnapshot): string | null {
  if (isWin(env) && env.appData) {
    return path.join(env.appData, 'Macromedia', 'Flash Player', '#SharedObjects');
  }
  if (isMac(env) && env.home) {
    return path.join(env.home, 'Library', 'Preferences', 'Macromedia', 'Flash Player', '#SharedObjects');
  }
  return null;
}

export interface AnimatePaths {
  windowSwfDir: string;
  configurationDir: string;
  commandsDir: string;
  jvmIniPath: string;
  cacheDir: string;
}

/** Derive sibling Animate config paths from a discovered WindowSWF directory. */
export function pathsFromWindowSwf(windowSwfDir: string): AnimatePaths {
  const configurationDir = path.dirname(windowSwfDir);
  return {
    windowSwfDir,
    configurationDir,
    commandsDir: path.join(configurationDir, 'Commands'),
    jvmIniPath: path.join(configurationDir, 'ActionScript 3.0', 'jvm.ini'),
    cacheDir: path.join(configurationDir, 'tmp'),
  };
}

// ---------------------------------------------------------------------------
// jvm.ini memory edit (port of the legit "扩内存" utility)
// ---------------------------------------------------------------------------

export interface JvmEditResult {
  content: string;
  changed: boolean;
  previousXmxMb: number | null;
  newXmxMb: number;
  newXmsMb: number;
}

/**
 * Set the Animate JVM max heap (`-Xmx`) to `xmxMb` and the initial heap
 * (`-Xms`) to half of it, mirroring the original maintenance tool. Pure string
 * transform; preserves the file's newline style.
 */
export function editJvmIni(content: string, xmxMb: number): JvmEditResult {
  if (!Number.isInteger(xmxMb) || xmxMb <= 0) {
    throw new Error('xmxMb must be a positive integer (megabytes)');
  }
  const eol = content.includes('\r\n') ? '\r\n' : '\n';
  const lines = content.split(/\r?\n/);
  const xms = Math.floor(xmxMb / 2);
  let previousXmxMb: number | null = null;
  let sawXms = false;
  let changed = false;

  const out = lines.map((line) => {
    if (line.startsWith('-Xmx')) {
      const m = line.match(/^-Xmx(\d+)m/);
      if (m && m[1] !== undefined) previousXmxMb = Number.parseInt(m[1], 10);
      const next = `-Xmx${xmxMb}m`;
      if (next !== line) changed = true;
      return next;
    }
    if (line.startsWith('-Xms')) {
      sawXms = true;
      const next = `-Xms${xms}m`;
      if (next !== line) changed = true;
      return next;
    }
    return line;
  });

  if (!sawXms) {
    out.push(`-Xms${xms}m`);
    changed = true;
  }
  return { content: out.join(eol), changed, previousXmxMb, newXmxMb: xmxMb, newXmsMb: xms };
}

// ---------------------------------------------------------------------------
// Sidebar tighten (port of the legit "收侧边" utility)
// ---------------------------------------------------------------------------

const AUTOKERN_LINE_PREFIXES = [
  '"$$$/PI/Text/Character/Autokern/tooltip=自动调整字距"',
  '"$$$/PI/Text/Character/Kern/label=自动调整字距"',
];

export interface SidebarResult {
  content: string;
  changed: boolean;
  removedWidthLines: number;
  replacedLabels: number;
}

/**
 * Tighten the AN Property Inspector sidebar: drop the `PI_MAX_WIDTH` /
 * `PI_MIN_WIDTH` dictionary lines and shorten the long auto-kern labels. Pure
 * transform over a `fl_dictionary_*.dat` file's content.
 */
export function tightenSidebar(content: string): SidebarResult {
  const eol = content.includes('\r\n') ? '\r\n' : '\n';
  const lines = content.split(/\r?\n/);
  let removedWidthLines = 0;
  let replacedLabels = 0;
  const out: string[] = [];
  for (const line of lines) {
    if (line.startsWith('"$$$/PI_MAX_WIDTH=') || line.startsWith('"$$$/PI_MIN_WIDTH=')) {
      removedWidthLines++;
      continue;
    }
    if (AUTOKERN_LINE_PREFIXES.some((p) => line.startsWith(p))) {
      out.push(line.replace('自动调整字距', '自动'));
      replacedLabels++;
      continue;
    }
    out.push(line);
  }
  return {
    content: out.join(eol),
    changed: removedWidthLines > 0 || replacedLabels > 0,
    removedWidthLines,
    replacedLabels,
  };
}

// ---------------------------------------------------------------------------
// Safe machine diagnostics (NO hardware id / MAC / activation)
// ---------------------------------------------------------------------------

export interface MachineInfoInput {
  platform: string;
  osRelease?: string;
  nodeVersion?: string;
  resolvedWindowSwf: string[];
  cepExtensionsDirs: string[];
  sharedObjectsBase: string | null;
}

export interface MachineInfo {
  platform: string;
  osRelease: string;
  nodeVersion: string;
  windowSwfDirs: string[];
  cepExtensionsDirs: string[];
  sharedObjectsBase: string | null;
  /** Always false — this tool derives no activation seed / machine id. */
  containsMachineId: false;
}

/**
 * Build a human-readable diagnostic snapshot. Deliberately excludes ANY
 * hardware identifier (no MAC, no volume serial, no activation seed). The
 * `containsMachineId: false` flag is asserted by a unit test.
 */
export function machineInfoSafe(input: MachineInfoInput): MachineInfo {
  return {
    platform: input.platform,
    osRelease: input.osRelease ?? 'unknown',
    nodeVersion: input.nodeVersion ?? 'unknown',
    windowSwfDirs: input.resolvedWindowSwf,
    cepExtensionsDirs: input.cepExtensionsDirs,
    sharedObjectsBase: input.sharedObjectsBase,
    containsMachineId: false,
  };
}
