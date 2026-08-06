"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const Evidence = require("../lib/evidence-artifact");

const API_VERSION = "crafting-v4";
const BUNDLE_SCHEMA = "workbench-live-e2e.crafting.bundle.v6";
const RECEIPT_SCHEMA = "workbench-live-e2e.crafting.receipt.v4";
const TRANSCRIPT_SCHEMA = "workbench-live-e2e.crafting.transcript.v4";
const ARTIFACT_MANIFEST_SCHEMA = "workbench-live-e2e.crafting.artifact-manifest.v4";
const CONTROL_REQUEST_SCHEMA = "workbench-live-e2e.crafting.control-request.v4";
const CONTROL_ACK_SCHEMA = "workbench-live-e2e.crafting.control-ack.v4";
const PROVIDER_RECEIPT_SCHEMA = "workbench-live-e2e.crafting.provider-receipt.v5";
const PROVIDER_CAPTURE_EVENT_SCHEMA =
  "workbench-live-e2e.crafting.provider-capture-event.v1";
const AUTHORIZATION_SCHEMA = "workbench-live-e2e.crafting.authorization.v3";
const CAPABILITY_SCHEMA = "workbench-live-e2e.crafting.capability.v3";
const TOKEN_REF_RE = /^sha256_[a-f0-9]{24}$/;
const SHA256_RE = /^[a-f0-9]{64}$/i;
const ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "crafting");

function fail(code, phase, message, details) {
  Evidence.contractFail(code, phase, message, details);
}

function deepClone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function own(value, key) {
  return Object.prototype.hasOwnProperty.call(value || {}, key);
}

function tokenRef(value) {
  const text = String(value == null ? "" : value);
  return TOKEN_REF_RE.test(text) ? text : "sha256_" + Evidence.sha256Text(text).slice(0, 24);
}

function deriveRequestAuthorityBinding(message) {
  if (!Evidence.isPlainObject(message) || message.type !== "panel"
      || message.panel !== "crafting" || message.domain !== "crafting"
      || !Evidence.isPlainObject(message.payload)) return null;
  if (message.cmd === "preview") {
    const selector = {
      category: String(message.payload.category || ""),
      recipeIndex: Number(message.payload.recipeIndex),
      craftCount: Number(message.payload.craftCount),
    };
    return { basis: "request_payload", cmd: "preview",
      selectorRef: tokenRef(Evidence.canonicalJson(selector)) };
  }
  if (message.cmd === "commit") {
    return { basis: "request_payload", cmd: "commit",
      expectedCraftTokenRef: tokenRef(message.payload.expectedCraftToken) };
  }
  return null;
}

function sensitiveKey(key) {
  const value = String(key || "");
  return (/(?:token|transaction|secret)/i.test(value)
      || /^(?:expected|slot|close)?lease$/i.test(value))
    && !/(?:Ref|Refs|Present|Count|Sha256|Digest|Hash)$/i.test(value);
}

function redactAuthority(value, keyHint) {
  if (Array.isArray(value)) return value.map((entry) => redactAuthority(entry, keyHint));
  if (Evidence.isPlainObject(value)) {
    const output = {};
    Object.keys(value).forEach((key) => {
      if (sensitiveKey(key)) {
        const referenceKey = key + "Ref";
        const reference = tokenRef(typeof value[key] === "string"
          ? value[key] : Evidence.canonicalJson(value[key]));
        if (own(value, referenceKey) && value[referenceKey] !== reference) {
          fail("authority_reference_collision", "redaction",
            "raw authority value conflicts with its declared reference", { key });
        }
        output[referenceKey] = reference;
      } else output[key] = redactAuthority(value[key], key);
    });
    return output;
  }
  if (sensitiveKey(keyHint)) return tokenRef(value);
  return value;
}

function assertNoRawAuthority(value, phase) {
  function walk(current, key, locator) {
    if (sensitiveKey(key)) {
      fail("raw_authority_token_present", phase || "redaction",
        "authority-bearing field was persisted instead of a digest reference", { locator });
    }
    if (/(?:token|lease|transaction|secret|selector).*(?:Ref|Refs)$/i.test(String(key || ""))) {
      const values = String(current || "").split(",");
      if (!values.length || values.some((entry) => !TOKEN_REF_RE.test(entry))) {
        fail("authority_reference_invalid", phase || "redaction",
          "authority reference is not a bounded SHA-256 reference", { locator });
      }
    }
    if (Array.isArray(current)) current.forEach((entry, index) =>
      walk(entry, key, locator + "[" + index + "]"));
    else if (Evidence.isPlainObject(current)) Object.keys(current).forEach((child) =>
      walk(current[child], child, locator + "." + child));
  }
  walk(value, "", "$");
  return true;
}

function atomicWriteJson(filePath, value) {
  assertNoRawAuthority(value, "artifact_write");
  const absolute = path.resolve(filePath);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  const temporary = absolute + ".tmp-" + process.pid + "-" + Date.now();
  const text = JSON.stringify(value, null, 2) + "\n";
  fs.writeFileSync(temporary, text, { encoding: "utf8", flag: "wx", mode: 0o600 });
  fs.renameSync(temporary, absolute);
  return { path: absolute, bytes: Buffer.byteLength(text), sha256: Evidence.sha256Text(text) };
}

function readJsonFile(filePath, phase, maximumBytes) {
  const file = Evidence.readExactRegularFile(path.resolve(filePath), {
    phase: phase || "artifact", maximumBytes: maximumBytes || 128 * 1024 * 1024,
  });
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) { fail("artifact_json_invalid", phase || "artifact", error.message); }
  return { file, value };
}

function relativeOwnedPath(runDir, filePath) {
  const relative = path.relative(path.resolve(runDir), path.resolve(filePath)).replace(/\\/g, "/");
  if (!relative || relative.startsWith("../") || path.isAbsolute(relative)) {
    fail("artifact_path_escape", "artifact", "artifact escaped the owned run directory", { filePath });
  }
  return relative;
}

function walkRegularFiles(directory) {
  const output = [];
  function visit(current) {
    const stat = fs.lstatSync(current);
    if (stat.isSymbolicLink()) fail("artifact_reparse_forbidden", "artifact",
      "artifact tree contains a symbolic link", { current });
    if (stat.isDirectory()) {
      fs.readdirSync(current).forEach((name) => visit(path.join(current, name)));
      return;
    }
    if (!stat.isFile()) fail("artifact_not_regular", "artifact",
      "artifact is not a regular file", { current });
    output.push(current);
  }
  visit(path.resolve(directory));
  return output.sort((left, right) => left.localeCompare(right));
}

function buildArtifactManifest(options) {
  const root = path.resolve(options.root);
  const runDir = Evidence.assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || OWNED_BASE_RELATIVE, "artifact_manifest");
  const excluded = new Set(["artifact-manifest.json", "verified-receipt.json"]);
  const roles = options.roleByPath || {};
  const entries = walkRegularFiles(runDir).map((filePath) => {
    const relativePath = relativeOwnedPath(runDir, filePath);
    if (excluded.has(relativePath)) return null;
    const file = Evidence.readExactRegularFile(filePath, {
      phase: "artifact_manifest", maximumBytes: 128 * 1024 * 1024,
    });
    const role = String(roles[relativePath] || "raw_evidence");
    if (!/^[A-Za-z0-9._~-]{1,80}$/.test(role)) {
      fail("artifact_role_invalid", "artifact_manifest", "artifact role is malformed", { role });
    }
    return { relativePath, role, bytes: file.length, sha256: file.sha256 };
  }).filter(Boolean);
  const manifest = { schema: ARTIFACT_MANIFEST_SCHEMA, apiVersion: API_VERSION,
    runId: String(options.runId || ""), createdAt: new Date().toISOString(), entries };
  manifest.manifestSha256 = Evidence.sha256Text(Evidence.canonicalJson(manifest));
  return manifest;
}

function verifyArtifactManifest(options) {
  const root = path.resolve(options.root);
  const runDir = Evidence.assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || OWNED_BASE_RELATIVE, "artifact_manifest");
  const manifest = options.manifest;
  if (!Evidence.isPlainObject(manifest) || manifest.schema !== ARTIFACT_MANIFEST_SCHEMA
      || manifest.apiVersion !== API_VERSION || !ID_RE.test(String(manifest.runId || ""))
      || !Number.isFinite(Date.parse(manifest.createdAt)) || !Array.isArray(manifest.entries)
      || !SHA256_RE.test(String(manifest.manifestSha256 || ""))) {
    fail("artifact_manifest_invalid", "artifact_manifest", "artifact manifest is malformed");
  }
  const payload = deepClone(manifest);
  delete payload.manifestSha256;
  if (Evidence.sha256Text(Evidence.canonicalJson(payload)) !== manifest.manifestSha256) {
    fail("artifact_manifest_digest_invalid", "artifact_manifest", "artifact manifest digest drifted");
  }
  let previous = "";
  const seen = new Set();
  manifest.entries.forEach((entry) => {
    if (!Evidence.isPlainObject(entry) || typeof entry.relativePath !== "string"
        || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(entry.role || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1 || !SHA256_RE.test(String(entry.sha256 || ""))
        || entry.relativePath <= previous || seen.has(entry.relativePath.toLowerCase())) {
      fail("artifact_manifest_entry_invalid", "artifact_manifest",
        "artifact entry is malformed, duplicated, or unordered", { entry });
    }
    previous = entry.relativePath;
    seen.add(entry.relativePath.toLowerCase());
    const absolute = path.resolve(runDir, entry.relativePath.replace(/\//g, path.sep));
    if (relativeOwnedPath(runDir, absolute) !== entry.relativePath) {
      fail("artifact_manifest_path_invalid", "artifact_manifest", "artifact path is not canonical");
    }
    const file = Evidence.readExactRegularFile(absolute, {
      phase: "artifact_manifest", maximumBytes: 128 * 1024 * 1024,
    });
    if (file.length !== entry.bytes || file.sha256 !== entry.sha256.toLowerCase()) {
      fail("artifact_manifest_file_mismatch", "artifact_manifest", "artifact bytes/hash drifted");
    }
  });
  const actual = walkRegularFiles(runDir).map((entry) => relativeOwnedPath(runDir, entry))
    .filter((entry) => !["artifact-manifest.json", "verified-receipt.json"].includes(entry));
  if (Evidence.canonicalJson(actual) !== Evidence.canonicalJson(
    manifest.entries.map((entry) => entry.relativePath))) {
    fail("artifact_manifest_set_mismatch", "artifact_manifest", "artifact set is not complete");
  }
  return new Map(manifest.entries.map((entry) => [entry.relativePath, entry]));
}

let pngCrcTable = null;
function pngCrc32(bytes) {
  if (!pngCrcTable) {
    pngCrcTable = Array.from({ length: 256 }, (_unused, index) => {
      let value = index;
      for (let bit = 0; bit < 8; bit += 1) {
        value = (value & 1) ? (0xedb88320 ^ (value >>> 1)) : (value >>> 1);
      }
      return value >>> 0;
    });
  }
  let crc = 0xffffffff;
  for (const byte of bytes) crc = pngCrcTable[(crc ^ byte) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

/** Strictly parses and inflates one bounded, non-interlaced PNG capture. */
function decodePng(bytesInput) {
  const bytes = Buffer.isBuffer(bytesInput) ? bytesInput : Buffer.from(bytesInput || []);
  const signature = Buffer.from("89504e470d0a1a0a", "hex");
  if (bytes.length < 45 || bytes.length > 16 * 1024 * 1024
      || !bytes.subarray(0, 8).equals(signature)) {
    fail("control_capture_media_invalid", "control_capture",
      "capture is not one bounded PNG file");
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
    if (bytes.readUInt32BE(offset + 8 + length)
        !== pngCrc32(Buffer.concat([typeBytes, data]))) {
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
      if (!ihdr || iend || idatClosed) {
        fail("control_capture_media_invalid", "control_capture", "PNG IDAT order is invalid");
      }
      idat.push(Buffer.from(data));
    } else if (type === "IEND") {
      if (length !== 0 || iend || end !== bytes.length) {
        fail("control_capture_media_invalid", "control_capture",
          "PNG IEND or trailing bytes are invalid");
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
    fail("control_capture_media_invalid", "control_capture", "PNG IHDR is unsupported or unsafe");
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
  } catch (error) {
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
        const byte = pixels[rowOffset + Math.floor(bitOffset / 8)];
        const shift = 8 - bitDepth - bitOffset % 8;
        const paletteIndex = (byte >>> shift) & mask;
        if (paletteIndex >= paletteEntries) {
          fail("control_capture_media_invalid", "control_capture",
            "PNG indexed pixel exceeds the declared palette", {
              row, column, paletteIndex, paletteEntries,
            });
        }
      }
    }
  }
  return { mediaType: "image/png", width, height, bytes: bytes.length,
    pixelBytes: pixels.length, pixelSha256: Evidence.sha256Bytes(pixels) };
}



function nextRecord(previousHash, sequence, raw) {
  const record = Object.assign({}, raw, { sequence, previousHash });
  record.eventHash = Evidence.sha256Text(previousHash + "\n" + Evidence.canonicalJson(record));
  return record;
}

function verifyRecordChain(transcript) {
  if (!Evidence.isPlainObject(transcript) || transcript.schema !== TRANSCRIPT_SCHEMA
      || !ID_RE.test(String(transcript.observerId || "")) || !Array.isArray(transcript.events)) {
    fail("transcript_invalid", "transcript", "passive transcript envelope is malformed");
  }
  let previousHash = "0".repeat(64);
  transcript.events.forEach((event, index) => {
    if (!Evidence.isPlainObject(event) || event.sequence !== index + 1
        || event.previousHash !== previousHash || !SHA256_RE.test(String(event.eventHash || ""))) {
      fail("transcript_chain_invalid", "transcript", "transcript chain is malformed", { index });
    }
    const payload = deepClone(event);
    delete payload.eventHash;
    if (Evidence.sha256Text(previousHash + "\n" + Evidence.canonicalJson(payload)) !== event.eventHash) {
      fail("transcript_chain_invalid", "transcript", "transcript event digest drifted", { index });
    }
    assertNoRawAuthority(event, "transcript");
    previousHash = event.eventHash;
  });
  if (transcript.eventCount !== transcript.events.length || transcript.chainHead !== previousHash) {
    fail("transcript_terminal_invalid", "transcript", "transcript terminal count/head drifted");
  }
  return transcript;
}

module.exports = {
  API_VERSION, ARTIFACT_MANIFEST_SCHEMA, AUTHORIZATION_SCHEMA, BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA, CONTROL_ACK_SCHEMA, CONTROL_REQUEST_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA, PROVIDER_RECEIPT_SCHEMA, ID_RE,
  OWNED_BASE_RELATIVE, RECEIPT_SCHEMA, SHA256_RE, TOKEN_REF_RE, TRANSCRIPT_SCHEMA,
  assertNoRawAuthority, atomicWriteJson, buildArtifactManifest, decodePng, deepClone, fail, nextRecord,
  deriveRequestAuthorityBinding, own, readJsonFile,
  redactAuthority, relativeOwnedPath, tokenRef, verifyArtifactManifest,
  verifyRecordChain, walkRegularFiles,
};
