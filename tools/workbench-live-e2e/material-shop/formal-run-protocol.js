"use strict";

const path = require("path");

const Evidence = require("../lib/evidence-artifact");
const RuntimeProducer = require("../crafting/runtime-producer");
const Common = require("./common");
const CandidateProtocol = require("./protocol");

const FORMAL_PLAN_SCHEMA = "workbench-live-e2e.material-shop.formal-run-plan.v1";
const FORMAL_AUTHORIZATION_SCHEMA =
  "workbench-live-e2e.material-shop.formal-purchase-authorization.v1";
const FORMAL_APPLICABILITY_BINDING_SCHEMA =
  "workbench-live-e2e.material-shop.formal-applicability-binding.v1";
const PROMOTION_BINDING_SCHEMA =
  "workbench-live-e2e.material-shop.formal-promotion-binding.v1";
const CANDIDATE_ACCEPTANCE_SCHEMA = "workbench-live-e2e.material-shop.acceptance.v3";
const CONSENSUS_SCHEMA = "cf7-runtime-release-consensus.v2";
const EVIDENCE_MODE = "formal_entry_capture";
const RUNTIME_MODE = "formal_runtime";
const PROCESS_IMAGE_RELATIVE_PATH = "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe";
const CORE_LIBRARY_RELATIVE_PATH = "runtime/CRAZYFLASHER7MercenaryEmpire.Core.dll";
const CORE_RELATIVE_PATH = PROCESS_IMAGE_RELATIVE_PATH;
const ENTRY_RELATIVE_PATH = "automation/start.ps1";
const SESSION_LABELS = Object.freeze(["first", "restart"]);
const FORMAL_TARGET = Object.freeze({ shopId: "厨师", catalogIndex: 24, itemName: "食用油" });
const FORMAL_SLOTS = Object.freeze({
  seedSlot: "cf7_agent_a5_material_shop_seed",
  targetSlot: CandidateProtocol.AGENT_RUNTIME_SLOT,
  recoverySlot: "cf7_agent_a5_material_shop_recovery",
});
const UPPER_SHA256_RE = /^[A-F0-9]{64}$/;
const SOURCE_TAG_RE = /^runtime-build-v2\/[A-Za-z0-9._-]{1,160}$/;
const NORMALIZED_STEP_KEYS = Object.freeze([
  "ordinal", "id", "action", "visibleTarget", "transportClass", "allowedTransports",
  "driverMethods", "requiresCapture", "requiresCommitAuthorization",
]);

const ACCEPTANCE_KEYS = Object.freeze([
  "schema", "acceptedAt", "status", "deployment", "runId", "planSha256",
  "preparationSha256", "closureSha256", "materializationSha256", "buildSha256",
  "externalToolchainSha256", "candidateIdentitySha256", "applicabilitySha256",
  "rawSha256", "operationTerminalSha256", "journeyEvidenceSha256",
  "settlementSha256", "cloneReleaseSha256", "staticGateSha256",
  "reviewRequestSha256", "reviewReceiptSha256", "captureSetSha256", "boundaries",
  "acceptanceSha256",
]);
const ACCEPTANCE_SHA_KEYS = Object.freeze(ACCEPTANCE_KEYS.filter((key) =>
  key.endsWith("Sha256")));

function clone(value) {
  if (value === undefined) return undefined;
  return JSON.parse(JSON.stringify(value));
}

function unsignedDigest(value, digestKey) {
  const unsigned = Object.assign({}, value);
  delete unsigned[digestKey];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function samePath(left, right) {
  if (typeof left !== "string" || typeof right !== "string"
      || !path.isAbsolute(left) || !path.isAbsolute(right)) return false;
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function validateBoundFile(value, locator, code) {
  Common.exactKeys(value, ["locator", "sha256", "bytes"], code, "formal_protocol");
  if (value.locator !== locator || !Common.SHA256_RE.test(String(value.sha256 || ""))
      || !Number.isSafeInteger(value.bytes) || value.bytes < 1) {
    Common.fail(code, "formal_protocol", "candidate producer file binding is malformed");
  }
  return value;
}

function validateCandidateProducerBinding(value, identity) {
  Common.exactKeys(value, ["schema", "candidateRoot", "metadata", "manifest",
    "builderLabel", "createdAtUtc", "producerInputsSha256", "artifactSourceHash",
    "producerRecipeHash", "toolchainLockHash", "buildIdentityHash",
    "payloadClosureHash", "payloadFileCount", "processImage", "coreLibrary",
    "evidenceSha256"], "material_shop_formal_candidate_invalid", "formal_protocol");
  validateBoundFile(value.metadata, "candidate:runtime-build-metadata.v2.json",
    "material_shop_formal_candidate_invalid");
  validateBoundFile(value.manifest, "candidate:runtime/cf7-runtime-manifest.tsv",
    "material_shop_formal_candidate_invalid");
  validateBoundFile(value.processImage, "candidate:" + PROCESS_IMAGE_RELATIVE_PATH,
    "material_shop_formal_candidate_invalid");
  validateBoundFile(value.coreLibrary, "candidate:" + CORE_LIBRARY_RELATIVE_PATH,
    "material_shop_formal_candidate_invalid");
  if (value.schema !== RuntimeProducer.CANDIDATE_PRODUCER_SCHEMA
      || !samePath(value.candidateRoot, identity.installRoot)
      || typeof value.builderLabel !== "string" || !value.builderLabel.trim()
      || !Number.isFinite(Date.parse(value.createdAtUtc))
      || !Common.SHA256_RE.test(String(value.producerInputsSha256 || ""))
      || !UPPER_SHA256_RE.test(String(value.artifactSourceHash || ""))
      || !UPPER_SHA256_RE.test(String(value.producerRecipeHash || ""))
      || !UPPER_SHA256_RE.test(String(value.toolchainLockHash || ""))
      || value.buildIdentityHash !== identity.buildIdentity
      || value.payloadClosureHash !== identity.payloadClosure
      || !Number.isSafeInteger(value.payloadFileCount) || value.payloadFileCount < 1
      || String(value.coreLibrary.sha256).toUpperCase() !== identity.coreSha256
      || value.evidenceSha256 !== unsignedDigest(value, "evidenceSha256")) {
    Common.fail("material_shop_formal_candidate_invalid", "formal_protocol",
      "candidate producer binding does not preserve exact Core EXE and DLL identities");
  }
  return value;
}

// This verifies the closed projection and its internal hashes; a preparer must still load the
// accepted artifacts from their authoritative closure before external admission.
function validateAcceptedCandidate(value) {
  Common.exactKeys(value, ["acceptance", "candidateIdentity", "candidateProducerBinding",
    "controlPlan"],
    "material_shop_formal_candidate_invalid", "formal_protocol");
  const acceptance = value.acceptance;
  Common.exactKeys(acceptance, ACCEPTANCE_KEYS,
    "material_shop_formal_candidate_invalid", "formal_protocol");
  Common.exactKeys(acceptance.boundaries, ["realGuiExecuted", "candidateBuilt",
    "candidateExecuted", "e2eVerified", "promoted", "standardEntryVerified"],
  "material_shop_formal_candidate_invalid", "formal_protocol");
  if (acceptance.schema !== CANDIDATE_ACCEPTANCE_SCHEMA
      || !Common.ID_RE.test(String(acceptance.runId || ""))
      || !Number.isFinite(Date.parse(acceptance.acceptedAt))
      || acceptance.status !== "e2e_verified"
      || acceptance.deployment !== "NOT_DEPLOYED"
      || ACCEPTANCE_SHA_KEYS.some((key) =>
        !Common.SHA256_RE.test(String(acceptance[key] || "")))
      || acceptance.acceptanceSha256 !== unsignedDigest(acceptance, "acceptanceSha256")
      || acceptance.boundaries.realGuiExecuted !== true
      || acceptance.boundaries.candidateBuilt !== true
      || acceptance.boundaries.candidateExecuted !== true
      || acceptance.boundaries.e2eVerified !== true
      || acceptance.boundaries.promoted !== false
      || acceptance.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_formal_candidate_invalid", "formal_protocol",
      "formal planning requires one exact accepted candidate acceptance envelope");
  }

  const identity = value.candidateIdentity;
  Common.exactKeys(identity, ["runtimeMode", "processPath", "coreSha256",
    "buildIdentity", "payloadClosure", "installRoot"],
  "material_shop_formal_candidate_invalid", "formal_protocol");
  const expectedProcess = path.join(identity.installRoot || "", CORE_RELATIVE_PATH);
  if (identity.runtimeMode !== "isolated_candidate"
      || typeof identity.installRoot !== "string" || !path.isAbsolute(identity.installRoot)
      || typeof identity.processPath !== "string" || !path.isAbsolute(identity.processPath)
      || !samePath(identity.processPath, expectedProcess)
      || !UPPER_SHA256_RE.test(String(identity.coreSha256 || ""))
      || !UPPER_SHA256_RE.test(String(identity.buildIdentity || ""))
      || !UPPER_SHA256_RE.test(String(identity.payloadClosure || ""))
      || Evidence.sha256Text(Evidence.canonicalJson(identity))
        !== acceptance.candidateIdentitySha256) {
    Common.fail("material_shop_formal_candidate_invalid", "formal_protocol",
      "accepted candidate identity is malformed or detached from its acceptance");
  }
  validateCandidateProducerBinding(value.candidateProducerBinding, identity);

  const controlPlan = value.controlPlan;
  CandidateProtocol.validateAgentRuntimeControlPlan(controlPlan);
  if (controlPlan.schema !== CandidateProtocol.AGENT_RUNTIME_PLAN_SCHEMA
      || controlPlan.runId !== acceptance.runId
      || controlPlan.planSha256 !== acceptance.planSha256
      || controlPlan.applicability.applicabilitySha256 !== acceptance.applicabilitySha256
      || controlPlan.steps.length !== 24
      || Evidence.canonicalJson(controlPlan.steps.map((step) => step.id))
        !== Evidence.canonicalJson(CandidateProtocol.AGENT_RUNTIME_BASE_STEPS)
      || Evidence.canonicalJson(controlPlan.applicability.selectedUnlockedTarget)
        !== Evidence.canonicalJson(FORMAL_TARGET)) {
    Common.fail("material_shop_formal_candidate_invalid", "formal_protocol",
      "accepted candidate must carry the exact current 24-step control plan named by acceptance");
  }
  return value;
}

// Shape/binding only. A formal preparer must derive this projection from the official
// consensus bytes and a successful strict-v2 promotion verification receipt.
function validatePromotionProjection(value) {
  Common.exactKeys(value, ["schema", "consensusSchema", "status", "sourceCommitOid",
    "releaseTreeOid", "sourceTag", "requestId", "buildIdentityHash",
    "payloadClosureHash", "processImageSha256", "coreLibrarySha256",
    "policyReceiptSha256", "consensusSha256", "promotedAtUtc"],
  "material_shop_formal_promotion_invalid", "formal_protocol");
  if (value.schema !== PROMOTION_BINDING_SCHEMA
      || value.consensusSchema !== CONSENSUS_SCHEMA || value.status !== "promoted"
      || !Common.GIT_OID_RE.test(String(value.sourceCommitOid || ""))
      || !Common.GIT_OID_RE.test(String(value.releaseTreeOid || ""))
      || !SOURCE_TAG_RE.test(String(value.sourceTag || ""))
      || !UPPER_SHA256_RE.test(String(value.requestId || ""))
      || !UPPER_SHA256_RE.test(String(value.buildIdentityHash || ""))
      || !UPPER_SHA256_RE.test(String(value.payloadClosureHash || ""))
      || !UPPER_SHA256_RE.test(String(value.processImageSha256 || ""))
      || !UPPER_SHA256_RE.test(String(value.coreLibrarySha256 || ""))
      || !UPPER_SHA256_RE.test(String(value.policyReceiptSha256 || ""))
      || !Common.SHA256_RE.test(String(value.consensusSha256 || ""))
      || !Number.isFinite(Date.parse(value.promotedAtUtc))) {
    Common.fail("material_shop_formal_promotion_invalid", "formal_protocol",
      "formal planning requires one exact promoted v2 source and runtime identity");
  }
  return value;
}

function validateFormalApplicabilityBinding(value, promotion) {
  Common.exactKeys(value, ["schema", "source", "sourceCommitOid", "buildIdentityHash",
    "payloadClosureHash", "applicabilitySha256", "selectedUnlockedTarget",
    "verificationReceiptSha256"],
  "material_shop_formal_applicability_invalid", "formal_protocol");
  Common.exactKeys(value.selectedUnlockedTarget, ["shopId", "catalogIndex", "itemName"],
    "material_shop_formal_applicability_invalid", "formal_protocol");
  if (value.schema !== FORMAL_APPLICABILITY_BINDING_SCHEMA
      || value.source !== "fresh_promoted_canonical_root_capture"
      || !Common.GIT_OID_RE.test(String(value.sourceCommitOid || ""))
      || !UPPER_SHA256_RE.test(String(value.buildIdentityHash || ""))
      || !UPPER_SHA256_RE.test(String(value.payloadClosureHash || ""))
      || !Common.SHA256_RE.test(String(value.applicabilitySha256 || ""))
      || !Common.SHA256_RE.test(String(value.verificationReceiptSha256 || ""))
      || Evidence.canonicalJson(value.selectedUnlockedTarget)
        !== Evidence.canonicalJson(FORMAL_TARGET)
      || (promotion && (value.sourceCommitOid !== promotion.sourceCommitOid
        || value.buildIdentityHash !== promotion.buildIdentityHash
        || value.payloadClosureHash !== promotion.payloadClosureHash))) {
    Common.fail("material_shop_formal_applicability_invalid", "formal_protocol",
      "formal applicability must be a fresh canonical-root binding for the promoted runtime");
  }
  return value;
}

function normalizeJourneyStep(step) {
  return Object.fromEntries(NORMALIZED_STEP_KEYS.map((key) => [key, clone(step[key])]));
}

function stableJourneyContract(value) {
  const stable = Object.assign({}, value);
  delete stable.contractSha256;
  return stable;
}

function createJourneyContract(acceptedCandidate) {
  validateAcceptedCandidate(acceptedCandidate);
  const controlPlan = acceptedCandidate.controlPlan;
  const stepIds = controlPlan.steps.map((step) => step.id);
  const restartIndex = stepIds.indexOf("restart_candidate");
  if (restartIndex < 1 || restartIndex >= stepIds.length - 1) {
    Common.fail("material_shop_formal_journey_contract_invalid", "formal_protocol",
      "the A5 restart boundary is missing from the 24-step journey");
  }
  // Candidate authorizationRef is run-specific. Its authorization requirement remains in
  // each normalized step; the fresh formal authorization is bound separately by the plan.
  const steps = controlPlan.steps.map(normalizeJourneyStep);
  const value = {
    sourcePlanSchema: controlPlan.schema,
    sourcePlanSha256: controlPlan.planSha256,
    stepCount: steps.length,
    steps,
    stepsSha256: Evidence.sha256Text(Evidence.canonicalJson(steps)),
    recipeJump: clone(controlPlan.recipeJump),
    recipeJumpSha256: Evidence.sha256Text(
      Evidence.canonicalJson(controlPlan.recipeJump)),
    purchase: { target: clone(FORMAL_TARGET), quantity: 1, saleCount: 0,
      commitStepId: "unlocked_commit" },
    sessions: [
      { label: "first", stepIds: stepIds.slice(0, restartIndex) },
      { label: "restart", stepIds: stepIds.slice(restartIndex + 1) },
    ],
    restartBoundaryStepId: "restart_candidate",
  };
  value.contractSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(stableJourneyContract(value)));
  return validateJourneyContract(value, acceptedCandidate);
}

function validateJourneyContract(value, acceptedCandidate) {
  validateAcceptedCandidate(acceptedCandidate);
  Common.exactKeys(value, ["sourcePlanSchema", "sourcePlanSha256", "stepCount", "steps",
    "stepsSha256", "recipeJump", "recipeJumpSha256", "purchase", "sessions",
    "restartBoundaryStepId", "contractSha256"],
  "material_shop_formal_journey_contract_invalid", "formal_protocol");
  Common.exactKeys(value.purchase, ["target", "quantity", "saleCount", "commitStepId"],
    "material_shop_formal_journey_contract_invalid", "formal_protocol");
  Common.exactKeys(value.purchase.target, ["shopId", "catalogIndex", "itemName"],
    "material_shop_formal_journey_contract_invalid", "formal_protocol");
  const controlPlan = acceptedCandidate.controlPlan;
  const expectedIds = controlPlan.steps.map((step) => step.id);
  const expectedSteps = controlPlan.steps.map(normalizeJourneyStep);
  const restartIndex = expectedIds.indexOf("restart_candidate");
  const expectedSessions = [
    { label: "first", stepIds: expectedIds.slice(0, restartIndex) },
    { label: "restart", stepIds: expectedIds.slice(restartIndex + 1) },
  ];
  if (value.sourcePlanSchema !== controlPlan.schema
      || value.sourcePlanSha256 !== controlPlan.planSha256
      || value.stepCount !== 24
      || Evidence.canonicalJson(value.steps) !== Evidence.canonicalJson(expectedSteps)
      || value.stepsSha256 !== Evidence.sha256Text(Evidence.canonicalJson(expectedSteps))
      || Evidence.canonicalJson(value.recipeJump)
        !== Evidence.canonicalJson(controlPlan.recipeJump)
      || value.recipeJumpSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(controlPlan.recipeJump))
      || Evidence.canonicalJson(value.purchase.target) !== Evidence.canonicalJson(FORMAL_TARGET)
      || value.purchase.quantity !== 1 || value.purchase.saleCount !== 0
      || value.purchase.commitStepId !== "unlocked_commit"
      || Evidence.canonicalJson(value.sessions) !== Evidence.canonicalJson(expectedSessions)
      || value.restartBoundaryStepId !== "restart_candidate"
      || value.contractSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableJourneyContract(value)))) {
    Common.fail("material_shop_formal_journey_contract_invalid", "formal_protocol",
      "formal entry must replay the accepted candidate's exact normalized 24-step journey");
  }
  value.steps.forEach((step) => {
    Common.exactKeys(step, NORMALIZED_STEP_KEYS,
      "material_shop_formal_journey_contract_invalid", "formal_protocol");
  });
  value.sessions.forEach((session) => {
    Common.exactKeys(session, ["label", "stepIds"],
      "material_shop_formal_journey_contract_invalid", "formal_protocol");
  });
  return value;
}

// This helper creates only the projection emitted after an explicit prepare flag. Real
// authority and one-shot consumption belong to a future preparer plus operation lease.
function createFormalAuthorization(options) {
  const settings = options || {};
  const value = {
    schema: FORMAL_AUTHORIZATION_SCHEMA,
    decisionId: String(settings.decisionId || ""),
    source: "explicit_prepare_flag_authorization",
    preparerInputSha256: String(settings.preparerInputSha256 || ""),
    nonce: String(settings.nonce || ""),
    oneShot: true,
    runId: String(settings.runId || ""),
    applicabilitySha256: String(settings.applicabilitySha256 || ""),
    target: clone(FORMAL_TARGET),
    stepId: "unlocked_commit",
    quantity: 1,
    saleCount: 0,
  };
  value.decisionSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateFormalAuthorization(value, {
    runId: value.runId, applicabilitySha256: value.applicabilitySha256,
  });
}

function validateFormalAuthorization(value, binding) {
  Common.exactKeys(value, ["schema", "decisionId", "source", "preparerInputSha256", "nonce",
    "oneShot", "runId",
    "applicabilitySha256", "target", "stepId", "quantity", "saleCount",
    "decisionSha256"],
  "material_shop_formal_authorization_invalid", "formal_protocol");
  Common.exactKeys(value.target, ["shopId", "catalogIndex", "itemName"],
    "material_shop_formal_authorization_invalid", "formal_protocol");
  if (value.schema !== FORMAL_AUTHORIZATION_SCHEMA
      || !Common.ID_RE.test(String(value.decisionId || ""))
      || !Common.SHA256_RE.test(String(value.preparerInputSha256 || ""))
      || !Common.ID_RE.test(String(value.nonce || ""))
      || !Common.ID_RE.test(String(value.runId || ""))
      || !Common.SHA256_RE.test(String(value.applicabilitySha256 || ""))
      || value.source !== "explicit_prepare_flag_authorization"
      || value.oneShot !== true
      || Evidence.canonicalJson(value.target) !== Evidence.canonicalJson(FORMAL_TARGET)
      || value.stepId !== "unlocked_commit" || value.quantity !== 1
      || value.saleCount !== 0
      || value.decisionSha256 !== unsignedDigest(value, "decisionSha256")
      || (binding && (value.runId !== binding.runId
        || value.applicabilitySha256 !== binding.applicabilitySha256))) {
    Common.fail("material_shop_formal_authorization_invalid", "formal_protocol",
      "formal q1 purchase authorization is malformed or detached");
  }
  return value;
}

function createLaunchContract(canonicalRoot, promotion) {
  return {
    projectRoot: canonicalRoot,
    entryRelativePath: ENTRY_RELATIVE_PATH,
    arguments: ["-UnattendedAdapter", "jsonl", "-UnattendedSlot",
      CandidateProtocol.AGENT_RUNTIME_SLOT],
    runtimeMode: RUNTIME_MODE,
    candidateRoot: null,
    candidateId: null,
    expectedProcessPath: path.join(canonicalRoot, PROCESS_IMAGE_RELATIVE_PATH),
    expectedProcessImageSha256: promotion.processImageSha256,
    expectedCoreLibrarySha256: promotion.coreLibrarySha256,
    expectedBuildIdentity: promotion.buildIdentityHash,
    expectedPayloadClosure: promotion.payloadClosureHash,
  };
}

function validateLaunchContract(value, canonicalRoot, promotion) {
  Common.exactKeys(value, ["projectRoot", "entryRelativePath", "arguments", "runtimeMode",
    "candidateRoot", "candidateId", "expectedProcessPath", "expectedProcessImageSha256",
    "expectedCoreLibrarySha256", "expectedBuildIdentity", "expectedPayloadClosure"],
  "material_shop_formal_launch_invalid", "formal_protocol");
  const expectedArguments = ["-UnattendedAdapter", "jsonl", "-UnattendedSlot",
    CandidateProtocol.AGENT_RUNTIME_SLOT];
  if (!samePath(value.projectRoot, canonicalRoot)
      || value.entryRelativePath !== ENTRY_RELATIVE_PATH
      || Evidence.canonicalJson(value.arguments) !== Evidence.canonicalJson(expectedArguments)
      || value.runtimeMode !== RUNTIME_MODE || value.candidateRoot !== null
      || value.candidateId !== null
      || !samePath(value.expectedProcessPath,
        path.join(canonicalRoot, PROCESS_IMAGE_RELATIVE_PATH))
      || value.expectedProcessImageSha256 !== promotion.processImageSha256
      || value.expectedCoreLibrarySha256 !== promotion.coreLibrarySha256
      || value.expectedBuildIdentity !== promotion.buildIdentityHash
      || value.expectedPayloadClosure !== promotion.payloadClosureHash) {
    Common.fail("material_shop_formal_launch_invalid", "formal_protocol",
      "formal A5 launch must use the canonical root with no candidate selector");
  }
  return value;
}

function stableFormalPlan(value) {
  const stable = Object.assign({}, value);
  delete stable.planSha256;
  return stable;
}

function createFormalRunPlan(options) {
  const settings = options || {};
  const canonicalRoot = Common.assertCanonicalRoot(settings.canonicalRoot || Common.CANONICAL_ROOT);
  const acceptedCandidate = clone(settings.acceptedCandidate);
  const promotion = clone(settings.promotion);
  validateAcceptedCandidate(acceptedCandidate);
  validatePromotionProjection(promotion);
  const formalApplicabilityBinding = clone(settings.formalApplicabilityBinding);
  const identity = acceptedCandidate.candidateIdentity;
  const producer = acceptedCandidate.candidateProducerBinding;
  if (identity.buildIdentity !== promotion.buildIdentityHash
      || identity.payloadClosure !== promotion.payloadClosureHash
      || identity.coreSha256 !== promotion.coreLibrarySha256
      || String(producer.processImage.sha256).toUpperCase()
        !== promotion.processImageSha256
      || String(producer.coreLibrary.sha256).toUpperCase()
        !== promotion.coreLibrarySha256) {
    Common.fail("material_shop_formal_promotion_identity_mismatch", "formal_protocol",
      "promotion identity, payload closure, and Core bytes must equal the accepted candidate");
  }
  validateFormalApplicabilityBinding(formalApplicabilityBinding, promotion);
  const runId = String(settings.runId || "");
  if (!Common.ID_RE.test(runId) || runId === acceptedCandidate.acceptance.runId) {
    Common.fail("material_shop_formal_run_id_invalid", "formal_protocol",
      "formal entry requires a fresh run id distinct from the accepted candidate run");
  }
  const slots = Common.assertDedicatedSlots(
    settings.seedSlot || FORMAL_SLOTS.seedSlot,
    settings.targetSlot || FORMAL_SLOTS.targetSlot,
    settings.recoverySlot || FORMAL_SLOTS.recoverySlot);
  const authorization = clone(settings.authorization);
  validateFormalAuthorization(authorization, {
    runId,
    applicabilitySha256: formalApplicabilityBinding.applicabilitySha256,
  });
  const value = {
    schema: FORMAL_PLAN_SCHEMA,
    runId,
    evidenceMode: EVIDENCE_MODE,
    sourceFixtureSlot: Common.SOURCE_FIXTURE_SLOT,
    slots,
    acceptedCandidate,
    promotion,
    formalApplicabilityBinding,
    journeyContract: createJourneyContract(acceptedCandidate),
    authorization,
    launch: createLaunchContract(canonicalRoot, promotion),
    boundaries: { controllerMayCallBusinessApis: false,
      acceptanceProjectionBound: true, promotionProjectionBound: true,
      formalApplicabilityProjectionBound: true, authorizationProjectionBound: true,
      externalAdmissionRequired: true,
      formalEntryExecuted: false, standardEntryVerified: false },
  };
  value.planSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableFormalPlan(value)));
  return validateFormalRunPlan(value);
}

function validateFormalRunPlan(value) {
  Common.exactKeys(value, ["schema", "runId", "evidenceMode", "sourceFixtureSlot",
    "slots", "acceptedCandidate", "promotion", "formalApplicabilityBinding",
    "journeyContract", "authorization", "launch", "boundaries", "planSha256"],
  "material_shop_formal_plan_invalid", "formal_protocol");
  if (value.schema !== FORMAL_PLAN_SCHEMA || !Common.ID_RE.test(String(value.runId || ""))
      || value.evidenceMode !== EVIDENCE_MODE
      || value.sourceFixtureSlot !== Common.SOURCE_FIXTURE_SLOT) {
    Common.fail("material_shop_formal_plan_invalid", "formal_protocol",
      "formal run plan envelope is malformed");
  }
  Common.exactKeys(value.slots, ["seedSlot", "targetSlot", "recoverySlot"],
    "material_shop_formal_plan_invalid", "formal_protocol");
  Common.assertDedicatedSlots(value.slots.seedSlot, value.slots.targetSlot,
    value.slots.recoverySlot);
  if (Evidence.canonicalJson(value.slots) !== Evidence.canonicalJson(FORMAL_SLOTS)) {
    Common.fail("material_shop_formal_plan_invalid", "formal_protocol",
      "formal run must use the exact dedicated A5 clone slots");
  }
  validateAcceptedCandidate(value.acceptedCandidate);
  validatePromotionProjection(value.promotion);
  if (value.runId === value.acceptedCandidate.acceptance.runId
      || value.acceptedCandidate.candidateIdentity.buildIdentity
        !== value.promotion.buildIdentityHash
      || value.acceptedCandidate.candidateIdentity.payloadClosure
        !== value.promotion.payloadClosureHash
      || value.acceptedCandidate.candidateIdentity.coreSha256
        !== value.promotion.coreLibrarySha256
      || String(value.acceptedCandidate.candidateProducerBinding.processImage.sha256)
        .toUpperCase() !== value.promotion.processImageSha256
      || String(value.acceptedCandidate.candidateProducerBinding.coreLibrary.sha256)
        .toUpperCase() !== value.promotion.coreLibrarySha256) {
    Common.fail("material_shop_formal_promotion_identity_mismatch", "formal_protocol",
      "formal plan is detached from the accepted and promoted identical runtime");
  }
  validateFormalApplicabilityBinding(value.formalApplicabilityBinding, value.promotion);
  validateJourneyContract(value.journeyContract, value.acceptedCandidate);
  validateFormalAuthorization(value.authorization, {
    runId: value.runId,
    applicabilitySha256: value.formalApplicabilityBinding.applicabilitySha256,
  });
  if (!value.launch || typeof value.launch.projectRoot !== "string"
      || !path.isAbsolute(value.launch.projectRoot)) {
    Common.fail("material_shop_formal_launch_invalid", "formal_protocol",
      "formal launch must name the absolute canonical project root");
  }
  const canonicalRoot = Common.assertCanonicalRoot(value.launch.projectRoot);
  validateLaunchContract(value.launch, canonicalRoot, value.promotion);
  Common.exactKeys(value.boundaries, ["controllerMayCallBusinessApis",
    "acceptanceProjectionBound", "promotionProjectionBound",
    "formalApplicabilityProjectionBound", "authorizationProjectionBound",
    "externalAdmissionRequired", "formalEntryExecuted", "standardEntryVerified"],
  "material_shop_formal_plan_invalid", "formal_protocol");
  if (value.boundaries.controllerMayCallBusinessApis !== false
      || value.boundaries.acceptanceProjectionBound !== true
      || value.boundaries.promotionProjectionBound !== true
      || value.boundaries.formalApplicabilityProjectionBound !== true
      || value.boundaries.authorizationProjectionBound !== true
      || value.boundaries.externalAdmissionRequired !== true
      || value.boundaries.formalEntryExecuted !== false
      || value.boundaries.standardEntryVerified !== false
      || value.planSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableFormalPlan(value)))) {
    Common.fail("material_shop_formal_plan_invalid", "formal_protocol",
      "unexecuted formal plan overclaims execution or has digest drift");
  }
  return value;
}

module.exports = {
  CANDIDATE_ACCEPTANCE_SCHEMA,
  CONSENSUS_SCHEMA,
  CORE_LIBRARY_RELATIVE_PATH,
  CORE_RELATIVE_PATH,
  ENTRY_RELATIVE_PATH,
  EVIDENCE_MODE,
  FORMAL_APPLICABILITY_BINDING_SCHEMA,
  FORMAL_AUTHORIZATION_SCHEMA,
  FORMAL_PLAN_SCHEMA,
  FORMAL_SLOTS,
  FORMAL_TARGET,
  PROMOTION_BINDING_SCHEMA,
  PROCESS_IMAGE_RELATIVE_PATH,
  RUNTIME_MODE,
  SESSION_LABELS,
  createFormalAuthorization,
  createFormalRunPlan,
  createJourneyContract,
  stableFormalPlan,
  validateAcceptedCandidate,
  validateCandidateProducerBinding,
  validateFormalApplicabilityBinding,
  validateFormalAuthorization,
  validateFormalRunPlan,
  validateJourneyContract,
  validateLaunchContract,
  validatePromotionProjection,
};
