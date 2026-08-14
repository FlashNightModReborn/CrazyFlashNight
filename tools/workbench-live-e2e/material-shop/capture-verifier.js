"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const Evidence = require("../lib/evidence-artifact");
const PngContract = require("../kshop/png-contract");
const Common = require("./common");

const CAPTURE_SCHEMA = "workbench-live-e2e.material-shop.capture.v1";
const AGENT_RUNTIME_CAPTURE_SCHEMA =
  "workbench-live-e2e.material-shop.agent-runtime-capture.v1";
const MAXIMUM_CAPTURE_BYTES = 32 * 1024 * 1024;
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let index = 0; index < 256; index += 1) {
    let value = index;
    for (let bit = 0; bit < 8; bit += 1) {
      value = (value & 1) ? (0xEDB88320 ^ (value >>> 1)) : (value >>> 1);
    }
    table[index] = value >>> 0;
  }
  return table;
})();

function crc32(bytes) {
  let value = 0xFFFFFFFF;
  for (let index = 0; index < bytes.length; index += 1) {
    value = CRC_TABLE[(value ^ bytes[index]) & 0xFF] ^ (value >>> 8);
  }
  return (value ^ 0xFFFFFFFF) >>> 0;
}

function pngChunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBytes, data])), 0);
  return Buffer.concat([length, typeBytes, data, crc]);
}

function bgraPremultipliedToPng(pixels, width, height) {
  const expectedBytes = width * height * 4;
  if (!Buffer.isBuffer(pixels) || !Number.isSafeInteger(expectedBytes)
      || expectedBytes < 4 || pixels.length !== expectedBytes) {
    Common.fail("material_shop_agent_capture_bgra_invalid", "agent_capture",
      "Agent Runtime capture is not one exact width*height*4 BGRA object");
  }
  const scanlines = Buffer.alloc(height * (1 + width * 4));
  for (let y = 0; y < height; y += 1) {
    const row = y * (1 + width * 4);
    scanlines[row] = 0;
    for (let x = 0; x < width; x += 1) {
      const source = (y * width + x) * 4;
      const target = row + 1 + x * 4;
      const blue = pixels[source];
      const green = pixels[source + 1];
      const red = pixels[source + 2];
      const alpha = pixels[source + 3];
      if (blue > alpha || green > alpha || red > alpha) {
        Common.fail("material_shop_agent_capture_premultiplication_invalid", "agent_capture",
          "BGRA color channels exceed alpha in a premultiplied frame", { x, y });
      }
      const unpremultiply = (channel) => alpha === 0 ? 0
        : Math.min(255, Math.floor((channel * 255 + Math.floor(alpha / 2)) / alpha));
      scanlines[target] = unpremultiply(red);
      scanlines[target + 1] = unpremultiply(green);
      scanlines[target + 2] = unpremultiply(blue);
      scanlines[target + 3] = alpha;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  return Buffer.concat([PNG_SIGNATURE, pngChunk("IHDR", ihdr),
    pngChunk("IDAT", zlib.deflateSync(scanlines)), pngChunk("IEND", Buffer.alloc(0))]);
}

function pngDimensions(bytes) {
  let decoded;
  try { decoded = PngContract.decodePng(bytes, "material_shop_capture"); }
  catch (error) {
    Common.fail("material_shop_capture_png_invalid", "capture",
      "capture failed strict PNG chunks/CRC/decode validation", {
        cause: error && error.code || error && error.message,
      });
  }
  const width = decoded.width;
  const height = decoded.height;
  const bitDepth = decoded.bitDepth;
  const colorType = decoded.colorType;
  if (width < 800 || height < 450 || width > 16384 || height > 16384
      || ![1, 2, 4, 8, 16].includes(bitDepth) || ![0, 2, 3, 4, 6].includes(colorType)) {
    Common.fail("material_shop_capture_png_invalid", "capture",
      "capture PNG dimensions, color contract, or terminal chunk is invalid",
      { width, height, bitDepth, colorType });
  }
  return { width, height, bitDepth, colorType };
}

function stableCapture(value) {
  return {
    schema: value.schema, step: value.step, requestId: value.requestId,
    capturedAt: value.capturedAt, sourceLastWriteUtc: value.sourceLastWriteUtc,
    requestBindingSha256: value.requestBindingSha256,
    operationArtifactSha256: value.operationArtifactSha256,
    candidateBinding: value.candidateBinding, capture: value.capture,
    width: value.width, height: value.height,
    bitDepth: value.bitDepth, colorType: value.colorType,
  };
}

function stableAgentRuntimeCapture(value) {
  return {
    schema: value.schema,
    sessionLabel: value.sessionLabel,
    stepId: value.stepId,
    observationId: value.observationId,
    grantId: value.grantId,
    targetId: value.targetId,
    frameId: value.frameId,
    width: value.width,
    height: value.height,
    frameContentHash: value.frameContentHash,
    source: value.source,
    png: value.png,
  };
}

function agentRuntimeCaptureFields(capture) {
  if (!Evidence.isPlainObject(capture) || !Evidence.isPlainObject(capture.grant)
      || !Evidence.isPlainObject(capture.surface)
      || !Evidence.isPlainObject(capture.observation)
      || !Evidence.isPlainObject(capture.frame)) {
    Common.fail("material_shop_agent_capture_input_invalid", "agent_capture",
      "Agent Runtime capture lacks its exact grant/surface/observation/frame binding");
  }
  const pixels = capture.pixels;
  const width = capture.width;
  const height = capture.height;
  const observationId = String(capture.observation.observationId || "");
  const grantId = String(capture.grant.observationGrantId || "");
  const targetId = String(capture.surface.targetId || "");
  const frameId = String(capture.frame.frameId || "");
  const frameContentHash = String(capture.frame.contentHash || "").toLowerCase();
  const sourceSha256 = Buffer.isBuffer(pixels) ? Evidence.sha256Bytes(pixels) : "";
  if (!Common.ID_RE.test(observationId) || !Common.ID_RE.test(grantId)
      || !Common.ID_RE.test(targetId) || !Common.ID_RE.test(frameId)
      || !Common.SHA256_RE.test(frameContentHash)
      || !Number.isSafeInteger(width) || width < 1
      || !Number.isSafeInteger(height) || height < 1
      || capture.frame.width !== width || capture.frame.height !== height
      || capture.frame.pixelFormat !== "bgra8_premultiplied"
      || capture.observation.observationGrantId !== grantId
      || capture.observation.observationId !== observationId
      || capture.observation.targetId !== targetId
      || capture.frame.observationId !== observationId
      || capture.frame.targetId !== targetId
      || frameContentHash !== sourceSha256) {
    Common.fail("material_shop_agent_capture_binding_invalid", "agent_capture",
      "Agent Runtime BGRA bytes are detached from the exact capture binding");
  }
  return { pixels, width, height, observationId, grantId, targetId, frameId,
    frameContentHash, sourceSha256 };
}

function createAgentRuntimeCapture(runDirValue, options) {
  const settings = options || {};
  const runDir = Evidence.assertOwnedRunDirectory(settings.root, runDirValue,
    Common.OWNED_BASE_RELATIVE, "agent_capture");
  const sessionLabel = String(settings.sessionLabel || "");
  const stepId = String(settings.stepId || "");
  if (!Common.ID_RE.test(sessionLabel) || !Common.ID_RE.test(stepId)) {
    Common.fail("material_shop_agent_capture_identity_invalid", "agent_capture",
      "Agent Runtime capture session/step identity is not closed");
  }
  const input = agentRuntimeCaptureFields(settings.capture);
  const pngBytes = bgraPremultipliedToPng(input.pixels, input.width, input.height);
  if (pngBytes.length > MAXIMUM_CAPTURE_BYTES) {
    Common.fail("material_shop_agent_capture_png_oversize", "agent_capture",
      "Agent Runtime PNG exceeds its bounded evidence limit");
  }
  const decoded = PngContract.decodePng(pngBytes, "material_shop_agent_capture_png");
  if (decoded.width !== input.width || decoded.height !== input.height
      || decoded.bitDepth !== 8 || decoded.colorType !== 6) {
    Common.fail("material_shop_agent_capture_png_invalid", "agent_capture",
      "encoded Agent Runtime PNG does not preserve exact frame geometry");
  }
  const capturesDir = Evidence.ensureExactChildDirectory(runDir, "captures", "agent_capture");
  const relativePath = "captures/agent-" + stepId + ".png";
  const outputPath = path.join(capturesDir, "agent-" + stepId + ".png");
  try { fs.writeFileSync(outputPath, pngBytes, { flag: "wx", mode: 0o600 }); }
  catch (error) {
    Common.fail("material_shop_agent_capture_create_failed", "agent_capture",
      "Agent Runtime capture output must be a new exact file", { code: error && error.code });
  }
  const value = {
    schema: AGENT_RUNTIME_CAPTURE_SCHEMA,
    sessionLabel,
    stepId,
    observationId: input.observationId,
    grantId: input.grantId,
    targetId: input.targetId,
    frameId: input.frameId,
    width: input.width,
    height: input.height,
    frameContentHash: input.frameContentHash,
    source: {
      pixelFormat: "bgra8_premultiplied",
      bytes: input.pixels.length,
      sha256: input.sourceSha256,
    },
    png: {
      relativePath,
      bytes: pngBytes.length,
      sha256: Evidence.sha256Bytes(pngBytes),
    },
  };
  value.captureSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(stableAgentRuntimeCapture(value)));
  return verifyAgentRuntimeCapture(settings.root, runDir, value);
}

function verifyAgentRuntimeCapture(root, runDirValue, value) {
  const runDir = Evidence.assertOwnedRunDirectory(root, runDirValue,
    Common.OWNED_BASE_RELATIVE, "agent_capture");
  Common.exactKeys(value, ["schema", "sessionLabel", "stepId", "observationId",
    "grantId", "targetId", "frameId", "width", "height", "frameContentHash",
    "source", "png", "captureSha256"],
  "material_shop_agent_capture_receipt_invalid", "agent_capture");
  Common.exactKeys(value.source, ["pixelFormat", "bytes", "sha256"],
    "material_shop_agent_capture_receipt_invalid", "agent_capture");
  Common.exactKeys(value.png, ["relativePath", "bytes", "sha256"],
    "material_shop_agent_capture_receipt_invalid", "agent_capture");
  const expectedRelativePath = "captures/agent-" + value.stepId + ".png";
  if (value.schema !== AGENT_RUNTIME_CAPTURE_SCHEMA
      || !Common.ID_RE.test(String(value.sessionLabel || ""))
      || !Common.ID_RE.test(String(value.stepId || ""))
      || !Common.ID_RE.test(String(value.observationId || ""))
      || !Common.ID_RE.test(String(value.grantId || ""))
      || !Common.ID_RE.test(String(value.targetId || ""))
      || !Common.ID_RE.test(String(value.frameId || ""))
      || !Number.isSafeInteger(value.width) || value.width < 1
      || !Number.isSafeInteger(value.height) || value.height < 1
      || !Common.SHA256_RE.test(String(value.frameContentHash || ""))
      || value.source.pixelFormat !== "bgra8_premultiplied"
      || value.source.bytes !== value.width * value.height * 4
      || !Common.SHA256_RE.test(String(value.source.sha256 || ""))
      || value.source.sha256 !== value.frameContentHash
      || value.png.relativePath !== expectedRelativePath
      || !Number.isSafeInteger(value.png.bytes) || value.png.bytes < 1
      || value.png.bytes > MAXIMUM_CAPTURE_BYTES
      || !Common.SHA256_RE.test(String(value.png.sha256 || ""))
      || value.captureSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableAgentRuntimeCapture(value)))) {
    Common.fail("material_shop_agent_capture_receipt_invalid", "agent_capture",
      "Agent Runtime capture receipt is malformed or detached");
  }
  const capturePath = path.resolve(runDir, value.png.relativePath.replace(/\//g, path.sep));
  if (!Evidence.pathInside(runDir, capturePath)) {
    Common.fail("material_shop_agent_capture_path_escape", "agent_capture",
      "Agent Runtime capture escaped the owned run directory");
  }
  const file = Evidence.readExactRegularFile(capturePath, {
    phase: "agent_capture", maximumBytes: MAXIMUM_CAPTURE_BYTES,
  });
  if (file.length !== value.png.bytes || file.sha256 !== value.png.sha256) {
    Common.fail("material_shop_agent_capture_png_mismatch", "agent_capture",
      "Agent Runtime PNG bytes differ from the receipt");
  }
  const decoded = PngContract.decodePng(file.bytes, "material_shop_agent_capture_png");
  if (decoded.width !== value.width || decoded.height !== value.height
      || decoded.bitDepth !== 8 || decoded.colorType !== 6
      || decoded.decodedBytes !== value.width * value.height * 4) {
    Common.fail("material_shop_agent_capture_dimension_mismatch", "agent_capture",
      "Agent Runtime PNG dimensions or RGBA payload differ from the receipt");
  }
  return value;
}

function stageCapture(options) {
  const settings = options || {};
  const runDir = Evidence.assertOwnedRunDirectory(settings.root, settings.runDir,
    Common.OWNED_BASE_RELATIVE, "capture");
  const capturesDir = Evidence.ensureExactChildDirectory(
    path.join(runDir, "control"), "captures", "capture");
  const capture = Evidence.stageOwnedCapture({
    root: settings.root, runDir, ownedBaseRelative: Common.OWNED_BASE_RELATIVE,
    capturesDir, artifactId: settings.requestId,
    sourcePath: settings.sourcePath, expectedSha256: settings.expectedSha256,
    maximumBytes: MAXIMUM_CAPTURE_BYTES, phase: "capture",
  });
  if (capture.mediaType !== "image/png") {
    Common.fail("material_shop_capture_media_invalid", "capture",
      "A5 visual evidence requires a lossless PNG capture");
  }
  const sourceStat = fs.statSync(path.resolve(settings.sourcePath));
  const stagedPath = path.join(runDir, capture.relativePath.replace(/\//g, path.sep));
  fs.utimesSync(stagedPath, sourceStat.atime, sourceStat.mtime);
  const file = Evidence.readExactRegularFile(path.join(runDir,
    capture.relativePath.replace(/\//g, path.sep)), {
    phase: "capture", maximumBytes: MAXIMUM_CAPTURE_BYTES,
  });
  const dimensions = pngDimensions(file.bytes);
  const sourceLastWriteUtc = fs.statSync(stagedPath).mtime.toISOString();
  const request = settings.request;
  const capturedAt = settings.capturedAt || new Date().toISOString();
  if (!request || Date.parse(sourceLastWriteUtc) < Date.parse(request.issuedAt)
      || Date.parse(sourceLastWriteUtc) > Date.parse(capturedAt)
      || !settings.rawOperationArtifact || !settings.candidateBinding) {
    Common.fail("material_shop_capture_provenance_invalid", "capture",
      "capture source is stale or detached from operator/candidate evidence");
  }
  const value = {
    schema: CAPTURE_SCHEMA,
    step: String(settings.step || ""),
    requestId: String(settings.requestId || ""),
    capturedAt,
    sourceLastWriteUtc,
    requestBindingSha256: Evidence.sha256Text(Evidence.canonicalJson(request)),
    operationArtifactSha256: settings.rawOperationArtifact.sha256,
    candidateBinding: JSON.parse(JSON.stringify(settings.candidateBinding)),
    capture,
    width: dimensions.width,
    height: dimensions.height,
    bitDepth: dimensions.bitDepth,
    colorType: dimensions.colorType,
  };
  if (!Common.ID_RE.test(value.step) || !Common.ID_RE.test(value.requestId)
      || !Number.isFinite(Date.parse(value.capturedAt))) {
    Common.fail("material_shop_capture_identity_invalid", "capture",
      "capture lacks an exact request/step/time identity");
  }
  value.captureReceiptSha256 = Evidence.sha256Text(Evidence.canonicalJson(stableCapture(value)));
  return verifyCapture(settings.root, runDir, value);
}

function verifyCapture(root, runDir, value) {
  Common.exactKeys(value, ["schema", "step", "requestId", "capturedAt",
    "sourceLastWriteUtc", "requestBindingSha256", "operationArtifactSha256",
    "candidateBinding", "capture", "width", "height", "bitDepth", "colorType",
    "captureReceiptSha256"],
  "material_shop_capture_receipt_invalid", "capture");
  if (value.schema !== CAPTURE_SCHEMA || !Common.ID_RE.test(String(value.step || ""))
      || !Common.ID_RE.test(String(value.requestId || ""))
      || !Number.isFinite(Date.parse(value.capturedAt))
      || !Number.isFinite(Date.parse(value.sourceLastWriteUtc))
      || !Common.SHA256_RE.test(String(value.requestBindingSha256 || ""))
      || !Common.SHA256_RE.test(String(value.operationArtifactSha256 || ""))
      || !Evidence.isPlainObject(value.candidateBinding)
      || value.captureReceiptSha256 !== Evidence.sha256Text(
        Evidence.canonicalJson(stableCapture(value)))) {
    Common.fail("material_shop_capture_receipt_invalid", "capture",
      "capture receipt is malformed or detached");
  }
  const capture = Evidence.verifyOwnedCapture({
    root, runDir, ownedBaseRelative: Common.OWNED_BASE_RELATIVE,
    capture: value.capture, phase: "capture", maximumBytes: MAXIMUM_CAPTURE_BYTES,
  });
  if (capture.mediaType !== "image/png") {
    Common.fail("material_shop_capture_media_invalid", "capture", "capture is not PNG");
  }
  const dimensions = pngDimensions(fs.readFileSync(capture.path));
  if (dimensions.width !== value.width || dimensions.height !== value.height
      || dimensions.bitDepth !== value.bitDepth || dimensions.colorType !== value.colorType) {
    Common.fail("material_shop_capture_dimension_mismatch", "capture",
      "PNG IHDR differs from the bound capture receipt");
  }
  return value;
}

module.exports = {
  AGENT_RUNTIME_CAPTURE_SCHEMA,
  CAPTURE_SCHEMA,
  MAXIMUM_CAPTURE_BYTES,
  bgraPremultipliedToPng,
  createAgentRuntimeCapture,
  pngDimensions,
  stableCapture,
  stableAgentRuntimeCapture,
  stageCapture,
  verifyCapture,
  verifyAgentRuntimeCapture,
};
