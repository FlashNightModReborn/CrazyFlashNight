/** Independent cold read of the unique disposable slot written by the CS6 owned-SOL suite. */
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { readSol, solToJson } from './cf7-animate-kit/packages/core/src/amf/index.ts';

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [fixtureArgument, sourceArgument] = process.argv.slice(2);
function requireThat(ok: unknown, message: string): asserts ok {
  if (!ok) throw new Error(message);
}
function samePath(a: string, b: string): boolean {
  return path.resolve(a).toUpperCase() === path.resolve(b).toUpperCase();
}
function sha(bytes: Buffer): string {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}
function durable(file: string, bytes: Buffer | string): void {
  const descriptor = fs.openSync(file, 'wx');
  try { fs.writeFileSync(descriptor, bytes); fs.fsyncSync(descriptor); }
  finally { fs.closeSync(descriptor); }
}
function collectAmmo(node: unknown, matches: any[]): void {
  if (!node || typeof node !== 'object') return;
  const object = node as any;
  if (object.name === 'TTI Benelli M4' && object.value?.ownedAmmoFixture === true) matches.push(object);
  for (const value of Object.values(object)) collectAmmo(value, matches);
}

requireThat(fixtureArgument && sourceArgument, 'Usage: inspect-weapon-ammo-sol.mts fixture.json unique-owned-slot.sol');
const fixturePath = fs.realpathSync(fixtureArgument);
const cfg = JSON.parse(fs.readFileSync(fixturePath, 'utf8').replace(/^\uFEFF/, ''));
requireThat(/^cf7_env_set_[0-9a-f]{20}$/.test(cfg.slot), 'Only the generated disposable slot is permitted');
const nonce = cfg.slot.slice('cf7_env_set_'.length);
const expectedDirectory = path.join(repo, 'tmp', 'focus-sol-20261013', 'owned-sol-' + nonce);
requireThat(samePath(path.dirname(fixturePath), expectedDirectory) &&
  samePath(cfg.evidenceDirectory, expectedDirectory) && samePath(cfg.installRoot, repo), 'Fixture ownership/path mismatch');
requireThat(cfg.metadata?.slot === cfg.slot && cfg.apply?.operationToken === 'op.' + nonce,
  'Fixture operation identity mismatch');
const source = fs.realpathSync(sourceArgument);
requireThat(path.basename(source) === cfg.slot + '.sol', 'Source basename does not match the owned slot');
requireThat(!fs.lstatSync(source).isSymbolicLink(), 'Source must be a regular file');
const bytes = fs.readFileSync(source);
const evidence = path.join(expectedDirectory, 'ammo-cold-' + crypto.randomBytes(8).toString('hex'));
fs.mkdirSync(evidence, { recursive: false });
const snapshot = path.join(evidence, path.basename(source));
durable(snapshot, bytes);
const coldBytes = fs.readFileSync(snapshot);
requireThat(sha(coldBytes) === sha(bytes), 'Immutable snapshot differs from native bytes');
const sol = readSol(coldBytes);
requireThat(sol.name === cfg.slot && sol.amfVersion === 0, 'SOL header identity/version mismatch');
const root = solToJson(sol) as any;
const settingsReceipt = root.test?.ext?.settingsReceipt;
requireThat(settingsReceipt?.operationToken === cfg.apply.operationToken &&
  settingsReceipt?.saveAttemptId === cfg.save.saveAttemptId, 'Native settings receipt does not bind to this fixture');
const matches: any[] = [];
collectAmmo(root.test, matches);
requireThat(matches.length === 1, 'Expected exactly one synthetic owned weapon');
const weapon = matches[0];
const state = weapon.value.ammoState;
for (const [key, value] of Object.entries({v:1, capacity:7, chamber:1, ghost:2, reward:0, reserve:4, paidNormal:7, paidChamber:0})) {
  requireThat(state?.[key] === value, 'Cold typed-ammo mismatch: ' + key);
}
requireThat(weapon.value.shot === -3 && state.reserveName === '00号鹿弹', 'Cold total/ammunition identity mismatch');
requireThat(sha(fs.readFileSync(source)) === sha(bytes), 'Native source changed during independent cold read');
const result = {
  schema:1, status:'passed', kind:'independent-owned-sol-cold-read', observedUtc:new Date().toISOString(),
  slot:cfg.slot, fixturePath, fixtureSha256:sha(fs.readFileSync(fixturePath)), source, snapshot,
  sourceSha256:sha(bytes), snapshotSha256:sha(coldBytes), originalUnchanged:true,
  settingsReceipt, weapon,
  boundary:'Disposable test slot only; proves native bytes, not player-save migration or human gameplay acceptance.'
};
const receipt = path.join(evidence, 'receipt.json');
durable(receipt, JSON.stringify(result, null, 2) + '\n');
console.log(JSON.stringify({status:result.status, slot:cfg.slot, receipt, sourceSha256:result.sourceSha256}));
