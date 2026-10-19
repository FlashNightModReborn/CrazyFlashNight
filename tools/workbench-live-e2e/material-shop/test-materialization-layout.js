#!/usr/bin/env node
"use strict";

// Offline fixtures only. No PowerShell, Launcher, save/SOL, network, or product build.
const assert = require("assert");
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const os = require("os");
const path = require("path");
const vm = require("vm");
const Evidence = require("../lib/evidence-artifact");
const Budget = require("./worktree-path-budget");
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-layout-"));
const root = path.join(temporary, "repo");
fs.mkdirSync(root);
let passed = 0;
function test(name, callback) { callback(); passed += 1; process.stdout.write("ok - " + name + "\n"); }
function clone(value) { return JSON.parse(JSON.stringify(value)); }
function seal(value, field) { delete value[field]; value[field] = Evidence.sha256Text(Evidence.canonicalJson(value)); return value; }
function rejects(callback, code) { assert.throws(callback, (error) => !code || error.code === code); }
function git(args) {
  const result = childProcess.spawnSync("git", ["-C", root].concat(args), { encoding: "utf8",
    env: Object.assign({}, process.env, { GIT_AUTHOR_NAME: "Layout fixture", GIT_AUTHOR_EMAIL: "fixture@example.invalid",
      GIT_COMMITTER_NAME: "Layout fixture", GIT_COMMITTER_EMAIL: "fixture@example.invalid" }) });
  assert.strictEqual(result.status, 0, String(result.stderr || result.error)); return result.stdout.trim();
}
let Common;
let Materialize;
let Operation;
function load(name, extra, fileSystem) {
  const filename = path.join(__dirname, name);
  const module = { exports: {} };
  const imports = Object.assign({ fs: fileSystem || fs, path, child_process: childProcess, crypto,
    "./common": Common, "./materialize": Materialize, "./run-operation-lease": Operation,
    "../lib/evidence-artifact": Evidence, "./worktree-path-budget": Budget,
    "./scope-manifest": { MAXIMUM_FILES: 8192, MAXIMUM_TOTAL_BYTES: 1024 * 1024 * 1024, verifyScopeManifest: () => {} },
    "../lib/launcher-observation": { assertExclusiveLauncherProcess: () => {}, queryLauncherCoreProcesses: () => [] },
  }, extra || {});
  const localRequire = (id) => {
    if (id === "./run-operation-lease") return Operation;
    if (Object.prototype.hasOwnProperty.call(imports, id)) return imports[id];
    // Unused product dependencies have no callable surface in this isolated harness.
    if (/^\.\.?\//.test(id)) return {};
    return require(id);
  };
  const wrapper = new vm.Script("(function(require, module, exports, __dirname, __filename) {\n"
    + fs.readFileSync(filename, "utf8").replace(/^#![^\n]*\n/, "") + "\n})", { filename }).runInThisContext();
  const virtualDir = name === "common.js" ? path.join(root, "tools/workbench-live-e2e/material-shop") : __dirname;
  wrapper(localRequire, module, module.exports, virtualDir, filename);
  return module.exports;
}
let head;
const scope = () => ({ head, scopeSha256: "a".repeat(64), files: [{ relativePath: "fixture.txt" }] });
function createRun(id, legacy, options) {
  const layout = Materialize.materializationLayout(root, id, legacy
    ? Materialize.LEGACY_CREATION_INTENT_SCHEMA : Materialize.CREATION_INTENT_SCHEMA);
  fs.mkdirSync(layout.runDir, { recursive: true });
  let intent;
  if (!legacy) intent = Materialize.createCreationIntent({ runId: id, runDir: layout.runDir,
    ownedBase: layout.ownedBase, destination: layout.destination, scope: scope() });
  else {
    const current = Materialize.materializationLayout(root, id);
    intent = Materialize.createCreationIntent({ runId: id, runDir: current.runDir,
      ownedBase: current.ownedBase, destination: current.destination, scope: scope() });
    Object.assign(intent, { schema: Materialize.LEGACY_CREATION_INTENT_SCHEMA,
      ownedBase: layout.ownedBase, destination: layout.destination,
      removeCommand: ["git", "worktree", "remove", "--force", layout.destination] });
    seal(intent, "intentSha256");
    Materialize.validateCreationIntent(intent);
  }
  const bytes = Buffer.from(JSON.stringify(intent, null, legacy ? 3 : 2).replace(/\n/g, legacy ? "\r\n" : "\n") + (legacy ? "\r\n" : "\n"));
  fs.writeFileSync(path.join(layout.runDir, Materialize.CREATION_INTENT_NAME), bytes, { flag: "wx" });
  if (options && options.worktree) {
    fs.mkdirSync(path.dirname(layout.destination), { recursive: true });
    git(["worktree", "add", "--detach", layout.destination, head]);
  }
  return { layout, intent, bytes };
}
function prepareEnvelope(run) {
  const value = { schema: "workbench-live-e2e.material-shop.preparation.v2", createdAt: "2026-01-01T00:00:00Z",
    runId: run.intent.runId, root, runDir: run.layout.runDir, resourcesRoot: run.layout.destination,
    slots: {}, scopeSha256: "a".repeat(64), closureSha256: "b".repeat(64),
    externalToolchainSha256: "c".repeat(64), applicabilitySha256: "d".repeat(64),
    materializationSha256: "e".repeat(64), planSha256: "f".repeat(64), artifacts: {}, boundaries: {} };
  value.preparationSha256 = Evidence.sha256Text(Evidence.canonicalJson(Prepare.stablePreparation(value)));
  return value;
}
let Prepare;
try {
  git(["init"]); fs.writeFileSync(path.join(root, ".gitignore"), "/tmp/\n");
  fs.writeFileSync(path.join(root, "fixture.txt"), "isolated layout fixture\n");
  git(["add", "."]); git(["commit", "-m", "isolated fixture"]); head = git(["rev-parse", "HEAD"]);
  Common = load("common.js"); Materialize = load("materialize.js"); Operation = load("run-operation-lease.js");
  Prepare = load("prepare.js");

  test("new layout keeps original evidence and lease root, shortening only resources", () => {
    const layout = Materialize.materializationLayout(root, "new-run");
    assert.strictEqual(layout.runDir, path.join(root, Common.OWNED_BASE_RELATIVE, "runs", "new-run"));
    assert.strictEqual(layout.destination, path.join(root, "tmp/a5/m/new-run/resources"));
    assert.strictEqual(Common.OWNED_BASE_RELATIVE, path.join("tmp", "workbench-live-e2e", "material-shop"));
  });
  for (const id of [".", "..", "CON", "aux.txt", "LPT9.log", "run.", "x~y", "x".repeat(101), "a/b", "a\\b", "a "]) {
    test("new layout rejects unsafe directory id " + JSON.stringify(id), () => {
      rejects(() => Materialize.materializationLayout(root, id), "material_shop_materialization_layout_invalid");
    });
  }
  const sample = "a".repeat(179);
  for (const units of [26, 27, 28, 60]) test("short layout actual projection at canonical root units " + units, () => {
    const fakeRoot = path.parse(root).root + "r".repeat(units - path.parse(root).root.length);
    const destination = Materialize.materializationLayout(fakeRoot, "a5-0813-1903x").destination;
    const execute = () => Budget.projectPaths(destination, [{ relativePath: sample, kind: "file" }], [{ relativePath: "overlay.txt" }]);
    if (units <= 27) assert.strictEqual(execute().longestPathLength, units + 213);
    else rejects(execute, "material_shop_worktree_path_budget_exceeded");
  });
  test("one extra dirty overlay unit narrows the canonical-root allowance", () => {
    const dest = Materialize.materializationLayout(path.parse(root).root + "r".repeat(27 - path.parse(root).root.length), "a5-0813-1903x").destination;
    rejects(() => Budget.projectPaths(dest, [{ relativePath: sample, kind: "file" }], [{ relativePath: "b".repeat(180) }]),
      "material_shop_worktree_path_budget_exceeded");
  });
  const old = createRun("opaque-old", true);
  const fresh = createRun("fresh-new", false);
  for (const run of [old, fresh]) test("explicit creation schema replays " + run.intent.schema, () => {
    assert.strictEqual(Materialize.loadCreationState(run.layout.runDir).intent.destination, run.layout.destination);
    assert.deepStrictEqual(fs.readFileSync(path.join(run.layout.runDir, Materialize.CREATION_INTENT_NAME)), run.bytes);
  });
  test("unknown creation schema has no legacy destination fallback", () => {
    const value = clone(old.intent); value.schema = "unknown"; seal(value, "intentSha256");
    rejects(() => Materialize.validateCreationIntent(value), "material_shop_materialization_layout_invalid");
  });
  for (const run of [old, fresh]) test("creation schema cannot cross-match the opposite root: " + run.intent.runId, () => {
    const value = clone(run.intent); value.schema = run === old ? Materialize.CREATION_INTENT_SCHEMA : Materialize.LEGACY_CREATION_INTENT_SCHEMA;
    seal(value, "intentSha256"); rejects(() => Materialize.validateCreationIntent(value), "material_shop_materialization_intent_invalid");
  });
  const copied = Materialize.materializationLayout(root, "copied-marker"); fs.mkdirSync(copied.runDir, { recursive: true });
  fs.copyFileSync(path.join(old.layout.runDir, Materialize.CREATION_INTENT_NAME), path.join(copied.runDir, Materialize.CREATION_INTENT_NAME));
  test("copied creation marker is rejected by the outer evidence run identity", () => {
    rejects(() => Materialize.loadCreationState(copied.runDir), "material_shop_materialization_recovery_state_invalid");
  });
  test("markerless short worktree cannot select or invent a cleanup target", () => {
    const layout = Materialize.materializationLayout(root, "no-marker"); fs.mkdirSync(layout.runDir, { recursive: true });
    rejects(() => Materialize.materializationDestinationForRun(layout.runDir, "no-marker"), "material_shop_materialization_recovery_state_invalid");
  });
  for (const [label, prepareCollision] of [
    ["empty original evidence run", (layout) => fs.mkdirSync(layout.runDir, { recursive: true })],
    ["original active operation lease", (layout) => { fs.mkdirSync(layout.runDir, { recursive: true }); fs.writeFileSync(path.join(layout.runDir, Operation.LEASE_NAME), "opaque active lease\n"); }],
    ["legacy orphan resources parent", (layout) => fs.mkdirSync(path.dirname(Materialize.materializationLayout(root, layout.runId, Materialize.LEGACY_CREATION_INTENT_SCHEMA).destination), { recursive: true })],
    ["short orphan resources parent", (layout) => fs.mkdirSync(path.dirname(layout.destination), { recursive: true })],
  ]) test("new run cannot bypass " + label, () => {
    const id = "collision-" + passed;
    const layout = Materialize.materializationLayout(root, id); prepareCollision(layout);
    const snapshot = git(["worktree", "list", "--porcelain"]);
    rejects(() => Materialize.assertNewRunAvailable(root, id), "material_shop_run_exists");
    assert.strictEqual(git(["worktree", "list", "--porcelain"]), snapshot);
  });
  test("case-folded run id collision is rejected on a case-sensitive test host too", () => {
    const layout = Materialize.materializationLayout(root, "CaseFold"); fs.mkdirSync(layout.runDir, { recursive: true });
    rejects(() => Materialize.assertNewRunAvailable(root, "casefold"), "material_shop_run_exists");
  });
  test("fresh same-id preparation reservation is CreateNew, not merged", () => {
    const layout = Materialize.assertNewRunAvailable(root, "reserved-new"); fs.mkdirSync(layout.runDir, { recursive: true });
    assert.throws(() => fs.mkdirSync(layout.runDir), (error) => error.code === "EEXIST");
    rejects(() => Materialize.assertNewRunAvailable(root, "reserved-new"), "material_shop_run_exists");
  });
  const liveA = createRun("producer-a", false);
  const liveB = createRun("producer-b", false);
  const producerA = Materialize.acquireMaterializationProducer(liveA.layout.runDir);
  const producerB = Materialize.acquireMaterializationProducer(liveB.layout.runDir);
  test("two run producers own distinct leases, never a shared short-root lease", () => {
    assert.notStrictEqual(producerA.leasePath, producerB.leasePath);
    assert.strictEqual(Materialize.readMaterializationProducer(liveA.layout.runDir).ownerState, "same_process");
    assert.strictEqual(Materialize.readMaterializationProducer(liveB.layout.runDir).ownerState, "same_process");
    rejects(() => Materialize.acquireMaterializationProducer(liveA.layout.runDir), "material_shop_materialization_producer_busy");
  });
  test("active producer prevents cleanup without any removal callback", () => {
    let calls = 0;
    rejects(() => Materialize.cleanupFailedMaterialization(liveA.layout.runDir, { acknowledge: true,
      removeWorktree: () => { calls += 1; } }), "material_shop_materialization_producer_busy");
    assert.strictEqual(calls, 0);
  });
  Materialize.releaseMaterializationProducer(producerA); Materialize.releaseMaterializationProducer(producerB);
  test("a producer terminal from another run cannot authorize cleanup", () => {
    const a = Materialize.readMaterializationProducer(liveA.layout.runDir);
    const b = Materialize.readMaterializationProducer(liveB.layout.runDir);
    const saved = fs.readFileSync(b.path); fs.unlinkSync(b.path);
    const injected = path.join(liveB.layout.runDir, a.name); fs.copyFileSync(a.path, injected);
    try { rejects(() => Materialize.cleanupFailedMaterialization(liveB.layout.runDir, { acknowledge: true }), "material_shop_materialization_producer_lease_invalid"); }
    finally { fs.unlinkSync(injected); fs.writeFileSync(b.path, saved); }
  });
  const Build = load("build-candidate.js", { "./prepare": Prepare });
  for (const run of [old, fresh]) test("current preparation loader chooses exact sealed " + (run === old ? "v1" : "v2") + " destination", () => {
    const producer = Materialize.acquireMaterializationProducer(run.layout.runDir); Materialize.releaseMaterializationProducer(producer);
    fs.renameSync(path.join(run.layout.runDir, Materialize.CREATION_INTENT_NAME), path.join(run.layout.runDir, Materialize.creationResolvedName(run.intent)));
    const value = prepareEnvelope(run); const target = path.join(run.layout.runDir, "preparation.json"); fs.writeFileSync(target, JSON.stringify(value));
    assert.strictEqual(Build.loadPreparation(target).resourcesRoot, run.layout.destination);
    value.resourcesRoot = Materialize.materializationLayout(root, value.runId, run === old ? Materialize.CREATION_INTENT_SCHEMA : Materialize.LEGACY_CREATION_INTENT_SCHEMA).destination;
    value.preparationSha256 = Evidence.sha256Text(Evidence.canonicalJson(Prepare.stablePreparation(value))); fs.writeFileSync(target, JSON.stringify(value));
    rejects(() => Build.loadPreparation(target), "material_shop_preparation_invalid");
  });
  for (const legacy of [false, true]) test("real Git failed-worktree cleanup targets only sealed " + (legacy ? "legacy" : "short") + " run", () => {
    const run = createRun(legacy ? "cleanup-old" : "cleanup-new", legacy, { worktree: true });
    const producer = Materialize.acquireMaterializationProducer(run.layout.runDir); Materialize.releaseMaterializationProducer(producer);
    const beforeSibling = fs.readFileSync(path.join(liveB.layout.runDir, Materialize.CREATION_INTENT_NAME));
    const receipt = Materialize.cleanupFailedMaterialization(run.layout.runDir, { acknowledge: true });
    assert.strictEqual(receipt.destination, run.layout.destination);
    assert.strictEqual(fs.existsSync(run.layout.destination), false); assert.strictEqual(Materialize.worktreeListed(root, run.layout.destination), false);
    assert.deepStrictEqual(fs.readFileSync(path.join(run.layout.runDir, Materialize.cleanupResolvedName(run.intent))), run.bytes);
    assert.deepStrictEqual(fs.readFileSync(path.join(liveB.layout.runDir, Materialize.CREATION_INTENT_NAME)), beforeSibling);
    assert.strictEqual(Materialize.cleanupFailedMaterialization(run.layout.runDir, { acknowledge: true }).cleanupSha256, receipt.cleanupSha256);
  });
  test("copied release removal marker cannot finalize another run", () => {
    const Release = load("release-worktree.js", { "./prepare": Prepare });
    const a = createRun("release-a", false); const b = createRun("release-b", false);
    const intent = Release.createRemovalIntent({ runId: a.intent.runId, runDir: a.layout.runDir,
      destination: a.layout.destination, outputPath: path.join(a.layout.runDir, Release.REMOVAL_OUTPUT_NAME),
      materializationSha256: "a".repeat(64), preparationSha256: "b".repeat(64), closureSha256: "c".repeat(64),
      buildSha256: "d".repeat(64), rawSha256: "e".repeat(64), journeyEvidenceSha256: "f".repeat(64),
      cloneReleaseSha256: "1".repeat(64), acceptanceSha256: "2".repeat(64), cloneInspectionSha256: "3".repeat(64),
      gitWorktreeIdentitySha256: "4".repeat(64), head, commonDir: path.join(root, ".git") });
    fs.writeFileSync(path.join(b.layout.runDir, Release.REMOVAL_INTENT_NAME), JSON.stringify(intent));
    let writes = 0;
    rejects(() => Release.finalizeRemoval(b.layout.runDir, { writeReceipt: () => { writes += 1; } }), "material_shop_worktree_removal_state_invalid");
    assert.strictEqual(writes, 0); assert.strictEqual(fs.existsSync(intent.outputPath), false);
  });
  for (const units of [6, 27, 28]) test("read-only diagnosis reports full-HEAD run/root limits at root " + units, () => {
    const virtualRoot = path.parse(root).root + "r".repeat(units - path.parse(root).root.length);
    const Diagnose = load("diagnose-materialization-layout.js", {
      "./common": Object.assign({}, Common, { assertCanonicalRoot: (value) => value }),
      "./materialize": Object.assign({}, Materialize, { assertWorktreePathBudget: (_root, destination, sealed) =>
        Budget.projectPaths(destination, [{ relativePath: sample, kind: "file" }], sealed.files) }),
    });
    const value = Diagnose.diagnose(virtualRoot, "a5-0813-1903x", { files: [{ relativePath: "overlay.txt" }] });
    assert.strictEqual(value.maximumCanonicalRootUtf16, 27);
    assert.strictEqual(value.maximumNewRunIdUtf16, 40 - units);
    assert.strictEqual(value.relativeMaximumUtf16, 179);
    assert.strictEqual(value.ok, units <= 27);
    assert.strictEqual(value.diagnosticOnly, true);
  });
  for (const variable of Budget.GIT_CONTEXT_ENVIRONMENT.concat(["git_dir"])) test("ambient Git override refuses all touched entries before side effects: " + variable, () => {
    const foreign = path.join(temporary, "foreign");
    if (!fs.existsSync(foreign)) {
      fs.mkdirSync(foreign); const initialized = childProcess.spawnSync("git", ["init", foreign], { encoding: "utf8" });
      assert.strictEqual(initialized.status, 0, initialized.stderr);
    }
    const foreignIndex = path.join(temporary, "foreign-index");
    const sourceIndex = fs.readFileSync(path.join(root, ".git/index"));
    const sourceWorktrees = fs.existsSync(path.join(root, ".git/worktrees"))
      ? fs.readdirSync(path.join(root, ".git/worktrees")).sort() : [];
    const oldValue = process.env[variable];
    process.env[variable] = variable.toUpperCase() === "GIT_INDEX_FILE" ? foreignIndex : path.join(foreign, ".git");
    try {
      rejects(() => Budget.assertWorktreePathBudget(root, Materialize.materializationLayout(root, "env-blocked").destination, scope()),
        "material_shop_worktree_path_budget_environment");
      rejects(() => Prepare.prepare({ root, runId: "env-blocked" }), "material_shop_worktree_path_budget_environment");
      rejects(() => Materialize.materializeScope({ root }), "material_shop_worktree_path_budget_environment");
      rejects(() => Materialize.cleanupFailedMaterialization(liveA.layout.runDir, { acknowledge: true }),
        "material_shop_worktree_path_budget_environment");
    } finally { if (oldValue === undefined) delete process.env[variable]; else process.env[variable] = oldValue; }
    assert.strictEqual(fs.existsSync(foreignIndex), false);
    assert.strictEqual(fs.existsSync(path.join(foreign, ".git/worktrees")), false);
    assert.deepStrictEqual(fs.readFileSync(path.join(root, ".git/index")), sourceIndex);
    assert.deepStrictEqual(fs.existsSync(path.join(root, ".git/worktrees"))
      ? fs.readdirSync(path.join(root, ".git/worktrees")).sort() : [], sourceWorktrees);
    assert.strictEqual(fs.existsSync(Materialize.materializationLayout(root, "env-blocked").runDir), false);
    assert.strictEqual(fs.existsSync(Materialize.materializationLayout(root, "env-blocked").destination), false);
  });
  test("static dependency scope explicitly protects layout diagnostic and tests", () => {
    const manifest = fs.readFileSync(path.join(__dirname, "scope-manifest.js"), "utf8");
    assert(manifest.includes("test-materialization-layout.js")); assert(manifest.includes("diagnose-materialization-layout.js"));
  });
  process.stdout.write(passed + "/" + passed + " materialization-layout tests passed\n");
} finally {
  // Only this process's newly-created disposable fixture is removed.
  fs.rmSync(temporary, { recursive: true, force: true });
}
