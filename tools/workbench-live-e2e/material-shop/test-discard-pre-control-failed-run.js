#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Build = require("./build-candidate");
const Common = require("./common");
const Discard = require("./discard-pre-control-failed-run");
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
    assert.strictEqual(error.code, code, error && error.stack);
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

function projection(entry) {
  return { name: entry.name, bytes: entry.bytes, sha256: entry.sha256,
    kind: entry.kind, lease: clone(entry.lease) };
}

function binding(handle, runDir) {
  const histories = RunOperationLease.historyMarkers(runDir).map(projection);
  const live = histories.filter((entry) => entry.lease.mode === "live_execution");
  assert.strictEqual(live.length, 1);
  const value = { lease: clone(handle.lease), leaseArtifact: clone(handle.artifact),
    liveHistory: clone(live[0]), preexistingHistory: histories };
  reseal(value, "operationSha256");
  return Discard.validateOperationBinding(value, runDir,
    handle.lease.preparationSha256, handle.lease.buildSha256);
}

function makeContext(runId, runDir, destination, operation, runArtifacts, hashes) {
  const safety = {
    runArtifacts: { files: clone(runArtifacts),
      filesSha256: Materialize.filesDigest(runArtifacts) },
    postBuildScope: { scopeSha256: hashes.scope,
      ignoredOutputInventorySha256: "8".repeat(64),
      ignoredFileCount: 4, ignoredTotalBytes: 1024 },
    slots: ["seed", "target", "recovery"].map((slot) => ({ slot,
      lockPresent: false, recoveryPresent: false })),
    targetSetSha256: "9".repeat(64),
    targetArtifactsSha256: "a".repeat(64),
    materializationSha256: hashes.materialization,
    buildSha256: hashes.build,
    candidateRoot: hashes.candidateRoot,
    gitWorktreeIdentitySha256: "b".repeat(64),
    failureReceiptSha256: hashes.failureReceipt,
  };
  const probe = Object.assign({}, safety, { operation: clone(operation) });
  probe.safetyProbeSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Discard.safetyProbe(probe)));
  probe.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(
    Object.assign({}, Discard.safetyProbe(probe), { operation: probe.operation })));
  return {
    preparation: { runId, runDir, resourcesRoot: destination,
      preparationSha256: hashes.preparation },
    materialization: { materializationSha256: hashes.materialization,
      gitWorktree: { head: "c".repeat(40),
        commonDir: path.join(Common.CANONICAL_ROOT, ".git") } },
    closure: { closureSha256: hashes.closure,
      scope: { scopeSha256: hashes.scope } },
    build: { buildSha256: hashes.build, candidateRoot: hashes.candidateRoot },
    failureReceipt: { value: { receiptSha256: hashes.failureReceipt } },
    probe,
  };
}

function safeCleanup(target, expectedParent) {
  if (!fs.existsSync(target)) return;
  const resolved = path.resolve(target);
  const parent = path.resolve(expectedParent) + path.sep;
  assert(resolved.toLowerCase().startsWith(parent.toLowerCase()));
  fs.rmSync(resolved, { recursive: true, force: true });
}

function runGit(args) {
  const result = childProcess.spawnSync("git", args, {
    cwd: Common.CANONICAL_ROOT, encoding: "utf8", windowsHide: true,
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    throw new Error(String(result.stderr || result.error && result.error.message || "git failed"));
  }
  return String(result.stdout || "").trim();
}

function createTransactionFixture(suffix, behavior) {
  const runId = "pre-control-discard-fixture-" + process.pid + "-"
    + Date.now() + "-" + suffix;
  const owned = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runDir = path.join(owned, "runs", runId);
  const materializedBase = path.join(owned, Materialize.MATERIALIZED_DIRECTORY, runId);
  const destination = path.join(materializedBase, "resources");
  fs.mkdirSync(runDir, { recursive: true });
  fs.mkdirSync(materializedBase, { recursive: true });
  runGit(["-C", Common.CANONICAL_ROOT, "worktree", "add", "--no-checkout",
    "--detach", destination, "HEAD"]);
  fs.writeFileSync(path.join(runDir, "fixture-bound.json"), "{}\n", {
    encoding: "utf8", flag: "wx",
  });
  const hashes = { preparation: "1".repeat(64), materialization: "2".repeat(64),
    closure: "3".repeat(64), scope: "4".repeat(64), build: "5".repeat(64),
    failureReceipt: "6".repeat(64),
    candidateRoot: path.join(destination, "tmp", "runtime-candidates", "v2",
      Build.CANDIDATE_LEAF) };
  const live = RunOperationLease.acquire({ runDir, runId, mode: "live_execution",
    preparationSha256: hashes.preparation, buildSha256: hashes.build });
  const terminal = RunOperationLease.release(live);
  const failureReceipt = { receiptSha256: hashes.failureReceipt,
    operationLease: clone(live.lease), operationTerminal: clone(terminal) };
  const context = {
    preparation: { runId, runDir, resourcesRoot: destination,
      preparationSha256: hashes.preparation },
    materialization: { materializationSha256: hashes.materialization,
      gitWorktree: { head: runGit(["-C", destination, "rev-parse", "HEAD"]),
        commonDir: path.join(Common.CANONICAL_ROOT, ".git") } },
    closure: { closureSha256: hashes.closure,
      scope: { scopeSha256: hashes.scope } },
    build: { buildSha256: hashes.build, candidateRoot: hashes.candidateRoot },
    failureReceipt: { value: failureReceipt },
  };
  let staticLoads = 0;
  const captureSafety = (current, state) => {
    Discard.exactResumeMarkerInventory(runDir, state);
    const excluded = new Set([RunOperationLease.LEASE_NAME,
      state && state.markerName].filter(Boolean));
    const operation = /^(?:run-operation-terminal-|run-operation-stale-resolved-)[a-f0-9]{16}\.json$/;
    const resume = new RegExp("^" + Discard.RESUME_PREFIX
      + "[0-9]{4}-[a-f0-9]{16}\\.json$");
    const files = Materialize.collectDestinationFiles(runDir).filter((entry) =>
      !excluded.has(entry.relativePath) && !operation.test(entry.relativePath)
        && !resume.test(entry.relativePath));
    assert.deepStrictEqual(files.map((entry) => entry.relativePath), ["fixture-bound.json"]);
    const value = { runArtifacts: { files,
      filesSha256: Materialize.filesDigest(files) },
    postBuildScope: { scopeSha256: hashes.scope,
      ignoredOutputInventorySha256: "7".repeat(64),
      ignoredFileCount: 0, ignoredTotalBytes: 0 },
    slots: ["seed", "target", "recovery"].map((slot) => ({ slot,
      lockPresent: false, recoveryPresent: false })),
    targetSetSha256: "8".repeat(64), targetArtifactsSha256: "9".repeat(64),
    materializationSha256: hashes.materialization, buildSha256: hashes.build,
    candidateRoot: hashes.candidateRoot, gitWorktreeIdentitySha256: "a".repeat(64),
    failureReceiptSha256: hashes.failureReceipt };
    value.safetyProbeSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
    return value;
  };
  const runtime = (remove, onStaticLoad) => ({
    loadStaticContext: () => {
      staticLoads += 1;
      if (onStaticLoad) onStaticLoad(staticLoads, context);
      if (behavior && behavior.preflightErrorCode) {
        Common.fail(behavior.preflightErrorCode,
          "pre_control_discard", "fixture static preflight rejected before lease acquisition");
      }
      return context;
    },
    captureSafetyProbe: captureSafety,
    loadContext: (_paths, state, current) => {
      const safety = captureSafety(current, state);
      const probe = Object.assign({}, safety, {
        operation: Discard.operationBinding(current),
      });
      probe.probeSha256 = Evidence.sha256Text(Evidence.canonicalJson(
        Object.assign({}, Discard.safetyProbe(probe), { operation: probe.operation })));
      return Object.assign({}, current, { probe });
    },
    removeWorktree: remove || Discard.removeWorktree,
    finalize: Discard.finalize,
  });
  return { runId, runDir, destination, materializedBase, context, runtime,
    cleanup() {
      if (Materialize.worktreeListed(Common.CANONICAL_ROOT, destination)) {
        runGit(["-C", Common.CANONICAL_ROOT, "worktree", "remove", "--force", destination]);
      }
      safeCleanup(runDir, path.join(owned, "runs"));
      safeCleanup(materializedBase,
        path.join(owned, Materialize.MATERIALIZED_DIRECTORY));
    } };
}

function main() {
  const runId = "pre-control-discard-test-" + process.pid + "-" + Date.now();
  const owned = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runBase = path.join(owned, "runs");
  const runDir = path.join(runBase, runId);
  const materializedBase = path.join(owned, Materialize.MATERIALIZED_DIRECTORY, runId);
  const destination = path.join(materializedBase, "resources");
  const hashes = { preparation: "1".repeat(64), materialization: "2".repeat(64),
    closure: "3".repeat(64), scope: "4".repeat(64), build: "5".repeat(64),
    failureReceipt: "6".repeat(64),
    candidateRoot: path.join(destination, "tmp", "runtime-candidates", "v2",
      Build.CANDIDATE_LEAF) };
  fs.mkdirSync(runDir, { recursive: true });
  fs.mkdirSync(destination, { recursive: true });
  const boundPath = path.join(runDir, "fixture-bound.json");
  fs.writeFileSync(boundPath, "{}\n", { encoding: "utf8", flag: "wx" });
  const bound = Evidence.readExactRegularFile(boundPath, {
    phase: "self_test", maximumBytes: 1024,
  });
  const runArtifacts = [{ relativePath: "fixture-bound.json",
    bytes: bound.length, sha256: bound.sha256 }];
  let liveHandle = null;
  let initialHandle = null;
  let resumeHandle = null;
  try {
    const foreignResume = path.join(runDir,
      Discard.RESUME_PREFIX + "0001-" + "0".repeat(16) + ".json");
    fs.writeFileSync(foreignResume, "{}\n", { encoding: "utf8", flag: "wx" });
    negative("fresh discard rejects a pre-existing shaped resume marker",
      "material_shop_pre_control_discard_resume_invalid", () => {
        Discard.exactResumeMarkerInventory(runDir, { intent: null });
      });
    fs.unlinkSync(foreignResume);

    liveHandle = RunOperationLease.acquire({ runDir, runId, mode: "live_execution",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    RunOperationLease.release(liveHandle);
    liveHandle = null;
    initialHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    const initialBinding = binding(initialHandle, runDir);
    const initialContext = makeContext(runId, runDir, destination,
      initialBinding, runArtifacts, hashes);
    const intent = Discard.createIntent(initialContext, "2026-08-12T00:00:00.000Z");

    test("pre-control removal intent binds static safety and active cleanup mutex", () => {
      assert.strictEqual(Discard.validateIntent(intent), intent);
      assert.strictEqual(intent.safetyProbeSha256,
        Evidence.sha256Text(Evidence.canonicalJson(intent.safetyProbe)));
      assert.strictEqual(intent.operation.lease.leaseSha256,
        initialHandle.lease.leaseSha256);
    });
    negative("intent cannot detach probe digest from its operation lease",
      "material_shop_pre_control_discard_intent_invalid", () => {
        const drift = clone(intent);
        drift.probeSha256 = "7".repeat(64);
        reseal(drift, "intentSha256");
        Discard.validateIntent(drift);
      });

    RunOperationLease.release(initialHandle);
    initialHandle = null;
    test("closed initial attempt is eligible for full-context resume", () => {
      const chain = Discard.assertResumeHistory(intent, { requireClosed: true });
      assert.strictEqual(chain.markers.length, 0);
      assert.strictEqual(chain.expected.length, 2);
    });

    const initialArchive = path.join(runDir,
      RunOperationLease.terminalName(intent.operation.lease));
    const initialBytes = fs.readFileSync(initialArchive);
    negative("same-operation archive byte drift blocks resume before removal",
      "material_shop_pre_control_discard_operation_invalid", () => {
        fs.appendFileSync(initialArchive, " \n", "utf8");
        try { Discard.assertResumeHistory(intent, { requireClosed: true }); }
        finally { fs.writeFileSync(initialArchive, initialBytes); }
      });

    resumeHandle = RunOperationLease.acquire({ runDir, runId, mode: "built_only_discard",
      preparationSha256: hashes.preparation, buildSha256: hashes.build });
    const resumeBinding = binding(resumeHandle, runDir);
    const marker = Discard.createResumeMarker(intent, resumeBinding, 1,
      "2026-08-12T00:01:00.000Z");
    const markerName = Discard.resumeName(marker.sequence, marker.operation.lease);
    const markerPath = path.join(runDir, markerName);
    fs.writeFileSync(markerPath, JSON.stringify(marker, null, 2) + "\n", {
      encoding: "utf8", flag: "wx",
    });
    RunOperationLease.release(resumeHandle);
    resumeHandle = null;

    test("resume marker adopts the exact prior chain and closes after terminal release", () => {
      assert.deepStrictEqual(Discard.exactResumeMarkerInventory(runDir,
        { intent }), [markerName]);
      const chain = Discard.assertResumeHistory(intent, { requireClosed: true });
      assert.strictEqual(chain.markers.length, 1);
      assert.strictEqual(chain.binding.lease.leaseSha256,
        marker.operation.lease.leaseSha256);
      assert.strictEqual(chain.extra.length, 0);
    });

    negative("self-consistent resume marker rewrite fails its exact byte fence",
      "material_shop_pre_control_discard_resume_invalid", () => {
        const original = fs.readFileSync(markerPath);
        const artifact = Discard.bindResumeMarkerArtifact(intent, marker);
        const drift = clone(marker);
        drift.createdAt = "2026-08-12T00:01:01.000Z";
        reseal(drift, "markerSha256");
        fs.writeFileSync(markerPath, JSON.stringify(drift, null, 2) + "\n");
        try { Discard.assertResumeMarkerArtifact(intent, marker, artifact); }
        finally { fs.writeFileSync(markerPath, original); }
      });

    negative("resume marker cannot claim a history entry absent from disk",
      "material_shop_pre_control_discard_resume_invalid", () => {
        const original = fs.readFileSync(markerPath);
        const drift = clone(marker);
        const invented = clone(drift.operation.preexistingHistory.find((entry) =>
          entry.lease.mode === "built_only_discard"));
        invented.lease.createdAt = "2026-08-12T00:00:30.000Z";
        invented.lease.ownerNonceSha256 = "d".repeat(64);
        reseal(invented.lease, "leaseSha256");
        invented.name = RunOperationLease.terminalName(invented.lease);
        invented.sha256 = "e".repeat(64);
        drift.operation.preexistingHistory.push(invented);
        drift.operation.preexistingHistory.sort((left, right) =>
          left.name.localeCompare(right.name));
        reseal(drift.operation, "operationSha256");
        reseal(drift, "markerSha256");
        fs.writeFileSync(markerPath, JSON.stringify(drift, null, 2) + "\n");
        try { Discard.assertResumeHistory(intent, { requireClosed: true }); }
        finally { fs.writeFileSync(markerPath, original); }
      });

    const closure = Discard.operationClosure(intent);
    const receipt = Discard.receiptFromIntent(intent, closure,
      "2026-08-12T00:02:00.000Z");
    test("receipt binds resumed outcome and starts at the exact intent time", () => {
      assert.strictEqual(Discard.validateReceipt(receipt, intent, closure), receipt);
      assert.strictEqual(receipt.startedAt, intent.createdAt);
      assert.strictEqual(receipt.operationOutcomeName,
        RunOperationLease.terminalName(marker.operation.lease));
      assert.strictEqual(receipt.resumeMarkersSha256, closure.resumeMarkersSha256);
    });
    negative("receipt cannot rewrite the intent start time",
      "material_shop_pre_control_discard_receipt_invalid", () => {
        const drift = clone(receipt);
        drift.startedAt = "2026-08-12T00:00:01.000Z";
        reseal(drift, "receiptSha256");
        Discard.validateReceipt(drift, intent, closure);
      });
    negative("receipt cannot detach from the exact resume marker descriptor chain",
      "material_shop_pre_control_discard_receipt_invalid", () => {
        const drift = clone(receipt);
        drift.resumeMarkersSha256 = "0".repeat(64);
        reseal(drift, "receiptSha256");
        Discard.validateReceipt(drift, intent, closure);
      });

    test("static context binding replays worktree identity and receipt authority", () => {
      assert.strictEqual(Discard.assertStaticContextMatchesIntent(initialContext,
        { active: true, intent }, initialContext.probe), intent);
    });
    negative("resume cannot swap the materialized worktree HEAD",
      "material_shop_pre_control_discard_resume_binding_invalid", () => {
        const drift = clone(initialContext);
        drift.materialization.gitWorktree.head = "f".repeat(40);
        Discard.assertStaticContextMatchesIntent(drift,
          { active: true, intent }, initialContext.probe);
      });
    negative("safety probe byte drift blocks destructive continuation",
      "material_shop_pre_control_discard_probe_drift", () => {
        const drift = clone(initialContext.probe);
        drift.targetArtifactsSha256 = "0".repeat(64);
        drift.safetyProbeSha256 = Evidence.sha256Text(
          Evidence.canonicalJson(Discard.safetyProbe(drift)));
        Discard.assertSameSafetyProbe(initialContext.probe, drift);
      });

    negative("CLI rejects mixed discard and finalizer modes",
      "material_shop_pre_control_discard_arguments_invalid", () => {
        Discard.parseArgs(["--discard-pre-control-failure",
          "--finalize-pre-control-failure-discard", "--run-dir", runDir]);
      });
    negative("destructive CLI requires explicit acknowledgement",
      "material_shop_pre_control_discard_arguments_invalid", () => {
        Discard.parseArgs(["--discard-pre-control-failure", "--preparation",
          path.join(runDir, "preparation.json"), "--build",
          path.join(runDir, "candidate-build.json")]);
      });
    test("bare finalizer CLI remains non-destructive and exact", () => {
      const args = Discard.parseArgs(["--finalize-pre-control-failure-discard",
        "--run-dir", runDir]);
      assert.deepStrictEqual(args, { mode: "finalize", runDir,
        preparation: null, build: null, acknowledge: false });
    });

    test("fresh transaction removes one exact temporary Git worktree and finalizes", () => {
      const fixture = createTransactionFixture("fresh");
      try {
        const receiptValue = Discard.discardFixture({ acknowledge: true,
          preparation: path.join(fixture.runDir, "preparation.json"),
          build: path.join(fixture.runDir, "candidate-build.json") }, fixture.runtime());
        assert.strictEqual(receiptValue.worktreeRemoved, true);
        assert.strictEqual(receiptValue.candidateExecuted, true);
        assert.strictEqual(receiptValue.controlIssued, false);
        assert.strictEqual(fs.existsSync(fixture.destination), false);
        assert.strictEqual(Materialize.worktreeListed(Common.CANONICAL_ROOT,
          fixture.destination), false);
        assert(fs.existsSync(path.join(fixture.runDir, Discard.RECEIPT_NAME)));
      } finally { fixture.cleanup(); }
    });

    test("remove failure leaves intent and terminal for full-context resumed removal", () => {
      const fixture = createTransactionFixture("resume");
      try {
        let failure = null;
        try {
          Discard.discardFixture({ acknowledge: true,
            preparation: path.join(fixture.runDir, "preparation.json"),
            build: path.join(fixture.runDir, "candidate-build.json") },
          fixture.runtime(() => Common.fail(
            "material_shop_pre_control_discard_remove_failed",
            "pre_control_discard", "simulated exact remove failure")));
        } catch (error) { failure = error; }
        assert(failure);
        assert.strictEqual(failure.code, "material_shop_pre_control_discard_remove_failed");
        assert(fs.existsSync(path.join(fixture.runDir, Discard.INTENT_NAME)));
        assert(fs.existsSync(fixture.destination));
        let finalizeError = null;
        try { Discard.finalize(fixture.runDir); }
        catch (error) { finalizeError = error; }
        assert(finalizeError);
        assert.strictEqual(finalizeError.code,
          "material_shop_pre_control_discard_remove_incomplete");
        const receiptValue = Discard.discardFixture({ acknowledge: true,
          preparation: path.join(fixture.runDir, "preparation.json"),
          build: path.join(fixture.runDir, "candidate-build.json") }, fixture.runtime());
        assert.strictEqual(receiptValue.worktreeRemoved, true);
        assert.strictEqual(fs.existsSync(fixture.destination), false);
        assert.strictEqual(Discard.loadResumeMarkers(
          Discard.loadState(fixture.runDir).intent).length, 1);
      } finally { fixture.cleanup(); }
    });

    test("missing or invalid cleanup receipt cannot create a lease or marker", () => {
      for (const code of ["material_shop_pre_control_discard_receipt_missing",
        "material_shop_pre_control_discard_receipt_invalid"]) {
        const fixture = createTransactionFixture(code.endsWith("missing")
          ? "missing-receipt" : "bad-receipt", { preflightErrorCode: code });
        try {
          const beforeHistory = RunOperationLease.historyMarkers(fixture.runDir)
            .map(projection);
          const beforeFiles = Materialize.collectDestinationFiles(fixture.runDir);
          let error = null;
          try {
            Discard.discardFixture({ acknowledge: true,
              preparation: path.join(fixture.runDir, "preparation.json"),
              build: path.join(fixture.runDir, "candidate-build.json") }, fixture.runtime());
          } catch (failure) { error = failure; }
          assert(error);
          assert.strictEqual(error.code, code);
          assert.deepStrictEqual(RunOperationLease.historyMarkers(fixture.runDir)
            .map(projection), beforeHistory);
          assert.deepStrictEqual(Materialize.collectDestinationFiles(fixture.runDir),
            beforeFiles);
          assert.strictEqual(RunOperationLease.readLease(fixture.runDir).active, false);
          assert.strictEqual(Discard.loadState(fixture.runDir).intent, null);
        } finally { fixture.cleanup(); }
      }
    });

    test("self-consistent resume marker mutation blocks remove and preserves worktree", () => {
      const fixture = createTransactionFixture("marker-drift");
      try {
        try {
          Discard.discardFixture({ acknowledge: true,
            preparation: path.join(fixture.runDir, "preparation.json"),
            build: path.join(fixture.runDir, "candidate-build.json") },
          fixture.runtime(() => Common.fail(
            "material_shop_pre_control_discard_remove_failed",
            "pre_control_discard", "simulated exact remove failure")));
        } catch (error) {
          assert.strictEqual(error.code, "material_shop_pre_control_discard_remove_failed");
        }
        let mutated = false;
        let removeCalls = 0;
        let error = null;
        try {
          Discard.discardFixture({ acknowledge: true,
            preparation: path.join(fixture.runDir, "preparation.json"),
            build: path.join(fixture.runDir, "candidate-build.json") },
          fixture.runtime(() => { removeCalls += 1; }, () => {
            if (mutated) return;
            const names = fs.readdirSync(fixture.runDir).filter((name) =>
              name.startsWith(Discard.RESUME_PREFIX));
            if (names.length !== 1) return;
            const markerPathValue = path.join(fixture.runDir, names[0]);
            const value = JSON.parse(fs.readFileSync(markerPathValue, "utf8"));
            value.createdAt = new Date(Date.parse(value.createdAt) + 1).toISOString();
            reseal(value, "markerSha256");
            fs.writeFileSync(markerPathValue, JSON.stringify(value, null, 2) + "\n");
            mutated = true;
          }));
        } catch (failure) { error = failure; }
        assert(error);
        assert.strictEqual(error.code, "material_shop_pre_control_discard_resume_invalid");
        assert.strictEqual(mutated, true);
        assert.strictEqual(removeCalls, 0);
        assert.strictEqual(fs.existsSync(fixture.destination), true);
        assert.strictEqual(Materialize.worktreeListed(Common.CANONICAL_ROOT,
          fixture.destination), true);
      } finally { fixture.cleanup(); }
    });

    test("implementation preflights receipt and safety before lease acquisition", () => {
      const source = fs.readFileSync(path.join(__dirname,
        "discard-pre-control-failed-run.js"), "utf8");
      const start = source.indexOf("function executeDiscard(options");
      const staticLoad = source.indexOf(
        "const staticContext = runtime.loadStaticContext(paths)", start);
      const safety = source.indexOf(
        "const preflightSafety = runtime.captureSafetyProbe", staticLoad);
      const acquire = source.indexOf("RunOperationLease.acquire", safety);
      const intentWrite = source.indexOf("Materialize.writeJsonAtomicNew", acquire);
      const secondLoad = source.indexOf(
        "const freshStatic = runtime.loadStaticContext(paths)", intentWrite);
      const remove = source.indexOf(
        "runtime.removeWorktree(context.preparation.resourcesRoot)", secondLoad);
      assert(staticLoad > start && safety > staticLoad && acquire > safety
        && intentWrite > acquire && secondLoad > intentWrite && remove > secondLoad);
      assert(!source.includes('"worktree", "prune"'));
      assert(!source.includes("fs.rmSync"));
    });

    process.stdout.write(JSON.stringify({ ok: true, passed, total,
      status: "OFFLINE_VERIFIED", fixtureWorktreeRemovalExecuted: true,
      productionRunCleanupExecuted: false }) + "\n");
  } finally {
    for (const handle of [resumeHandle, initialHandle, liveHandle]) {
      if (handle && handle.active) RunOperationLease.release(handle);
    }
    safeCleanup(runDir, runBase);
    safeCleanup(materializedBase,
      path.join(owned, Materialize.MATERIALIZED_DIRECTORY));
  }
}

try { main(); }
catch (error) {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  process.exitCode = 1;
}
