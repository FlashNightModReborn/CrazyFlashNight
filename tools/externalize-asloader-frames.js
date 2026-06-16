#!/usr/bin/env node
/*
 * externalize-asloader-frames.js — C2 同步帧 CDATA 外置（asLoader 重构 P3 第一步）
 *
 * 把指定同步代码定义帧的 symbol CDATA 逐字节搬进 scripts/asLoaderManifest/frameNN.as，
 * CDATA 改为单行 `#include "../asLoaderManifest/frameNN.as"`。源码级内联 → 字节等价
 * （由 tools/swf-tag-diff 编译后核验）。从此模块增删只改外置 .as，不碰 symbol XML。
 *
 * 用法：node tools/externalize-asloader-frames.js <idx,idx,...>   实际执行（写盘）
 *       node tools/externalize-asloader-frames.js <...> --dry     仅打印计划
 * 生成的 .as 带 UTF-8 BOM；asLoader.xml 保留原 BOM。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");
var MANIFEST_DIR = path.join(REPO, "scripts", "asLoaderManifest");
var BOM = Buffer.from([0xEF, 0xBB, 0xBF]);

function readXml() {
  var raw = fs.readFileSync(XML);
  var hasBom = raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF;
  var text = hasBom ? raw.slice(3).toString("utf8") : raw.toString("utf8");
  return { text: text, hasBom: hasBom };
}
function writeXml(text, hasBom) {
  var body = Buffer.from(text, "utf8");
  fs.writeFileSync(XML, hasBom ? Buffer.concat([BOM, body]) : body);
}
function writeManifest(name, content) {
  var p = path.join(MANIFEST_DIR, name);
  fs.writeFileSync(p, Buffer.concat([BOM, Buffer.from(content, "utf8")]));
  return p;
}

function main() {
  var args = process.argv.slice(2);
  var dry = args.indexOf("--dry") >= 0;
  var idxArg = args.filter(function (a) { return a !== "--dry"; })[0];
  if (!idxArg) { console.error("用法: externalize-asloader-frames.js <idx,idx,...> [--dry]"); process.exit(2); }
  var targets = idxArg.split(",").map(function (s) { return parseInt(s.trim(), 10); });

  if (!fs.existsSync(MANIFEST_DIR)) fs.mkdirSync(MANIFEST_DIR, { recursive: true });
  var x = readXml();
  var text = x.text;
  var done = [], skipped = [];

  targets.forEach(function (idx) {
    // 匹配该 index 的「带脚本」DOMFrame：index 后紧跟 <Actionscript><script><![CDATA[...]]>
    var re = new RegExp(
      '(<DOMFrame\\b[^>]*\\bindex="' + idx + '"[^>]*>\\s*<Actionscript>\\s*<script><!\\[CDATA\\[)([\\s\\S]*?)(\\]\\]></script>)');
    var m = re.exec(text);
    if (!m) { skipped.push(idx + "(无脚本帧)"); return; }
    var content = m[2];
    if (/asLoaderManifest\/frame/.test(content)) { skipped.push(idx + "(已外置)"); return; }
    var fname = "frame" + idx + ".as";
    var include = '#include "../asLoaderManifest/' + fname + '"';
    if (dry) {
      console.log("f" + idx + " → " + fname + "  (" + (content.match(/#include/g) || []).length + " 个 #include, " + content.length + " 字符)");
      done.push(idx); return;
    }
    writeManifest(fname, content);
    text = text.slice(0, m.index) + m[1] + include + m[3] + text.slice(m.index + m[0].length);
    done.push(idx);
  });

  if (!dry) writeXml(text, x.hasBom);
  console.log((dry ? "[DRY] " : "[DONE] ") + "外置 " + done.length + " 帧: " + done.map(function (i) { return "f" + i; }).join(",") +
    (skipped.length ? "  跳过: " + skipped.join(",") : ""));
}
main();
