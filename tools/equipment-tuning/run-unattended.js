#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const path = require("path");

const PORT_CANDIDATES = [
  1192, 1924, 9243, 2433, 4339, 3399, 3993,
  11924, 19243, 24339, 43399, 33993, 3000,
];
const DEFAULT_AGENT_SLOT = "cf7_agent_equipment_tuning";
const AGENT_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const SAFE_SLOT_RE = /^[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const HANDOFF_MARKER = "[BootstrapAS] event=handoff";
const AGENT_ENTER_COMMAND = "#func:_root.agentEnterResolvedSave()";
const LOG_TAIL_LIMIT = 2000;

class RunnerError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "RunnerError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
    this.isUsageError = phase === "arguments";
  }
}

function fail(code, phase, message, details) {
  throw new RunnerError(code, phase, message, details);
}

function parseArgs(argv) {
  const args = {
    slot: DEFAULT_AGENT_SLOT,
    seedSlot: null,
    startLauncher: true,
    fresh: false,
    shutdown: false,
    readyTimeoutMs: 180000,
    panelTimeoutMs: 60000,
    pollMs: 500,
    report: null,
    reportMd: null,
    check: false,
    help: false,
  };

  function valueAfter(index, option) {
    if (index + 1 >= argv.length || String(argv[index + 1]).startsWith("--")) {
      fail("missing_argument_value", "arguments", option + " requires a value");
    }
    return argv[index + 1];
  }

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--slot") args.slot = valueAfter(index++, token);
    else if (token === "--seed-slot") args.seedSlot = valueAfter(index++, token);
    else if (token === "--no-start-launcher") args.startLauncher = false;
    else if (token === "--fresh") args.fresh = true;
    else if (token === "--shutdown") args.shutdown = true;
    else if (token === "--ready-timeout-ms") args.readyTimeoutMs = Number(valueAfter(index++, token));
    else if (token === "--panel-timeout-ms") args.panelTimeoutMs = Number(valueAfter(index++, token));
    else if (token === "--poll-ms") args.pollMs = Number(valueAfter(index++, token));
    else if (token === "--report") args.report = valueAfter(index++, token);
    else if (token === "--report-md") args.reportMd = valueAfter(index++, token);
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail("unknown_argument", "arguments", "unknown argument: " + token);
  }
  return args;
}

function printHelp() {
  console.log([
    "Usage: node tools/equipment-tuning/run-unattended.js --seed-slot <slot> [options]",
    "",
    "Opens the production equipment-tuning workbench on an isolated save clone,",
    "waits for the active workbench instance and its first authoritative tuning",
    "snapshot, then stops. It never clicks business controls or sends preview/commit.",
    "",
    "Options:",
    "  --slot <slot>              Dedicated target slot. Default: " + DEFAULT_AGENT_SLOT,
    "  --seed-slot <slot>         Required source shadow. Read-only; cloned before launch.",
    "  --no-start-launcher        Require an already running launcher.",
    "  --ready-timeout-ms <n>     Runtime readiness timeout. Default: 180000.",
    "  --panel-timeout-ms <n>     Workbench/snapshot evidence timeout. Default: 60000.",
    "  --poll-ms <n>              Status/log polling interval. Default: 500.",
    "  --report <file>            JSON report path.",
    "  --report-md <file>         Markdown report path.",
    "  --shutdown                 Ask launcher to shut down after reporting.",
    "  --fresh                    Always rejected; fresh save automation is forbidden.",
    "  --check                    Offline self-check; does not launch or touch saves.",
    "",
    "Safety:",
    "  The target must match cf7_agent_* and can never be crazyflasher7_saves*.",
    "  --seed-slot may name a live shadow because it is only read and cloned.",
  ].join("\n"));
}

function assertSafeArgs(args) {
  if (args.fresh) {
    fail(
      "fresh_forbidden",
      "arguments",
      "--fresh is forbidden for unattended equipment tuning; use an explicit seeded clone"
    );
  }
  if (!AGENT_SLOT_RE.test(String(args.slot || "")) || LIVE_SLOT_RE.test(String(args.slot || ""))) {
    fail(
      "unsafe_target_slot",
      "arguments",
      "target slot must be a dedicated cf7_agent_* slot and can never be a live save slot"
    );
  }
  if (!args.seedSlot) {
    fail(
      "seed_slot_required",
      "arguments",
      "--seed-slot is required; implicit newest-save selection is not allowed"
    );
  }
  if (!isSafeSlotName(args.seedSlot)) {
    fail(
      "unsafe_seed_slot",
      "arguments",
      "--seed-slot must contain only letters, digits, underscore, or hyphen"
    );
  }
  if (args.seedSlot === args.slot) {
    fail(
      "seed_equals_target",
      "arguments",
      "--seed-slot must differ from the dedicated target slot"
    );
  }
  assertPositiveInteger(args.readyTimeoutMs, "--ready-timeout-ms", 1000);
  assertPositiveInteger(args.panelTimeoutMs, "--panel-timeout-ms", 1000);
  assertPositiveInteger(args.pollMs, "--poll-ms", 50);
}

function assertPositiveInteger(value, option, minimum) {
  if (!Number.isInteger(value) || value < minimum) {
    fail(
      "invalid_timeout",
      "arguments",
      option + " must be an integer greater than or equal to " + minimum
    );
  }
}

function isSafeSlotName(slot) {
  const text = String(slot || "");
  return SAFE_SLOT_RE.test(text) && text !== "." && text !== ".." && !text.includes("..");
}

function projectRoot() {
  return path.resolve(__dirname, "../..");
}

function timestampId(date) {
  const value = date || new Date();
  return value.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function toProjectRelative(root, filePath) {
  const relative = path.relative(root, filePath);
  if (!relative.startsWith("..") && !path.isAbsolute(relative)) {
    return relative.replace(/\\/g, "/");
  }
  return filePath;
}

function resolveOutputPath(root, filePath) {
  return path.isAbsolute(filePath) ? filePath : path.resolve(root, filePath);
}

function formatLocalSaveTimestamp(date) {
  const value = date || new Date();
  const pad = (number) => String(number).padStart(2, "0");
  return value.getFullYear() + "-" + pad(value.getMonth() + 1) + "-" + pad(value.getDate())
    + " " + pad(value.getHours()) + ":" + pad(value.getMinutes()) + ":" + pad(value.getSeconds());
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
  if (!data.tasks || !Array.isArray(data.tasks.tasks_to_do)
      || !data.tasks.tasks_finished || !data.tasks.task_chains_progress) return false;
  if (!data.pets || !Array.isArray(data.pets["宠物信息"])
      || data.pets["宠物信息"].length < 5 || data.pets["宠物领养限制"] == null) return false;
  if (!data.shop || !Array.isArray(data.shop["商城已购买物品"])
      || !Array.isArray(data.shop["商城购物车"])) return false;
  return true;
}

function tryReadValidSave(filePath) {
  try {
    const raw = fs.readFileSync(filePath, "utf8");
    const data = JSON.parse(raw);
    if (!isValidSaveData(data)) return null;
    return { filePath, data, raw };
  } catch (_error) {
    return null;
  }
}

function saveJsonPath(root, slot) {
  return path.join(root, "saves", String(slot) + ".json");
}

function backupFile(source, backupDir, label) {
  if (!fs.existsSync(source)) return null;
  fs.mkdirSync(backupDir, { recursive: true });
  const destination = path.join(backupDir, label + "-" + path.basename(source));
  fs.copyFileSync(source, destination);
  return destination;
}

function findSolFiles(root, slot) {
  const appData = process.env.APPDATA;
  if (!appData) return [];
  const sharedRoot = path.join(appData, "Macromedia", "Flash Player", "#SharedObjects");
  if (!fs.existsSync(sharedRoot)) return [];

  const fileName = String(slot) + ".sol";
  const projectNeedle = path.basename(root).toLowerCase();
  const results = [];
  const stack = [sharedRoot];
  while (stack.length > 0) {
    const directory = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(directory, { withFileTypes: true });
    } catch (_error) {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(directory, entry.name);
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && entry.name === fileName) {
        const lower = full.toLowerCase();
        if (lower.includes(projectNeedle)
            && lower.includes("crazyflasher7mercenaryempire.swf")) {
          results.push(full);
        }
      }
    }
  }
  return results.sort();
}

function prepareDedicatedSave(root, args, runDir) {
  const seedPath = saveJsonPath(root, args.seedSlot);
  const seed = tryReadValidSave(seedPath);
  if (!seed) {
    fail(
      "invalid_seed_shadow",
      "save_seed",
      "--seed-slot " + args.seedSlot + " is missing or is not a valid save shadow"
    );
  }

  const targetPath = saveJsonPath(root, args.slot);
  const backupDir = path.join(runDir, "save-backups");
  const preparation = {
    targetSlot: args.slot,
    seedSlot: args.seedSlot,
    seedSource: toProjectRelative(root, seedPath),
    targetJson: toProjectRelative(root, targetPath),
    seedSha256: crypto.createHash("sha256").update(seed.raw, "utf8").digest("hex"),
    role: seed.data["0"][0],
    level: seed.data["0"][3],
    backups: [],
    removedSolFiles: [],
    wroteSeed: false,
  };

  const targetBackup = backupFile(targetPath, backupDir, "target-json");
  if (targetBackup) preparation.backups.push(toProjectRelative(root, targetBackup));

  const solFiles = findSolFiles(root, args.slot);
  solFiles.forEach((solPath, index) => {
    const backup = backupFile(solPath, backupDir, "target-sol-" + String(index + 1));
    if (backup) preparation.backups.push(toProjectRelative(root, backup));
    fs.unlinkSync(solPath);
    preparation.removedSolFiles.push(solPath);
  });

  const clone = JSON.parse(JSON.stringify(seed.data));
  clone.lastSaved = formatLocalSaveTimestamp();
  fs.mkdirSync(path.dirname(targetPath), { recursive: true });
  fs.writeFileSync(targetPath, JSON.stringify(clone), "utf8");
  preparation.wroteSeed = true;
  preparation.targetSha256 = crypto
    .createHash("sha256")
    .update(fs.readFileSync(targetPath))
    .digest("hex");
  return preparation;
}

function httpRequest(port, method, pathname, body, timeoutMs) {
  return new Promise((resolve, reject) => {
    const payload = body === undefined || body === null ? "" : JSON.stringify(body);
    const req = http.request(
      {
        hostname: "localhost",
        port,
        path: pathname,
        method,
        timeout: timeoutMs || 5000,
        headers: {
          "Content-Type": "application/json",
          "Content-Length": Buffer.byteLength(payload),
        },
      },
      (res) => {
        const chunks = [];
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          resolve({
            statusCode: res.statusCode,
            text: Buffer.concat(chunks).toString("utf8"),
          });
        });
      }
    );
    req.on("timeout", () => {
      req.destroy(new Error("HTTP " + method + " " + pathname + " timed out"));
    });
    req.on("error", reject);
    req.end(payload);
  });
}

function parseJsonResponse(response, context) {
  try {
    return JSON.parse(response.text);
  } catch (_error) {
    fail(
      "non_json_response",
      "http",
      context + " returned non-JSON HTTP " + response.statusCode + ": "
        + response.text.slice(0, 300)
    );
  }
}

async function testPort(port) {
  try {
    const response = await httpRequest(port, "POST", "/testConnection", null, 1000);
    return response.statusCode === 200;
  } catch (_error) {
    return false;
  }
}

async function discoverPort(root) {
  const ports = [];
  const portsFile = path.join(root, "launcher_ports.json");
  if (fs.existsSync(portsFile)) {
    try {
      const parsed = JSON.parse(fs.readFileSync(portsFile, "utf8"));
      if (Number.isInteger(parsed.httpPort)) ports.push(parsed.httpPort);
    } catch (_error) {
      // Candidate scan below is the safe fallback for a stale/truncated ports file.
    }
  }
  PORT_CANDIDATES.forEach((port) => {
    if (!ports.includes(port)) ports.push(port);
  });
  for (const port of ports) {
    if (await testPort(port)) return port;
  }
  return null;
}

function startLauncher(root) {
  const script = path.join(root, "automation", "start.ps1");
  const result = childProcess.spawnSync(
    "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script],
    { cwd: root, encoding: "utf8" }
  );
  if (result.status !== 0) {
    fail(
      "launcher_start_failed",
      "launcher",
      "automation/start.ps1 failed with exit code " + result.status,
      {
        stdout: tailText(result.stdout || ""),
        stderr: tailText(result.stderr || ""),
        signal: result.signal || null,
      }
    );
  }
  if (result.stdout) process.stdout.write(result.stdout);
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function waitForPort(root, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() <= deadline) {
    const port = await discoverPort(root);
    if (port) return port;
    await sleep(Math.max(250, pollMs));
  }
  fail(
    "launcher_http_timeout",
    "launcher",
    "launcher HTTP bus was not ready within " + timeoutMs + "ms"
  );
}

async function ensureLauncherPort(root, args) {
  let port = await discoverPort(root);
  if (!port && args.startLauncher) {
    startLauncher(root);
    port = await waitForPort(root, args.readyTimeoutMs, args.pollMs);
  }
  if (!port) {
    fail(
      "launcher_not_running",
      "launcher",
      "launcher is not running; remove --no-start-launcher or start it first"
    );
  }
  return port;
}

async function callTask(port, message, timeoutMs) {
  const response = await httpRequest(port, "POST", "/task", message, timeoutMs || 20000);
  return parseJsonResponse(response, "/task " + String(message.task || ""));
}

async function agent(port, action, fields) {
  return callTask(port, Object.assign(
    { task: "agent_control", action },
    fields || {}
  ));
}

async function consoleCommand(port, command) {
  const response = await httpRequest(
    port,
    "POST",
    "/console",
    { command },
    10000
  );
  return parseJsonResponse(response, "/console");
}

function responseSucceeded(response) {
  return !!response && (response.success === true || response.ok === true);
}

function assertResponseSucceeded(response, phase, label) {
  if (responseSucceeded(response)) return;
  fail(
    "task_failed",
    phase,
    label + " failed: " + JSON.stringify(response),
    response
  );
}

async function waitForAgentControl(port, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let last = null;
  while (Date.now() <= deadline) {
    try {
      last = await agent(port, "status");
      if (responseSucceeded(last)
          && last.error !== "task 'agent_control' is not httpCallable") {
        return last;
      }
    } catch (_error) {
      // Launcher may expose HTTP a moment before TaskRegistry is fully ready.
    }
    await sleep(pollMs);
  }
  fail(
    "agent_control_timeout",
    "launcher",
    "agent_control was not available within " + timeoutMs + "ms",
    last
  );
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
  if (parsed.success !== true || !Number.isInteger(parsed.total) || !Array.isArray(parsed.lines)) {
    fail(
      "logs_unavailable",
      "logs",
      "/logs did not return a usable watermark: " + JSON.stringify(parsed),
      parsed
    );
  }
  return {
    total: parsed.total,
    lines: parsed.lines.map((line) => String(line)),
    capturedAt: new Date().toISOString(),
  };
}

function logWatermark(snapshot) {
  return {
    total: snapshot.total,
    capturedAt: snapshot.capturedAt || new Date().toISOString(),
  };
}

function freshLogRecords(watermark, snapshot) {
  if (!watermark || !Number.isInteger(watermark.total)) {
    fail("invalid_log_watermark", "logs", "log watermark is missing or malformed");
  }
  if (!snapshot || !Number.isInteger(snapshot.total) || !Array.isArray(snapshot.lines)) {
    fail("invalid_log_snapshot", "logs", "log snapshot is missing or malformed");
  }
  if (snapshot.total < watermark.total) {
    fail(
      "log_reset_after_watermark",
      "logs",
      "launcher.log shrank after the watermark; freshness cannot be proven",
      { watermarkTotal: watermark.total, currentTotal: snapshot.total }
    );
  }

  const oldestZeroBased = snapshot.total - snapshot.lines.length;
  if (watermark.total < oldestZeroBased) {
    fail(
      "log_gap_after_watermark",
      "logs",
      "more than " + LOG_TAIL_LIMIT
        + " launcher log lines arrived after the watermark; freshness evidence was lost",
      { watermarkTotal: watermark.total, oldestAvailable: oldestZeroBased }
    );
  }

  const start = Math.max(0, watermark.total - oldestZeroBased);
  return snapshot.lines.slice(start).map((line, offset) => ({
    line,
    lineNumber: oldestZeroBased + start + offset + 1,
  }));
}

function findFreshHandoff(records) {
  return records.find((record) => record.line.includes(HANDOFF_MARKER)) || null;
}

function extractLogField(line, name) {
  const escaped = name.replace(/[.*+?^{}$()|[\]\\]/g, "\\$&");
  const match = String(line).match(new RegExp("(?:^|\\s)" + escaped + "=([^\\s]+)"));
  return match ? match[1] : null;
}

function parsePanelBoundEvidence(record) {
  if (!record || !record.line.includes("event=equipment_tuning_panel_bound")) return null;
  const panelInstanceId = extractLogField(record.line, "panelInstanceId");
  if (!panelInstanceId) return null;
  return {
    kind: "active_workbench",
    marker: "equipment_tuning_panel_bound",
    panelInstanceId,
    lineNumber: record.lineNumber,
    line: record.line,
  };
}

function parseSnapshotEvidence(record) {
  if (!record || !record.line.includes("event=equipment_tuning_snapshot_confirmed")) return null;
  const callId = extractLogField(record.line, "callId");
  const panelInstanceId = extractLogField(record.line, "panelInstanceId");
  const viewSessionId = extractLogField(record.line, "viewSessionId");
  const writeEpochText = extractLogField(record.line, "writeEpoch");
  const writeEpoch = writeEpochText == null ? NaN : Number(writeEpochText);
  if (!callId || !panelInstanceId || !viewSessionId
      || !Number.isInteger(writeEpoch) || writeEpoch < 0) return null;
  return {
    kind: "tuning_snapshot",
    marker: "equipment_tuning_snapshot_confirmed",
    callId,
    panelInstanceId,
    viewSessionId,
    writeEpoch,
    lineNumber: record.lineNumber,
    line: record.line,
  };
}

function selectWorkbenchSnapshotGate(records) {
  const bounds = records.map(parsePanelBoundEvidence).filter(Boolean);
  const snapshots = records.map(parseSnapshotEvidence).filter(Boolean);
  for (const bound of bounds) {
    for (const snapshot of snapshots) {
      if (snapshot.lineNumber <= bound.lineNumber) continue;
      if (snapshot.panelInstanceId !== bound.panelInstanceId) continue;
      return { activeWorkbench: bound, tuningSnapshot: snapshot };
    }
  }
  return null;
}

function readyBlockers(status) {
  return status && Array.isArray(status.runtimeReadyBlockedBy)
    ? status.runtimeReadyBlockedBy
    : [];
}

function isSafeSnapshotStatus(save) {
  return !!save
    && save.decision === "snapshot"
    && save.kind === "Snapshot";
}

function statusAttemptForSlot(status, slot) {
  const save = status && status.save;
  if (!save || save.slot !== slot) return null;
  return typeof save.attemptId === "string" && save.attemptId
    ? save.attemptId
    : null;
}

function shouldRequestAgentEnter(status, state) {
  if (!status || !state || state.enterRequested) return false;
  if (!state.handoffEvidence || !state.expectedAttemptId) return false;
  if (status.launchState !== "Ready"
      || status.revealPerformed !== true
      || status.socketConnected !== true) return false;
  if (!readyBlockers(status).includes("runtime_save_not_loaded")) return false;
  if (!isSafeSnapshotStatus(status.save)) return false;
  return status.save.slot === state.expectedSlot
    && status.save.attemptId === state.expectedAttemptId;
}

function assertRuntimeReadyStatus(status, expectedSlot, expectedAttemptId) {
  if (!status || status.readyForRuntimeAutomation !== true
      || readyBlockers(status).length !== 0) {
    fail(
      "runtime_not_ready",
      "runtime_ready",
      "readyForRuntimeAutomation was not satisfied",
      status
    );
  }
  if (!isSafeSnapshotStatus(status.save)
      || status.save.slot !== expectedSlot
      || status.save.attemptId !== expectedAttemptId) {
    fail(
      "launcher_save_watermark_mismatch",
      "runtime_ready",
      "launcher save watermark does not match the dedicated slot/attempt",
      status.save
    );
  }
  const runtime = status.saveRuntime;
  if (!runtime || runtime.loaded !== true
      || runtime.savePath !== expectedSlot
      || runtime.attemptId !== expectedAttemptId
      || typeof runtime.role !== "string" || !runtime.role
      || runtime.level == null || Number.isNaN(Number(runtime.level))) {
    fail(
      "runtime_save_watermark_mismatch",
      "runtime_ready",
      "AS2 runtime acknowledgement does not match the dedicated slot/attempt",
      runtime
    );
  }
}

async function waitForRuntimeReady(port, args, startWatermark, priorStatus, startResponse, timeline) {
  const deadline = Date.now() + args.readyTimeoutMs;
  const priorAttemptId = priorStatus && priorStatus.save
    ? priorStatus.save.attemptId || null
    : null;
  let status = startResponse;
  let expectedAttemptId = statusAttemptForSlot(status, args.slot);
  if (expectedAttemptId && priorAttemptId && expectedAttemptId === priorAttemptId) {
    expectedAttemptId = null;
  }
  const state = {
    expectedSlot: args.slot,
    expectedAttemptId,
    handoffEvidence: null,
    enterRequested: false,
    enterRequestCount: 0,
    enterResponse: null,
  };
  let lastLogSnapshot = null;

  while (Date.now() <= deadline) {
    status = await agent(port, "status");
    assertResponseSucceeded(status, "runtime_ready", "agent_control status");

    const candidateAttempt = statusAttemptForSlot(status, args.slot);
    if (candidateAttempt && (!priorAttemptId || candidateAttempt !== priorAttemptId)) {
      if (state.expectedAttemptId && state.expectedAttemptId !== candidateAttempt) {
        fail(
          "attempt_changed",
          "runtime_ready",
          "launcher attempt changed while waiting for runtime readiness",
          { expected: state.expectedAttemptId, actual: candidateAttempt }
        );
      }
      state.expectedAttemptId = candidateAttempt;
    }

    lastLogSnapshot = await readLogSnapshot(port);
    const freshRecords = freshLogRecords(startWatermark, lastLogSnapshot);
    if (!state.handoffEvidence && state.expectedAttemptId) {
      state.handoffEvidence = findFreshHandoff(freshRecords);
      if (state.handoffEvidence) {
        timeline.push({
          phase: "fresh_handoff_observed",
          at: new Date().toISOString(),
          lineNumber: state.handoffEvidence.lineNumber,
        });
      }
    }

    if (status.launchState === "Error") {
      fail(
        "launcher_error",
        "runtime_ready",
        "launcher entered Error state while waiting for runtime readiness",
        status
      );
    }

    if (state.handoffEvidence
        && status.launchState === "Ready"
        && status.revealPerformed === true
        && readyBlockers(status).includes("save_decision_unsafe")) {
      fail(
        "save_decision_unsafe",
        "runtime_ready",
        "launcher rejected the dedicated clone as an authoritative snapshot",
        status.save
      );
    }

    if (status.readyForRuntimeAutomation === true) {
      if (!state.handoffEvidence) {
        await sleep(args.pollMs);
        continue;
      }
      if (state.enterRequestCount !== 1) {
        fail(
          "runtime_ready_without_single_enter",
          "runtime_ready",
          "runtime became ready without exactly one agentEnterResolvedSave request",
          { enterRequestCount: state.enterRequestCount }
        );
      }
      if (!state.expectedAttemptId) {
        fail(
          "attempt_missing",
          "runtime_ready",
          "runtime became ready without a fresh launcher attempt id"
        );
      }
      assertRuntimeReadyStatus(status, args.slot, state.expectedAttemptId);
      return {
        status,
        expectedAttemptId: state.expectedAttemptId,
        handoffEvidence: state.handoffEvidence,
        enterRequestCount: state.enterRequestCount,
        enterResponse: state.enterResponse,
        lastLogTotal: lastLogSnapshot.total,
      };
    }

    if (shouldRequestAgentEnter(status, state)) {
      state.enterRequested = true;
      state.enterRequestCount += 1;
      state.enterResponse = await consoleCommand(port, AGENT_ENTER_COMMAND);
      assertResponseSucceeded(
        state.enterResponse,
        "agent_enter",
        "agentEnterResolvedSave"
      );
      timeline.push({
        phase: "agent_enter_requested",
        at: new Date().toISOString(),
        attemptId: state.expectedAttemptId,
        count: state.enterRequestCount,
      });
    }
    await sleep(args.pollMs);
  }

  fail(
    "runtime_ready_timeout",
    "runtime_ready",
    "game did not reach readyForRuntimeAutomation within "
      + args.readyTimeoutMs + "ms",
    {
      status,
      expectedAttemptId: state.expectedAttemptId,
      handoffEvidence: state.handoffEvidence,
      enterRequestCount: state.enterRequestCount,
      logTotal: lastLogSnapshot ? lastLogSnapshot.total : null,
    }
  );
}

async function waitForWorkbenchSnapshotGate(port, watermark, timeoutMs, pollMs) {
  const deadline = Date.now() + timeoutMs;
  let lastSnapshot = null;
  while (Date.now() <= deadline) {
    lastSnapshot = await readLogSnapshot(port);
    const records = freshLogRecords(watermark, lastSnapshot);
    const evidence = selectWorkbenchSnapshotGate(records);
    if (evidence) {
      return {
        evidence,
        lastLogTotal: lastSnapshot.total,
      };
    }
    await sleep(pollMs);
  }
  fail(
    "snapshot_gate_timeout",
    "snapshot_gate",
    "active workbench and first equipment-tuning snapshot were not both confirmed within "
      + timeoutMs + "ms",
    {
      watermarkTotal: watermark.total,
      lastLogTotal: lastSnapshot ? lastSnapshot.total : null,
      requiredMarkers: [
        "event=equipment_tuning_panel_bound",
        "event=equipment_tuning_snapshot_confirmed",
      ],
    }
  );
}

async function shutdownLauncher(port) {
  try {
    return await agent(port, "shutdown");
  } catch (error) {
    return {
      success: false,
      error: "shutdown_failed",
      message: error.message,
    };
  }
}

function tailText(text, limit) {
  const max = limit || 6000;
  const value = String(text || "");
  return value.length <= max ? value : value.slice(value.length - max);
}

function defaultOutputPaths(root, args) {
  const runDir = path.join(
    root,
    "tmp",
    "equipment-tuning",
    "unattended",
    timestampId() + "-" + args.slot
  );
  return {
    runDir,
    report: args.report
      ? resolveOutputPath(root, args.report)
      : path.join(runDir, "run-report.json"),
    reportMd: args.reportMd
      ? resolveOutputPath(root, args.reportMd)
      : path.join(runDir, "run-report.md"),
  };
}

function serializeError(error) {
  return {
    code: error.code || "unhandled_error",
    phase: error.phase || "unknown",
    message: error.message,
    details: error.details || null,
  };
}

function formatReportMarkdown(report) {
  const lines = [
    "# Equipment tuning unattended run",
    "",
    "- Status: " + report.status,
    "- Slot: " + report.slot,
    "- Seed slot: " + report.seedSlot,
    "- Started: " + report.startedAt,
    "- Finished: " + (report.finishedAt || ""),
    "- Gate: " + report.scope.gate,
    "- UI business clicks: " + String(report.scope.uiBusinessClicks),
    "- Business writes attempted: " + String(report.scope.businessWritesAttempted),
    "",
  ];
  if (report.runtime && report.runtime.expectedAttemptId) {
    lines.push("## Runtime watermark", "");
    lines.push("- Attempt: " + report.runtime.expectedAttemptId);
    lines.push("- Fresh handoff line: "
      + String(report.runtime.handoffEvidence
        ? report.runtime.handoffEvidence.lineNumber
        : "not observed"));
    lines.push("- agentEnterResolvedSave calls: "
      + String(report.runtime.enterRequestCount));
    lines.push("");
  }
  if (report.snapshotGate && report.snapshotGate.evidence) {
    const evidence = report.snapshotGate.evidence;
    lines.push("## Snapshot gate", "");
    lines.push("- Active workbench instance: "
      + evidence.activeWorkbench.panelInstanceId);
    lines.push("- Tuning view session: "
      + evidence.tuningSnapshot.viewSessionId);
    lines.push("- Snapshot call: " + evidence.tuningSnapshot.callId);
    lines.push("- Write epoch: " + String(evidence.tuningSnapshot.writeEpoch));
    lines.push("");
  }
  if (report.error) {
    lines.push("## Failure", "");
    lines.push("- Code: " + report.error.code);
    lines.push("- Phase: " + report.error.phase);
    lines.push("- Message: " + report.error.message);
    lines.push("");
  }
  lines.push("## Boundary", "");
  lines.push(
    "This run stops after the production AS2 opener, active workbench binding, "
      + "and the first authoritative equipment-tuning snapshot. It does not "
      + "click operation controls or send preview/commit."
  );
  lines.push("");
  return lines.join("\n");
}

function writeJsonFile(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function writeReport(report, outputs) {
  writeJsonFile(outputs.report, report);
  fs.mkdirSync(path.dirname(outputs.reportMd), { recursive: true });
  fs.writeFileSync(outputs.reportMd, formatReportMarkdown(report), "utf8");
}

function expectRejected(label, callback, expectedCode) {
  let error = null;
  try {
    callback();
  } catch (caught) {
    error = caught;
  }
  if (!error) throw new Error(label + " was not rejected");
  if (expectedCode && error.code !== expectedCode) {
    throw new Error(label + " returned " + error.code + ", expected " + expectedCode);
  }
}

function runCheck() {
  const parsed = parseArgs(["--seed-slot", "crazyflasher7_saves2"]);
  assertSafeArgs(parsed);
  if (parsed.slot !== DEFAULT_AGENT_SLOT) {
    throw new Error("default dedicated equipment-tuning slot changed");
  }

  expectRejected(
    "live target",
    () => assertSafeArgs(Object.assign({}, parsed, { slot: "crazyflasher7_saves2" })),
    "unsafe_target_slot"
  );
  expectRejected(
    "fresh flow",
    () => assertSafeArgs(Object.assign({}, parsed, { fresh: true })),
    "fresh_forbidden"
  );
  expectRejected(
    "implicit seed",
    () => assertSafeArgs(Object.assign({}, parsed, { seedSlot: null })),
    "seed_slot_required"
  );
  expectRejected(
    "target as seed",
    () => assertSafeArgs(Object.assign({}, parsed, { seedSlot: parsed.slot })),
    "seed_equals_target"
  );

  const watermark = { total: 2, capturedAt: "2026-07-16T00:00:00.000Z" };
  const snapshot = {
    total: 5,
    lines: [
      "old-1",
      "old-2",
      "[BootstrapAS] event=handoff",
      "event=equipment_tuning_panel_bound panelInstanceId=panel.workbench.7",
      "event=equipment_tuning_snapshot_confirmed callId=tune.check.1 "
        + "panelInstanceId=panel.workbench.7 viewSessionId=view.check.1 writeEpoch=3",
    ],
  };
  const records = freshLogRecords(watermark, snapshot);
  const handoff = findFreshHandoff(records);
  if (!handoff || handoff.lineNumber !== 3) {
    throw new Error("fresh handoff watermark check failed");
  }
  const gate = selectWorkbenchSnapshotGate(records);
  if (!gate
      || gate.activeWorkbench.panelInstanceId !== gate.tuningSnapshot.panelInstanceId
      || gate.tuningSnapshot.writeEpoch !== 3) {
    throw new Error("correlated workbench/snapshot evidence check failed");
  }

  const mismatched = selectWorkbenchSnapshotGate([
    {
      lineNumber: 3,
      line: "event=equipment_tuning_panel_bound panelInstanceId=panel.workbench.A",
    },
    {
      lineNumber: 4,
      line: "event=equipment_tuning_snapshot_confirmed callId=tune.bad.1 "
        + "panelInstanceId=panel.workbench.B viewSessionId=view.bad.1 writeEpoch=0",
    },
  ]);
  if (mismatched) throw new Error("cross-instance snapshot evidence was accepted");

  const beforeHandoff = {
    launchState: "Ready",
    revealPerformed: true,
    socketConnected: true,
    runtimeReadyBlockedBy: ["runtime_save_not_loaded"],
    save: {
      decision: "snapshot",
      kind: "Snapshot",
      slot: DEFAULT_AGENT_SLOT,
      attemptId: "attempt-check",
    },
  };
  const enterState = {
    expectedSlot: DEFAULT_AGENT_SLOT,
    expectedAttemptId: "attempt-check",
    handoffEvidence: null,
    enterRequested: false,
  };
  if (shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was allowed before fresh handoff");
  }
  enterState.handoffEvidence = handoff;
  if (!shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was not allowed after all narrow gates");
  }
  enterState.enterRequested = true;
  if (shouldRequestAgentEnter(beforeHandoff, enterState)) {
    throw new Error("agent enter was not single-shot");
  }

  const ready = JSON.parse(JSON.stringify(beforeHandoff));
  ready.runtimeReadyBlockedBy = [];
  ready.readyForRuntimeAutomation = true;
  ready.saveRuntime = {
    loaded: true,
    savePath: DEFAULT_AGENT_SLOT,
    attemptId: "attempt-check",
    role: "check-role",
    level: 10,
  };
  assertRuntimeReadyStatus(ready, DEFAULT_AGENT_SLOT, "attempt-check");
  expectRejected(
    "stale runtime attempt",
    () => {
      const stale = JSON.parse(JSON.stringify(ready));
      stale.saveRuntime.attemptId = "attempt-stale";
      assertRuntimeReadyStatus(stale, DEFAULT_AGENT_SLOT, "attempt-check");
    },
    "runtime_save_watermark_mismatch"
  );

  const markdown = formatReportMarkdown({
    status: "snapshot_gate_reached",
    slot: DEFAULT_AGENT_SLOT,
    seedSlot: "crazyflasher7_saves2",
    startedAt: "2026-07-16T00:00:00.000Z",
    finishedAt: "2026-07-16T00:00:01.000Z",
    scope: {
      gate: "active_workbench_and_first_tuning_snapshot",
      uiBusinessClicks: false,
      businessWritesAttempted: false,
    },
    runtime: {
      expectedAttemptId: "attempt-check",
      handoffEvidence: handoff,
      enterRequestCount: 1,
    },
    snapshotGate: { evidence: gate },
    error: null,
  });
  if (!markdown.includes("does not click operation controls")
      || !markdown.includes("panel.workbench.7")) {
    throw new Error("report boundary/evidence check failed");
  }

  console.log(JSON.stringify({
    ok: true,
    slot: DEFAULT_AGENT_SLOT,
    checks: 12,
    scope: "open_snapshot_gate_only",
  }, null, 2));
}

async function runUnattended(args) {
  assertSafeArgs(args);
  const root = projectRoot();
  const outputs = defaultOutputPaths(root, args);
  fs.mkdirSync(outputs.runDir, { recursive: true });

  const report = {
    schema: "equipment-tuning.unattended-run.v1",
    status: "running",
    slot: args.slot,
    seedSlot: args.seedSlot,
    startedAt: new Date().toISOString(),
    finishedAt: null,
    reportPath: toProjectRelative(root, outputs.report),
    reportMarkdownPath: toProjectRelative(root, outputs.reportMd),
    scope: {
      gate: "active_workbench_and_first_tuning_snapshot",
      productionOpenerOnly: true,
      uiBusinessClicks: false,
      businessWritesAttempted: false,
      businessCommandsSent: [],
      stopAfterSnapshot: true,
    },
    timeline: [],
    savePreparation: null,
    httpPort: null,
    startLogWatermark: null,
    startResponse: null,
    runtime: null,
    openLogWatermark: null,
    openResponse: null,
    snapshotGate: null,
    shutdownResponse: null,
    error: null,
  };

  let port = null;
  let caught = null;
  try {
    report.savePreparation = prepareDedicatedSave(root, args, outputs.runDir);
    report.timeline.push({
      phase: "dedicated_save_seeded",
      at: new Date().toISOString(),
      targetSlot: args.slot,
      seedSlot: args.seedSlot,
    });

    port = await ensureLauncherPort(root, args);
    report.httpPort = port;
    const priorStatus = await waitForAgentControl(
      port,
      args.readyTimeoutMs,
      args.pollMs
    );

    const startLog = await readLogSnapshot(port);
    report.startLogWatermark = logWatermark(startLog);
    report.timeline.push({
      phase: "pre_start_log_watermark",
      at: new Date().toISOString(),
      total: report.startLogWatermark.total,
    });

    report.startResponse = await agent(port, "start", {
      slot: args.slot,
      fresh: false,
      deferReveal: false,
      requireFlashReveal: true,
      rememberSlot: false,
    });
    assertResponseSucceeded(report.startResponse, "start", "agent_control start");
    report.timeline.push({
      phase: "start_requested",
      at: new Date().toISOString(),
      slot: args.slot,
      fresh: false,
    });

    report.runtime = await waitForRuntimeReady(
      port,
      args,
      report.startLogWatermark,
      priorStatus,
      report.startResponse,
      report.timeline
    );
    report.timeline.push({
      phase: "runtime_ready",
      at: new Date().toISOString(),
      attemptId: report.runtime.expectedAttemptId,
    });

    const openLog = await readLogSnapshot(port);
    report.openLogWatermark = logWatermark(openLog);
    report.timeline.push({
      phase: "pre_open_log_watermark",
      at: new Date().toISOString(),
      total: report.openLogWatermark.total,
    });

    report.openResponse = await agent(port, "openEquipmentTuning", {
      expectedSlot: args.slot,
      expectedAttemptId: report.runtime.expectedAttemptId,
    });
    assertResponseSucceeded(
      report.openResponse,
      "open_equipment_tuning",
      "agent_control openEquipmentTuning"
    );
    report.timeline.push({
      phase: "equipment_tuning_open_requested",
      at: new Date().toISOString(),
      attemptId: report.runtime.expectedAttemptId,
    });

    report.snapshotGate = await waitForWorkbenchSnapshotGate(
      port,
      report.openLogWatermark,
      args.panelTimeoutMs,
      args.pollMs
    );
    report.timeline.push({
      phase: "snapshot_gate_reached",
      at: new Date().toISOString(),
      panelInstanceId: report.snapshotGate.evidence.activeWorkbench.panelInstanceId,
      viewSessionId: report.snapshotGate.evidence.tuningSnapshot.viewSessionId,
    });
    report.status = "snapshot_gate_reached";
  } catch (error) {
    caught = error;
    report.status = "failed";
    report.error = serializeError(error);
  } finally {
    if (args.shutdown && port) {
      report.shutdownResponse = await shutdownLauncher(port);
    }
    report.finishedAt = new Date().toISOString();
    writeReport(report, outputs);
  }

  if (caught) throw caught;
  console.log(JSON.stringify({
    ok: true,
    status: report.status,
    slot: report.slot,
    attemptId: report.runtime.expectedAttemptId,
    panelInstanceId: report.snapshotGate.evidence.activeWorkbench.panelInstanceId,
    viewSessionId: report.snapshotGate.evidence.tuningSnapshot.viewSessionId,
    scope: "open_snapshot_gate_only",
    report: report.reportPath,
  }, null, 2));
  return report;
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
  await runUnattended(args);
}

module.exports = {
  AGENT_ENTER_COMMAND,
  DEFAULT_AGENT_SLOT,
  HANDOFF_MARKER,
  assertRuntimeReadyStatus,
  assertSafeArgs,
  extractLogField,
  findFreshHandoff,
  formatReportMarkdown,
  freshLogRecords,
  isValidSaveData,
  logWatermark,
  parseArgs,
  parsePanelBoundEvidence,
  parseSnapshotEvidence,
  runCheck,
  selectWorkbenchSnapshotGate,
  shouldRequestAgentEnter,
};

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    console.error(error.message);
    process.exit(error.isUsageError ? 2 : 1);
  });
}
