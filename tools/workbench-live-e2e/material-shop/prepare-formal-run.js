"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");

const Evidence = require("../lib/evidence-artifact");
const Accept = require("./accept-run");
const Build = require("./build-candidate");
const Common = require("./common");
const FormalProtocol = require("./formal-run-protocol");
const Prepare = require("./prepare");
const CandidateProtocol = require("./protocol");
const ReleaseWorktree = require("./release-worktree");
const VerifyRun = require("./verify-run");

const FORMAL_PREFLIGHT_SCHEMA = "workbench-live-e2e.material-shop.formal-preflight.v1";
const FORMAL_RUNS_DIRECTORY = "formal-runs";
const FORMAL_PREFLIGHT_NAME = "formal-preflight.json";
const REVIEW_REQUEST_KEYS = Object.freeze([
  "schema", "requestedAt", "runId", "planSha256", "preparationSha256",
  "closureSha256", "materializationSha256", "applicabilitySha256", "buildSha256",
  "externalToolchainSha256", "candidateIdentitySha256", "rawSha256",
  "operationTerminalSha256", "journeyEvidenceSha256", "settlementSha256",
  "cloneReleaseSha256", "staticGateSha256", "trustedRunnerSessions",
  "captureSetSha256", "captures", "claims", "deployment", "reviewScope",
  "requestSha256",
]);

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function samePath(left, right) {
  if (typeof left !== "string" || typeof right !== "string"
      || !path.isAbsolute(left) || !path.isAbsolute(right)) return false;
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function parseArgs(argv) {
  const args = { project: false, runId: null, candidateRunDir: null,
    candidateReviewReceipt: null, authorizePurchase: false };
  const seen = new Set();
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (seen.has(token)) {
      Common.fail("material_shop_formal_argument_duplicate", "formal_project", token);
    }
    seen.add(token);
    const take = () => {
      index += 1;
      if (index >= argv.length) {
        Common.fail("material_shop_formal_argument_missing", "formal_project", token);
      }
      return argv[index];
    };
    if (token === "--project") args.project = true;
    else if (token === "--run-id") args.runId = take();
    else if (token === "--candidate-run-dir") args.candidateRunDir = take();
    else if (token === "--candidate-review-receipt") {
      args.candidateReviewReceipt = take();
    } else if (token === "--authorize-quantity-one-purchase") {
      args.authorizePurchase = true;
    } else {
      Common.fail("material_shop_formal_argument_unknown", "formal_project", token);
    }
  }
  if (args.project !== true || !Common.ID_RE.test(String(args.runId || ""))
      || !args.candidateRunDir || !args.candidateReviewReceipt
      || args.authorizePurchase !== true) {
    Common.fail("material_shop_formal_project_arguments_invalid", "formal_project",
      "--project, a fresh run id, candidate run/review receipt, and explicit q1 request are required");
  }
  return args;
}

function validatePreparationProjection(value) {
  Common.exactKeys(value.slots, ["seedSlot", "targetSlot", "recoverySlot"],
    "material_shop_formal_preparation_invalid", "formal_project");
  if (Evidence.canonicalJson(value.slots)
      !== Evidence.canonicalJson(FormalProtocol.FORMAL_SLOTS)) {
    Common.fail("material_shop_formal_preparation_invalid", "formal_project",
      "candidate preparation does not use the exact current A5 slots");
  }
  Common.exactKeys(value.boundaries, ["worktreeMaterialized", "candidateBuilt",
    "candidateExecuted", "liveAdmission", "promoted", "standardEntryVerified"],
  "material_shop_formal_preparation_invalid", "formal_project");
  if (value.boundaries.worktreeMaterialized !== true
      || value.boundaries.candidateBuilt !== false
      || value.boundaries.candidateExecuted !== false
      || value.boundaries.liveAdmission !== "candidate_ui_probe_required"
      || value.boundaries.promoted !== false
      || value.boundaries.standardEntryVerified !== false) {
    Common.fail("material_shop_formal_preparation_invalid", "formal_project",
      "candidate preparation boundaries are not the exact unpromoted A5 envelope");
  }
  return value;
}

function validateBuildEnvelope(value, preparation) {
  Common.exactKeys(value, ["schema", "createdAt", "startedAt", "preparationSha256",
    "materializationSha256", "externalToolchain", "command", "candidateRoot",
    "candidateIdentity", "candidateBinding", "materializedProducerBinding",
    "liveAdmission", "boundaries", "buildSha256"],
  "material_shop_formal_build_invalid", "formal_project");
  Common.exactKeys(value.boundaries, ["candidateBuilt", "candidateExecuted", "e2eVerified",
    "promoted", "standardEntryVerified"], "material_shop_formal_build_invalid",
  "formal_project");
  const expectedCandidateRoot = Build.candidateContract(preparation).candidateRoot;
  if (value.schema !== Build.BUILD_SCHEMA
      || !Number.isFinite(Date.parse(value.startedAt))
      || !Number.isFinite(Date.parse(value.createdAt))
      || Date.parse(value.createdAt) < Date.parse(value.startedAt)
      || value.preparationSha256 !== preparation.preparationSha256
      || value.materializationSha256 !== preparation.materializationSha256
      || !value.externalToolchain
      || value.externalToolchain.descriptorSha256 !== preparation.externalToolchainSha256
      || value.liveAdmission !== "candidate_ui_probe_required"
      || !samePath(value.candidateRoot, expectedCandidateRoot)
      || !value.candidateIdentity
      || !samePath(value.candidateIdentity.installRoot, expectedCandidateRoot)
      || value.boundaries.candidateBuilt !== true
      || value.boundaries.candidateExecuted !== false
      || value.boundaries.e2eVerified !== false
      || value.boundaries.promoted !== false
      || value.boundaries.standardEntryVerified !== false
      || value.buildSha256 !== digestWithout(value, "buildSha256")) {
    Common.fail("material_shop_formal_build_invalid", "formal_project",
      "post-removal candidate build envelope is malformed or detached");
  }
  Build.validateExecutedCommand(value.command, preparation, "formal_project");
  return value;
}

function validateReviewRequestProjection(value, acceptedCandidate) {
  Common.exactKeys(value, REVIEW_REQUEST_KEYS,
    "material_shop_formal_review_request_invalid", "formal_project");
  const acceptance = acceptedCandidate.acceptance;
  const plan = acceptedCandidate.controlPlan;
  const expectedClaims = Accept.reviewClaims(plan);
  const expectedScope = Accept.reviewScope(plan);
  if (value.schema !== Accept.REVIEW_REQUEST_SCHEMA
      || !Number.isFinite(Date.parse(value.requestedAt))
      || value.runId !== acceptance.runId || value.planSha256 !== acceptance.planSha256
      || value.preparationSha256 !== acceptance.preparationSha256
      || value.closureSha256 !== acceptance.closureSha256
      || value.materializationSha256 !== acceptance.materializationSha256
      || value.applicabilitySha256 !== acceptance.applicabilitySha256
      || value.buildSha256 !== acceptance.buildSha256
      || value.externalToolchainSha256 !== acceptance.externalToolchainSha256
      || value.candidateIdentitySha256 !== acceptance.candidateIdentitySha256
      || value.rawSha256 !== acceptance.rawSha256
      || value.operationTerminalSha256 !== acceptance.operationTerminalSha256
      || value.journeyEvidenceSha256 !== acceptance.journeyEvidenceSha256
      || value.settlementSha256 !== acceptance.settlementSha256
      || value.cloneReleaseSha256 !== acceptance.cloneReleaseSha256
      || value.staticGateSha256 !== acceptance.staticGateSha256
      || !Array.isArray(value.captures)
      || value.captureSetSha256 !== Evidence.sha256Text(Evidence.canonicalJson(value.captures))
      || value.captureSetSha256 !== acceptance.captureSetSha256
      || Evidence.canonicalJson(value.claims) !== Evidence.canonicalJson(expectedClaims)
      || value.reviewScope !== expectedScope || value.deployment !== "NOT_DEPLOYED"
      || value.requestSha256 !== acceptance.reviewRequestSha256
      || value.requestSha256 !== digestWithout(value, "requestSha256")) {
    Common.fail("material_shop_formal_review_request_invalid", "formal_project",
      "review request is malformed or detached from the sealed candidate acceptance");
  }
  if (!Array.isArray(value.trustedRunnerSessions)
      || value.trustedRunnerSessions.length !== FormalProtocol.SESSION_LABELS.length) {
    Common.fail("material_shop_formal_review_request_invalid", "formal_project",
      "review request lacks exact first/restart trusted-runner projections");
  }
  value.trustedRunnerSessions.forEach((session, index) => {
    Common.exactKeys(session, ["label", "completionSha256", "transcriptSha256", "ledgerSha256"],
      "material_shop_formal_review_request_invalid", "formal_project");
    if (session.label !== FormalProtocol.SESSION_LABELS[index]
        || [session.completionSha256, session.transcriptSha256, session.ledgerSha256]
          .some((entry) => !Common.SHA256_RE.test(String(entry || "")))) {
      Common.fail("material_shop_formal_review_request_invalid", "formal_project",
        "trusted-runner review projection is malformed");
    }
  });
  return value;
}

function gitWorktreeListed(canonicalRoot, destination, spawnSync) {
  const invoke = spawnSync || childProcess.spawnSync;
  const result = invoke("git", ["worktree", "list", "--porcelain"], {
    cwd: canonicalRoot, encoding: "utf8", windowsHide: true, maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0 || result.signal) {
    Common.fail("material_shop_formal_git_probe_failed", "formal_project",
      "git worktree inventory failed during post-removal projection");
  }
  const target = path.resolve(destination).toLowerCase();
  return String(result.stdout || "").split(/\r?\n/)
    .filter((line) => line.startsWith("worktree "))
    .some((line) => path.resolve(line.slice("worktree ".length)).toLowerCase() === target);
}

function validateCrossBindings(context) {
  const { preparation, build, acceptedCandidate, reviewRequest, reviewReceipt,
    removalState, worktreeRelease } = context;
  FormalProtocol.validateAcceptedCandidate(acceptedCandidate);
  const acceptance = acceptedCandidate.acceptance;
  const plan = acceptedCandidate.controlPlan;
  validatePreparationProjection(preparation);
  validateBuildEnvelope(build, preparation);
  validateReviewRequestProjection(reviewRequest, acceptedCandidate);
  Accept.validateReviewReceipt(reviewReceipt, reviewRequest);
  const intent = removalState.intent;
  const exact = acceptance.runId === preparation.runId
    && samePath(removalState.runDir, preparation.runDir)
    && samePath(intent.runDir, preparation.runDir)
    && samePath(intent.outputPath, path.join(preparation.runDir,
      ReleaseWorktree.REMOVAL_OUTPUT_NAME))
    && Date.parse(intent.createdAt) >= Date.parse(acceptance.acceptedAt)
    && plan.runId === preparation.runId
    && plan.planSha256 === preparation.planSha256
    && acceptance.planSha256 === preparation.planSha256
    && acceptance.preparationSha256 === preparation.preparationSha256
    && acceptance.closureSha256 === preparation.closureSha256
    && acceptance.materializationSha256 === preparation.materializationSha256
    && acceptance.applicabilitySha256 === preparation.applicabilitySha256
    && acceptance.externalToolchainSha256 === preparation.externalToolchainSha256
    && acceptance.buildSha256 === build.buildSha256
    && acceptance.candidateIdentitySha256
      === Evidence.sha256Text(Evidence.canonicalJson(build.candidateIdentity))
    && reviewReceipt.reviewReceiptSha256 === acceptance.reviewReceiptSha256
    && Date.parse(acceptance.acceptedAt) >= Date.parse(reviewReceipt.reviewedAt)
    && intent.runId === acceptance.runId
    && intent.preparationSha256 === acceptance.preparationSha256
    && intent.closureSha256 === acceptance.closureSha256
    && intent.materializationSha256 === acceptance.materializationSha256
    && intent.buildSha256 === acceptance.buildSha256
    && intent.rawSha256 === acceptance.rawSha256
    && intent.journeyEvidenceSha256 === acceptance.journeyEvidenceSha256
    && intent.cloneReleaseSha256 === acceptance.cloneReleaseSha256
    && intent.acceptanceSha256 === acceptance.acceptanceSha256
    && worktreeRelease.acceptanceSha256 === acceptance.acceptanceSha256
    && worktreeRelease.preparationSha256 === acceptance.preparationSha256
    && worktreeRelease.closureSha256 === acceptance.closureSha256
    && worktreeRelease.materializationSha256 === acceptance.materializationSha256
    && worktreeRelease.buildSha256 === acceptance.buildSha256
    && worktreeRelease.rawSha256 === acceptance.rawSha256
    && worktreeRelease.journeyEvidenceSha256 === acceptance.journeyEvidenceSha256
    && worktreeRelease.cloneReleaseSha256 === acceptance.cloneReleaseSha256
    && samePath(preparation.resourcesRoot, intent.destination)
    && samePath(build.candidateRoot, build.candidateIdentity.installRoot);
  if (!exact) {
    Common.fail("material_shop_formal_candidate_binding_invalid", "formal_project",
      "post-removal durable anchors do not cross-bind one exact accepted candidate");
  }
  return context;
}

function loadPostRemovalCandidate(options, dependencies) {
  const settings = options || {};
  const deps = dependencies || {};
  const candidateRunDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT,
    settings.candidateRunDir, Common.OWNED_BASE_RELATIVE, "formal_project");
  const removalState = (deps.loadRemovalState || ReleaseWorktree.loadRemovalState)(candidateRunDir);
  if (removalState.active !== false || !samePath(removalState.markerPath,
    removalState.resolvedPath)) {
    Common.fail("material_shop_formal_removal_unresolved", "formal_project",
      "formal projection requires one uniquely resolved removal intent");
  }
  const readJson = deps.readJson || Prepare.readJson;
  const preparation = (deps.loadPreparation || Build.loadPreparation)(
    path.join(candidateRunDir, "preparation.json"));
  const plan = CandidateProtocol.validateAgentRuntimeControlPlan(
    (deps.readPlanArtifact || VerifyRun.artifact)(preparation.runDir,
      preparation.artifacts.plan));
  const build = (deps.loadBuildEnvelope || Build.loadBuildEnvelope)(
    path.join(candidateRunDir, "candidate-build.json"), preparation, "formal_project");
  const acceptance = readJson(path.join(candidateRunDir, "acceptance.json"), "formal_project");
  const reviewRequest = readJson(path.join(candidateRunDir, "review-request.json"),
    "formal_project");
  const reviewReceipt = readJson(path.resolve(settings.candidateReviewReceipt),
    "formal_project");
  const worktreeRelease = (deps.validateRemovalReceipt
    || ReleaseWorktree.validateRemovalReceipt)(
    readJson(path.join(candidateRunDir, ReleaseWorktree.REMOVAL_OUTPUT_NAME),
      "formal_project"), removalState.intent);
  const destinationPresent = (deps.existsSync || fs.existsSync)(removalState.intent.destination);
  const listed = (deps.gitWorktreeListed || gitWorktreeListed)(Common.CANONICAL_ROOT,
    removalState.intent.destination, deps.spawnSync);
  if (destinationPresent || listed) {
    Common.fail("material_shop_formal_candidate_worktree_present", "formal_project",
      "removed candidate destination must be absent from filesystem and Git inventory", {
        destinationPresent, worktreeListed: listed,
      });
  }
  const acceptedCandidate = { acceptance, candidateIdentity: build.candidateIdentity,
    candidateProducerBinding: build.candidateBinding, controlPlan: plan };
  return validateCrossBindings({ preparation, build, acceptedCandidate, reviewRequest,
    reviewReceipt, removalState, worktreeRelease });
}

function preparerInputProjection(value) {
  return { mode: value.mode, runId: value.runId, canonicalRoot: value.canonicalRoot,
    acceptedCandidate: value.acceptedCandidate, candidate: value.candidate,
    review: value.review, removal: value.removal,
    authorizationRequest: value.authorizationRequest };
}

function stableFormalPreflight(value) {
  const stable = Object.assign({}, value);
  delete stable.preflightSha256;
  return stable;
}

function createFormalPreflight(options) {
  const settings = options || {};
  const root = Common.assertCanonicalRoot(settings.canonicalRoot || Common.CANONICAL_ROOT);
  const runId = String(settings.runId || "");
  const acceptedCandidate = clone(settings.acceptedCandidate);
  FormalProtocol.validateAcceptedCandidate(acceptedCandidate);
  if (!Common.ID_RE.test(runId) || runId === acceptedCandidate.acceptance.runId) {
    Common.fail("material_shop_formal_run_id_invalid", "formal_project",
      "formal projection requires a fresh run id distinct from the candidate run");
  }
  const formalRunDir = path.join(root, Common.OWNED_BASE_RELATIVE,
    FORMAL_RUNS_DIRECTORY, runId);
  const candidate = clone(settings.candidate);
  const review = clone(settings.review);
  const removal = clone(settings.removal);
  const value = {
    schema: FORMAL_PREFLIGHT_SCHEMA,
    projectedAt: settings.projectedAt || new Date().toISOString(),
    mode: "project",
    runId,
    canonicalRoot: root,
    formalRunDir,
    acceptedCandidate,
    candidate,
    review,
    removal,
    authorizationRequest: {
      source: "explicit_project_flag_request",
      quantityOneAuthorizationRequested: true,
      target: clone(FormalProtocol.FORMAL_TARGET),
      stepId: "unlocked_commit",
      quantity: 1,
      saleCount: 0,
    },
    boundaries: {
      projectionOnly: true,
      rawCandidateRead: false,
      materializedTreeRead: false,
      consensusVerifierCalled: false,
      consensusVerified: false,
      admitted: false,
      formalPlanCreated: false,
      purchaseAuthorityCreated: false,
      runtimeLaunched: false,
      purchasePerformed: false,
      standardEntryVerified: false,
    },
  };
  value.preparerInputSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(preparerInputProjection(value)));
  value.preflightSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(stableFormalPreflight(value)));
  return validateFormalPreflight(value);
}

function validateFormalPreflight(value) {
  Common.exactKeys(value, ["schema", "projectedAt", "mode", "runId", "canonicalRoot",
    "formalRunDir", "acceptedCandidate", "candidate", "review", "removal",
    "authorizationRequest", "boundaries", "preparerInputSha256", "preflightSha256"],
  "material_shop_formal_preflight_invalid", "formal_project");
  FormalProtocol.validateAcceptedCandidate(value.acceptedCandidate);
  Common.exactKeys(value.candidate, ["runId", "runDir", "preparationSha256",
    "buildSha256", "acceptanceSha256", "planSha256", "candidateIdentitySha256",
    "reviewRequestSha256", "reviewReceiptSha256", "removalIntentSha256",
    "worktreeReleaseSha256"], "material_shop_formal_preflight_invalid", "formal_project");
  Common.exactKeys(value.review, ["requestSha256", "receiptSha256", "reviewerId",
    "operationId", "decision"], "material_shop_formal_preflight_invalid", "formal_project");
  Common.exactKeys(value.removal, ["destination", "resolvedMarkerPath",
    "destinationPresent", "worktreeListed"], "material_shop_formal_preflight_invalid",
  "formal_project");
  Common.exactKeys(value.authorizationRequest, ["source",
    "quantityOneAuthorizationRequested", "target", "stepId", "quantity", "saleCount"],
  "material_shop_formal_preflight_invalid", "formal_project");
  Common.exactKeys(value.authorizationRequest.target, ["shopId", "catalogIndex", "itemName"],
    "material_shop_formal_preflight_invalid", "formal_project");
  Common.exactKeys(value.boundaries, ["projectionOnly", "rawCandidateRead",
    "materializedTreeRead", "consensusVerifierCalled", "consensusVerified", "admitted",
    "formalPlanCreated", "purchaseAuthorityCreated", "runtimeLaunched", "purchasePerformed",
    "standardEntryVerified"], "material_shop_formal_preflight_invalid", "formal_project");
  const acceptance = value.acceptedCandidate.acceptance;
  const root = Common.assertCanonicalRoot(value.canonicalRoot);
  const expectedFormalRunDir = path.join(root, Common.OWNED_BASE_RELATIVE,
    FORMAL_RUNS_DIRECTORY, value.runId);
  const expectedCandidateRunDir = path.join(root, Common.OWNED_BASE_RELATIVE,
    "runs", acceptance.runId);
  const expectedRemovedDestination = path.join(root, Common.OWNED_BASE_RELATIVE,
    "materialized", acceptance.runId, "resources");
  const expectedResolvedMarker = path.join(expectedCandidateRunDir,
    ReleaseWorktree.REMOVAL_RESOLVED_PREFIX
      + value.candidate.removalIntentSha256.slice(0, 16) + ".json");
  const digestFields = [value.candidate.preparationSha256, value.candidate.buildSha256,
    value.candidate.acceptanceSha256, value.candidate.planSha256,
    value.candidate.candidateIdentitySha256, value.candidate.reviewRequestSha256,
    value.candidate.reviewReceiptSha256, value.candidate.removalIntentSha256,
    value.candidate.worktreeReleaseSha256, value.review.requestSha256,
    value.review.receiptSha256];
  if (value.schema !== FORMAL_PREFLIGHT_SCHEMA || value.mode !== "project"
      || !Number.isFinite(Date.parse(value.projectedAt))
      || !Common.ID_RE.test(String(value.runId || "")) || value.runId === acceptance.runId
      || !samePath(value.formalRunDir, expectedFormalRunDir)
      || !samePath(value.candidate.runDir, expectedCandidateRunDir)
      || value.candidate.runId !== acceptance.runId
      || value.candidate.acceptanceSha256 !== acceptance.acceptanceSha256
      || value.candidate.preparationSha256 !== acceptance.preparationSha256
      || value.candidate.buildSha256 !== acceptance.buildSha256
      || value.candidate.planSha256 !== acceptance.planSha256
      || value.candidate.candidateIdentitySha256 !== acceptance.candidateIdentitySha256
      || value.candidate.reviewRequestSha256 !== acceptance.reviewRequestSha256
      || value.candidate.reviewReceiptSha256 !== acceptance.reviewReceiptSha256
      || digestFields.some((entry) => !Common.SHA256_RE.test(String(entry || "")))
      || value.review.requestSha256 !== acceptance.reviewRequestSha256
      || value.review.receiptSha256 !== acceptance.reviewReceiptSha256
      || !Common.ID_RE.test(String(value.review.reviewerId || ""))
      || !Common.ID_RE.test(String(value.review.operationId || ""))
      || value.review.decision !== "accepted"
      || !samePath(value.removal.destination, expectedRemovedDestination)
      || !samePath(value.removal.resolvedMarkerPath, expectedResolvedMarker)
      || value.removal.destinationPresent !== false || value.removal.worktreeListed !== false
      || typeof value.removal.destination !== "string"
      || typeof value.removal.resolvedMarkerPath !== "string"
      || value.authorizationRequest.source !== "explicit_project_flag_request"
      || value.authorizationRequest.quantityOneAuthorizationRequested !== true
      || Evidence.canonicalJson(value.authorizationRequest.target)
        !== Evidence.canonicalJson(FormalProtocol.FORMAL_TARGET)
      || value.authorizationRequest.stepId !== "unlocked_commit"
      || value.authorizationRequest.quantity !== 1
      || value.authorizationRequest.saleCount !== 0
      || value.boundaries.projectionOnly !== true
      || value.boundaries.rawCandidateRead !== false
      || value.boundaries.materializedTreeRead !== false
      || value.boundaries.consensusVerifierCalled !== false
      || value.boundaries.consensusVerified !== false
      || value.boundaries.admitted !== false
      || value.boundaries.formalPlanCreated !== false
      || value.boundaries.purchaseAuthorityCreated !== false
      || value.boundaries.runtimeLaunched !== false
      || value.boundaries.purchasePerformed !== false
      || value.boundaries.standardEntryVerified !== false
      || value.preparerInputSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(preparerInputProjection(value)))
      || value.preflightSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableFormalPreflight(value)))) {
    Common.fail("material_shop_formal_preflight_invalid", "formal_project",
      "formal preflight projection is malformed, detached, or overclaims authority/execution");
  }
  return value;
}

function writeJsonAtomicCreateNew(outputPath, value) {
  const output = path.resolve(outputPath);
  const bytes = Buffer.from(JSON.stringify(value, null, 2) + "\n", "utf8");
  const staged = output + ".staged-" + Evidence.sha256Bytes(bytes).slice(0, 16);
  let descriptor;
  try {
    descriptor = fs.openSync(staged, "wx", 0o600);
    fs.writeFileSync(descriptor, bytes);
    fs.fsyncSync(descriptor);
    fs.closeSync(descriptor);
    descriptor = undefined;
    fs.linkSync(staged, output);
    fs.unlinkSync(staged);
  } catch (error) {
    if (descriptor !== undefined) fs.closeSync(descriptor);
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  return output;
}

function project(options, dependencies) {
  const settings = options || {};
  if (settings.project !== true || settings.authorizePurchase !== true) {
    Common.fail("material_shop_formal_project_arguments_invalid", "formal_project",
      "programmatic formal projection also requires explicit project and q1 flags");
  }
  const context = loadPostRemovalCandidate(settings, dependencies);
  const runId = String(settings.runId || "");
  if (!Common.ID_RE.test(runId) || runId === context.acceptedCandidate.acceptance.runId) {
    Common.fail("material_shop_formal_run_id_invalid", "formal_project",
      "formal projection requires a fresh run id");
  }
  const ownedBase = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const formalBase = path.join(ownedBase, FORMAL_RUNS_DIRECTORY);
  const formalRunDir = path.join(formalBase, runId);
  const candidateRunCollision = path.join(ownedBase, "runs", runId);
  const materializedCollision = path.join(ownedBase, "materialized", runId);
  if (fs.existsSync(formalRunDir) || fs.existsSync(candidateRunCollision)
      || fs.existsSync(materializedCollision)) {
    Common.fail("material_shop_formal_run_exists", "formal_project",
      "formal run id is not fresh across owned run namespaces");
  }
  const acceptance = context.acceptedCandidate.acceptance;
  const receipt = context.reviewReceipt;
  const preflight = createFormalPreflight({ canonicalRoot: Common.CANONICAL_ROOT, runId,
    acceptedCandidate: context.acceptedCandidate,
    candidate: { runId: acceptance.runId, runDir: context.preparation.runDir,
      preparationSha256: acceptance.preparationSha256,
      buildSha256: acceptance.buildSha256,
      acceptanceSha256: acceptance.acceptanceSha256,
      planSha256: acceptance.planSha256,
      candidateIdentitySha256: acceptance.candidateIdentitySha256,
      reviewRequestSha256: acceptance.reviewRequestSha256,
      reviewReceiptSha256: acceptance.reviewReceiptSha256,
      removalIntentSha256: context.removalState.intent.intentSha256,
      worktreeReleaseSha256: context.worktreeRelease.releaseSha256 },
    review: { requestSha256: context.reviewRequest.requestSha256,
      receiptSha256: receipt.reviewReceiptSha256,
      reviewerId: receipt.reviewer.reviewerId,
      operationId: receipt.reviewer.operationId,
      decision: receipt.decision },
    removal: { destination: context.removalState.intent.destination,
      resolvedMarkerPath: context.removalState.resolvedPath,
      destinationPresent: false, worktreeListed: false } });
  const exactOwnedBase = Evidence.assertExactDirectory(ownedBase, "formal_project");
  const exactFormalBase = Evidence.ensureExactChildDirectory(exactOwnedBase,
    FORMAL_RUNS_DIRECTORY, "formal_project");
  fs.mkdirSync(path.join(exactFormalBase, runId));
  Evidence.assertExactDirectory(formalRunDir, "formal_project");
  const output = path.join(formalRunDir, FORMAL_PREFLIGHT_NAME);
  writeJsonAtomicCreateNew(output, preflight);
  return { value: validateFormalPreflight(Prepare.readJson(output, "formal_project")), output };
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = project(args);
    process.stdout.write(JSON.stringify({ ok: true, mode: "project", runId: result.value.runId,
      output: result.output, preflightSha256: result.value.preflightSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  FORMAL_PREFLIGHT_NAME,
  FORMAL_PREFLIGHT_SCHEMA,
  FORMAL_RUNS_DIRECTORY,
  createFormalPreflight,
  gitWorktreeListed,
  loadPostRemovalCandidate,
  parseArgs,
  preparerInputProjection,
  project,
  stableFormalPreflight,
  validateBuildEnvelope,
  validateCrossBindings,
  validateFormalPreflight,
  validatePreparationProjection,
  validateReviewRequestProjection,
  writeJsonAtomicCreateNew,
};
