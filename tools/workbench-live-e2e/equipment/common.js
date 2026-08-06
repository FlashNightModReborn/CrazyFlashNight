"use strict";

const fs = require("fs");
const path = require("path");
const zlib = require("zlib");
const SharedEvidence = require("../lib/evidence-artifact");

const API_VERSION = "equipment-v4";
const BUNDLE_SCHEMA = "workbench-live-e2e.equipment.bundle.v4";
const RECEIPT_SCHEMA = "workbench-live-e2e.equipment.receipt.v4";
const TRANSCRIPT_SCHEMA = "workbench-live-e2e.equipment.transcript.v3";
const ARTIFACT_MANIFEST_SCHEMA = "workbench-live-e2e.equipment.artifact-manifest.v3";
const CONTROL_REQUEST_SCHEMA = "workbench-live-e2e.equipment.control-request.v4";
const CONTROL_ACK_SCHEMA = "workbench-live-e2e.equipment.control-ack.v4";
const PROVIDER_RECEIPT_SCHEMA = "workbench-live-e2e.equipment.provider-receipt.v5";
const PROVIDER_CAPTURE_EVENT_SCHEMA =
  "workbench-live-e2e.equipment.provider-capture-event.v1";
const NATIVE_INPUT_EVENT_SCHEMA = "workbench-live-e2e.equipment.native-input-event.v1";
const AUTHORIZATION_SCHEMA = "workbench-live-e2e.equipment.authorization.v2";
const CAPABILITY_SCHEMA = "workbench-live-e2e.equipment.capability.v2";
const AUTHORITY_BINDING_SCHEMA = "workbench-live-e2e.equipment.authority-binding.v2";
// Superseded v1 static-surface helpers are deliberately private.  Current admission
// uses production-closure.js, whose inventory includes Host/AS2/data and loaded bytes.
const PRODUCTION_SURFACE_CLOSURE_SCHEMA =
  "workbench-live-e2e.equipment.production-surface-closure.v1";
const TOKEN_REF_RE = /^sha256_[a-f0-9]{24}$/;
const SHA256_RE = /^[a-f0-9]{64}$/i;
const ID_RE = /^[A-Za-z0-9._~-]{1,160}$/;
const OWNED_BASE_RELATIVE = path.join("tmp", "workbench-live-e2e", "equipment");
const PRODUCTION_SURFACE_FILES = Object.freeze([
  "launcher/web/bootstrap.html",
  "launcher/web/css/bootstrap.css",
  "launcher/web/css/welcome.css",
  "launcher/web/assets/intro.mp4",
  "launcher/web/assets/logos/cf7me-title.png",
  "launcher/web/assets/logos/steam.svg",
  "launcher/web/config/version.js",
  "launcher/web/overlay.html",
  "launcher/web/bootstrap-main.js",
  "launcher/web/css/game-ui-behavior.css",
  "launcher/web/css/overlay.css",
  "launcher/web/css/panels.css",
  "launcher/web/modules/minigames/shared/minigame-shell.css",
  "launcher/web/modules/minigames/lockbox/lockbox.css",
  "launcher/web/modules/minigames/pinalign/pinalign.css",
  "launcher/web/modules/minigames/gobang/gobang.css",
  "launcher/web/css/panels/foundation-top.css",
  "launcher/web/css/workbench/tokens.css",
  "launcher/web/css/panels/foundation-rest.css",
  "launcher/web/css/workbench/core.css",
  "launcher/web/css/workbench/profiles.css",
  "launcher/web/css/panels/features.css",
  "launcher/web/css/workbench/inventory.css",
  "launcher/web/css/workbench/skins.css",
  "launcher/web/css/workbench/entities.css",
  "launcher/web/css/workbench/crafting.css",
  "launcher/web/css/workbench/equipment-inspector.css",
  "launcher/web/css/workbench/skills.css",
  "launcher/web/css/workbench/equipment-tuning.css",
  "launcher/web/css/workbench/components.css",
  "launcher/web/css/workbench/character-build.css",
  "launcher/web/css/workbench/character-build-stats.css",
  "launcher/web/css/workbench/states.css",
  "launcher/web/css/workbench/motion.css",
  "launcher/web/css/hairdresser.css",
  "launcher/web/css/workbench/utilities.css",
  "launcher/web/modules/game-ui-behavior.js",
  "launcher/web/lib/marked.min.js",
  "launcher/web/modules/perf-frame-limiter.js",
  "launcher/web/modules/bridge.js",
  "launcher/web/modules/uidata.js",
  "launcher/web/modules/toast.js",
  "launcher/web/modules/sparkline.js",
  "launcher/web/modules/notch.js",
  "launcher/web/modules/cursor-feedback.js",
  "launcher/web/modules/currency.js",
  "launcher/web/modules/combo.js",
  "launcher/web/modules/lazy-loader.js",
  "launcher/web/modules/panels.js",
  "launcher/web/modules/panel-scale.js",
  "launcher/web/modules/audio.js",
  "launcher/web/modules/factions.js",
  "launcher/web/modules/archive-schema.js",
  "launcher/web/modules/archive-editor.js",
  "launcher/web/modules/diagnostic-log.js",
  "launcher/web/modules/display.js",
  "launcher/web/modules/about.js",
  "launcher/web/modules/repair-card.js",
  "launcher/web/modules/overlay-audio-bindings.js",
  "launcher/web/modules/tooltip.js",
  "launcher/web/modules/asset-timeline.js",
  "launcher/web/modules/icons.js",
  "launcher/web/modules/map-panel-data.js",
  "launcher/web/modules/map-fit-presets.js",
  "launcher/web/modules/map-hud.js",
  "launcher/web/modules/panels-lazy-registry.js",
  "launcher/web/modules/panel-runtime.js",
  "launcher/web/modules/workbench-lifecycle.js",
  "launcher/web/modules/workbench-focus.js",
  "launcher/web/modules/workbench-primitives.js",
  "launcher/web/modules/workbench-profile.js",
  "launcher/web/modules/workbench.js",
  "launcher/web/modules/workbench-components.js",
  "launcher/web/modules/item-filter.js",
  "launcher/web/modules/inventory-runtime.js",
  "launcher/web/modules/inventory-ui.js",
  "launcher/web/modules/inventory-workbench-config.js",
  "launcher/web/modules/inventory-workbench-preparation-menu.js",
  "launcher/web/modules/inventory-workbench-navigation.js",
  "launcher/web/modules/inventory-workbench-header.js",
  "launcher/web/modules/inventory-workbench-quick-transfer.js",
  "launcher/web/modules/inventory-workbench-owned-view.js",
  "launcher/web/modules/inventory-workbench-feature-loader.js",
  "launcher/web/modules/inventory-storage-workbench.js",
  "launcher/web/modules/inventory-workbench.js",
  "launcher/web/modules/dressup-doll-renderer.js",
  "launcher/web/modules/workbench-inspection-viewport.js",
  "launcher/web/modules/equipment-inspector.js",
  "launcher/web/modules/equipment-tuning-runtime.js",
  "launcher/web/modules/equipment-tuning-model.js",
  "launcher/web/modules/equipment-tuning-decision-presenter.js",
  "launcher/web/modules/equipment-tuning-render.js",
  "launcher/web/modules/equipment-tuning-confirmation.js",
  "launcher/web/modules/equipment-tuning-interaction.js",
  "launcher/web/modules/equipment-tuning-write-lifecycle.js",
  "launcher/web/modules/equipment-tuning-loadout-lifecycle.js",
  "launcher/web/modules/equipment-tuning-source-marker.js",
  "launcher/web/modules/equipment-tuning-view.js",
  "launcher/web/modules/inventory-tuning-scope.js",
  "scripts/asLoader.swf",
]);

function fail(code, phase, message, details) {
  SharedEvidence.contractFail(code, phase, message, details);
}

function deepClone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
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
  let paletteEntries = null;
  let maximumPaletteIndex = null;
  if (colorType === 3) {
    paletteEntries = plte.length / 3;
    maximumPaletteIndex = 0;
    const mask = (1 << bitDepth) - 1;
    for (let row = 0; row < height; row += 1) {
      const rowOffset = row * rowBytes;
      for (let column = 0; column < width; column += 1) {
        const bitOffset = column * bitDepth;
        const packed = pixels[rowOffset + Math.floor(bitOffset / 8)];
        const shift = 8 - bitDepth - (bitOffset % 8);
        const paletteIndex = (packed >>> shift) & mask;
        maximumPaletteIndex = Math.max(maximumPaletteIndex, paletteIndex);
        if (paletteIndex >= paletteEntries) {
          fail("control_capture_media_invalid", "control_capture",
            "PNG indexed pixel references a palette entry that does not exist", {
              row, column, paletteIndex, paletteEntries,
            });
        }
      }
    }
  }
  return { mediaType: "image/png", width, height, bytes: bytes.length,
    pixelBytes: pixels.length, pixelSha256: SharedEvidence.sha256Bytes(pixels),
    paletteEntries, maximumPaletteIndex };
}

function createAuthorityReference(value) {
  const text = typeof value === "string" ? value
    : value == null ? "" : JSON.stringify(value);
  return "sha256_" + SharedEvidence.sha256Text(text).slice(0, 24);
}

function tokenRef(value) {
  const text = String(value == null ? "" : value);
  return TOKEN_REF_RE.test(text) ? text : createAuthorityReference(text);
}

function redactSourceKey(value) {
  return createAuthorityReference(value);
}

function diagnosticAuthoritySourceKey(source) {
  if (!SharedEvidence.isPlainObject(source)) {
    fail("authority_binding_source_invalid", "capture",
      "authority binding requires one exact tuning source");
  }
  if (source.sourceKind === "inventory") {
    if (source.containerId !== "背包" || !Number.isInteger(source.slot) || source.slot < 0
        || source.slot > 49 || typeof source.expectedLease !== "string"
        || !/^[A-Za-z0-9._-]{1,128}$/.test(source.expectedLease)) {
      fail("authority_binding_source_invalid", "capture",
        "inventory authority source is malformed");
    }
    return "inventory:" + source.containerId + ":" + source.slot + ":" + source.expectedLease;
  }
  if (source.sourceKind === "loadout") {
    if (!Number.isInteger(source.sessionGeneration) || source.sessionGeneration <= 0
        || typeof source.slotKey !== "string" || !source.slotKey
        || !Number.isInteger(source.expectedLoadoutRevision)
        || source.expectedLoadoutRevision < 0) {
      fail("authority_binding_source_invalid", "capture",
        "loadout authority source is malformed");
    }
    return "loadout:" + source.sessionGeneration + ":" + source.slotKey + ":"
      + source.expectedLoadoutRevision;
  }
  fail("authority_binding_source_invalid", "capture", "unknown tuning source kind");
}

function previewIntentKey(operation, payload) {
  const body = SharedEvidence.isPlainObject(payload) ? payload : {};
  if (operation === "enhance") return "enhance|" + Math.floor(Number(body.targetLevel || 0));
  if (operation === "convert") {
    const target = SharedEvidence.isPlainObject(body.target) ? body.target : {};
    return "convert|" + String(target.containerId || "") + "|" + Number(target.slot) + "|"
      + String(target.expectedLease || "");
  }
  return String(operation || "") + "|" + String(body.candidateKey || "") + "|"
    + String(body.replaceCandidateKey || "");
}

function deriveRequestAuthorityBinding(message) {
  if (!SharedEvidence.isPlainObject(message) || message.type !== "panel"
      || message.panel !== "workbench" || message.domain !== "equipment_tuning"
      || !["snapshot", "preview"].includes(message.cmd)
      || !SharedEvidence.isPlainObject(message.payload)
      || !SharedEvidence.isPlainObject(message.payload.source)) return null;
  const sourceKeyRef = createAuthorityReference(
    diagnosticAuthoritySourceKey(message.payload.source));
  if (message.cmd === "snapshot") {
    return {
      schema: AUTHORITY_BINDING_SCHEMA,
      basis: "request_source",
      sourceKeyRef,
    };
  }
  const operation = String(message.payload.operation || "");
  const candidateKey = String(message.payload.candidateKey || "");
  return {
    schema: AUTHORITY_BINDING_SCHEMA,
    basis: "request_payload",
    operation,
    candidateKey,
    sourceKeyRef,
    intentKeyRef: createAuthorityReference(previewIntentKey(operation, message.payload)),
  };
}

function productionSurfaceEntry(root, relativePath) {
  const absolutePath = path.resolve(root, relativePath.replace(/\//g, path.sep));
  const rootPath = path.resolve(root);
  const relative = path.relative(rootPath, absolutePath);
  if (!relative || relative.startsWith("..") || path.isAbsolute(relative)) {
    fail("production_surface_path_invalid", "production_surface",
      "production surface path escaped the repository root", { relativePath });
  }
  let stat;
  try { stat = fs.lstatSync(absolutePath); }
  catch (error) {
    fail("production_surface_file_missing", "production_surface",
      "required production Web/SWF file is missing", { relativePath, error: error.message });
  }
  if (!stat.isFile() || stat.isSymbolicLink()) {
    fail("production_surface_file_invalid", "production_surface",
      "required production Web/SWF path is not one exact regular file", { relativePath });
  }
  const bytes = fs.readFileSync(absolutePath);
  return {
    relativePath: relativePath.replace(/\\/g, "/"),
    sha256: SharedEvidence.sha256Bytes(bytes),
    bytes: bytes.length,
  };
}

function buildProductionSurfaceClosure(root) {
  const files = PRODUCTION_SURFACE_FILES.map((relativePath) =>
    productionSurfaceEntry(root, relativePath));
  const payload = {
    schema: PRODUCTION_SURFACE_CLOSURE_SCHEMA,
    files,
  };
  return Object.assign({}, payload, {
    closureSha256: SharedEvidence.sha256Text(SharedEvidence.canonicalJson(payload)),
  });
}

function verifyProductionSurfaceClosure(root, closure, options) {
  const settings = options || {};
  if (!SharedEvidence.isPlainObject(closure)
      || closure.schema !== PRODUCTION_SURFACE_CLOSURE_SCHEMA
      || !Array.isArray(closure.files)
      || closure.files.length !== PRODUCTION_SURFACE_FILES.length
      || !SHA256_RE.test(String(closure.closureSha256 || ""))) {
    fail("production_surface_closure_invalid", "production_surface",
      "production Web/SWF byte closure is missing or malformed");
  }
  const expectedPaths = PRODUCTION_SURFACE_FILES.slice();
  const actualPaths = closure.files.map((entry) => entry && entry.relativePath);
  if (SharedEvidence.canonicalJson(actualPaths)
      !== SharedEvidence.canonicalJson(expectedPaths)
      || closure.files.some((entry) => !SharedEvidence.isPlainObject(entry)
        || !SHA256_RE.test(String(entry.sha256 || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 1)) {
    fail("production_surface_closure_invalid", "production_surface",
      "production surface inventory is not the frozen exact file set");
  }
  const payload = { schema: closure.schema, files: closure.files };
  if (SharedEvidence.sha256Text(SharedEvidence.canonicalJson(payload))
      !== closure.closureSha256) {
    fail("production_surface_closure_invalid", "production_surface",
      "production surface aggregate digest does not match its entries");
  }
  if (settings.skipFileClosure !== true) {
    const current = buildProductionSurfaceClosure(root);
    if (SharedEvidence.canonicalJson(current) !== SharedEvidence.canonicalJson(closure)) {
      fail("production_surface_tree_drift", "production_surface",
        "current-tree Web/SWF bytes differ from the launch-bound closure");
    }
  }
  return closure;
}

function deriveDiagnosticAuthorityBinding(message) {
  if (!SharedEvidence.isPlainObject(message) || message.type !== "debug"
      || message.scope !== "equipment_tuning"
      || !/^(?:preview|commit)_issued$/.test(String(message.event || ""))) return null;
  if (typeof message.sourceKey !== "string" || !message.sourceKey
      || typeof message.intentKey !== "string" || !message.intentKey) {
    fail("diagnostic_authority_binding_invalid", "capture",
      "issued tuning diagnostic lacks exact raw authority keys", { event: message.event });
  }
  return {
    schema: AUTHORITY_BINDING_SCHEMA,
    basis: "web_diagnostic",
    event: message.event,
    webCallId: String(message.webCallId || ""),
    operation: String(message.operation || ""),
    candidateKey: String(message.candidateKey || ""),
    sourceKeyRef: createAuthorityReference(message.sourceKey),
    intentKeyRef: createAuthorityReference(message.intentKey),
  };
}

function authorityKey(key) {
  return /(?:^|_)(?:expected)?(?:tuning)?token$/i.test(key)
    || /^(?:tuningToken|expectedTuningToken|transactionId|expectedLease|slotLease)$/i.test(key);
}

function redactAuthority(value, keyHint) {
  if (value != null && authorityKey(String(keyHint || ""))) {
    return createAuthorityReference(value);
  }
  if (value != null && keyHint === "sourceKey") return redactSourceKey(value);
  if (value != null && keyHint === "intentKey") return createAuthorityReference(value);
  if (Array.isArray(value)) return value.map((entry) => redactAuthority(entry, keyHint));
  if (SharedEvidence.isPlainObject(value)) {
    const output = {};
    Object.keys(value).forEach((key) => {
      if (key === "sourceKey" || key === "intentKey") {
        const referenceKey = key + "Ref";
        const reference = key === "sourceKey"
          ? redactSourceKey(value[key]) : createAuthorityReference(value[key]);
        if (Object.prototype.hasOwnProperty.call(value, referenceKey)
            && value[referenceKey] !== reference) {
          fail("authority_reference_collision", "redaction",
            "raw authority key conflicts with an existing digest reference", { key, referenceKey });
        }
        output[referenceKey] = reference;
        return;
      }
      output[key] = redactAuthority(value[key], key);
    });
    return output;
  }
  return value;
}

function assertNoRawAuthority(value, phase) {
  function walk(current, keyHint, locator) {
    if (current != null && authorityKey(String(keyHint || ""))
        && (typeof current !== "string" || !TOKEN_REF_RE.test(current))) {
      fail("raw_authority_token_present", phase || "redaction",
        "authority credential was persisted without a digest reference", { locator });
    }
    if (keyHint === "sourceKey" || keyHint === "intentKey") {
      fail("raw_authority_key_present", phase || "redaction",
        "raw sourceKey/intentKey field was persisted instead of a named digest reference", { locator });
    }
    if ((keyHint === "sourceKeyRef" || keyHint === "intentKeyRef")
        && (typeof current !== "string" || !TOKEN_REF_RE.test(current))) {
      fail("authority_reference_invalid", phase || "redaction",
        "authority reference is not a SHA-256 digest reference", { locator });
    }
    if (Array.isArray(current)) {
      current.forEach((entry, index) => walk(entry, keyHint, locator + "[" + index + "]"));
    } else if (SharedEvidence.isPlainObject(current)) {
      Object.keys(current).forEach((key) => walk(current[key], key, locator + "." + key));
    }
  }
  walk(value, "", "$");
  return true;
}

function atomicWriteJson(filePath, value) {
  const absolute = path.resolve(filePath);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  const temporary = absolute + ".tmp-" + process.pid + "-" + Date.now();
  const text = JSON.stringify(value, null, 2) + "\n";
  fs.writeFileSync(temporary, text, { encoding: "utf8", flag: "wx", mode: 0o600 });
  fs.renameSync(temporary, absolute);
  return {
    path: absolute,
    bytes: Buffer.byteLength(text, "utf8"),
    sha256: SharedEvidence.sha256Text(text),
  };
}

function readJsonFile(filePath, phase, maximumBytes) {
  const file = SharedEvidence.readExactRegularFile(path.resolve(filePath), {
    phase: phase || "artifact",
    maximumBytes: maximumBytes || 128 * 1024 * 1024,
  });
  let value;
  try { value = JSON.parse(file.bytes.toString("utf8")); }
  catch (error) { fail("artifact_json_invalid", phase || "artifact", error.message, { filePath }); }
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
  const root = path.resolve(directory);
  const output = [];
  function visit(current) {
    const stat = fs.lstatSync(current, { bigint: true });
    if (stat.isSymbolicLink() || stat.isSymbolicLink && stat.isSymbolicLink()) {
      fail("artifact_reparse_forbidden", "artifact", "artifact tree contains a symlink", { current });
    }
    if (stat.isDirectory()) {
      fs.readdirSync(current, { withFileTypes: true }).forEach((entry) => {
        visit(path.join(current, entry.name));
      });
      return;
    }
    if (!stat.isFile()) fail("artifact_not_regular", "artifact", "artifact is not a regular file", { current });
    output.push(current);
  }
  visit(root);
  return output.sort((left, right) => left.localeCompare(right));
}

function buildArtifactManifest(options) {
  const root = path.resolve(options.root);
  const runDir = SharedEvidence.assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || OWNED_BASE_RELATIVE, "artifact_manifest");
  const manifestPath = path.join(runDir, "artifact-manifest.json");
  const receiptPath = path.join(runDir, "verified-receipt.json");
  const roleByPath = options.roleByPath || {};
  const entries = walkRegularFiles(runDir).filter((filePath) =>
    filePath.toLowerCase() !== manifestPath.toLowerCase()
      && filePath.toLowerCase() !== receiptPath.toLowerCase()).map((filePath) => {
    const file = SharedEvidence.readExactRegularFile(filePath, {
      phase: "artifact_manifest", maximumBytes: 128 * 1024 * 1024,
    });
    const relativePath = relativeOwnedPath(runDir, filePath);
    const role = String(roleByPath[relativePath] || "raw_evidence");
    if (!/^[A-Za-z0-9._~-]{1,80}$/.test(role)) {
      fail("artifact_role_invalid", "artifact_manifest", "artifact role is malformed", { relativePath, role });
    }
    return { relativePath, role, bytes: file.length, sha256: file.sha256 };
  });
  const manifest = {
    schema: ARTIFACT_MANIFEST_SCHEMA,
    apiVersion: API_VERSION,
    runId: String(options.runId || ""),
    createdAt: new Date().toISOString(),
    entries,
  };
  manifest.manifestSha256 = SharedEvidence.sha256Text(SharedEvidence.canonicalJson(manifest));
  return manifest;
}

function verifyArtifactManifest(options) {
  const root = path.resolve(options.root);
  const runDir = SharedEvidence.assertOwnedRunDirectory(root, options.runDir,
    options.ownedBaseRelative || OWNED_BASE_RELATIVE, "artifact_manifest");
  const manifest = options.manifest;
  if (!SharedEvidence.isPlainObject(manifest) || manifest.schema !== ARTIFACT_MANIFEST_SCHEMA
      || manifest.apiVersion !== API_VERSION || !ID_RE.test(String(manifest.runId || ""))
      || !Number.isFinite(Date.parse(manifest.createdAt)) || !Array.isArray(manifest.entries)
      || !SHA256_RE.test(String(manifest.manifestSha256 || ""))) {
    fail("artifact_manifest_invalid", "artifact_manifest", "artifact manifest envelope is malformed");
  }
  const payload = deepClone(manifest);
  delete payload.manifestSha256;
  if (SharedEvidence.sha256Text(SharedEvidence.canonicalJson(payload)) !== manifest.manifestSha256) {
    fail("artifact_manifest_digest_invalid", "artifact_manifest", "artifact manifest digest drifted");
  }
  const seen = new Set();
  let previous = "";
  manifest.entries.forEach((entry) => {
    if (!SharedEvidence.isPlainObject(entry) || typeof entry.relativePath !== "string"
        || !/^[A-Za-z0-9._~-]{1,80}$/.test(String(entry.role || ""))
        || !Number.isInteger(entry.bytes) || entry.bytes < 0
        || !SHA256_RE.test(String(entry.sha256 || ""))
        || entry.relativePath <= previous || seen.has(entry.relativePath.toLowerCase())) {
      fail("artifact_manifest_entry_invalid", "artifact_manifest", "artifact entry is malformed or unordered", { entry });
    }
    previous = entry.relativePath;
    seen.add(entry.relativePath.toLowerCase());
    const absolute = path.resolve(runDir, entry.relativePath.replace(/\//g, path.sep));
    if (relativeOwnedPath(runDir, absolute) !== entry.relativePath) {
      fail("artifact_manifest_path_invalid", "artifact_manifest", "artifact path is not canonical", { entry });
    }
    const file = SharedEvidence.readExactRegularFile(absolute, {
      phase: "artifact_manifest", maximumBytes: 128 * 1024 * 1024,
    });
    if (file.length !== entry.bytes || file.sha256.toLowerCase() !== entry.sha256.toLowerCase()) {
      fail("artifact_manifest_file_mismatch", "artifact_manifest", "artifact bytes/hash drifted", { entry });
    }
  });
  const manifestPath = path.join(runDir, "artifact-manifest.json").toLowerCase();
  const receiptPath = path.join(runDir, "verified-receipt.json").toLowerCase();
  const actual = walkRegularFiles(runDir).filter((entry) => {
    const lower = entry.toLowerCase();
    return lower !== manifestPath && lower !== receiptPath;
  }).map((entry) => relativeOwnedPath(runDir, entry));
  if (SharedEvidence.canonicalJson(actual) !== SharedEvidence.canonicalJson(
    manifest.entries.map((entry) => entry.relativePath))) {
    fail("artifact_manifest_set_mismatch", "artifact_manifest", "owned artifact set is not exact", { actual });
  }
  return new Map(manifest.entries.map((entry) => [entry.relativePath, Object.assign({}, entry, {
    absolutePath: path.resolve(runDir, entry.relativePath.replace(/\//g, path.sep)),
  })]));
}

function nextRecord(previousHash, sequence, raw) {
  const record = Object.assign({}, raw, { sequence, previousHash });
  record.eventHash = SharedEvidence.sha256Text(previousHash + "\n" + SharedEvidence.canonicalJson(record));
  return record;
}

function verifyRecordChain(transcript) {
  if (!SharedEvidence.isPlainObject(transcript) || transcript.schema !== TRANSCRIPT_SCHEMA
      || !Array.isArray(transcript.events) || !ID_RE.test(String(transcript.observerId || ""))) {
    fail("transcript_invalid", "transcript", "passive transcript envelope is malformed");
  }
  let previousHash = "0".repeat(64);
  transcript.events.forEach((event, index) => {
    if (!SharedEvidence.isPlainObject(event) || event.sequence !== index + 1
        || event.previousHash !== previousHash || !SHA256_RE.test(String(event.eventHash || ""))) {
      fail("transcript_chain_invalid", "transcript", "transcript sequence/hash chain is malformed", { index });
    }
    const payload = deepClone(event);
    delete payload.eventHash;
    const expected = SharedEvidence.sha256Text(previousHash + "\n" + SharedEvidence.canonicalJson(payload));
    if (expected !== event.eventHash) {
      fail("transcript_chain_invalid", "transcript", "transcript event hash drifted", { index });
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
  API_VERSION,
  ARTIFACT_MANIFEST_SCHEMA,
  AUTHORITY_BINDING_SCHEMA,
  AUTHORIZATION_SCHEMA,
  BUNDLE_SCHEMA,
  CAPABILITY_SCHEMA,
  CONTROL_ACK_SCHEMA,
  CONTROL_REQUEST_SCHEMA,
  NATIVE_INPUT_EVENT_SCHEMA,
  PROVIDER_CAPTURE_EVENT_SCHEMA,
  PROVIDER_RECEIPT_SCHEMA,
  ID_RE,
  OWNED_BASE_RELATIVE,
  RECEIPT_SCHEMA,
  SHA256_RE,
  TOKEN_REF_RE,
  TRANSCRIPT_SCHEMA,
  assertNoRawAuthority,
  atomicWriteJson,
  buildArtifactManifest,
  deepClone,
  decodePng,
  deriveDiagnosticAuthorityBinding,
  deriveRequestAuthorityBinding,
  diagnosticAuthoritySourceKey,
  fail,
  nextRecord,
  readJsonFile,
  redactAuthority,
  redactSourceKey,
  relativeOwnedPath,
  tokenRef,
  previewIntentKey,
  verifyArtifactManifest,
  verifyRecordChain,
  walkRegularFiles,
};
