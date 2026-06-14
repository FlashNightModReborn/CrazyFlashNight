import fs from 'node:fs';
import path from 'node:path';

function wildcardToRegExp(segment: string): RegExp {
  const escaped = segment.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*');
  return new RegExp(`^${escaped}$`, 'i');
}

/**
 * Expand a filesystem glob containing only single-`*` wildcards (no `**`),
 * returning existing paths. Native path separators. Used to discover Animate
 * `WindowSWF` directories without a third-party glob dependency.
 */
export function expandPattern(pattern: string): string[] {
  const normalized = pattern.replace(/\//g, path.sep);
  const parts = normalized.split(path.sep);
  if (parts.length === 0) return [];

  const first = parts[0] ?? '';
  // Absolute root: 'C:' -> 'C:\', '' (posix leading sep) -> '/'.
  let current: string[] = first === '' ? [path.sep] : [`${first}${path.sep}`];

  for (let i = 1; i < parts.length; i++) {
    const seg = parts[i];
    if (seg === undefined || seg === '') continue;
    const next: string[] = [];
    for (const dir of current) {
      if (seg.includes('*')) {
        const re = wildcardToRegExp(seg);
        let entries: fs.Dirent[];
        try {
          entries = fs.readdirSync(dir, { withFileTypes: true });
        } catch {
          continue;
        }
        for (const e of entries) {
          if (re.test(e.name)) next.push(path.join(dir, e.name));
        }
      } else {
        next.push(path.join(dir, seg));
      }
    }
    current = next;
  }

  return current.filter((p) => {
    try {
      fs.accessSync(p);
      return true;
    } catch {
      return false;
    }
  });
}
