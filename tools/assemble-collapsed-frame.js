// tools/assemble-collapsed-frame.js
// 组装 asLoader 单帧塌缩后的帧 CDATA（评审产物 → scripts/asLoaderManifest/_collapsed_frame.as；**不触碰 asLoader.xml**）。
// 来源：13 个已 staged 同步帧 + 16 个 loader-fire 帧 manifest（均 BOM 感知读取）。
// 产出结构：帧顶(_lockroot/stop/打印加载内容/onError) + 联合通配 import 头(收集去重) + staged fN 定义(去内联调用)
//   + loader-fire fN 定义(import 提升) + stage 分组函数(s0..s9) + BootSequencer.run(this)。
// 协作：异步/控制帧由 BootSequencer.as 编排——f4握手(S2)/f5,6 await(S3,4)/f7 parse(S5 经 b.s5_parseTask(host))/
//   f9,10,18,26,32(S6 含 _root.loaders 逐tick抽干)/f75 craft(S9)/f91 handoff(S10)。
'use strict';
var fs = require('fs'), path = require('path');
var REPO = path.resolve(__dirname, '..');
var MAN = path.join(REPO, 'scripts', 'asLoaderManifest');
var OUT = path.join(MAN, '_collapsed_frame.as');
var BOM = Buffer.from([0xEF, 0xBB, 0xBF]);

var STAGED = [2, 3, 9, 10, 18, 32, 36, 37, 38, 39, 40, 41, 42]; // 同步 #include 帧（已 stage-wrap）
var S7_LOADERS = [53, 54, 55, 56, 58, 59];                       // S7 杂项 loader-fire（子弹/发型/色彩/宠物/技能/过场）
var S8_LOADERS = [62, 63, 64, 65, 66, 67, 68, 69, 70, 74];       // S8 fire-and-forget fanout

// 与 stage-wrap-frame.js 同源（分号可选、标识符分段式防贪婪吞 .*）
var IMPORT_RE = /^[ \t]*import\s+([A-Za-z_][\w$]*(?:\.[\w$]+)*(?:\.\*)?)[ \t]*;?[ \t]*\r?\n?/gm;

function readBom(p) {
  var raw = fs.readFileSync(p);
  var hb = raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF;
  return hb ? raw.slice(3).toString('utf8') : raw.toString('utf8');
}

var _pkgs = {};
function collectPkgs(text) {
  var m; IMPORT_RE.lastIndex = 0;
  while ((m = IMPORT_RE.exec(text)) !== null) {
    var id = m[1];
    var pkg = /\.\*$/.test(id) ? id.slice(0, -2) : id.slice(0, id.lastIndexOf('.'));
    if (pkg) _pkgs[pkg] = true;
  }
}
function stripImports(t) { return t.replace(IMPORT_RE, ''); }

// staged manifest → 仅函数定义块（去帧首注释/import/guard/末尾内联调用）
function extractStagedDefs(text) {
  var t = text.replace(/^(?:[ \t]*\/\/[^\n]*\r?\n)+/, '');                       // 帧首注释块
  t = stripImports(t);                                                          // import（已 collectPkgs）
  t = t.replace(/^[ \t]*if\s*\(_root\.__boot == undefined\)[^\n]*\r?\n/m, '');   // guard（统一只发一次）
  t = t.replace(/^[ \t]*_root\.__boot\.f\d+(?:_\d+)?\(\);[ \t]*\r?\n?/gm, '');    // 末尾内联调用
  return t.replace(/^\s+|\s+$/g, '');
}

// 提取帧定义的全部 _root.__boot.fN(_k) 函数名（顺序）；chunk 帧→[fN_1..fN_k]，单函数帧→[fN]
function extractDefNames(text) {
  var names = [], re = /_root\.__boot\.(f\d+(?:_\d+)?)\s*=\s*function/g, m;
  while ((m = re.exec(text)) !== null) names.push(m[1]);
  return names;
}

// loader-fire manifest（裸 #include 无、直接 loader 调用）→ 包成 _root.__boot.fN（import 提升、含交错 import 如 f64）
function wrapLoaderFire(N, text) {
  var body = text.replace(/^(?:[ \t]*\/\/[^\n]*\r?\n)+/, '');
  body = stripImports(body).replace(/^\s+|\s+$/g, '');
  return '_root.__boot.f' + N + ' = function() {\n' + body.replace(/^/gm, '    ') + '\n};';
}

// 1) staged fN 定义 + 函数名表（供 stage 分组按真实 chunk 名调用，绕开「调 base fN 而 chunk 帧无 base fN」的坑）
var frameNames = {};
var stagedDefs = STAGED.map(function (N) {
  var t = readBom(path.join(MAN, 'frame' + N + '.as')); collectPkgs(t);
  frameNames[N] = extractDefNames(t);
  return extractStagedDefs(t);
});
// 调用某帧全部函数（chunk 帧=全 chunk 顺序调用；单函数帧=fN）
function callsFor(N) {
  return (frameNames[N] && frameNames[N].length ? frameNames[N] : ['f' + N])
    .map(function (nm) { return '_root.__boot.' + nm + '();'; }).join(' ');
}
// 2) loader-fire fN 定义
var loaderDefs = S7_LOADERS.concat(S8_LOADERS).map(function (N) {
  var t = readBom(path.join(MAN, 'frame' + N + '.as')); collectPkgs(t); return wrapLoaderFire(N, t);
});
// 3) 联合头（收集去重排序；lint --fold-specific 已证 82 超集 0 碰撞，子集必 0）
var header = Object.keys(_pkgs).sort().map(function (p) { return 'import ' + p + '.*;'; }).join('\n');

// 4) stage 分组（手写：调用顺序 + s5/s9 移植 this→host/data，s7 含 f48 打印）
var s7calls = [36, 37, 38, 39, 40, 41, 42].map(callsFor).join(' ');   // ⚠ 用 callsFor：f36/f37/f41 是 chunk 帧，无 base fN
var s7loaderCalls = S7_LOADERS.map(function (n) { return '_root.__boot.f' + n + '();'; }).join(' ');
var s8calls = S8_LOADERS.map(function (n) { return '_root.__boot.f' + n + '();'; }).join(' ');

var wiring = [
  '// === stage 分组函数（BootSequencer 按序 + 异步门调度） ===',
  '_root.__boot.s0_init = function() {',
  '    org.flashNight.gesh.init.GlobalInitializer.initialize();   // 原 f1',
  '};',
  '_root.__boot.s1_syncCode = function() {',
  '    ' + callsFor(2) + ' ' + callsFor(3) + '                       // 引擎 + 通信(建 _root._bootstrap)',
  '};',
  '_root.__boot.s5_parseTask = function(host) {                    // 原 f7（this→host：rawTaskData 在 BootSequencer.host 上）',
  '    org.flashNight.arki.task.TaskUtil.ParseTaskData(host.rawTaskData, host.rawTextData);',
  '    host.rawTaskData = null;',
  '    host.rawTextData = null;',
  '    var guideLoader = org.flashNight.gesh.json.LoadJson.ProgressGuideLoader.getInstance();',
  '    guideLoader.loadGuideData(',
  '        function(data:Object):Void { org.flashNight.arki.task.TaskUtil.ParseGuideData(data); },',
  '        function():Void {}',
  '    );',
  '};',
  '_root.__boot.s6_pre = function() {',
  '    ' + callsFor(9) + ' ' + callsFor(10) + ' ' + callsFor(18) + '  // 建_root.loaders + 兼容×4 push + 最终化1 跑 preloaders',
  '};',
  '_root.__boot.s6_post = function() {',
  '    ' + callsFor(32) + '                                          // 最终化3 跑 loaderkillers + 删三队列',
  '};',
  '_root.__boot.s7_syncLogic = function() {',
  '    ' + s7calls + '   // 单位函数/装备/功能/关卡/战斗/UI交互/视觉',
  '    打印加载内容("加载杂项数据……");                              // 原 f48',
  '    ' + s7loaderCalls + '   // 子弹/发型/色彩/宠物/技能/过场',
  '};',
  '_root.__boot.s8_fanout = function() {',
  '    ' + s8calls + '   // fire-and-forget：物品/敌人属性/称号+材料+地图/情报/关卡/环境×2/基建/装备配置/NPC技能',
  '};',
  '_root.__boot.s9_onCrafting = function(data) {                   // 原 f75 cb：建改装清单 + ItemObtainIndex',
  '    var carftingDict = {};',
  '    for (var category in data) {',
  '        var list = data[category];',
  '        for (var i = 0; i < list.length; i++) {',
  '            var item = list[i];',
  '            carftingDict[item.name] = item;',
  '            if (isNaN(item.value)) item.value = 1;',
  '        }',
  '    }',
  '    _root.改装清单 = data;',
  '    _root.改装清单对象 = carftingDict;',
  '    var obtainIndex = org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance();',
  '    obtainIndex.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);',
  '};'
].join('\n');

var out = [
  '// asLoader 单帧 boot 帧 CDATA（由 tools/assemble-collapsed-frame.js 生成；asLoader.xml 单关键帧 #include 之，勿手改本文件——改组装器重生成）。',
  '// 联合头 ' + Object.keys(_pkgs).length + ' 包 | staged fN ' + STAGED.length + ' | loader-fire fN ' + (S7_LOADERS.length + S8_LOADERS.length) + ' | s0..s9 分组 + BootSequencer.run',
  '// 异步/控制帧(f4握手/f5,6 await/f7→s5_parseTask/f26 最终化2 队列/f75 craft/f91 handoff) 由 BootSequencer.as 编排。',
  'this._lockroot = false;',
  'this.stop();',
  '',
  '// === 帧顶跨帧符号（门② 结论：必须时间轴作用域，不可入 staged 函数体） ===',
  'function 打印加载内容(str) {',
  '    _root.加载内容文本.text = str;',
  '}',
  'function onError():Void {',
  '    // 原 f41 空 TODO 死桩；保留同等 benign no-op（f3 载入关卡数据错误回调裸调，经闭包→时间轴解析）',
  '}',
  '',
  '// === 联合通配 import 头（收集去重；lint --fold-specific 已证 82 超集 0 碰撞，子集亦 0） ===',
  header,
  'import org.flashNight.boot.BootSequencer;   // 显式 import（L42 陷阱：CS6 会话缓存对会话内新类需显式 import，FQN 亦可能失败）',
  '',
  '// === staged 同步代码函数（仅定义，无内联调用；#include 编译期展开） ===',
  'if (_root.__boot == undefined) _root.__boot = {};',
  stagedDefs.join('\n'),
  '',
  '// === loader-fire 函数（import 已提升至联合头） ===',
  loaderDefs.join('\n'),
  '',
  wiring,
  '',
  '// === 启动状态机（tick 挂 _root，自删后回调可达） ===',
  'BootSequencer.run(this);',
  ''
].join('\n');

fs.writeFileSync(OUT, Buffer.concat([BOM, Buffer.from(out, 'utf8')]));
console.log('[DONE] 写出 ' + path.relative(REPO, OUT).replace(/\\/g, '/'));
console.log('  联合头 ' + Object.keys(_pkgs).length + ' 包 | staged fN ' + STAGED.length + ' | loader-fire fN ' + (S7_LOADERS.length + S8_LOADERS.length));
console.log('  ⚠ 评审产物，未改 asLoader.xml。需配合 BootSequencer S5 调 this.b.s5_parseTask(this.host)。');
