#!/usr/bin/env node
/*
 * audit-frame-scope-safety.js — asLoader 单帧折叠的「作用域安全门」（P3/P4 viability gate）
 *
 * 背景：BootSequencer 折叠把每个时间轴帧的 #include 列表包成 `_root.__boot.sN = function(){...}`，
 *   由状态机按序调用。此举把帧体从**时间轴作用域**搬进**函数作用域**：
 *     - `_root.X=` / `_global.X=` 赋值：目标显式，包进函数后行为不变 → 安全。
 *     - 顶层 `var NAME` / `function NAME(){}` / 裸 `NAME=`：原是**时间轴变量**，跨帧可经裸名/this 访问；
 *       包进函数后变成**函数局部**。
 *         · 若该名只在**本帧**（同一 staged 函数体，或其中定义的 _root.* 闭包）被读 → 安全（闭包/同体捕获）。
 *         · 若被**其它帧**裸读 → 折叠后断链（函数局部不跨帧）→ **必须 hoist 到 _root./ _root.__boot.**。
 *
 * 本工具：枚举每帧编译单元的顶层时间轴声明，扫全部帧的裸引用，报告**跨帧**依赖（= 折叠前必须 hoist 的清单）。
 *   零跨帧依赖 = staged 函数设计对该名安全。CJK 标识符感知。
 *
 * 用法：
 *   node tools/audit-frame-scope-safety.js           人读报告
 *   node tools/audit-frame-scope-safety.js --json     结构化
 *   node tools/audit-frame-scope-safety.js --strict   有跨帧时间轴依赖 → exit 1
 *
 * 路径基准：#include = scripts/asLoader/（同 lint-frame-imports）。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var INCLUDE_BASE = path.join(REPO, "scripts", "asLoader");
var XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");

// AS2 标识符（含 CJK），用于 var/function 名 + 裸引用边界
var ID = "[A-Za-z_$\\u4e00-\\u9fff][A-Za-z0-9_$\\u4e00-\\u9fff]*";
// 引用边界：前后均非「标识符字符或点」，避免匹配 obj.NAME / NAMEsuffix
var BEFORE = "(?:^|[^A-Za-z0-9_$.\\u4e00-\\u9fff])";
var AFTER = "(?![A-Za-z0-9_$\\u4e00-\\u9fff])";

function stripComments(t) {
  return t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}
// 抹掉字符串字面量内容（保留引号占位），避免路径/文案里的子串（如 "data/config/…"）被误判为裸引用，
// 同时避免字符串内不配对的 { } 干扰大括号深度计数。注释先于字符串剥离。
function stripStrings(t) {
  return t.replace(/"(?:\\.|[^"\\])*"/g, '""').replace(/'(?:\\.|[^'\\])*'/g, "''");
}
function sanitize(t) { return stripStrings(stripComments(t)); }
function extractIncludes(text) {
  var re = /#include\s+"([^"]+)"/g, m, out = [];
  text = stripComments(text);
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}
function parseFrames(xmlText) {
  var re = /<DOMFrame\b[^>]*\bindex="(\d+)"[^>]*>([\s\S]*?)<\/DOMFrame>/g, m;
  var frames = [];
  while ((m = re.exec(xmlText)) !== null) {
    var inner = m[2];
    var cd = /<script>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/.exec(inner);
    if (cd) frames.push({ index: parseInt(m[1], 10), script: cd[1] });
  }
  return frames;
}
function gatherUnitText(script) {
  var seen = {}, queue = extractIncludes(script).slice(), text = sanitize(script);
  while (queue.length) {
    var ref = queue.shift();
    var abs = path.resolve(INCLUDE_BASE, ref);
    if (seen[abs]) continue;
    seen[abs] = true;
    if (!fs.existsSync(abs)) continue;
    var t = fs.readFileSync(abs, "utf8");
    text += "\n" + sanitize(t);
    extractIncludes(t).forEach(function (r) { queue.push(r); });
  }
  return text;
}

// 顶层时间轴声明：行首（允许前导空白后即声明，但要求该声明不在 { 块内——近似用「行首/前导空白」）。
// AS2 帧脚本惯例：顶层声明在列 0；函数体内有缩进。我们取「该行 trim 后以 var/function 开头，且其所在
// 行的缩进 ≤ 1 个制表符/空格组」作为顶层近似；再要求大括号深度==0（精确）。
function findTopLevelDecls(unitText) {
  // 计算每个字符的大括号深度（跳过字符串/正则的简单近似：仅排除明显字符串）
  var decls = {}; // name -> {kind}
  var depth = 0;
  var lines = unitText.split(/\r?\n/);
  // 逐行维护 brace 深度（行尾结算）；顶层时间轴声明须 ① brace 深度==0 ② **列 0**（无前导空白）——
  // 本仓帧脚本惯例：时间轴层声明顶格，函数体内缩进。列 0 约束剔除缩进的对象字面量/函数内赋值误报。
  var reVar = new RegExp("^var\\s+(" + ID + ")");
  var reFunc = new RegExp("^function\\s+(" + ID + ")\\s*\\(");
  var reBareAssign = new RegExp("^(" + ID + ")\\s*=(?!=)");
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    if (depth === 0) {
      var m;
      if ((m = reVar.exec(line))) decls[m[1]] = decls[m[1]] || { name: m[1], kind: "var" };
      else if ((m = reFunc.exec(line))) decls[m[1]] = decls[m[1]] || { name: m[1], kind: "function" };
      else if ((m = reBareAssign.exec(line))) {
        var nm = m[1];
        // 排除关键字/明显非声明
        if (!/^(if|for|while|switch|return|else|var|function|new|delete|with|do|case|default|break|continue|this|super)$/.test(nm))
          decls[nm] = decls[nm] || { name: nm, kind: "bareAssign" };
      }
    }
    // 行尾结算 brace 深度（粗略：计 { } 净增；忽略字符串内花括号——帧脚本中极少见）
    var opens = (line.match(/\{/g) || []).length;
    var closes = (line.match(/\}/g) || []).length;
    depth += opens - closes;
    if (depth < 0) depth = 0;
  }
  return decls; // map name->{name,kind}
}

function main() {
  var argv = process.argv.slice(2);
  var asJson = argv.indexOf("--json") >= 0;
  var strict = argv.indexOf("--strict") >= 0;

  // 收集某单元文本里**任意深度**的 var/function 声明名（用于裸引用的 shadowing 抑制：
  // 若使用帧自己有同名 local var/function，则其裸引用是 local 而非跨帧时间轴依赖）。
  var reAnyVar = new RegExp("\\bvar\\s+(" + ID + ")", "g");
  var reAnyFunc = new RegExp("\\bfunction\\s+(" + ID + ")\\s*\\(", "g");
  function findAllLocalNames(text) {
    var set = {}, m;
    reAnyVar.lastIndex = 0; while ((m = reAnyVar.exec(text)) !== null) set[m[1]] = true;
    reAnyFunc.lastIndex = 0; while ((m = reAnyFunc.exec(text)) !== null) set[m[1]] = true;
    return set;
  }

  var frames = parseFrames(fs.readFileSync(XML, "utf8"));
  // 每帧：单元文本 + 顶层声明 + 任意深度 local 名集
  var frameData = frames.map(function (fr) {
    var text = gatherUnitText(fr.script);
    return { index: fr.index, text: text, decls: findTopLevelDecls(text), locals: findAllLocalNames(text) };
  });

  // 全局声明表：name -> [declaring frame indices]
  var declOwners = {}; // name -> {kind, frames:Set}
  frameData.forEach(function (fd) {
    Object.keys(fd.decls).forEach(function (n) {
      var d = declOwners[n] = declOwners[n] || { name: n, kind: fd.decls[n].kind, frames: {} };
      d.frames[fd.index] = true;
    });
  });

  // 对每个声明名，扫所有帧的裸引用 → 记录使用帧
  var crossFrame = []; // {name, kind, declFrames, useFrames, usedOutside:[frames]}
  var multiDecl = [];
  Object.keys(declOwners).forEach(function (n) {
    var owner = declOwners[n];
    var declFrames = Object.keys(owner.frames).map(Number).sort(function (a, b) { return a - b; });
    if (declFrames.length > 1) multiDecl.push({ name: n, kind: owner.kind, frames: declFrames });
    var useRe = new RegExp(BEFORE + n.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + AFTER);
    var declSet = {}; declFrames.forEach(function (f) { declSet[f] = true; });
    var usedOutside = [];
    frameData.forEach(function (fd) {
      if (declSet[fd.index]) return;        // 声明帧本身不算外部使用
      if (fd.locals[n]) return;             // shadowing：使用帧有同名 local → 裸引用是 local，非跨帧依赖
      if (useRe.test(fd.text)) usedOutside.push(fd.index);
    });
    if (usedOutside.length > 0) crossFrame.push({ name: n, kind: owner.kind, declFrames: declFrames, usedOutside: usedOutside });
  });

  crossFrame.sort(function (a, b) { return b.usedOutside.length - a.usedOutside.length || a.name.localeCompare(b.name); });

  var totalDecls = Object.keys(declOwners).length;

  if (asJson) {
    process.stdout.write(JSON.stringify({
      frameCount: frames.length, topLevelDeclCount: totalDecls,
      crossFrameDeps: crossFrame, redeclaredAcrossFrames: multiDecl
    }, null, 1) + "\n");
    return;
  }

  console.log("=== asLoader 单帧折叠作用域安全门 ===");
  console.log("时间轴帧: " + frames.length + "   顶层时间轴声明(去重): " + totalDecls);
  console.log("");
  console.log("--- 跨帧时间轴依赖（折叠为 per-frame staged 函数后会断链，必须 hoist 到 _root.）: " + crossFrame.length + " ---");
  if (crossFrame.length === 0) {
    console.log("  ✅ 零跨帧依赖 → 所有顶层声明仅在本帧（经同体/闭包捕获）被读，staged 函数设计安全。");
  } else {
    crossFrame.slice(0, 60).forEach(function (c) {
      console.log("  ⚠ " + c.name + " [" + c.kind + "]  声明@f" + c.declFrames.join(",f") + "  被读@f" + c.usedOutside.join(",f"));
    });
    if (crossFrame.length > 60) console.log("  …另 " + (crossFrame.length - 60) + " 个");
  }
  console.log("");
  console.log("--- 跨帧重复声明（信息性，折叠后同名合并需确认意图）: " + multiDecl.length + " ---");
  multiDecl.slice(0, 20).forEach(function (c) { console.log("  · " + c.name + " [" + c.kind + "] @f" + c.frames.join(",f")); });

  if (strict && crossFrame.length > 0) {
    console.log("\n[strict] 存在跨帧时间轴依赖 → exit 1（折叠前须 hoist）");
    process.exit(1);
  }
}

main();
