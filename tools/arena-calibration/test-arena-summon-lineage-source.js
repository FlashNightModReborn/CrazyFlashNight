#!/usr/bin/env node
"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "../..");
const servicePath = path.join(
  ROOT, "scripts", "类定义", "org", "flashNight", "arki", "merc", "ArenaCalibrationService.as",
);
const serviceBytes = fs.readFileSync(servicePath);
assert.deepStrictEqual(Array.from(serviceBytes.slice(0, 3)), [0xef, 0xbb, 0xbf]);
const service = serviceBytes.toString("utf8");
assert(service.includes("initObject.产生源"));
assert(service.includes("sourceName == parentName || sourceName == parentSpawnName"));
assert(service.includes("registerPhaseSpawnedUnit(parentRecord, unitType, String(child._name || name), child, child)"));

const library = path.join(ROOT, "flashswf", "arts", "things4", "LIBRARY");
const symbol691 = fs.readFileSync(path.join(library, "Symbol 691.xml"), "utf8");
const symbol692 = fs.readFileSync(path.join(library, "Symbol 692.xml"), "utf8");
const symbol698 = fs.readFileSync(path.join(library, "Symbol 698.xml"), "utf8");
[symbol691, symbol692].forEach((source) => {
  assert(source.includes("if (_parent._arenaCalibrationUnit === true) 产生源名 = _parent._name;"));
  assert(source.includes("产生源:产生源名"));
});
const directNameBindings = symbol698.match(/僵尸型敌人newname = \(_parent\._parent\._arenaCalibrationUnit === true/g) || [];
const directSourceBindings = symbol698.match(/产生源:\(_parent\._parent\._arenaCalibrationUnit === true/g) || [];
assert.strictEqual(directNameBindings.length, 16);
assert.strictEqual(directSourceBindings.length, 16);
assert.strictEqual(symbol698.includes("产生源:this._name"), false);

console.log(JSON.stringify({
  ok: true,
  check: "arena-summon-lineage-source",
  trackedSpawnerBindings: 18,
  as2Utf8Bom: true,
  normalGameplayFallbackPreserved: true,
}));
