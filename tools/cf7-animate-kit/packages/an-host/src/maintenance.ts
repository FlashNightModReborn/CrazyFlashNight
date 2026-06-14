import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { anEnv } from '@cf7-animate-kit/core';
import { backupFile } from './backup.js';

export type FileAction = 'create' | 'overwrite' | 'delete' | 'clear' | 'noop';

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

export interface ApplyOpts {
  apply?: boolean;
  backupSuffix?: string;
}

function backupIf(apply: boolean, file: string, opts: ApplyOpts): string | null {
  if (!apply) return null;
  const suffix = opts.backupSuffix;
  return backupFile(file, suffix !== undefined ? { suffix } : undefined).backupPath;
}

// ---------------------------------------------------------------------------
// Install / delete / clear-cache
// ---------------------------------------------------------------------------

/** Copy a plugin .swf into each WindowSWF dir (backing up any existing same-name file). */
export function installPluginSwf(srcSwf: string, windowSwfDirs: string[], opts: ApplyOpts = {}): OpResult {
  const apply = opts.apply ?? false;
  const changes: FileChange[] = [];
  const warnings: string[] = [];
  if (!fs.existsSync(srcSwf)) {
    return { ok: false, applied: false, summary: `source not found: ${srcSwf}`, changes, warnings };
  }
  const fileName = path.basename(srcSwf);
  for (const dir of windowSwfDirs) {
    const dest = path.join(dir, fileName);
    const existed = fs.existsSync(dest);
    let backup: string | null = null;
    if (apply) {
      if (!fs.existsSync(dir)) {
        warnings.push(`WindowSWF dir missing, skipped: ${dir}`);
        continue;
      }
      backup = existed ? backupIf(apply, dest, opts) : null;
      fs.copyFileSync(srcSwf, dest);
    }
    changes.push({ path: dest, action: existed ? 'overwrite' : 'create', backup });
  }
  return {
    ok: true,
    applied: apply,
    summary: `${apply ? 'installed' : 'would install'} ${fileName} into ${changes.length} dir(s)`,
    changes,
    warnings,
  };
}

/** Delete plugin .swf files matching `nameOrGlob` (single-* wildcard) from each dir. */
export function deletePluginSwf(nameOrGlob: string, windowSwfDirs: string[], opts: ApplyOpts = {}): OpResult {
  const apply = opts.apply ?? false;
  const changes: FileChange[] = [];
  const warnings: string[] = [];
  const re = new RegExp(`^${nameOrGlob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`, 'i');
  for (const dir of windowSwfDirs) {
    let entries: string[];
    try {
      entries = fs.readdirSync(dir);
    } catch {
      warnings.push(`cannot read dir: ${dir}`);
      continue;
    }
    for (const name of entries) {
      if (!re.test(name)) continue;
      const target = path.join(dir, name);
      let backup: string | null = null;
      if (apply) {
        backup = backupIf(apply, target, opts);
        fs.rmSync(target, { force: true });
      }
      changes.push({ path: target, action: 'delete', backup });
    }
  }
  return {
    ok: true,
    applied: apply,
    summary: `${apply ? 'deleted' : 'would delete'} ${changes.length} file(s) matching "${nameOrGlob}"`,
    changes,
    warnings,
  };
}

/** Clear the contents of a WindowSWF `tmp` cache directory (not the dir itself). */
export function clearCacheDir(cacheDir: string, opts: ApplyOpts = {}): OpResult {
  const apply = opts.apply ?? false;
  const changes: FileChange[] = [];
  const warnings: string[] = [];
  if (!fs.existsSync(cacheDir)) {
    return { ok: true, applied: apply, summary: `no cache dir: ${cacheDir}`, changes, warnings };
  }
  let entries: string[];
  try {
    entries = fs.readdirSync(cacheDir);
  } catch {
    return { ok: false, applied: false, summary: `cannot read cache: ${cacheDir}`, changes, warnings };
  }
  for (const name of entries) {
    const target = path.join(cacheDir, name);
    if (apply) fs.rmSync(target, { recursive: true, force: true });
    changes.push({ path: target, action: 'clear' });
  }
  return {
    ok: true,
    applied: apply,
    summary: `${apply ? 'cleared' : 'would clear'} ${changes.length} entr(ies) under ${cacheDir}`,
    changes,
    warnings,
  };
}

// ---------------------------------------------------------------------------
// jvm.ini memory / sidebar tighten (read -> pure transform -> backup -> write)
// ---------------------------------------------------------------------------

export interface JvmOpResult extends OpResult {
  previousXmxMb: number | null;
  newXmxMb: number;
  newXmsMb: number;
}

export function applyJvmMemory(jvmIniPath: string, xmxMb: number, opts: ApplyOpts = {}): JvmOpResult {
  const apply = opts.apply ?? false;
  const warnings: string[] = [];
  if (!fs.existsSync(jvmIniPath)) {
    return {
      ok: false,
      applied: false,
      summary: `jvm.ini not found: ${jvmIniPath}`,
      changes: [],
      warnings,
      previousXmxMb: null,
      newXmxMb: xmxMb,
      newXmsMb: Math.floor(xmxMb / 2),
    };
  }
  const content = fs.readFileSync(jvmIniPath, 'utf8');
  const res = anEnv.editJvmIni(content, xmxMb);
  let backup: string | null = null;
  if (apply && res.changed) {
    backup = backupIf(apply, jvmIniPath, opts);
    fs.writeFileSync(jvmIniPath, res.content, 'utf8');
  }
  return {
    ok: true,
    applied: apply && res.changed,
    summary: res.changed
      ? `${apply ? 'set' : 'would set'} -Xmx=${res.newXmxMb}m -Xms=${res.newXmsMb}m (was -Xmx=${res.previousXmxMb ?? '?'}m)`
      : `already -Xmx=${res.newXmxMb}m; no change`,
    changes: res.changed ? [{ path: jvmIniPath, action: 'overwrite', backup }] : [{ path: jvmIniPath, action: 'noop' }],
    warnings,
    previousXmxMb: res.previousXmxMb,
    newXmxMb: res.newXmxMb,
    newXmsMb: res.newXmsMb,
  };
}

export function tightenSidebarFile(datPath: string, opts: ApplyOpts = {}): OpResult {
  const apply = opts.apply ?? false;
  if (!fs.existsSync(datPath)) {
    return { ok: false, applied: false, summary: `dictionary not found: ${datPath}`, changes: [], warnings: [] };
  }
  const content = fs.readFileSync(datPath, 'utf8');
  const res = anEnv.tightenSidebar(content);
  let backup: string | null = null;
  if (apply && res.changed) {
    backup = backupIf(apply, datPath, opts);
    fs.writeFileSync(datPath, res.content, 'utf8');
  }
  return {
    ok: true,
    applied: apply && res.changed,
    summary: res.changed
      ? `${apply ? 'tightened' : 'would tighten'} sidebar (removed ${res.removedWidthLines} width line(s), shortened ${res.replacedLabels} label(s))`
      : 'sidebar already tightened; no change',
    changes: res.changed ? [{ path: datPath, action: 'overwrite', backup }] : [{ path: datPath, action: 'noop' }],
    warnings: [],
  };
}

// ---------------------------------------------------------------------------
// Open folder in the OS file manager
// ---------------------------------------------------------------------------

export function openFolder(dir: string): { ok: boolean; summary: string } {
  if (!fs.existsSync(dir)) return { ok: false, summary: `not found: ${dir}` };
  let cmd: string;
  let args: string[];
  if (process.platform === 'win32') {
    cmd = 'explorer.exe';
    args = [dir];
  } else if (process.platform === 'darwin') {
    cmd = 'open';
    args = [dir];
  } else {
    cmd = 'xdg-open';
    args = [dir];
  }
  try {
    const child = spawn(cmd, args, { detached: true, stdio: 'ignore' });
    child.unref();
    return { ok: true, summary: `opened ${dir}` };
  } catch (e) {
    return { ok: false, summary: `failed to open ${dir}: ${String(e)}` };
  }
}
