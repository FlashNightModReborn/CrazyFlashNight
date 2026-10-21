"use strict";

// Interactive adapter over the existing qualified formal/candidate trusted runner. It does
// not enroll a client, read credentials, invoke business commands, or reset saves.
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const zlib = require("node:zlib");
const assert = require("node:assert/strict");
const Profile = require("./regression-profile");
const Evidence = require("../workbench-live-e2e/lib/evidence-artifact");
const Controller = require("../workbench-live-e2e/material-shop/trusted-runtime-controller");
const resourcesRoot = path.resolve(__dirname, "../..");

function createPreparation({ candidateId, slot }) {
  const preparation = { schema: Profile.SCHEMA, resourcesRoot, candidateId,
    slots: { targetSlot: slot } };
  Profile.resolve(preparation);
  if (candidateId === undefined) {
    const manifestFile = Evidence.readExactRegularFile(path.join(resourcesRoot,
      "runtime/cf7-runtime-manifest.tsv"), {phase:"regression_session",maximumBytes:65536});
    const lines = manifestFile.bytes.toString("utf8").replace(/^\uFEFF/, "").trimEnd().split(/\r?\n/);
    assert.equal(lines[0], "cf7-runtime-manifest-v2");
    function field(name) {
      const rows = lines.slice(1).map(line=>line.split("\t")).filter(row=>row[0]===name);
      assert.equal(rows.length, 1, "Expected one manifest " + name);
      assert.equal(rows[0].length, 2);
      assert(/^[A-Fa-f0-9]{64}$/.test(rows[0][1]), "Invalid manifest " + name);
      return rows[0][1];
    }
    const core = Evidence.readExactRegularFile(path.join(resourcesRoot,
      "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe"),
    {phase:"regression_session",maximumBytes:16*1024*1024});
    const coreRows = lines.map(line=>line.split("\t")).filter(row=>row[0]==="file"
      && row[1]==="runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe");
    assert.equal(coreRows.length, 1);
    assert.equal(coreRows[0].length, 4);
    assert.equal(coreRows[0][2], String(core.bytes.length));
    assert.equal(coreRows[0][3].toLowerCase(), core.sha256);
    preparation.runtimeIdentity = {runtimeMode:"formal_runtime",processPath:core.path,
      coreSha256:core.sha256,buildIdentity:field("buildIdentityHash"),payloadClosure:field("payloadClosureHash")};
    // The canonical bootstrap and trusted Core independently verify the complete
    // manifest/consensus. These expectations bind the supported exit to this launch.
    return preparation;
  }
  preparation.candidateRoot = path.join(resourcesRoot, "tmp/runtime-candidates/v2", candidateId);
  Evidence.assertExactDirectory(preparation.candidateRoot, "regression_session");
  const metadataFile = Evidence.readExactRegularFile(
    path.join(preparation.candidateRoot, "runtime-build-metadata.v2.json"),
    { phase: "regression_session", maximumBytes: 65536 });
  const metadata = JSON.parse(metadataFile.bytes.toString("utf8").replace(/^\uFEFF/, ""));
  assert.equal(metadata.schema, "cf7-runtime-candidate-metadata.v2");
  for (const key of ["buildIdentityHash", "payloadClosureHash"])
    assert(/^[A-Fa-f0-9]{64}$/.test(metadata[key]), "Missing candidate " + key);
  const core = Evidence.readExactRegularFile(path.join(preparation.candidateRoot,
    "runtime/CRAZYFLASHER7MercenaryEmpire.Core.exe"),
  { phase: "regression_session", maximumBytes: 16 * 1024 * 1024 });
  preparation.candidateIdentity = {
    runtimeMode: "isolated_candidate", processPath: core.path, coreSha256: core.sha256,
    buildIdentity: metadata.buildIdentityHash, payloadClosure: metadata.payloadClosureHash
  };
  // The wrapper/Host independently verify the complete immutable manifest before
  // launch. These expected values also bind the final normal-exit receipt.
  return preparation;
}

async function createSession(options) {
  return bindWorkBudget(await Controller.start(createPreparation(options)));
}

function bindWorkBudget(session, now = () => Number(process.hrtime.bigint() / 1000000n)) {
  const began = now(), workWindowMs = 8 * 60 * 1000;
  session.getRegressionBudget = () => ({ workWindowMs,
    elapsedMs: Math.max(0, now() - began),
    remainingWorkMs: Math.max(0, workWindowMs - (now() - began)),
    checkpointDue: now() - began >= workWindowMs });
  for (const name of ["click", "pressKey", "typeText", "openPanel"]) {
    const operation = session[name].bind(session);
    session[name] = (...args) => {
      if (session.getRegressionBudget().checkpointDue) {
        const error = new Error("Regression work window ended; inspect/reconcile any pending business result, finish normally, then resume the current test role in a fresh session");
        error.code = "regression_checkpoint_due";
        throw error;
      }
      return operation(...args);
    };
  }
  // Reads and supported shutdown remain available. This is a conservative client
  // work budget, not a claim about or extension of the Host's credential expiry.
  return session;
}

function withoutPixels(value) {
  if (Array.isArray(value)) return value.map(withoutPixels);
  if (value && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).filter(([key]) =>
      !["contentBase64", "pixels"].includes(key)).map(([key, entry]) => [key, withoutPixels(entry)]));
  }
  return value;
}

function writeAudit(session, file, observations = [], completion = null) {
  const auditRoot = path.join(resourcesRoot, "tmp/issue-152-acceptance");
  const destination = path.resolve(file);
  assert(destination.startsWith(auditRoot + path.sep), "Audit must stay inside the task evidence directory");
  Evidence.assertExactDirectory(path.dirname(destination), "regression_session");
  const audit = withoutPixels({ schema: "cf7.regression-session-audit.v1",
    capturedAtUtc: new Date().toISOString(), preparation: session.preparation,
    status: session.status, observations, completion,
    ledger: session.getLedger(), rpcTranscript: session.getRpcTranscript() });
  fs.writeFileSync(destination, JSON.stringify(audit, null, 2) + "\n", { encoding: "utf8", flag: "wx" });
  return { path: destination, sha256: crypto.createHash("sha256")
    .update(fs.readFileSync(destination)).digest("hex").toUpperCase() };
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const name = Buffer.from(type, "ascii"), size = Buffer.alloc(4), checksum = Buffer.alloc(4);
  size.writeUInt32BE(data.length); checksum.writeUInt32BE(crc32(Buffer.concat([name, data])));
  return Buffer.concat([size, name, data, checksum]);
}

// Returns in-memory PNG bytes for an ephemeral viewer. Observation grants do not
// permit persisting/exporting pixels; the audit records frame hashes instead.
function captureToPng(capture) {
  const { width, height, pixels } = capture;
  assert(Number.isSafeInteger(width) && width > 0 && Number.isSafeInteger(height) && height > 0);
  assert(width * height <= 4194304 && Buffer.isBuffer(pixels) && pixels.length === width * height * 4);
  assert.equal(capture.frame.pixelFormat, "bgra8_premultiplied");
  const rows = Buffer.alloc(height * (width * 4 + 1));
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const source = (y * width + x) * 4, target = y * (width * 4 + 1) + 1 + x * 4;
      const alpha = pixels[source + 3];
      for (let channel = 0; channel < 3; channel++)
        rows[target + channel] = alpha ? Math.min(255, Math.round(pixels[source + 2 - channel] * 255 / alpha)) : 0;
      rows[target + 3] = alpha;
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 6;
  return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]), pngChunk("IHDR", header),
    pngChunk("IDAT", zlib.deflateSync(rows)), pngChunk("IEND", Buffer.alloc(0))]);
}

module.exports = { createPreparation, createSession, captureToPng, withoutPixels, writeAudit, bindWorkBudget };
