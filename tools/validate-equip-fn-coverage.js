#!/usr/bin/env node
// tools/validate-equip-fn-coverage.js
// 装备函数三方一致性巡检：scripts/逻辑/装备函数/*.as  ≡  frame37.as 的 #include  ≡  装备函数 README 索引。
//
// 背景（为什么要这道门）：asLoader 2026-06 塌缩成单帧后，装备函数真正的编译清单是
//   scripts/asLoaderManifest/frame37.as（f37_1..f37_8 chunk，由 stage-wrap --flatten 展平而来），
//   而旧的 装备函数列表.as 已退役、不在编译链里。开发者「加了 .as 却忘接 frame37」会
//   静默不生效（无编译错、无运行报错）——本门把这个失败模式从「上线后排查数小时」前移到
//   「改完即 exit 1」。同时锁住 README 索引与目录同步，使 README 不退化成会过期的二手清单。
//
// 用法：node tools/validate-equip-fn-coverage.js   （exit 0 = 一致；exit 1 = 有缺口并打印明细）
// 已接入 tools/validate-doc-governance.js（其末尾 spawn 本脚本）。

var fs = require("fs");
var path = require("path");

var ROOT = path.resolve(__dirname, "..");
var DIR_REL = "scripts/逻辑/装备函数";
var FRAME37_REL = "scripts/asLoaderManifest/frame37.as";
var README_REL = DIR_REL + "/README.md";

// 故意不编译进 boot 的 .as（WIP / 已禁用 / 纯文档）在此显式登记，避免误报。
// 留空即「目录里每个 .as 都必须接进 frame37 且被 README 索引」。
var EXCLUDE = {};

function abs(rel) { return path.join(ROOT, rel); }
function read(rel) { return fs.readFileSync(abs(rel), "utf8"); }

var errors = [];

// 1) 目录下所有 .as（扁平目录）
var dirSet = {};
var names = fs.readdirSync(abs(DIR_REL));
for (var i = 0; i < names.length; i++) {
    var n = names[i];
    if (!/\.as$/.test(n)) continue;
    if (EXCLUDE[n]) continue;
    dirSet[n] = true;
}

// 2) frame37.as 里 #include 的装备函数 basename（精确提取，无子串歧义）
var frameSet = {};
var f37 = read(FRAME37_REL);
var reInc = /#include\s+"\.\.\/逻辑\/装备函数\/([^"]+\.as)"/g;
var m;
while ((m = reInc.exec(f37)) !== null) {
    if (EXCLUDE[m[1]]) continue;
    frameSet[m[1]] = true;
}

// 3) README 索引文本（按精确文件名子串命中；.as 结尾锚定，G11.as 不会误中 G111.as）
var readmeText = "";
if (fs.existsSync(abs(README_REL))) {
    readmeText = read(README_REL);
} else {
    errors.push("缺少装备函数 README：" + README_REL);
}

// 三方对账
var name;
for (name in dirSet) {
    if (!frameSet[name]) errors.push("[未接线] " + name + " 在目录但不在 " + FRAME37_REL + " 的 #include（改完会静默不生效）");
    if (readmeText.indexOf(name) < 0) errors.push("[未索引] " + name + " 在目录但 README 未收录：" + README_REL);
}
for (name in frameSet) {
    if (!dirSet[name]) errors.push("[悬空接线] " + FRAME37_REL + " #include 了 " + name + " 但目录无此文件");
}

var dirCount = 0; for (name in dirSet) dirCount++;
var frameCount = 0; for (name in frameSet) frameCount++;

if (errors.length) {
    console.error("[equip-fn-coverage] failed（目录 " + dirCount + " · frame37 " + frameCount + "）");
    for (var e = 0; e < errors.length; e++) console.error(" - " + errors[e]);
    process.exit(1);
}

console.log("[equip-fn-coverage] ok（目录 " + dirCount + " 个 .as ≡ frame37 #include ≡ README 索引）");
