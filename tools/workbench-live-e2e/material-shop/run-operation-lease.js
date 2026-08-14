#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const LauncherObservation = require("../lib/launcher-observation");
const Common = require("./common");
const Materialize = require("./materialize");

const LEASE_SCHEMA = "workbench-live-e2e.material-shop.run-operation-lease.v1";
const TERMINAL_SCHEMA = "workbench-live-e2e.material-shop.run-operation-terminal.v1";
const LEASE_NAME = "run-operation-lease.json";
const TERMINAL_PREFIX = "run-operation-terminal-";
const STALE_RESOLVED_PREFIX = "run-operation-stale-resolved-";
const MODES = Object.freeze(["live_execution", "built_only_discard"]);
const ACTIVE_HANDLES = new Map();
const NON_WINDOWS_SELF_START_TICKS = String(BigInt(Math.floor(
  Date.now() - process.uptime() * 1000)) * 10000n + 621355968000000000n);

function digestWithout(value, key) {
  const copy = Object.assign({}, value);
  delete copy[key];
  return Evidence.sha256Text(Evidence.canonicalJson(copy));
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function fail(code, message, details) {
  Common.fail(code, "run_operation_lease", message, details);
}

function exactRunDirectory(runDirValue, runId) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "run_operation_lease");
  const expected = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", String(runId || ""));
  if (!Common.ID_RE.test(String(runId || "")) || !samePath(runDir, expected)) {
    fail("material_shop_run_operation_path_invalid",
      "operation lease is outside its exact owned A5 run", { runDir, expected });
  }
  return runDir;
}

function processStartProbe(pid) {
  if (process.platform !== "win32") {
    if (pid === process.pid) {
      return { state: "found", ticks: NON_WINDOWS_SELF_START_TICKS };
    }
    if (process.platform === "linux") {
      try {
        fs.accessSync("/proc/" + Number(pid), fs.constants.F_OK);
        return { state: "unverifiable", ticks: null };
      } catch (error) {
        return error && error.code === "ENOENT"
          ? { state: "not_found", ticks: null }
          : { state: "unverifiable", ticks: null };
      }
    }
    return { state: "unverifiable", ticks: null };
  }
  const script = "$ErrorActionPreference='Stop';"
    + "$probeErrors=@();$p=Get-Process -Id " + Number(pid)
    + " -ErrorAction SilentlyContinue -ErrorVariable +probeErrors;"
    + "if($null -eq $p){$missing=($probeErrors.Count -eq 1 -and "
    + "$probeErrors[0].FullyQualifiedErrorId -like 'NoProcessFoundForGivenId,*');"
    + "$state=if($missing){'not_found'}else{'unverifiable'};"
    + "[pscustomobject]@{state=$state;ticks=$null}|ConvertTo-Json -Compress;exit 0};"
    + "try{$ticks=$p.StartTime.ToUniversalTime().Ticks.ToString();"
    + "[pscustomobject]@{state='found';ticks=$ticks}|ConvertTo-Json -Compress}"
    + "catch{[pscustomobject]@{state='unverifiable';ticks=$null}|ConvertTo-Json -Compress}";
  const result = childProcess.spawnSync("powershell.exe", ["-NoProfile", "-Command", script], {
    encoding: "utf8", windowsHide: true, maxBuffer: 1024 * 1024,
  });
  if (result.error || result.status !== 0) {
    return { state: "unverifiable", ticks: null };
  }
  let value;
  try { value = JSON.parse(String(result.stdout || "").trim()); }
  catch (_error) { return { state: "unverifiable", ticks: null }; }
  if (value && value.state === "not_found" && value.ticks === null) {
    return { state: "not_found", ticks: null };
  }
  if (value && value.state === "found" && /^\d{12,20}$/.test(String(value.ticks || ""))) {
    return { state: "found", ticks: String(value.ticks) };
  }
  return { state: "unverifiable", ticks: null };
}

function validateLease(value, runDirValue) {
  const keys = ["schema", "createdAt", "runId", "runDir", "mode", "preparationSha256",
    "buildSha256", "ownerPid", "ownerProcessStartUtcTicks", "ownerNonceSha256",
    "leaseSha256"].sort();
  const runDir = exactRunDirectory(runDirValue, value && value.runId);
  if (!value || Evidence.canonicalJson(Object.keys(value).sort())
        !== Evidence.canonicalJson(keys)
      || value.schema !== LEASE_SCHEMA || !Number.isFinite(Date.parse(value.createdAt))
      || !samePath(value.runDir, runDir) || !MODES.includes(value.mode)
      || !Common.SHA256_RE.test(String(value.preparationSha256 || ""))
      || !Common.SHA256_RE.test(String(value.buildSha256 || ""))
      || !Number.isInteger(value.ownerPid) || value.ownerPid < 1
      || !/^\d{12,20}$/.test(String(value.ownerProcessStartUtcTicks || ""))
      || !Common.SHA256_RE.test(String(value.ownerNonceSha256 || ""))
      || value.leaseSha256 !== digestWithout(value, "leaseSha256")) {
    fail("material_shop_run_operation_lease_invalid",
      "operation lease is malformed, foreign, or byte-detached");
  }
  return value;
}

function readLease(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "run_operation_lease");
  const leasePath = path.join(runDir, LEASE_NAME);
  if (!fs.existsSync(leasePath)) return { active: false, runDir, leasePath, lease: null,
    artifact: null, ownerState: "absent" };
  const file = Evidence.readExactRegularFile(leasePath, {
    phase: "run_operation_lease", maximumBytes: 1024 * 1024,
  });
  let lease;
  try { lease = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { fail("material_shop_run_operation_lease_invalid", error.message); }
  validateLease(lease, runDir);
  const observed = processStartProbe(lease.ownerPid);
  const ownerState = observed.state === "not_found" ? "not_found"
    : observed.state === "unverifiable" ? "unverifiable"
      : observed.ticks === lease.ownerProcessStartUtcTicks ? "same_process" : "pid_reused";
  return { active: true, runDir, leasePath, lease,
    artifact: { bytes: file.length, sha256: file.sha256 }, ownerState,
    observedProcessStartUtcTicks: observed.ticks, ownerProbeState: observed.state };
}

function writeLeaseNew(filePath, value) {
  const bytes = Buffer.from(JSON.stringify(value, null, 2) + "\n", "utf8");
  let descriptor;
  try {
    descriptor = fs.openSync(filePath, "wx");
    let offset = 0;
    while (offset < bytes.length) {
      offset += fs.writeSync(descriptor, bytes, offset, bytes.length - offset, null);
    }
    fs.fsyncSync(descriptor);
  } finally {
    if (descriptor !== undefined) fs.closeSync(descriptor);
  }
  return { bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
}

function acquire(options) {
  const settings = options || {};
  const runDir = exactRunDirectory(settings.runDir, settings.runId);
  if (!MODES.includes(settings.mode)
      || !Common.SHA256_RE.test(String(settings.preparationSha256 || ""))
      || !Common.SHA256_RE.test(String(settings.buildSha256 || ""))) {
    fail("material_shop_run_operation_lease_invalid",
      "operation lease acquisition lacks exact mode/preparation/build bindings");
  }
  const prior = readLease(runDir);
  if (prior.active) {
    fail("material_shop_run_operation_busy",
      "another live/discard operation owns this A5 run; inspect or explicitly recover a stale lease",
      { mode: prior.lease.mode, ownerPid: prior.lease.ownerPid,
        ownerState: prior.ownerState, leaseSha256: prior.lease.leaseSha256 });
  }
  if (settings.mode === "live_execution"
      && historyMarkers(runDir).some((entry) => entry.lease.mode === "live_execution")) {
    fail("material_shop_run_operation_live_reentry_forbidden",
      "a run with terminal or stale-recovered live execution history cannot start again; use a fresh run id");
  }
  const terminalCollision = path.join(runDir, TERMINAL_PREFIX + "pending.json");
  if (fs.existsSync(terminalCollision)) fail("material_shop_run_operation_terminal_invalid",
    "foreign operation terminal staging marker blocks acquisition");
  const processStart = processStartProbe(process.pid);
  if (processStart.state !== "found") fail("material_shop_run_operation_owner_unavailable",
    "current process start identity is unavailable");
  const nonce = crypto.randomBytes(32).toString("hex");
  const lease = { schema: LEASE_SCHEMA, createdAt: new Date().toISOString(),
    runId: settings.runId, runDir, mode: settings.mode,
    preparationSha256: settings.preparationSha256,
    buildSha256: settings.buildSha256, ownerPid: process.pid,
    ownerProcessStartUtcTicks: processStart.ticks,
    ownerNonceSha256: Evidence.sha256Text(nonce) };
  lease.leaseSha256 = Evidence.sha256Text(Evidence.canonicalJson(lease));
  const leasePath = path.join(runDir, LEASE_NAME);
  let artifact;
  try { artifact = writeLeaseNew(leasePath, lease); }
  catch (error) {
    if (error && error.code === "EEXIST") fail("material_shop_run_operation_busy",
      "another operation acquired the A5 run concurrently");
    throw error;
  }
  const handle = { runDir, leasePath, lease, nonce, artifact, active: true,
    executionStarted: false };
  ACTIVE_HANDLES.set(leasePath.toLowerCase(), handle);
  return handle;
}

function validateTerminal(value, expected) {
  const keys = ["schema", "runId", "mode", "preparationSha256", "buildSha256",
    "leaseSha256", "archiveName", "archiveBytes", "archiveSha256", "active",
    "terminalSha256"].sort();
  if (!value || Evidence.canonicalJson(Object.keys(value).sort())
        !== Evidence.canonicalJson(keys)
      || value.schema !== TERMINAL_SCHEMA
      || value.active !== false || !MODES.includes(value.mode)
      || !Common.SHA256_RE.test(String(value.preparationSha256 || ""))
      || !Common.SHA256_RE.test(String(value.buildSha256 || ""))
      || !Common.SHA256_RE.test(String(value.leaseSha256 || ""))
      || value.archiveName !== TERMINAL_PREFIX + value.leaseSha256.slice(0, 16) + ".json"
      || !Number.isSafeInteger(value.archiveBytes) || value.archiveBytes < 1
      || !Common.SHA256_RE.test(String(value.archiveSha256 || ""))
      || value.terminalSha256 !== digestWithout(value, "terminalSha256")
      || expected && (value.runId !== expected.runId || value.mode !== expected.mode
        || value.preparationSha256 !== expected.preparationSha256
        || value.buildSha256 !== expected.buildSha256)) {
    fail("material_shop_run_operation_terminal_invalid",
      "operation terminal evidence is malformed or detached");
  }
  return value;
}

function terminalName(lease) {
  return TERMINAL_PREFIX + lease.leaseSha256.slice(0, 16) + ".json";
}

function terminalFromArchive(runDir, lease) {
  validateLease(lease, runDir);
  const archiveName = terminalName(lease);
  const archivePath = path.join(runDir, archiveName);
  const file = Evidence.readExactRegularFile(archivePath, {
    phase: "run_operation_lease", maximumBytes: 1024 * 1024,
  });
  let archived;
  try { archived = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { fail("material_shop_run_operation_terminal_invalid", error.message); }
  validateLease(archived, runDir);
  if (Evidence.canonicalJson(archived) !== Evidence.canonicalJson(lease)
      || fs.existsSync(path.join(runDir, LEASE_NAME))) {
    fail("material_shop_run_operation_terminal_invalid",
      "terminal operation archive differs from its released lease or active lease remains");
  }
  const terminal = { schema: TERMINAL_SCHEMA, runId: lease.runId, mode: lease.mode,
    preparationSha256: lease.preparationSha256, buildSha256: lease.buildSha256,
    leaseSha256: lease.leaseSha256, archiveName, archiveBytes: file.length,
    archiveSha256: file.sha256, active: false };
  terminal.terminalSha256 = Evidence.sha256Text(Evidence.canonicalJson(terminal));
  return validateTerminal(terminal, lease);
}

function assertExactOwner(handle) {
  if (!handle || handle.active !== true
      || ACTIVE_HANDLES.get(String(handle.leasePath).toLowerCase()) !== handle
      || Evidence.sha256Text(String(handle.nonce || "")) !== handle.lease.ownerNonceSha256) {
    fail("material_shop_run_operation_owner_mismatch",
      "only the exact in-process lease owner may release the run");
  }
  const current = readLease(handle.runDir);
  if (!current.active || Evidence.canonicalJson(current.lease)
      !== Evidence.canonicalJson(handle.lease)
      || current.artifact.sha256 !== handle.artifact.sha256
      || current.artifact.bytes !== handle.artifact.bytes
      || current.ownerState !== "same_process") {
    fail("material_shop_run_operation_lease_drift",
      "operation lease bytes or owner identity changed before an owner transition");
  }
  return current;
}

function markExecutionStarted(handle) {
  assertExactOwner(handle);
  if (handle.lease.mode !== "live_execution" || handle.executionStarted !== false) {
    fail("material_shop_run_operation_execution_state_invalid",
      "only one exact pre-execution live lease may cross into candidate execution");
  }
  handle.executionStarted = true;
  return { leaseSha256: handle.lease.leaseSha256, executionStarted: true };
}

function cancelBeforeExecution(handle) {
  assertExactOwner(handle);
  if (handle.lease.mode !== "live_execution" || handle.executionStarted !== false) {
    fail("material_shop_run_operation_cancel_forbidden",
      "an operation lease may be cancelled only before live execution begins");
  }
  fs.unlinkSync(handle.leasePath);
  if (fs.existsSync(handle.leasePath)) {
    fail("material_shop_run_operation_cancel_failed",
      "pre-execution operation lease remained after exact-owner cancellation");
  }
  handle.active = false;
  ACTIVE_HANDLES.delete(handle.leasePath.toLowerCase());
  return { runId: handle.lease.runId, mode: handle.lease.mode,
    leaseSha256: handle.lease.leaseSha256, executionStarted: false,
    cancelledWithoutTerminal: true };
}

function release(handle) {
  assertExactOwner(handle);
  const archivePath = path.join(handle.runDir, terminalName(handle.lease));
  if (fs.existsSync(archivePath)) fail("material_shop_run_operation_terminal_exists",
    "operation terminal archive already exists before exact-owner release");
  fs.renameSync(handle.leasePath, archivePath);
  if (fs.existsSync(handle.leasePath) || !fs.existsSync(archivePath)) {
    fail("material_shop_run_operation_release_failed",
      "operation lease did not atomically become its terminal archive");
  }
  handle.active = false;
  ACTIVE_HANDLES.delete(handle.leasePath.toLowerCase());
  return terminalFromArchive(handle.runDir, handle.lease);
}

function resolvedName(lease) {
  return STALE_RESOLVED_PREFIX + lease.leaseSha256.slice(0, 16) + ".json";
}

function recoverStale(runDirValue, acknowledge) {
  if (acknowledge !== true) fail("material_shop_run_operation_recovery_ack_required",
    "stale operation recovery requires explicit acknowledgement");
  const current = readLease(runDirValue);
  if (!current.active || !["not_found", "pid_reused"].includes(current.ownerState)) {
    fail("material_shop_run_operation_not_stale",
      "operation lease owner is still active or no stale lease exists", {
        ownerState: current.ownerState,
      });
  }
  LauncherObservation.assertExclusiveLauncherProcess(
    LauncherObservation.queryLauncherCoreProcesses(), null);
  if (current.lease.mode === "built_only_discard") {
    const destination = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
      Materialize.MATERIALIZED_DIRECTORY, current.lease.runId, "resources");
    const present = fs.existsSync(destination);
    const listed = Materialize.worktreeListed(Common.CANONICAL_ROOT, destination);
    if (present !== listed) fail("material_shop_run_operation_recovery_split_state",
      "stale discard lease has split filesystem/Git worktree state");
  }
  const fresh = readLease(current.runDir);
  if (!fresh.active || !["not_found", "pid_reused"].includes(fresh.ownerState)
      || Evidence.canonicalJson(fresh.lease) !== Evidence.canonicalJson(current.lease)
      || fresh.artifact.sha256 !== current.artifact.sha256) {
    fail("material_shop_run_operation_recovery_drift",
      "stale operation lease changed during explicit recovery");
  }
  const resolvedPath = path.join(current.runDir, resolvedName(current.lease));
  if (fs.existsSync(resolvedPath)) fail("material_shop_run_operation_recovery_exists",
    "stale operation recovery marker already exists");
  fs.renameSync(current.leasePath, resolvedPath);
  return { schema: "workbench-live-e2e.material-shop.run-operation-stale-recovery.v1",
    runId: current.lease.runId, mode: current.lease.mode,
    leaseSha256: current.lease.leaseSha256,
    ownerState: fresh.ownerState, active: false,
    resolvedPath: path.basename(resolvedPath) };
}

function historyMarkers(runDirValue) {
  const runDir = Evidence.assertOwnedRunDirectory(Common.CANONICAL_ROOT, runDirValue,
    Common.OWNED_BASE_RELATIVE, "run_operation_lease");
  const matcher = new RegExp("^(?:" + STALE_RESOLVED_PREFIX + "|" + TERMINAL_PREFIX
    + ")[a-f0-9]{16}\\.json$");
  return fs.readdirSync(runDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && matcher.test(entry.name))
    .map((entry) => {
      const file = Evidence.readExactRegularFile(path.join(runDir, entry.name), {
        phase: "run_operation_lease", maximumBytes: 1024 * 1024,
      });
      let lease;
      try { lease = JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
      catch (error) { fail("material_shop_run_operation_history_invalid", error.message); }
      validateLease(lease, runDir);
      const expected = entry.name.startsWith(TERMINAL_PREFIX)
        ? terminalName(lease) : resolvedName(lease);
      if (entry.name !== expected) fail("material_shop_run_operation_history_invalid",
        "operation history marker name differs from its sealed lease");
      return { name: entry.name, bytes: file.length, sha256: file.sha256,
        kind: entry.name.startsWith(TERMINAL_PREFIX) ? "terminal" : "stale_recovery",
        lease };
    }).sort((left, right) => left.name.localeCompare(right.name));
}

function parseArgs(argv) {
  const args = { mode: null, runDir: null, acknowledge: false };
  for (let index = 0; index < argv.length; index += 1) {
    if (argv[index] === "--inspect") args.mode = "inspect";
    else if (argv[index] === "--recover-stale") args.mode = "recover";
    else if (argv[index] === "--run-dir") args.runDir = argv[++index];
    else if (argv[index] === "--acknowledge-stale-operation-recovery") args.acknowledge = true;
    else fail("material_shop_run_operation_argument_unknown", argv[index]);
  }
  if (!args.runDir || !["inspect", "recover"].includes(args.mode)
      || args.mode === "inspect" && args.acknowledge) {
    fail("material_shop_run_operation_arguments_invalid",
      "use exact --inspect or explicitly acknowledged --recover-stale with one run directory");
  }
  return args;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const result = args.mode === "inspect" ? readLease(args.runDir)
      : recoverStale(args.runDir, args.acknowledge);
    process.stdout.write(JSON.stringify({ ok: true, result }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  LEASE_NAME,
  LEASE_SCHEMA,
  MODES,
  STALE_RESOLVED_PREFIX,
  TERMINAL_PREFIX,
  TERMINAL_SCHEMA,
  acquire,
  cancelBeforeExecution,
  historyMarkers,
  markExecutionStarted,
  parseArgs,
  processStartProbe,
  readLease,
  recoverStale,
  release,
  resolvedName,
  terminalFromArchive,
  terminalName,
  validateLease,
  validateTerminal,
};
