#!/usr/bin/env node
"use strict";

const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { sha256OfValue } = require("./lib/arena-calibration-core");
const { writeJsonAtomic } = require("./lib/durable-campaign-journal");

const ROOT = path.resolve(__dirname, "../..");
const TARGET_PATH = "data/arena/arena_calibrated_rosters.json";
const BUNDLE_SCHEMA = "arena-calibration.production-recommendation-bundle.v1";

function fail(message) {
  const error = new Error(message);
  error.isUsageError = true;
  throw error;
}

function parseArgs(argv) {
  const args = { bundle: null, approval: null, check: false, help: false };
  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === "--bundle") args.bundle = argv[++index];
    else if (token === "--approve-bundle-hash") args.approval = argv[++index];
    else if (token === "--check") args.check = true;
    else if (token === "--help" || token === "-h") args.help = true;
    else fail(`unknown argument: ${token}`);
  }
  return args;
}

function printHelp() {
  console.log(`Usage: node tools/arena-calibration/apply-production-recommendation.js [options]

  --bundle <recommendation-bundle.json>
  --approve-bundle-hash <sha256:...>
  [--check]

Applies only the exact hash-approved recommendation. The command verifies the
base file, proposed catalog, implementation closure and current Git revision,
then runs the declared production consumers. Any verification failure restores
the exact pre-apply bytes. There is no force or skip-verification mode.
`);
}

function resolveInsideRoot(value, label, mustExist = true) {
  if (!value) fail(`${label} is required`);
  const resolved = path.resolve(ROOT, value);
  const relative = path.relative(ROOT, resolved);
  if (relative.startsWith("..") || path.isAbsolute(relative)) fail(`${label} is outside project root`);
  if (mustExist && !fs.existsSync(resolved)) fail(`${label} does not exist: ${value}`);
  return resolved;
}

function relative(filePath) {
  return path.relative(ROOT, filePath).replace(/\\/g, "/");
}

function sha256Buffer(value) {
  return `sha256:${crypto.createHash("sha256").update(value).digest("hex")}`;
}

function withoutHash(value, field) {
  const clone = JSON.parse(JSON.stringify(value));
  delete clone[field];
  return clone;
}

function assertHash(value, label) {
  if (!/^sha256:[0-9a-f]{64}$/.test(String(value || ""))) fail(`${label} is not a canonical sha256 value`);
}

function validateClosure(closure) {
  if (!closure || !Array.isArray(closure.files) || closure.files.length === 0) {
    fail("implementationClosure.files is required");
  }
  assertHash(closure.closureHash, "implementationClosure.closureHash");
  const actualFiles = closure.files.map((entry) => {
    if (!entry || typeof entry.path !== "string") fail("implementation closure entry has no path");
    assertHash(entry.sha256, `implementation closure ${entry.path}`);
    const filePath = resolveInsideRoot(entry.path, `implementation closure ${entry.path}`);
    const actualSha256 = sha256Buffer(fs.readFileSync(filePath));
    if (actualSha256 !== entry.sha256) {
      fail(`implementation closure drift: ${entry.path} expected ${entry.sha256}, got ${actualSha256}`);
    }
    return { path: relative(filePath), sha256: actualSha256 };
  });
  const actualClosureHash = sha256OfValue(actualFiles);
  if (actualClosureHash !== closure.closureHash) {
    fail(`implementation closure hash mismatch: expected ${closure.closureHash}, got ${actualClosureHash}`);
  }
  return actualFiles;
}

function validateCatalog(bytes, bundle) {
  let catalog;
  try {
    catalog = JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(`replacement catalog is not JSON: ${error.message}`);
  }
  if (!catalog || Array.isArray(catalog) || catalog.schemaVersion !== 1 || catalog.active !== true) {
    fail("replacement catalog must be an active schemaVersion=1 object");
  }
  if (!Array.isArray(catalog.rosters) || catalog.rosters.length === 0) fail("replacement catalog has no rosters");
  assertHash(catalog.catalogHash, "replacement catalogHash");
  const actualCatalogHash = sha256OfValue(withoutHash(catalog, "catalogHash"));
  if (actualCatalogHash !== catalog.catalogHash) {
    fail(`replacement catalog hash mismatch: expected ${catalog.catalogHash}, got ${actualCatalogHash}`);
  }
  if (bundle.recommendation.activeRosterCount !== catalog.rosters.length) {
    fail("replacement roster count does not match recommendation");
  }
  return catalog;
}

function validateBundle(bundle, approvedHash) {
  if (!bundle || Array.isArray(bundle) || bundle.schema !== BUNDLE_SCHEMA) fail("unsupported recommendation bundle schema");
  if (bundle.state !== "AWAITING_HUMAN_APPROVAL") fail(`bundle is not awaiting approval: ${bundle.state}`);
  assertHash(bundle.bundleHash, "bundleHash");
  const actualBundleHash = sha256OfValue(withoutHash(bundle, "bundleHash"));
  if (actualBundleHash !== bundle.bundleHash) {
    fail(`bundle hash mismatch: expected ${bundle.bundleHash}, got ${actualBundleHash}`);
  }
  if (!approvedHash) fail("--approve-bundle-hash is required for formal apply");
  if (approvedHash !== bundle.bundleHash) {
    fail(`human approval hash mismatch: approved ${approvedHash}, bundle is ${bundle.bundleHash}`);
  }
  if (!bundle.target || bundle.target.path !== TARGET_PATH || bundle.target.symbol !== "root calibrated roster catalog") {
    fail("bundle target is not the calibrated roster root catalog");
  }
  if (!bundle.patch || bundle.patch.operation !== "replace_file_exact") fail("bundle patch operation is not replace_file_exact");
  if (!bundle.rollback || bundle.rollback.operation !== "replace_file_exact") fail("bundle rollback operation is not replace_file_exact");
  assertHash(bundle.target.baseSha256, "target.baseSha256");
  assertHash(bundle.patch.expectedBaseSha256, "patch.expectedBaseSha256");
  assertHash(bundle.patch.replacementSha256, "patch.replacementSha256");
  assertHash(bundle.rollback.expectedAppliedSha256, "rollback.expectedAppliedSha256");
  assertHash(bundle.rollback.replacementSha256, "rollback.replacementSha256");
  if (bundle.target.baseSha256 !== bundle.patch.expectedBaseSha256
      || bundle.target.baseSha256 !== bundle.rollback.replacementSha256
      || bundle.patch.replacementSha256 !== bundle.rollback.expectedAppliedSha256) {
    fail("bundle base/apply/rollback hashes do not close");
  }
}

function atomicReplace(filePath, bytes) {
  const temporary = `${filePath}.apply-${process.pid}-${Date.now()}.tmp`;
  const descriptor = fs.openSync(temporary, "wx");
  try {
    fs.writeFileSync(descriptor, bytes);
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  try {
    fs.renameSync(temporary, filePath);
  } finally {
    if (fs.existsSync(temporary)) fs.unlinkSync(temporary);
  }
}

function runCommand(name, executable, args) {
  const started = Date.now();
  console.log(`[arena-production-apply] verify ${name}`);
  const result = childProcess.spawnSync(executable, args, {
    cwd: ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    windowsHide: true,
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${name} failed with exit code ${result.status}`);
  return { name, exitCode: result.status, durationMs: Date.now() - started };
}

function runVerification() {
  const results = [];
  results.push(runCommand("recommendation contract", process.execPath,
    ["tools/arena-calibration/build-production-recommendation.js", "--check"]));
  results.push(runCommand("arena web syntax: preview", process.execPath,
    ["--check", "launcher/web/modules/arena/arena-preview-authority.js"]));
  results.push(runCommand("arena web syntax: commit", process.execPath,
    ["--check", "launcher/web/modules/arena/arena-challenge-browser.js"]));
  const dotnetCommand = [
    "$ErrorActionPreference = 'Stop'",
    "chcp.com 65001 | Out-Null",
    ". .\\launcher\\resolve-dotnet.ps1",
    "$cf7Dotnet = Resolve-Cf7Dotnet -ProjectRoot (Get-Location).Path",
    "& $cf7Dotnet test launcher/tests/Launcher.Tests.csproj --filter FullyQualifiedName~ArenaAuthorityCatalogTests --no-restore --verbosity minimal",
    "if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }",
  ].join("; ");
  results.push(runCommand("Host calibrated roster authority", "powershell.exe",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", dotnetCommand]));
  results.push(runCommand("arena browser harness", process.execPath,
    ["tools/run-arena-harness.js"]));
  results.push(runCommand("arena live E2E contract syntax", process.execPath,
    ["--check", "tools/workbench-live-e2e/arena-live-e2e.js"]));
  results.push(runCommand("arena live E2E self-test syntax", process.execPath,
    ["--check", "tools/workbench-live-e2e/arena-live-e2e.self-test.js"]));
  results.push(runCommand("documentation governance", process.execPath,
    ["tools/validate-doc-governance.js"]));
  return results;
}

function acquireLock(bundlePath) {
  const lockPath = `${bundlePath}.apply.lock`;
  const descriptor = fs.openSync(lockPath, "wx");
  try {
    fs.writeFileSync(descriptor, JSON.stringify({ pid: process.pid, openedAt: new Date().toISOString() }) + "\n", "utf8");
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
  return lockPath;
}

function formalApply(args) {
  const bundlePath = resolveInsideRoot(args.bundle, "bundle");
  const bundle = JSON.parse(fs.readFileSync(bundlePath, "utf8"));
  validateBundle(bundle, args.approval);
  const currentRevision = childProcess.execFileSync("git", ["rev-parse", "HEAD"], { cwd: ROOT, encoding: "utf8" }).trim();
  if (currentRevision !== bundle.sourceRevision || currentRevision !== bundle.target.sourceRevision) {
    fail(`Git revision drift: bundle ${bundle.sourceRevision}, current ${currentRevision}`);
  }
  validateClosure(bundle.implementationClosure);

  const targetPath = resolveInsideRoot(bundle.target.path, "target");
  const proposedPath = resolveInsideRoot(bundle.patch.replacementPath, "replacement");
  const rollbackPath = resolveInsideRoot(bundle.rollback.replacementPath, "rollback replacement");
  const baseBytes = fs.readFileSync(targetPath);
  const proposedBytes = fs.readFileSync(proposedPath);
  const rollbackBytes = fs.readFileSync(rollbackPath);
  const actualBaseSha256 = sha256Buffer(baseBytes);
  const actualProposedSha256 = sha256Buffer(proposedBytes);
  if (actualBaseSha256 !== bundle.target.baseSha256) {
    fail(`base hash drift: expected ${bundle.target.baseSha256}, got ${actualBaseSha256}`);
  }
  if (actualProposedSha256 !== bundle.patch.replacementSha256) {
    fail(`replacement hash mismatch: expected ${bundle.patch.replacementSha256}, got ${actualProposedSha256}`);
  }
  if (sha256Buffer(rollbackBytes) !== actualBaseSha256 || !rollbackBytes.equals(baseBytes)) {
    fail("rollback bytes do not exactly equal the current base file");
  }
  const catalog = validateCatalog(proposedBytes, bundle);

  const lockPath = acquireLock(bundlePath);
  const receiptPath = path.join(path.dirname(bundlePath), "apply-receipt.json");
  const intentPath = path.join(path.dirname(bundlePath), "apply-intent.json");
  let applied = false;
  try {
    writeJsonAtomic(intentPath, {
      schema: "arena-calibration.production-apply-intent.v1",
      state: "APPLYING",
      bundleHash: bundle.bundleHash,
      targetPath: TARGET_PATH,
      baseSha256: actualBaseSha256,
      proposedSha256: actualProposedSha256,
      startedAt: new Date().toISOString(),
    });
    atomicReplace(targetPath, proposedBytes);
    applied = true;
    if (sha256Buffer(fs.readFileSync(targetPath)) !== actualProposedSha256) {
      throw new Error("post-apply target hash mismatch");
    }
    const verification = runVerification();
    if (sha256Buffer(fs.readFileSync(targetPath)) !== actualProposedSha256) {
      throw new Error("verification changed the calibrated roster target");
    }
    const receipt = {
      schema: "arena-calibration.production-apply-receipt.v1",
      state: "APPLIED_VERIFIED",
      bundleHash: bundle.bundleHash,
      sourceRevision: currentRevision,
      targetPath: TARGET_PATH,
      baseSha256: actualBaseSha256,
      appliedSha256: actualProposedSha256,
      catalogHash: catalog.catalogHash,
      activeRosterCount: catalog.rosters.length,
      implementationClosureHash: bundle.implementationClosure.closureHash,
      verification,
      completedAt: new Date().toISOString(),
      receiptHash: "",
    };
    receipt.receiptHash = sha256OfValue(withoutHash(receipt, "receiptHash"));
    writeJsonAtomic(receiptPath, receipt);
    writeJsonAtomic(intentPath, { ...receipt, state: "COMPLETED" });
    console.log(JSON.stringify({ ok: true, receiptPath: relative(receiptPath), ...receipt }, null, 2));
  } catch (error) {
    if (applied) {
      const currentHash = sha256Buffer(fs.readFileSync(targetPath));
      if (currentHash !== actualProposedSha256) {
        throw new Error(`verification failed and rollback refused because target drifted to ${currentHash}; original error: ${error.message}`);
      }
      atomicReplace(targetPath, baseBytes);
      if (sha256Buffer(fs.readFileSync(targetPath)) !== actualBaseSha256) {
        throw new Error(`verification failed and rollback hash did not restore; original error: ${error.message}`);
      }
      writeJsonAtomic(intentPath, {
        schema: "arena-calibration.production-apply-intent.v1",
        state: "ROLLED_BACK",
        bundleHash: bundle.bundleHash,
        targetPath: TARGET_PATH,
        baseSha256: actualBaseSha256,
        proposedSha256: actualProposedSha256,
        failedAt: new Date().toISOString(),
        error: error.message,
      });
    }
    throw error;
  } finally {
    if (fs.existsSync(lockPath)) fs.unlinkSync(lockPath);
  }
}

function runCheck() {
  const sample = { schema: BUNDLE_SCHEMA, state: "AWAITING_HUMAN_APPROVAL", bundleHash: "" };
  sample.bundleHash = sha256OfValue(withoutHash(sample, "bundleHash"));
  assertHash(sample.bundleHash, "self-check bundleHash");
  const bytes = Buffer.from("arena-calibration-production-apply", "utf8");
  assertHash(sha256Buffer(bytes), "self-check byte hash");
  console.log(JSON.stringify({
    ok: true,
    check: "arena-production-apply-contract",
    exactHumanBundleHashRequired: true,
    forceMode: false,
    rollbackOnVerificationFailure: true,
    formalWrite: false,
  }, null, 2));
}

function main(argv) {
  const args = parseArgs(argv);
  if (args.help) return printHelp();
  if (args.check) return runCheck();
  formalApply(args);
}

if (require.main === module) {
  try {
    main(process.argv.slice(2));
  } catch (error) {
    console.error(error.stack || error.message);
    process.exit(error.isUsageError ? 2 : 1);
  }
}

module.exports = { parseArgs, validateBundle, validateCatalog };
