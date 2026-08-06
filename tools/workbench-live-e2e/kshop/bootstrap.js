#!/usr/bin/env node
"use strict";

const RuntimeModuleJournal = require("../lib/runtime-module-journal");

const bootstrapSuffix = "\\tools\\workbench-live-e2e\\kshop\\bootstrap.js";
if (!__filename.toLowerCase().endsWith(bootstrapSuffix.toLowerCase())) {
  throw new Error("KShop bootstrap path is outside the fixed repository layout");
}
const root = __filename.slice(0, -bootstrapSuffix.length);
function repo(relativePath) { return root + "\\" + relativePath.replace(/\//g, "\\"); }
const argv = process.argv.slice(2);

function classifyArgs(values) {
  if (values.length === 1 && values[0] === "--check") return "check";
  if (values.length === 1 && ["--help", "-h"].includes(values[0])) return "help";
  if (values.length === 1 && values[0] === "--emit-offline-admission-fixture") return "fixture";
  if (values.length === 2 && values[0] === "--verify-bundle"
      && values[1] && !values[1].startsWith("--")) return "verify";
  if (values.length === 4 && values[0] === "--verify-bundle"
      && values[1] && !values[1].startsWith("--")
      && values[2] === "--receipt" && values[3] && !values[3].startsWith("--")) return "verify";
  const controlFlags = new Set(["--check", "--help", "-h",
    "--emit-offline-admission-fixture", "--verify-bundle", "--receipt"]);
  if (values.some((value) => controlFlags.has(value))) {
    const error = new Error("bootstrap control modes are exact and cannot be mixed with live arguments");
    error.isUsageError = true;
    throw error;
  }
  return "live";
}

let mode;
try {
  mode = classifyArgs(argv);
} catch (error) {
  console.error(error.message);
  process.exit(2);
}
const bootstrapOnly = mode !== "live";
const auditProfile = mode === "check" || mode === "fixture";
const verificationProfile = mode === "verify";

// The bundled ws implementation has complete JavaScript fallbacks. Disable only its
// optional native accelerators so the exact module closure stays deterministic.
process.env.WS_NO_BUFFER_UTIL = "1";
process.env.WS_NO_UTF_8_VALIDATE = "1";

const manifest = RuntimeModuleJournal.buildExplicitModuleManifest({
  root,
  requiredPhases: auditProfile ? ["domain_loaded", "audit_executed", "terminal"]
    : verificationProfile ? ["domain_loaded", "verification_executed", "terminal"]
    : bootstrapOnly ? ["domain_loaded", "terminal"]
    : ["domain_loaded", "clone_prepared", "first_captured", "restart_captured",
      "verification_executed", "terminal"],
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
  entries: [
    { filePath: __filename, role: "bootstrap", loadable: true, preexisting: true },
    { filePath: repo("tools/workbench-live-e2e/lib/runtime-module-journal.js"),
      role: "journal", loadable: true, preexisting: true },
    { filePath: repo("tools/workbench-live-e2e/lib/evidence-artifact.js"),
      role: "journal_helper", loadable: true, preexisting: true },
    { filePath: process.execPath, role: "external_node_binary",
      loadable: false, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/run-live-journey.js"),
      role: "domain_runner", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/verify-live-journey.js"),
      role: "domain_verifier_entry", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/production-closure.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/common.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/control-channel.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/png-contract.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/cdp-client.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("launcher/perf/node_modules/playwright-core/lib/utilsBundle.js"),
      role: "mature_websocket_transport", loadable: true, preexisting: false },
    { filePath: repo("launcher/perf/node_modules/playwright-core/lib/utilsBundleImpl/index.js"),
      role: "mature_websocket_transport", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/cdp-passive-observer.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/evidence-verifier.js"),
      role: "domain_module", loadable: true, preexisting: false },
    { filePath: repo("tools/workbench-live-e2e/kshop/generic-opener.js"),
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
    ...(mode === "check" ? [
      { filePath: repo("tools/run-kshop-harness.js"),
        role: "offline_browser_harness_gate", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/kshop/browser-bootstrap.js"),
        role: "offline_browser_harness_bootstrap", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/kshop/browser-module-inventory.v1.json"),
        role: "offline_browser_module_inventory", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/kshop/browser-resource-inventory.v1.json"),
        role: "offline_browser_resource_inventory", loadable: false, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/lib/browser-child-resource-closure.js"),
        role: "offline_browser_resource_closure", loadable: false, preexisting: false },
      { filePath: repo("launcher/web/modules/kshop/dev/harness.html"),
        role: "offline_browser_harness_assertions", loadable: false, preexisting: false },
    ] : []),
    ...(auditProfile ? [
      { filePath: repo("tools/workbench-live-e2e/kshop/self-test.js"),
        role: "audit_test", loadable: true, preexisting: false },
      { filePath: repo("tools/workbench-live-e2e/kshop/fixtures/valid-bundle.js"),
        role: "audit_fixture", loadable: true, preexisting: false },
      { filePath: repo("launcher/web/modules/panel-runtime.js"),
        role: "production_contract_module", loadable: true, preexisting: false },
      { filePath: repo("launcher/web/modules/inventory-runtime.js"),
        role: "production_contract_module", loadable: true, preexisting: false },
    ] : []),
  ],
});
const controller = RuntimeModuleJournal.installRuntimeModuleJournal({ root, manifest });
const runner = require("./run-live-journey");
const verifier = require("./verify-live-journey");
controller.checkpoint("domain_loaded");
const admission = { manifest, controller, finished: false };

if (mode === "fixture") {
  const audit = require("./self-test");
  const smoke = audit.runAdmissionSmoke();
  controller.checkpoint("audit_executed");
  controller.seal("terminal");
  const journal = controller.reverifyAndRestore();
  process.stdout.write(JSON.stringify({ manifest, journal, smoke }));
  admission.finished = true;
} else if (mode === "verify") {
  try {
    const receiptArgs = ["--bundle", argv[1]];
    if (argv.length === 4) receiptArgs.push("--receipt", argv[3]);
    const prepared = verifier.prepare(receiptArgs);
    controller.checkpoint("verification_executed");
    controller.seal("terminal");
    const journal = controller.reverifyAndRestore();
    admission.finished = true;
    const verification = verifier.finalize(prepared);
    console.log(JSON.stringify({ receipt: verification.receipt,
      receiptPath: verification.receiptPath,
      verificationAdmission: journal.admissionStatus,
      verificationPhases: journal.checkpoints.map((entry) => entry.phase)
        .concat([journal.seal.phase]),
      moduleJournalSha256: journal.evidenceSha256 }, null, 2));
  } catch (error) {
    console.error(error && error.message || String(error));
    process.exitCode = error && error.isUsageError ? 2 : 1;
  }
} else if (mode === "check") {
  try {
    const checks = require("./self-test").runSelfTests();
    controller.checkpoint("audit_executed");
    controller.seal("terminal");
    const journal = controller.reverifyAndRestore();
    admission.finished = true;
    const Evidence = require("../lib/evidence-artifact");
    const receipt = { schema:"workbench-live-e2e.kshop.offline-check-receipt.v1",
      status: "OFFLINE_VERIFIED", liveStatus: "LIVE_BLOCKED",
      deployment: "NOT_DEPLOYED", checks: checks.passed,
      moduleAdmission: journal.admissionStatus,
      processExecutable: manifest.entries.find((entry) =>
        entry.role === "external_node_binary"),
      manifestSha256: manifest.manifestSha256,
      moduleJournalSha256: journal.evidenceSha256,
      childReceipts:checks.childReceipts };
    receipt.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(receipt));
    console.log(JSON.stringify(receipt, null, 2));
  } catch (error) {
    console.error(error && error.stack || error && error.message || String(error));
    process.exitCode = 1;
  }
} else {

  runner.main(argv, admission).then(() => {
    if (!admission.finished) {
      controller.seal("terminal");
      controller.reverifyAndRestore();
      admission.finished = true;
    }
  }).catch((error) => {
    console.error(error && error.message || String(error));
    process.exitCode = error && error.isUsageError ? 2 : 1;
  });
}
