"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const test = require("node:test");
const CloneGuard = require("../lib/clone-save-guard");
const Evidence = require("../lib/evidence-artifact");
const Adapter = require("./admit-post-release-finalization");
const Build = require("./build-candidate");
const Common = require("./common");
const Finalize = require("./finalize-clone-release");

function seal(value, key) {
  const output = Object.assign({}, value);
  output[key] = Evidence.sha256Text(Evidence.canonicalJson(value));
  return output;
}

function absentCloneInspection(root, slot) {
  return seal({ schema: "workbench-live-e2e.clone-lock-inspection.v1",
    apiVersion: CloneGuard.API_VERSION, observedAt: "2026-08-13T12:00:00.000Z", slot,
    lockPath: path.join(root, "tmp", "workbench-live-e2e", "locks", slot + ".clone.lock"),
    lockPresent: false, recordSha256: null, ownerPid: null,
    ownerProcessStartUtcTicks: null, observedProcessStartUtcTicks: null,
    ownerState: "absent", recoveryPresent: false, recoveryStatus: null,
    recoveryRecordSha256: null }, "evidenceSha256");
}

function frozenContinuationContext() {
  return { preparation: { runId: Adapter.RUN_ID,
    preparationSha256: "c21aa7e18d6af758fd6d2d4f8a914566497de60ff585c0c59af1d7031a760598",
    runDir: path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
      "runs", Adapter.RUN_ID),
    resourcesRoot: path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
      "materialized", Adapter.RUN_ID, "resources"),
    slots: { seedSlot: "cf7_agent_a5_material_shop_seed",
      targetSlot: "cf7_agent_a5_material_shop_run",
      recoverySlot: "cf7_agent_a5_material_shop_recovery" } },
  plan: { runId: Adapter.RUN_ID } };
}

test("t1903 adapter is a single frozen migration case", () => {
  assert.strictEqual(Adapter.MIGRATION_CASE_ID,
    "a5-material-shop-agent-20260813t1903-post-release-v1");
  assert.strictEqual(Adapter.RUN_ID, "a5-material-shop-agent-20260813t1903");
  assert.strictEqual(Adapter.ELIGIBILITY_SCHEMA,
    "workbench-live-e2e.material-shop.post-release-finalization-eligibility.v1");
  assert.strictEqual(Adapter.PROTECTED_SCOPE_BOOTSTRAP_SCHEMA,
    "workbench-live-e2e.material-shop.post-release-protected-scope-bootstrap.v1");
});

test("eligibility artifact name is content-addressed", () => {
  assert.strictEqual(Adapter.eligibilityFileName("a".repeat(64)),
    "post-release-finalization-eligibility-aaaaaaaaaaaaaaaa.json");
  assert.throws(() => Adapter.eligibilityFileName("short"));
});

test("finalization adapter rejects incomplete CLI input", () => {
  assert.throws(() => Adapter.parseArgs(["--preparation", "one"]));
  assert.throws(() => Adapter.parseArgs(["--foreign", "one"]));
});

test("fresh inspection is exact, digest-bound, and proves one absent clone", () => {
  const root = path.join(os.tmpdir(), "a5-finalization-inspection-root");
  const slot = "cf7_agent_a5_material_shop_run";
  const inspection = absentCloneInspection(root, slot);
  const fresh = seal({ observedAt: "2026-08-13T12:01:00.000Z",
    launcherProcessCount: 0, cloneInspection: inspection }, "evidenceSha256");
  assert.strictEqual(Adapter.validateFreshInspection(fresh, root, slot), fresh);
  assert.throws(() => Adapter.validateFreshInspection(
    Object.assign({}, fresh, { launcherProcessCount: 1 }), root, slot));
  assert.throws(() => Adapter.validateFreshInspection(
    Object.assign({}, fresh, { foreign: true }), root, slot));
  const owned = Object.assign({}, inspection, { ownerState: "alive", ownerPid: 42 });
  owned.evidenceSha256 = Evidence.sha256Text(Evidence.canonicalJson(
    Object.fromEntries(Object.entries(owned).filter(([key]) => key !== "evidenceSha256"))));
  const drift = seal({ observedAt: fresh.observedAt, launcherProcessCount: 0,
    cloneInspection: owned }, "evidenceSha256");
  assert.throws(() => Adapter.validateFreshInspection(drift, root, slot));
});

test("admission artifact state reuses one eligibility and one required marker", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-admission-state-"));
  const eligibility = "post-release-finalization-eligibility-" + "a".repeat(16) + ".json";
  try {
    fs.writeFileSync(path.join(root, eligibility), "{}\n");
    fs.writeFileSync(path.join(root, "release-finalization-required.json"), "{}\n");
    assert.deepStrictEqual(Adapter.admissionArtifactState(root), {
      names: [eligibility, "release-finalization-required.json"].sort(),
      eligibilityName: eligibility, requiredMarkerPresent: true,
    });
    assert.doesNotThrow(() => Adapter.assertNoLaterArtifacts(root, eligibility, true));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("admission rejects multiple eligibility, removal intent, and staged finalization", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-admission-negative-"));
  try {
    fs.writeFileSync(path.join(root,
      "post-release-finalization-eligibility-" + "a".repeat(16) + ".json"), "{}\n");
    fs.writeFileSync(path.join(root,
      "post-release-finalization-eligibility-" + "b".repeat(16) + ".json"), "{}\n");
    assert.throws(() => Adapter.admissionArtifactState(root));
    fs.rmSync(root, { recursive: true, force: true });
    fs.mkdirSync(root);
    fs.writeFileSync(path.join(root, "worktree-removal-intent.json"), "{}\n");
    assert.throws(() => Adapter.assertNoLaterArtifacts(root, null, false));
    fs.unlinkSync(path.join(root, "worktree-removal-intent.json"));
    fs.writeFileSync(path.join(root,
      "release-finalization-required.json.staged-" + "c".repeat(16)), "{}\n");
    assert.throws(() => Adapter.assertNoLaterArtifacts(root, null, false));
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("operation history admits exactly one matching terminal and zero stale records", () => {
  const lease = { leaseSha256: "1".repeat(64) };
  const terminal = { archiveName: "run-operation-terminal-" + "1".repeat(16) + ".json",
    archiveBytes: 123, archiveSha256: "2".repeat(64) };
  const matching = { name: terminal.archiveName, kind: "terminal", bytes: 123,
    sha256: terminal.archiveSha256, lease };
  assert.strictEqual(Adapter.validateOperationHistoryEntries([matching], terminal, lease), matching);
  assert.throws(() => Adapter.validateOperationHistoryEntries(
    [matching, Object.assign({}, matching, { name: "run-operation-terminal-" +
      "3".repeat(16) + ".json" })], terminal, lease));
  assert.throws(() => Adapter.validateOperationHistoryEntries(
    [Object.assign({}, matching, { kind: "stale_recovery" })], terminal, lease));
});

test("all unbound recovery blocker names remain fenced", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-unbound-blocker-"));
  try {
    fs.writeFileSync(path.join(root, "recovery-blocker-foreign.json"), "{}\n");
    fs.writeFileSync(path.join(root, "Recovery-Blocker-NearMatch.json"), "{}\n");
    assert.deepStrictEqual(Finalize.unresolvedBlockerFiles(root, null, null),
      ["Recovery-Blocker-NearMatch.json", "recovery-blocker-foreign.json"]);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("adapter wiring binds materialize and only reuses frozen persisted admission artifacts", () => {
  const source = fs.readFileSync(path.join(__dirname,
    "admit-post-release-finalization.js"), "utf8");
  assert(source.includes('"tools/workbench-live-e2e/material-shop/materialize.js"'));
  const state = source.indexOf("const state = validateFrozenAdmissionState(");
  const readEligibility = source.indexOf("const eligibility = readEligibility(", state);
  const readMarker = source.indexOf("const existing = Prepare.readJson(markerPath", state);
  assert(state >= 0 && readEligibility > state && readMarker > readEligibility);
  const bodyEnd = source.indexOf("function parseArgs(", state);
  const body = source.slice(state, bodyEnd);
  assert(!body.includes("createEligibility(context)"));
  assert(!body.includes("createFinalizationBlocker(context"));
  assert(!body.includes("writeAtomicNew("));
  assert(source.includes("Evidence.canonicalJson(value.officialInspectReceipt.value)"));
});

test("frozen admission cannot recreate either immutable artifact", () => {
  const valid = { eligibilityName: Adapter.FROZEN_ELIGIBILITY_NAME,
    requiredMarkerPresent: true };
  assert.strictEqual(Adapter.validateFrozenAdmissionState(valid), valid);
  assert.throws(() => Adapter.validateFrozenAdmissionState({
    eligibilityName: null, requiredMarkerPresent: true,
  }));
  assert.throws(() => Adapter.validateFrozenAdmissionState({
    eligibilityName: Adapter.FROZEN_ELIGIBILITY_NAME, requiredMarkerPresent: false,
  }));
  assert.throws(() => Adapter.validateFrozenAdmissionState({
    eligibilityName: "post-release-finalization-eligibility-" + "f".repeat(16) + ".json",
    requiredMarkerPresent: true,
  }));
});

test("frozen bootstrap applies only to the exact t1903 preparation identity", () => {
  const runDir = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "runs", Adapter.RUN_ID);
  const resourcesRoot = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE,
    "materialized", Adapter.RUN_ID, "resources");
  const preparation = { runId: Adapter.RUN_ID,
    preparationSha256: "c21aa7e18d6af758fd6d2d4f8a914566497de60ff585c0c59af1d7031a760598",
    runDir, resourcesRoot, slots: { seedSlot: "cf7_agent_a5_material_shop_seed",
      targetSlot: "cf7_agent_a5_material_shop_run",
      recoverySlot: "cf7_agent_a5_material_shop_recovery" } };
  assert.strictEqual(Adapter.validateBootstrapPreparation(preparation, false), true);
  assert.throws(() => Adapter.validateBootstrapPreparation(
    Object.assign({}, preparation, { preparationSha256: "f".repeat(64) }), true));
  assert.strictEqual(Adapter.captureProtectedScopeBootstrap(
    { runId: "material-shop-unrelated-run" }, { optional: true }), null);
});

test("ordinary build options remain byte-shape compatible and cannot accept a bare supplement", () => {
  const preparation = { runId: "material-shop-unrelated-run", slots: {
    seedSlot: "cf7_agent_a5_material_shop_seed", targetSlot: "cf7_agent_a5_material_shop_run",
    recoverySlot: "cf7_agent_a5_material_shop_recovery" } };
  const candidateRoot = path.join(os.tmpdir(), "ordinary-a5-candidate");
  assert.deepStrictEqual(Build.protectedScopeOptions(preparation, candidateRoot), {
    runId: preparation.runId, seedSlot: preparation.slots.seedSlot,
    targetSlot: preparation.slots.targetSlot, recoverySlot: preparation.slots.recoverySlot,
    candidateRoot,
  });
  assert.throws(() => Build.protectedScopeOptions(preparation, candidateRoot, {
    supplementalGeneratedOutputs: [],
  }));
  assert.throws(() => Build.protectedScopeOptions(preparation, candidateRoot, {
    protectedScopeBootstrap: {},
  }));
});

test("bootstrap wiring is ephemeral and full marker/release validation remains downstream", () => {
  const buildSource = fs.readFileSync(path.join(__dirname, "build-candidate.js"), "utf8");
  const adapterSource = fs.readFileSync(path.join(__dirname,
    "admit-post-release-finalization.js"), "utf8");
  const finalizerSource = fs.readFileSync(path.join(__dirname,
    "finalize-clone-release.js"), "utf8");
  const acceptSource = fs.readFileSync(path.join(__dirname, "accept-run.js"), "utf8");
  const buildValidator = buildSource.indexOf("adapter.validateProtectedScopeBootstrap");
  const supplement = buildSource.indexOf("value.supplementalGeneratedOutputs", buildValidator);
  assert(buildValidator >= 0 && supplement > buildValidator);
  assert(!buildSource.includes("options.supplementalGeneratedOutputs"));
  assert(adapterSource.includes('"tools/workbench-live-e2e/material-shop/build-candidate.js"'));
  assert(adapterSource.includes(
    "Finalize.loadContext(args, { allowFrozenPostReleaseBootstrap: true })"));
  const finalizerMain = finalizerSource.indexOf("function main()");
  const bootstrapContext = finalizerSource.indexOf(
    "loadContext(args, { allowFrozenPostReleaseBootstrap: true })", finalizerMain);
  const strictMarker = finalizerSource.indexOf("loadFinalizationMarker(", bootstrapContext);
  const receiptWrite = finalizerSource.indexOf("writeReleaseReceipt(", strictMarker);
  assert(bootstrapContext > finalizerMain && strictMarker > bootstrapContext
    && receiptWrite > strictMarker);
  const acceptLoad = acceptSource.indexOf("function loadContext(options)");
  const acceptBootstrap = acceptSource.indexOf("captureProtectedScopeBootstrap(", acceptLoad);
  const acceptBuild = acceptSource.indexOf("Build.loadBuildReceipt(", acceptBootstrap);
  const releaseValidation = acceptSource.indexOf("validateCloneRelease(", acceptBuild);
  const blockerValidation = acceptSource.indexOf("unresolvedBlockerFiles(", releaseValidation);
  assert(acceptBootstrap > acceptLoad && acceptBuild > acceptBootstrap
    && releaseValidation > acceptBuild && blockerValidation > releaseValidation);
});

test("frozen t1903 eligibility preserves its historical five-program descriptor bytes", () => {
  assert.strictEqual(Adapter.FROZEN_ELIGIBILITY_NAME,
    "post-release-finalization-eligibility-85e2fddba8152861.json");
  assert.strictEqual(Adapter.FROZEN_ELIGIBILITY_BYTES, 10589);
  assert.strictEqual(Adapter.FROZEN_ELIGIBILITY_FILE_SHA256,
    "e35a364588cdca191015d20df53062bb2d88a5c3783a6835a4b8105ed2263f08");
  assert.strictEqual(Adapter.FROZEN_REQUIRED_BLOCKER_BYTES, 15610);
  assert.strictEqual(Adapter.FROZEN_REQUIRED_BLOCKER_FILE_SHA256,
    "b31726ac4db16c171a88750c1e8f694bc21c60b33cada6f7f5f7b642b6d4c622");
  assert.strictEqual(Adapter.FROZEN_CURRENT_PROGRAMS.length, 5);
  assert.strictEqual(Evidence.sha256Text(Evidence.canonicalJson(
    Adapter.FROZEN_CURRENT_PROGRAMS)), Adapter.FROZEN_CURRENT_PROGRAMS_SHA256);
  assert.strictEqual(Adapter.validateFrozenProgramDescriptors(
    Adapter.FROZEN_CURRENT_PROGRAMS), Adapter.FROZEN_CURRENT_PROGRAMS);
  const drift = JSON.parse(JSON.stringify(Adapter.FROZEN_CURRENT_PROGRAMS));
  drift[3].sha256 = "f".repeat(64);
  assert.throws(() => Adapter.validateFrozenProgramDescriptors(drift));
});

test("release v4 is one nested t1903 continuation while legacy v3 stays distinct", () => {
  assert.strictEqual(Finalize.RELEASE_SCHEMA,
    "workbench-live-e2e.material-shop.clone-release.v4");
  assert.strictEqual(Finalize.LEGACY_RELEASE_SCHEMA,
    "workbench-live-e2e.material-shop.clone-release.v3");
  assert.strictEqual(Finalize.CONTINUATION_MIGRATION_CASE_ID,
    "a5-material-shop-agent-20260813t1903-ordinal-inventory-v1");
  const blocker = { blockerSha256: Adapter.FROZEN_REQUIRED_BLOCKER_SHA256,
    cleanupResult: { postReleaseEligibility: {
      eligibilitySha256: Adapter.FROZEN_ELIGIBILITY_SHA256,
    } } };
  assert.strictEqual(Finalize.isFrozenContinuationBlocker(blocker), true);
  assert.strictEqual(Finalize.isFrozenContinuationBlocker(Object.assign({}, blocker, {
    blockerSha256: "f".repeat(64),
  })), false);
});

test("exact t1903 context forces frozen v4 independently of marker claims", () => {
  const context = frozenContinuationContext();
  assert.strictEqual(Finalize.requiresFrozenContinuation(context), true);
  const exact = { blockerSha256: Adapter.FROZEN_REQUIRED_BLOCKER_SHA256,
    cleanupResult: { postReleaseEligibility: {
      eligibilitySha256: Adapter.FROZEN_ELIGIBILITY_SHA256,
    } } };
  assert.strictEqual(Finalize.validateFrozenContinuationBlockerIdentity(
    context, exact), exact);
  const alternate = JSON.parse(JSON.stringify(exact));
  alternate.blockerSha256 = "f".repeat(64);
  assert.throws(() => Finalize.validateFrozenContinuationBlockerIdentity(
    context, alternate));
  assert.throws(() => Finalize.requiresFrozenContinuation({
    preparation: Object.assign({}, context.preparation, {
      preparationSha256: "f".repeat(64),
    }), plan: context.plan,
  }));
  assert.strictEqual(Finalize.requiresFrozenContinuation({
    preparation: { runId: "ordinary-run" }, plan: { runId: "ordinary-run" },
  }), false);
});

test("ordinal witness projection is locale-independent", () => {
  const inventory = { files: ["DIPS", "DawnGraphiteCache/data_0", "lower"]
    .map((relativePath) => ({ relativePath })) };
  const projection = Finalize.projectOrdinalInventoryWitness(inventory);
  assert.strictEqual(projection.fileCount, 3);
  assert.strictEqual(projection.sourceOrderIsOrdinal, true);
  assert.deepStrictEqual(Object.keys(projection).sort(),
    ["fileCount", "ordinalPathsSha256", "sourceOrderIsOrdinal"].sort());
  assert.strictEqual(Finalize.ORDINAL_WITNESS_FILE_COUNT, 456);
  assert.strictEqual(Finalize.ORDINAL_WITNESS_PATHS_SHA256,
    "435be00593d891e0ef488eacc4c71cd42dcadd3b37a06b27611643e87da546a3");
});

test("continuation receipt seals current programs, ordinal witness, and inventory before release", () => {
  const source = fs.readFileSync(path.join(__dirname, "finalize-clone-release.js"), "utf8");
  const create = source.indexOf("function createContinuationEvidence(");
  const programs = source.indexOf("continuationProgramClosure()", create);
  const witness = source.indexOf("createOrdinalInventoryWitness(ignoredOutputInventory)", create);
  const inventory = source.indexOf("ignoredOutputInventorySha256:", create);
  const continuationSeal = source.indexOf("value.continuationSha256 =", create);
  const releaseSeal = source.indexOf("value.releaseSha256 =", continuationSeal);
  assert(create >= 0 && programs > create && witness > programs && inventory > witness
    && continuationSeal > inventory && releaseSeal > continuationSeal);
  assert(source.includes("the frozen t1903 ordinal migration cannot be represented by a legacy v3 release"));
  assert(source.includes("value.continuationEvidence.cloneInspection.evidenceSha256"));
  const resume = source.indexOf("function resumeStagedReleaseReceipt(");
  const validateStage = source.indexOf("validateReleaseReceipt(", resume);
  const renameStage = source.indexOf("fs.renameSync(staged, output)", validateStage);
  assert(resume >= 0 && validateStage > resume && renameStage > validateStage);
});

test("continuation program closure is explicit, ordinal, bounded, and complete", () => {
  assert.strictEqual(Finalize.CONTINUATION_PROGRAM_FILES.length, 38);
  assert.deepStrictEqual(Finalize.CONTINUATION_PROGRAM_FILES,
    Finalize.CONTINUATION_PROGRAM_FILES.slice().sort((left, right) =>
      left < right ? -1 : left > right ? 1 : 0));
  assert.strictEqual(new Set(Finalize.CONTINUATION_PROGRAM_FILES).size, 38);
  const closure = Finalize.continuationProgramClosure();
  assert.strictEqual(closure.fileCount, 38);
  assert.strictEqual(closure.files.length, 38);
  assert.strictEqual(closure.filesSha256,
    Evidence.sha256Text(Evidence.canonicalJson(closure.files)));
  assert.deepStrictEqual(closure.files.map((entry) => entry.relativePath),
    Finalize.CONTINUATION_PROGRAM_FILES);
  const discovered = new Set();
  const pending = ["tools/workbench-live-e2e/material-shop/admit-post-release-finalization.js",
    "tools/workbench-live-e2e/material-shop/finalize-clone-release.js"];
  while (pending.length) {
    const relativePath = pending.shift();
    if (discovered.has(relativePath)) continue;
    discovered.add(relativePath);
    const source = fs.readFileSync(path.join(Common.CANONICAL_ROOT,
      relativePath.replace(/\//g, path.sep)), "utf8");
    const pattern = /require\(\s*["'](\.{1,2}\/[^"']+)["']\s*\)/g;
    let match;
    while ((match = pattern.exec(source))) {
      let child = path.posix.normalize(path.posix.join(
        path.posix.dirname(relativePath), match[1].replace(/\\/g, "/")));
      if (!path.posix.extname(child)) child += ".js";
      if (fs.existsSync(path.join(Common.CANONICAL_ROOT,
        child.replace(/\//g, path.sep)))) pending.push(child);
    }
  }
  assert.deepStrictEqual(Array.from(discovered).sort((left, right) =>
    left < right ? -1 : left > right ? 1 : 0), Finalize.CONTINUATION_PROGRAM_FILES);
});

test("existing and staged release replay rechecks current ignored output before marker rename", () => {
  const source = fs.readFileSync(path.join(__dirname, "finalize-clone-release.js"), "utf8");
  const replay = source.indexOf("function replayReleaseIgnoredOutputInventory(");
  assert(replay >= 0 && source.indexOf("Materialize.verifyIgnoredOutputInventory(", replay)
    > replay);
  const main = source.indexOf("function main()");
  const readBefore = source.indexOf("const persisted = readCanonicalReleaseReceipt(", main);
  const resolve = source.indexOf("resolveFinalizationMarker(marker)", readBefore);
  const readAfter = source.indexOf("const finalReceipt = readCanonicalReleaseReceipt(", resolve);
  assert(readBefore > main && resolve > readBefore && readAfter > resolve);
});

test("rename failure preserves one complete digest-named release stage for re-entry", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-release-stage-"));
  const output = path.join(root, "release.json");
  const value = { schema: Finalize.RELEASE_SCHEMA,
    releaseSha256: "a".repeat(64), payload: "sealed" };
  const staged = output + ".staged-" + value.releaseSha256.slice(0, 16);
  try {
    assert.throws(() => Finalize.writeReleaseReceipt(output, value, root, {
      renameSync: () => { throw new Error("simulated rename failure"); },
    }));
    assert.strictEqual(fs.existsSync(output), false);
    assert.strictEqual(fs.readFileSync(staged, "utf8"),
      JSON.stringify(value, null, 2) + "\n");
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("legacy v3 rename failure keeps historical no-stage cleanup behavior", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "a5-v3-release-stage-"));
  const output = path.join(root, "release.json");
  const value = { schema: Finalize.LEGACY_RELEASE_SCHEMA,
    releaseSha256: "b".repeat(64), payload: "legacy" };
  const staged = output + ".staged-" + value.releaseSha256.slice(0, 16);
  try {
    assert.throws(() => Finalize.writeReleaseReceipt(output, value, root, {
      renameSync: () => { throw new Error("simulated rename failure"); },
    }));
    assert.strictEqual(fs.existsSync(output), false);
    assert.strictEqual(fs.existsSync(staged), false);
  } finally {
    fs.rmSync(root, { recursive: true, force: true });
  }
});

test("v4 receipt and resolved marker paths are file-flushed without claiming directory durability", () => {
  const source = fs.readFileSync(path.join(__dirname, "finalize-clone-release.js"), "utf8");
  const write = source.indexOf("function writeReleaseReceipt(");
  const stageFlush = source.indexOf("fsyncRegularFile(staged)", write);
  const rename = source.indexOf("renameFile(staged, output)", stageFlush);
  const outputFlush = source.indexOf("fsyncRegularFile(output)", rename);
  const resolve = source.indexOf("function resolveFinalizationMarker(");
  const markerRename = source.indexOf("fs.renameSync(marker.requiredPath, marker.resolvedPath)",
    resolve);
  const markerFlush = source.indexOf("fsyncRegularFile(marker.resolvedPath)", markerRename);
  assert(stageFlush > write && rename > stageFlush && outputFlush > rename);
  assert(markerRename > resolve && markerFlush > markerRename);
  const readme = fs.readFileSync(path.join(__dirname, "README.md"), "utf8");
  assert(readme.includes("not evidence of\narbitrary power-loss durability"));
});
