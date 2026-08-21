#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const { canonicalJson, sha256Text } = require("../lib/evidence-artifact");

const root = path.resolve(__dirname, "../../..");
const inventoryPath = path.join(__dirname, "browser-module-inventory.v1.json");
const inventory = JSON.parse(fs.readFileSync(inventoryPath, "utf8"));
const resourceInventoryPath = path.join(__dirname, "browser-resource-inventory.v1.json");
const rawResourceInventory = JSON.parse(fs.readFileSync(resourceInventoryPath, "utf8"));
const RECEIPT_SCHEMA = "workbench-live-e2e.npc.browser-gate-receipt.v1";
const INVENTORY_SCHEMA = "workbench-live-e2e.npc.browser-module-inventory.v1";
const CRITICAL_CHECK_NAMES = [
  "filtered visible projection failure exposes an actionable retry and blocks the next trade write",
  "visible retry redoes 3 physical + exact filtered projection and restores the preserved filter/page/receipt",
  "generic write dispatch rechecks Inventory immediately before sending after an intervening synchronous failure",
  "filtered authority projection rejects containerVersion drift from its paired physical receipt",
  "preview dispatch independently refuses an Inventory-invalid settlement mutation",
  "commit dispatch independently refuses an Inventory-invalid settlement",
  "settlement entry independently refuses an Inventory-invalid selection",
];
process.env.WS_NO_BUFFER_UTIL = "1";
process.env.WS_NO_UTF_8_VALIDATE = "1";

function fail(code, details) {
  const error = new Error(code);
  error.code = code;
  error.details = details || null;
  throw error;
}

function exactSortedStrings(values, label) {
  if (!Array.isArray(values) || values.length < 1
      || values.some((value) => typeof value !== "string" || !value)) {
    fail("browser_module_inventory_invalid", { label });
  }
  const sorted = values.slice().sort();
  if (new Set(values).size !== values.length || canonicalJson(values) !== canonicalJson(sorted)) {
    fail("browser_module_inventory_invalid", { label, reason:"not_exact_sorted_unique" });
  }
  return values;
}

if (!inventory || inventory.schema !== INVENTORY_SCHEMA || inventory.nodeVersion !== process.version) {
  fail("browser_module_inventory_invalid", {
    schema:inventory && inventory.schema, nodeVersion:inventory && inventory.nodeVersion,
    actualNodeVersion:process.version,
  });
}
const expectedCheckNamesSha256 = inventory.expectedCheckNamesSha256;
if (!/^[a-f0-9]{64}$/.test(String(expectedCheckNamesSha256 || ""))) {
  fail("browser_module_inventory_invalid", { reason:"expected_check_names" });
}
const builtins = exactSortedStrings(inventory.builtins, "builtins");
const moduleFiles = exactSortedStrings(inventory.files, "files");
if (!rawResourceInventory
    || rawResourceInventory.schema !== "workbench-live-e2e.browser-resource-inventory.v1") {
  fail("browser_resource_inventory_invalid");
}
const resourceFiles = exactSortedStrings(rawResourceInventory.files, "resource_files");
if (resourceFiles.some((relative) => relative.includes("\\") || path.posix.isAbsolute(relative)
    || relative.split("/").some((part) => !part || part === "." || part === ".."))) {
  fail("browser_resource_inventory_invalid", { reason:"path_escape" });
}
if (moduleFiles.some((relative) => path.isAbsolute(relative)
    || relative.split(/[\\/]/).includes("..") || !/\.(?:js|json)$/.test(relative))) {
  fail("browser_module_inventory_invalid", { reason:"path_escape_or_extension" });
}

function repo(relative) {
  return path.join(root, relative.replace(/\//g, path.sep));
}

function edgePath() {
  return [
    path.join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)",
      "Microsoft", "Edge", "Application", "msedge.exe"),
    path.join(process.env.ProgramFiles || "C:\\Program Files",
      "Microsoft", "Edge", "Application", "msedge.exe"),
  ].find((candidate) => fs.existsSync(candidate));
}

const browserBinary = edgePath();
if (!browserBinary) fail("browser_binary_missing");
const entryRows = [
  [__filename, "bootstrap", true, true],
  [repo("tools/workbench-live-e2e/lib/runtime-module-journal.js"), "journal", true, true],
  [repo("tools/workbench-live-e2e/lib/evidence-artifact.js"), "journal_helper", true, true],
  [repo("tools/workbench-live-e2e/lib/browser-child-resource-closure.js"),
    "browser_resource_closure", false, true],
  [inventoryPath, "module_inventory", false, false],
  [resourceInventoryPath, "browser_resource_inventory", false, false],
].concat(moduleFiles.map((relative) => [repo(relative),
  relative === "tools/run-npcshop-harness.js" ? "browser_runner"
    : relative === "tools/lib/read-css-bundle.js" ? "browser_runner_helper"
      : "browser_runtime_module",
  false, true])).concat(resourceFiles.map((relative) => [
  repo("launcher/web/" + relative), "browser_served_resource", false, false,
])).concat([[browserBinary, "external_browser_binary", false, false]]);

const manifest = RuntimeModuleJournal.buildExplicitModuleManifest({
  root,
  requiredPhases:["domain_loaded", "browser_executed", "terminal"],
  builtins:builtins.map((name) => ({ name,
    risk:name === "child_process" ? "high_risk_explicit" : "standard" })),
  entries:entryRows.map(([filePath, role, preexisting, loadable]) => ({
    filePath, role, preexisting, loadable,
  })),
});
const controller = RuntimeModuleJournal.installRuntimeModuleJournal({ root, manifest });
const BrowserChildResourceClosure = require("../lib/browser-child-resource-closure");
const resourceInventory = BrowserChildResourceClosure.loadResourceInventory({
  root:path.join(root, "launcher", "web"), inventoryPath:resourceInventoryPath,
});

async function run() {
  const runner = require(repo("tools/run-npcshop-harness.js"));
  controller.checkpoint("domain_loaded");
  const result = await runner.run();
  const servedResourceReceipt = BrowserChildResourceClosure.verifyServedResourceClosure({
    root:path.join(root, "launcher", "web"), inventory:resourceInventory,
    ledger:result && result.servedResourceLedger,
    allowedFailures:[{ requestPath:"/favicon.ico", relativePath:"favicon.ico",
      failureCode:"read_failed" }],
  });
  const launchedBrowserBinary = BrowserChildResourceClosure.browserExecutableReceipt({
    expectedPath:browserBinary, launchedPath:result && result.executablePath,
  });
  const checks = result && Array.isArray(result.checks) ? result.checks : [];
  const checkNames = checks.map((entry) => entry && entry.name);
  const criticalChecks = CRITICAL_CHECK_NAMES.map((name) =>
    checks.filter((entry) => entry && entry.name === name));
  if (!result || result.passed !== result.total || result.total !== 130
      || result.materialNavigationPassed !== result.materialNavigationTotal
      || result.materialNavigationTotal !== 23
      || result.reducedPassed !== result.reducedTotal || result.reducedTotal !== 2
      || result.contractQuantity !== 4549 || checks.length !== 130
      || checkNames.some((name) => typeof name !== "string" || !name)
      || new Set(checkNames).size !== checkNames.length
      || checks.some((entry) => entry.ok !== true)
      || criticalChecks.some((entries) => entries.length !== 1)) {
    fail("browser_gate_result_invalid", { result });
  }
  const checkNamesSha256 = sha256Text(canonicalJson(checkNames));
  if (checkNamesSha256 !== expectedCheckNamesSha256) {
    fail("browser_gate_result_invalid", { reason:"check_names",
      expected:expectedCheckNamesSha256, actual:checkNamesSha256 });
  }
  controller.checkpoint("browser_executed");
  controller.seal("terminal");
  const journal = controller.reverifyAndRestore();
  try {
    RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal });
  } catch (error) {
    const expected = manifest.entries.filter((entry) => entry.loadable).map((entry) => entry.locator);
    const actual = journal.loadedFiles.map((entry) => entry.locator);
    const expectedLoaded = manifest.entries.filter((entry) => entry.loadable)
      .map((entry) => ({ locator:entry.locator, sha256:entry.sha256, bytes:entry.bytes }));
    function firstDifference(left, right) {
      const length = Math.max(left.length, right.length);
      for (let index = 0; index < length; index += 1) {
        if (canonicalJson(left[index]) !== canonicalJson(right[index])) {
          return { index, left:left[index], right:right[index] };
        }
      }
      return null;
    }
    error.details = Object.assign({}, error.details || {}, {
      expectedCount:expected.length, actualCount:actual.length,
      missing:expected.filter((locator) => !actual.includes(locator)),
      unexpected:actual.filter((locator) => !expected.includes(locator)),
      expectedPreexisting:manifest.entries.filter((entry) => entry.preexisting)
        .map((entry) => entry.locator),
      actualPreexisting:journal.preexisting.map((entry) => entry.locator),
      cacheCount:journal.cacheAtRestore.length,
      loadedDifference:firstDifference(expectedLoaded, journal.loadedFiles),
      cacheDifference:firstDifference(expectedLoaded, journal.cacheAtRestore),
      builtinsExpected:manifest.builtins.map((entry) => entry.name).sort(),
      builtinsActual:journal.builtins,
    });
    throw error;
  }
  const browserEntry = manifest.entries.find((entry) => entry.role === "external_browser_binary");
  if (!browserEntry || browserEntry.locator !== launchedBrowserBinary.locator
      || browserEntry.sha256 !== launchedBrowserBinary.sha256
      || browserEntry.bytes !== launchedBrowserBinary.bytes) {
    fail("browser_binary_manifest_mismatch", { browserEntry, launchedBrowserBinary });
  }
  const receipt = {
    schema:RECEIPT_SCHEMA,
    status:"OFFLINE_VERIFIED",
    moduleAdmission:journal.admissionStatus,
    journalVerification:"VERIFIED",
    manifestSha256:manifest.manifestSha256,
    moduleJournalSha256:journal.evidenceSha256,
    moduleEntryCount:manifest.entries.length,
    browserBinary:launchedBrowserBinary,
    servedResourceClosure:servedResourceReceipt,
    result:{ passed:result.passed, total:result.total,
      materialNavigationPassed:result.materialNavigationPassed,
      materialNavigationTotal:result.materialNavigationTotal,
      reducedPassed:result.reducedPassed, reducedTotal:result.reducedTotal,
      contractQuantity:result.contractQuantity,
      checkNamesSha256,
      criticalChecks:criticalChecks.map((entries) => ({ name:entries[0].name,
        ok:entries[0].ok, detail:entries[0].detail })),
      resultSha256:sha256Text(canonicalJson(result)) },
  };
  receipt.evidenceSha256 = sha256Text(canonicalJson(receipt));
  process.stdout.write(JSON.stringify(receipt) + "\n");
}

run().catch((error) => {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  if (error && error.details) process.stderr.write(JSON.stringify(error.details) + "\n");
  process.exitCode = 1;
});
