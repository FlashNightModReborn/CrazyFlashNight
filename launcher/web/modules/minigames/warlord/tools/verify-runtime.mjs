import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const manifestPath = resolve(root, 'runtime-manifest.json');
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
if (manifest.schema !== 'cf7.warlord-sandtable-runtime.v1') throw new Error('runtime manifest schema mismatch');
if (manifest.organization?.id !== 'demo1-organizations'
    || manifest.organization?.rulesVersion !== 'warlord.organization.v1'
    || !/^sha256:[A-F0-9]{64}$/.test(manifest.organization?.digest ?? '')) {
  throw new Error('runtime organization identity mismatch');
}
if (manifest.encounter?.id !== 'demo1-encounter-distance'
    || manifest.encounter?.rulesVersion !== 'warlord.encounter-distance.v1'
    || manifest.encounter?.digest !== 'sha256:6D94E0ABCA11BE5AE1574219D30E4E8E1E3890293496FB2192E081AB24DFE29E') {
  throw new Error('runtime encounter identity mismatch');
}
if (manifest.compiler?.version !== '5.8.3') throw new Error('runtime compiler version drift');
if (manifest.renderer?.version !== '0.185.1' || manifest.renderer?.license !== 'MIT') {
  throw new Error('runtime renderer version/license drift');
}

function collect(path) {
  const files = [];
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const full = resolve(path, entry.name);
    if (entry.isDirectory()) files.push(...collect(full));
    else files.push(full);
  }
  return files;
}

const actualPaths = [resolve(root, 'runtime'), resolve(root, 'vendor')]
  .flatMap(collect)
  .filter((path) => path !== resolve(root, 'vendor/manifest.json'))
  .map((path) => relative(root, path).replaceAll('\\', '/'))
  .sort();
const declaredPaths = manifest.files.map((entry) => entry.path).sort();
if (JSON.stringify(actualPaths) !== JSON.stringify(declaredPaths)) {
  throw new Error('runtime manifest file closure mismatch');
}

for (const entry of manifest.files) {
  const path = resolve(root, entry.path);
  if (!existsSync(path) || !statSync(path).isFile()) throw new Error(`missing runtime file: ${entry.path}`);
  const bytes = readFileSync(path);
  const digest = createHash('sha256').update(bytes).digest('hex').toUpperCase();
  if (bytes.length !== entry.bytes || digest !== entry.sha256) {
    throw new Error(`runtime integrity mismatch: ${entry.path}`);
  }
}

const requiredVendor = ['vendor/three.module.min.js', 'vendor/three.core.min.js', 'vendor/three-LICENSE.txt'];
for (const path of requiredVendor) {
  if (!declaredPaths.includes(path)) throw new Error(`missing audited vendor file: ${path}`);
}

console.log(JSON.stringify({ ok: true, files: manifest.files.length, bytes: manifest.files.reduce((sum, entry) => sum + entry.bytes, 0) }));
