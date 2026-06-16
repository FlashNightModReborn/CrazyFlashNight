#!/usr/bin/env node
/*
 * stage-wrap-frame.js — asLoader 折叠 P3：把一个**同步帧**包成 staged 函数（中间态，多帧结构上可 boot 验证）
 *
 * 单帧折叠的核心变换：帧体 `#include` 列表从「时间轴顶层直接执行」搬进 `_root.__boot.fN=function(){...}`，
 * 由状态机/内联调用驱动。`import` 不能在函数体内 → 必须把被包含子文件的 import **剥掉**，提升为帧顶通配头
 * （联合头零碰撞已由 lint --fold-specific 证，子集亦零碰撞）。本工具机械完成该变换：
 *   1. 读 manifest frameN.as，收集其 #include 子文件（已验证：各子文件单帧独占，剥 import 不影响他帧）。
 *   2. 逐子文件 + manifest 本体剥 import（BOM 感知、注释行不误剥），记录被剥 import 的「包」。
 *   3. 重写 frameN.as = [帧顶通配头(本帧所需包)] + `_root.__boot.fN=function(){ <原帧体> }; _root.__boot.fN();`
 *      —— 内联调用保持多帧时序不变（仅作用域从时间轴变函数，可单帧 boot 验证）；P5 折叠时把内联调用
 *      改为 BootSequencer 驱动。
 *
 * ⚠ 仅用于**同步帧**（引擎/通信/系统/逻辑层）。异步帧（f4 握手 / f5,f6,f75 await / f62-74 fanout / f91 handoff）
 *   由 BootSequencer 状态机接管，不走本工具。
 * ⚠ 帧顶 `打印加载内容`/`onError` 是跨帧时间轴符号（audit-frame-scope-safety 结论），保持帧顶定义不动；
 *   本工具不碰 f0（其定义处）/f41（onError 定义处）的那两个定义，只把**调用**包进函数（靠闭包捕获时间轴 scope）。
 *
 * 用法：node tools/stage-wrap-frame.js <N> [--dry]
 *   --dry 仅打印计划（不写盘）。生成文件均保持/写入 UTF-8 BOM。
 * 回退：git（每帧一次提交边界）。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var INCLUDE_BASE = path.join(REPO, "scripts", "asLoader");
var MANIFEST_DIR = path.join(REPO, "scripts", "asLoaderManifest");
var BOM = Buffer.from([0xEF, 0xBB, 0xBF]);

function readBom(abs) {
  var raw = fs.readFileSync(abs);
  var hasBom = raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF;
  return { hasBom: hasBom, text: hasBom ? raw.slice(3).toString("utf8") : raw.toString("utf8") };
}
function writeBom(abs, text, hasBom) {
  var body = Buffer.from(text, "utf8");
  fs.writeFileSync(abs, hasBom ? Buffer.concat([BOM, body]) : body);
}

// 行首 import 语句（允许前导空白；注释行 // 或 * 开头不匹配）。返回 {text, pkgs:[wildcardPkg]}
var IMPORT_RE = /^[ \t]*import\s+([A-Za-z_][\w.$]*(?:\.\*)?)\s*;[ \t]*\r?\n?/gm;
function stripImports(text) {
  var pkgs = [], m;
  IMPORT_RE.lastIndex = 0;
  while ((m = IMPORT_RE.exec(text)) !== null) {
    var id = m[1];
    var pkg = /\.\*$/.test(id) ? id.slice(0, -2) : id.slice(0, id.lastIndexOf("."));
    if (pkg) pkgs.push(pkg);
  }
  var out = text.replace(IMPORT_RE, "");
  return { text: out, pkgs: pkgs };
}

function stripComments(t) {
  return t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
}
// 注释感知：忽略 //#include 这类被注释掉的包含（如 frame10 的 兼容.as 已禁用项）。
function extractIncludes(text) {
  var re = /#include\s+"([^"]+)"/g, m, out = [];
  text = stripComments(text);
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}

// 顶层(brace 深度 0)时间轴耦合自卫门：帧体/子文件顶层若用 this / 裸 stop|play|gotoAndStop|gotoAndPlay|
// nextFrame|prevFrame / onEnterFrame=|onUnload= → wrap 后 this 变 _root.__boot、时间轴失控 → 必须拒绝
// （如 f26 最终化2 的 loader 循环）。镜像 tools/audit-frame-timeline-coupling.js 的判据。
function stripStrings(t) { return t.replace(/"(?:\\.|[^"\\])*"/g, '""').replace(/'(?:\\.|[^'\\])*'/g, "''"); }
var RE_THIS = /(^|[^A-Za-z0-9_$.一-鿿])this(?![A-Za-z0-9_$一-鿿])/;
var RE_NAV = /(^|[^A-Za-z0-9_$.一-鿿])(stop|play|gotoAndStop|gotoAndPlay|nextFrame|prevFrame)\s*\(/;
var RE_HANDLER = /(^|[^A-Za-z0-9_$.])(onEnterFrame|onUnload|onLoad)\s*=|this\.(onEnterFrame|onUnload|onLoad)\s*=/;
function scanTopLevelCoupling(file, text) {
  var hits = [], depth = 0;
  stripStrings(stripComments(text)).split(/\r?\n/).forEach(function (line, i) {
    if (depth === 0) {
      if (RE_THIS.test(line)) hits.push(file + ":" + (i + 1) + " [this] " + line.trim().slice(0, 70));
      else if (RE_NAV.test(line)) hits.push(file + ":" + (i + 1) + " [nav] " + line.trim().slice(0, 70));
      else if (RE_HANDLER.test(line)) hits.push(file + ":" + (i + 1) + " [handler] " + line.trim().slice(0, 70));
    }
    depth += (line.match(/\{/g) || []).length - (line.match(/\}/g) || []).length;
    if (depth < 0) depth = 0;
  });
  return hits;
}

// 某 #include ref 的传递闭包源字节数（含其递归 #include）—— chunk 预算用源码大小近似字节码（保守）。
function closureBytes(ref) {
  var seen = {}, q = [ref], total = 0;
  while (q.length) {
    var r = q.shift(); var abs = path.resolve(INCLUDE_BASE, r);
    if (seen[abs]) continue; seen[abs] = true;
    if (!fs.existsSync(abs)) continue;
    var t = fs.readFileSync(abs, "utf8");
    total += Buffer.byteLength(t, "utf8");
    extractIncludes(t).forEach(function (x) { q.push(x); });
  }
  return total;
}
// 展平：递归把「闭包 > budget 且自身含 #include」的聚合型 include（如 装备函数列表.as = imports+62 武器 #include）
// 替换为其内容（剥 import），使其子 include 被拉到帧级可被 chunk 分配。叶子 include 原样保留。
function flattenBody(text, budget) {
  return text.split(/\r?\n/).map(function (line) {
    var m = /#include\s+"([^"]+)"/.exec(stripComments(line));
    if (!m) return line;
    var abs = path.resolve(INCLUDE_BASE, m[1]);
    if (!fs.existsSync(abs)) return line;
    var content = fs.readFileSync(abs, "utf8");
    if (extractIncludes(content).length > 0 && closureBytes(m[1]) > budget) {
      return flattenBody(stripImports(content).text.replace(/^\s+|\s+$/g, ""), budget);  // 展开聚合 include，递归
    }
    return line;   // 叶子或小文件原样
  }).join("\n");
}
// 把帧体按源字节预算切成 consecutive chunk（保序，按整文件不拆单文件）。返回 [chunkText...]。
function buildChunks(body, budget) {
  var lines = body.split(/\r?\n/);
  var chunks = [], cur = [], curSize = 0, curHasInc = false;
  lines.forEach(function (line) {
    var m = /#include\s+"([^"]+)"/.exec(stripComments(line));
    var sz = m ? closureBytes(m[1]) : 0;
    if (m && curHasInc && curSize + sz > budget) { chunks.push(cur.join("\n")); cur = []; curSize = 0; curHasInc = false; }
    cur.push(line); curSize += sz; if (m) curHasInc = true;
  });
  if (cur.length) chunks.push(cur.join("\n"));
  return chunks;
}

function main() {
  var args = process.argv.slice(2);
  var dry = args.indexOf("--dry") >= 0;
  var cbIdx = args.indexOf("--chunk-bytes");
  var CHUNK = cbIdx >= 0 ? parseInt(args[cbIdx + 1], 10) : 0;   // 0 = 单函数（旧行为）；>0 = 切 <budget 源字节的多 chunk
  var FLATTEN = args.indexOf("--flatten") >= 0;                  // 展平聚合型大 include（如 f37 装备函数列表→62 武器）
  var N = parseInt(args.filter(function (a, i) { return /^\d+$/.test(a) && args[i - 1] !== "--chunk-bytes"; })[0], 10);
  if (isNaN(N)) { console.error("用法: stage-wrap-frame.js <N> [--dry] [--chunk-bytes <源字节预算,如 90000>]"); process.exit(2); }

  var manifestPath = path.join(MANIFEST_DIR, "frame" + N + ".as");
  if (!fs.existsSync(manifestPath)) { console.error("找不到 manifest: frame" + N + ".as（该帧未外置，或非外置帧）"); process.exit(2); }

  var mani = readBom(manifestPath);
  if (/__boot\.f\d+\s*=/.test(mani.text)) { console.error("frame" + N + " 已 stage-wrap，跳过"); process.exit(0); }

  var allPkgs = {};   // wildcardPkg -> true
  var stripPlan = []; // {file, pkgs, removed}
  var coupling = scanTopLevelCoupling("(manifest frame" + N + ".as)", mani.text);  // 自卫门累积

  // 1) manifest 本体的 import（同步帧通常无；async 帧 CDATA 有，本工具不处理 async 帧故一般为空）
  var maniStripped = stripImports(mani.text);
  maniStripped.pkgs.forEach(function (p) { allPkgs[p] = true; });
  if (maniStripped.pkgs.length) stripPlan.push({ file: "(manifest frame" + N + ".as)", pkgs: maniStripped.pkgs.slice() });

  // 2) 剥 import：**传递闭包**（帧体直接 #include + 其递归 #include，如 装备函数列表.as → 60+ 武器文件，
  //    其中 红外夜视仪/剑圣头部装甲 自带 import org.flashNight.arki.weather.* → 不剥则 import 落进函数体编译错）。
  var subEdits = []; // {abs, hasBom, newText, file}
  var seen = {};
  var queue = extractIncludes(mani.text).map(function (r) { return { ref: r, abs: path.resolve(INCLUDE_BASE, r) }; });
  while (queue.length) {
    var item = queue.shift();
    if (seen[item.abs]) continue;
    seen[item.abs] = true;
    if (!fs.existsSync(item.abs)) { console.error("⚠ 缺失子文件(跳过): " + item.ref); continue; }
    var f = readBom(item.abs);
    coupling = coupling.concat(scanTopLevelCoupling(item.ref, f.text));
    var s = stripImports(f.text);
    s.pkgs.forEach(function (p) { allPkgs[p] = true; });
    if (s.pkgs.length) {
      stripPlan.push({ file: item.ref, pkgs: s.pkgs });
      subEdits.push({ abs: item.abs, hasBom: f.hasBom, newText: s.text, file: item.ref });
    }
    // 递归该文件的 #include（注释感知；基准恒为 INCLUDE_BASE）
    extractIncludes(f.text).forEach(function (r) { queue.push({ ref: r, abs: path.resolve(INCLUDE_BASE, r) }); });
  }

  // 自卫门：顶层时间轴耦合 → 拒绝 wrap（该帧应归 BootSequencer 状态机，而非 inline-wrap）。
  if (coupling.length) {
    console.error("✗ frame" + N + " 含**顶层**时间轴耦合，拒绝 stage-wrap（应归 BootSequencer）：");
    coupling.slice(0, 10).forEach(function (h) { console.error("    " + h); });
    process.exit(3);
  }

  var header = Object.keys(allPkgs).sort().map(function (p) { return "import " + p + ".*;"; });

  // 3) 组装新 manifest：帧顶通配头 + staged 函数(可分 chunk 绕 64KB) + 内联调用
  var body = maniStripped.text.replace(/^\s+|\s+$/g, "");  // 去首尾空白，保留中间
  if (FLATTEN && CHUNK > 0) body = flattenBody(body, CHUNK);   // 展平聚合 include 后再 chunk
  var chunks = CHUNK > 0 ? buildChunks(body, CHUNK) : [body];
  var single = chunks.length === 1;
  var fnDefs = [], fnCalls = [];
  chunks.forEach(function (chunkText, i) {
    var name = "f" + N + (single ? "" : "_" + (i + 1));
    fnDefs.push("_root.__boot." + name + " = function() {\n" + chunkText.replace(/^/gm, "    ") + "\n};");
    fnCalls.push("_root.__boot." + name + "();");
  });
  var newMani =
    "// [stage-wrap" + (CHUNK > 0 ? " chunked<" + CHUNK + "B" : "") + "] frame" + N + " 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)\n" +
    "//   + staged 函数" + (single ? "" : "(" + chunks.length + " chunk 绕 AVM1 64KB 函数体上限,见 swf-function-sizes 门)") + " + 内联调用。\n" +
    header.join("\n") + "\n\n" +
    "if (_root.__boot == undefined) _root.__boot = {};\n" +
    fnDefs.join("\n") + "\n" +
    fnCalls.join("\n") + "\n";

  if (dry) {
    console.log("[DRY] frame" + N + " stage-wrap 计划" + (CHUNK > 0 ? "（chunk<" + CHUNK + "B）" : "") + ":");
    console.log("  帧顶通配头(" + header.length + " 包)");
    console.log("  剥 import 的文件(" + stripPlan.length + ")");
    console.log("  chunk 数: " + chunks.length + "  →  " + chunks.map(function (c, i) {
      var incs = (stripComments(c).match(/#include/g) || []).length;
      return "f" + N + "_" + (i + 1) + "(" + incs + " inc," + Math.round(c.length / 1024) + "KB src)";
    }).join(" + "));
    return;
  }

  subEdits.forEach(function (e) { writeBom(e.abs, e.newText, e.hasBom); });
  writeBom(manifestPath, newMani, mani.hasBom);
  console.log("[DONE] frame" + N + " stage-wrap 完成：帧顶 " + header.length + " 包；剥 import " + subEdits.length +
    " 文件；" + chunks.length + " chunk（" + fnCalls.map(function (c) { return c.match(/\.(\w+)\(/)[1]; }).join(",") + "）内联。");
}
main();
