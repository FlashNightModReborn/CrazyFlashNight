#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const {
  readJsonFile,
  readJsonLines,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  createIdleGrant,
  createProducerRegistry,
} = require("./lib/campaign-resource-arbiter");
const { CampaignSupervisor } = require("./lib/campaign-supervisor");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");
const {
  aggregateAttention,
  captureDiskHealth,
  classifyShardRowHealth,
  collectControlProcessIds,
  compareRuntimeIdentity,
  createAttentionMeasurement,
  createExceptionInboxItem,
  createGateFShardReceipt,
  createGateFStatus,
  createIdleWindow,
  createProducerObservations,
  evaluateShardHealth,
  freezeGateFPlan,
  listWindowsProcesses,
  projectRelative,
  resolveInsideRoot,
  sha256File,
  verifyGateFPlan,
  verifyIdleWindow,
  withoutHash,
} = require("./lib/gate-f-campaign");
const { assertSchemaInstance } = require("./lib/schema-registry");

const ROOT = path.resolve(__dirname, "../..");
const DEFAULT_JOURNAL_ROOT = path.join(ROOT, "logs", "arena-calibration", "campaigns");
const POLL_MS = 1000;

function fail(message, code) {
  const error = new Error(message);
  error.code = code || "gate_fctl_failed";
  throw error;
}

function safeId(value, fallback) {
  const normalized = String(value || "").replace(/[^A-Za-z0-9._:-]+/g, "-").slice(0, 150);
  return normalized && /^[A-Za-z0-9]/.test(normalized) ? normalized : fallback;
}

function timestampId(date = new Date()) {
  return date.toISOString().replace(/[-:]/g, "").replace(/\..+$/, "Z");
}

function parseArgs(argv) {
  const directCheck = argv[0] === "--check";
  const directHelp = argv[0] === "--help" || argv[0] === "-h";
  const args = {
    command: (directCheck || directHelp) ? "help" : (argv[0] || "help"),
    projectRoot: ROOT,
    journalRoot: DEFAULT_JOURNAL_ROOT,
    draft: null,
    plan: null,
    window: null,
    outputDir: null,
    output: null,
    hours: 8,
    maxShards: Number.POSITIVE_INFINITY,
    check: directCheck,
  };
  for (let index = 1; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--project-root") args.projectRoot = path.resolve(argv[++index]);
    else if (token === "--journal-root") args.journalRoot = path.resolve(argv[++index]);
    else if (token === "--draft") args.draft = argv[++index];
    else if (token === "--plan") args.plan = argv[++index];
    else if (token === "--window") args.window = argv[++index];
    else if (token === "--output-dir") args.outputDir = argv[++index];
    else if (token === "--output") args.output = argv[++index];
    else if (token === "--hours") args.hours = Number(argv[++index]);
    else if (token === "--max-shards") args.maxShards = Number(argv[++index]);
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.command = "help";
    else fail(`unknown argument: ${token}`, "usage_error");
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/gate-fctl.js <command> [options]

Commands:
  freeze   Freeze clean Git source, exact formal runtime, candidates and 10-25-run manifests.
  arm      Verify the frozen plan and issue one bounded, revocable idle window.
  run      Execute remaining short shards with fresh producer observations and durable imports.
  status   Rebuild Gate F status from canonical receipts without starting the game.
  revoke   Create the exact owned revoke signal named by an idle window.

Options:
  freeze: --draft <json> --output-dir <project path>
  arm:    --plan <json> --output-dir <project path> [--hours 1..24]
  run:    --plan <json> --window <json> [--max-shards <n>]
  status: --plan <json> [--output <json>]
  revoke: --plan <json> --window <json>
  shared: [--journal-root <path>] [--project-root <path>]
  --check  Contract self-check; never launches the game.
`);
}

function requireArg(args, name) {
  if (args[name] === null || args[name] === undefined || args[name] === "") {
    fail(`--${name.replace(/[A-Z]/g, (char) => `-${char.toLowerCase()}`)} is required`, "usage_error");
  }
  return args[name];
}

function resolveInput(projectRoot, value, label) {
  return resolveInsideRoot(projectRoot, requireArg({ value }, "value"), label);
}

function resolveOutput(projectRoot, value, label) {
  return resolveInsideRoot(projectRoot, value, label, false);
}

function readPlan(projectRoot, filePath, options) {
  const resolved = resolveInput(projectRoot, filePath, "Gate F plan");
  const plan = readJsonFile(resolved);
  verifyGateFPlan(projectRoot, plan, options);
  return { plan, path: resolved };
}

function readWindow(projectRoot, plan, filePath, options) {
  const resolved = resolveInput(projectRoot, filePath, "Gate F idle window");
  const window = readJsonFile(resolved);
  verifyIdleWindow(projectRoot, plan, window, options);
  return { window, path: resolved };
}

function campaignArtifactDir(args, plan) {
  return path.join(path.resolve(args.journalRoot), plan.campaignId, "artifacts");
}

function readArtifacts(args, plan, pattern, schema) {
  const artifactDir = campaignArtifactDir(args, plan);
  if (!fs.existsSync(artifactDir)) return [];
  return fs.readdirSync(artifactDir)
    .filter((name) => pattern.test(name))
    .sort()
    .map((name) => {
      const value = readJsonFile(path.join(artifactDir, name));
      if (schema) assertSchemaInstance(schema, value, name);
      return value;
    });
}

function verifyShardReceipt(receipt) {
  assertSchemaInstance("arena-calibration.gate-f-shard-receipt.v1", receipt, "Gate F shard receipt");
  if (receipt.receiptHash !== sha256OfValue(withoutHash(receipt, "receiptHash"))) {
    fail(`Gate F shard receipt hash mismatch: ${receipt.receiptId}`, "shard_receipt_hash_mismatch");
  }
  return receipt;
}

function latestReceipts(receipts) {
  const latest = new Map();
  receipts.forEach((receipt) => {
    const previous = latest.get(receipt.shardId);
    if (!previous || previous.finishedAt.localeCompare(receipt.finishedAt) < 0) latest.set(receipt.shardId, receipt);
  });
  return latest;
}

function summarizeExceptions(items, plan, now) {
  const open = items.filter((item) => !["resolved", "expired_default_applied"].includes(item.status));
  const nowMs = Date.parse(now);
  const urgent = open.filter((item) => ["blocking_scope", "failed_closed"].includes(item.severity)
    || Date.parse(item.reviewDeadline) <= nowMs);
  const deferred = open.filter((item) => item.status === "deferred" && !urgent.includes(item));
  const scopes = new Set(deferred.flatMap((item) => item.affectedScopes));
  const candidates = new Set(Array.from(scopes).filter((scope) => scope.startsWith("candidate:")).map((scope) => scope.slice(10)));
  const workItems = new Set(Array.from(scopes).filter((scope) => scope.startsWith("work:")).map((scope) => scope.slice(5)));
  const affectedCandidateRate = candidates.size / plan.candidateIds.length;
  const affectedWorkItemRate = workItems.size / plan.shards.length;
  const maximumFanOut = open.reduce((maximum, item) => Math.max(maximum, item.affectedScopes.length), 0);
  return {
    items: items.length,
    open: open.length,
    urgentOrOverdue: urgent.length,
    deferred: deferred.length,
    occurrences: open.reduce((total, item) => total + item.occurrences.length, 0),
    affectedScopes: new Set(open.flatMap((item) => item.affectedScopes)).size,
    maximumFanOut,
    affectedCandidateRate,
    affectedWorkItemRate,
    ok: urgent.length === 0
      && deferred.length <= plan.attentionPolicy.maximumDeferredItems
      && affectedCandidateRate <= plan.attentionPolicy.maximumDeferredScopeRate
      && affectedWorkItemRate <= plan.attentionPolicy.maximumDeferredScopeRate,
  };
}

function buildStatus(args, plan, options) {
  options = options || {};
  const now = options.now || new Date().toISOString();
  const receipts = readArtifacts(args, plan, /^gate-f-shard-receipt-.*\.json$/i, "arena-calibration.gate-f-shard-receipt.v1")
    .map(verifyShardReceipt)
    .filter((entry) => entry.planHash === plan.planHash);
  const latest = latestReceipts(receipts);
  const measurements = readArtifacts(args, plan, /^attention-measurement-.*\.json$/i, "arena-calibration.attention-measurement.v1")
    .filter((entry) => entry.campaignId === plan.campaignId && entry.evidenceRefs.includes(plan.planHash));
  const attention = aggregateAttention(measurements, plan.attentionPolicy, now);
  const exceptionItems = readArtifacts(args, plan, /^exception-.*\.json$/i, "arena-calibration.exception-inbox-item.v1")
    .filter((entry) => entry.campaignId === plan.campaignId);
  const exceptions = summarizeExceptions(exceptionItems, plan, now);
  const completed = Array.from(latest.values()).filter((entry) => entry.state === "completed").length;
  const failed = Array.from(latest.values()).filter((entry) => entry.state === "failed").length;
  const completedHealth = Array.from(latest.values()).filter((entry) => entry.state === "completed").every((entry) => entry.health.ok === true);
  let sourceAndRuntimeCurrent = true;
  let drift = null;
  try { verifyGateFPlan(args.projectRoot, plan); }
  catch (error) {
    sourceAndRuntimeCurrent = false;
    drift = { code: error.code || null, message: error.message };
  }
  const latestSequence = plan.shards.map((shard) => latest.get(shard.shardId)).filter(Boolean);
  let consecutiveFailures = 0;
  for (let index = latestSequence.length - 1; index >= 0; index -= 1) {
    if (latestSequence[index].state !== "failed") break;
    consecutiveFailures += 1;
  }
  const failedClosed = consecutiveFailures >= plan.healthPolicy.maximumConsecutiveShardFailures
    || Array.from(latest.values()).some((entry) => entry.health.fatal === true);
  const allCompleted = completed === plan.shards.length;
  const candidateOutcomes = plan.candidateBaselines.map((baseline) => {
    if (baseline.initialState === "completed_prior") return { candidateId: baseline.candidateId, state: "completed" };
    if (baseline.initialState === "quarantined") return { candidateId: baseline.candidateId, state: "quarantined" };
    const candidateShards = plan.shards.filter((shard) => shard.candidateIds.includes(baseline.candidateId));
    const complete = candidateShards.length > 0 && candidateShards.every((shard) => {
      const receipt = latest.get(shard.shardId);
      return receipt && receipt.state === "completed";
    });
    return { candidateId: baseline.candidateId, state: complete ? "provisional" : "pending" };
  });
  const pendingCandidates = candidateOutcomes.filter((entry) => entry.state === "pending").length;
  const state = failedClosed ? "FAILED_CLOSED"
    : (allCompleted && pendingCandidates === 0 && attention.status === "within_threshold" && exceptions.ok && completedHealth && sourceAndRuntimeCurrent
      ? "COMPLETED" : (receipts.length === 0 ? "READY" : "PAUSED"));
  return createGateFStatus({
    plan,
    state,
    shards: {
      planned: plan.shards.length,
      completed,
      failed,
      remaining: plan.shards.length - completed,
    },
    rows: {
      committed: receipts.reduce((total, entry) => total + entry.committedRows, 0),
      duplicatesExcluded: receipts.reduce((total, entry) => total + entry.duplicatesExcluded, 0),
    },
    attention,
    exceptions,
    health: {
      sourceAndRuntimeCurrent,
      drift,
      completedShardHealthOk: completedHealth,
      consecutiveFailures,
      latestReceiptCount: latest.size,
      candidateOutcomes: {
        total: candidateOutcomes.length,
        completed: candidateOutcomes.filter((entry) => entry.state === "completed").length,
        provisional: candidateOutcomes.filter((entry) => entry.state === "provisional").length,
        quarantined: candidateOutcomes.filter((entry) => entry.state === "quarantined").length,
        pending: pendingCandidates,
        items: candidateOutcomes,
      },
    },
    createdAt: now,
  });
}

function commandFreeze(args) {
  const draftPath = resolveInput(args.projectRoot, requireArg(args, "draft"), "Gate F draft");
  const outputDir = resolveOutput(args.projectRoot, requireArg(args, "outputDir"), "Gate F output directory");
  const plan = freezeGateFPlan(args.projectRoot, readJsonFile(draftPath));
  fs.mkdirSync(outputDir, { recursive: true });
  const outputPath = path.join(outputDir, "gate-f-plan.json");
  writeJsonAtomic(outputPath, plan);
  return { ok: true, state: "FROZEN", plan: projectRelative(args.projectRoot, outputPath), planHash: plan.planHash };
}

function commandArm(args) {
  if (!Number.isFinite(args.hours) || args.hours < 1 || args.hours > 24) fail("--hours must be between 1 and 24", "usage_error");
  const { plan } = readPlan(args.projectRoot, requireArg(args, "plan"));
  const outputDir = resolveOutput(args.projectRoot, requireArg(args, "outputDir"), "Gate F arm output directory");
  const disk = captureDiskHealth(args.projectRoot, plan.healthPolicy.minimumFreeBytes);
  if (!disk.ok) fail(`Gate F disk gate failed: ${disk.freeBytes} < ${disk.minimumFreeBytes}`, "disk_below_minimum");
  const window = createIdleWindow(args.projectRoot, plan, { durationMs: args.hours * 60 * 60 * 1000 });
  if (fs.existsSync(resolveOutput(args.projectRoot, window.revokeFile, "Gate F revoke file"))) {
    fail("Gate F revoke file already exists; arm a new plan/window path", "idle_window_already_revoked");
  }
  const observations = createProducerObservations(args.projectRoot, plan, window);
  const now = new Date().toISOString();
  const registry = createProducerRegistry(observations, {
    registryId: `gate-f-registry-${timestampId()}`,
    generatedAt: now,
    observationTtlSeconds: 60,
  });
  const grant = createIdleGrant(registry, {
    grantId: `gate-f-grant-${timestampId()}`,
    issuedAt: now,
    ttlSeconds: 120,
  });
  fs.mkdirSync(outputDir, { recursive: true });
  const windowPath = path.join(outputDir, "idle-window.json");
  writeJsonAtomic(windowPath, window);
  writeJsonAtomic(path.join(outputDir, "arm-producer-registry.json"), registry);
  writeJsonAtomic(path.join(outputDir, "arm-idle-grant.json"), grant);
  writeJsonAtomic(path.join(outputDir, "arm-disk-health.json"), disk);
  return {
    ok: true,
    state: "ARMED",
    window: projectRelative(args.projectRoot, windowPath),
    expiresAt: window.expiresAt,
    freeBytes: disk.freeBytes,
  };
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function boundedText(current, chunk, maximum = 1024 * 1024) {
  const next = `${current}${String(chunk || "")}`;
  return next.length <= maximum ? next : next.slice(next.length - maximum);
}

function writeYieldSignal(signalPath, reason) {
  if (fs.existsSync(signalPath)) return;
  fs.mkdirSync(path.dirname(signalPath), { recursive: true });
  writeJsonAtomic(signalPath, {
    schema: "arena-calibration.gate-f-yield-signal.v1",
    reason,
    requestedAt: new Date().toISOString(),
  });
}

function terminateExactChildTree(child) {
  if (!child || !Number.isInteger(child.pid) || child.pid <= 0) return { attempted: false, method: null, status: null };
  if (process.platform === "win32") {
    const result = childProcess.spawnSync("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], {
      windowsHide: true,
      encoding: "utf8",
      timeout: 15000,
    });
    if (result.status === 0) return { attempted: true, method: "taskkill_exact_tree", status: 0 };
  }
  try { child.kill("SIGKILL"); } catch (_error) { }
  return { attempted: true, method: "node_sigkill_fallback", status: null };
}

async function runChildWithMonitor(args, plan, window, shard, runDir, runnerArgs) {
  const signalPath = path.join(runDir, "yield.signal");
  const child = childProcess.spawn(process.execPath, runnerArgs.concat(["--cancel-file", signalPath]), {
    cwd: args.projectRoot,
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout = boundedText(stdout, chunk); });
  child.stderr.on("data", (chunk) => { stderr = boundedText(stderr, chunk); });
  let exit = null;
  const exited = new Promise((resolve) => {
    child.once("error", (error) => {
      exit = { code: null, signal: null, spawnError: error.message };
      resolve(exit);
    });
    child.once("close", (code, signal) => {
      if (!exit) exit = { code, signal, spawnError: null };
      resolve(exit);
    });
  });
  let yieldReason = null;
  let yieldRequestedAt = null;
  let hardYieldEnforced = false;
  let treeTermination = null;
  let lastDeepProbe = 0;
  while (!exit) {
    await Promise.race([exited, sleep(POLL_MS)]);
    if (exit) break;
    try {
      verifyIdleWindow(args.projectRoot, plan, window);
      const nowMs = Date.now();
      if (nowMs - lastDeepProbe >= 5000) {
        lastDeepProbe = nowMs;
        const disk = captureDiskHealth(args.projectRoot, plan.healthPolicy.minimumFreeBytes);
        if (!disk.ok) fail("disk fell below the frozen Gate F minimum", "disk_below_minimum");
        verifyGateFPlan(args.projectRoot, plan);
        const processSnapshot = listWindowsProcesses();
        const controlProcessIds = collectControlProcessIds(processSnapshot, [process.pid, child.pid]);
        const competing = processSnapshot.filter((entry) => {
          const pid = Number(entry.ProcessId);
          if (controlProcessIds.has(pid)) return false;
          if (/^Flash\.exe$/i.test(String(entry.Name || ""))) return true;
          return /(?:run-unattended|gate-fctl)\.js/i.test(String(entry.CommandLine || ""));
        });
        if (competing.length > 0) fail("content development or another arena runner requested the machine", "producer_preempted");
      }
    } catch (error) {
      if (!yieldReason) {
        yieldReason = { code: error.code || "gate_f_monitor_failed", message: error.message };
        yieldRequestedAt = Date.now();
        writeYieldSignal(signalPath, yieldReason);
      }
    }
    if (yieldRequestedAt && !hardYieldEnforced
        && Date.now() - yieldRequestedAt > plan.attentionPolicy.maximumYieldSeconds * 1000) {
      hardYieldEnforced = true;
      treeTermination = terminateExactChildTree(child);
      yieldReason = {
        code: "yield_latency_exceeded",
        message: `runner exceeded ${plan.attentionPolicy.maximumYieldSeconds}s hard yield bound`,
      };
    }
  }
  await exited;
  return {
    ...exit,
    stdout,
    stderr,
    signalPath: projectRelative(args.projectRoot, signalPath),
    yieldReason,
    yieldLatencySeconds: yieldRequestedAt ? (Date.now() - yieldRequestedAt) / 1000 : null,
    hardYieldEnforced,
    treeTermination,
    shardId: shard.shardId,
  };
}

function readAttemptResults(projectRoot, report) {
  return (report.attempts || []).flatMap((attempt) => {
    if (!attempt.resultPath || !attempt.manifestPath || attempt.resultRows < 1) return [];
    const resultPath = resolveInsideRoot(projectRoot, attempt.resultPath, "Gate F attempt result");
    const manifestPath = resolveInsideRoot(projectRoot, attempt.manifestPath, "Gate F attempt manifest");
    const rows = readJsonLines(resultPath);
    if (rows.length !== attempt.resultRows) fail(`attempt ${attempt.index} result row count drifted`, "attempt_row_count_drift");
    return [{ attempt, resultPath, manifestPath, rows }];
  });
}

function exceptionCounts(args, plan) {
  const items = readArtifacts(args, plan, /^exception-.*\.json$/i, "arena-calibration.exception-inbox-item.v1")
    .filter((entry) => entry.campaignId === plan.campaignId && !["resolved", "expired_default_applied"].includes(entry.status));
  return {
    items: items.length,
    occurrences: items.reduce((total, entry) => total + entry.occurrences.length, 0),
    affectedScopes: new Set(items.flatMap((entry) => entry.affectedScopes)).size,
  };
}

function createShardMeasurement(args, plan, window, shard, report, reportPath, runEvidence, eligible) {
  const finishedAt = report.completedAt || new Date().toISOString();
  const startedAt = report.startedAt || finishedAt;
  const evidenceRefs = [
    plan.planHash,
    window.windowHash,
    sha256File(reportPath),
    sha256OfValue(runEvidence),
  ];
  if (shard.decisionEvidenceRef) evidenceRefs.push(shard.decisionEvidenceRef);
  return createAttentionMeasurement({
    measurementId: `gate-f-${shard.shardId}-${timestampId(new Date(finishedAt))}`,
    campaignId: plan.campaignId,
    shardId: shard.shardId,
    shardKind: "unattended",
    shardKindDeclaredAt: startedAt,
    shardStartedAt: startedAt,
    shardFinishedAt: finishedAt,
    automationEvidence: {
      driver: "gate-fctl-v1",
      stdinMode: "disabled",
      interactivePromptCount: 0,
      operatorSignalCount: 0,
    },
    shardHumanActionCount: 0,
    opsBreakdown: { startup: 0, recovery: 0, exception: 0, closeout: 0, total: 0 },
    humanBlockedMinutes: 0,
    interruptCount: 0,
    eligibleEpochDelta: eligible ? 1 : 0,
    humanTouchDelta: 0,
    manualEditDelta: 0,
    exceptionCounts: exceptionCounts(args, plan),
    evidenceRefs,
    createdAt: finishedAt,
  });
}

function writeFailureException(supervisor, plan, shard, error, severity) {
  const now = new Date();
  const reason = safeId(error.code || "shard-failed", "shard-failed");
  const scopes = [`work:${shard.shardId}`].concat(shard.candidateIds.map((id) => `candidate:${id}`));
  const item = createExceptionInboxItem({
    exceptionId: `gate-f-${shard.shardId}-${reason}`,
    campaignId: plan.campaignId,
    dedupeKey: `gate-f|${shard.shardId}|${reason}`,
    category: "gate_f_shard_failure",
    severity: severity || "warning",
    status: "deferred",
    summary: error.message,
    affectedScopes: scopes,
    occurrences: [{
      occurrenceId: `occ-${timestampId(now)}`,
      observedAt: now.toISOString(),
      evidenceRef: sha256OfValue({ shardId: shard.shardId, code: error.code || null, message: error.message }),
    }],
    defaultAction: severity === "failed_closed" ? "quarantine" : "pause_scope",
    reviewDeadline: new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
  });
  return supervisor.recordException(item);
}

function writeCandidateTimeoutException(supervisor, plan, shard, rowHealth, reportPath) {
  const now = new Date();
  const scopes = [`work:${shard.shardId}`].concat(shard.candidateIds.map((id) => `candidate:${id}`));
  const reportSha256 = sha256File(reportPath);
  const item = createExceptionInboxItem({
    exceptionId: `gate-f-${shard.shardId}-candidate-timeout-rate`,
    campaignId: plan.campaignId,
    dedupeKey: `gate-f|${shard.shardId}|candidate-timeout-rate`,
    category: "candidate_timeout_anomaly",
    severity: "warning",
    status: "deferred",
    summary: `valid shard completed with ${rowHealth.timeouts}/${rowHealth.total} timeout rows; keep the original rows, continue the campaign, and exclude the timeout rows from strength fitting`,
    affectedScopes: scopes,
    occurrences: [{
      occurrenceId: `occ-${timestampId(now)}`,
      observedAt: now.toISOString(),
      evidenceRef: sha256OfValue({
        planHash: plan.planHash,
        shardId: shard.shardId,
        manifestHash: shard.manifestHash,
        reportSha256,
        total: rowHealth.total,
        timeouts: rowHealth.timeouts,
        timeoutRate: rowHealth.timeoutRate,
      }),
    }],
    defaultAction: "keep_provisional",
    reviewDeadline: new Date(now.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    createdAt: now.toISOString(),
    updatedAt: now.toISOString(),
  });
  return supervisor.recordException(item);
}

function supervisorFor(args, plan) {
  return new CampaignSupervisor({
    projectRoot: args.projectRoot,
    journalRoot: args.journalRoot,
    campaignId: plan.campaignId,
  });
}

function freshGrant(args, plan, window) {
  const now = new Date().toISOString();
  const observations = createProducerObservations(args.projectRoot, plan, window, { observedAt: now });
  const registry = createProducerRegistry(observations, {
    registryId: `gate-f-registry-${timestampId()}`,
    generatedAt: now,
    observationTtlSeconds: 60,
  });
  const grant = createIdleGrant(registry, {
    grantId: `gate-f-grant-${timestampId()}`,
    issuedAt: now,
    ttlSeconds: 300,
  });
  return { registry, grant };
}

function gateFDecisionPolicyId(plan) {
  return `gate-f-frozen-plan-v1:${plan.planHash}`;
}

function verifyJournalPlanBinding(supervisor, plan) {
  const created = supervisor.journal.state.events
    .map((entry) => entry.event)
    .find((event) => event.eventType === "campaign_created");
  if (!created || created.payload.decisionPolicyId !== gateFDecisionPolicyId(plan)
      || created.payload.battleSemanticsCohortId !== plan.battleSemanticsCohortId) {
    supervisor.release("gate_f_plan_binding_mismatch");
    fail("campaign journal belongs to a different Gate F plan or battle-semantics cohort", "gate_f_plan_binding_mismatch");
  }
}

function writeShardReceipt(supervisor, receipt) {
  const artifactDir = path.join(supervisor.journal.root, "artifacts");
  fs.mkdirSync(artifactDir, { recursive: true });
  const filePath = path.join(artifactDir, `gate-f-shard-receipt-${receipt.receiptId}.json`);
  writeJsonAtomic(filePath, receipt);
  supervisor.journal.append("gate_f_shard_receipt_recorded", {
    shardId: receipt.shardId,
    state: receipt.state,
    receiptId: receipt.receiptId,
    receiptHash: receipt.receiptHash,
    committedRows: receipt.committedRows,
    duplicatesExcluded: receipt.duplicatesExcluded,
  });
  return filePath;
}

async function runOneShard(args, plan, window, shard, priorReceipts) {
  verifyGateFPlan(args.projectRoot, plan);
  verifyIdleWindow(args.projectRoot, plan, window);
  const diskBefore = captureDiskHealth(args.projectRoot, plan.healthPolicy.minimumFreeBytes);
  if (!diskBefore.ok) fail("disk is below the frozen Gate F minimum", "disk_below_minimum");
  const { registry, grant } = freshGrant(args, plan, window);
  const supervisor = supervisorFor(args, plan);
  supervisor.acquire({ allowStaleRecovery: true });
  let paused = false;
  let receiptWritten = false;
  let runReportPathForFailure = null;
  const startedAt = new Date().toISOString();
  try {
    if (supervisor.snapshot().eventCount === 0) {
      supervisor.initialize({
        profile: "gate_f_week_v1",
        decisionPolicyId: gateFDecisionPolicyId(plan),
        battleSemanticsCohortId: plan.battleSemanticsCohortId,
        executionArtifactPolicy: "formal-runtime-row-exactly-once-v1",
        retentionDays: 90,
      }, registry, grant);
    } else {
      verifyJournalPlanBinding(supervisor, plan);
      supervisor.resume(registry, grant, `gate_f_${shard.shardId}`);
    }
    supervisor.scheduleShard({ shardId: shard.shardId, shardKind: "unattended", manifestPath: shard.manifestPath });

    const runDir = resolveOutput(
      args.projectRoot,
      path.join("tmp", "arena-calibration", "gate-f", plan.planId, "runs", `${shard.shardId}-${timestampId()}`),
      "Gate F run directory"
    );
    fs.mkdirSync(runDir, { recursive: true });
    const reportPath = path.join(runDir, "run-report.json");
    runReportPathForFailure = reportPath;
    const runnerArgs = [
      path.join(args.projectRoot, "tools", "arena-calibration", "run-unattended.js"),
      "--slot", plan.slot,
      "--seed-slot", plan.seedSlot,
      "--manifest", shard.manifestPath,
      "--batch-timeout-ms", String(shard.maxWallClockMinutes * 60 * 1000),
      "--max-recovery-attempts", String(shard.maxRecoveryAttempts),
      "--build-gate", "arena-tools",
      "--summary", path.join(runDir, "summary.json"),
      "--summary-md", path.join(runDir, "summary.md"),
      "--report", reportPath,
      "--report-md", path.join(runDir, "run-report.md"),
      "--rerun-manifest", path.join(runDir, "remaining-rerun-manifest.json"),
      "--shutdown",
    ];
    const childResult = await runChildWithMonitor(args, plan, window, shard, runDir, runnerArgs);
    writeJsonAtomic(path.join(runDir, "driver-process-result.json"), {
      schema: "arena-calibration.gate-f-driver-process-result.v1",
      ...childResult,
      stdoutSha256: sha256OfValue({ text: childResult.stdout }),
      stderrSha256: sha256OfValue({ text: childResult.stderr }),
    });
    if (!fs.existsSync(reportPath)) fail("unattended runner did not write its run report", "run_report_missing");
    const report = readJsonFile(reportPath);
    if (!report.runtimeIdentity || report.runtimeIdentity.verified !== true) {
      fail("unattended report did not verify its runtime identity", "runtime_identity_unverified");
    }
    compareRuntimeIdentity(plan.runtimeIdentity, report.runtimeIdentity);
    const attempts = readAttemptResults(args.projectRoot, report);
    const allRows = attempts.flatMap((entry) => entry.rows);
    const comparableShardIds = new Set(plan.shards
      .filter((entry) => JSON.stringify(entry.candidateIds) === JSON.stringify(shard.candidateIds))
      .map((entry) => entry.shardId));
    const baselineDurations = priorReceipts
      .filter((entry) => comparableShardIds.has(entry.shardId)
        && entry.state === "completed" && entry.health && entry.health.rows)
      .map((entry) => entry.health.rows.medianDurationMs)
      .filter(Number.isFinite)
      .sort((left, right) => left - right);
    const baselineMedian = baselineDurations.length > 0
      ? baselineDurations[Math.floor(baselineDurations.length / 2)] : null;
    const rowHealth = evaluateShardHealth(allRows, plan.healthPolicy, baselineMedian);
    const canonicalManifest = readJsonFile(resolveInsideRoot(args.projectRoot, shard.manifestPath, "Gate F shard manifest"));
    const allowCandidateTimeoutAnomaly = canonicalManifest.planner
      && ["standard", "long"].includes(canonicalManifest.planner.phase);
    const rowDisposition = classifyShardRowHealth(rowHealth, { allowCandidateTimeoutAnomaly });
    const diskAfter = captureDiskHealth(args.projectRoot, plan.healthPolicy.minimumFreeBytes);
    const finishedAt = report.completedAt || new Date().toISOString();
    const wallClockMinutes = Math.max(0, (Date.parse(finishedAt) - Date.parse(startedAt)) / 60000);
    const reportCompleted = report.status === "completed" && childResult.code === 0;
    const saveUnchanged = report.saveProtection && report.saveProtection.unchanged === true;
    const runtimeVerified = true;
    const withinWallClock = wallClockMinutes <= shard.maxWallClockMinutes + 1;
    const preliminaryOk = reportCompleted && saveUnchanged && runtimeVerified && diskAfter.ok
      && rowDisposition.executionOk && withinWallClock && allRows.length >= shard.plannedRuns;
    const yielded = report.status === "yielded" || Boolean(childResult.yieldReason);
    if (preliminaryOk && rowDisposition.candidateTimeoutAnomaly) {
      writeCandidateTimeoutException(supervisor, plan, shard, rowHealth, reportPath);
    }
    const measurement = createShardMeasurement(
      args,
      plan,
      window,
      shard,
      report,
      reportPath,
      {
        runner: "run-unattended.js",
        args: runnerArgs.map((entry) => projectRelative(args.projectRoot, entry).startsWith("..") ? path.basename(entry) : entry),
        exitCode: childResult.code,
        exitSignal: childResult.signal,
        yieldReason: childResult.yieldReason,
      },
      preliminaryOk && shard.eligibleEpoch
    );
    const executionArtifactIds = [];
    let committedRows = 0;
    let duplicatesExcluded = 0;
    const lastAttemptIndex = attempts.length - 1;
    attempts.forEach((entry, index) => {
      const isLast = index === lastAttemptIndex;
      const imported = supervisor.importShard({
        shardId: shard.shardId,
        shardKind: "unattended",
        manifestPath: projectRelative(args.projectRoot, entry.manifestPath),
        resultPath: projectRelative(args.projectRoot, entry.resultPath),
        runReportPath: projectRelative(args.projectRoot, reportPath),
        battleSemanticsCohortId: plan.battleSemanticsCohortId,
        changedPaths: [],
        compatible: true,
        allowPartial: true,
        complete: isLast && preliminaryOk,
        gateFPlanHash: plan.planHash,
        recordAttention: isLast,
        attentionMeasurement: isLast ? measurement : null,
        attentionPolicy: plan.attentionPolicy,
      });
      executionArtifactIds.push(imported.artifact.artifactId);
      committedRows += imported.disposition.acceptedCount;
      duplicatesExcluded += imported.disposition.duplicateCount;
    });
    if (attempts.length === 0) supervisor.recordAttentionMeasurement(measurement, plan.attentionPolicy);
    const state = preliminaryOk ? "completed" : (yielded ? "yielded" : "failed");
    const fatal = !saveUnchanged || !runtimeVerified || !diskAfter.ok;
    const health = {
      ok: preliminaryOk,
      fatal,
      reportCompleted,
      saveUnchanged,
      runtimeVerified,
      withinWallClock,
      diskBefore,
      diskAfter,
      rows: rowHealth,
      rowDisposition,
    };
    const reason = preliminaryOk ? null
      : (childResult.yieldReason ? childResult.yieldReason.message
        : (report.error && report.error.message) || `runner status=${report.status}`);
    if (state === "failed") {
      writeFailureException(supervisor, plan, shard, {
        code: fatal ? "gate_f_fatal_health" : "gate_f_shard_failed",
        message: reason,
      }, fatal ? "failed_closed" : "warning");
    }
    const receipt = createGateFShardReceipt({
      receiptId: `${safeId(shard.shardId, "shard")}-${timestampId(new Date(finishedAt))}`,
      planHash: plan.planHash,
      campaignId: plan.campaignId,
      shardId: shard.shardId,
      manifestHash: shard.manifestHash,
      state,
      runReportPath: projectRelative(args.projectRoot, reportPath),
      runReportSha256: sha256File(reportPath),
      executionArtifactIds,
      committedRows,
      duplicatesExcluded,
      recoveryAttemptsUsed: report.recoveryAttemptsUsed || 0,
      health,
      startedAt,
      finishedAt,
      wallClockMinutes,
      yieldLatencySeconds: childResult.yieldLatencySeconds,
      reason,
    });
    writeShardReceipt(supervisor, receipt);
    receiptWritten = true;
    supervisor.pause(`gate_f_${state}`, { resourcesReleased: true });
    paused = true;
    return receipt;
  } catch (error) {
    if (!receiptWritten && supervisor.journal.lease) {
      try {
        const finishedAt = new Date().toISOString();
        const reportExists = Boolean(runReportPathForFailure && fs.existsSync(runReportPathForFailure));
        const fatalCodes = ["runtime_identity_drift", "runtime_identity_unverified", "source_identity_drift", "disk_below_minimum"];
        const receipt = createGateFShardReceipt({
          receiptId: `${safeId(shard.shardId, "shard")}-${timestampId(new Date(finishedAt))}`,
          planHash: plan.planHash,
          campaignId: plan.campaignId,
          shardId: shard.shardId,
          manifestHash: shard.manifestHash,
          state: "failed",
          runReportPath: reportExists ? projectRelative(args.projectRoot, runReportPathForFailure) : null,
          runReportSha256: reportExists ? sha256File(runReportPathForFailure) : null,
          executionArtifactIds: [],
          committedRows: 0,
          duplicatesExcluded: 0,
          recoveryAttemptsUsed: 0,
          health: {
            ok: false,
            fatal: fatalCodes.includes(error.code),
            failureCode: error.code || "gate_f_shard_exception",
          },
          startedAt,
          finishedAt,
          wallClockMinutes: Math.max(0, (Date.parse(finishedAt) - Date.parse(startedAt)) / 60000),
          yieldLatencySeconds: null,
          reason: error.message,
        });
        writeShardReceipt(supervisor, receipt);
        receiptWritten = true;
      } catch (_receiptError) { }
    }
    try {
      writeFailureException(supervisor, plan, shard, error, ["runtime_identity_drift", "runtime_identity_unverified", "source_identity_drift", "disk_below_minimum"].includes(error.code)
        ? "failed_closed" : "warning");
    } catch (_inboxError) { }
    throw error;
  } finally {
    if (!paused && supervisor.journal.lease) {
      try { supervisor.pause("gate_f_exception", { resourcesReleased: true }); }
      catch (_pauseError) { try { supervisor.release("gate_f_exception"); } catch (_releaseError) { } }
    }
  }
}

async function commandRun(args) {
  if ((!Number.isInteger(args.maxShards) && args.maxShards !== Number.POSITIVE_INFINITY) || args.maxShards < 1) {
    fail("--max-shards must be a positive integer", "usage_error");
  }
  const { plan } = readPlan(args.projectRoot, requireArg(args, "plan"));
  const { window } = readWindow(args.projectRoot, plan, requireArg(args, "window"));
  const priorReceipts = readArtifacts(args, plan, /^gate-f-shard-receipt-.*\.json$/i, "arena-calibration.gate-f-shard-receipt.v1")
    .map(verifyShardReceipt)
    .filter((entry) => entry.planHash === plan.planHash);
  const completed = latestReceipts(priorReceipts);
  const remaining = plan.shards.filter((shard) => !completed.has(shard.shardId)
    || completed.get(shard.shardId).state !== "completed").slice(0, args.maxShards);
  const receipts = [];
  for (const shard of remaining) {
    const receipt = await runOneShard(args, plan, window, shard, priorReceipts.concat(receipts));
    receipts.push(receipt);
    if (receipt.state !== "completed") break;
  }
  const status = buildStatus(args, plan);
  return { ok: status.state !== "FAILED_CLOSED", receipts, status };
}

function commandStatus(args) {
  const { plan } = readPlan(args.projectRoot, requireArg(args, "plan"), { skipSource: true, skipRuntime: true });
  const status = buildStatus(args, plan);
  if (args.output) {
    const outputPath = resolveOutput(args.projectRoot, args.output, "Gate F status output");
    writeJsonAtomic(outputPath, status);
  }
  return { ok: true, status };
}

function commandRevoke(args) {
  const { plan } = readPlan(args.projectRoot, requireArg(args, "plan"), { skipSource: true, skipRuntime: true });
  const windowPath = resolveInput(args.projectRoot, requireArg(args, "window"), "Gate F idle window");
  const window = readJsonFile(windowPath);
  assertSchemaInstance("arena-calibration.gate-f-idle-window.v1", window, "Gate F idle window");
  if (window.windowHash !== sha256OfValue(withoutHash(window, "windowHash"))) {
    fail("Gate F idle window hash mismatch", "idle_window_hash_mismatch");
  }
  if (window.campaignId !== plan.campaignId || window.planHash !== plan.planHash) {
    fail("idle window is not bound to the supplied Gate F plan", "idle_window_plan_mismatch");
  }
  const revokePath = resolveOutput(args.projectRoot, window.revokeFile, "Gate F revoke file");
  writeYieldSignal(revokePath, { code: "operator_revoke", message: "Gate F idle window revoked by explicit command" });
  return { ok: true, state: "REVOKED", revokeFile: projectRelative(args.projectRoot, revokePath) };
}

function runCheck() {
  const parsed = parseArgs(["run", "--plan", "tmp/plan.json", "--window", "tmp/window.json", "--max-shards", "3"]);
  if (parsed.command !== "run" || parsed.maxShards !== 3) fail("Gate F CLI parsing check failed");
  let rejected = false;
  try { resolveOutput(ROOT, "../outside.json", "check output"); }
  catch (_error) { rejected = true; }
  if (!rejected) fail("Gate F output path boundary check failed");
  console.log(JSON.stringify({
    ok: true,
    check: "gate-fctl-contract",
    commands: ["freeze", "arm", "run", "status", "revoke"],
    stdinMode: "disabled",
    defaultMaxShards: "all_remaining",
  }));
}

async function main(argv) {
  const args = parseArgs(argv);
  if (args.check) return runCheck();
  if (args.command === "help") return printHelp();
  let result;
  if (args.command === "freeze") result = commandFreeze(args);
  else if (args.command === "arm") result = commandArm(args);
  else if (args.command === "run") result = await commandRun(args);
  else if (args.command === "status") result = commandStatus(args);
  else if (args.command === "revoke") result = commandRevoke(args);
  else fail(`unknown command: ${args.command}`, "usage_error");
  console.log(JSON.stringify(result, null, 2));
  if (result.ok === false) process.exitCode = 1;
}

main(process.argv.slice(2)).catch((error) => {
  console.error(JSON.stringify({
    ok: false,
    code: error.code || null,
    message: error.message,
    details: error.details || null,
  }, null, 2));
  process.exit(error.code === "usage_error" ? 2 : 1);
});
