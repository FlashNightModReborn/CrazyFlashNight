#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");
const Control = require("./control-channel");

const ROOT = path.resolve(__dirname, "..", "..", "..");
const STAGING_ROOT = path.join(ROOT, "tmp", "workbench-live-e2e", "cu-staging");
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/;

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const values = {};
  const flags = new Set();
  const valueNames = new Set(["run-dir", "request-id", "source-jpeg", "started-at",
    "input-at", "observer-id", "client-x", "client-y", "viewport-width",
    "viewport-height", "rect-left", "rect-top", "rect-width", "rect-height"]);
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--help" || token === "-h") {
      if (argv.length !== 1) usage("help must be used alone");
      return { help: true };
    }
    if (token === "--native") {
      if (flags.has(token)) usage("duplicate argument: " + token);
      flags.add(token);
      continue;
    }
    if (!token.startsWith("--") || !valueNames.has(token.slice(2))) {
      usage("unknown argument: " + token);
    }
    if (Object.prototype.hasOwnProperty.call(values, token)) {
      usage("duplicate argument: " + token);
    }
    if (!argv[index + 1] || argv[index + 1].startsWith("--")) {
      usage(token + " requires a value");
    }
    values[token] = argv[++index];
  }
  const parsed = {};
  Object.keys(values).forEach((token) => {
    parsed[token.slice(2).replace(/-([a-z])/g, (_match, letter) => letter.toUpperCase())]
      = values[token];
  });
  parsed.native = flags.has("--native");
  return parsed;
}

function finiteNumber(value, label) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) usage(label + " must be finite");
  return parsed;
}

function exactIso(value, label) {
  if (!ISO_RE.test(String(value || "")) || !Number.isFinite(Date.parse(value))
      || new Date(Date.parse(value)).toISOString() !== value) {
    usage(label + " must be an exact ISO timestamp");
  }
  return value;
}

function inside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative && !relative.startsWith(".." + path.sep) && relative !== ".."
    && !path.isAbsolute(relative);
}

function writeNewJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", mode: 0o600, flag: "wx",
  });
  return fs.readFileSync(filePath);
}

function nativeInput(request, args) {
  const inputAt = exactIso(args.inputAt, "input-at");
  const point = { x: finiteNumber(args.clientX, "client-x"),
    y: finiteNumber(args.clientY, "client-y") };
  const rect = { left: finiteNumber(args.rectLeft, "rect-left"),
    top: finiteNumber(args.rectTop, "rect-top"),
    width: finiteNumber(args.rectWidth, "rect-width"),
    height: finiteNumber(args.rectHeight, "rect-height") };
  rect.right = rect.left + rect.width;
  rect.bottom = rect.top + rect.height;
  const mirrored = { eventType: "click", isTrusted: true, selector: request.selectors[0],
    tagName: "NATIVE", visible: true, enabled: true,
    viewport: { width: finiteNumber(args.viewportWidth, "viewport-width"),
      height: finiteNumber(args.viewportHeight, "viewport-height") },
    rect, clientPoint: point, hitTargetMatches: true,
    key: null, button: 0, repeat: false };
  const event = Object.assign({ schema: Common.NATIVE_INPUT_EVENT_SCHEMA,
    runId: request.runId, requestId: request.requestId, step: request.step,
    observedAt: args.startedAt, receivedAt: inputAt }, mirrored);
  event.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(event));
  const relativePath = Control.nativeInputEventRelativePath(request.requestId);
  return { event, relativePath, mirrored, inputAt };
}

function webInput(runDir, request, args) {
  if (!/^[A-Za-z0-9._~-]{1,160}$/.test(String(args.observerId || ""))) {
    usage("observer-id is malformed");
  }
  const transcriptPath = path.join(runDir, args.observerId + "-passive-transcript.jsonl");
  const records = fs.readFileSync(transcriptPath, "utf8").split(/\r?\n/)
    .filter(Boolean).map((line) => JSON.parse(line));
  const started = Date.parse(args.startedAt);
  const event = records.slice().reverse().find((entry) => entry.kind === "dom_input"
    && entry.isTrusted === true && entry.target
    && entry.target.selector === request.selectors[0]
    && Date.parse(entry.observedAt) >= started
    && Date.parse(entry.observedAt) > Date.parse(request.issuedAt));
  if (!event) throw new Error("no matching trusted DOM input event for " + request.step);
  const inputEvidence = Control.domInputEvidence(args.observerId, event);
  Control.validateInputEvidence(inputEvidence, request);
  return { inputEvidence, inputAt: inputEvidence.observedAt };
}

function execute(args) {
  if (!args.runDir || !args.requestId || !args.sourceJpeg || !args.startedAt) {
    usage("run-dir, request-id, source-jpeg and started-at are required");
  }
  exactIso(args.startedAt, "started-at");
  const runDir = path.resolve(args.runDir);
  const channel = new Control.ControlChannel(ROOT, runDir);
  const requestFile = Evidence.readExactRegularFile(channel.requestPath(args.requestId), {
    phase: "control", maximumBytes: 2 * 1024 * 1024,
  });
  const request = Control.validateRequest(JSON.parse(requestFile.bytes.toString("utf8")));
  if (request.runId !== channel.runId || Date.now() > Date.parse(request.expiresAt)) {
    throw new Error("control request is not current for the owned run");
  }
  const sourceJpeg = path.resolve(args.sourceJpeg);
  if (!inside(STAGING_ROOT, sourceJpeg)
      || path.basename(sourceJpeg) !== request.requestId + ".jpg"
      || !fs.existsSync(sourceJpeg)) {
    usage("source-jpeg must be the exact request-owned staging artifact");
  }
  const captureRelative = "control/captures/" + request.requestId + ".png";
  const capturePath = path.join(runDir, ...captureRelative.split("/"));
  childProcess.execFileSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", path.join(__dirname, "convert-computer-use-capture.ps1"),
    "-Source", sourceJpeg, "-Destination", capturePath], {
    cwd: ROOT, encoding: "utf8", windowsHide: true, stdio: ["ignore", "pipe", "pipe"],
    timeout: 30000,
  });
  const sourceStat = fs.statSync(sourceJpeg);
  const captureFile = Evidence.readExactRegularFile(capturePath, {
    phase: "provider_capture", maximumBytes: 16 * 1024 * 1024,
  });
  const captureStat = fs.statSync(capturePath);
  const decoded = Common.decodePng(captureFile.bytes);

  let inputEvidence;
  let inputAt;
  if (args.native) {
    if (args.observerId) usage("native and observer-id are mutually exclusive");
    const native = nativeInput(request, args);
    const nativeBytes = writeNewJson(path.join(runDir, ...native.relativePath.split("/")),
      native.event);
    inputEvidence = Object.assign({ kind: "native_input",
      eventRef: { artifact: native.relativePath, sha256: Evidence.sha256Bytes(nativeBytes),
        eventSha256: native.event.eventSha256 } }, native.mirrored,
    { observedAt: native.inputAt });
    inputAt = native.inputAt;
  } else {
    if (args.inputAt || args.clientX || args.clientY || args.viewportWidth
        || args.viewportHeight || args.rectLeft || args.rectTop
        || args.rectWidth || args.rectHeight) {
      usage("native geometry is only valid with --native");
    }
    const web = webInput(runDir, request, args);
    inputEvidence = web.inputEvidence;
    inputAt = web.inputAt;
  }
  const issuedMs = Date.parse(request.issuedAt);
  const startedMs = Date.parse(args.startedAt);
  const inputMs = Date.parse(inputAt);
  const capturedMs = sourceStat.mtimeMs;
  if (!(issuedMs < startedMs && startedMs <= inputMs && inputMs < capturedMs
      && capturedMs <= captureStat.mtimeMs)) {
    throw new Error("computer-use action and capture timestamps are not strictly ordered");
  }

  const captureEvent = { schema: Common.PROVIDER_CAPTURE_EVENT_SCHEMA,
    runId: request.runId, requestId: request.requestId, step: request.step,
    transport: "codex_computer_use", issuer: "codex_computer_use",
    toolResultSource: "codex_computer_use_tool_result", providerEventId: "pending",
    requestSha256: requestFile.sha256, captureArtifact: captureRelative,
    capturedAt: new Date(capturedMs).toISOString(),
    fileModifiedAt: captureStat.mtime.toISOString(), captureBytes: captureFile.bytes.length,
    captureSha256: captureFile.sha256, captureWidth: decoded.width,
    captureHeight: decoded.height, captureSemanticContentIndependentlyVerified: false };
  captureEvent.providerEventId = Control.expectedProviderCaptureEventId(captureEvent);
  captureEvent.eventSha256 = Evidence.sha256Text(Evidence.canonicalJson(captureEvent));
  const captureEventRelative = Control.providerCaptureEventRelativePath(request.requestId);
  const captureEventBytes = writeNewJson(
    path.join(runDir, ...captureEventRelative.split("/")), captureEvent);
  const captureEventRef = { artifact: captureEventRelative,
    sha256: Evidence.sha256Bytes(captureEventBytes), eventSha256: captureEvent.eventSha256 };

  const providerCompletedMs = Math.max(Date.now() + 50, captureStat.mtimeMs + 1);
  if (providerCompletedMs >= Date.parse(request.expiresAt)) {
    throw new Error("control request expired before provider completion");
  }
  const receiptRelative = "control/provider-receipts/" + request.requestId + ".json";
  const receipt = { schema: Common.PROVIDER_RECEIPT_SCHEMA,
    runId: request.runId, requestId: request.requestId, step: request.step,
    transport: "codex_computer_use", issuer: "codex_computer_use",
    toolResultSource: "codex_computer_use_tool_result", requestSha256: requestFile.sha256,
    providerOperationId: "pending", action: request.step, result: "completed",
    startedAt: args.startedAt, inputEvidence,
    completedAt: new Date(providerCompletedMs).toISOString(),
    ownedArtifact: receiptRelative, captureEventRef };
  receipt.providerOperationId = Control.expectedProviderOperationId(receipt);
  receipt.receiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  writeNewJson(path.join(runDir, ...receiptRelative.split("/")), receipt);
  while (Date.now() <= providerCompletedMs) { /* bounded to 50 ms */ }
  const result = Control.writeAck(ROOT, runDir, request.requestId, {
    transport: "codex_computer_use", result: "completed",
    authorizationDecisionId: request.requiresCommitAuthorization
      ? request.authorizationRef.decisionId : null,
    providerReceiptArtifact: receiptRelative,
  });
  fs.unlinkSync(sourceJpeg);
  return { schema: "workbench-live-e2e.equipment.codex-control-record.v1",
    requestId: request.requestId, step: request.step, result: result.ack.result,
    completedAt: result.ack.completedAt, captureSha256: result.ack.captureSha256 };
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) {
    console.log(JSON.stringify({ status: "HELP", usage:
      "node record-codex-control.js --run-dir <owned-run> --request-id <id> --source-jpeg <owned-staging.jpg> --started-at <iso> (--observer-id <id> | --native --input-at <iso> --client-x <n> --client-y <n> --viewport-width <n> --viewport-height <n> --rect-left <n> --rect-top <n> --rect-width <n> --rect-height <n>)" }));
    return null;
  }
  const result = execute(args);
  console.log(JSON.stringify(result));
  return result;
}

module.exports = { execute, main, parseArgs };

if (require.main === module) {
  try { main(process.argv.slice(2)); }
  catch (error) {
    console.error(error.message);
    process.exit(error.isUsageError ? 2 : 1);
  }
}
