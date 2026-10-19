'use strict';
const assert = require('node:assert/strict');
const { TransitionOracle } = require('./oracle');
let checks = 0;
const wire = (phase, revision, targetScene = 3, requestId = 'tr:1') =>
  '[XmlSocket:JSON] ' + JSON.stringify({ task: 'scene_transition', payload: { requestId, phase, revision, targetScene } });
function valid() {
  return [wire('cover', 1), 'event=scene_transition_begin id=tr:1', wire('loading', 3),
    '[SceneEntryNavigation] route=same_frame from=158 target=158 scene=地图-食堂',
    wire('reveal', 4), 'event=scene_transition_revealed id=tr:1 scene=3',
    '[SceneEntryReady] request=tr:1 targetScene=3 rootFrame=158 scene=地图-食堂'];
}
function result(lines, spec = {}) {
  return new TransitionOracle({ label: 'hop', scene: '地图-食堂', route: 'same_frame', minimumScene: 2, ...spec }).add(lines);
}
function check(status, lines, spec) { assert.equal(result(lines, spec).status, status); checks++; }
check('pass', valid());
const batched = valid();
batched[6] = '[LogBatch] messages=[SceneEntryReady] request=tr:0 targetScene=2 rootFrame=146 scene=基地场景-基地门口|' + batched[6] + '|next message&frame=123';
check('pass', batched);
check('pending', ['overlay closed', 'runnerExit=0']);
check('pending', valid().filter(l => !l.includes('SceneEntryReady')));
check('pending', valid().filter(l => !l.includes('revealed id=')));
check('pending', valid().map(l => l.replace('SceneEntryReady] request=tr:1', 'SceneEntryReady] request=tr:0')));
check('pending', valid().map(l => l.replace('scene=地图-食堂', 'scene=地图-实验室')));
check('pending', valid().map(l => l.replace('route=same_frame', 'route=remembered_frame')));
check('fail', valid().map(l => l.replace('from=158', 'from=146')));
check('fail', valid(), { minimumScene: 3 });
check('fail', [...valid(), 'event=scene_transition_begin id=tr:2']);
check('fail', [...valid(), 'event=scene_transition_revealed id=tr:1 scene=3']);
check('fail', [...valid(), wire('error', 5)]);
check('pending', valid().filter(l => !l.includes('"phase":"reveal"')));
check('pending', valid().map(l => l.replace('"targetScene":3,"', '"targetScene":99,"'))
  .map(l => l.includes('"phase":"reveal"') ? l.replace('"targetScene":3', '"targetScene":99') : l));
check('pass', [...Array(1000).fill('event=world_compositor_progress state=advancing sceneReady=True'), ...valid()]);
check('pending', [...valid().filter(l => !l.includes('SceneEntryReady')), 'sceneReady=True capture advancing']);
const reverse = valid(); [reverse[0], reverse[2]] = [reverse[2], reverse[0]]; check('fail', reverse);
const replay = new TransitionOracle({ label: 'incremental', scene: '地图-食堂', route: 'same_frame', minimumScene: 2 });
assert.equal(replay.add(valid().slice(0, 4)).status, 'pending'); checks++;
assert.equal(replay.add(valid().slice(4)).status, 'pass'); checks++;
assert.equal(replay.records.length, valid().length); checks++;
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { LogTracker } = require('./log-tracker');
const dir = path.resolve(__dirname, '../../tmp/external-scene-entry/oracle-fixtures', crypto.randomUUID());
fs.mkdirSync(dir, { recursive: true });
const log = path.join(dir, 'launcher.log');
fs.writeFileSync(log, 'old scene receipt\n');
const tracker = new LogTracker([log]);
assert.deepEqual(tracker.poll().newLines, []); checks++;
const utf8 = Buffer.from('地图-测试空间\n');
fs.appendFileSync(log, utf8.subarray(0, 5));
assert.deepEqual(tracker.poll().newLines, []); checks++;
fs.appendFileSync(log, utf8.subarray(5));
assert.deepEqual(tracker.poll().newLines, ['地图-测试空间']); checks++;
fs.appendFileSync(log, 'last old-file receipt\n');
fs.renameSync(log, log + '.1'); fs.writeFileSync(log, 'first new-file receipt\n');
assert.deepEqual(tracker.poll().newLines, ['last old-file receipt', 'first new-file receipt']); checks++;
tracker.close();
const missing = path.join(dir, 'created-after-start.log');
const later = new LogTracker([missing]); fs.writeFileSync(missing, 'fresh event\n');
assert.deepEqual(later.poll().newLines, ['fresh event']); checks++; later.close();
const { validateCompletion } = require('./identity');
const identity = { processPath: path.join(dir, 'Core.exe'), coreSha256: 'A', buildIdentity: 'B', payloadClosure: 'C' };
const completion = { runtimeMode: 'isolated_candidate', ...identity, guardianProcessId: 42,
  terminalReceipt: { terminal: true, outcome: 'input_dispatched', reasonCode: 'shutdown_requested' } };
validateCompletion(completion, identity); checks++;
for (const field of ['runtimeMode', 'processPath', 'coreSha256', 'buildIdentity', 'payloadClosure']) {
  assert.throws(() => validateCompletion({ ...completion, [field]: 'foreign' }, identity)); checks++;
}
assert.throws(() => validateCompletion({ ...completion, terminalReceipt: { terminal: true } }, identity)); checks++;
const { startupMetadata } = require('./identity');
fs.mkdirSync(path.join(dir, 'saves'));
assert.equal(startupMetadata(dir), null); checks++;
const marker = path.join(dir, 'saves/.launcher-version-marker.json');
fs.writeFileSync(marker, JSON.stringify({ version: 1, writtenAt: '2026-10-19T00:00:00Z' }));
assert.equal(startupMetadata(dir).version, 1); checks++;
for (const body of [{ version: 2, writtenAt: '2026-10-19T00:00:00Z' },
  { version: 1, writtenAt: 'bad date' }, { version: 1, writtenAt: '2026-10-19T00:00:00Z', playerData: {} }]) {
  fs.writeFileSync(marker, JSON.stringify(body)); assert.throws(() => startupMetadata(dir)); checks++;
}
const { validateNormalExit } = require('./identity');
const normalExpected = { ...identity, guardianPid: 42 };
const normalExit = { schema: 'cf7.scene-entry.normal-exit.v1', ...normalExpected,
  runtimeMode: 'isolated_candidate', exitCode: 0, forced: false };
validateNormalExit(normalExit, normalExpected); checks++;
for (const bad of [{ exitCode: 1 }, { forced: true }, { guardianPid: 41 }, { processPath: 'foreign' }]) {
  assert.throws(() => validateNormalExit({ ...normalExit, ...bad }, normalExpected)); checks++;
}
const { validateBinding } = require('./cdp-input');
const own = { guardianPid: 4242, processPath: 'C:/owned/candidate/Core.exe', projectRoot: 'C:/owned' };
const proof = { observedAt: new Date().toISOString(), listeners: [{ LocalAddress: '127.0.0.1', OwningProcess: 4243 }],
  processes: [{ ProcessId: 4242, ExecutablePath: own.processPath, createdAt: new Date().toISOString() },
    { ProcessId: 4243, Name: 'msedgewebview2.exe', ParentProcessId: 4242,
      CommandLine: 'browser --user-data-dir="C:/owned/launcher/webview2_userdata/fixed-154.0.4258.53/EBWebView"' }] };
assert.equal(validateBinding(proof, own, 10101, proof.observedAt).guardianPid, 4242); checks++;
for (const change of [p => { p.listeners[0].LocalAddress = '0.0.0.0'; },
  p => { p.listeners[0].OwningProcess = 9999; }, p => { p.processes[1].ParentProcessId = 9999; },
  p => { p.processes[1].CommandLine = 'browser --user-data-dir="C:/foreign"'; },
  p => { p.processes[0].ExecutablePath = 'C:/foreign/Core.exe'; }, p => { p.observedAt = '2020-01-01'; },
  p => { p.processes[0].createdAt = '2020-01-01'; },
  p => { p.processes[1].CommandLine = 'browser --user-data-dir="C:/owned/launcher/webview2_userdata/../foreign"'; },
  p => { p.processes[1].CommandLine = 'browser --user-data-dir="C:/owned/launcher/webview2_userdata-foreign/fixed-154.0.4258.53/EBWebView"'; }]) {
  const bad = structuredClone(proof); change(bad);
  assert.throws(() => validateBinding(bad, own, 10101, proof.observedAt)); checks++;
}
const { validateOrderedLegs } = require('./ui-session');
const flowLabels = ['first-entry', 'external-hop', 'same-frame-return', 'return-base',
  'repeat-entry', 'return-base-2', 'repeat-entry-2', 'return-base-3'];
const sequence = flowLabels.map((label, index) => {
  const scene = label.startsWith('return-base') ? '基地场景-基地门口'
    : label === 'external-hop' ? '地图-军阀帐篷' : '地图-测试空间';
  const route = label.startsWith('return-base') ? null : label === 'first-entry' ? 'label'
    : label.startsWith('repeat-entry') ? 'remembered_frame' : 'same_frame';
  const target = index + 3, id = 'tr:' + (index + 1), root = route === null ? 146 : 158;
  const records = [wire('cover', 1, target, id), 'event=scene_transition_begin id=' + id,
    wire('loading', 3, target, id), wire('reveal', 4, target, id),
    'event=scene_transition_revealed id=' + id + ' scene=' + target,
    '[SceneEntryReady] request=' + id + ' targetScene=' + target + ' rootFrame=' + root + ' scene=' + scene];
  if (route) records.push('[SceneEntryNavigation] route=' + route + ' from='
    + (route === 'same_frame' ? 158 : 146) + ' target=' + (route === 'label' ? 0 : 158) + ' scene=' + scene);
  return { label, scene, route, records };
});
assert.equal(validateOrderedLegs(sequence, 2).length, 8); checks++;
assert.throws(() => validateOrderedLegs(sequence.slice(1), 2)); checks++;
assert.throws(() => validateOrderedLegs([sequence[1], sequence[0], ...sequence.slice(2)], 2)); checks++;
const duplicateTarget = structuredClone(sequence);
duplicateTarget[1].records = duplicateTarget[1].records.map(line => line.replaceAll('targetScene":4', 'targetScene":3')
  .replaceAll('targetScene=4', 'targetScene=3').replaceAll('scene=4', 'scene=3'));
assert.throws(() => validateOrderedLegs(duplicateTarget, 2)); checks++;
const duplicateRequest = structuredClone(sequence);
duplicateRequest[1].records = duplicateRequest[1].records.map(line => line.replaceAll('tr:2', 'tr:1'));
assert.throws(() => validateOrderedLegs(duplicateRequest, 2)); checks++;
const absentReady = structuredClone(sequence);
absentReady[1].records = absentReady[1].records.filter(line => !line.includes('SceneEntryReady'));
assert.throws(() => validateOrderedLegs(absentReady, 2)); checks++;
console.log('External scene evidence guards: ' + checks + ' checks passed (offline validation only).');
