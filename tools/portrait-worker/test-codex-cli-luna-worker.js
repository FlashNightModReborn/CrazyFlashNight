#!/usr/bin/env node
"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { spawnSync } = require("node:child_process");
const {
  CodexCliLunaWorker,
  WorkerError,
  createCapabilityPrompt,
  extractFinalAgentMessage,
  isPidAlive,
  listDescendantPids,
  parseJsonl,
  sha256Bytes,
  spawnCaptured,
  validateCapabilityResult,
} = require("./lib/codex-cli-luna-worker");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const PILOT_PATH = path.join(__dirname, "run-capability-pilot.js");
const FIXTURE = JSON.parse(
  fs.readFileSync(path.join(__dirname, "fixtures", "capability-tasks.json"), "utf8"),
);
const SCHEMA_PATH = path.join(__dirname, "schemas", "capability-result.schema.json");
const IMAGE_PATH = path.join(REPO_ROOT, FIXTURE.imageProbe.relativePath);

const FAKE_CLI_SOURCE = String.raw`
"use strict";
const fs = require("node:fs");
const { spawn } = require("node:child_process");
const args = process.argv.slice(2);
if (args.includes("--version")) {
  process.stdout.write("codex-cli fake-p1\n");
  process.exit(0);
}
if (args[0] === "exec" && args.includes("--help")) {
  process.stdout.write("--ephemeral --ignore-user-config --ignore-rules --model --config --sandbox --cd --skip-git-repo-check --image --output-schema --json\n");
  process.exit(0);
}
let prompt = "";
process.stdin.setEncoding("utf8");
process.stdin.on("data", (chunk) => { prompt += chunk; });
process.stdin.on("end", () => {
  const mode = process.env.FAKE_MODE || "success";
  if (process.env.PID_LOG) {
    fs.appendFileSync(process.env.PID_LOG, String(process.pid) + "\n");
  }
  if (mode === "timeout") {
    const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
      stdio: "ignore",
      windowsHide: true,
    });
    fs.writeFileSync(process.env.CHILD_PID_FILE, String(child.pid));
    setInterval(() => {}, 1000);
    return;
  }
  if (mode === "late_orphan") {
    // 活过 250ms/2000ms 两个定时扫描窗口后才 fork 存活孙进程并正常退出，
    // 只有 close 之后的最终子孙扫描能捕获它。Windows 上非 detached 子进程会随父进程
    // 退出被回收，必须用 detached 才能模拟“父退孙存”的孤儿（POSIX 两种都存活）。
    setTimeout(() => {
      const child = spawn(process.execPath, ["-e", "setInterval(() => {}, 1000)"], {
        stdio: "ignore",
        windowsHide: true,
        detached: true,
      });
      fs.writeFileSync(process.env.CHILD_PID_FILE, String(child.pid));
      process.exit(0);
    }, 2_400);
    return;
  }
  if (mode === "retry_once") {
    const count = fs.existsSync(process.env.COUNTER_FILE)
      ? Number(fs.readFileSync(process.env.COUNTER_FILE, "utf8"))
      : 0;
    fs.writeFileSync(process.env.COUNTER_FILE, String(count + 1));
    if (count === 0) {
      process.stdout.write("not-jsonl\n");
      return;
    }
  }
  const canonicalLine = prompt.split(/\r?\n/u).find((line) => line.startsWith("Canonical input: "));
  const envelope = JSON.parse(canonicalLine.slice("Canonical input: ".length));
  const field = (name) => {
    const line = prompt.split(/\r?\n/u).find((item) => item.startsWith(name + "="));
    return line.slice(name.length + 1);
  };
  const result = {
    schema: field("schema"),
    batchId: field("batchId"),
    inputDigest: field("inputDigest"),
    promptDigest: field("promptDigest"),
    runRole: field("runRole"),
    imageProbe: {
      imageId: envelope.fixture.imageProbe.imageId,
      classification: envelope.fixture.imageProbe.allowedClassifications[0],
    },
    results: envelope.fixture.tasks.map((task) => ({
      taskId: task.taskId,
      selectedCandidateId: task.candidates.find((candidate) => candidate.token === task.signal).candidateId,
      frame: 0,
      cropBox: [0, 0, 1, 1],
    })),
  };
  if (mode === "bad_candidate") {
    result.results[0].selectedCandidateId = "controller-never-offered-this";
  }
  if (mode === "wrong_selection") {
    // 选中的候选在白名单内但 token 不命中 signal：语义答错，不是格式失败。
    const wrongTask = envelope.fixture.tasks[0];
    result.results[0].selectedCandidateId = wrongTask.candidates.find(
      (candidate) => candidate.token !== wrongTask.signal,
    ).candidateId;
  }
  const emit = (event) => process.stdout.write(JSON.stringify(event) + "\n");
  emit({ type: "thread.started", thread_id: "fake-thread-" + process.pid });
  emit({ type: "item.completed", item: { type: "agent_message", text: JSON.stringify({ intermediate: true }) } });
  if (mode === "recoverable_transport") {
    emit({ type: "error", message: "synthetic reconnect" });
    emit({ type: "item.completed", item: { type: "error", message: "synthetic HTTPS fallback" } });
  }
  if (mode === "turn_failed") {
    emit({ type: "turn.failed", error: { message: "synthetic failure" } });
    return;
  }
  emit({ type: "item.completed", item: { type: "agent_message", text: JSON.stringify(result) } });
  emit({ type: "turn.completed", usage: {} });
});
`;

function makeHarness(mode = "success") {
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-portrait-worker-"));
  const fakeCliPath = path.join(temporaryDirectory, "fake-codex.js");
  const pidLog = path.join(temporaryDirectory, "pids.log");
  const counterFile = path.join(temporaryDirectory, "counter.txt");
  const childPidFile = path.join(temporaryDirectory, "child.pid");
  fs.writeFileSync(fakeCliPath, FAKE_CLI_SOURCE, "utf8");
  const worker = new CodexCliLunaWorker({
    executablePath: process.execPath,
    executableArgs: [fakeCliPath],
    environment: {
      FAKE_MODE: mode,
      PID_LOG: pidLog,
      COUNTER_FILE: counterFile,
      CHILD_PID_FILE: childPidFile,
    },
  });
  return {
    temporaryDirectory,
    fakeCliPath,
    pidLog,
    counterFile,
    childPidFile,
    worker,
    options: {
      fixture: FIXTURE,
      imagePath: IMAGE_PATH,
      outputSchemaPath: SCHEMA_PATH,
      runRole: "proposal",
      cwd: temporaryDirectory,
      timeoutMs: 5_000,
      maxRetries: 0,
    },
  };
}

function disposeHarness(harness) {
  fs.rmSync(harness.temporaryDirectory, { recursive: true, force: true });
}

test("JSONL closure uses the last agent_message before turn.completed", () => {
  const stdout = [
    JSON.stringify({ type: "thread.started", thread_id: "thread-1" }),
    JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: "first" } }),
    JSON.stringify({ type: "item.completed", item: { type: "agent_message", text: "last" } }),
    JSON.stringify({ type: "turn.completed", usage: {} }),
    "",
  ].join("\n");
  const result = extractFinalAgentMessage(parseJsonl(stdout));
  assert.equal(result.text, "last");
  assert.equal(result.agentMessageCount, 2);
  assert.equal(result.threadId, "thread-1");
});

test("controller rejects unknown candidates even when JSON shape is valid", () => {
  const imageSha256 = sha256Bytes(fs.readFileSync(IMAGE_PATH));
  const prompt = createCapabilityPrompt({
    fixture: FIXTURE,
    imageSha256,
    runRole: "proposal",
  });
  const value = {
    schema: "cf7.portrait-worker-capability-result.v1",
    batchId: FIXTURE.batchId,
    inputDigest: prompt.inputDigest,
    promptDigest: prompt.promptDigest,
    runRole: "proposal",
    imageProbe: {
      imageId: FIXTURE.imageProbe.imageId,
      classification: FIXTURE.imageProbe.allowedClassifications[0],
    },
    results: FIXTURE.tasks.map((task) => ({
      taskId: task.taskId,
      selectedCandidateId: task.candidates.find((candidate) => candidate.token === task.signal).candidateId,
      frame: 0,
      cropBox: [0, 0, 1, 1],
    })),
  };
  value.results[0].selectedCandidateId = "invented";
  assert.throws(
    () =>
      validateCapabilityResult(value, {
        fixture: FIXTURE,
        inputDigest: prompt.inputDigest,
        promptDigest: prompt.promptDigest,
        runRole: "proposal",
      }),
    (error) => error instanceof WorkerError && error.code === "RESULT_CANDIDATE_INVALID",
  );
});

test("static probe and two roles use separate processes with exact closure", async () => {
  const harness = makeHarness();
  try {
    const probe = await harness.worker.probe();
    assert.equal(probe.executableVersion, "codex-cli fake-p1");
    assert.equal(probe.executablePath, fs.realpathSync.native(process.execPath));

    const proposal = await harness.worker.runWithRetry(harness.options);
    const review = await harness.worker.runWithRetry({
      ...harness.options,
      runRole: "independent_review",
    });
    assert.equal(proposal.run.status, "accepted");
    assert.equal(review.run.status, "accepted");
    assert.notEqual(proposal.run.attempts[0].pid, review.run.attempts[0].pid);
    assert.notEqual(proposal.run.attempts[0].promptDigest, review.run.attempts[0].promptDigest);
    assert.equal(proposal.run.attempts[0].agentMessageCount, 2);
    assert.equal(proposal.run.result.results.length, 12);
    assert.equal(proposal.run.attempts[0].descendantScanFailed, false);
    assert.deepEqual(proposal.run.attempts[0].descendantScanFailures, []);
  } finally {
    disposeHarness(harness);
  }
});

test("format failure retries once in a fresh process", async () => {
  const harness = makeHarness("retry_once");
  try {
    await harness.worker.probe();
    const result = await harness.worker.runWithRetry({ ...harness.options, maxRetries: 1 });
    assert.equal(result.run.attempts.length, 2);
    assert.equal(result.run.attempts[0].status, "rejected");
    assert.equal(result.run.attempts[0].error.code, "STDOUT_JSONL_INVALID");
    assert.equal(result.run.attempts[1].status, "accepted");
    assert.notEqual(result.run.attempts[0].pid, result.run.attempts[1].pid);
  } finally {
    disposeHarness(harness);
  }
});

test("recoverable transport diagnostics are hashed when the turn later completes", async () => {
  const harness = makeHarness("recoverable_transport");
  try {
    await harness.worker.probe();
    const result = await harness.worker.runWithRetry(harness.options);
    const attempt = result.run.attempts[0];
    assert.equal(attempt.status, "accepted");
    assert.equal(attempt.recoverableDiagnostics.length, 2);
    assert.match(attempt.recoverableDiagnosticDigest, /^[0-9A-F]{64}$/u);
  } finally {
    disposeHarness(harness);
  }
});

for (const [mode, expectedCode] of [
  ["bad_candidate", "RESULT_CANDIDATE_INVALID"],
  ["turn_failed", "TURN_FAILED"],
]) {
  test(`${mode} fails closed with ${expectedCode}`, async () => {
    const harness = makeHarness(mode);
    try {
      await harness.worker.probe();
      await assert.rejects(
        harness.worker.runWithRetry(harness.options),
        (error) =>
          error instanceof WorkerError &&
          error.code === "RUN_RETRIES_EXHAUSTED" &&
          error.details.terminalError.code === expectedCode,
      );
    } finally {
      disposeHarness(harness);
    }
  });
}

test("timeout terminates the exact child process tree", async () => {
  const harness = makeHarness("timeout");
  try {
    await harness.worker.probe();
    const startedMs = Date.now();
    await assert.rejects(
      harness.worker.runWithRetry({ ...harness.options, timeoutMs: 400 }),
      (error) =>
        error instanceof WorkerError &&
        error.code === "RUN_RETRIES_EXHAUSTED" &&
        error.details.terminalError.code === "PROCESS_TIMEOUT",
    );
    assert.ok(
      Date.now() - startedMs < 15_000,
      "400 ms timeout exceeded the bounded 15 s cleanup envelope",
    );
    const childPid = Number(fs.readFileSync(harness.childPidFile, "utf8"));
    assert.equal(isPidAlive(childPid), false, `child PID ${childPid} survived timeout cleanup`);
  } finally {
    disposeHarness(harness);
  }
});

test("normal exit still catches a grandchild forked after the scheduled scan windows", async () => {
  const harness = makeHarness("late_orphan");
  try {
    await harness.worker.probe();
    let failure = null;
    await assert.rejects(
      harness.worker.runWithRetry({ ...harness.options, maxRetries: 1 }),
      (error) => {
        failure = error;
        return (
          error instanceof WorkerError &&
          error.code === "RUN_RETRIES_EXHAUSTED" &&
          error.details.terminalError.code === "ORPHAN_PROCESS_OBSERVED"
        );
      },
    );
    assert.ok(failure, "late-forked grandchild must fail the orphan gate");
    assert.equal(failure.details.attempts.length, 1, "orphan failures must not be retried");
    const childPid = Number(fs.readFileSync(harness.childPidFile, "utf8"));
    assert.ok(
      failure.details.attempts[0].normalExitOrphanPids.includes(childPid),
      `final post-close scan must observe grandchild PID ${childPid}`,
    );
    assert.equal(isPidAlive(childPid), false, `grandchild PID ${childPid} survived cleanup`);
  } finally {
    disposeHarness(harness);
  }
});

test("descendant scan helper failure throws instead of silently returning []", async () => {
  const failingRunner = async () => ({
    exitCode: 1,
    stdout: "",
    stderr: "synthetic scan failure",
    error: null,
    timedOut: false,
  });
  await assert.rejects(
    listDescendantPids(process.pid, failingRunner),
    (error) => error instanceof WorkerError && error.code === "DESCENDANT_SCAN_FAILED",
  );
});

test("descendant scan failure is recorded on capture evidence instead of staying silent", async () => {
  const capture = await spawnCaptured({
    command: process.execPath,
    args: ["-e", "setTimeout(() => {}, 50)"],
    cwd: os.tmpdir(),
    env: { ...process.env },
    stdin: "",
    timeoutMs: 5_000,
    listDescendants: async () => {
      throw new Error("synthetic scan outage");
    },
  });
  assert.equal(capture.exitCode, 0);
  assert.equal(capture.descendantScanFailed, true);
  assert.equal(capture.descendantScanFailures.length, 1);
  assert.equal(capture.descendantScanFailures[0].phase, "final");
  assert.equal(capture.descendantScanFailures[0].code, "DESCENDANT_SCAN_ERROR");
  assert.match(capture.descendantScanFailures[0].message, /synthetic scan outage/u);
});

test("pilot entry rejects a relative --codex-exe path explicitly", () => {
  const result = spawnSync(
    process.execPath,
    [PILOT_PATH, "--codex-exe", path.join("relative", "codex.exe"), "--probe-only"],
    { encoding: "utf8" },
  );
  assert.equal(result.status, 1, result.stderr);
  const payload = JSON.parse(result.stderr.trim());
  assert.equal(payload.code, "CLI_PATH_NOT_ABSOLUTE");
  assert.match(payload.message, /绝对路径/u);
});

test("pilot entry accepts an absolute --codex-exe path and fails later at file validation", () => {
  const temporaryDirectory = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-pilot-entry-"));
  try {
    const missingExe = path.join(temporaryDirectory, "missing-codex.exe");
    const reportPath = path.join(temporaryDirectory, "report.json");
    const result = spawnSync(
      process.execPath,
      [PILOT_PATH, "--codex-exe", missingExe, "--probe-only", "--output", reportPath],
      { encoding: "utf8" },
    );
    assert.equal(result.status, 1, result.stderr);
    const payload = JSON.parse(result.stderr.trim());
    assert.equal(payload.code, "PATH_NOT_FOUND");
  } finally {
    fs.rmSync(temporaryDirectory, { recursive: true, force: true });
  }
});

test("semantic selection errors are not retried", async () => {
  const harness = makeHarness("wrong_selection");
  try {
    await harness.worker.probe();
    let failure = null;
    await assert.rejects(
      harness.worker.runWithRetry({ ...harness.options, maxRetries: 1 }),
      (error) => {
        failure = error;
        return (
          error instanceof WorkerError &&
          error.code === "RUN_RETRIES_EXHAUSTED" &&
          error.details.terminalError.code === "RESULT_SELECTION_INCORRECT"
        );
      },
    );
    assert.ok(failure, "wrong semantic selection must fail closed");
    assert.equal(
      failure.details.attempts.length,
      1,
      "RESULT_SELECTION_INCORRECT is semantic and must not spawn a retry process",
    );
    assert.equal(failure.details.attempts[0].error.code, "RESULT_SELECTION_INCORRECT");
  } finally {
    disposeHarness(harness);
  }
});
