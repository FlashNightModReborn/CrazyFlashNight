#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const Ajv2020 = require("ajv/dist/2020");
const {
  extractFinalAgentMessage,
  parseJsonl,
  spawnCaptured,
} = require("../portrait-worker/lib/codex-cli-luna-worker");
const {
  readJsonFile,
  sha256OfValue,
} = require("./lib/arena-calibration-core");
const {
  validateProposalAgainstSnapshot,
} = require("./lib/campaign-contracts");
const {
  assertSchemaInstance,
} = require("./lib/schema-registry");

const PROMPT_POLICY_VERSION = "gate-c-shadow-cli-v1";
const PROFILES = Object.freeze([
  { profile: "A_sol_manager_only", model: "gpt-5.6-sol", role: "manager", label: "A-sol-manager" },
  { profile: "B_luna_manager_only", model: "gpt-5.6-luna", role: "manager", label: "B-luna-manager" },
  { profile: "C_luna_propose_sol_adjudicate", model: "gpt-5.6-luna", role: "worker", label: "C-luna-draft", intermediate: true },
  { profile: "C_luna_propose_sol_adjudicate", model: "gpt-5.6-sol", role: "adjudicator", label: "C-sol-adjudicator" },
]);

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    requestsDir: null,
    outputDir: null,
    codexExe: null,
    timeoutMs: 600000,
    serviceTier: "fast",
    reasoningEffort: "high",
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--requests-dir") options.requestsDir = path.resolve(argv[++index]);
    else if (token === "--output-dir") options.outputDir = path.resolve(argv[++index]);
    else if (token === "--codex-exe") options.codexExe = path.resolve(argv[++index]);
    else if (token === "--timeout-ms") options.timeoutMs = Number(argv[++index]);
    else if (token === "--service-tier") options.serviceTier = String(argv[++index]);
    else if (token === "--reasoning-effort") options.reasoningEffort = String(argv[++index]);
    else if (token === "--check") options.check = true;
    else if (token === "--help" || token === "-h") options.help = true;
    else fail(`unknown argument: ${token}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 30000 || options.timeoutMs > 1800000) {
    fail("--timeout-ms must be an integer between 30000 and 1800000");
  }
  if (!["standard", "fast"].includes(options.serviceTier)) fail("--service-tier must be standard or fast");
  if (!["low", "medium", "high", "xhigh", "max"].includes(options.reasoningEffort)) {
    fail("--reasoning-effort must be low, medium, high, xhigh, or max");
  }
  return options;
}

function usage() {
  return [
    "Usage: node tools/arena-calibration/run-shadow-models.js --requests-dir <dir> --output-dir <dir> --codex-exe <absolute exe>",
    "  --timeout-ms <ms>            Per-model hard limit, default 600000",
    "  --service-tier fast|standard Default fast",
    "  --reasoning-effort <effort>  Default high",
    "  --check                      Compile the generated output contract without calling a model",
  ].join("\n");
}

function sha256Buffer(value) {
  return `sha256:${crypto.createHash("sha256").update(value).digest("hex")}`;
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function stableClone(value) {
  if (Array.isArray(value)) return value.map(stableClone);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.keys(value).sort().map((key) => [key, stableClone(value[key])]));
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableClone(value));
}

function writeImmutable(filePath, bytes) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const content = Buffer.isBuffer(bytes) ? bytes : Buffer.from(String(bytes), "utf8");
  if (fs.existsSync(filePath)) {
    const prior = fs.readFileSync(filePath);
    if (!prior.equals(content)) throw new Error(`immutable evidence already exists with different bytes: ${filePath}`);
    return;
  }
  fs.writeFileSync(filePath, content, { flag: "wx" });
}

function writeImmutableJson(filePath, value) {
  writeImmutable(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function budgetSchema(maxRuns) {
  return {
    type: "object",
    additionalProperties: false,
    required: ["maxRuns", "maxFrames", "maxWallClockMinutes", "maxHumanMinutes"],
    properties: {
      maxRuns: { type: "integer", minimum: 1, maximum: maxRuns },
      maxFrames: { type: "integer", minimum: 1, maximum: 225000 },
      maxWallClockMinutes: { type: "integer", minimum: 1, maximum: 120 },
      maxHumanMinutes: { type: "integer", const: 0 },
    },
  };
}

function outputSchemaFor(request, spec, identifiers) {
  const snapshot = request.decisionSnapshot;
  const evidenceRefs = Array.from(new Set([snapshot.snapshotHash, ...(snapshot.committedResultRefs || [])]));
  const candidateIds = snapshot.caseCatalog.map((entry) => entry.candidateId);
  const caseHashes = snapshot.caseCatalog.map((entry) => entry.caseHash);
  const action = {
    type: "object",
    additionalProperties: false,
    required: [
      "actionId", "action", "riskLevel", "budget", "expectedInformationGain", "evidenceRefs",
      "confidence", "preconditions", "candidateId", "caseHash", "sideAssignment", "additionalRuns",
    ],
    properties: {
      actionId: { type: "string", pattern: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$" },
      action: { type: "string", const: "append_samples" },
      riskLevel: { type: "string", const: "auto_execute" },
      budget: budgetSchema(25),
      expectedInformationGain: { type: "number", minimum: 0, maximum: 1 },
      evidenceRefs: { type: "array", minItems: 1, items: { type: "string", enum: evidenceRefs } },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      preconditions: {
        type: "object",
        additionalProperties: false,
        required: ["campaignStates", "requiresIdleGrant", "snapshotHash"],
        properties: {
          campaignStates: { type: "array", minItems: 1, maxItems: 1, items: { type: "string", const: "RUNNING" } },
          requiresIdleGrant: { type: "boolean", const: true },
          snapshotHash: { type: "string", const: snapshot.snapshotHash },
        },
      },
      candidateId: { type: "string", enum: candidateIds },
      caseHash: { type: "string", enum: caseHashes },
      sideAssignment: { type: "string", enum: ["original", "swapped"] },
      additionalRuns: { type: "integer", minimum: 1, maximum: 25 },
    },
  };
  return {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    type: "object",
    additionalProperties: false,
    required: [
      "schema", "proposalId", "decisionSnapshotId", "modelProfile", "role", "generatedAt", "actions",
      "totalBudget", "evidenceRefs", "risks", "counterexamples", "confidence", "abstain", "requiresHuman",
    ],
    properties: {
      schema: { type: "string", const: "arena-calibration.controller-proposal.v1" },
      proposalId: { type: "string", const: identifiers.proposalId },
      decisionSnapshotId: { type: "string", const: snapshot.decisionSnapshotId },
      modelProfile: { type: "string", const: spec.profile },
      role: { type: "string", const: spec.role },
      generatedAt: { type: "string", const: identifiers.generatedAt },
      actions: { type: "array", minItems: 1, maxItems: Math.min(5, candidateIds.length), items: action },
      totalBudget: budgetSchema(Math.min(100, snapshot.remainingBudget.maxRuns)),
      evidenceRefs: { type: "array", minItems: 1, items: { type: "string", enum: evidenceRefs } },
      risks: { type: "array", minItems: 1, maxItems: 8, items: { type: "string", minLength: 1 } },
      counterexamples: { type: "array", minItems: 1, maxItems: 8, items: { type: "string", minLength: 1 } },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      abstain: { type: "boolean", const: false },
      requiresHuman: { type: "boolean", const: false },
    },
  };
}

function catalogPairs(snapshot) {
  return snapshot.caseCatalog.map((entry) => ({ candidateId: entry.candidateId, caseHash: entry.caseHash }));
}

function createPrompt(request, spec, identifiers, priorDraft, correction) {
  const snapshot = request.decisionSnapshot;
  const evidenceRefs = Array.from(new Set([snapshot.snapshotHash, ...(snapshot.committedResultRefs || [])]));
  const roleText = spec.role === "adjudicator"
    ? "You are the final adjudicator. Critically inspect the Luna draft, then keep or replace its sampling choices."
    : "You are an independent experiment manager. Select the smallest high-information fresh sampling plan.";
  const draftText = priorDraft ? `\nLUNA_DRAFT_JSON\n${stableStringify(priorDraft)}\n` : "";
  const correctionText = correction ? `\nYOUR PREVIOUS OUTPUT FAILED VALIDATION\n${correction}\nReturn a corrected full proposal.\n` : "";
  return [
    "You are participating in a blind, read-only arena-calibration shadow evaluation.",
    roleText,
    "Do not call tools, inspect files, execute the plan, alter the snapshot, complete a candidate, or enqueue PVE.",
    "Return only one JSON object matching the supplied output schema.",
    "Only append_samples is permitted in this response. Prioritize missing swapped-side evidence, then timeout-sensitive or weakly connected cases.",
    "Use only an exact candidateId/caseHash pair from CATALOG_PAIRS. Do not mix a candidate with another case hash.",
    "For every action: budget.maxRuns must equal additionalRuns; budget.maxFrames must equal additionalRuns * 1800; budget.maxWallClockMinutes must equal additionalRuns * 2; maxHumanMinutes is 0.",
    "The totalBudget fields must exactly equal the sum of all action budgets. Do not duplicate candidateId/caseHash/sideAssignment.",
    "Use only the listed evidence hashes. Preconditions are exactly campaignStates=[RUNNING], requiresIdleGrant=true, and the frozen snapshotHash.",
    `Frozen proposalId: ${identifiers.proposalId}`,
    `Frozen generatedAt: ${identifiers.generatedAt}`,
    `CATALOG_PAIRS ${stableStringify(catalogPairs(snapshot))}`,
    `ALLOWED_EVIDENCE_REFS ${stableStringify(evidenceRefs)}`,
    draftText,
    correctionText,
    `SHADOW_REQUEST_JSON\n${stableStringify(request)}`,
  ].join("\n");
}

function sumBudgets(actions) {
  return actions.reduce((sum, action) => ({
    maxRuns: sum.maxRuns + action.budget.maxRuns,
    maxFrames: sum.maxFrames + action.budget.maxFrames,
    maxWallClockMinutes: sum.maxWallClockMinutes + action.budget.maxWallClockMinutes,
    maxHumanMinutes: sum.maxHumanMinutes + action.budget.maxHumanMinutes,
  }), { maxRuns: 0, maxFrames: 0, maxWallClockMinutes: 0, maxHumanMinutes: 0 });
}

function assertExactProposal(proposal, request, spec) {
  const snapshot = request.decisionSnapshot;
  assertSchemaInstance("arena-calibration.controller-proposal.v1", proposal, "model controller proposal");
  if (proposal.modelProfile !== spec.profile || proposal.role !== spec.role) throw new Error("model profile/role mismatch");
  validateProposalAgainstSnapshot(proposal, snapshot, "RUNNING");
  const pairSet = new Set(catalogPairs(snapshot).map((entry) => `${entry.candidateId}\u0000${entry.caseHash}`));
  const actionKeys = new Set();
  proposal.actions.forEach((action) => {
    if (action.action !== "append_samples") throw new Error(`runner policy rejects action ${action.action}`);
    if (!pairSet.has(`${action.candidateId}\u0000${action.caseHash}`)) throw new Error("action candidateId/caseHash pair is not in the frozen catalog");
    const actionKey = `${action.candidateId}\u0000${action.caseHash}\u0000${action.sideAssignment}`;
    if (actionKeys.has(actionKey)) throw new Error("duplicate candidate/case/side action");
    actionKeys.add(actionKey);
    if (action.budget.maxRuns !== action.additionalRuns) throw new Error("action maxRuns must equal additionalRuns");
    if (action.budget.maxFrames !== action.additionalRuns * 1800) throw new Error("action maxFrames must equal additionalRuns * 1800");
    if (action.budget.maxWallClockMinutes !== action.additionalRuns * 2) throw new Error("action wall-clock budget must equal additionalRuns * 2");
  });
  const summed = sumBudgets(proposal.actions);
  if (stableStringify(summed) !== stableStringify(proposal.totalBudget)) throw new Error("proposal totalBudget is not the exact action-budget sum");
  return true;
}

function usageFromEvents(events) {
  const completed = events.find(({ event }) => event.type === "turn.completed");
  const raw = completed && completed.event && completed.event.usage && typeof completed.event.usage === "object"
    ? completed.event.usage
    : {};
  const input = Number(raw.input_tokens || raw.inputTokens || 0);
  const output = Number(raw.output_tokens || raw.outputTokens || 0);
  return { ...raw, totalTokens: Number(raw.total_tokens || raw.totalTokens || input + output) };
}

function cliIdentity(executablePath) {
  const version = childProcess.execFileSync(executablePath, ["--version"], {
    encoding: "utf8",
    windowsHide: true,
    timeout: 30000,
  }).trim();
  return {
    executablePath,
    executableSha256: sha256File(executablePath),
    version,
  };
}

function stagePaths(outputDir, spec) {
  const base = spec.intermediate ? path.join(outputDir, "intermediate", spec.label) : path.join(outputDir, spec.label);
  return {
    base,
    proposal: path.join(base, "proposal.json"),
    receipt: path.join(base, "receipt.json"),
    evidence: path.join(base, "model-evidence.json"),
    schema: path.join(base, "controller-output.schema.json"),
  };
}

function loadCompletedStage(paths, request, spec) {
  if (![paths.proposal, paths.receipt, paths.evidence].every(fs.existsSync)) return null;
  const proposal = readJsonFile(paths.proposal);
  const receipt = readJsonFile(paths.receipt);
  const evidence = readJsonFile(paths.evidence);
  assertExactProposal(proposal, request, spec);
  assertSchemaInstance("arena-calibration.decision-receipt.v1", receipt, "model decision receipt");
  if (receipt.proposalHash !== sha256OfValue(proposal) || receipt.outcome !== "accepted") {
    throw new Error(`completed stage receipt closure is invalid: ${spec.label}`);
  }
  return { proposal, receipt, evidence, resumed: true };
}

async function runStage(options, request, spec, priorDraft, cli) {
  const paths = stagePaths(options.outputDir, spec);
  const completed = loadCompletedStage(paths, request, spec);
  if (completed) {
    process.stdout.write(`${JSON.stringify({ event: "shadow_stage_resumed", stage: spec.label, proposalHash: completed.receipt.proposalHash })}\n`);
    return completed;
  }
  fs.mkdirSync(paths.base, { recursive: true });
  const generatedAt = new Date().toISOString();
  const proposalId = spec.intermediate
    ? `draft-${request.experimentId}-C-luna`
    : `proposal-${request.experimentId}-${spec.label}`;
  const identifiers = { proposalId, generatedAt };
  const outputSchema = outputSchemaFor(request, spec, identifiers);
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  if (!ajv.validateSchema(outputSchema)) throw new Error(`generated output schema is invalid: ${ajv.errorsText()}`);
  writeImmutableJson(paths.schema, outputSchema);
  let correction = null;
  const attempts = [];
  for (let attemptNumber = 1; attemptNumber <= 2; attemptNumber += 1) {
    const prompt = createPrompt(request, spec, identifiers, priorDraft, correction);
    const attemptDir = path.join(paths.base, `attempt-${String(attemptNumber).padStart(2, "0")}`);
    writeImmutable(path.join(attemptDir, "prompt.txt"), prompt);
    const args = [
      "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
      "--model", spec.model,
      "--config", `model_reasoning_effort=${JSON.stringify(options.reasoningEffort)}`,
      "--config", 'approval_policy="never"',
      ...(options.serviceTier === "fast" ? ["--config", 'service_tier="fast"', "--config", "features.fast_mode=true"] : []),
      "--sandbox", "read-only",
      "--cd", options.isolatedCwd,
      "--skip-git-repo-check",
      "--output-schema", paths.schema,
      "--json", "-",
    ];
    process.stdout.write(`${JSON.stringify({ event: "shadow_stage_started", stage: spec.label, attempt: attemptNumber, model: spec.model })}\n`);
    const capture = await spawnCaptured({
      command: options.codexExe,
      args,
      cwd: options.isolatedCwd,
      env: { ...process.env, NO_COLOR: "1" },
      stdin: prompt,
      timeoutMs: options.timeoutMs,
    });
    writeImmutable(path.join(attemptDir, "stdout.jsonl"), capture.stdout);
    writeImmutable(path.join(attemptDir, "stderr.txt"), capture.stderr);
    const captureSummary = {
      attemptNumber,
      pid: capture.pid,
      startedAt: capture.startedAt,
      endedAt: capture.endedAt,
      durationMs: capture.durationMs,
      exitCode: capture.exitCode,
      signal: capture.signal,
      timedOut: capture.timedOut,
      overflowStream: capture.overflowStream,
      terminationReason: capture.terminationReason,
      knownDescendantPids: capture.knownDescendantPids,
      normalExitOrphanPids: capture.normalExitOrphanPids,
      descendantScanFailed: capture.descendantScanFailed,
      descendantScanFailures: capture.descendantScanFailures,
      terminatedTreePids: capture.termination.targetPids,
      survivorPids: capture.termination.survivorPids,
      stdoutBytes: capture.stdoutBytes,
      stderrBytes: capture.stderrBytes,
      stdoutSha256: sha256Buffer(Buffer.from(capture.stdout, "utf8")),
      stderrSha256: sha256Buffer(Buffer.from(capture.stderr, "utf8")),
    };
    attempts.push(captureSummary);
    writeImmutableJson(path.join(attemptDir, "capture.json"), captureSummary);
    try {
      if (capture.exitCode !== 0 || capture.timedOut || capture.overflowStream) throw new Error(`Codex CLI exit was not clean: exit=${capture.exitCode}, timeout=${capture.timedOut}`);
      if (capture.descendantScanFailed || capture.normalExitOrphanPids.length > 0 || capture.termination.survivorPids.length > 0) {
        throw new Error("Codex CLI process-tree closure failed");
      }
      const events = parseJsonl(capture.stdout);
      const finalMessage = extractFinalAgentMessage(events);
      const proposal = JSON.parse(finalMessage.text);
      assertExactProposal(proposal, request, spec);
      if (proposal.proposalId !== proposalId || proposal.generatedAt !== generatedAt) throw new Error("frozen proposal identifiers changed");
      const receipt = {
        schema: "arena-calibration.decision-receipt.v1",
        receiptId: `receipt-${proposalId}`,
        proposalId,
        proposalHash: sha256OfValue(proposal),
        decisionSnapshotId: request.decisionSnapshot.decisionSnapshotId,
        modelProfile: spec.profile,
        role: spec.role,
        promptPolicyVersion: PROMPT_POLICY_VERSION,
        durationMs: capture.durationMs,
        usage: usageFromEvents(events),
        validation: {
          controllerProposalSchema: true,
          frozenSnapshotReferences: true,
          exactBudgetClosure: true,
          processTreeClosed: true,
        },
        outcome: "accepted",
        campaignState: "PAUSED",
        acceptedActionIds: proposal.actions.map((action) => action.actionId),
        rejectedActionIds: [],
        fallback: "none",
        createdAt: capture.endedAt,
      };
      assertSchemaInstance("arena-calibration.decision-receipt.v1", receipt, "model decision receipt");
      const evidence = {
        schema: "arena-calibration.shadow-model-evidence.v1",
        stage: spec.label,
        requestId: request.requestId,
        requestHash: sha256OfValue(request),
        outputSchemaSha256: sha256File(paths.schema),
        promptSha256: sha256Buffer(Buffer.from(prompt, "utf8")),
        modelRequested: spec.model,
        reasoningEffort: options.reasoningEffort,
        serviceTier: options.serviceTier,
        cli,
        acceptedAttempt: attemptNumber,
        threadId: finalMessage.threadId,
        agentMessageCount: finalMessage.agentMessageCount,
        recoverableDiagnostics: finalMessage.recoverableDiagnostics,
        attempts,
        proposalHash: receipt.proposalHash,
        completedAt: capture.endedAt,
      };
      writeImmutableJson(paths.proposal, proposal);
      writeImmutableJson(paths.receipt, receipt);
      writeImmutableJson(paths.evidence, evidence);
      process.stdout.write(`${JSON.stringify({ event: "shadow_stage_accepted", stage: spec.label, proposalHash: receipt.proposalHash, durationMs: capture.durationMs })}\n`);
      return { proposal, receipt, evidence, resumed: false };
    } catch (error) {
      correction = String(error && error.message ? error.message : error).slice(0, 1200);
      writeImmutableJson(path.join(attemptDir, "validation-error.json"), {
        schema: "arena-calibration.shadow-model-attempt-error.v1",
        stage: spec.label,
        attemptNumber,
        error: correction,
        createdAt: new Date().toISOString(),
      });
      process.stdout.write(`${JSON.stringify({ event: "shadow_stage_retryable_failure", stage: spec.label, attempt: attemptNumber, error: correction })}\n`);
    }
  }
  throw new Error(`${spec.label} failed after two bounded attempts: ${correction}`);
}

function loadRequests(requestsDir) {
  const requests = new Map();
  for (const profile of new Set(PROFILES.map((entry) => entry.profile))) {
    const requestPath = path.join(requestsDir, `${profile}-request.json`);
    if (!fs.existsSync(requestPath)) throw new Error(`shadow request is missing: ${requestPath}`);
    const request = readJsonFile(requestPath);
    if (request.profile !== profile || request.outputSchema !== "arena-calibration.controller-proposal.v1") {
      throw new Error(`shadow request profile/output schema mismatch: ${requestPath}`);
    }
    assertSchemaInstance("arena-calibration.decision-snapshot.v1", request.decisionSnapshot, "shadow request decision snapshot");
    requests.set(profile, request);
  }
  const experimentIds = new Set([...requests.values()].map((entry) => entry.experimentId));
  const snapshotHashes = new Set([...requests.values()].map((entry) => entry.decisionSnapshot.snapshotHash));
  if (experimentIds.size !== 1 || snapshotHashes.size !== 1) throw new Error("shadow requests do not share one experiment/snapshot");
  return requests;
}

function checkContract() {
  const hash = `sha256:${"a".repeat(64)}`;
  const request = {
    profile: "A_sol_manager_only",
    decisionSnapshot: {
      decisionSnapshotId: "snapshot-check",
      snapshotHash: hash,
      caseCatalog: [{ candidateId: "candidate-check", caseHash: hash }],
      committedResultRefs: [hash],
      remainingBudget: { maxRuns: 100, maxFrames: 180000, maxWallClockMinutes: 120, maxHumanMinutes: 15 },
    },
  };
  const spec = PROFILES[0];
  const schema = outputSchemaFor(request, spec, { proposalId: "proposal-check", generatedAt: "2026-08-27T00:00:00.000Z" });
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  if (!ajv.validateSchema(schema)) throw new Error(ajv.errorsText());
  process.stdout.write(`${JSON.stringify({ ok: true, check: "shadow-model-output-contract", profiles: 3, modelInvocations: 4 })}\n`);
}

async function main(argv) {
  const options = parseArgs(argv);
  if (options.help) {
    process.stdout.write(`${usage()}\n`);
    return;
  }
  if (options.check) return checkContract();
  if (!options.requestsDir || !options.outputDir || !options.codexExe) fail("--requests-dir, --output-dir, and --codex-exe are required");
  if (!path.isAbsolute(options.codexExe) || !fs.existsSync(options.codexExe)) fail("--codex-exe must be an existing absolute file");
  fs.mkdirSync(options.outputDir, { recursive: true });
  options.isolatedCwd = path.join(options.outputDir, "isolated-cwd");
  fs.mkdirSync(options.isolatedCwd, { recursive: true });
  const requests = loadRequests(options.requestsDir);
  const cli = cliIdentity(options.codexExe);
  const results = [];
  let lunaDraft = null;
  for (const spec of PROFILES) {
    const request = requests.get(spec.profile);
    const result = await runStage(options, request, spec, spec.role === "adjudicator" ? lunaDraft : null, cli);
    if (spec.intermediate) lunaDraft = result.proposal;
    else results.push({ spec, ...result });
  }
  const summary = {
    schema: "arena-calibration.shadow-model-run-summary.v1",
    experimentId: results[0].proposal.proposalId.split("-A-sol-manager")[0].replace(/^proposal-/, ""),
    snapshotHash: requests.values().next().value.decisionSnapshot.snapshotHash,
    promptPolicyVersion: PROMPT_POLICY_VERSION,
    cli,
    serviceTier: options.serviceTier,
    reasoningEffort: options.reasoningEffort,
    proposals: results.map((entry) => ({
      profile: entry.spec.profile,
      model: entry.spec.model,
      role: entry.spec.role,
      proposalPath: path.relative(options.outputDir, stagePaths(options.outputDir, entry.spec).proposal).replaceAll("\\", "/"),
      receiptPath: path.relative(options.outputDir, stagePaths(options.outputDir, entry.spec).receipt).replaceAll("\\", "/"),
      proposalHash: entry.receipt.proposalHash,
      resumed: entry.resumed,
    })),
    intermediateDraftHash: sha256OfValue(lunaDraft),
    completedAt: new Date().toISOString(),
  };
  writeImmutableJson(path.join(options.outputDir, "shadow-model-run-summary.json"), summary);
  process.stdout.write(`${JSON.stringify({ ok: true, event: "shadow_models_complete", proposals: summary.proposals, summaryHash: sha256OfValue(summary) })}\n`);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.isUsageError ? 2 : 1;
  });
}

module.exports = {
  assertExactProposal,
  createPrompt,
  outputSchemaFor,
  parseArgs,
};
