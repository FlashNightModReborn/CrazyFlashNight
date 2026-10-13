#!/usr/bin/env node
/*
 * swf-function-sizes.js — AVM1 函数体 64KB 上限门（asLoader collapse 安全网）
 *
 * 背景（2026-06-16 真机实证）：`DefineFunction2.codeSize` / `DefineFunction.codeSize` 是 **UI16**
 *   → 单个函数/方法体字节码 **>65535 字节即无法表示**。帧脚本(DoAction)长度是 UI32 无此限，故
 *   236KB 的单位函数帧本身能编；但一旦把这种大帧 wrap 进 `function(){...}`（或 class 方法），函数体
 *   字节码溢出 UI16 → 编译器 0 错却产出**坏函数**（运行时根本不执行）。stage-wrap 批量真机 boot 即因此
 *   静默失败（f36 506K/f37 456K/f41 189K 源码的 staged 函数从未执行）。
 *
 * 本工具解析 SWF 全部 DoAction/DoInitAction 动作流（含 DefineSprite 内嵌 + 函数体内嵌套函数），抽取每个
 *   DefineFunction/DefineFunction2 的 codeSize，报告最大者，并对 >= 阈值（默认 60000，留 ~5KB 余量）失败。
 *   collapse/class-chunk 施工：每次编译后跑本门，确认每个 staged 方法 < 64KB。
 *
 * ⚠ **能力边界（必读，勿误以为本门能拦一切 64KB 溢出）**：codeSize 是 UI16，一个**已经**溢出（如体 70000B）
 *   的坏函数其 codeSize 字段存的是低 16 位（70000 & 0xFFFF = 4464），从编译后 SWF 看与一个真 4464B 的小函数
 *   **字节级无法区分**（CS6 不报错、流不一定 desync）。故本门只能拦「**逼近**阈值」（靠默认 60000 给 ~5.5KB
 *   余量预警），**无法**拦「**已越过** 64KB 后回绕成小值」的函数。canonical 源闭包度量可帮助定位
 *   chunk 候选，但源字节与 AVM1 codeSize 没有可证明的单调边界，不能单独作为 hard gate。
 *   当前最大值会随每次发布变化，不在源码注释里冻结易腐数字；任何「向 boot 加代码」都必须重跑本门，
 *   并结合源闭包度量与 fresh 行为证据。
 *
 * 用法：
 *   node tools/swf-function-sizes.js <swf> [--max 60000 | --max=60000] [--top 15] [--json]
 *   exit 1 当存在 codeSize >= --max 的函数；exit 2 当 --max 非数字（避免 NaN 比较静默放过）。
 */

var path = require("path");
var scanSwf = require("./swf-metadata").scanSwf;

function main() {
  var argv = process.argv.slice(2);
  var swfPath = argv.filter(function (a) { return a.indexOf("--") !== 0 && !/^\d+$/.test(a) || /\.swf$/i.test(a); })[0];
  swfPath = argv.find(function (a) { return /\.swf$/i.test(a); }) || swfPath;
  if (!swfPath) { console.error("用法: swf-function-sizes.js <swf> [--max 60000] [--top 15] [--json]"); process.exit(2); }
  // --max 解析：兼容 `--max 60000` 与 `--max=60000`；非数字 → exit 2（旧版 parseInt(undefined)=NaN，
  //   而 `codeSize >= NaN` 恒 false → 门被静默关成绿灯。一个 typo 不能让安全网失效）。
  var MAX = 60000;
  for (var ai = 0; ai < argv.length; ai++) {
    // 裸 `--max`（末位无值）→ argv[ai+1]=undefined → parseInt(undefined)=NaN → 下方 isNaN 拦（exit 2）。
    // 不加 `&& argv[ai+1]!=null` 守卫：那样裸 --max 会静默回落默认 60000，掩盖「想设阈值却漏填」的意图。
    if (argv[ai] === "--max") MAX = parseInt(argv[ai + 1], 10);
    else { var mEq = /^--max=(.*)$/.exec(argv[ai]); if (mEq) MAX = parseInt(mEq[1], 10); }
  }
  if (isNaN(MAX)) { console.error("[ERROR] --max 需要数字阈值（如 --max 60000 或 --max=60000）；收到非数字 → 拒绝（NaN 比较会静默放过 64KB 溢出）"); process.exit(2); }
  var topIdx = argv.indexOf("--top"); var TOP = topIdx >= 0 ? parseInt(argv[topIdx + 1], 10) : 15;
  if (isNaN(TOP)) TOP = 15;
  var asJson = argv.indexOf("--json") >= 0;

  var swf = scanSwf(swfPath, path.resolve(__dirname, "../tmp/swf-metadata-cache"));
  var funcs = swf.functions.slice();
  funcs.sort(function (a, b) { return b.codeSize - a.codeSize; });
  var over = funcs.filter(function (f) { return f.codeSize >= MAX; });

  if (asJson) {
    process.stdout.write(JSON.stringify({ total: funcs.length, max: MAX, over: over, top: funcs.slice(0, TOP) }, null, 1) + "\n");
    process.exit(over.length ? 1 : 0);
  }

  console.log("=== AVM1 函数体 64KB 门 ===  " + swfPath.replace(/\\/g, "/"));
  console.log("函数总数: " + funcs.length + "   阈值(--max): " + MAX + " 字节 (UI16 上限 65535)");
  console.log("");
  console.log("最大的 " + Math.min(TOP, funcs.length) + " 个函数体:");
  funcs.slice(0, TOP).forEach(function (f) {
    var flag = f.codeSize >= MAX ? "  ✗超限" : (f.codeSize >= MAX * 0.8 ? "  ⚠接近" : "");
    console.log("  " + String(f.codeSize).padStart(6) + " B  " + f.type + "  " + f.name + flag);
  });
  console.log("");
  if (over.length) {
    console.log("✗ " + over.length + " 个函数体 >= " + MAX + " B（接近/超 UI16 64KB 上限，运行时会坏）：");
    over.forEach(function (f) { console.log("    " + f.codeSize + " B  " + f.name + "  @ " + f.owner); });
    process.exit(1);
  }
  console.log("✓ 未发现 codeSize >= " + MAX + " B 的近墙项；本门不能排除已越墙回绕，须与源闭包度量和 fresh 行为证据合用。");
}
main();
