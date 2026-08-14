"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const CaptureVerifier = require("./capture-verifier");
const Common = require("./common");
const Evidence = require("../lib/evidence-artifact");
const PngContract = require("../kshop/png-contract");

const root = Common.CANONICAL_ROOT;

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function fixture(stepId) {
  const width = 320;
  const height = 180;
  const pixels = Buffer.alloc(width * height * 4);
  // Fully transparent pixels canonicalize to transparent black.
  pixels.set([0, 0, 0, 0], 0);
  // BGRA premultiplied half-alpha: unpremultiplies to RGBA [64,128,255,128].
  pixels.set([128, 64, 32, 128], 4);
  // Opaque BGRA becomes RGBA without scaling.
  pixels.set([3, 2, 1, 255], 8);
  const contentHash = sha256(pixels);
  const observationId = "observation_1";
  const grantId = "grant_1";
  const targetId = "target_1";
  return {
    sessionLabel: "first_session",
    stepId,
    capture: {
      width,
      height,
      pixels,
      grant: { observationGrantId: grantId },
      surface: { targetId },
      observation: {
        observationId,
        observationGrantId: grantId,
        targetId,
      },
      frame: {
        frameId: "frame_1",
        observationId,
        targetId,
        width,
        height,
        pixelFormat: "bgra8_premultiplied",
        contentHash,
      },
    },
  };
}

function createRunDir(label) {
  const base = path.join(root, Common.OWNED_BASE_RELATIVE);
  fs.mkdirSync(base, { recursive: true });
  return fs.mkdtempSync(path.join(base, "capture-test-" + label + "-"));
}

function expectFailure(fn, label) {
  assert.throws(fn, (error) => error && typeof error.code === "string", label);
}

function main() {
  const runDirs = [];
  try {
    const runDir = createRunDir("positive");
    runDirs.push(runDir);
    const options = fixture("open_materials");
    options.root = root;
    const receipt = CaptureVerifier.createAgentRuntimeCapture(runDir, options);
    assert.strictEqual(receipt.schema, CaptureVerifier.AGENT_RUNTIME_CAPTURE_SCHEMA);
    assert.strictEqual(receipt.source.bytes, 320 * 180 * 4);
    assert.strictEqual(receipt.source.sha256, options.capture.frame.contentHash);
    CaptureVerifier.verifyAgentRuntimeCapture(root, runDir, receipt);

    const pngPath = path.join(runDir, receipt.png.relativePath);
    const decoded = PngContract.decodePng(fs.readFileSync(pngPath), "test_agent_capture");
    const expectedRgba = Buffer.alloc(320 * 180 * 4);
    expectedRgba.set([0, 0, 0, 0], 0);
    expectedRgba.set([64, 128, 255, 128], 4);
    expectedRgba.set([1, 2, 3, 255], 8);
    assert.strictEqual(decoded.pixelSha256, sha256(expectedRgba),
      "alpha edges must unpremultiply and transparent pixels must canonicalize");

    const hashDriftDir = createRunDir("hash-drift");
    runDirs.push(hashDriftDir);
    const hashDrift = fixture("hash_drift");
    hashDrift.root = root;
    hashDrift.capture.frame.contentHash = "0".repeat(64);
    expectFailure(() => CaptureVerifier.createAgentRuntimeCapture(hashDriftDir, hashDrift),
      "BGRA/frame hash drift must fail before creating evidence");

    const pngDrift = clone(receipt);
    const pngBytes = fs.readFileSync(pngPath);
    pngBytes[pngBytes.length - 1] ^= 1;
    fs.writeFileSync(pngPath, pngBytes);
    expectFailure(() => CaptureVerifier.verifyAgentRuntimeCapture(root, runDir, pngDrift),
      "PNG drift must fail exact re-read verification");

    const pathDir = createRunDir("path-escape");
    runDirs.push(pathDir);
    const pathOptions = fixture("path_escape");
    pathOptions.root = root;
    const pathReceipt = CaptureVerifier.createAgentRuntimeCapture(pathDir, pathOptions);
    pathReceipt.png.relativePath = "../escaped.png";
    pathReceipt.captureSha256 = Evidence.sha256Text(Evidence.canonicalJson(
      CaptureVerifier.stableAgentRuntimeCapture(pathReceipt)));
    expectFailure(() => CaptureVerifier.verifyAgentRuntimeCapture(root, pathDir, pathReceipt),
      "path escape must fail even with a recomputed receipt digest");

    const duplicateDir = createRunDir("duplicate");
    runDirs.push(duplicateDir);
    const duplicate = fixture("duplicate");
    duplicate.root = root;
    CaptureVerifier.createAgentRuntimeCapture(duplicateDir, duplicate);
    expectFailure(() => CaptureVerifier.createAgentRuntimeCapture(duplicateDir, duplicate),
      "Agent Runtime capture output must use CreateNew semantics");

    const invalidAlphaDir = createRunDir("invalid-alpha");
    runDirs.push(invalidAlphaDir);
    const invalidAlpha = fixture("invalid_alpha");
    invalidAlpha.root = root;
    invalidAlpha.capture.pixels[0] = 1;
    invalidAlpha.capture.frame.contentHash = sha256(invalidAlpha.capture.pixels);
    expectFailure(() => CaptureVerifier.createAgentRuntimeCapture(invalidAlphaDir, invalidAlpha),
      "non-premultiplied alpha edge must fail closed");

    console.log("agent runtime capture tests: 6/6 passed");
  } finally {
    for (const runDir of runDirs) fs.rmSync(runDir, { recursive: true, force: true });
  }
}

main();
