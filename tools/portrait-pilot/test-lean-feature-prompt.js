#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const { createPrompt } = require("./run-visual-pilot");

const digest = "A".repeat(64);
const manifest = {
  phase: "P3_FEATURE_REFINEMENT",
  batchId: "fixture-batch",
  sourceDigest: digest,
  featureContract: {
    global: ["This compact accumulated human contract is transmitted once for the selection stage."],
    geometry: {
      mustIncludeSafeMargin: 0.1,
      modes: {
        head_closeup: {},
        feature_closeup: {},
        feature_group: {},
        full_subject: {},
      },
    },
  },
  humanPreferenceCalibration: {
    coverage: {
      decisionCount: 108,
      passAnchorCount: 19,
      guidedCorrectionCount: 87,
      anomalyCount: 1,
    },
  },
};
const rows = [{
  reviewCode: "R01",
  reviewKey: "fixture::default",
  portraitRef: "fixture",
  variantKey: "default",
  variantResolution: "default_only",
  category: "humanoid",
  humanFeedback: { note: "head first" },
  intentPolicy: null,
  oldReference: null,
  candidates: [{
    candidateId: "e01-c01",
    frame: 1,
    width: 200,
    height: 300,
    vectorArtifact: { sha256: digest },
  }],
}];
const imageInputs = [
  { role: "current_candidates", artifact: { sha256: digest } },
  { role: "retrieved_human_preferences_not_candidates", artifact: { sha256: "B".repeat(64) } },
];
const result = createPrompt(
  manifest,
  rows,
  "proposal",
  "fixture-model-batch",
  { sha256: digest },
  imageInputs,
);

assert.deepEqual(result.input.globalFeatureContract, manifest.featureContract.global);
assert.deepEqual(result.input.humanEvidenceSummary, {
  decisionCount: 108,
  passAnchorCount: 19,
  guidedCorrectionCount: 87,
  anomalyCount: 1,
});
assert.match(result.prompt, /smallest visible feature/);
assert.match(result.prompt, /every extra strip of torso/);
assert.equal(result.prompt.split("compact accumulated human contract").length - 1, 1);
assert.doesNotMatch(result.prompt, /featureWidth=\(fx1-fx0\)/);
assert.doesNotMatch(result.prompt, /complete human review rejected/);
assert.ok(result.prompt.length < 6500, `lean fixture prompt unexpectedly long: ${result.prompt.length}`);

const localizationRows = [{
  ...rows[0],
  lockedCandidateId: "e01-c01",
  localizationView: {
    attachmentIndex: 1,
    artifact: { sha256: digest },
    viewSize: [1600, 2048],
  },
}];
const localization = createPrompt(
  manifest,
  localizationRows,
  "proposal",
  "fixture-localization-batch",
  { sha256: digest },
  [{ role: "selected_high_resolution_view:R01", artifact: { sha256: digest } }],
);
assert.equal(localization.input.globalFeatureContract, null);
assert.equal(localization.input.rows[0].candidates.length, 1);
assert.match(localization.prompt, /frame selection is already locked/);
assert.match(localization.prompt, /smallest visible feature/);
assert.doesNotMatch(localization.prompt, /compact accumulated human contract/);

process.stdout.write(`${JSON.stringify({
  status: "two_stage_feature_prompt_test_passed",
  selectionPromptBytes: Buffer.byteLength(result.prompt, "utf8"),
  localizationPromptBytes: Buffer.byteLength(localization.prompt, "utf8"),
})}\n`);
