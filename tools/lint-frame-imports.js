#!/usr/bin/env node
/*
 * lint-frame-imports.js — C3 帧脚本 import 治理 + 单帧联合头分析（asLoader 重构 P2）
 *
 * 背景：asLoader 每个时间轴帧的全部 #include 子文件在编译期拼接成**一个 DoAction 编译单元**，
 *   具体 import 的作用域=整个单元 → 跨 sibling 泄漏（污染）；故约定帧脚本只能用通配符 import
 *   （as2-anti-hallucination.md §1）。BootSequencer 单帧重构会把**所有**同步代码并入一个单元，
 *   届时需要一份「策划过的通配 import 联合头」，且跨包**叶名碰撞**处必须改 FQN。本工具产出该数据。
 *
 * 做三件事：
 *   1. 解析 asLoader.xml → 每个时间轴帧的编译单元（脚本 + 传递闭包 #include 文件）。
 *   2. C3 lint：列出帧脚本里的「具体 import」（非通配）——C3 转换目标；并按帧报告其通配 import 集。
 *   3. 单帧联合头分析：全局通配包并集 + 跨包叶名碰撞（同一简单类名存在于 ≥2 个并集包）。
 *      碰撞 = 单帧合并后会 ambiguous 的名字，必须 FQN 化。叠加「该叶名是否在帧脚本中被裸用」标注。
 *
 * 用法：
 *   node tools/lint-frame-imports.js            人读报告
 *   node tools/lint-frame-imports.js --json     结构化输出（供联合头生成器消费）
 *   node tools/lint-frame-imports.js --strict    有具体 import 或被裸用的碰撞 → exit 1
 *   node tools/lint-frame-imports.js --fold-specific
 *       把 47 个具体 import 的「包」并入通配并集后重算碰撞 —— 这是 P5 单帧折叠后的真实
 *       import 头（子文件剥掉自带具体 import，靠联合头解析）。报告折叠**新引入**的叶名碰撞
 *       （需在子文件改 FQN）。与 --strict 叠加时，新碰撞 → exit 1。Runbook P3 步骤 1 的门。
 *
 * 路径基准：#include = scripts/asLoader/（含嵌套）；类索引 = scripts/类定义/。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var INCLUDE_BASE = path.join(REPO, "scripts", "asLoader");
var XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");
var CLASSDIR = path.join(REPO, "scripts", "类定义");

function stripComments(t) {
  return t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}
function extractIncludes(text) {
  var re = /#include\s+"([^"]+)"/g, m, out = [];
  text = stripComments(text);
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}
// 返回 {wild:[pkg], spec:[{full,pkg,name}]}
function extractImports(text) {
  text = stripComments(text);
  // 行首锚定 + 分号可选：AS2 import 末尾分号非必需（实测 单位函数_*_模板迁移.as / LineSurface.as），
  // 旧 `\bimport ...;` 既漏无分号 import、又可能误命中字符串内 "import"。改 ^[ \t]*import…;? 更稳。
  // 标识符分段式（同 stage-wrap）：避免无分号通配 import 下贪婪点吞 .* 而漏掉尾 `*`。
  var re = /^[ \t]*import\s+([A-Za-z_][\w$]*(?:\.[\w$]+)*(?:\.\*)?)[ \t]*;?/gm, m;
  var wild = [], spec = [];
  while ((m = re.exec(text)) !== null) {
    var id = m[1];
    if (/\.\*$/.test(id)) wild.push(id.slice(0, -2));
    else {
      var dot = id.lastIndexOf(".");
      spec.push({ full: id, pkg: dot >= 0 ? id.slice(0, dot) : "", name: dot >= 0 ? id.slice(dot + 1) : id });
    }
  }
  return { wild: wild, spec: spec };
}

// 解析 asLoader.xml → [{index, script}]（取含 CDATA 脚本的 DOMFrame）
function parseFrames(xmlText) {
  var re = /<DOMFrame\b[^>]*\bindex="(\d+)"[^>]*>([\s\S]*?)<\/DOMFrame>/g, m;
  var frames = [];
  while ((m = re.exec(xmlText)) !== null) {
    var idx = parseInt(m[1], 10);
    var inner = m[2];
    var cd = /<script>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/.exec(inner);
    if (cd) frames.push({ index: idx, script: cd[1] });
  }
  return frames;
}

// 传递闭包收集一个帧编译单元的全部源文本（脚本 + 所有 #include 文件，基准恒为 INCLUDE_BASE）
function gatherUnit(script) {
  var files = [];
  var seen = {};
  var queue = extractIncludes(script).slice();
  while (queue.length) {
    var ref = queue.shift();
    var abs = path.resolve(INCLUDE_BASE, ref);
    if (seen[abs]) continue;
    seen[abs] = true;
    if (!fs.existsSync(abs)) { files.push({ abs: abs, rel: ref, missing: true, text: "" }); continue; }
    var text = fs.readFileSync(abs, "utf8");
    files.push({ abs: abs, rel: path.relative(REPO, abs).replace(/\\/g, "/"), text: text });
    extractIncludes(text).forEach(function (r) { queue.push(r); });
  }
  return files;
}

// 扫 类定义 → {pkgToNames:{pkg:Set}, nameToPkgs:{name:Set}}（排除 Test 文件以免噪声）
function buildClassIndex() {
  var pkgToNames = {}, nameToPkgs = {};
  (function walk(dir) {
    fs.readdirSync(dir, { withFileTypes: true }).forEach(function (e) {
      var p = path.join(dir, e.name);
      if (e.isDirectory()) return walk(p);
      if (!/\.as$/i.test(e.name)) return;
      var name = e.name.slice(0, -3);
      if (/Test$/.test(name) || /Test[A-Z0-9]/.test(name)) return;
      var relDir = path.relative(CLASSDIR, dir).replace(/[\\/]/g, ".");
      if (!relDir) return;
      (pkgToNames[relDir] = pkgToNames[relDir] || {})[name] = true;
      (nameToPkgs[name] = nameToPkgs[name] || {})[relDir] = true;
    });
  })(CLASSDIR);
  return { pkgToNames: pkgToNames, nameToPkgs: nameToPkgs };
}

function uniq(arr) { var s = {}; arr.forEach(function (x) { s[x] = true; }); return Object.keys(s).sort(); }

// 给定通配包并集 + 类索引 + 全单元文本，算跨包叶名碰撞。addedSet（可空）= 折叠新增的包，
// 用于标注哪些碰撞是折叠「新引入」的（去掉新增包后该名不再 ≥2 包共享）。
function computeCollisions(unionWild, idx, allUnitText, addedSet) {
  addedSet = addedSet || {};
  var nameInUnion = {};   // name -> [pkgs in union that contain it]
  unionWild.forEach(function (pkg) {
    var names = idx.pkgToNames[pkg];
    if (!names) return;
    Object.keys(names).forEach(function (n) {
      (nameInUnion[n] = nameInUnion[n] || []).push(pkg);
    });
  });
  var collisions = [];
  Object.keys(nameInUnion).forEach(function (n) {
    var pkgs = nameInUnion[n];
    if (pkgs.length < 2) return;
    var bareRe = new RegExp("(^|[^\\w.$])" + n + "\\b");
    var used = bareRe.test(allUnitText);
    // 折叠新引入：剔除新增包后剩余 < 2 个包 → 该碰撞由折叠产生
    var withoutAdded = pkgs.filter(function (p) { return !addedSet[p]; });
    collisions.push({ name: n, packages: pkgs.sort(), usedBare: used, introducedByFold: withoutAdded.length < 2 });
  });
  collisions.sort(function (a, b) { return (b.usedBare - a.usedBare) || (b.packages.length - a.packages.length) || a.name.localeCompare(b.name); });
  return collisions;
}

function main() {
  var argv = process.argv.slice(2);
  var asJson = argv.indexOf("--json") >= 0;
  var strict = argv.indexOf("--strict") >= 0;
  var foldSpecific = argv.indexOf("--fold-specific") >= 0;

  var frames = parseFrames(fs.readFileSync(XML, "utf8"));
  var idx = buildClassIndex();

  var perFrame = [];
  var specificFindings = [];   // {frame, file, full}
  var unionWildSet = {};
  var allUnitText = "";

  frames.forEach(function (fr) {
    var unit = gatherUnit(fr.script);
    var wild = {}, missing = [];
    // 帧 CDATA 本身的 import
    var inlineImp = extractImports(fr.script);
    inlineImp.wild.forEach(function (p) { wild[p] = true; });
    inlineImp.spec.forEach(function (s) { specificFindings.push({ frame: fr.index, file: "(asLoader.xml CDATA)", full: s.full }); });
    allUnitText += "\n" + stripComments(fr.script);
    unit.forEach(function (f) {
      if (f.missing) { missing.push(f.rel); return; }
      var imp = extractImports(f.text);
      imp.wild.forEach(function (p) { wild[p] = true; });
      imp.spec.forEach(function (s) { specificFindings.push({ frame: fr.index, file: f.rel, full: s.full }); });
      allUnitText += "\n" + stripComments(f.text);
    });
    Object.keys(wild).forEach(function (p) { unionWildSet[p] = true; });
    perFrame.push({ index: fr.index, fileCount: unit.length, wild: Object.keys(wild).sort(), missing: missing });
  });

  var unionWild = Object.keys(unionWildSet).sort();

  // 折叠模式：把具体 import 的「包」并入并集（= 单帧折叠后子文件剥具体 import 靠联合头解析）
  var addedSet = {};
  var effectiveUnion = unionWild;
  if (foldSpecific) {
    specificFindings.forEach(function (s) {
      var dot = s.full.lastIndexOf(".");
      var pkg = dot >= 0 ? s.full.slice(0, dot) : "";
      if (pkg && !unionWildSet[pkg]) addedSet[pkg] = true;
    });
    effectiveUnion = unionWild.concat(Object.keys(addedSet)).sort();
  }

  // 跨包叶名碰撞：某简单类名存在于 ≥2 个并集包
  var collisions = computeCollisions(effectiveUnion, idx, allUnitText, addedSet);
  var addedPkgs = Object.keys(addedSet).sort();
  var newCollisions = collisions.filter(function (c) { return c.introducedByFold; });

  if (asJson) {
    process.stdout.write(JSON.stringify({
      frameCount: frames.length, unionWild: unionWild,
      foldSpecific: foldSpecific, addedPackages: addedPkgs, effectiveUnion: foldSpecific ? effectiveUnion : undefined,
      specificImports: specificFindings, collisions: collisions, perFrame: perFrame
    }, null, 1) + "\n");
    return;
  }

  // 人读报告
  console.log("=== C3 帧 import 治理报告" + (foldSpecific ? "（--fold-specific：模拟单帧折叠联合头）" : "") + " ===");
  console.log("时间轴帧(含脚本): " + frames.length + "   通配包并集: " + unionWild.length +
    (foldSpecific ? " (+折叠 " + addedPkgs.length + " = " + effectiveUnion.length + ")" : "") +
    "   类索引(非Test): " + Object.keys(idx.nameToPkgs).length + " 简单名");
  if (foldSpecific) {
    console.log("");
    console.log("--- [0] 折叠新增包（具体 import 提升为通配，子文件需删掉对应具体 import）: " + addedPkgs.length + " ---");
    addedPkgs.forEach(function (p) { console.log("  + import " + p + ".*;"); });
    console.log("  折叠**新引入**碰撞（必须 FQN 化，否则单帧 ambiguous）: " + newCollisions.length);
    newCollisions.forEach(function (c) {
      console.log("  ⚠NEW " + c.name + (c.usedBare ? "（裸用!）" : "") + "  ∈ {" + c.packages.join(", ") + "}");
    });
    if (newCollisions.length === 0) console.log("  ✅ 折叠零新碰撞 → 联合头可安全合并，子文件仅需删具体 import");
  }
  console.log("");
  console.log("--- [1] 具体 import（C3 转换目标，应改通配头解析或 FQN）: " + specificFindings.length + " 处 ---");
  var byFile = {};
  specificFindings.forEach(function (s) { (byFile[s.file] = byFile[s.file] || []).push(s.full + " (f" + s.frame + ")"); });
  Object.keys(byFile).sort().forEach(function (f) {
    console.log("  " + f + "  [" + byFile[f].length + "]");
    byFile[f].slice(0, 12).forEach(function (x) { console.log("      " + x); });
  });
  console.log("");
  var bareCollisions = collisions.filter(function (c) { return c.usedBare; });
  console.log("--- [2] 跨包叶名碰撞（单帧联合头会 ambiguous）---");
  console.log("  并集内共享简单名: " + collisions.length + "；其中帧脚本裸用(必 FQN): " + bareCollisions.length);
  bareCollisions.slice(0, 40).forEach(function (c) {
    console.log("  ⚠ " + c.name + "  ∈ {" + c.packages.join(", ") + "}");
  });
  if (collisions.length - bareCollisions.length > 0)
    console.log("  (另 " + (collisions.length - bareCollisions.length) + " 个共享名当前未裸用，单帧合并前不致命，但属潜在面)");
  console.log("");
  console.log("--- [3] 通配包并集（单帧联合头候选，已去重排序）: " + unionWild.length + " 包 ---");
  unionWild.forEach(function (p) { console.log("  import " + p + ".*;"); });

  var missingAny = perFrame.some(function (f) { return f.missing.length; });
  if (missingAny) {
    console.log("\n--- ⚠ 未解析 #include ---");
    perFrame.forEach(function (f) { f.missing.forEach(function (r) { console.log("  f" + f.index + ": " + r); }); });
  }

  if (strict) {
    // 折叠模式下的 strict 门 = 折叠后新引入碰撞为 0（折叠是终态，具体 import 会被联合头吸收，故不计为失败）
    if (foldSpecific) {
      if (newCollisions.length > 0) {
        console.log("\n[strict+fold] 折叠引入 " + newCollisions.length + " 个新碰撞 → exit 1（须在子文件 FQN 化）");
        process.exit(1);
      }
    } else if (specificFindings.length > 0 || bareCollisions.length > 0) {
      console.log("\n[strict] 存在具体 import 或裸用碰撞 → exit 1");
      process.exit(1);
    }
  }
}

main();
