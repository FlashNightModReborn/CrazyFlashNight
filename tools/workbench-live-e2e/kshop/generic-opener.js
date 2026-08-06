"use strict";

const fs = require("fs");
const path = require("path");
const CloneSaveGuard = require("../lib/clone-save-guard");
const SharedEvidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const { canonicalJson, fail, sha256Bytes, sha256Text } = require("./common");

const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "kshop");

function formatLocalSaveTimestamp(now) {
  const value = now || new Date();
  const part = (number) => String(number).padStart(2, "0");
  return value.getFullYear() + "-" + part(value.getMonth() + 1) + "-" + part(value.getDate())
    + " " + part(value.getHours()) + ":" + part(value.getMinutes()) + ":" + part(value.getSeconds());
}

function isValidSaveData(data) {
  if (!data || data.version !== "3.0" || !data.lastSaved) return false;
  const player = data["0"];
  return Array.isArray(player) && player.length >= 14 && player[0] != null && player[0] !== ""
    && player[3] != null && !Number.isNaN(Number(player[3]))
    && Array.isArray(data["1"]) && data["1"].length >= 28
    && Array.isArray(data["4"]) && data["4"].length >= 2
    && Array.isArray(data["5"])
    && Array.isArray(data["7"]) && data["7"].length >= 5
    && !!data.inventory && !!data.collection && !!data.infrastructure
    && !!data.tasks && Array.isArray(data.tasks.tasks_to_do)
    && !!data.tasks.tasks_finished && !!data.tasks.task_chains_progress
    && !!data.pets && Array.isArray(data.pets["宠物信息"])
    && data.pets["宠物信息"].length >= 5 && data.pets["宠物领养限制"] != null
    && !!data.shop && Array.isArray(data.shop["商城已购买物品"])
    && Array.isArray(data.shop["商城购物车"]);
}

function assertNoLauncherBeforeMutation() {
  const processes = LauncherObservation.queryLauncherCoreProcesses();
  LauncherObservation.assertExclusiveLauncherProcess(processes, null);
  return true;
}

function artifactEntry(root, appData, filePath, kind) {
  const file = SharedEvidence.readExactRegularFile(filePath, {
    phase: "save_universe", maximumBytes: 128 * 1024 * 1024,
  });
  const locator = kind === "json"
    ? "root:" + path.relative(root, file.path).replace(/\\/g, "/")
    : "appdata:" + path.relative(appData, file.path).replace(/\\/g, "/");
  return { kind, locator, sha256: file.sha256, bytes: file.length,
    regularFile: true, exactRealPath: true };
}

function captureSaveUniverse(rootValue, appDataValue, excludedTargetSlot, capturedAt) {
  const root = SharedEvidence.assertExactDirectory(path.resolve(rootValue), "save_universe");
  const appData = SharedEvidence.assertExactDirectory(path.resolve(appDataValue), "save_universe");
  const saves = SharedEvidence.assertExactDirectory(path.join(root, "saves"), "save_universe");
  const artifacts = [];
  fs.readdirSync(saves, { withFileTypes: true }).forEach((entry) => {
    const fullPath = path.join(saves, entry.name);
    if (entry.isSymbolicLink()) fail("save_universe_reparse", "save_universe",
      "saves/ contains a reparse entry", { fullPath });
    if (entry.isFile() && /\.json$/i.test(entry.name)
        && entry.name.toLowerCase() !== (excludedTargetSlot + ".json").toLowerCase()) {
      artifacts.push(artifactEntry(root, appData, fullPath, "json"));
    }
  });
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (fs.existsSync(sharedRoot)) {
    SharedEvidence.assertExactDirectory(sharedRoot, "save_universe");
    const swfParentSuffix = path.dirname(CloneSaveGuard.solOwnershipSuffix(root, excludedTargetSlot))
      .toLowerCase();
    const stack = [sharedRoot];
    let visited = 0;
    while (stack.length > 0) {
      const directory = stack.pop();
      fs.readdirSync(directory, { withFileTypes: true }).forEach((entry) => {
        visited += 1;
        if (visited > 100000) fail("save_universe_unbounded", "save_universe",
          "save/SOL universe exceeded its fixed traversal bound");
        const fullPath = path.join(directory, entry.name);
        if (entry.isSymbolicLink()) fail("save_universe_reparse", "save_universe",
          "SharedObjects contains a reparse entry", { fullPath });
        if (entry.isDirectory()) stack.push(fullPath);
        else if (entry.isFile() && /\.sol$/i.test(entry.name)
            && path.dirname(path.resolve(fullPath)).toLowerCase().endsWith(swfParentSuffix)
            && entry.name.toLowerCase() !== (excludedTargetSlot + ".sol").toLowerCase()) {
          artifacts.push(artifactEntry(root, appData, fullPath, "sol"));
        }
      });
    }
  }
  artifacts.sort((left, right) => left.locator.localeCompare(right.locator));
  const payload = { schema: "workbench-live-e2e.kshop.save-universe.v1",
    root, appDataRoot: appData, excludedTargetSlot, artifacts };
  return Object.assign({}, payload, { capturedAt: capturedAt || new Date().toISOString(),
    setSha256: sha256Text(canonicalJson(payload)) });
}

function verifySaveUniverse(universe) {
  if (!universe || universe.schema !== "workbench-live-e2e.kshop.save-universe.v1"
      || !path.isAbsolute(String(universe.root || ""))
      || !path.isAbsolute(String(universe.appDataRoot || ""))
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(String(universe.excludedTargetSlot || ""))
      || !Number.isFinite(Date.parse(universe.capturedAt))
      || !/^[a-f0-9]{64}$/.test(String(universe.setSha256 || ""))
      || !Array.isArray(universe.artifacts)) {
    fail("save_universe_invalid", "save_universe", "save/SOL universe envelope is malformed");
  }
  const sorted = universe.artifacts.slice().sort((left, right) => left.locator.localeCompare(right.locator));
  if (canonicalJson(sorted) !== canonicalJson(universe.artifacts)
      || new Set(universe.artifacts.map((entry) => entry.locator.toLowerCase())).size
        !== universe.artifacts.length
      || universe.artifacts.some((entry) => !entry || !["json", "sol"].includes(entry.kind)
        || !/^(?:root|appdata):/.test(String(entry.locator || ""))
        || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1
        || entry.regularFile !== true || entry.exactRealPath !== true)) {
    fail("save_universe_invalid", "save_universe", "save/SOL universe entries are malformed");
  }
  const payload = { schema: universe.schema, root: path.resolve(universe.root),
    appDataRoot: path.resolve(universe.appDataRoot), excludedTargetSlot: universe.excludedTargetSlot,
    artifacts: universe.artifacts };
  if (sha256Text(canonicalJson(payload)) !== universe.setSha256) {
    fail("save_universe_digest_mismatch", "save_universe", "save/SOL universe digest changed");
  }
  return universe;
}

function assertSaveUniverseInvariant(begin, end) {
  verifySaveUniverse(begin);
  verifySaveUniverse(end);
  if (begin.root.toLowerCase() !== end.root.toLowerCase()
      || begin.appDataRoot.toLowerCase() !== end.appDataRoot.toLowerCase()
      || begin.excludedTargetSlot !== end.excludedTargetSlot
      || begin.setSha256 !== end.setSha256
      || canonicalJson(begin.artifacts) !== canonicalJson(end.artifacts)) {
    fail("save_universe_collateral_changed", "save_universe",
      "a non-target save JSON or owned SOL changed during the KShop journey");
  }
  return { setSha256: end.setSha256, artifactCount: end.artifacts.length };
}

async function startGenericRuntime(root, args, preparation, expectedIdentity) {
  const cdpBinding = await RuntimeGuard.allocateLoopbackCdpPort();
  const launch = LauncherObservation.startLauncherCandidate({ root,
    candidateRoot: path.resolve(args.candidateRoot), expectedIdentity, cdpPort: cdpBinding.port });
  const session = await LauncherObservation.waitForAuthenticatedLegacyHttp({ root,
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
  const identity = session.verifyRuntimeIdentity(expectedIdentity);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), identity.pid);
  const processContract = LauncherObservation.attestAuthenticatedLauncherProcess({ root,
    sessionEvidence: session.evidence, runtimeIdentity: identity });
  cdpBinding.runtimePid = identity.pid;
  cdpBinding.configurationSource = "CF7_WEBVIEW2_ARGS";
  cdpBinding.developerMode = true;
  cdpBinding.expectedPageUrl = "https://overlay.local/overlay.html";
  const startSnapshot = await session.readTerminalLogSnapshot(2000);
  const startBoundary = LauncherObservation.createTerminalLogBoundary(startSnapshot);
  await LauncherObservation.waitForAgentControl(session, {
    timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
  });
  const startResponse = await session.agentControl("start", {
    slot: preparation.targetSlot, fresh: false, deferReveal: false,
    requireFlashReveal: true, rememberSlot: false,
  });
  LauncherObservation.assertResponseSucceeded(startResponse, "launcher", "agent_control start");
  const ready = await LauncherObservation.waitForRuntimeReady(session, {
    slot: preparation.targetSlot, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
    startBoundary, startResponse,
  });
  const baseline = await CloneSaveGuard.captureStableSlotArtifactSet({ root,
    appData: preparation.seedBegin.appDataRoot, slot: preparation.targetSlot, requireJson: true,
    timeoutMs: args.cloneBaselineTimeoutMs, stableMs: args.cloneBaselineStableMs,
    pollMs: args.pollMs,
  });
  return { session, sessionEvidence: session.evidence, identity, processContract,
    launch, ready, baseline, cdpBinding, startBoundary };
}

async function openGenericRuntime(root, args, runDir) {
  if (!process.env.APPDATA) fail("appdata_root_missing", "clone_prepare",
    "APPDATA is required to prove the complete owned SOL set");
  const appData = SharedEvidence.assertExactDirectory(path.resolve(process.env.APPDATA),
    "clone_prepare");
  let lock = null;
  const resolved = RuntimeGuard.resolveCandidateIdentityBeforeMutation({ root,
    candidateRoot: path.resolve(args.candidateRoot), assertNoRuntime: assertNoLauncherBeforeMutation,
    prepareClone: (_identity, candidateEvidence) => {
      lock = CloneSaveGuard.acquireCloneLock({ root, slot: args.slot, runDir,
        ownedBaseRelative: OWNED_BASE_RELATIVE });
      try {
        const collateralBefore = captureSaveUniverse(root, appData, args.slot);
        const preparation = CloneSaveGuard.prepareDedicatedClone({ root, appData, runDir,
          ownedBaseRelative: OWNED_BASE_RELATIVE, seedSlot: args.seedSlot, targetSlot: args.slot, lock,
          validateSeed: isValidSaveData,
          transformJson(data) { data.lastSaved = formatLocalSaveTimestamp(); return data; },
          transformId: "kshop-clone-lastSaved-v1", validateTarget: isValidSaveData,
        });
        return { preparation, collateralBefore, candidateEvidence };
      } catch (error) {
        try { CloneSaveGuard.releaseCloneLock(lock); } catch (_releaseError) {}
        throw error;
      }
    },
  });
  const expectedIdentity = resolved.identity;
  try {
    const started = await startGenericRuntime(root, args,
      resolved.preparation.preparation, expectedIdentity);
    return Object.assign({}, started, { expectedIdentity, lock, appData,
      preparation: resolved.preparation.preparation,
      collateralBefore: resolved.preparation.collateralBefore,
      candidateBeforeClone: { schema: resolved.schema, apiVersion: resolved.apiVersion,
        resolvedAt: resolved.resolvedAt, identity: resolved.identity,
        identitySha256: resolved.identitySha256,
        candidateEvidence: resolved.preparation.candidateEvidence } });
  } catch (error) {
    await cleanupAuthenticatedPartialStart(root, expectedIdentity);
    throw error;
  }
}

async function restartGenericRuntime(root, args, preparation, expectedIdentity, first) {
  assertNoLauncherBeforeMutation();
  const restarted = await startGenericRuntime(root, args, preparation, expectedIdentity);
  LauncherObservation.assertFreshAuthenticatedRestart({
    first: first.identity, restart: restarted.identity,
    firstAttemptId: first.ready.expectedAttemptId,
    restartAttemptId: restarted.ready.expectedAttemptId,
    firstSession: first.sessionEvidence, restartSession: restarted.sessionEvidence,
  });
  return restarted;
}

async function cleanupAuthenticatedPartialStart(root, expectedIdentity) {
  try {
    const session = await LauncherObservation.waitForAuthenticatedLegacyHttp({ root,
      timeoutMs: 3000, pollMs: 200 });
    session.verifyRuntimeIdentity(expectedIdentity);
    const response = await session.agentControl("shutdown");
    return LauncherObservation.responseSucceeded(response);
  } catch (_error) { return false; }
}

function releaseGenericClone(runtime) {
  const collateralEnd = captureSaveUniverse(runtime.preparation.root, runtime.appData,
    runtime.preparation.targetSlot);
  const collateral = assertSaveUniverseInvariant(runtime.collateralBefore, collateralEnd);
  const release = CloneSaveGuard.releaseDedicatedClone({ preparation: runtime.preparation,
    lock: runtime.lock, appData: runtime.appData });
  return { release, collateralBefore: runtime.collateralBefore, collateralEnd, collateral };
}

module.exports = {
  OWNED_BASE_RELATIVE,
  assertNoLauncherBeforeMutation,
  assertSaveUniverseInvariant,
  captureSaveUniverse,
  cleanupAuthenticatedPartialStart,
  formatLocalSaveTimestamp,
  isValidSaveData,
  openGenericRuntime,
  releaseGenericClone,
  restartGenericRuntime,
  startGenericRuntime,
  verifySaveUniverse,
  withWebViewDebugEnvironment: RuntimeGuard.withWebViewDebugEnvironment,
};
