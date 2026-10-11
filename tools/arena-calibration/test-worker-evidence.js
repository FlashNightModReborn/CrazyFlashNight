#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const http = require("http");
const os = require("os");
const path = require("path");
const { Worker } = require("worker_threads");
const { resolveExpectedRuntimeIdentity } = require("../lib/runtime-process-identity");
const { sha256Bytes } = require("./lib/immutable-evidence");
const { CONTROL_HEADER, createWorkerClient, normalizePerformance } = require("./lib/arena-worker-client");
const { captureProtectedSaveSnapshot } = require("./lib/unattended-save-safety");
const { captureResourceClosure, runEvidenceTask, resolveWorkerRuntimeIdentity } = require("./lib/arena-worker-evidence");

function write(file, bytes) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, bytes);
}

function fixture(root) {
  fs.mkdirSync(root, { recursive: true });
  const git = childProcess.spawnSync("git", ["init", "--quiet", root], { encoding: "utf8", windowsHide: true });
  assert.strictEqual(git.status, 0, git.stderr);
  const candidateRoot = path.join(root, "tmp", "runtime-candidates", "v2", "fixture-candidate");
  const dll = Buffer.from("isolated test bytes; not executable");
  const dllPath = path.join(candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.dll");
  write(dllPath, dll);
  write(path.join(candidateRoot, "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"), "not executable");
  write(path.join(candidateRoot, "runtime", "cf7-runtime-manifest.tsv"), [
    "cf7-runtime-manifest-v2", `buildIdentityHash\t${"B".repeat(64)}`, `payloadClosureHash\t${"C".repeat(64)}`,
    `file\truntime/CRAZYFLASHER7MercenaryEmpire.Core.dll\t${dll.length}\t${sha256Bytes(dll).slice(7).toUpperCase()}`, "",
  ].join("\n"));
  write(path.join(candidateRoot, "runtime-build-metadata.v2.json"), JSON.stringify({
    schema: "cf7-runtime-candidate-metadata.v2", buildIdentityHash: "B".repeat(64), payloadClosureHash: "C".repeat(64),
  }));
  write(path.join(root, "CRAZYFLASHER7MercenaryEmpire.swf"), "fixture main");
  write(path.join(root, "scripts", "asLoader.swf"), "fixture loader");
  write(path.join(root, "data", "units.xml"), "<units />");
  write(path.join(root, "config", "options.json"), "{}");
  const blockPath = path.join(root, "media", "fixture.bin");
  write(blockPath, Buffer.alloc(4096, 23));
  write(path.join(root, "saves", "protected-fixture.json"), '{"fixture":true}');
  write(path.join(root, "saves", "cf7_agent_sampler.json"), '{}');
  return { projectRoot: root, candidateRoot, slot: "cf7_agent_sampler", resourcePaths: ["media/fixture.bin"],
    saveOptions: { appData: path.join(root, "fixture-appdata") }, blockPath, dllPath };
}

async function waitForBarrier(words) {
  const deadline = Date.now() + 10000;
  while (Atomics.load(words, 0) !== 1) {
    if (Date.now() >= deadline) throw new Error("evidence fixture did not enter its resource read");
    await new Promise((resolve) => setTimeout(resolve, 5));
  }
}

async function httpWhileOtherShardSamples(sample, control) {
  const sockets = new Set();
  let mode = "reply";
  const calls = [];
  const token = "isolated-fixture-control-token-".repeat(3);
  const server = http.createServer((request, response) => {
    const chunks = [];
    request.on("data", (chunk) => chunks.push(chunk));
    request.on("end", () => {
      const body = JSON.parse(Buffer.concat(chunks).toString("utf8"));
      calls.push(body.action);
      assert.strictEqual(request.headers[CONTROL_HEADER.toLowerCase()], token);
      assert.strictEqual(request.url, "/arena-worker");
      if (mode === "timeout") return;
      if (mode === "reset") { request.socket.destroy(); return; }
      const bytes = JSON.stringify({ success: true, ok: true, workerId: body.workerId,
        sessionEpoch: body.sessionEpoch, completeBody: "both response chunks received" });
      response.writeHead(200, { "Content-Type": "application/json" });
      response.write(bytes.slice(0, 17));
      setTimeout(() => response.end(bytes.slice(17)), 15);
    });
  });
  server.on("connection", (socket) => { sockets.add(socket); socket.on("close", () => sockets.delete(socket)); });
  await new Promise((resolve) => server.listen(0, "127.0.0.1", resolve));
  const runtime = resolveExpectedRuntimeIdentity(control.projectRoot, control.candidateRoot);
  const httpPort = server.address().port;
  const launch = { schema: "arena-worker.launch.v1", workerId: "http-neighbor", sessionEpoch: "http-session",
    projectRoot: control.projectRoot, stateRoot: path.join(control.projectRoot, "tmp", "arena-worker", "http-session"),
    saveRoot: path.join(control.projectRoot, "saves"), outputRoot: path.join(control.projectRoot, "tmp", "arena-calibration"),
    swfOrigin: path.join(control.projectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"), slot: "cf7_agent_http",
    performance: normalizePerformance() };
  const owner = { ...launch, schema: "arena-worker.owner.v1", executionMode: "arena_worker", hostPid: process.pid,
    processStartUtcTicks: "638400000000000001", processPath: runtime.processPath, httpPort,
    socketPort: httpPort === 65535 ? httpPort - 1 : httpPort + 1, runtimeIdentity: runtime,
    appData: control.saveOptions.appData,
    sharedObjectsRoot: path.join(control.saveOptions.appData, "Macromedia", "Flash Player", "#SharedObjects") };
  write(path.join(launch.stateRoot, "owner.json"), JSON.stringify(owner));
  write(path.join(launch.stateRoot, "control-credential.json"), JSON.stringify({ schema: "arena-worker.control-credential.v1",
    workerId: launch.workerId, sessionEpoch: launch.sessionEpoch, header: CONTROL_HEADER, token }));
  const client = createWorkerClient(launch, runtime, { timeoutMs: 150,
    ownershipProbe: () => ({ process: { pid: owner.hostPid, processStartUtcTicks: owner.processStartUtcTicks,
      processPath: owner.processPath }, listeners: [{ localPort: httpPort, owningProcess: owner.hostPid }] }) });

  // A fixture-only Worker factory holds one actual production resource read.
  // The unchanged entry point and capture algorithm run in the real thread.
  // No huge payload, busy loop, fake HTTP transport, or game process is needed.
  const barrier = new SharedArrayBuffer(Int32Array.BYTES_PER_ELEMENT * 2);
  const words = new Int32Array(barrier);
  const bootstrap = `
    const fs = require('fs'), path = require('path');
    const { workerData } = require('worker_threads');
    const words = new Int32Array(workerData.barrier), read = fs.readFileSync;
    fs.readFileSync = function(file, ...args) {
      if (typeof file === 'string' && path.resolve(file) === workerData.blockPath) {
        Atomics.store(words, 0, 1); Atomics.notify(words, 0);
        if (Atomics.wait(words, 1, 0, 10000) === 'timed-out') throw new Error('fixture barrier expired');
      }
      return read.call(fs, file, ...args);
    };
    require(workerData.entry);
  `;
  let settled = false;
  const sampling = runEvidenceTask({ ...sample, operation: "after" }, {
    workerFactory: (entry, options) => new Worker(bootstrap, { eval: true,
      workerData: { ...options.workerData, entry, barrier, blockPath: sample.blockPath } }),
  });
  sampling.then(() => { settled = true; }, () => { settled = true; });
  try {
    await waitForBarrier(words);
    const response = await client.call("status");
    assert.strictEqual(response.completeBody, "both response chunks received");
    assert.strictEqual(settled, false, "complete HTTP data/end must be processed while the other shard is still sampling");
    mode = "timeout";
    await assert.rejects(() => client.call("status"), /timeout; delivery outcome is unknown/);
    assert.strictEqual(settled, false);
    mode = "reset";
    await assert.rejects(() => client.call("status"), (error) => error.code === "ECONNRESET");
    assert.deepStrictEqual(calls, ["status", "status", "status"], "unknown/reset delivery is never replayed");
  } finally {
    Atomics.store(words, 1, 1); Atomics.notify(words, 1);
    sockets.forEach((socket) => socket.destroy());
    await new Promise((resolve) => server.close(resolve));
  }
  const result = await sampling;
  assert.deepStrictEqual(result.resourceClosure, captureResourceClosure(sample.projectRoot, sample.resourcePaths));
  assert.strictEqual(result.sampling.source, "worker_thread");
  assert(result.sampling.threadId > 0);
}

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-worker-evidence-"));
  try {
    const sample = fixture(path.join(temp, "sampling-worker"));
    const control = fixture(path.join(temp, "control-worker"));
    const expected = captureResourceClosure(sample.projectRoot, sample.resourcePaths);
    const protectedSave = captureProtectedSaveSnapshot(sample.projectRoot, sample.slot, sample.saveOptions);
    const before = await runEvidenceTask({ ...sample, operation: "before" });
    assert.deepStrictEqual(before.resourceClosure, expected);
    assert.strictEqual(before.resourceClosure.files.length, 5);
    assert.deepStrictEqual(before.protectedSave.files, protectedSave.files);
    assert.strictEqual(before.protectedSave.snapshotHash, protectedSave.snapshotHash);
    assert.deepStrictEqual(before.runtimeIdentity, resolveExpectedRuntimeIdentity(sample.projectRoot, sample.candidateRoot));
    assert.deepStrictEqual(await resolveWorkerRuntimeIdentity(sample.projectRoot, sample.candidateRoot), before.runtimeIdentity);
    await httpWhileOtherShardSamples(sample, control);
    write(path.join(sample.projectRoot, "data", "units.xml"), "<changed />");
    write(path.join(sample.projectRoot, "saves", "protected-fixture.json"), '{"changed":true}');
    const after = await runEvidenceTask({ ...sample, operation: "after" });
    assert.notStrictEqual(after.resourceClosure.closureHash, before.resourceClosure.closureHash);
    assert.notStrictEqual(after.protectedSave.snapshotHash, before.protectedSave.snapshotHash);
    write(sample.dllPath, "changed candidate bytes");
    await assert.rejects(() => runEvidenceTask({ ...sample, operation: "after" }), (error) => {
      assert.match(error.message, /Core DLL bytes do not match/);
      assert.strictEqual(error.partialEvidence.protectedSave.snapshotHash, after.protectedSave.snapshotHash);
      assert.deepStrictEqual(error.partialEvidence.resourceClosure, after.resourceClosure);
      assert.strictEqual(error.partialEvidence.runtimeIdentity, undefined);
      return true;
    });
    fs.unlinkSync(path.join(sample.projectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"));
    await assert.rejects(() => runEvidenceTask({ ...sample, operation: "after" }), (error) => {
      assert.match(error.message, /ENOENT/);
      assert.strictEqual(error.partialEvidence.protectedSave.snapshotHash, after.protectedSave.snapshotHash);
      assert.strictEqual(error.partialEvidence.resourceClosure, undefined);
      assert.strictEqual(error.partialEvidence.runtimeIdentity, undefined);
      return true;
    });
    await assert.rejects(() => runEvidenceTask({ ...control, operation: "before" }, {
      workerFactory: () => new Worker("process.exit(0)", { eval: true }),
    }), /without complete evidence/);
    await assert.rejects(() => runEvidenceTask({ ...control, operation: "before" }, {
      workerFactory: () => new Worker("throw new Error('evidence thread failed')", { eval: true }),
    }), /evidence thread failed/);
    console.log(JSON.stringify({ ok: true, workerEvidence: "isolated_fixture", fullSnapshotAlgorithmPreserved: true,
      httpResponseDuringOtherShardResourceRead: true, genuineTimeoutAndResetRemainFailures: true,
      noRetry: true, incompleteOrChangedEvidenceRejected: true }));
  } finally {
    const resolved = path.resolve(temp);
    assert(resolved.startsWith(path.resolve(os.tmpdir()) + path.sep)
      && path.basename(resolved).startsWith("cf7-worker-evidence-"));
    fs.rmSync(resolved, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error.stack || error.message); process.exitCode = 1; });
