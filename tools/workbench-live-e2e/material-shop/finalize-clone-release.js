#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const Applicability = require("./applicability");
const Build = require("./build-candidate");
const Common = require("./common");
const JourneyVerifier = require("./journey-verifier");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const Protocol = require("./protocol");
const VerifyRun = require("./verify-run");

const INTENT_SCHEMA = "workbench-live-e2e.material-shop.clone-release-intent.v1";
const LEGACY_RELEASE_SCHEMA = "workbench-live-e2e.material-shop.clone-release.v3";
const RELEASE_SCHEMA = "workbench-live-e2e.material-shop.clone-release.v4";
const CONTINUATION_SCHEMA =
  "workbench-live-e2e.material-shop.post-release-finalization-continuation.v1";
const CONTINUATION_MIGRATION_CASE_ID =
  "a5-material-shop-agent-20260813t1903-ordinal-inventory-v1";
const ORDINAL_WITNESS_SCHEMA =
  "workbench-live-e2e.material-shop.ordinal-ignored-output-witness.v1";
const ORDINAL_WITNESS_FILE_COUNT = 456;
const ORDINAL_WITNESS_PATHS_SHA256 =
  "435be00593d891e0ef488eacc4c71cd42dcadd3b37a06b27611643e87da546a3";
const CONTINUATION_PROGRAM_FILES = Object.freeze([
  "launcher/web/modules/inventory-runtime.js",
  "tools/cf7-agent/lib/strict-json.js",
  "tools/lib/legacy-http-auth.js",
  "tools/lib/legacy-http-client.js",
  "tools/lib/runtime-process-identity.js",
  "tools/workbench-live-e2e/crafting/common.js",
  "tools/workbench-live-e2e/crafting/runtime-producer.js",
  "tools/workbench-live-e2e/crafting/source-contract.js",
  "tools/workbench-live-e2e/kshop/common.js",
  "tools/workbench-live-e2e/kshop/png-contract.js",
  "tools/workbench-live-e2e/lib/clone-save-guard.js",
  "tools/workbench-live-e2e/lib/control-contract.js",
  "tools/workbench-live-e2e/lib/evidence-artifact.js",
  "tools/workbench-live-e2e/lib/launcher-observation.js",
  "tools/workbench-live-e2e/lib/playwright-websocket-toolchain.js",
  "tools/workbench-live-e2e/lib/runtime-guard.js",
  "tools/workbench-live-e2e/material-shop/admission.js",
  "tools/workbench-live-e2e/material-shop/admit-post-release-finalization.js",
  "tools/workbench-live-e2e/material-shop/applicability.js",
  "tools/workbench-live-e2e/material-shop/build-candidate.js",
  "tools/workbench-live-e2e/material-shop/candidate-lifecycle.js",
  "tools/workbench-live-e2e/material-shop/capture-verifier.js",
  "tools/workbench-live-e2e/material-shop/common.js",
  "tools/workbench-live-e2e/material-shop/control-channel.js",
  "tools/workbench-live-e2e/material-shop/finalize-clone-release.js",
  "tools/workbench-live-e2e/material-shop/journey-verifier.js",
  "tools/workbench-live-e2e/material-shop/materialize.js",
  "tools/workbench-live-e2e/material-shop/prepare.js",
  "tools/workbench-live-e2e/material-shop/production-closure.js",
  "tools/workbench-live-e2e/material-shop/protocol.js",
  "tools/workbench-live-e2e/material-shop/run-operation-lease.js",
  "tools/workbench-live-e2e/material-shop/scope-manifest.js",
  "tools/workbench-live-e2e/material-shop/trusted-runner-jsonl.js",
  "tools/workbench-live-e2e/material-shop/verify-run.js",
  "tools/workbench-live-e2e/npc/common.js",
  "tools/workbench-live-e2e/npc/production-closure.js",
  "tools/workbench-live-e2e/npc/protocol.js",
  "tools/workbench-live-e2e/npc/shared-adapter.js",
]);
const FINALIZATION_BLOCKER_SCHEMA =
  "workbench-live-e2e.material-shop.release-finalization-blocker.v1";
const FINALIZATION_REQUIRED_NAME = "release-finalization-required.json";
const FINALIZATION_RESOLVED_PREFIX = "release-finalization-resolved-";

function digestWithout(value, key) {
  const unsigned = Object.assign({}, value);
  delete unsigned[key];
  return Evidence.sha256Text(Evidence.canonicalJson(unsigned));
}

function fsyncRegularFile(filePath) {
  const fd = fs.openSync(path.resolve(filePath), "r");
  try { fs.fsyncSync(fd); }
  finally { fs.closeSync(fd); }
  return filePath;
}

function frozenContinuationAdapter() {
  return require("./admit-post-release-finalization");
}

function requiresFrozenContinuation(context) {
  const adapter = frozenContinuationAdapter();
  const preparation = context && context.preparation;
  const plan = context && context.plan;
  const mentionsFrozenRun = preparation && preparation.runId === adapter.RUN_ID
    || plan && plan.runId === adapter.RUN_ID;
  if (!mentionsFrozenRun) return false;
  if (!preparation || !plan || plan.runId !== adapter.RUN_ID) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "the t1903 run identity cannot be detached from its exact preparation and plan");
  }
  adapter.validateBootstrapPreparation(preparation, false);
  return true;
}

function isFrozenContinuationBlocker(value) {
  const adapter = frozenContinuationAdapter();
  const eligibility = value && value.cleanupResult
    && value.cleanupResult.postReleaseEligibility;
  return Boolean(value && value.blockerSha256 === adapter.FROZEN_REQUIRED_BLOCKER_SHA256
    && eligibility && eligibility.eligibilitySha256 === adapter.FROZEN_ELIGIBILITY_SHA256);
}

function validateFrozenContinuationBlockerIdentity(context, blocker) {
  if (requiresFrozenContinuation(context) && !isFrozenContinuationBlocker(blocker)) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "exact t1903 context requires its immutable eligibility and finalization blocker");
  }
  return blocker;
}

function assertFrozenContinuationMarkerFile(filePath, blocker, context) {
  if (requiresFrozenContinuation(context)) {
    validateFrozenContinuationBlockerIdentity(context, blocker);
    frozenContinuationAdapter().assertFrozenFinalizationArtifact(filePath, blocker);
  }
  return blocker;
}

function projectOrdinalInventoryWitness(ignoredOutputInventory) {
  const paths = ignoredOutputInventory && Array.isArray(ignoredOutputInventory.files)
    ? ignoredOutputInventory.files.map((entry) => String(entry.relativePath || "")) : [];
  const ordinalPaths = paths.slice().sort(Materialize.compareOrdinal);
  return { fileCount: paths.length,
    sourceOrderIsOrdinal: Evidence.canonicalJson(paths) === Evidence.canonicalJson(ordinalPaths),
    ordinalPathsSha256: Evidence.sha256Text(Evidence.canonicalJson(ordinalPaths)) };
}

function createOrdinalInventoryWitness(ignoredOutputInventory) {
  const projection = projectOrdinalInventoryWitness(ignoredOutputInventory);
  if (projection.fileCount !== ORDINAL_WITNESS_FILE_COUNT
      || projection.sourceOrderIsOrdinal !== true
      || projection.ordinalPathsSha256 !== ORDINAL_WITNESS_PATHS_SHA256) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "t1903 ignored-output paths do not match the frozen ordinal migration witness",
      projection);
  }
  return Object.assign({ schema: ORDINAL_WITNESS_SCHEMA }, projection);
}

function continuationProgramClosure() {
  const adapter = frozenContinuationAdapter();
  const files = adapter.currentProgramDescriptors(CONTINUATION_PROGRAM_FILES);
  if (Evidence.canonicalJson(CONTINUATION_PROGRAM_FILES)
      !== Evidence.canonicalJson(CONTINUATION_PROGRAM_FILES.slice()
        .sort(Materialize.compareOrdinal))
      || new Set(CONTINUATION_PROGRAM_FILES).size !== CONTINUATION_PROGRAM_FILES.length) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "continuation program closure allowlist is not unique ordinal order");
  }
  const value = { fileCount: files.length, files,
    filesSha256: Evidence.sha256Text(Evidence.canonicalJson(files)) };
  return value;
}

function createIntent(context, createdAt) {
  const value = { schema: INTENT_SCHEMA,
    createdAt: createdAt || new Date().toISOString(),
    runId: context.plan.runId,
    preparationSha256: context.preparation.preparationSha256,
    buildSha256: context.build.buildSha256,
    rawSha256: context.raw.rawSha256,
    journeyEvidenceSha256: context.evidence.evidenceSha256,
    resourcesRoot: context.preparation.resourcesRoot,
    candidateRoot: context.build.candidateRoot,
    targetSlot: context.plan.slots.targetSlot,
    seedSlot: context.plan.slots.seedSlot };
  value.intentSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateIntent(value, context);
}

function validateIntent(value, context) {
  Common.exactKeys(value, ["schema", "createdAt", "runId", "preparationSha256",
    "buildSha256", "rawSha256", "journeyEvidenceSha256", "resourcesRoot",
    "candidateRoot", "targetSlot", "seedSlot", "intentSha256"],
  "material_shop_clone_release_intent_invalid", "clone_release");
  if (value.schema !== INTENT_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || value.runId !== context.plan.runId
      || value.preparationSha256 !== context.preparation.preparationSha256
      || value.buildSha256 !== context.build.buildSha256
      || value.rawSha256 !== context.raw.rawSha256
      || value.journeyEvidenceSha256 !== context.evidence.evidenceSha256
      || path.resolve(value.resourcesRoot).toLowerCase()
        !== path.resolve(context.preparation.resourcesRoot).toLowerCase()
      || path.resolve(value.candidateRoot).toLowerCase()
        !== path.resolve(context.build.candidateRoot).toLowerCase()
      || value.targetSlot !== context.plan.slots.targetSlot
      || value.seedSlot !== context.plan.slots.seedSlot
      || value.intentSha256 !== digestWithout(value, "intentSha256")) {
    Common.fail("material_shop_clone_release_intent_invalid", "clone_release",
      "clone release intent is malformed or detached from verified journey evidence");
  }
  return value;
}

function finalizationEligibility(blocker, context) {
  const cleanup = blocker && blocker.cleanupResult;
  if (!cleanup || !cleanup.postReleaseEligibility) return null;
  if (!context) {
    Common.fail("material_shop_post_release_eligibility_invalid", "clone_release",
      "post-release eligibility validation requires the exact journey context");
  }
  const adapter = require("./admit-post-release-finalization");
  if (typeof adapter.validateFinalizationEligibility !== "function") {
    Common.fail("material_shop_post_release_eligibility_invalid", "clone_release",
      "post-release eligibility adapter does not expose its sealed validator");
  }
  return adapter.validateFinalizationEligibility(blocker, context);
}

function expectedRecoveryCommand(value, context, eligibilityValue) {
  if (value && value.cleanupResult && value.cleanupResult.postReleaseEligibility) {
    const eligibility = eligibilityValue || finalizationEligibility(value, context);
    if (!eligibility || !Array.isArray(eligibility.recoveryCommand)) {
      Common.fail("material_shop_post_release_eligibility_invalid", "clone_release",
        "post-release eligibility omitted its canonical recovery command");
    }
    return eligibility.recoveryCommand.slice();
  }
  return ["node", path.join(value.resourcesRoot, "tools", "workbench-live-e2e",
    "material-shop", "finalize-clone-release.js"),
  "--preparation", value.preparationPath, "--build", value.buildPath,
  "--raw", value.rawPath, "--evidence", value.evidencePath,
  "--intent", value.releaseIntentPath, "--out", value.releaseOutputPath];
}

function validateFinalizationBlocker(value, context, args) {
  Common.exactKeys(value, ["schema", "recordedAt", "runId", "targetSlot",
    "resourcesRoot", "commitMayHaveReachedAuthority", "originalError", "cleanupResult",
    "cleanupError", "preparationPath", "buildPath", "rawPath", "evidencePath",
    "releaseIntentPath", "releaseOutputPath", "recoveryCommand", "stopLine",
    "blockerSha256"], "material_shop_release_finalization_blocker_invalid", "clone_release");
  const runDir = path.resolve(context.preparation.runDir);
  const expectedPaths = {
    preparationPath: path.resolve(args.preparation),
    buildPath: path.resolve(args.build),
    rawPath: path.resolve(args.raw),
    evidencePath: path.resolve(args.evidence),
    releaseIntentPath: path.resolve(args.intent),
    releaseOutputPath: path.resolve(args.out),
  };
  const pathsMatch = Object.keys(expectedPaths).every((key) =>
    path.resolve(value[key] || "").toLowerCase() === expectedPaths[key].toLowerCase());
  const cleanup = value.cleanupResult;
  validateFrozenContinuationBlockerIdentity(context, value);
  const eligibility = cleanup && cleanup.postReleaseEligibility
    ? finalizationEligibility(value, context) : null;
  if (value.schema !== FINALIZATION_BLOCKER_SCHEMA
      || !Number.isFinite(Date.parse(value.recordedAt))
      || value.runId !== context.plan.runId
      || value.targetSlot !== context.plan.slots.targetSlot
      || path.resolve(value.resourcesRoot || "").toLowerCase()
        !== path.resolve(context.preparation.resourcesRoot).toLowerCase()
      || value.commitMayHaveReachedAuthority !== true
      || !cleanup || cleanup.cloneAlreadyReleased !== true
      || cleanup.preservedForManualRecovery !== false
      || !pathsMatch
      || path.dirname(expectedPaths.releaseOutputPath).toLowerCase() !== runDir.toLowerCase()
      || path.basename(expectedPaths.releaseOutputPath).toLowerCase() !== "release.json"
      || Evidence.canonicalJson(value.recoveryCommand)
        !== Evidence.canonicalJson(expectedRecoveryCommand(value, context, eligibility))
      || value.blockerSha256 !== digestWithout(value, "blockerSha256")) {
    Common.fail("material_shop_release_finalization_blocker_invalid", "clone_release",
      "release finalization marker is malformed or detached from the released journey");
  }
  return value;
}

function resolvedMarkerPath(runDir, blocker) {
  return path.join(path.resolve(runDir), FINALIZATION_RESOLVED_PREFIX
    + blocker.blockerSha256.slice(0, 16) + ".json");
}

function loadFinalizationMarker(runDirValue, context, args) {
  const runDir = path.resolve(runDirValue);
  const requiredPath = path.join(runDir, FINALIZATION_REQUIRED_NAME);
  if (fs.existsSync(requiredPath)) {
    const blocker = validateFinalizationBlocker(
      Prepare.readJson(requiredPath, "clone_release"), context, args);
    assertFrozenContinuationMarkerFile(requiredPath, blocker, context);
    return { blocker, requiredPath, resolvedPath: resolvedMarkerPath(runDir, blocker),
      active: true };
  }
  const names = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile()
      && new RegExp("^" + FINALIZATION_RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$")
        .test(entry.name))
    .map((entry) => entry.name).sort();
  if (names.length !== 1) {
    Common.fail("material_shop_release_finalization_marker_missing", "clone_release",
      "exactly one active or resolved release finalization marker is required");
  }
  const resolvedPath = path.join(runDir, names[0]);
  const blocker = validateFinalizationBlocker(
    Prepare.readJson(resolvedPath, "clone_release"), context, args);
  assertFrozenContinuationMarkerFile(resolvedPath, blocker, context);
  if (resolvedPath.toLowerCase() !== resolvedMarkerPath(runDir, blocker).toLowerCase()) {
    Common.fail("material_shop_release_finalization_marker_invalid", "clone_release",
      "resolved release finalization marker name differs from its sealed blocker");
  }
  return { blocker, requiredPath, resolvedPath, active: false };
}

function resolveFinalizationMarker(marker) {
  if (marker.active) {
    if (fs.existsSync(marker.resolvedPath)) {
      Common.fail("material_shop_release_finalization_marker_duplicate", "clone_release",
        "active and resolved release finalization markers coexist");
    }
    fs.renameSync(marker.requiredPath, marker.resolvedPath);
    if (isFrozenContinuationBlocker(marker.blocker)) {
      fsyncRegularFile(marker.resolvedPath);
    }
  }
  return marker.resolvedPath;
}

function markerFiles(runDirValue) {
  const runDir = path.resolve(runDirValue);
  return fs.readdirSync(runDir, { withFileTypes: true }).filter((entry) => entry.isFile()
    && (entry.name === FINALIZATION_REQUIRED_NAME
      || new RegExp("^" + FINALIZATION_RESOLVED_PREFIX + "[a-f0-9]{16}\\.json$")
        .test(entry.name))).map((entry) => entry.name).sort();
}

function blockerArgs(blocker) {
  return { preparation: blocker.preparationPath, build: blocker.buildPath,
    raw: blocker.rawPath, evidence: blocker.evidencePath,
    intent: blocker.releaseIntentPath, out: blocker.releaseOutputPath };
}

function createMarkerEvidence(marker) {
  if (!marker) {
    return { mode: "none", blocker: null, blockerSha256: null,
      requiredName: null, resolvedName: null };
  }
  return { mode: "resumed_release", blocker: JSON.parse(JSON.stringify(marker.blocker)),
    blockerSha256: marker.blocker.blockerSha256,
    requiredName: FINALIZATION_REQUIRED_NAME,
    resolvedName: path.basename(marker.resolvedPath) };
}

function validateMarkerEvidence(value, context, phase) {
  Common.exactKeys(value, ["mode", "blocker", "blockerSha256", "requiredName",
    "resolvedName"], "material_shop_clone_release_marker_evidence_invalid", "clone_release");
  const runDir = path.resolve(context.preparation.runDir);
  const state = phase || "final";
  if (value.mode === "none") {
    if (value.blocker !== null || value.blockerSha256 !== null
        || value.requiredName !== null || value.resolvedName !== null
        || (state !== "structural" && markerFiles(runDir).length !== 0)) {
      Common.fail("material_shop_clone_release_marker_evidence_invalid", "clone_release",
        "live clone release requires zero active or resolved finalization markers");
    }
    return value;
  }
  if (value.mode !== "resumed_release" || !Evidence.isPlainObject(value.blocker)
      || value.blockerSha256 !== value.blocker.blockerSha256
      || value.requiredName !== FINALIZATION_REQUIRED_NAME
      || value.resolvedName !== path.basename(resolvedMarkerPath(runDir, value.blocker))) {
    Common.fail("material_shop_clone_release_marker_evidence_invalid", "clone_release",
      "resumed release marker evidence is malformed or detached");
  }
  validateFinalizationBlocker(value.blocker, context, blockerArgs(value.blocker));
  if (state === "structural") return value;
  const expectedName = state === "required" ? value.requiredName : value.resolvedName;
  const unexpectedName = state === "required" ? value.resolvedName : value.requiredName;
  const names = markerFiles(runDir);
  if (Evidence.canonicalJson(names) !== Evidence.canonicalJson([expectedName])
      || fs.existsSync(path.join(runDir, unexpectedName))) {
    Common.fail("material_shop_clone_release_marker_evidence_invalid", "clone_release",
      "finalization marker disk state does not match the release receipt", { state, names });
  }
  const marker = Prepare.readJson(path.join(runDir, expectedName), "clone_release");
  if (Evidence.canonicalJson(marker) !== Evidence.canonicalJson(value.blocker)) {
    Common.fail("material_shop_clone_release_marker_evidence_invalid", "clone_release",
      "finalization marker bytes differ from the release-bound blocker");
  }
  assertFrozenContinuationMarkerFile(path.join(runDir, expectedName), marker, context);
  return value;
}

function validateAbsentInspection(value, targetSlot, resourcesRoot) {
  Common.exactKeys(value, ["schema", "apiVersion", "observedAt", "slot", "lockPath",
    "lockPresent", "recordSha256", "ownerPid", "ownerProcessStartUtcTicks",
    "observedProcessStartUtcTicks", "ownerState", "recoveryPresent", "recoveryStatus",
    "recoveryRecordSha256", "evidenceSha256"],
  "material_shop_clone_release_not_complete", "clone_release");
  const unsigned = Object.assign({}, value);
  delete unsigned.evidenceSha256;
  if (!value || value.schema !== "workbench-live-e2e.clone-lock-inspection.v1"
      || value.apiVersion !== CloneGuard.API_VERSION || value.slot !== targetSlot
      || !Number.isFinite(Date.parse(value.observedAt))
      || resourcesRoot && path.resolve(value.lockPath).toLowerCase()
        !== path.resolve(resourcesRoot, "tmp", "workbench-live-e2e", "locks",
          targetSlot + ".clone.lock").toLowerCase()
      || value.lockPresent !== false || value.recordSha256 !== null
      || value.ownerPid !== null || value.ownerProcessStartUtcTicks !== null
      || value.observedProcessStartUtcTicks !== null || value.ownerState !== "absent"
      || value.recoveryPresent !== false || value.recoveryStatus !== null
      || value.recoveryRecordSha256 !== null
      || value.evidenceSha256 !== Evidence.sha256Text(Evidence.canonicalJson(unsigned))) {
    Common.fail("material_shop_clone_release_not_complete", "clone_release",
      "clone release cannot finalize while a lock or recovery record remains");
  }
  return value;
}

function ignoredOutputOptions(context, markerEvidence) {
  const options = Object.assign(Build.protectedScopeOptions(
    context.preparation, context.build.candidateRoot), { scope: context.closure.scope });
  if (!markerEvidence || markerEvidence.mode === "none") return options;
  validateMarkerEvidence(markerEvidence, context, "structural");
  const eligibility = finalizationEligibility(markerEvidence.blocker, context);
  if (!eligibility || !Array.isArray(eligibility.supplementalGeneratedOutputs)
      || eligibility.supplementalGeneratedOutputs.length < 1) {
    Common.fail("material_shop_post_release_eligibility_invalid", "clone_release",
      "resumed post-release marker omitted verified supplemental output descriptors");
  }
  return Object.assign(options, {
    supplementalGeneratedOutputs: eligibility.supplementalGeneratedOutputs.map(
      (entry) => Object.assign({}, entry)),
  });
}

function replayReleaseIgnoredOutputInventory(value, context) {
  return Materialize.verifyIgnoredOutputInventory(value.ignoredOutputInventory,
    context.preparation.resourcesRoot, ignoredOutputOptions(context, value.markerEvidence));
}

function unresolvedBlockerFiles(runDirValue, context, markerEvidence) {
  const runDir = path.resolve(runDirValue);
  const names = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile()
      && (/^recovery-blocker-.*\.json$/i.test(entry.name)
        || entry.name.toLowerCase() === FINALIZATION_REQUIRED_NAME))
    .map((entry) => entry.name).sort();
  if (!markerEvidence || markerEvidence.mode !== "resumed_release") return names;
  validateMarkerEvidence(markerEvidence, context, "structural");
  const eligibility = finalizationEligibility(markerEvidence.blocker, context);
  const binding = eligibility && eligibility.legacyBlocker;
  if (!binding || !Evidence.isPlainObject(binding)) return names;
  Common.exactKeys(binding, ["relativePath", "bytes", "sha256", "blockerSha256", "value"],
    "material_shop_post_release_eligibility_invalid", "clone_release");
  const relativePath = Common.normalizeRelative(binding.relativePath);
  const blockerName = path.basename(relativePath);
  if (relativePath !== blockerName
      || !/^recovery-blocker-[0-9]+(?:-[a-f0-9]{8})?\.json$/.test(blockerName)
      || !Number.isInteger(binding.bytes) || binding.bytes < 1
      || !Common.SHA256_RE.test(String(binding.sha256 || ""))
      || !Common.SHA256_RE.test(String(binding.blockerSha256 || ""))
      || !names.includes(blockerName)) return names;
  try {
    const file = Evidence.readExactRegularFile(path.join(runDir, blockerName), {
      phase: "clone_release", maximumBytes: Math.max(binding.bytes, 1),
    });
    const parsed = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, ""));
    if (file.length !== binding.bytes || file.sha256 !== binding.sha256
        || !parsed || parsed.blockerSha256 !== binding.blockerSha256
        || Evidence.canonicalJson(parsed) !== Evidence.canonicalJson(binding.value)) return names;
  } catch (_) {
    return names;
  }
  return names.filter((name) => name !== blockerName);
}

function frozenContinuationArtifactDescriptors(context, markerEvidence) {
  if (!requiresFrozenContinuation(context)
      || !markerEvidence || markerEvidence.mode !== "resumed_release"
      || !isFrozenContinuationBlocker(markerEvidence.blocker)) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "v4 continuation requires the exact frozen t1903 finalization blocker");
  }
  const adapter = frozenContinuationAdapter();
  adapter.validateFinalizationEligibility(markerEvidence.blocker, context);
  const runDir = path.resolve(context.preparation.runDir);
  const eligibilityPath = path.join(runDir, adapter.FROZEN_ELIGIBILITY_NAME);
  const eligibility = markerEvidence.blocker.cleanupResult.postReleaseEligibility;
  adapter.assertFrozenEligibilityArtifact(eligibilityPath, eligibility);
  const names = markerFiles(runDir);
  const markerName = names.length === 1 ? names[0] : null;
  if (!markerName || ![markerEvidence.requiredName, markerEvidence.resolvedName]
    .includes(markerName)) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "frozen t1903 continuation requires exactly one active or resolved marker", { names });
  }
  adapter.assertFrozenFinalizationArtifact(path.join(runDir, markerName),
    markerEvidence.blocker);
  return {
    eligibilityArtifact: { relativePath: adapter.FROZEN_ELIGIBILITY_NAME,
      bytes: adapter.FROZEN_ELIGIBILITY_BYTES,
      sha256: adapter.FROZEN_ELIGIBILITY_FILE_SHA256,
      eligibilitySha256: adapter.FROZEN_ELIGIBILITY_SHA256 },
    requiredBlockerArtifact: { requiredName: FINALIZATION_REQUIRED_NAME,
      resolvedName: FINALIZATION_RESOLVED_PREFIX
        + adapter.FROZEN_REQUIRED_BLOCKER_SHA256.slice(0, 16) + ".json",
      bytes: adapter.FROZEN_REQUIRED_BLOCKER_BYTES,
      sha256: adapter.FROZEN_REQUIRED_BLOCKER_FILE_SHA256,
      blockerSha256: adapter.FROZEN_REQUIRED_BLOCKER_SHA256 },
  };
}

function createContinuationEvidence(context, markerEvidence, ignoredOutputInventory,
  cloneInspection) {
  const adapter = frozenContinuationAdapter();
  const artifacts = frozenContinuationArtifactDescriptors(context, markerEvidence);
  const currentPrograms = continuationProgramClosure();
  const value = { schema: CONTINUATION_SCHEMA,
    migrationCaseId: CONTINUATION_MIGRATION_CASE_ID,
    runId: adapter.RUN_ID,
    eligibilityArtifact: artifacts.eligibilityArtifact,
    requiredBlockerArtifact: artifacts.requiredBlockerArtifact,
    frozenCurrentProgramsSha256: adapter.FROZEN_CURRENT_PROGRAMS_SHA256,
    currentProgramClosure: currentPrograms,
    cloneInspection: JSON.parse(JSON.stringify(validateAbsentInspection(cloneInspection,
      context.plan.slots.targetSlot, context.preparation.resourcesRoot))),
    ordinalInventoryWitness: createOrdinalInventoryWitness(ignoredOutputInventory),
    ignoredOutputInventorySha256: ignoredOutputInventory.inventorySha256 };
  value.continuationSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateContinuationEvidence(value, context, markerEvidence, ignoredOutputInventory);
}

function validateContinuationEvidence(value, context, markerEvidence,
  ignoredOutputInventory) {
  Common.exactKeys(value, ["schema", "migrationCaseId", "runId", "eligibilityArtifact",
    "requiredBlockerArtifact", "frozenCurrentProgramsSha256", "currentProgramClosure",
    "cloneInspection", "ordinalInventoryWitness", "ignoredOutputInventorySha256",
    "continuationSha256"],
  "material_shop_post_release_continuation_invalid", "clone_release");
  const adapter = frozenContinuationAdapter();
  const artifacts = frozenContinuationArtifactDescriptors(context, markerEvidence);
  const programs = continuationProgramClosure();
  const witness = createOrdinalInventoryWitness(ignoredOutputInventory);
  validateAbsentInspection(value.cloneInspection, context.plan.slots.targetSlot,
    context.preparation.resourcesRoot);
  if (value.schema !== CONTINUATION_SCHEMA
      || value.migrationCaseId !== CONTINUATION_MIGRATION_CASE_ID
      || value.runId !== adapter.RUN_ID
      || Evidence.canonicalJson(value.eligibilityArtifact)
        !== Evidence.canonicalJson(artifacts.eligibilityArtifact)
      || Evidence.canonicalJson(value.requiredBlockerArtifact)
        !== Evidence.canonicalJson(artifacts.requiredBlockerArtifact)
      || value.frozenCurrentProgramsSha256 !== adapter.FROZEN_CURRENT_PROGRAMS_SHA256
      || Evidence.canonicalJson(value.currentProgramClosure) !== Evidence.canonicalJson(programs)
      || Evidence.canonicalJson(value.ordinalInventoryWitness)
        !== Evidence.canonicalJson(witness)
      || value.ignoredOutputInventorySha256 !== ignoredOutputInventory.inventorySha256
      || value.continuationSha256 !== digestWithout(value, "continuationSha256")) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "v4 continuation evidence is malformed or detached from exact t1903 state");
  }
  return value;
}

function createReleaseReceipt(context, intent, releasedClone, finalizedAt, marker) {
  validateIntent(intent, context);
  const inspection = validateAbsentInspection(CloneGuard.inspectCloneLock({
    root: context.preparation.resourcesRoot, slot: context.plan.slots.targetSlot,
  }), context.plan.slots.targetSlot);
  if (releasedClone && (releasedClone.cloneLockReleased !== true
      || releasedClone.recoveryCleared !== true)) {
    Common.fail("material_shop_clone_release_not_complete", "clone_release",
      "live clone release did not clear its exact lock and recovery record");
  }
  const markerEvidence = createMarkerEvidence(marker);
  const ignoredOutputInventory = Materialize.captureIgnoredOutputInventory(
    context.preparation.resourcesRoot, ignoredOutputOptions(context, markerEvidence));
  const continuation = requiresFrozenContinuation(context);
  const value = { schema: continuation ? RELEASE_SCHEMA : LEGACY_RELEASE_SCHEMA,
    runId: context.plan.runId,
    targetSlot: context.plan.slots.targetSlot,
    releasedAt: releasedClone && releasedClone.releasedAt || new Date().toISOString(),
    finalizedAt: finalizedAt || new Date().toISOString(),
    finalizationMode: releasedClone ? "live_release" : "resumed_after_observed_release",
    cloneLockReleased: true, recoveryCleared: true,
    releaseIntentSha256: intent.intentSha256,
    cloneInspectionSha256: inspection.evidenceSha256,
    ignoredOutputInventory, markerEvidence };
  if (continuation) {
    value.continuationEvidence = createContinuationEvidence(
      context, markerEvidence, ignoredOutputInventory, inspection);
  }
  value.releaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(value));
  return validateReleaseReceipt(value, context, intent, {
    markerPhase: releasedClone ? "final" : "required",
  });
}

function validateReleaseReceipt(value, context, intent, options) {
  const continuation = value && value.schema === RELEASE_SCHEMA;
  const legacy = value && value.schema === LEGACY_RELEASE_SCHEMA;
  const keys = ["schema", "runId", "targetSlot", "releasedAt", "finalizedAt",
    "finalizationMode", "cloneLockReleased", "recoveryCleared", "releaseIntentSha256",
    "cloneInspectionSha256", "ignoredOutputInventory", "markerEvidence"];
  if (continuation) keys.push("continuationEvidence");
  keys.push("releaseSha256");
  Common.exactKeys(value, keys, "material_shop_clone_release_invalid", "clone_release");
  validateIntent(intent, context);
  if ((!continuation && !legacy) || value.runId !== context.plan.runId
      || value.targetSlot !== context.plan.slots.targetSlot
      || !Number.isFinite(Date.parse(value.releasedAt))
      || !Number.isFinite(Date.parse(value.finalizedAt))
      || !["live_release", "resumed_after_observed_release"].includes(value.finalizationMode)
      || value.cloneLockReleased !== true || value.recoveryCleared !== true
      || value.releaseIntentSha256 !== intent.intentSha256
      || !Common.SHA256_RE.test(String(value.cloneInspectionSha256 || ""))
      || value.releaseSha256 !== digestWithout(value, "releaseSha256")) {
    Common.fail("material_shop_clone_release_invalid", "clone_release",
      "clone release receipt is malformed or detached");
  }
  if ((value.finalizationMode === "live_release" && value.markerEvidence.mode !== "none")
      || (value.finalizationMode === "resumed_after_observed_release"
        && value.markerEvidence.mode !== "resumed_release")) {
    Common.fail("material_shop_clone_release_marker_evidence_invalid", "clone_release",
      "clone release mode disagrees with finalization marker evidence");
  }
  validateMarkerEvidence(value.markerEvidence, context,
    options && options.markerPhase || "final");
  if (options && options.verifyIgnoredOutputInventory === true) {
    replayReleaseIgnoredOutputInventory(value, context);
  } else {
    Materialize.validateIgnoredOutputInventory(value.ignoredOutputInventory,
      context.preparation.resourcesRoot, ignoredOutputOptions(context, value.markerEvidence));
  }
  const frozen = requiresFrozenContinuation(context);
  if (continuation) {
    if (!frozen) {
      Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
        "v4 release is restricted to the exact frozen t1903 continuation");
    }
    validateContinuationEvidence(value.continuationEvidence, context,
      value.markerEvidence, value.ignoredOutputInventory);
    if (value.cloneInspectionSha256
        !== value.continuationEvidence.cloneInspection.evidenceSha256) {
      Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
        "top-level clone inspection digest differs from embedded exact inspection");
    }
  } else if (frozen) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "the frozen t1903 ordinal migration cannot be represented by a legacy v3 release");
  }
  return value;
}

function frozenPostReleaseBuildOptions(preparation, options) {
  if (options == null) return undefined;
  Common.exactKeys(options, ["allowFrozenPostReleaseBootstrap"],
    "material_shop_post_release_eligibility_invalid", "clone_release");
  if (options.allowFrozenPostReleaseBootstrap !== true) {
    Common.fail("material_shop_post_release_eligibility_invalid", "clone_release",
      "clone release bootstrap requires one explicit frozen-case opt-in");
  }
  const adapter = require("./admit-post-release-finalization");
  const ticket = adapter.captureProtectedScopeBootstrap(preparation, { optional: true });
  return ticket ? { protectedScopeBootstrap: ticket } : undefined;
}

function loadContext(args, options) {
  const preparation = Build.loadPreparation(path.resolve(args.preparation));
  const closure = VerifyRun.artifact(preparation.runDir, preparation.artifacts.closure);
  const plan = Protocol.validateControlPlan(VerifyRun.artifact(
    preparation.runDir, preparation.artifacts.plan));
  const applicability = Applicability.validateApplicability(VerifyRun.artifact(
    preparation.runDir, preparation.artifacts.applicability));
  const buildOptions = frozenPostReleaseBuildOptions(preparation, options);
  const build = Build.loadBuildReceipt(path.resolve(args.build), preparation, closure,
    "clone_release", buildOptions);
  const raw = VerifyRun.readRawCandidateJourney(path.resolve(args.raw), "clone_release");
  const verified = JourneyVerifier.verifyRawCandidateJourney(raw, plan, applicability,
    preparation.runDir, build);
  const evidence = Prepare.readJson(path.resolve(args.evidence), "clone_release");
  if (Evidence.canonicalJson(evidence) !== Evidence.canonicalJson(verified.evidence)) {
    Common.fail("material_shop_clone_release_evidence_drift", "clone_release",
      "stored journey evidence differs from strict raw replay");
  }
  return { preparation, closure, plan, applicability, build, raw, evidence };
}

function parseArgs(argv) {
  const args = { preparation: null, build: null, raw: null, evidence: null,
    intent: null, out: null };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--preparation") args.preparation = argv[++index];
    else if (token === "--build") args.build = argv[++index];
    else if (token === "--raw") args.raw = argv[++index];
    else if (token === "--evidence") args.evidence = argv[++index];
    else if (token === "--intent") args.intent = argv[++index];
    else if (token === "--out") args.out = argv[++index];
    else Common.fail("material_shop_clone_release_argument_unknown", "clone_release", token);
  }
  if (![args.preparation, args.build, args.raw, args.evidence, args.intent, args.out]
    .every(Boolean)) {
    Common.fail("material_shop_clone_release_arguments_invalid", "clone_release",
      "preparation/build/raw/evidence/intent/output are required");
  }
  return args;
}

function writeReleaseReceipt(outputPath, value, runDir, io) {
  const output = path.resolve(outputPath);
  const expected = path.join(path.resolve(runDir), "release.json");
  if (output.toLowerCase() !== expected.toLowerCase() || fs.existsSync(output)) {
    Common.fail("material_shop_clone_release_output_invalid", "clone_release",
      "clone release output must be one new canonical run release.json");
  }
  const staged = output + ".staged-" + value.releaseSha256.slice(0, 16);
  const writeFile = io && io.writeFileSync || fs.writeFileSync;
  const renameFile = io && io.renameSync || fs.renameSync;
  try {
    writeFile(staged, JSON.stringify(value, null, 2) + "\n",
      { encoding: "utf8", mode: 0o600, flag: "wx" });
    if (value.schema === RELEASE_SCHEMA) fsyncRegularFile(staged);
    renameFile(staged, output);
    if (value.schema === RELEASE_SCHEMA) fsyncRegularFile(output);
  } catch (error) {
    // Only v4 has exact staged-reentry validation. Preserve its digest-named stage; retain the
    // legacy v3 cleanup behavior so ordinary runs cannot strand an untracked stage.
    if (value.schema !== RELEASE_SCHEMA && fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  return output;
}

function readCanonicalReleaseReceipt(outputPath, context, intent, options) {
  return validateReleaseReceipt(Prepare.readJson(path.resolve(outputPath), "clone_release"),
    context, intent, options);
}

function resumeStagedReleaseReceipt(stagedPath, outputPath, context, intent) {
  const staged = path.resolve(stagedPath);
  const output = path.resolve(outputPath);
  if (fs.existsSync(output)) {
    Common.fail("material_shop_clone_release_output_invalid", "clone_release",
      "staged release recovery cannot replace an existing canonical receipt");
  }
  const value = validateReleaseReceipt(Prepare.readJson(staged, "clone_release"),
    context, intent, { markerPhase: "required", verifyIgnoredOutputInventory: true });
  if (path.basename(staged) !== "release.json.staged-"
      + value.releaseSha256.slice(0, 16)) {
    Common.fail("material_shop_clone_release_output_invalid", "clone_release",
      "staged release filename differs from its validated content digest");
  }
  fs.renameSync(staged, output);
  return value;
}

function assertFrozenContinuationPreflight(context, marker, outputPath) {
  if (!requiresFrozenContinuation(context)) return null;
  validateFrozenContinuationBlockerIdentity(context, marker && marker.blocker);
  const adapter = frozenContinuationAdapter();
  const runDir = path.resolve(context.preparation.runDir);
  const output = path.resolve(outputPath);
  const names = fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile()).map((entry) => entry.name).sort();
  const eligibilityNames = names.filter((name) =>
    /^post-release-finalization-eligibility-[a-f0-9]{16}\.json$/i.test(name));
  const releaseStagedNames = names.filter((name) =>
    /^release\.json\.staged-[a-f0-9]{16}$/i.test(name));
  const forbiddenExact = new Set(["static-gate.json", "review-request.json",
    "independent-review-receipt.json", "acceptance.json", "worktree-release.json",
    "worktree-removal-intent.json"]);
  const resumableStage = marker.active && !fs.existsSync(output)
    && releaseStagedNames.length === 1 ? releaseStagedNames[0] : null;
  const forbidden = names.filter((name) => forbiddenExact.has(name.toLowerCase())
    || /^(?:release-finalization-required\.json|post-release-finalization-eligibility-[a-f0-9]{16}\.json)\.staged-[a-f0-9]{16}$/i.test(name)
    || /^release\.json\.staged-[a-f0-9]{16}$/i.test(name) && name !== resumableStage
    || /^worktree-removal-resolved-[a-f0-9]{16}\.json$/i.test(name));
  if (Evidence.canonicalJson(eligibilityNames)
      !== Evidence.canonicalJson([adapter.FROZEN_ELIGIBILITY_NAME])
      || forbidden.length
      || marker.active && markerFiles(runDir).some((name) =>
        name !== FINALIZATION_REQUIRED_NAME)
      || !marker.active && (!fs.existsSync(output)
        || markerFiles(runDir).length !== 1
        || markerFiles(runDir)[0] !== path.basename(marker.resolvedPath))) {
    Common.fail("material_shop_post_release_continuation_invalid", "clone_release",
      "frozen t1903 continuation preflight found a later, staged, or foreign artifact",
      { eligibilityNames, forbidden, markerFiles: markerFiles(runDir),
        releasePresent: fs.existsSync(output), markerActive: marker.active });
  }
  adapter.assertFrozenEligibilityArtifact(path.join(runDir,
    adapter.FROZEN_ELIGIBILITY_NAME), marker.blocker.cleanupResult.postReleaseEligibility);
  assertFrozenContinuationMarkerFile(marker.active ? marker.requiredPath : marker.resolvedPath,
    marker.blocker, context);
  return { releasePresent: fs.existsSync(output), markerActive: marker.active,
    stagedPath: resumableStage ? path.join(runDir, resumableStage) : null };
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const context = loadContext(args, { allowFrozenPostReleaseBootstrap: true });
    const intent = validateIntent(Prepare.readJson(path.resolve(args.intent), "clone_release"),
      context);
    const marker = loadFinalizationMarker(context.preparation.runDir, context, args);
    const output = path.resolve(args.out);
    const continuationPreflight = assertFrozenContinuationPreflight(
      context, marker, output);
    if (!marker.active && !fs.existsSync(output)) {
      Common.fail("material_shop_release_finalization_receipt_missing", "clone_release",
        "a resolved finalization marker cannot authorize recreation of a missing receipt");
    }
    const value = continuationPreflight && continuationPreflight.stagedPath
      ? resumeStagedReleaseReceipt(continuationPreflight.stagedPath, output, context, intent)
      : fs.existsSync(output)
        ? validateReleaseReceipt(Prepare.readJson(output, "clone_release"), context, intent,
          { markerPhase: marker.active ? "required" : "final",
            verifyIgnoredOutputInventory: true })
        : createReleaseReceipt(context, intent, null, null, marker);
    if (!fs.existsSync(output)) {
      writeReleaseReceipt(output, value, context.preparation.runDir);
    }
    const persisted = readCanonicalReleaseReceipt(output, context, intent, {
      markerPhase: marker.active ? "required" : "final",
      verifyIgnoredOutputInventory: true,
    });
    const resolvedMarker = resolveFinalizationMarker(marker);
    const finalReceipt = readCanonicalReleaseReceipt(output, context, intent, {
      markerPhase: "final", verifyIgnoredOutputInventory: true,
    });
    if (persisted.releaseSha256 !== finalReceipt.releaseSha256) {
      Common.fail("material_shop_clone_release_invalid", "clone_release",
        "canonical release receipt changed across marker resolution");
    }
    process.stdout.write(JSON.stringify({ ok: true, releaseSha256: finalReceipt.releaseSha256,
      finalizationMode: finalReceipt.finalizationMode, resolvedMarker }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = { CONTINUATION_MIGRATION_CASE_ID, CONTINUATION_SCHEMA,
  FINALIZATION_BLOCKER_SCHEMA, FINALIZATION_REQUIRED_NAME,
  FINALIZATION_RESOLVED_PREFIX, INTENT_SCHEMA, LEGACY_RELEASE_SCHEMA,
  ORDINAL_WITNESS_FILE_COUNT, ORDINAL_WITNESS_PATHS_SHA256, ORDINAL_WITNESS_SCHEMA,
  RELEASE_SCHEMA, assertFrozenContinuationPreflight, createContinuationEvidence,
  CONTINUATION_PROGRAM_FILES, continuationProgramClosure, createIntent,
  createMarkerEvidence, createOrdinalInventoryWitness, createReleaseReceipt,
  expectedRecoveryCommand, ignoredOutputOptions, isFrozenContinuationBlocker,
  fsyncRegularFile, projectOrdinalInventoryWitness, replayReleaseIgnoredOutputInventory,
  requiresFrozenContinuation,
  frozenPostReleaseBuildOptions, loadContext,
  loadFinalizationMarker, markerFiles,
  parseArgs, resolveFinalizationMarker, resumeStagedReleaseReceipt,
  readCanonicalReleaseReceipt,
  validateFinalizationBlocker, validateFrozenContinuationBlockerIdentity, validateIntent,
  unresolvedBlockerFiles, validateContinuationEvidence, validateMarkerEvidence,
  validateReleaseReceipt,
  writeReleaseReceipt };
