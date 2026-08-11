#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");
const { projectDressupPortrait } = require("./lib/arena-portrait-routing");

const ROOT = path.resolve(__dirname, "..");
const SOURCE_PATH = path.join(ROOT, "data", "units", "units.json");
const OUTPUT_PATH = path.join(ROOT, "launcher", "web", "modules", "arena-unit-catalog.js");
const ARTS_PATH = path.join(ROOT, "flashswf", "arts");

const FACTION_RULES = [
  { re: /盗贼/, faction: "堕落城" },
  { re: /贝斯|主唱|鼓手|吉他|键盘|摇滚/, faction: "摇滚公园" },
  { re: /军阀|游寇|革命军/, faction: "军阀势力" },
  { re: /黑铁/, faction: "黑铁会" },
  { re: /终结者|天网|机器人|机械|无人机|炮台|EXUSIAI|克隆/, faction: "天网" },
  { re: /凤凰眷属/, faction: "凤凰眷属" },
  { re: /方舟/, faction: "方舟" },
  { re: /异形|奇美拉|徘徊者|吐酸者|美洲狮|渗透者|原体融合/, faction: "异形" },
  { re: /日本/, faction: "日本军" },
  { re: /波斯/, faction: "波斯军" },
  { re: /斯巴达|罗马军团/, faction: "斯巴达" },
  { re: /不死/, faction: "不死军团" },
  { re: /忍者/, faction: "忍者" },
  { re: /僵尸|尸|亡灵|骷髅/, faction: "亡灵/僵尸" },
  { re: /基因虫|虫|寄生|孢子|母巢/, faction: "虫群" },
  { re: /狂野玫瑰|玫瑰|少女|萝莉|姑娘|女仆|护士/, faction: "狂野玫瑰" },
  { re: /雪女|霜精|冰/, faction: "雪山" },
  { re: /魔神|恶魔|魔女/, faction: "魔神" },
  { re: /大学|学生|教师|老师/, faction: "联合大学" },
  { re: /铁血/, faction: "铁血" },
];

function factionFor(spritename) {
  const text = String(spritename || "");
  for (let i = 0; i < FACTION_RULES.length; i += 1) {
    if (FACTION_RULES[i].re.test(text)) return FACTION_RULES[i].faction;
  }
  return "未归类";
}

function summarizeSlots(data) {
  const slots = [];
  if (!data || typeof data !== "object") return slots;
  ["primary", "secondary", "secondary2", "melee"].forEach((key) => {
    const value = data[key];
    if (value == null || value === "") return;
    if (typeof value === "string" || typeof value === "number") {
      slots.push({ slot: key, value: String(value) });
    } else if (typeof value === "object") {
      const name = value.name || value.weapon || value.id || value.type || "";
      if (name) slots.push({ slot: key, value: String(name) });
    }
  });
  return slots;
}

function collectXmlFiles(dir, out) {
  if (!fs.existsSync(dir)) return out;
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  entries.forEach((entry) => {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectXmlFiles(fullPath, out);
    } else if (entry.isFile() && entry.name.toLowerCase().endsWith(".xml")) {
      out.push(fullPath);
    }
  });
  return out;
}

function extractSpawnedSpritename(xml) {
  const direct = xml.match(/加载游戏世界人物\s*\(\s*["']([^"']+)["']/);
  if (direct) return direct[1];

  const assigned = xml.match(/(?:var\s+)?兵种\s*=\s*["']([^"']+)["']/);
  if (assigned) return assigned[1];

  const target = xml.match(/目标兵种\s*=\s*\{[^}]*兵种\s*:\s*["']([^"']+)["']/);
  if (target) return target[1];

  return "";
}

function derivePhaseSpawns(rawUnits) {
  const unitTypesBySprite = new Map();
  rawUnits.forEach((unit) => {
    const spritename = unit && unit.spritename ? String(unit.spritename) : "";
    if (!spritename) return;
    const unitType = "兵种" + Number(unit.id);
    if (!unitTypesBySprite.has(spritename)) unitTypesBySprite.set(spritename, []);
    unitTypesBySprite.get(spritename).push(unitType);
  });

  const xmlFiles = collectXmlFiles(ARTS_PATH, []);
  const phaseSymbols = new Map();
  const parentRefs = new Map();

  xmlFiles.forEach((filePath) => {
    const dir = path.dirname(filePath);
    const itemName = path.basename(filePath, ".xml");
    const xml = fs.readFileSync(filePath, "utf8");
    const refs = Array.from(xml.matchAll(/libraryItemName="([^"]+)"/g)).map((match) => match[1]);
    if (refs.length > 0) parentRefs.set(filePath, refs);

    if (!/加载游戏世界人物/.test(xml)) return;
    if (!/死亡检测\s*\(\s*\{\s*noCount\s*:\s*true/.test(xml)) return;
    const spritename = extractSpawnedSpritename(xml);
    if (!spritename) return;

    phaseSymbols.set(dir + "\0" + itemName, {
      trigger: "death",
      symbol: itemName,
      spritename,
      unitTypes: unitTypesBySprite.get(spritename) || [],
    });
  });

  const phaseSpawnsBySprite = new Map();
  parentRefs.forEach((refs, filePath) => {
    const dir = path.dirname(filePath);
    const spritename = path.basename(filePath, ".xml");
    const found = [];
    const seen = new Set();
    refs.forEach((ref) => {
      const spawn = phaseSymbols.get(dir + "\0" + ref);
      if (!spawn) return;
      const key = spawn.symbol + "\0" + spawn.spritename;
      if (seen.has(key)) return;
      seen.add(key);
      found.push(spawn);
    });
    if (found.length > 0) phaseSpawnsBySprite.set(spritename, found);
  });

  return phaseSpawnsBySprite;
}

function normalizeUnit(unit, phaseSpawnsBySprite) {
  const id = Number(unit.id);
  const spritename = unit.spritename ? String(unit.spritename) : "";
  const normalized = {
    id,
    type: "兵种" + id,
    name: unit.name ? String(unit.name) : ("兵种" + id),
    spritename,
    level: Number(unit.level) > 0 ? Number(unit.level) : 1,
    isHostile: unit.is_hostile === true,
    faction: factionFor(unit.spritename),
    height: Number(unit.height) > 0 ? Number(unit.height) : 0,
    slots: summarizeSlots(unit.data),
  };
  const portrait = projectDressupPortrait(unit);
  if (portrait) normalized.portrait = portrait;
  const phaseSpawns = phaseSpawnsBySprite.get(spritename);
  if (phaseSpawns && phaseSpawns.length > 0) {
    normalized.multiPhase = true;
    normalized.phaseSpawns = phaseSpawns;
  }
  return normalized;
}

function buildModule() {
  const raw = JSON.parse(fs.readFileSync(SOURCE_PATH, "utf8"));
  if (!Array.isArray(raw)) {
    throw new Error("data/units/units.json must be an array");
  }
  const phaseSpawnsBySprite = derivePhaseSpawns(raw);
  const units = raw
    .map((unit) => normalizeUnit(unit, phaseSpawnsBySprite))
    .sort((a, b) => a.id - b.id);
  const hostileCount = units.filter((unit) => unit.isHostile).length;
  const multiPhaseCount = units.filter((unit) => unit.multiPhase === true).length;

  const payload = {
    schema: "arena-unit-catalog.v2",
    source: "data/units/units.json",
    phaseSource: "flashswf/arts/**/LIBRARY/*.xml",
    generatedBy: "tools/derive-arena-unit-catalog.js",
    rawCount: raw.length,
    unitCount: units.length,
    hostileCount,
    multiPhaseCount,
    units,
  };

  return [
    "// AUTO-GENERATED by tools/derive-arena-unit-catalog.js — 请勿手改，改 data/units/units.json 后重跑。",
    "// 定制死亡竞赛单位浏览器目录；全量暴露 units.json，is_hostile 只作为 UI 标签，faction 仅用于浏览器分组。",
    "(function() {",
    "    'use strict';",
    "    window.ArenaUnitCatalog = " + JSON.stringify(payload) + ";",
    "})();",
    "",
  ].join("\n");
}

function main() {
  const expected = buildModule();
  const check = process.argv.indexOf("--check") >= 0;
  const current = fs.existsSync(OUTPUT_PATH) ? fs.readFileSync(OUTPUT_PATH, "utf8") : "";

  if (check) {
    if (current !== expected) {
      throw new Error("launcher/web/modules/arena-unit-catalog.js is stale; run node tools/derive-arena-unit-catalog.js");
    }
    console.log("[derive-arena-unit-catalog] up-to-date");
    return;
  }

  fs.mkdirSync(path.dirname(OUTPUT_PATH), { recursive: true });
  if (current !== expected) {
    fs.writeFileSync(OUTPUT_PATH, expected, "utf8");
    console.log("[derive-arena-unit-catalog] wrote " + path.relative(ROOT, OUTPUT_PATH));
  } else {
    console.log("[derive-arena-unit-catalog] unchanged");
  }
}

try {
  main();
} catch (error) {
  console.error(error.message);
  process.exit(1);
}
