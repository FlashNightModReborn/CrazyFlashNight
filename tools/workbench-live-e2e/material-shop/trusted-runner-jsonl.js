"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const path = require("path");
const { TextDecoder } = require("util");
const Evidence = require("../lib/evidence-artifact");
const { parseStrictJson } = require("../../cf7-agent/lib/strict-json");

const SLOT = "cf7_agent_a5_material_shop_run";
const CANDIDATE_ID = "a5";
const COMPLETION_PREFIX = "cf7-trusted-runner-evidence: ";
const COMPLETION_SCHEMA = "cf7.agent_runtime.trusted_unattended_completion.v1";
const DEFAULT_REQUEST_TIMEOUT_MS = 30_000;
const DEFAULT_EXIT_TIMEOUT_MS = 75_000;
const MAXIMUM_JSONL_BYTES = 8 * 1024 * 1024;
const MAXIMUM_STDERR_LINE_BYTES = 16 * 1024;
const MAXIMUM_BINARY_OBJECT_BYTES = 16_777_216;
const MAXIMUM_BINARY_READ_COUNT = 4_193_276;
// The v1 Host admits at most 120 requests in one rolling minute. Pace this
// A5-only client at 100/minute so EOF shutdown retains twenty request slots.
// Admission completes before the request timer and before any stdin write.
const MINIMUM_REQUEST_INTERVAL_MS = 600;
const SHA256_RE = /^[A-Fa-f0-9]{64}$/;
const OPAQUE_ID_RE = /^[A-Za-z0-9_-]{22,128}$/;
const EXTRA_ENV_NAMES = new Set([
  "CF7_WEBVIEW2_ARGS",
  "CF7_WEBVIEW2_DEV_MODE",
]);

class TrustedRunnerJsonlError extends Error {
  constructor(code, message, details) {
    super(message);
    this.name = "TrustedRunnerJsonlError";
    this.code = code;
    this.phase = "trusted_runner_jsonl";
    this.details = details || null;
  }
}

function fail(code, message, details) {
  throw new TrustedRunnerJsonlError(code, message, details);
}

function isPlainObject(value) {
  return Evidence.isPlainObject(value);
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function exactKeys(value, expected, code) {
  if (!isPlainObject(value)
      || Evidence.canonicalJson(Object.keys(value).sort())
        !== Evidence.canonicalJson(expected.slice().sort())) {
    fail(code, "object key set is not exact", {
      expected: expected.slice().sort(),
      actual: isPlainObject(value) ? Object.keys(value).sort() : null,
    });
  }
  return value;
}

function validBoundedString(value, maximumBytes) {
  return typeof value === "string" && value.length > 0
    && Buffer.byteLength(value, "utf8") <= maximumBytes
    && value === value.trim() && !/[\u0000-\u001f\u007f]/u.test(value);
}

function validatePreparation(preparation) {
  if (!isPlainObject(preparation)
      || typeof preparation.resourcesRoot !== "string"
      || !path.isAbsolute(preparation.resourcesRoot)) {
    fail("trusted_runner_preparation_invalid",
      "preparation must name one absolute materialized resourcesRoot");
  }
  const resourcesRoot = Evidence.assertExactDirectory(
    preparation.resourcesRoot, "trusted_runner_jsonl");
  const candidateRoot = path.join(resourcesRoot, "tmp", "runtime-candidates", "v2", CANDIDATE_ID);
  if (preparation.candidateRoot !== undefined
      && (typeof preparation.candidateRoot !== "string"
        || !path.isAbsolute(preparation.candidateRoot)
        || !samePath(preparation.candidateRoot, candidateRoot))) {
    fail("trusted_runner_candidate_root_mismatch",
      "preparation candidateRoot is not the exact A5 candidate leaf", {
        expected: candidateRoot,
        actual: preparation.candidateRoot,
      });
  }
  Evidence.assertExactDirectory(candidateRoot, "trusted_runner_jsonl");
  const entry = path.join(resourcesRoot, "tools", "cf7-agent", "unattended.js");
  const entryArtifact = Evidence.readExactRegularFile(entry, {
    phase: "trusted_runner_jsonl",
    maximumBytes: 1024 * 1024,
  });
  if (!samePath(entryArtifact.path, entry)) {
    fail("trusted_runner_entry_mismatch",
      "trusted runner entry did not resolve to the exact materialized wrapper");
  }
  if (preparation.runId !== undefined
      && (typeof preparation.runId !== "string"
        || !/^[A-Za-z0-9._~-]{1,160}$/u.test(preparation.runId))) {
    fail("trusted_runner_preparation_invalid", "preparation runId is malformed");
  }
  if (preparation.buildSha256 !== undefined
      && !SHA256_RE.test(String(preparation.buildSha256))) {
    fail("trusted_runner_preparation_invalid", "preparation buildSha256 is malformed");
  }
  return Object.freeze({ resourcesRoot, candidateRoot, entry,
    entrySha256: entryArtifact.sha256 });
}

function normalizeEnvironment(options) {
  const settings = options || {};
  if (settings.env !== undefined && settings.extraEnv !== undefined) {
    fail("trusted_runner_environment_invalid", "env and extraEnv are mutually exclusive");
  }
  let environment;
  if (settings.env !== undefined) {
    if (!isPlainObject(settings.env)) {
      fail("trusted_runner_environment_invalid", "env must be one plain object");
    }
    environment = Object.assign({}, settings.env);
  } else {
    environment = Object.assign({}, process.env);
    if (settings.extraEnv !== undefined) {
      if (!isPlainObject(settings.extraEnv)
          || Object.keys(settings.extraEnv).some((name) => !EXTRA_ENV_NAMES.has(name))) {
        fail("trusted_runner_environment_invalid",
          "extraEnv may contain only the closed WebView2 launch variables");
      }
      Object.assign(environment, settings.extraEnv);
    }
  }
  Object.keys(environment).forEach((name) => {
    const value = environment[name];
    if (!name || /[=\u0000]/u.test(name) || typeof value !== "string"
        || /\u0000/u.test(value)) {
      fail("trusted_runner_environment_invalid", "environment contains an invalid entry", {
        name,
      });
    }
  });
  return environment;
}

function strictBase64(value) {
  if (typeof value !== "string" || value.length % 4 !== 0) {
    fail("trusted_runner_content_base64_invalid", "contentBase64 is not canonical base64");
  }
  let padding = 0;
  if (value.endsWith("==")) padding = 2;
  else if (value.endsWith("=")) padding = 1;
  const contentLength = value.length - padding;
  if (padding === 1 && contentLength % 4 !== 3
      || padding === 2 && contentLength % 4 !== 2) {
    fail("trusted_runner_content_base64_invalid", "contentBase64 is not canonical base64");
  }
  for (let index = 0; index < contentLength; index += 1) {
    const code = value.charCodeAt(index);
    const base64 = code >= 0x41 && code <= 0x5a
      || code >= 0x61 && code <= 0x7a
      || code >= 0x30 && code <= 0x39
      || code === 0x2b || code === 0x2f;
    if (!base64) {
      fail("trusted_runner_content_base64_invalid", "contentBase64 is not canonical base64");
    }
  }
  for (let index = contentLength; index < value.length; index += 1) {
    if (value.charCodeAt(index) !== 0x3d) {
      fail("trusted_runner_content_base64_invalid", "contentBase64 is not canonical base64");
    }
  }
  const bytes = Buffer.from(value, "base64");
  if (bytes.toString("base64") !== value) {
    fail("trusted_runner_content_base64_invalid", "contentBase64 did not round-trip canonically");
  }
  return bytes;
}

function expectedIdentity(preparation) {
  const nested = isPlainObject(preparation.candidateIdentity)
    ? preparation.candidateIdentity : null;
  const direct = {};
  ["runtimeMode", "processPath", "coreSha256", "buildIdentity", "payloadClosure"]
    .forEach((name) => {
      if (preparation[name] !== undefined) direct[name] = preparation[name];
      else if (nested && nested[name] !== undefined) direct[name] = nested[name];
    });
  return direct;
}

function validateTerminalReceipt(receipt) {
  const keys = ["actionId", "auditSequence", "terminal", "outcome",
    "evidenceKind", "reasonCode", "reconcileKind", "retryable", "actualTargetId",
    "focusVerified", "beforeObservationId", "leaseState"];
  if (isPlainObject(receipt) && Object.hasOwn(receipt, "afterObservationId")) {
    keys.push("afterObservationId");
  }
  exactKeys(receipt, keys, "trusted_runner_completion_receipt_invalid");
  if (!OPAQUE_ID_RE.test(String(receipt.actionId || ""))
      || !Number.isSafeInteger(receipt.auditSequence) || receipt.auditSequence < 1
      || receipt.terminal !== true || receipt.outcome !== "input_dispatched"
      || receipt.evidenceKind !== "broker_dispatch"
      || receipt.reasonCode !== "shutdown_requested"
      || receipt.reconcileKind !== "none" || receipt.retryable !== false
      || !OPAQUE_ID_RE.test(String(receipt.actualTargetId || ""))
      || receipt.focusVerified !== false
      || !OPAQUE_ID_RE.test(String(receipt.beforeObservationId || ""))
      || (Object.hasOwn(receipt, "afterObservationId")
        && !OPAQUE_ID_RE.test(String(receipt.afterObservationId || "")))
      || receipt.leaseState !== "consumed") {
    fail("trusted_runner_completion_receipt_invalid",
      "completion terminalReceipt is not the strict supported-shutdown receipt");
  }
  return receipt;
}

function validateCompletion(value, preparation, paths) {
  exactKeys(value, ["schema", "runtimeMode", "processPath", "coreSha256",
    "buildIdentity", "payloadClosure", "guardianProcessId", "terminalReceipt"],
  "trusted_runner_completion_invalid");
  const expectedProcess = path.join(paths.candidateRoot, "runtime",
    "CRAZYFLASHER7MercenaryEmpire.Core.exe");
  if (value.schema !== COMPLETION_SCHEMA || value.runtimeMode !== "isolated_candidate"
      || typeof value.processPath !== "string" || !path.isAbsolute(value.processPath)
      || !samePath(value.processPath, expectedProcess)
      || !SHA256_RE.test(String(value.coreSha256 || ""))
      || !SHA256_RE.test(String(value.buildIdentity || ""))
      || !SHA256_RE.test(String(value.payloadClosure || ""))
      || !Number.isSafeInteger(value.guardianProcessId) || value.guardianProcessId < 1) {
    fail("trusted_runner_completion_invalid",
      "completion identity is malformed or outside the exact A5 candidate", {
        expectedProcess,
      });
  }
  const core = Evidence.readExactRegularFile(expectedProcess, {
    phase: "trusted_runner_jsonl",
    maximumBytes: 512 * 1024 * 1024,
  });
  if (core.sha256 !== String(value.coreSha256).toLowerCase()) {
    fail("trusted_runner_completion_core_mismatch",
      "completion coreSha256 differs from the exact candidate process bytes");
  }
  const expected = expectedIdentity(preparation);
  ["runtimeMode", "processPath"].forEach((name) => {
    if (expected[name] !== undefined
        && (name === "processPath"
          ? !samePath(value[name], expected[name])
          : value[name] !== expected[name])) {
      fail("trusted_runner_completion_identity_mismatch",
        "completion identity differs from preparation", { field: name });
    }
  });
  ["buildIdentity", "payloadClosure"].forEach((name) => {
    if (expected[name] !== undefined
        && String(value[name]).toLowerCase() !== String(expected[name]).toLowerCase()) {
      fail("trusted_runner_completion_identity_mismatch",
        "completion identity differs from preparation", { field: name });
    }
  });
  validateTerminalReceipt(value.terminalReceipt);
  return value;
}

class TrustedRunnerJsonl {
  constructor(preparation, options) {
    this.preparation = preparation;
    this.paths = validatePreparation(preparation);
    this.options = options || {};
    if (!isPlainObject(this.options)
        || Object.keys(this.options).some((key) => ![
          "spawnImpl", "requestTimeoutMs", "exitTimeoutMs", "env", "extraEnv",
          "monotonicNowImpl", "delayImpl",
        ].includes(key))) {
      fail("trusted_runner_options_invalid", "trusted runner options are not closed");
    }
    const hasTimingOverride = this.options.monotonicNowImpl !== undefined
      || this.options.delayImpl !== undefined;
    if (hasTimingOverride
        && (typeof this.options.spawnImpl !== "function"
          || typeof this.options.monotonicNowImpl !== "function"
          || typeof this.options.delayImpl !== "function")) {
      fail("trusted_runner_options_invalid",
        "timing overrides are paired test seams and require an injected spawnImpl");
    }
    this.requestTimeoutMs = this._positiveTimeout(
      this.options.requestTimeoutMs, DEFAULT_REQUEST_TIMEOUT_MS,
      "trusted_runner_request_timeout_invalid");
    this.exitTimeoutMs = this._positiveTimeout(
      this.options.exitTimeoutMs, DEFAULT_EXIT_TIMEOUT_MS,
      "trusted_runner_exit_timeout_invalid");
    this.environment = normalizeEnvironment(this.options);
    this.monotonicNow = this.options.monotonicNowImpl
      || (() => Number(process.hrtime.bigint() / 1_000_000n));
    this.delay = this.options.delayImpl
      || ((milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds)));
    this.nextRequestAdmissionMonotonic = null;
    this.admissionTail = Promise.resolve();
    this.pending = new Map();
    this.responseIds = new Set();
    this.transcript = [];
    this.sequence = 0;
    this.nextRequest = 0;
    this.requestPrefix = "a5jsonl_" + crypto.randomBytes(16).toString("base64url");
    this.stdoutText = "";
    this.stderrText = "";
    this.stdoutDecoder = new TextDecoder("utf-8", { fatal: true });
    this.stderrDecoder = new TextDecoder("utf-8", { fatal: true });
    this.stderrLines = [];
    this.completion = null;
    this.fatal = null;
    this.writeAuthorityIssued = false;
    this._uncertainWrite = false;
    this.closingMode = null;
    this.exitObserved = false;
    this.closeObserved = false;
    this.exitCode = null;
    this.exitSignal = null;
    this.finishPromise = null;
    this.writeChain = Promise.resolve();
    this.closePromise = new Promise((resolve) => { this.resolveClose = resolve; });

    const spawnImpl = this.options.spawnImpl || childProcess.spawn;
    if (typeof spawnImpl !== "function") {
      fail("trusted_runner_spawn_invalid", "spawnImpl must be a function");
    }
    const args = [this.paths.entry, "--adapter", "jsonl", "--slot", SLOT,
      "--candidate-id", CANDIDATE_ID];
    try {
      this.child = spawnImpl(process.execPath, args, {
        cwd: this.paths.resourcesRoot,
        stdio: ["pipe", "pipe", "pipe"],
        shell: false,
        windowsHide: true,
        env: this.environment,
      });
    } catch (error) {
      fail("trusted_runner_spawn_failed", error && error.message || "spawn failed");
    }
    this._validateChild();
    this._record("spawn", { executable: process.execPath, args,
      cwd: this.paths.resourcesRoot, entrySha256: this.paths.entrySha256 });
    this.child.stdout.on("data", (chunk) => this._onStdout(chunk));
    this.child.stderr.on("data", (chunk) => this._onStderr(chunk));
    this.child.once("error", (error) => this._fail(new TrustedRunnerJsonlError(
      "trusted_runner_spawn_failed", error && error.message || "child process error")));
    this.child.once("exit", (code, signal) => this._onExit(code, signal));
    this.child.once("close", (code, signal) => this._onClose(code, signal));
  }

  get uncertainWrite() {
    return this._uncertainWrite;
  }

  _positiveTimeout(value, fallback, code) {
    const actual = value === undefined ? fallback : value;
    if (!Number.isSafeInteger(actual) || actual < 1 || actual > 300_000) {
      fail(code, "timeout must be a bounded positive integer");
    }
    return actual;
  }

  _validateChild() {
    const child = this.child;
    if (!child || !child.stdin || !child.stdout || !child.stderr
        || typeof child.once !== "function" || typeof child.stdin.write !== "function"
        || typeof child.stdin.end !== "function" || typeof child.stdout.on !== "function"
        || typeof child.stderr.on !== "function") {
      fail("trusted_runner_spawn_invalid", "spawn did not return a piped child process");
    }
  }

  _record(kind, fields) {
    this.transcript.push(Object.assign({ sequence: ++this.sequence, kind }, fields || {}));
  }

  getTranscript() {
    return JSON.parse(JSON.stringify(this.transcript));
  }

  canonicalTranscriptSha256() {
    return Evidence.sha256Text(Evidence.canonicalJson(this.transcript));
  }

  _newId() {
    this.nextRequest += 1;
    return this.requestPrefix + "_" + this.nextRequest;
  }

  _admitRequest() {
    const predecessor = this.admissionTail;
    let release;
    this.admissionTail = new Promise((resolve) => { release = resolve; });
    return predecessor.then(async () => {
      try {
        for (;;) {
          const now = this.monotonicNow();
          if (!Number.isSafeInteger(now) || now < 0) {
            fail("trusted_runner_clock_invalid",
              "request admission requires a non-negative monotonic millisecond clock");
          }
          if (this.nextRequestAdmissionMonotonic === null
              || now >= this.nextRequestAdmissionMonotonic) {
            this.nextRequestAdmissionMonotonic = now + MINIMUM_REQUEST_INTERVAL_MS;
            return;
          }
          await this.delay(this.nextRequestAdmissionMonotonic - now);
        }
      } finally {
        release();
      }
    });
  }

  async call(method, params, callOptions) {
    const settings = callOptions || {};
    try {
      if (this.fatal) throw this.fatal;
      if (this.closingMode || this.closeObserved) {
        fail("trusted_runner_closed", "trusted runner stdin is already closing or closed");
      }
      if (!validBoundedString(method, 160) || !isPlainObject(params)
          || !isPlainObject(settings)
          || Object.keys(settings).some((key) => !["writeAuthority", "timeoutMs"].includes(key))
          || settings.writeAuthority !== undefined && typeof settings.writeAuthority !== "boolean") {
        fail("trusted_runner_call_invalid", "call requires one bounded method and plain params");
      }
      const timeoutMs = this._positiveTimeout(settings.timeoutMs,
        this.requestTimeoutMs, "trusted_runner_request_timeout_invalid");
      await this._admitRequest();
      if (this.fatal) throw this.fatal;
      if (this.closingMode || this.closeObserved) {
        fail("trusted_runner_closed", "trusted runner stdin is already closing or closed");
      }
      const id = this._newId();
      const request = { jsonrpc: "2.0", id, method, params };
      const line = JSON.stringify(request) + "\n";
      if (Buffer.byteLength(line, "utf8") > MAXIMUM_JSONL_BYTES) {
        fail("trusted_runner_request_oversize", "request exceeds the bounded JSONL line size");
      }
      if (settings.writeAuthority === true) this.writeAuthorityIssued = true;
      this._record("request", { request, writeAuthority: settings.writeAuthority === true });
      const response = new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          const pending = this.pending.get(id);
          if (!pending) return;
          const error = new TrustedRunnerJsonlError("trusted_runner_request_timeout",
            "trusted runner request timed out", { id, method });
          this._fail(error);
        }, timeoutMs);
        this.pending.set(id, { id, method, params, writeAuthority: settings.writeAuthority === true,
          resolve, reject, timer });
      });
      this.writeChain = this.writeChain.then(() => new Promise((resolve, reject) => {
        if (this.fatal) { reject(this.fatal); return; }
        try {
          this.child.stdin.write(line, "utf8", (error) => {
            if (error) reject(error); else resolve();
          });
        } catch (error) { reject(error); }
      }));
      this.writeChain.catch((error) => this._fail(new TrustedRunnerJsonlError(
        "trusted_runner_stdin_write_failed", error && error.message || "stdin write failed")));
      return await response;
    } catch (error) {
      throw error;
    }
  }

  _onStdout(chunk) {
    if (this.fatal) return;
    try {
      this.stdoutText += this.stdoutDecoder.decode(Buffer.from(chunk), { stream: true });
      this._drainLines("stdout");
    } catch (error) {
      this._fail(error instanceof TrustedRunnerJsonlError ? error
        : new TrustedRunnerJsonlError("trusted_runner_stdout_invalid",
          error && error.message || "stdout is not strict UTF-8 JSONL"));
    }
  }

  _onStderr(chunk) {
    if (this.fatal) return;
    try {
      this.stderrText += this.stderrDecoder.decode(Buffer.from(chunk), { stream: true });
      this._drainLines("stderr");
    } catch (error) {
      this._fail(error instanceof TrustedRunnerJsonlError ? error
        : new TrustedRunnerJsonlError("trusted_runner_stderr_invalid",
          error && error.message || "stderr is not strict UTF-8"));
    }
  }

  _drainLines(stream) {
    const property = stream + "Text";
    let text = this[property];
    while (true) {
      const newline = text.indexOf("\n");
      if (newline < 0) break;
      let line = text.slice(0, newline);
      text = text.slice(newline + 1);
      if (line.endsWith("\r")) line = line.slice(0, -1);
      const maximum = stream === "stdout" ? MAXIMUM_JSONL_BYTES : MAXIMUM_STDERR_LINE_BYTES;
      if (!line || Buffer.byteLength(line, "utf8") > maximum) {
        fail("trusted_runner_" + stream + "_invalid",
          stream + " contains an empty or oversized line");
      }
      if (stream === "stdout") this._handleResponseLine(line);
      else this._handleStderrLine(line);
    }
    if (Buffer.byteLength(text, "utf8")
        > (stream === "stdout" ? MAXIMUM_JSONL_BYTES : MAXIMUM_STDERR_LINE_BYTES)) {
      fail("trusted_runner_" + stream + "_invalid", stream + " partial line is oversized");
    }
    this[property] = text;
  }

  _handleResponseLine(line) {
    let response;
    try { response = parseStrictJson(line, { maximumDepth: 64 }); }
    catch (error) {
      fail("trusted_runner_response_json_invalid", "stdout line is not strict JSON", {
        cause: error && error.message,
      });
    }
    if (!isPlainObject(response) || response.jsonrpc !== "2.0"
        || typeof response.id !== "string"
        || (Object.hasOwn(response, "result") === Object.hasOwn(response, "error"))) {
      fail("trusted_runner_response_invalid", "stdout response envelope is malformed");
    }
    const keys = Object.hasOwn(response, "result")
      ? ["jsonrpc", "id", "result"] : ["jsonrpc", "id", "error"];
    exactKeys(response, keys, "trusted_runner_response_invalid");
    if (this.responseIds.has(response.id)) {
      fail("trusted_runner_response_duplicate", "response id was emitted more than once", {
        id: response.id,
      });
    }
    const pending = this.pending.get(response.id);
    if (!pending) {
      fail("trusted_runner_response_unknown", "response id has no pending request", {
        id: response.id,
      });
    }
    if (Object.hasOwn(response, "error")) {
      if (!isPlainObject(response.error) || !Number.isInteger(response.error.code)
          || !validBoundedString(response.error.message, 4096)) {
        fail("trusted_runner_response_invalid", "RPC error response is malformed");
      }
    } else if (pending.method === "content.read") {
      this._validateContentEnvelope(response.result, pending.params);
    }
    this.responseIds.add(response.id);
    clearTimeout(pending.timer);
    this.pending.delete(response.id);
    this._record("response", { response });
    if (Object.hasOwn(response, "error")) {
      const error = new TrustedRunnerJsonlError("trusted_runner_rpc_error",
        response.error.message, { id: response.id, method: pending.method,
          rpcError: response.error });
      pending.reject(error);
      return;
    }
    pending.resolve(response.result);
  }

  _validateContentEnvelope(envelope, request) {
    exactKeys(envelope, ["result", "metadata", "contentBase64"],
      "trusted_runner_content_envelope_invalid");
    const result = exactKeys(envelope.result, ["handle", "offset", "totalLength",
      "returnedBytes", "final", "contentHash"], "trusted_runner_content_result_invalid");
    const metadata = exactKeys(envelope.metadata, ["handle", "offset", "totalLength",
      "final", "contentHash"], "trusted_runner_content_metadata_invalid");
    const bytes = strictBase64(envelope.contentBase64);
    if (!OPAQUE_ID_RE.test(String(request.handle || ""))
        || !Number.isSafeInteger(request.offset) || request.offset < 0
        || !Number.isSafeInteger(request.count) || request.count < 1
        || request.count > MAXIMUM_BINARY_READ_COUNT
        || result.handle !== request.handle || metadata.handle !== request.handle
        || result.offset !== request.offset || metadata.offset !== request.offset
        || result.totalLength !== metadata.totalLength
        || result.returnedBytes !== bytes.length || bytes.length > request.count
        || result.final !== metadata.final || result.contentHash !== metadata.contentHash
        || !Number.isSafeInteger(result.totalLength) || result.totalLength < 0
        || result.totalLength > MAXIMUM_BINARY_OBJECT_BYTES
        || !SHA256_RE.test(String(result.contentHash || ""))
        || request.offset + bytes.length > result.totalLength
        || result.final !== (request.offset + bytes.length === result.totalLength)
        || result.final !== true && bytes.length === 0) {
      fail("trusted_runner_content_binding_invalid",
        "content.read base64, result, metadata, and requested range are not exact-bound");
    }
    return bytes;
  }

  async readContent(handle, options) {
    const settings = options || {};
    try {
      if (!OPAQUE_ID_RE.test(String(handle || "")) || !isPlainObject(settings)
          || Object.keys(settings).some((key) => !["totalLength", "contentHash", "count",
            "timeoutMs"].includes(key))) {
        fail("trusted_runner_content_request_invalid", "readContent arguments are malformed");
      }
      const count = settings.count === undefined ? MAXIMUM_BINARY_READ_COUNT : settings.count;
      if (!Number.isSafeInteger(count) || count < 1 || count > MAXIMUM_BINARY_READ_COUNT
          || settings.totalLength !== undefined
            && (!Number.isSafeInteger(settings.totalLength) || settings.totalLength < 0
              || settings.totalLength > MAXIMUM_BINARY_OBJECT_BYTES)
          || settings.contentHash !== undefined
            && !SHA256_RE.test(String(settings.contentHash))) {
        fail("trusted_runner_content_request_invalid", "readContent bounds are invalid");
      }
      const chunks = [];
      let offset = 0;
      let totalLength = null;
      let contentHash = null;
      while (true) {
        const envelope = await this.call("content.read", { handle, offset, count }, {
          timeoutMs: settings.timeoutMs,
        });
        const bytes = this._validateContentEnvelope(envelope, { handle, offset, count });
        const result = envelope.result;
        if (totalLength === null) {
          totalLength = result.totalLength;
          contentHash = result.contentHash;
          if (settings.totalLength !== undefined && totalLength !== settings.totalLength
              || settings.contentHash !== undefined && contentHash !== settings.contentHash) {
            fail("trusted_runner_content_expected_mismatch",
              "content.read metadata differs from the caller-bound object identity");
          }
        } else if (totalLength !== result.totalLength || contentHash !== result.contentHash) {
          fail("trusted_runner_content_changed",
            "content.read object identity changed between chunks");
        }
        chunks.push(bytes);
        offset += bytes.length;
        if (result.final) break;
      }
      const complete = Buffer.concat(chunks, offset);
      const actualHash = crypto.createHash("sha256").update(complete).digest("hex");
      if (complete.length !== totalLength
          || actualHash !== String(contentHash).toLowerCase()) {
        fail("trusted_runner_content_hash_mismatch",
          "assembled content failed totalLength/contentHash validation");
      }
      return complete;
    } catch (error) {
      this._fail(error);
      throw this.fatal;
    }
  }

  _handleStderrLine(line) {
    if (line.startsWith(COMPLETION_PREFIX)) {
      if (this.completion !== null) {
        fail("trusted_runner_completion_duplicate", "completion evidence appeared more than once");
      }
      let completion;
      try {
        completion = parseStrictJson(line.slice(COMPLETION_PREFIX.length), { maximumDepth: 64 });
      } catch (error) {
        fail("trusted_runner_completion_json_invalid", "completion evidence is not strict JSON", {
          cause: error && error.message,
        });
      }
      this.completion = completion;
      this.stderrLines.push({ kind: "completion", line });
      this._record("completion", { completion });
      return;
    }
    if (!(line.startsWith("cf7-trusted-runner: ")
        || line.startsWith("cf7-agent-unattended: "))
        || !validBoundedString(line, 1024)) {
      fail("trusted_runner_stderr_pollution", "stderr contains a non-runner diagnostic line");
    }
    this.stderrLines.push({ kind: "diagnostic", line });
    this._record("diagnostic", { line });
  }

  _onExit(code, signal) {
    if (this.exitObserved) return;
    this.exitObserved = true;
    this.exitCode = Number.isInteger(code) ? code : null;
    this.exitSignal = signal == null ? null : String(signal);
    this._record("exit", { code: this.exitCode, signal: this.exitSignal });
    if (!this.closingMode || this.pending.size !== 0) {
      this._fail(new TrustedRunnerJsonlError("trusted_runner_early_exit",
        "trusted runner exited before an requested supported shutdown completed", {
          code: this.exitCode, signal: this.exitSignal,
        }));
    }
  }

  _onClose(code, signal) {
    if (this.closeObserved) return;
    this.closeObserved = true;
    if (!this.exitObserved) this._onExit(code, signal);
    try {
      this.stdoutText += this.stdoutDecoder.decode();
      this.stderrText += this.stderrDecoder.decode();
      this._drainLines("stdout");
      this._drainLines("stderr");
      if (this.stdoutText.length !== 0 || this.stderrText.length !== 0) {
        fail("trusted_runner_truncated_line", "process closed with a partial protocol line");
      }
    } catch (error) {
      this._fail(error instanceof TrustedRunnerJsonlError ? error
        : new TrustedRunnerJsonlError("trusted_runner_stream_invalid", error.message));
    }
    this.resolveClose({ code: this.exitCode, signal: this.exitSignal });
  }

  _fail(error) {
    if (this.fatal) return;
    this.fatal = error instanceof TrustedRunnerJsonlError ? error
      : new TrustedRunnerJsonlError("trusted_runner_failed",
        error && error.message || String(error));
    if (this.writeAuthorityIssued) this._uncertainWrite = true;
    this._record("failure", { code: this.fatal.code, message: this.fatal.message,
      uncertainWrite: this._uncertainWrite });
    for (const pending of this.pending.values()) {
      clearTimeout(pending.timer);
      pending.reject(this.fatal);
    }
    this.pending.clear();
    if (!this.closingMode) this.closingMode = "failure";
    try { this.child && this.child.stdin && this.child.stdin.end(); } catch (_error) {}
  }

  finish() {
    if (!this.finishPromise) this.finishPromise = this._gracefulClose("finish");
    return this.finishPromise;
  }

  abortBeforeAuthority() {
    if (this.writeAuthorityIssued) {
      this._uncertainWrite = true;
      return Promise.reject(new TrustedRunnerJsonlError(
        "trusted_runner_abort_after_authority_forbidden",
        "abortBeforeAuthority is forbidden after a write-authority request was issued"));
    }
    if (!this.finishPromise) this.finishPromise = this._gracefulClose("abort_before_authority");
    return this.finishPromise;
  }

  async _gracefulClose(mode) {
    if (this.fatal) throw this.fatal;
    if (this.pending.size !== 0) {
      fail("trusted_runner_requests_pending", "cannot close with pending JSONL requests");
    }
    this.closingMode = mode;
    this._record("stdin_end", { mode });
    try { this.child.stdin.end(); }
    catch (error) {
      this._fail(new TrustedRunnerJsonlError("trusted_runner_stdin_close_failed", error.message));
      throw this.fatal;
    }
    let timer;
    try {
      await Promise.race([
        this.closePromise,
        new Promise((_, reject) => {
          timer = setTimeout(() => reject(new TrustedRunnerJsonlError(
            "trusted_runner_exit_timeout", "trusted runner did not complete supported shutdown")),
          this.exitTimeoutMs);
        }),
      ]);
    } catch (error) {
      this._fail(error);
      throw this.fatal;
    } finally {
      if (timer) clearTimeout(timer);
    }
    if (this.fatal) throw this.fatal;
    if (this.exitCode !== 0 || this.exitSignal !== null) {
      this._fail(new TrustedRunnerJsonlError("trusted_runner_exit_invalid",
        "trusted runner did not exit cleanly", { code: this.exitCode, signal: this.exitSignal }));
      throw this.fatal;
    }
    if (this.completion === null
        || this.stderrLines.filter((entry) => entry.kind === "completion").length !== 1) {
      this._fail(new TrustedRunnerJsonlError("trusted_runner_completion_missing",
        "clean exit requires exactly one trusted-runner completion line"));
      throw this.fatal;
    }
    let completion;
    try { completion = validateCompletion(this.completion, this.preparation, this.paths); }
    catch (error) {
      this._fail(error);
      throw this.fatal;
    }
    this._record("complete", { mode, exitCode: 0 });
    return {
      completion: JSON.parse(JSON.stringify(completion)),
      transcript: this.getTranscript(),
      transcriptSha256: this.canonicalTranscriptSha256(),
      exitCode: 0,
      abortedBeforeAuthority: mode === "abort_before_authority",
    };
  }
}

function createTrustedRunner(preparation, options) {
  return new TrustedRunnerJsonl(preparation, options);
}

module.exports = {
  CANDIDATE_ID,
  COMPLETION_PREFIX,
  COMPLETION_SCHEMA,
  MAXIMUM_BINARY_READ_COUNT,
  MINIMUM_REQUEST_INTERVAL_MS,
  SLOT,
  TrustedRunnerJsonlError,
  createTrustedRunner,
  strictBase64,
  validateCompletion,
  validatePreparation,
};
