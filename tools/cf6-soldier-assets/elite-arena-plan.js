"use strict";

const fs = require("fs");
const path = require("path");
const cp = require("child_process");
const crypto = require("crypto");
const { normalizeManifest } = require("../arena-calibration/lib/arena-calibration-core");

const ROOT = path.resolve(__dirname, "../..");
const DEFAULT_WEAPON = "M4A1战术版";
const DEFAULT_TOUGHNESS = { ordinary: 5, elite: 50 };
const VARIANTS = Object.freeze({
  ordinary: { id: 466, behavior: "ordinary-controller" },
  elite: { id: 478, behavior: "elite-retreat" },
  stationary: { id: 478, ablation: "stationary", behavior: "elite-retreat-stationary" },
  ordinaryBrain: { id: 478, ablation: "ordinary", behavior: "ordinary-controller" },
  noSidearm: { id: 478, ablation: "noSidearm", behavior: "disabled-noSidearm" },
  shieldOrdinary: { id: 467, behavior: "ordinary-controller" },
  shieldElite: { id: 479, behavior: "elite-retreat" },
});
const SOURCE_PATHS = Object.freeze([
  "tools/cf6-soldier-assets/elite-arena-plan.js",
  "tools/cf6-soldier-assets/elite-campaign.js",
  "tools/cf6-soldier-assets/elite-arena-summary.js",
  "tools/cf6-soldier-assets/foreground-evidence.js",
  "tools/cf6-soldier-assets/EliteAI.as",
  "tools/cf6-soldier-assets/SoldierAI.as",
  "tools/cf6-soldier-assets/SoldierRoles.as",
  "tools/cf6-soldier-assets/TacticalAI.as",
  "tools/cf6-soldier-assets/tactical-profiles.json",
  "tools/cf6-soldier-assets/elite.py",
  "tools/cf6-soldier-assets/elite_anatomy.py",
  "tools/cf6-soldier-assets/elite-tuning.json",
  "tools/cf6-soldier-assets/elite-motion-profile.json",
  "tools/cf6-soldier-assets/elite-panel-inputs.json",
  "flashswf/arts/new/Codex特种兵素材.swf",
  "flashswf/arts/new/CodexWings素材.swf",
  "flashswf/arts/new/Codex大刀机器人素材.swf",
  "tools/cf6-bladebot-assets/BladebotAI.as",
  "scripts/asLoader.swf",
  "scripts/类定义/org/flashNight/arki/unit/Action/Shoot/ShootCore.as",
  "scripts/类定义/org/flashNight/arki/unit/UnitComponent/Initializer/EventComponent/FireEventComponent.as",
  "scripts/逻辑/单位函数/单位函数_lsy_主角射击函数.as",
  "scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as",
  "scripts/逻辑/单位函数/单位函数_lsy_主角技能.as",
  "data/enemy_properties/CF6重制敌人.xml",
  "data/units/units.json",
  "data/items/asset_source_map.xml",
  "data/items/武器_长枪_突击步枪.xml",
  "data/items/武器_手枪_大威力手枪.xml",
  "data/items/武器_手枪_突击步枪.xml",
]);

function hashFile(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(path.toNamespacedPath(filePath))).digest("hex");
}

function bindSources(root = ROOT, paths = SOURCE_PATHS, hash = hashFile) {
  return paths.map((relativePath) => ({
    path: relativePath,
    sha256: hash(path.join(root, relativePath)),
  }));
}

function positiveInteger(value, defaultValue, label) {
  const result = value === undefined ? defaultValue : value;
  if (!Number.isSafeInteger(result) || result <= 0) throw Error(`${label} must be a positive integer`);
  return result;
}

function validateAuthorities(root = ROOT) {
  const units = JSON.parse(fs.readFileSync(path.join(root, "data/units/units.json"), "utf8"));
  const byId = new Map(units.map((unit) => [unit.id, unit]));
  for (const [id, expected] of [[466, null], [467, null], [478, "FR506"], [479, "FR506"]]) {
    const unit = byId.get(id);
    if (!unit || unit.data.secondary !== expected || unit.data.secondary2 !== expected) throw Error(`Unexpected default sidearm authority for unit ${id}`);
  }
  const tuning = JSON.parse(fs.readFileSync(path.join(root, "tools/cf6-soldier-assets/elite-tuning.json"), "utf8"));
  if (tuning.toughnessCoefficient !== DEFAULT_TOUGHNESS.elite
      || tuning.sidearmModule.item !== "FR506" || tuning.sidearmModule.ablation !== "noSidearm") {
    throw Error("Elite toughness/sidearm tuning authority changed");
  }
  const profile = JSON.parse(fs.readFileSync(path.join(root, "tools/cf6-soldier-assets/elite-motion-profile.json"), "utf8"));
  const counts = {};
  for (const action of ["retreat", "stand", "run", "slide"]) {
    const events = profile.actions[action].fireEvents;
    counts[action] = {
      primary: events.filter((event) => event.weapon === "primary").length,
      secondary: events.filter((event) => event.weapon === "secondary").length,
    };
  }
  if (counts.retreat.primary !== 4 || counts.retreat.secondary !== 4
      || counts.stand.primary !== 5 || counts.stand.secondary !== 0
      || counts.run.primary !== 8 || counts.run.secondary !== 0
      || counts.slide.primary !== 5 || counts.slide.secondary !== 0) {
    throw Error("Elite motion fire-event authority changed");
  }
  const eliteAi = fs.readFileSync(path.join(root, "tools/cf6-soldier-assets/EliteAI.as"), "utf8");
  if (!eliteAi.includes('eliteAbstraction!="noSidearm"')
      || !eliteAi.includes("eliteSidearmAllowed=eliteAbstraction!=\"noSidearm\"")
      || !eliteAi.includes("this.eliteSidearmAllowed")) {
    throw Error("noSidearm must disable behavior without removing equipment");
  }
  const pistolXml = fs.readFileSync(path.join(root, "data/items/武器_手枪_大威力手枪.xml"), "utf8");
  const fr506 = pistolXml.split("<item").find((block) => /<name>FR506<\/name>/.test(block));
  if (!fr506 || !/<weight>5<\/weight>/.test(fr506) || !/<reloadType>tube<\/reloadType>/.test(fr506)) {
    throw Error("FR506 weight=5 and tube reload authority are required");
  }
  return { units: byId, tuning, profile, fireEventCounts: counts, sidearmWeight: 5 };
}

function defaultWhenUndefined(value, defaultValue) {
  return value === undefined ? defaultValue : value;
}

function buildCases(comparisons, options = {}) {
  if (!Array.isArray(comparisons) || comparisons.length === 0) throw Error("Non-empty comparisons required");
  const authorities = options.authorities || validateAuthorities(options.root || ROOT);
  const sourceBindings = options.sourceBindings || bindSources(options.root || ROOT);
  const prepared = comparisons.map((row, index) => {
    if (!row || typeof row !== "object" || Array.isArray(row)) throw Error(`Comparison ${index} must be an object`);
    const variant = VARIANTS[row.variant];
    if (!variant) throw Error(`Unknown variant: ${row.variant}`);
    if (typeof row.id !== "string" || !row.id.trim()) throw Error(`Comparison ${index} requires a case id`);
    const level = positiveInteger(row.level, 60, "level");
    const opponentLevel = positiveInteger(row.opponentLevel, level, "opponentLevel");
    const opponentId = positiveInteger(row.opponentId, undefined, "opponentId");
    const side = defaultWhenUndefined(row.side, "red");
    if (!["red", "blue"].includes(side)) throw Error("candidate side must be red or blue");
    const weapon = defaultWhenUndefined(row.weapon, DEFAULT_WEAPON);
    if (typeof weapon !== "string" || !weapon.trim()) throw Error("Explicit primary weapon required");
    const opponentWeapon = defaultWhenUndefined(row.opponentWeapon, opponentId === 449 ? weapon : null);
    if (opponentWeapon !== null && (opponentId !== 449 || typeof opponentWeapon !== "string" || !opponentWeapon)) {
      throw Error("Opponent primary override is only verified for unit 449");
    }
    const repeat = positiveInteger(row.repeat, 1, "repeat");
    const timeoutFrames = positiveInteger(row.timeoutFrames, 1800, "timeoutFrames");
    const spawnDistance = positiveInteger(row.distance, 650, "distance");
    const isElite = variant.id === 478 || variant.id === 479;
    const isShield = variant.id === 467 || variant.id === 479;
    const toughness = row.toughnessCoefficient;
    if (toughness !== undefined && (!Number.isFinite(toughness) || toughness < 1 || toughness > 100)) {
      throw Error("Bounded explicit toughness required");
    }
    const tableToughness = row.useDefaultToughness === true;
    if (row.useDefaultToughness !== undefined && typeof row.useDefaultToughness !== "boolean") {
      throw Error("useDefaultToughness must be boolean");
    }
    if (tableToughness && (!isElite || toughness !== authorities.tuning.toughnessCoefficient)) {
      throw Error("Expected default elite toughness must match its authority");
    }
    const effectiveToughness = toughness === undefined
      ? (isElite ? authorities.tuning.toughnessCoefficient : DEFAULT_TOUGHNESS.ordinary)
      : toughness;
    const shieldReduction = row.shieldReductionPercent;
    if (shieldReduction !== undefined
        && (!isShield || !Number.isFinite(shieldReduction) || shieldReduction < 0 || shieldReduction > 99)) {
      throw Error("Existing shield reduction override must be 0..99 on shield roots only");
    }
    const initialPhase = defaultWhenUndefined(row.initialPhase, isShield ? 1 : 2);
    if (![1, 2].includes(initialPhase)) throw Error("initialPhase must be 1 or 2");
    const defaultSidearm = authorities.units.get(variant.id).data.secondary;
    const sidearm = Object.prototype.hasOwnProperty.call(row, "sidearm") ? row.sidearm : defaultSidearm;
    const sidearm2 = Object.prototype.hasOwnProperty.call(row, "sidearm2") ? row.sidearm2 : authorities.units.get(variant.id).data.secondary2;
    if (sidearm !== null && (typeof sidearm !== "string" || !sidearm.trim())) {
      throw Error("sidearm must be null or a non-empty equipment string");
    }
    if (sidearm2 !== null && (typeof sidearm2 !== "string" || !sidearm2.trim())) throw Error("sidearm2 must be null or a non-empty equipment string");
    if (row.variant === "noSidearm" && (sidearm !== "FR506" || sidearm2 !== "FR506")) {
      throw Error("noSidearm must retain FR506 equipment and disable only its behavior");
    }
    if (isElite && (sidearm === null || sidearm2 === null)) throw Error("Explicit elite sidearm removal is not a verified plan input");
    const equipmentProfile = !isElite && sidearm === null && sidearm2 === null && effectiveToughness === DEFAULT_TOUGHNESS.ordinary
      ? "ordinary-stock"
      : isElite && sidearm === "FR506" && sidearm2 === "FR506" && effectiveToughness === authorities.tuning.toughnessCoefficient
        ? "elite-stock"
        : "custom";
    const dualWieldState = sidearm === null
      ? "not-equipped"
      : row.variant === "noSidearm"
        ? "equipped-ablated-noSidearm"
        : variant.behavior.startsWith("elite-retreat")
          ? initialPhase === 2 ? "equipped-active-phase2" : "equipped-phase2-only"
          : "equipped-behavior-inactive";
    const parameters = {
      "长枪": weapon,
      ...(sidearm !== null ? { "手枪": sidearm } : {}),
      ...(sidearm2 !== null ? { "手枪2": sidearm2 } : {}),
      ...(isElite ? { "特种兵精英诊断": true } : {}),
      ...(toughness !== undefined && !tableToughness ? { "韧性系数": toughness, "基础韧性系数": toughness } : {}),
      ...(shieldReduction !== undefined ? { "特种兵持盾减伤率": shieldReduction } : {}),
      ...(row.initialPhase !== undefined ? { "特种兵初始阶段": initialPhase } : {}),
      ...(variant.ablation ? { "特种兵精英消融": variant.ablation } : {}),
    };
    const candidate = { type: `兵种${variant.id}`, level, sourceId: "candidate", parameters };
    const rival = {
      type: `兵种${opponentId}`,
      level: opponentLevel,
      sourceId: "reference",
      ...(opponentWeapon !== null ? { parameters: { "长枪": opponentWeapon } } : {}),
    };
    const matchInputs = {
      baseUnitId: isShield ? 467 : 466,
      level,
      weapon,
      sidearm,
      sidearm2,
      toughnessCoefficient: effectiveToughness,
      shieldReductionPercent: shieldReduction === undefined ? null : shieldReduction,
      initialPhase,
    };
    const matchKey = "cf6-passive-v1:" + crypto.createHash("sha256").update(JSON.stringify(matchInputs)).digest("hex");
    const comparisonKey = row.pairKey === undefined ? row.id : row.pairKey;
    if (typeof comparisonKey !== "string" || !comparisonKey.trim() || comparisonKey.length > 128) {
      throw Error("A bounded comparison pairing key is required");
    }
    const authorityContext = {
      comparisonKey,
      variant: row.variant,
      unitId: variant.id,
      candidateSide: side,
      baseUnitId: matchInputs.baseUnitId,
      opponentId,
      opponentLevel,
      opponentWeapon,
      weapon,
      level,
      sidearm,
      sidearm2,
      sidearmBehavior: variant.behavior,
      passiveMatched: false,
      matchKey,
      matchInputs,
      passiveMatchScope: "standard equipment weight and cross-slot projections; no full-effective-panel equality claim",
      fullEffectivePanelEqualityClaim: "not-claimed",
      equipmentProfile,
      dualWieldState,
      toughnessCoefficient: toughness === undefined ? null : toughness,
      effectiveToughnessCoefficient: effectiveToughness,
      toughnessSource: tableToughness ? "unit-table" : toughness === undefined ? "unit-table-unspecified" : "constructor-override",
      shieldReductionPercent: shieldReduction === undefined ? null : shieldReduction,
      initialPhase,
      noPairwiseRngClaim: true,
      blueFriendlyHpMultiplierReportedSeparately: true,
      sourceBindings,
    };
    const testCase = {
      caseId: row.id,
      repeat,
      timeoutFrames,
      spawnDistance,
      blueFormation: "line",
      redFormation: "line",
      formationSpacing: 54,
      blueRoster: [side === "blue" ? candidate : rival],
      redRoster: [side === "red" ? candidate : rival],
      tags: ["cf6-elite", row.variant, side, "inherited-base-panel", "same-primary",
        sidearm === null ? "no-sidearm-equipped" : "sidearm-equipped"],
      plannerReason: "同阵营对应基础面板、同型号同强化长枪及相同出生条件；不换边合并蓝方人形三倍生命。noSidearm保留FR506装备，仅禁用副枪行为；被动匹配只覆盖标准装备重量和跨槽投影，不声称完整有效面板绝对相同。",
      authorityContext,
    };
    return { testCase, matchKey, variant: row.variant };
  });
  const ids = new Set();
  const matches = new Map();
  for (const entry of prepared) {
    if (ids.has(entry.testCase.caseId)) throw Error(`Duplicate case id: ${entry.testCase.caseId}`);
    ids.add(entry.testCase.caseId);
    if (!matches.has(entry.matchKey)) matches.set(entry.matchKey, new Set());
    matches.get(entry.matchKey).add(entry.variant);
  }
  for (const entry of prepared) {
    const matched = matches.get(entry.matchKey).size > 1;
    entry.testCase.authorityContext.passiveMatched = matched;
    if (matched) entry.testCase.tags.push("passive-matched");
  }
  return prepared.map((entry) => entry.testCase);
}

function create(config, dependencies = {}) {
  const { candidateRoot, outputDirectory, batchId } = config;
  if (!path.isAbsolute(candidateRoot || "")
      || !path.resolve(candidateRoot).startsWith(path.join(ROOT, "tmp/runtime-candidates/v2") + path.sep)) {
    throw Error("Explicit isolated candidate required");
  }
  if (!path.isAbsolute(outputDirectory || "")
      || !path.resolve(outputDirectory).startsWith(path.join(ROOT, "tmp") + path.sep)) {
    throw Error("Plans belong in this checkout's tmp directory");
  }
  if (!/^[a-z0-9-]{1,40}$/.test(batchId || "")) throw Error("Fresh bounded batch id required");
  const sourceBindings = dependencies.sourceBindings || bindSources();
  const cases = buildCases(config.comparisons, { sourceBindings });
  const buildCommit = dependencies.buildCommit || cp.execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: ROOT, encoding: "utf8", windowsHide: true,
  }).trim();
  const manifest = normalizeManifest({
    batchId,
    buildCommit,
    planner: { name: "cf6-elite-controlled-comparison", version: 2 },
    repeat: 1,
    timeoutFrames: 1800,
    cases,
  });
  const worst = manifest.cases.reduce((total, testCase) =>
    total + testCase.repeat * testCase.timeoutFrames / 30 * 1000, 0);
  if (!Number.isSafeInteger(Math.ceil(worst)) || worst > 900000) {
    throw Error("Split comparison into batches under 15 minutes");
  }
  fs.mkdirSync(outputDirectory, { recursive: true });
  const write = (name, data) => fs.writeFileSync(path.join(outputDirectory, name), `${JSON.stringify(data, null, 2)}\n`, { flag: "wx" });
  const manifestPath = path.join(outputDirectory, "manifest.json");
  const slot = `cf7_agent_${batchId.replace(/-/g, "_")}`;
  const hashes = Object.fromEntries(sourceBindings.map((binding) => [binding.path, binding.sha256]));
  write("manifest.json", manifest);
  write("source-identity.json", {
    buildCommit,
    hashes,
    scope: "development comparison; no production roster recommendation",
    passiveMatchScope: "standard equipment weight and cross-slot projections only",
    fullEffectivePanelEqualityClaim: "not-claimed",
  });
  write("evidence-config.json", { resourceRoot: ROOT, candidateRoot, manifestPath, slot, allowNaturalTimeout: true });
  return {
    manifestPath,
    slot,
    worstCaseMs: worst,
    rows: cases.reduce((total, testCase) => total + testCase.repeat, 0),
    candidateRoot,
  };
}

if (require.main === module) {
  if (process.argv.length !== 3) throw Error("Usage: node elite-arena-plan.js <explicit-config.json>");
  const result = create(JSON.parse(fs.readFileSync(process.argv[2], "utf8")));
  console.log(JSON.stringify(result));
}

module.exports = {
  DEFAULT_TOUGHNESS,
  ROOT,
  SOURCE_PATHS,
  VARIANTS,
  bindSources,
  buildCases,
  create,
  hashFile,
  positiveInteger,
  validateAuthorities,
};
