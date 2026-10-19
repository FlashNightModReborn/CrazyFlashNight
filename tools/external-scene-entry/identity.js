'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex').toUpperCase();
const canonical = file => path.resolve(file).replace(/\\/g, '/').toLowerCase();
function saveInventory(root, except) {
  const directory = path.join(root, 'saves');
  return Object.fromEntries(fs.readdirSync(directory).filter(name => name.endsWith('.json') && name !== except && name !== '.launcher-version-marker.json')
    .sort().map(name => [name, sha256(path.join(directory, name))]));
}
function startupMetadata(root) {
  const file = path.join(root, 'saves/.launcher-version-marker.json');
  if (!fs.existsSync(file)) return null;
  const body = JSON.parse(fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, ''));
  if (Object.keys(body).sort().join(',') !== 'version,writtenAt' || body.version !== 1
      || typeof body.writtenAt !== 'string' || !Number.isFinite(Date.parse(body.writtenAt))) {
    throw new Error('unexpected launcher version marker schema; no blanket save exclusion');
  }
  return { sha256: sha256(file), ...body };
}
function seal(root, args) {
  const candidateRoot = path.join(root, 'tmp/runtime-candidates/v2', args.candidate);
  const metadata = JSON.parse(fs.readFileSync(path.join(candidateRoot, 'runtime-build-metadata.v2.json'), 'utf8').replace(/^\uFEFF/, ''));
  const processPath = path.join(candidateRoot, 'runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe');
  const slotFile = path.join(root, 'saves', args.slot + '.json');
  const products = ['scripts/asLoader.swf', 'CRAZYFLASHER7MercenaryEmpire.swf'];
  if (metadata.schema !== 'cf7-runtime-candidate-metadata.v2') throw new Error('candidate metadata schema mismatch');
  if (!args.slot.startsWith('cf7_agent_')) throw new Error('isolated agent slot required');
  return { projectRoot: root, candidateRoot, processPath, coreSha256: sha256(processPath),
    nativeBinaries: Object.fromEntries(['CRAZYFLASHER7MercenaryEmpire.Core.exe', 'CRAZYFLASHER7MercenaryEmpire.Core.dll']
      .map(file => [file, sha256(path.join(candidateRoot, 'runtime', file))])),
    sourceBase: require('node:child_process').execFileSync('git', ['rev-parse', 'HEAD'], {cwd: root, encoding: 'utf8'}).trim(),
    sources: Object.fromEntries(['CRAZYFLASHER7MercenaryEmpire/DOMDocument.xml',
      'scripts/类定义/org/flashNight/arki/scene/SceneTransitionGuard.as',
      'scripts/类定义/org/flashNight/arki/ui/SceneTransitionService.as',
      'scripts/逻辑/关卡系统/关卡系统_lsy_场景转换.as'].map(file => [file, sha256(path.join(root, file))])),
    buildIdentity: metadata.buildIdentityHash, payloadClosure: metadata.payloadClosureHash,
    swfs: Object.fromEntries(products.map(file => [file, sha256(path.join(root, file))])),
    slotFile, initialSlotSha256: sha256(slotFile), otherSaves: saveInventory(root, args.slot + '.json'),
    startupMetadataBefore: startupMetadata(root),
    programs: Object.fromEntries(['run.js', 'ui-session.js', 'oracle.js', 'log-tracker.js', 'identity.js', 'cdp-input.js']
      .map(name => ['tools/external-scene-entry/' + name, sha256(path.join(root, 'tools/external-scene-entry', name))])) };
}
function validateCompletion(completion, expected) {
  if (!completion || completion.runtimeMode !== 'isolated_candidate'
      || canonical(completion.processPath || '') !== canonical(expected.processPath)
      || String(completion.coreSha256).toUpperCase() !== expected.coreSha256
      || String(completion.buildIdentity).toUpperCase() !== expected.buildIdentity
      || String(completion.payloadClosure).toUpperCase() !== expected.payloadClosure
      || !(completion.guardianProcessId > 0)
      || completion.terminalReceipt?.terminal !== true
      || completion.terminalReceipt?.outcome !== 'input_dispatched'
      || completion.terminalReceipt?.reasonCode !== 'shutdown_requested') {
    throw new Error('trusted shutdown does not match the selected runtime identity');
  }
}
function validateNormalExit(report, expected) {
  if (!report || report.schema !== 'cf7.scene-entry.normal-exit.v1'
      || report.runtimeMode !== 'isolated_candidate' || report.exitCode !== 0 || report.forced !== false
      || canonical(report.processPath || '') !== canonical(expected.processPath)
      || report.buildIdentity !== expected.buildIdentity || report.payloadClosure !== expected.payloadClosure
      || !(report.guardianPid > 0) || report.guardianPid !== expected.guardianPid) {
    throw new Error('normal process exit does not match the selected candidate; not a trusted-runner receipt');
  }
}
function verifyAfter(expected, slot) {
  for (const [file, hash] of Object.entries(expected.programs)) {
    if (sha256(path.join(expected.projectRoot, file)) !== hash) throw new Error('verifier changed during live run: ' + file);
  }
  for (const [file, hash] of Object.entries(expected.sources)) {
    if (sha256(path.join(expected.projectRoot, file)) !== hash) throw new Error('scene source changed during live run: ' + file);
  }
  for (const [file, hash] of Object.entries(expected.swfs)) {
    if (sha256(path.join(expected.projectRoot, file)) !== hash) throw new Error('SWF changed during live run: ' + file);
  }
  for (const [file, hash] of Object.entries(expected.nativeBinaries)) {
    if (sha256(path.join(expected.candidateRoot, 'runtime', file)) !== hash) throw new Error('native binary changed during live run: ' + file);
  }
  if (JSON.stringify(saveInventory(expected.projectRoot, slot + '.json')) !== JSON.stringify(expected.otherSaves)) {
    throw new Error('non-target save inventory changed');
  }
  return { finalSlotSha256: sha256(expected.slotFile), otherSavesUnchanged: true, binariesUnchanged: true,
    programsUnchanged: true, sceneSourcesUnchanged: true, startupMetadataAfter: startupMetadata(expected.projectRoot) };
}
module.exports = { seal, validateCompletion, validateNormalExit, verifyAfter, startupMetadata };
