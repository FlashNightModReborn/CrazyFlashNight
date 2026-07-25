// tools/assemble-collapsed-frame.js
// 组装 asLoader 单帧塌缩后的帧 CDATA（评审产物 → scripts/asLoaderManifest/_collapsed_frame.as；**不触碰 asLoader.xml**）。
// 来源：BOOT_SOURCES 内 13 个 staged 同步帧 + 16 个 loader-fire 帧（均强制 UTF-8 BOM）。
// 产出结构：帧顶(_lockroot/stop/打印加载内容/onError) + 联合通配 import 头(收集去重) + staged fN 定义(去内联调用)
//   + loader-fire fN 定义(import 提升) + 由表派生的纯装配 stage 函数 + BootSequencer.run(this)。
// 协作：S0/S5/S9 与异步/控制行为全部归 BootSequencer.as；本工具只读取、排序、展开、校验和生成。
'use strict';
var fs = require('fs'), path = require('path');
var REPO = path.resolve(__dirname, '..');
var MAN = path.join(REPO, 'scripts', 'asLoaderManifest');
var INCLUDE_BASE = path.join(REPO, 'scripts', 'asLoader');
var OUT = path.join(MAN, '_collapsed_frame.as');
var BOM = Buffer.from([0xEF, 0xBB, 0xBF]);
var CLI_ARGS = process.argv.slice(2);
if (CLI_ARGS.some(function (arg) { return arg !== '--check'; })) {
  console.error('用法: node tools/assemble-collapsed-frame.js [--check]');
  process.exit(2);
}
var CHECK_ONLY = CLI_ARGS.indexOf('--check') >= 0;

// 唯一 live 输入表。数组顺序就是同一 phase 内的确定性执行顺序；不要另建 frame 数组或平行清单。
// name 只用于维护定位，frame 保留旧坐标，phase 是生成的装配函数名，shape 决定机械展开方式。
var BOOT_SOURCES = [
  { name: 'engine-core',                 frame: 2,  phase: 's1_syncCode',    shape: 'staged' },
  { name: 'communication-bootstrap',     frame: 3,  phase: 's1_syncCode',    shape: 'staged' },

  { name: 'loader-queue-init',           frame: 9,  phase: 's6_pre',         shape: 'staged' },
  { name: 'legacy-system-compatibility', frame: 10, phase: 's6_pre',         shape: 'staged' },
  { name: 'preloader-fire',              frame: 18, phase: 's6_pre',         shape: 'staged' },
  { name: 'loader-cleanup',              frame: 32, phase: 's6_post',        shape: 'staged' },

  { name: 'unit-functions',              frame: 36, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'equipment-functions',         frame: 37, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'feature-functions',           frame: 38, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'stage-functions',             frame: 39, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'combat-functions',            frame: 40, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'ui-interaction',              frame: 41, phase: 's7_syncLogic',   shape: 'staged' },
  { name: 'visual-system',               frame: 42, phase: 's7_syncLogic',   shape: 'staged' },

  { name: 'bullet-mappings',             frame: 53, phase: 's7_miscLoaders', shape: 'loader-fire' },
  { name: 'hairstyles',                  frame: 54, phase: 's7_miscLoaders', shape: 'loader-fire' },
  { name: 'color-presets',               frame: 55, phase: 's7_miscLoaders', shape: 'loader-fire' },
  { name: 'pets',                        frame: 56, phase: 's7_miscLoaders', shape: 'loader-fire' },
  { name: 'skill-data',                  frame: 58, phase: 's7_miscLoaders', shape: 'loader-fire' },
  { name: 'loading-scenes',              frame: 59, phase: 's7_miscLoaders', shape: 'loader-fire' },

  { name: 'item-data',                   frame: 62, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'enemy-properties',            frame: 63, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'hero-material-map-data',      frame: 64, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'information-data',            frame: 65, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'stage-data',                  frame: 66, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'stage-environment',           frame: 67, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'scene-environment',           frame: 68, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'infrastructure-data',         frame: 69, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'equipment-config',            frame: 70, phase: 's8_fanout',      shape: 'loader-fire' },
  { name: 'npc-skills',                  frame: 74, phase: 's8_fanout',      shape: 'loader-fire' }
];
var VALID_PHASE_SHAPES = {
  s1_syncCode: 'staged',
  s6_pre: 'staged',
  s6_post: 'staged',
  s7_syncLogic: 'staged',
  s7_miscLoaders: 'loader-fire',
  s8_fanout: 'loader-fire'
};
// 只作 canonical-LF 调查信号，不作构建 hard gate：源字节与 AVM1 codeSize
// 没有可证明的单调边界，单凭它阻断会把注释/格式变化变成维护 ratchet。
var SOURCE_REVIEW_THRESHOLD = 70000;

// CS6 常驻会话对“本会话内新增类”的包索引可能陈旧：即使已有通配 import/FQN，仍可能无法解析。
// 只允许在这里维护需要绕过该 L42 陷阱的具体 import，生成后由 exact-match 门守住白名单。
var SPECIFIC_IMPORTS = [
  'org.flashNight.boot.BootSequencer',
  'org.flashNight.arki.unit.Action.Skill.DrugInputService',
  'org.flashNight.arki.unit.Action.Skill.ManualCooldownService',
  'org.flashNight.arki.unit.Action.Skill.QuickSkillInputService',
  'org.flashNight.arki.unit.Action.Skill.SkillReleaseGuard',
  'org.flashNight.arki.unit.Action.Skill.SkillAttributeCore',
  'org.flashNight.arki.unit.Action.Skill.SkillDamageCore',
  'org.flashNight.arki.unit.Action.Skill.SkillReloadCore',
  'org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService'
];
// AS2 不允许同包通配 import 与具体 import 同时出现；从唯一白名单派生包集合，
// 避免新增具体类时还要手工同步第二张事实表。
var SPECIFIC_IMPORT_PACKAGES = {};
SPECIFIC_IMPORTS.forEach(function (className) {
  var lastDot = className.lastIndexOf('.');
  if (lastDot <= 0 || lastDot === className.length - 1)
    throw new Error('非法具体 import: ' + className);
  SPECIFIC_IMPORT_PACKAGES[className.slice(0, lastDot)] = true;
});

// 与 stage-wrap-frame.js 同源（分号可选、标识符分段式防贪婪吞 .*）
var IMPORT_RE = /^[ \t]*import\s+([A-Za-z_][\w$]*(?:\.[\w$]+)*(?:\.\*)?)[ \t]*;?[ \t]*\r?\n?/gm;

function readBom(p) {
  var raw = fs.readFileSync(p);
  var hb = raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF;
  if (!hb) throw new Error(path.relative(REPO, p).replace(/\\/g, '/') + ' 缺少 UTF-8 BOM');
  var txt = raw.slice(3).toString('utf8');
  // 行尾规范：真 CRLF→LF；剩余「裸 CR」是源 staged manifest 每行尾的 `\r<空格>` 垃圾(非换行符)，
  // 直接剥除而非转 \n —— 若转 \n 会把每行裂成「内容 + 空行」(= _collapsed_frame.as 大量空行噪声根源)。
  return txt.replace(/\r\n/g, '\n').replace(/\r/g, '');
}

var _pkgs = {};
function collectPkgs(text) {
  var m; IMPORT_RE.lastIndex = 0;
  while ((m = IMPORT_RE.exec(text)) !== null) {
    var id = m[1];
    if (/\.\*$/.test(id)) { _pkgs[id.slice(0, -2)] = true; continue; }   // 通配
    var dot = id.lastIndexOf('.');
    if (dot >= 0) _pkgs[id.slice(0, dot)] = true;                        // 有包名具体 import → 提升其包
    else throw new Error('默认包 import 无法安全提升进联合头: import ' + id);
  }
}
function stripImports(t) { return t.replace(IMPORT_RE, ''); }

// 只服务两种受控 manifest envelope，不尝试成为一般 AS2 parser。
function stripStrings(t) {
  return t.replace(/"(?:\\.|[^"\\])*"/g, '""').replace(/'(?:\\.|[^'\\])*'/g, "''");
}
function stripComments(t) {
  return t.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}
function maskNested(t) {
  var out = '', depth = 0;
  for (var i = 0; i < t.length; i++) {
    var c = t.charAt(i);
    if (c === '\n') { out += '\n'; continue; }
    if (c === '{') { out += ' '; depth++; continue; }
    if (c === '}') { if (depth > 0) depth--; out += ' '; continue; }
    out += depth === 0 ? c : ' ';
  }
  return out;
}
function topLevelCode(t) {
  return maskNested(stripComments(stripStrings(t)));
}

function validateStagedEnvelope(source, text, names) {
  var top = topLevelCode(text);
  var callNames = [], callRe = /_root\.__boot\.(f\d+(?:_\d+)?)\s*\(\s*\)\s*;/g, match;
  while ((match = callRe.exec(top)) !== null) callNames.push(match[1]);
  if (callNames.join('\n') !== names.join('\n'))
    throw new Error(source.name + ' 顶层内联调用必须与定义同数量、同顺序；defs=' +
      names.join(',') + ' calls=' + callNames.join(','));

  var residue = top.split(/\r?\n/).filter(function (line) {
    var value = line.replace(/^\s+|\s+$/g, '');
    if (!value || value === ';') return false;
    if (/^import\s+/.test(value)) return false;
    if (/^if\s*\(_root\.__boot == undefined\)\s*_root\.__boot\s*=\s*;?$/.test(value)) return false;
    if (/^_root\.__boot\.f\d+(?:_\d+)?\s*=\s*function\b/.test(value)) return false;
    if (/^_root\.__boot\.f\d+(?:_\d+)?\s*\(\s*\)\s*;$/.test(value)) return false;
    return true;
  });
  if (residue.length)
    throw new Error(source.name + ' staged envelope 含 guard/import/定义/内联调用之外的顶层语句: ' + residue[0]);
}

function validateLoaderFireEnvelope(source, text) {
  var code = stripComments(stripStrings(text));
  if (/#include\s+""/.test(code))
    throw new Error(source.name + ' loader-fire 不得包含 #include');
  var top = maskNested(code);
  var coupling = [
    { name: 'this', re: /(^|[^A-Za-z0-9_$.一-鿿])this(?![A-Za-z0-9_$一-鿿])/ },
    { name: 'timeline navigation', re: /(^|[^A-Za-z0-9_$.一-鿿])(stop|play|gotoAndStop|gotoAndPlay|nextFrame|prevFrame)\s*\(/ },
    { name: 'timeline handler', re: /(^|[^A-Za-z0-9_$.])(onEnterFrame|onUnload|onLoad)\s*=|this\.(onEnterFrame|onUnload|onLoad)\s*=/ }
  ];
  for (var i = 0; i < coupling.length; i++) {
    if (coupling[i].re.test(top))
      throw new Error(source.name + ' loader-fire 顶层含 ' + coupling[i].name + '，wrap 后会改变时间轴语义');
  }
}

function validateBootSources() {
  if (!BOOT_SOURCES.length) throw new Error('BOOT_SOURCES 不能为空');
  var names = {}, frames = {}, phases = {}, closedPhases = {}, currentPhase = null;
  for (var i = 0; i < BOOT_SOURCES.length; i++) {
    var source = BOOT_SOURCES[i];
    if (!source || !/^[a-z][a-z0-9-]*$/.test(source.name))
      throw new Error('BOOT_SOURCES[' + i + '] name 必须是稳定的 kebab-case 语义名');
    if (names[source.name]) throw new Error('BOOT_SOURCES 语义名重复: ' + source.name);
    names[source.name] = true;
    if (typeof source.frame !== 'number' || source.frame < 0 || source.frame % 1 !== 0)
      throw new Error(source.name + ' 的 frame 必须是非负整数');
    if (frames[source.frame]) throw new Error('BOOT_SOURCES frame 重复: ' + source.frame);
    frames[source.frame] = true;
    if (!/^s\d+_[A-Za-z][A-Za-z0-9]*$/.test(source.phase))
      throw new Error(source.name + ' 的 phase 非法: ' + source.phase);
    if (source.shape !== 'staged' && source.shape !== 'loader-fire')
      throw new Error(source.name + ' 的 shape 非法: ' + source.shape);
    if (VALID_PHASE_SHAPES[source.phase] !== source.shape)
      throw new Error(source.name + ' 的 phase/shape 不符合固定装配契约: ' + source.phase + '/' + source.shape);
    phases[source.phase] = true;
    if (source.phase !== currentPhase) {
      if (closedPhases[source.phase])
        throw new Error('phase 必须在 BOOT_SOURCES 中连续，不能拆成两段: ' + source.phase);
      if (currentPhase !== null) closedPhases[currentPhase] = true;
      currentPhase = source.phase;
    }
  }
  var expectedPhases = Object.keys(VALID_PHASE_SHAPES).sort();
  var actualPhases = Object.keys(phases).sort();
  if (actualPhases.join(',') !== expectedPhases.join(','))
    throw new Error('BOOT_SOURCES phase 必须 exact-match；expected=' +
      expectedPhases.join(',') + ' actual=' + actualPhases.join(','));
  var expectedFrames = BOOT_SOURCES.map(function (source) { return source.frame; }).sort(function (a, b) { return a - b; });
  var diskFrames = fs.readdirSync(MAN).map(function (file) {
    var match = /^frame(\d+)\.as$/.exec(file);
    return match ? parseInt(match[1], 10) : null;
  }).filter(function (frame) { return frame !== null; }).sort(function (a, b) { return a - b; });
  if (diskFrames.join(',') !== expectedFrames.join(','))
    throw new Error('asLoaderManifest 根目录的 frameNN.as 必须与 BOOT_SOURCES exact-match；expected=' +
      expectedFrames.join(',') + ' actual=' + diskFrames.join(','));
}

// staged manifest → 仅函数定义块（去帧首注释/import/guard/末尾内联调用）。
// 调用只按已验证 names 从文件尾 exact-remove，绝不全文删除函数体内的同形语句。
function extractStagedDefs(text, names) {
  var t = text.replace(/^(?:[ \t]*\/\/[^\n]*\r?\n)+/, '');                       // 帧首注释块
  t = stripImports(t);                                                          // import（已 collectPkgs）
  t = t.replace(/^\s*if\s*\(_root\.__boot == undefined\)[^\n]*\n/, '');           // 仅文件头 guard
  var tailCalls = names.map(function (name) {
    return '_root\\.__boot\\.' + name + '\\s*\\(\\s*\\)\\s*;';
  }).join('[ \\t]*\\n[ \\t]*');
  var tailRe = new RegExp('\\n[ \\t]*' + tailCalls + '[ \\t]*\\n?$');
  if (!tailRe.test(t))
    throw new Error('staged 文件尾调用与定义列表不一致，拒绝宽松删除: ' + names.join(','));
  t = t.replace(tailRe, '');
  return t.replace(/^\s+|\s+$/g, '');
}

// 提取帧定义的全部 _root.__boot.fN(_k) 函数名（顺序）；chunk 帧→[fN_1..fN_k]，单函数帧→[fN]
function extractDefNames(text) {
  var names = [], re = /_root\.__boot\.(f\d+(?:_\d+)?)\s*=\s*function/g, m;
  while ((m = re.exec(text)) !== null) names.push(m[1]);
  return names;
}

function extractDefSegments(text) {
  var defs = [], re = /_root\.__boot\.(f\d+(?:_\d+)?)\s*=\s*function[^{]*\{/g, match;
  while ((match = re.exec(text)) !== null)
    defs.push({ name: match[1], start: match.index, bodyStart: re.lastIndex });
  var segments = {};
  for (var i = 0; i < defs.length; i++)
    segments[defs[i].name] = text.slice(defs[i].bodyStart, i + 1 < defs.length ? defs[i + 1].start : text.length);
  return segments;
}

function extractActiveIncludes(text) {
  var code = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^[ \t]*\/\/[^\n]*$/gm, '');
  var refs = [], re = /^[ \t]*#include\s+"([^"]+)"/gm, match;
  while ((match = re.exec(code)) !== null) refs.push(match[1]);
  return refs;
}

function includeClosureBytes(ref) {
  var seen = {}, queue = [ref], total = 0;
  while (queue.length) {
    var current = queue.shift();
    var absolute = path.resolve(INCLUDE_BASE, current);
    if (seen[absolute]) continue;
    seen[absolute] = true;
    if (!fs.existsSync(absolute)) throw new Error('找不到 #include: ' + current);
    var raw = fs.readFileSync(absolute);
    if (/\.as$/i.test(absolute) && !(raw.length >= 3 && raw[0] === 0xEF && raw[1] === 0xBB && raw[2] === 0xBF))
      throw new Error(path.relative(REPO, absolute).replace(/\\/g, '/') + ' 缺少 UTF-8 BOM');
    // 源闭包度量必须与 checkout 的 autocrlf 无关：BOM 不属于 AS2 源体，
    // CRLF/LF 也不应让同一 Git blob 得到不同的调查值。
    var canonicalText = raw.slice(3).toString('utf8')
      .replace(/\r\n/g, '\n').replace(/\r/g, '\n');
    total += Buffer.byteLength(canonicalText, 'utf8');
    extractActiveIncludes(canonicalText).forEach(function (nested) { queue.push(nested); });
  }
  return total;
}

var sourceClosureMeasurements = {};
function measureStagedSourceClosures(text, names) {
  var segments = extractDefSegments(text);
  names.forEach(function (name) {
    var segment = segments[name] || '';
    var refs = extractActiveIncludes(segment);
    var bytes = Buffer.byteLength(segment, 'utf8') +
      refs.reduce(function (sum, ref) { return sum + includeClosureBytes(ref); }, 0);
    sourceClosureMeasurements[name] = bytes;
  });
}

function measureLoaderSourceClosure(text, name) {
  var bytes = Buffer.byteLength(text, 'utf8');
  sourceClosureMeasurements[name] = bytes;
}

// loader-fire manifest（裸 #include 无、直接 loader 调用）→ 包成 _root.__boot.fN（import 提升、含交错 import 如 f64）
function wrapLoaderFire(N, text) {
  var body = text.replace(/^(?:[ \t]*\/\/[^\n]*\r?\n)+/, '');
  body = stripImports(body).replace(/^\s+|\s+$/g, '');
  return '_root.__boot.f' + N + ' = function() {\n' + body.replace(/^/gm, '    ') + '\n};';
}

validateBootSources();

// 1) 只从 BOOT_SOURCES 读取 live 输入；每条记录同时产出定义与真实调用名。
var sourceRecords = [], functionOwners = {};
for (var sourceIndex = 0; sourceIndex < BOOT_SOURCES.length; sourceIndex++) {
  var source = BOOT_SOURCES[sourceIndex];
  var sourcePath = path.join(MAN, 'frame' + source.frame + '.as');
  if (!fs.existsSync(sourcePath))
    throw new Error(source.name + ' 缺少 live 输入: ' + path.relative(REPO, sourcePath).replace(/\\/g, '/'));
  var sourceText = readBom(sourcePath);
  collectPkgs(sourceText);
  var names = extractDefNames(topLevelCode(sourceText));
  var definition;
  if (source.shape === 'staged') {
    if (!names.length)
      throw new Error(source.name + ' (frame' + source.frame + ') 未提取到 staged 函数，拒绝回退调 base f' + source.frame);
    for (var nameIndex = 0; nameIndex < names.length; nameIndex++) {
      var expectedName = new RegExp('^f' + source.frame + '(?:_\\d+)?$');
      if (!expectedName.test(names[nameIndex]))
        throw new Error(source.name + ' 定义了不属于 frame' + source.frame + ' 的函数: ' + names[nameIndex]);
      if (functionOwners[names[nameIndex]])
        throw new Error('staged 函数重复: ' + names[nameIndex] + ' (' + functionOwners[names[nameIndex]] + ' / ' + source.name + ')');
      functionOwners[names[nameIndex]] = source.name;
    }
    validateStagedEnvelope(source, sourceText, names);
    measureStagedSourceClosures(sourceText, names);
    definition = extractStagedDefs(sourceText, names);
  } else {
    if (names.length)
      throw new Error(source.name + ' 标为 loader-fire，却已经定义 staged 函数: ' + names.join(', '));
    validateLoaderFireEnvelope(source, sourceText);
    names = ['f' + source.frame];
    measureLoaderSourceClosure(sourceText, names[0]);
    definition = wrapLoaderFire(source.frame, sourceText);
  }
  sourceRecords.push({ source: source, definition: definition, names: names });
}
function callLinesFor(record) {
  return record.names.map(function (name) { return '    _root.__boot.' + name + '();'; });
}

// 2) 表内 phase 首次出现顺序即 stage 生成顺序；phase 必须连续，已由 validateBootSources 守住。
var phaseOrder = [], phaseRecords = {};
sourceRecords.forEach(function (record) {
  var phase = record.source.phase;
  if (!phaseRecords[phase]) {
    phaseRecords[phase] = [];
    phaseOrder.push(phase);
  }
  phaseRecords[phase].push(record);
});
var wiring = ['// === 由 BOOT_SOURCES 派生的纯装配 stage（业务条件归 BootSequencer） ==='];
phaseOrder.forEach(function (phase) {
  wiring.push('_root.__boot.' + phase + ' = function() {');
  phaseRecords[phase].forEach(function (record) {
    wiring.push('    // ' + record.source.name + ' (frame' + record.source.frame + ')');
    Array.prototype.push.apply(wiring, callLinesFor(record));
  });
  wiring.push('};');
});
wiring = wiring.join('\n');

// 3) 定义按表顺序保留，联合头只由同一批输入收集去重。
var stagedDefs = sourceRecords.filter(function (record) {
  return record.source.shape === 'staged';
}).map(function (record) { return record.definition; });
var loaderDefs = sourceRecords.filter(function (record) {
  return record.source.shape === 'loader-fire';
}).map(function (record) { return record.definition; });
var specificPackageCount = Object.keys(SPECIFIC_IMPORT_PACKAGES).length;
var headerPackages = Object.keys(_pkgs).filter(function (p) { return !SPECIFIC_IMPORT_PACKAGES[p]; }).sort();
var header = headerPackages.map(function (p) { return 'import ' + p + '.*;'; }).join('\n');

var out = [
  '// asLoader 单帧 boot 帧 CDATA（由 tools/assemble-collapsed-frame.js 生成；asLoader.xml 单关键帧 #include 之，勿手改本文件——改组装器重生成）。',
  '// ▶ 架构导览 + 反直觉点 + 待测项：docs/asLoader-README.md（接手测试先读此文件）。',
  '// 联合头 ' + headerPackages.length + ' 包 + 具体类 ' + SPECIFIC_IMPORTS.length +
    ' | live sources ' + BOOT_SOURCES.length + ' | generated stages ' + phaseOrder.length + ' | BootSequencer.run',
  '// S0/S5/S9 业务、异步/控制行为与 f48 进度文案由 BootSequencer.as 编排。',
  // 必须先于本帧任何 `_root` 读写；这是加载作用域前置，不是 S0 业务。
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
  '// === 联合通配 import 头（' + headerPackages.length +
    ' 包；lint --fold-specific 已证把 ' + specificPackageCount +
    ' 个具体包折入后的 ' + (headerPackages.length + specificPackageCount) +
    ' 包模拟并集仍为 0 碰撞） ===',
  header,
  '// === 会话内新增类的具体 import 白名单（L42 陷阱；FQN 亦可能失败） ===',
  SPECIFIC_IMPORTS.map(function (className) { return 'import ' + className + ';'; }).join('\n'),
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

// 规范化空白以过 git whitespace 门（git diff --check）：CRLF/CR→LF + 行首缩进 tab→4 空格
//（消 space-before-tab：源自 wrapLoaderFire 对 tab 缩进的 loader 体前置 4 空格）+ 去行尾空白
//（源帧逐字复制带入 90+ 行行尾空白）。纯空白变换，AS2 忽略空白 → 不影响字节码。
out = out.replace(/\r\n/g, '\n').replace(/\r/g, '').split('\n').map(function (line) {
  line = line.replace(/[ \t]+$/, '');            // 先去行尾空白（全空白行→空行，否则缩进会被当 lead 保留）
  var lead = /^[ \t]*/.exec(line)[0];            // 再展开行首缩进 tab→4 空格（消 space-before-tab）
  return lead.replace(/\t/g, '    ') + line.slice(lead.length);
}).join('\n').replace(/\n{3,}/g, '\n\n');        // 折叠 2+ 连续空行为单空行（去残余分隔噪声）

// F10 守门：联合头之外只允许 SPECIFIC_IMPORTS 中 exact-match 的具体 import。
//   防后续组装逻辑把其它具体 import 混进产物（白名单例外悄悄扩散 = 违反 C3 单帧通配头纪律）。
var importLines = out.split('\n').filter(function (l) { return /^[ \t]*import\s+/.test(l); });
var specificImports = importLines.filter(function (l) { return !/\.\*\s*;?\s*$/.test(l.replace(/\/\/.*$/, '').replace(/[ \t]+$/, '')); });
var normalizedSpecificImports = specificImports.map(function (l) {
  return l.replace(/\/\/.*$/, '').replace(/[ \t]+/g, ' ').replace(/\s*;?\s*$/, '').replace(/^\s+/, '');
});
var expectedSpecificImports = SPECIFIC_IMPORTS.map(function (className) { return 'import ' + className; });
if (normalizedSpecificImports.join('\n') !== expectedSpecificImports.join('\n')) {
  console.error('[ASSERT FAIL] 联合头外的具体 import 必须与 SPECIFIC_IMPORTS exact-match，期望:\n  ' +
    expectedSpecificImports.join('\n  ') + '\n实得:\n  ' + normalizedSpecificImports.join('\n  '));
  process.exit(1);
}

// 产物形状门：只验证本生成器承诺的结构，不尝试解析一般 AS2。
var generatedTail = out.slice(out.indexOf('if (_root.__boot == undefined)'));
if (/^[ \t]*import\s+/m.test(generatedTail))
  throw new Error('生成的函数区仍含 import；import 必须只在联合头');
['s0_init', 's5_parseTask', 's9_onCrafting'].forEach(function (businessStage) {
  if (out.indexOf('_root.__boot.' + businessStage) >= 0)
    throw new Error('生成器不得重新拥有 BootSequencer 业务 stage: ' + businessStage);
});
phaseOrder.forEach(function (phase) {
  var phaseDefs = out.match(new RegExp('_root\\.__boot\\.' + phase + '\\s*=\\s*function', 'g')) || [];
  if (phaseDefs.length !== 1) throw new Error('生成 stage 定义次数异常: ' + phase + ' = ' + phaseDefs.length);
});
sourceRecords.forEach(function (record) {
  record.names.forEach(function (name) {
    var defs = out.match(new RegExp('_root\\.__boot\\.' + name + '\\s*=\\s*function', 'g')) || [];
    var calls = out.match(new RegExp('_root\\.__boot\\.' + name + '\\(\\);', 'g')) || [];
    if (defs.length !== 1 || calls.length !== 1)
      throw new Error(name + ' 必须恰好定义/调用一次，实得 defs=' + defs.length + ' calls=' + calls.length);
  });
});
var runCalls = out.match(/BootSequencer\.run\(this\);/g) || [];
if (runCalls.length !== 1 || out.replace(/\s+$/, '').slice(-24) !== 'BootSequencer.run(this);')
  throw new Error('BootSequencer.run(this) 必须是唯一且最后的启动动作');

var outputBytes = Buffer.concat([BOM, Buffer.from(out, 'utf8')]);
var relativeOut = path.relative(REPO, OUT).replace(/\\/g, '/');
var stagedCount = sourceRecords.filter(function (record) { return record.source.shape === 'staged'; }).length;
var loaderCount = sourceRecords.length - stagedCount;
if (CHECK_ONLY) {
  if (!fs.existsSync(OUT) || !fs.readFileSync(OUT).equals(outputBytes)) {
    console.error('[CHECK FAIL] ' + relativeOut + ' 与 BOOT_SOURCES/生成规则不一致；请运行 node tools/assemble-collapsed-frame.js');
    process.exit(1);
  }
  console.log('[OK] ' + relativeOut + ' 可由唯一 BOOT_SOURCES 字节级重建');
} else {
  fs.writeFileSync(OUT, outputBytes);
  console.log('[DONE] 写出 ' + relativeOut);
}
console.log('  联合头 ' + headerPackages.length + ' 包 + 具体类 ' + SPECIFIC_IMPORTS.length +
  ' | live ' + sourceRecords.length + ' (staged ' + stagedCount + ' + loader-fire ' + loaderCount +
  ') | stages ' + phaseOrder.length);
var measuredNames = Object.keys(sourceClosureMeasurements).sort(function (a, b) {
  return sourceClosureMeasurements[b] - sourceClosureMeasurements[a];
});
var reviewNames = measuredNames.filter(function (name) {
  return sourceClosureMeasurements[name] >= SOURCE_REVIEW_THRESHOLD;
});
console.log('  源闭包度量仅供调查（非 hard gate），最大项 ' + measuredNames[0] + '=' +
  sourceClosureMeasurements[measuredNames[0]] + 'B；>=' + SOURCE_REVIEW_THRESHOLD + 'B: ' +
  (reviewNames.length ? reviewNames.map(function (name) {
    return name + '=' + sourceClosureMeasurements[name] + 'B';
  }).join(', ') : '无'));
