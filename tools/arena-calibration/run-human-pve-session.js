#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const RuntimeIdentity = require("../lib/runtime-process-identity");
const CloneSaveGuard = require("../workbench-live-e2e/lib/clone-save-guard");
const LauncherObservation = require("../workbench-live-e2e/lib/launcher-observation");
const RuntimeGuard = require("../workbench-live-e2e/lib/runtime-guard");
const SharedEvidence = require("../workbench-live-e2e/lib/evidence-artifact");
const { openArenaInputChannel } = require("../workbench-live-e2e/arena/cdp-input-channel");
const {
  assertNoLauncherBeforeMutation,
  captureSaveUniverse,
  isValidSaveData,
  releaseGenericClone,
} = require("../workbench-live-e2e/kshop/generic-opener");
const {
  atomicWriteJson,
  canonicalJson,
  readJson,
  sha256Bytes,
  sha256Text,
  sleep,
  timestampId,
} = require("../workbench-live-e2e/kshop/common");

const ROOT = path.resolve(__dirname, "..", "..");
const OWNED_RELATIVE = path.join("tmp", "workbench-live-e2e", "arena-pve");
const OWNED_BASE = path.join(ROOT, OWNED_RELATIVE);

class PveTranscriptWriter {
  constructor(runDir, observerId) {
    this.path = path.join(runDir, "pve-control-transcript.jsonl");
    this.summaryPath = path.join(runDir, "pve-control-transcript.json");
    this.observerId = String(observerId);
    this.events = [];
    this.previousHash = "0".repeat(64);
    fs.writeFileSync(this.path, "", { encoding: "utf8", mode: 0o600, flag: "wx" });
  }

  append(rawEvent) {
    const event = Object.assign({}, rawEvent, {
      observerId: this.observerId,
      sequence: this.events.length + 1,
      previousHash: this.previousHash,
      observedAt: new Date().toISOString(),
    });
    event.eventHash = sha256Text(canonicalJson(event));
    fs.appendFileSync(this.path, JSON.stringify(event) + "\n", { encoding: "utf8" });
    this.events.push(event);
    this.previousHash = event.eventHash;
    return event;
  }

  flush(extra) {
    const snapshot = Object.assign({
      schema: "arena-calibration.pve-control-transcript.v1",
      observerId: this.observerId,
      eventCount: this.events.length,
      chainHead: this.previousHash,
      events: this.events.slice(),
    }, extra || {});
    atomicWriteJson(this.summaryPath, snapshot);
    return snapshot;
  }
}

function usageError(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    plan: null,
    readyTimeoutMs: 180000,
    pollMs: 250,
    cloneBaselineTimeoutMs: 30000,
    cloneBaselineStableMs: 2000,
    startOrder: 1,
    signal: null,
    runDir: null,
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--plan") options.plan = path.resolve(argv[++index]);
    else if (token === "--ready-timeout-ms") options.readyTimeoutMs = Number(argv[++index]);
    else if (token === "--poll-ms") options.pollMs = Number(argv[++index]);
    else if (token === "--clone-baseline-timeout-ms") options.cloneBaselineTimeoutMs = Number(argv[++index]);
    else if (token === "--clone-baseline-stable-ms") options.cloneBaselineStableMs = Number(argv[++index]);
    else if (token === "--start-order") options.startOrder = Number(argv[++index]);
    else if (token === "--signal") options.signal = String(argv[++index] || "").toLowerCase();
    else if (token === "--run-dir") options.runDir = path.resolve(argv[++index]);
    else if (token === "--check") options.check = true;
    else if (token === "--help" || token === "-h") options.help = true;
    else usageError(`unknown argument: ${token}`);
  }
  ["readyTimeoutMs", "pollMs", "cloneBaselineTimeoutMs", "cloneBaselineStableMs"].forEach((field) => {
    if (!Number.isInteger(options[field]) || options[field] < 100 || options[field] > 3600000) {
      usageError(`invalid timeout: ${field}`);
    }
  });
  if (![1, 2].includes(options.startOrder)) usageError("--start-order must be 1 or 2");
  if (options.signal && !["next", "finish", "abort"].includes(options.signal)) {
    usageError("--signal must be next, finish, or abort");
  }
  if (options.signal && !options.runDir) usageError("--signal requires --run-dir");
  return options;
}

function usage() {
  return [
    "Usage: node tools/arena-calibration/run-human-pve-session.js --plan <private/pve-runtime-plan.json>",
    "       node tools/arena-calibration/run-human-pve-session.js --signal <next|finish|abort> --run-dir <owned-run-dir>",
    "The runner holds the exact clone lock and formal runtime open until an owned file signal is consumed.",
    "  --start-order <1|2>  Start directly from one frozen encounter (default: 1)",
    "  --check  Validate the session command/parser contract without starting the game",
  ].join("\n");
}

function validatePlan(plan, planPath) {
  if (!plan || plan.schema !== "arena-calibration.pve-runtime-plan.v1"
      || !/^cf7_agent_[A-Za-z0-9_-]+$/.test(String(plan.targetSlot || ""))
      || !/^[A-Za-z0-9_-]+$/.test(String(plan.seedSlot || ""))
      || !path.isAbsolute(String(plan.sourceSavePath || ""))
      || !Array.isArray(plan.encounters) || plan.encounters.length !== 2
      || !plan.playerBuild || plan.playerBuild.targetSlot !== plan.targetSlot
      || plan.playerBuild.seedSlot !== plan.seedSlot
      || !plan.runtimeIdentityRequired || plan.runtimeIdentityRequired.runtimeMode !== "formal_runtime"
      || plan.runtimeIdentityRequired.verified !== true) {
    usageError(`PVE runtime plan is incomplete: ${planPath}`);
  }
  const expectedSave = path.join(ROOT, "saves", `${plan.seedSlot}.json`);
  if (path.resolve(plan.sourceSavePath).toLowerCase() !== path.resolve(expectedSave).toLowerCase()) {
    usageError("PVE runtime plan sourceSavePath does not match seedSlot");
  }
  const seedBytes = fs.readFileSync(expectedSave);
  if (sha256Bytes(seedBytes) !== String(plan.playerBuild.saveSha256).replace(/^sha256:/, "")) {
    usageError("PVE player-build seed bytes changed after packet freeze");
  }
  const seedData = JSON.parse(seedBytes.toString("utf8"));
  if (!isValidSaveData(seedData)) usageError("PVE player-build seed no longer satisfies the clone contract");
  return { plan, seedBytes, seedData, expectedSave };
}

function exactRunDirectory(slot) {
  fs.mkdirSync(OWNED_BASE, { recursive: true });
  SharedEvidence.assertExactDirectory(OWNED_BASE, "pve_run_directory");
  const runDir = path.join(OWNED_BASE, `${timestampId()}-human-${slot}`);
  fs.mkdirSync(runDir);
  SharedEvidence.assertOwnedRunDirectory(ROOT, runDir, OWNED_RELATIVE, "pve_run_directory");
  return runDir;
}

function publicIdentity(identity) {
  if (!identity || !identity.processPath) throw new Error("runtime identity has no process path");
  return {
    runtimeMode: String(identity.runtimeMode || ""),
    processPath: path.resolve(identity.processPath),
    coreSha256: String(identity.coreSha256 || "").toUpperCase(),
    buildIdentity: String(identity.buildIdentity || "").toUpperCase(),
    payloadClosure: String(identity.payloadClosure || "").toUpperCase(),
  };
}

function assertFormalIdentity(plan, observed) {
  const required = plan.runtimeIdentityRequired;
  const fields = ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"];
  const normalized = publicIdentity(observed);
  if (fields.some((field) => {
    if (field === "processPath") return path.resolve(normalized[field]).toLowerCase() !== path.resolve(required[field]).toLowerCase();
    return String(normalized[field]).toUpperCase() !== String(required[field]).toUpperCase();
  })) {
    throw new Error("formal runtime identity differs from the frozen PVE plan");
  }
  return normalized;
}

function launchFormalRuntime(expectedIdentity, cdpPort) {
  const current = publicIdentity(RuntimeIdentity.resolveExpectedRuntimeIdentity(ROOT));
  if (canonicalJson(current) !== canonicalJson(publicIdentity(expectedIdentity))) {
    throw new Error("formal runtime identity drifted between clone preparation and launch");
  }
  const script = path.join(ROOT, "automation", "start.ps1");
  const args = RuntimeIdentity.buildLauncherStartArguments(script, expectedIdentity, {
    enableLegacyHttpAutomation: true,
  });
  const launch = () => childProcess.spawnSync("powershell.exe", args, {
    cwd: ROOT, encoding: "utf8", windowsHide: true, timeout: 120000,
  });
  const result = RuntimeGuard.withWebViewDebugEnvironment(cdpPort, launch);
  if (!result || result.status !== 0) {
    throw new Error(`formal Launcher start failed: status=${result && result.status}; ${String(result && result.stderr || "").slice(-1600)}`);
  }
  return {
    startedAt: new Date().toISOString(),
    scriptSha256: SharedEvidence.readExactRegularFile(script, {
      phase: "pve_launcher_start", maximumBytes: 4 * 1024 * 1024,
    }).sha256,
    stdoutTail: String(result.stdout || "").slice(-1600),
    cdpPort,
  };
}

async function waitNoLauncher(timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    try {
      if (assertNoLauncherBeforeMutation() === true) return true;
    } catch (_error) { /* runtime still present */ }
    await sleep(pollMs);
  }
  throw new Error("formal Launcher did not shut down inside the cleanup bound");
}

async function startRuntime(plan, args, preparation, expectedIdentity) {
  const cdpBinding = await RuntimeGuard.allocateLoopbackCdpPort();
  const launch = launchFormalRuntime(expectedIdentity, cdpBinding.port);
  const session = await LauncherObservation.waitForAuthenticatedLegacyHttp({
    root: ROOT, timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs,
  });
  const identity = session.verifyRuntimeIdentity(expectedIdentity);
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), identity.pid);
  const processContract = LauncherObservation.attestAuthenticatedLauncherProcess({
    root: ROOT, sessionEvidence: session.evidence, runtimeIdentity: identity,
  });
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
    slot: preparation.targetSlot,
    fresh: false,
    deferReveal: false,
    requireFlashReveal: true,
    rememberSlot: false,
  });
  LauncherObservation.assertResponseSucceeded(startResponse, "pve_launcher", "agent_control start");
  const ready = await LauncherObservation.waitForRuntimeReady(session, {
    slot: preparation.targetSlot,
    timeoutMs: args.readyTimeoutMs,
    pollMs: args.pollMs,
    startBoundary,
    startResponse,
  });
  const baseline = await CloneSaveGuard.captureStableSlotArtifactSet({
    root: ROOT,
    appData: preparation.seedBegin.appDataRoot,
    slot: preparation.targetSlot,
    requireJson: true,
    timeoutMs: args.cloneBaselineTimeoutMs,
    stableMs: args.cloneBaselineStableMs,
    pollMs: args.pollMs,
  });
  return { launch, session, identity, processContract, startBoundary, startResponse, ready,
    baseline, cdpBinding };
}

function signalSession(args) {
  const runDir = SharedEvidence.assertOwnedRunDirectory(
    ROOT, args.runDir, OWNED_RELATIVE, "pve_operator_signal");
  const reportPath = path.join(runDir, "report.json");
  const report = readJson(reportPath, "PVE live-session report");
  const allowedByStatus = {
    ready_for_human_pve_encounter_1: ["next", "finish", "abort"],
    ready_for_human_pve_encounter_2: ["finish", "abort"],
  };
  const allowed = allowedByStatus[report.status] || [];
  if (!allowed.includes(args.signal)) {
    usageError(`signal ${args.signal} is not allowed while session status is ${report.status}`);
  }
  const signalPath = path.join(runDir, "operator-command.pending.json");
  const payload = {
    schema: "arena-calibration.pve-operator-command.v1",
    runId: report.runId,
    command: args.signal,
    expectedStatus: report.status,
    requestedAt: new Date().toISOString(),
  };
  payload.commandHash = sha256Text(canonicalJson(payload));
  fs.writeFileSync(signalPath, JSON.stringify(payload, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
  process.stdout.write(`${JSON.stringify({ ok: true, event: "pve_session_signal_written",
    command: args.signal, runDir, signalPath, commandHash: payload.commandHash })}\n`);
}

async function waitForCommand(runDir, report, reportPath, args) {
  const signalPath = path.join(runDir, "operator-command.pending.json");
  while (true) {
    if (!fs.existsSync(signalPath)) {
      await sleep(args.pollMs);
      continue;
    }
    const payload = readJson(signalPath, "PVE operator command");
    const unsigned = Object.assign({}, payload);
    delete unsigned.commandHash;
    if (!payload || payload.schema !== "arena-calibration.pve-operator-command.v1"
        || payload.runId !== report.runId
        || !["next", "finish", "abort"].includes(payload.command)
        || payload.expectedStatus !== report.status
        || payload.commandHash !== sha256Text(canonicalJson(unsigned))) {
      throw new Error("PVE operator command is malformed or stale");
    }
    report.commandHistory = report.commandHistory || [];
    const consumedAt = new Date().toISOString();
    const consumedName = `operator-command-${String(report.commandHistory.length + 1).padStart(2, "0")}-${payload.command}.json`;
    const consumedPath = path.join(runDir, consumedName);
    fs.renameSync(signalPath, consumedPath);
    report.commandHistory.push({ command: payload.command, requestedAt: payload.requestedAt,
      consumedAt, commandHash: payload.commandHash, artifact: consumedName });
    atomicWriteJson(reportPath, report);
    return payload.command;
  }
}

async function waitUntil(label, timeoutMs, pollMs, probe) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    last = await probe();
    if (last) return last;
    await sleep(pollMs);
  }
  throw new Error(`${label} did not reach the required visible state`);
}

async function openAndPreloadEncounter(runtime, input, encounter, index, args, runDir) {
  const opener = await runtime.session.agentControl("openArena", {
    expectedSlot: runtime.ready.status.saveRuntime.savePath,
    expectedAttemptId: runtime.ready.expectedAttemptId,
  });
  LauncherObservation.assertResponseSucceeded(opener, "pve_arena_open", "agent_control openArena");
  if (opener.note !== "arena_panel_open_requested") {
    throw new Error("formal arena opener returned an unexpected note");
  }
  await waitUntil("arena panel", args.readyTimeoutMs, args.pollMs, async () => {
    const state = await input.readPveState();
    return state.panel === "arena" && state.hidden === false && state.customTabPresent ? state : null;
  });
  await input.click("customTab");
  await waitUntil("custom-mode entry", 15000, args.pollMs, async () => {
    const state = await input.readPveState();
    return state.activeMode === "custom" && state.customCardVisible ? state : null;
  });
  await input.click("customEdit");
  await waitUntil("custom editor", 15000, args.pollMs, async () => {
    const state = await input.readPveState();
    return state.editorVisible && state.codeInputPresent ? state : null;
  });
  await input.replaceText("codeInput", encounter.matchCode);
  await input.click("importCode");
  const imported = await waitUntil("frozen PVE code import", 15000, args.pollMs, async () => {
    const state = await input.readPveState();
    return state.matchError === "" && state.parsed && state.parsed.mode === "pve"
      && state.parsed.canonical === encounter.matchCode ? state : null;
  });
  await input.click("editorDone");
  await waitUntil("custom PVE card", 15000, args.pollMs, async () => {
    const state = await input.readPveState();
    return !state.editorVisible && state.customCardVisible && state.parsed
      && state.parsed.canonical === encounter.matchCode ? state : null;
  });
  await input.click("generatePve");
  const ready = await waitUntil("PVE final confirmation", 15000, args.pollMs, async () => {
    const state = await input.readPveState();
    return state.confirmVisible && state.startVisible && !state.startDisabled
      && state.parsed && state.parsed.mode === "pve"
      && state.parsed.canonical === encounter.matchCode ? state : null;
  });
  const screenshot = await input.captureScreenshot(
    path.join(runDir, `pve-encounter-${index + 1}-ready.png`),
    `controlled PVE encounter ${index + 1} ready before human start`);
  return {
    encounterId: encounter.encounterId,
    candidateAlias: encounter.candidateAlias,
    order: encounter.order,
    matchCodeSha256: encounter.matchCodeSha256,
    openedAt: new Date().toISOString(),
    opener,
    imported: { mode: imported.parsed.mode, seed: imported.parsed.seed,
      enemyCount: imported.parsed.enemyCount },
    finalConfirmation: { visible: ready.confirmVisible, startPresent: ready.startPresent,
      startVisible: ready.startVisible, startDisabled: ready.startDisabled,
      startText: ready.startText, automaticStartClick: false },
    screenshot,
  };
}

function checkContract() {
  const parsed = parseArgs(["--plan", "C:\\fixture\\plan.json", "--ready-timeout-ms", "180000",
    "--start-order", "2"]);
  const signal = parseArgs(["--signal", "finish", "--run-dir", "C:\\fixture\\run"]);
  if (parsed.readyTimeoutMs !== 180000 || parsed.plan !== path.resolve("C:\\fixture\\plan.json")
      || parsed.startOrder !== 2 || signal.signal !== "finish"
      || signal.runDir !== path.resolve("C:\\fixture\\run")) {
    throw new Error("human PVE session parser contract failed");
  }
  process.stdout.write(`${JSON.stringify({ ok: true, check: "human-pve-session-contract",
    controlTransport: "owned-file-signal", commands: ["next", "finish", "abort"] })}\n`);
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return process.stdout.write(`${usage()}\n`);
  if (args.check) return checkContract();
  if (args.signal) return signalSession(args);
  if (!args.plan) usageError("--plan is required");
  const validated = validatePlan(readJson(args.plan, "PVE runtime plan"), args.plan);
  const plan = validated.plan;
  const runDir = exactRunDirectory(plan.targetSlot);
  const reportPath = path.join(runDir, "report.json");
  const report = {
    schema: "arena-calibration.human-pve-live-session.v1",
    packetId: plan.packetId,
    packetHash: plan.packetHash,
    planHash: plan.planHash,
    runId: path.basename(runDir),
    runDir,
    seedSlot: plan.seedSlot,
    targetSlot: plan.targetSlot,
    startOrder: args.startOrder,
    commandHistory: [],
    seedBefore: { path: validated.expectedSave, bytes: validated.seedBytes.length,
      sha256: sha256Bytes(validated.seedBytes) },
    status: "preparing",
    startedAt: new Date().toISOString(),
  };
  atomicWriteJson(reportPath, report);
  let lock = null;
  let preparation = null;
  let runtime = null;
  let appData = null;
  let collateralBefore = null;
  let writer = null;
  let input = null;
  let cleaned = false;
  async function cleanup(command, originalError) {
    if (cleaned) return;
    cleaned = true;
    report.operatorCommand = command;
    report.cleanupStartedAt = new Date().toISOString();
    try {
      if (runtime && runtime.session) {
        try { if (input) input.close(); } catch (error) {
          report.inputDetachError = error.message;
        }
        try { if (writer) report.transcript = writer.flush({ detachedAt: new Date().toISOString() }); }
        catch (error) { report.transcriptFlushError = error.message; }
        try {
          report.terminalLog = await runtime.session.readTerminalLogSnapshot(2000);
        } catch (error) {
          report.terminalLogError = error.message;
        }
        try {
          const requestedAt = new Date().toISOString();
          const shutdown = await runtime.session.agentControl("shutdown");
          LauncherObservation.assertResponseSucceeded(shutdown, "pve_cleanup", "agent_control shutdown");
          report.shutdown = { responseSucceeded: true, requestedAt,
            completedAt: new Date().toISOString() };
        } catch (error) {
          report.shutdown = { responseSucceeded: false, error: error.message };
        }
        await waitNoLauncher(args.readyTimeoutMs, args.pollMs);
      }
      const seedAfter = fs.readFileSync(validated.expectedSave);
      if (!seedAfter.equals(validated.seedBytes)) throw new Error("PVE source player save changed during isolated session");
      report.seedInvariant = { unchanged: true, bytes: seedAfter.length, sha256: sha256Bytes(seedAfter) };
      if (preparation && lock) {
        report.cloneLifecycle = releaseGenericClone({
          preparation, lock, appData, collateralBefore,
        });
      } else if (lock && !preparation) {
        CloneSaveGuard.releaseCloneLock(lock);
      }
      report.status = originalError ? "failed_cleaned" : command === "finish" ? "human_run_finished_cleanup" : "aborted_cleaned";
      report.completedAt = new Date().toISOString();
      if (originalError) report.error = originalError.message;
      atomicWriteJson(reportPath, report);
    } catch (cleanupError) {
      report.status = "cleanup_failed";
      report.cleanupError = cleanupError.message;
      if (originalError) report.error = originalError.message;
      report.completedAt = new Date().toISOString();
      atomicWriteJson(reportPath, report);
      throw cleanupError;
    }
  }
  try {
    assertNoLauncherBeforeMutation();
    const expectedIdentity = RuntimeIdentity.resolveExpectedRuntimeIdentity(ROOT);
    if (expectedIdentity.runtimeMode !== "formal_runtime") throw new Error("canonical root did not resolve formal_runtime");
    report.expectedRuntimeIdentity = assertFormalIdentity(plan, expectedIdentity);
    if (!process.env.APPDATA) throw new Error("APPDATA is required for PVE clone ownership proof");
    appData = SharedEvidence.assertExactDirectory(path.resolve(process.env.APPDATA), "pve_clone_prepare");
    lock = CloneSaveGuard.acquireCloneLock({
      root: ROOT, slot: plan.targetSlot, runDir, ownedBaseRelative: OWNED_RELATIVE,
    });
    collateralBefore = captureSaveUniverse(ROOT, appData, plan.targetSlot);
    preparation = CloneSaveGuard.prepareDedicatedClone({
      root: ROOT,
      appData,
      runDir,
      ownedBaseRelative: OWNED_RELATIVE,
      seedSlot: plan.seedSlot,
      targetSlot: plan.targetSlot,
      lock,
      validateSeed: isValidSaveData,
      validateTarget: isValidSaveData,
    });
    if (preparation.transformId !== "exact-byte-copy") throw new Error("PVE clone was not an exact-byte copy");
    report.clonePreparation = {
      preparationSha256: preparation.preparationSha256,
      transformId: preparation.transformId,
      targetPrepared: preparation.targetPrepared,
    };
    report.status = "launching_formal_runtime";
    atomicWriteJson(reportPath, report);
    runtime = await startRuntime(plan, args, preparation, expectedIdentity);
    report.runtimeIdentity = assertFormalIdentity(plan, runtime.identity);
    report.runtime = {
      pid: runtime.identity.pid,
      launch: runtime.launch,
      processContract: runtime.processContract,
      attemptId: runtime.ready.expectedAttemptId,
      savePath: runtime.ready.status.saveRuntime.savePath,
      cdpBinding: runtime.cdpBinding,
    };
    writer = new PveTranscriptWriter(runDir, `arena-pve-${timestampId()}`);
    report.cdpAttestation = RuntimeGuard.attestLoopbackCdpEndpoint({
      port: runtime.cdpBinding.port,
      runtimePid: runtime.cdpBinding.runtimePid,
      expectedUserDataRoot: path.join(ROOT, "launcher", "webview2_overlay_userdata", "EBWebView"),
      expectedExecutableName: "msedgewebview2.exe",
    });
    writer.append({ kind: "pve_cdp_endpoint_attested",
      runtimePid: runtime.identity.pid, cdpPort: runtime.cdpBinding.port,
      attestation: report.cdpAttestation });
    input = await openArenaInputChannel({ cdpBinding: runtime.cdpBinding,
      runtimeIdentity: runtime.identity, writer,
      timeoutMs: args.readyTimeoutMs, pollMs: args.pollMs });
    let encounterIndex = args.startOrder - 1;
    report.controlledEncounters = [await openAndPreloadEncounter(
      runtime, input, plan.encounters[encounterIndex], encounterIndex, args, runDir)];
    report.status = `ready_for_human_pve_encounter_${encounterIndex + 1}`;
    if (encounterIndex === 0) report.readyAt = new Date().toISOString();
    else report.encounter2ReadyAt = new Date().toISOString();
    atomicWriteJson(reportPath, report);
    process.stdout.write(`${JSON.stringify({
      ok: true,
      event: "human_pve_session_ready",
      runDir,
      reportPath,
      packetId: plan.packetId,
      targetSlot: plan.targetSlot,
      runtimeIdentity: report.runtimeIdentity,
      attemptId: runtime.ready.expectedAttemptId,
      arenaOpen: true,
      controlledEncounter: { order: encounterIndex + 1, total: 2,
        alias: plan.encounters[encounterIndex].candidateAlias,
        matchCodeSha256: plan.encounters[encounterIndex].matchCodeSha256,
        startButtonReady: true, automaticStartClick: false },
      waitingFor: encounterIndex === 0 ? ["next", "finish", "abort"] : ["finish", "abort"],
    }, null, 2)}\n`);
    let command = await waitForCommand(runDir, report, reportPath, args);
    if (command === "next" && encounterIndex === 0) {
      encounterIndex = 1;
      report.encounter1AdvancedAt = new Date().toISOString();
      report.status = "loading_human_pve_encounter_2";
      atomicWriteJson(reportPath, report);
      report.controlledEncounters.push(await openAndPreloadEncounter(
        runtime, input, plan.encounters[1], 1, args, runDir));
      report.status = "ready_for_human_pve_encounter_2";
      report.encounter2ReadyAt = new Date().toISOString();
      atomicWriteJson(reportPath, report);
      process.stdout.write(`${JSON.stringify({ ok: true, event: "human_pve_encounter_ready",
        order: 2, total: 2, alias: plan.encounters[1].candidateAlias,
        matchCodeSha256: plan.encounters[1].matchCodeSha256,
        startButtonReady: true, automaticStartClick: false, reportPath }, null, 2)}\n`);
      command = await waitForCommand(runDir, report, reportPath, args);
    }
    await cleanup(command, null);
    process.stdout.write(`${JSON.stringify({ ok: true, event: "human_pve_session_closed", command, reportPath })}\n`);
  } catch (error) {
    try { await cleanup("abort", error); }
    catch (cleanupError) { throw new Error(`${error.message}; cleanup failed: ${cleanupError.message}`); }
    throw error;
  }
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.isUsageError ? 2 : 1;
  });
}

module.exports = { assertFormalIdentity, parseArgs, validatePlan };
