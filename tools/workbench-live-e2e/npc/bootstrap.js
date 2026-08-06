#!/usr/bin/env node
"use strict";

// This is the only repository-local module allowed before argv classification.
const RuntimeModuleJournal = require("../lib/runtime-module-journal");

const suffix = "\\tools\\workbench-live-e2e\\npc\\bootstrap.js";
if (!__filename.toLowerCase().endsWith(suffix.toLowerCase())) {
  throw new Error("NPC bootstrap path is outside the fixed repository layout");
}
const root = __filename.slice(0, -suffix.length);
function repo(relativePath) { return root + "\\" + relativePath.replace(/\//g, "\\"); }

const argv = process.argv.slice(2);
const BOOLEAN_LIVE_FLAGS = new Set(["--allow-read-only-live-seed", "--purchase-only",
  "--allow-isolated-commit", "--allow-codex-cu-fallback"]);
const VALUE_LIVE_FLAGS = new Set(["--candidate-root", "--seed-slot", "--slot",
  "--ready-timeout-ms", "--evidence-timeout-ms", "--control-timeout-ms", "--poll-ms",
  "--sale-quantity", "--sale-slot", "--expected-sale-item", "--expected-sale-pre-quantity",
  "--expected-purchase-item", "--purchase-catalog-index"]);
const CONTROL_FLAGS = new Set(["--check", "--help", "-h",
  "--emit-offline-admission-fixture", "--verify-bundle", "--receipt"]);
const REQUIRED_LIVE_FLAGS = Object.freeze(["--candidate-root", "--seed-slot", "--slot",
  "--allow-isolated-commit", "--allow-codex-cu-fallback"]);
const ABSOLUTE_PATH_RE = /^(?:[A-Za-z]:[\\/]|\\\\[^\\/]+[\\/][^\\/]+[\\/]|\/)/;
const READ_ONLY_LIVE_SEED_RE = /^crazyflasher7_saves\d*$/;

function usageError(message) {
  const error = new Error(message);
  error.isUsageError = true;
  return error;
}

function validateLiveArgs(values) {
  const seen = new Set();
  const parsed = Object.create(null);
  for (let index = 0; index < values.length; index += 1) {
    const token = values[index];
    if (CONTROL_FLAGS.has(token)) {
      throw usageError("bootstrap control modes are exact and cannot be mixed with live arguments");
    }
    if (seen.has(token)) throw usageError("duplicate live argument: " + token);
    seen.add(token);
    if (token === "--purchase-only") {
      throw usageError("--purchase-only is diagnostic and is not admitted by the production bootstrap");
    }
    if (BOOLEAN_LIVE_FLAGS.has(token)) {
      parsed[token] = true;
      continue;
    }
    if (!VALUE_LIVE_FLAGS.has(token) || index + 1 >= values.length
        || values[index + 1].startsWith("--")) {
      throw usageError("unknown or incomplete live argument: " + token);
    }
    parsed[token] = values[++index];
  }
  REQUIRED_LIVE_FLAGS.forEach((flag) => {
    if (!seen.has(flag)) throw usageError("complete live arguments require " + flag);
  });
  if (!ABSOLUTE_PATH_RE.test(parsed["--candidate-root"])) {
    throw usageError("--candidate-root is required and must be absolute");
  }
  const liveSlot = /^cf7_agent_[A-Za-z0-9_-]+$/;
  const seedSlot = String(parsed["--seed-slot"] || "");
  const targetSlot = String(parsed["--slot"] || "");
  if (!liveSlot.test(targetSlot)) throw usageError("--slot must be an explicit cf7_agent_* target");
  if (!liveSlot.test(seedSlot)
      && !(READ_ONLY_LIVE_SEED_RE.test(seedSlot) && parsed["--allow-read-only-live-seed"])) {
    throw usageError("--seed-slot must be cf7_agent_* (or an explicitly read-only live seed)");
  }
  if (seedSlot === targetSlot) throw usageError("seed and target slot must differ");
  ["--ready-timeout-ms", "--evidence-timeout-ms", "--control-timeout-ms", "--poll-ms"]
    .forEach((flag) => {
      if (parsed[flag] == null) return;
      const value = Number(parsed[flag]);
      if (!Number.isInteger(value) || value < 50 || value > 600000) {
        throw usageError("invalid " + flag);
      }
    });
  if (parsed["--sale-slot"] != null) {
    const value = Number(parsed["--sale-slot"]);
    if (!Number.isInteger(value) || value < 0 || value > 49) throw usageError("invalid --sale-slot");
  }
  if (parsed["--sale-quantity"] != null && Number(parsed["--sale-quantity"]) !== 1) {
    throw usageError("--sale-quantity must be exactly 1");
  }
  if (parsed["--expected-sale-pre-quantity"] != null) {
    const value = Number(parsed["--expected-sale-pre-quantity"]);
    if (!Number.isInteger(value) || value < 1) {
      throw usageError("--expected-sale-pre-quantity must be a positive integer");
    }
  }
  if (parsed["--purchase-catalog-index"] != null) {
    const value = Number(parsed["--purchase-catalog-index"]);
    if (!Number.isInteger(value) || value < 0) throw usageError("invalid --purchase-catalog-index");
  }
  ["--expected-sale-item", "--expected-purchase-item"].forEach((flag) => {
    if (parsed[flag] != null && !String(parsed[flag]).trim()) throw usageError(flag + " must be non-empty");
  });
  if (parsed["--expected-sale-item"] != null && parsed["--expected-purchase-item"] != null
      && parsed["--expected-sale-item"] === parsed["--expected-purchase-item"]) {
    throw usageError("purchase and sale evidence must use different item names");
  }
  return parsed;
}

function classifyArgs(values) {
  if (!Array.isArray(values) || values.length === 0) {
    throw usageError("one exact bootstrap mode or complete live argument set is required");
  }
  if (values.length === 1 && values[0] === "--check") return "check";
  if (values.length === 1 && ["--help", "-h"].includes(values[0])) return "help";
  if (values.length === 1 && values[0] === "--emit-offline-admission-fixture") return "fixture";
  if ((values.length === 2 || values.length === 4) && values[0] === "--verify-bundle"
      && values[1] && !values[1].startsWith("--")
      && (values.length === 2 || (values[2] === "--receipt"
        && values[3] && !values[3].startsWith("--")))) {
    if (!ABSOLUTE_PATH_RE.test(values[1])
        || values.length === 4 && !ABSOLUTE_PATH_RE.test(values[3])) {
      throw usageError("--verify-bundle and --receipt paths must be absolute");
    }
    return "verify";
  }
  validateLiveArgs(values);
  return "live";
}

let mode;
try { mode = classifyArgs(argv); }
catch (error) {
  process.stderr.write((error && error.message || String(error)) + "\n");
  process.exit(2);
}

process.env.WS_NO_BUFFER_UTIL = "1";
process.env.WS_NO_UTF_8_VALIDATE = "1";
const bootstrapOnly = mode !== "live";
const requiredPhases = mode === "check" ? ["domain_loaded", "audit_executed", "terminal"]
  : mode === "verify" ? ["domain_loaded", "verification_executed", "terminal"]
    : bootstrapOnly ? ["domain_loaded", "terminal"]
      : ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
        "verification_executed", "terminal"];
const entryRows = [
  [__filename, "bootstrap", true],
  [repo("tools/workbench-live-e2e/lib/runtime-module-journal.js"), "journal", true],
  [repo("tools/workbench-live-e2e/lib/evidence-artifact.js"), "journal_helper", true],
  [process.execPath, "external_node_binary", false, false],
];
if (mode !== "help") entryRows.push(
  [repo("tools/workbench-live-e2e/npc/run-live-journey.js"), "domain_runner", false],
  [repo("tools/workbench-live-e2e/npc/verify-live-journey.js"), "domain_verifier_entry", false],
  [repo("tools/workbench-live-e2e/npc/verify-evidence.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/protocol.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/common.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/control-channel.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/control-contract.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/passive-recorder.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/shared-adapter.js"), "domain_module", false],
  [repo("tools/workbench-live-e2e/npc/production-closure.js"), "domain_module", false],
  [repo("launcher/web/modules/inventory-runtime.js"), "production_schema_validator", false],
  [repo("tools/workbench-live-e2e/lib/clone-save-guard.js"), "shared_runtime", false],
  [repo("tools/workbench-live-e2e/lib/launcher-observation.js"), "shared_runtime", false],
  [repo("tools/workbench-live-e2e/lib/runtime-guard.js"), "shared_runtime", false],
  [repo("tools/lib/legacy-http-auth.js"), "shared_dependency", false],
  [repo("tools/lib/legacy-http-client.js"), "shared_dependency", false],
  [repo("tools/lib/runtime-process-identity.js"), "shared_dependency", false],
  [repo("launcher/perf/node_modules/playwright-core/lib/utilsBundle.js"),
    "mature_websocket_transport", false],
  [repo("launcher/perf/node_modules/playwright-core/lib/utilsBundleImpl/index.js"),
    "mature_websocket_transport", false]);
if (mode === "check") entryRows.push(
  [repo("tools/workbench-live-e2e/npc/self-test.js"), "offline_gate", false],
  [repo("tools/workbench-live-e2e/npc/run-checks.js"), "offline_gate_alias", false],
  [repo("tools/workbench-live-e2e/npc/fixtures/valid-bundle.js"), "offline_fixture", false],
  [repo("tools/workbench-live-e2e/npc/ack-control.js"), "control_ack_helper", false],
  [repo("tools/run-npcshop-harness.js"), "offline_browser_gate", false, false],
  [repo("tools/workbench-live-e2e/npc/browser-bootstrap.js"),
    "offline_browser_gate_bootstrap", false, false],
  [repo("tools/workbench-live-e2e/npc/browser-module-inventory.v1.json"),
    "offline_browser_module_inventory", false, false],
  [repo("tools/workbench-live-e2e/npc/browser-resource-inventory.v1.json"),
    "offline_browser_resource_inventory", false, false],
  [repo("tools/workbench-live-e2e/lib/browser-child-resource-closure.js"),
    "offline_browser_resource_closure", false, false],
  [repo("launcher/web/modules/panel-runtime.js"), "production_schema_validator", false],
  [repo("launcher/web/modules/npcshop-runtime.js"), "production_schema_validator", false]);
const entries = entryRows.map(([filePath, role, preexisting, loadable]) => ({
  filePath, role, loadable: loadable !== false, preexisting,
}));

const manifest = RuntimeModuleJournal.buildExplicitModuleManifest({
  root,
  requiredPhases,
  builtins: (mode === "help" ? [] : ["assert", "buffer", "child_process", "constants", "crypto", "dns", "events",
    "fs", "http", "https", "net", "os", "path", "process", "stream", "tls", "tty",
    "url", "util", "zlib"].map((name) => ({ name,
    risk: name === "child_process" ? "high_risk_explicit" : "standard" }))),
  entries,
});
const controller = RuntimeModuleJournal.installRuntimeModuleJournal({ root, manifest });
const runner = mode === "help" ? null : require("./run-live-journey");
const verifier = mode === "help" ? null : require("./verify-live-journey");

function seal() {
  controller.seal("terminal");
  return controller.reverifyAndRestore();
}

async function dispatch() {
  if (mode === "fixture") {
    controller.checkpoint("domain_loaded");
    const journal = seal();
    process.stdout.write(JSON.stringify({ manifest, journal }) + "\n");
    return;
  }
  if (mode === "help") {
    controller.checkpoint("domain_loaded");
    const journal = seal();
    process.stdout.write(JSON.stringify({ help:
      "NPC A3: --check | --verify-bundle <absolute evidence-bundle.json> [--receipt <absolute path>] | complete live arguments",
    moduleEntryCount: manifest.entries.length,
    moduleAdmission: journal.admissionStatus,
    moduleJournalSha256: journal.evidenceSha256 }) + "\n");
    return;
  }
  if (mode === "verify") {
    controller.checkpoint("domain_loaded");
    const verifyArgs = ["--bundle", argv[1]];
    if (argv.length === 4) verifyArgs.push("--receipt", argv[3]);
    const prepared = verifier.prepare(verifyArgs);
    controller.checkpoint("verification_executed");
    const journal = seal();
    const finalized = verifier.finalize(prepared);
    process.stdout.write(JSON.stringify({ receipt: finalized.receipt,
      receiptPath: finalized.receiptPath,
      verificationAdmission: journal.admissionStatus,
      moduleJournalSha256: journal.evidenceSha256 }) + "\n");
    return;
  }
  if (mode === "check") {
    const selfTest = require("./self-test");
    require("./run-checks");
    require("./fixtures/valid-bundle");
    require("./ack-control");
    controller.checkpoint("domain_loaded");
    const checks = await selfTest.run({ quiet: true });
    controller.checkpoint("audit_executed");
    const journal = seal();
    const Evidence = require("../lib/evidence-artifact");
    const receipt = { schema:"workbench-live-e2e.npc.offline-check-receipt.v1",
      status: "OFFLINE_VERIFIED",
      liveStatus: "LIVE_BLOCKED", deployment: "NOT_DEPLOYED",
      checks: checks.passed, total: checks.total,
      moduleAdmission: journal.admissionStatus,
      processExecutable: manifest.entries.find((entry) =>
        entry.role === "external_node_binary"),
      manifestSha256: manifest.manifestSha256,
      moduleJournalSha256: journal.evidenceSha256,
      childReceipts:checks.childReceipts };
    receipt.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
    process.stdout.write(JSON.stringify(receipt) + "\n");
    return;
  }

  controller.checkpoint("domain_loaded");
  const result = await runner.main(argv, controller);
  if (!result || typeof result.prepare !== "function") {
    throw new Error("NPC runner returned without a pre-seal evidence verifier");
  }
  const prepared = result.prepare(manifest);
  controller.checkpoint("verification_executed");
  const journal = seal();
  const finalized = prepared.complete(journal);
  process.stdout.write(JSON.stringify({ type: "final_status",
    status: finalized.receipt.status,
    liveStatus: finalized.receipt.liveStatus,
    deployment: finalized.receipt.deployment,
    runDir: result.runDir, bundlePath: finalized.bundlePath,
    receiptPath: finalized.receiptPath }) + "\n");
}

dispatch().catch((error) => {
  process.stderr.write((error && error.stack || error && error.message || String(error)) + "\n");
  if (error && error.details) process.stderr.write(JSON.stringify(error.details) + "\n");
  process.exitCode = error && error.isUsageError ? 2 : 1;
});

module.exports = { classifyArgs, validateLiveArgs };
