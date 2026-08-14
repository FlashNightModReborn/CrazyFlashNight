"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const API_VERSION = "FROZEN-v1";

class LiveE2EContractError extends Error {
  constructor(code, phase, message, details) {
    super(message);
    this.name = "LiveE2EContractError";
    this.code = code;
    this.phase = phase;
    this.details = details || null;
  }
}

function contractFail(code, phase, message, details) {
  throw new LiveE2EContractError(code, phase, message, details);
}

function isPlainObject(value) {
  if (value === null || typeof value !== "object" || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
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

function sha256Bytes(value) {
  return crypto.createHash("sha256").update(value).digest("hex");
}

function sha256Text(value) {
  return sha256Bytes(Buffer.from(String(value), "utf8"));
}

function sha256File(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function samePath(left, right) {
  return path.resolve(left).toLowerCase() === path.resolve(right).toLowerCase();
}

function pathInside(parent, candidate) {
  const relative = path.relative(path.resolve(parent), path.resolve(candidate));
  return relative !== "" && !relative.startsWith(".." + path.sep) && relative !== ".."
    && !path.isAbsolute(relative);
}

function assertExactDirectory(directory, phase) {
  const resolved = path.resolve(directory);
  let stat;
  let real;
  try {
    stat = fs.lstatSync(resolved);
    real = fs.realpathSync.native(resolved);
  } catch (error) {
    contractFail("exact_directory_unavailable", phase || "filesystem", error.message, { directory: resolved });
  }
  if (!stat.isDirectory() || stat.isSymbolicLink() || !samePath(real, resolved)) {
    contractFail("exact_directory_invalid", phase || "filesystem",
      "directory must be a non-reparse exact path", { directory: resolved, real });
  }
  return resolved;
}

function assertOwnedRunDirectory(root, runDir, ownedBaseRelative, phase) {
  const exactRoot = assertExactDirectory(path.resolve(root), phase || "filesystem");
  const relative = String(ownedBaseRelative || "");
  const segments = relative.split(/[\\/]/);
  if (!relative || path.isAbsolute(relative) || path.win32.isAbsolute(relative)
      || path.posix.isAbsolute(relative) || path.win32.parse(relative).root
      || path.posix.parse(relative).root || segments.some((entry) => !entry || entry === "." || entry === "..")) {
    contractFail("owned_base_relative_invalid", phase || "filesystem",
      "owned base must be one closed non-empty relative path", { ownedBaseRelative: relative });
  }
  const base = path.resolve(exactRoot, relative);
  const resolved = path.resolve(runDir);
  if (!pathInside(exactRoot, base) || !pathInside(base, resolved)) {
    contractFail("owned_run_directory_invalid", phase || "filesystem",
      "run directory is outside its owned base", { base, runDir: resolved });
  }
  assertExactDirectory(base, phase || "filesystem");
  return assertExactDirectory(resolved, phase || "filesystem");
}

function ensureExactChildDirectory(parent, name, phase) {
  const exactParent = assertExactDirectory(parent, phase || "filesystem");
  if (!/^[A-Za-z0-9._-]{1,80}$/.test(String(name || ""))) {
    contractFail("child_directory_name_invalid", phase || "filesystem", "child name is not closed");
  }
  const child = path.join(exactParent, name);
  if (!pathInside(exactParent, child)) {
    contractFail("child_directory_escape", phase || "filesystem", "child path escaped parent");
  }
  try { fs.mkdirSync(child); } catch (error) {
    if (!error || error.code !== "EEXIST") throw error;
  }
  return assertExactDirectory(child, phase || "filesystem");
}

function detectRasterMediaType(buffer) {
  if (!Buffer.isBuffer(buffer)) return null;
  if (buffer.length >= 8 && buffer.subarray(0, 8).equals(
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "image/png";
  if (buffer.length >= 3 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
    return "image/jpeg";
  }
  if (buffer.length >= 12 && buffer.toString("ascii", 0, 4) === "RIFF"
      && buffer.toString("ascii", 8, 12) === "WEBP") return "image/webp";
  if (buffer.length >= 2 && buffer.toString("ascii", 0, 2) === "BM") return "image/bmp";
  return null;
}

function readExactRegularFile(filePath, options) {
  const settings = options || {};
  const phase = settings.phase || "artifact";
  const maximumBytes = Number(settings.maximumBytes || 64 * 1024 * 1024);
  const minimumBytes = settings.allowEmpty === true ? 0 : 1;
  if (!Number.isSafeInteger(maximumBytes) || maximumBytes < 1) {
    contractFail("exact_file_limit_invalid", phase, "artifact byte limit is invalid");
  }
  const resolved = path.resolve(filePath);
  let initialPathStat;
  let initialReal;
  try {
    initialPathStat = fs.lstatSync(resolved);
    initialReal = fs.realpathSync.native(resolved);
  } catch (error) {
    contractFail("exact_file_unavailable", phase, error.message, { filePath: resolved });
  }
  if (!initialPathStat.isFile() || initialPathStat.isSymbolicLink()
      || !samePath(initialReal, resolved)
      || initialPathStat.size < minimumBytes || initialPathStat.size > maximumBytes) {
    contractFail("exact_file_invalid", phase, "artifact must be an exact bounded regular file", {
      filePath: resolved,
      bytes: initialPathStat && initialPathStat.size,
    });
  }
  let descriptor = null;
  let before;
  let after;
  let bytes;
  let finalPathStat;
  let finalReal;
  try {
    descriptor = fs.openSync(resolved, "r");
    before = fs.fstatSync(descriptor);
    bytes = fs.readFileSync(descriptor);
    after = fs.fstatSync(descriptor);
    finalPathStat = fs.lstatSync(resolved);
    finalReal = fs.realpathSync.native(resolved);
  } catch (error) {
    contractFail("exact_file_read_failed", phase, error.message, { filePath: resolved });
  } finally {
    if (descriptor !== null) {
      try { fs.closeSync(descriptor); } catch (_error) {}
    }
  }
  const sameIdentity = String(before.dev) === String(after.dev)
    && String(before.ino) === String(after.ino)
    && String(after.dev) === String(finalPathStat.dev)
    && String(after.ino) === String(finalPathStat.ino);
  if (!before.isFile() || !after.isFile() || !finalPathStat.isFile()
      || finalPathStat.isSymbolicLink() || !samePath(finalReal, resolved)
      || !sameIdentity || before.size !== after.size || after.size !== finalPathStat.size
      || bytes.length !== after.size || before.mtimeMs !== after.mtimeMs
      || before.ctimeMs !== after.ctimeMs || bytes.length < minimumBytes
      || bytes.length > maximumBytes) {
    contractFail("exact_file_changed_during_read", phase,
      "artifact identity or bytes changed while it was being captured", { filePath: resolved });
  }
  return { path: resolved, bytes, length: bytes.length, sha256: sha256Bytes(bytes) };
}

function verifyOwnedCapture(options) {
  const root = path.resolve(options.root);
  const runDir = assertOwnedRunDirectory(root, options.runDir, options.ownedBaseRelative,
    options.phase || "capture");
  const capture = options.capture;
  if (!isPlainObject(capture) || typeof capture.relativePath !== "string"
      || !/^[A-Fa-f0-9]{64}$/.test(String(capture.sha256 || ""))
      || !Number.isInteger(capture.bytes) || capture.bytes < 1) {
    contractFail("capture_envelope_invalid", options.phase || "capture", "capture envelope is malformed");
  }
  const capturePath = path.resolve(runDir, capture.relativePath.replace(/\//g, path.sep));
  if (!pathInside(runDir, capturePath)) {
    contractFail("capture_path_escape", options.phase || "capture", "capture escaped the owned run directory");
  }
  const file = readExactRegularFile(capturePath, {
    phase: options.phase || "capture",
    maximumBytes: options.maximumBytes || 64 * 1024 * 1024,
  });
  const mediaType = detectRasterMediaType(file.bytes);
  if (!mediaType || file.length !== capture.bytes || file.sha256 !== capture.sha256
      || (capture.mediaType && capture.mediaType !== mediaType)) {
    contractFail("capture_digest_mismatch", options.phase || "capture",
      "capture bytes/media do not match the envelope");
  }
  return { path: file.path, relativePath: capture.relativePath, sha256: file.sha256,
    bytes: file.length, mediaType };
}

function stageOwnedCapture(options) {
  const root = path.resolve(options.root);
  const runDir = assertOwnedRunDirectory(root, options.runDir, options.ownedBaseRelative,
    options.phase || "capture");
  const capturesDir = assertExactDirectory(options.capturesDir, options.phase || "capture");
  if (!pathInside(runDir, capturesDir)) {
    contractFail("capture_directory_invalid", options.phase || "capture",
      "capture directory is outside the owned run directory");
  }
  if (!/^[A-Za-z0-9._~-]{1,160}$/.test(String(options.artifactId || ""))) {
    contractFail("capture_id_invalid", options.phase || "capture", "capture artifact id is malformed");
  }
  const source = readExactRegularFile(options.sourcePath, {
    phase: options.phase || "capture",
    maximumBytes: options.maximumBytes || 64 * 1024 * 1024,
  });
  const mediaType = detectRasterMediaType(source.bytes);
  if (!mediaType) {
    contractFail("capture_media_invalid", options.phase || "capture",
      "capture must be PNG, JPEG, WebP, or BMP");
  }
  if (options.expectedSha256
      && String(options.expectedSha256).toLowerCase() !== source.sha256) {
    contractFail("capture_digest_mismatch", options.phase || "capture",
      "capture does not match the caller-provided digest");
  }
  const extension = { "image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp",
    "image/bmp": ".bmp" }[mediaType];
  const destination = path.join(capturesDir, options.artifactId + extension);
  fs.copyFileSync(source.path, destination, fs.constants.COPYFILE_EXCL);
  const capture = {
    relativePath: path.relative(runDir, destination).replace(/\\/g, "/"),
    sha256: source.sha256,
    bytes: source.length,
    mediaType,
  };
  verifyOwnedCapture({ root, runDir, ownedBaseRelative: options.ownedBaseRelative,
    capture, phase: options.phase || "capture", maximumBytes: options.maximumBytes });
  return capture;
}

function canonicalRecordsDigest(records) {
  return sha256Text(canonicalJson(records));
}

function verifyCanonicalRecords(options) {
  const records = options.records;
  if (!Array.isArray(records) || !/^[A-Fa-f0-9]{64}$/.test(String(options.digest || ""))
      || canonicalRecordsDigest(records) !== String(options.digest).toLowerCase()) {
    contractFail("records_digest_mismatch", options.phase || "records",
      "record slice does not match its canonical digest");
  }
  let previous = Number(options.watermarkTotal || 0);
  records.forEach((record) => {
    if (!isPlainObject(record) || !Number.isInteger(record.lineNumber)
        || record.lineNumber <= previous || typeof record.body !== "string") {
      contractFail("records_order_invalid", options.phase || "records",
        "record slice is not strictly ordered");
    }
    previous = record.lineNumber;
  });
  if (records.length < 1 || (options.finalTotal != null && Number(options.finalTotal) < previous)) {
    contractFail("records_bounds_invalid", options.phase || "records", "record slice bounds are invalid");
  }
  return records;
}

module.exports = {
  API_VERSION,
  LiveE2EContractError,
  assertExactDirectory,
  assertOwnedRunDirectory,
  canonicalJson,
  canonicalRecordsDigest,
  contractFail,
  detectRasterMediaType,
  ensureExactChildDirectory,
  isPlainObject,
  pathInside,
  readExactRegularFile,
  samePath,
  sha256Bytes,
  sha256File,
  sha256Text,
  stableValue,
  stageOwnedCapture,
  verifyCanonicalRecords,
  verifyOwnedCapture,
};
