"use strict";

const fs = require("fs");
const path = require("path");
const { canonicalJson, sha256Bytes, sha256Text } = require("./evidence-artifact");

const INVENTORY_SCHEMA = "workbench-live-e2e.browser-resource-inventory.v1";
const LEDGER_SCHEMA = "workbench-live-e2e.browser-served-resource-ledger.v1";
const RECEIPT_SCHEMA = "workbench-live-e2e.browser-resource-closure-receipt.v1";

function fail(code, details) {
  const error = new Error(code);
  error.code = code;
  error.details = details || null;
  throw error;
}

function compareText(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function canonicalRelativePath(value) {
  const relative = String(value || "");
  if (!relative || relative.length > 512 || relative.includes("\\")
      || path.posix.isAbsolute(relative)
      || relative.split("/").some((part) => !part || part === "." || part === "..")) {
    fail("browser_resource_path_invalid", { relativePath:relative });
  }
  return relative;
}

function pathInside(root, target) {
  const relative = path.relative(root, target);
  return relative !== "" && !relative.startsWith(".." + path.sep)
    && relative !== ".." && !path.isAbsolute(relative);
}

function samePath(left, right) {
  const a = path.resolve(left);
  const b = path.resolve(right);
  return process.platform === "win32" ? a.toLowerCase() === b.toLowerCase() : a === b;
}

function realpath(value) {
  return fs.realpathSync.native ? fs.realpathSync.native(value) : fs.realpathSync(value);
}

function createRootBoundary(root) {
  const canonicalRoot = path.resolve(root || "");
  let stat;
  try { stat = fs.lstatSync(canonicalRoot); }
  catch (_) { fail("browser_resource_root_invalid", { root:canonicalRoot }); }
  if (!stat.isDirectory() || stat.isSymbolicLink()) {
    fail("browser_resource_root_invalid", { root:canonicalRoot });
  }
  return { canonicalRoot, realRoot:realpath(canonicalRoot) };
}

function resolveWithinRoot(boundary, targetValue, options) {
  const settings = options || {};
  const target = path.resolve(targetValue);
  if (!pathInside(boundary.canonicalRoot, target)) {
    fail("browser_resource_path_escape", { filePath:target });
  }
  const relativeNative = path.relative(boundary.canonicalRoot, target);
  const parts = relativeNative.split(path.sep);
  let current = boundary.canonicalRoot;
  for (let index = 0; index < parts.length; index += 1) {
    current = path.join(current, parts[index]);
    let stat;
    try { stat = fs.lstatSync(current); }
    catch (error) {
      if (settings.allowMissingFinal === true && index === parts.length - 1
          && error && error.code === "ENOENT") {
        return { filePath:target,
          relativePath:canonicalRelativePath(relativeNative.replace(/\\/g, "/")), exists:false };
      }
      fail("browser_resource_path_missing", { filePath:current });
    }
    if (stat.isSymbolicLink()) {
      fail("browser_resource_link_component", { filePath:current });
    }
    if (index < parts.length - 1 && !stat.isDirectory()) {
      fail("browser_resource_path_invalid", { filePath:current });
    }
    const currentReal = realpath(current);
    if (!samePath(boundary.realRoot, currentReal) && !pathInside(boundary.realRoot, currentReal)) {
      fail("browser_resource_realpath_escape", { filePath:current, realPath:currentReal });
    }
    if (index === parts.length - 1 && settings.requireFile === true && !stat.isFile()) {
      fail("browser_resource_not_regular_file", { filePath:current });
    }
  }
  return { filePath:target,
    relativePath:canonicalRelativePath(relativeNative.replace(/\\/g, "/")), exists:true };
}

function resolveResource(root, relativePath) {
  const boundary = createRootBoundary(root);
  const relative = canonicalRelativePath(relativePath);
  const target = path.resolve(boundary.canonicalRoot, relative.replace(/\//g, path.sep));
  const resolved = resolveWithinRoot(boundary, target, { requireFile:true });
  const bytes = fs.readFileSync(resolved.filePath);
  return { filePath:resolved.filePath, relativePath:relative, bytes:bytes.length,
    sha256:sha256Bytes(bytes) };
}

function exactInventory(root, value) {
  if (!value || value.schema !== INVENTORY_SCHEMA || !Array.isArray(value.files)
      || value.files.length < 1 || value.files.length > 2048
      || value.optionalFiles != null && !Array.isArray(value.optionalFiles)) {
    fail("browser_resource_inventory_invalid");
  }
  const files = value.files.map(canonicalRelativePath);
  const optionalFiles = (value.optionalFiles || []).map(canonicalRelativePath);
  const sorted = files.slice().sort(compareText);
  const optionalSorted = optionalFiles.slice().sort(compareText);
  if (new Set(files).size !== files.length || canonicalJson(files) !== canonicalJson(sorted)
      || new Set(optionalFiles).size !== optionalFiles.length
      || canonicalJson(optionalFiles) !== canonicalJson(optionalSorted)
      || optionalFiles.some((relative) => files.includes(relative))
      || files.length + optionalFiles.length > 4096) {
    fail("browser_resource_inventory_invalid", { reason:"not_exact_sorted_unique" });
  }
  const requiredResources = files.map((relative) => resolveResource(root, relative));
  const optionalResources = optionalFiles.map((relative) => resolveResource(root, relative));
  const resources = requiredResources.concat(optionalResources)
    .sort((left, right) => compareText(left.relativePath, right.relativePath));
  const binding = { schema:INVENTORY_SCHEMA, files:requiredResources.map((entry) => ({
    relativePath:entry.relativePath, bytes:entry.bytes, sha256:entry.sha256,
  })), optionalFiles:optionalResources.map((entry) => ({
    relativePath:entry.relativePath, bytes:entry.bytes, sha256:entry.sha256,
  })) };
  return { schema:INVENTORY_SCHEMA, root:path.resolve(root), files, optionalFiles,
    requiredResources, optionalResources, resources,
    inventorySha256:sha256Text(canonicalJson(binding)) };
}

function loadResourceInventory(options) {
  const settings = options || {};
  const source = typeof settings.inventoryPath === "string"
    ? JSON.parse(fs.readFileSync(settings.inventoryPath, "utf8")) : settings.inventory;
  return exactInventory(settings.root, source);
}

function resourceManifestEntries(inventory, role) {
  if (!inventory || !Array.isArray(inventory.resources)) {
    fail("browser_resource_inventory_invalid");
  }
  return inventory.resources.map((entry) => ({ filePath:entry.filePath,
    role:role || "browser_served_resource", preexisting:false, loadable:false }));
}

function canonicalRequestPath(value) {
  const raw = String(value || "");
  if (!raw.startsWith("/") || raw.startsWith("//")) {
    fail("browser_resource_request_path_invalid", { requestPath:value });
  }
  let parsed;
  try { parsed = new URL(raw, "http://127.0.0.1"); }
  catch (_) { fail("browser_resource_request_path_invalid", { requestPath:value }); }
  if (!parsed.pathname || parsed.hash || parsed.username || parsed.password
      || parsed.origin !== "http://127.0.0.1") {
    fail("browser_resource_request_path_invalid", { requestPath:value });
  }
  return parsed.pathname + parsed.search;
}

function requestRelativePath(value) {
  const requestPath = canonicalRequestPath(value);
  const parsed = new URL(requestPath, "http://127.0.0.1");
  let decoded;
  try { decoded = decodeURIComponent(parsed.pathname); }
  catch (_) { fail("browser_resource_request_path_invalid", { requestPath:value }); }
  if (!decoded.startsWith("/") || decoded.startsWith("//")) {
    fail("browser_resource_request_path_invalid", { requestPath:value });
  }
  return canonicalRelativePath(decoded.slice(1));
}

function createServedResourceLedger(options) {
  const boundary = createRootBoundary(options && options.root || "");
  const occurrences = [];
  let sealed = false;

  function begin(requestPath, filePath) {
    if (sealed) fail("browser_resource_ledger_sealed");
    const resolved = resolveWithinRoot(boundary, filePath, { allowMissingFinal:true });
    const relativePath = resolved.relativePath;
    const expectedRelativePath = requestRelativePath(requestPath);
    if (relativePath !== expectedRelativePath) {
      fail("browser_resource_route_mismatch", { requestPath:canonicalRequestPath(requestPath),
        expectedRelativePath, relativePath });
    }
    const record = { sequence:occurrences.length + 1,
      requestPath:canonicalRequestPath(requestPath), relativePath, status:"pending" };
    occurrences.push(record);
    let finished = false;
    return {
      success(data, mimeType) {
        if (finished || sealed) fail("browser_resource_occurrence_reused", { sequence:record.sequence });
        const bytes = Buffer.isBuffer(data) ? data : Buffer.from(data);
        const mime = String(mimeType || "");
        if (!mime || mime.length > 160 || /[\r\n]/.test(mime)) {
          fail("browser_resource_mime_invalid", { sequence:record.sequence, mimeType:mime });
        }
        finished = true;
        Object.assign(record, { status:"served", mimeType:mime,
          bytes:bytes.length, sha256:sha256Bytes(bytes) });
      },
      failure(code) {
        if (finished || sealed) fail("browser_resource_occurrence_reused", { sequence:record.sequence });
        finished = true;
        Object.assign(record, { status:"failed", failureCode:String(code || "read_failed") });
      },
    };
  }

  function snapshot() {
    if (sealed) fail("browser_resource_ledger_sealed");
    sealed = true;
    const incomplete = occurrences.filter((entry) => entry.status === "pending");
    if (incomplete.length) {
      fail("browser_resource_occurrence_incomplete", { incomplete });
    }
    const unique = new Map();
    occurrences.filter((entry) => entry.status === "served").forEach((entry) => {
      const facts = { relativePath:entry.relativePath, mimeType:entry.mimeType,
        bytes:entry.bytes, sha256:entry.sha256 };
      if (unique.has(entry.relativePath)
          && canonicalJson(unique.get(entry.relativePath)) !== canonicalJson(facts)) {
        fail("browser_resource_occurrence_drift", { relativePath:entry.relativePath });
      }
      unique.set(entry.relativePath, facts);
    });
    const resources = Array.from(unique.values())
      .sort((left, right) => compareText(left.relativePath, right.relativePath));
    const artifact = { schema:LEDGER_SCHEMA, occurrenceCount:occurrences.length,
      failureCount:occurrences.filter((entry) => entry.status === "failed").length,
      resourceCount:resources.length, occurrences, resources };
    artifact.evidenceSha256 = sha256Text(canonicalJson(artifact));
    return JSON.parse(JSON.stringify(artifact));
  }

  return { begin, snapshot };
}

function verifyServedResourceClosure(options) {
  const settings = options || {};
  const inventorySource = settings.inventory && Array.isArray(settings.inventory.files)
    ? { schema:INVENTORY_SCHEMA, files:settings.inventory.files,
      optionalFiles:settings.inventory.optionalFiles || [] }
    : settings.inventory;
  const inventory = exactInventory(settings.root
    || settings.inventory && settings.inventory.root, inventorySource);
  const ledger = JSON.parse(JSON.stringify(settings.ledger || null));
  if (!ledger || ledger.schema !== LEDGER_SCHEMA || !Array.isArray(ledger.occurrences)
      || !Array.isArray(ledger.resources)) {
    fail("browser_resource_ledger_invalid");
  }
  const claimedDigest = ledger.evidenceSha256;
  delete ledger.evidenceSha256;
  if (!/^[a-f0-9]{64}$/.test(String(claimedDigest || ""))
      || sha256Text(canonicalJson(ledger)) !== claimedDigest) {
    fail("browser_resource_ledger_digest_invalid");
  }
  if (ledger.occurrenceCount !== ledger.occurrences.length
      || ledger.resourceCount !== ledger.resources.length
      || ledger.failureCount !== ledger.occurrences.filter((entry) => entry.status === "failed").length
      || ledger.occurrenceCount < ledger.resourceCount) {
    fail("browser_resource_ledger_count_invalid");
  }
  const derivedByPath = new Map();
  ledger.occurrences.forEach((entry, index) => {
    if (!entry || entry.sequence !== index + 1 || !["served", "failed"].includes(entry.status)
        || canonicalRequestPath(entry.requestPath) !== entry.requestPath
        || canonicalRelativePath(entry.relativePath) !== entry.relativePath) {
      fail("browser_resource_occurrence_invalid", { index });
    }
    const expectedRelativePath = requestRelativePath(entry.requestPath);
    if (entry.relativePath !== expectedRelativePath) {
      fail("browser_resource_route_mismatch", { index, requestPath:entry.requestPath,
        expectedRelativePath, relativePath:entry.relativePath });
    }
    const expectedKeys = entry.status === "served"
      ? ["bytes", "mimeType", "relativePath", "requestPath", "sequence", "sha256", "status"]
      : ["failureCode", "relativePath", "requestPath", "sequence", "status"];
    if (canonicalJson(Object.keys(entry).sort(compareText)) !== canonicalJson(expectedKeys)) {
      fail("browser_resource_occurrence_invalid", { index, reason:"field_set" });
    }
    if (entry.status === "served") {
      if (!Number.isSafeInteger(entry.bytes) || entry.bytes < 0
          || !/^[a-f0-9]{64}$/.test(String(entry.sha256 || ""))
          || typeof entry.mimeType !== "string" || !entry.mimeType || entry.mimeType.length > 160
          || /[\r\n]/.test(entry.mimeType)) {
        fail("browser_resource_occurrence_invalid", { index, reason:"served_facts" });
      }
      const facts = { relativePath:entry.relativePath, mimeType:entry.mimeType,
        bytes:entry.bytes, sha256:entry.sha256 };
      if (derivedByPath.has(entry.relativePath)
          && canonicalJson(derivedByPath.get(entry.relativePath)) !== canonicalJson(facts)) {
        fail("browser_resource_occurrence_drift", { relativePath:entry.relativePath });
      }
      derivedByPath.set(entry.relativePath, facts);
    } else if (typeof entry.failureCode !== "string" || !entry.failureCode
        || entry.failureCode.length > 160 || /[\r\n]/.test(entry.failureCode)) {
      fail("browser_resource_occurrence_invalid", { index, reason:"failure_facts" });
    }
  });
  const derivedResources = Array.from(derivedByPath.values())
    .sort((left, right) => compareText(left.relativePath, right.relativePath));
  if (canonicalJson(ledger.resources) !== canonicalJson(derivedResources)) {
    fail("browser_resource_ledger_resource_projection_invalid", {
      expected:derivedResources, actual:ledger.resources });
  }
  const allowedFailures = Array.isArray(settings.allowedFailures) ? settings.allowedFailures : [];
  const expectedFailures = allowedFailures.map((entry) => ({
    requestPath:canonicalRequestPath(entry && entry.requestPath),
    relativePath:canonicalRelativePath(entry && entry.relativePath),
    failureCode:String(entry && entry.failureCode || ""),
  }));
  expectedFailures.forEach((entry, index) => {
    const expectedRelativePath = requestRelativePath(entry.requestPath);
    if (entry.relativePath !== expectedRelativePath || !entry.failureCode
        || entry.failureCode.length > 160 || /[\r\n]/.test(entry.failureCode)) {
      fail("browser_resource_failure_set_invalid", { index, expectedRelativePath, entry });
    }
  });
  const actualFailures = ledger.occurrences.filter((entry) => entry.status === "failed")
    .map((entry) => ({ requestPath:entry.requestPath, relativePath:entry.relativePath,
      failureCode:entry.failureCode }));
  if (canonicalJson(actualFailures) !== canonicalJson(expectedFailures)) {
    fail("browser_resource_failure_set_mismatch", { expectedFailures, actualFailures });
  }
  const required = inventory.requiredResources.map((entry) => ({ relativePath:entry.relativePath,
    bytes:entry.bytes, sha256:entry.sha256 }));
  const allowed = inventory.resources.map((entry) => ({ relativePath:entry.relativePath,
    bytes:entry.bytes, sha256:entry.sha256 }));
  const actual = ledger.resources.map((entry) => ({ relativePath:entry.relativePath,
    bytes:entry.bytes, sha256:entry.sha256 }));
  const actualByPath = new Map(actual.map((entry) => [entry.relativePath, entry]));
  const allowedByPath = new Map(allowed.map((entry) => [entry.relativePath, entry]));
  const missing = required.filter((entry) => !actualByPath.has(entry.relativePath));
  const unexpected = actual.filter((entry) => !allowedByPath.has(entry.relativePath));
  const drifted = actual.filter((entry) => allowedByPath.has(entry.relativePath)
    && canonicalJson(entry) !== canonicalJson(allowedByPath.get(entry.relativePath)));
  if (missing.length || unexpected.length || drifted.length) {
    fail("browser_resource_exact_set_mismatch", { missing, unexpected, drifted });
  }
  const byPath = new Map(ledger.resources.map((entry) => [entry.relativePath, entry]));
  ledger.occurrences.filter((entry) => entry.status === "served").forEach((entry) => {
    const resource = byPath.get(entry.relativePath);
    if (!resource || entry.bytes !== resource.bytes || entry.sha256 !== resource.sha256
        || entry.mimeType !== resource.mimeType) {
      fail("browser_resource_occurrence_invalid", { sequence:entry.sequence });
    }
  });
  const receipt = { schema:RECEIPT_SCHEMA, inventorySha256:inventory.inventorySha256,
    resourceCount:ledger.resourceCount, requiredResourceCount:required.length,
    allowedResourceCount:allowed.length, occurrenceCount:ledger.occurrenceCount,
    failureCount:ledger.failureCount,
    resourcesSha256:sha256Text(canonicalJson(ledger.resources)),
    occurrencesSha256:sha256Text(canonicalJson(ledger.occurrences)),
    failuresSha256:sha256Text(canonicalJson(actualFailures)) };
  receipt.evidenceSha256 = sha256Text(canonicalJson(receipt));
  return receipt;
}

function browserExecutableReceipt(options) {
  const expectedPath = path.resolve(options && options.expectedPath || "");
  const launchedPath = path.resolve(options && options.launchedPath || "");
  const equal = process.platform === "win32"
    ? expectedPath.toLowerCase() === launchedPath.toLowerCase() : expectedPath === launchedPath;
  if (!equal) fail("browser_executable_path_mismatch", { expectedPath, launchedPath });
  const stat = fs.lstatSync(expectedPath);
  if (!stat.isFile() || stat.isSymbolicLink()) fail("browser_executable_invalid", { expectedPath });
  const bytes = fs.readFileSync(expectedPath);
  return { locator:"external:" + expectedPath.replace(/\\/g, "/"),
    bytes:bytes.length, sha256:sha256Bytes(bytes) };
}

module.exports = { INVENTORY_SCHEMA, LEDGER_SCHEMA, RECEIPT_SCHEMA,
  browserExecutableReceipt, createServedResourceLedger, loadResourceInventory,
  resourceManifestEntries, verifyServedResourceClosure };
