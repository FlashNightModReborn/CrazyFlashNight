"use strict";

const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const { spawn } = require("node:child_process");

const RESULT_SCHEMA = "cf7.portrait-worker-capability-result.v1";
const DEFAULT_MODEL = "gpt-5.6-luna";
const DEFAULT_EFFORT = "max";
const MAX_CAPTURE_BYTES = 4 * 1024 * 1024;

class WorkerError extends Error {
  constructor(code, phase, message, details = {}) {
    super(message);
    this.name = "WorkerError";
    this.code = code;
    this.phase = phase;
    this.details = details;
  }
}

function stableValue(value) {
  if (Array.isArray(value)) {
    return value.map(stableValue);
  }
  if (value && typeof value === "object") {
    return Object.fromEntries(
      Object.keys(value)
        .sort()
        .map((key) => [key, stableValue(value[key])]),
    );
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableValue(value));
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex").toUpperCase();
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function isPidAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) {
    return false;
  }
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error && error.code === "EPERM";
  }
}

async function collectCommand(command, args, timeoutMs = 5_000) {
  return new Promise((resolve) => {
    const child = spawn(command, args, {
      shell: false,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        child.kill("SIGKILL");
      }
    }, timeoutMs);
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("error", (error) => {
      settled = true;
      clearTimeout(timer);
      resolve({ exitCode: null, stdout: "", stderr: "", error });
    });
    child.on("close", (exitCode) => {
      if (settled) {
        return;
      }
      settled = true;
      clearTimeout(timer);
      resolve({
        exitCode,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
        error: null,
      });
    });
  });
}

async function listDescendantPids(rootPid) {
  let rows = [];
  if (process.platform === "win32") {
    const script = [
      "$ErrorActionPreference='Stop'",
      "Get-CimInstance Win32_Process |",
      "Select-Object ProcessId,ParentProcessId |",
      "ConvertTo-Json -Compress",
    ].join(" ");
    const result = await collectCommand(
      "powershell.exe",
      ["-NoProfile", "-NonInteractive", "-Command", script],
      10_000,
    );
    if (result.exitCode !== 0 || !result.stdout.trim()) {
      return [];
    }
    const parsed = JSON.parse(result.stdout);
    rows = (Array.isArray(parsed) ? parsed : [parsed]).map((row) => ({
      pid: Number(row.ProcessId),
      parentPid: Number(row.ParentProcessId),
    }));
  } else {
    const result = await collectCommand("ps", ["-eo", "pid=,ppid="], 5_000);
    if (result.exitCode !== 0) {
      return [];
    }
    rows = result.stdout
      .split(/\r?\n/u)
      .map((line) => line.trim().split(/\s+/u).map(Number))
      .filter(([pid, parentPid]) => Number.isInteger(pid) && Number.isInteger(parentPid))
      .map(([pid, parentPid]) => ({ pid, parentPid }));
  }

  const descendants = [];
  const frontier = [rootPid];
  while (frontier.length > 0) {
    const parentPid = frontier.shift();
    for (const row of rows) {
      if (row.parentPid === parentPid && !descendants.includes(row.pid)) {
        descendants.push(row.pid);
        frontier.push(row.pid);
      }
    }
  }
  return descendants;
}

async function terminateExactProcessTree(rootPid, knownDescendants = []) {
  const targets = [...new Set([...knownDescendants, rootPid])]
    .filter((pid) => Number.isInteger(pid) && pid > 0);
  if (process.platform === "win32") {
    await collectCommand(
      "taskkill.exe",
      ["/PID", String(rootPid), "/T", "/F"],
      10_000,
    );
  } else {
    for (const pid of [...targets].reverse()) {
      try {
        process.kill(pid, "SIGTERM");
      } catch {
        // The exact process already exited.
      }
    }
    await sleep(250);
    for (const pid of [...targets].reverse()) {
      if (isPidAlive(pid)) {
        try {
          process.kill(pid, "SIGKILL");
        } catch {
          // The exact process exited between the check and signal.
        }
      }
    }
  }

  const deadline = Date.now() + 3_000;
  let survivors = targets.filter(isPidAlive);
  while (survivors.length > 0 && Date.now() < deadline) {
    await sleep(50);
    survivors = targets.filter(isPidAlive);
  }
  return { targetPids: targets, survivorPids: survivors };
}

async function spawnCaptured(options) {
  const {
    command,
    args,
    cwd,
    env,
    stdin,
    timeoutMs,
    maxCaptureBytes = MAX_CAPTURE_BYTES,
  } = options;

  const startedAt = new Date().toISOString();
  const startedMs = Date.now();
  const child = spawn(command, args, {
    cwd,
    env,
    shell: false,
    windowsHide: true,
    stdio: ["pipe", "pipe", "pipe"],
  });
  const pid = child.pid || null;
  const stdoutChunks = [];
  const stderrChunks = [];
  let stdoutBytes = 0;
  let stderrBytes = 0;
  let overflowStream = null;
  let timedOut = false;
  let terminationReason = null;
  let terminationPromise = null;
  const knownDescendants = new Set();
  let descendantScanChain = Promise.resolve();

  const queueDescendantScan = () => {
    if (!pid) {
      return descendantScanChain;
    }
    descendantScanChain = descendantScanChain.then(async () => {
      try {
        for (const descendantPid of await listDescendantPids(pid)) {
          knownDescendants.add(descendantPid);
        }
      } catch {
        // A fresh scan is retried before forced termination.
      }
    });
    return descendantScanChain;
  };
  const descendantScanTimers = [250, 2_000].map((delayMs) =>
    setTimeout(() => void queueDescendantScan(), delayMs),
  );

  const beginTermination = (reason) => {
    if (terminationPromise || !pid) {
      return terminationPromise;
    }
    terminationReason = reason;
    terminationPromise = (async () => {
      await queueDescendantScan();
      return terminateExactProcessTree(pid, [...knownDescendants]);
    })();
    return terminationPromise;
  };

  child.stdout.on("data", (chunk) => {
    stdoutBytes += chunk.length;
    if (stdoutBytes <= maxCaptureBytes) {
      stdoutChunks.push(chunk);
    } else if (!overflowStream) {
      overflowStream = "stdout";
      void beginTermination("capture_overflow");
    }
  });
  child.stderr.on("data", (chunk) => {
    stderrBytes += chunk.length;
    if (stderrBytes <= maxCaptureBytes) {
      stderrChunks.push(chunk);
    } else if (!overflowStream) {
      overflowStream = "stderr";
      void beginTermination("capture_overflow");
    }
  });
  child.stdin.on("error", () => {
    // EPIPE is reported by process exit/JSONL validation with stronger evidence.
  });
  child.stdin.end(stdin, "utf8");

  const timer = setTimeout(() => {
    timedOut = true;
    void beginTermination("timeout");
  }, timeoutMs);

  const closed = await new Promise((resolve) => {
    let spawnError = null;
    child.on("error", (error) => {
      spawnError = error;
    });
    child.on("close", (exitCode, signal) => resolve({ exitCode, signal, spawnError }));
  });
  clearTimeout(timer);
  for (const scanTimer of descendantScanTimers) {
    clearTimeout(scanTimer);
  }
  await descendantScanChain;
  let termination = terminationPromise
    ? await terminationPromise
    : { targetPids: [], survivorPids: [] };
  const normalExitOrphans = !terminationPromise
    ? [...knownDescendants].filter(isPidAlive)
    : [];
  if (normalExitOrphans.length > 0) {
    terminationReason = "orphan_after_exit";
    const cleanupResults = [];
    for (const orphanPid of normalExitOrphans) {
      cleanupResults.push(await terminateExactProcessTree(orphanPid));
    }
    termination = {
      targetPids: cleanupResults.flatMap((result) => result.targetPids),
      survivorPids: cleanupResults.flatMap((result) => result.survivorPids),
    };
  }

  return {
    pid,
    startedAt,
    endedAt: new Date().toISOString(),
    durationMs: Date.now() - startedMs,
    exitCode: closed.exitCode,
    signal: closed.signal,
    spawnError: closed.spawnError,
    timedOut,
    overflowStream,
    terminationReason,
    knownDescendantPids: [...knownDescendants],
    normalExitOrphanPids: normalExitOrphans,
    termination,
    stdout: Buffer.concat(stdoutChunks).toString("utf8"),
    stderr: Buffer.concat(stderrChunks).toString("utf8"),
    stdoutBytes,
    stderrBytes,
  };
}

function requireAbsoluteFile(filePath, label) {
  if (!filePath || !path.isAbsolute(filePath)) {
    throw new WorkerError("PATH_NOT_ABSOLUTE", "preflight", `${label} 必须是显式绝对路径`, {
      label,
    });
  }
  let canonicalPath;
  try {
    canonicalPath = fs.realpathSync.native(filePath);
  } catch (error) {
    throw new WorkerError("PATH_NOT_FOUND", "preflight", `${label} 不存在`, {
      label,
      filePath,
      cause: error.message,
    });
  }
  if (!fs.statSync(canonicalPath).isFile()) {
    throw new WorkerError("PATH_NOT_FILE", "preflight", `${label} 不是文件`, {
      label,
      canonicalPath,
    });
  }
  return canonicalPath;
}

function parseJsonl(stdout) {
  const events = [];
  const lines = stdout.split(/\r?\n/u);
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index].trim();
    if (!line) {
      continue;
    }
    try {
      events.push({ line: index + 1, event: JSON.parse(line) });
    } catch (error) {
      throw new WorkerError("STDOUT_JSONL_INVALID", "protocol", "CLI stdout 含非 JSONL 行", {
        line: index + 1,
        cause: error.message,
      });
    }
  }
  return events;
}

function extractFinalAgentMessage(events) {
  const completedTurns = events.filter(({ event }) => event.type === "turn.completed");
  for (const { line, event } of events) {
    if (event.type === "turn.failed") {
      throw new WorkerError("TURN_FAILED", "protocol", "CLI turn.failed", { line });
    }
  }
  if (completedTurns.length !== 1) {
    throw new WorkerError(
      "TURN_COMPLETION_INVALID",
      "protocol",
      "CLI 必须恰好报告一个 turn.completed",
      { count: completedTurns.length },
    );
  }

  const completionLine = completedTurns[0].line;
  const recoverableDiagnostics = [];
  for (const { line, event } of events) {
    const topLevelError = event.type === "error";
    const itemError =
      event.type === "item.completed" && event.item && event.item.type === "error";
    if (!topLevelError && !itemError) {
      continue;
    }
    if (line >= completionLine) {
      throw new WorkerError(
        "TERMINAL_ERROR_EVENT",
        "protocol",
        "turn.completed 之后出现 error 事件",
        { line },
      );
    }
    const message = topLevelError ? event.message : event.item.message;
    recoverableDiagnostics.push({
      line,
      type: topLevelError ? "error" : "item_error",
      messageSha256: sha256Bytes(typeof message === "string" ? message : ""),
    });
  }
  const messages = events.filter(
    ({ line, event }) =>
      line < completionLine &&
      event.type === "item.completed" &&
      event.item &&
      event.item.type === "agent_message" &&
      typeof event.item.text === "string",
  );
  if (messages.length === 0) {
    throw new WorkerError("AGENT_MESSAGE_MISSING", "protocol", "turn.completed 前没有 agent_message", {});
  }
  return {
    text: messages[messages.length - 1].event.item.text,
    threadId:
      events.find(({ event }) => event.type === "thread.started")?.event.thread_id || null,
    agentMessageCount: messages.length,
    recoverableDiagnostics,
  };
}

function exactKeys(value, requiredKeys, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new WorkerError("RESULT_SCHEMA_INVALID", "closure", `${label} 必须是对象`, { label });
  }
  const actual = Object.keys(value).sort();
  const expected = [...requiredKeys].sort();
  if (JSON.stringify(actual) !== JSON.stringify(expected)) {
    throw new WorkerError("RESULT_SCHEMA_INVALID", "closure", `${label} 字段不闭合`, {
      label,
      actual,
      expected,
    });
  }
}

function validateCapabilityResult(value, expected) {
  exactKeys(
    value,
    ["schema", "batchId", "inputDigest", "promptDigest", "runRole", "imageProbe", "results"],
    "result",
  );
  for (const [field, expectedValue] of [
    ["schema", RESULT_SCHEMA],
    ["batchId", expected.fixture.batchId],
    ["inputDigest", expected.inputDigest],
    ["promptDigest", expected.promptDigest],
    ["runRole", expected.runRole],
  ]) {
    if (value[field] !== expectedValue) {
      throw new WorkerError("RESULT_CLOSURE_MISMATCH", "closure", `${field} 与 controller 闭包不一致`, {
        field,
        expected: expectedValue,
        actual: value[field],
      });
    }
  }

  exactKeys(value.imageProbe, ["imageId", "classification"], "imageProbe");
  if (value.imageProbe.imageId !== expected.fixture.imageProbe.imageId) {
    throw new WorkerError("RESULT_CLOSURE_MISMATCH", "closure", "imageId 不匹配", {});
  }
  if (!expected.fixture.imageProbe.allowedClassifications.includes(value.imageProbe.classification)) {
    throw new WorkerError("RESULT_VALUE_INVALID", "closure", "图片分类不在 controller 白名单", {
      actual: value.imageProbe.classification,
    });
  }

  if (!Array.isArray(value.results) || value.results.length !== expected.fixture.tasks.length) {
    throw new WorkerError("RESULT_SCHEMA_INVALID", "closure", "results 数量不闭合", {
      expected: expected.fixture.tasks.length,
      actual: Array.isArray(value.results) ? value.results.length : null,
    });
  }
  const tasks = new Map(expected.fixture.tasks.map((task) => [task.taskId, task]));
  const seen = new Set();
  for (const row of value.results) {
    exactKeys(row, ["taskId", "selectedCandidateId", "frame", "cropBox"], "results[]");
    const task = tasks.get(row.taskId);
    if (!task || seen.has(row.taskId)) {
      throw new WorkerError("RESULT_TASK_ID_INVALID", "closure", "taskId 未知或重复", {
        taskId: row.taskId,
      });
    }
    seen.add(row.taskId);
    const candidate = task.candidates.find((item) => item.candidateId === row.selectedCandidateId);
    if (!candidate) {
      throw new WorkerError("RESULT_CANDIDATE_INVALID", "closure", "候选 ID 不在 controller 白名单", {
        taskId: row.taskId,
        selectedCandidateId: row.selectedCandidateId,
      });
    }
    if (candidate.token !== task.signal) {
      throw new WorkerError("RESULT_SELECTION_INCORRECT", "closure", "fixture 候选选择不正确", {
        taskId: row.taskId,
        selectedCandidateId: row.selectedCandidateId,
      });
    }
    if (row.frame !== 0) {
      throw new WorkerError("RESULT_VALUE_INVALID", "closure", "capability fixture 的 frame 必须为 0", {
        taskId: row.taskId,
      });
    }
    if (
      !Array.isArray(row.cropBox) ||
      row.cropBox.length !== 4 ||
      row.cropBox.some((number) => typeof number !== "number" || !Number.isFinite(number)) ||
      row.cropBox.some((number, index) => number !== [0, 0, 1, 1][index])
    ) {
      throw new WorkerError("RESULT_VALUE_INVALID", "closure", "capability fixture 的 cropBox 必须为 [0,0,1,1]", {
        taskId: row.taskId,
      });
    }
  }

  return {
    ...value,
    results: [...value.results].sort((left, right) => left.taskId.localeCompare(right.taskId)),
  };
}

function validateFixture(fixture) {
  exactKeys(fixture, ["schema", "batchId", "imageProbe", "tasks"], "fixture");
  if (fixture.schema !== "cf7.portrait-worker-capability-input.v1") {
    throw new WorkerError("FIXTURE_INVALID", "preflight", "fixture schema 不受支持", {});
  }
  exactKeys(fixture.imageProbe, ["imageId", "relativePath", "allowedClassifications"], "fixture.imageProbe");
  if (!Array.isArray(fixture.tasks) || fixture.tasks.length < 10 || fixture.tasks.length > 20) {
    throw new WorkerError("FIXTURE_INVALID", "preflight", "fixture tasks 必须为 10–20 项", {});
  }
  const ids = new Set();
  for (const task of fixture.tasks) {
    exactKeys(task, ["taskId", "signal", "candidates"], "fixture.tasks[]");
    if (ids.has(task.taskId) || !Array.isArray(task.candidates) || task.candidates.length < 2) {
      throw new WorkerError("FIXTURE_INVALID", "preflight", "fixture taskId 重复或候选不足", {
        taskId: task.taskId,
      });
    }
    ids.add(task.taskId);
    const matches = task.candidates.filter((candidate) => candidate.token === task.signal);
    if (matches.length !== 1) {
      throw new WorkerError("FIXTURE_INVALID", "preflight", "每项必须恰有一个 token 命中 signal", {
        taskId: task.taskId,
      });
    }
  }
}

function createCapabilityPrompt({ fixture, imageSha256, runRole }) {
  const inputEnvelope = {
    fixture,
    image: {
      imageId: fixture.imageProbe.imageId,
      relativePath: fixture.imageProbe.relativePath,
      sha256: imageSha256,
    },
  };
  const inputDigest = sha256Bytes(stableStringify(inputEnvelope));
  const promptBody = [
    "You are a capability-test worker. Do not use tools and do not modify files.",
    `Run role: ${runRole}.`,
    runRole === "independent_review"
      ? "Independently recompute every choice; no proposal result is supplied or trusted."
      : "Produce the first independent proposal from the supplied fixture.",
    "Inspect the attached image and choose exactly one allowed image classification.",
    "For every task, choose the candidate whose token exactly equals signal.",
    "Return every task exactly once. Use frame 0 and cropBox [0,0,1,1].",
    "Return only the JSON object required by the output schema.",
    `Canonical input: ${stableStringify(inputEnvelope)}`,
  ].join("\n");
  const promptDigest = sha256Bytes(promptBody);
  const prompt = [
    promptBody,
    "Echo these controller-owned closure fields exactly:",
    `schema=${RESULT_SCHEMA}`,
    `batchId=${fixture.batchId}`,
    `inputDigest=${inputDigest}`,
    `promptDigest=${promptDigest}`,
    `runRole=${runRole}`,
  ].join("\n");
  return {
    inputDigest,
    promptDigest,
    transmittedPromptSha256: sha256Bytes(prompt),
    prompt,
  };
}

function publicError(error) {
  if (error instanceof WorkerError) {
    return {
      code: error.code,
      phase: error.phase,
      message: error.message,
      details: error.details,
    };
  }
  return {
    code: "UNEXPECTED_ERROR",
    phase: "internal",
    message: error && error.message ? error.message : String(error),
    details: {},
  };
}

function classifyNonzeroExit(capture) {
  const diagnostic = `${capture.stderr}\n${capture.stdout}`;
  if (/unauthorized|authentication|login required|status[=: ]+401/iu.test(diagnostic)) {
    return "AUTHENTICATION_FAILED";
  }
  if (/model.{0,80}(not available|not supported|not found|unsupported|invalid)/iu.test(diagnostic)) {
    return "MODEL_UNAVAILABLE";
  }
  return "PROCESS_EXIT_NONZERO";
}

const RETRIABLE_CODES = new Set([
  "PROCESS_TIMEOUT",
  "PROCESS_EXIT_NONZERO",
  "STDOUT_JSONL_INVALID",
  "TURN_FAILED",
  "TERMINAL_ERROR_EVENT",
  "TURN_COMPLETION_INVALID",
  "AGENT_MESSAGE_MISSING",
  "RESULT_JSON_INVALID",
  "RESULT_SCHEMA_INVALID",
  "RESULT_CLOSURE_MISMATCH",
  "RESULT_TASK_ID_INVALID",
  "RESULT_CANDIDATE_INVALID",
  "RESULT_SELECTION_INCORRECT",
  "RESULT_VALUE_INVALID",
]);

class CodexCliLunaWorker {
  constructor(options) {
    this.executablePath = requireAbsoluteFile(options.executablePath, "Codex CLI");
    this.executableArgs = Array.isArray(options.executableArgs) ? [...options.executableArgs] : [];
    this.environment = { ...process.env, ...(options.environment || {}) };
    this.model = options.model || DEFAULT_MODEL;
    this.reasoningEffort = options.reasoningEffort || DEFAULT_EFFORT;
    this.probeEvidence = null;
  }

  commandArgs(args) {
    return [...this.executableArgs, ...args];
  }

  async probe(timeoutMs = 15_000) {
    const executableSha256 = sha256File(this.executablePath);
    const version = await spawnCaptured({
      command: this.executablePath,
      args: this.commandArgs(["--version"]),
      cwd: path.dirname(this.executablePath),
      env: this.environment,
      stdin: "",
      timeoutMs,
    });
    if (version.timedOut || version.exitCode !== 0 || !version.stdout.trim()) {
      throw new WorkerError("CLI_VERSION_PROBE_FAILED", "probe", "Codex CLI 版本探针失败", {
        exitCode: version.exitCode,
        timedOut: version.timedOut,
      });
    }
    const help = await spawnCaptured({
      command: this.executablePath,
      args: this.commandArgs(["exec", "--help"]),
      cwd: path.dirname(this.executablePath),
      env: this.environment,
      stdin: "",
      timeoutMs,
    });
    if (help.timedOut || help.exitCode !== 0) {
      throw new WorkerError("CLI_HELP_PROBE_FAILED", "probe", "Codex CLI exec --help 探针失败", {
        exitCode: help.exitCode,
        timedOut: help.timedOut,
      });
    }
    const requiredFlags = [
      "--ephemeral",
      "--ignore-user-config",
      "--ignore-rules",
      "--model",
      "--config",
      "--sandbox",
      "--cd",
      "--skip-git-repo-check",
      "--image",
      "--output-schema",
      "--json",
    ];
    const missingFlags = requiredFlags.filter((flag) => !help.stdout.includes(flag));
    if (missingFlags.length > 0) {
      throw new WorkerError("CLI_CAPABILITY_MISSING", "probe", "Codex CLI 缺少 P1 所需参数", {
        missingFlags,
      });
    }
    const evidence = {
      executablePath: this.executablePath,
      executableSha256,
      executableVersion: version.stdout.trim().split(/\r?\n/u)[0],
      helpSha256: sha256Bytes(help.stdout),
      requiredFlags,
    };
    evidence.capabilityProbeDigest = sha256Bytes(stableStringify(evidence));
    this.probeEvidence = evidence;
    return evidence;
  }

  async runAttempt(options, attemptNumber) {
    if (!this.probeEvidence) {
      throw new WorkerError("CLI_NOT_PROBED", "preflight", "运行前必须先完成 CLI capability probe", {});
    }
    validateFixture(options.fixture);
    const imagePath = requireAbsoluteFile(options.imagePath, "capability image");
    const outputSchemaPath = requireAbsoluteFile(options.outputSchemaPath, "output schema");
    const imageSha256 = sha256File(imagePath);
    const prompt = createCapabilityPrompt({
      fixture: options.fixture,
      imageSha256,
      runRole: options.runRole,
    });
    const args = [
      "exec",
      "--ephemeral",
      "--ignore-user-config",
      "--ignore-rules",
      "--model",
      this.model,
      "--config",
      `model_reasoning_effort=${JSON.stringify(this.reasoningEffort)}`,
      "--config",
      'approval_policy="never"',
      "--sandbox",
      "read-only",
      "--cd",
      options.cwd,
      "--skip-git-repo-check",
      "--image",
      imagePath,
      "--output-schema",
      outputSchemaPath,
      "--json",
      "-",
    ];
    const capture = await spawnCaptured({
      command: this.executablePath,
      args: this.commandArgs(args),
      cwd: options.cwd,
      env: this.environment,
      stdin: prompt.prompt,
      timeoutMs: options.timeoutMs,
    });
    const evidence = {
      attemptNumber,
      pid: capture.pid,
      startedAt: capture.startedAt,
      endedAt: capture.endedAt,
      durationMs: capture.durationMs,
      exitCode: capture.exitCode,
      signal: capture.signal,
      timedOut: capture.timedOut,
      terminationReason: capture.terminationReason,
      observedDescendantPids: capture.knownDescendantPids,
      normalExitOrphanPids: capture.normalExitOrphanPids,
      terminatedTreePids: capture.termination.targetPids,
      survivorPids: capture.termination.survivorPids,
      modelRequested: this.model,
      reasoningEffort: this.reasoningEffort,
      inputDigest: prompt.inputDigest,
      imageSha256,
      promptDigest: prompt.promptDigest,
      transmittedPromptSha256: prompt.transmittedPromptSha256,
      outputSchemaSha256: sha256File(outputSchemaPath),
      stdoutSha256: sha256Bytes(capture.stdout),
      stderrSha256: sha256Bytes(capture.stderr),
      stdoutBytes: capture.stdoutBytes,
      stderrBytes: capture.stderrBytes,
    };
    const artifact = { stdout: capture.stdout, stderr: capture.stderr };
    const fail = (code, phase, message, details = {}) => {
      throw new WorkerError(code, phase, message, {
        ...details,
        attempt: { evidence, artifact },
      });
    };

    if (capture.spawnError) {
      fail("PROCESS_SPAWN_FAILED", "transport", "Codex CLI 进程启动失败", {
        cause: capture.spawnError.message,
      });
    }
    if (capture.timedOut) {
      fail("PROCESS_TIMEOUT", "transport", "Codex CLI 运行超时", {});
    }
    if (capture.overflowStream) {
      fail("CAPTURE_OVERFLOW", "transport", "Codex CLI 输出超过有界缓冲", {
        stream: capture.overflowStream,
      });
    }
    if (capture.termination.survivorPids.length > 0) {
      fail("ORPHAN_PROCESS_SURVIVED", "transport", "精确进程树终止后仍有存活 PID", {
        survivorPids: capture.termination.survivorPids,
      });
    }
    if (capture.normalExitOrphanPids.length > 0) {
      fail("ORPHAN_PROCESS_OBSERVED", "transport", "CLI 主进程退出后留下子进程", {
        orphanPids: capture.normalExitOrphanPids,
      });
    }
    if (capture.exitCode !== 0) {
      fail(classifyNonzeroExit(capture), "transport", "Codex CLI 非零退出", {
        exitCode: capture.exitCode,
      });
    }

    let events;
    try {
      events = parseJsonl(capture.stdout);
    } catch (error) {
      if (error instanceof WorkerError) {
        fail(error.code, error.phase, error.message, error.details);
      }
      throw error;
    }
    let finalMessage;
    try {
      finalMessage = extractFinalAgentMessage(events);
    } catch (error) {
      if (error instanceof WorkerError) {
        fail(error.code, error.phase, error.message, error.details);
      }
      throw error;
    }
    let parsedResult;
    try {
      parsedResult = JSON.parse(finalMessage.text);
    } catch (error) {
      fail("RESULT_JSON_INVALID", "closure", "最终 agent_message 不是 JSON 对象", {
        cause: error.message,
      });
    }
    let result;
    try {
      result = validateCapabilityResult(parsedResult, {
        fixture: options.fixture,
        inputDigest: prompt.inputDigest,
        promptDigest: prompt.promptDigest,
        runRole: options.runRole,
      });
    } catch (error) {
      if (error instanceof WorkerError) {
        fail(error.code, error.phase, error.message, error.details);
      }
      throw error;
    }
    evidence.threadId = finalMessage.threadId;
    evidence.agentMessageCount = finalMessage.agentMessageCount;
    evidence.recoverableDiagnostics = finalMessage.recoverableDiagnostics;
    evidence.recoverableDiagnosticDigest = sha256Bytes(
      stableStringify(finalMessage.recoverableDiagnostics),
    );
    evidence.resultSha256 = sha256Bytes(stableStringify(result));
    evidence.status = "accepted";
    return { evidence, artifact, result };
  }

  async runWithRetry(options) {
    const maxRetries = options.maxRetries ?? 1;
    if (!Number.isInteger(maxRetries) || maxRetries < 0 || maxRetries > 1) {
      throw new WorkerError("RETRY_POLICY_INVALID", "preflight", "P1 只允许 0 或 1 次重试", {
        maxRetries,
      });
    }
    const attempts = [];
    const artifacts = [];
    const seenPids = new Set();
    for (let attemptNumber = 1; attemptNumber <= maxRetries + 1; attemptNumber += 1) {
      try {
        const attempt = await this.runAttempt(options, attemptNumber);
        if (seenPids.has(attempt.evidence.pid)) {
          throw new WorkerError("PROCESS_ID_REUSED", "transport", "重试未取得新的进程身份", {
            attempt: { evidence: attempt.evidence, artifact: attempt.artifact },
          });
        }
        attempts.push(attempt.evidence);
        artifacts.push(attempt.artifact);
        return {
          run: {
            role: options.runRole,
            status: "accepted",
            attempts,
            acceptedAttempt: attemptNumber,
            result: attempt.result,
          },
          artifacts,
        };
      } catch (error) {
        const normalized = publicError(error);
        const attempt = error instanceof WorkerError ? error.details.attempt : null;
        if (attempt) {
          if (seenPids.has(attempt.evidence.pid)) {
            throw new WorkerError("PROCESS_ID_REUSED", "transport", "重试未取得新的进程身份", {
              attempts,
            });
          }
          seenPids.add(attempt.evidence.pid);
          attempts.push({
            ...attempt.evidence,
            status: "rejected",
            error: {
              code: normalized.code,
              phase: normalized.phase,
              message: normalized.message,
            },
          });
          artifacts.push(attempt.artifact);
        }
        const canRetry = attemptNumber <= maxRetries && RETRIABLE_CODES.has(normalized.code);
        if (!canRetry) {
          throw new WorkerError("RUN_RETRIES_EXHAUSTED", normalized.phase, normalized.message, {
            role: options.runRole,
            terminalError: {
              code: normalized.code,
              phase: normalized.phase,
              message: normalized.message,
            },
            attempts,
            artifacts,
          });
        }
      }
    }
    throw new WorkerError("RUN_RETRIES_EXHAUSTED", "internal", "不可达的重试终态", {
      role: options.runRole,
      attempts,
    });
  }
}

module.exports = {
  CodexCliLunaWorker,
  RESULT_SCHEMA,
  WorkerError,
  createCapabilityPrompt,
  extractFinalAgentMessage,
  isPidAlive,
  parseJsonl,
  publicError,
  requireAbsoluteFile,
  sha256Bytes,
  sha256File,
  spawnCaptured,
  stableStringify,
  validateCapabilityResult,
  validateFixture,
};
