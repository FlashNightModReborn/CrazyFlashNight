import { createHash } from 'node:crypto';
import {
  cpSync,
  existsSync,
  mkdirSync,
  readFileSync,
  readdirSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const runtime = resolve(root, 'runtime');
const testDist = resolve(root, '.test-dist');
const vendor = resolve(root, 'vendor');
const configManifestPath = resolve(root, 'src/data/config-manifest.json');
const configManifestBytes = readFileSync(configManifestPath);
const configManifest = JSON.parse(configManifestBytes.toString('utf8'));

function assertInside(candidate, parent, label) {
  const rel = relative(parent, candidate);
  if (rel.startsWith('..') || rel === '') throw new Error(`unsafe ${label}: ${candidate}`);
}

function resetDirectory(path, label) {
  assertInside(path, root, label);
  rmSync(path, { recursive: true, force: true });
  mkdirSync(path, { recursive: true });
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex').toUpperCase();
}

function verifyFrozenConfig() {
  const configPath = resolve(root, 'src/data/config.ts');
  // Git on Windows may materialize the single trailing LF as CRLF.  The frozen
  // rules identity is content-based, so normalize text line endings before hashing.
  const canonicalManifestBytes = Buffer.from(
    configManifestBytes.toString('utf8').replaceAll('\r\n', '\n'),
    'utf8',
  );
  const computedDigest = `sha256:${sha256(canonicalManifestBytes)}`;
  const configSource = readFileSync(configPath, 'utf8');
  const declaredDigest = configSource.match(/CONFIG_DIGEST = '([^']+)'/)?.[1];
  if (declaredDigest !== computedDigest) {
    throw new Error(`configDigest mismatch: declared ${declaredDigest ?? '<missing>'}, computed ${computedDigest}`);
  }
  const checks = [
    ['RULES_VERSION', configManifest.rulesVersion],
    ['RULES_EXTENSION_VERSION', configManifest.rulesExtensionVersion],
    ['TUNING_VERSION', configManifest.tuningVersion],
    ['AI_POLICY_VERSION', configManifest.aiPolicyVersion],
    ['MAX_STRATEGIC_ROUNDS', configManifest.maxStrategicRounds],
    ['MAX_BATTLE_ROUNDS', configManifest.maxBattleRounds],
    ['DAMAGE_SCALE', configManifest.damageScale],
    ['HIT_MIN', configManifest.hitMin],
    ['HIT_MAX', configManifest.hitMax],
    ['DAMAGE_RANDOM_MIN', configManifest.damageRandomMin],
    ['DAMAGE_RANDOM_MAX', configManifest.damageRandomMax],
  ];
  for (const [name, expected] of checks) {
    const literal = typeof expected === 'string' ? `'${expected}'` : String(expected).replace('.', '\\.');
    if (!new RegExp(`export const ${name} = ${literal};`).test(configSource)) {
      throw new Error(`config.ts does not match config-manifest.json for ${name}`);
    }
  }
}

function runTsc(config) {
  const tsc = resolve(root, 'node_modules/typescript/lib/tsc.js');
  if (!existsSync(tsc)) throw new Error('node_modules missing; run npm ci first');
  const result = spawnSync(process.execPath, [tsc, '-p', resolve(root, config)], {
    cwd: root,
    stdio: 'inherit',
  });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function collectFiles(path) {
  const files = [];
  for (const entry of readdirSync(path, { withFileTypes: true })) {
    const full = resolve(path, entry.name);
    if (entry.isDirectory()) files.push(...collectFiles(full));
    else files.push(full);
  }
  return files.sort();
}

verifyFrozenConfig();
resetDirectory(runtime, 'runtime output');
resetDirectory(testDist, 'test output');
mkdirSync(vendor, { recursive: true });

const threeModule = resolve(root, 'node_modules/three/build/three.module.min.js');
const threeCore = resolve(root, 'node_modules/three/build/three.core.min.js');
const threeLicense = resolve(root, 'node_modules/three/LICENSE');
if (!existsSync(threeModule) || !existsSync(threeCore) || !existsSync(threeLicense)) {
  throw new Error('three 0.185.1 runtime or license missing; run npm ci first');
}
cpSync(threeModule, resolve(vendor, 'three.module.min.js'));
cpSync(threeCore, resolve(vendor, 'three.core.min.js'));
cpSync(threeLicense, resolve(vendor, 'three-LICENSE.txt'));

runTsc('tsconfig.runtime.json');
runTsc('tsconfig.tests.json');

const packageLock = JSON.parse(readFileSync(resolve(root, 'package-lock.json'), 'utf8'));
const locked = packageLock.packages ?? {};
if (locked['node_modules/three']?.version !== '0.185.1') throw new Error('three lock drift');
if (locked['node_modules/typescript']?.version !== '5.8.3') throw new Error('TypeScript lock drift');

const trackedRoots = [runtime, vendor];
const files = trackedRoots.flatMap(collectFiles)
  .filter((path) => path !== resolve(vendor, 'manifest.json'))
  .map((path) => {
  const bytes = readFileSync(path);
  return {
    path: relative(root, path).replaceAll('\\', '/'),
    bytes: statSync(path).size,
    sha256: sha256(bytes),
  };
  });
const manifest = {
  schema: 'cf7.warlord-sandtable-runtime.v1',
  rulesVersion: configManifest.rulesVersion,
  nodeEngine: '>=22.0.0',
  compiler: { name: 'typescript', version: '5.8.3' },
  renderer: { name: 'three', version: '0.185.1', license: 'MIT' },
  files,
};
writeFileSync(resolve(root, 'runtime-manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`, 'utf8');
writeFileSync(resolve(vendor, 'manifest.json'), `${JSON.stringify({
  schema: 'cf7.warlord-three-vendor.v1',
  package: 'three',
  version: '0.185.1',
  license: 'MIT',
  files: files.filter((entry) => entry.path.startsWith('vendor/')),
}, null, 2)}\n`, 'utf8');

console.log(JSON.stringify({
  ok: true,
  runtimeFiles: collectFiles(runtime).length,
  vendorFiles: collectFiles(vendor).length,
  compiler: 'TypeScript 5.8.3',
  renderer: 'Three.js 0.185.1',
}));
