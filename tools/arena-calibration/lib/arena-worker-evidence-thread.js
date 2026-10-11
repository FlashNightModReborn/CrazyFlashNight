"use strict";

const { parentPort, workerData } = require("worker_threads");
const { performEvidenceTask } = require("./arena-worker-evidence");

try {
  const result = performEvidenceTask(workerData.request);
  parentPort.postMessage({ schema: "arena-worker.evidence-result.v1", result });
} catch (error) {
  parentPort.postMessage({ schema: "arena-worker.evidence-result.v1",
    error: { message: error.message, code: error.code || null, partialEvidence: error.partialEvidence || null } });
} finally {
  parentPort.close();
}
