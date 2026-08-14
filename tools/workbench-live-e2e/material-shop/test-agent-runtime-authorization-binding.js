"use strict";

const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const test = require("node:test");
const Evidence = require("../lib/evidence-artifact");
const Applicability = require("./applicability");
const Protocol = require("./protocol");

const TARGET = Object.freeze({ shopId: "厨师", catalogIndex: 24, itemName: "食用油" });
const BINDING = Object.freeze({
  runId: "a5-auth-binding-a",
  applicabilitySha256: "a".repeat(64),
  target: TARGET,
});

function currentAuthorization(binding) {
  return Protocol.createAgentRuntimeAuthorization({
    evidenceMode: "candidate_capture",
    decisionId: binding.runId + "-qty1",
    runId: binding.runId,
    applicabilitySha256: binding.applicabilitySha256,
    target: binding.target,
  });
}

function expectBindingFailure(authorization, binding) {
  assert.throws(() => Protocol.validateAgentRuntimeAuthorization(
    authorization, "candidate_capture", binding), (error) => {
    assert.equal(error.code, "material_shop_authorization_binding_invalid");
    return true;
  });
}

function protocolApplicability() {
  return {
    applicabilitySha256: BINDING.applicabilitySha256,
    counts: {
      materialCount: 1,
      shopFileCount: 1,
      materialOccurrenceCount: 1,
      uniqueMaterialItemCount: 1,
      requiredInfoOccurrenceCount: 0,
      purchaseLimitOccurrenceCount: 0,
      seedCount: 4,
      seedMaterialPairCount: 4,
      affordableSeedOccurrenceCount: 4,
      atDefaultLimitSeedOccurrenceCount: 0,
    },
    unlocked: { status: "required_candidate_journey", qualifyingOccurrenceCount: 1 },
    locked: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
    max: { status: "not_applicable_current_data", qualifyingOccurrenceCount: 0 },
    selectedUnlockedTarget: TARGET,
  };
}

function createCurrentPlan(applicability, authorization) {
  return Protocol.createAgentRuntimeControlPlan({
    runId: BINDING.runId,
    evidenceMode: "candidate_capture",
    seedSlot: "cf7_agent_a5_material_shop_seed",
    targetSlot: Protocol.AGENT_RUNTIME_SLOT,
    recoverySlot: "cf7_agent_a5_material_shop_recovery",
    scope: {
      head: "1".repeat(40),
      scopeSha256: "2".repeat(64),
      closureSha256: "3".repeat(64),
      materializationSha256: "4".repeat(64),
    },
    applicability,
    authorization,
  });
}

test("current v2 authorization seals run, applicability, and exact selected target", () => {
  const value = currentAuthorization(BINDING);
  assert.equal(value.schema, Protocol.AGENT_RUNTIME_AUTHORIZATION_SCHEMA);
  assert.equal(value.runId, BINDING.runId);
  assert.equal(value.applicabilitySha256, BINDING.applicabilitySha256);
  assert.deepEqual(value.target, TARGET);
  assert.equal(value.quantity, 1);
  assert.equal(value.saleCount, 0);
  assert.equal(value.decisionSha256, Evidence.sha256Text(Evidence.canonicalJson(
    Object.fromEntries(Object.entries(value).filter(([key]) => key !== "decisionSha256")))));
});

test("current v2 authorization rejects run drift", () => {
  expectBindingFailure(currentAuthorization(BINDING), Object.assign({}, BINDING, {
    runId: "a5-auth-binding-b",
  }));
});

test("current v2 authorization rejects applicability drift", () => {
  expectBindingFailure(currentAuthorization(BINDING), Object.assign({}, BINDING, {
    applicabilitySha256: "b".repeat(64),
  }));
});

test("current v2 authorization rejects selected-target drift", () => {
  expectBindingFailure(currentAuthorization(BINDING), Object.assign({}, BINDING, {
    target: { shopId: "前治安官", catalogIndex: 0, itemName: "军用帆布" },
  }));
});

test("a valid current authorization cannot be transplanted to another plan binding", () => {
  const transplanted = currentAuthorization({
    runId: "a5-auth-binding-other",
    applicabilitySha256: "c".repeat(64),
    target: { shopId: "前治安官", catalogIndex: 0, itemName: "军用帆布" },
  });
  expectBindingFailure(transplanted, BINDING);
});

test("current plan summary and validation bind the authorization to the selected target", () => {
  const applicability = protocolApplicability();
  const originalValidate = Applicability.validateApplicability;
  Applicability.validateApplicability = (value) => value;
  try {
    const plan = createCurrentPlan(applicability, currentAuthorization(BINDING));
    assert.deepEqual(plan.applicability.selectedUnlockedTarget, TARGET);
    assert.doesNotThrow(() => Protocol.validateControlPlan(plan));

    const transplanted = currentAuthorization({
      runId: BINDING.runId,
      applicabilitySha256: BINDING.applicabilitySha256,
      target: { shopId: "前治安官", catalogIndex: 0, itemName: "军用帆布" },
    });
    const forged = JSON.parse(JSON.stringify(plan));
    forged.authorization = transplanted;
    const commit = forged.steps.find((step) => step.id === "unlocked_commit");
    commit.authorizationRef = {
      decisionId: transplanted.decisionId,
      decisionSha256: transplanted.decisionSha256,
    };
    forged.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      Protocol.stablePlan(forged)));
    assert.throws(() => Protocol.validateControlPlan(forged), (error) => {
      assert.equal(error.code, "material_shop_authorization_binding_invalid");
      return true;
    });
  } finally {
    Applicability.validateApplicability = originalValidate;
  }
});

test("generic Computer Use plan remains on v1 and frozen t1903 replay bytes remain unchanged", () => {
  const generic = Protocol.createAuthorization({
    evidenceMode: "offline_fixture",
    decisionId: "generic-computer-use-qty1",
  });
  assert.equal(generic.schema, Protocol.AUTHORIZATION_SCHEMA);
  assert.doesNotThrow(() => Protocol.validateAuthorization(generic, "offline_fixture"));
  const artifact = { provider: "offline-fixture" };
  const originalValidate = Applicability.validateApplicability;
  Applicability.validateApplicability = (value) => value;
  try {
    const plan = Protocol.createControlPlan({
      runId: "generic-computer-use",
      evidenceMode: "offline_fixture",
      seedSlot: "cf7_agent_a5_material_shop_seed_test",
      targetSlot: "cf7_agent_a5_material_shop_run_test",
      recoverySlot: "cf7_agent_a5_material_shop_recovery_test",
      scope: {
        head: "1".repeat(40),
        scopeSha256: "2".repeat(64),
        closureSha256: "3".repeat(64),
        materializationSha256: "4".repeat(64),
      },
      applicability: protocolApplicability(),
      environmentCapability: {
        available: true,
        source: "offline_fixture_capability",
        artifact,
        artifactSha256: Evidence.sha256Text(Evidence.canonicalJson(artifact)),
      },
      allowPanelCdpFallback: false,
      authorization: generic,
    });
    assert.equal(plan.schema, Protocol.PLAN_SCHEMA);
    assert.equal(plan.authorization.schema, Protocol.AUTHORIZATION_SCHEMA);
    assert.equal(Object.hasOwn(plan.applicability, "selectedUnlockedTarget"), false);
  } finally {
    Applicability.validateApplicability = originalValidate;
  }

  const frozen = {
    schema: "workbench-live-e2e.material-shop.purchase-authorization.v1",
    decisionId: "a5-material-shop-agent-20260813t1903-qty1",
    source: "operator_authorization",
    oneShot: true,
    stepId: "unlocked_commit",
    quantity: 1,
    saleCount: 0,
    decisionSha256: "5638565aa50c19fa506a8b3adca808292e27ecb9f8b54a1c980c226f9578c445",
  };
  assert.doesNotThrow(() => Protocol.validateAuthorization(frozen, "candidate_capture"));
  const bytes = Buffer.from(JSON.stringify(frozen, null, 2) + "\n", "utf8");
  assert.equal(bytes.length, 349);
  assert.equal(crypto.createHash("sha256").update(bytes).digest("hex"),
    "ab706aff316765640513bf5ddf072f89d51c0dfe080de674bdd7ff7bd3ace66a");
});
