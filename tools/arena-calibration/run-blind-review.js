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

const PROMPT_POLICY_VERSION = "gate-c-blind-model-review-v1";

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const options = {
    packet: null,
    outputDir: null,
    codexExe: null,
    model: "gpt-5.6-sol",
    timeoutMs: 600000,
    serviceTier: "fast",
    reasoningEffort: "high",
    check: false,
    help: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--packet") options.packet = path.resolve(argv[++index]);
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
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 30000 || options.timeoutMs > 1800000) {
    fail("--timeout-ms must be an integer between 30000 and 1800000");
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
    "Usage: node tools/arena-calibration/run-blind-review.js --packet <json> --output-dir <dir> --codex-exe <absolute exe>",
    "  --model <id>                 Default gpt-5.6-sol",
    "  --timeout-ms <ms>            Default 600000",
    "  --service-tier fast|standard Default fast",
    "  --reasoning-effort <effort>  Default high",
    "  --check                      Compile the output contract without calling a model",
  ].join("\n");
}

function sha256Buffer(value) {
  return `sha256:${crypto.createHash("sha256").update(value).digest("hex")}`;
}

function sha256File(filePath) {
  return sha256Buffer(fs.readFileSync(filePath));
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

function outputSchema(packet) {
  return {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    type: "object",
    additionalProperties: false,
    required: [
      "schema", "packetId", "packetHash", "reviewerKind", "blinded", "ranking",
      "selectedAlias", "safetyConcerns", "usefulnessReason", "confidence",
    ],
    properties: {
      schema: { type: "string", const: "arena-calibration.blind-model-review.v1" },
      packetId: { type: "string", const: packet.packetId },
      packetHash: { type: "string", const: packet.packetHash },
      reviewerKind: { type: "string", const: "model" },
      blinded: { type: "boolean", const: true },
      ranking: {
        type: "array",
        minItems: 3,
        maxItems: 3,
        items: { type: "string", enum: ["A", "B", "C"] },
      },
      selectedAlias: { type: "string", enum: ["A", "B", "C", "insufficient_evidence"] },
      safetyConcerns: { type: "array", maxItems: 8, items: { type: "string", minLength: 1 } },
      usefulnessReason: { type: "string", minLength: 1, maxLength: 1600 },
      confidence: { type: "number", minimum: 0, maximum: 1 },
    },
  };
}

function validateReview(review, packet, schema) {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  const validate = ajv.compile(schema);
  if (!validate(review)) throw new Error(`blind model review is invalid: ${ajv.errorsText(validate.errors)}`);
  if (new Set(review.ranking).size !== 3) throw new Error("blind model ranking must contain A, B, and C exactly once");
  if (review.selectedAlias !== "insufficient_evidence" && review.ranking[0] !== review.selectedAlias) {
    throw new Error("selectedAlias must equal ranking[0] unless the result is insufficient_evidence");
  }
  if (review.packetHash !== packet.packetHash || review.packetId !== packet.packetId) {
    throw new Error("blind model review packet binding changed");
  }
  return true;
}

function promptFor(packet) {
  return [
    "You are an independent blind reviewer of three arena-calibration sampling proposals.",
    "The packet has already removed model identity, profile identity, source, prior tier, and historical conclusions.",
    "Do not call tools, inspect files, infer hidden identities, or use information outside BLIND_PACKET_JSON.",
    "Assess only safety, statistical usefulness, budget efficiency, counterexample coverage, and whether the plan advances the frozen completion criteria.",
    "Rank A, B, and C exactly once. selectedAlias must equal the first-ranked alias unless evidence is insufficient, in which case use insufficient_evidence.",
    "Return only one JSON object matching the supplied output schema. reviewerKind is model and blinded is true.",
    `BLIND_PACKET_JSON\n${JSON.stringify(packet)}`,
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

function checkContract() {
  const hash = `sha256:${"a".repeat(64)}`;
  const packet = { packetId: "blind-check", packetHash: hash };
  const schema = outputSchema(packet);
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  if (!ajv.validateSchema(schema)) throw new Error(ajv.errorsText());
  validateReview({
    schema: "arena-calibration.blind-model-review.v1",
    packetId: packet.packetId,
    packetHash: packet.packetHash,
    reviewerKind: "model",
    blinded: true,
    ranking: ["A", "B", "C"],
    selectedAlias: "A",
    safetyConcerns: [],
    usefulnessReason: "contract fixture",
    confidence: 1,
  }, packet, schema);
  process.stdout.write(`${JSON.stringify({ ok: true, check: "blind-model-review-contract", modelInvocations: 1 })}\n`);
}

function usageFromEvents(events) {
  const completed = events.find(({ event }) => event.type === "turn.completed");
  const raw = completed && completed.event && completed.event.usage && typeof completed.event.usage === "object"
    ? completed.event.usage : {};
  const input = Number(raw.input_tokens || raw.inputTokens || 0);
  const output = Number(raw.output_tokens || raw.outputTokens || 0);
  return { ...raw, totalTokens: Number(raw.total_tokens || raw.totalTokens || input + output) };
}

async function main(argv) {
  const options = parseArgs(argv);
  if (options.help) return process.stdout.write(`${usage()}\n`);
  if (options.check) return checkContract();
  if (!options.packet || !options.outputDir || !options.codexExe) {
    fail("--packet, --output-dir, and --codex-exe are required");
  }
  if (!path.isAbsolute(options.codexExe) || !fs.existsSync(options.codexExe)) {
    fail("--codex-exe must be an existing absolute file");
  }
  const packet = readJsonFile(options.packet);
  assertSchemaInstance("arena-calibration.blind-adjudication-packet.v1", packet, "blind review packet");
  const expectedPacketHash = sha256OfValue(Object.fromEntries(Object.entries(packet).filter(([key]) => key !== "packetHash")));
  if (packet.packetHash !== expectedPacketHash) throw new Error("blind packet hash mismatch");
  fs.mkdirSync(options.outputDir, { recursive: true });
  const isolatedCwd = path.join(options.outputDir, "isolated-cwd");
  fs.mkdirSync(isolatedCwd, { recursive: true });
  const paths = {
    schema: path.join(options.outputDir, "blind-model-output.schema.json"),
    prompt: path.join(options.outputDir, "prompt.txt"),
    stdout: path.join(options.outputDir, "stdout.jsonl"),
    stderr: path.join(options.outputDir, "stderr.txt"),
    capture: path.join(options.outputDir, "capture.json"),
    review: path.join(options.outputDir, "blind-model-review.json"),
    receipt: path.join(options.outputDir, "blind-model-review-receipt.json"),
  };
  const schema = outputSchema(packet);
  const prompt = promptFor(packet);
  writeImmutableJson(paths.schema, schema);
  writeImmutable(paths.prompt, prompt);
  const cli = cliIdentity(options.codexExe);
  const args = [
    "exec", "--ephemeral", "--ignore-user-config", "--ignore-rules",
    "--model", options.model,
    "--config", `model_reasoning_effort=${JSON.stringify(options.reasoningEffort)}`,
    "--config", 'approval_policy="never"',
    ...(options.serviceTier === "fast" ? ["--config", 'service_tier="fast"', "--config", "features.fast_mode=true"] : []),
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
  writeImmutableJson(paths.capture, captureSummary);
  if (capture.exitCode !== 0 || capture.timedOut || capture.overflowStream) {
    throw new Error(`Codex CLI exit was not clean: exit=${capture.exitCode}, timeout=${capture.timedOut}`);
  }
  if (capture.descendantScanFailed || capture.normalExitOrphanPids.length > 0 || capture.termination.survivorPids.length > 0) {
    throw new Error("Codex CLI process-tree closure failed");
  }
  const events = parseJsonl(capture.stdout);
  const finalMessage = extractFinalAgentMessage(events);
  const review = JSON.parse(finalMessage.text);
  validateReview(review, packet, schema);
  const receipt = {
    schema: "arena-calibration.blind-model-review-receipt.v1",
    packetId: packet.packetId,
    packetHash: packet.packetHash,
    reviewHash: sha256OfValue(review),
    reviewerKind: "model",
    modelRequested: options.model,
    reasoningEffort: options.reasoningEffort,
    serviceTier: options.serviceTier,
    promptPolicyVersion: PROMPT_POLICY_VERSION,
    promptSha256: sha256Buffer(Buffer.from(prompt, "utf8")),
    outputSchemaSha256: sha256File(paths.schema),
    cli,
    threadId: finalMessage.threadId,
    agentMessageCount: finalMessage.agentMessageCount,
    usage: usageFromEvents(events),
    capture: captureSummary,
    processTreeClosed: true,
    completedAt: capture.endedAt,
  };
  writeImmutableJson(paths.review, review);
  writeImmutableJson(paths.receipt, receipt);
  process.stdout.write(`${JSON.stringify({
    ok: true,
    packetHash: packet.packetHash,
    reviewHash: receipt.reviewHash,
    selectedAlias: review.selectedAlias,
    ranking: review.ranking,
    durationMs: capture.durationMs,
    processTreeClosed: true,
  }, null, 2)}\n`);
}

if (require.main === module) {
  main(process.argv.slice(2)).catch((error) => {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.isUsageError ? 2 : 1;
  });
}

module.exports = { outputSchema, parseArgs, promptFor, validateReview };
