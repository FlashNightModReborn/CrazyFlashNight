#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { createPilotManifest, normalizeManifest } = require("./lib/arena-calibration-core");
const { writeImmutableBytes } = require("./lib/immutable-evidence");
const { captureProtectedSaveSnapshot, captureGlobalProtectionSnapshot, findSolFiles } = require("./lib/unattended-save-safety");
const { compareProtectedSaveSnapshots, defaultOutputPaths, runBatch } = require("./run-unattended");

function write(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, text);
}

function origin(appData, root, hash, keepDrive = false) {
  const swf = path.join(fs.realpathSync(root), "CRAZYFLASHER7MercenaryEmpire.swf");
  const parsed = path.parse(swf);
  const parts = swf.slice(parsed.root.length).split(/[\\/]/).filter(Boolean);
  if (keepDrive && /^[A-Za-z]:/.test(parsed.root)) parts.unshift(parsed.root[0]);
  return path.join(appData, "Macromedia", "Flash Player", "#SharedObjects", hash, "localhost", ...parts);
}

async function main() {
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-arena-safety-"));
  try {
    const root1 = path.join(temp, "w01", "resources");
    const root2 = path.join(temp, "w02", "resources");
    const appData = path.join(temp, "appdata");
    fs.mkdirSync(root1, { recursive: true });
    fs.mkdirSync(root2, { recursive: true });
    const slot = "cf7_agent_arena_fixture";
    const sol1 = path.join(origin(appData, root1, "hash-a"), `${slot}.sol`);
    const sol2 = path.join(origin(appData, root2, "hash-a"), `${slot}.sol`);
    write(sol1, "worker 1");
    write(sol2, "worker 2");
    assert.deepStrictEqual(findSolFiles(root1, slot, { appData }), [sol1]);
    assert.deepStrictEqual(findSolFiles(root2, slot, { appData }), [sol2]);
    const duplicateSol = path.join(origin(appData, root1, "hash-b"), `${slot}.sol`);
    write(duplicateSol, "ambiguous");
    assert.throws(() => findSolFiles(root1, slot, { appData }), /ambiguous SOL origin/);
    fs.unlinkSync(duplicateSol);
    const protectedSol = path.join(path.dirname(sol1), "custom_player_slot.sol");
    write(protectedSol, "SOL-only original");
    write(path.join(root1, "saves", "custom-save.json"), "custom JSON original");
    write(path.join(root1, "saves", ".repair-backups", "custom-save", "old.broken.json"), "backup original");
    write(path.join(root1, "saves", `${slot}.json`), "owned target");
    const before = captureProtectedSaveSnapshot(root1, slot, { appData });
    assert.strictEqual(before.files.length, 3, "custom JSON, backup and SOL-only slot must all be protected");
    const suffix = "a".repeat(32);
    write(path.join(root1, "saves", `${slot}.json.previous-${suffix}`), "owned previous retained");
    write(path.join(root1, "saves", `${slot}.json.tmp-${suffix}`), "owned temporary retained");
    let artifacts = captureProtectedSaveSnapshot(root1, slot, { appData });
    assert.strictEqual(artifacts.files.length, 3, "known exact target durable companions are not another player's save");
    assert.strictEqual(artifacts.targetArtifacts.length, 2, "target companions remain fingerprinted evidence");
    write(path.join(root1, "saves", `${slot}.json.previous-not-a-guid`), "unknown suffix protected");
    write(path.join(root1, "saves", `foreign.json.previous-${suffix}`), "foreign slot backup protected");
    write(path.join(root2, "saves", `${slot}.json.previous-${suffix}`), "same slot another root protected");
    const global = captureGlobalProtectionSnapshot({saveRoots:[path.join(root1,"saves"),path.join(root2,"saves")],
      sharedObjectsRoot:path.join(appData,"Macromedia","Flash Player","#SharedObjects"),
      allowedTargets:[{swfOrigin:path.join(root1,"CRAZYFLASHER7MercenaryEmpire.swf"),slot}]});
    assert.strictEqual(global.targetArtifacts.length, 2);
    assert(global.files.some(f=>f.path.includes("previous-not-a-guid")), "unknown target suffix remains protected");
    assert(global.files.some(f=>f.path.includes("foreign.json.previous-")), "foreign slot backup remains protected");
    assert(global.files.some(f=>f.path.includes(`${slot}.json.previous-`)), "another root with same slot remains protected");
    // Restore fixture additions only; production evidence/sidecars are never deleted by this checker.
    for(const file of [path.join(root1,"saves",`${slot}.json.previous-not-a-guid`),path.join(root1,"saves",`foreign.json.previous-${suffix}`),
      path.join(root2,"saves",`${slot}.json.previous-${suffix}`)])fs.unlinkSync(file);
    write(protectedSol, "changed SOL-only bytes");
    const after = captureProtectedSaveSnapshot(root1, slot, { appData });
    assert.strictEqual(compareProtectedSaveSnapshots(before, after).length, 1);
    assert.strictEqual(fs.readFileSync(sol2, "utf8"), "worker 2");

    const immutable = path.join(temp, "evidence", "raw.jsonl");
    writeImmutableBytes(immutable, "first\n");
    writeImmutableBytes(immutable, "first\n");
    assert.throws(() => writeImmutableBytes(immutable, "replacement\n"), /immutable evidence collision/);
    assert.strictEqual(fs.readFileSync(immutable, "utf8"), "first\n");
    const out1 = defaultOutputPaths(root1, "same-batch", {});
    const out2 = defaultOutputPaths(root1, "same-batch", {});
    assert.notStrictEqual(out1.runDir, out2.runDir);
    write(out1.report, "prior report");
    assert.throws(() => defaultOutputPaths(root1, "same-batch", { report: out1.report }), /refusing to overwrite/);

    const manifest = createPilotManifest({ batchId: "identity-fixture", repeat: 1 });
    const missingReason = JSON.parse(JSON.stringify(manifest));
    delete missingReason.cases[0].plannerReason;
    const canonicalMissingReason = normalizeManifest(missingReason);
    assert.strictEqual(canonicalMissingReason.cases[0].plannerReason, "");
    assert.strictEqual(normalizeManifest(canonicalMissingReason).manifestHash, canonicalMissingReason.manifestHash);
    const manifestPath = "tmp/arena-calibration/fixture.json";
    const args = { assignmentId: "assignment-1", attemptId: "attempt-1", pollMs: 1, batchTimeoutMs: 1000 };
    const exact = { success: true, workerId: "guardian", sessionEpoch: "epoch-1", ...args,
      batchId: manifest.batchId, manifestHash: manifest.manifestHash, manifestPath, state: "completed" };
    for (const field of ["batchId", "manifestHash", "manifestPath", "assignmentId", "attemptId"]) {
      const calls = [];
      await assert.rejects(() => runBatch(1, manifestPath, args, manifest, {
        arena: async (_port, action) => {
          calls.push(action);
          return { ...exact, success: false, error: "batch_already_running", [field]: "foreign" };
        },
      }), /identity mismatch/);
      assert.deepStrictEqual(calls, ["startBatch"], "foreign batch must never be polled or aborted");
    }
    const reused = await runBatch(1, manifestPath, args, manifest, {
      arena: async (_port, action) => action === "startBatch"
        ? { ...exact, success: false, error: "batch_already_running" } : exact,
    });
    assert.strictEqual(reused.status.state, "completed");
    await assert.rejects(() => runBatch(1, manifestPath, args, manifest, {
      arena: async (_port, action) => action === "startBatch" ? exact : { ...exact, sessionEpoch: "foreign" },
    }), /identity mismatch/);
    console.log(JSON.stringify({ ok: true, exactSolOrigin: true, ambiguityRejected: true,
      solOnlyAndCustomSavesProtected: true, immutableEvidence: true, exactRunningBatch: true }));
  } finally {
    assert(path.resolve(temp).startsWith(`${path.resolve(os.tmpdir())}${path.sep}cf7-arena-safety-`));
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => { console.error(error.stack); process.exitCode = 1; });
