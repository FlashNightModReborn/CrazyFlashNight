"use strict";

const fs = require("fs");
const path = require("path");
const { Worker, threadId } = require("worker_threads");
const { resolveExpectedRuntimeIdentity } = require("../../lib/runtime-process-identity");
const { sha256OfValue } = require("./arena-calibration-core");
const { sha256Bytes } = require("./immutable-evidence");
const { assertNoReparse, resolveInside } = require("./arena-worker-client");
const { captureProtectedSaveSnapshot, findSolFiles } = require("./unattended-save-safety");

// Same synchronous primitive, ordering and hash contract as the old shard API.
// Worker orchestration invokes it inside the evidence thread, never on its
// HTTP control loop. Existing read-only callers keep the synchronous export.
function captureResourceClosure(root, extras = []) {
  const selected = ["CRAZYFLASHER7MercenaryEmpire.swf", "scripts/asLoader.swf", "data", "config", ...extras];
  const files = new Map();
  const visit = (file) => {
    assertNoReparse(file);
    const stat = fs.statSync(file);
    if (stat.isDirectory()) fs.readdirSync(file).sort().forEach((name) => visit(path.join(file, name)));
    else if (stat.isFile()) {
      const relative = path.relative(root, file).replace(/\\/g, "/");
      files.set(relative, { path: relative, size: stat.size, sha256: sha256Bytes(fs.readFileSync(file)) });
    }
  };
  selected.forEach((entry, index) => {
    const file = resolveInside(root, entry, "observed resource");
    if (index < 2 || fs.existsSync(file)) visit(file);
  });
  const entries = [...files.values()].sort((a, b) => a.path.localeCompare(b.path));
  return { scope: "observed_runtime_resources", completeResourceClosure: false,
    mainSwfSha256: files.get("CRAZYFLASHER7MercenaryEmpire.swf").sha256,
    asLoaderSha256: files.get("scripts/asLoader.swf").sha256,
    files: entries, closureHash: sha256OfValue(entries) };
}

function performEvidenceTask(request) {
  if (!request || !["runtime_identity", "before", "after"].includes(request.operation)) {
    throw new Error("unsupported Worker evidence operation");
  }
  const startedAtUtc = new Date().toISOString();
  const runtime = () => request.fixture === true && request.fixtureRuntimeIdentity
    ? request.fixtureRuntimeIdentity : resolveExpectedRuntimeIdentity(request.projectRoot, request.candidateRoot);
  const result = {};
  const sampled = () => ({ ...result, sampling: { source: "worker_thread", operation: request.operation, threadId,
    startedAtUtc, completedAtUtc: new Date().toISOString() } });
  try {
    if (request.operation === "runtime_identity") result.runtimeIdentity = runtime();
    else if (request.operation === "before") {
      result.runtimeIdentity = runtime();
      if (findSolFiles(request.projectRoot, request.slot, request.saveOptions).length > 0) {
        throw new Error("Worker fresh session found a prior target SOL; seed preparation must resolve it explicitly");
      }
      result.resourceClosure = captureResourceClosure(request.projectRoot, request.resourcePaths || []);
      result.protectedSave = captureProtectedSaveSnapshot(request.projectRoot, request.slot, request.saveOptions);
    } else {
      result.protectedSave = captureProtectedSaveSnapshot(request.projectRoot, request.slot, request.saveOptions);
      result.resourceClosure = captureResourceClosure(request.projectRoot, request.resourcePaths || []);
      result.runtimeIdentity = runtime();
    }
  } catch (error) {
    // Preserve each completed diagnostic stage without qualifying a failed
    // composite sample. The caller still records the capture error.
    error.partialEvidence = sampled();
    throw error;
  }
  return sampled();
}

function runEvidenceTask(request, { workerFactory = (file, options) => new Worker(file, options) } = {}) {
  return new Promise((resolve, reject) => {
    const worker = workerFactory(path.join(__dirname, "arena-worker-evidence-thread.js"), { workerData: { request } });
    let result = null;
    let failure = null;
    worker.on("message", (message) => {
      if (!message || message.schema !== "arena-worker.evidence-result.v1" || result || failure) {
        failure = failure || new Error("Worker evidence thread returned an invalid or duplicate result");
        return;
      }
      if (message.error) {
        failure = new Error(message.error.message || "Worker evidence capture failed");
        if (message.error.code) failure.code = message.error.code;
        const partial = message.error.partialEvidence;
        if (partial && partial.sampling && partial.sampling.operation === request.operation
            && partial.sampling.source === "worker_thread" && partial.sampling.threadId > 0) {
          failure.partialEvidence = partial;
        }
      } else if (!message.result || !message.result.sampling || message.result.sampling.operation !== request.operation
          || message.result.sampling.source !== "worker_thread" || message.result.sampling.threadId <= 0) {
        failure = new Error("Worker evidence thread returned unbound sampling metadata");
      } else result = message.result;
    });
    worker.once("error", (error) => { failure = error; });
    // Thread teardown remains in lifecycle wall time; a crash or missing reply
    // never turns an incomplete sample into accepted evidence.
    worker.once("exit", (code) => {
      if (failure) reject(failure);
      else if (code !== 0 || !result) reject(new Error(`Worker evidence thread exited without complete evidence (code ${code})`));
      else resolve(result);
    });
  });
}

async function resolveWorkerRuntimeIdentity(projectRoot, candidateRoot) {
  return (await runEvidenceTask({ operation: "runtime_identity", projectRoot, candidateRoot })).runtimeIdentity;
}

module.exports = { captureResourceClosure, performEvidenceTask, runEvidenceTask, resolveWorkerRuntimeIdentity };
