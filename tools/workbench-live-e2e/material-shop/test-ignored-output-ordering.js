#!/usr/bin/env node
"use strict";

const assert = require("assert");
const childProcess = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");
const Evidence = require("../lib/evidence-artifact");
const Materialize = require("./materialize");
const Scope = require("./scope-manifest");

let passed = 0;

function test(name, callback) {
  callback();
  passed += 1;
  process.stdout.write("ok - " + name + "\n");
}

function reseal(value, key) {
  delete value[key];
  value[key] = Evidence.sha256Text(Evidence.canonicalJson(value));
}

function runGit(root, args) {
  const result = childProcess.spawnSync("git", ["-C", root].concat(args), {
    encoding: "utf8", windowsHide: true,
  });
  assert.strictEqual(result.status, 0, String(result.stderr || result.error || ""));
}

function makeScope(root, descriptors) {
  const files = descriptors.slice().sort((left, right) =>
    left.relativePath.localeCompare(right.relativePath)).map((entry, ordinal) => ({
    ordinal,
    relativePath: entry.relativePath,
    roles: ["fixture"],
    origins: ["fixture"],
    bytes: entry.bytes,
    sha256: entry.sha256,
  }));
  const value = {
    schema: Scope.SCOPE_SCHEMA,
    capturedAt: "2026-08-13T00:00:00.000Z",
    root,
    head: "a".repeat(40),
    composition: { fixture: "ignored_output_ordering" },
    fileCount: files.length,
    totalBytes: files.reduce((sum, entry) => sum + entry.bytes, 0),
    files,
  };
  value.scopeSha256 = Evidence.sha256Text(
    Evidence.canonicalJson(Scope.stableProjection(value)));
  return Scope.verifyScopeManifest(value, { currentTree: false });
}

function inventoryOptions(root, scope, supplementalGeneratedOutputs) {
  return {
    runId: "ignored-output-ordering",
    seedSlot: "cf7_agent_a5_material_shop_seed_ordering",
    targetSlot: "cf7_agent_a5_material_shop_run_ordering",
    recoverySlot: "cf7_agent_a5_material_shop_recovery_ordering",
    candidateRoot: path.join(root, "tmp", "runtime-candidates", "v2", "a5"),
    scope,
    supplementalGeneratedOutputs,
  };
}

test("ordinal comparator is locale-independent for ASCII case and Chinese paths", () => {
  assert.deepStrictEqual(["啊", "中", "a", "Z"].sort(Materialize.compareOrdinal),
    ["Z", "a", "中", "啊"]);
  assert(Materialize.compareOrdinal("scripts/中.as", "scripts/啊.as") < 0);
  assert.strictEqual(Materialize.compareOrdinal("same", "same"), 0);
});

test("ignored-output capture and validation share ordinal path ordering", () => {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), "a5-ignored-order-"));
  const root = fs.realpathSync.native(temporaryRoot);
  try {
    runGit(root, ["init", "--quiet"]);
    fs.writeFileSync(path.join(root, ".gitignore"),
      "scripts/\ntmp/workbench-live-e2e/offline-recovery-receipts/\n", "utf8");

    const protectedDescriptors = ["scripts/中.as", "scripts/啊.as"].map(
      (relativePath, index) => {
        const bytes = Buffer.from("fixture-" + index, "utf8");
        const absolute = path.join(root, relativePath.replace(/\//g, path.sep));
        fs.mkdirSync(path.dirname(absolute), { recursive: true });
        fs.writeFileSync(absolute, bytes);
        return { relativePath, bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
      });
    const scope = makeScope(root, protectedDescriptors);

    const supplemental = ["a.json", "Z.json"].map((name, index) => {
      const relativePath = "tmp/workbench-live-e2e/offline-recovery-receipts/" + name;
      const bytes = Buffer.from("{\"fixture\":" + index + "}\n", "utf8");
      const absolute = path.join(root, relativePath.replace(/\//g, path.sep));
      fs.mkdirSync(path.dirname(absolute), { recursive: true });
      fs.writeFileSync(absolute, bytes);
      return { relativePath, bytes: bytes.length, sha256: Evidence.sha256Bytes(bytes) };
    });
    const options = inventoryOptions(root, scope, supplemental);
    const inventory = Materialize.captureIgnoredOutputInventory(root, options);

    assert.deepStrictEqual(inventory.policy.supplementalGeneratedOutputs.map(
      (entry) => entry.relativePath), [
      "tmp/workbench-live-e2e/offline-recovery-receipts/Z.json",
      "tmp/workbench-live-e2e/offline-recovery-receipts/a.json",
    ]);
    assert.deepStrictEqual(inventory.files.map((entry) => entry.relativePath), [
      "scripts/中.as",
      "scripts/啊.as",
      "tmp/workbench-live-e2e/offline-recovery-receipts/Z.json",
      "tmp/workbench-live-e2e/offline-recovery-receipts/a.json",
    ]);
    Materialize.verifyIgnoredOutputInventory(inventory, root, options);

    const unordered = JSON.parse(JSON.stringify(inventory));
    [unordered.files[0], unordered.files[1]] = [unordered.files[1], unordered.files[0]];
    unordered.filesSha256 = Evidence.sha256Text(Evidence.canonicalJson(unordered.files));
    reseal(unordered, "inventorySha256");
    assert.throws(() => Materialize.validateIgnoredOutputInventory(unordered, root, options),
      (error) => error.code === "material_shop_ignored_output_inventory_invalid");

    const legacyOptions = Object.assign({}, options);
    delete legacyOptions.targetSlot;
    delete legacyOptions.recoverySlot;
    delete legacyOptions.supplementalGeneratedOutputs;
    const legacyFiles = inventory.files.filter((entry) =>
      entry.kind === "protected_scope_input");
    const legacy = {
      schema: Materialize.LEGACY_IGNORED_OUTPUT_SCHEMA,
      policy: Materialize.legacyIgnoredOutputPolicy(root, legacyOptions),
      fileCount: legacyFiles.length,
      totalBytes: legacyFiles.reduce((sum, entry) => sum + entry.bytes, 0),
      files: legacyFiles,
      filesSha256: Evidence.sha256Text(Evidence.canonicalJson(legacyFiles)),
    };
    reseal(legacy, "inventorySha256");
    Materialize.validateIgnoredOutputInventory(legacy, root, legacyOptions);
  } finally {
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  }
});

test("capture, supplemental normalization, and validation use the one comparator", () => {
  const source = fs.readFileSync(path.join(__dirname, "materialize.js"), "utf8");
  assert.match(source,
    /\.map\(\(entry\) => entry\.replace\(\/\\\\\/g, "\/"\)\)\.sort\(compareOrdinal\)/);
  assert.match(source,
    /\.sort\(\(left, right\) => compareOrdinal\(left\.relativePath, right\.relativePath\)\)/);
  assert.match(source,
    /index > 0 && compareOrdinal\(\s*files\[index - 1\]\.relativePath, entry\.relativePath\) >= 0/);
});

process.stdout.write(passed + "/" + passed
  + " ignored-output ordering tests passed\n");
