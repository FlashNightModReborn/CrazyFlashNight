#!/usr/bin/env node
"use strict";

// This must remain the first repository-local require. Exact argv mode is classified
// before the journal admits any domain, verifier, fixture, or mutation-capable module.
const RuntimeModuleJournal = require("../lib/runtime-module-journal");
const path = require("path");

const bootstrapSuffix = "\\tools\\workbench-live-e2e\\equipment\\bootstrap.js";
if (!__filename.toLowerCase().endsWith(bootstrapSuffix.toLowerCase())) {
  throw new Error("Equipment bootstrap path is outside the fixed repository layout");
}
const root = __filename.slice(0, -bootstrapSuffix.length);
function repo(relativePath) { return root + "\\" + relativePath.replace(/\//g, "\\"); }

process.env.WS_NO_BUFFER_UTIL = "1";
process.env.WS_NO_UTF_8_VALIDATE = "1";

function usage(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function exactBootstrapMode(args) {
  if (args.length === 1 && args[0] === "--check") return "check";
  if (args.length === 1 && (args[0] === "--help" || args[0] === "-h")) return "help";
  if (args.length === 1 && args[0] === "--emit-offline-admission-fixture") return "emit";
  if ((args.length === 2 || args.length === 4) && args[0] === "--verify-bundle") {
    if (!args[1] || !path.isAbsolute(args[1])) {
      usage("--verify-bundle requires one absolute bundle path");
    }
    if (args.length === 4 && (args[2] !== "--receipt" || !args[3]
        || !path.isAbsolute(args[3]))) {
      usage("--receipt requires one absolute path after --verify-bundle");
    }
    return "verify";
  }
  const controlTokens = new Set(["--check", "--help", "-h",
    "--emit-offline-admission-fixture", "--verify-bundle", "--receipt"]);
  if (args.some((value) => controlTokens.has(value))) {
    usage("bootstrap control modes are mutually exclusive and require exact arguments");
  }
  return "live";
}

function manifestEntries(mode) {
  const entries = [
    { filePath: __filename, role: "bootstrap", loadable: true, preexisting: true },
    { filePath: repo("tools/workbench-live-e2e/lib/runtime-module-journal.js"),
      role: "journal", loadable: true, preexisting: true },
    { filePath: repo("tools/workbench-live-e2e/lib/evidence-artifact.js"),
      role: "journal_helper", loadable: true, preexisting: true },
    { filePath: repo("tools/workbench-live-e2e/equipment/run-live-journey.js"),
      role: "domain_runner", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/verify-live-journey.js"),
      role: "domain_verifier_entry", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/production-closure.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/common.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/protocol.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/control-channel.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/cdp-passive-observer.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/equipment/evidence-verifier.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/lib/clone-save-guard.js"),
      role: "shared_runtime", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/lib/control-contract.js"),
      role: "shared_runtime", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/lib/launcher-observation.js"),
      role: "shared_runtime", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/lib/runtime-guard.js"),
      role: "shared_runtime", loadable: true, preexisting: false },
    { filePath: repo("tools/lib/legacy-http-auth.js"),
      role: "shared_dependency", loadable: true, preexisting: false },
    { filePath: repo("tools/lib/legacy-http-client.js"),
      role: "shared_dependency", loadable: true, preexisting: false },
    { filePath: repo("tools/lib/runtime-process-identity.js"),
      role: "shared_dependency", loadable: true, preexisting: false },
    { filePath: repo("tools/equipment-tuning/fixtures/item-identity-triple.json"),
      role: "canonical_identity_fixture", loadable: true, preexisting: false },
    { filePath: repo("launcher/perf/node_modules/playwright-core/lib/utilsBundle.js"),
      role: "mature_websocket_transport", loadable: true, preexisting: false },
    { filePath: repo("launcher/perf/node_modules/playwright-core/lib/utilsBundleImpl/index.js"),
      role: "mature_websocket_transport", loadable: true, preexisting: false },
    { filePath: process.execPath, role: "external_node_binary",
      loadable: false, preexisting: false },
  ];
  if (mode === "check" || mode === "emit") {
    entries.push(
      { filePath: repo("tools/workbench-live-e2e/equipment/self-test.js"),
        role: "offline_gate", loadable: true, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/equipment/fixtures/valid-bundle.js"),
        role: "offline_fixture", loadable: true, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/equipment/ack-control.js"),
        role: "ack_helper", loadable: true, preexisting: false },
      { filePath: repo("tools/run-equipment-tuning-harness.js"),
        role: "offline_browser_runner", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/equipment/browser-bootstrap.js"),
        role: "offline_browser_bootstrap", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/equipment/browser-module-inventory.v1.json"),
        role: "offline_browser_module_inventory", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/equipment/browser-resource-inventory.v1.json"),
        role: "offline_browser_resource_inventory", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/lib/browser-child-resource-closure.js"),
        role: "offline_browser_resource_closure", loadable: false, preexisting: false },
      { filePath: repo("launcher/web/modules/equipment-tuning/dev/harness.html"),
        role: "offline_browser_harness", loadable: false, preexisting: false },
    );
  }
  return entries;
}

async function dispatch(argv) {
  const mode = exactBootstrapMode(argv);
  const auditProfile = mode === "check" || mode === "emit";
  const verificationProfile = mode === "verify";
  const requiredPhases = auditProfile
    ? ["domain_loaded", "audit_executed", "terminal"]
    : verificationProfile
      ? ["domain_loaded", "verification_executed", "terminal"]
      : mode === "live"
        ? ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
          "verification_executed", "terminal"]
        : ["domain_loaded", "terminal"];
  const manifest = RuntimeModuleJournal.buildExplicitModuleManifest({
    root,
    requiredPhases,
    builtins: [
      { name: "assert", risk: "standard" },
      { name: "buffer", risk: "standard" },
      { name: "child_process", risk: "high_risk_explicit" },
      { name: "constants", risk: "standard" },
      { name: "crypto", risk: "standard" },
      { name: "dns", risk: "standard" },
      { name: "events", risk: "standard" },
      { name: "fs", risk: "standard" },
      { name: "http", risk: "standard" },
      { name: "https", risk: "standard" },
      { name: "net", risk: "standard" },
      { name: "os", risk: "standard" },
      { name: "path", risk: "standard" },
      { name: "process", risk: "standard" },
      { name: "stream", risk: "standard" },
      { name: "tls", risk: "standard" },
      { name: "tty", risk: "standard" },
      { name: "url", risk: "standard" },
      { name: "util", risk: "standard" },
      { name: "zlib", risk: "standard" },
    ],
    entries: manifestEntries(mode),
  });

  const controller = RuntimeModuleJournal.installRuntimeModuleJournal({ root, manifest });
  const runner = require("./run-live-journey");
  const verifier = require("./verify-live-journey");
  let selfTest = null;
  if (mode === "check" || mode === "emit") {
    selfTest = require("./self-test");
    require("./fixtures/valid-bundle");
    require("./ack-control");
  }
  controller.checkpoint("domain_loaded");

  function sealAdmission() {
    controller.seal("terminal");
    return controller.reverifyAndRestore();
  }

  if (mode === "emit") {
    const audit = selfTest.runSelfTests();
    controller.checkpoint("audit_executed");
    const artifact = sealAdmission();
    process.stdout.write(JSON.stringify({ manifest, artifact,
      processExecutable: manifest.entries.find((entry) =>
        entry.role === "external_node_binary"),
      audit: { checks: audit.passed, positives: audit.positives, negatives: audit.negatives } }));
    return;
  }
  if (mode === "verify") {
    const verifyArgs = ["--bundle", argv[1]];
    if (argv.length === 4) verifyArgs.push("--receipt", argv[3]);
    const prepared = verifier.prepare(verifyArgs);
    controller.checkpoint("verification_executed");
    const artifact = sealAdmission();
    const verified = verifier.finalize(prepared, { manifest, journal: artifact });
    console.log(JSON.stringify({ receipt: verified.receipt,
      verificationAdmission: artifact.admissionStatus,
      manifestSha256: manifest.manifestSha256,
      moduleJournalSha256: artifact.evidenceSha256 }, null, 2));
    return;
  }
  if (mode === "check") {
    const checks = verifier.runCheck({ emit: false });
    controller.checkpoint("audit_executed");
    const artifact = sealAdmission();
    const Evidence = require("../lib/evidence-artifact");
    const receipt = { schema:"workbench-live-e2e.equipment.offline-check-receipt.v1",
      status: "OFFLINE_VERIFIED", liveStatus: "LIVE_BLOCKED",
      deployment: "NOT_DEPLOYED", checks: checks.passed,
      positives: checks.positives, negatives: checks.negatives,
      moduleAdmission: artifact.admissionStatus,
      processExecutable: manifest.entries.find((entry) =>
        entry.role === "external_node_binary"),
      manifestSha256: manifest.manifestSha256,
      moduleJournalSha256: artifact.evidenceSha256,
      childReceipts:checks.childReceipts };
    receipt.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
    console.log(JSON.stringify(receipt, null, 2));
    return;
  }
  if (mode === "help") {
    runner.main(argv, controller);
    sealAdmission();
    return;
  }

  const output = await runner.main(argv, controller);
  if (!output || typeof output.finalize !== "function") {
    throw new Error("Equipment runner returned without a finalizable evidence bundle");
  }
  const pending = output.finalize(manifest);
  if (!pending || typeof pending.complete !== "function"
      || !pending.preSealVerification
      || pending.preSealVerification.status !== "PRESEAL_VERIFIED") {
    throw new Error("Equipment runner did not execute the pre-seal final verifier");
  }
  controller.checkpoint("verification_executed");
  const artifact = sealAdmission();
  const result = pending.complete(artifact);
  console.log(JSON.stringify({ status: result.receipt.status,
    deployment: result.receipt.deployment, runDir: output.runDir,
    bundlePath: result.bundlePath, receiptPath: result.receiptPath }, null, 2));
}

dispatch(process.argv.slice(2)).catch((error) => {
  console.error(error && error.isUsageError ? error.message
    : error && error.stack || error && error.message || String(error));
  process.exitCode = error && error.isUsageError ? 2 : 1;
});
