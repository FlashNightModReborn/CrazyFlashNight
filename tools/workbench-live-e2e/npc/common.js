"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

const BUNDLE_SCHEMA = "workbench-live-e2e.npc.bundle.v5";
const RECEIPT_SCHEMA = "workbench-live-e2e.npc.receipt.v5";
const TRANSCRIPT_SCHEMA = "workbench-live-e2e.npc.transcript.v1";
const EVENT_SCHEMA = "workbench-live-e2e.npc.passive-event.v1";
const CONTROL_REQUEST_SCHEMA = "workbench-live-e2e.npc.control-request.v1";
const CONTROL_ACK_SCHEMA = "workbench-live-e2e.npc.control-ack.v2";
const PROVIDER_RECEIPT_SCHEMA = "workbench-live-e2e.npc.provider-receipt.v4";
const PRICING_CONSTRAINT_SCHEMA = "workbench-live-e2e.npc.pricing-constraint.v1";
const ARTIFACT_MANIFEST_SCHEMA = "workbench-live-e2e.npc.artifact-manifest.v2";
const EVIDENCE_ORIGIN_SCHEMA = "workbench-live-e2e.npc.evidence-origin.v1";
const TRUSTED_TIMELINE_SCHEMA = "workbench-live-e2e.npc.trusted-timeline.v3";
const CANONICAL_TIMELINE_ORDER = Object.freeze([
  "first_runtime_started", "first_cdp_bound", "first_observer_ready",
  "final_authority_response", "first_close_control_request", "first_close_operation",
  "first_close_input", "first_close_request", "first_host_close_receipt",
  "first_close_capture", "first_close_provider", "first_close_ack", "first_close_settled",
  "first_observer_detached", "first_loaded_production", "safe_exit_issued",
  "safe_exit_operation", "safe_exit_input", "safe_exit_capture", "safe_exit_provider",
  "safe_exit_ack", "safe_exit_host_boundary", "sv1", "sv2", "archive_host_receipt",
  "archive_capture", "first_host_terminal", "exit_confirm_issued", "exit_confirm_operation",
  "exit_confirm_input", "exit_confirm_capture", "exit_confirm_provider", "exit_confirm_ack",
  "first_residue", "restart_runtime_started", "restart_cdp_bound", "restart_observer_ready",
  "restart_open_control_request", "restart_open_operation", "restart_open_input", "restart_open",
  "restart_open_capture", "restart_open_provider", "restart_open_ack",
  "restart_close_control_request", "restart_close_operation", "restart_close_input",
  "restart_close_request", "restart_host_close_receipt", "restart_close_capture",
  "restart_close_provider", "restart_close_ack", "restart_close_settled",
  "restart_observer_detached", "restart_loaded_production", "restart_host_terminal",
  "shutdown_requested", "shutdown_completed", "restart_residue", "restart_disk_capture",
  "post_restart_production_capture", "clone_lock_release",
]);

const SHA256_RE = /^[a-f0-9]{64}$/;
const TOKEN_REF_RE = /^sha256:[a-f0-9]{64}$/;
const OPAQUE_ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const SAFE_SLOT_RE = /^cf7_agent_[A-Za-z0-9_-]+$/;
const LIVE_SLOT_RE = /^crazyflasher7_saves\d*$/;
const TRADE_TOKEN_KEYS = new Set(["tradeToken", "expectedTradeToken", "batchToken", "expectedBatchToken"]);

class NpcJourneyError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "NpcJourneyError";
    this.code = String(code || "npc_journey_failed");
    this.phase = String(phase || "unknown");
    this.details = details || null;
  }
}

function fail(code, phase, message, details) {
  throw new NpcJourneyError(code, phase, message, details);
}

function isPlainObject(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function requireObject(value, code, phase, message) {
  if (!isPlainObject(value)) fail(code, phase, message);
  return value;
}

function requireArray(value, code, phase, message) {
  if (!Array.isArray(value)) fail(code, phase, message);
  return value;
}

function requireOne(values, code, phase, message, details) {
  if (!Array.isArray(values) || values.length !== 1) {
    fail(code, phase, message, Object.assign({ count: Array.isArray(values) ? values.length : -1 }, details || {}));
  }
  return values[0];
}

function deepClone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function stableValue(value) {
  if (Array.isArray(value)) return value.map(stableValue);
  if (!isPlainObject(value)) return value;
  const output = {};
  Object.keys(value).sort().forEach((key) => { output[key] = stableValue(value[key]); });
  return output;
}

function canonicalJson(value) {
  return JSON.stringify(stableValue(value));
}

function deepEqual(left, right) {
  return canonicalJson(left) === canonicalJson(right);
}

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256Text(value) {
  return sha256Bytes(Buffer.from(String(value), "utf8"));
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

let crcTable = null;
function pngCrc32(bytes) {
  if (!crcTable) {
    crcTable = Array.from({ length: 256 }, (_unused, index) => {
      let value = index;
      for (let bit = 0; bit < 8; bit += 1) {
        value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
      }
      return value >>> 0;
    });
  }
  let crc = 0xffffffff;
  for (const byte of bytes) crc = crcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** Strictly parses and inflates a bounded, non-interlaced PNG screenshot. */
function decodePng(bytesInput) {
  const bytes = Buffer.isBuffer(bytesInput) ? bytesInput : Buffer.from(bytesInput || []);
  const signature = Buffer.from("89504e470d0a1a0a", "hex");
  if (bytes.length < 45 || bytes.length > 16 * 1024 * 1024
      || !bytes.subarray(0, 8).equals(signature)) {
    fail("control_capture_media_invalid", "control_capture", "capture is not a bounded PNG file");
  }
  let offset = 8;
  let ihdr = null;
  let plte = null;
  let iend = false;
  let idatClosed = false;
  const idat = [];
  while (offset < bytes.length) {
    if (offset + 12 > bytes.length) {
      fail("control_capture_media_invalid", "control_capture", "PNG chunk header is truncated");
    }
    const length = bytes.readUInt32BE(offset);
    const end = offset + 12 + length;
    if (length > 16 * 1024 * 1024 || end > bytes.length) {
      fail("control_capture_media_invalid", "control_capture", "PNG chunk length is invalid");
    }
    const typeBytes = bytes.subarray(offset + 4, offset + 8);
    const type = typeBytes.toString("ascii");
    const data = bytes.subarray(offset + 8, offset + 8 + length);
    if (!/^[A-Za-z]{4}$/.test(type) || type[2] !== type[2].toUpperCase()
        || type[0] === type[0].toUpperCase()
          && !["IHDR", "PLTE", "IDAT", "IEND"].includes(type)) {
      fail("control_capture_media_invalid", "control_capture",
        "PNG chunk type is malformed or unsupported", { type });
    }
    const expectedCrc = bytes.readUInt32BE(offset + 8 + length);
    const actualCrc = pngCrc32(Buffer.concat([typeBytes, data]));
    if (expectedCrc !== actualCrc) {
      fail("control_capture_media_invalid", "control_capture", "PNG chunk CRC is invalid", { type });
    }
    if (!ihdr && type !== "IHDR") {
      fail("control_capture_media_invalid", "control_capture", "PNG IHDR is not the first chunk");
    }
    if (type === "IHDR") {
      if (ihdr || length !== 13) {
        fail("control_capture_media_invalid", "control_capture", "PNG IHDR is duplicated or malformed");
      }
      ihdr = Buffer.from(data);
    } else if (type === "PLTE") {
      if (plte || idat.length || iend || length < 3 || length > 768 || length % 3 !== 0) {
        fail("control_capture_media_invalid", "control_capture", "PNG PLTE is malformed or misplaced");
      }
      plte = Buffer.from(data);
    } else if (type === "IDAT") {
      if (!ihdr || iend || idatClosed) fail("control_capture_media_invalid", "control_capture", "PNG IDAT order is invalid");
      idat.push(Buffer.from(data));
    } else if (type === "IEND") {
      if (length !== 0 || iend || end !== bytes.length) {
        fail("control_capture_media_invalid", "control_capture", "PNG IEND or trailing bytes are invalid");
      }
      iend = true;
    } else if (idat.length) {
      idatClosed = true;
    }
    offset = end;
  }
  if (!ihdr || !iend || !idat.length) {
    fail("control_capture_media_invalid", "control_capture", "PNG lacks IHDR, IDAT, or IEND");
  }
  const width = ihdr.readUInt32BE(0);
  const height = ihdr.readUInt32BE(4);
  const bitDepth = ihdr[8];
  const colorType = ihdr[9];
  const channels = { 0: 1, 2: 3, 3: 1, 4: 2, 6: 4 }[colorType];
  const validDepth = ({ 0: [1, 2, 4, 8, 16], 2: [8, 16], 3: [1, 2, 4, 8],
    4: [8, 16], 6: [8, 16] }[colorType] || []).includes(bitDepth);
  if (width < 320 || height < 180 || width > 16384 || height > 16384
      || width * height > 64 * 1024 * 1024 || !channels || !validDepth
      || colorType === 3 && (!plte || plte.length / 3 > 2 ** bitDepth)
      || [0, 4].includes(colorType) && plte
      || ihdr[10] !== 0 || ihdr[11] !== 0 || ihdr[12] !== 0) {
    fail("control_capture_media_invalid", "control_capture",
      "PNG IHDR is unsupported, below 320x180, or unsafe");
  }
  const rowBytes = Math.ceil(width * channels * bitDepth / 8);
  const expectedInflated = height * (rowBytes + 1);
  if (!Number.isSafeInteger(expectedInflated) || expectedInflated > 64 * 1024 * 1024) {
    fail("control_capture_media_invalid", "control_capture",
      "PNG decoded byte size exceeds the bounded capture contract");
  }
  const compressed = Buffer.concat(idat);
  let inflated;
  let compressedBytesConsumed = null;
  try {
    const decoded = zlib.inflateSync(compressed, {
      maxOutputLength: expectedInflated,
      info: true,
    });
    inflated = decoded.buffer;
    compressedBytesConsumed = decoded.engine && decoded.engine.bytesWritten;
  }
  catch (error) {
    fail("control_capture_media_invalid", "control_capture", "PNG IDAT cannot be decoded", {
      message: error.message,
    });
  }
  if (inflated.length !== expectedInflated
      || compressedBytesConsumed !== compressed.length) {
    fail("control_capture_media_invalid", "control_capture",
      "PNG decoded size or compressed-stream consumption is inconsistent", {
        expectedInflated, actualInflated: inflated.length,
        compressedBytes: compressed.length, compressedBytesConsumed,
      });
  }
  const bytesPerPixel = Math.max(1, Math.ceil(channels * bitDepth / 8));
  const pixels = Buffer.allocUnsafe(rowBytes * height);
  function paeth(left, up, upperLeft) {
    const prediction = left + up - upperLeft;
    const leftDistance = Math.abs(prediction - left);
    const upDistance = Math.abs(prediction - up);
    const upperLeftDistance = Math.abs(prediction - upperLeft);
    return leftDistance <= upDistance && leftDistance <= upperLeftDistance
      ? left : upDistance <= upperLeftDistance ? up : upperLeft;
  }
  for (let row = 0; row < height; row += 1) {
    const inputOffset = row * (rowBytes + 1);
    const outputOffset = row * rowBytes;
    const filter = inflated[inputOffset];
    if (filter > 4) {
      fail("control_capture_media_invalid", "control_capture", "PNG row filter is invalid");
    }
    for (let column = 0; column < rowBytes; column += 1) {
      const encoded = inflated[inputOffset + 1 + column];
      const left = column >= bytesPerPixel ? pixels[outputOffset + column - bytesPerPixel] : 0;
      const up = row > 0 ? pixels[outputOffset - rowBytes + column] : 0;
      const upperLeft = row > 0 && column >= bytesPerPixel
        ? pixels[outputOffset - rowBytes + column - bytesPerPixel] : 0;
      let predictor = 0;
      if (filter === 1) predictor = left;
      else if (filter === 2) predictor = up;
      else if (filter === 3) predictor = Math.floor((left + up) / 2);
      else if (filter === 4) predictor = paeth(left, up, upperLeft);
      pixels[outputOffset + column] = (encoded + predictor) & 0xff;
    }
  }
  if (pixels.length !== rowBytes * height) {
    fail("control_capture_media_invalid", "control_capture",
      "PNG reconstructed pixel byte length is inconsistent");
  }
  if (colorType === 3) {
    const paletteEntries = plte.length / 3;
    const mask = (1 << bitDepth) - 1;
    for (let row = 0; row < height; row += 1) {
      const rowOffset = row * rowBytes;
      for (let column = 0; column < width; column += 1) {
        const bitOffset = column * bitDepth;
        const packed = pixels[rowOffset + (bitOffset >> 3)];
        const shift = 8 - bitDepth - (bitOffset & 7);
        const paletteIndex = (packed >> shift) & mask;
        if (paletteIndex >= paletteEntries) {
          fail("control_capture_media_invalid", "control_capture",
            "PNG indexed pixel references an absent palette entry", {
              row, column, paletteIndex, paletteEntries,
            });
        }
      }
    }
  }
  return { mediaType: "image/png", width, height, bytes: bytes.length,
    pixelBytes: pixels.length, pixelSha256: sha256Bytes(pixels) };
}

function tokenRef(value) {
  return "sha256:" + sha256Text(String(value == null ? "" : value));
}

function redactAuthorityTokens(value, keyHint) {
  if (Array.isArray(value)) return value.map((entry) => redactAuthorityTokens(entry, keyHint));
  if (!isPlainObject(value)) {
    if (TRADE_TOKEN_KEYS.has(String(keyHint || "")) && typeof value === "string") return tokenRef(value);
    return value;
  }
  const output = {};
  Object.keys(value).forEach((key) => {
    const child = value[key];
    output[key] = TRADE_TOKEN_KEYS.has(key) && typeof child === "string"
      ? (TOKEN_REF_RE.test(child) ? child : tokenRef(child))
      : redactAuthorityTokens(child, key);
  });
  return output;
}

function assertNoRawAuthorityTokens(value, label) {
  const rootLabel = label || "$";
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoRawAuthorityTokens(entry, rootLabel + "[" + index + "]"));
    return;
  }
  if (!isPlainObject(value)) return;
  Object.keys(value).forEach((key) => {
    const child = value[key];
    const childLabel = rootLabel + "." + key;
    if (TRADE_TOKEN_KEYS.has(key) && typeof child === "string" && !TOKEN_REF_RE.test(child)) {
      fail("raw_authority_token_present", "redaction", "authority token was not reduced to a digest reference", {
        path: childLabel,
      });
    }
    assertNoRawAuthorityTokens(child, childLabel);
  });
}

function nextEvent(previousHash, sequence, rawEvent) {
  const base = redactAuthorityTokens(deepClone(rawEvent));
  delete base.schema;
  delete base.sequence;
  delete base.previousHash;
  delete base.eventHash;
  const event = Object.assign({}, base, {
    schema: EVENT_SCHEMA,
    sequence,
    previousHash,
  });
  event.eventHash = sha256Text(previousHash + "\n" + canonicalJson(event));
  return event;
}

function sealEvents(rawEvents, observerId) {
  let previousHash = "0".repeat(64);
  const events = (rawEvents || []).map((rawEvent, index) => {
    const event = nextEvent(previousHash, index + 1, rawEvent);
    previousHash = event.eventHash;
    return event;
  });
  return {
    schema: TRANSCRIPT_SCHEMA,
    observerId: String(observerId || "npc.fixture.observer"),
    pageUrl: "https://overlay.local/overlay.html",
    eventCount: events.length,
    chainHead: previousHash,
    events,
  };
}

function verifyEventChain(transcript) {
  requireObject(transcript, "transcript_missing", "transcript", "passive transcript is missing");
  if (transcript.schema !== TRANSCRIPT_SCHEMA
      || !OPAQUE_ID_RE.test(String(transcript.observerId || ""))
      || transcript.pageUrl !== "https://overlay.local/overlay.html") {
    fail("transcript_contract_invalid", "transcript", "transcript schema or production URL is invalid");
  }
  const events = requireArray(transcript.events, "transcript_events_missing", "transcript", "transcript events are missing");
  if (Number(transcript.eventCount) !== events.length) {
    fail("transcript_count_mismatch", "transcript", "transcript event count does not match its event array");
  }
  let previousHash = "0".repeat(64);
  let previousObservedAt = null;
  events.forEach((event, index) => {
    requireObject(event, "transcript_event_invalid", "transcript", "transcript event is not an object");
    if (event.schema !== EVENT_SCHEMA || event.sequence !== index + 1 || event.previousHash !== previousHash) {
      fail("transcript_chain_invalid", "transcript", "transcript event ordering or previous hash is invalid", {
        sequence: index + 1,
      });
    }
    const copy = deepClone(event);
    delete copy.eventHash;
    const expected = sha256Text(previousHash + "\n" + canonicalJson(copy));
    if (event.eventHash !== expected) {
      fail("transcript_chain_invalid", "transcript", "transcript event hash is invalid", { sequence: index + 1 });
    }
    const observedAt = Date.parse(event.observedAt);
    if (!Number.isFinite(observedAt) || new Date(observedAt).toISOString() !== event.observedAt
        || (previousObservedAt !== null && observedAt < previousObservedAt)) {
      fail("transcript_timeline_invalid", "transcript",
        "transcript observedAt timestamps are missing, malformed, or non-monotonic", {
          sequence: index + 1,
        });
    }
    previousObservedAt = observedAt;
    previousHash = event.eventHash;
  });
  if (transcript.chainHead !== previousHash) {
    fail("transcript_head_mismatch", "transcript", "transcript chain head is invalid");
  }
  assertNoRawAuthorityTokens(transcript, "transcript");
  return events;
}

function pathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative !== "" && !relative.startsWith(".." + path.sep) && relative !== ".." && !path.isAbsolute(relative);
}

function assertPlainFileInside(runDir, relativePath, phase) {
  if (typeof relativePath !== "string" || relativePath.length < 1 || relativePath.length > 300
      || relativePath.includes("\0") || path.isAbsolute(relativePath)) {
    fail("artifact_path_invalid", phase, "artifact path is not a bounded relative path", { relativePath });
  }
  const resolvedRun = path.resolve(runDir);
  const filePath = path.resolve(resolvedRun, relativePath);
  if (!pathInside(resolvedRun, filePath)) {
    fail("artifact_path_escape", phase, "artifact escaped the run directory", { relativePath });
  }
  let stat;
  try { stat = fs.lstatSync(filePath); }
  catch (error) { fail("artifact_missing", phase, "artifact is missing", { relativePath, message: error.message }); }
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("artifact_not_plain_file", phase, "artifact must be a plain non-link file", { relativePath });
  }
  const realRun = fs.realpathSync.native(resolvedRun);
  const realFile = fs.realpathSync.native(filePath);
  if (!pathInside(realRun, realFile)) {
    fail("artifact_realpath_escape", phase, "artifact real path escaped the run directory", { relativePath });
  }
  return { filePath, stat };
}

function relativeArtifactPath(runDir, filePath) {
  const relative = path.relative(path.resolve(runDir), path.resolve(filePath)).replace(/\\/g, "/");
  if (!relative || relative.startsWith("../") || path.isAbsolute(relative)
      || relative.split("/").some((part) => !part || part === "." || part === "..")) {
    fail("artifact_path_invalid", "artifacts", "artifact path is not canonical", { filePath });
  }
  return relative;
}

function walkArtifactFiles(runDir) {
  const root = path.resolve(runDir);
  const output = [];
  function visit(current) {
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) {
      fail("artifact_missing", "artifacts", "artifact tree cannot be read", {
        current, message: error.message,
      });
    }
    if (stat.isSymbolicLink()) {
      fail("artifact_reparse_forbidden", "artifacts",
        "artifact tree contains a symbolic link", { current });
    }
    if (stat.isDirectory()) {
      fs.readdirSync(current).forEach((name) => visit(path.join(current, name)));
      return;
    }
    if (!stat.isFile()) {
      fail("artifact_not_plain_file", "artifacts", "artifact tree contains a non-file", { current });
    }
    output.push(current);
  }
  visit(root);
  return output.sort((left, right) => {
    const a = relativeArtifactPath(root, left);
    const b = relativeArtifactPath(root, right);
    return a < b ? -1 : a > b ? 1 : 0;
  });
}

function buildArtifactManifest(runDir, runId, roleByPath, excludedPaths) {
  const excluded = new Set(excludedPaths || ["artifact-manifest.json", "receipt.json", "status.json"]);
  const roles = roleByPath || {};
  const artifacts = walkArtifactFiles(runDir).map((filePath) => {
    const relativePath = relativeArtifactPath(runDir, filePath);
    if (excluded.has(relativePath)) return null;
    const bytes = fs.readFileSync(filePath);
    const role = String(roles[relativePath] || "raw_evidence");
    if (!/^[A-Za-z0-9._~-]{1,80}$/.test(role)) {
      fail("artifact_role_invalid", "artifacts", "artifact role is malformed", {
        path: relativePath, role,
      });
    }
    return { path: relativePath, role, bytes: bytes.length, sha256: sha256Bytes(bytes) };
  }).filter(Boolean);
  const manifest = {
    schema: ARTIFACT_MANIFEST_SCHEMA,
    runId: String(runId || ""),
    createdAt: new Date().toISOString(),
    artifacts,
  };
  manifest.manifestSha256 = sha256Text(canonicalJson(manifest));
  return manifest;
}

function readJson(filePath, label) {
  let data;
  try { data = JSON.parse(fs.readFileSync(filePath, "utf8")); }
  catch (error) { fail("json_invalid", label || "json", "JSON artifact is invalid", { filePath, message: error.message }); }
  return data;
}

function atomicWriteJson(filePath, value) {
  const parent = path.dirname(filePath);
  fs.mkdirSync(parent, { recursive: true });
  const temporary = filePath + ".tmp-" + process.pid + "-" + crypto.randomBytes(6).toString("hex");
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2) + "\n", { encoding: "utf8", mode: 0o600, flag: "wx" });
  fs.renameSync(temporary, filePath);
}

function verifyArtifactManifest(runDir, manifest, options) {
  const settings = options || {};
  requireObject(manifest, "artifact_manifest_missing", "artifacts", "artifact manifest is missing");
  if (manifest.schema !== ARTIFACT_MANIFEST_SCHEMA || !Array.isArray(manifest.artifacts)
      || !OPAQUE_ID_RE.test(String(manifest.runId || ""))
      || !Number.isFinite(Date.parse(manifest.createdAt))
      || !SHA256_RE.test(String(manifest.manifestSha256 || ""))) {
    fail("artifact_manifest_invalid", "artifacts", "artifact manifest contract is invalid");
  }
  const unsigned = deepClone(manifest);
  delete unsigned.manifestSha256;
  if (manifest.manifestSha256 !== sha256Text(canonicalJson(unsigned))) {
    fail("artifact_manifest_digest_invalid", "artifacts", "artifact manifest digest is invalid");
  }
  if (settings.runId && manifest.runId !== settings.runId) {
    fail("artifact_manifest_run_mismatch", "artifacts", "artifact manifest runId drifted");
  }
  const byPath = new Map();
  const seenPaths = new Set();
  let previousPath = "";
  manifest.artifacts.forEach((entry) => {
    requireObject(entry, "artifact_entry_invalid", "artifacts", "artifact manifest entry is invalid");
    const foldedPath = String(entry.path || "").toLowerCase();
    if (typeof entry.path !== "string" || seenPaths.has(foldedPath) || entry.path <= previousPath
        || !SHA256_RE.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 0
        || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(entry.role || ""))) {
      fail("artifact_entry_invalid", "artifacts", "artifact manifest entry fields are invalid", { entry });
    }
    const canonicalPath = relativeArtifactPath(runDir,
      path.resolve(runDir, entry.path.replace(/\//g, path.sep)));
    if (canonicalPath !== entry.path) {
      fail("artifact_path_invalid", "artifacts", "artifact path is not canonical", { entry });
    }
    const resolved = assertPlainFileInside(runDir, entry.path, "artifacts");
    const bytes = fs.readFileSync(resolved.filePath);
    const digest = sha256Bytes(bytes);
    if (bytes.length !== entry.bytes || digest !== entry.sha256) {
      fail("artifact_hash_mismatch", "artifacts", "artifact bytes do not match the sealed manifest", {
        path: entry.path,
        expectedSha256: entry.sha256,
        actualSha256: digest,
      });
    }
    if (settings.roleByPath && settings.roleByPath[entry.path] !== entry.role) {
      fail("artifact_role_set_invalid", "artifacts", "artifact role drifted", {
        path: entry.path, expectedRole: settings.roleByPath[entry.path], actualRole: entry.role,
      });
    }
    byPath.set(entry.path, Object.assign({ absolutePath: resolved.filePath }, entry));
    seenPaths.add(foldedPath);
    previousPath = entry.path;
  });
  const excluded = new Set(settings.excludedPaths
    || ["artifact-manifest.json", "receipt.json", "status.json"]);
  const actual = walkArtifactFiles(runDir).map((filePath) => relativeArtifactPath(runDir, filePath))
    .filter((relativePath) => excluded.has(relativePath) === false);
  const expected = manifest.artifacts.map((entry) => entry.path);
  if (canonicalJson(actual) !== canonicalJson(expected)) {
    fail("artifact_set_mismatch", "artifacts",
      "owned artifact set contains an extra, omission, duplicate, or reorder", { actual, expected });
  }
  if (settings.roleByPath) {
    const expectedPaths = Object.keys(settings.roleByPath).sort();
    if (canonicalJson(expected) !== canonicalJson(expectedPaths)) {
      fail("artifact_role_set_invalid", "artifacts",
        "artifact role inventory contains an extra, omission, or reorder", { expectedPaths, actual: expected });
    }
  }
  return byPath;
}

function readManifestJson(byPath, relativePath, expectedRole, phase) {
  const entry = byPath.get(relativePath);
  if (!entry || (expectedRole && entry.role !== expectedRole)) {
    fail("artifact_reference_invalid", phase, "artifact reference is absent or has the wrong role", {
      path: relativePath,
      expectedRole,
    });
  }
  return readJson(entry.absolutePath, phase);
}

function assertOpaqueId(value, code, phase, label) {
  if (typeof value !== "string" || !OPAQUE_ID_RE.test(value)) {
    fail(code, phase, label + " is not a valid opaque identity", { value });
  }
  return value;
}

function assertSafeSlot(value, label) {
  if (typeof value !== "string" || !SAFE_SLOT_RE.test(value)) {
    fail("unsafe_slot", "slot", (label || "target slot") + " must use the cf7_agent_* namespace", { value });
  }
  return value;
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function timestampId() {
  return new Date().toISOString().replace(/[-:.TZ]/g, "").slice(0, 17)
    + "-" + crypto.randomBytes(5).toString("hex");
}

function sealEvidenceOrigin(fields) {
  const required = ["origin", "profile", "evidenceMode", "runId", "root", "journeyMode",
    "fullScopeEligible", "requiredPhases", "sourceGenerator", "moduleManifestSha256",
    "moduleJournalSha256"];
  if (!isPlainObject(fields)
      || canonicalJson(Object.keys(fields).sort()) !== canonicalJson(required.slice().sort())) {
    fail("evidence_origin_input_invalid", "evidence_origin",
      "evidence origin requires one exact closed input set");
  }
  const value = Object.assign({ schema: EVIDENCE_ORIGIN_SCHEMA }, deepClone(fields));
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function sealTrustedTimeline(fields) {
  const required = ["runId", "transcriptSha256", "hostLogSha256", "safeExitRequestId",
    "safeExitProviderOperationId", "exitConfirmRequestId", "exitConfirmProviderOperationId",
    "safeExitProviderBoundarySha256", "archiveHostLine", "shutdownSha256", "residueSha256",
    "inventoryEvents"];
  if (!isPlainObject(fields)
      || canonicalJson(Object.keys(fields).sort()) !== canonicalJson(required.slice().sort())) {
    fail("trusted_timeline_input_invalid", "trusted_timeline",
      "trusted timeline requires one exact source binding set");
  }
  if (!Array.isArray(fields.inventoryEvents) || fields.inventoryEvents.length < 3
      || fields.inventoryEvents.some((entry) => !isPlainObject(entry)
        || canonicalJson(Object.keys(entry).sort())
          !== canonicalJson(["phase", "pairOrdinal", "callId", "requestAt", "responseAt"].sort())
        || !Number.isInteger(entry.pairOrdinal) || entry.pairOrdinal < 0
        || !OPAQUE_ID_RE.test(String(entry.callId || ""))
        || !Number.isFinite(Date.parse(entry.requestAt)) || !Number.isFinite(Date.parse(entry.responseAt))
        || Date.parse(entry.requestAt) >= Date.parse(entry.responseAt))
      || new Set(fields.inventoryEvents.map((entry) => entry.callId)).size
        !== fields.inventoryEvents.length) {
    fail("trusted_inventory_timeline_invalid", "trusted_timeline",
      "trusted timeline requires every Inventory probe/supplement request and response exactly once");
  }
  const value = Object.assign({ schema: TRUSTED_TIMELINE_SCHEMA,
    orderedEvents: CANONICAL_TIMELINE_ORDER.slice() }, deepClone(fields));
  value.evidenceSha256 = sha256Text(canonicalJson(value));
  return value;
}

function canonicalTimelineEntries(timestampByEvent, inventoryEvents, lifecycleOrderErrorCode) {
  if (!isPlainObject(timestampByEvent)
      || canonicalJson(Object.keys(timestampByEvent).sort())
        !== canonicalJson(CANONICAL_TIMELINE_ORDER.slice().sort())) {
    fail("canonical_timeline_input_invalid", "timeline",
      "canonical lifecycle timeline requires one exact timestamp for every ordered event");
  }
  const lifecycle = CANONICAL_TIMELINE_ORDER.map((label) => [label, timestampByEvent[label]]);
  const parsedLifecycle = lifecycle.map((entry) => Date.parse(entry[1]));
  if (parsedLifecycle.some((value, index) => !Number.isFinite(value)
      || index > 0 && value <= parsedLifecycle[index - 1])) {
    fail(lifecycleOrderErrorCode || "canonical_timeline_order_invalid", "timeline",
      "canonical lifecycle spine is missing, duplicated, or reordered");
  }
  if (!Array.isArray(inventoryEvents)) {
    fail("canonical_inventory_timeline_missing", "timeline",
      "global timeline is missing its Inventory probe/supplement events");
  }
  const dynamic = [];
  inventoryEvents.forEach((entry) => {
    dynamic.push(["inventory." + entry.phase + "." + entry.pairOrdinal + ".request."
      + entry.callId, entry.requestAt]);
    dynamic.push(["inventory." + entry.phase + "." + entry.pairOrdinal + ".response."
      + entry.callId, entry.responseAt]);
  });
  const merged = lifecycle.concat(dynamic).sort((left, right) => {
    const delta = Date.parse(left[1]) - Date.parse(right[1]);
    return delta || (left[0] < right[0] ? -1 : 1);
  });
  if (merged.some((entry, index) => !Number.isFinite(Date.parse(entry[1]))
      || index > 0 && Date.parse(entry[1]) <= Date.parse(merged[index - 1][1]))) {
    fail("canonical_global_timeline_collision", "timeline",
      "lifecycle and Inventory evidence require one collision-free global order");
  }
  return merged;
}

module.exports = {
  ARTIFACT_MANIFEST_SCHEMA,
  BUNDLE_SCHEMA,
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  EVENT_SCHEMA,
  EVIDENCE_ORIGIN_SCHEMA,
  CANONICAL_TIMELINE_ORDER,
  TRUSTED_TIMELINE_SCHEMA,
  LIVE_SLOT_RE,
  NpcJourneyError,
  OPAQUE_ID_RE,
  PRICING_CONSTRAINT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  RECEIPT_SCHEMA,
  SAFE_SLOT_RE,
  SHA256_RE,
  TOKEN_REF_RE,
  TRANSCRIPT_SCHEMA,
  assertNoRawAuthorityTokens,
  assertOpaqueId,
  assertPlainFileInside,
  assertSafeSlot,
  atomicWriteJson,
  buildArtifactManifest,
  canonicalJson,
  canonicalTimelineEntries,
  deepClone,
  deepEqual,
  decodePng,
  fail,
  isPlainObject,
  nextEvent,
  pathInside,
  readJson,
  readManifestJson,
  redactAuthorityTokens,
  requireArray,
  requireObject,
  requireOne,
  sealEvents,
  sealEvidenceOrigin,
  sealTrustedTimeline,
  sha256Bytes,
  sha256File,
  sha256Text,
  sleep,
  stableValue,
  timestampId,
  tokenRef,
  verifyArtifactManifest,
  verifyEventChain,
  walkArtifactFiles,
};
