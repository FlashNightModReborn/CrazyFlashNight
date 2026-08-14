#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const Common = require("./common");
const JourneyVerifier = require("./journey-verifier");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const RunOperationLease = require("./run-operation-lease");

const ELIGIBILITY_SCHEMA =
  "workbench-live-e2e.material-shop.post-release-finalization-eligibility.v1";
const PROTECTED_SCOPE_BOOTSTRAP_SCHEMA =
  "workbench-live-e2e.material-shop.post-release-protected-scope-bootstrap.v1";
const MIGRATION_CASE_ID = "a5-material-shop-agent-20260813t1903-post-release-v1";
const RUN_ID = "a5-material-shop-agent-20260813t1903";
const LEGACY_BLOCKER_NAME = "recovery-blocker-1786619711229-5187fbae.json";
const LEGACY_BLOCKER_FILE_SHA256 =
  "48ad52cb9b30aa6120c42c50d5920577c4655aa0cf4480bb9ead26c7c9bb2102";
const LEGACY_BLOCKER_SHA256 =
  "8057849f8abd70c37da8ff0252547bad2e10671fa95cf0b57040427d6e92800f";
const OFFICIAL_INSPECT_RELATIVE_PATH =
  "tmp/workbench-live-e2e/offline-recovery-receipts/"
  + "20260813111537225-inspect-cf7_agent_a5_material_shop_run-24520-28e143421af2.json";
const OFFICIAL_INSPECT_FILE_SHA256 =
  "ad551889329516e36b77d906d71681b312e3a3f12f48fdbb69ef98e72e40983e";
const RAW_SHA256 = "af1940ebadc40f0cd61099cd17cba630776d41c5e033fc1a636d7403621c88d6";
const EVIDENCE_SHA256 =
  "6d0f61b7f7964809d0ae0ec15a65e69a3d868270d9c7eec0338c4a66868c71b5";
const INTENT_SHA256 = "be443a891da718ad49fb2d9a6ca588b628b229085d3f2712eb19aa2e3a8541ae";
const PREPARATION_SHA256 =
  "c21aa7e18d6af758fd6d2d4f8a914566497de60ff585c0c59af1d7031a760598";
const BUILD_SHA256 = "78d420b1755b29d324777438433a37875606c037e38f0980741603436c58d5e1";
const TARGET_SHA256 = "746f3cf740935d82017ae28ea7d9f868a24be8d39504c3a78e3b2f01292e8f7a";
const TARGET_BYTES = 32730;
const TERMINAL_SHA256 =
  "07dc765a54984ff9e27a4fae6f8ed0451027494c0b26b59e87966c57a1e51c5b";
const TERMINAL_ARCHIVE_SHA256 =
  "8d30a60dde3cd687f905a80981648d7d7e6fc1ec26eacde97322c4c5252a087d";
const FINALIZATION_REQUIRED_NAME = "release-finalization-required.json";
const FINALIZATION_BLOCKER_SCHEMA =
  "workbench-live-e2e.material-shop.release-finalization-blocker.v1";
const FINALIZATION_STOP_LINE =
  "Run only the eligibility-bound canonical clone release finalizer; do not retry, reseed, restore, or edit the target.";
const FROZEN_ELIGIBILITY_NAME =
  "post-release-finalization-eligibility-85e2fddba8152861.json";
const FROZEN_ELIGIBILITY_BYTES = 10589;
const FROZEN_ELIGIBILITY_FILE_SHA256 =
  "e35a364588cdca191015d20df53062bb2d88a5c3783a6835a4b8105ed2263f08";
const FROZEN_ELIGIBILITY_SHA256 =
  "85e2fddba81528619b34244ae070f8e0a0a58b6f160d2e6f97d8bf0206d32782";
const FROZEN_REQUIRED_BLOCKER_BYTES = 15610;
const FROZEN_REQUIRED_BLOCKER_FILE_SHA256 =
  "b31726ac4db16c171a88750c1e8f694bc21c60b33cada6f7f5f7b642b6d4c622";
const FROZEN_REQUIRED_BLOCKER_SHA256 =
  "8c872056bd8946f57992e529a261af625bed51c6935face3c47c311f85be1516";
const FROZEN_CURRENT_PROGRAMS_SHA256 =
  "b7b91a04b431d70bc7212a104b2bdfc639484dc39e3fc96bda22f5ea06067437";
const FROZEN_VALIDATION_TOKEN = Symbol("t1903-frozen-program-validation");
const FROZEN_CURRENT_PROGRAMS = Object.freeze([
  Object.freeze({
    relativePath: "tools/workbench-live-e2e/material-shop/admit-post-release-finalization.js",
    bytes: 38381,
    sha256: "b550239ab0b3dcf36d2a7d15d3222b6d940294823de0691cc1433273af9e2f41",
  }),
  Object.freeze({
    relativePath: "tools/workbench-live-e2e/material-shop/build-candidate.js",
    bytes: 32693,
    sha256: "38dd8aeb995eae023a82b34fac37e57dc1a6d3e615dced8d26d2acfa8739aac4",
  }),
  Object.freeze({
    relativePath: "tools/workbench-live-e2e/material-shop/finalize-clone-release.js",
    bytes: 25370,
    sha256: "42100b7c283c60ca3838cf9d78d6e4b3d36edcf48ae11b6c4fde41aa1d2cecf3",
  }),
  Object.freeze({
    relativePath: "tools/workbench-live-e2e/material-shop/materialize.js",
    bytes: 93938,
    sha256: "0107c92a071f3b36a8b5d492f0749011815c7d91bf5f369498011a7481d1c809",
  }),
  Object.freeze({
    relativePath: "tools/workbench-live-e2e/material-shop/verify-run.js",
    bytes: 6531,
    sha256: "26d460673ba6c0325a1fbb894ef347b3de0d4102cc923c4215e39d8af6d58013",
  }),
]);

const HISTORICAL_SOURCES = Object.freeze([
  ["tools/workbench-live-e2e/material-shop/run-live-journey.js",
    "ee40d5be0aa1f768c7867bd114e91142272385503f5f8845ee0df0fc41dc088c"],
  ["tools/workbench-live-e2e/material-shop/finalize-clone-release.js",
    "e7167f1f4be9f6bb84d591a2448ffcb44114d22fe57e4b54e7a230a41391c5d8"],
  ["tools/workbench-live-e2e/material-shop/materialize.js",
    "ca5dd67805bdeb50ea22e4cec400f43e4bb66cd3df87fdd5ca911ab56db65d33"],
  ["tools/workbench-live-e2e/npc/shared-adapter.js",
    "beffbd5f158408a52b5a115cf42c8c0e3c51790063c8c3faa555aab3c2b56e1f"],
  ["tools/workbench-live-e2e/lib/clone-save-guard.js",
    "16f497228de73617429e5c8fee6c9eee599fe30b8df86fcf99bdc17d2e72b892"],
]);

function fail(message, details) {
  Common.fail("material_shop_post_release_eligibility_invalid",
    "post_release_finalization", message, details);
}

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function artifact(filePath, maximumBytes) {
  const file = Evidence.readExactRegularFile(filePath, {
    phase: "post_release_finalization", maximumBytes: maximumBytes || 16 * 1024 * 1024,
  });
  return { bytes: file.length, sha256: file.sha256, value: (() => {
    try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
    catch (error) { fail("post-release artifact is not valid JSON", { filePath, error: error.message }); }
  })() };
}

function eligibilityFileName(value) {
  const digest = typeof value === "string" ? value : value && value.eligibilitySha256;
  if (!Common.SHA256_RE.test(String(digest || ""))) fail("eligibility digest is invalid");
  return "post-release-finalization-eligibility-" + digest.slice(0, 16) + ".json";
}

function canonicalArgs(context) {
  const runDir = path.resolve(context.preparation.runDir);
  return {
    preparation: path.join(runDir, "preparation.json"),
    build: path.join(runDir, "candidate-build.json"),
    raw: path.join(runDir, "raw-candidate-journey.json"),
    evidence: path.join(runDir, "journey-evidence.json"),
    intent: path.join(runDir, "clone-release-intent.json"),
    out: path.join(runDir, "release.json"),
  };
}

function recoveryCommand(context) {
  const args = canonicalArgs(context);
  return ["node", path.join(Common.CANONICAL_ROOT, "tools", "workbench-live-e2e",
    "material-shop", "finalize-clone-release.js"),
  "--preparation", args.preparation, "--build", args.build,
  "--raw", args.raw, "--evidence", args.evidence,
  "--intent", args.intent, "--out", args.out];
}

function validateOfficialInspectReceipt(value, resourcesRoot) {
  Common.exactKeys(value, ["apiVersion", "authorizationConfirmed", "completedAt",
    "evidenceSha256", "expectedLockSha256", "expectedRecoveryRecordSha256",
    "expectedRecoveryStatus", "operation", "result", "runtimeObservations", "schema", "slot"],
  "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  const result = value.result;
  const runtime = value.runtimeObservations;
  if (Array.isArray(runtime) && runtime.length === 1) {
    Common.exactKeys(runtime[0], ["observedAt", "pids", "processCount"],
      "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  }
  if (value.schema !== "workbench-live-e2e.offline-clone-recovery-receipt.v1"
      || value.apiVersion !== CloneGuard.API_VERSION || value.operation !== "inspect"
      || value.authorizationConfirmed !== false
      || value.slot !== "cf7_agent_a5_material_shop_run"
      || value.expectedLockSha256 !== null || value.expectedRecoveryRecordSha256 !== null
      || value.expectedRecoveryStatus !== null
      || !Number.isFinite(Date.parse(value.completedAt))
      || value.evidenceSha256 !== digestWithout(value, "evidenceSha256")
      || !Array.isArray(runtime) || runtime.length !== 1
      || runtime[0].processCount !== 0 || !Array.isArray(runtime[0].pids)
      || runtime[0].pids.length !== 0 || !Number.isFinite(Date.parse(runtime[0].observedAt))
      || !result) {
    fail("official offline inspection does not prove an unowned released clone");
  }
  validateAbsentCloneInspection(result, resourcesRoot, "cf7_agent_a5_material_shop_run");
  return value;
}

function validateLegacyBlocker(value) {
  if (!value || value.schema !== "workbench-live-e2e.material-shop.recovery-blocker.v1"
      || value.runId !== RUN_ID || value.targetSlot !== "cf7_agent_a5_material_shop_run"
      || value.commitMayHaveReachedAuthority !== true
      || !value.originalError
      || value.originalError.code !== "material_shop_ignored_output_foreign"
      || value.originalError.phase !== "materialize_verify"
      || value.cleanupError !== null || value.blockerSha256 !== LEGACY_BLOCKER_SHA256
      || value.blockerSha256 !== digestWithout(value, "blockerSha256")) {
    fail("legacy recovery blocker is not the exact t1903 post-release classification error");
  }
  return value;
}

function freshInspection(context) {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  const inspection = CloneGuard.inspectCloneLock({
    root: context.preparation.resourcesRoot, slot: context.plan.slots.targetSlot,
  });
  if (inspection.lockPresent !== false || inspection.ownerState !== "absent"
      || inspection.recoveryPresent !== false || inspection.recoveryStatus !== null) {
    fail("fresh clone inspection no longer proves the released state");
  }
  const value = { observedAt: new Date().toISOString(), launcherProcessCount: 0,
    cloneInspection: inspection };
  value.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function sourceDescriptor(root, relativePath, expectedSha256) {
  const resolved = Common.resolveWithin(root, relativePath, "post_release_finalization");
  const file = Evidence.readExactRegularFile(resolved.absolute, {
    phase: "post_release_finalization", maximumBytes: 16 * 1024 * 1024,
  });
  if (expectedSha256 && file.sha256 !== expectedSha256) {
    fail("historical source binding differs from the t1903 executed bytes", { relativePath });
  }
  return { relativePath, bytes: file.length, sha256: file.sha256 };
}

function currentProgramDescriptors(relativePaths) {
  const paths = relativePaths || [
    "tools/workbench-live-e2e/material-shop/admit-post-release-finalization.js",
    "tools/workbench-live-e2e/material-shop/build-candidate.js",
    "tools/workbench-live-e2e/material-shop/finalize-clone-release.js",
    "tools/workbench-live-e2e/material-shop/materialize.js",
    "tools/workbench-live-e2e/material-shop/verify-run.js",
  ];
  return paths.map((relativePath) => sourceDescriptor(Common.CANONICAL_ROOT, relativePath));
}

function validateFrozenProgramDescriptors(value) {
  if (Evidence.canonicalJson(value) !== Evidence.canonicalJson(FROZEN_CURRENT_PROGRAMS)
      || Evidence.sha256Text(Evidence.canonicalJson(value))
        !== FROZEN_CURRENT_PROGRAMS_SHA256) {
    fail("frozen t1903 program descriptors differ from the immutable eligibility bytes");
  }
  return value;
}

function assertFrozenEligibilityArtifact(filePath, value) {
  const resolved = path.resolve(filePath);
  const file = artifact(resolved, FROZEN_ELIGIBILITY_BYTES);
  if (path.basename(resolved) !== FROZEN_ELIGIBILITY_NAME
      || file.bytes !== FROZEN_ELIGIBILITY_BYTES
      || file.sha256 !== FROZEN_ELIGIBILITY_FILE_SHA256
      || !file.value || file.value.eligibilitySha256 !== FROZEN_ELIGIBILITY_SHA256
      || Evidence.canonicalJson(file.value) !== Evidence.canonicalJson(value)) {
    fail("frozen t1903 eligibility artifact bytes changed");
  }
  validateFrozenProgramDescriptors(file.value.currentPrograms);
  return file.value;
}

function assertFrozenFinalizationArtifact(filePath, value) {
  const resolved = path.resolve(filePath);
  const allowedNames = new Set([FINALIZATION_REQUIRED_NAME,
    "release-finalization-resolved-" + FROZEN_REQUIRED_BLOCKER_SHA256.slice(0, 16) + ".json"]);
  const file = artifact(resolved, FROZEN_REQUIRED_BLOCKER_BYTES);
  const eligibility = file.value && file.value.cleanupResult
    && file.value.cleanupResult.postReleaseEligibility;
  if (!allowedNames.has(path.basename(resolved))
      || file.bytes !== FROZEN_REQUIRED_BLOCKER_BYTES
      || file.sha256 !== FROZEN_REQUIRED_BLOCKER_FILE_SHA256
      || !file.value || file.value.blockerSha256 !== FROZEN_REQUIRED_BLOCKER_SHA256
      || !eligibility || eligibility.eligibilitySha256 !== FROZEN_ELIGIBILITY_SHA256
      || Evidence.canonicalJson(file.value) !== Evidence.canonicalJson(value)) {
    fail("frozen t1903 finalization blocker artifact bytes changed");
  }
  validateFrozenProgramDescriptors(eligibility.currentPrograms);
  return file.value;
}

function validateBootstrapPreparation(preparation, optional) {
  if (!preparation || preparation.runId !== RUN_ID) {
    if (optional === true) return false;
    fail("protected-scope bootstrap is restricted to the frozen t1903 run");
  }
  const expectedRunDir = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", RUN_ID);
  const expectedResourcesRoot = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    Materialize.MATERIALIZED_DIRECTORY, RUN_ID, "resources");
  Common.exactKeys(preparation.slots, ["seedSlot", "targetSlot", "recoverySlot"],
    "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  if (preparation.preparationSha256 !== PREPARATION_SHA256
      || !samePath(preparation.runDir, expectedRunDir)
      || !samePath(preparation.resourcesRoot, expectedResourcesRoot)
      || preparation.slots.seedSlot !== "cf7_agent_a5_material_shop_seed"
      || preparation.slots.targetSlot !== "cf7_agent_a5_material_shop_run"
      || preparation.slots.recoverySlot !== "cf7_agent_a5_material_shop_recovery") {
    fail("protected-scope bootstrap preparation differs from the exact t1903 identity");
  }
  return true;
}

function protectedScopeBootstrapArtifacts(preparation) {
  const blockerFile = artifact(path.join(preparation.runDir, LEGACY_BLOCKER_NAME),
    1024 * 1024);
  if (blockerFile.sha256 !== LEGACY_BLOCKER_FILE_SHA256) {
    fail("protected-scope bootstrap legacy blocker bytes changed");
  }
  validateLegacyBlocker(blockerFile.value);
  const inspectPath = Common.resolveWithin(preparation.resourcesRoot,
    OFFICIAL_INSPECT_RELATIVE_PATH, "post_release_finalization").absolute;
  const inspectFile = artifact(inspectPath, 1024 * 1024);
  if (inspectFile.sha256 !== OFFICIAL_INSPECT_FILE_SHA256) {
    fail("protected-scope bootstrap official inspection bytes changed");
  }
  validateOfficialInspectReceipt(inspectFile.value, preparation.resourcesRoot);
  return { blockerFile, inspectFile };
}

function validateProtectedScopeBootstrap(value, preparation) {
  validateBootstrapPreparation(preparation, false);
  Common.exactKeys(value, ["schema", "migrationCaseId", "runId", "preparationSha256",
    "resourcesRoot", "targetSlot", "legacyBlocker", "officialInspectReceipt",
    "supplementalGeneratedOutputs", "bootstrapSha256"],
  "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  Common.exactKeys(value.legacyBlocker, ["relativePath", "bytes", "sha256",
    "blockerSha256", "value"], "material_shop_post_release_eligibility_invalid",
  "post_release_finalization");
  Common.exactKeys(value.officialInspectReceipt, ["relativePath", "bytes", "sha256", "value"],
    "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  const artifacts = protectedScopeBootstrapArtifacts(preparation);
  const expectedBlocker = { relativePath: LEGACY_BLOCKER_NAME,
    bytes: artifacts.blockerFile.bytes, sha256: artifacts.blockerFile.sha256,
    blockerSha256: artifacts.blockerFile.value.blockerSha256,
    value: artifacts.blockerFile.value };
  const expectedInspect = { relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
    bytes: artifacts.inspectFile.bytes, sha256: artifacts.inspectFile.sha256,
    value: artifacts.inspectFile.value };
  const expectedSupplemental = [{ relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
    bytes: artifacts.inspectFile.bytes, sha256: artifacts.inspectFile.sha256 }];
  if (value.schema !== PROTECTED_SCOPE_BOOTSTRAP_SCHEMA
      || value.migrationCaseId !== MIGRATION_CASE_ID || value.runId !== RUN_ID
      || value.preparationSha256 !== PREPARATION_SHA256
      || !samePath(value.resourcesRoot, preparation.resourcesRoot)
      || value.targetSlot !== preparation.slots.targetSlot
      || Evidence.canonicalJson(value.legacyBlocker)
        !== Evidence.canonicalJson(expectedBlocker)
      || Evidence.canonicalJson(value.officialInspectReceipt)
        !== Evidence.canonicalJson(expectedInspect)
      || Evidence.canonicalJson(value.supplementalGeneratedOutputs)
        !== Evidence.canonicalJson(expectedSupplemental)
      || value.bootstrapSha256 !== digestWithout(value, "bootstrapSha256")) {
    fail("protected-scope bootstrap ticket is malformed or detached from exact t1903 evidence");
  }
  return value;
}

function captureProtectedScopeBootstrap(preparation, options) {
  const settings = options || {};
  Common.exactKeys(settings, ["optional"], "material_shop_post_release_eligibility_invalid",
    "post_release_finalization");
  if (!validateBootstrapPreparation(preparation, settings.optional === true)) return null;
  const artifacts = protectedScopeBootstrapArtifacts(preparation);
  const value = { schema: PROTECTED_SCOPE_BOOTSTRAP_SCHEMA,
    migrationCaseId: MIGRATION_CASE_ID, runId: RUN_ID,
    preparationSha256: PREPARATION_SHA256,
    resourcesRoot: preparation.resourcesRoot, targetSlot: preparation.slots.targetSlot,
    legacyBlocker: { relativePath: LEGACY_BLOCKER_NAME,
      bytes: artifacts.blockerFile.bytes, sha256: artifacts.blockerFile.sha256,
      blockerSha256: artifacts.blockerFile.value.blockerSha256,
      value: artifacts.blockerFile.value },
    officialInspectReceipt: { relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
      bytes: artifacts.inspectFile.bytes, sha256: artifacts.inspectFile.sha256,
      value: artifacts.inspectFile.value },
    supplementalGeneratedOutputs: [{ relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
      bytes: artifacts.inspectFile.bytes, sha256: artifacts.inspectFile.sha256 }] };
  value.bootstrapSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateProtectedScopeBootstrap(value, preparation);
}

function validateAbsentCloneInspection(value, resourcesRoot, targetSlot) {
  Common.exactKeys(value, ["schema", "apiVersion", "observedAt", "slot", "lockPath",
    "lockPresent", "recordSha256", "ownerPid", "ownerProcessStartUtcTicks",
    "observedProcessStartUtcTicks", "ownerState", "recoveryPresent", "recoveryStatus",
    "recoveryRecordSha256", "evidenceSha256"],
  "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  if (value.schema !== "workbench-live-e2e.clone-lock-inspection.v1"
      || value.apiVersion !== CloneGuard.API_VERSION
      || value.slot !== targetSlot
      || !Number.isFinite(Date.parse(value.observedAt))
      || value.lockPresent !== false || value.recordSha256 !== null
      || value.ownerPid !== null || value.ownerProcessStartUtcTicks !== null
      || value.observedProcessStartUtcTicks !== null || value.ownerState !== "absent"
      || value.recoveryPresent !== false || value.recoveryStatus !== null
      || value.recoveryRecordSha256 !== null
      || value.evidenceSha256 !== digestWithout(value, "evidenceSha256")
      || !samePath(value.lockPath, path.join(resourcesRoot, "tmp", "workbench-live-e2e",
        "locks", targetSlot + ".clone.lock"))) {
    fail("clone inspection does not prove the exact released target state");
  }
  return value;
}

function validateFreshInspection(value, resourcesRoot, targetSlot) {
  Common.exactKeys(value, ["observedAt", "launcherProcessCount", "cloneInspection",
    "evidenceSha256"], "material_shop_post_release_eligibility_invalid",
  "post_release_finalization");
  if (!Number.isFinite(Date.parse(value.observedAt)) || value.launcherProcessCount !== 0
      || value.evidenceSha256 !== digestWithout(value, "evidenceSha256")) {
    fail("fresh inspection evidence is malformed or does not prove zero Launcher processes");
  }
  validateAbsentCloneInspection(value.cloneInspection, resourcesRoot, targetSlot);
  return value;
}

function validateOperationHistoryEntries(history, terminal, lease) {
  if (history.length !== 1 || history[0].kind !== "terminal"
      || history[0].name !== terminal.archiveName
      || history[0].bytes !== terminal.archiveBytes
      || history[0].sha256 !== terminal.archiveSha256
      || Evidence.canonicalJson(history[0].lease) !== Evidence.canonicalJson(lease)) {
    fail("operation history is not the sole exact t1903 terminal archive", {
      history: history.map((entry) => ({ name: entry.name, kind: entry.kind })),
    });
  }
  return history[0];
}

function validateOperationHistory(runDir, terminal, lease) {
  const names = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile()
      && /^(?:run-operation-terminal-|run-operation-stale-resolved-).*\.json$/i.test(entry.name))
    .map((entry) => entry.name).sort();
  if (Evidence.canonicalJson(names) !== Evidence.canonicalJson([terminal.archiveName])) {
    fail("operation directory contains an extra or non-canonical terminal/stale marker", { names });
  }
  return validateOperationHistoryEntries(
    RunOperationLease.historyMarkers(runDir), terminal, lease);
}

function admissionArtifactState(runDir) {
  const names = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile()).map((entry) => entry.name).sort();
  const eligibilityNames = names.filter((name) =>
    /^post-release-finalization-eligibility-[a-f0-9]{16}\.json$/.test(name));
  if (eligibilityNames.length > 1) {
    fail("multiple post-release eligibility artifacts cannot be replayed", { eligibilityNames });
  }
  return { names, eligibilityName: eligibilityNames[0] || null,
    requiredMarkerPresent: names.includes(FINALIZATION_REQUIRED_NAME) };
}

function assertNoLaterArtifacts(runDir, allowEligibilityName, allowRequiredMarker) {
  const forbiddenExact = ["release.json", "static-gate.json", "review-request.json",
    "independent-review-receipt.json", "acceptance.json", "worktree-release.json",
    "worktree-removal-intent.json"];
  if (!allowRequiredMarker) forbiddenExact.push(FINALIZATION_REQUIRED_NAME);
  const names = admissionArtifactState(runDir).names;
  const forbidden = names.filter((name) => forbiddenExact.includes(name.toLowerCase())
    || /^release-finalization-resolved-[a-f0-9]{16}\.json$/i.test(name)
    || /^worktree-removal-resolved-[a-f0-9]{16}\.json$/i.test(name)
    || /^(?:release\.json|release-finalization-required\.json|worktree-release\.json|worktree-removal-intent\.json|post-release-finalization-eligibility-[a-f0-9]{16}\.json)\.staged-[a-f0-9]{16}$/i.test(name)
    || /^post-release-finalization-eligibility-[a-f0-9]{16}\.json$/i.test(name)
      && name !== allowEligibilityName);
  if (forbidden.length) fail("later release or acceptance artifacts already exist", { forbidden });
  return names;
}

function validateFrozenAdmissionState(state) {
  if (!state || state.eligibilityName !== FROZEN_ELIGIBILITY_NAME
      || state.requiredMarkerPresent !== true) {
    fail("t1903 admission is reuse-only after its immutable eligibility and marker exist", {
      eligibilityName: state && state.eligibilityName,
      requiredMarkerPresent: state && state.requiredMarkerPresent,
    });
  }
  return state;
}

function validateContext(context) {
  if (!context || !context.preparation || !context.plan || !context.build || !context.raw
      || !context.evidence || context.plan.runId !== RUN_ID
      || context.preparation.runId !== RUN_ID
      || context.preparation.preparationSha256 !== PREPARATION_SHA256
      || context.build.buildSha256 !== BUILD_SHA256
      || context.raw.rawSha256 !== RAW_SHA256
      || context.evidence.evidenceSha256 !== EVIDENCE_SHA256
      || context.raw.runId !== RUN_ID
      || context.evidence.runId !== RUN_ID
      || context.evidence.boundaries.e2eVerified !== false
      || context.evidence.journey.routes.unlocked.target.itemName !== "食用油"
      || context.evidence.journey.routes.unlocked.quantity !== 1
      || context.evidence.journey.routes.unlocked.saleCount !== 0
      || context.evidence.journey.persistence.restartOwned !== 1
      || context.evidence.journey.persistence.settledMoney !== 2402769
      || context.evidence.journey.persistence.archiveSemanticSha256
        !== context.evidence.journey.persistence.restartSemanticSha256) {
    fail("strict replay context is not the exact successful t1903 candidate journey");
  }
  const terminal = JourneyVerifier.verifyOperationTerminal(
    context.raw, context.preparation.runDir, context.build);
  if (terminal.terminalSha256 !== TERMINAL_SHA256
      || terminal.archiveSha256 !== TERMINAL_ARCHIVE_SHA256) {
    fail("operation terminal differs from the sole t1903 live execution archive");
  }
  validateOperationHistory(context.preparation.runDir, terminal, context.raw.operationLease);
  return terminal;
}

function createEligibility(context) {
  const terminal = validateContext(context);
  const runDir = path.resolve(context.preparation.runDir);
  const resourcesRoot = path.resolve(context.preparation.resourcesRoot);
  const blockerPath = path.join(runDir, LEGACY_BLOCKER_NAME);
  const blockerFile = artifact(blockerPath, 1024 * 1024);
  if (blockerFile.sha256 !== LEGACY_BLOCKER_FILE_SHA256) fail("legacy blocker bytes changed");
  validateLegacyBlocker(blockerFile.value);

  const inspectPath = Common.resolveWithin(resourcesRoot, OFFICIAL_INSPECT_RELATIVE_PATH,
    "post_release_finalization").absolute;
  const inspectFile = artifact(inspectPath, 1024 * 1024);
  if (inspectFile.sha256 !== OFFICIAL_INSPECT_FILE_SHA256) fail("official inspect receipt changed");
  validateOfficialInspectReceipt(inspectFile.value, resourcesRoot);

  const targetPath = path.join(resourcesRoot, "saves", "cf7_agent_a5_material_shop_run.json");
  const target = Evidence.readExactRegularFile(targetPath, {
    phase: "post_release_finalization", maximumBytes: 1024 * 1024,
  });
  if (target.length !== TARGET_BYTES || target.sha256 !== TARGET_SHA256
      || fs.existsSync(path.join(Common.CANONICAL_ROOT, "saves",
        "cf7_agent_a5_material_shop_run.json"))) {
    fail("released materialized target is not the exact sealed restart artifact");
  }

  const sources = HISTORICAL_SOURCES.map(([relativePath, sha256]) =>
    sourceDescriptor(resourcesRoot, relativePath, sha256));
  const currentPrograms = currentProgramDescriptors();
  const args = canonicalArgs(context);
  const intent = Prepare.readJson(args.intent, "post_release_finalization");
  const Finalize = require("./finalize-clone-release");
  Finalize.validateIntent(intent, context);
  if (intent.intentSha256 !== INTENT_SHA256) fail("clone release intent changed");

  const value = { schema: ELIGIBILITY_SCHEMA, migrationCaseId: MIGRATION_CASE_ID,
    createdAt: new Date().toISOString(), runId: RUN_ID,
    preparationSha256: PREPARATION_SHA256, buildSha256: BUILD_SHA256,
    rawSha256: RAW_SHA256, journeyEvidenceSha256: EVIDENCE_SHA256,
    releaseIntentSha256: INTENT_SHA256,
    target: { relativePath: "saves/cf7_agent_a5_material_shop_run.json",
      bytes: target.length, sha256: target.sha256 },
    persistence: { baselineMoney: 2403069, settledMoney: 2402769,
      beforeOwned: 0, restartOwned: 1,
      semanticSha256: context.evidence.journey.persistence.restartSemanticSha256 },
    operationTerminal: terminal,
    legacyBlocker: { relativePath: LEGACY_BLOCKER_NAME, bytes: blockerFile.bytes,
      sha256: blockerFile.sha256, blockerSha256: blockerFile.value.blockerSha256,
      value: blockerFile.value },
    officialInspectReceipt: { relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
      bytes: inspectFile.bytes, sha256: inspectFile.sha256, value: inspectFile.value },
    freshInspection: freshInspection(context), historicalSources: sources,
    currentPrograms,
    supplementalGeneratedOutputs: [{ relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
      bytes: inspectFile.bytes, sha256: inspectFile.sha256 }],
    recoveryCommand: recoveryCommand(context) };
  value.eligibilitySha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateEligibility(value, context, { skipArtifact: true });
}

function validateEligibility(value, context, options) {
  const keys = ["schema", "migrationCaseId", "createdAt", "runId",
    "preparationSha256", "buildSha256", "rawSha256", "journeyEvidenceSha256",
    "releaseIntentSha256", "target", "persistence", "operationTerminal", "legacyBlocker",
    "officialInspectReceipt", "freshInspection", "historicalSources", "currentPrograms",
    "supplementalGeneratedOutputs", "recoveryCommand", "eligibilitySha256"];
  Common.exactKeys(value, keys, "material_shop_post_release_eligibility_invalid",
    "post_release_finalization");
  const terminal = validateContext(context);
  const runDir = path.resolve(context.preparation.runDir);
  const resourcesRoot = path.resolve(context.preparation.resourcesRoot);
  Common.exactKeys(value.target, ["relativePath", "bytes", "sha256"],
    "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  Common.exactKeys(value.persistence, ["baselineMoney", "settledMoney", "beforeOwned",
    "restartOwned", "semanticSha256"], "material_shop_post_release_eligibility_invalid",
  "post_release_finalization");
  Common.exactKeys(value.legacyBlocker, ["relativePath", "bytes", "sha256",
    "blockerSha256", "value"], "material_shop_post_release_eligibility_invalid",
  "post_release_finalization");
  Common.exactKeys(value.officialInspectReceipt, ["relativePath", "bytes", "sha256", "value"],
    "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  const expectedTarget = { relativePath: "saves/cf7_agent_a5_material_shop_run.json",
    bytes: TARGET_BYTES, sha256: TARGET_SHA256 };
  const journeyPersistence = context.evidence.journey.persistence;
  const expectedPersistence = { baselineMoney: journeyPersistence.baselineMoney,
    settledMoney: journeyPersistence.settledMoney, beforeOwned: journeyPersistence.beforeOwned,
    restartOwned: journeyPersistence.restartOwned,
    semanticSha256: journeyPersistence.restartSemanticSha256 };
  if (value.schema !== ELIGIBILITY_SCHEMA || value.migrationCaseId !== MIGRATION_CASE_ID
      || value.runId !== RUN_ID || !Number.isFinite(Date.parse(value.createdAt))
      || value.preparationSha256 !== PREPARATION_SHA256 || value.buildSha256 !== BUILD_SHA256
      || value.rawSha256 !== RAW_SHA256 || value.journeyEvidenceSha256 !== EVIDENCE_SHA256
      || value.releaseIntentSha256 !== INTENT_SHA256
      || value.eligibilitySha256 !== digestWithout(value, "eligibilitySha256")
      || Evidence.canonicalJson(value.target) !== Evidence.canonicalJson(expectedTarget)
      || Evidence.canonicalJson(value.persistence) !== Evidence.canonicalJson(expectedPersistence)
      || value.persistence.baselineMoney !== 2403069 || value.persistence.settledMoney !== 2402769
      || value.persistence.beforeOwned !== 0 || value.persistence.restartOwned !== 1
      || Evidence.canonicalJson(value.operationTerminal) !== Evidence.canonicalJson(terminal)
      || Evidence.canonicalJson(value.recoveryCommand)
        !== Evidence.canonicalJson(recoveryCommand(context))) {
    fail("eligibility record is malformed or detached from t1903");
  }
  validateLegacyBlocker(value.legacyBlocker.value);
  const blockerFile = artifact(path.join(runDir, LEGACY_BLOCKER_NAME), 1024 * 1024);
  if (value.legacyBlocker.relativePath !== LEGACY_BLOCKER_NAME
      || value.legacyBlocker.bytes !== blockerFile.bytes
      || value.legacyBlocker.sha256 !== blockerFile.sha256
      || value.legacyBlocker.blockerSha256 !== LEGACY_BLOCKER_SHA256
      || blockerFile.sha256 !== LEGACY_BLOCKER_FILE_SHA256
      || Evidence.canonicalJson(value.legacyBlocker.value)
        !== Evidence.canonicalJson(blockerFile.value)) fail("legacy blocker binding drifted");

  validateOfficialInspectReceipt(value.officialInspectReceipt.value, resourcesRoot);
  const inspectPath = Common.resolveWithin(resourcesRoot, OFFICIAL_INSPECT_RELATIVE_PATH,
    "post_release_finalization").absolute;
  const inspect = artifact(inspectPath, 1024 * 1024);
  if (value.officialInspectReceipt.relativePath !== OFFICIAL_INSPECT_RELATIVE_PATH
      || value.officialInspectReceipt.bytes !== inspect.bytes
      || value.officialInspectReceipt.sha256 !== inspect.sha256
      || inspect.sha256 !== OFFICIAL_INSPECT_FILE_SHA256
      || Evidence.canonicalJson(value.officialInspectReceipt.value)
        !== Evidence.canonicalJson(inspect.value)
      || Evidence.canonicalJson(value.supplementalGeneratedOutputs)
        !== Evidence.canonicalJson([{ relativePath: OFFICIAL_INSPECT_RELATIVE_PATH,
          bytes: inspect.bytes, sha256: inspect.sha256 }])) {
    fail("supplemental official inspection binding drifted");
  }
  validateFreshInspection(value.freshInspection, resourcesRoot, context.plan.slots.targetSlot);
  if (Evidence.canonicalJson(value.historicalSources)
      !== Evidence.canonicalJson(HISTORICAL_SOURCES.map(([relativePath, sha256]) =>
        sourceDescriptor(resourcesRoot, relativePath, sha256)))) {
    fail("historical phase source bindings drifted");
  }
  const frozenPrograms = options
    && options.frozenCurrentPrograms === FROZEN_VALIDATION_TOKEN;
  const expectedPrograms = frozenPrograms ? FROZEN_CURRENT_PROGRAMS
    : currentProgramDescriptors();
  if (Evidence.canonicalJson(value.currentPrograms) !== Evidence.canonicalJson(expectedPrograms)) {
    fail("canonical finalization program bindings drifted");
  }
  if (frozenPrograms) validateFrozenProgramDescriptors(value.currentPrograms);
  const target = Evidence.readExactRegularFile(path.join(resourcesRoot,
    value.target.relativePath.replace(/\//g, path.sep)), {
    phase: "post_release_finalization", maximumBytes: 1024 * 1024,
  });
  if (target.length !== value.target.bytes || target.sha256 !== value.target.sha256
      || fs.existsSync(path.join(Common.CANONICAL_ROOT, "saves",
        "cf7_agent_a5_material_shop_run.json"))) {
    fail("target changed after eligibility capture");
  }
  const current = CloneGuard.inspectCloneLock({ root: resourcesRoot,
    slot: context.plan.slots.targetSlot });
  validateAbsentCloneInspection(current, resourcesRoot, context.plan.slots.targetSlot);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);

  if (!options || options.skipArtifact !== true) {
    const name = eligibilityFileName(value);
    const eligibilityPath = path.join(runDir, name);
    if (frozenPrograms) assertFrozenEligibilityArtifact(eligibilityPath, value);
    else {
      const file = artifact(eligibilityPath, 8 * 1024 * 1024);
      if (Evidence.canonicalJson(file.value) !== Evidence.canonicalJson(value)) {
        fail("eligibility artifact differs from its marker-bound value");
      }
    }
  }
  return value;
}

function validateFrozenEligibility(value, context) {
  return validateEligibility(value, context, {
    skipArtifact: false,
    frozenCurrentPrograms: FROZEN_VALIDATION_TOKEN,
  });
}

function validateFinalizationEligibility(blocker, context) {
  const cleanup = blocker && blocker.cleanupResult;
  if (!cleanup || !cleanup.postReleaseEligibility) return null;
  Common.exactKeys(cleanup, ["releasedBeforeCommit", "cloneAlreadyReleased",
    "runtimeCleanupVerified", "shutdownSucceeded", "preservedForManualRecovery",
    "postReleaseEligibility", "supplementalIgnoredOutputs"],
  "material_shop_post_release_eligibility_invalid", "post_release_finalization");
  const frozen = cleanup.postReleaseEligibility.eligibilitySha256
    === FROZEN_ELIGIBILITY_SHA256;
  const eligibility = frozen
    ? validateFrozenEligibility(cleanup.postReleaseEligibility, context)
    : validateEligibility(cleanup.postReleaseEligibility, context);
  if (cleanup.releasedBeforeCommit !== false || cleanup.cloneAlreadyReleased !== true
      || cleanup.runtimeCleanupVerified !== true || cleanup.shutdownSucceeded !== true
      || cleanup.preservedForManualRecovery !== false || blocker.cleanupError !== null
      || Evidence.canonicalJson(blocker.originalError)
        !== Evidence.canonicalJson(eligibility.legacyBlocker.value.originalError)
      || Evidence.canonicalJson(blocker.recoveryCommand)
        !== Evidence.canonicalJson(eligibility.recoveryCommand)
      || blocker.stopLine !== FINALIZATION_STOP_LINE
      || Evidence.canonicalJson(cleanup.supplementalIgnoredOutputs)
      !== Evidence.canonicalJson(eligibility.supplementalGeneratedOutputs)) {
    fail("finalization marker classification differs from the exact eligibility record");
  }
  return { eligibility,
    supplementalGeneratedOutputs: eligibility.supplementalGeneratedOutputs,
    legacyBlocker: eligibility.legacyBlocker,
    recoveryCommand: eligibility.recoveryCommand };
}

function eligibilityFromFinalizationBlocker(blocker, context) {
  return validateFinalizationEligibility(blocker, context);
}

function supplementalGeneratedFiles(blocker, context) {
  const value = validateFinalizationEligibility(blocker, context);
  return value ? value.supplementalGeneratedOutputs.map((entry) => Object.assign({}, entry)) : [];
}

function readEligibility(filePath, context) {
  const value = Prepare.readJson(filePath, "post_release_finalization");
  return value.eligibilitySha256 === FROZEN_ELIGIBILITY_SHA256
    ? validateFrozenEligibility(value, context) : validateEligibility(value, context);
}

function createFinalizationBlocker(context, eligibility) {
  validateEligibility(eligibility, context, { skipArtifact: true });
  const args = canonicalArgs(context);
  const value = { schema: FINALIZATION_BLOCKER_SCHEMA, recordedAt: new Date().toISOString(),
    runId: RUN_ID, targetSlot: context.plan.slots.targetSlot,
    resourcesRoot: context.preparation.resourcesRoot, commitMayHaveReachedAuthority: true,
    originalError: eligibility.legacyBlocker.value.originalError,
    cleanupResult: { releasedBeforeCommit: false, cloneAlreadyReleased: true,
      runtimeCleanupVerified: true, shutdownSucceeded: true,
      preservedForManualRecovery: false, postReleaseEligibility: eligibility,
      supplementalIgnoredOutputs: eligibility.supplementalGeneratedOutputs },
    cleanupError: null, preparationPath: args.preparation, buildPath: args.build,
    rawPath: args.raw, evidencePath: args.evidence, releaseIntentPath: args.intent,
    releaseOutputPath: args.out, recoveryCommand: eligibility.recoveryCommand,
    stopLine: FINALIZATION_STOP_LINE };
  value.blockerSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  const Finalize = require("./finalize-clone-release");
  return Finalize.validateFinalizationBlocker(value, context, args);
}

function writeAtomicNew(filePath, value) {
  return Materialize.writeJsonAtomicNew(filePath, value);
}

function writeAdmission(context) {
  const runDir = path.resolve(context.preparation.runDir);
  const markerPath = path.join(runDir, FINALIZATION_REQUIRED_NAME);
  const state = validateFrozenAdmissionState(admissionArtifactState(runDir));
  assertNoLaterArtifacts(runDir, FROZEN_ELIGIBILITY_NAME, true);
  const eligibilityPath = path.join(runDir, FROZEN_ELIGIBILITY_NAME);
  const eligibility = readEligibility(eligibilityPath, context);
  const existing = Prepare.readJson(markerPath, "post_release_finalization");
  assertFrozenFinalizationArtifact(markerPath, existing);
  const Finalize = require("./finalize-clone-release");
  const blocker = Finalize.validateFinalizationBlocker(
    existing, context, canonicalArgs(context));
  const binding = validateFinalizationEligibility(blocker, context);
  if (!binding || Evidence.canonicalJson(binding.eligibility)
      !== Evidence.canonicalJson(eligibility)) {
    fail("existing required marker differs from the persisted eligibility record");
  }
  return { eligibility, eligibilityPath, blocker, markerPath };
}

function parseArgs(argv) {
  const args = { preparation: null, build: null, raw: null, evidence: null,
    intent: null, out: null };
  const keys = new Set(Object.keys(args));
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (!token.startsWith("--") || !keys.has(token.slice(2)) || index + 1 >= argv.length) {
      fail("unknown or incomplete adapter argument", { token });
    }
    args[token.slice(2)] = argv[++index];
  }
  if (Object.values(args).some((entry) => !entry)) fail("all finalization artifact paths are required");
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const Finalize = require("./finalize-clone-release");
    const context = Finalize.loadContext(args, { allowFrozenPostReleaseBootstrap: true });
    const canonical = canonicalArgs(context);
    if (Object.keys(canonical).some((key) => !samePath(args[key], canonical[key]))) {
      fail("adapter arguments differ from the exact t1903 canonical run artifacts");
    }
    const result = writeAdmission(context);
    process.stdout.write(JSON.stringify({ ok: true, migrationCaseId: MIGRATION_CASE_ID,
      eligibilitySha256: result.eligibility.eligibilitySha256,
      eligibilityPath: result.eligibilityPath, requiredMarker: result.markerPath,
      recoveryCommand: result.eligibility.recoveryCommand }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

module.exports = { ELIGIBILITY_SCHEMA, FROZEN_CURRENT_PROGRAMS,
  FROZEN_CURRENT_PROGRAMS_SHA256, FROZEN_ELIGIBILITY_BYTES,
  FROZEN_ELIGIBILITY_FILE_SHA256, FROZEN_ELIGIBILITY_NAME, FROZEN_ELIGIBILITY_SHA256,
  FROZEN_REQUIRED_BLOCKER_BYTES, FROZEN_REQUIRED_BLOCKER_FILE_SHA256,
  FROZEN_REQUIRED_BLOCKER_SHA256, MIGRATION_CASE_ID, PROTECTED_SCOPE_BOOTSTRAP_SCHEMA,
  RUN_ID, admissionArtifactState, assertFrozenEligibilityArtifact,
  assertFrozenFinalizationArtifact, assertNoLaterArtifacts, captureProtectedScopeBootstrap,
  createEligibility, createFinalizationBlocker, eligibilityFileName,
  eligibilityFromFinalizationBlocker, currentProgramDescriptors, main, parseArgs, readEligibility,
  supplementalGeneratedFiles, validateAbsentCloneInspection, validateBootstrapPreparation,
  validateEligibility, validateFinalizationEligibility, validateFreshInspection,
  validateFrozenAdmissionState, validateFrozenEligibility, validateFrozenProgramDescriptors,
  validateOfficialInspectReceipt, validateOperationHistoryEntries,
  validateProtectedScopeBootstrap, writeAdmission };

if (require.main === module) main();
