#!/usr/bin/env node
"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const STAGES_DIR = path.join(ROOT, "data", "stages");
const UNITS_PATH = path.join(ROOT, "data", "units", "units.json");
const OUTPUT_PATH = path.join(ROOT, "launcher", "web", "modules", "arena-unit-param-presets.js");
const CHECK_ONLY = process.argv.indexOf("--check") >= 0;

const SKIP_FILES = new Set(["list.xml", "loading_data.xml", "__list__.xml"]);
const WEAPON_KEYS = ["长枪", "手枪", "手枪2", "刀", "手雷"];

function stableHash(text) {
  return crypto.createHash("sha1").update(String(text), "utf8").digest("hex");
}

function normalizeUnitId(value) {
  if (value == null) return null;
  const text = String(value).trim();
  const match = text.match(/^兵种([0-9]+)$/) || text.match(/^u([0-9]+)$/i);
  if (match) return Number(match[1]);
  if (/^[0-9]+$/.test(text)) return Number(text);
  return null;
}

function walk(dir, out) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full, out);
    else if (entry.name.toLowerCase().endsWith(".xml") && !SKIP_FILES.has(entry.name)) out.push(full);
  }
  return out;
}

function tagText(xml, tagName) {
  const re = new RegExp("<" + tagName + "(?:\\s[^>]*)?>\\s*([\\s\\S]*?)\\s*</" + tagName + ">", "i");
  const match = xml.match(re);
  return match ? match[1].trim() : null;
}

function parseScalar(value) {
  const text = String(value == null ? "" : value).trim();
  if (text === "true") return true;
  if (text === "false") return false;
  if (/^-?(?:\d+|\d+\.\d+)$/.test(text)) return Number(text);
  return text;
}

function addObjectValue(obj, key, value) {
  if (Object.prototype.hasOwnProperty.call(obj, key)) {
    if (!Array.isArray(obj[key])) obj[key] = [obj[key]];
    obj[key].push(value);
  } else {
    obj[key] = value;
  }
}

function parseStringParameters(text) {
  const out = {};
  const parts = String(text || "").split(",");
  let parsed = 0;
  for (let i = 0; i < parts.length; i += 1) {
    const part = parts[i].trim();
    if (!part) continue;
    const idx = part.indexOf(":");
    if (idx <= 0) continue;
    const key = part.slice(0, idx).trim();
    const value = part.slice(idx + 1).trim();
    if (!key) continue;
    out[key] = parseScalar(value);
    parsed += 1;
  }
  return parsed > 0 ? out : null;
}

function parseParameterBody(xml) {
  const text = String(xml == null ? "" : xml).trim();
  if (!text) return {};

  if (text.indexOf("<") < 0) {
    return parseStringParameters(text) || { value: parseScalar(text) };
  }

  const out = {};
  const childRe = /<([^\s/>]+)(?:\s[^>]*)?>\s*([\s\S]*?)\s*<\/\1>/g;
  let match;
  let count = 0;
  while ((match = childRe.exec(text))) {
    count += 1;
    const key = match[1];
    const body = match[2].trim();
    const value = body.indexOf("<") >= 0 ? parseParameterBody(body) : parseScalar(body);
    addObjectValue(out, key, value);
  }

  return count > 0 ? out : (parseStringParameters(text) || { value: parseScalar(text) });
}

function stableNormalize(value) {
  if (Array.isArray(value)) return value.map(stableNormalize);
  if (value && typeof value === "object") {
    const out = {};
    Object.keys(value).sort().forEach(key => {
      out[key] = stableNormalize(value[key]);
    });
    return out;
  }
  return value;
}

function stableStringify(value) {
  return JSON.stringify(stableNormalize(value));
}

function collectKeys(value, out) {
  if (!value || typeof value !== "object") return out;
  if (Array.isArray(value)) {
    value.forEach(item => collectKeys(item, out));
    return out;
  }
  Object.keys(value).forEach(key => {
    out[key] = true;
    collectKeys(value[key], out);
  });
  return out;
}

function summarizeParameters(parameters) {
  const parts = [];
  for (let i = 0; i < WEAPON_KEYS.length; i += 1) {
    const key = WEAPON_KEYS[i];
    if (parameters[key] != null && parameters[key] !== "") parts.push(key + "=" + String(parameters[key]));
  }
  if (parts.length > 0) return parts.join(" / ");

  const keys = Object.keys(collectKeys(parameters, {})).sort();
  for (let i = 0; i < keys.length && parts.length < 3; i += 1) {
    const value = parameters[keys[i]];
    if (value == null || typeof value === "object") parts.push(keys[i]);
    else parts.push(keys[i] + "=" + String(value));
  }
  return parts.join(" / ") || "参数预设";
}

function cleanUnitName(unit, id) {
  const name = String(unit && unit.name || "");
  if (name && name !== "???" && name !== "null") return name;
  const sprite = String(unit && unit.spritename || "");
  return sprite ? sprite.replace(/^敌人-/, "") : ("兵种" + id);
}

function modeLevel(levelCounts, fallback) {
  let bestLevel = fallback;
  let bestCount = -1;
  Object.keys(levelCounts).forEach(level => {
    const count = levelCounts[level];
    const numeric = Number(level);
    if (count > bestCount || (count === bestCount && numeric < Number(bestLevel))) {
      bestCount = count;
      bestLevel = numeric;
    }
  });
  return Number(bestLevel) > 0 ? Number(bestLevel) : 1;
}

function buildPresets() {
  const units = JSON.parse(fs.readFileSync(UNITS_PATH, "utf8"));
  const byType = {};
  units.forEach(unit => {
    byType["兵种" + unit.id] = unit;
  });

  const files = walk(STAGES_DIR, []);
  const records = {};
  let enemyWithParameters = 0;
  let skippedUnknownType = 0;

  files.forEach(file => {
    const rel = path.relative(STAGES_DIR, file).replace(/\\/g, "/");
    const xml = fs.readFileSync(file, "utf8");
    const enemyRe = /<Enemy\b[^>]*>([\s\S]*?)<\/Enemy>/g;
    let match;
    while ((match = enemyRe.exec(xml))) {
      const body = match[1];
      const type = tagText(body, "Type");
      const parametersBody = tagText(body, "Parameters");
      if (!parametersBody) continue;
      enemyWithParameters += 1;
      if (!type || !/^兵种\d+$/.test(type.trim()) || !byType[type.trim()]) {
        skippedUnknownType += 1;
        continue;
      }

      const unitType = type.trim();
      const id = normalizeUnitId(unitType);
      const unit = byType[unitType];
      const parameters = stableNormalize(parseParameterBody(parametersBody));
      const signature = stableStringify(parameters);
      const key = unitType + "::" + signature;
      const level = Number(tagText(body, "Level"));

      if (!records[key]) {
        records[key] = {
          type: unitType,
          id,
          name: cleanUnitName(unit, id),
          spritename: unit.spritename || "",
          parameters,
          parameterSignature: signature,
          count: 0,
          sources: [],
          levelCounts: {},
          keys: collectKeys(parameters, {})
        };
      }

      const rec = records[key];
      rec.count += 1;
      if (rec.sources.length < 8 && rec.sources.indexOf(rel) < 0) rec.sources.push(rel);
      if (!isNaN(level) && level > 0) rec.levelCounts[Math.floor(level)] = (rec.levelCounts[Math.floor(level)] || 0) + 1;
    }
  });

  const presets = Object.keys(records).map(key => {
    const rec = records[key];
    const summary = summarizeParameters(rec.parameters);
    const defaultLevel = modeLevel(rec.levelCounts, 1);
    return {
      id: "param-" + stableHash(rec.type + "|" + rec.parameterSignature).slice(0, 12),
      type: rec.type,
      unitId: rec.id,
      unitName: rec.name,
      spritename: rec.spritename,
      label: rec.name + " / " + summary,
      summary,
      parameters: rec.parameters,
      parameterKeys: Object.keys(rec.keys).sort(),
      defaultLevel,
      count: rec.count,
      sourceStages: rec.sources
    };
  }).sort((a, b) => {
    if (a.unitId !== b.unitId) return a.unitId - b.unitId;
    if (a.summary === b.summary) return 0;
    return a.summary > b.summary ? 1 : -1;
  });

  const byUnit = {};
  const byId = {};
  presets.forEach(preset => {
    const key = String(preset.unitId);
    if (!byUnit[key]) byUnit[key] = [];
    byUnit[key].push(preset);
    byId[preset.id] = preset;
  });

  return {
    meta: {
      schema: "arena-unit-param-presets.v1",
      generatedBy: "tools/derive-arena-unit-param-presets.js",
      source: "data/stages/**",
      enemyWithParameters,
      skippedUnknownType,
      presetCount: presets.length,
      unitCount: Object.keys(byUnit).length
    },
    data: {
      schema: "arena-unit-param-presets.v1",
      presets,
      byUnit,
      byId
    }
  };
}

function buildModule() {
  const built = buildPresets();
  return [
    "// AUTO-GENERATED by tools/derive-arena-unit-param-presets.js — 请勿手改，改关卡 XML 后重跑。",
    "// 竞技场定制赛单位参数预设：从 data/stages/** 的 Enemy Type + Parameters 派生。",
    "(function() {",
    "    'use strict';",
    "    if (typeof window === \"undefined\") return;",
    "    window.ArenaUnitParameterPresetsMeta = " + JSON.stringify(built.meta) + ";",
    "    window.ArenaUnitParameterPresets = " + JSON.stringify(built.data) + ";",
    "})();",
    ""
  ].join("\n");
}

function main() {
  const expected = buildModule();
  const current = fs.existsSync(OUTPUT_PATH) ? fs.readFileSync(OUTPUT_PATH, "utf8") : "";
  if (CHECK_ONLY) {
    if (current !== expected) {
      throw new Error("launcher/web/modules/arena-unit-param-presets.js is stale; run node tools/derive-arena-unit-param-presets.js");
    }
    console.log("[derive-arena-unit-param-presets] up-to-date");
    return;
  }

  fs.mkdirSync(path.dirname(OUTPUT_PATH), { recursive: true });
  if (current !== expected) {
    fs.writeFileSync(OUTPUT_PATH, expected, "utf8");
    console.log("[derive-arena-unit-param-presets] wrote " + path.relative(ROOT, OUTPUT_PATH));
  } else {
    console.log("[derive-arena-unit-param-presets] unchanged");
  }
}

try {
  main();
} catch (error) {
  console.error(error && error.message ? error.message : String(error));
  process.exit(1);
}
