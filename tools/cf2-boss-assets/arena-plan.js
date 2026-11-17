"use strict";
// Bounded same-level prototype comparison, not a calibrated production roster.
const fs = require("fs"), path = require("path"), cp = require("child_process"), crypto = require("crypto");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");
const { resolveExpectedRuntimeIdentity } = require("../lib/runtime-process-identity");
const ROOT = path.resolve(__dirname, "../..");
const sha = file => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const write = (file, value) => fs.writeFileSync(file, JSON.stringify(value, null, 2) + "\n", { flag: "wx" });

function panel(root, file, sprite) {
  const text = fs.readFileSync(path.join(root, file), "utf8");
  const escaped = sprite.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const matches = [...text.matchAll(new RegExp("<" + escaped + ">([\\s\\S]*?)</" + escaped + ">", "g"))];
  if (matches.length !== 1) throw Error("Ambiguous unit properties: " + sprite);
  return Object.fromEntries(["hp_min", "hp_max"].map(key => {
    const fields = [...matches[0][1].matchAll(new RegExp("<" + key + ">([^<]+)</" + key + ">", "g"))];
    const value = fields.length === 1 ? Number(fields[0][1]) : NaN;
    if (!Number.isFinite(value) || value <= 0) throw Error("Invalid source HP: " + sprite);
    return [key, value];
  }));
}

function createPlan(config) {
  if (!config || !/^[a-z0-9][a-z0-9-]{0,47}$/.test(config.experimentId || "")) throw Error("Fresh ASCII experimentId required");
  for (const key of ["projectRoot", "candidateRoot", "seedPath"])
    if (!path.isAbsolute(config[key] || "")) throw Error("Explicit absolute " + key + " required");
  const root = path.resolve(config.projectRoot);
  const levels = config.levels || [37], repeat = config.repeat === undefined ? 1 : config.repeat;
  if (!Array.isArray(levels) || !levels.length || levels.length > 3 || new Set(levels).size !== levels.length
      || levels.some(n => !Number.isInteger(n) || n < 1 || n > 99)) throw Error("Invalid comparison levels");
  if (!Number.isInteger(repeat) || repeat < 1 || repeat > 2) throw Error("repeat must be 1..2");
  const timeoutFrames = config.timeoutFrames === undefined ? 5400 : config.timeoutFrames;
  if (!Number.isInteger(timeoutFrames) || timeoutFrames < 1800 || timeoutFrames > 5400) throw Error("Invalid bounded timeout");
  if (2 * repeat * timeoutFrames / 30 * 1000 > 780000) throw Error("Split the bounded shard");
  const runtime = resolveExpectedRuntimeIdentity(root, config.candidateRoot);
  if (runtime.runtimeMode !== "isolated_candidate") throw Error("Only an exact isolated candidate is permitted");
  const units = JSON.parse(fs.readFileSync(path.join(root, "data/units/units.json"), "utf8").replace(/^\uFEFF/, ""));
  const find = key => {
    const rows = units.filter(row => row.key === key);
    if (rows.length !== 1) throw Error("Unit identity changed: " + key);
    return rows[0];
  };
  const boss = find("cf2.大机器人.坦克形态"), reference = find("黑铁会.黑铁");
  const bossPanel = panel(root, "data/enemy_properties/CF2重制敌人.xml", boss.spritename);
  const referencePanel = panel(root, "data/enemy_properties/原版敌人 2013-2016.xml", reference.spritename);
  const bindings = [
    "CRAZYFLASHER7MercenaryEmpire.swf", "scripts/asLoader.swf", "scripts/asLoaderShared.swf", "scripts/asLoaderLogic.swf",
    "flashswf/arts/new/Codex大机器人素材.swf", "flashswf/arts/things-new.swf",
    "data/units/units.json", "data/enemy_properties/CF2重制敌人.xml", "data/enemy_properties/原版敌人 2013-2016.xml",
    "data/items/asset_source_map.xml", "tools/cf2-boss-assets/TankBossAI.as", "tools/cf2-boss-assets/spec.json",
    "tools/cf2-boss-assets/native-manifest.json", "tools/cf2-boss-assets/balance-inputs.json", "tools/cf2-boss-assets/motion-samples.json"
  ].map(file => ({ path: file, sha256: sha(path.join(root, file)) }));
  const listed = cp.execFileSync("git", ["ls-files", "-z", "--cached", "--others", "--exclude-standard", "--",
    "flashswf", "sound", "sounds", "music", "font", "fonts"], { cwd: root, maxBuffer: 32 * 1024 * 1024, windowsHide: true })
    .toString("utf8").split("\0");
  const resourcePaths = [...new Set(listed.filter(file =>
    (/^flashswf\//.test(file) && /\.(swf|png|jpg|jpeg|webp|mp3|wav|ogg|mp4|flv|f4v)$/i.test(file))
      || /^(sounds?|music|fonts?)\//.test(file)))];
  const buildCommit = cp.execFileSync("git", ["rev-parse", "HEAD"], { cwd: root, encoding: "utf8", windowsHide: true }).trim();
  const output = path.join(ROOT, "tmp/cf2-boss/arena", config.experimentId);
  fs.mkdirSync(path.dirname(output), { recursive: true }); fs.mkdirSync(output);
  const groups = levels.map(level => {
    const cases = ["blue", "red"].map(side => {
      function entry(unit) {
        // Both assets call 初始化敌人模板: its HP scale is difficulty, not
        // the player/humanoid template's blue-side ×3 multiplier.
        return { type: "兵种" + unit.id, level, sourceId: unit.id === boss.id ? "cf2-tank" : "blackiron" };
      }
      return { caseId: "l" + level + "-" + side, repeat, timeoutFrames, spawnDistance: 650,
        blueRoster: [side === "blue" ? entry(boss) : entry(reference)],
        redRoster: [side === "red" ? entry(boss) : entry(reference)],
        tags: ["cf2-tank-prototype", "blackiron", side],
        plannerReason: "同等级交换红蓝；双方均为固定敌人模板，不套人物模板的蓝方生命×3补偿，不覆盖任何面板或技能。保留胜负、超时和原始出生数据，不写生产标定目录。",
        authorityContext: { candidateUnitId: boss.id, referenceUnitId: reference.id, candidateSide: side,
          level, blueHpCompensation: 1, panelEquality: "requires-live-spawn-audit", prototypeOnly: true, sourceBindings: bindings } };
    });
    const manifest = normalizeManifest({ batchId: config.experimentId + "-l" + level, buildCommit,
      planner: { name: "cf2-tank-blackiron-prototype", version: 1 }, repeat: 1, timeoutFrames, cases });
    const manifestPath = path.join(output, "level-" + level + ".json"); write(manifestPath, manifest);
    return { groupId: "level-" + level, mode: "serial", condition: "prototype-blackiron",
      visibility: "background-visible", performance: { preset: "performance", mode: "fixed", maxRenderHeight: 180 },
      jobs: [{ jobId: "level-" + level, workerId: "cf2-tank", manifestPath, batchTimeoutMs: 900000 }] };
  });
  const plan = { schema: "arena-worker.experiment-plan.v1", experimentId: config.experimentId,
    workers: [{ workerId: "cf2-tank", projectRoot: root, candidateRoot: config.candidateRoot, seedPath: config.seedPath, resourcePaths }],
    saveRoots: [...new Set([path.join(ROOT, "saves"), path.join(root, "saves")])],
    sharedObjectsRoot: path.join(process.env.APPDATA, "Macromedia", "Flash Player", "#SharedObjects"), groups, comparisons: [] };
  const planPath = path.join(output, "experiment-plan.json"); write(planPath, plan);
  write(path.join(output, "input-identity.json"), { sourceBindings: bindings, runtime, levels, repeat, timeoutFrames,
    sourcePanels: { candidate: bossPanel, reference: referencePanel },
    expectedRows: levels.length * repeat * 2, productionCalibration: false });
  return { planPath, expectedRows: levels.length * repeat * 2 };
}
if (require.main === module) {
  if (process.argv.length !== 3) throw Error("Usage: node tools/cf2-boss-assets/arena-plan.js <explicit-config.json>");
  console.log(JSON.stringify(createPlan(JSON.parse(fs.readFileSync(process.argv[2], "utf8").replace(/^\uFEFF/, ""))), null, 2));
}
module.exports = { createPlan };
