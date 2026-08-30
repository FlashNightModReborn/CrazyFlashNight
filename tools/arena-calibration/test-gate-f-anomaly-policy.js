#!/usr/bin/env node
"use strict";

const assert = require("assert");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const {
  classifyCandidateAnomaly,
  createExceptionReviewRequest,
  selectRunnableShards,
} = require("./lib/gate-f-anomaly-policy");

const HASH = (text) => sha256OfValue({ text });
const candidates = ["candidate-a", "candidate-b"];
const manifest = {
  planner: { phase: "standard", candidateIds: candidates },
};
const rows = [
  {
    caseId: "candidate-a",
    status: "contamination",
    errors: [{ code: "arena_contamination", name: "derived-red-crystal" }],
  },
  { caseId: "candidate-b-side-swap", status: "finished", errors: [] },
];
const base = {
  manifest,
  rows,
  candidateIds: candidates,
  plannedRuns: 2,
  saveUnchanged: true,
  runtimeVerified: true,
  diskOk: true,
  withinWallClock: true,
};
const anomaly = classifyCandidateAnomaly(base);
assert.strictEqual(anomaly.eligible, true);
assert.deepStrictEqual(anomaly.affectedCandidateIds, ["candidate-a"]);
assert.deepStrictEqual(anomaly.rowStatusCounts, { contamination: 1, finished: 1 });
assert.strictEqual(anomaly.errorSignals[0].code, "arena_contamination");
assert.strictEqual(classifyCandidateAnomaly({ ...base, saveUnchanged: false }).eligible, false);
assert.strictEqual(classifyCandidateAnomaly({
  ...base,
  manifest: { planner: { phase: "soak", candidateIds: candidates } },
}).eligible, false);
assert.strictEqual(classifyCandidateAnomaly({
  ...base,
  rows: [{ caseId: "candidate-a", status: "bridge_lost", errors: [] }],
  plannedRuns: 1,
}).eligible, false);

const plan = {
  candidateBaselines: candidates.map((candidateId) => ({ candidateId, initialState: "scheduled" })),
  shards: [
    { shardId: "a-p1", candidateIds: ["candidate-a"] },
    { shardId: "a-p2", candidateIds: ["candidate-a"] },
    { shardId: "b-p1", candidateIds: ["candidate-b"] },
  ],
};
const latest = new Map([["a-p1", {
  shardId: "a-p1",
  state: "quarantined",
  affectedCandidateIds: ["candidate-a"],
}]]);
const scheduling = selectRunnableShards(plan, latest, Number.POSITIVE_INFINITY);
assert.deepStrictEqual(scheduling.runnable.map((entry) => entry.shardId), ["b-p1"]);
assert.deepStrictEqual(Array.from(scheduling.quarantinedCandidateIds), ["candidate-a"]);
assert.deepStrictEqual(Array.from(scheduling.quarantinedShardIds).sort(), ["a-p1", "a-p2"]);

const receipt = {
  receiptId: "a-p1-20260830T000000Z",
  campaignId: "gate-f-fixture",
  planHash: HASH("plan"),
  shardId: "a-p1",
  manifestHash: HASH("manifest"),
  state: "quarantined",
  affectedCandidateIds: ["candidate-a"],
  receiptHash: HASH("receipt"),
  runReportPath: "tmp/report.json",
  runReportSha256: HASH("report"),
  reason: "candidate-scoped anomaly",
};
const request = createExceptionReviewRequest({
  receipt,
  candidateIds: anomaly.affectedCandidateIds,
  rowStatusCounts: anomaly.rowStatusCounts,
  errorSignals: anomaly.errorSignals,
  createdAt: "2026-08-30T00:00:00.000Z",
});
assert.strictEqual(request.policy.mayAcceptSample, false);
assert.strictEqual(request.policy.mayResumeCandidate, false);
assert.strictEqual(request.policy.campaignAction, "defer_and_continue");
assert.strictEqual(request.requestHash, sha256OfValue(Object.fromEntries(
  Object.entries(request).filter(([key]) => key !== "requestHash"),
)));

console.log(JSON.stringify({
  ok: true,
  check: "gate-f-candidate-quarantine-and-async-review",
  deterministicDefault: "quarantine_candidate",
  campaignAction: "defer_and_continue",
  modelAutoAcceptAuthority: false,
}));
