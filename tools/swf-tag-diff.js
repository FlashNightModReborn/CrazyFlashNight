#!/usr/bin/env node
/*
 * swf-tag-diff.js — C1 字节金标准门（asLoader 重构 P0）
 *
 * 用途：把一个 SWF 的「有序标签结构」提取为稳定指纹，用于验证
 *   「源码级平移」（把 CDATA 多行 #include 逐字节搬进外置 manifest）
 *   编译产物是否字节等价。重点关注 DoAction(12) / DoInitAction(59)：
 *   #include 是编译期源码级内联，真正逐字节平移 → 内联结果不变 → 这两类
 *   标签的字节数与内容 hash 完全一致 ≈ 行为不变。
 *
 * 同时检测「丢 BOM 静默坑」：某帧 DoAction len<=1（只剩 End 字节）= 该帧
 *   #include 内容被编译器静默跳过（见 as2-anti-hallucination.md §0）。
 *
 * 子命令：
 *   dump  <swf> [--out file.json]      产生指纹 JSON（缺 --out 打到 stdout）
 *   diff  <golden.json> <swf|new.json> 对比；有差异 exit 1
 *
 * 设计 doc：docs/asLoader重构-架构设计-2026-06-15.md §4 轨道一
 */

var fs = require("fs");
var zlib = require("zlib");
var crypto = require("crypto");

var TAG_NAMES = {
  0: "End", 1: "ShowFrame", 2: "DefineShape", 4: "PlaceObject", 9: "SetBackgroundColor",
  12: "DoAction", 22: "DefineShape2", 26: "PlaceObject2", 28: "RemoveObject2",
  32: "DefineShape3", 34: "DefineButton2", 36: "DefineBitsLossless2", 39: "DefineSprite",
  43: "FrameLabel", 48: "DefineFont2", 56: "ExportAssets", 59: "DoInitAction",
  69: "FileAttributes", 70: "PlaceObject3", 76: "SymbolClass", 77: "Metadata",
  86: "DefineSceneAndFrameLabelData", 88: "DefineFontName"
};

function readSwf(p) {
  var raw = fs.readFileSync(p);
  var sig = raw.toString("ascii", 0, 3);
  var version = raw[3];
  var fileLength = raw.readUInt32LE(4);
  var body;
  if (sig === "FWS") body = raw.slice(8);
  else if (sig === "CWS") body = zlib.inflateSync(raw.slice(8));
  else if (sig === "ZWS") throw new Error("LZMA-compressed SWF (ZWS) not supported");
  else throw new Error("not a SWF (sig=" + sig + "): " + p);
  return { sig: sig, version: version, fileLength: fileLength, body: body };
}

// SWF body 起始：RECT(可变) + frameRate(u16) + frameCount(u16)
function tagAreaStart(body) {
  var nbits = body[0] >> 3;          // RECT 首 5 bit = 每字段位宽
  var totalBits = 5 + nbits * 4;     // nbits + 4 个 nbits 宽字段
  var rectBytes = Math.ceil(totalBits / 8);
  return rectBytes + 2 + 2;
}

// 递归遍历 tag 列表（含 DefineSprite 内嵌时间轴——asLoader 帧脚本在此）。
// sprite=null 表示主时间轴；否则为所属 DefineSprite 的 id。
function walkTagList(buf, startOff, sprite, out) {
  var off = startOff;
  var frame = 0;
  while (off + 2 <= buf.length) {
    var codeAndLen = buf.readUInt16LE(off); off += 2;
    var code = codeAndLen >> 6;
    var len = codeAndLen & 0x3f;
    if (len === 0x3f) { len = buf.readUInt32LE(off); off += 4; }
    var tagBody = buf.slice(off, off + len);
    off += len;
    var entry = { code: code, name: TAG_NAMES[code] || ("tag" + code), len: len, sprite: sprite, frame: frame };
    if (code === 39) {
      // DefineSprite: u16 id + u16 frameCount + 嵌套 tag 列表
      var spriteId = tagBody.length >= 2 ? tagBody.readUInt16LE(0) : -1;
      entry.spriteId = spriteId;
      out.push(entry);
      walkTagList(tagBody, 4, spriteId, out);   // 递归进 sprite 内嵌时间轴
    } else {
      if (code === 12 || code === 59) {
        entry.hash = crypto.createHash("sha1").update(tagBody).digest("hex").slice(0, 16);
        if (code === 59 && len >= 2) entry.classSpriteId = tagBody.readUInt16LE(0);
        // DoAction 实际字节 <=1 = 只剩 End(0x00)，帧脚本内容被静默跳过（丢 BOM 症状）
        if (code === 12 && len <= 1) entry.SUSPECT_EMPTY = true;
      }
      out.push(entry);
      if (code === 1) frame++;
      if (code === 0) return off;   // End：结束本（嵌套或顶层）列表
    }
  }
  return off;
}

function walkTags(body) {
  var tags = [];
  walkTagList(body, tagAreaStart(body), null, tags);
  return tags;
}

function fingerprint(swfPath) {
  var swf = readSwf(swfPath);
  var tags = walkTags(swf.body);
  var counts = {};
  var doAction = [], doInit = [], empties = [];
  for (var i = 0; i < tags.length; i++) {
    var t = tags[i];
    counts[t.name] = (counts[t.name] || 0) + 1;
    if (t.code === 12) { doAction.push(t); if (t.SUSPECT_EMPTY) empties.push(t); }
    if (t.code === 59) doInit.push(t);
  }
  return {
    file: swfPath.replace(/\\/g, "/"),
    sig: swf.sig, version: swf.version, bodyBytes: swf.body.length,
    tagCount: tags.length, counts: counts,
    doActionCount: doAction.length, doInitActionCount: doInit.length,
    suspectEmptyDoAction: empties.map(function (t) { return { sprite: t.sprite, frame: t.frame, len: t.len }; }),
    tags: tags
  };
}

function loadDump(p) {
  if (/\.json$/i.test(p)) return JSON.parse(fs.readFileSync(p, "utf8"));
  return fingerprint(p);
}

function diff(goldenPath, otherPath) {
  var a = loadDump(goldenPath);
  var b = loadDump(otherPath);
  var problems = [];
  function note(s) { problems.push(s); }

  if (a.doActionCount !== b.doActionCount)
    note("DoAction 数量变化: " + a.doActionCount + " -> " + b.doActionCount);
  if (a.doInitActionCount !== b.doInitActionCount)
    note("DoInitAction(class) 数量变化: " + a.doInitActionCount + " -> " + b.doInitActionCount + "  (class 嵌入集变了)");

  // 逐 tag 比对有序结构（code + len + 对 12/59 比 hash）
  var n = Math.max(a.tags.length, b.tags.length);
  var seqDiffs = 0;
  for (var i = 0; i < n; i++) {
    var ta = a.tags[i], tb = b.tags[i];
    if (!ta) { note("[#" + i + "] golden 无此 tag，new 多出 " + tb.name); seqDiffs++; continue; }
    if (!tb) { note("[#" + i + "] new 缺失 tag " + ta.name); seqDiffs++; continue; }
    if (ta.code !== tb.code) { note("[#" + i + "] tag 类型 " + ta.name + " -> " + tb.name); seqDiffs++; continue; }
    if (ta.code === 12 || ta.code === 59) {
      if (ta.len !== tb.len || ta.hash !== tb.hash) {
        note("[#" + i + " " + ta.name + (tb.sprite != null ? " sprite=" + tb.sprite : "") + " frame=" + tb.frame +
          "] 内容变化 len " + ta.len + "->" + tb.len + " hash " + ta.hash + "->" + tb.hash);
        seqDiffs++;
      }
    } else if (ta.len !== tb.len) {
      note("[#" + i + " " + ta.name + "] len " + ta.len + "->" + tb.len);
      seqDiffs++;
    }
    if (seqDiffs >= 60) { note("... (差异过多，截断)"); break; }
  }

  // 丢 BOM 静默坑：只报「新出现」的空 DoAction（golden 已有的=故意的注释帧，如 49-52）
  var goldenEmpty = {};
  (a.suspectEmptyDoAction || []).forEach(function (e) { goldenEmpty[e.sprite + ":" + e.frame] = true; });
  var newEmpty = (b.suspectEmptyDoAction || []).filter(function (e) { return !goldenEmpty[e.sprite + ":" + e.frame]; });
  if (newEmpty.length)
    note("⚠ 疑似丢 BOM（新增空 DoAction len<=1）@ frame " + newEmpty.map(function (e) { return e.frame; }).join(",") +
      "  —— 该帧 #include 内容可能被编译器静默跳过");

  if (problems.length === 0) {
    console.log("[OK] swf-tag-diff: 字节等价（DoAction " + b.doActionCount +
      " / DoInitAction " + b.doInitActionCount + " 全部 hash 一致）");
    return 0;
  }
  console.log("[DIFF] swf-tag-diff 检出 " + problems.length + " 处差异：");
  problems.forEach(function (s) { console.log("  - " + s); });
  return 1;
}

function main() {
  var argv = process.argv.slice(2);
  var cmd = argv[0];
  if (cmd === "dump") {
    var swf = argv[1];
    if (!swf) { console.error("用法: swf-tag-diff dump <swf> [--out file.json]"); process.exit(2); }
    var fp = fingerprint(swf);
    var outIdx = argv.indexOf("--out");
    var json = JSON.stringify(fp, null, 1);
    if (outIdx >= 0 && argv[outIdx + 1]) {
      fs.writeFileSync(argv[outIdx + 1], json);
      console.log("[dump] " + fp.file + "  tags=" + fp.tagCount +
        " DoAction=" + fp.doActionCount + " DoInitAction=" + fp.doInitActionCount +
        " -> " + argv[outIdx + 1]);
      if (fp.suspectEmptyDoAction.length)
        console.log("  ⚠ 空 DoAction(len<=1): frame " + fp.suspectEmptyDoAction.map(function (e) { return e.frame; }).join(","));
    } else {
      process.stdout.write(json + "\n");
    }
    process.exit(0);
  } else if (cmd === "diff") {
    if (!argv[1] || !argv[2]) { console.error("用法: swf-tag-diff diff <golden.json> <swf|new.json>"); process.exit(2); }
    process.exit(diff(argv[1], argv[2]));
  } else {
    console.error("swf-tag-diff — C1 字节金标准门\n用法:\n  swf-tag-diff dump <swf> [--out file.json]\n  swf-tag-diff diff <golden.json> <swf|new.json>");
    process.exit(2);
  }
}

main();
