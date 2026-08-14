"use strict";

const path = require("path");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const RuntimeGuard = require("../lib/runtime-guard");
const { fail, sha256Text, canonicalJson } = require("./common");

const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "npc");

function validSave(data) {
  const player = data && data["0"];
  return !!data && data.version === "3.0" && Array.isArray(player)
    && player.length >= 14 && player[0] != null && player[0] !== ""
    && Array.isArray(data["1"]) && !!data.inventory && !!data.collection;
}

function localTimestamp() {
  const now = new Date();
  const part = (value) => String(value).padStart(2, "0");
  return now.getFullYear() + "-" + part(now.getMonth() + 1) + "-" + part(now.getDate())
    + " " + part(now.getHours()) + ":" + part(now.getMinutes()) + ":" + part(now.getSeconds());
}

function publicArtifactSet(set) {
  const json = set.artifacts.find((entry) => entry.kind === "json");
  const sols = set.artifacts.filter((entry) => entry.kind === "sol");
  const manifest = { schema: "workbench-live-e2e.npc.disk-artifact-set.v1",
    slot: set.slot, capturedAt: set.capturedAt,
    sourceSetSha256: set.setSha256, artifacts: set.artifacts };
  manifest.evidenceSha256 = sha256Text(canonicalJson(manifest));
  return { slot: set.slot, jsonSha256: json && json.sha256,
    solSetSha256: sha256Text(canonicalJson(sols)), solFiles: sols,
    artifactSetSha256: set.setSha256, manifest };
}

function noRuntime() {
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  return true;
}

function hostBody(line) {
  return String(line || "").replace(/^\d{2}:\d{2}:\d{2}\.\d{3}\s+/, "");
}

function recoveryDisposition(inspection) {
  const preserved = !!(inspection
    && (inspection.lockPresent === true || inspection.recoveryPresent === true));
  return { preservedForManualRecovery: preserved,
    cloneAlreadyReleased: !preserved, cloneInspection: inspection || null };
}

function lifecycleDependencies(overrides) {
  return Object.assign({
    allocateLoopbackCdpPort: RuntimeGuard.allocateLoopbackCdpPort,
    startLauncherCandidate: LauncherObservation.startLauncherCandidate,
    waitForAuthenticatedLegacyHttp: LauncherObservation.waitForAuthenticatedLegacyHttp,
    queryLauncherCoreProcesses: LauncherObservation.queryLauncherCoreProcesses,
    assertExclusiveLauncherProcess: LauncherObservation.assertExclusiveLauncherProcess,
    attestAuthenticatedLauncherProcess: LauncherObservation.attestAuthenticatedLauncherProcess,
    createTerminalLogBoundary: LauncherObservation.createTerminalLogBoundary,
    waitForAgentControl: LauncherObservation.waitForAgentControl,
    assertResponseSucceeded: LauncherObservation.assertResponseSucceeded,
    waitForRuntimeReady: LauncherObservation.waitForRuntimeReady,
    waitForCleanResidue: LauncherObservation.waitForCleanResidue,
  }, overrides || {});
}

function createLifecycleOwnership(label) {
  return { label: String(label || ""), phase: "created", launchAttempted: false,
    launchAccepted: false, runtimeReady: false, launchReceipt: null,
    identity: null, http: null, processContract: null, cdpBinding: null };
}

function cleanupErrorEvidence(error) {
  return { code: error && error.code || null,
    phase: error && error.phase || null,
    message: String(error && error.message || error || "runtime cleanup failed").slice(0, 1000) };
}

async function startLifecycle(root, candidateRoot, targetSlot, expectedIdentity, options,
    ownership, dependencyOverrides) {
  const dependencies = lifecycleDependencies(dependencyOverrides);
  const lifecycle = ownership || createLifecycleOwnership("runtime");
  lifecycle.phase = "allocating_cdp";
  const cdpBinding = await dependencies.allocateLoopbackCdpPort();
  lifecycle.cdpBinding = cdpBinding;
  lifecycle.phase = "launching";
  lifecycle.launchAttempted = true;
  lifecycle.launchReceipt = dependencies.startLauncherCandidate({ root, candidateRoot,
    expectedIdentity, cdpPort: cdpBinding.port });
  lifecycle.launchAccepted = true;
  lifecycle.phase = "authenticating";
  const http = await dependencies.waitForAuthenticatedLegacyHttp({
    root, timeoutMs: options.readyTimeoutMs, pollMs: options.pollMs,
  });
  lifecycle.http = http;
  const identity = http.verifyRuntimeIdentity(expectedIdentity);
  lifecycle.identity = identity;
  dependencies.assertExclusiveLauncherProcess(
    dependencies.queryLauncherCoreProcesses(), identity.pid);
  const processContract = dependencies.attestAuthenticatedLauncherProcess({
    root, sessionEvidence: http.evidence, runtimeIdentity: identity,
  });
  lifecycle.processContract = processContract;
  cdpBinding.runtimePid = identity.pid;
  cdpBinding.configurationSource = "CF7_WEBVIEW2_ARGS";
  cdpBinding.developerMode = true;
  const startBoundary = dependencies.createTerminalLogBoundary(
    await http.readTerminalLogSnapshot(2000));
  lifecycle.startBoundary = startBoundary;
  lifecycle.phase = "starting_runtime";
  await dependencies.waitForAgentControl(http, options);
  const startResponse = await http.agentControl("start", { slot: targetSlot,
    fresh: false, deferReveal: false, requireFlashReveal: true, rememberSlot: false });
  dependencies.assertResponseSucceeded(startResponse, "launcher", "agent_control start");
  lifecycle.startResponse = startResponse;
  lifecycle.phase = "waiting_runtime_ready";
  const ready = await dependencies.waitForRuntimeReady(http, {
    slot: targetSlot, timeoutMs: options.readyTimeoutMs, pollMs: options.pollMs,
    startBoundary, startResponse,
  });
  const stableIdentity = RuntimeGuard.publicCandidateIdentity(expectedIdentity);
  Object.assign(lifecycle, { identity, http, processContract, cdpBinding, startBoundary,
    attemptId: ready.expectedAttemptId, finalLog: null,
    timelineBoundaries: Object.create(null), shutdownEvidence: null,
    publicEvidence: { pid: identity.pid, controlPort: http.evidence.httpPort,
      cdpPort: cdpBinding.port, controlBindingPid: identity.pid,
      cdpBindingPid: identity.pid, cdpExclusiveBeforeLaunch: true,
      startedAt: new Date().toISOString(), stableIdentity } });
  lifecycle.runtimeReady = true;
  lifecycle.phase = "ready";
  return lifecycle;
}

async function cleanResidue(root, lifecycle, options, dependencyOverrides) {
  const dependencies = lifecycleDependencies(dependencyOverrides);
  return dependencies.waitForCleanResidue({ root,
    runtimeIdentity: lifecycle.identity, sessionEvidence: lifecycle.http.evidence,
    cdpBinding: lifecycle.cdpBinding, timeoutMs: options.timeoutMs,
    pollMs: options.pollMs, stableSamples: 3 });
}

async function cleanupOwnedLifecycle(root, lifecycle, options, dependencyOverrides) {
  const dependencies = lifecycleDependencies(dependencyOverrides);
  if (!lifecycle || lifecycle.launchAttempted !== true) {
    try {
      dependencies.assertExclusiveLauncherProcess(
        dependencies.queryLauncherCoreProcesses(), null);
      return { runtimeCleanupVerified: true, shutdownSucceeded: false,
        noLaunchAttempted: true, residue: null };
    } catch (error) {
      return { runtimeCleanupVerified: false, shutdownSucceeded: false,
        preservedForManualRecovery: true, reason: "runtime_absence_unverified",
        cleanupError: cleanupErrorEvidence(error) };
    }
  }
  if (lifecycle.launchAccepted !== true || !lifecycle.http || !lifecycle.identity
      || !lifecycle.processContract || !lifecycle.cdpBinding
      || lifecycle.cdpBinding.runtimePid !== lifecycle.identity.pid
      || !lifecycle.http.evidence || lifecycle.http.evidence.pid !== lifecycle.identity.pid) {
    return { runtimeCleanupVerified: false, shutdownSucceeded: false,
      preservedForManualRecovery: true, reason: "partial_start_identity_unavailable" };
  }
  let response;
  const requestedAt = new Date().toISOString();
  try {
    response = await lifecycle.http.agentControl("shutdown");
    dependencies.assertResponseSucceeded(response, "shutdown", "agent_control shutdown");
  } catch (error) {
    return { runtimeCleanupVerified: false, shutdownSucceeded: false,
      preservedForManualRecovery: true, reason: "authenticated_shutdown_failed",
      cleanupError: cleanupErrorEvidence(error) };
  }
  const shutdown = {
    schema: "workbench-live-e2e.npc.failure-cleanup-shutdown.v1",
    requestedAt, completedAt: new Date().toISOString(), pid: lifecycle.identity.pid,
    runtimeIdentity: JSON.parse(JSON.stringify(lifecycle.identity)),
    sessionEvidence: JSON.parse(JSON.stringify(lifecycle.http.evidence)),
    cdpBinding: JSON.parse(JSON.stringify(lifecycle.cdpBinding)),
    response: JSON.parse(JSON.stringify(response)),
    responseSha256: sha256Text(canonicalJson(response)), responseSucceeded: true,
  };
  shutdown.evidenceSha256 = sha256Text(canonicalJson(shutdown));
  let residue;
  try {
    residue = await cleanResidue(root, lifecycle, options, dependencies);
  } catch (error) {
    return { runtimeCleanupVerified: false, shutdownSucceeded: true,
      preservedForManualRecovery: true, reason: "runtime_residue_unverified",
      shutdown,
      cleanupError: cleanupErrorEvidence(error) };
  }
  return { runtimeCleanupVerified: true, shutdownSucceeded: true,
    preservedForManualRecovery: false, shutdown, residue };
}

async function completePrecommitCleanup(settings) {
  const runtimeCleanup = await cleanupOwnedLifecycle(settings.root, settings.lifecycle,
    settings.runtimeOptions, settings.lifecycleDependencies);
  if (runtimeCleanup.runtimeCleanupVerified !== true) {
    const inspection = settings.inspectClone();
    return Object.assign({}, runtimeCleanup, {
      preservedForManualRecovery: true,
      cloneAlreadyReleased: inspection.lockPresent !== true
        && inspection.recoveryPresent !== true,
      cloneInspection: inspection,
    });
  }
  const release = settings.releaseClone();
  return Object.assign({}, runtimeCleanup, { releasedBeforeCommit: true,
    cloneAlreadyReleased: true, cloneRelease: release });
}

function loadSharedAdapter(rootInput, adapterOptions) {
  const root = path.resolve(rootInput);
  const ownedBaseRelative = adapterOptions && adapterOptions.ownedBaseRelative
    ? String(adapterOptions.ownedBaseRelative) : OWNED_BASE_RELATIVE;
  const returnFullArchiveEvidence = !!(adapterOptions
    && adapterOptions.returnFullArchiveEvidence === true);
  return Object.freeze({
    async prepare(options) {
      if (!process.env.APPDATA) fail("appdata_root_missing", "clone_prepare", "APPDATA is required");
      const appData = Evidence.assertExactDirectory(path.resolve(process.env.APPDATA), "clone_prepare");
      let lock = null;
      let preparation = null;
      const resolved = RuntimeGuard.resolveCandidateIdentityBeforeMutation({
        root, candidateRoot: path.resolve(options.candidateRoot), assertNoRuntime: noRuntime,
        prepareClone: () => {
          lock = CloneGuard.acquireCloneLock({ root, slot: options.slot,
            runDir: options.runDir, ownedBaseRelative });
          try {
            preparation = CloneGuard.prepareDedicatedClone({ root, appData,
              runDir: options.runDir, ownedBaseRelative,
              seedSlot: options.seedSlot, targetSlot: options.slot, lock,
              validateSeed: validSave,
              transformJson(data) { data.lastSaved = localTimestamp(); return data; },
              transformId: "npc-clone-lastSaved-v2", validateTarget: validSave,
            });
            return { preparationSha256: preparation.preparationSha256 };
          } catch (error) {
            try { CloneGuard.releaseCloneLock(lock); } catch (_releaseError) {}
            throw error;
          }
        },
      });
      const lifecycles = {};
      let archive = null;
      let firstResidue = null;
      const candidateIdentity = RuntimeGuard.publicCandidateIdentity(resolved.identity);
      const candidate = { verifiedBeforeCloneMutation: true, verifiedAt: resolved.resolvedAt,
        stableIdentity: candidateIdentity };
      const clone = { slot: options.slot, lockExclusive: true,
        mutatedAt: preparation.preparedAt,
        baselineJsonSha256: publicArtifactSet(preparation.targetPrepared).jsonSha256,
        afterArchiveJsonSha256: null };
      const seedBefore = publicArtifactSet(preparation.seedBegin);

      return {
        candidate, clone, seedBefore,
        async start(label, startOptions) {
          if (lifecycles[label]) fail("runtime_label_reused", "runtime", "runtime lifecycle label was reused");
          const lifecycle = createLifecycleOwnership(label);
          // Ownership is registered before the first launch side effect. A readiness
          // exception must still leave an authenticated runtime available to cleanupFailure.
          lifecycles[label] = lifecycle;
          await startLifecycle(root, path.resolve(options.candidateRoot),
            options.slot, resolved.identity, startOptions, lifecycle);
          if (label === "restart" && lifecycles.first) {
            LauncherObservation.assertFreshAuthenticatedRestart({
              first: lifecycles.first.identity, restart: lifecycle.identity,
              firstAttemptId: lifecycles.first.attemptId, restartAttemptId: lifecycle.attemptId,
              firstSession: lifecycles.first.http.evidence, restartSession: lifecycle.http.evidence,
            });
          }
          return lifecycle;
        },
        async awaitArchive(label, settings) {
          const lifecycle = lifecycles[label];
          if (!lifecycle) fail("runtime_label_missing", "archive", "first lifecycle is absent");
          const deadline = Date.now() + settings.timeoutMs;
          let last = null;
          while (Date.now() <= deadline) {
            try {
              lifecycle.finalLog = await lifecycle.http.readTerminalLogSnapshot(2000);
              const disk = LauncherObservation.captureDiskSaveEvidence({ root, slot: options.slot });
              const value = LauncherObservation.verifyArchiveSaveEvidence({ root,
                slot: options.slot, boundary: lifecycle.startBoundary,
                snapshot: lifecycle.finalLog, diskEvidence: disk,
                requiredOrder: ["sv1", "sv2", "archive"] });
              clone.afterArchiveJsonSha256 = value.disk.sha256;
              archive = returnFullArchiveEvidence ? {
                schema: "workbench-live-e2e.npc.archive-capture-bundle.v1",
                evidence: value,
                snapshot: lifecycle.finalLog,
              } : { slot: options.slot, hostLine: value.archive.lineNumber,
                characters: value.archive.characters,
                sv1HostLine: value.positions.sv1.lineNumber,
                sv2HostLine: value.positions.sv2.lineNumber,
                observedAt: lifecycle.finalLog.capturedAt };
              if (returnFullArchiveEvidence) {
                archive.bundleSha256 = sha256Text(canonicalJson(archive));
              }
              return archive;
            } catch (error) { last = error; }
            await new Promise((resolve) => setTimeout(resolve, settings.pollMs));
          }
          throw last || new Error("archive wait timed out");
        },
        async awaitExactClose(label, panelOrInstanceId, instanceOrSettings, maybeSettings) {
          const lifecycle = lifecycles[label];
          if (!lifecycle) fail("runtime_label_missing", "host_close", "runtime lifecycle is absent");
          const legacy = maybeSettings == null;
          const panel = legacy ? "npcshop" : String(panelOrInstanceId || "");
          const panelInstanceId = legacy ? panelOrInstanceId : instanceOrSettings;
          const settings = legacy ? instanceOrSettings : maybeSettings;
          if (!["npcshop", "crafting"].includes(panel)
              || !/^[A-Za-z0-9._~-]{1,128}$/.test(String(panelInstanceId || ""))) {
            fail("host_close_owner_invalid", "host_close",
              "exact close wait requires one supported panel and opaque owner instance");
          }
          const completion = "event=panel_exact_close_completed panel=" + panel
            + " panelInstanceId=" + String(panelInstanceId);
          const requestPrefix = "[Panel] HandlePanelMessage: task=panel panel=" + panel
            + " domain=other cmd=close callId=other payload=redacted len=";
          const deadline = Date.now() + settings.timeoutMs;
          let last = null;
          while (Date.now() <= deadline) {
            try {
              const snapshot = await lifecycle.http.readTerminalLogSnapshot(2000);
              const records = LauncherObservation.recordsAfterTerminalBoundary(
                lifecycle.startBoundary, snapshot).map((record) => ({
                lineNumber: record.lineNumber, body: hostBody(record.line),
              }));
              const closeRequests = records.filter((record) =>
                record.body.startsWith(requestPrefix)
                && /^\d+$/.test(record.body.slice(requestPrefix.length)));
              const closed = records.filter((record) => record.body === "[PanelHost] closed: " + panel);
              const completed = records.filter((record) => record.body === completion);
              if (closeRequests.length === 1 && closed.length === 1 && completed.length === 1
                  && closeRequests[0].lineNumber < closed[0].lineNumber
                  && closed[0].lineNumber < completed[0].lineNumber) {
                lifecycle.closeSettledLog = snapshot;
                return { capturedAt: snapshot.capturedAt,
                  closeReceiptLine: completed[0].lineNumber };
              }
              last = new Error("exact NPC close completion is not yet present");
            } catch (error) { last = error; }
            await new Promise((resolve) => setTimeout(resolve, settings.pollMs));
          }
          throw last || new Error("exact NPC close wait timed out");
        },
        async awaitExit(label, settings) {
          firstResidue = await cleanResidue(root, lifecycles[label], settings);
          const archivedSet = publicArtifactSet(CloneGuard.captureSlotArtifactSet({ root, appData,
            slot: options.slot, requireJson: true }));
          if (archivedSet.jsonSha256 !== clone.afterArchiveJsonSha256) {
            fail("archive_disk_changed_after_exit", "archive",
              "JSON changed between exact archive receipt and first-process exit");
          }
          clone.afterArchiveArtifactSetSha256 = archivedSet.artifactSetSha256;
          clone.afterArchiveSolSetSha256 = archivedSet.solSetSha256;
          clone.afterArchiveManifest = archivedSet.manifest;
          return firstResidue;
        },
        async captureHostBoundary(label, name) {
          const lifecycle = lifecycles[label];
          if (!lifecycle || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(name || ""))) {
            fail("host_timeline_boundary_invalid", "host_log", "timeline boundary identity is invalid");
          }
          const snapshot = await lifecycle.http.readTerminalLogSnapshot(2000);
          LauncherObservation.verifyLogSnapshot(snapshot);
          const boundary = LauncherObservation.createTerminalLogBoundary(snapshot);
          lifecycle.timelineBoundaries[name] = boundary;
          return boundary;
        },
        async captureTerminalLog(label) {
          const lifecycle = lifecycles[label];
          if (!lifecycle) fail("runtime_label_missing", "host_log",
            "runtime lifecycle is absent");
          const snapshot = await lifecycle.http.readTerminalLogSnapshot(2000);
          LauncherObservation.verifyLogSnapshot(snapshot);
          lifecycle.finalLog = snapshot;
          return snapshot;
        },
        async shutdownFinal(label, settings) {
          const lifecycle = lifecycles[label];
          lifecycle.finalLog = await lifecycle.http.readTerminalLogSnapshot(2000);
          const requestedAt = new Date().toISOString();
          const response = await lifecycle.http.agentControl("shutdown");
          LauncherObservation.assertResponseSucceeded(response, "shutdown", "agent_control shutdown");
          const completedAt = new Date().toISOString();
          lifecycle.shutdownEvidence = {
            schema: "workbench-live-e2e.npc.supported-shutdown.v1",
            lifecycle: label,
            action: "shutdown",
            pid: lifecycle.identity.pid,
            requestedAt,
            completedAt,
            responseSha256: sha256Text(canonicalJson(response)),
            responseSucceeded: true,
          };
          lifecycle.shutdownEvidence.evidenceSha256 = sha256Text(canonicalJson(lifecycle.shutdownEvidence));
          lifecycle.finalResidue = await cleanResidue(root, lifecycle, settings);
          return { shutdown: lifecycle.shutdownEvidence,
            response: JSON.parse(JSON.stringify(response)), residue: lifecycle.finalResidue };
        },
        async verifyResidue() {
          const value = lifecycles.restart && lifecycles.restart.finalResidue;
          if (!value || !firstResidue) {
            fail("runtime_residue_missing", "residue", "first/restart clean residue was not captured");
          }
          const evidence = { schema: "workbench-live-e2e.npc.runtime-residue.v2",
            checkedAfterRestartShutdown: true, checkedAt: value.observedAt,
            first: firstResidue, restart: value };
          evidence.evidenceSha256 = sha256Text(canonicalJson(evidence));
          return evidence;
        },
        async captureSeedInvariant() {
          return publicArtifactSet(CloneGuard.captureSlotArtifactSet({ root, appData,
            slot: options.seedSlot, requireJson: true }));
        },
        async captureCloneAfterRestart() {
          const set = CloneGuard.captureSlotArtifactSet({ root, appData,
            slot: options.slot, requireJson: true });
          return publicArtifactSet(set);
        },
        async captureHostLog() {
          const output = { schema: "workbench-live-e2e.npc.host-evidence.v4",
            utcOffsetMinutes: -new Date().getTimezoneOffset(), lifecycles: {} };
          ["first", "restart"].forEach((label) => {
            const lifecycle = lifecycles[label];
            if (!lifecycle || !lifecycle.finalLog) {
              fail("host_lifecycle_missing", "host_log",
                "authenticated Host terminal evidence is missing", { label });
            }
            if (!lifecycle.closeSettledLog) {
              fail("host_close_settlement_missing", "host_log",
                "exact close was not captured before the next lifecycle action", { label });
            }
            LauncherObservation.verifyTerminalLogBoundary(lifecycle.startBoundary);
            LauncherObservation.verifyLogSnapshot(lifecycle.closeSettledLog);
            LauncherObservation.verifyLogSnapshot(lifecycle.finalLog);
            LauncherObservation.recordsAfterTerminalBoundary(
              lifecycle.startBoundary, lifecycle.closeSettledLog);
            LauncherObservation.recordsAfterTerminalBoundary(
              LauncherObservation.createTerminalLogBoundary(lifecycle.closeSettledLog),
              lifecycle.finalLog);
            LauncherObservation.recordsAfterTerminalBoundary(
              lifecycle.startBoundary, lifecycle.finalLog);
            output.lifecycles[label] = {
              startBoundary: lifecycle.startBoundary,
              closeSettledSnapshot: lifecycle.closeSettledLog,
              terminalSnapshot: lifecycle.finalLog,
              timelineBoundaries: lifecycle.timelineBoundaries,
            };
          });
          return output;
        },
        async release() {
          const evidence = CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
          return { cloneLockReleased: true, releasedAt: evidence.releasedAt,
            recoveryCleared: evidence.recoveryClear && evidence.recoveryClear.recoveryFileAbsent === true };
        },
        async cleanupFailure(settings) {
          if (settings && settings.commitMayHaveReachedAuthority) {
            // Never terminate or restore after an authority write may have landed. Report
            // durable lock/recovery state instead of claiming preservation after release.
            return recoveryDisposition(CloneGuard.inspectCloneLock({
              root, slot: options.slot,
            }));
          }
          const active = lifecycles.restart || lifecycles.first;
          return completePrecommitCleanup({ root, lifecycle: active,
            runtimeOptions: { timeoutMs: 60000, pollMs: 250 },
            inspectClone: () => CloneGuard.inspectCloneLock({ root, slot: options.slot }),
            releaseClone: () => CloneGuard.releaseDedicatedClone({ preparation, lock, appData }),
          });
        },
      };
    },
  });
}

module.exports = { loadSharedAdapter, recoveryDisposition, createLifecycleOwnership,
  startLifecycle, cleanupOwnedLifecycle, completePrecommitCleanup };
