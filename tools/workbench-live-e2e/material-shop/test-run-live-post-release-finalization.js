"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const Finalize = require("./finalize-clone-release");
const Live = require("./run-live-journey");

const SLOT = "cf7_agent_a5_material_shop_run_test";

function inspection(overrides) {
  const value = Object.assign({
    schema: "workbench-live-e2e.clone-lock-inspection.v1",
    apiVersion: CloneGuard.API_VERSION,
    observedAt: "2026-08-13T12:00:00.000Z",
    slot: SLOT,
    lockPath: "E:\\fixture\\tmp\\workbench-live-e2e\\locks\\" + SLOT + ".clone.lock",
    lockPresent: false,
    recordSha256: null,
    ownerPid: null,
    ownerProcessStartUtcTicks: null,
    observedProcessStartUtcTicks: null,
    ownerState: "absent",
    recoveryPresent: false,
    recoveryStatus: null,
    recoveryRecordSha256: null,
  }, overrides || {});
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function fixture(phase, overrides) {
  const calls = { inspections: [], blockers: [] };
  const runDir = path.resolve("E:\\fixture\\run");
  const options = Object.assign({
    releasePhase: phase,
    releasedClone: { cloneLockReleased: true, recoveryCleared: true,
      releasedAt: "2026-08-13T12:00:00.000Z" },
    releaseIntentPath: path.join(runDir, "clone-release-intent.json"),
    error: Object.assign(new Error("receipt failed"), { code: "receipt_failed" }),
    runDir,
    plan: { runId: "future-live-release-test" },
    preparation: { resourcesRoot: path.resolve("E:\\fixture"),
      slots: { targetSlot: SLOT } },
    preparationPath: path.join(runDir, "preparation.json"),
    buildPath: path.join(runDir, "candidate-build.json"),
    inspectCloneLock: (request) => {
      calls.inspections.push(request);
      return inspection();
    },
    writeBlocker: (request) => {
      calls.blockers.push(request);
      return { blockerPath: path.join(runDir, Finalize.FINALIZATION_REQUIRED_NAME),
        blocker: { schema: Finalize.FINALIZATION_BLOCKER_SCHEMA } };
    },
  }, overrides || {});
  return { calls, options };
}

for (const phase of ["released", "receipt_created"]) {
  test("post-release " + phase + " writes one exact required-finalization marker", () => {
    const value = fixture(phase);
    const result = Live.persistPostReleaseFinalizationRequired(value.options);
    assert.equal(value.calls.inspections.length, 1);
    assert.deepEqual(value.calls.inspections[0], {
      root: value.options.preparation.resourcesRoot,
      slot: SLOT,
    });
    assert.equal(value.calls.blockers.length, 1);
    const request = value.calls.blockers[0];
    assert.equal(request.commitMayHaveReachedAuthority, true);
    assert.equal(request.cleanupError, null);
    assert.equal(request.cleanupResult.releasedBeforeCommit, false);
    assert.equal(request.cleanupResult.cloneAlreadyReleased, true);
    assert.equal(request.cleanupResult.runtimeCleanupVerified, true);
    assert.equal(request.cleanupResult.shutdownSucceeded, true);
    assert.equal(request.cleanupResult.preservedForManualRecovery, false);
    assert.equal(request.cleanupResult.releasePhase, phase);
    assert.deepEqual(request.cleanupResult.released, value.options.releasedClone);
    assert.equal(request.cleanupResult.cloneInspection.ownerState, "absent");
    assert.equal(path.basename(result.persisted.blockerPath),
      Finalize.FINALIZATION_REQUIRED_NAME);
  });
}

test("pre-release phases do not claim finalization-only recovery", () => {
  for (const phase of ["not_started", "intent_written", "release_in_progress",
    "receipt_written"]) {
    const value = fixture(phase);
    assert.equal(Live.persistPostReleaseFinalizationRequired(value.options), null);
    assert.equal(value.calls.inspections.length, 0);
    assert.equal(value.calls.blockers.length, 0);
  }
});

test("returned release must explicitly prove lock and recovery clearance", () => {
  for (const releasedClone of [null, {}, { cloneLockReleased: true },
    { cloneLockReleased: false, recoveryCleared: true }]) {
    const value = fixture("released", { releasedClone });
    assert.throws(() => Live.persistPostReleaseFinalizationRequired(value.options), {
      code: "material_shop_post_release_state_invalid",
    });
    assert.equal(value.calls.inspections.length, 0);
    assert.equal(value.calls.blockers.length, 0);
  }
});

test("fresh inspection must prove exact absent lock and recovery state", () => {
  const cases = [
    { lockPresent: true, ownerState: "owner_active", ownerPid: 123,
      recordSha256: "a".repeat(64) },
    { recoveryPresent: true, recoveryStatus: "prepared_pending_release",
      recoveryRecordSha256: "b".repeat(64) },
  ];
  cases.forEach((drift) => {
    const value = fixture("released", {
      inspectCloneLock: (request) => {
        value.calls.inspections.push(request);
        return inspection(drift);
      },
    });
    assert.throws(() => Live.persistPostReleaseFinalizationRequired(value.options), {
      code: "material_shop_post_release_inspection_invalid",
    });
    assert.equal(value.calls.blockers.length, 0);
  });
});

test("release phases advance only through the frozen sequence", () => {
  const sequence = ["not_started", "intent_written", "release_in_progress", "released",
    "receipt_created", "receipt_written"];
  for (let index = 1; index < sequence.length; index += 1) {
    assert.equal(Live.advanceReleasePhase(sequence[index - 1], sequence[index]),
      sequence[index]);
  }
  assert.throws(() => Live.advanceReleasePhase("released", "receipt_written"), {
    code: "material_shop_release_phase_invalid",
  });
});

test("both live execution paths branch before any cleanup after release", () => {
  const source = fs.readFileSync(path.join(__dirname, "run-live-journey.js"), "utf8");
  assert.equal((source.match(/let releasePhase = "not_started";/g) || []).length, 2);
  assert.equal((source.match(/let releasedClone = null;/g) || []).length, 2);
  assert.equal((source.match(/persistPostReleaseFinalizationRequired\(\{/g) || []).length, 2);
  const agent = source.indexOf("async function executeAgentRuntimeOwned");
  const legacy = source.indexOf("async function executeOwned");
  const agentPostRelease = source.indexOf("if (isPostReleaseFinalizationPhase(releasePhase))",
    agent);
  const agentFinish = source.indexOf("failureState.controller.finish", agentPostRelease);
  const legacyPostRelease = source.indexOf("if (isPostReleaseFinalizationPhase(releasePhase))",
    legacy);
  const legacyCleanup = source.indexOf("journey.cleanupFailure", legacyPostRelease);
  assert(agentPostRelease > agent && agentFinish > agentPostRelease);
  assert(legacyPostRelease > legacy && legacyCleanup > legacyPostRelease);
});
