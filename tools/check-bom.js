#!/usr/bin/env node
/*
 * check-bom.js — UTF-8 BOM 门（asLoader 重构 P0）
 *
 * 背景：被 FLA 帧脚本 #include 的 .as 丢 BOM 时，CS6 编译器**静默跳过**其内容，
 *   生成 SWF 对应 DoAction 为 0 字节，但 compiler_errors 仍报「0 个错误」，
 *   现有 compile_test 冒烟链抓不到（见 as2-anti-hallucination.md §0）。本方案
 *   大量外置/生成 .as 会放大此坑，故 P0 先建此门。
 *
 * 约束：#include 路径基准 = FLA 文件夹（scripts/asLoader/），**任意嵌套深度都用此基准**
 *   （非当前文件路径）。故 ../引擎/X.as、嵌套 manifest 里的 ../逻辑/装备函数/Y.as
 *   全部从 scripts/asLoader/ 解析。
 *
 * 用法：
 *   check-bom            从 asLoader.xml 起，沿 #include 图遍历全部 .as 验 BOM
 *   check-bom --dir <d>  额外扫描目录 d 下所有 .as
 *   check-bom --file <f> 额外扫描单个 .as
 *   check-bom --xml <f>  指定起点 symbol xml（默认 scripts/asLoader/LIBRARY/asLoader.xml）
 * 任一 .as 缺 BOM → 列出并 exit 1。
 */

var fs = require("fs");
var path = require("path");

var REPO = path.resolve(__dirname, "..");
var INCLUDE_BASE = path.join(REPO, "scripts", "asLoader");   // #include 解析基准
var DEFAULT_XML = path.join(REPO, "scripts", "asLoader", "LIBRARY", "asLoader.xml");

function hasBom(file) {
  var fd = fs.openSync(file, "r");
  var buf = Buffer.alloc(3);
  var n = fs.readSync(fd, buf, 0, 3, 0);
  fs.closeSync(fd);
  return n === 3 && buf[0] === 0xEF && buf[1] === 0xBB && buf[2] === 0xBF;
}

function extractIncludes(text) {
  // 先剥注释，避免把 //#include 或 /* #include */ 当成活引用
  text = text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "");
  var re = /#include\s+"([^"]+)"/g, m, out = [];
  while ((m = re.exec(text)) !== null) out.push(m[1]);
  return out;
}

function main() {
  var argv = process.argv.slice(2);
  var xmlPath = DEFAULT_XML;
  var extraDirs = [];
  var extraFiles = [];
  for (var i = 0; i < argv.length; i++) {
    if (argv[i] === "--xml" && argv[i + 1]) { xmlPath = path.resolve(argv[++i]); }
    else if (argv[i] === "--dir" && argv[i + 1]) { extraDirs.push(path.resolve(argv[++i])); }
    else if (argv[i] === "--file" && argv[i + 1]) { extraFiles.push(path.resolve(argv[++i])); }
  }

  var visited = {};       // resolved abs path -> true
  var missing = [];       // {file, includedFrom}
  var notFound = [];      // {ref, includedFrom}
  var queue = [];         // {ref, from}

  // 起点：symbol xml 里的全部 #include
  if (!fs.existsSync(xmlPath)) { console.error("[check-bom] 起点 xml 不存在: " + xmlPath); process.exit(2); }
  extractIncludes(fs.readFileSync(xmlPath, "utf8")).forEach(function (ref) {
    queue.push({ ref: ref, from: path.relative(REPO, xmlPath).replace(/\\/g, "/") });
  });

  while (queue.length) {
    var item = queue.shift();
    // 所有 #include 一律以 INCLUDE_BASE 为基准解析（含嵌套）
    var abs = path.resolve(INCLUDE_BASE, item.ref);
    if (visited[abs]) continue;
    visited[abs] = true;
    if (!fs.existsSync(abs)) { notFound.push({ ref: item.ref, from: item.from }); continue; }
    if (!hasBom(abs)) missing.push({ file: path.relative(REPO, abs).replace(/\\/g, "/"), from: item.from });
    var rel = path.relative(REPO, abs).replace(/\\/g, "/");
    extractIncludes(fs.readFileSync(abs, "utf8")).forEach(function (ref) {
      queue.push({ ref: ref, from: rel });
    });
  }

  // 额外目录扫描
  function walkDir(d) {
    fs.readdirSync(d, { withFileTypes: true }).forEach(function (e) {
      var p = path.join(d, e.name);
      if (e.isDirectory()) walkDir(p);
      else if (/\.as$/i.test(e.name)) {
        var abs = path.resolve(p);
        if (visited[abs]) return;
        visited[abs] = true;
        if (!hasBom(abs)) missing.push({ file: path.relative(REPO, abs).replace(/\\/g, "/"), from: "(--dir)" });
      }
    });
  }
  extraDirs.forEach(function (d) { if (fs.existsSync(d)) walkDir(d); });
  extraFiles.forEach(function (f) {
    if (!fs.existsSync(f)) { notFound.push({ ref: path.relative(REPO, f).replace(/\\/g, "/"), from: "(--file)" }); return; }
    var abs = path.resolve(f);
    if (visited[abs]) return;
    visited[abs] = true;
    if (!hasBom(abs)) missing.push({ file: path.relative(REPO, abs).replace(/\\/g, "/"), from: "(--file)" });
  });

  var scanned = Object.keys(visited).length;
  if (notFound.length) {
    console.log("[check-bom] ⚠ " + notFound.length + " 个 #include 目标未找到（可能路径基准写错——基准是 scripts/asLoader/）:");
    notFound.forEach(function (x) { console.log("  - \"" + x.ref + "\"  (from " + x.from + ")"); });
  }
  if (missing.length === 0 && notFound.length === 0) {
    console.log("[OK] check-bom: " + scanned + " 个 .as 全部带 UTF-8 BOM");
    process.exit(0);
  }
  if (missing.length) {
    console.log("[FAIL] check-bom: " + missing.length + " 个 .as 缺 BOM（编译器会静默跳过其内容）:");
    missing.forEach(function (x) { console.log("  - " + x.file + "  (included from " + x.from + ")"); });
  }
  process.exit(1);
}

main();
