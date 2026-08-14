"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");

const Evidence = require("../lib/evidence-artifact");
const Accept = require("./accept-run");
const Build = require("./build-candidate");
const Common = require("./common");
const FormalProtocol = require("./formal-run-protocol");
const Preparer = require("./prepare-formal-run");
const CandidateProtocol = require("./protocol");

function sha(character) {
  return character.repeat(64);
}

function withAcceptedCandidateValidator(callback) {
  const original = FormalProtocol.validateAcceptedCandidate;
  FormalProtocol.validateAcceptedCandidate = (value) => value;
  try { return callback(); }
  finally { FormalProtocol.validateAcceptedCandidate = original; }
}

function fixture() {
  const acceptance = {
    runId: "candidate-a5-accepted",
    preparationSha256: sha("1"),
    buildSha256: sha("2"),
    acceptanceSha256: sha("3"),
    planSha256: sha("4"),
    candidateIdentitySha256: sha("5"),
    reviewRequestSha256: sha("6"),
    reviewReceiptSha256: sha("7"),
  };
  const candidateRunDir = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", acceptance.runId);
  const removalIntentSha256 = sha("8");
  return {
    acceptedCandidate: { acceptance, candidateIdentity: {}, controlPlan: {} },
    candidate: { runId: acceptance.runId,
      runDir: candidateRunDir,
      preparationSha256: acceptance.preparationSha256,
      buildSha256: acceptance.buildSha256,
      acceptanceSha256: acceptance.acceptanceSha256,
      planSha256: acceptance.planSha256,
      candidateIdentitySha256: acceptance.candidateIdentitySha256,
      reviewRequestSha256: acceptance.reviewRequestSha256,
      reviewReceiptSha256: acceptance.reviewReceiptSha256,
      removalIntentSha256, worktreeReleaseSha256: sha("9") },
    review: { requestSha256: acceptance.reviewRequestSha256,
      receiptSha256: acceptance.reviewReceiptSha256,
      reviewerId: "independent-reviewer", operationId: "review-op-01",
      decision: "accepted" },
    removal: { destination: path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
      "materialized", acceptance.runId, "resources"),
      resolvedMarkerPath: path.join(candidateRunDir,
        "worktree-removal-resolved-" + removalIntentSha256.slice(0, 16) + ".json"),
      destinationPresent: false, worktreeListed: false },
  };
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function postRemovalFixture(candidateRunDir) {
  const runId = path.basename(candidateRunDir);
  const resourcesRoot = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "materialized", runId, "resources");
  const candidateRoot = path.join(resourcesRoot, "tmp", "runtime-candidates", "v2", "a5");
  const preparation = {
    runId, runDir: candidateRunDir, resourcesRoot,
    slots: FormalProtocol.FORMAL_SLOTS,
    preparationSha256: sha("1"), closureSha256: sha("2"),
    materializationSha256: sha("3"), applicabilitySha256: sha("4"),
    externalToolchainSha256: sha("5"), planSha256: sha("6"),
    artifacts: { plan: { relativePath: "control-plan.json", sha256: sha("a"), bytes: 1 } },
    boundaries: { worktreeMaterialized: true, candidateBuilt: false,
      candidateExecuted: false, liveAdmission: "candidate_ui_probe_required",
      promoted: false, standardEntryVerified: false },
  };
  const plan = { runId, planSha256: preparation.planSha256 };
  const candidateIdentity = { installRoot: candidateRoot };
  const build = {
    schema: Build.BUILD_SCHEMA,
    createdAt: "2026-08-14T07:01:00.000Z",
    startedAt: "2026-08-14T07:00:00.000Z",
    preparationSha256: preparation.preparationSha256,
    materializationSha256: preparation.materializationSha256,
    externalToolchain: { descriptorSha256: preparation.externalToolchainSha256 },
    command: {}, candidateRoot, candidateIdentity,
    candidateBinding: {}, materializedProducerBinding: {},
    liveAdmission: "candidate_ui_probe_required",
    boundaries: { candidateBuilt: true, candidateExecuted: false, e2eVerified: false,
      promoted: false, standardEntryVerified: false },
  };
  build.buildSha256 = digestWithout(build, "buildSha256");
  const acceptance = {
    acceptedAt: "2026-08-14T08:00:00.000Z", runId,
    planSha256: preparation.planSha256,
    preparationSha256: preparation.preparationSha256,
    closureSha256: preparation.closureSha256,
    materializationSha256: preparation.materializationSha256,
    applicabilitySha256: preparation.applicabilitySha256,
    externalToolchainSha256: preparation.externalToolchainSha256,
    buildSha256: build.buildSha256,
    candidateIdentitySha256: Evidence.sha256Text(Evidence.canonicalJson(candidateIdentity)),
    rawSha256: sha("7"), operationTerminalSha256: sha("8"),
    journeyEvidenceSha256: sha("9"), settlementSha256: sha("a"),
    cloneReleaseSha256: sha("b"), staticGateSha256: sha("c"),
    captureSetSha256: Evidence.sha256Text(Evidence.canonicalJson([])),
  };
  const reviewRequest = {
    schema: Accept.REVIEW_REQUEST_SCHEMA,
    requestedAt: "2026-08-14T07:30:00.000Z", runId,
    planSha256: acceptance.planSha256,
    preparationSha256: acceptance.preparationSha256,
    closureSha256: acceptance.closureSha256,
    materializationSha256: acceptance.materializationSha256,
    applicabilitySha256: acceptance.applicabilitySha256,
    buildSha256: acceptance.buildSha256,
    externalToolchainSha256: acceptance.externalToolchainSha256,
    candidateIdentitySha256: acceptance.candidateIdentitySha256,
    rawSha256: acceptance.rawSha256,
    operationTerminalSha256: acceptance.operationTerminalSha256,
    journeyEvidenceSha256: acceptance.journeyEvidenceSha256,
    settlementSha256: acceptance.settlementSha256,
    cloneReleaseSha256: acceptance.cloneReleaseSha256,
    staticGateSha256: acceptance.staticGateSha256,
    trustedRunnerSessions: ["first", "restart"].map((label, index) => ({ label,
      completionSha256: sha(index ? "d" : "e"),
      transcriptSha256: sha(index ? "f" : "0"),
      ledgerSha256: sha(index ? "1" : "2") })),
    captureSetSha256: acceptance.captureSetSha256,
    captures: [], claims: [], deployment: "NOT_DEPLOYED",
    reviewScope: "fixture_scope",
  };
  reviewRequest.requestSha256 = digestWithout(reviewRequest, "requestSha256");
  acceptance.reviewRequestSha256 = reviewRequest.requestSha256;
  const reviewReceipt = {
    schema: Accept.REVIEW_RECEIPT_SCHEMA,
    reviewedAt: "2026-08-14T07:45:00.000Z",
    requestSha256: reviewRequest.requestSha256,
    captureSetSha256: reviewRequest.captureSetSha256,
    reviewer: { reviewerId: "fixture-reviewer", operationId: "fixture-review-op",
      reviewMethod: "independent_visible_png_review", reviewScope: "fixture_scope",
      independenceAttested: true, businessApiCalls: 0 },
    verdicts: [], decision: "accepted",
  };
  reviewReceipt.reviewReceiptSha256 = digestWithout(reviewReceipt, "reviewReceiptSha256");
  acceptance.reviewReceiptSha256 = reviewReceipt.reviewReceiptSha256;
  acceptance.acceptanceSha256 = digestWithout(acceptance, "acceptanceSha256");
  const intent = {
    createdAt: "2026-08-14T08:01:00.000Z", runId, runDir: candidateRunDir,
    outputPath: path.join(candidateRunDir, "worktree-release.json"),
    destination: resourcesRoot,
    preparationSha256: acceptance.preparationSha256,
    closureSha256: acceptance.closureSha256,
    materializationSha256: acceptance.materializationSha256,
    buildSha256: acceptance.buildSha256,
    rawSha256: acceptance.rawSha256,
    journeyEvidenceSha256: acceptance.journeyEvidenceSha256,
    cloneReleaseSha256: acceptance.cloneReleaseSha256,
    acceptanceSha256: acceptance.acceptanceSha256,
    intentSha256: sha("d"),
  };
  const resolvedPath = path.join(candidateRunDir,
    "worktree-removal-resolved-" + intent.intentSha256.slice(0, 16) + ".json");
  const removalState = { runDir: candidateRunDir, intent, markerPath: resolvedPath,
    active: false, resolvedPath };
  const worktreeRelease = {
    preparationSha256: acceptance.preparationSha256,
    closureSha256: acceptance.closureSha256,
    materializationSha256: acceptance.materializationSha256,
    buildSha256: acceptance.buildSha256,
    rawSha256: acceptance.rawSha256,
    journeyEvidenceSha256: acceptance.journeyEvidenceSha256,
    cloneReleaseSha256: acceptance.cloneReleaseSha256,
    acceptanceSha256: acceptance.acceptanceSha256,
    releaseSha256: sha("e"),
  };
  return { preparation, plan, build, acceptance, reviewRequest, reviewReceipt,
    removalState, worktreeRelease };
}

function withPostRemovalValidatorStubs(candidateRoot, callback) {
  const original = {
    formal: FormalProtocol.validateAcceptedCandidate,
    plan: CandidateProtocol.validateAgentRuntimeControlPlan,
    claims: Accept.reviewClaims,
    scope: Accept.reviewScope,
    candidateContract: Build.candidateContract,
    command: Build.validateExecutedCommand,
  };
  FormalProtocol.validateAcceptedCandidate = (value) => value;
  CandidateProtocol.validateAgentRuntimeControlPlan = (value) => value;
  Accept.reviewClaims = () => [];
  Accept.reviewScope = () => "fixture_scope";
  Build.candidateContract = () => ({ candidateRoot });
  Build.validateExecutedCommand = (value) => value;
  try { return callback(); }
  finally {
    FormalProtocol.validateAcceptedCandidate = original.formal;
    CandidateProtocol.validateAgentRuntimeControlPlan = original.plan;
    Accept.reviewClaims = original.claims;
    Accept.reviewScope = original.scope;
    Build.candidateContract = original.candidateContract;
    Build.validateExecutedCommand = original.command;
  }
}

test("project CLI is explicit and exposes no admit mode", () => {
  const parsed = Preparer.parseArgs(["--project", "--run-id", "formal-a5-01",
    "--candidate-run-dir", "candidate-run", "--candidate-review-receipt", "receipt.json",
    "--authorize-quantity-one-purchase"]);
  assert.equal(parsed.project, true);
  assert.equal(parsed.authorizePurchase, true);
  assert.throws(() => Preparer.parseArgs(["--admit"]),
    (error) => error.code === "material_shop_formal_argument_unknown");
  assert.throws(() => Preparer.parseArgs(["--project", "--run-id", "formal-a5-01",
    "--candidate-run-dir", "candidate-run", "--candidate-review-receipt", "receipt.json"]),
  (error) => error.code === "material_shop_formal_project_arguments_invalid");
});

test("formal preflight is projection-only and all authority/execution states stay false", () => {
  const fx = fixture();
  const value = withAcceptedCandidateValidator(() => Preparer.createFormalPreflight({
    canonicalRoot: Common.CANONICAL_ROOT,
    runId: "formal-a5-01",
    projectedAt: "2026-08-14T08:00:00.000Z",
    ...fx,
  }));
  assert.equal(value.schema, Preparer.FORMAL_PREFLIGHT_SCHEMA);
  assert.equal(value.authorizationRequest.quantityOneAuthorizationRequested, true);
  assert.deepEqual(value.authorizationRequest.target, FormalProtocol.FORMAL_TARGET);
  for (const key of ["consensusVerifierCalled", "consensusVerified", "admitted",
    "formalPlanCreated", "purchaseAuthorityCreated", "runtimeLaunched",
    "purchasePerformed", "standardEntryVerified"]) {
    assert.equal(value.boundaries[key], false, key);
  }
  assert.equal(value.preparerInputSha256, Evidence.sha256Text(
    Evidence.canonicalJson(Preparer.preparerInputProjection(value))));
  const overclaim = JSON.parse(JSON.stringify(value));
  overclaim.boundaries.admitted = true;
  assert.throws(() => withAcceptedCandidateValidator(() =>
    Preparer.validateFormalPreflight(overclaim)),
  (error) => error.code === "material_shop_formal_preflight_invalid");
});

test("preflight publication is atomic CreateNew", () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-a5-formal-project-"));
  const output = path.join(directory, "formal-preflight.json");
  try {
    Preparer.writeJsonAtomicCreateNew(output, { first: true });
    assert.deepEqual(JSON.parse(fs.readFileSync(output, "utf8")), { first: true });
    assert.throws(() => Preparer.writeJsonAtomicCreateNew(output, { first: false }),
      (error) => error && error.code === "EEXIST");
    assert.deepEqual(JSON.parse(fs.readFileSync(output, "utf8")), { first: true });
  } finally {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("Git worktree probe is read-only, exact-path, and fail-closed", () => {
  const destination = path.join(Common.CANONICAL_ROOT, "tmp", "removed", "resources");
  const listed = Preparer.gitWorktreeListed(Common.CANONICAL_ROOT, destination,
    (_file, args, options) => {
      assert.deepEqual(args, ["worktree", "list", "--porcelain"]);
      assert.equal(options.cwd, Common.CANONICAL_ROOT);
      return { status: 0, signal: null, stdout: "worktree " + destination + "\n" };
    });
  assert.equal(listed, true);
  assert.throws(() => Preparer.gitWorktreeListed(Common.CANONICAL_ROOT, destination,
    () => ({ status: 1, signal: null, stdout: "" })),
  (error) => error.code === "material_shop_formal_git_probe_failed");
});

test("post-removal loader closes anchors and rejects marker, digest, and residue drift", () => {
  const runsRoot = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE, "runs");
  const candidateRunDir = fs.mkdtempSync(path.join(runsRoot, "formal-preparer-fixture-"));
  const receiptPath = path.join(candidateRunDir, "external-review-receipt.json");
  try {
    const invoke = (mutate, state) => {
      const fx = postRemovalFixture(candidateRunDir);
      if (mutate) mutate(fx);
      const files = new Map([
        ["acceptance.json", fx.acceptance],
        ["review-request.json", fx.reviewRequest],
        ["external-review-receipt.json", fx.reviewReceipt],
        ["worktree-release.json", fx.worktreeRelease],
      ]);
      const dependencies = {
        loadRemovalState: () => fx.removalState,
        loadPreparation: () => fx.preparation,
        readPlanArtifact: () => fx.plan,
        loadBuildEnvelope: () => fx.build,
        readJson: (filePath) => files.get(path.basename(filePath)),
        validateRemovalReceipt: (value) => value,
        existsSync: () => state && state.destinationPresent === true,
        gitWorktreeListed: () => state && state.worktreeListed === true,
      };
      return withPostRemovalValidatorStubs(fx.build.candidateRoot, () =>
        Preparer.loadPostRemovalCandidate({ candidateRunDir,
          candidateReviewReceipt: receiptPath }, dependencies));
    };

    const happy = invoke();
    assert.equal(happy.acceptedCandidate.acceptance.acceptanceSha256,
      happy.removalState.intent.acceptanceSha256);

    const cases = [
      { name: "active marker", mutate: (fx) => { fx.removalState.active = true; },
        code: "material_shop_formal_removal_unresolved" },
      { name: "acceptance/build binding drift",
        mutate: (fx) => { fx.acceptance.buildSha256 = sha("f"); },
        code: "material_shop_formal_review_request_invalid" },
      { name: "build self digest drift",
        mutate: (fx) => { fx.build.buildSha256 = sha("f"); },
        code: "material_shop_formal_build_invalid" },
      { name: "filesystem destination remains", state: { destinationPresent: true },
        code: "material_shop_formal_candidate_worktree_present" },
      { name: "Git worktree remains", state: { worktreeListed: true },
        code: "material_shop_formal_candidate_worktree_present" },
    ];
    cases.forEach((entry) => {
      assert.throws(() => invoke(entry.mutate, entry.state),
        (error) => error.code === entry.code, entry.name);
    });
  } finally {
    fs.rmSync(candidateRunDir, { recursive: true, force: true });
  }
});
