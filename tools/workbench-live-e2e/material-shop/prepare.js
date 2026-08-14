"use strict";

const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Common = require("./common");
const Applicability = require("./applicability");
const Admission = require("./admission");
const ExternalToolchain = require("../lib/playwright-websocket-toolchain");
const Materialize = require("./materialize");
const Production = require("./production-closure");
const Protocol = require("./protocol");

const PREPARATION_SCHEMA = "workbench-live-e2e.material-shop.preparation.v2";

function readJson(filePath, phase) {
  const file = Evidence.readExactRegularFile(path.resolve(filePath), {
    phase: phase || "prepare", maximumBytes: 16 * 1024 * 1024,
  });
  try { return JSON.parse(file.bytes.toString("utf8").replace(/^\uFEFF/, "")); }
  catch (error) { Common.fail("material_shop_json_invalid", phase || "prepare", error.message); }
}

function writeJsonNew(filePath, value) {
  const output = path.resolve(filePath);
  const digest = Evidence.sha256Text(Evidence.canonicalJson(value));
  const staged = output + ".staged-" + digest.slice(0, 16);
  try {
    fs.writeFileSync(staged, JSON.stringify(value, null, 2) + "\n", {
      encoding: "utf8", mode: 0o600, flag: "wx",
    });
    fs.renameSync(staged, output);
  } catch (error) {
    if (fs.existsSync(staged)) fs.unlinkSync(staged);
    throw error;
  }
  const file = Evidence.readExactRegularFile(output, {
    phase: "prepare", maximumBytes: 64 * 1024 * 1024,
  });
  return { path: file.path, sha256: file.sha256, bytes: file.length };
}

function parseArgs(argv) {
  const args = {
    root: Common.CANONICAL_ROOT,
    runId: null,
    seedSlot: "cf7_agent_a5_material_shop_seed",
    targetSlot: "cf7_agent_a5_material_shop_run",
    recoverySlot: "cf7_agent_a5_material_shop_recovery",
    capabilityFile: null,
    allowCdpFallback: false,
    agentRuntimeJsonl: false,
    authorizePurchase: false,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    const take = () => {
      index += 1;
      if (index >= argv.length) Common.fail("material_shop_argument_missing", "prepare", token);
      return argv[index];
    };
    if (token === "--root") args.root = take();
    else if (token === "--run-id") args.runId = take();
    else if (token === "--seed-slot") args.seedSlot = take();
    else if (token === "--target-slot") args.targetSlot = take();
    else if (token === "--recovery-slot") args.recoverySlot = take();
    else if (token === "--environment-capability-file") args.capabilityFile = take();
    else if (token === "--allow-panel-cdp-input-fallback") args.allowCdpFallback = true;
    else if (token === "--agent-runtime-jsonl") args.agentRuntimeJsonl = true;
    else if (token === "--authorize-quantity-one-purchase") args.authorizePurchase = true;
    else Common.fail("material_shop_argument_unknown", "prepare", "unknown argument", { token });
  }
  const legacyComputerUse = args.agentRuntimeJsonl !== true;
  if (!Common.ID_RE.test(String(args.runId || ""))
      || legacyComputerUse && !args.capabilityFile
      || !legacyComputerUse && (args.capabilityFile || args.allowCdpFallback)
      || args.authorizePurchase !== true) {
    Common.fail("material_shop_prepare_arguments_invalid", "prepare",
      "run id and explicit quantity-one authorization are required; Agent Runtime JSONL forbids Computer Use capability and CDP fallback");
  }
  Common.assertDedicatedSlots(args.seedSlot, args.targetSlot, args.recoverySlot);
  if (args.agentRuntimeJsonl === true && args.targetSlot !== Protocol.AGENT_RUNTIME_SLOT) {
    Common.fail("material_shop_prepare_arguments_invalid", "prepare",
      "Agent Runtime JSONL requires the exact A5 target slot");
  }
  return args;
}

function assertCapability(value) {
  try { return Admission.validateEnvironmentCapability(value); }
  catch (error) {
    Common.fail("material_shop_capability_invalid", "prepare",
      "Computer Use environment capability failed its operator-attestation/raw-artifact validator", {
        cause: error && error.code || null,
      });
  }
}

function stablePreparation(value) {
  return {
    schema: value.schema, runId: value.runId, root: value.root,
    runDir: value.runDir, resourcesRoot: value.resourcesRoot,
    slots: value.slots, scopeSha256: value.scopeSha256,
    closureSha256: value.closureSha256,
    externalToolchainSha256: value.externalToolchainSha256,
    applicabilitySha256: value.applicabilitySha256,
    materializationSha256: value.materializationSha256,
    planSha256: value.planSha256, artifacts: value.artifacts,
    boundaries: value.boundaries,
  };
}

function prepare(options) {
  const settings = options || {};
  const root = Common.assertCanonicalRoot(settings.root || Common.CANONICAL_ROOT);
  const runId = String(settings.runId || "");
  if (!Common.ID_RE.test(runId)) Common.fail("material_shop_run_id_invalid", "prepare", "run id is invalid");
  const slots = Common.assertDedicatedSlots(settings.seedSlot,
    settings.targetSlot, settings.recoverySlot);
  const agentRuntimeJsonl = settings.agentRuntimeJsonl === true;
  if (agentRuntimeJsonl && (slots.targetSlot !== Protocol.AGENT_RUNTIME_SLOT
      || settings.allowCdpFallback === true || settings.capability != null)) {
    Common.fail("material_shop_agent_runtime_prepare_invalid", "prepare",
      "Agent Runtime JSONL preparation requires exact slot a5 and no CU/CDP capability");
  }
  const capability = agentRuntimeJsonl ? null : assertCapability(settings.capability);
  const closure = Production.captureProductionClosure(root);
  const base = path.resolve(root, Common.OWNED_BASE_RELATIVE);
  const resourcesRoot = path.join(base, "materialized", runId, "resources");
  // Once the full closure is sealed, reject an unsafe destination before any
  // other preparation probe or owned-directory side effect.
  Materialize.assertMaterializedPathBudget(resourcesRoot, closure.scope);
  const packageLock = closure.scope.files.find((entry) =>
    entry.relativePath === "launcher/perf/package-lock.json");
  if (!packageLock) Common.fail("material_shop_external_toolchain_lock_unbound", "prepare",
    "protected scope does not bind the canonical Playwright package lock");
  const externalToolchain = ExternalToolchain.captureDescriptor(root);
  ExternalToolchain.validateDescriptor(externalToolchain, root, {
    expectedPackageLock: packageLock,
  });
  const applicability = Applicability.captureCurrentDataApplicability(root, {
    appData: process.env.APPDATA,
  });
  const authorization = agentRuntimeJsonl
    ? Protocol.createAgentRuntimeAuthorization({
      evidenceMode: "candidate_capture",
      decisionId: runId + "-qty1",
      runId,
      applicabilitySha256: applicability.applicabilitySha256,
      target: applicability.selectedUnlockedTarget,
    })
    : Protocol.createAuthorization({
      evidenceMode: "candidate_capture", decisionId: runId + "-qty1",
    });
  if (!fs.existsSync(base)) fs.mkdirSync(base, { recursive: true });
  const runs = path.join(base, "runs");
  if (!fs.existsSync(runs)) fs.mkdirSync(runs);
  const runDir = path.join(runs, runId);
  if (fs.existsSync(runDir)) Common.fail("material_shop_run_exists", "prepare", "run directory already exists");
  fs.mkdirSync(runDir);
  const materialization = Materialize.materializeScope({
    root, sourceRoot: root, scope: closure.scope, destination: resourcesRoot,
    runDir,
  });
  const scopeBinding = {
    head: closure.head,
    scopeSha256: closure.scope.scopeSha256,
    closureSha256: closure.closureSha256,
    materializationSha256: materialization.materializationSha256,
  };
  const planOptions = {
    runId, evidenceMode: "candidate_capture",
    seedSlot: slots.seedSlot, targetSlot: slots.targetSlot,
    recoverySlot: slots.recoverySlot, scope: scopeBinding,
    applicability, authorization,
  };
  const plan = agentRuntimeJsonl
    ? Protocol.createAgentRuntimeControlPlan(planOptions)
    : Protocol.createControlPlan(Object.assign(planOptions, {
      environmentCapability: capability,
      allowPanelCdpFallback: settings.allowCdpFallback === true,
    }));
  const artifacts = {};
  artifacts.scope = writeJsonNew(path.join(runDir, "scope-manifest.json"), closure.scope);
  artifacts.closure = writeJsonNew(path.join(runDir, "production-closure.json"), closure);
  artifacts.materialization = writeJsonNew(path.join(runDir, "materialization.json"), materialization);
  artifacts.applicability = writeJsonNew(path.join(runDir, "applicability.json"), applicability);
  artifacts.authorization = writeJsonNew(path.join(runDir, "purchase-authorization.json"), authorization);
  artifacts.plan = writeJsonNew(path.join(runDir, "control-plan.json"), plan);
  artifacts.externalToolchain = writeJsonNew(
    path.join(runDir, "external-toolchain.json"), externalToolchain);
  Object.keys(artifacts).forEach((name) => {
    artifacts[name].relativePath = path.relative(runDir, artifacts[name].path).replace(/\\/g, "/");
    delete artifacts[name].path;
  });
  const value = {
    schema: PREPARATION_SCHEMA,
    createdAt: new Date().toISOString(),
    runId, root, runDir, resourcesRoot, slots,
    scopeSha256: closure.scope.scopeSha256,
    closureSha256: closure.closureSha256,
    externalToolchainSha256: externalToolchain.descriptorSha256,
    applicabilitySha256: applicability.applicabilitySha256,
    materializationSha256: materialization.materializationSha256,
    planSha256: plan.planSha256,
    artifacts,
    boundaries: { worktreeMaterialized: true, candidateBuilt: false,
      candidateExecuted: false, liveAdmission: plan.transportPolicy.liveAdmission,
      promoted: false, standardEntryVerified: false },
  };
  value.preparationSha256 = Evidence.sha256Text(Evidence.canonicalJson(stablePreparation(value)));
  Materialize.writeJsonAtomicNew(path.join(runDir, "preparation.json"), value);
  // The materialization producer remains active through every preparation artifact.
  // Only the complete preparation may archive the creation intent and producer lease.
  Materialize.resolveCreationIntent(runDir, materialization, closure.scope);
  return value;
}

function main() {
  try {
    const args = parseArgs(process.argv.slice(2));
    const capability = args.agentRuntimeJsonl
      ? null : assertCapability(readJson(args.capabilityFile, "prepare"));
    const value = prepare(Object.assign({}, args, { capability }));
    process.stdout.write(JSON.stringify({ ok: true, runDir: value.runDir,
      resourcesRoot: value.resourcesRoot, preparationSha256: value.preparationSha256 }) + "\n");
  } catch (error) {
    process.stderr.write(JSON.stringify(Common.publicError(error)) + "\n");
    process.exitCode = 1;
  }
}

if (require.main === module) main();

module.exports = {
  PREPARATION_SCHEMA,
  assertCapability,
  parseArgs,
  prepare,
  readJson,
  stablePreparation,
  writeJsonNew,
};
