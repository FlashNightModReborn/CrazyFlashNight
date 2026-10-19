'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { seal, verifyAfter, validateNormalExit } = require('./identity');
const { LogTracker } = require('./log-tracker');
const { TransitionOracle } = require('./oracle');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const labels = ['first-entry', 'external-hop', 'same-frame-return', 'return-base',
  'repeat-entry', 'return-base-2', 'repeat-entry-2', 'return-base-3'];

// Lighting telemetry may be coalesced. Previous proven targets remain a strict
// lower bound, independent of the lighting log's startup watermark.
function validateOrderedLegs(legs, initialScene = 0) {
  if (legs.length !== labels.length) throw new Error('all eight scene legs required');
  const requests = new Set();
  let previous = initialScene;
  return legs.map((leg, index) => {
    if (leg.label !== labels[index]) throw new Error('scene leg order mismatch');
    const result = new TransitionOracle({ label: leg.label, scene: leg.scene,
      route: leg.route, minimumScene: previous }).add(leg.records);
    if (result.status !== 'pass' || requests.has(result.requestId)
        || result.targetScene <= previous) throw new Error('scene sequence lacks fresh increasing target proof');
    requests.add(result.requestId); previous = result.targetScene; return result;
  });
}

// Native input uses sky; explicitly authorized browser input has a separate channel.
// This is normal production entry, not the A5 specialist/trusted-runner journey.
class SceneUiSession {
  constructor(root, candidate) {
    if (!/^c-[0-9a-f]{12}-[0-9a-f]{10}-[a-z0-9][a-z0-9-]{0,31}$/.test(candidate))
      throw new Error('normal candidate requires an immutable c-* identity');
    this.slot = 'cf7_agent_equipment_tuning';
    this.identity = seal(root, { candidate, slot: this.slot });
    this.file = path.join(root, 'tmp/external-scene-entry/e2e-ui-' + Date.now() + '.json');
    this.data = { schema: 'cf7.scene-entry.normal-ui-evidence.v1',
      entryKind: 'normal_bootstrap_ui', trustedRunnerUsed: false,
      startedAt: new Date().toISOString(), identity: this.identity,
      actions: [], legs: [], errors: [], shutdown: null, result: 'incomplete' };
    this.tracker = new LogTracker(LogTracker.discover(root), this.file.replace('.json', '-receipts.jsonl'));
    this.active = null;
    this.persist();
  }
  persist() { fs.writeFileSync(this.file, JSON.stringify(this.data, null, 2) + '\n'); }
  attachStart(report) {
    if (report.schema !== 'cf7.scene-entry.normal-start.v1' || report.runtimeMode !== 'isolated_candidate'
        || report.processPath.toLowerCase() !== this.identity.processPath.toLowerCase()
        || report.buildIdentity !== this.identity.buildIdentity || report.payloadClosure !== this.identity.payloadClosure
        || !(report.guardianPid > 0)) throw new Error('normal startup identity mismatch');
    this.data.start = report; this.identity.guardianPid = report.guardianPid; this.persist();
  }
  action(window, method, details, basisTree) {
    if (window.app.toLowerCase() !== ('process:' + this.identity.processPath).toLowerCase())
      throw new Error('UI action belongs to a different executable');
    this.data.actions.push({ at: new Date().toISOString(), channel: 'sky', window, method, details,
      basisTreeSha256: crypto.createHash('sha256').update(basisTree || '').digest('hex') });
    this.persist();
  }
  browserAction(record) {
    if (record.channel !== 'cdp_input' || record.binding?.guardianPid !== this.identity.guardianPid
        || record.physicalInputAttestation !== false || !this.data.start)
      throw new Error('browser action lacks its owned candidate binding');
    this.data.actions.push(record); this.persist();
  }
  expect(label, scene, route = null) {
    if (this.active || labels[this.data.legs.length] !== label) throw new Error('dependent navigation out of order');
    const minimumScene = Math.max(this.tracker.checkpoint(), this.data.legs.at(-1)?.targetScene || 0);
    this.active = new TransitionOracle({ label, scene, route, minimumScene });
    this.data.pending = { ...this.active.expected, at: new Date().toISOString() }; this.persist();
  }
  async observe(timeoutMs = 45000) {
    if (!this.active) throw new Error('scene action was not checkpointed');
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      const records = this.tracker.poll().records.filter(r => /scene_transition|SceneEntry/.test(r.line));
      const result = this.active.add(records);
      if (result.status === 'pass') {
        this.data.legs.push({ ...result, records: this.active.records });
        this.active = null; delete this.data.pending; this.persist(); return result;
      }
      if (result.status === 'fail') return this.fail(result);
      await sleep(300);
    }
    return this.fail(this.active.result());
  }
  fail(result) {
    this.data.errors.push({ result, records: this.active?.records || [] });
    this.data.result = 'failed'; this.persist();
    throw new Error('navigation stopped without replay: ' + result.reason);
  }
  finish(exit) {
    validateNormalExit(exit, this.identity);
    this.data.shutdown = exit;
    this.data.postRun = verifyAfter(this.identity, this.slot);
    if (this.active || this.data.errors.length || this.data.legs.length !== labels.length)
      throw new Error('clean normal exit does not substitute for all eight scene legs');
    this.data.orderedSequenceProof = { result: 'pass', legs: validateOrderedLegs(this.data.legs) };
    this.data.finishedAt = new Date().toISOString(); this.data.result = 'passed_normal_ui';
    this.tracker.close(); this.persist(); return this.data;
  }
}
module.exports = { SceneUiSession, validateOrderedLegs };
