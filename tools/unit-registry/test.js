"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { pathToFileURL } = require("node:url");
const vm = require("node:vm");
const { UnitRegistry, validKey, extractDirectChildXml } = require("../lib/unit-registry");
const cases = JSON.parse(fs.readFileSync(path.join(__dirname, "cases.json"), "utf8"));
const registry = new UnitRegistry(cases.units);
let passed = 0;
function check(run) { run(); passed++; }

for (const item of cases.references) {
  check(() => assert.equal(registry.resolveType(item.input), item.expected));
}
for (const value of cases.rejectedReferences) {
  check(() => assert.throws(() => registry.resolveType(value, "fixture.Type"), /fixture.Type/));
}
for (const value of cases.validKeys) check(() => assert.equal(validKey(value), true));
for (const value of cases.invalidKeys) check(() => assert.equal(validKey(value), false));
check(() => assert.equal(validKey("x." + "甲".repeat(94)), true));
check(() => assert.equal(validKey("x." + "甲".repeat(95)), false));
check(() => assert.equal(registry.resolveId(0), 0));
check(() => assert.equal(registry.get("cf6.特种兵.二阶段").id, 466));
check(() => assert.equal(registry.byId.size, cases.units.length));
for (const value of [true, null, -1, 1.5, Infinity, NaN, "466"]) {
  check(() => assert.throws(() => registry.resolveId(value)));
}
for (const bad of [null, [], {}, [{ id: true, spritename: "x" }],
  [{ id: -1, spritename: "x" }], [{ id: 1.5, spritename: "x" }],
  [{ id: Infinity, spritename: "x" }], [{ id: 2147483648, spritename: "x" }],
  [{ id: 0, spritename: "" }], [{ id: 0, spritename: "x", key: null }],
  cases.units.concat(cases.units[0]), cases.units.concat({ id: 500, spritename: "x", key: "测试.零号" })]) {
  check(() => assert.throws(() => new UnitRegistry(bad)));
}
check(() => assert.equal(new UnitRegistry([{ id: 1.0, spritename: "x", key: "测试.整数" }])
  .resolveType("测试.整数"), "兵种1"));

// Exercise the real production extractor without running its file-writing CLI.
const source = fs.readFileSync(path.join(__dirname, "../derive-arena-meta-teams.js"), "utf8");
function take(name) {
  const start = source.indexOf("function " + name + "(");
  const end = source.indexOf("\n}", start) + 2;
  assert(start >= 0 && end > start, "production function not found: " + name);
  return source.slice(start, end);
}
const context = vm.createContext({ unitRegistry: registry, extractDirectChildXml });
vm.runInContext(["tag1", "parseScalar", "addObjectValue", "parseStringParameters", "parseParameterBody",
  "stableNormalize", "hasParameters", "extractEnemies"].map(take).join("\n"), context);
function extract(xml) {
  context.input = xml;
  return JSON.parse(JSON.stringify(vm.runInContext("extractEnemies(input, 'fixture.xml')", context)));
}
const enemy = type => "<Enemy><Type>" + type + "</Type><Level>30</Level><Quantity>3</Quantity>"
  + "<Parameters><NPC>true</NPC><Type>opaque.parameter</Type></Parameters></Enemy>";
check(() => assert.deepEqual(extract(enemy("cf6.特种兵.二阶段")), extract(enemy("兵种466"))));
check(() => assert.equal(extract(enemy("cf6.特种兵.二阶段"))[0].parameters.Type, "opaque.parameter"));
const branches = "<CaseSwitch expression=\"must_not_evaluate\"><Case>cf6.特种兵.二阶段</Case>"
  + "<Case>兵种1</Case><Case>cf6.特种兵.持盾一阶段</Case><Case>cf6.特种兵.二阶段</Case></CaseSwitch>";
check(() => assert.deepEqual(extract(enemy(branches))[0].types, ["兵种466", "兵种1", "兵种467", "兵种466"]));
check(() => assert.throws(() => extract(enemy("cf6.拼错")), /fixture.xml.*unknown unit reference/));
check(() => assert.throws(() => extract(enemy(branches.replace("兵种1", "兵种999999"))), /unknown unit reference/));
check(() => assert.throws(() => extract(enemy(branches.replace("兵种1", ""))), /unknown unit reference/));
check(() => assert.deepEqual(extract("<Enemy><spritename>敌人-内联</spritename></Enemy>"), []));
check(() => assert.deepEqual(extract("<Enemy><Parameters><Type>cf6.特种兵.二阶段</Type></Parameters><spritename>敌人-内联</spritename></Enemy>"), []));
check(() => assert.equal(extractDirectChildXml('<Parameters><Type>opaque</Type></Parameters><Type>兵种466</Type>', 'Type'), '兵种466'));
check(() => assert.equal(extractDirectChildXml('<Attribute note="x > y"><Type>opaque</Type></Attribute><!-- <Type>fake</Type> --><Type>cf6.特种兵.二阶段</Type>', 'Type'), 'cf6.特种兵.二阶段'));
check(() => assert.equal(extractDirectChildXml('<Type/>', 'Type'), ''));
check(() => assert.throws(() => extract(enemy('兵种466').replace('</Enemy>', '<Type>兵种467</Type></Enemy>')), /duplicate direct Type/));
check(() => assert.deepEqual(extract('<Enemy><RandomType><Type>兵种466</Type><Type>兵种467</Type></RandomType><Level>30</Level></Enemy>')[0].types, ['兵种466']));
check(() => assert.throws(() => extract(enemy(' cf6.特种兵.二阶段 ')), /fixture.xml.*unknown unit reference/));
check(() => assert.throws(() => extract(enemy(branches.replace('兵种1', ' cf6.特种兵.二阶段 '))), /fixture.xml.*unknown unit reference/));

(async () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-ts-"));
  const repo = fs.mkdtempSync(path.join(os.tmpdir(), "cf7-repo-"));
  try {
    const srcDir = path.join(__dirname, "../cf7-balance-tool/packages/xml-io/src");
    for (const file of ["document.ts", "monster-stage.ts"]) {
      const src = fs.readFileSync(path.join(srcDir, file), "utf8")
        .replaceAll("./document.js", "./document.ts")
        .replaceAll("./monster-stage.js", "./monster-stage.ts")
        .replaceAll("../../../../lib/unit-registry.js", pathToFileURL(path.resolve(__dirname, "../lib/unit-registry.js")).href);
      fs.writeFileSync(path.join(tmp, file), src, "utf8");
    }
    const { buildStageIndex } = await import(pathToFileURL(path.join(tmp, "monster-stage.ts")).href);
    fs.mkdirSync(path.join(repo, "data/stages/基地门口"), { recursive: true });
    fs.mkdirSync(path.join(repo, "data/units"), { recursive: true });
    fs.mkdirSync(path.join(repo, "data/task"), { recursive: true });
    fs.writeFileSync(path.join(repo, "data/stages/基地门口/__list__.xml"), "<root><StageInfo><Name>废城街头</Name><Type>主线</Type><UnlockCondition>1</UnlockCondition></StageInfo></root>");
    fs.writeFileSync(path.join(repo, "data/stages/基地门口/废城街头.xml"), "<GameStage><SubStage id=\"0\"><Event><Dialogue id=\"0\"><Type>测试.单位1</Type></Dialogue></Event></SubStage></GameStage>");
    fs.writeFileSync(path.join(repo, "data/units/units.json"), JSON.stringify([
      { id: 1, key: "测试.单位1", spritename: "敌人-主线怪" },
      { id: 2, key: "测试.单位2", spritename: "敌人-支线怪" }
    ]));
    fs.writeFileSync(path.join(repo, "data/task/list.xml"), "<root><task>t.json</task></root>");
    fs.writeFileSync(path.join(repo, "data/task/t.json"), JSON.stringify({ tasks: [] }));
    const cfg = { chapters: { 基地门口: 1 }, stageChapterOverrides: {}, excludedStagePatterns: ["菲尼克斯"], mainlineCompletedUntil: 77, mainlineBands: [{ from: 1, to: 22, stage: 1, label: "废城" }] };
    check(() => assert.deepEqual(buildStageIndex(repo, cfg).spawnStagesBySprite.get("敌人-主线怪"), ["废城街头"]));
    fs.writeFileSync(path.join(repo, "data/stages/基地门口/废城街头.xml"), "<GameStage><SubStage id=\"0\"><Event><Dialogue id=\"0\"><Type>测试.单位1</Type><Type>测试.单位2</Type></Dialogue></Event></SubStage></GameStage>");
    const overrideIdx = buildStageIndex(repo, cfg);
    check(() => assert.equal(overrideIdx.spawnStagesBySprite.get("敌人-主线怪"), undefined));
    check(() => assert.deepEqual(overrideIdx.spawnStagesBySprite.get("敌人-支线怪"), ["废城街头"]));
    fs.writeFileSync(path.join(repo, "data/stages/基地门口/废城街头.xml"), "<GameStage><SubStage id=\"0\"><Event><Dialogue id=\"0\"><Type>测试.拼错</Type><Type>测试.单位2</Type></Dialogue></Event></SubStage></GameStage>");
    check(() => assert.throws(() => buildStageIndex(repo, cfg), /unknown unit reference/));
    fs.writeFileSync(path.join(repo, "data/stages/基地门口/废城街头.xml"), "<GameStage><SubStage id=\"0\"><EnemyGroup><Enemy><Type> 测试.单位1 </Type></Enemy></EnemyGroup></SubStage></GameStage>");
    check(() => assert.throws(() => buildStageIndex(repo, cfg), /unknown unit reference/));
    const rootDir = path.resolve(__dirname, "../..");
    const realIdx = buildStageIndex(rootDir, cfg);
    check(() => assert.ok(realIdx.spawnStagesBySprite.size > 0));
  } finally {
    fs.rmSync(tmp, { recursive: true, force: true });
    fs.rmSync(repo, { recursive: true, force: true });
  }
  console.log("unit-registry JavaScript: " + passed + " checks passed (production tools only; no AVM1 execution)");
})();
