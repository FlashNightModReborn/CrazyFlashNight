"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");

const Evidence = require("../lib/evidence-artifact");
const Applicability = require("./applicability");
const Common = require("./common");
const Formal = require("./formal-run-protocol");
const CandidateProtocol = require("./protocol");

function lower(char) {
  return char.repeat(64);
}

function upper(char) {
  return char.repeat(64);
}

function candidateIdentity() {
  const installRoot = path.join(Common.CANONICAL_ROOT, "tmp", "formal-protocol-fixture",
    "candidate");
  return {
    runtimeMode: "isolated_candidate",
    processPath: path.join(installRoot, Formal.CORE_RELATIVE_PATH),
    coreSha256: upper("C"),
    buildIdentity: upper("A"),
    payloadClosure: upper("B"),
    installRoot,
  };
}

function candidateProducerBinding(identity) {
  const value = {
    schema: "workbench-live-e2e.crafting.candidate-producer-binding.v2",
    candidateRoot: identity.installRoot,
    metadata: { locator: "candidate:runtime-build-metadata.v2.json",
      sha256: lower("1"), bytes: 123 },
    manifest: { locator: "candidate:runtime/cf7-runtime-manifest.tsv",
      sha256: lower("2"), bytes: 456 },
    builderLabel: "fixture-builder",
    createdAtUtc: "2026-08-14T00:00:00.000Z",
    producerInputsSha256: lower("3"),
    artifactSourceHash: upper("4"),
    producerRecipeHash: upper("5"),
    toolchainLockHash: upper("6"),
    buildIdentityHash: identity.buildIdentity,
    payloadClosureHash: identity.payloadClosure,
    payloadFileCount: 33,
    processImage: { locator: "candidate:" + Formal.PROCESS_IMAGE_RELATIVE_PATH,
      sha256: lower("d"), bytes: 789 },
    coreLibrary: { locator: "candidate:" + Formal.CORE_LIBRARY_RELATIVE_PATH,
      sha256: identity.coreSha256.toLowerCase(), bytes: 987 },
  };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function protocolApplicability() {
  return {
    applicabilitySha256: lower("7"),
    counts: {
      materialCount: 1, shopFileCount: 1, materialOccurrenceCount: 1,
      uniqueMaterialItemCount: 1, requiredInfoOccurrenceCount: 0,
      purchaseLimitOccurrenceCount: 0, seedCount: 4, seedMaterialPairCount: 4,
      affordableSeedOccurrenceCount: 4, atDefaultLimitSeedOccurrenceCount: 0,
    },
    unlocked: { status: "required_candidate_journey", qualifyingOccurrenceCount: 1 },
    locked: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
    max: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
    selectedUnlockedTarget: Formal.FORMAL_TARGET,
  };
}

function candidateControlPlan() {
  const applicability = protocolApplicability();
  const runId = "a5-candidate-accepted";
  const authorization = CandidateProtocol.createAgentRuntimeAuthorization({
    evidenceMode: "candidate_capture",
    decisionId: "a5-candidate-accepted-q1",
    runId,
    applicabilitySha256: applicability.applicabilitySha256,
    target: applicability.selectedUnlockedTarget,
  });
  const originalValidate = Applicability.validateApplicability;
  Applicability.validateApplicability = (value) => value;
  try {
    return CandidateProtocol.createAgentRuntimeControlPlan({
      runId,
      evidenceMode: "candidate_capture",
      seedSlot: Formal.FORMAL_SLOTS.seedSlot,
      targetSlot: Formal.FORMAL_SLOTS.targetSlot,
      recoverySlot: Formal.FORMAL_SLOTS.recoverySlot,
      scope: { head: "1".repeat(40), scopeSha256: lower("2"),
        closureSha256: lower("3"), materializationSha256: lower("4") },
      applicability,
      authorization,
    });
  } finally {
    Applicability.validateApplicability = originalValidate;
  }
}

function candidateAcceptance(identity, controlPlan) {
  const value = {
    schema: Formal.CANDIDATE_ACCEPTANCE_SCHEMA,
    acceptedAt: "2026-08-14T00:00:00.000Z",
    status: "e2e_verified",
    deployment: "NOT_DEPLOYED",
    runId: "a5-candidate-accepted",
    planSha256: controlPlan.planSha256,
    preparationSha256: lower("2"),
    closureSha256: lower("3"),
    materializationSha256: lower("4"),
    buildSha256: lower("5"),
    externalToolchainSha256: lower("6"),
    candidateIdentitySha256: Evidence.sha256Text(Evidence.canonicalJson(identity)),
    applicabilitySha256: controlPlan.applicability.applicabilitySha256,
    rawSha256: lower("8"),
    operationTerminalSha256: lower("9"),
    journeyEvidenceSha256: lower("a"),
    settlementSha256: lower("b"),
    cloneReleaseSha256: lower("c"),
    staticGateSha256: lower("d"),
    reviewRequestSha256: lower("e"),
    reviewReceiptSha256: lower("f"),
    captureSetSha256: lower("0"),
    boundaries: { realGuiExecuted: true, candidateBuilt: true,
      candidateExecuted: true, e2eVerified: true, promoted: false,
      standardEntryVerified: false },
  };
  value.acceptanceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function promotion(identity, producer) {
  return {
    schema: Formal.PROMOTION_BINDING_SCHEMA,
    consensusSchema: Formal.CONSENSUS_SCHEMA,
    status: "promoted",
    sourceCommitOid: "a".repeat(40),
    releaseTreeOid: "b".repeat(40),
    sourceTag: "runtime-build-v2/20260814-material-a5-v1",
    requestId: upper("D"),
    buildIdentityHash: identity.buildIdentity,
    payloadClosureHash: identity.payloadClosure,
    processImageSha256: producer.processImage.sha256.toUpperCase(),
    coreLibrarySha256: producer.coreLibrary.sha256.toUpperCase(),
    policyReceiptSha256: upper("E"),
    consensusSha256: lower("f"),
    promotedAtUtc: "2026-08-14T01:00:00.000Z",
  };
}

function fixture() {
  const identity = candidateIdentity();
  const producer = candidateProducerBinding(identity);
  const controlPlan = candidateControlPlan();
  const promoted = promotion(identity, producer);
  const formalApplicabilityBinding = {
    schema: Formal.FORMAL_APPLICABILITY_BINDING_SCHEMA,
    source: "fresh_promoted_canonical_root_capture",
    sourceCommitOid: promoted.sourceCommitOid,
    buildIdentityHash: promoted.buildIdentityHash,
    payloadClosureHash: promoted.payloadClosureHash,
    applicabilitySha256: lower("6"),
    selectedUnlockedTarget: Formal.FORMAL_TARGET,
    verificationReceiptSha256: lower("5"),
  };
  return {
    identity,
    acceptedCandidate: { acceptance: candidateAcceptance(identity, controlPlan),
      candidateIdentity: identity, candidateProducerBinding: producer, controlPlan },
    promotion: promoted,
    formalApplicabilityBinding,
  };
}

function formalOptions(fx, runId) {
  const authorization = Formal.createFormalAuthorization({
    decisionId: "a5-formal-q1-01",
    preparerInputSha256: lower("d"),
    nonce: "a5-formal-q1-nonce-01",
    runId,
    applicabilitySha256: fx.formalApplicabilityBinding.applicabilitySha256,
  });
  return {
    canonicalRoot: Common.CANONICAL_ROOT,
    runId,
    acceptedCandidate: fx.acceptedCandidate,
    promotion: fx.promotion,
    formalApplicabilityBinding: fx.formalApplicabilityBinding,
    authorization,
  };
}

function createPlan() {
  const fx = fixture();
  return Formal.createFormalRunPlan(formalOptions(fx, "a5-formal-entry-01"));
}

function mutate(value, callback) {
  const copy = JSON.parse(JSON.stringify(value));
  callback(copy);
  return copy;
}

test("formal protocol projection binds candidate plan, promotion, fresh applicability, and launch", () => {
  const plan = createPlan();
  assert.equal(plan.schema, Formal.FORMAL_PLAN_SCHEMA);
  assert.equal(plan.evidenceMode, "formal_entry_capture");
  assert.equal(plan.journeyContract.stepCount, 24);
  assert.deepEqual(plan.journeyContract.steps.map((entry) => entry.id),
    CandidateProtocol.AGENT_RUNTIME_BASE_STEPS);
  assert.deepEqual(plan.journeyContract.sessions.map((entry) => entry.label),
    ["first", "restart"]);
  assert.equal(plan.launch.runtimeMode, "formal_runtime");
  assert.equal(plan.launch.candidateRoot, null);
  assert.equal(plan.launch.candidateId, null);
  assert.equal(plan.launch.projectRoot, Common.CANONICAL_ROOT);
  assert.equal(plan.launch.expectedBuildIdentity, plan.promotion.buildIdentityHash);
  assert.equal(plan.launch.expectedPayloadClosure, plan.promotion.payloadClosureHash);
  assert.equal(plan.launch.expectedProcessImageSha256,
    plan.promotion.processImageSha256);
  assert.equal(plan.launch.expectedCoreLibrarySha256,
    plan.promotion.coreLibrarySha256);
  assert.equal(plan.acceptedCandidate.controlPlan.planSha256,
    plan.acceptedCandidate.acceptance.planSha256);
  assert.notEqual(plan.formalApplicabilityBinding.applicabilitySha256,
    plan.acceptedCandidate.acceptance.applicabilitySha256);
  assert.equal(plan.authorization.runId, plan.runId);
  assert.equal(plan.authorization.applicabilitySha256,
    plan.formalApplicabilityBinding.applicabilitySha256);
  assert.deepEqual(plan.authorization.target, Formal.FORMAL_TARGET);
  assert.equal(plan.boundaries.externalAdmissionRequired, true);
  assert.equal(plan.boundaries.formalEntryExecuted, false);
  assert.equal(Formal.validateFormalRunPlan(plan), plan);
});

test("accepted candidate must carry the exact current plan named by acceptance", () => {
  const fx = fixture();
  fx.acceptedCandidate.acceptance.planSha256 = lower("e");
  fx.acceptedCandidate.acceptance.acceptanceSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Object.fromEntries(Object.entries(fx.acceptedCandidate.acceptance)
      .filter(([key]) => key !== "acceptanceSha256"))));
  assert.throws(() => Formal.createFormalRunPlan(
    formalOptions(fx, "a5-formal-entry-01")),
  (error) => error.code === "material_shop_formal_candidate_invalid");
});

test("formal plan rejects a candidate acceptance that is not accepted and NOT_DEPLOYED", () => {
  const fx = fixture();
  fx.acceptedCandidate.acceptance.status = "candidate_executed";
  fx.acceptedCandidate.acceptance.acceptanceSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Object.fromEntries(Object.entries(fx.acceptedCandidate.acceptance)
      .filter(([key]) => key !== "acceptanceSha256"))));
  assert.throws(() => Formal.createFormalRunPlan(
    formalOptions(fx, "a5-formal-entry-01")),
  (error) => error.code === "material_shop_formal_candidate_invalid");
});

test("accepted candidate preserves distinct Core EXE and Core DLL producer bindings", () => {
  for (const apply of [
    (fx) => { fx.acceptedCandidate.candidateProducerBinding.processImage.locator =
      "candidate:" + Formal.CORE_LIBRARY_RELATIVE_PATH; },
    (fx) => { fx.acceptedCandidate.candidateProducerBinding.coreLibrary.sha256 = lower("e"); },
    (fx) => { fx.acceptedCandidate.candidateProducerBinding.evidenceSha256 = lower("f"); },
  ]) {
    const fx = fixture();
    apply(fx);
    assert.throws(() => Formal.createFormalRunPlan(
      formalOptions(fx, "a5-formal-entry-01")),
    (error) => error.code === "material_shop_formal_candidate_invalid");
  }
});

test("formal plan rejects promotion identity, closure, process image, or Core library drift", () => {
  for (const field of ["buildIdentityHash", "payloadClosureHash", "processImageSha256",
    "coreLibrarySha256"]) {
    const fx = fixture();
    fx.promotion[field] = upper("F");
    assert.throws(() => Formal.createFormalRunPlan(
      formalOptions(fx, "a5-formal-entry-01")),
    (error) => error.code === "material_shop_formal_promotion_identity_mismatch");
  }
});

test("formal plan rejects malformed source commit and non-v2 source tag", () => {
  const fx = fixture();
  fx.promotion.sourceCommitOid = "not-a-commit";
  assert.throws(() => Formal.createFormalRunPlan(
    formalOptions(fx, "a5-formal-entry-01")),
  (error) => error.code === "material_shop_formal_promotion_invalid");
  fx.promotion.sourceCommitOid = "a".repeat(40);
  fx.promotion.sourceTag = "refs/heads/main";
  assert.throws(() => Formal.createFormalRunPlan(
    formalOptions(fx, "a5-formal-entry-01")),
  (error) => error.code === "material_shop_formal_promotion_invalid");
});

test("formal plan rejects candidate selectors and non-canonical process path", () => {
  const plan = createPlan();
  assert.throws(() => Formal.validateFormalRunPlan(mutate(plan, (copy) => {
    copy.launch.candidateId = "a5";
    copy.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Formal.stableFormalPlan(copy)));
  })), (error) => error.code === "material_shop_formal_launch_invalid");
  assert.throws(() => Formal.validateFormalRunPlan(mutate(plan, (copy) => {
    copy.launch.expectedProcessPath = copy.acceptedCandidate.candidateIdentity.processPath;
    copy.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Formal.stableFormalPlan(copy)));
  })), (error) => error.code === "material_shop_formal_launch_invalid");
});

test("formal plan rejects 24-step order, session, or restart-boundary drift", () => {
  for (const apply of [
    (copy) => { [copy.journeyContract.steps[0], copy.journeyContract.steps[1]] =
      [copy.journeyContract.steps[1], copy.journeyContract.steps[0]]; },
    (copy) => { copy.journeyContract.sessions[1].label = "third"; },
    (copy) => { copy.journeyContract.restartBoundaryStepId = "restart_open_materials"; },
  ]) {
    const plan = mutate(createPlan(), apply);
    plan.journeyContract.contractSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Object.fromEntries(Object.entries(plan.journeyContract)
        .filter(([key]) => key !== "contractSha256"))));
    plan.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(Formal.stableFormalPlan(plan)));
    assert.throws(() => Formal.validateFormalRunPlan(plan),
      (error) => error.code === "material_shop_formal_journey_contract_invalid");
  }
});

test("formal journey rejects normalized per-step semantic drift with all wrapper digests fresh", () => {
  const plan = createPlan();
  plan.journeyContract.steps[2].driverMethods = ["content.read"];
  plan.journeyContract.stepsSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(plan.journeyContract.steps));
  plan.journeyContract.contractSha256 = Evidence.sha256Text(Evidence.canonicalJson(
    Object.fromEntries(Object.entries(plan.journeyContract)
      .filter(([key]) => key !== "contractSha256"))));
  plan.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(Formal.stableFormalPlan(plan)));
  assert.throws(() => Formal.validateFormalRunPlan(plan),
    (error) => error.code === "material_shop_formal_journey_contract_invalid");
});

test("formal authorization binds fresh formal applicability, never the candidate digest", () => {
  const plan = createPlan();
  const digestDrift = mutate(plan, (copy) => {
    copy.formalApplicabilityBinding.applicabilitySha256 = lower("a");
  });
  digestDrift.planSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Formal.stableFormalPlan(digestDrift)));
  assert.throws(() => Formal.validateFormalRunPlan(digestDrift),
    (error) => error.code === "material_shop_formal_authorization_invalid");

  const targetDrift = mutate(plan, (copy) => {
    copy.formalApplicabilityBinding.selectedUnlockedTarget.catalogIndex = 25;
  });
  targetDrift.planSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Formal.stableFormalPlan(targetDrift)));
  assert.throws(() => Formal.validateFormalRunPlan(targetDrift),
    (error) => error.code === "material_shop_formal_applicability_invalid");
});

test("formal authorization is bound to fresh run, applicability, exact q1 target, and digest", () => {
  const plan = createPlan();
  for (const apply of [
    (copy) => { copy.authorization.runId = "foreign-run"; },
    (copy) => { copy.authorization.target.catalogIndex = 25; },
    (copy) => { copy.authorization.quantity = 2; },
  ]) {
    const changed = mutate(plan, apply);
    changed.authorization.decisionSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Object.fromEntries(Object.entries(changed.authorization)
        .filter(([key]) => key !== "decisionSha256"))));
    changed.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Formal.stableFormalPlan(changed)));
    assert.throws(() => Formal.validateFormalRunPlan(changed),
      (error) => error.code === "material_shop_formal_authorization_invalid");
  }
});

test("formal run id must be fresh and the final plan digest is fail-closed", () => {
  const fx = fixture();
  assert.throws(() => Formal.createFormalRunPlan(
    formalOptions(fx, fx.acceptedCandidate.acceptance.runId)),
  (error) => error.code === "material_shop_formal_run_id_invalid");
  const plan = createPlan();
  plan.planSha256 = lower("0");
  assert.throws(() => Formal.validateFormalRunPlan(plan),
    (error) => error.code === "material_shop_formal_plan_invalid");
});

test("projection-only fixtures cannot remove external admission or claim execution", () => {
  for (const apply of [
    (copy) => { copy.boundaries.externalAdmissionRequired = false; },
    (copy) => { copy.boundaries.formalEntryExecuted = true; },
    (copy) => { copy.boundaries.standardEntryVerified = true; },
  ]) {
    const changed = mutate(createPlan(), apply);
    changed.planSha256 = Evidence.sha256Text(
      Evidence.canonicalJson(Formal.stableFormalPlan(changed)));
    assert.throws(() => Formal.validateFormalRunPlan(changed),
      (error) => error.code === "material_shop_formal_plan_invalid");
  }
});

test("formal plan rejects extra keys instead of silently widening authority", () => {
  const plan = createPlan();
  plan.launch.allowCandidateFallback = true;
  assert.throws(() => Formal.validateFormalRunPlan(plan),
    (error) => error.code === "material_shop_formal_launch_invalid");
});
