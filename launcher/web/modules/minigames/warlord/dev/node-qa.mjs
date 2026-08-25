#!/usr/bin/env node
import { createHash } from 'node:crypto';
import { readFileSync, readdirSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { runSingleSimulation } from '../runtime/simulation/run.js';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const requestedCase = readArg('--case');

function readArg(name) {
  const index = process.argv.indexOf(name);
  return index >= 0 && index + 1 < process.argv.length ? process.argv[index + 1] : '';
}

function digest(value) {
  return createHash('sha256').update(value).digest('hex').toUpperCase();
}

function collectFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap((entry) => {
    const full = resolve(dir, entry.name);
    return entry.isDirectory() ? collectFiles(full) : [full];
  });
}

const cases = [
  {
    id: 'runtime-closure',
    title: 'committed runtime/vendor closure matches its SHA-256 manifest',
    run() {
      const manifest = JSON.parse(readFileSync(resolve(root, 'runtime-manifest.json'), 'utf8'));
      if (manifest.schema !== 'cf7.warlord-sandtable-runtime.v1') throw new Error('schema mismatch');
      const declared = manifest.files.map((entry) => entry.path).sort();
      const actual = [resolve(root, 'runtime'), resolve(root, 'vendor')]
        .flatMap(collectFiles)
        .filter((path) => path !== resolve(root, 'vendor/manifest.json'))
        .map((path) => relative(root, path).replaceAll('\\', '/'))
        .sort();
      if (JSON.stringify(actual) !== JSON.stringify(declared)) throw new Error('file closure mismatch');
      for (const entry of manifest.files) {
        const bytes = readFileSync(resolve(root, entry.path));
        if (bytes.length !== entry.bytes || digest(bytes) !== entry.sha256) {
          throw new Error(`integrity mismatch: ${entry.path}`);
        }
      }
      return `${manifest.files.length} files`;
    },
  },
  {
    id: 'deterministic-simulation',
    title: 'same seed produces the same terminal state and battle log',
    run() {
      const first = runSingleSimulation('warlord-launcher-qa-001');
      const second = runSingleSimulation('warlord-launcher-qa-001');
      if (first.commandGuardHit || first.invalidCommands !== 0 || !first.state.result) {
        throw new Error('simulation did not reach a clean terminal state');
      }
      const firstDigest = digest(JSON.stringify(first));
      const secondDigest = digest(JSON.stringify(second));
      if (firstDigest !== secondDigest) throw new Error('deterministic digest mismatch');
      return `${first.state.result.winner}/${first.state.result.reason}/${firstDigest.slice(0, 12)}`;
    },
  },
  {
    id: 'read-only-authority',
    title: 'facade forces productionWrites=false and has no local panel close fallback',
    run() {
      const facade = readFileSync(resolve(root, 'warlord-panel.js'), 'utf8');
      if (!facade.includes('productionWrites: false')) throw new Error('read-only boundary missing');
      if (facade.includes('productionWrites: true')) throw new Error('production write path present');
      const closeStart = facade.indexOf('function onRequestClose(reason)');
      const closeEnd = facade.indexOf('function onClose()', closeStart);
      const close = facade.slice(closeStart, closeEnd);
      if (closeStart < 0 || closeEnd < 0 || close.includes('Panels.close()')) {
        throw new Error('exact Host close boundary missing');
      }
      return 'productionWrites=false/exact-host-close';
    },
  },
];

const selected = requestedCase ? cases.filter((item) => item.id === requestedCase) : cases;
if (requestedCase && selected.length === 0) {
  console.log(JSON.stringify({
    results: [{ id: requestedCase, title: 'unknown case', pass: false, detail: 'case not found' }],
    passed: 0,
    failed: 1,
    total: 1,
  }));
  process.exitCode = 1;
} else {
  const results = selected.map((item) => {
    try {
      return { id: item.id, title: item.title, pass: true, detail: item.run() };
    } catch (error) {
      return { id: item.id, title: item.title, pass: false, detail: error?.message ?? String(error) };
    }
  });
  const passed = results.filter((item) => item.pass).length;
  const bundle = { results, passed, failed: results.length - passed, total: results.length };
  console.log(JSON.stringify(bundle));
  if (bundle.failed > 0) process.exitCode = 1;
}
