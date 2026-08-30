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
const { readJsonFile, sha256OfValue } = require("./lib/arena-calibration-core");
const { assertSchemaInstance } = require("./lib/schema-registry");

const PROMPT_POLICY_VERSION = "gate-f-exception-review-v1";
const RECOMMENDATIONS = [
  "confirm_quarantine",
  "likely_legitimate_spawn",
  "request_method_change",
  "abstain",
];

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    request: null,
    outputDir: null,
    codexExe: null,
    model: "gpt-5.6-sol",
    timeoutMs: 300000,
    serviceTier: "fast",
    reasoningEffort: "high",
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--request") options.request = path.resolve(argv[++index]);
    else if (token === "--output-dir") options.outputDir = path.resolve(argv[++index]);
    else if (token === "--codex-exe") options.codexExe = path.resolve(argv[++index]);
    else if (token === "--model") options.model = String(argv[++index]);
    else if (token === "--timeout-ms") options.timeoutMs = Number(argv[++index]);
    else if (token === "--service-tier") options.serviceTier = String(argv[++index]);
    else if (token === "--reasoning-effort") options.reasoningEffort = String(argv[++index]);
    else if (token === "--check") options.check = true;
    else if (token === "--help" || token === "-h") options.help = true;
    else fail(`unknown argument: ${token}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 30000 || options.timeoutMs > 600000) {
    fail("--timeout-ms must be an integer between 30000 and 600000");
  }
  if (!options.model || /[\0\r\n]/.test(options.model)) fail("--model is invalid");
  if (!["standard", "fast"].includes(options.serviceTier)) fail("--service-tier must be standard or fast");
  if (!["low", "medium", "high", "xhigh", "max"].includes(options.reasoningEffort)) {
    fail("--reasoning-effort must be low, medium, high, xhigh, or max");
  }
  return options;
}

function usage() {
  return [
    "Usage: node tools/arena-calibration/run-exception-review.js --request <json> --output-dir <dir> --codex-exe <absolute exe>",
    "  --model <id>                 Default gpt-5.6-sol",
    "  --timeout-ms <ms>            Default 300000; maximum 600000",
    "  --service-tier fast|standard Default fast",
    "  --reasoning-effort <effort>  Default high",
    "  --check                      Compile and exercise the output contract without calling a model",
  ].join("\n");
}

function sha256Buffer(value) {
  return `sha256:${crypto.createHash("sha256").update(value).digest("hex")}`;
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
}

function writeImmutable(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const content = Buffer.isBuffer(value) ? value : Buffer.from(String(value), "utf8");
  if (fs.existsSync(filePath)) {
    if (!fs.readFileSync(filePath).equals(content)) {
      throw new Error(`immutable exception-review evidence already exists with different bytes: ${filePath}`);
    }
    return;
  }
  fs.writeFileSync(filePath, content, { flag: "wx" });
}

function writeImmutableJson(filePath, value) {
  writeImmutable(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function outputSchema(request) {
  return {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    type: "object",
    additionalProperties: false,
    required: [
      "schema", "requestId", "requestHash", "recommendation", "confidence", "rationale",
      "evidenceSignals", "proposedChecks", "mayAcceptSample", "mayResumeCandidate", "reviewedAt",
    ],
    properties: {
      schema: { type: "string", const: "arena-calibration.exception-review-result.v1" },
      requestId: { type: "string", const: request.requestId },
      requestHash: { type: "string", const: request.requestHash },
      recommendation: { type: "string", enum: RECOMMENDATIONS },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      rationale: { type: "string", minLength: 1, maxLength: 2000 },
      evidenceSignals: {
        type: "array", maxItems: 12,
        items: { type: "string", minLength: 1, maxLength: 400 },
      },
      proposedChecks: {
        type: "array", maxItems: 12,
        items: { type: "string", minLength: 1, maxLength: 400 },
      },
      mayAcceptSample: { type: "boolean", const: false },
      mayResumeCandidate: { type: "boolean", const: false },
      reviewedAt: { type: "string", minLength: 1 },
    },
  };
}

function validateResult(result, request, schema) {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  const validate = ajv.compile(schema);
  if (!validate(result)) throw new Error(`exception review result is invalid: ${ajv.errorsText(validate.errors)}`);
  assertSchemaInstance(result.schema, result, "exception review result");
  if (result.requestId !== request.requestId || result.requestHash !== request.requestHash) {
    throw new Error("exception review result changed its request binding");
  }
  return true;
}

function promptFor(request) {
  return [
    "You are an advisory reviewer for one quarantined arena-calibration shard.",
    "Use only EXCEPTION_REVIEW_REQUEST_JSON. Do not call tools, inspect files, or infer facts outside the packet.",
    "The deterministic controller has already quarantined the affected candidate and continued unrelated work.",
    "You cannot accept any sample, resume any candidate, alter a receipt, or block the campaign.",
    "Choose exactly one recommendation: confirm_quarantine, likely_legitimate_spawn, request_method_change, or abstain.",
    "likely_legitimate_spawn means the evidence resembles a legitimate derived actor, but still requires a code/method repair and a fresh rerun.",
    "Return only one JSON object matching the supplied output schema. Set mayAcceptSample and mayResumeCandidate to false.",
    `EXCEPTION_REVIEW_REQUEST_JSON\n${JSON.stringify(request)}`,
  ].join("\n");
}

function cliIdentity(executablePath) {
  return {
    executablePath,
    executableSha256: sha256File(executablePath),
    version: childProcess.execFileSync(executablePath, ["--version"], {
      encoding: "utf8", windowsHide: true, timeout: 30000,
    }).trim(),
  };
}

function usageFromEvents(events) {
  const completed = events.find(({ event }) => event.type === "turn.completed");
  const raw = completed && completed.event && completed.event.usage && typeof completed.event.usage === "object"
    ? completed.event.usage : {};
  const input = Number(raw.input_tokens || raw.inputTokens || 0);
  const output = Number(raw.output_tokens || raw.outputTokens || 0);
  return { ...raw, totalTokens: Number(raw.total_tokens || raw.totalTokens || input + output) };
}

function checkContract() {
  const hash = `sha256:${"a".repeat(64)}`;
  const request = { requestId: "review-check", requestHash: hash };
  const schema = outputSchema(request);
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  if (!ajv.validateSchema(schema)) throw new Error(ajv.errorsText());
  validateResult({
    schema: "arena-calibration.exception-review-result.v1",
    requestId: request.requestId,
    requestHash: request.requestHash,
    recommendation: "abstain",
    confidence: 0,
    rationale: "Contract fixture has no runtime evidence.",
    evidenceSignals: [],
    proposedChecks: [],
    mayAcceptSample: false,
    mayResumeCandidate: false,
    reviewedAt: "2026-08-30T00:00:00.000Z",
  }, request, schema);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    check: "exception-review-output-contract",
    modelInvocations: 1,
    autoAcceptAuthority: false,
  })}\n`);
}

async function main(argv) {
  const options = parseArgs(argv);
  if (options.help) return process.stdout.write(`${usage()}\n`);
  if (options.check) return checkContract();
  if (!options.request || !options.outputDir || !options.codexExe) {
    fail("--request, --output-dir, and --codex-exe are required");
  }
  if (!path.isAbsolute(options.codexExe) || !fs.existsSync(options.codexExe)) {
    fail("--codex-exe must be an existing absolute file");
  }
  const request = readJsonFile(options.request);
  assertSchemaInstance(request.schema, request, "exception review request");
  const expectedHash = sha256OfValue(Object.fromEntries(
    Object.entries(request).filter(([key]) => key !== "requestHash"),
  ));
  if (request.requestHash !== expectedHash) throw new Error("exception review request hash mismatch");

  fs.mkdirSync(options.outputDir, { recursive: true });
  const isolatedCwd = path.join(options.outputDir, "isolated-cwd");
  fs.mkdirSync(isolatedCwd, { recursive: true });
  const paths = {
    schema: path.join(options.outputDir, "model-output.schema.json"),
    prompt: path.join(options.outputDir, "prompt.txt"),
    stdout: path.join(options.outputDir, "model-stdout.jsonl"),
    stderr: path.join(options.outputDir, "model-stderr.txt"),
    capture: path.join(options.outputDir, "capture.json"),
    cli: path.join(options.outputDir, "cli-identity.json"),
    result: path.join(options.outputDir, "exception-review-result.json"),
    receipt: path.join(options.outputDir, "exception-review-receipt.json"),
  };
  const schema = outputSchema(request);
  const prompt = promptFor(request);
  writeImmutableJson(paths.schema, schema);
  writeImmutable(paths.prompt, prompt);
  const cli = cliIdentity(options.codexExe);
  writeImmutableJson(paths.cli, cli);
  const args = [
    "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
    "--model", options.model,
    "--config", `model_reasoning_effort=${JSON.stringify(options.reasoningEffort)}`,
    "--config", 'approval_policy="never"',
    ...(options.serviceTier === "fast"
      ? ["--config", 'service_tier="fast"', "--config", "features.fast_mode=true"] : []),
    "--sandbox", "read-only",
    "--cd", isolatedCwd,
    "--skip-git-repo-check",
    "--output-schema", paths.schema,
    "--json", "-",
  ];
  const capture = await spawnCaptured({
    command: options.codexExe,
    args,
    cwd: isolatedCwd,
    env: { ...process.env, NO_COLOR: "1" },
    stdin: prompt,
    timeoutMs: options.timeoutMs,
  });
  writeImmutable(paths.stdout, capture.stdout);
  writeImmutable(paths.stderr, capture.stderr);
  const captureSummary = {
    pid: capture.pid,
    startedAt: capture.startedAt,
    endedAt: capture.endedAt,
    durationMs: capture.durationMs,
    exitCode: capture.exitCode,
    signal: capture.signal,
    timedOut: capture.timedOut,
    overflowStream: capture.overflowStream,
    terminationReason: capture.terminationReason,
    descendantScanFailed: capture.descendantScanFailed,
    normalExitOrphanPids: capture.normalExitOrphanPids,
    survivorPids: capture.termination && capture.termination.survivorPids || [],
    stdoutSha256: sha256Buffer(Buffer.from(capture.stdout, "utf8")),
    stderrSha256: sha256Buffer(Buffer.from(capture.stderr, "utf8")),
  };
  writeImmutableJson(paths.capture, captureSummary);
  if (capture.exitCode !== 0 || capture.timedOut || capture.overflowStream) {
    throw new Error(`Codex exception review exit was not clean: exit=${capture.exitCode}, timeout=${capture.timedOut}`);
  }
  if (capture.descendantScanFailed || captureSummary.normalExitOrphanPids.length > 0
      || captureSummary.survivorPids.length > 0) {
    throw new Error("Codex exception review process-tree closure failed");
  }
  const events = parseJsonl(capture.stdout);
  const finalMessage = extractFinalAgentMessage(events);
  const result = JSON.parse(finalMessage.text);
  validateResult(result, request, schema);
  const receipt = {
    schema: "arena-calibration.exception-review-receipt.v1",
    requestId: request.requestId,
    requestHash: request.requestHash,
    resultHash: sha256OfValue(result),
    modelRequested: options.model,
    reasoningEffort: options.reasoningEffort,
    serviceTier: options.serviceTier,
    promptPolicyVersion: PROMPT_POLICY_VERSION,
    promptSha256: sha256Buffer(Buffer.from(prompt, "utf8")),
    outputSchemaSha256: sha256File(paths.schema),
    cliIdentityHash: sha256OfValue(cli),
    threadId: finalMessage.threadId || null,
    usage: usageFromEvents(events),
    capture: captureSummary,
    processTreeClosed: true,
    dispositionApplied: false,
    campaignWasBlocked: false,
    completedAt: capture.endedAt,
    receiptHash: "",
  };
  receipt.receiptHash = sha256OfValue(Object.fromEntries(
    Object.entries(receipt).filter(([key]) => key !== "receiptHash"),
  ));
  assertSchemaInstance(receipt.schema, receipt, "exception review receipt");
  writeImmutableJson(paths.result, result);
  writeImmutableJson(paths.receipt, receipt);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    requestHash: request.requestHash,
    resultHash: receipt.resultHash,
    recommendation: result.recommendation,
    dispositionApplied: false,
    campaignWasBlocked: false,
  })}\n`);
}

function failureOutputDir(argv) {
  const index = argv.indexOf("--output-dir");
  return index >= 0 && argv[index + 1] ? path.resolve(argv[index + 1]) : null;
}

if (require.main === module) {
  const argv = process.argv.slice(2);
  main(argv).catch((error) => {
    const outputDir = failureOutputDir(argv);
    if (outputDir) {
      try {
        writeImmutableJson(path.join(outputDir, "exception-review-failure.json"), {
          schema: "arena-calibration.exception-review-failure.v1",
          message: error.message,
          failedAt: new Date().toISOString(),
        });
      } catch (_writeError) { }
    }
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.isUsageError ? 2 : 1;
  });
}

module.exports = { outputSchema, parseArgs, promptFor, validateResult };
