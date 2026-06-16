#!/usr/bin/env node
/*
 * trace-diff.js — C1 行为 trace 等价门（asLoader 重构 轨道二，P4/P5 用）
 *
 * BootSequencer 改变 bytecode 结构 → swf-tag-diff 字节门不适用。改用「行为 trace 等价」：
 *   给当前 boot 与 BootSequencer 各发一条有序事件流（走 socket sendServerMessage 或日志），
 *   抽取规范化事件序列后 diff。顺序 + 事件类型一致 ≈ boot 行为不变（容时间戳/细节差）。
 *
 * 事件来源：Flash SA 无 trace，启动期诊断走 `_root.server.sendServerMessage("[BootstrapAS] ...")`
 *   （asLoader.xml:134-135 既有 __bslog 模式）。本工具同时识别既有 [BootstrapAS] 文案与未来
 *   BootSequencer 的规范 `[BOOTTRACE] event=<ID>` 文案，故对当前 boot 的真实 socket 日志即可用。
 *
 * 用法：
 *   node tools/trace-diff.js extract <log>                抽取规范化事件序列（调试用）
 *   node tools/trace-diff.js diff <golden.log> <new.log>  diff；分歧→exit 1
 *   node tools/trace-diff.js selftest                     内置合成用例自测
 *
 * 构建标准：docs/asLoader-BootSequencer-构建标准-2026-06-16.md §5
 */

var fs = require("fs");

// 规范事件词表（boot 关键节点）。规则 regex → canonical event。
// 同时覆盖既有 [BootstrapAS] 文案 与 未来 [BOOTTRACE] event=<ID> 文案。
var RULES = [
  { re: /event=s2_enter\b|frame4 entered/i, ev: "S2_ENTER" },
  { re: /event=socket_ready\b|socket ready|firing handshake/i, ev: "SOCKET_READY" },
  { re: /event=handshake_success\b|hs=Success|handshake (FAILED|success)/i, ev: "HANDSHAKE_RESULT" },
  { re: /event=preload\b|firing preload/i, ev: "PRELOAD_FIRE" },
  { re: /event=recovery_enter\b|recovery gate enter|存档恢复.*(enter|进入)/i, ev: "RECOVERY_GATE_ENTER" },
  { re: /event=recovery_exit\b|recovery gate exit|存档恢复.*(exit|离开)/i, ev: "RECOVERY_GATE_EXIT" },
  { re: /event=ready\b|sending ready ack/i, ev: "READY_ACK" },
  { re: /event=boot_check\b|jumping boot_check|bootstrap complete/i, ev: "BOOT_CHECK_JUMP" },
  { re: /event=taskdata\b|任务数据加载(完毕|成功)/i, ev: "TASKDATA_OK" },
  { re: /event=tasktext\b|任务文本加载(完毕|成功)/i, ev: "TASKTEXT_OK" },
  { re: /event=parse_task\b|ParseTaskData|任务数据.*配置/i, ev: "PARSE_TASK" },
  { re: /event=crafting\b|合成表数据加载(完毕|成功)/i, ev: "CRAFTING_OK" },
  { re: /event=handoff\b|f91|_root\.play|卸载影片剪辑/i, ev: "HANDOFF_PLAY" },
];

function extractEvents(text) {
  var out = [];
  var lines = text.split(/\r?\n/);
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i];
    for (var r = 0; r < RULES.length; r++) {
      if (RULES[r].re.test(line)) { out.push({ ev: RULES[r].ev, line: line.trim() }); break; }
    }
  }
  return out;
}

// LCS over event-id sequences → 对齐报告（缺失/多余/顺序）
function lcs(a, b) {
  var n = a.length, m = b.length;
  var dp = [];
  for (var i = 0; i <= n; i++) { dp[i] = []; for (var j = 0; j <= m; j++) dp[i][j] = 0; }
  for (i = 1; i <= n; i++) for (j = 1; j <= m; j++)
    dp[i][j] = a[i - 1] === b[j - 1] ? dp[i - 1][j - 1] + 1 : Math.max(dp[i - 1][j], dp[i][j - 1]);
  // backtrack → ops
  var ops = [], ii = n, jj = m;
  while (ii > 0 && jj > 0) {
    if (a[ii - 1] === b[jj - 1]) { ops.unshift({ t: "=", v: a[ii - 1] }); ii--; jj--; }
    else if (dp[ii - 1][jj] >= dp[ii][jj - 1]) { ops.unshift({ t: "-", v: a[ii - 1] }); ii--; }
    else { ops.unshift({ t: "+", v: b[jj - 1] }); jj--; }
  }
  while (ii > 0) { ops.unshift({ t: "-", v: a[--ii] }); }
  while (jj > 0) { ops.unshift({ t: "+", v: b[--jj] }); }
  return ops;
}

function diff(goldenPath, newPath) {
  var ga = extractEvents(fs.readFileSync(goldenPath, "utf8")).map(function (e) { return e.ev; });
  var nb = extractEvents(fs.readFileSync(newPath, "utf8")).map(function (e) { return e.ev; });
  var ops = lcs(ga, nb);
  var changes = ops.filter(function (o) { return o.t !== "="; });
  console.log("golden 事件: " + ga.length + "  new 事件: " + nb.length + "  共同子序列: " + (ops.length - changes.length));
  if (changes.length === 0 && ga.length === nb.length) {
    console.log("[OK] trace 等价：事件序列完全一致 (" + ga.join(" → ") + ")");
    return 0;
  }
  console.log("[DIFF] 事件序列分歧：");
  ops.forEach(function (o) {
    if (o.t === "=") return;
    console.log("  " + (o.t === "-" ? "− golden 有 / new 缺失: " : "+ new 多出 / golden 无: ") + o.v);
  });
  return 1;
}

function selftest() {
  var fail = 0;
  function check(name, cond) { console.log((cond ? "  [OK] " : "  [FAIL] ") + name); if (!cond) fail++; }
  var goldenLog =
    "[BootstrapAS] frame4 entered, _bootstrap=true\n" +
    "[BootstrapAS] socket ready at tick=3, firing handshake\n" +
    "[BootstrapAS] tick=30 hs=Success\n" +
    "[BootstrapAS] firing preload\n" +
    "[BootstrapAS] sending ready ack\n" +
    "[BootstrapAS] bootstrap complete, jumping boot_check\n" +
    "主程序：任务数据加载完毕\n主程序：任务文本加载完毕\n主程序：合成表数据加载成功！\n";
  var ev = extractEvents(goldenLog).map(function (e) { return e.ev; });
  check("既有 [BootstrapAS] 日志抽出 9 个事件", ev.length === 9);
  check("顺序: S2_ENTER 在首", ev[0] === "S2_ENTER");
  check("含 BOOT_CHECK_JUMP", ev.indexOf("BOOT_CHECK_JUMP") >= 0);
  check("含 CRAFTING_OK", ev.indexOf("CRAFTING_OK") >= 0);

  // BootSequencer 规范文案应映射到同序列
  var newLog =
    "[BOOTTRACE] event=s2_enter\n[BOOTTRACE] event=socket_ready\n[BOOTTRACE] event=handshake_success\n" +
    "[BOOTTRACE] event=preload\n[BOOTTRACE] event=ready\n[BOOTTRACE] event=boot_check\n" +
    "[BOOTTRACE] event=taskdata\n[BOOTTRACE] event=tasktext\n[BOOTTRACE] event=crafting\n";
  var ev2 = extractEvents(newLog).map(function (e) { return e.ev; });
  check("BOOTTRACE 规范文案抽出同 9 事件序列", JSON.stringify(ev) === JSON.stringify(ev2));

  // 注入分歧：new 缺失 preload
  var newBad = newLog.replace("[BOOTTRACE] event=preload\n", "");
  fs.writeFileSync(".__tg_g.tmp", goldenLog); fs.writeFileSync(".__tg_b.tmp", newBad);
  var rc = diffQuiet(".__tg_g.tmp", ".__tg_b.tmp");
  check("缺失 preload → diff 报红(rc=1)", rc === 1);
  // 一致用例
  fs.writeFileSync(".__tg_n.tmp", newLog);
  var rc2 = diffQuiet(".__tg_g.tmp", ".__tg_n.tmp");
  check("等价用例 → rc=0", rc2 === 0);
  try { fs.unlinkSync(".__tg_g.tmp"); fs.unlinkSync(".__tg_b.tmp"); fs.unlinkSync(".__tg_n.tmp"); } catch (e) {}

  console.log(fail === 0 ? "\n[OK] trace-diff selftest 全过" : "\n[FAIL] " + fail + " 项");
  process.exit(fail === 0 ? 0 : 1);
}
function diffQuiet(g, n) {
  var ga = extractEvents(fs.readFileSync(g, "utf8")).map(function (e) { return e.ev; });
  var nb = extractEvents(fs.readFileSync(n, "utf8")).map(function (e) { return e.ev; });
  var ops = lcs(ga, nb);
  return (ops.filter(function (o) { return o.t !== "="; }).length === 0 && ga.length === nb.length) ? 0 : 1;
}

function main() {
  var a = process.argv.slice(2);
  if (a[0] === "extract" && a[1]) {
    extractEvents(fs.readFileSync(a[1], "utf8")).forEach(function (e, i) { console.log((i + 1) + ". " + e.ev + "   « " + e.line); });
  } else if (a[0] === "diff" && a[1] && a[2]) {
    process.exit(diff(a[1], a[2]));
  } else if (a[0] === "selftest") {
    selftest();
  } else {
    console.error("用法:\n  trace-diff extract <log>\n  trace-diff diff <golden.log> <new.log>\n  trace-diff selftest");
    process.exit(2);
  }
}
main();
