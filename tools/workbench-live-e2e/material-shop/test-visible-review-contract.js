#!/usr/bin/env node
"use strict";

const assert = require("assert");
const Accept = require("./accept-run");
const Evidence = require("../lib/evidence-artifact");
const Protocol = require("./protocol");

const CAPTURE_STEPS = Object.freeze([
  "open_materials",
  "materials_visual_current_window",
  "materials_keyboard",
  "materials_recipe_jump",
  "recipe_escape_close",
  "recipe_reopen_materials",
  "materials_multi_variant",
  "materials_portraits",
  "ordinary_close",
  "reopen_materials",
  "unlocked_exact_focus",
  "unlocked_intent_qty1",
  "unlocked_settlement",
  "unlocked_return",
  "restart_open_materials",
  "restart_readback",
]);

let passed = 0;

function test(name, body) {
  body();
  passed += 1;
  process.stdout.write("ok " + passed + " - " + name + "\n");
}

function agentPlan() {
  return { schema: Protocol.AGENT_RUNTIME_PLAN_SCHEMA,
    steps: CAPTURE_STEPS.map((id) => ({ id, requiresCapture: true }))
      .concat([{ id: "trusted_runner_final_shutdown", requiresCapture: false }]) };
}

function expectClaimSetFailure(body) {
  assert.throws(body, (error) => error
    && error.code === "material_shop_review_claim_set_invalid");
}

function sealReceipt(value) {
  const sealed = JSON.parse(JSON.stringify(value));
  delete sealed.reviewReceiptSha256;
  sealed.reviewReceiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(sealed));
  return sealed;
}

test("new Agent Runtime requests use review-request v4 and visible-only scope", () => {
  const plan = agentPlan();
  assert.strictEqual(Accept.reviewRequestSchema(plan), Accept.REVIEW_REQUEST_SCHEMA);
  assert.strictEqual(Accept.REVIEW_REQUEST_SCHEMA,
    "workbench-live-e2e.material-shop.review-request.v4");
  assert.strictEqual(Accept.reviewScope(plan), Accept.AGENT_RUNTIME_REVIEW_SCOPE);
});

test("legacy non-Agent replay remains explicit v3", () => {
  const plan = { schema: Protocol.PLAN_SCHEMA, steps: [] };
  assert.strictEqual(Accept.reviewRequestSchema(plan), Accept.LEGACY_REVIEW_REQUEST_SCHEMA);
  assert.strictEqual(Accept.LEGACY_REVIEW_REQUEST_SCHEMA,
    "workbench-live-e2e.material-shop.review-request.v3");
  assert.strictEqual(Accept.reviewScope(plan), Accept.LEGACY_REVIEW_SCOPE);
});

test("Agent visible claims exactly cover all sixteen capture steps once", () => {
  const claims = Accept.reviewClaims(agentPlan());
  const flattened = claims.flatMap((claim) => claim.captureSteps);
  assert.strictEqual(claims.length, 14);
  assert.strictEqual(flattened.length, CAPTURE_STEPS.length);
  assert.strictEqual(new Set(flattened).size, CAPTURE_STEPS.length);
  assert.deepStrictEqual(new Set(flattened), new Set(CAPTURE_STEPS));
});

test("Agent claim ids state visible content and retain portrait review", () => {
  const claims = Accept.reviewClaims(agentPlan());
  const ids = claims.map((claim) => claim.claimId);
  assert(ids.includes("reachable_enemy_and_shop_portraits_visible"));
  ids.forEach((id) => assert(!/(?:native|input|keyboard|restart|shutdown|close|transition|focus)/i
    .test(id), id));
});

test("a claim cannot point at a non-capture step", () => {
  const plan = agentPlan();
  plan.steps.find((step) => step.id === "materials_portraits").requiresCapture = false;
  expectClaimSetFailure(() => Accept.reviewClaims(plan));
});

test("a foreign required capture cannot escape the claim union", () => {
  const plan = agentPlan();
  plan.steps.push({ id: "foreign_visible_capture", requiresCapture: true });
  expectClaimSetFailure(() => Accept.reviewClaims(plan));
});

test("a missing bound capture step cannot be silently filtered", () => {
  const plan = agentPlan();
  plan.steps = plan.steps.filter((step) => step.id !== "ordinary_close");
  expectClaimSetFailure(() => Accept.reviewClaims(plan));
});

test("receipt validation still requires every visible claim to pass", () => {
  const request = { requestedAt: "2026-08-13T00:00:00.000Z",
    requestSha256: "4".repeat(64), captureSetSha256: "5".repeat(64),
    reviewScope: Accept.AGENT_RUNTIME_REVIEW_SCOPE,
    claims: Accept.reviewClaims(agentPlan()) };
  const receipt = sealReceipt({ schema: Accept.REVIEW_RECEIPT_SCHEMA,
    reviewedAt: "2026-08-13T00:01:00.000Z", requestSha256: request.requestSha256,
    captureSetSha256: request.captureSetSha256,
    reviewer: { reviewerId: "independent-reviewer", operationId: "visible-review-1",
      reviewMethod: "independent_visible_png_review", reviewScope: request.reviewScope,
      independenceAttested: true, businessApiCalls: 0 },
    verdicts: request.claims.map((claim) => ({ claimId: claim.claimId, status: "pass",
      captureStepsReviewed: claim.captureSteps,
      observation: "Every bound PNG visibly supports this exact claim." })),
    decision: "accepted" });
  Accept.validateReviewReceipt(receipt, request);
  const rejected = JSON.parse(JSON.stringify(receipt));
  rejected.verdicts[0].status = "fail";
  assert.throws(() => Accept.validateReviewReceipt(sealReceipt(rejected), request),
    (error) => error && error.code === "material_shop_review_verdict_invalid");
});

process.stdout.write("visible-review-contract: " + passed + "/" + passed + " passed\n");
