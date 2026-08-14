#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");
const Discard = require("./discard-seed-audit-failed-run");
const Materialize = require("./materialize");
const RunOperationLease = require("./run-operation-lease");

let passed = 0;
let total = 0;

function test(name, body) {
  total += 1;
  body();
  passed += 1;
  process.stdout.write("PASS " + name + "\n");
}

function negative(name, code, body) {
  test(name, () => {
    let error = null;
    try { body(); } catch (failure) { error = failure; }
    assert(error, name + " did not fail closed");
    assert.strictEqual(error.code, code);
  });
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function reseal(value, key) {
  delete value[key];
  value[key] = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function writeIntent(runDir, intent) {
  const name = Discard.intentMarkerName(intent);
  fs.writeFileSync(path.join(runDir, name), JSON.stringify(intent, null, 2) + "\n", {
    encoding: "utf8", flag: "wx", mode: 0o600,
  });
  return name;
}

function probe(operation, preparationSha256, materializationSha256, closureSha256,
  scopeSha256, applicabilitySha256, buildSha256, candidateRoot) {
  const slots = [
    "cf7_agent_a5_material_shop_seed_test",
    "cf7_agent_a5_material_shop_run_test",
    "cf7_agent_a5_material_shop_recovery_test",
  ].map((slot) => ({ slot, lockPresent: false, recoveryPresent: false,
    artifactCount: 0 }));
  const value = {
    eligibilityKind: Discard.ELIGIBILITY_KIND,
    preparationSha256,
    materializationSha256,
    closureSha256,
    scopeSha256,
    applicabilitySha256,
    buildSha256,
    candidateRoot,
    historicalRootBug: { relativePath:
      "tools/workbench-live-e2e/material-shop/run-live-journey.js",
    bytes: 1, sha256: "7".repeat(64) },
    runnerLogs: {
      stdout: { derivedRelativePath: "operator-attestations/test.runner.stdout.log",
        bytes: 0, sha256: Discard.EMPTY_SHA256 },
      stderr: { derivedRelativePath: "operator-attestations/test.runner.stderr.log",
        bytes: Buffer.byteLength(JSON.stringify(Discard.EXPECTED_ERROR) + "\n"),
        sha256: Evidence.sha256Bytes(Buffer.from(
          JSON.stringify(Discard.EXPECTED_ERROR) + "\n", "utf8")) },
      parsedError: clone(Discard.EXPECTED_ERROR),
    },
    qualifyingLiveTerminal: clone(operation.qualifyingLiveTerminal),
    preCandidateState: {
      launcherCoreProcessCount: 0,
      candidateProcessCount: 0,
      processInventorySha256: Evidence.sha256Text(Evidence.canonicalJson([])),
      passiveTranscriptBytes: 0,
      passiveTranscriptSha256: Discard.EMPTY_SHA256,
      admissionCount: 0,
      rawEvidenceCount: 0,
      cloneMutationCount: 0,
      lifecycleBasePresent: false,
      slots,
    },
    runLayout: { topLevelCoreNames: [], entries: [], fileCount: 0,
      layoutSha256: Evidence.sha256Text(Evidence.canonicalJson([])) },
    postBuildScope: { scopeSha256, ignoredOutputInventorySha256: "8".repeat(64),
      ignoredFileCount: 0, ignoredTotalBytes: 0 },
    gitWorktreeIdentitySha256: "9".repeat(64),
    operation: clone(operation),
  };
  value.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return Discard.validateProbe(value);
}

function context(runId, runDir, destination, currentProbe, hashes) {
  return {
    preparation: { runId, runDir, resourcesRoot: destination,
      preparationSha256: hashes.preparation },
    materialization: { materializationSha256: hashes.materialization,
      gitWorktree: { head: "a".repeat(40),
        commonDir: path.join(Common.CANONICAL_ROOT, ".git") } },
    closure: { closureSha256: hashes.closure,
      scope: { scopeSha256: hashes.scope } },
    applicability: { applicabilitySha256: hashes.applicability },
    build: { buildSha256: hashes.build, candidateRoot: hashes.candidateRoot },
    probe: currentProbe,
  };
}

function ensureControl(runDir) {
  const control = path.join(runDir, "control");
  ["acks", "captures", "requests"].forEach((name) =>
    fs.mkdirSync(path.join(control, name), { recursive: true }));
  return control;
}

function main() {
  const runId = "seed-audit-resume-test-" + process.pid + "-" + Date.now();
  const owned = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runDir = path.join(owned, "runs", runId);
  const materializedBase = path.join(owned, Materialize.MATERIALIZED_DIRECTORY, runId);
  const destination = path.join(materializedBase, "resources");
  const hashes = {
    preparation: "1".repeat(64),
    materialization: "2".repeat(64),
    closure: "3".repeat(64),
    scope: "4".repeat(64),
    applicability: "5".repeat(64),
    build: "6".repeat(64),
    candidateRoot: path.join(destination, "tmp", "runtime-candidates", "v2", "a5"),
  };
  fs.mkdirSync(runDir, { recursive: true });
  fs.mkdirSync(destination, { recursive: true });
  const control = ensureControl(runDir);
  let liveHandle = null;
  let orphanTerminalHandle = null;
  let orphanStaleHandle = null;
  let foreignHandle = null;
  let firstHandle = null;
  let postIntentOrphanHandle = null;
  let resumeHandle = null;
  let extraHandle = null;
  try {
    test("historical seed-audit cleanup source closure is exact", () => {
      const projection = clone(Discard.HISTORICAL_FAILURE_SOURCES);
      assert.strictEqual(Discard.validateHistoricalFailureSources(projection), projection);
      assert.strictEqual(projection.length, 3);
    });
    negative("one historical source byte-count drift rejects eligibility",
      "material_shop_seed_failure_historical_source_invalid", () => {
        const drift = clone(Discard.HISTORICAL_FAILURE_SOURCES);
        drift[1].bytes += 1;
        Discard.validateHistoricalFailureSources(drift);
      });
    negative("one historical source SHA drift rejects eligibility",
      "material_shop_seed_failure_historical_source_invalid", () => {
        const drift = clone(Discard.HISTORICAL_FAILURE_SOURCES);
        drift[2].sha256 = "0".repeat(64);
        Discard.validateHistoricalFailureSources(drift);
      });
    negative("fixed current runner cannot qualify as the historical root bug",
      "material_shop_seed_failure_historical_source_invalid", () => {
        Discard.assertHistoricalRootBug(Common.CANONICAL_ROOT);
      });
    liveHandle = RunOperationLease.acquire({ runDir, runId, mode: "live_execution",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    const liveTerminal = RunOperationLease.release(liveHandle);
    liveHandle = null;

    foreignHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: "d".repeat(64) });
    RunOperationLease.release(foreignHandle);
    const foreignLease = foreignHandle.lease;
    foreignHandle = null;
    negative("foreign no-intent cleanup outcome cannot be adopted",
      "material_shop_seed_failure_operation_chain_invalid", () => {
        Discard.preIntentOperationHistory(runDir, hashes.preparation, hashes.build);
      });
    fs.unlinkSync(path.join(runDir, RunOperationLease.terminalName(foreignLease)));

    orphanTerminalHandle = RunOperationLease.acquire({ runDir, runId,
      mode: "built_only_discard", preparationSha256: hashes.preparation,
      buildSha256: hashes.build });
    RunOperationLease.release(orphanTerminalHandle);
    orphanTerminalHandle = null;
    orphanStaleHandle = RunOperationLease.acquire({ runDir, runId,
      mode: "built_only_discard", preparationSha256: hashes.preparation,
      buildSha256: hashes.build });
    RunOperationLease.release(orphanStaleHandle);
    const orphanStaleLease = orphanStaleHandle.lease;
    orphanStaleHandle = null;
    fs.renameSync(path.join(runDir, RunOperationLease.terminalName(orphanStaleLease)),
      path.join(runDir, RunOperationLease.resolvedName(orphanStaleLease)));
    const preIntent = Discard.preIntentOperationHistory(runDir, hashes.preparation,
      hashes.build);

    test("no-intent terminal and stale cleanup attempts are mechanically adopted", () => {
      assert.strictEqual(preIntent.priorOperationChain.length, 2);
      assert.deepStrictEqual(preIntent.priorOperationChain.map((entry) => entry.outcome.kind)
        .sort(), ["stale_recovery", "terminal"]);
      assert(preIntent.priorOperationChain.every((entry) =>
        entry.lease.preparationSha256 === hashes.preparation
          && entry.lease.buildSha256 === hashes.build));
    });

    firstHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    negative("an active no-intent cleanup lease must be explicitly terminal or stale-recovered",
      "material_shop_seed_failure_operation_busy", () => {
        Discard.preIntentOperationHistory(runDir, hashes.preparation, hashes.build);
      });
    const firstOperation = Discard.captureCleanupOperation(runDir, hashes.preparation,
      hashes.build, preIntent.priorOperationChain);
    const firstProbe = probe(firstOperation, hashes.preparation, hashes.materialization,
      hashes.closure, hashes.scope, hashes.applicability, hashes.build,
      hashes.candidateRoot);
    const firstIntent = Discard.createIntent(context(runId, runDir, destination,
      firstProbe, hashes), "2026-08-12T00:00:00.000Z",
    preIntent.priorOperationChain);
    const firstName = writeIntent(runDir, firstIntent);

    test("initial intent seals the first cleanup lease", () => {
      assert.strictEqual(firstIntent.sequence, 0);
      assert.strictEqual(firstIntent.operationChain.length, 3);
      assert(firstIntent.operationChain.slice(0, -1).every((entry) => entry.outcome));
      assert.strictEqual(firstIntent.operationChain[2].lease.leaseSha256,
        firstOperation.lease.leaseSha256);
      assert.strictEqual(firstIntent.operationChain[2].outcome, null);
    });

    RunOperationLease.release(firstHandle);
    firstHandle = null;
    postIntentOrphanHandle = RunOperationLease.acquire({ runDir, runId,
      mode: "built_only_discard", preparationSha256: hashes.preparation,
      buildSha256: hashes.build });
    RunOperationLease.release(postIntentOrphanHandle);
    const postIntentOrphanLease = postIntentOrphanHandle.lease;
    postIntentOrphanHandle = null;
    fs.renameSync(path.join(runDir, RunOperationLease.terminalName(postIntentOrphanLease)),
      path.join(runDir, RunOperationLease.resolvedName(postIntentOrphanLease)));
    const initialState = Discard.loadState(runDir);
    const sealed = Discard.sealPriorOperationChain(initialState.intent);

    test("active-intent pre-remove crash adopts the recovered orphan operation", () => {
      assert.strictEqual(sealed.length, 4);
      assert.strictEqual(sealed[2].outcome.kind, "terminal");
      assert.strictEqual(sealed[2].outcome.name,
        RunOperationLease.terminalName(sealed[2].lease));
      assert.strictEqual(sealed[3].outcome.kind, "stale_recovery");
      assert.strictEqual(sealed[3].lease.leaseSha256,
        postIntentOrphanLease.leaseSha256);
    });

    test("stale recovery is an admitted exact prior outcome kind", () => {
      const stale = clone(sealed[2].outcome);
      stale.kind = "stale_recovery";
      stale.name = RunOperationLease.resolvedName(stale.lease);
      assert.strictEqual(Discard.validateOutcome(stale, sealed[2].lease,
        sealed[2].leaseArtifact, runDir), stale);
    });

    negative("resume rejects whitespace-only drift in a retained cleanup archive",
      "material_shop_seed_failure_operation_chain_invalid", () => {
        const archivePath = path.join(runDir, sealed[0].outcome.name);
        const original = fs.readFileSync(archivePath);
        fs.writeFileSync(archivePath,
          JSON.stringify(JSON.parse(original.toString("utf8"))) + "\n", "utf8");
        try { Discard.sealPriorOperationChain(initialState.intent); }
        finally { fs.writeFileSync(archivePath, original); }
      });

    resumeHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    negative("fresh destructive probe rejects retained archive byte drift",
      "material_shop_seed_failure_operation_chain_invalid", () => {
        const archivePath = path.join(runDir, sealed[0].outcome.name);
        const original = fs.readFileSync(archivePath);
        fs.writeFileSync(archivePath,
          JSON.stringify(JSON.parse(original.toString("utf8"))) + "\n", "utf8");
        try {
          Discard.captureCleanupOperation(runDir, hashes.preparation,
            hashes.build, sealed);
        } finally { fs.writeFileSync(archivePath, original); }
      });
    const resumeOperation = Discard.captureCleanupOperation(runDir, hashes.preparation,
      hashes.build, sealed);
    const resumeProbe = probe(resumeOperation, hashes.preparation, hashes.materialization,
      hashes.closure, hashes.scope, hashes.applicability, hashes.build,
      hashes.candidateRoot);
    const resumeContext = context(runId, runDir, destination, resumeProbe, hashes);
    const resumeIntent = Discard.createResumeIntent(resumeContext, initialState,
      sealed, "2026-08-12T00:01:00.000Z");
    const resumeName = writeIntent(runDir, resumeIntent);

    test("resume intent appends parent-bound cleanup mutex", () => {
      assert.strictEqual(resumeIntent.sequence, 1);
      assert.deepStrictEqual(resumeIntent.parentIntent, {
        name: firstName, intentSha256: firstIntent.intentSha256,
      });
      assert.strictEqual(resumeIntent.operationChain.length, 5);
      assert(resumeIntent.operationChain.slice(0, -1).every((entry) => entry.outcome));
      assert.strictEqual(resumeIntent.operationChain[4].lease.leaseSha256,
        resumeOperation.lease.leaseSha256);
      assert.strictEqual(resumeIntent.operationChain[4].outcome, null);
    });

    test("loadState replays the append-only intent chain", () => {
      const state = Discard.loadState(runDir);
      assert.strictEqual(state.active, true);
      assert.strictEqual(state.intent.intentSha256, resumeIntent.intentSha256);
      assert.deepStrictEqual(state.markerNames.slice().sort(),
        [firstName, resumeName].sort());
      assert.strictEqual(state.intents.length, 2);
    });

    RunOperationLease.release(resumeHandle);
    resumeHandle = null;
    const closure = Discard.operationClosure(resumeIntent);

    test("operation closure binds live terminal plus both cleanup outcomes", () => {
      assert.strictEqual(closure.history.length, 6);
      assert.strictEqual(closure.outcomes.length, 5);
      assert.strictEqual(closure.outcome.lease.leaseSha256,
        resumeIntent.operationChain[4].lease.leaseSha256);
      assert.strictEqual(liveTerminal.leaseSha256,
        resumeIntent.probe.qualifyingLiveTerminal.lease.leaseSha256);
    });

    test("receipt reports the complete resumed operation chain", () => {
      const receipt = Discard.receiptFromIntent(resumeIntent, closure,
        "2026-08-12T00:02:00.000Z");
      assert.strictEqual(receipt.cleanupOperationCount, 5);
      assert.strictEqual(receipt.resumedCleanup, true);
      const closed = resumeIntent.operationChain.map((entry, index) => {
        const value = clone(entry);
        value.outcome = clone(closure.outcomes[index]);
        return value;
      });
      assert.strictEqual(receipt.operationChainSha256,
        Evidence.sha256Text(Evidence.canonicalJson(closed)));
    });

    negative("an already sealed outcome cannot drift from its retained marker",
      "material_shop_seed_failure_operation_chain_invalid", () => {
        const drift = clone(initialState.intent);
        drift.operationChain[0].outcome.kind = drift.operationChain[0].outcome.kind
          === "terminal" ? "stale_recovery" : "terminal";
        drift.operationChain[0].outcome.name = drift.operationChain[0].outcome.kind
          === "terminal" ? RunOperationLease.terminalName(drift.operationChain[0].lease)
            : RunOperationLease.resolvedName(drift.operationChain[0].lease);
        reseal(drift, "intentSha256");
        Discard.sealPriorOperationChain(drift);
      });

    negative("foreign parent digest cannot replay the intent chain",
      "material_shop_seed_failure_state_invalid", () => {
        const original = fs.readFileSync(path.join(runDir, resumeName));
        const foreign = clone(resumeIntent);
        foreign.parentIntent.intentSha256 = "f".repeat(64);
        reseal(foreign, "intentSha256");
        fs.writeFileSync(path.join(runDir, resumeName),
          JSON.stringify(foreign, null, 2) + "\n", "utf8");
        try { Discard.loadState(runDir); }
        finally { fs.writeFileSync(path.join(runDir, resumeName), original); }
      });

    negative("sealed prior outcome byte drift is rejected",
      "material_shop_seed_failure_operation_chain_invalid", () => {
        const drift = clone(resumeIntent);
        drift.operationChain[0].outcome.sha256 = "e".repeat(64);
        reseal(drift, "intentSha256");
        Discard.validateIntent(drift);
      });

    extraHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    RunOperationLease.release(extraHandle);
    const extraLease = extraHandle.lease;
    extraHandle = null;
    negative("foreign appended cleanup terminal cannot join a sealed chain",
      "material_shop_seed_failure_operation_drift", () => {
        Discard.operationClosure(resumeIntent);
      });
    fs.unlinkSync(path.join(runDir, RunOperationLease.terminalName(extraLease)));

    test("finalizer control replay accepts only the exact empty topology", () => {
      assert.deepStrictEqual(Discard.replayControlTopology(runDir), {
        directories: ["acks", "captures", "requests"], fileCount: 0,
      });
    });

    negative("extra control child is rejected on replay",
      "material_shop_seed_failure_control_invalid", () => {
        const extra = path.join(control, "foreign");
        fs.mkdirSync(extra);
        try { Discard.replayControlTopology(runDir); }
        finally { fs.rmdirSync(extra); }
      });

    negative("non-empty exact control child is rejected on replay",
      "material_shop_seed_failure_control_invalid", () => {
        const extra = path.join(control, "requests", "foreign.json");
        fs.writeFileSync(extra, "{}\n", "utf8");
        try { Discard.replayControlTopology(runDir); }
        finally { fs.unlinkSync(extra); }
      });

    negative("bare finalizer guard rejects a present worktree without deleting it",
      "material_shop_seed_failure_remove_incomplete", () => {
        try { Discard.assertFinalizeWorktreeAbsent(destination, () => false); }
        finally { assert(fs.existsSync(destination)); }
      });

    negative("bare finalizer guard rejects a Git-listed absent worktree",
      "material_shop_seed_failure_remove_incomplete", () => {
        const absent = path.join(materializedBase, "absent-resources");
        Discard.assertFinalizeWorktreeAbsent(absent, () => true);
      });

    test("full-context CLI remains acknowledged while bare finalizer accepts no context", () => {
      const full = Discard.parseArgs([
        "--discard-seed-audit-pre-candidate-failure",
        "--preparation", path.join(runDir, "preparation.json"),
        "--build", path.join(runDir, "candidate-build.json"),
        "--acknowledge-seed-audit-failure-discard",
      ]);
      assert.strictEqual(full.mode, "discard");
      const bare = Discard.parseArgs([
        "--finalize-seed-audit-failure-discard", "--run-dir", runDir,
      ]);
      assert.strictEqual(bare.mode, "finalize");
    });

    test("resume keeps two fresh probes before exact removal and finalizer has no remover", () => {
      const source = fs.readFileSync(path.join(__dirname,
        "discard-seed-audit-failed-run.js"), "utf8");
      const resumeStart = source.indexOf("function resumeDiscard");
      const firstProbe = source.indexOf(
        "const context = loadContext(settings, initialState, sealedPriorChain)", resumeStart);
      const intentWrite = source.indexOf("Materialize.writeJsonAtomicNew(markerPath, intent)",
        firstProbe);
      const secondProbe = source.indexOf(
        "const fresh = loadContext(settings, freshState, sealedPriorChain)", intentWrite);
      const removal = source.indexOf("removeAfterFreshProbe(fresh, operationHandle)",
        secondProbe);
      assert(resumeStart >= 0 && firstProbe > resumeStart && intentWrite > firstProbe
        && secondProbe > intentWrite && removal > secondProbe);
      const finalizeStart = source.indexOf("function finalize(");
      const finalizeEnd = source.indexOf("function probeEligibilityProjection", finalizeStart);
      assert(!source.slice(finalizeStart, finalizeEnd).includes("runGitRemove("));
      const generic = fs.readFileSync(path.join(__dirname, "discard-built-run.js"), "utf8");
      assert(generic.includes("assertNoLiveOperationHistory(initialPreparation.runDir)"));
      assert(!generic.includes("discard-seed-audit-failed-run"));
    });

    process.stdout.write(JSON.stringify({ ok: true, passed, total,
      status: "OFFLINE_VERIFIED", actualCleanupExecuted: false }) + "\n");
  } finally {
    for (const handle of [extraHandle, resumeHandle, postIntentOrphanHandle, firstHandle,
      foreignHandle,
      orphanStaleHandle, orphanTerminalHandle, liveHandle]) {
      if (handle && handle.active) {
        try { RunOperationLease.release(handle); } catch (_error) {}
      }
    }
    if (fs.existsSync(runDir)) fs.rmSync(runDir, { recursive: true, force: true });
    if (fs.existsSync(materializedBase)) {
      fs.rmSync(materializedBase, { recursive: true, force: true });
    }
  }
}

try { main(); }
catch (error) {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  process.exitCode = 1;
}
