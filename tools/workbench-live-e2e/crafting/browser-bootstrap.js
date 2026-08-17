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
const RECEIPT_SCHEMA = "workbench-live-e2e.crafting.browser-gate-receipt.v1";
const INVENTORY_SCHEMA = "workbench-live-e2e.crafting.browser-module-inventory.v1";
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
const expectedScenarioNamesSha256 = inventory.expectedScenarioNamesSha256;
if (!expectedScenarioNamesSha256
    || canonicalJson(Object.keys(expectedScenarioNamesSha256))
      !== canonicalJson(["baseline", "coverage", "fault", "identity", "legacy",
        "sessionLock", "recipeJump", "materialShop", "infrastructure", "procurement"])
    || Object.values(expectedScenarioNamesSha256).some((digest) =>
      !/^[a-f0-9]{64}$/.test(String(digest || "")))) {
  fail("browser_module_inventory_invalid", { reason:"expected_scenario_names" });
}
const builtins = exactSortedStrings(inventory.builtins, "builtins");
const moduleFiles = exactSortedStrings(inventory.files, "files");
if (!rawResourceInventory
    || rawResourceInventory.schema !== "workbench-live-e2e.browser-resource-inventory.v1") {
  fail("browser_resource_inventory_invalid");
}
const requiredResourceFiles = exactSortedStrings(rawResourceInventory.files, "resource_files");
const optionalResourceFiles = rawResourceInventory.optionalFiles == null ? []
  : exactSortedStrings(rawResourceInventory.optionalFiles, "optional_resource_files");
if (optionalResourceFiles.some((relative) => requiredResourceFiles.includes(relative))) {
  fail("browser_resource_inventory_invalid", { reason:"required_optional_overlap" });
}
const resourceFiles = requiredResourceFiles.concat(optionalResourceFiles).sort();
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
  relative === "tools/run-crafting-harness.js" ? "browser_runner"
    : relative === "tools/lib/read-css-bundle.js" ? "browser_runner_helper"
      : "browser_runtime_module",
  false, true])).concat(resourceFiles.map((relative) => [
  repo("launcher/web/" + relative), "browser_served_resource", false, false,
])).concat([
  [browserBinary, "external_browser_binary", false, false],
]);

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
  const runner = require(repo("tools/run-crafting-harness.js"));
  controller.checkpoint("domain_loaded");
  const result = await runner.run();
  const servedResourceReceipt = BrowserChildResourceClosure.verifyServedResourceClosure({
    root:path.join(root, "launcher", "web"), inventory:resourceInventory,
    ledger:result && result.servedResourceLedger,
    allowedFailures:[{ requestPath:"/favicon.ico", relativePath:"favicon.ico",
      failureCode:"read_failed" },
    { requestPath:"/assets/dressup/skins/__crafting_inspector_missing__.png",
      relativePath:"assets/dressup/skins/__crafting_inspector_missing__.png",
      failureCode:"read_failed" },
    { requestPath:"/assets/dressup/skins/__crafting_inspector_missing__.png",
      relativePath:"assets/dressup/skins/__crafting_inspector_missing__.png",
      failureCode:"read_failed" },
    { requestPath:"/assets/dressup/skins/__crafting_inspector_missing__.png",
      relativePath:"assets/dressup/skins/__crafting_inspector_missing__.png",
      failureCode:"read_failed" }],
  });
  const launchedBrowserBinary = BrowserChildResourceClosure.browserExecutableReceipt({
    expectedPath:browserBinary, launchedPath:result && result.executablePath,
  });
  const scenarioCounts = { baseline:150, coverage:15, fault:8, identity:10,
    legacy:6, sessionLock:9, recipeJump:26, materialShop:12,
    infrastructure:9, procurement:17 };
  const scenarioNames = {};
  let scenarioInvalid = false;
  Object.keys(scenarioCounts).forEach((name) => {
    const runs = result && result[name];
    if (!Array.isArray(runs) || runs.length !== 3) { scenarioInvalid = true; return; }
    scenarioNames[name] = runs.map((run) => {
      const checks = run && Array.isArray(run.checks) ? run.checks : [];
      const names = checks.map((entry) => entry && entry.name);
      if (!run || run.total !== scenarioCounts[name] || run.passed !== run.total
          || checks.length !== run.total || checks.some((entry) => entry.ok !== true)
          || names.some((value) => typeof value !== "string" || !value)
          || new Set(names).size !== names.length) scenarioInvalid = true;
      return names;
    });
  });
  if (!result || result.mode !== "full" || scenarioInvalid
      || canonicalJson(result.viewports) !== canonicalJson([
        {width:1024,height:576}, {width:1366,height:768}, {width:1920,height:1080},
      ])) {
    fail("browser_gate_result_invalid", { result });
  }
  const scenarioNamesSha256 = Object.fromEntries(Object.keys(scenarioNames).map((name) =>
    [name, sha256Text(canonicalJson(scenarioNames[name]))]));
  if (canonicalJson(scenarioNamesSha256) !== canonicalJson(expectedScenarioNamesSha256)) {
    fail("browser_gate_result_invalid", { reason:"scenario_names",
      expected:expectedScenarioNamesSha256, actual:scenarioNamesSha256 });
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
    result:{ viewports:result.viewports, scenarioCounts,
      scenarioNamesSha256,
      faultChecks:result.fault[0].checks.map((entry) => ({
        name:entry.name, ok:entry.ok, detail:entry.detail,
      })),
      procurementChecks:result.procurement[0].checks.map((entry) => ({
        name:entry.name, ok:entry.ok, detail:entry.detail,
      })),
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
