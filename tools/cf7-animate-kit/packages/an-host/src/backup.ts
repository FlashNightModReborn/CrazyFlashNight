import fs from 'node:fs';

export interface BackupResult {
  backedUp: boolean;
  backupPath: string | null;
}

function timestamp(now: Date): string {
  const pad = (x: number): string => String(x).padStart(2, '0');
  return (
    `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}` +
    `-${pad(now.getHours())}${pad(now.getMinutes())}${pad(now.getSeconds())}`
  );
}

/**
 * Copy `file` to a sibling `.bak-<timestamp>` before it is overwritten/deleted.
 * Returns `{ backedUp:false }` if the file does not exist. Never clobbers an
 * existing backup (adds a numeric suffix). `opts.suffix` makes tests deterministic.
 */
export function backupFile(file: string, opts?: { suffix?: string }): BackupResult {
  if (!fs.existsSync(file)) return { backedUp: false, backupPath: null };
  const suffix = opts?.suffix ?? `.bak-${timestamp(new Date())}`;
  let backupPath = `${file}${suffix}`;
  let n = 1;
  while (fs.existsSync(backupPath)) {
    backupPath = `${file}${suffix}.${n}`;
    n++;
  }
  fs.copyFileSync(file, backupPath);
  return { backedUp: true, backupPath };
}
