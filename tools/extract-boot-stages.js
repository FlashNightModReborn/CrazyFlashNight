#!/usr/bin/env node
/*
 * extract-boot-stages.js — asLoader boot 时间轴 → 结构化阶段蓝图（asLoader 重构 P4 前置）
 *
 * BootSequencer(P4) 要把多帧异步 boot 内化成 onEnterFrame 状态机，前提是**精确**知道当前
 *   时间轴每个 playhead 步做什么、顺序、异步门控、跨 SWF 控制点。本工具从 asLoader.xml
 *   提取每帧脚本并分类，产出蓝图（BootSequencer 实现规格 + 轨道二 trace schema 的参照）。
 *
 * 分类（启发式，逐帧标注信号，人审为准）：
 *   sync-include   纯同步代码定义（仅 #include，无 stop/异步）
 *   async-await    this.stop() + 回调 .play()（硬门控，BootSequencer 需「状态不前进直到 done」）
 *   async-fire     发起异步 load 但不 stop（fire-and-continue）
 *   onEnterFrame   帧内挂 onEnterFrame 轮询（f4 握手）
 *   control-jump   gotoAndPlay/gotoAndStop（含跨 SWF 的 _root.gotoAndStop）
 *   self-unload    removeMovieClip 自卸载
 *   mixed/other    多信号或无明确信号
 *
 * 用法：node tools/extract-boot-stages.js [--json]
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");

function parseFramesWithLabels(xml) {
  // 收集 name/comment 标签：index -> labelName
  var labels = {};
  var lre = /<DOMFrame\b[^>]*\bindex="(\d+)"[^>]*\bname="([^"]*)"[^>]*labelType="(name|comment)"/g, lm;
  while ((lm = lre.exec(xml)) !== null) labels[parseInt(lm[1], 10)] = { name: lm[2].trim(), type: lm[3] };

  var re = /<DOMFrame\b[^>]*\bindex="(\d+)"[^>]*>([\s\S]*?)<\/DOMFrame>/g, m;
  var byIndex = {};
  while ((m = re.exec(xml)) !== null) {
    var idx = parseInt(m[1], 10);
    var cd = /<script>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*<\/script>/.exec(m[2]);
    if (!cd) continue;
    // 同一 index 可能多层都有脚本——合并（编译期同帧 DoAction 合并）
    (byIndex[idx] = byIndex[idx] || []).push(cd[1]);
  }
  return { labels: labels, byIndex: byIndex };
}

function classify(script) {
  // 必须先剥注释：f64 等帧的注释里出现 "this.removeMovieClip()" 等字样会污染信号检测
  var s = script.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  var sig = {
    includes: (s.match(/#include\s+"[^"]+"/g) || []).map(function (x) { return x.match(/"([^"]+)"/)[1]; }),
    thisStop: /\bthis\.stop\(\)/.test(s) || /(^|\n)\s*stop\(\)/.test(s),
    play: /\.(play)\(\)/.test(s) || /(^|[^.])\bplay\(\)/.test(s),
    onEnterFrame: /onEnterFrame\s*=/.test(s),
    gotoLocal: /(^|[^.])\bgotoAnd(Play|Stop)\s*\(/.test(s),
    gotoRoot: /_root\.gotoAnd(Play|Stop)\s*\(/.test(s),
    removeClip: /removeMovieClip\(\)/.test(s),
    loaderCb: /\.(load[A-Za-z]*|getInstance)\s*\(/.test(s),
    rootPlay: /_root\.play\(\)/.test(s),
    printLoad: /打印加载内容\s*\(/.test(s),
    asyncDataQuery: /DataQueryService|whenAvailable/.test(s)
  };
  var kind;
  if (sig.removeClip) kind = "self-unload";
  else if (sig.onEnterFrame) kind = "onEnterFrame";
  else if (sig.thisStop && sig.loaderCb) kind = "async-await";
  else if (sig.gotoLocal || sig.gotoRoot) kind = "control-jump";
  else if (sig.loaderCb && !sig.includes.length) kind = "async-fire";
  else if (sig.includes.length && !sig.thisStop) kind = "sync-include";
  else kind = "mixed/other";
  return { kind: kind, sig: sig };
}

function firstLine(s) {
  var t = s.replace(/\/\*[\s\S]*?\*\//g, "").split("\n").map(function (l) { return l.trim(); })
    .filter(function (l) { return l && !/^\/\//.test(l); });
  return t.length ? t[0].slice(0, 70) : "(空/注释帧)";
}

function main() {
  var asJson = process.argv.indexOf("--json") >= 0;
  var parsed = parseFramesWithLabels(fs.readFileSync(XML, "utf8"));
  var indices = Object.keys(parsed.byIndex).map(Number).sort(function (a, b) { return a - b; });

  var stages = indices.map(function (idx) {
    var scripts = parsed.byIndex[idx];
    var merged = scripts.join("\n/*--layer--*/\n");
    var c = classify(merged);
    var lab = parsed.labels[idx];
    return {
      frame: idx,
      label: lab ? lab.name : null,
      labelType: lab ? lab.type : null,
      kind: c.kind,
      layers: scripts.length,
      includeCount: c.sig.includes.length,
      includes: c.sig.includes,
      crossSwf: c.sig.gotoRoot || c.sig.rootPlay,
      signals: Object.keys(c.sig).filter(function (k) { return k !== "includes" && c.sig[k] === true; }),
      head: firstLine(merged)
    };
  });

  if (asJson) { process.stdout.write(JSON.stringify(stages, null, 1) + "\n"); return; }

  console.log("=== asLoader boot 阶段蓝图（" + stages.length + " 个含脚本帧）===");
  console.log("frame | kind          | inc | x-SWF | label / head");
  console.log("------+---------------+-----+-------+------------------------------------------");
  stages.forEach(function (st) {
    var pad = function (s, n) { s = String(s); return s + Array(Math.max(1, n - s.length + 1)).join(" "); };
    console.log(
      pad("f" + st.frame, 5) + " | " + pad(st.kind, 13) + " | " + pad(st.includeCount || "", 3) + " | " +
      pad(st.crossSwf ? "⚠ROOT" : "", 5) + " | " +
      (st.label ? "[" + st.label + "] " : "") + st.head
    );
  });
  var counts = {};
  stages.forEach(function (s) { counts[s.kind] = (counts[s.kind] || 0) + 1; });
  console.log("\n按类: " + Object.keys(counts).map(function (k) { return k + "=" + counts[k]; }).join("  "));
  var xs = stages.filter(function (s) { return s.crossSwf; }).map(function (s) { return "f" + s.frame; });
  console.log("跨 SWF 控制点(BootSequencer 须原样保留+真机验): " + (xs.join(", ") || "无"));
  var awaits = stages.filter(function (s) { return s.kind === "async-await"; }).map(function (s) { return "f" + s.frame; });
  console.log("硬门控 async-await 帧(状态机串行 await): " + (awaits.join(", ") || "无"));
}

main();
