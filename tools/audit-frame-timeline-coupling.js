#!/usr/bin/env node
/*
 * audit-frame-timeline-coupling.js — stage-wrap 的「顶层时间轴耦合门」（P3 决定性安全判据）
 *
 * stage-wrap 把帧体搬进 `_root.__boot.fN = function(){...}`。决定性破坏判据 = 帧编译单元在
 * **顶层（brace 深度 0，非任何函数/方法体内）** 出现以下任一 → wrap 后 `this`/时间轴语义改变 → 必须改归
 * BootSequencer，不可 inline-wrap：
 *   (A) `this` 关键字：顶层 this = 时间轴 MovieClip（asLoader 实例）；wrap 后 this = _root.__boot →
 *       `this.stop()` / `this.onEnterFrame=` / `this._lockroot` 等全失效（f0、f26 即此类）。
 *   (B) 裸时间轴导航调用：stop()/play()/gotoAndStop()/gotoAndPlay()/nextFrame()/prevFrame()
 *       （前缀非 `.`，即非 `_root.gotoAndPlay` 这类显式对象调用——后者 wrap 后仍正确）。
 *   (C) 顶层时间轴事件处理器赋值：onEnterFrame= / onUnload= / onLoad=（裸或 this.，挂时间轴；
 *       `someParam.onEnterFrame=` 在函数体内 depth>0 不计）。
 *
 * **关键：只看 depth==0**。函数/方法体内（`_root.X=function(){...this.../...gotoAndPlay...}`）的同类用法
 * 在 wrap 后仍以正确 this/上下文延迟执行 → 安全，不计。本工具正是把对抗审计里「顶层 vs 函数体内」的
 * 混淆做成确定性判据。CJK 感知、剥字符串/注释、传递闭包。
 *
 * 用法：node tools/audit-frame-timeline-coupling.js [frames...]   不带参=全部有脚本帧
 *       --json / --strict（任一帧有顶层耦合 → exit 1）
 * 输出：每帧顶层耦合命中（含来源文件 + 行）。零命中 = inline-wrap 安全。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var INCLUDE_BASE = path.join(REPO, "scripts", "asLoader");
var XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");

function stripComments(t) { return t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, ""); }
function stripStrings(t) { return t.replace(/"(?:\\.|[^"\\])*"/g, '""').replace(/'(?:\\.|[^'\\])*'/g, "''"); }
function sanitize(t) { return stripStrings(stripComments(t)); }

function extractIncludes(text) {
  var re = /#include\s+"([^"]+)"/g, m, out = [];
  text = stripComments(text);
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}
function parseFrames(xmlText) {
  var re = /<DOMFrame\b[^>]*\bindex="(\d+)"[^>]*>([\s\S]*?)<\/DOMFrame>/g, m, frames = [];
  while ((m = re.exec(xmlText)) !== null) {
    var cd = /<script>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/.exec(m[2]);
    if (cd) frames.push({ index: parseInt(m[1], 10), script: cd[1] });
  }
  return frames;
}
// 收集帧单元的 (来源文件, 行文本) 列表，每行带其大括号深度（行首处的深度）。
function gatherUnitLines(script) {
  var seen = {}, queue = extractIncludes(script).slice();
  var sources = [{ file: "(CDATA)", text: sanitize(script) }];
  while (queue.length) {
    var ref = queue.shift();
    var abs = path.resolve(INCLUDE_BASE, ref);
    if (seen[abs]) continue;
    seen[abs] = true;
    if (!fs.existsSync(abs)) continue;
    var t = fs.readFileSync(abs, "utf8");
    sources.push({ file: ref, text: sanitize(t) });
    extractIncludes(t).forEach(function (r) { queue.push(r); });
  }
  return sources;
}

// depth-0 危险模式（前缀 [^...\.] 排除 `_root.gotoAndPlay`/`obj.onLoad` 这类显式对象调用）
var RE_THIS = /(^|[^A-Za-z0-9_$.一-鿿])this(?![A-Za-z0-9_$一-鿿])/;
var RE_NAV = /(^|[^A-Za-z0-9_$.一-鿿])(stop|play|gotoAndStop|gotoAndPlay|nextFrame|prevFrame)\s*\(/;
var RE_HANDLER2 = /(^|[^A-Za-z0-9_$.])(onEnterFrame|onUnload|onLoad)\s*=|this\.(onEnterFrame|onUnload|onLoad)\s*=/;

function scanFrame(sources) {
  var hits = []; // {kind, file, line, text}
  sources.forEach(function (src) {
    var depth = 0;
    src.text.split(/\r?\n/).forEach(function (line, i) {
      if (depth === 0) {
        var trimmed = line.replace(/^\s+/, "");
        if (RE_THIS.test(line)) hits.push({ kind: "this", file: src.file, line: i + 1, text: trimmed.slice(0, 80) });
        if (RE_NAV.test(line)) hits.push({ kind: "nav", file: src.file, line: i + 1, text: trimmed.slice(0, 80) });
        if (RE_HANDLER2.test(line)) hits.push({ kind: "handler", file: src.file, line: i + 1, text: trimmed.slice(0, 80) });
      }
      depth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
      if (depth < 0) depth = 0;
    });
  });
  return hits;
}

function main() {
  var argv = process.argv.slice(2);
  var asJson = argv.indexOf("--json") >= 0;
  var strict = argv.indexOf("--strict") >= 0;
  var want = argv.filter(function (a) { return /^\d+$/.test(a); }).map(Number);

  var frames = parseFrames(fs.readFileSync(XML, "utf8"));
  if (want.length) frames = frames.filter(function (f) { return want.indexOf(f.index) >= 0; });

  var report = frames.map(function (fr) {
    return { frame: fr.index, hits: scanFrame(gatherUnitLines(fr.script)) };
  });
  var coupled = report.filter(function (r) { return r.hits.length > 0; });
  var clean = report.filter(function (r) { return r.hits.length === 0; });

  if (asJson) {
    process.stdout.write(JSON.stringify({
      inlineWrapSafe: clean.map(function (r) { return r.frame; }),
      topLevelCoupled: coupled.map(function (r) { return { frame: r.frame, hits: r.hits }; }),
    }, null, 1) + "\n");
    return;
  }

  console.log("=== stage-wrap 顶层时间轴耦合门 ===");
  console.log("扫描帧: " + report.length + "   inline-wrap 安全(零顶层耦合): " + clean.length + "   有顶层耦合(须归 BootSequencer): " + coupled.length);
  console.log("");
  console.log("--- inline-wrap 安全帧 ---  f" + clean.map(function (r) { return r.frame; }).join(", f"));
  console.log("");
  console.log("--- 顶层时间轴耦合帧（不可 inline-wrap）---");
  coupled.forEach(function (r) {
    console.log("  f" + r.frame + "  (" + r.hits.length + " 命中):");
    r.hits.slice(0, 8).forEach(function (h) {
      console.log("      [" + h.kind + "] " + h.file + ":" + h.line + "  " + h.text);
    });
    if (r.hits.length > 8) console.log("      …另 " + (r.hits.length - 8));
  });

  if (strict && coupled.length > 0) { console.log("\n[strict] 存在顶层时间轴耦合帧 → exit 1"); process.exit(1); }
}
main();
