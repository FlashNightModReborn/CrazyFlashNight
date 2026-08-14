"use strict";

const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const Common = require("./common");
const JourneyVerifier = require("./journey-verifier");
const Prepare = require("./prepare");
const Production = require("./production-closure");
const Protocol = require("./protocol");

const MAXIMUM_RAW_JOURNEY_BYTES = 512 * 1024 * 1024;

function readJson(filePath, phase) {
  return Prepare.readJson(path.resolve(filePath), phase || "verify_run");
}

function readRawCandidateJourney(filePath, phase) {
  const resolved = path.resolve(filePath);
  const file = Evidence.readExactRegularFile(resolved, {
    phase: phase || "verify_run",
    maximumBytes: MAXIMUM_RAW_JOURNEY_BYTES,
  });
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) {
    Common.fail("material_shop_json_invalid", phase || "verify_run", error.message,
      { filePath: resolved });
  }
}

function artifact(runDir, reference) {
  const filePath = path.resolve(runDir, String(reference.relativePath || "").replace(/\//g, path.sep));
  if (!Evidence.pathInside(runDir, filePath)) {
    Common.fail("material_shop_verify_artifact_escape", "verify_run",
      "verification artifact escaped its run directory");
  }
  const file = Evidence.readExactRegularFile(filePath, {
    phase: "verify_run", maximumBytes: 128 * 1024 * 1024,
  });
  if (file.sha256 !== reference.sha256 || file.length !== reference.bytes) {
    Common.fail("material_shop_verify_artifact_drift", "verify_run",
      "preparation artifact changed after capture");
  }
  return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, ""));
}

function verify(options) {
  const preparation = Build.loadPreparation(options.preparation);
  const PostReleaseAdapter = require("./admit-post-release-finalization");
  const bootstrap = PostReleaseAdapter.captureProtectedScopeBootstrap(
    preparation, { optional: true });
  const buildOptions = bootstrap ? { protectedScopeBootstrap: bootstrap } : undefined;
  const closure = artifact(preparation.runDir, preparation.artifacts.closure);
  const plan = Protocol.validateControlPlan(artifact(preparation.runDir,
    preparation.artifacts.plan));
  const applicability = Applicability.validateApplicability(artifact(preparation.runDir,
    preparation.artifacts.applicability));
  const build = Build.loadBuildReceipt(options.build, preparation, closure, "verify_run",
    buildOptions);
  if (build.liveAdmission !== plan.transportPolicy.liveAdmission) {
    Common.fail("material_shop_build_plan_admission_drift", "verify_run",
      "candidate build receipt carries a different live-admission decision");
  }
  const raw = readRawCandidateJourney(options.raw, "verify_run");
  const verified = JourneyVerifier.verifyRawCandidateJourney(raw, plan, applicability,
    preparation.runDir, build);
  verified.operationTerminal = JourneyVerifier.verifyOperationTerminal(raw,
    preparation.runDir, build);
  if (options.evidence) {
    const existing = readJson(options.evidence, "verify_run");
    if (Evidence.canonicalJson(existing) !== Evidence.canonicalJson(verified.evidence)) {
      Common.fail("material_shop_evidence_replay_drift", "verify_run",
        "stored journey evidence differs from fresh raw replay verification");
    }
  }
  return verified;
}

function checkCurrentTree() {
  const first = Production.captureProductionClosure(Common.CANONICAL_ROOT);
  const second = Production.captureProductionClosure(Common.CANONICAL_ROOT);
  Production.verifyProductionClosure(first, { currentTree: true });
  if (Evidence.canonicalJson(Production.stableProjection(first))
      !== Evidence.canonicalJson(Production.stableProjection(second))) {
    Common.fail("material_shop_current_tree_unstable", "verify_run",
      "two consecutive current-tree captures differ after timestamp normalization");
  }
  const applicability = Applicability.captureCurrentDataApplicability(Common.CANONICAL_ROOT, {
    appData: process.env.APPDATA,
  });
  Applicability.verifyCurrentDataApplicability(Common.CANONICAL_ROOT, applicability, {
    appData: process.env.APPDATA,
  });
  const packageLock = first.scope.files.find((entry) =>
    entry.relativePath === "launcher/perf/package-lock.json");
  const externalToolchain = ExternalToolchain.captureDescriptor(Common.CANONICAL_ROOT);
  ExternalToolchain.validateDescriptor(externalToolchain, Common.CANONICAL_ROOT, {
    expectedPackageLock: packageLock,
  });
  return { ok: true, mode: "current_tree_check", fileCount: first.scope.fileCount,
    closureSha256: first.closureSha256, applicabilitySha256: applicability.applicabilitySha256,
    externalToolchainSha256: externalToolchain.descriptorSha256,
    counts: applicability.counts, locked: applicability.locked.status,
    max: applicability.max.status, candidateBuilt: false, realGuiExecuted: false };
}

function parseArgs(argv) {
  const args = { check: false, preparation: null, build: null, raw: null, evidence: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--check") args.check = true;
    else if (token === "--preparation") args.preparation = argv[++index];
    else if (token === "--build") args.build = argv[++index];
    else if (token === "--raw") args.raw = argv[++index];
    else if (token === "--evidence") args.evidence = argv[++index];
    else Common.fail("material_shop_verify_argument_unknown", "verify_run", token);
  }
  if (!args.check && (!args.preparation || !args.build || !args.raw)) {
    Common.fail("material_shop_verify_arguments_invalid", "verify_run",
      "--check or preparation+build+raw journey is required");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const value = args.check ? checkCurrentTree() : verify(args);
    process.stdout.write(JSON.stringify(args.check ? value : { ok: true,
      result: value.evidence.result, evidenceSha256: value.evidence.evidenceSha256,
      e2eVerified: false, promoted: false }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { MAXIMUM_RAW_JOURNEY_BYTES, artifact, checkCurrentTree, parseArgs,
  readRawCandidateJourney, verify };
