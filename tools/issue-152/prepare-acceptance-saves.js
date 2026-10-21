"use strict";

// Offline preparation only. Existing saves, SOLs, tombstones and display names are never replaced.
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const cp = require("child_process");
const assert = require("assert/strict");
const guards = require("../prepare-loot-target-full-save");
const root = path.resolve(__dirname, "../..");
const bundle = path.join(root, "tmp/issue-152-acceptance");
const seedSlot = "cf7_agent_equipment_tuning";
const scenarios = [
  { slot: "cf7_agent_152_a28", name: "152A·主线28·有摩托", main: 28, motorcycle: 1 },
  { slot: "cf7_agent_152_b29", name: "152B·主线29·有摩托", main: 29, motorcycle: 1 },
  { slot: "cf7_agent_152_c68", name: "152C·主线68·有摩托", main: 68, motorcycle: 1 },
  { slot: "cf7_agent_152_d69", name: "152D·主线69·有摩托", main: 69, motorcycle: 1 },
  { slot: "cf7_agent_152_e69", name: "152E·主线69·无载具", main: 69, motorcycle: 0 }
];
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex").toUpperCase();
const clone = data => JSON.parse(JSON.stringify(data));
const readJson = file => JSON.parse(fs.readFileSync(file, "utf8").replace(/^\uFEFF/, ""));

function assertStopped() {
  const script = "$r=$env:CF7_I152_RESOURCES; $p=@(Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -and $_.ExecutablePath.StartsWith($r+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) }); if($p.Count -gt 0){throw '请先正常退出此目录的游戏及候选进程，再准备验收存档。'}";
  cp.execFileSync("powershell.exe", ["-NoProfile", "-EncodedCommand", Buffer.from(script, "utf16le").toString("base64")],
    { windowsHide: true, env: { ...process.env, CF7_I152_RESOURCES: root }, stdio: "pipe" });
}

function filesBelow(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const file = path.join(dir, entry.name);
    assert(!entry.isSymbolicLink(), "拒绝跟随存档目录中的链接：" + file);
    return entry.isDirectory() ? filesBelow(file) : [file];
  });
}

function snapshot(files) {
  return files.map(file => ({ path: file, sha256: sha(fs.readFileSync(file)) }));
}

function assertPreserved(records) {
  for (const record of records) {
    assert(fs.existsSync(record.path), "原存档文件消失：" + record.path);
    assert.equal(sha(fs.readFileSync(record.path)), record.sha256, "原存档文件被改动：" + record.path);
  }
}

function assertNoCollision() {
  for (const scenario of scenarios) {
    assert(/^[A-Za-z0-9_-]{1,32}$/.test(scenario.slot));
    const matching = filesBelow(path.join(root, "saves")).filter(file => {
      const name = path.basename(file);
      return name === scenario.slot || name.startsWith(scenario.slot + ".");
    });
    assert.equal(matching.length, 0, "验收槽已有文件；不会覆盖，请保留现场：" + scenario.slot);
    assert.equal(guards.findSolFiles(root, scenario.slot).length, 0, "验收槽已有 SOL：" + scenario.slot);
  }
}

function makeSave(seed, scenario, mainTasks, timestamp) {
  const data = clone(seed);
  data["0"][0] = scenario.name;
  data["0"][2] = 500000;
  data["0"][9] = 1000;
  data["0"][11] = 0;
  data["0"][12] = [0, 0, 0, 0, 0];
  data["3"] = scenario.main;
  data["4"] = [[], 0];
  for (const storage of ["背包", "战备箱", "仓库", "药剂栏"]) data.inventory[storage] = {};
  data.collection = { "材料": {}, "情报": { "黑龙令": 4 } };
  data.infrastructure = { "自行车": 0, "摩托车": scenario.motorcycle, "越野车": 0 };
  const finished = {};
  for (const task of mainTasks) {
    const match = /^主线#(\d+)$/.exec(task.chain || "");
    if (match && Number(match[1]) <= scenario.main) finished[String(task.id)] = 1;
  }
  data.tasks = { tasks_to_do: [], tasks_finished: finished,
    task_chains_progress: { "主线": scenario.main, "大学": 0, "引导": 12 } };
  data.shop = { "商城已购买物品": [], "商城购物车": [] };
  // A new original character starts with no sessions, pending rewards or book-run ownership.
  data.ext = {};
  data.reserved = {};
  data.others["击杀统计"] = { total: 0, byType: {} };
  data.lastSaved = timestamp;
  assertFixture(data, scenario);
  return data;
}

function assertFixture(data, scenario) {
  assert(guards.isValidSaveData(data), "不符合现有 3.0 存档形状");
  assert.equal(data["0"][0], scenario.name);
  assert.equal(data["0"][2], 500000);
  assert.equal(data["0"][9], 1000);
  assert.equal(data["3"], scenario.main);
  assert.equal(data.tasks.task_chains_progress["主线"], scenario.main);
  assert.equal(data.tasks.tasks_finished["21"], 1, "书架历险需完成任务 21");
  assert.equal(data.tasks.tasks_finished["28"] === 1, scenario.main >= 29);
  assert.equal(data.tasks.tasks_finished["68"] === 1, scenario.main >= 69);
  assert.equal(data.infrastructure["摩托车"], scenario.motorcycle);
  assert.equal(data.infrastructure["自行车"], 0);
  assert.equal(data.infrastructure["越野车"], 0);
  assert.equal(Object.keys(data.inventory["背包"]).length, 0);
  assert.equal(Object.keys(data.collection["材料"]).length, 0);
  assert.equal(data.collection["情报"]["黑龙令"], 4);
  assert(data["5"].some(row => row[0] === "解密" && row[1] >= 5 && row[4] === true), "Lee 第五页需启用5级解密");
  assert.deepEqual(data.ext, {});
  assert.deepEqual(data.tasks.tasks_to_do, []);
  assert(!data["5"].some(row => row[0] === "口才" && row[4] === true), "验收余额按无口才折扣计算");
}

function prepare() {
  assertStopped();
  assert(!fs.existsSync(path.join(bundle, "manifest.json")), "验收包已建立；使用 --verify 查看，禁止静默复位");
  assertNoCollision();
  const existing = snapshot(filesBelow(path.join(root, "saves")));
  const source = path.join(root, "saves", seedSlot + ".json");
  const sourceBytes = fs.readFileSync(source);
  const seed = readJson(source);
  assert(guards.isValidSaveData(seed), "只读种子不合法");
  assert(!seed.ext.bookRun && !seed.ext.bookshelf, "种子不能携带书中局次");
  const mainTasks = readJson(path.join(root, "data/task/tasks1.json")).tasks;
  const timestamp = new Date().toISOString().slice(0, 19).replace("T", " ");
  const staged = scenarios.map(scenario => {
    const data = makeSave(seed, scenario, mainTasks, timestamp);
    const bytes = Buffer.from(JSON.stringify(data));
    return { scenario, bytes, sha256: sha(bytes) };
  });
  // Complete all preflight checks before the first clone write; never replace an existing file.
  assertStopped();
  assertNoCollision();
  assertPreserved(existing);
  fs.mkdirSync(path.join(bundle, "seeds"), { recursive: true });
  fs.writeFileSync(path.join(bundle, "preexisting-saves.sha256.json"), JSON.stringify(existing, null, 2), { flag: "wx" });
  const entries = [];
  for (const entry of staged) {
    const scenario = entry.scenario;
    const seedFile = path.join(bundle, "seeds", scenario.slot + ".json");
    const installed = path.join(root, "saves", scenario.slot + ".json");
    fs.writeFileSync(seedFile, entry.bytes, { flag: "wx" });
    fs.writeFileSync(installed, entry.bytes, { flag: "wx" });
    assert.equal(sha(fs.readFileSync(installed)), entry.sha256);
    entries.push({ ...scenario, sha256: entry.sha256, money: 500000, kpoints: 1000,
      level: seed["0"][3], emptyBackpackSlots: 50,
      studentExpected: scenario.main >= 29, diplomatExpected: scenario.main >= 69 });
  }
  assertPreserved(existing);
  assert.equal(sha(fs.readFileSync(source)), sha(sourceBytes));
  const manifest = { schema: "issue152-human-acceptance.v1", createdAt: new Date().toISOString(),
    root, source, sourceSha256: sha(sourceBytes), originalSaveFilesPreserved: existing.length,
    candidate: "tmp/runtime-candidates/v2/c-issue152-20261021", slots: entries,
    changes: ["角色名、金币/K点、主线与相应已完成任务", "清空背包/仓库/战备箱/药剂/材料", "仅放入4份真实情报黑龙令", "载具按场景设定，原等级/装备/技能保留", "新槽不继承局次、奖励或交易状态；保留种子已发现来源索引"],
    evidence: { offlinePrepared: true, gameplayE2e: false, humanAccepted: false, promoted: false } };
  fs.writeFileSync(path.join(bundle, "manifest.json"), JSON.stringify(manifest, null, 2), { flag: "wx" });
  console.log(JSON.stringify({ success: true, manifest: path.join(bundle, "manifest.json"),
    slots: entries.map(entry => ({ slot: entry.slot, name: entry.name })), originalSaveFilesPreserved: existing.length }));
}

function verify() {
  const manifest = readJson(path.join(bundle, "manifest.json"));
  assert.deepEqual(manifest.slots.map(entry => entry.slot), scenarios.map(entry => entry.slot));
  const result = manifest.slots.map((entry, index) => {
    const seedFile = path.join(bundle, "seeds", entry.slot + ".json");
    assert.equal(sha(fs.readFileSync(seedFile)), entry.sha256, "种子变动");
    assertFixture(readJson(seedFile), scenarios[index]);
    const installed = path.join(root, "saves", entry.slot + ".json");
    const data = readJson(installed);
    assert(guards.isValidSaveData(data));
    return { slot: entry.slot, name: data["0"][0], unchangedSincePreparation: sha(fs.readFileSync(installed)) === entry.sha256,
      money: data["0"][2], main: data.tasks.task_chains_progress["主线"],
      glue: data.collection["材料"]["强力胶"] || 0, scarf: Object.values(data.inventory["背包"]).filter(v => v.name === "黑铁死士围巾").length,
      solFiles: guards.findSolFiles(root, entry.slot).length };
  });
  console.log(JSON.stringify({ success: true, slots: result }));
}

if (require.main === module) {
  try {
    assert.equal(process.argv.length, 3, "用法：node tools/issue-152/prepare-acceptance-saves.js --prepare 或 --verify");
    if (process.argv[2] === "--prepare") prepare();
    else { assert.equal(process.argv[2], "--verify"); verify(); }
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}

module.exports = { makeSave, assertFixture, scenarios };
