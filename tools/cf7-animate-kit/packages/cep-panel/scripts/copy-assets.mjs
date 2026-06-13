/**
 * Post-build asset copier (cross-platform, zero deps).
 * Runs after `vite build`. Assembles dist/ into a self-contained, installable
 * CEP extension by copying:
 *   - ../../jsfl-host/host        -> dist/host        (the JSFL <ScriptPath>)
 *   - ./CSXS/manifest.xml         -> dist/CSXS/manifest.xml
 *   - ./.debug                    -> dist/.debug      (remote DevTools port)
 *
 * Vite already emitted dist/index.html + dist/assets/* from the build entry.
 *
 * No networking. Pure local fs. Invoked by the package.json "build" script.
 */
import { cpSync, existsSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pkgRoot = resolve(here, '..');
const dist = resolve(pkgRoot, 'dist');

if (!existsSync(dist)) {
  console.error('[copy-assets] dist/ not found — run `vite build` first.');
  process.exit(1);
}

/** @param {string} from @param {string} to */
function copy(from, to) {
  if (!existsSync(from)) {
    console.error(`[copy-assets] missing source: ${from}`);
    process.exit(1);
  }
  mkdirSync(dirname(to), { recursive: true });
  cpSync(from, to, { recursive: true });
  console.log(`[copy-assets] ${from} -> ${to}`);
}

// 1) JSFL host script tree (the only code that touches the live FLA).
copy(resolve(pkgRoot, '..', 'jsfl-host', 'host'), resolve(dist, 'host'));

// 2) CSXS manifest.
copy(resolve(pkgRoot, 'CSXS', 'manifest.xml'), resolve(dist, 'CSXS', 'manifest.xml'));

// 3) .debug descriptor (unsigned dev installs only).
copy(resolve(pkgRoot, '.debug'), resolve(dist, '.debug'));

console.log('[copy-assets] done — dist/ is an installable CEP extension.');
