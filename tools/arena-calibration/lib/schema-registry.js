"use strict";

const fs = require("fs");
const path = require("path");
const Ajv2020 = require("ajv/dist/2020");

const SCHEMA_DIR = path.resolve(__dirname, "../schemas");

const EMBEDDED_SCHEMA_IDS = Object.freeze({
  "arena-calibration.raw-submission.v1": "arena-calibration.campaign-contracts.v1#/$defs/rawSubmission",
  "arena-calibration.normalized-candidate.v1": "arena-calibration.campaign-contracts.v1#/$defs/normalizedCandidate",
  "arena-calibration.campaign.v1": "arena-calibration.campaign-contracts.v1#/$defs/campaign",
  "arena-calibration.decision-snapshot.v1": "arena-calibration.campaign-contracts.v1#/$defs/decisionSnapshot",
  "arena-calibration.controller-proposal.v1": "arena-calibration.campaign-contracts.v1#/$defs/controllerProposal",
  "arena-calibration.decision-receipt.v1": "arena-calibration.campaign-contracts.v1#/$defs/decisionReceipt",
  "arena-calibration.adjudication.v1": "arena-calibration.campaign-contracts.v1#/$defs/adjudication",
  "arena-calibration.attention-event.v1": "arena-calibration.campaign-contracts.v1#/$defs/attentionEvent",
  "arena-calibration.exception-inbox-item.v1": "arena-calibration.campaign-contracts.v1#/$defs/exceptionInboxItem",
  "arena-calibration.workbook-intake.v1": "arena-calibration.campaign-contracts.v1#/$defs/workbookIntake",
  "arena-calibration.producer-registry.v1": "arena-calibration.campaign-runtime.v1#/$defs/producerRegistry",
  "arena-calibration.idle-grant.v1": "arena-calibration.campaign-runtime.v1#/$defs/idleGrant",
  "arena-calibration.journal-event.v1": "arena-calibration.campaign-runtime.v1#/$defs/journalEvent",
  "arena-calibration.durable-commit.v1": "arena-calibration.campaign-runtime.v1#/$defs/durableCommit",
  "arena-calibration.execution-artifact.v1": "arena-calibration.campaign-runtime.v1#/$defs/executionArtifact",
  "arena-calibration.cohort-compatibility-receipt.v1": "arena-calibration.campaign-runtime.v1#/$defs/cohortCompatibilityReceipt",
  "arena-calibration.campaign-checkpoint.v1": "arena-calibration.campaign-runtime.v1#/$defs/campaignCheckpoint",
  "arena-calibration.shadow-experiment.v1": "arena-calibration.campaign-evaluation.v1#/$defs/shadowExperiment",
  "arena-calibration.shadow-scorecard.v1": "arena-calibration.campaign-evaluation.v1#/$defs/shadowScorecard",
  "arena-calibration.blind-adjudication-packet.v1": "arena-calibration.campaign-evaluation.v1#/$defs/blindAdjudicationPacket",
  "arena-calibration.paired-strength-report.v1": "arena-calibration.campaign-evaluation.v1#/$defs/pairedStrengthReport",
  "arena-calibration.active-sampling-plan.v1": "arena-calibration.campaign-evaluation.v1#/$defs/activeSamplingPlan",
  "arena-calibration.pve-packet.v1": "arena-calibration.campaign-evaluation.v1#/$defs/pvePacket",
  "arena-calibration.pve-response.v1": "arena-calibration.campaign-evaluation.v1#/$defs/pveResponse",
  "arena-calibration.pve-equivalence-response.v1": "arena-calibration.campaign-evaluation.v1#/$defs/pveEquivalenceResponse",
  "arena-calibration.gate-f-plan.v1": "arena-calibration.gate-f.v1#/$defs/gateFPlan",
  "arena-calibration.gate-f-idle-window.v1": "arena-calibration.gate-f.v1#/$defs/idleWindow",
  "arena-calibration.gate-f-decision-evidence.v1": "arena-calibration.gate-f.v1#/$defs/gateFDecisionEvidence",
  "arena-calibration.attention-measurement.v1": "arena-calibration.gate-f.v1#/$defs/attentionMeasurement",
  "arena-calibration.gate-f-shard-receipt.v1": "arena-calibration.gate-f.v1#/$defs/gateFShardReceipt",
  "arena-calibration.gate-f-status.v1": "arena-calibration.gate-f.v1#/$defs/gateFStatus",
  "arena-calibration.exception-review-request.v1": "arena-calibration.exception-review.v1#/$defs/exceptionReviewRequest",
  "arena-calibration.exception-review-result.v1": "arena-calibration.exception-review.v1#/$defs/exceptionReviewResult",
  "arena-calibration.exception-review-receipt.v1": "arena-calibration.exception-review.v1#/$defs/exceptionReviewReceipt",
  "arena-calibration.exception-review-dispatch.v1": "arena-calibration.exception-review.v1#/$defs/exceptionReviewDispatch",
});

let registry = null;

function formatErrors(errors) {
  return (errors || [])
    .map((error) => {
      const location = error.instancePath || "$";
      return `${location} ${error.message || "is invalid"}`;
    })
    .join("; ");
}

function loadSchemaRegistry() {
  if (registry) return registry;

  const ajv = new Ajv2020({
    allErrors: true,
    allowUnionTypes: true,
    strict: false,
    validateSchema: true,
  });
  const files = fs
    .readdirSync(SCHEMA_DIR)
    .filter((name) => name.endsWith(".schema.json"))
    .sort();
  const schemas = files.map((name) => {
    const filePath = path.join(SCHEMA_DIR, name);
    const schema = JSON.parse(fs.readFileSync(filePath, "utf8"));
    if (!schema.$id) throw new Error(`${name} is missing $id`);
    return { name, filePath, schema };
  });

  schemas.forEach(({ name, schema }) => {
    try {
      ajv.addSchema(schema);
    } catch (error) {
      throw new Error(`${name}: schema compilation failed: ${error.message}`);
    }
  });

  registry = { ajv, schemas };
  return registry;
}

function getValidator(schemaId) {
  const { ajv } = loadSchemaRegistry();
  const validate = ajv.getSchema(schemaId) || ajv.getSchema(EMBEDDED_SCHEMA_IDS[schemaId]);
  if (!validate) throw new Error(`unknown JSON Schema id: ${schemaId}`);
  return validate;
}

function validateSchemaInstance(schemaId, value) {
  const validate = getValidator(schemaId);
  const ok = validate(value);
  return {
    ok: Boolean(ok),
    errors: ok ? [] : (validate.errors || []).map((error) => ({ ...error })),
  };
}

function assertSchemaInstance(schemaId, value, label) {
  const result = validateSchemaInstance(schemaId, value);
  if (!result.ok) {
    const prefix = label ? `${label}: ` : "";
    const error = new Error(`${prefix}${schemaId} instance validation failed: ${formatErrors(result.errors)}`);
    error.schemaId = schemaId;
    error.validationErrors = result.errors;
    throw error;
  }
  return value;
}

module.exports = {
  EMBEDDED_SCHEMA_IDS,
  SCHEMA_DIR,
  assertSchemaInstance,
  formatErrors,
  getValidator,
  loadSchemaRegistry,
  validateSchemaInstance,
};
