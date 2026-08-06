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

async function startLifecycle(root, candidateRoot, targetSlot, expectedIdentity, options) {
  const cdpBinding = await RuntimeGuard.allocateLoopbackCdpPort();
  LauncherObservation.startLauncherCandidate({ root, candidateRoot,
    expectedIdentity, cdpPort: cdpBinding.port });
  const http = await LauncherObservation.waitForAuthenticatedLegacyHttp({
    root, timeoutMs: options.readyTimeoutMs, pollMs: options.pollMs,
  });
  const identity = http.verifyRuntimeIdentity(expectedIdentity);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), identity.pid);
  const processContract = LauncherObservation.attestAuthenticatedLauncherProcess({
    root, sessionEvidence: http.evidence, runtimeIdentity: identity,
  });
  cdpBinding.runtimePid = identity.pid;
  cdpBinding.configurationSource = "CF7_WEBVIEW2_ARGS";
  cdpBinding.developerMode = true;
  const startBoundary = LauncherObservation.createTerminalLogBoundary(
    await http.readTerminalLogSnapshot(2000));
  await LauncherObservation.waitForAgentControl(http, options);
  const startResponse = await http.agentControl("start", { slot: targetSlot,
    fresh: false, deferReveal: false, requireFlashReveal: true, rememberSlot: false });
  LauncherObservation.assertResponseSucceeded(startResponse, "launcher", "agent_control start");
  const ready = await LauncherObservation.waitForRuntimeReady(http, {
    slot: targetSlot, timeoutMs: options.readyTimeoutMs, pollMs: options.pollMs,
    startBoundary, startResponse,
  });
  const stableIdentity = RuntimeGuard.publicCandidateIdentity(expectedIdentity);
  return { identity, http, processContract, cdpBinding, startBoundary,
    attemptId: ready.expectedAttemptId, finalLog: null,
    timelineBoundaries: Object.create(null), shutdownEvidence: null,
    publicEvidence: { pid: identity.pid, controlPort: http.evidence.httpPort,
      cdpPort: cdpBinding.port, controlBindingPid: identity.pid,
      cdpBindingPid: identity.pid, cdpExclusiveBeforeLaunch: true,
      startedAt: new Date().toISOString(), stableIdentity } };
}

async function cleanResidue(root, lifecycle, options) {
  return LauncherObservation.waitForCleanResidue({ root,
    runtimeIdentity: lifecycle.identity, sessionEvidence: lifecycle.http.evidence,
    cdpBinding: lifecycle.cdpBinding, timeoutMs: options.timeoutMs,
    pollMs: options.pollMs, stableSamples: 3 });
}

function loadSharedAdapter(rootInput) {
  const root = path.resolve(rootInput);
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
            runDir: options.runDir, ownedBaseRelative: OWNED_BASE_RELATIVE });
          try {
            preparation = CloneGuard.prepareDedicatedClone({ root, appData,
              runDir: options.runDir, ownedBaseRelative: OWNED_BASE_RELATIVE,
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
          const lifecycle = await startLifecycle(root, path.resolve(options.candidateRoot),
            options.slot, resolved.identity, startOptions);
          if (label === "restart" && lifecycles.first) {
            LauncherObservation.assertFreshAuthenticatedRestart({
              first: lifecycles.first.identity, restart: lifecycle.identity,
              firstAttemptId: lifecycles.first.attemptId, restartAttemptId: lifecycle.attemptId,
              firstSession: lifecycles.first.http.evidence, restartSession: lifecycle.http.evidence,
            });
          }
          lifecycles[label] = lifecycle;
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
              archive = { slot: options.slot, hostLine: value.archive.lineNumber,
                characters: value.archive.characters,
                sv1HostLine: value.positions.sv1.lineNumber,
                sv2HostLine: value.positions.sv2.lineNumber,
                observedAt: lifecycle.finalLog.capturedAt };
              return archive;
            } catch (error) { last = error; }
            await new Promise((resolve) => setTimeout(resolve, settings.pollMs));
          }
          throw last || new Error("archive wait timed out");
        },
        async awaitExactClose(label, panelInstanceId, settings) {
          const lifecycle = lifecycles[label];
          if (!lifecycle) fail("runtime_label_missing", "host_close", "runtime lifecycle is absent");
          const completion = "event=panel_exact_close_completed panel=npcshop panelInstanceId="
            + String(panelInstanceId);
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
                record.body.startsWith("[Panel] HandlePanelMessage: ")
                && /(?:^|\s)panel=npcshop(?:\s|$)/.test(record.body)
                && /(?:^|\s)domain=none(?:\s|$)/.test(record.body)
                && /(?:^|\s)cmd=close(?:\s|$)/.test(record.body));
              const closed = records.filter((record) => record.body === "[PanelHost] closed: npcshop");
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
            // Never terminate or restore after an authority write may have landed. The exact
            // clone lock/recovery record remains for visible SAFEEXIT recovery.
            return { preservedForManualRecovery: true };
          }
          const active = lifecycles.restart || lifecycles.first;
          if (active && active.http) {
            try { await active.http.agentControl("shutdown"); } catch (_error) {}
            try { await cleanResidue(root, active, { timeoutMs: 60000, pollMs: 250 }); }
            catch (_error) { return { preservedForManualRecovery: true }; }
          }
          CloneGuard.releaseDedicatedClone({ preparation, lock, appData });
          return { releasedBeforeCommit: true };
        },
      };
    },
  });
}

module.exports = { loadSharedAdapter };
