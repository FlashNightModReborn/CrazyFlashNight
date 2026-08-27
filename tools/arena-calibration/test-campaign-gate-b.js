#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const {
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  createIdleGrant,
  createProducerRegistry,
  validateIdleGrant,
} = require("./lib/campaign-resource-arbiter");
const {
  DurableCampaignJournal,
  InjectedJournalCrash,
  JournalIntegrityError,
  WriterLeaseError,
} = require("./lib/durable-campaign-journal");
const { CampaignSupervisor } = require("./lib/campaign-supervisor");
const { validateSchemaInstance } = require("./lib/schema-registry");

const NOW = "2026-08-27T10:00:00.000Z";
const HASH = (text) => sha256OfValue({ text });

function observations(overrides) {
  overrides = overrides || {};
  return [
    ["launcher-runtime-producer", "launcher"],
    ["flash-runtime-producer", "flash"],
    ["arena-runner-producer", "arena_runner"],
    ["flash-cs6-content-producer", "content_development"],
  ].map(([producerId, scope]) => ({
    producerId,
    scope,
    online: true,
    leaseState: "idle",
    observedAt: NOW,
    evidenceRef: HASH(producerId),
    ...(overrides[producerId] || {}),
  }));
}

function registryAndGrant(overrides) {
  const registry = createProducerRegistry(observations(overrides), {
    registryId: "registry-gate-b-fixture",
    generatedAt: NOW,
    observationTtlSeconds: 60,
  });
  const grant = createIdleGrant(registry, {
    grantId: "grant-gate-b-fixture",
    issuedAt: NOW,
    ttlSeconds: 120,
  });
  return { registry, grant };
}

function expectError(action, ErrorType, code) {
  let observed = null;
  try { action(); } catch (error) { observed = error; }
  assert(observed instanceof ErrorType, `expected ${ErrorType.name}, got ${observed && observed.name}`);
  if (code) assert.strictEqual(observed.code, code);
  return observed;
}

function journal(root, campaignId) {
  return new DurableCampaignJournal({ root, campaignId, clock: () => NOW, leaseTtlMs: 1000 });
}

function runCrashFixture(root, point, expectsCommitted) {
  const campaignId = `campaign-${point.replace(/_/g, "-")}`;
  const first = journal(root, campaignId);
  first.acquireWriter();
  first.append("campaign_created", { profile: "provisional" });
  expectError(
    () => first.appendResultOnce("run-key-1", { artifactHash: HASH(point) }, { faultPoint: point }),
    InjectedJournalCrash,
    point === "after_second_flush_before_ack" ? "ack_lost" : "injected_crash"
  );
  first.releaseWriter("injected_process_exit");

  const recovered = journal(root, campaignId);
  recovered.acquireWriter({ allowStaleRecovery: true });
  const snapshot = recovered.snapshot();
  assert.strictEqual(snapshot.committedRunKeys.includes("run-key-1"), expectsCommitted);
  if (expectsCommitted) {
    const retry = recovered.appendResultOnce("run-key-1", { artifactHash: HASH(`${point}-retry`) });
    assert.strictEqual(retry.accepted, false);
    assert.strictEqual(recovered.snapshot().committedRunKeys.filter((entry) => entry === "run-key-1").length, 1);
  } else {
    assert(snapshot.eventCount >= 2, "recovery must record the excluded truncated tail");
    const retry = recovered.appendResultOnce("run-key-1", { artifactHash: HASH(`${point}-retry`) });
    assert.strictEqual(retry.accepted, true);
  }
  recovered.closeSegment("fixture_complete");
  recovered.releaseWriter("fixture_complete");
  return snapshot;
}

function main() {
  const { registry, grant } = registryAndGrant();
  assert.strictEqual(validateSchemaInstance(registry.schema, registry).ok, true);
  assert.strictEqual(validateSchemaInstance(grant.schema, grant).ok, true);
  assert.strictEqual(validateIdleGrant(grant, registry, {
    now: "2026-08-27T10:00:30.000Z",
    trustedIssuers: ["cf7-local-development-arbiter"],
  }), true);

  const missingScopeProducers = observations().filter((entry) => entry.scope !== "flash");
  missingScopeProducers.push({
    producerId: "secondary-content-producer",
    scope: "content_development",
    online: true,
    leaseState: "idle",
    observedAt: NOW,
    evidenceRef: HASH("secondary-content-producer"),
  });
  const missingScope = createProducerRegistry(missingScopeProducers, {
    registryId: "registry-missing-flash",
    generatedAt: NOW,
  });
  expectError(() => createIdleGrant(missingScope, { issuedAt: NOW }), Error, "producer_scope_missing");
  const active = createProducerRegistry(observations({ "flash-cs6-content-producer": { leaseState: "active" } }), {
    registryId: "registry-active-producer",
    generatedAt: NOW,
  });
  expectError(() => createIdleGrant(active, { issuedAt: NOW }), Error, "producer_not_idle");
  const unknown = createProducerRegistry(observations({ "arena-runner-producer": { leaseState: "unknown" } }), {
    registryId: "registry-unknown-producer",
    generatedAt: NOW,
  });
  expectError(() => createIdleGrant(unknown, { issuedAt: NOW }), Error, "producer_not_idle");
  expectError(
    () => validateIdleGrant(grant, registry, { now: "2026-08-27T10:02:01.000Z" }),
    Error,
    "producer_observation_expired"
  );
  const shortGrant = createIdleGrant(registry, { grantId: "short-grant", issuedAt: NOW, ttlSeconds: 30 });
  expectError(
    () => validateIdleGrant(shortGrant, registry, { now: "2026-08-27T10:00:31.000Z" }),
    Error,
    "grant_expired"
  );
  const revoked = { ...grant, revokeSignal: true, grantHash: "" };
  revoked.grantHash = sha256OfValue(Object.fromEntries(Object.entries(revoked).filter(([key]) => key !== "grantHash")));
  expectError(() => validateIdleGrant(revoked, registry, { now: NOW }), Error, "grant_revoked");

  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-arena-gate-b-"));
  try {
    const contentionA = journal(tempRoot, "campaign-writer-contention");
    const contentionB = journal(tempRoot, "campaign-writer-contention");
    contentionA.acquireWriter();
    expectError(() => contentionB.acquireWriter(), WriterLeaseError, "writer_contention");
    contentionA.releaseWriter("contention_fixture_complete");

    const crashResults = {
      beforeFirstFlush: runCrashFixture(tempRoot, "before_first_flush", false),
      afterFirstFlush: runCrashFixture(tempRoot, "after_first_flush", false),
      beforeSecondFlush: runCrashFixture(tempRoot, "before_second_flush", false),
      ackLost: runCrashFixture(tempRoot, "after_second_flush_before_ack", true),
    };

    const supervisorOptions = {
      projectRoot: path.resolve(__dirname, "../.."),
      journalRoot: tempRoot,
      campaignId: "campaign-supervisor-resume",
      clock: () => NOW,
    };
    const firstSupervisor = new CampaignSupervisor(supervisorOptions);
    firstSupervisor.initialize({
      profile: "provisional_gate_b_v1",
      decisionPolicyId: "rule-fixture-v1",
      battleSemanticsCohortId: "cohort-fixture",
      executionArtifactPolicy: "fixture-policy",
      retentionDays: 90,
    }, registry, grant);
    assert.strictEqual(firstSupervisor.journal.state.events.filter(({ event }) => event.eventType === "campaign_resumed").length, 1);
    firstSupervisor.pause("fixture_process_boundary", { resourcesReleased: true });
    const resumedSupervisor = new CampaignSupervisor(supervisorOptions);
    resumedSupervisor.acquire({ allowStaleRecovery: true });
    resumedSupervisor.resume(registry, grant, "fixture_resume");
    assert.strictEqual(resumedSupervisor.journal.state.events.filter(({ event }) => event.eventType === "campaign_resumed").length, 2);
    resumedSupervisor.pause("fixture_complete", { resourcesReleased: true });

    const tamper = journal(tempRoot, "campaign-tamper");
    tamper.acquireWriter();
    tamper.append("campaign_created", { profile: "provisional" });
    const closed = tamper.closeSegment("tamper_fixture");
    tamper.releaseWriter("tamper_fixture");
    const original = fs.readFileSync(closed.closedPath, "utf8");
    fs.writeFileSync(closed.closedPath, original.replace("provisional", "tampered-value"), "utf8");
    expectError(() => journal(tempRoot, "campaign-tamper").recover(), JournalIntegrityError);

    console.log(JSON.stringify({
      ok: true,
      gate: "B",
      producerRegistryFailClosed: true,
      writerContentionRejected: true,
      crashPoints: Object.keys(crashResults),
      ackLossExactlyOnce: true,
      pauseResumeTraced: true,
      truncatedTailExcluded: true,
      closedSegmentTamperRejected: true,
    }, null, 2));
  } finally {
    const resolvedTemp = path.resolve(tempRoot);
    const resolvedBase = path.resolve(os.tmpdir());
    if (!resolvedTemp.startsWith(`${resolvedBase}${path.sep}`)) {
      throw new Error(`refusing to remove unexpected fixture path: ${resolvedTemp}`);
    }
    fs.rmSync(resolvedTemp, { recursive: true, force: true });
  }
}

main();
