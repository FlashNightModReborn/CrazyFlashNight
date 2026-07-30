#!/usr/bin/env node
"use strict";

const assert = require("assert");
const crypto = require("crypto");
const fs = require("fs");
const http = require("http");
const net = require("net");
const os = require("os");
const path = require("path");
const LegacyHttpAuth = require("./lib/legacy-http-auth");
const Tool = require("./prepare-loot-target-full-save.js");

let checks = 0;
function equal(actual, expected, message) { assert.deepStrictEqual(actual, expected, message); checks += 1; }
function ok(value, message) { assert.ok(value, message); checks += 1; }
function rejected(callback, code) {
  assert.throws(callback, (error) => error && error.code === code);
  checks += 1;
}
async function rejectedAsync(callback, code) {
  await assert.rejects(callback, (error) => error && error.code === code);
  checks += 1;
}
function listen(server) {
  return new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, () => resolve(server.address().port));
  });
}
function close(server) {
  return new Promise((resolve) => server.close(resolve));
}

function fixtureSave(bag) {
  return {
    version: "3.0", lastSaved: "2026-07-19 12:00:00",
    "0": ["测试角色", 0, 0, 10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    "1": Array(28).fill(0), "4": [0, 0], "5": [], "7": Array(5).fill(0),
    inventory: { "背包": bag || {}, "装备栏": {}, "药剂栏": {}, "仓库": {}, "战备箱": {} },
    collection: {}, infrastructure: {},
    tasks: { tasks_to_do: [], tasks_finished: {}, task_chains_progress: {} },
    pets: { "宠物信息": [[], [], [], [], []], "宠物领养限制": 1 },
    shop: { "商城已购买物品": [], "商城购物车": [] },
  };
}

const root = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-loot-target-full-"));
(async () => {
try {
  const saves = path.join(root, "saves");
  fs.mkdirSync(saves, { recursive: true });
  const seedPath = path.join(saves, "crazyflasher7_saves.json");
  const seed = fixtureSave({
    "1": { name: "测试步枪", value: { level: 3, mods: ["测试配件"] }, lastUpdate: 101 },
    "7": { name: "抗生素", value: 12, lastUpdate: 103 },
    "48": { name: "测试弹药", value: 20, lastUpdate: 102 },
  });
  const seedRaw = JSON.stringify(seed);
  fs.writeFileSync(seedPath, seedRaw, "utf8");

  const slot = Tool.DEFAULT_TARGET_SLOT;
  const targetPath = path.join(saves, slot + ".json");
  const tombstone = path.join(saves, slot + ".tombstone");
  fs.writeFileSync(targetPath, JSON.stringify(fixtureSave({ "0": { name: "旧物品", value: 1 } })), "utf8");
  fs.writeFileSync(tombstone, "deleted", "utf8");
  const shared = path.join(root, "fake-shared");
  const ownedSol = path.join(shared, "hash-a", Tool.solOwnershipSuffix(root, slot));
  fs.mkdirSync(path.dirname(ownedSol), { recursive: true });
  fs.writeFileSync(ownedSol, Buffer.from([1, 2, 3]));
  const foreignSol = path.join(shared, "hash-b", "localhost", "other", "CRAZYFLASHER7MercenaryEmpire.swf", slot + ".sol");
  fs.mkdirSync(path.dirname(foreignSol), { recursive: true });
  fs.writeFileSync(foreignSol, Buffer.from([4, 5, 6]));

  const backupDir = path.join(root, "backups");
  const prepared = Tool.prepareTarget(root, { seedSlot: "crazyflasher7_saves", slot }, {
    backupDir, sharedObjectsRoot: shared, nowMs: 1700000000000, now: new Date("2026-07-19T12:34:56Z"),
  });
  equal(fs.readFileSync(seedPath, "utf8"), seedRaw, "seed shadow remains byte-for-byte untouched");
  equal(prepared.before.occupied, [1, 7, 48], "occupied slots are read dynamically before filling");
  equal(prepared.after.occupied, Array.from({ length: 50 }, (_, index) => index), "all 50 target slots are occupied");
  equal(prepared.insertedSlots.length, 47, "only empty slots are filled");
  ok(Object.values(prepared.assertions).every(Boolean), "all preparation assertions hold");
  equal(prepared.backups.length, 3, "JSON, tombstone, and exact-owned SOL are backed up");
  ok(!fs.existsSync(ownedSol), "owned stale SOL is removed after verbatim backup");
  ok(fs.existsSync(foreignSol), "foreign-installation SOL is never touched");
  ok(!fs.existsSync(tombstone), "target tombstone is removed after backup");
  const targetRaw = fs.readFileSync(targetPath, "utf8");
  equal(targetRaw, JSON.stringify(JSON.parse(targetRaw)), "target JSON is minified UTF-8 JSON");
  const target = JSON.parse(targetRaw);
  ok(target.inventory["背包"]["0"] !== seed.inventory["背包"]["1"], "inserted entry is a deep clone, not the seed object");
  equal(target.inventory["背包"]["0"].lastUpdate, 1700000000001, "inserted item gets an independent lastUpdate");
  const verification = Tool.verifyPreparedTarget(root, slot, shared);
  ok(Object.values(verification.assertions).every(Boolean), "verify-only contract accepts prepared target");
  equal(verification.verificationScope, "pre-launch-ready", "strict verification is explicitly a pre-launch readiness gate");
  equal(verification.observations.targetSolAbsent, true, "strict verification reports the observed SOL state");
  equal(verification.assertions.numericAntibioticStackPresent, true, "exact target requires a numeric antibiotic stack");
  equal(verification.assertions.darkGuitarAbsent, true, "exact target excludes dark guitar before loot");

  fs.writeFileSync(ownedSol, Buffer.from([7, 8, 9]));
  rejected(() => Tool.verifyPreparedTarget(root, slot, shared), "target_verification_failed");
  const postLaunchVerification = Tool.verifyPreparedContent(root, slot, shared);
  equal(postLaunchVerification.verificationScope, "shadow-content-only", "post-launch mode declares its limited verification scope");
  equal(postLaunchVerification.observations.targetSolAbsent, false, "post-launch mode reports the generated SOL without rejecting it");
  equal(postLaunchVerification.runtimeSolContentInspected, false, "content-only mode never implies that runtime SOL content was inspected");
  ok(!Object.prototype.hasOwnProperty.call(postLaunchVerification.assertions, "targetSolAbsent"), "SOL absence is not a required content-only assertion");
  ok(Object.values(postLaunchVerification.assertions).every(Boolean), "content-only assertions remain green after a legitimate runtime SOL appears");

  equal(Tool.parseArgs(["--verify-content-only"]).verifyContentOnly, true, "content-only CLI mode parses explicitly");
  rejected(() => Tool.parseArgs(["--verify-only", "--verify-content-only"]), "conflicting_verification_modes");

  rejected(() => Tool.assertSafeArgs({ seedSlot: "crazyflasher7_saves", slot: "crazyflasher7_saves2" }), "unsafe_target_slot");
  rejected(() => Tool.assertSafeArgs({ seedSlot: slot, slot }), "seed_equals_target");
  rejected(() => Tool.assertTargetSlotNotInUse({ save: { slot }, saveRuntime: { savePath: "another" } }, slot), "target_slot_in_use");
  rejected(() => Tool.assertTargetSlotNotInUse({ save: { slot: slot.toUpperCase() } }, slot, root), "target_slot_in_use");
  rejected(() => Tool.assertTargetSlotNotInUse({ saveRuntime: { savePath: targetPath.toUpperCase() } }, slot, root), "target_slot_in_use");
  rejected(() => Tool.assertTargetSlotNotInUse({ save: {}, saveRuntime: {} }, slot), "runtime_status_incomplete");
  const probeOrder = [];
  await rejectedAsync(() => Tool.assertTargetNotRunning(root, slot, {
    ports: [41001, 41002],
    queryAgentStatus: async (port) => {
      probeOrder.push(port);
      if (port === 41001) return { reachable: true, status: { save: { slot: "unrelated_slot" } } };
      return { reachable: true, status: { save: { slot } } };
    },
  }), "target_slot_in_use");
  equal(probeOrder, [41001, 41002], "a safe first Launcher cannot hide a later instance using the target slot");
  const safeGuard = await Tool.assertTargetNotRunning(root, slot, {
    ports: [41003, 41004, 41005],
    queryAgentStatus: async (port) => {
      if (port === 41003) return { reachable: false, status: null };
      return { reachable: true, status: { save: { slot: "safe_" + port } } };
    },
  });
  equal(safeGuard.port, 41004, "the first reachable unrelated Launcher remains the compatibility summary port");
  equal(safeGuard.slots, ["safe_41004", "safe_41005"], "all reachable unrelated Launcher slots are reported");
  equal(safeGuard.instances.map((instance) => instance.port), [41004, 41005], "unreachable ports are skipped while all reachable instances are retained");
  let rawSocketConnections = 0;
  const rawSockets = new Set();
  const rawSocketServer = net.createServer((socket) => {
    rawSocketConnections += 1;
    rawSockets.add(socket);
    socket.on("close", () => rawSockets.delete(socket));
  });
  const socketPort = await listen(rawSocketServer);
  const requestedPaths = [];
  const receivedTokens = [];
  const token = crypto.randomBytes(32).toString("base64url");
  const launcherHttp = http.createServer((request, response) => {
    requestedPaths.push(request.method + " " + request.url);
    receivedTokens.push(request.headers["x-cf7-automation-token"] || null);
    if (request.method === "POST" && request.url === "/testConnection") {
      response.writeHead(200, { "Content-Type": "application/x-www-form-urlencoded" });
      response.end("status=success");
    } else if (request.method === "GET" && request.url === "/getSocketPort") {
      response.writeHead(200, { "Content-Type": "application/x-www-form-urlencoded" });
      response.end("socketPort=" + socketPort);
    } else if (request.method === "POST" && request.url === "/task") {
      response.writeHead(200, { "Content-Type": "application/json" });
      response.end(JSON.stringify({ ok: true, result: { save: { slot: "integration_safe_slot" } } }));
    } else {
      response.writeHead(404);
      response.end("Not Found");
    }
  });
  try {
    const httpPort = await listen(launcherHttp);
    const localAppData = path.join(root, "local-app-data");
    const credentialPath = LegacyHttpAuth.expectedCredentialPath(
      root,
      {localAppData});
    fs.mkdirSync(path.dirname(credentialPath), {recursive: true});
    fs.writeFileSync(path.join(root, "launcher_ports.json"), JSON.stringify({
      pid: process.pid,
      httpPort,
      socketPort,
      legacyHttpAuthFile: credentialPath,
    }), "utf8");
    fs.writeFileSync(credentialPath, JSON.stringify({
      v: 1,
      kind: "legacy_http_automation",
      pid: process.pid,
      processStartUtcTicks: "638900000000000000",
      lifecycleId: crypto.randomBytes(16).toString("base64url"),
      header: LegacyHttpAuth.HEADER_NAME,
      token,
      capabilities: ["legacy.task"],
    }), "utf8");
    const pairedGuard = await Tool.assertTargetNotRunning(root, slot, {
      legacyHttpOptions: {
        localAppData,
        resolveProcessStartUtcTicks:
          () => "638900000000000000",
      },
    });
    equal(pairedGuard.instances.map((instance) => instance.port), [httpPort], "the confirmed Launcher HTTP instance is scanned exactly once");
    equal(pairedGuard.skippedSocketPorts, [], "exact launcher_ports.json avoids probing the paired XMLSocket port");
    equal(rawSocketConnections, 0, "the paired non-HTTP socket is never probed as HTTP");
    equal(requestedPaths, ["POST /testConnection", "GET /getSocketPort", "POST /task"], "exact Launcher identity and authenticated status endpoints are used");
    equal(receivedTokens, [null, null, token], "only the privileged /task request carries the lifecycle credential");
  } finally {
    rawSockets.forEach((socket) => socket.destroy());
    await Promise.all([close(launcherHttp), close(rawSocketServer)]);
  }
  rejected(() => Tool.fillBackpack(fixtureSave({}), 1), "no_legal_donor");
  fs.writeFileSync(path.join(saves, "seed_without_antibiotic.json"), JSON.stringify(fixtureSave({
    "0": { name: "测试步枪", value: { level: 1 } },
  })), "utf8");
  rejected(() => Tool.prepareTarget(root, { seedSlot: "seed_without_antibiotic", slot: "cf7_agent_missing_antibiotic" }, {
    backupDir: path.join(root, "missing-antibiotic-backups"), sharedObjectsRoot: shared,
  }), "antibiotic_stack_missing");
  rejected(() => Tool.assertExactScenario(fixtureSave({
    "0": { name: "加强抗生素药剂", value: 1 },
  })), "antibiotic_stack_missing");
  rejected(() => Tool.assertExactScenario(fixtureSave({
    "0": { name: "抗生素", value: 1 },
    "1": { name: "黑暗吉他", value: { level: 1 } },
  })), "dark_guitar_already_present");

  console.log(JSON.stringify({ ok: true, checks, root: "isolated-temp" }));
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
})().catch((error) => {
  console.error(error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
