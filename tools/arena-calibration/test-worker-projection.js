"use strict";
const assert = require("assert");
const { normalizeProjection, PROJECTION_CONSUMERS } = require("./lib/arena-worker-client");
const { validateProjectionProof, validateProjectionRows } = require("./run-worker-shard");
const { sha256Bytes } = require("./lib/immutable-evidence");
const { assertSchemaInstance: assertSchema } = require("./lib/schema-registry");
const copy = (value) => JSON.parse(JSON.stringify(value));
let checks = 0;
function ok(run) { run(); checks++; }
function reject(run) { assert.throws(run); checks++; }
const requested = { presentationPolicy: "full", projectionConsumers: Object.fromEntries(PROJECTION_CONSUMERS.map((name) =>
  [name, name === "sceneLighting" || name === "equipmentLighting" ? "full" : "none"])),
controlFrameFormat: "f-visual-v1", visualSeedRevision: "visual-event-v1", simulationRngConsumptionRevision: "legacy-global-consume-v1", sessionVisualSeed: 42 };
ok(() => assert.deepStrictEqual(normalizeProjection(requested), requested));
ok(() => assert.strictEqual(normalizeProjection(undefined), undefined));
for (const change of [p => p.presentationPolicy = "none", p => p.controlFrameFormat = "f-control-placeholder-v1",
  p => p.projectionConsumers.equipmentLighting = "none", p => p.projectionConsumers.sceneLighting = "none",
  p => p.projectionConsumers.ray = "shadow", p => p.projectionConsumers.extra = "none", p => delete p.projectionConsumers.chain,
  p => p.simulationRngConsumptionRevision = "visual-isolation-2", p => p.sessionVisualSeed = 0, p => p.sessionVisualSeed = 1.5,
  p => p.sessionVisualSeed = 2147483647, p => p.extra = true, p => delete p.visualSeedRevision]) {
  reject(() => { const p = copy(requested); change(p); normalizeProjection(p); });
}
const launch = { ...requested, workerId: "w01", sessionEpoch: "s01" };
const hash = "sha256:" + "a".repeat(64);
const policy = { presentation: "full", readinessKind: "arena.presented.v1", projectionConsumers: requested.projectionConsumers,
  controlFrameFormat: "f-visual-v1", ownership: "as2-gameplay-native-model-v1",
  catalogBindings: { bulletStyles: hash, combatFxStyles: hash, rayStyles: hash, sceneLights: hash },
  visualSeedRevision: "visual-event-v1", simulationRngConsumptionRevision: "legacy-global-consume-v1", sessionVisualSeed: 42 };
const receipt = { ...policy, task: "worker_projection_committed", version: 1, sequence: 2, workerId: "w01", sessionEpoch: "s01",
  connectionGeneration: 7, contractId: "b".repeat(32), policyDigest: sha256Bytes(Buffer.from(JSON.stringify(policy))),
  installClockKind: "flashRootEnterFrame", installEpoch: 1, installTick: 2 };
const proof = { state: "committed", committed: true, failure: null, connectionGeneration: 7, contractId: receipt.contractId, policy, installReceipt: receipt };
ok(() => validateProjectionProof(proof, launch));
for (const change of [p => p.committed = false, p => p.installReceipt.installTick = 0, p => p.installReceipt.installClockKind = "manual",
  p => p.installReceipt.workerId = "other", p => p.installReceipt.contractId = "c".repeat(32), p => p.installReceipt.connectionGeneration = 6,
  p => p.installReceipt.policyDigest = hash, p => p.installReceipt.projectionConsumers.ray = "full"]) {
  reject(() => { const p = copy(proof); change(p); validateProjectionProof(p, launch); });
}
const row = { presentationPolicy: "full", presentationContractVersion: 1, presentationContractId: receipt.contractId,
  readinessKind: "arena.presented.v1", projectionConsumers: requested.projectionConsumers, projectionInstallReceipt: receipt,
  visualSeedRevision: requested.visualSeedRevision, simulationRngConsumptionRevision: requested.simulationRngConsumptionRevision };
ok(() => validateProjectionRows([row], launch, proof));
reject(() => validateProjectionRows([{ ...row, presentationContractId: "c".repeat(32) }], launch, proof));
reject(() => validateProjectionRows([{ ...row, projectionInstallReceipt: null }], launch, proof));

// The installed-contract check and the normal raw-result schema must accept the same real wire shape.
const legacyRow = { schema: "arena-calibration.result.v1", workerId: "w01", sessionEpoch: "s01", assignmentId: "a01", attemptId: "t01",
  batchId: "projection-schema", manifestHash: hash, caseId: "case-1", caseHash: hash, runId: "case-1-r001", repeatIndex: 1,
  status: "timeout", winner: "timeout", frames: 1800, durationMs: 60001, requestedSpawnDistance: 650,
  blueFormation: "line", redFormation: "line", formationSpacing: 54, phaseSpawnCount: 0, spawnedUnits: [],
  blueSpawnPositions: [], redSpawnPositions: [], formationAudit: {}, authorityContext: {},
  blue: { maxHp: 10, remainHp: 5, aliveCount: 1, startMaxHp: 10, startCount: 1 },
  red: { maxHp: 10, remainHp: 5, aliveCount: 1, startMaxHp: 10, startCount: 1 },
  blueUnitResults: [], redUnitResults: [], errors: [], startedAt: "2026-10-11T00:00:00Z", completedAt: "2026-10-11T00:01:00Z" };
const boundRow = { ...legacyRow, ...copy(row) };
ok(() => assertSchema("arena-calibration.result.v1", legacyRow));
ok(() => { assertSchema("arena-calibration.result.v1", boundRow); validateProjectionRows([boundRow], launch, proof); });
for (const field of Object.keys(row))
  reject(() => { const r = copy(boundRow); delete r[field]; assertSchema("arena-calibration.result.v1", r); });
for (const change of [r => r.extra = true, r => r.presentationContractVersion = "1", r => r.projectionConsumers.extra = "none",
  r => r.projectionConsumers.sceneLighting = "none", r => r.projectionInstallReceipt.extra = true,
  r => r.projectionInstallReceipt.installTick = 0, r => r.projectionInstallReceipt.installClockKind = "manual",
  r => r.projectionInstallReceipt.catalogBindings.extra = hash, r => r.projectionInstallReceipt.catalogBindings.rayStyles = "uppercase",
  r => r.projectionInstallReceipt.sessionVisualSeed = 2147483647, r => delete r.workerId])
  reject(() => { const r = copy(boundRow); change(r); assertSchema("arena-calibration.result.v1", r); });
console.log(`Worker projection contracts: ${checks} checks passed`);
