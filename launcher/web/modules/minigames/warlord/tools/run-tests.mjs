import { readdirSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const tests = resolve(root, '.test-dist/tests');

function collect(path) {
  const files = [];
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const full = resolve(path, entry.name);
    if (entry.isDirectory()) files.push(...collect(full));
    else if (entry.name.endsWith('.test.js')) files.push(full);
  }
  return files.sort();
}

const files = collect(tests);
if (files.length === 0) throw new Error('No compiled warlord tests found.');
const result = spawnSync(process.execPath, ['--test', ...files], {
  cwd: root,
  stdio: 'inherit',
});
process.exit(result.status ?? 1);
