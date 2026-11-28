"use strict";

// Invoked only by the executor that owns the Default desktop and the isolated save attempt.
const { spawn } = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const readline = require("node:readline");
const { performance } = require("node:perf_hooks");
const { parseArgs } = require("node:util");
const { setTimeout: delay } = require("node:timers/promises");
const launcher = require("../workbench-live-e2e/lib/launcher-observation");
const runtime = require("../lib/runtime-process-identity");
const legacy = require("../lib/legacy-http-client");

const movementCommand = "#eval:hero._x";
const snapshotCommand = "#eval:[root.GameInput.snapshot.systemFrame,root.GameInput.snapshot.inputFrameSeq," +
  "root.GameInput.snapshot.keyboardEpoch,root.GameInput.snapshot.words[2],hero._x]";
const holdMs = 120;
const perPulseMs = 650;

async function sample(context, observer) {
  const requestedMs = performance.now();
  const response = await fetch(`http://localhost:${context.httpPort}/console`, {
    method: "POST",
    headers: { "Content-Type": "application/json", ...legacy.authorizationHeadersFor(context, "/console") },
    body: JSON.stringify({ command: observer === "movement" ? movementCommand : snapshotCommand }),
    signal: AbortSignal.timeout(1200),
  });
  const body = await response.json();
  const returnedMs = performance.now();
  const valueBody = body.data ?? body;
  const text = valueBody.result ?? valueBody.value;
  const payload = typeof text === "string" ? / = ([^\r\n]*)\s*$/.exec(text)?.[1] ?? text : text;
  if (observer === "movement") {
    const value = String(payload);
    if (!response.ok || body.success === false || valueBody.success === false ||
        !/^[-+]?\d+(?:\.\d+)?$/.test(value) || !Number.isFinite(Number(value))) {
      throw new Error("The existing read-only hero._x observation was not available.");
    }
    return { requestedMs, returnedMs, x: Number(value) };
  }
  const values = Array.isArray(payload) ? payload : String(payload).split(",");
  const frame = Number(values[0]);
  const inputFrame = Number(values[1]);
  const keyEpoch = Number(values[2]);
  const word = Number(values[3]);
  const x = Number(values[4]);
  if (!response.ok || body.success === false || valueBody.success === false || values.length !== 5 || !Number.isInteger(word) ||
      !Number.isInteger(frame) || !Number.isInteger(inputFrame) || !Number.isInteger(keyEpoch) || !Number.isFinite(x)) {
    throw new Error("The exact AS2 frame/key/hero snapshot was not available.");
  }
  return { requestedMs, returnedMs, frame, inputFrame, keyEpoch, key: (word & 16) !== 0, x };
}

async function openDriver(foreground, pid) {
  const child = spawn("python", ["-B", path.join(__dirname, "latency_key.py"), foreground, String(pid), String(holdMs)], {
    windowsHide: true, stdio: ["pipe", "pipe", "pipe"],
  });
  let error = "";
  child.stderr.setEncoding("utf8").on("data", chunk => { error += chunk; });
  child.on("error", failure => { error += failure.message; });
  child.stdin.on("error", failure => { error += failure.message; });
  const iterator = readline.createInterface({ input: child.stdout })[Symbol.asyncIterator]();
  async function receive() {
    const result = await iterator.next();
    if (result.done) throw new Error(error || "The guarded keyboard driver closed unexpectedly.");
    return { ...JSON.parse(result.value), receivedMs: performance.now() };
  }
  const ready = await receive();
  if (ready.event !== "ready") {
    child.stdin.end();
    throw new Error("The keyboard driver did not acknowledge readiness.");
  }
  return {
    pulse(mode = "pulse") {
      const requestedMs = performance.now();
      const vk = mode === "recenter" ? 65 : 68;
      child.stdin.write(mode + "\n");
      const completed = (async () => {
        const edges = [];
        try {
          edges.push(await receive());
          edges.push(await receive());
          const correct = edges[0].edge === "down" && edges[1].edge === "up" && edges[0].pid === pid &&
            edges.every(edge => edge.vk === vk) &&
            edges[0].foreground === Number(foreground) && edges[1].foreground === edges[0].foreground;
          return { requestedMs, edges, exit: correct ? 0 : 1,
            ...(!correct && { error: "The keyboard receipt or foreground changed during the pulse." }) };
        } catch (failure) {
          return { requestedMs, edges, exit: 1, error: failure.message };
        }
      })();
      return { requestedMs, completed };
    },
    close() { child.stdin.end(); },
  };
}

function responseInterval(before, observations, input, predicate) {
  const positive = observations.findIndex(observation => predicate(observation, before));
  if (positive < 0 || input.edges.length !== 2 || input.exit !== 0) return null;
  const latestPossibleEdge = input.edges[0].receivedMs;
  const negative = positive === 0 ? before : observations[positive - 1];
  // The request/response timestamps bound the in-game observation. The driver acknowledgement bounds SendInput.
  return { lowerMs: Math.max(0, negative.requestedMs - latestPossibleEdge),
    upperMs: observations[positive].returnedMs - input.requestedMs,
    firstPositiveFrame: observations[positive].frame, firstPositiveInputFrame: observations[positive].inputFrame };
}

async function main() {
  const { values } = parseArgs({ options: {
    "project-root": { type: "string", default: path.join(__dirname, "..", "..") },
    "candidate-root": { type: "string" }, slot: { type: "string" }, "attempt-id": { type: "string" },
    foreground: { type: "string" }, scene: { type: "string" }, output: { type: "string" },
    role: { type: "string" }, samples: { type: "string", default: "8" },
    observer: { type: "string", default: "movement" },
  } });
  const count = Number(values.samples);
  if (!values["candidate-root"] || !values.slot?.startsWith("cf7_agent_") || !values["attempt-id"] ||
      !/^(?:0x[\da-f]+|[1-9]\d*)$/i.test(values.foreground || "") || !values.scene || !values.output ||
      !["baseline", "candidate"].includes(values.role) || !["movement", "latched-movement"].includes(values.observer) ||
      !Number.isInteger(count) || count < 1 || count > 25) {
    throw new Error("Use --candidate-root --slot --attempt-id --foreground --scene --role --output [--samples].");
  }
  if (fs.existsSync(values.output)) throw new Error("Use a new output file.");
  const root = path.resolve(values["project-root"]);
  const expected = runtime.resolveExpectedRuntimeIdentity(root, path.resolve(values["candidate-root"]));
  const session = launcher.openAuthenticatedLegacyHttpSession({ root });
  const observed = session.verifyRuntimeIdentity(expected);
  launcher.assertRuntimeReadyStatus(await session.agentControl("status"), values.slot, values["attempt-id"]);
  const context = legacy.readExactLauncherHttpContext(root, { expectedHttpPort: session.evidence.httpPort });
  if (context.pid !== observed.pid) throw new Error("The active console moved to another Core process.");
  const beforeLog = launcher.createTerminalLogBoundary(await session.readTerminalLogSnapshot(2000));
  const report = { schema: "cf7-input-authority-ordinary-latency.v1", startedUtc: new Date().toISOString(),
    role: values.role, observed, scene: values.scene, slot: values.slot, attemptId: values["attempt-id"],
    stimulus: "os-sendinput", observer: values.observer, vk: 68, holdMs, perPulseMs, plannedSamples: count,
    conditioningPulses: 1, recenterVk: 65, recenterHoldMs: holdMs, originTolerance: 80, samples: [], errors: [] };

  let driver;
  try {
    driver = await openDriver(values.foreground, observed.pid);
    for (let i = 0; i <= count; i++) {
      const idle = await sample(context, values.observer);
      await delay(70);
      const before = await sample(context, values.observer);
      if (idle.key || before.key || Math.abs(idle.x - before.x) > 0.1) {
        throw new Error("The no-key stationary control did not settle before the next paired stimulus.");
      }
      if (i === 0) report.originX = before.x;
      if (Math.abs(before.x - report.originX) > report.originTolerance) {
        throw new Error("The hero drifted outside the prepared movement area; no further pulse was sent.");
      }
      const output = { id: i, idle, before, observations: [] };
      if (i === 0) report.conditioningControl = output;
      else report.samples.push(output);
      const edge = driver.pulse();
      try {
        do {
          output.observations.push(await sample(context, values.observer));
          await delay(8);
        } while (performance.now() < edge.requestedMs + perPulseMs);
      } finally {
        output.injection = await edge.completed;
      }
      if (output.injection.exit !== 0) throw new Error(output.injection.error || "The guarded OS pulse did not complete.");
      if (output.observations.some(row => row.keyEpoch !== before.keyEpoch)) {
        output.invalidReason = "Keyboard epoch changed during controlled stimulus.";
      } else {
        output.osToLatch = values.observer === "latched-movement" ? responseInterval(before, output.observations, output.injection,
          (row, baseline) => row.key && row.inputFrame > baseline.inputFrame) : null;
        output.osToMovement = responseInterval(before, output.observations, output.injection,
          (row, baseline) => (values.observer === "movement" || row.frame > baseline.frame) && row.x - baseline.x > 0.1);
      }
      if (i === 0 && output.osToMovement == null) throw new Error("The warm-up pulse found no observable movement space.");
      output.recenter = await driver.pulse("recenter").completed;
      if (output.recenter.exit !== 0) throw new Error(output.recenter.error || "The guarded room reset did not complete.");
      await delay(250);
    }
  } catch (error) {
    report.errors.push(error.message);
  } finally {
    driver?.close();
    try {
      const final = session.verifyRuntimeIdentity(expected);
      if (final.pid !== observed.pid) throw new Error("Runtime changed during the capture window.");
      launcher.assertRuntimeReadyStatus(await session.agentControl("status"), values.slot, values["attempt-id"]);
      report.sessionStayedBound = true;
    } catch (error) {
      report.sessionStayedBound = false;
      report.errors.push(error.message);
    }
    try {
      report.presentationContext = launcher.recordsAfterTerminalBoundary(beforeLog, await session.readTerminalLogSnapshot(2000))
        .filter(row => /world_compositor_(?:identity|frame)|world_bullet_source|render_sample/i.test(row.line ?? row.text ?? ""));
    } catch (error) {
      report.presentationContextUnavailable = error.message;
    }
    report.presentationLatency = null;
    report.completedUtc = new Date().toISOString();
    fs.writeFileSync(values.output, JSON.stringify(report, null, 2) + "\n", { flag: "wx" });
  }
  if (report.errors.length) process.exitCode = 1;
}

main().catch(error => { console.error(error.message); process.exitCode = 1; });
