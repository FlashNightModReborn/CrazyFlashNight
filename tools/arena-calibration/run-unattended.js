#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");
const LegacyHttpClient = require("../lib/legacy-http-client");
const {
  buildLauncherStartArguments,
  checkRuntimeIdentityContract,
  createRuntimeIdentityReport,
  recordObservedRuntimeIdentity,
  recordVerifiedRuntimeIdentity,
  resolveExpectedRuntimeIdentity,
  verifyRuntimeIdentity,
} = require("../lib/runtime-process-identity");
const {
  AGENT_ENTER_COMMAND,
  assertRuntimeReadyStatus,
  findFreshHandoff,
  findFreshRevealWatchdog,
  findFreshTitleFrame,
  freshLogRecords,
  logWatermark,
  shouldRequestAgentEnter,
  statusAttemptForSlot,
} = require("../equipment-tuning/run-unattended");
const { checkAgentEntryContract } = require("../test-agent-entry-contract");
const {
  analyzeRows,
  createPilotManifest,
  fail,
  formatSummaryMarkdown,
  normalizeManifest,
  normalizeResultRow,
  readJsonFile,
  readJsonLines,
  sha256OfValue,
  writeJsonFile,
} = require("./lib/arena-calibration-core");
const { assertSchemaInstance } = require("./lib/schema-registry");

const TERMINAL_STATES = new Set(["completed", "failed", "aborted"]);
const DEFAULT_AGENT_SLOT = "cf7_agent_arena_calibration";
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const LOG_TAIL_LIMIT = 2000;
let activeLegacyHttpContext = null;

function parseArgs(argv) {
  const args = {
    slot: null,
    manifest: null,
    generatePilot: false,
    batchId: null,
    repeat: 5,
    timeoutFrames: 5400,
    startLauncher: true,
    fresh: false,
    shutdown: false,
    readyTimeoutMs: 180000,
    batchTimeoutMs: 0,
    pollMs: 1000,
    summary: null,
    summaryMd: null,
    report: null,
    reportMd: null,
    rerunManifest: null,
    buildGates: ["arena-tools"],
    keepLauncherDuringGate: false,
    maxRecoveryAttempts: 1,
    allowLiveSlot: false,
    allowFresh: false,
    seedSlot: null,
    candidateRoot: null,
    cancelFile: null,
    check: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--slot") args.slot = argv[++index];
    else if (token === "--manifest") args.manifest = argv[++index];
    else if (token === "--generate-pilot") args.generatePilot = true;
    else if (token === "--batch-id") args.batchId = argv[++index];
    else if (token === "--repeat") args.repeat = Number(argv[++index]);
    else if (token === "--timeout-frames") args.timeoutFrames = Number(argv[++index]);
    else if (token === "--no-start-launcher") args.startLauncher = false;
    else if (token === "--fresh") args.fresh = true;
    else if (token === "--shutdown") args.shutdown = true;
    else if (token === "--ready-timeout-ms") args.readyTimeoutMs = Number(argv[++index]);
    else if (token === "--batch-timeout-ms") args.batchTimeoutMs = Number(argv[++index]);
    else if (token === "--poll-ms") args.pollMs = Number(argv[++index]);
    else if (token === "--summary") args.summary = argv[++index];
    else if (token === "--summary-md") args.summaryMd = argv[++index];
    else if (token === "--report") args.report = argv[++index];
    else if (token === "--report-md") args.reportMd = argv[++index];
    else if (token === "--rerun-manifest") args.rerunManifest = argv[++index];
    else if (token === "--build-gate") args.buildGates = parseGateList(argv[++index]);
    else if (token === "--add-build-gate") args.buildGates.push(...parseGateList(argv[++index]));
    else if (token === "--keep-launcher-during-gate") args.keepLauncherDuringGate = true;
    else if (token === "--max-recovery-attempts") args.maxRecoveryAttempts = Number(argv[++index]);
    else if (token === "--allow-live-slot") args.allowLiveSlot = true;
    else if (token === "--allow-fresh") args.allowFresh = true;
    else if (token === "--seed-slot") args.seedSlot = argv[++index];
    else if (token === "--cancel-file") args.cancelFile = argv[++index];
    else if (token === "--candidate-root") {
      const value = argv[++index];
      if (!value || String(value).startsWith("--")) fail("--candidate-root requires a value");
      args.candidateRoot = value;
    }
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/run-unattended.js [options]

Options:
  --slot <slot>              Dedicated launcher save slot to enter. Default: ${DEFAULT_AGENT_SLOT}.
  --manifest <file>          Existing manifest seed; normalized into tmp/arena-calibration.
  --generate-pilot           Generate a pilot manifest when --manifest is omitted.
  --batch-id <id>            Batch id for generated pilot manifests.
  --repeat <n>               Pilot repeat count. Default: 5.
  --timeout-frames <n>       Pilot timeout frames. Default: 5400.
  --fresh                    Use fresh-start/rebuild semantics for the selected slot.
  --no-start-launcher        Require an already running launcher.
  --candidate-root <dir>     Run and bind to one immutable local runtime candidate.
  --ready-timeout-ms <n>     Cold-start/game-ready timeout. Default: 180000.
  --batch-timeout-ms <n>     Abort the batch after this wall-clock timeout. Default: disabled.
  --poll-ms <n>              Status polling interval. Default: 1000.
  --summary <file>           Summary JSON output path.
  --summary-md <file>        Summary markdown output path.
  --report <file>            Unattended run report JSON output path.
  --report-md <file>         Unattended run report markdown output path.
  --rerun-manifest <file>    Output path for missing/abnormal rerun manifest.
  --build-gate <list>        Comma-separated gates before launch. Default: arena-tools.
                             Values: none, arena-tools, launcher-tests, as2-publish, as2-test.
                             Runtime builds are not an inline gate: build separately, then
                             select the exact producer output with --candidate-root.
  --add-build-gate <list>    Append gates to the current gate list.
  --keep-launcher-during-gate
                             Do not auto-shutdown an existing launcher before build gates.
  --max-recovery-attempts <n>
                             Auto-run generated rerun manifests after crash/abnormal rows. Default: 1.
  --seed-slot <slot>         Source shadow slot used to seed the dedicated calibration slot.
  --cancel-file <file>       Owned tmp/arena-calibration/*.signal path; presence requests bounded abort/yield.
  --allow-live-slot          Allow crazyflasher7_saves* as target slot. Unsafe; off by default.
  --allow-fresh              Allow --fresh. Unsafe for seeded unattended calibration; off by default.
  --shutdown                 Ask launcher to shut down after terminal batch state.
  --check                    Self-check without launching the game.

Without --candidate-root, runtimeMode=formal_runtime; with it, isolated_candidate.
`);
}

function parseGateList(value) {
  if (!value) return [];
  return String(value)
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function projectRoot() {
  return path.resolve(__dirname, "../..");
}

function timestampId(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function toProjectRelative(root, filePath) {
  return path.relative(root, filePath).replace(/\\/g, "/");
}

function resolveInputPath(root, filePath) {
  return path.isAbsolute(filePath) ? filePath : path.resolve(root, filePath);
}

function resolveOwnedCancelFile(root, filePath) {
  if (!filePath) return null;
  const resolved = resolveInputPath(root, filePath);
  const ownedRoot = path.resolve(root, "tmp", "arena-calibration");
  const relative = path.relative(ownedRoot, resolved);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative) || path.extname(resolved).toLowerCase() !== ".signal") {
    fail("--cancel-file must be a .signal file below tmp/arena-calibration");
  }
  return resolved;
}

function sanitizeSlotName(slot) {
  const text = String(slot || "");
  let out = "";
  for (const ch of text) {
    if ((ch >= "a" && ch <= "z") || (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") || ch === "_" || ch === "-") {
      out += ch;
    } else {
      out += "_";
    }
  }
  return out || "default";
}

function isLiveSlot(slot) {
  return LIVE_SLOT_RE.test(String(slot || ""));
}

function assertSafeSlotArgs(args) {
  if (!args.slot) args.slot = DEFAULT_AGENT_SLOT;
  if (sanitizeSlotName(args.slot) !== args.slot) {
    fail(`slot ${args.slot} is not a safe launcher slot name; use only letters, digits, "_" or "-"`);
  }
  if (isLiveSlot(args.slot) && !args.allowLiveSlot) {
    fail(`refusing to run unattended calibration against live slot ${args.slot}; use a dedicated slot or pass --allow-live-slot`);
  }
  if (args.fresh && !args.allowFresh) {
    fail("--fresh is disabled by the unattended save-safety gate; use the seeded dedicated slot flow or pass --allow-fresh");
  }
}

function formatLocalSaveTimestamp(date = new Date()) {
  const pad = (n) => String(n).padStart(2, "0");
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function isValidSaveData(data) {
  if (!data || data.version !== "3.0" || !data.lastSaved) return false;
  const player = data["0"];
  if (!Array.isArray(player) || player.length < 14) return false;
  if (player[0] == null || player[0] === "") return false;
  if (player[3] == null || Number.isNaN(Number(player[3]))) return false;
  if (!Array.isArray(data["1"]) || data["1"].length < 28) return false;
  if (!Array.isArray(data["4"]) || data["4"].length < 2) return false;
  if (!Array.isArray(data["5"])) return false;
  if (!Array.isArray(data["7"]) || data["7"].length < 5) return false;
  if (!data.inventory || !data.collection || !data.infrastructure) return false;
  if (!data.tasks || !Array.isArray(data.tasks.tasks_to_do) || !data.tasks.tasks_finished || !data.tasks.task_chains_progress) return false;
  if (!data.pets || !Array.isArray(data.pets["宠物信息"]) || data.pets["宠物信息"].length < 5 || data.pets["宠物领养限制"] == null) return false;
  if (!data.shop || !Array.isArray(data.shop["商城已购买物品"]) || !Array.isArray(data.shop["商城购物车"])) return false;
  return true;
}

function tryReadValidSave(filePath) {
  try {
    const text = fs.readFileSync(filePath, "utf8");
    const data = JSON.parse(text);
    if (!isValidSaveData(data)) return null;
    return { filePath, data };
  } catch (_error) {
    return null;
  }
}

function saveJsonPath(root, slot) {
  return path.join(root, "saves", `${sanitizeSlotName(slot)}.json`);
}

function listValidSeedCandidates(root, targetSlot) {
  const savesDir = path.join(root, "saves");
  if (!fs.existsSync(savesDir)) return [];
  const targetName = `${sanitizeSlotName(targetSlot)}.json`;
  return fs.readdirSync(savesDir)
    .filter((name) => name.endsWith(".json") && !name.startsWith(".") && name !== targetName)
    .map((name) => tryReadValidSave(path.join(savesDir, name)))
    .filter(Boolean)
    .sort((a, b) => fs.statSync(b.filePath).mtimeMs - fs.statSync(a.filePath).mtimeMs);
}

function backupFile(src, backupDir, label) {
  if (!fs.existsSync(src)) return null;
  fs.mkdirSync(backupDir, { recursive: true });
  const base = path.basename(src);
  const dest = path.join(backupDir, `${label}-${base}`);
  fs.copyFileSync(src, dest);
  return dest;
}

function findSolFiles(root, slot) {
  const appData = process.env.APPDATA;
  if (!appData) return [];
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];
  const fileName = `${slot}.sol`;
  const rootNeedle = path.basename(root).toLowerCase();
  const results = [];
  const stack = [sharedRoot];
  while (stack.length > 0) {
    const dir = stack.pop();
    let entries = [];
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (_error) { continue; }
    for (const entry of entries) {
      const full = path.join(dir, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && entry.name === fileName) {
        const lower = full.toLowerCase();
        if (lower.includes(rootNeedle) && lower.includes("crazyflasher7mercenaryempire.swf")) {
          results.push(full);
        }
      }
    }
  }
  return results;
}

function fileFingerprint(root, filePath, slot, kind) {
  const bytes = fs.readFileSync(filePath);
  const stat = fs.statSync(filePath);
  const insideRoot = path.relative(root, filePath);
  const pathKey = crypto.createHash("sha256").update(path.resolve(filePath).toLowerCase(), "utf8").digest("hex").slice(0, 16);
  return {
    key: `${kind}:${slot}:${pathKey}`,
    kind,
    slot,
    path: insideRoot.startsWith("..") ? `${kind}/${path.basename(filePath)}` : toProjectRelative(root, filePath),
    sha256: `sha256:${crypto.createHash("sha256").update(bytes).digest("hex")}`,
    size: stat.size,
  };
}

function captureProtectedSaveSnapshot(root, targetSlot) {
  const savesDir = path.join(root, "saves");
  const slots = fs.existsSync(savesDir)
    ? fs.readdirSync(savesDir)
        .filter((name) => /^crazyflasher7_saves\d*\.json$/.test(name))
        .map((name) => path.basename(name, ".json"))
        .filter((slot) => slot !== targetSlot)
        .sort()
    : [];
  const files = [];
  slots.forEach((slot) => {
    const jsonPath = saveJsonPath(root, slot);
    if (fs.existsSync(jsonPath)) files.push(fileFingerprint(root, jsonPath, slot, "shadow_json"));
    findSolFiles(root, slot).sort().forEach((solPath) => {
      files.push(fileFingerprint(root, solPath, slot, "flash_sol"));
    });
  });
  files.sort((left, right) => left.key.localeCompare(right.key) || left.sha256.localeCompare(right.sha256));
  return {
    capturedAt: new Date().toISOString(),
    targetSlot,
    files,
    snapshotHash: sha256OfValue(files.map(({ key, sha256, size }) => ({ key, sha256, size }))),
  };
}

function compareProtectedSaveSnapshots(before, after) {
  const beforeMap = new Map(before.files.map((entry) => [entry.key, entry]));
  const afterMap = new Map(after.files.map((entry) => [entry.key, entry]));
  const keys = Array.from(new Set([...beforeMap.keys(), ...afterMap.keys()])).sort();
  return keys.flatMap((key) => {
    const left = beforeMap.get(key);
    const right = afterMap.get(key);
    if (!left) return [{ key, change: "added", afterSha256: right.sha256 }];
    if (!right) return [{ key, change: "removed", beforeSha256: left.sha256 }];
    if (left.sha256 !== right.sha256 || left.size !== right.size) {
      return [{ key, change: "modified", beforeSha256: left.sha256, afterSha256: right.sha256 }];
    }
    return [];
  });
}

function finalizeSaveProtection(report, root) {
  if (!report.saveProtection || !report.saveProtection.before) return;
  const after = captureProtectedSaveSnapshot(root, report.slot);
  const differences = compareProtectedSaveSnapshots(report.saveProtection.before, after);
  report.saveProtection.after = after;
  report.saveProtection.differences = differences;
  report.saveProtection.unchanged = differences.length === 0;
}

function prepareCalibrationSave(root, args, runDir) {
  const safeSlot = sanitizeSlotName(args.slot);
  const backupDir = path.join(runDir, "save-backups");
  const targetJson = saveJsonPath(root, safeSlot);
  fs.mkdirSync(path.dirname(targetJson), { recursive: true });

  const result = {
    slot: safeSlot,
    targetJson: toProjectRelative(root, targetJson),
    seedSource: null,
    seedRole: null,
    seedLevel: null,
    backups: [],
    solBackups: [],
    removedSolFiles: [],
    wroteSeed: false,
  };

  const existingTarget = tryReadValidSave(targetJson);
  const jsonBackup = backupFile(targetJson, backupDir, "target-json");
  if (jsonBackup) result.backups.push(toProjectRelative(root, jsonBackup));

  for (const solPath of findSolFiles(root, safeSlot)) {
    const solBackup = backupFile(solPath, backupDir, "target-sol");
    if (solBackup) result.solBackups.push(toProjectRelative(root, solBackup));
    fs.unlinkSync(solPath);
    result.removedSolFiles.push(solPath);
  }

  let seed = null;
  if (args.seedSlot) {
    const seedPath = saveJsonPath(root, args.seedSlot);
    seed = tryReadValidSave(seedPath);
    if (!seed) fail(`--seed-slot ${args.seedSlot} is missing or not a valid save shadow`);
  } else {
    const candidates = listValidSeedCandidates(root, safeSlot);
    seed = candidates[0] || existingTarget;
  }
  if (!seed) {
    fail("no valid save shadow is available to seed the dedicated calibration slot");
  }

  const clone = JSON.parse(JSON.stringify(seed.data));
  clone.lastSaved = formatLocalSaveTimestamp();
  fs.writeFileSync(targetJson, JSON.stringify(clone), "utf8");

  const player = clone["0"] || [];
  result.seedSource = toProjectRelative(root, seed.filePath);
  result.seedRole = player[0] || null;
  result.seedLevel = player[3] == null ? null : player[3];
  result.wroteSeed = true;
  return result;
}

function prepareManifest(root, args) {
  if (args.manifest && args.generatePilot) {
    fail("--manifest and --generate-pilot are mutually exclusive");
  }
  if (!args.manifest && !args.generatePilot) {
    fail("--manifest is required unless --generate-pilot is used");
  }

  const manifest = args.manifest
    ? normalizeManifest(readJsonFile(resolveInputPath(root, args.manifest)))
    : createPilotManifest({
        batchId: args.batchId,
        repeat: args.repeat,
        timeoutFrames: args.timeoutFrames,
        buildCommit: "unattended-runner",
      });

  const batchDir = path.join(root, "tmp", "arena-calibration", "batches", manifest.batchId);
  const manifestPath = path.join(batchDir, "case_manifest.json");
  writeJsonFile(manifestPath, manifest);
  return {
    manifest,
    manifestPath,
    manifestPathRel: toProjectRelative(root, manifestPath),
  };
}

function httpRequest(port, method, pathname, body, timeoutMs = 5000) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined || body === null ? "" : JSON.stringify(body);
    let authorizationHeaders;
    try {
      authorizationHeaders = LegacyHttpClient.authorizationHeadersFor(
        activeLegacyHttpContext,
        pathname
      );
    } catch (error) {
      reject(error);
      return;
    }
    const req = http.request(
      {
        hostname: "localhost",
        port,
        path: pathname,
        method,
        timeout: timeoutMs,
        headers: Object.assign({
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
        }, authorizationHeaders),
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const text = Buffer.concat(chunks).toString("utf8");
          resolve({ statusCode: res.statusCode, text });
        });
      }
    );
    req.on("timeout", () => {
      req.destroy(new Error(`HTTP ${method} ${pathname} timed out`));
    });
    req.on("error", reject);
    req.end(payload);
  });
}

async function testPort(port) {
  try {
    const resp = await httpRequest(port, "POST", "/testConnection", null, 1000);
    return resp.statusCode === 200;
  } catch (_error) {
    return false;
  }
}

async function discoverPort(root) {
  const portsFile = path.join(root, "launcher_ports.json");
  activeLegacyHttpContext = null;
  if (!fs.existsSync(portsFile)) return null;

  const ports = LegacyHttpClient.readExactLauncherPorts(root);
  if (!await testPort(ports.httpPort)) return null;
  activeLegacyHttpContext =
    LegacyHttpClient.readExactLauncherHttpContext(root);
  return activeLegacyHttpContext.httpPort;
}

function startLauncher(root, expectedIdentity) {
  const script = path.join(root, "automation", "start.ps1");
  const launchArgs = buildLauncherStartArguments(
    script,
    expectedIdentity,
    { enableLegacyHttpAutomation: true },
  );
  const result = childProcess.spawnSync(
    "powershell.exe",
    launchArgs,
    { cwd: root, encoding: "utf8" }
  );
  if (result.status !== 0) {
    process.stderr.write(result.stdout || "");
    process.stderr.write(result.stderr || "");
    fail(`automation/start.ps1 failed with exit code ${result.status}`);
  }
  process.stdout.write(result.stdout || "");
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForPort(root, timeoutMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const port = await discoverPort(root);
    if (port) return port;
    await sleep(1000);
  }
  fail(`launcher HTTP bus was not ready within ${timeoutMs}ms`);
}

function parseJsonResponse(resp, context) {
  try {
    return JSON.parse(resp.text);
  } catch (_error) {
    fail(`${context} returned non-JSON HTTP ${resp.statusCode}: ${resp.text.slice(0, 200)}`);
  }
}

async function readLogSnapshot(port) {
  const response = await httpRequest(
    port,
    "GET",
    "/logs?lines=" + LOG_TAIL_LIMIT,
    null,
    5000
  );
  const parsed = parseJsonResponse(response, "/logs");
  if (parsed.success !== true
      || !Number.isInteger(parsed.total)
      || !Array.isArray(parsed.lines)) {
    fail("/logs did not return a usable watermark: " + JSON.stringify(parsed));
  }
  return {
    total: parsed.total,
    lines: parsed.lines.map((line) => String(line)),
    capturedAt: new Date().toISOString(),
  };
}

async function callTask(port, message, timeoutMs = 20000) {
  const resp = await httpRequest(port, "POST", "/task", message, timeoutMs);
  const json = parseJsonResponse(resp, `/task ${message.task || ""}`);
  if (resp.statusCode >= 400 && json.ok !== true && json.success !== true) {
    return json;
  }
  return json;
}

async function agent(port, action, fields = {}) {
  return callTask(port, { task: "agent_control", action, ...fields });
}

async function arena(port, action, fields = {}) {
  return callTask(port, { task: "arena_calibration", action, ...fields });
}

async function consoleCommand(port, command, timeoutMs = 10000) {
  const resp = await httpRequest(port, "POST", "/console", { command }, timeoutMs);
  return parseJsonResponse(resp, `/console ${command}`);
}

async function waitForAgentControl(port, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    last = await agent(port, "status");
    if (last && last.success !== false && last.error !== "task 'agent_control' is not httpCallable") {
      return last;
    }
    await sleep(pollMs);
  }
  fail(`agent_control was not available within ${timeoutMs}ms; last=${JSON.stringify(last)}`);
}

function canReuseEntryProof(status, slot, proof) {
  if (!status || status.readyForArenaCalibration !== true || !proof) return false;
  const attemptId = statusAttemptForSlot(status, slot);
  return proof.slot === slot
    && proof.attemptId === attemptId
    && proof.enterRequestCount === 1
    && proof.gameEnteredObserved === true
    && proof.gameEnteredAttemptId === attemptId
    && Number.isInteger(proof.titleFrameLine);
}

async function ensureGameReady(port, args, priorEntryProof) {
  let status = await waitForAgentControl(port, args.readyTimeoutMs, args.pollMs);
  if (status.readyForArenaCalibration) {
    if (!canReuseEntryProof(status, args.slot, priorEntryProof)) {
      fail("refusing to reuse a pre-existing ready game without this run's fresh handoff/attempt proof");
    }
    assertRuntimeReadyStatus(status, args.slot, priorEntryProof.attemptId);
    return { status, entryProof: priorEntryProof };
  }

  const startLogWatermark = logWatermark(await readLogSnapshot(port));

  const start = await agent(port, "start", {
    slot: args.slot,
    fresh: args.fresh,
    requireFlashReveal: true,
  });
  if (start.success === false) {
    fail(`agent_control start failed: ${start.error || ""} ${start.message || ""}`);
  }

  const deadline = Date.now() + args.readyTimeoutMs;
  const state = {
    expectedSlot: args.slot,
    expectedAttemptId: statusAttemptForSlot(start, args.slot),
    handoffEvidence: null,
    titleFrameEvidence: null,
    revealWatchdogEvidence: null,
    enterRequested: false,
    enterRequestCount: 0,
  };
  let lastLogSnapshot = null;
  while (Date.now() <= deadline) {
    status = await agent(port, "status");
    const candidateAttempt = statusAttemptForSlot(status, args.slot);
    if (candidateAttempt) {
      if (state.expectedAttemptId && state.expectedAttemptId !== candidateAttempt) {
        fail(`launcher attempt changed while waiting for arena readiness: expected=${state.expectedAttemptId} actual=${candidateAttempt}`);
      }
      state.expectedAttemptId = candidateAttempt;
    }

    lastLogSnapshot = await readLogSnapshot(port);
    const freshRecords = freshLogRecords(startLogWatermark, lastLogSnapshot);
    if (!state.handoffEvidence && state.expectedAttemptId) {
      state.handoffEvidence = findFreshHandoff(freshRecords);
    }
    if (!state.titleFrameEvidence && state.expectedAttemptId) {
      state.titleFrameEvidence = findFreshTitleFrame(freshRecords);
    }
    if (!state.revealWatchdogEvidence) {
      state.revealWatchdogEvidence = findFreshRevealWatchdog(freshRecords);
    }
    if (state.revealWatchdogEvidence && !state.titleFrameEvidence) {
      fail("title_frame_not_observed: Flash reveal watchdog fired before the real title-frame receipt");
    }

    if (status.readyForArenaCalibration) {
      if (!state.handoffEvidence || !state.titleFrameEvidence
          || state.enterRequestCount !== 1 || !state.expectedAttemptId) {
        fail("arena became ready without a fresh handoff, real title-frame receipt, exact attempt, and exactly one agent entry request");
      }
      assertRuntimeReadyStatus(status, args.slot, state.expectedAttemptId);
      return {
        status,
        entryProof: {
          slot: args.slot,
          attemptId: state.expectedAttemptId,
          handoffLine: state.handoffEvidence.lineNumber,
          titleFrameLine: state.titleFrameEvidence.lineNumber,
          enterRequestCount: state.enterRequestCount,
          gameEnteredObserved: status.gameEnteredObserved === true,
          gameEnteredAttemptId: status.gameEnteredAttemptId,
        },
      };
    }

    // 只有 fresh 主 SWF handoff、精确 dedicated slot/attempt、安全 snapshot、socket
    // 都已实收后，才允许唯一一次 helper 调用。
    if (shouldRequestAgentEnter(status, state)) {
      state.enterRequested = true;
      state.enterRequestCount += 1;
      const entered = await consoleCommand(port, AGENT_ENTER_COMMAND);
      if (entered && entered.success === false) {
        fail(`agent enter save command failed: ${JSON.stringify(entered)}`);
      }
    }
    if (status.launchState === "Error") {
      fail(`launcher entered Error state while waiting for game ready: ${JSON.stringify(status)}`);
    }
    await sleep(args.pollMs);
  }
  if (!state.titleFrameEvidence) {
    fail(`title_frame_not_observed: real bootstrap_reveal_ready receipt missing; last=${JSON.stringify({ state, logTotal: lastLogSnapshot && lastLogSnapshot.total })}`);
  }
  fail(`game did not become ready for arena calibration within ${args.readyTimeoutMs}ms; last=${JSON.stringify({ status, state, logTotal: lastLogSnapshot && lastLogSnapshot.total })}`);
}

async function shutdownExistingLauncherForGate(root, gates) {
  if (!requiresLauncherShutdown(gates)) return null;
  return shutdownLauncher(root);
}

async function shutdownLauncher(root) {
  let expectedPid = null;
  try {
    expectedPid = Number(LegacyHttpClient.readExactLauncherPorts(root).pid) || null;
  } catch (_error) { }
  const port = await discoverPort(root);
  if (!port) return null;

  let response = null;
  try {
    response = await agent(port, "shutdown");
  } catch (_error) {
    try {
      const raw = await httpRequest(port, "POST", "/shutdown", null, 5000);
      response = parseJsonResponse(raw, "/shutdown");
    } catch (error) {
      response = { success: false, error: "shutdown_failed", message: error.message };
    }
  }

  const deadline = Date.now() + 15000;
  while (Date.now() <= deadline) {
    let stillRunning = null;
    try {
      stillRunning = await discoverPort(root);
    } catch (error) {
      if (expectedPid && !isProcessRunning(expectedPid)) {
        activeLegacyHttpContext = null;
        break;
      }
      throw error;
    }
    if (!stillRunning) break;
    await sleep(500);
  }
  return { port, pid: expectedPid, stopped: expectedPid ? !isProcessRunning(expectedPid) : null, response };
}

function isProcessRunning(pid) {
  if (!Number.isInteger(Number(pid)) || Number(pid) <= 0) return false;
  try {
    process.kill(Number(pid), 0);
    return true;
  } catch (_error) {
    return false;
  }
}

async function ensureLauncherReady(root, args, expectedIdentity, onIdentityObserved, priorEntryProof) {
  let port = await discoverPort(root);
  if (!port && args.startLauncher) {
    startLauncher(root, expectedIdentity);
    port = await waitForPort(root, args.readyTimeoutMs);
  }
  if (!port) {
    throw new Error("launcher is not running; remove --no-start-launcher or start it first");
  }
  const runtimeIdentity = verifyRuntimeIdentity(
    root,
    port,
    expectedIdentity,
    onIdentityObserved
  );
  const gameReady = await ensureGameReady(port, args, priorEntryProof);
  return {
    port,
    status: gameReady.status,
    entryProof: gameReady.entryProof,
    runtimeIdentity,
  };
}

function requiresLauncherShutdown(gates) {
  return gates.some((gate) =>
    gate === "launcher-build" ||
    gate === "launcher-tests" ||
    gate === "launcher" ||
    gate === "as2-publish" ||
    gate === "as2-test"
  );
}

function expandBuildGates(gates) {
  const expanded = [];
  (gates || []).forEach((gate) => {
    if (!gate || gate === "none") return;
    if (gate === "launcher") {
      expanded.push("launcher-build", "launcher-tests");
    } else {
      expanded.push(gate);
    }
  });
  return expanded;
}

function assertRuntimeBuildGateSeparated(gates) {
  if ((gates || []).includes("launcher-build")) {
    fail(
      "launcher-build only produces an unselected runtime candidate; build it separately, "
        + "then pass its exact path with --candidate-root"
    );
  }
}

function commandForGate(root, gate) {
  if (gate === "arena-tools") {
    return {
      gate,
      command: process.execPath,
      args: [path.join(root, "tools", "arena-calibration", "run-checks.js")],
    };
  }
  if (gate === "launcher-build") {
    return {
      gate,
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(root, "launcher", "build.ps1")],
    };
  }
  if (gate === "launcher-tests") {
    return {
      gate,
      command: "powershell.exe",
      args: ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path.join(root, "launcher", "tests", "run_tests.ps1")],
    };
  }
  if (gate === "as2-publish") {
    return {
      gate,
      command: "powershell.exe",
      args: [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        path.join(root, "scripts", "compile_test.ps1"),
        "-Target",
        "publish",
        "-VerifySwf",
        path.join(root, "scripts", "asLoader.swf"),
      ],
    };
  }
  if (gate === "as2-test") {
    return {
      gate,
      command: "powershell.exe",
      args: [
        "-NoProfile",
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        path.join(root, "scripts", "compile_test.ps1"),
        "-Target",
        "test",
      ],
    };
  }
  fail(`unsupported build gate: ${gate}`);
}

function runBuildGates(root, gates) {
  return gates.map((gate) => {
    const spec = commandForGate(root, gate);
    const startedAt = new Date().toISOString();
    const result = childProcess.spawnSync(spec.command, spec.args, {
      cwd: root,
      encoding: "utf8",
      timeout: gate.startsWith("as2-") ? 300000 : 180000,
    });
    const finishedAt = new Date().toISOString();
    return {
      gate,
      command: formatCommand(spec.command, spec.args),
      startedAt,
      finishedAt,
      exitCode: result.status,
      signal: result.signal || null,
      ok: result.status === 0,
      stdoutTail: tailText(result.stdout || ""),
      stderrTail: tailText(result.stderr || ""),
      error: result.error ? result.error.message : null,
    };
  });
}

function formatCommand(command, args) {
  return [command, ...(args || [])].map((part) => {
    const text = String(part);
    return /\s/.test(text) ? `"${text.replace(/"/g, '\\"')}"` : text;
  }).join(" ");
}

function tailText(text, limit = 6000) {
  if (!text || text.length <= limit) return text;
  return text.slice(text.length - limit);
}

async function runBatch(port, manifestPathRel, args) {
  let start = null;
  let status = null;
  if (args.cancelFile && fs.existsSync(args.cancelFile)) {
    const error = new Error(`external cancel signal is already present: ${toProjectRelative(projectRoot(), args.cancelFile)}`);
    error.code = "gate_f_yield_requested";
    error.phase = "external_cancel";
    error.controlledYield = true;
    throw error;
  }
  try {
    start = await arena(port, "startBatch", { manifestPath: manifestPathRel });
  } catch (error) {
    error.phase = "startBatch";
    error.start = start;
    throw error;
  }
  if (start.success === false && start.error !== "batch_already_running") {
    const error = new Error(`arena_calibration startBatch failed: ${start.error || ""} ${start.message || ""}`);
    error.phase = "startBatch";
    error.start = start;
    throw error;
  }

  const deadline = args.batchTimeoutMs > 0 ? Date.now() + args.batchTimeoutMs : Number.POSITIVE_INFINITY;
  try {
    status = await arena(port, "status");
    while (!TERMINAL_STATES.has(status.state)) {
      if (args.cancelFile && fs.existsSync(args.cancelFile)) {
        let abortStatus = null;
        try {
          abortStatus = await arena(port, "abort", { batchId: status.batchId });
          if (abortStatus && abortStatus.state) status = abortStatus;
        } catch (_error) { }
        const error = new Error(`external cancel signal requested bounded batch yield: ${toProjectRelative(projectRoot(), args.cancelFile)}`);
        error.code = "gate_f_yield_requested";
        error.phase = "external_cancel";
        error.controlledYield = true;
        error.start = start;
        error.lastStatus = abortStatus || status;
        throw error;
      }
      if (Date.now() > deadline) {
        let abortStatus = null;
        try {
          abortStatus = await arena(port, "abort", { batchId: status.batchId });
          if (abortStatus && abortStatus.state) status = abortStatus;
        } catch (_error) { }
        const error = new Error(`batch timed out after ${args.batchTimeoutMs}ms and abort was requested`);
        error.phase = "batch_timeout";
        error.start = start;
        error.lastStatus = abortStatus || status;
        throw error;
      }
      await sleep(args.pollMs);
      status = await arena(port, "status");
    }
  } catch (error) {
    if (!error.phase) error.phase = "poll";
    error.start = start;
    error.lastStatus = status;
    throw error;
  }
  return { start, status };
}

function expectedResultPathRel(manifest) {
  const planner = manifest && manifest.planner ? manifest.planner : {};
  const logDir = planner.name === "arena-custom-match" ? "arena-custom" : "arena-calibration";
  return `logs/${logDir}/${manifest.batchId}-results.jsonl`;
}

function resultPathFromBatchOutcome(manifest, batch, error) {
  return (
    (batch && batch.status && batch.status.resultPath) ||
    (batch && batch.start && batch.start.resultPath) ||
    (error && error.lastStatus && error.lastStatus.resultPath) ||
    (error && error.start && error.start.resultPath) ||
    expectedResultPathRel(manifest)
  );
}

function validateResultRowsAgainstManifest(rows, manifest, label) {
  if (!manifest || !Array.isArray(manifest.cases)) fail(`${label}: manifest is unavailable`);
  const cases = new Map(manifest.cases.map((testCase) => [testCase.caseId, testCase]));
  const seenRunIds = new Set();
  const seenRepeats = new Set();
  rows.forEach((row, index) => {
    assertSchemaInstance("arena-calibration.result.v1", row, `${label} row ${index + 1}`);
    if (row.batchId !== manifest.batchId || row.manifestHash !== manifest.manifestHash) {
      fail(`${label} row ${index + 1}: batch/manifest binding mismatch`);
    }
    const testCase = cases.get(row.caseId);
    if (!testCase || row.caseHash !== testCase.caseHash) {
      fail(`${label} row ${index + 1}: case binding mismatch for ${row.caseId}`);
    }
    const expectedRepeats = testCase.repeat || manifest.repeat;
    if (row.repeatIndex > expectedRepeats) {
      fail(`${label} row ${index + 1}: repeatIndex exceeds ${expectedRepeats}`);
    }
    if (seenRunIds.has(row.runId)) fail(`${label}: duplicate runId ${row.runId}`);
    seenRunIds.add(row.runId);
    const repeatKey = `${row.caseId}|${row.repeatIndex}`;
    if (seenRepeats.has(repeatKey)) fail(`${label}: duplicate case repeat ${repeatKey}`);
    seenRepeats.add(repeatKey);
  });
  return true;
}

function analyzeResult(root, resultPathRel, outputs, manifest) {
  if (!resultPathRel) {
    fail("arena_calibration did not report resultPath");
  }
  const resultPath = resolveInputPath(root, resultPathRel);
  if (!fs.existsSync(resultPath)) {
    fail(`result JSONL not found: ${resultPath}`);
  }

  const rows = readJsonLines(resultPath);
  validateResultRowsAgainstManifest(rows, manifest, resultPathRel);
  const summary = analyzeRows(rows, { resultPath });
  if (outputs.summary) writeJsonFile(outputs.summary, summary);
  if (outputs.summaryMd) {
    fs.mkdirSync(path.dirname(outputs.summaryMd), { recursive: true });
    fs.writeFileSync(outputs.summaryMd, formatSummaryMarkdown(summary), "utf8");
  }
  return { resultPath, rows, summary };
}

function analyzeAttemptResult(root, resultPathRel, summaryPath, summaryMdPath, manifest) {
  const result = {
    resultPath: resultPathRel || null,
    resultPathAbs: null,
    rows: [],
    summary: null,
    summaryPath: summaryPath ? toProjectRelative(root, summaryPath) : null,
    summaryMdPath: summaryMdPath ? toProjectRelative(root, summaryMdPath) : null,
    error: null,
  };
  if (!resultPathRel) {
    result.error = "missing resultPath";
    return result;
  }
  const resultPath = resolveInputPath(root, resultPathRel);
  result.resultPathAbs = resultPath;
  if (!fs.existsSync(resultPath)) {
    result.error = `result JSONL not found: ${resultPath}`;
    return result;
  }
  try {
    result.rows = readJsonLines(resultPath);
    if (result.rows.length > 0) {
      validateResultRowsAgainstManifest(result.rows, manifest, resultPathRel);
      result.summary = analyzeRows(result.rows, { resultPath });
      if (summaryPath) writeJsonFile(summaryPath, result.summary);
      if (summaryMdPath) {
        fs.mkdirSync(path.dirname(summaryMdPath), { recursive: true });
        fs.writeFileSync(summaryMdPath, formatSummaryMarkdown(result.summary), "utf8");
      }
    }
  } catch (error) {
    result.error = error.message;
  }
  return result;
}

function describeAttemptError(error) {
  if (error && error.message) return error.message;
  if (error && error.phase === "external_cancel") return "external cancel requested a bounded yield";
  if (error && error.phase === "poll") return "arena_calibration status polling failed";
  if (error && error.phase === "batch_timeout") return "batch timeout";
  if (error && error.phase === "startBatch") return "arena_calibration startBatch failed";
  return "attempt failed";
}

async function waitForResultFile(root, resultPathRel, timeoutMs, pollMs) {
  if (!resultPathRel || timeoutMs <= 0) return false;
  const resultPath = resolveInputPath(root, resultPathRel);
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    try {
      if (fs.existsSync(resultPath) && fs.statSync(resultPath).size > 0) return true;
    } catch (_error) {
      // Keep polling until the writer has fully released the file.
    }
    await sleep(Math.max(100, pollMs || 250));
  }
  return false;
}

function attemptOutputPaths(root, outputs, attemptIndex, batchId) {
  const prefix = `attempt-${attemptIndex}-${batchId}`;
  return {
    summary: path.join(outputs.runDir, `${prefix}-summary.json`),
    summaryMd: path.join(outputs.runDir, `${prefix}-summary.md`),
  };
}

function buildFailureList(report) {
  const failures = [];
  if (report.saveProtection && report.saveProtection.unchanged === false) {
    failures.push({
      type: "protected_save_changed",
      message: "one or more protected player save files changed during calibration",
      differences: report.saveProtection.differences,
    });
  }
  (report.buildGates || []).forEach((gate) => {
    if (!gate.ok) {
      failures.push({
        type: "build_gate",
        gate: gate.gate,
        exitCode: gate.exitCode,
        signal: gate.signal,
        message: gate.error || `build gate failed: ${gate.gate}`,
      });
    }
  });
  (report.attempts || []).forEach((attempt) => {
    if (attempt.error) {
      failures.push({
        type: "attempt_error",
        attempt: attempt.index,
        batchId: attempt.batchId,
        phase: attempt.error.phase || null,
        message: attempt.error.message,
      });
    }
    if (attempt.analysisError) {
      failures.push({
        type: "analysis_error",
        attempt: attempt.index,
        batchId: attempt.batchId,
        message: attempt.analysisError,
      });
    }
    if (attempt.rerunManifestPath && !attempt.autoRecovered) {
      failures.push({
        type: "needs_rerun",
        attempt: attempt.index,
        batchId: attempt.batchId,
        rerunManifestPath: attempt.rerunManifestPath,
      });
    }
  });
  return failures;
}

function copyFinalSummary(outputs, analyzed) {
  if (!analyzed || !analyzed.summary) return;
  if (outputs.summary) writeJsonFile(outputs.summary, analyzed.summary);
  if (outputs.summaryMd) {
    fs.mkdirSync(path.dirname(outputs.summaryMd), { recursive: true });
    fs.writeFileSync(outputs.summaryMd, formatSummaryMarkdown(analyzed.summary), "utf8");
  }
}

function countExpectedRuns(manifest) {
  return manifest.cases.reduce((sum, testCase) => sum + (testCase.repeat || manifest.repeat || 0), 0);
}

function buildRerunManifest(sourceManifest, rows, reason) {
  const doneStatuses = new Set(["finished", "timeout"]);
  const doneByCase = new Map();
  rows.forEach((row) => {
    if (!doneStatuses.has(row.status)) return;
    const key = `${row.caseId}|${row.caseHash}`;
    doneByCase.set(key, (doneByCase.get(key) || 0) + 1);
  });

  const rerunCases = [];
  sourceManifest.cases.forEach((testCase) => {
    const expected = testCase.repeat || sourceManifest.repeat;
    const key = `${testCase.caseId}|${testCase.caseHash}`;
    const done = doneByCase.get(key) || 0;
    const missing = Math.max(0, expected - done);
    if (missing <= 0) return;
    const rerunCase = {
      caseId: testCase.caseId,
      blueRoster: testCase.blueRoster,
      redRoster: testCase.redRoster,
      repeat: missing,
      timeoutFrames: testCase.timeoutFrames,
      blueFormation: testCase.blueFormation,
      redFormation: testCase.redFormation,
      formationSpacing: testCase.formationSpacing,
      tags: Array.from(new Set([...(testCase.tags || []), "rerun"])),
      plannerReason: `rerun ${missing}/${expected}: ${reason}`,
    };
    if (testCase.spawnDistance !== undefined) {
      rerunCase.spawnDistance = testCase.spawnDistance;
    }
    if (Object.prototype.hasOwnProperty.call(testCase, "authorityContext")) {
      rerunCase.authorityContext = testCase.authorityContext;
    }
    rerunCases.push(rerunCase);
  });

  if (rerunCases.length === 0) return null;

  const suffix = `rerun-${timestampId()}`;
  const batchId = `${sourceManifest.batchId.slice(0, Math.max(1, 63 - suffix.length))}-${suffix}`;
  return normalizeManifest({
    schema: "arena-calibration.case-manifest.v1",
    batchId,
    createdAt: new Date().toISOString(),
    buildCommit: sourceManifest.buildCommit || "unattended-rerun",
    planner: {
      name: "unattended-rerun",
      version: 1,
      sourceBatchId: sourceManifest.batchId,
      sourceManifestHash: sourceManifest.manifestHash,
      reason,
    },
    arenaMode: "calibration",
    repeat: 1,
    timeoutFrames: sourceManifest.timeoutFrames,
    blueBench: sourceManifest.blueBench || null,
    cases: rerunCases,
  });
}

function writeRerunManifest(root, sourceManifest, rows, reason, requestedPath) {
  const manifest = buildRerunManifest(sourceManifest, rows, reason);
  if (!manifest) return null;
  const manifestPath = requestedPath
    ? resolveInputPath(root, requestedPath)
    : path.join(root, "tmp", "arena-calibration", "batches", manifest.batchId, "case_manifest.json");
  writeJsonFile(manifestPath, manifest);
  return {
    manifest,
    manifestPath,
    manifestPathRel: toProjectRelative(root, manifestPath),
  };
}

function writeReport(report, reportPath, reportMdPath) {
  if (reportPath) writeJsonFile(reportPath, report);
  if (reportMdPath) {
    fs.mkdirSync(path.dirname(reportMdPath), { recursive: true });
    fs.writeFileSync(reportMdPath, formatReportMarkdown(report), "utf8");
  }
}

function formatReportMarkdown(report) {
  const lines = [
    "# Unattended Arena Calibration Run",
    "",
    `- status: ${report.status}`,
    `- batchId: \`${report.batchId || ""}\``,
    `- slot: \`${report.slot || ""}\``,
    `- seedSource: \`${report.savePreflight && report.savePreflight.seedSource ? report.savePreflight.seedSource : ""}\``,
    `- manifest: \`${report.manifestPath || ""}\``,
    `- resultPath: \`${report.resultPath || ""}\``,
    `- summaryPath: \`${report.summaryPath || ""}\``,
    `- recoveryAttemptsUsed: ${report.recoveryAttemptsUsed || 0}/${report.maxRecoveryAttempts || 0}`,
    `- startedAt: ${report.startedAt}`,
    `- completedAt: ${report.completedAt || ""}`,
    "",
    "## Runtime Binary Identity",
    "",
    `- verified: ${Boolean(report.runtimeIdentity && report.runtimeIdentity.verified)}`,
    `- runtimeMode: \`${report.runtimeIdentity && report.runtimeIdentity.runtimeMode || "not observed"}\``,
    `- processPath: \`${report.runtimeIdentity && report.runtimeIdentity.processPath || "not observed"}\``,
    `- coreSha256: \`${report.runtimeIdentity && report.runtimeIdentity.coreSha256 || "not observed"}\``,
    `- buildIdentity: \`${report.runtimeIdentity && report.runtimeIdentity.buildIdentity || "not observed"}\``,
    `- payloadClosure: \`${report.runtimeIdentity && report.runtimeIdentity.payloadClosure || "not observed"}\``,
    `- protectedSaveUnchanged: ${report.saveProtection && report.saveProtection.unchanged !== null ? report.saveProtection.unchanged : "not checked"}`,
    `- protectedSaveBefore: \`${report.saveProtection && report.saveProtection.before ? report.saveProtection.before.snapshotHash : "not observed"}\``,
    `- protectedSaveAfter: \`${report.saveProtection && report.saveProtection.after ? report.saveProtection.after.snapshotHash : "not observed"}\``,
    "",
    "## Attempts",
    "",
    "| # | status | batchId | rows | resultPath | rerun |",
    "|---|---|---|---:|---|---|",
    ...((report.attempts || []).map((attempt) => [
      `| ${attempt.index}`,
      attempt.status || "",
      `\`${attempt.batchId || ""}\``,
      `${attempt.resultRows || 0}/${attempt.expectedRows || 0}`,
      `\`${attempt.resultPath || ""}\``,
      attempt.rerunManifestPath
        ? `\`${attempt.rerunManifestPath}\`${attempt.autoRecovered ? " (auto)" : ""}`
        : "",
    ].join(" | ") + " |")),
    "",
    "## Failures",
    "",
    "```json",
    JSON.stringify(report.failures || [], null, 2),
    "```",
    "",
    "## Final Status",
    "",
    "```json",
    JSON.stringify(report.finalArenaStatus || report.error || {}, null, 2),
    "```",
    "",
  ];
  if (report.suggestions && report.suggestions.length > 0) {
    lines.push("## Suggestions", "");
    report.suggestions.forEach((item) => lines.push(`- ${item}`));
    lines.push("");
  }
  return lines.join("\n");
}

function defaultOutputPaths(root, batchId, args) {
  const runDir = path.join(root, "tmp", "arena-calibration", "unattended", `${timestampId()}-${batchId}`);
  return {
    runDir,
    summary: args.summary ? resolveInputPath(root, args.summary) : path.join(runDir, "summary.json"),
    summaryMd: args.summaryMd ? resolveInputPath(root, args.summaryMd) : path.join(runDir, "summary.md"),
    report: args.report ? resolveInputPath(root, args.report) : path.join(runDir, "run-report.json"),
    reportMd: args.reportMd ? resolveInputPath(root, args.reportMd) : path.join(runDir, "run-report.md"),
    rerunManifest: args.rerunManifest ? resolveInputPath(root, args.rerunManifest) : null,
  };
}

function runCheck() {
  const agentEntryContract = checkAgentEntryContract();
  const candidateArgs = parseArgs(["--candidate-root", "tmp/runtime-candidates/v2/check"]);
  if (candidateArgs.candidateRoot !== "tmp/runtime-candidates/v2/check") {
    throw new Error("--candidate-root parsing failed");
  }
  const cancelArgs = parseArgs(["--cancel-file", "tmp/arena-calibration/gate-f/check/revoke.signal"]);
  const cancelPath = resolveOwnedCancelFile(projectRoot(), cancelArgs.cancelFile);
  if (!cancelPath.endsWith(path.join("gate-f", "check", "revoke.signal"))) {
    throw new Error("--cancel-file parsing failed");
  }
  let unsafeCancelRejected = false;
  try {
    resolveOwnedCancelFile(projectRoot(), "logs/revoke.signal");
  } catch (_error) {
    unsafeCancelRejected = true;
  }
  if (!unsafeCancelRejected) throw new Error("unsafe --cancel-file escaped its owned root");
  checkRuntimeIdentityContract();
  if (!isProcessRunning(process.pid) || isProcessRunning(2147483647)) {
    throw new Error("process liveness contract failed");
  }
  const manifest = createPilotManifest({ batchId: "unattended-check", repeat: 1, timeoutFrames: 1 });
  const rerunBase = createPilotManifest({
    batchId: "unattended-rerun-check",
    repeat: 2,
    timeoutFrames: 1,
    blueFormation: "wedge",
    redFormation: "shield",
    formationSpacing: 64,
  });
  const rerunInput = JSON.parse(JSON.stringify(rerunBase));
  delete rerunInput.manifestHash;
  rerunInput.cases.forEach((testCase) => {
    delete testCase.caseHash;
  });
  rerunInput.cases[0].blueRoster[0].parameters = { 手枪: "P90战术版" };
  rerunInput.cases[0].authorityContext = { economyMode: "observe_only" };
  const rerunSource = normalizeManifest(rerunInput);
  const rerunCase = rerunSource.cases[0];
  const rerun = buildRerunManifest(
    rerunSource,
    [
      normalizeResultRow({
        schema: "arena-calibration.result.v1",
        batchId: rerunSource.batchId,
        manifestHash: rerunSource.manifestHash,
        caseId: rerunCase.caseId,
        caseHash: rerunCase.caseHash,
        runId: `${rerunCase.caseId}-r1`,
        repeatIndex: 1,
        status: "finished",
        winner: "blue",
      }),
    ],
    "check"
  );
  if (!rerun || rerun.cases.length !== 1 || rerun.cases[0].repeat !== 1) {
    throw new Error("rerun manifest check failed");
  }
  if (rerun.cases[0].blueRoster[0].parameters.手枪 !== "P90战术版"
      || rerun.cases[0].blueFormation !== "wedge"
      || rerun.cases[0].redFormation !== "shield"
      || rerun.cases[0].formationSpacing !== 64
      || rerun.cases[0].authorityContext.economyMode !== "observe_only") {
    throw new Error("rerun manifest did not preserve parameters, authority, and formation semantics");
  }
  const manifestCase = manifest.cases[0];
  const canonicalRow = normalizeResultRow({
    schema: "arena-calibration.result.v1",
    batchId: manifest.batchId,
    manifestHash: manifest.manifestHash,
    caseId: manifestCase.caseId,
    caseHash: manifestCase.caseHash,
    runId: `${manifestCase.caseId}-r001`,
    repeatIndex: 1,
    status: "finished",
    winner: "blue",
    authorityContext: { economyMode: "observe_only" },
    spawnedUnits: [{ side: "blue", unit: "兵种45", from: "兵种44", name: "derived-1", frame: 12 }],
    blueUnitResults: [{
      sourceId: "fixture-blue-1", petId: -1, identifier: "", resolvedType: "兵种44",
      level: 30, strategicPromotions: [], strategicPromotionsValid: true,
      startMaxHp: 100, remainHp: 50, hpPermille: 500, alive: true,
    }],
    redUnitResults: [],
  });
  validateResultRowsAgainstManifest([canonicalRow], manifest, "canonical result fixture");
  const invalidCanonicalRow = JSON.parse(JSON.stringify(canonicalRow));
  invalidCanonicalRow.unclosedProductionField = true;
  let invalidCanonicalRejected = false;
  try {
    validateResultRowsAgainstManifest([invalidCanonicalRow], manifest, "invalid result fixture");
  } catch (_error) {
    invalidCanonicalRejected = true;
  }
  if (!invalidCanonicalRejected) throw new Error("raw result schema did not reject an unclosed field");
  if (expandBuildGates(["none", "launcher", "arena-tools"]).join(",") !== "launcher-build,launcher-tests,arena-tools") {
    throw new Error("build gate expansion check failed");
  }
  let buildGateRejected = false;
  try {
    assertRuntimeBuildGateSeparated(["launcher-build"]);
  } catch (_error) {
    buildGateRejected = true;
  }
  if (!buildGateRejected) throw new Error("embedded launcher-build gate was not rejected");
  const beforeReveal = {
    launchState: "Ready",
    revealPerformed: false,
    socketConnected: true,
    runtimeReadyBlockedBy: ["flash_not_revealed", "runtime_save_not_loaded", "game_enter_not_observed"],
    save: {
      decision: "snapshot",
      kind: "Snapshot",
      slot: DEFAULT_AGENT_SLOT,
      attemptId: "attempt-check",
    },
  };
  const afterReveal = {
    launchState: "Ready",
    revealPerformed: true,
    socketConnected: true,
    runtimeReadyBlockedBy: ["runtime_save_not_loaded", "game_enter_not_observed"],
    save: beforeReveal.save,
  };
  const enterState = {
    expectedSlot: DEFAULT_AGENT_SLOT,
    expectedAttemptId: "attempt-check",
    handoffEvidence: null,
    titleFrameEvidence: null,
    enterRequested: false,
  };
  if (shouldRequestAgentEnter(beforeReveal, enterState)) {
    throw new Error("agent enter must not consume save before Flash reveal");
  }
  if (shouldRequestAgentEnter(afterReveal, enterState)) {
    throw new Error("agent enter must not run before a fresh handoff");
  }
  enterState.handoffEvidence = { lineNumber: 7, line: "[BootstrapAS] event=handoff" };
  if (shouldRequestAgentEnter(afterReveal, enterState)) {
    throw new Error("agent enter must not run before the real title-frame receipt");
  }
  enterState.titleFrameEvidence = {
    lineNumber: 8,
    line: "[LaunchFlow] bootstrap_reveal_ready: Flash reveal cleared",
  };
  if (!shouldRequestAgentEnter(afterReveal, enterState)) {
    throw new Error("agent enter must run after all fresh handoff/attempt gates pass");
  }
  enterState.enterRequested = true;
  if (shouldRequestAgentEnter(afterReveal, enterState)) {
    throw new Error("agent enter must remain single-shot after request");
  }
  const reusableStatus = {
    readyForArenaCalibration: true,
    save: { slot: DEFAULT_AGENT_SLOT, attemptId: "attempt-check" },
  };
  const reusableProof = {
    slot: DEFAULT_AGENT_SLOT,
    attemptId: "attempt-check",
    enterRequestCount: 1,
    gameEnteredObserved: true,
    gameEnteredAttemptId: "attempt-check",
    titleFrameLine: 8,
  };
  if (!canReuseEntryProof(reusableStatus, DEFAULT_AGENT_SLOT, reusableProof)
      || canReuseEntryProof(reusableStatus, DEFAULT_AGENT_SLOT, Object.assign({}, reusableProof, {
        attemptId: "attempt-stale",
      }))) {
    throw new Error("same-run arena entry proof reuse contract failed");
  }
  const report = {
    schema: "arena-calibration.unattended-run.v1",
    status: "check",
    batchId: manifest.batchId,
    slot: "check",
    manifestPath: "tmp/arena-calibration/batches/unattended-check/case_manifest.json",
    resultPath: null,
    summaryPath: null,
    startedAt: "2026-07-04T00:00:00.000Z",
    completedAt: "2026-07-04T00:00:00.000Z",
    attempts: [
      {
        index: 1,
        batchId: "unattended-check",
        status: "interrupted",
        expectedRows: 1,
        resultRows: 0,
        resultPath: "logs/arena-calibration/unattended-check-results.jsonl",
        rerunManifestPath: "tmp/arena-calibration/batches/unattended-check-rerun/case_manifest.json",
        autoRecovered: true,
        error: { message: "simulated check interruption", phase: "poll" },
      },
    ],
    failures: [],
    recoveryAttemptsUsed: 0,
    maxRecoveryAttempts: 1,
    suggestions: ["check mode does not launch the game"],
  };
  const checkIdentity = {
    runtimeMode: "isolated_candidate",
    processPath: path.join("C:\\", "check", "runtime", "CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    coreSha256: "C".repeat(64),
    buildIdentity: "A".repeat(64),
    payloadClosure: "B".repeat(64),
    pid: 123,
    httpPort: 1192,
  };
  report.runtimeIdentity = createRuntimeIdentityReport(checkIdentity);
  recordVerifiedRuntimeIdentity(report.runtimeIdentity, checkIdentity);
  report.failures = buildFailureList(report);
  const markdown = formatReportMarkdown(report);
  if (!markdown.includes("attempt_error") || !markdown.includes("(auto)")
      || !markdown.includes("isolated_candidate") || !markdown.includes("C".repeat(64))) {
    throw new Error("report markdown check failed");
  }
  console.log(JSON.stringify({
    ok: true,
    batchId: manifest.batchId,
    agentEntryContract: agentEntryContract.uiState,
    rawResultSchemaValidated: true,
    manifestCaseBindingsValidated: true,
    authorityRerunPreserved: true,
  }, null, 2));
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    printHelp();
    return;
  }
  if (args.check) {
    runCheck();
    return;
  }
  assertSafeSlotArgs(args);
  if (!Number.isInteger(args.maxRecoveryAttempts) || args.maxRecoveryAttempts < 0) {
    fail("--max-recovery-attempts must be a non-negative integer");
  }

  const root = projectRoot();
  args.cancelFile = resolveOwnedCancelFile(root, args.cancelFile);
  const startedAt = new Date().toISOString();
  const prepared = prepareManifest(root, args);
  const outputs = defaultOutputPaths(root, prepared.manifest.batchId, args);
  const report = {
    schema: "arena-calibration.unattended-run.v1",
    status: "running",
    batchId: prepared.manifest.batchId,
    manifestHash: prepared.manifest.manifestHash,
    slot: args.slot,
    fresh: args.fresh,
    manifestPath: prepared.manifestPathRel,
    cancelFile: args.cancelFile ? toProjectRelative(root, args.cancelFile) : null,
    resultPath: null,
    summaryPath: toProjectRelative(root, outputs.summary),
    summaryMdPath: toProjectRelative(root, outputs.summaryMd),
    rerunManifestPath: null,
    reportPath: toProjectRelative(root, outputs.report),
    startedAt,
    completedAt: null,
    buildGates: [],
    preGateShutdown: null,
    postRunShutdown: null,
    runtimeIdentity: createRuntimeIdentityReport(null),
    savePreflight: null,
    saveProtection: null,
    finalAgentStatus: null,
    finalArenaStatus: null,
    attempts: [],
    rows: 0,
    expectedRows: 0,
    summaryTotals: null,
    failures: [],
    recoveryAttemptsUsed: 0,
    maxRecoveryAttempts: args.maxRecoveryAttempts,
    error: null,
    suggestions: [],
  };

  let expectedIdentity = null;
  try {
    expectedIdentity = resolveExpectedRuntimeIdentity(root, args.candidateRoot);
    report.runtimeIdentity = createRuntimeIdentityReport(expectedIdentity);
    const gates = expandBuildGates(args.buildGates);
    assertRuntimeBuildGateSeparated(gates);
    if (!args.keepLauncherDuringGate) {
      report.preGateShutdown = await shutdownExistingLauncherForGate(root, gates);
    }
    report.buildGates = runBuildGates(root, gates);
    const failedGate = report.buildGates.find((gate) => !gate.ok);
    if (failedGate) {
      report.status = "build_failed";
      report.completedAt = new Date().toISOString();
      report.error = {
        message: `build gate failed: ${failedGate.gate}`,
        gate: failedGate.gate,
        exitCode: failedGate.exitCode,
        signal: failedGate.signal,
      };
      report.failures = buildFailureList(report);
      report.suggestions.push("Fix the failing build gate before launching the unattended calibration batch.");
      writeReport(report, outputs.report, outputs.reportMd);
      throw new Error(report.error.message);
    }

    const existingPort = await discoverPort(root);
    if (existingPort) {
      const actualIdentity = verifyRuntimeIdentity(
        root,
        existingPort,
        expectedIdentity,
        (observed) => recordObservedRuntimeIdentity(report.runtimeIdentity, observed)
      );
      recordVerifiedRuntimeIdentity(report.runtimeIdentity, actualIdentity);
    } else if (!args.startLauncher) {
      fail("launcher is not running; remove --no-start-launcher or start it first");
    }

    report.saveProtection = {
      before: captureProtectedSaveSnapshot(root, args.slot),
      after: null,
      unchanged: null,
      differences: [],
    };
    report.savePreflight = prepareCalibrationSave(root, args, outputs.runDir);
    writeReport(report, outputs.report, outputs.reportMd);

    let current = prepared;
    let entryProof = null;
    let finalAttempt = null;
    let finalAnalyzed = null;
    while (true) {
      const attemptIndex = report.attempts.length + 1;
      const attempt = {
        index: attemptIndex,
        batchId: current.manifest.batchId,
        manifestHash: current.manifest.manifestHash,
        manifestPath: current.manifestPathRel,
        expectedRows: countExpectedRuns(current.manifest),
        startedAt: new Date().toISOString(),
        completedAt: null,
        status: "running",
        httpPort: null,
        runtimeIdentity: null,
        agentStatus: null,
        agentEntryProof: null,
        batchStart: null,
        finalArenaStatus: null,
        resultPath: null,
        resultRows: 0,
        summaryPath: null,
        summaryMdPath: null,
        summaryTotals: null,
        analysisError: null,
        rerunManifestPath: null,
        rerunBatchId: null,
        autoRecovered: false,
        error: null,
      };

      let resultPathRel = null;
      try {
        attempt.runtimeIdentity = createRuntimeIdentityReport(expectedIdentity);
        const ready = await ensureLauncherReady(
          root,
          args,
          expectedIdentity,
          (observed) => {
            recordObservedRuntimeIdentity(attempt.runtimeIdentity, observed);
            recordObservedRuntimeIdentity(report.runtimeIdentity, observed);
          },
          entryProof
        );
        attempt.httpPort = ready.port;
        recordVerifiedRuntimeIdentity(attempt.runtimeIdentity, ready.runtimeIdentity);
        recordVerifiedRuntimeIdentity(report.runtimeIdentity, ready.runtimeIdentity);
        attempt.agentStatus = ready.status;
        attempt.agentEntryProof = ready.entryProof;
        entryProof = ready.entryProof;
        report.httpPort = ready.port;
        report.finalAgentStatus = ready.status;

        const batch = await runBatch(ready.port, current.manifestPathRel, args);
        const finalRuntimeIdentity = verifyRuntimeIdentity(
          root,
          ready.port,
          expectedIdentity,
          (observed) => {
            recordObservedRuntimeIdentity(attempt.runtimeIdentity, observed);
            recordObservedRuntimeIdentity(report.runtimeIdentity, observed);
          }
        );
        recordVerifiedRuntimeIdentity(attempt.runtimeIdentity, finalRuntimeIdentity);
        recordVerifiedRuntimeIdentity(report.runtimeIdentity, finalRuntimeIdentity);
        attempt.batchStart = batch.start;
        attempt.finalArenaStatus = batch.status;
        attempt.status = batch.status && batch.status.state ? batch.status.state : "unknown";
        resultPathRel = resultPathFromBatchOutcome(current.manifest, batch, null);
      } catch (error) {
        if (error && error.phase === "runtime_identity") throw error;
        const terminalStatus = error.lastStatus && TERMINAL_STATES.has(error.lastStatus.state)
          ? error.lastStatus.state
          : null;
        attempt.status = terminalStatus || "interrupted";
        attempt.error = {
          message: describeAttemptError(error),
          phase: error.phase || null,
        };
        attempt.batchStart = error.start || null;
        attempt.finalArenaStatus = error.lastStatus || null;
        resultPathRel = resultPathFromBatchOutcome(
          current.manifest,
          { start: error.start || null, status: error.lastStatus || null },
          error
        );
      }

      attempt.completedAt = new Date().toISOString();
      report.finalArenaStatus = attempt.finalArenaStatus;

      const attemptOutputs = attemptOutputPaths(root, outputs, attempt.index, current.manifest.batchId);
      if (attempt.error && (attempt.error.phase === "batch_timeout" || attempt.error.phase === "external_cancel")) {
        await waitForResultFile(root, resultPathRel, Math.max(5000, args.pollMs * 2), args.pollMs);
      }
      const analyzed = analyzeAttemptResult(
        root,
        resultPathRel,
        attemptOutputs.summary,
        attemptOutputs.summaryMd,
        current.manifest
      );
      attempt.resultPath = analyzed.resultPath;
      attempt.resultRows = analyzed.rows.length;
      attempt.summaryPath = analyzed.summaryPath;
      attempt.summaryMdPath = analyzed.summaryMdPath;
      attempt.summaryTotals = analyzed.summary ? analyzed.summary.totals : null;
      attempt.analysisError = analyzed.error;

      const reason = attempt.status === "completed"
        ? "missing_or_abnormal_rows"
        : (attempt.error && attempt.error.phase) || attempt.status || "attempt_failed";
      const canRecover = report.recoveryAttemptsUsed < args.maxRecoveryAttempts;
      const rerun = writeRerunManifest(
        root,
        current.manifest,
        analyzed.rows,
        reason,
        canRecover ? null : outputs.rerunManifest
      );
      if (rerun) {
        attempt.rerunManifestPath = rerun.manifestPathRel;
        attempt.rerunBatchId = rerun.manifest.batchId;
      }

      if (rerun && canRecover) {
        attempt.autoRecovered = true;
        report.attempts.push(attempt);
        report.recoveryAttemptsUsed += 1;
        report.suggestions.push(
          `Auto recovery ${report.recoveryAttemptsUsed}/${args.maxRecoveryAttempts}: ${attempt.batchId} -> ${rerun.manifestPathRel}`
        );
        await shutdownLauncher(root);
        current = rerun;
        continue;
      }

      report.attempts.push(attempt);
      finalAttempt = attempt;
      finalAnalyzed = analyzed;
      break;
    }

    if (!finalAttempt) {
      fail("unattended runner ended without a recorded attempt");
    }

    report.resultPath = finalAttempt.resultPath;
    report.rows = finalAttempt.resultRows;
    report.expectedRows = finalAttempt.expectedRows;
    report.summaryTotals = finalAttempt.summaryTotals;
    if (finalAttempt.rerunManifestPath && !finalAttempt.autoRecovered) {
      report.status = "needs_rerun";
      report.rerunManifestPath = finalAttempt.rerunManifestPath;
      report.suggestions.push(`Run rerun manifest: ${finalAttempt.rerunManifestPath}`);
    } else if (finalAttempt.error && finalAttempt.error.phase === "external_cancel") {
      report.status = "yielded";
      report.suggestions.push("The owned cancel signal remains authoritative; arm a fresh idle window before resuming.");
    } else if (finalAttempt.status === "completed") {
      report.status = "completed";
    } else if (finalAttempt.error) {
      report.status = "failed";
    } else {
      report.status = finalAttempt.status || "failed";
    }
    copyFinalSummary(outputs, finalAnalyzed);
    report.completedAt = new Date().toISOString();
    if (report.status !== "completed" || report.rerunManifestPath) {
      report.suggestions.push("Inspect finalArenaStatus and result JSONL before planning the next exploratory batch.");
    }
    if (args.shutdown) {
      report.postRunShutdown = await shutdownLauncher(root);
    }
    finalizeSaveProtection(report, root);
    if (report.saveProtection && report.saveProtection.unchanged === false) report.status = "failed";
    report.failures = buildFailureList(report);
    writeReport(report, outputs.report, outputs.reportMd);

    console.log(
      JSON.stringify(
        {
          ok: report.status === "completed",
          status: report.status,
          batchId: report.batchId,
          resultPath: report.resultPath,
          summary: toProjectRelative(root, outputs.summary),
          report: toProjectRelative(root, outputs.report),
          rerunManifest: report.rerunManifestPath,
          recoveryAttemptsUsed: report.recoveryAttemptsUsed,
          runtimeMode: report.runtimeIdentity.runtimeMode,
          processPath: report.runtimeIdentity.processPath,
          coreSha256: report.runtimeIdentity.coreSha256,
          buildIdentity: report.runtimeIdentity.buildIdentity,
          payloadClosure: report.runtimeIdentity.payloadClosure,
        },
        null,
        2
      )
    );
    if (report.status !== "completed") process.exitCode = 1;
  } catch (error) {
    if (report.status === "running") {
      report.status = "failed";
    }
    report.completedAt = new Date().toISOString();
    if (!report.error) {
      report.error = {
        code: error.code || null,
        phase: error.phase || null,
        message: error.message,
        details: error.details || null,
      };
    }
    try { finalizeSaveProtection(report, root); } catch (_saveProtectionError) { }
    report.failures = buildFailureList(report);
    report.suggestions.push("Rerun with the same manifest after checking launcher.log and the run report.");
    writeReport(report, outputs.report, outputs.reportMd);
    throw error;
  }
}

main(process.argv.slice(2)).catch((error) => {
  console.error(error.message);
  process.exit(error.isUsageError ? 2 : 1);
});
