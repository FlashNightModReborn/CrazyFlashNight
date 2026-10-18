"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const http = require("http");
const path = require("path");
const { assertRuntimeIdentity } = require("../../lib/runtime-process-identity");
const { assertEndpointOwnership, queryWorkerOwnership } = require("./arena-worker-endpoint");

const ID_FIELDS = ["workerId", "sessionEpoch", "assignmentId", "attemptId"];
const RUN_FIELDS = [...ID_FIELDS, "batchId", "manifestHash", "caseId", "caseHash", "runId", "repeatIndex"];
const ROOT_FIELDS = ["projectRoot", "stateRoot", "saveRoot", "outputRoot", "swfOrigin"];
const CONTROL_HEADER = "X-CF7-Automation-Token";
const ACTIONS = new Set(["start", "startBatch", "status", "abort", "result", "shutdown", "faultStopFlash"]);

function safeId(value, label) {
  if (typeof value !== "string" || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(value)) {
    throw new Error(`invalid Worker ${label}`);
  }
  return value;
}

function samePath(left, right) {
  return typeof left === "string" && typeof right === "string"
    && path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function assertNoReparse(candidate) {
  if (typeof candidate !== "string" || !path.isAbsolute(candidate)) throw new Error("Worker roots must be absolute");
  const absolute = path.resolve(candidate);
  let current = path.parse(absolute).root;
  for (const segment of absolute.slice(current.length).split(path.sep).filter(Boolean)) {
    current = path.join(current, segment);
    if (fs.existsSync(current) && fs.lstatSync(current).isSymbolicLink()) {
      throw new Error(`Worker path contains a reparse/symlink entry: ${current}`);
    }
  }
  return absolute;
}

function resolveInside(base, candidate, label) {
  const absolute = assertNoReparse(path.resolve(base, candidate));
  const relative = path.relative(base, absolute);
  if (!relative || relative.startsWith(`..${path.sep}`) || relative === ".." || path.isAbsolute(relative)) {
    throw new Error(`${label} must be strictly inside its Worker root`);
  }
  return absolute;
}

function readJson(filePath, maximumBytes = 1024 * 1024) {
  assertNoReparse(filePath);
  const stat = fs.lstatSync(filePath);
  if (!stat.isFile() || stat.size > maximumBytes) throw new Error("invalid Worker descriptor file");
  return JSON.parse(fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, ""));
}

function normalizePerformance(input) {
  if (input === undefined) return { preset: "performance", mode: "fixed", maxRenderHeight: 180 };
  if (!input || typeof input !== "object" || Array.isArray(input)
      || Object.keys(input).some((key) => !["preset", "mode", "maxRenderHeight"].includes(key))
      || ["preset", "mode", "maxRenderHeight"].some((key) => input[key] === undefined)) {
    throw new Error("Worker performance policy must contain the complete preset/mode/maxRenderHeight tuple");
  }
  const value = { preset: input.preset, mode: input.mode, maxRenderHeight: input.maxRenderHeight };
  if (!["balanced", "performance", "quality"].includes(value.preset) || !["auto", "fixed"].includes(value.mode)
      || (![0, 360, 540, 720, 900, 1080, 1440, 2160].includes(value.maxRenderHeight)
        && !(value.preset === "performance" && value.mode === "fixed" && value.maxRenderHeight === 180))) {
    throw new Error("invalid Worker performance policy value");
  }
  return value;
}

function normalizeFaultInjection(value) {
  if (value === undefined) return false;
  if (typeof value !== "boolean") throw new Error("Worker allowFaultInjection must be boolean");
  return value;
}

function validateFaultRequest(message) {
  if (Object.keys(message).some((key) => !["action", "faultId", ...RUN_FIELDS].includes(key))) {
    throw new Error("Worker faultStopFlash accepts only faultId and the exact run tuple");
  }
  ["faultId", ...ID_FIELDS, "batchId", "caseId", "runId"].forEach((field) => safeId(message[field], field));
  for (const field of ["manifestHash", "caseHash"]) {
    if (typeof message[field] !== "string" || !/^sha256:[a-f0-9]{64}$/.test(message[field])) {
      throw new Error(`invalid Worker fault ${field}`);
    }
  }
  if (!Number.isSafeInteger(message.repeatIndex) || message.repeatIndex < 1) throw new Error("invalid Worker fault repeatIndex");
}

function verifyGitRoot(projectRoot) {
  const result = childProcess.spawnSync("git", ["-C", projectRoot, "rev-parse", "--path-format=absolute",
    "--show-toplevel", "--git-common-dir", "--is-inside-work-tree"],
  { encoding: "utf8", windowsHide: true, timeout: 10000, maxBuffer: 1024 * 1024 });
  const lines = String(result.stdout || "").trim().split(/\r?\n/);
  if (result.status !== 0 || lines.length !== 3 || lines[2] !== "true"
      || !samePath(fs.realpathSync(projectRoot), lines[0]) || !path.isAbsolute(lines[1])
      || !fs.statSync(lines[1]).isDirectory()) throw new Error("Worker projectRoot is not an exact valid Git worktree or clone");
  const list = childProcess.spawnSync("git", ["-C", projectRoot, "worktree", "list", "--porcelain"],
    { encoding: "utf8", windowsHide: true, timeout: 10000, maxBuffer: 1024 * 1024 });
  if (list.status !== 0 || !String(list.stdout || "").split(/\r?\n/)
    .some((line) => line.startsWith("worktree ") && samePath(line.slice(9), projectRoot))) {
    throw new Error("Worker projectRoot is not registered in the Git worktree list");
  }
  return { projectRoot: lines[0], gitCommonDir: lines[1] };
}

const PROJECTION_FIELDS = ["presentationPolicy", "projectionConsumers", "controlFrameFormat",
  "visualSeedRevision", "simulationRngConsumptionRevision", "sessionVisualSeed"];
const PROJECTION_CONSUMERS = ["playerHud", "ordinaryBullet", "ray", "chain", "combatDecoration", "sceneLighting", "equipmentLighting"];
function normalizeProjection(value) {
  if (value === undefined) return undefined;
  if (!value || Array.isArray(value) || Object.keys(value).length !== PROJECTION_FIELDS.length
      || PROJECTION_FIELDS.some((key) => !Object.hasOwn(value, key))
      || value.presentationPolicy !== "full" || value.controlFrameFormat !== "f-visual-v1"
      || value.visualSeedRevision !== "visual-event-v1" || value.simulationRngConsumptionRevision !== "legacy-global-consume-v1"
      || !Number.isSafeInteger(value.sessionVisualSeed) || value.sessionVisualSeed < 1 || value.sessionVisualSeed > 2147483646) {
    throw new Error("invalid D1/D2 Worker projection policy");
  }
  const input = value.projectionConsumers;
  if (!input || Array.isArray(input) || Object.keys(input).length !== PROJECTION_CONSUMERS.length
      || PROJECTION_CONSUMERS.some((key) => !Object.hasOwn(input, key) || !["full", "none"].includes(input[key]))
      || input.sceneLighting !== "full" || input.equipmentLighting !== "full") {
    throw new Error("invalid D1/D2 Worker consumers");
  }
  const result = {};
  for (const key of PROJECTION_FIELDS) result[key] = key === "projectionConsumers"
    ? Object.fromEntries(PROJECTION_CONSUMERS.map((name) => [name, input[name]])) : value[key];
  return result;
}

function validateLaunch(launch) {
  if (!launch || !["arena-worker.launch.v1", "arena-worker.launch.v2"].includes(launch.schema)) throw new Error("unsupported Worker launch schema");
  if (launch.schema === "arena-worker.launch.v2") {
    normalizeProjection(Object.fromEntries(PROJECTION_FIELDS.map((key) => [key, launch[key]])));
  } else if (PROJECTION_FIELDS.some((key) => Object.hasOwn(launch, key))) throw new Error("v1 Worker cannot request projection policy");
  safeId(launch.workerId, "workerId");
  safeId(launch.sessionEpoch, "sessionEpoch");
  normalizePerformance(launch.performance);
  normalizeFaultInjection(launch.allowFaultInjection);
  ROOT_FIELDS.forEach((field) => assertNoReparse(launch[field]));
  verifyGitRoot(launch.projectRoot);
  if (!samePath(launch.saveRoot, path.join(launch.projectRoot, "saves"))
      || !samePath(launch.outputRoot, path.join(launch.projectRoot, "tmp", "arena-calibration"))
      || !samePath(launch.swfOrigin, path.join(launch.projectRoot, "CRAZYFLASHER7MercenaryEmpire.swf"))) {
    throw new Error("Worker launch roots do not match the fixed project ownership contract");
  }
  resolveInside(path.join(launch.projectRoot, "tmp", "arena-worker"), launch.stateRoot, "stateRoot");
  if (!/^cf7_agent_[A-Za-z0-9_-]+$/.test(launch.slot || "")) throw new Error("Worker launch requires a dedicated cf7_agent_ slot");
  return launch;
}

function assertTuple(actual, expected, fields = ID_FIELDS) {
  for (const field of fields) {
    if (typeof expected[field] !== "string" || !actual || actual[field] !== expected[field]) {
      throw new Error(`Worker identity mismatch: ${field}`);
    }
  }
}

function validateOwner(owner, launch, expectedRuntime) {
  if (!owner || owner.schema !== "arena-worker.owner.v1" || owner.executionMode !== "arena_worker") {
    throw new Error("unsupported Worker owner descriptor");
  }
  assertTuple(owner, launch, ID_FIELDS.slice(0, 2));
  if (owner.slot !== launch.slot) throw new Error("Worker owner slot mismatch");
  if (launch.schema === "arena-worker.launch.v2"
      && !require("util").isDeepStrictEqual(owner.projectionConsumers, launch.projectionConsumers)) throw new Error("Worker owner consumers mismatch");
  if (normalizeFaultInjection(owner.allowFaultInjection) !== normalizeFaultInjection(launch.allowFaultInjection)) {
    throw new Error("Worker owner fault-injection policy mismatch");
  }
  if (!owner.performance || JSON.stringify(normalizePerformance(owner.performance)) !== JSON.stringify(normalizePerformance(launch.performance))) {
    throw new Error("Worker owner requested performance policy mismatch");
  }
  ROOT_FIELDS.forEach((field) => {
    assertNoReparse(owner[field]);
    if (!samePath(owner[field], launch[field])) throw new Error(`Worker owner root mismatch: ${field}`);
  });
  assertNoReparse(owner.appData);
  assertNoReparse(owner.sharedObjectsRoot);
  if (!samePath(owner.sharedObjectsRoot, path.join(owner.appData, "Macromedia", "Flash Player", "#SharedObjects"))) {
    throw new Error("Worker owner SharedObjects root is inconsistent");
  }
  if (!Number.isSafeInteger(owner.hostPid) || owner.hostPid < 1
      || typeof owner.processStartUtcTicks !== "string" || !/^[1-9][0-9]{15,19}$/.test(owner.processStartUtcTicks)
      || !Number.isInteger(owner.httpPort) || owner.httpPort < 1 || owner.httpPort > 65535
      || !Number.isInteger(owner.socketPort) || owner.socketPort < 1 || owner.socketPort > 65535
      || owner.httpPort === owner.socketPort) throw new Error("invalid Worker owner process or endpoint identity");
  if (Object.keys(owner).some((key) => /token|credential|secret/i.test(key))) throw new Error("Worker owner must not contain credentials");
  if (!expectedRuntime || expectedRuntime.runtimeMode !== "isolated_candidate"
      || !samePath(owner.processPath, expectedRuntime.processPath)) throw new Error("Worker requires the exact isolated candidate process");
  assertRuntimeIdentity(expectedRuntime, owner.runtimeIdentity);
  return owner;
}

function validateProcessObservation(observation, pid) {
  if (observation === null) return null;
  if (!observation || observation.pid !== pid || !Number.isSafeInteger(observation.pid)
      || typeof observation.processPath !== "string" || !path.isAbsolute(observation.processPath)
      || typeof observation.processStartUtcTicks !== "string" || !/^[1-9][0-9]{15,19}$/.test(observation.processStartUtcTicks)) {
    throw new Error("incomplete process identity observation; exit is unknown");
  }
  return observation;
}

function queryProcess(pid) {
  if (!Number.isSafeInteger(pid) || pid < 1) throw new Error("invalid process identity probe PID");
  const script = "chcp.com 65001 | Out-Null; $ErrorActionPreference='Stop'; "
    + "try { $taskProcess=[Diagnostics.Process]::GetProcessById(" + pid + ") } "
    + "catch [ArgumentException] { [Console]::Write('null'); exit 0 }; "
    + "try { $taskHandle=$taskProcess.Handle; @{pid=$taskProcess.Id;processPath=$taskProcess.MainModule.FileName;processStartUtcTicks="
    + "$taskProcess.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture)} | ConvertTo-Json -Compress } "
    + "catch { if ($taskProcess.HasExited) { [Console]::Write('null') } else { throw } } finally { $taskProcess.Dispose() }";
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
    encoding: "utf8", windowsHide: true, timeout: 10000, maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) throw new Error("Worker process identity could not be queried");
  return validateProcessObservation(JSON.parse(result.stdout.trim()), pid);
}

function verifyProcessOwner(owner, probe = queryProcess) {
  const process = validateProcessObservation(probe(owner.hostPid), owner.hostPid);
  if (!process || process.pid !== owner.hostPid || process.processStartUtcTicks !== owner.processStartUtcTicks
      || !samePath(process.processPath, owner.processPath)) throw new Error("Worker process identity mismatch or PID reuse");
  return process;
}

function terminateExactProcess(identity) {
  const pid = identity.pid || identity.hostPid;
  if (!Number.isSafeInteger(pid) || pid < 1 || typeof identity.processStartUtcTicks !== "string"
      || !/^[1-9][0-9]{15,19}$/.test(identity.processStartUtcTicks) || !path.isAbsolute(identity.processPath || "")) {
    throw new Error("invalid exact process termination identity");
  }
  const encoded = Buffer.from(JSON.stringify({ pid, processStartUtcTicks: identity.processStartUtcTicks,
    processPath: identity.processPath }), "utf8").toString("base64");
  // Base64 contains no shell metacharacters. The Process handle is acquired
  // before identity comparison and remains held through Kill/WaitForExit.
  const script = "chcp.com 65001 | Out-Null; $ErrorActionPreference='Stop'; $taskIdentity="
    + "([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + encoded + "')) | ConvertFrom-Json); "
    + "try { $taskProcess=[Diagnostics.Process]::GetProcessById($taskIdentity.pid) } "
    + "catch [ArgumentException] { '{\"exited\":true,\"killed\":false}'; exit 0 }; "
    + "try { $taskHandle=$taskProcess.Handle; "
    + "if ($taskProcess.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture) -cne $taskIdentity.processStartUtcTicks "
    + "-or ![string]::Equals($taskProcess.Path,$taskIdentity.processPath,[StringComparison]::OrdinalIgnoreCase)) { throw 'owned process identity mismatch' }; "
    + "$taskProcess.Kill(); if (!$taskProcess.WaitForExit(10000)) { throw 'owned process exit unconfirmed' }; "
    + "'{\"exited\":true,\"killed\":true}' } finally { $taskProcess.Dispose() }";
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], {
    encoding: "utf8", windowsHide: true, timeout: 15000, maxBuffer: 1024 * 1024,
  });
  if (result.status !== 0) throw new Error("exact owned process termination was not confirmed");
  const outcome = JSON.parse(result.stdout.trim());
  if (outcome.exited !== true) throw new Error("exact owned process exit was not confirmed");
  return { pid, ...outcome };
}

function postControl(owner, token, message, timeoutMs) {
  return new Promise((resolve, reject) => {
    const bytes = Buffer.from(JSON.stringify(message));
    const request = http.request({
      hostname: "127.0.0.1", port: owner.httpPort, path: "/arena-worker", method: "POST",
      headers: { "Content-Type": "application/json", "Content-Length": bytes.length,
        Host: `localhost:${owner.httpPort}`, [CONTROL_HEADER]: token },
    }, (response) => {
      const parts = [];
      let size = 0;
      response.on("data", (chunk) => {
        size += chunk.length;
        if (size > 4 * 1024 * 1024) response.destroy(new Error("Worker response exceeded limit"));
        else parts.push(chunk);
      });
      response.on("error", reject);
      response.on("end", () => {
        if (response.statusCode !== 200) return reject(new Error(`Worker control HTTP ${response.statusCode}`));
        try { resolve(JSON.parse(Buffer.concat(parts).toString("utf8"))); }
        catch (_error) { reject(new Error("Worker control returned invalid JSON")); }
      });
    });
    request.setTimeout(timeoutMs, () => request.destroy(new Error("Worker control timeout; delivery outcome is unknown")));
    request.on("error", reject);
    request.end(bytes);
  });
}

function createWorkerClient(launch, expectedRuntime, options = {}) {
  validateLaunch(launch);
  let pinnedOwner = null;
  return {
    readOwner() {
      const owner = validateOwner(readJson(path.join(launch.stateRoot, "owner.json")), launch, expectedRuntime);
      if (pinnedOwner && (owner.hostPid !== pinnedOwner.hostPid || owner.processStartUtcTicks !== pinnedOwner.processStartUtcTicks
          || owner.httpPort !== pinnedOwner.httpPort || owner.socketPort !== pinnedOwner.socketPort)) {
        throw new Error("Worker owner changed during this client session");
      }
      pinnedOwner = owner;
      return owner;
    },
    async call(action, fields = {}) {
      if (!ACTIONS.has(action)) throw new Error("Worker action is not allowed");
      const message = { ...fields, action, workerId: launch.workerId, sessionEpoch: launch.sessionEpoch };
      if (action === "faultStopFlash") {
        if (!normalizeFaultInjection(launch.allowFaultInjection)) throw new Error("Worker fault injection was not enabled in its launch");
        assertTuple(fields, launch, ID_FIELDS.slice(0, 2));
        validateFaultRequest(message);
      }
      const owner = this.readOwner();
      assertEndpointOwnership(owner, (options.ownershipProbe || queryWorkerOwnership)(owner));
      const credential = readJson(path.join(launch.stateRoot, "control-credential.json"));
      assertTuple(credential, launch, ID_FIELDS.slice(0, 2));
      if (credential.schema !== "arena-worker.control-credential.v1" || credential.header !== CONTROL_HEADER
          || typeof credential.token !== "string" || credential.token.length < 32) throw new Error("invalid Worker credential");
      if (["startBatch", "abort", "result"].includes(action)) ID_FIELDS.slice(2).forEach((field) => safeId(message[field], field));
      const response = await (options.transport || postControl)(owner, credential.token, message, options.timeoutMs || 20000);
      assertTuple(response, launch, ID_FIELDS.slice(0, 2));
      if (["startBatch", "abort", "result", "faultStopFlash"].includes(action)) assertTuple(response, message);
      if (response.success !== true || response.ok !== true) {
        const error = new Error(`Worker ${action} rejected: ${response.error || response.message || "unknown"}`);
        error.response = response;
        throw error;
      }
      return response;
    },
  };
}

module.exports = { CONTROL_HEADER, ID_FIELDS, ROOT_FIELDS, RUN_FIELDS, assertNoReparse, assertTuple, createWorkerClient,
  normalizeFaultInjection, normalizePerformance, normalizeProjection, PROJECTION_FIELDS, PROJECTION_CONSUMERS, queryProcess, readJson, resolveInside, safeId, samePath, terminateExactProcess,
  validateFaultRequest, validateLaunch, validateOwner, validateProcessObservation, verifyGitRoot, verifyProcessOwner };
