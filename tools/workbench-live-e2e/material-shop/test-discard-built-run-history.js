#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Build = require("./build-candidate");
const Common = require("./common");
const DiscardBuilt = require("./discard-built-run");
const Materialize = require("./materialize");
const Prepare = require("./prepare");
const RunOperationLease = require("./run-operation-lease");

let passed = 0;

function test(name, callback) {
  callback();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}

function reseal(value, key) {
  delete value[key];
  value[key] = Evidence.sha256Text(Evidence.canonicalJson(value));
  return value;
}

function writeJsonNew(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", {
    encoding: "utf8", flag: "wx",
  });
}

function gitHead() {
  const result = childProcess.spawnSync("git", ["-C", Common.CANONICAL_ROOT,
    "rev-parse", "HEAD"], { encoding: "utf8", windowsHide: true });
  assert.strictEqual(result.status, 0, String(result.stderr || result.error || ""));
  return String(result.stdout || "").trim();
}

function operationLease(fixture, createdAt, nonce) {
  return reseal({ schema: RunOperationLease.LEASE_SCHEMA, createdAt,
    runId: fixture.runId, runDir: fixture.runDir, mode: "built_only_discard",
    preparationSha256: fixture.preparation.preparationSha256,
    buildSha256: fixture.build.buildSha256, ownerPid: process.pid,
    ownerProcessStartUtcTicks: "638900000000000001",
    ownerNonceSha256: nonce.repeat(64) }, "leaseSha256");
}

function expectCode(code, callback) {
  assert.throws(callback, (error) => error && error.code === code);
}

function createFixture() {
  const runId = "discard-history-" + process.pid + "-" + Date.now().toString(36);
  const ownedBase = path.join(Common.CANONICAL_ROOT, Common.OWNED_BASE_RELATIVE);
  const runDir = path.join(ownedBase, "runs", runId);
  const resourcesRoot = path.join(ownedBase, Materialize.MATERIALIZED_DIRECTORY,
    runId, "resources");
  fs.mkdirSync(runDir, { recursive: true });
  const head = gitHead();
  const scopeSha256 = "a".repeat(64);
  const creationIntent = Materialize.createCreationIntent({ runId, runDir, ownedBase,
    destination: resourcesRoot, scope: { head, scopeSha256,
      files: [{ relativePath: "fixture.txt" }] },
  });
  const creationName = Materialize.creationResolvedName(creationIntent);
  writeJsonNew(path.join(runDir, creationName), creationIntent);

  const producerLease = Materialize.createMaterializationProducerLease(creationIntent, {
    createdAt: "2026-08-13T00:00:00.000Z", ownerPid: process.pid,
    ownerProcessStartUtcTicks: "638900000000000001",
    ownerNonceSha256: "b".repeat(64),
  });
  const producerTerminalName = Materialize.producerTerminalName(producerLease);
  writeJsonNew(path.join(runDir, producerTerminalName), producerLease);

  const artifactNames = ["scope-manifest.json", "production-closure.json",
    "materialization.json", "applicability.json", "purchase-authorization.json",
    "control-plan.json", "external-toolchain.json"];
  artifactNames.forEach((name, index) => writeJsonNew(path.join(runDir, name), {
    fixture: index + 1,
  }));
  const artifacts = Object.fromEntries(artifactNames.map((name, index) => [
    "artifact" + index, { relativePath: name },
  ]));
  const preparation = { schema: Prepare.PREPARATION_SCHEMA, runId, runDir,
    resourcesRoot, scopeSha256, materializationSha256: "c".repeat(64), artifacts,
    preparationSha256: "d".repeat(64) };
  writeJsonNew(path.join(runDir, "preparation.json"), preparation);
  const build = { schema: Build.BUILD_SCHEMA,
    preparationSha256: preparation.preparationSha256,
    candidateRoot: path.join(resourcesRoot, "tmp", "runtime-candidates", "v2",
      Build.CANDIDATE_LEAF) };
  reseal(build, "buildSha256");
  const buildPath = path.join(runDir, "candidate-build.json");
  writeJsonNew(buildPath, build);
  const materialization = { mode: Materialize.PRODUCTION_MODE,
    destination: resourcesRoot, head, scopeSha256,
    materializationSha256: preparation.materializationSha256,
    gitWorktree: { head, commonDir: creationIntent.commonDir } };
  const fixture = { runId, runDir, resourcesRoot, preparation, build, buildPath,
    materialization, creationIntent, creationName, producerLease, producerTerminalName };

  const prior = operationLease(fixture, "2026-08-13T00:01:00.000Z", "e");
  writeJsonNew(path.join(runDir, RunOperationLease.terminalName(prior)), prior);
  const active = operationLease(fixture, "2026-08-13T00:02:00.000Z", "f");
  writeJsonNew(path.join(runDir, RunOperationLease.LEASE_NAME), active);
  fixture.priorOperationLease = prior;
  fixture.activeOperationLease = active;
  fixture.creation = Materialize.loadCreationState(runDir);
  return fixture;
}

const fixture = createFixture();
try {
  test("exact producer terminal and prior built-only terminal are sealed for the next discard", () => {
    const inventory = DiscardBuilt.captureRunArtifactInventory(fixture.preparation,
      fixture.buildPath, fixture.materialization, fixture.creation, { active: false });
    assert(inventory.files.some((entry) => entry.name === fixture.producerTerminalName));
    assert.strictEqual(inventory.operation.preexistingHistory.length, 1);
    assert.strictEqual(inventory.operation.preexistingHistory[0].name,
      RunOperationLease.terminalName(fixture.priorOperationLease));
    const context = { preparation: fixture.preparation,
      materialization: fixture.materialization,
      closure: { closureSha256: "1".repeat(64), scope: {
        scopeSha256: fixture.preparation.scopeSha256,
      } }, build: fixture.build,
      probe: { probeSha256: "2".repeat(64), gitWorktreeIdentitySha256: "3".repeat(64),
        operation: inventory.operation, runArtifacts: inventory } };
    const intent = DiscardBuilt.createIntent(context, "2026-08-13T00:03:00.000Z");
    assert.strictEqual(intent.operation.preexistingHistory.length, 1);
    assert.strictEqual(intent.operation.preexistingHistory[0].lease.mode,
      "built_only_discard");
  });

  test("the exact stale-resolved producer marker is also admitted", () => {
    const terminal = path.join(fixture.runDir, fixture.producerTerminalName);
    const staleName = Materialize.producerStaleName(fixture.producerLease);
    const stale = path.join(fixture.runDir, staleName);
    fs.renameSync(terminal, stale);
    try {
      const producer = DiscardBuilt.captureMaterializationProducerHistory(
        fixture.preparation, fixture.materialization, fixture.creation);
      assert.deepStrictEqual({ name: producer.name, kind: producer.kind }, {
        name: staleName, kind: "stale_recovery",
      });
    } finally { fs.renameSync(stale, terminal); }
  });

  test("current preparation rejects missing producer history", () => {
    const terminal = path.join(fixture.runDir, fixture.producerTerminalName);
    const bytes = fs.readFileSync(terminal);
    fs.unlinkSync(terminal);
    try {
      expectCode("material_shop_built_discard_materialization_state_invalid", () =>
        DiscardBuilt.captureMaterializationProducerHistory(fixture.preparation,
          fixture.materialization, fixture.creation));
    } finally { fs.writeFileSync(terminal, bytes, { flag: "wx" }); }
  });

  test("creation-detached producer marker remains foreign", () => {
    const terminal = path.join(fixture.runDir, fixture.producerTerminalName);
    const terminalBytes = fs.readFileSync(terminal);
    fs.unlinkSync(terminal);
    const foreign = JSON.parse(terminalBytes.toString("utf8"));
    foreign.intentSha256 = "4".repeat(64);
    foreign.ownerNonceSha256 = "5".repeat(64);
    reseal(foreign, "leaseSha256");
    const foreignPath = path.join(fixture.runDir,
      Materialize.producerTerminalName(foreign));
    writeJsonNew(foreignPath, foreign);
    try {
      expectCode("material_shop_materialization_producer_lease_invalid", () =>
        DiscardBuilt.captureMaterializationProducerHistory(fixture.preparation,
          fixture.materialization, fixture.creation));
    } finally {
      fs.unlinkSync(foreignPath);
      fs.writeFileSync(terminal, terminalBytes, { flag: "wx" });
    }
  });
} finally {
  fs.rmSync(fixture.runDir, { recursive: true, force: true });
}

process.stdout.write(passed + "/" + passed
  + " built-discard producer-history tests passed\n");
