"use strict";
// Reference-model checks execute source slices. Only the native runner proves AVM1 timelines.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");
const aiXml = fs.readFileSync("flashswf/arts/things5/LIBRARY/Symbol 654.xml", "utf8");
const unitSource = fs.readFileSync("scripts/逻辑/单位函数/单位函数_lsy_敌人模板迁移.as", "utf8");
function sourceFunction(name) {
    const pattern = new RegExp("^_root\\.敌人函数\\." + name + " = function\\([^\\r\\n]*\\) \\{[\\s\\S]*?^\\};", "gm");
    const matches = [...unitSource.matchAll(pattern)];
    assert.equal(matches.length, 1, "unambiguous production function: " + name);
    return matches[0][0];
}
const aiScript = aiXml.match(/<script><!\[CDATA\[([\s\S]*?)\]\]><\/script>/)[1];
const attackStart = aiScript.indexOf("function 攻击(");
assert.ok(attackStart >= 0);
let end = aiScript.indexOf("{", attackStart), depth = 1;
while (depth) { end++; if (aiScript[end] === "{") depth++; if (aiScript[end] === "}") depth--; }
const attack = aiScript.slice(attackStart, end + 1).replace(/\bor\b/g, "||").replace(/\band\b/g, "&&");
const fixedEntry = '_parent.状态改变(_parent.攻击模式 + "攻击");';
const legacyEntry = '_parent.gotoAndStop(_parent.攻击模式 + "攻击");';
assert.equal(attack.split(fixedEntry).length - 1, 1, "one attack admission through production state API");
assert.ok(!attack.includes(legacyEntry), "no direct parent attack jump");
const productionFunctions = sourceFunction("状态改变") + "\n" + sourceFunction("动画完毕");
function fixture(start, legacy = false, left = false) {
    const unit = { 状态: start, 攻击模式: "空手", hp: 100, _x: 200, _y: 200, 攻击目标: "target",
        jumps: [], aabbCollider: { updateFromUnitArea() {} },
        gotoAndStop(label) { this.animation = label; this.jumps.push(label); },
        方向改变(direction) { this.direction = direction; }
    };
    unit.animation = start;
    const root = { 敌人函数: {}, 暂停: false, gameworld: { target: { _x: left ? 150 : 250, Z轴坐标: 200, hp: 100 } } };
    const context = vm.createContext({ _parent: unit, _root: root, Math, random: () => 1 });
    vm.runInContext(productionFunctions, context);
    unit.状态改变 = root.敌人函数.状态改变;
    unit.动画完毕 = root.敌人函数.动画完毕;
    const trigger = vm.runInContext("(" + (legacy ? attack.replace(fixedEntry, legacyEntry) : attack) + ")", context);
    return { unit, root, trigger: () => trigger(100, 10, 50) };
}
let passed = 0;
function check(label, run) { run(); passed++; console.log("[PASS] " + label); }
check("legacy standing-entry control reproduces mismatch and repeated failed completion", () => {
    const f = fixture("空手站立", true); f.trigger();
    assert.equal(f.unit.状态, "空手站立");
    for (let i = 0; i < 3; i++) f.unit.动画完毕();
    assert.equal(f.unit.animation, "空手攻击"); assert.equal(f.unit.jumps.length, 1);
});
for (const state of ["空手站立", "空手行走", "空手跑"]) {
    for (const left of [false, true]) check("fixed admission and completion: " + state + (left ? " left" : " right"), () => {
        const f = fixture(state, false, left); f.trigger();
        assert.equal(f.unit.状态, "空手攻击"); assert.equal(f.unit.animation, "空手攻击");
        assert.equal(f.unit.direction, left ? "左" : "右");
        f.unit.动画完毕(); assert.equal(f.unit.状态, "空手站立"); assert.equal(f.unit.animation, "空手站立");
    });
}
check("completion does not depend on the departed target", () => {
    const f = fixture("空手站立"); f.trigger(); delete f.root.gameworld.target; f.unit.攻击目标 = "无";
    f.unit.动画完毕(); assert.equal(f.unit.animation, "空手站立");
});
check("standing can start a second distinct attack", () => {
    const f = fixture("空手站立");
    for (let i = 0; i < 2; i++) { f.trigger(); assert.equal(f.unit.状态, "空手攻击"); f.unit.动画完毕(); }
    assert.deepEqual(f.unit.jumps, ["空手攻击", "空手站立", "空手攻击", "空手站立"]);
});
check("public same-state guard remains effective", () => {
    const f = fixture("空手站立"); f.unit.状态改变("空手站立"); assert.equal(f.unit.jumps.length, 0);
});
check("legacy mismatch can recover after an external hit-state transition", () => {
    const f = fixture("空手站立", true); f.trigger(); f.unit.状态改变("被击"); f.unit.动画完毕();
    assert.equal(f.unit.animation, "空手站立");
});
check("lethal completion retains the production death-state decision", () => {
    const f = fixture("空手站立"); f.trigger(); f.unit.hp = 0; f.unit.动画完毕(); assert.equal(f.unit.animation, "血腥死");
});
console.log("Black dragon source/reference checks: " + passed + " passed; native AVM1 execution is separate.");
