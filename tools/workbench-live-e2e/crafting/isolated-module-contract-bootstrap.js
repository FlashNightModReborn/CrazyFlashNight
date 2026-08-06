#!/usr/bin/env node
"use strict";

// Keep this as the first repository-local require. The child closes its own
// module set before the pure fixture verifier is allowed to run.
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");

const root = path.resolve(__dirname, "../../..");
const inventoryPath = path.join(__dirname, "isolated-module-inventory.v1.json");
const INVENTORY_SCHEMA = "workbench-live-e2e.crafting.isolated-module-inventory.v1";
const FIXTURE_SCHEMA = "workbench-live-e2e.crafting.module-manifest-fixture.v1";
const RESULT_SCHEMA = "workbench-live-e2e.crafting.module-manifest-isolated-test.v1";
const RECEIPT_SCHEMA = "workbench-live-e2e.crafting.module-manifest-child-receipt.v2";
const MAX_INPUT_BYTES = 8 * 1024 * 1024;
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
    fail("isolated_module_inventory_invalid", { label });
  }
  const sorted = values.slice().sort();
  if (new Set(values).size !== values.length
      || Evidence.canonicalJson(values) !== Evidence.canonicalJson(sorted)) {
    fail("isolated_module_inventory_invalid", { label, reason:"not_exact_sorted_unique" });
  }
  return values;
}

function repo(relative) {
  return path.join(root, relative.replace(/\//g, path.sep));
}

function run() {
  const inputBytes = fs.readFileSync(0);
  if (inputBytes.length < 1 || inputBytes.length > MAX_INPUT_BYTES) {
    fail("isolated_module_fixture_size_invalid", { bytes:inputBytes.length });
  }
  const inputText = inputBytes.toString("utf8");
  const inventory = JSON.parse(fs.readFileSync(inventoryPath, "utf8"));
  if (!inventory || inventory.schema !== INVENTORY_SCHEMA
      || inventory.nodeVersion !== process.version) {
    fail("isolated_module_inventory_invalid", {
      schema:inventory && inventory.schema,
      nodeVersion:inventory && inventory.nodeVersion,
      actualNodeVersion:process.version,
    });
  }
  const builtins = exactSortedStrings(inventory.builtins, "builtins");
  const files = exactSortedStrings(inventory.files, "files");
  if (files.some((relative) => path.isAbsolute(relative)
      || relative.split(/[\\/]/).includes("..") || !/\.(?:js|json)$/.test(relative))) {
    fail("isolated_module_inventory_invalid", { reason:"path_escape_or_extension" });
  }

  function buildManifest(postAdmissionLoadable) {
    return RuntimeModuleJournal.buildExplicitModuleManifest({
      root,
      requiredPhases:["domain_loaded", "terminal"],
      builtins:(postAdmissionLoadable ? builtins : []).map((name) => ({ name,
        risk:name === "child_process" ? "high_risk_explicit" : "standard" })),
      entries:[
      { filePath:__filename, role:"bootstrap", loadable:true, preexisting:true },
      { filePath:repo("tools/workbench-live-e2e/lib/runtime-module-journal.js"),
        role:"journal", loadable:true, preexisting:true },
      { filePath:repo("tools/workbench-live-e2e/lib/evidence-artifact.js"),
        role:"journal_helper", loadable:true, preexisting:true },
      { filePath:inventoryPath, role:"module_inventory", loadable:false, preexisting:false },
      { filePath:process.execPath, role:"external_node_binary",
        loadable:false, preexisting:false },
    ].concat(files.map((relative) => ({ filePath:repo(relative),
      role:relative.endsWith("/self-test.js") ? "offline_gate_finalizer"
        : "offline_gate_dependency",
      loadable:postAdmissionLoadable, preexisting:false }))),
    });
  }

  const postAdmissionPaths = files.map((relative) => repo(relative));
  if (postAdmissionPaths.some((filePath) => require.cache[filePath])) {
    fail("isolated_module_loaded_before_admission");
  }
  const preAdmissionManifest = buildManifest(false);
  const preAdmissionController = RuntimeModuleJournal.installRuntimeModuleJournal({
    root, manifest:preAdmissionManifest });
  preAdmissionController.checkpoint("domain_loaded");
  preAdmissionController.seal("terminal");
  const preAdmissionJournal = preAdmissionController.reverifyAndRestore();
  RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest:preAdmissionManifest,
    artifact:preAdmissionJournal });
  if (postAdmissionPaths.some((filePath) => require.cache[filePath])) {
    fail("isolated_module_loaded_before_admission");
  }

  const manifest = buildManifest(true);
  const controller = RuntimeModuleJournal.installRuntimeModuleJournal({ root, manifest });
  const selfTest = require("./self-test");
  controller.checkpoint("domain_loaded");
  controller.seal("terminal");
  const journal = controller.reverifyAndRestore();
  RuntimeModuleJournal.verifyRuntimeModuleJournal({ root, manifest, artifact:journal });

  const fixture = JSON.parse(inputText);
  if (!fixture || fixture.schema !== FIXTURE_SCHEMA) {
    fail("isolated_module_fixture_invalid");
  }
  const result = selfTest.runIsolatedModuleManifestContractTests(fixture);
  if (!result || result.schema !== RESULT_SCHEMA) {
    fail("isolated_module_result_invalid");
  }
  const processExecutable = manifest.entries.find((entry) =>
    entry.role === "external_node_binary");
  const receipt = {
    schema:RECEIPT_SCHEMA,
    status:"OFFLINE_VERIFIED",
    inputSha256:Evidence.sha256Bytes(inputBytes),
    result,
    resultSha256:Evidence.sha256Text(Evidence.canonicalJson(result)),
    moduleAdmission:journal.admissionStatus,
    manifestSha256:manifest.manifestSha256,
    moduleJournalSha256:journal.evidenceSha256,
    moduleEntryCount:manifest.entries.length,
    preAdmissionManifestSha256:preAdmissionManifest.manifestSha256,
    preAdmissionModuleJournalSha256:preAdmissionJournal.evidenceSha256,
    preAdmissionModuleEntryCount:preAdmissionManifest.entries.length,
    testedModulesLoadedBeforeAdmission:false,
    processExecutable,
  };
  receipt.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
  process.stdout.write(JSON.stringify(receipt) + "\n");
}

try {
  run();
} catch (error) {
  process.stderr.write((error && error.stack || String(error)) + "\n");
  if (error && error.details) process.stderr.write(JSON.stringify(error.details) + "\n");
  process.exitCode = 1;
}
