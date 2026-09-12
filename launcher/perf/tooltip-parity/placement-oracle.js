// placement-oracle.js — Web→Native 定位回归契约的活体 Web 预言机。
//
// 不复制求解器：从生产 launcher/web/modules/tooltip.js 源码中机械抽取
// positionFloating 及其全部依赖函数（clamp/overlapArea/rectAt/anchorRectOf/
// normalizePlacement/placementCandidate/placementFeasible/candidateScore/
// resetPlacementState）与常量（POINTER_EXCLUSION/ANCHOR_GAP/VIEWPORT_INSET/
// PLACEMENT_EPS），在 Node 中以伪 tooltip 元素（getBoundingClientRect /
// querySelector / style / setAttribute）+ 伪 window 原样执行。
// 抽取失败（函数被改名/删除）即非零退出，不放绿。
//
// 输出：stdout 单条 JSON —— 用例输入 + Web 侧期望结果（CSS px 视口域）。
// 消费方：launcher/tests/Guardian/Tooltip/NativeTooltipPlacementContractTests.cs，
// 由它把 CSS 域输入 ×dpi + 视口物理原点换算后回放 NativeTooltipLayout.SolvePlacement。
//
// 运行：node launcher/perf/tooltip-parity/placement-oracle.js
'use strict';

var fs = require('fs');
var path = require('path');
var crypto = require('crypto');

var SOURCE_REL = path.join('launcher', 'web', 'modules', 'tooltip.js');
var sourcePath = path.resolve(__dirname, '..', '..', 'web', 'modules', 'tooltip.js');
var source = fs.readFileSync(sourcePath, 'utf8');
var sourceSha256 = crypto.createHash('sha256').update(source).digest('hex');

// ── 源码抽取 ──────────────────────────────────────────────────────────────
// 词法感知的花括号配对：跳过 '//' 行注释、'/* */' 块注释与 '...'/"..."/`...`
// 字符串，避免函数体内字符串/注释中的花括号截断配对。

function extractFunctionSource(src, name) {
    var needle = 'function ' + name + '(';
    var start = src.indexOf(needle);
    if (start < 0) throw new Error('tooltip.js 缺少函数 ' + name + '（契约抽取失败）');
    var braceStart = src.indexOf('{', start);
    if (braceStart < 0) throw new Error('tooltip.js 函数 ' + name + ' 无函数体');
    var depth = 0, inStr = null, inLine = false, inBlock = false;
    for (var i = braceStart; i < src.length; i++) {
        var c = src[i], n = src[i + 1];
        if (inLine) { if (c === '\n') inLine = false; continue; }
        if (inBlock) { if (c === '*' && n === '/') { inBlock = false; i++; } continue; }
        if (inStr) {
            if (c === '\\') { i++; continue; }
            if (c === inStr) inStr = null;
            continue;
        }
        if (c === '/' && n === '/') { inLine = true; continue; }
        if (c === '/' && n === '*') { inBlock = true; continue; }
        if (c === "'" || c === '"' || c === '`') { inStr = c; continue; }
        if (c === '{') depth++;
        else if (c === '}') {
            depth--;
            if (depth === 0) return src.slice(start, i + 1);
        }
    }
    throw new Error('tooltip.js 函数 ' + name + ' 花括号未闭合');
}

function extractConstSource(src, name) {
    var re = new RegExp('var\\s+' + name + '\\s*=\\s*([^;]+);');
    var m = re.exec(src);
    if (!m) throw new Error('tooltip.js 缺少常量 ' + name + '（契约抽取失败）');
    return 'var ' + name + ' = ' + m[1] + ';';
}

var CONST_NAMES = ['POINTER_EXCLUSION', 'ANCHOR_GAP', 'VIEWPORT_INSET', 'PLACEMENT_EPS'];
var FN_NAMES = [
    'clamp', 'overlapArea', 'rectAt', 'anchorRectOf', 'normalizePlacement',
    'placementCandidate', 'placementFeasible', 'candidateScore',
    'resetPlacementState', 'positionFloating'
];

var constSources = CONST_NAMES.map(function (n) { return extractConstSource(source, n); });
var fnSources = FN_NAMES.map(function (n) { return extractFunctionSource(source, n); });

// ── 沙箱装配 ──────────────────────────────────────────────────────────────
// 仅声明 positionFloating 读写到的模块级状态槽位；规则代码 100% 来自上方抽取。

var harnessBody = '"use strict";\n'
    + 'var _el = null, _placementHint = null, _lockedPlacement = null, _lastPlacement = null;\n'
    + constSources.join('\n') + '\n'
    + fnSources.join('\n') + '\n'
    + 'return {\n'
    + '  reset: function (hint) { resetPlacementState(hint); },\n'
    + '  forceLocked: function (s) { _lockedPlacement = s; },\n'
    + '  locked: function () { return _lockedPlacement; },\n'
    + '  setEl: function (e) { _el = e; },\n'
    + '  position: function (pointer, anchor, anchored) { positionFloating(pointer, anchor, anchored); },\n'
    + '  last: function () { return _lastPlacement; }\n'
    + '};';

var createModule = new Function('window', harnessBody);

function makeFakeElement() {
    return {
        rect: { left: 0, top: 0, right: 1, bottom: 1, width: 1, height: 1 },
        style: {},
        attrs: {},
        getBoundingClientRect: function () { return this.rect; },
        querySelector: function () { return null; },   // 无 .flash-tt-rich → 跳过 stacked 分支
        setAttribute: function (k, v) { this.attrs[k] = String(v); },
        classList: { add: function () { }, remove: function () { } }
    };
}

function pointAnchorEl(x, y) {
    // 退化元素锚：left==right、top==bottom 的零面积 getBoundingClientRect，
    // 与 anchorRectOf 的鼠标点回退形状一致，但走元素分支（anchored 用）。
    return {
        isConnected: true,
        getBoundingClientRect: function () {
            return { left: x, right: x, top: y, bottom: y, width: 0, height: 0 };
        }
    };
}

function elementAnchorEl(r) {
    // 真实元素锚：非零面积 getBoundingClientRect，走 anchorRectOf 元素分支；
    // 候选几何由矩形边缘决定，指针只参与碰撞评分。
    return {
        isConnected: true,
        getBoundingClientRect: function () {
            return {
                left: r.x, top: r.y, right: r.x + r.w, bottom: r.y + r.h,
                width: r.w, height: r.h
            };
        }
    };
}

// ── 用例（全部整数 CSS 坐标，×1.25/×1.5 仍为整数，规避浮点同分翻转）──────
//
// 每步两种锚形态：
//   { ax, ay }                    — 点锚（anchor=null，anchorRectOf 鼠标点回退，
//                                   pointer=锚点本身）；
//   { anchor:{x,y,w,h}, pointer:{x,y} } — 真实元素锚 rect（anchorRectOf 元素分支，
//                                   候选由矩形边缘决定）+ 独立指针点（只参与评分）；
//   anchored=true 用例省略 pointer —— web 端 pointer=null → 指针退化为锚 rect
//   中心点（positionFloating 内建 fallback），radius=0。
// tw/th = tooltip getBoundingClientRect 尺寸（post-transform CSS px）。
// locked = 用例首轮 _lockedPlacement（建模 native _lockedSide 初值）；
// hint = show* 入参 placement → resetPlacementState(hint) 真实入口设置
// _placementHint（锁定失效后、全量打分前的区域定侧偏好）。
// steps 之间属同一次 show：次轮起锁定侧 = 前轮实际落侧（web _lockedPlacement
// 语义），输出逐步带 lockedBefore 供 C# 端逐步回放。

var BASE_CASES = [
    { id: 'center-free', vw: 1024, vh: 576, steps: [{ ax: 512, ay: 288, tw: 200, th: 100 }] },
    { id: 'corner-tl', vw: 1024, vh: 576, steps: [{ ax: 20, ay: 20, tw: 220, th: 160 }] },
    { id: 'corner-tr', vw: 1024, vh: 576, steps: [{ ax: 1004, ay: 20, tw: 220, th: 160 }] },
    { id: 'corner-bl', vw: 1024, vh: 576, steps: [{ ax: 20, ay: 556, tw: 220, th: 160 }] },
    { id: 'corner-br', vw: 1024, vh: 576, steps: [{ ax: 1004, ay: 556, tw: 220, th: 160 }] },
    { id: 'edge-left', vw: 1024, vh: 576, steps: [{ ax: 12, ay: 288, tw: 200, th: 100 }] },
    { id: 'edge-right', vw: 1024, vh: 576, steps: [{ ax: 1012, ay: 288, tw: 200, th: 100 }] },
    // 宽 tip（> (vw-36)/2）封死左右两侧 → top/bottom 才有机会胜出。
    { id: 'edge-top-wide', vw: 800, vh: 600, steps: [{ ax: 400, ay: 20, tw: 400, th: 160 }] },
    { id: 'edge-bottom-wide', vw: 800, vh: 600, steps: [{ ax: 400, ay: 580, tw: 400, th: 160 }] },
    // 锁定侧仍可行 → 原侧直接沿用，不做打分（证明锁覆盖评分）。
    { id: 'locked-feasible', vw: 1024, vh: 576, locked: 'bottom',
        steps: [{ ax: 512, ay: 288, tw: 200, th: 100 }] },
    // 锁定侧主轴放不下 → 解锁全量重打分。
    { id: 'locked-unfeasible', vw: 1024, vh: 576, locked: 'left',
        steps: [{ ax: 80, ay: 288, tw: 220, th: 160 }] },
    // anchored=true：指针互斥半径归零；退化点锚走 anchorRectOf 元素分支。
    { id: 'anchored-point', vw: 1024, vh: 576, anchored: true,
        steps: [{ ax: 300, ay: 200, tw: 200, th: 100 }] },
    // 密集图标走位：同一次 show 内指针横向扫过；覆盖 锁保持→解锁→重锁，
    // 中途含 basic→rich 尺寸增长（tw/th 逐步变化）。
    { id: 'icon-walk', vw: 800, vh: 600, steps: [
        { ax: 300, ay: 300, tw: 220, th: 160 },
        { ax: 560, ay: 300, tw: 220, th: 160 },
        { ax: 200, ay: 300, tw: 260, th: 200 },
        { ax: 560, ay: 300, tw: 260, th: 200 },
        { ax: 80, ay: 560, tw: 260, th: 200 }
    ] },

    // ── 真实元素锚 rect + 独立指针（native 新重载 anchorRect+pointer+hint）──

    // 非零面积元素锚：候选贴矩形边缘，指针在元素内部但不改变锚几何。
    { id: 'rect-anchor-basic', vw: 1024, vh: 576, steps: [
        { anchor: { x: 400, y: 200, w: 120, h: 60 }, pointer: { x: 428, y: 216 }, tw: 200, th: 100 }
    ] },
    // 指针明显在元素外（右下方）：pointerRect 与 anchorRect 分离，
    // 只有指针参与碰撞评分、锚仍决定候选位置。
    { id: 'pointer-ne-anchor', vw: 1024, vh: 576, steps: [
        { anchor: { x: 300, y: 200, w: 80, h: 40 }, pointer: { x: 380, y: 300 }, tw: 200, th: 100 }
    ] },
    // 稳定格悬停走位：同一格锚 rect 固定，指针在格内巡游——侧不得逐像素翻
    // （"忽左忽右"回归：锁定侧可行即原位保留，不重新打分）。
    { id: 'cell-hover-walk', vw: 1024, vh: 576, steps: [
        { anchor: { x: 600, y: 200, w: 48, h: 48 }, pointer: { x: 608, y: 208 }, tw: 220, th: 160 },
        { anchor: { x: 600, y: 200, w: 48, h: 48 }, pointer: { x: 640, y: 208 }, tw: 220, th: 160 },
        { anchor: { x: 600, y: 200, w: 48, h: 48 }, pointer: { x: 640, y: 240 }, tw: 220, th: 160 },
        { anchor: { x: 600, y: 200, w: 48, h: 48 }, pointer: { x: 608, y: 240 }, tw: 220, th: 160 },
        { anchor: { x: 600, y: 200, w: 48, h: 48 }, pointer: { x: 624, y: 224 }, tw: 220, th: 160 }
    ] },
    // hint 可行 → 直接采用偏好侧，绕过全量打分（打分本会选 left）。
    { id: 'hint-feasible', vw: 1024, vh: 576, hint: 'bottom', steps: [
        { anchor: { x: 400, y: 200, w: 120, h: 60 }, pointer: { x: 428, y: 216 }, tw: 200, th: 100 }
    ] },
    // hint='right' 但锚贴右缘 → 偏好侧放不下 → 失效回退全量打分；
    // right 被夹回后还会与锚 rect 交叠（anchorOverlap 非零分支）。
    { id: 'hint-invalidated', vw: 1024, vh: 576, hint: 'right', steps: [
        { anchor: { x: 920, y: 200, w: 80, h: 40 }, pointer: { x: 940, y: 212 }, tw: 200, th: 100 }
    ] },
    // 锁 > hint：第 1 步 hint='right' 不可行 → 打分落 left 并上锁；
    // 第 2 步挪到左右都放得下的锚——locked left 先于 hint 检查 → 仍 left。
    // 全程只用真实 web 机制（_lockedPlacement 由上轮回写，_placementHint 由
    // resetPlacementState 设），不伪造内部状态。
    { id: 'lock-beats-hint', vw: 1024, vh: 576, hint: 'right', steps: [
        { anchor: { x: 920, y: 200, w: 80, h: 40 }, pointer: { x: 940, y: 212 }, tw: 200, th: 100 },
        { anchor: { x: 400, y: 200, w: 120, h: 60 }, pointer: { x: 428, y: 216 }, tw: 200, th: 100 }
    ] },
    // 同锚不同内容尺寸的边缘翻转：小 tip 时 left 胜出并上锁；tip 增大后
    // left 主轴放不下 → 解锁重打分落 right；tip 缩回后锁仍粘 right
    // （锁不自动回弹——真实 web 语义）。
    { id: 'edge-flip-resize', vw: 800, vh: 600, steps: [
        { anchor: { x: 200, y: 300, w: 48, h: 48 }, pointer: { x: 224, y: 324 }, tw: 160, th: 120 },
        { anchor: { x: 200, y: 300, w: 48, h: 48 }, pointer: { x: 224, y: 324 }, tw: 260, th: 200 },
        { anchor: { x: 200, y: 300, w: 48, h: 48 }, pointer: { x: 224, y: 324 }, tw: 160, th: 120 }
    ] },
    // anchored + 真实元素锚 rect：pointer=null → 中心点 fallback + radius=0。
    { id: 'anchored-rect', vw: 1024, vh: 576, anchored: true, steps: [
        { anchor: { x: 300, y: 100, w: 200, h: 80 }, tw: 200, th: 100 }
    ] }
];

// dpr → 物理视口原点（非零原点覆盖多屏/偏移宿主）。dpr=1 用零原点基线。
var DPRS = [1, 1.25, 1.5];
var ORIGINS = { '1': [0, 0], '1.25': [1920, 64], '1.5': [1366, 120] };

function runBaseCase(base, dpr) {
    var api = createModule({ innerWidth: base.vw, innerHeight: base.vh });
    api.reset(base.hint || null);            // show* 等价：placement hint + 锁清空
    if (base.locked) api.forceLocked(base.locked);
    var el = makeFakeElement();
    api.setEl(el);
    var origin = ORIGINS[String(dpr)];

    var steps = base.steps.map(function (s) {
        el.rect = { left: 0, top: 0, right: s.tw, bottom: s.th, width: s.tw, height: s.th };
        var anchor, pointer, anchorRectOut = null, pointerX = null, pointerY = null;
        if (s.anchor) {
            anchor = elementAnchorEl(s.anchor);                  // 真实元素锚 rect
            anchorRectOut = { x: s.anchor.x, y: s.anchor.y, w: s.anchor.w, h: s.anchor.h };
            if (!base.anchored) { pointerX = s.pointer.x; pointerY = s.pointer.y; }
        } else if (base.anchored) {
            anchor = pointAnchorEl(s.ax, s.ay);                  // 退化元素锚
            anchorRectOut = { x: s.ax, y: s.ay, w: 0, h: 0 };
        } else {
            anchor = null;                                       // 鼠标点锚回退
            pointerX = s.ax; pointerY = s.ay;
        }
        // anchored：web 传 pointer=null → positionFloating 内建锚中心 fallback；
        // 指针坐标输出 null，由 C# 端按同一规则回放（rect 中心）。
        pointer = (pointerX === null) ? null
            : { clientX: pointerX, clientY: pointerY };
        var lockedBefore = api.locked();
        api.position(pointer, anchor, !!base.anchored);
        var last = api.last();
        if (!last || el.attrs['data-placement'] !== last.placement) {
            throw new Error('positionFloating 未写回 data-placement：' + base.id);
        }
        var x = parseFloat(el.style.left), y = parseFloat(el.style.top);
        if (!isFinite(x) || !isFinite(y)) {
            throw new Error('positionFloating 未写 style.left/top：' + base.id);
        }
        return {
            input: {
                anchorRect: anchorRectOut,
                pointerX: pointerX, pointerY: pointerY,
                tipW: s.tw, tipH: s.th,
                lockedBefore: lockedBefore
            },
            expected: {
                side: last.placement,
                x: x, y: y, w: s.tw, h: s.th,
                pointerOverlap: last.pointerOverlap,
                anchorOverlap: last.anchorOverlap,
                insideViewport: last.insideViewport,
                lockedAfter: api.locked()
            }
        };
    });

    return {
        id: base.id + '@dpr' + dpr,
        baseId: base.id,
        dpr: dpr,
        viewportCss: { w: base.vw, h: base.vh },
        viewportOriginPhys: { x: origin[0], y: origin[1] },
        anchored: !!base.anchored,
        hint: base.hint || null,
        steps: steps
    };
}

var cases = [];
BASE_CASES.forEach(function (base) {
    DPRS.forEach(function (dpr) { cases.push(runBaseCase(base, dpr)); });
});

var sidesSeen = {};
cases.forEach(function (c) {
    c.steps.forEach(function (s) { sidesSeen[s.expected.side] = true; });
});
['left', 'right', 'top', 'bottom'].forEach(function (side) {
    if (!sidesSeen[side]) throw new Error('用例集未覆盖胜出侧 ' + side);
});

process.stdout.write(JSON.stringify({
    oracle: 'placement-oracle.v1',
    source: SOURCE_REL.split(path.sep).join('/'),
    sourceSha256: sourceSha256,
    extracted: { consts: CONST_NAMES, functions: FN_NAMES },
    domain: 'expected 为视口 CSS px 域（innerWidth/innerHeight 坐标系）；'
        + 'C# 端物理期望 = origin + expected × dpr',
    caseCount: cases.length,
    cases: cases
}, null, 1) + '\n');
