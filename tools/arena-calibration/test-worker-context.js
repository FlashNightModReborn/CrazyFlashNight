#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const { EventEmitter } = require("events");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createPilotManifest, normalizeResultRow, sha256OfValue } = require("./lib/arena-calibration-core");
const { sha256Bytes } = require("./lib/immutable-evidence");
const { CONTROL_HEADER, createWorkerClient, normalizeFaultInjection, normalizePerformance, validateOwner, verifyGitRoot, verifyProcessOwner } = require("./lib/arena-worker-client");
const { assertEndpointOwnership } = require("./lib/arena-worker-endpoint");
const { captureGlobalProtectionSnapshot } = require("./lib/unattended-save-safety");
const { compareProtectedSaveSnapshots } = require("./run-unattended");
const { captureResourceClosure, isSameProcessAlive, readBoundLaunch, runWorkerShard, validateRawRows } = require("./run-worker-shard");

function write(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, typeof value === "string" ? value : JSON.stringify(value));
}

function fixture(root, workerId) {
  const launch = { schema: "arena-worker.launch.v1", workerId, sessionEpoch: `epoch-${workerId}`,
    projectRoot: root, stateRoot: path.join(root, "tmp", "arena-worker", `epoch-${workerId}`),
    saveRoot: path.join(root, "saves"), outputRoot: path.join(root, "tmp", "arena-calibration"),
    swfOrigin: path.join(root, "CRAZYFLASHER7MercenaryEmpire.swf"), slot: `cf7_agent_${workerId}`,
    performance: normalizePerformance() };
  fs.mkdirSync(root, { recursive: true });
  const git = childProcess.spawnSync("git", ["init", "--quiet", root], { windowsHide: true, encoding: "utf8" });
  assert.strictEqual(git.status, 0, git.stderr);
  write(launch.swfOrigin, "fixture SWF bytes");
  write(path.join(root, "scripts", "asLoader.swf"), "fixture asLoader bytes");
  write(path.join(root, "data", "units.xml"), "<units />");
  write(path.join(launch.saveRoot, `${launch.slot}.json`), "{}");
  const launchPath = path.join(launch.stateRoot, "launch.json");
  write(launchPath, launch);
  const runtime = { runtimeMode: "isolated_candidate", processPath: path.join(root, "candidate", "runtime", "Core.exe"),
    coreSha256: "A".repeat(64), buildIdentity: "B".repeat(64), payloadClosure: "C".repeat(64) };
  const owner = { ...launch, schema: "arena-worker.owner.v1", executionMode: "arena_worker", hostPid: 901,
    processStartUtcTicks: "638400000000000001", startTimeUtc: new Date().toISOString(), processPath: runtime.processPath,
    httpPort: 30123, socketPort: 30124, runtimeIdentity: runtime,
    appData: path.join(root, "appdata"), sharedObjectsRoot: path.join(root, "appdata", "Macromedia", "Flash Player", "#SharedObjects") };
  const process = { pid: owner.hostPid, processStartUtcTicks: owner.processStartUtcTicks, processPath: owner.processPath };
  return { launch, launchPath, runtime, owner, process };
}

function rawRows(manifest, tuple) {
  return manifest.cases.flatMap((testCase) => Array.from({ length: testCase.repeat }, (_unused, index) => normalizeResultRow({
    ...tuple, schema: "arena-calibration.result.v1", batchId: manifest.batchId, manifestHash: manifest.manifestHash,
    caseId: testCase.caseId, caseHash: testCase.caseHash, runId: `${tuple.attemptId}-r${index + 1}`,
    repeatIndex: index + 1, status: "finished", winner: "blue", frames: 60, durationMs: 2000,
    skillStateAudit: { blue: [{ unit: "fixture", sourceId: "fixture", name: "unit", observed: false, state: null }], red: [] },
  })));
}

function solPath(sharedRoot, swfOrigin, slot) {
  return path.join(sharedRoot, "hash-a", "localhost", swfOrigin.slice(path.parse(swfOrigin).root.length), `${slot}.sol`);
}

async function noOwnerSignalFixture(root, appData) {
  const f = fixture(root, "no-owner-signal");
  const manifestPath = path.join(root, "manifest.json");
  write(manifestPath, createPilotManifest({ batchId: "no-owner-signal", repeat: 1 }));
  const child = new EventEmitter();
  child.pid = 903; child.exitCode = null; child.signalCode = null;
  child.kill = () => { child.signalCode = "SIGTERM"; child.emit("exit", null, "SIGTERM"); return true; };
  let controls = 0;
  const result = await runWorkerShard({ launchPath: f.launchPath, candidateRoot: path.join(root, "candidate"), manifestPath,
    pollMs: 1, shutdownTimeoutMs: 10, experiment: { groupId: "fixture-group", condition: "no-owner", concurrency: 1, sessionState: "cold", visibility: "unknown" } },
  { fixture: true, expectedRuntime: f.runtime, spawn: () => child, saveOptions: { appData }, client: {
    readOwner: () => { throw new Error("owner publication interrupted"); },
    call: async () => { controls++; throw new Error("unexpected control request"); },
  } });
  assert.strictEqual(controls, 0, "no-owner failure must not send start");
  assert.strictEqual(result.receipt.status, "failed");
  assert.strictEqual(result.receipt.shutdown.hostExited, true);
  assert.strictEqual(result.receipt.shutdown.flashExited, true);
  assert.strictEqual(result.receipt.shutdown.earlyHostExit.signalCode, "SIGTERM");
  assert.strictEqual(result.receipt.errors.some((entry) => entry.phase === "startup_cleanup"), false);
}

async function runFixture(root, appData, corrupt, forceShutdown = false, unknownStart = false, fault = {}) {
  const name = fault.name || (unknownStart ? "unknown-start" : forceShutdown ? "forced" : corrupt ? "bad" : "good");
  const f = fixture(root, name);
  f.owner.appData = appData;
  f.owner.sharedObjectsRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  const manifest = createPilotManifest({ batchId: `worker-${name}`, repeat: 2 });
  const manifestPath = path.join(root, "fixture-manifest.json");
  write(manifestPath, manifest);
  const tuple = { workerId: f.launch.workerId, sessionEpoch: f.launch.sessionEpoch,
    assignmentId: "assignment-fixture", attemptId: "attempt-fixture" };
  const flash = { pid: 902, processStartUtcTicks: "638400000000000002", processPath: path.join(root, "Flash.exe") };
  const child = new EventEmitter();
  child.pid = 901; child.exitCode = null;
  let hostAlive = true;
  let flashAlive = true;
  let submitted = false;
  const resultPath = path.join(f.launch.outputRoot, "batches", manifest.batchId, "attempts", tuple.attemptId, "results.jsonl");
  const observedPath = fault.foreignPath ? path.join(path.dirname(path.dirname(resultPath)), "attempt-other", "results.jsonl") : resultPath;
  const relativeResultPath = path.relative(root, observedPath).replace(/\\/g, "/");
  const status = { ...tuple, batchId: manifest.batchId, manifestHash: manifest.manifestHash, state: "completed",
    transportPoisoned: false, resultPath: relativeResultPath };
  const actions = [];
  const client = {
    readOwner: () => f.owner,
    async call(action) {
      actions.push(action);
      if (action === "start" && unknownStart) throw new Error("startup delivery unknown");
      if (action === "shutdown") {
        if (forceShutdown) throw new Error("shutdown outcome unknown");
        if (fault.postResourceMissing) fs.unlinkSync(f.launch.swfOrigin);
        hostAlive = false; flashAlive = false; child.exitCode = 0; return { flashProcess: flash };
      }
      if (submitted && (fault.lostBridge || fault.foreignPath || fault.noObservedPath) && ["status", "abort", "result"].includes(action)) {
        throw new Error("fixture bridge unavailable after submission");
      }
      if (action === "startBatch") {
        submitted = true;
        const rows = rawRows(manifest, tuple);
        if (corrupt) rows[0].sessionEpoch = "foreign-session";
        write(resultPath, rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
        if (fault.foreignPath) write(observedPath, rows.map((row) => JSON.stringify(row)).join("\n") + "\n");
        if (fault.noObservedPath) throw new Error("fixture startBatch response lost");
      }
      return { ...tuple, success: true, ok: true, flashProcess: flash, arenaStatus: submitted ? status : null,
        windowObservation: { observed: false, sampledAtUtc: "2026-10-11T00:00:00.000Z", reason: "fixture_no_window" },
        performanceObservation: { observed: false, sampledAtUtc: "2026-10-11T00:00:00.000Z", status: "waiting", reason: "fixture_no_applied_state" },
        hostProcessObservation: { observed: true, sampledAtUtc: "2026-10-11T00:00:00.000Z", pid: 901, totalProcessorTimeMs: 125, workingSetBytes: 4096, privateMemoryBytes: 2048 },
        flashProcessObservation: { observed: false, sampledAtUtc: "2026-10-11T00:00:00.000Z", reason: "fixture_process_sample_unavailable" },
        resultPath: relativeResultPath,
        agentStatus: { readyForRuntimeAutomation: true, runtimeReadyBlockedBy: [], gameEnteredObserved: true,
          gameEnteredAttemptId: "entry-1", save: { slot: f.launch.slot, attemptId: "entry-1", decision: "snapshot", kind: "Snapshot" },
          saveRuntime: { loaded: true, savePath: f.launch.slot, attemptId: "entry-1", role: "fixture", level: 1 } } };
    },
  };
  const result = await runWorkerShard({ launchPath: f.launchPath, candidateRoot: path.join(root, "candidate"),
    manifestPath, assignmentId: tuple.assignmentId, attemptId: tuple.attemptId, pollMs: 1, shutdownTimeoutMs: forceShutdown ? 5 : 100,
    expectedLaunch: f.launch, expectedLaunchSha256: sha256Bytes(fs.readFileSync(f.launchPath)),
    experiment: { groupId: "fixture-group", condition: "baseline", concurrency: 1, sessionState: "cold", visibility: "unknown" } },
  { fixture: true, expectedRuntime: f.runtime, client, saveOptions: { appData },
    detectDotnetRuntime: () => ({ available: true, source: "isolated_fixture", environment: {
      DOTNET_ROOT: path.join(root, "fixture-dotnet"), DOTNET_ROOT_X64: path.join(root, "fixture-dotnet") } }),
    spawn: (executable, args, options) => {
      assert.strictEqual(executable, f.runtime.processPath, "Core must remain the directly spawned child");
      assert.deepStrictEqual(args.slice(0, 2), ["--project-root", root]);
      assert.strictEqual(options.env.DOTNET_ROOT, path.join(root, "fixture-dotnet"));
      assert.strictEqual(options.env.DOTNET_ROOT_X64, options.env.DOTNET_ROOT);
      return child;
    },
    processProbe: (pid) => pid === 901 ? hostAlive ? f.process : null : flashAlive ? flash : null,
    terminateExactProcess: (owned) => {
      const pid = owned.pid || owned.hostPid;
      if (pid === 902) flashAlive = false;
      if (pid === 901) { hostAlive = false; child.exitCode = 0; }
      return { pid, exited: true, killed: true };
    } });
  assert.strictEqual(result.receipt.evidenceKind, "isolated_fixture");
  assert.strictEqual(result.receipt.shutdown.hostExited, true);
  assert.strictEqual(result.receipt.shutdown.flashExited, true);
  assert.strictEqual(result.receipt.saveProtection.unchanged, true);
  assert.strictEqual(result.receipt.resourcesUnchanged, fault.postResourceMissing ? null : true);
  assert.strictEqual(result.receipt.status, corrupt || forceShutdown || unknownStart || fault.name ? "failed" : "completed");
  assert.strictEqual(result.receipt.flashProcessObserved, true);
  assert.strictEqual(result.receipt.runtimeUnchanged, fault.postResourceMissing ? null : true);
  if (fault.postResourceMissing) {
    assert(result.receipt.saveProtection.after, "a completed protected-save snapshot must survive later resource failure");
    assert.deepStrictEqual(result.receipt.saveProtection.differences, []);
    assert(result.receipt.errors.some((entry) => entry.phase === "protection" && entry.message.includes("ENOENT")));
  }
  for (const phase of ["before", "after"]) {
    const sample = result.receipt.evidenceSampling[phase];
    assert.strictEqual(sample.source, "worker_thread");
    assert.strictEqual(sample.operation, phase);
    assert(sample.threadId > 0);
    assert(Date.parse(sample.startedAtUtc) >= Date.parse(result.receipt.startedAt));
    assert(Date.parse(sample.completedAtUtc) <= Date.parse(result.receipt.finalizedAt));
  }
  assert(result.receipt.windowObservations.some((entry) => entry.phase === (unknownStart ? "startup_reconcile" : "ready")
    && entry.observed === false && entry.reason === "fixture_no_window"));
  assert(result.receipt.performanceObservations.every((entry) => entry.observed === false && entry.status === "waiting"));
  assert(result.receipt.hostProcessObservations.some((entry) => entry.totalProcessorTimeMs === 125));
  assert(result.receipt.flashProcessObservations.every((entry) => entry.totalProcessorTimeMs === undefined));
  if (forceShutdown) {
    assert.deepStrictEqual(result.receipt.shutdown.forced.map((entry) => entry.pid), [902, 901]);
    assert(result.receipt.errors.some((entry) => entry.phase === "shutdown_delivery"));
  }
  if (fault.foreignPath || fault.noObservedPath) {
    assert.strictEqual(result.receipt.resultSha256, null, "unobserved or foreign paths cannot become current-attempt evidence");
    assert.strictEqual(result.receipt.sourceResultPath, undefined);
    assert(fs.existsSync(resultPath), "the canonical-looking file alone must never authorize a guessed read");
  } else if (!unknownStart) assert(result.receipt.resultSha256, "raw bytes remain available even when the echo is rejected");
  if (fault.lostBridge) {
    assert.strictEqual(result.receipt.rawEvidenceSource, "observed_start_response");
    assert.strictEqual(result.receipt.sourceResultPath, resultPath);
    assert.strictEqual(result.receipt.rows, 2);
    assert.deepStrictEqual(fs.readFileSync(result.receipt.resultPath), fs.readFileSync(resultPath));
    assert(result.receipt.errors.some((entry) => entry.message.includes("bridge unavailable")));
  }
  if (fault.foreignPath) assert(result.receipt.errors.some((entry) => entry.message.includes("exact assigned attempt")));
  assert.strictEqual(actions.filter((action) => action === "start").length, 1);
  assert.strictEqual(actions.filter((action) => action === "startBatch").length, unknownStart ? 0 : 1);
  if (unknownStart) {
    assert.strictEqual(actions.filter((action) => action === "status").length, 1);
    assert.strictEqual(result.receipt.startupReconciliation.action, "status");
    assert(result.receipt.errors.some((entry) => entry.message === "startup delivery unknown"));
  }
  assert.strictEqual(actions[actions.length - 1], "shutdown");
  assert(!fs.readFileSync(result.receiptPath, "utf8").includes("fixture-control-token"));
  return result;
}

async function dotnetUnavailableFixture(root, appData) {
  const f = fixture(root, "missing-dotnet");
  const manifestPath = path.join(root, "manifest.json");
  write(manifestPath, createPilotManifest({ batchId: "missing-dotnet", repeat: 1 }));
  let spawnCalls = 0; let controlCalls = 0;
  const result = await runWorkerShard({ launchPath: f.launchPath, candidateRoot: path.join(root, "candidate"), manifestPath,
    experiment: { groupId: "fixture-group", condition: "missing-dotnet", concurrency: 1, sessionState: "cold", visibility: "unknown" } },
  { fixture: true, expectedRuntime: f.runtime, saveOptions: { appData },
    detectDotnetRuntime: () => { throw new Error("Worker .NET 10 Desktop runtime is unavailable according to tools/dotnet-runtime-detect.ps1"); },
    spawn: () => { spawnCalls++; throw new Error("must not spawn"); },
    client: { readOwner: () => { controlCalls++; }, call: async () => { controlCalls++; } } });
  assert.strictEqual(spawnCalls, 0);
  assert.strictEqual(controlCalls, 0);
  assert.strictEqual(result.receipt.status, "failed");
  assert.strictEqual(result.receipt.hostStartedAt, null);
  assert.strictEqual(result.receipt.batchStartedAt, null);
  assert.strictEqual(result.receipt.resultPath, null);
  assert(result.receipt.errors.some((entry) => entry.phase === "execution" && entry.message.includes(".NET 10 Desktop runtime is unavailable")));
  assert(fs.existsSync(result.receiptPath), "failed preflight must retain its actual attempt receipt");
}

async function main() {
  assert.strictEqual(normalizeFaultInjection(), false);
  assert.strictEqual(normalizeFaultInjection(true), true);
  for (const invalid of [1, "true", null]) assert.throws(() => normalizeFaultInjection(invalid), /must be boolean/);
  assert.deepStrictEqual(normalizePerformance(), { preset: "performance", mode: "fixed", maxRenderHeight: 180 });
  assert.deepStrictEqual(normalizePerformance({ preset: "performance", mode: "fixed", maxRenderHeight: 180 }),
    { preset: "performance", mode: "fixed", maxRenderHeight: 180 });
  for (const preset of ["balanced", "quality", "performance"]) {
    for (const mode of ["auto", "fixed"]) {
      if (preset === "performance" && mode === "fixed") continue;
      assert.throws(() => normalizePerformance({ preset, mode, maxRenderHeight: 180 }), /performance policy value/);
    }
  }
  for (const explicit of [{ preset: "balanced", mode: "auto", maxRenderHeight: 0 },
    { preset: "performance", mode: "fixed", maxRenderHeight: 540 },
    { preset: "quality", mode: "fixed", maxRenderHeight: 1080 }]) {
    assert.deepStrictEqual(normalizePerformance(explicit), explicit);
  }
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-worker-context-"));
  try {
    const f = fixture(path.join(temp, "w01", "resources"), "w01");
    const f2 = fixture(path.join(temp, "w02", "resources"), "w02");
    const appData = path.join(temp, "appdata");
    assert.strictEqual(captureResourceClosure(f.launch.projectRoot).closureHash, captureResourceClosure(f2.launch.projectRoot).closureHash);
    const ownerPath = path.join(f.launch.stateRoot, "owner.json");
    write(ownerPath, f.owner);
    write(path.join(f.launch.stateRoot, "control-credential.json"), { schema: "arena-worker.control-credential.v1",
      workerId: f.launch.workerId, sessionEpoch: f.launch.sessionEpoch, header: CONTROL_HEADER, token: "fixture-control-token-".repeat(3) });
    let responseChanges = {};
    let ownership = { process: f.process, listeners: [{ localPort: f.owner.httpPort, owningProcess: f.owner.hostPid }] };
    let transports = 0;
    const client = createWorkerClient(f.launch, f.runtime, { ownershipProbe: () => ownership,
      transport: async (_owner, _token, message) => { transports++; return { ...message, success: true, ok: true, ...responseChanges }; } });
    await client.call("status");
    const initialTransports = transports;
    ownership.listeners[0].owningProcess = 902;
    await assert.rejects(() => client.call("status"), /another process/);
    ownership.listeners = [];
    await assert.rejects(() => client.call("status"), /no exact listening owner/);
    assert.strictEqual(transports, initialTransports, "changed actual listener must receive zero token-bearing requests");
    const queue = (pid, url = `HTTP://LOCALHOST:${f.owner.httpPort}/`) => `Request queue name: Request queue is unnamed.\n    State: Active\n    Number of active processes attached: 1\n    Processes:\n        ID: ${pid}, image: fixture.exe\n    URL groups:\n        Registered URLs:\n            ${url}\n`;
    const header = "Snapshot of HTTP service state (Request Queue View):\n";
    ownership = { process: f.process, listeners: [{ localPort: f.owner.httpPort, owningProcess: 4 }],
      httpServiceState: header + queue(901) };
    assert.strictEqual(assertEndpointOwnership(f.owner, ownership), "http_sys_request_queue");
    await client.call("status");
    const httpSysTransports = transports;
    for (const state of [header, header + queue(902), header + queue(901) + queue(902, `HTTP://*:${f.owner.httpPort}/`), "unrecognized locale output"]) {
      ownership.httpServiceState = state;
      await assert.rejects(() => client.call("status"), /HTTP.sys/);
      assert.strictEqual(transports, httpSysTransports, "unowned HTTP.sys request queues must receive zero credentials");
    }
    ownership = { process: f.process, listeners: [{ localPort: f.owner.httpPort, owningProcess: f.owner.hostPid }] };
    responseChanges = { sessionEpoch: "foreign" };
    await assert.rejects(() => client.call("status"), /identity mismatch/);
    responseChanges = { attemptId: "stale" };
    await assert.rejects(() => client.call("result", { assignmentId: "assignment-1", attemptId: "attempt-1" }), /identity mismatch/);
    responseChanges = { success: undefined };
    await assert.rejects(() => client.call("status"), /rejected/);
    responseChanges = {};
    const faultTuple = { workerId: f.launch.workerId, sessionEpoch: f.launch.sessionEpoch,
      assignmentId: "assignment-1", attemptId: "attempt-1", batchId: "batch-1", manifestHash: `sha256:${"a".repeat(64)}`,
      caseId: "case-1", caseHash: `sha256:${"b".repeat(64)}`, runId: "case-1-r001", repeatIndex: 1, faultId: "fault-1" };
    await assert.rejects(() => client.call("faultStopFlash", faultTuple), /not enabled/);
    assert.throws(() => validateOwner({ ...f.owner, allowFaultInjection: true }, f.launch, f.runtime), /fault-injection policy mismatch/);
    const faultLaunch = { ...f.launch, allowFaultInjection: true };
    write(ownerPath, { ...f.owner, allowFaultInjection: true });
    let faultRequests = 0;
    const faultClient = createWorkerClient(faultLaunch, f.runtime, { ownershipProbe: () => ownership,
      transport: async (_owner, _token, message) => {
        faultRequests++;
        assert.deepStrictEqual(message, { ...faultTuple, action: "faultStopFlash" });
        return { ...message, success: true, ok: true };
      } });
    await faultClient.call("faultStopFlash", faultTuple);
    await assert.rejects(() => faultClient.call("faultStopFlash", { ...faultTuple, pid: 123 }), /accepts only/);
    await assert.rejects(() => faultClient.call("faultStopFlash", { ...faultTuple, processPath: "foreign.exe" }), /accepts only/);
    await assert.rejects(() => faultClient.call("faultStopFlash", { ...faultTuple, workerId: "foreign-worker" }), /workerId/);
    await assert.rejects(() => faultClient.call("faultStopFlash", { ...faultTuple, caseHash: "missing" }), /caseHash/);
    await assert.rejects(() => faultClient.call("faultStopFlash", { ...faultTuple, repeatIndex: 0 }), /repeatIndex/);
    assert.strictEqual(faultRequests, 1, "malformed or foreign fault requests must never reach transport");
    write(ownerPath, f.owner);
    write(ownerPath, { ...f.owner, httpPort: 30125 });
    await assert.rejects(() => client.call("status"), /owner changed/);
    assert.throws(() => validateOwner({ ...f.owner, processStartUtcTicks: 638400000000000001 }, f.launch, f.runtime), /process or endpoint/);
    assert.throws(() => validateOwner({ ...f.owner, slot: "cf7_agent_other" }, f.launch, f.runtime), /slot mismatch/);
    assert.throws(() => validateOwner({ ...f.owner, performance: { preset: "performance", mode: "fixed", maxRenderHeight: 540 } }, f.launch, f.runtime), /performance policy mismatch/);
    assert.throws(() => normalizePerformance({ preset: "performance" }), /complete preset\/mode\/maxRenderHeight/);
    assert.throws(() => validateOwner({ ...f.owner, runtimeIdentity: { ...f.runtime, runtimeMode: "formal_runtime" } }, f.launch, f.runtime), /runtime identity/);
    assert.throws(() => verifyProcessOwner(f.owner, () => ({ ...f.process, processStartUtcTicks: "638400000000000009" })), /PID reuse/);
    assert.throws(() => isSameProcessAlive(f.owner, () => { throw new Error("probe unavailable"); }), /probe unavailable/,
      "probe failure must never prove that the owned process exited");
    for (const incomplete of [{ pid: 901 }, { ...f.process, processPath: null }, { ...f.process, processStartUtcTicks: null }]) {
      assert.throws(() => isSameProcessAlive(f.owner, () => incomplete), /incomplete process identity observation/);
    }
    const bound = readBoundLaunch(f.launchPath);
    assert.strictEqual(readBoundLaunch(f.launchPath, f.launch, bound.sha256).sha256, bound.sha256);
    assert.throws(() => readBoundLaunch(f.launchPath, { ...f.launch, slot: "cf7_agent_wrong" }, bound.sha256), /frozen experiment assignment/);
    write(f.launchPath, { ...f.launch, slot: "cf7_agent_changed_after_freeze" });
    assert.throws(() => readBoundLaunch(f.launchPath, f.launch, bound.sha256), /frozen experiment assignment/);
    write(f.launchPath, f.launch);
    const fakeGit = path.join(temp, "fake-git-root");
    write(path.join(fakeGit, ".git"), "not a repository");
    assert.throws(() => verifyGitRoot(fakeGit), /valid Git worktree/);

    const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
    const allowed = [f, f2].map((entry) => ({ swfOrigin: entry.launch.swfOrigin, slot: entry.launch.slot }));
    const protectedSol = solPath(sharedRoot, f.launch.swfOrigin, "player_without_json");
    write(protectedSol, "protected original");
    const globalOptions = { saveRoots: [f.launch.saveRoot, f2.launch.saveRoot], sharedObjectsRoot: sharedRoot, allowedTargets: allowed };
    const before = captureGlobalProtectionSnapshot(globalOptions);
    for (const entry of allowed) write(solPath(sharedRoot, entry.swfOrigin, entry.slot), "owned target creation");
    assert.strictEqual(captureGlobalProtectionSnapshot(globalOptions).snapshotHash, before.snapshotHash);
    write(protectedSol, "changed outside allowlist");
    const after = captureGlobalProtectionSnapshot(globalOptions);
    assert.strictEqual(compareProtectedSaveSnapshots(before, after).length, 1);
    assert.strictEqual(after.snapshotHash, sha256OfValue(after.files.map(({ key, sha256, size }) => ({ key, sha256, size }))));
    const manifest = createPilotManifest({ batchId: "raw-schema", repeat: 2 });
    const tuple = { workerId: "w01", sessionEpoch: "epoch-1", assignmentId: "assignment-1", attemptId: "attempt-1" };
    const rows = rawRows(manifest, tuple);
    const bytes = Buffer.from(rows.map(JSON.stringify).join("\n") + "\n");
    assert.strictEqual(validateRawRows(bytes, manifest, tuple, true).length, 2);
    assert.throws(() => validateRawRows(bytes, manifest, { ...tuple, workerId: "w02" }, true), /identity mismatch/);
    const invalidSkill = { ...rows[0], skillStateAudit: { blue: [{ ...rows[0].skillStateAudit.blue[0], state: {} }], red: [] } };
    assert.throws(() => normalizeResultRow(invalidSkill), /skillStateAudit/);
    const unknownPresentation = { observed: false, qualityApplied: "LOW", performanceLevel: null,
      lastAppliedSoftU: null, appliedCommand: null, sceneEpoch: null, paused: null, frameRate: null };
    const presentationRow = { ...rows[0], presentationAudit: { qualityAtStart: "LOW", qualityApplied: "LOW",
      atStart: unknownPresentation, atEnd: unknownPresentation } };
    assert.strictEqual(normalizeResultRow(presentationRow).presentationAudit.atStart.frameRate, null);
    assert.throws(() => normalizeResultRow({ ...presentationRow, presentationAudit: { ...presentationRow.presentationAudit,
      atEnd: { ...unknownPresentation, observed: true } } }), /presentationAudit/);
    await runFixture(path.join(temp, "runner-good"), appData, false);
    await runFixture(path.join(temp, "runner-bad"), appData, true);
    await runFixture(path.join(temp, "runner-forced"), appData, false, true);
    await runFixture(path.join(temp, "runner-unknown-start"), appData, false, false, true);
    await runFixture(path.join(temp, "runner-lost-bridge"), appData, false, false, false, { name: "lost-bridge", lostBridge: true });
    await runFixture(path.join(temp, "runner-foreign-result"), appData, false, false, false, { name: "foreign-result", foreignPath: true });
    await runFixture(path.join(temp, "runner-no-observed-result"), appData, false, false, false, { name: "no-observed-result", noObservedPath: true });
    await runFixture(path.join(temp, "runner-post-resource-failure"), appData, false, false, false, { name: "post-resource-failure", postResourceMissing: true });
    await noOwnerSignalFixture(path.join(temp, "runner-no-owner-signal"), appData);
    await dotnetUnavailableFixture(path.join(temp, "runner-missing-dotnet"), appData);
    console.log(JSON.stringify({ ok: true, evidenceKind: "isolated_fixture", ownerAndPidFence: true,
      exactEchoRequired: true, globalSaveAllowlistExact: true, rawTupleMismatchRetainedAndRejected: true,
      sequentialShardAndRecycling: true, resourceHashRootIndependent: true }));
  } finally {
    assert(path.resolve(temp).startsWith(`${path.resolve(os.tmpdir())}${path.sep}cf7-worker-context-`));
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
