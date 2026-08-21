#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const { canonicalJson, sha256Text } = require("../lib/evidence-artifact");

const root = path.resolve(__dirname, "../../..");
const inventoryPath = path.join(__dirname, "browser-module-inventory.v1.json");
const resourceInventoryPath = path.join(__dirname, "browser-resource-inventory.v1.json");
const inventory = JSON.parse(fs.readFileSync(inventoryPath, "utf8"));
const rawResourceInventory = JSON.parse(fs.readFileSync(resourceInventoryPath, "utf8"));
const INVENTORY_SCHEMA = "workbench-live-e2e.equipment.browser-module-inventory.v1";
const RECEIPT_SCHEMA = "workbench-live-e2e.equipment.browser-gate-receipt.v1";
const CRITICAL_CHECK_NAMES = Object.freeze([
  "isolated candidate projection preserves visible bag request and window",
  "right-pane convert target click previews immediately with exact inventory authority",
  "three all-distinct identity fixtures preserve display and icon roles",
  "tooltip-first response interleave preserves candidate activation and adopts the preview token",
  "commit holds the same inventory write capability through refresh",
  "blocked candidate remains keyboard-readable and activation only explains its reason",
  "definitive stale lease refreshes inventory before rebinding snapshot",
  "pending tuning write blocks close/rebind",
  "ambiguous commit is not replayed",
  "layout stays inside host",
]);
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

if (!inventory || inventory.schema !== INVENTORY_SCHEMA
    || inventory.nodeVersion !== process.version) {
  fail("browser_module_inventory_invalid", {
    schema:inventory && inventory.schema,
    nodeVersion:inventory && inventory.nodeVersion,
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
if (rawResourceInventory.optionalFiles != null) {
  fail("browser_resource_inventory_invalid", { reason:"unexpected_optional_files" });
}
if (moduleFiles.some((relative) => path.isAbsolute(relative)
    || relative.split(/[\\/]/).includes("..") || !/\.(?:js|json)$/.test(relative))) {
  fail("browser_module_inventory_invalid", { reason:"path_escape_or_extension" });
}
if (resourceFiles.some((relative) => relative.includes("\\") || path.posix.isAbsolute(relative)
    || relative.split("/").some((part) => !part || part === "." || part === ".."))) {
  fail("browser_resource_inventory_invalid", { reason:"path_escape" });
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
    process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA,
      "Microsoft", "Edge", "Application", "msedge.exe") : null,
  ].filter(Boolean).find((candidate) => fs.existsSync(candidate));
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
  relative === "tools/run-equipment-tuning-harness.js" ? "browser_runner"
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
  const runner = require(repo("tools/run-equipment-tuning-harness.js"));
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
  const expectedViewports = [
    {width:1024,height:576}, {width:1366,height:768}, {width:1920,height:1080},
  ];
  if (!result || result.mode !== "full"
      || canonicalJson(result.viewports) !== canonicalJson(expectedViewports)
      || !Array.isArray(result.runs) || result.runs.length !== expectedViewports.length) {
    fail("browser_gate_result_invalid", { reason:"envelope" });
  }
  const namesByViewport = [];
  result.runs.forEach((entry, index) => {
    const checks = entry && Array.isArray(entry.checks) ? entry.checks : [];
    const names = checks.map((check) => check && check.name);
    if (!entry || canonicalJson(entry.viewport) !== canonicalJson(expectedViewports[index])
        || entry.total !== 137 || entry.passed !== 137 || checks.length !== 137
        || checks.some((check) => !check || check.ok !== true)
        || names.some((name) => typeof name !== "string" || !name)
        || new Set(names).size !== names.length) {
      fail("browser_gate_result_invalid", { reason:"viewport_checks", index });
    }
    namesByViewport.push(names);
  });
  if (namesByViewport.slice(1).some((names) =>
    canonicalJson(names) !== canonicalJson(namesByViewport[0]))) {
    fail("browser_gate_result_invalid", { reason:"viewport_name_drift" });
  }
  const checkNamesSha256 = namesByViewport.map((names) =>
    sha256Text(canonicalJson(names)));
  if (checkNamesSha256.some((digest) => digest !== expectedCheckNamesSha256)) {
    fail("browser_gate_result_invalid", { reason:"check_names",
      expected:expectedCheckNamesSha256, actual:checkNamesSha256 });
  }
  const firstChecks = new Map(result.runs[0].checks.map((entry) => [entry.name, entry]));
  if (CRITICAL_CHECK_NAMES.some((name) => !firstChecks.has(name))) {
    fail("browser_gate_result_invalid", { reason:"critical_check_missing" });
  }
  const motion = result.motionProof;
  if (!motion || motion.pass !== true || !motion.normal || !motion.reduced
      || motion.normal.reduced !== false
      || motion.normal.animationName !== "equipment-tuning-core-pulse"
      || motion.normal.animationDuration !== "1.8s"
      || motion.normal.animationCount < 1 || motion.normal.width !== 56
      || motion.normal.height !== 56 || motion.reduced.reduced !== true
      || motion.reduced.animationName !== "none" || motion.reduced.animationDuration !== "0s"
      || motion.reduced.animationCount !== 0 || motion.reduced.width !== 56
      || motion.reduced.height !== 56) {
    fail("browser_gate_result_invalid", { reason:"motion_contract" });
  }
  controller.checkpoint("browser_executed");
  controller.seal("terminal");
  const journal = controller.reverifyAndRestore();
  RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal });
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
    result:{
      viewports:result.viewports,
      checkCount:137,
      checkNamesSha256,
      criticalChecks:CRITICAL_CHECK_NAMES.map((name) => {
        const check = firstChecks.get(name);
        return { name:check.name, ok:check.ok, detail:check.detail };
      }),
      motionProof:motion,
      resultSha256:sha256Text(canonicalJson(result)),
    },
  };
  receipt.evidenceSha256 = sha256Text(canonicalJson(receipt));
  process.stdout.write(JSON.stringify(receipt) + "\n");
}

run().catch((error) => {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  if (error && error.details) process.stderr.write(JSON.stringify(error.details) + "\n");
  process.exitCode = 1;
});
