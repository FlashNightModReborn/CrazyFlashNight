#!/usr/bin/env node
'use strict';

/**
 * tooltip-parity 比较器。
 * 对 out/cases/<cid>/ 下 web.{png,json} + native.{png,json} 做几何/文本/滚动/像素对比，
 * 产出 side-by-side.png / overlay.png / diff.png / compare.json，并汇总 summary.json。
 *
 * 判定：
 *  硬失败（fail）——缺内容、溢出、placement 不符、滚动不可达、
 *    tooltip 尺寸偏差 > max(sizeTolPx=24, sizeTolFrac=0.15·web)、
 *    位置偏差 > posTolHardPx=96、任一端渲染缺失/全空。
 *  软告警（warn）——边缘位置漂移 > posTolWarnPx=8、行数差 ≥3、
 *    并集区域像素差异率 > 40%（文字 AA/行高差异噪声大，单列观察不判死）。
 * 阈值可用 --thresholds <json> 覆盖；不允许把正文整区 mask 成全忽略。
 */

const fs = require('fs');
const path = require('path');
const png = require('./lib/png.js');

const DEFAULT_THRESHOLDS = {
    posTolWarnPx: 8,        // 矩形边位置漂移告警
    posTolHardPx: 96,       // 矩形边位置漂移硬失败
    sizeTolPx: 24,          // tooltip 宽/高绝对容差
    sizeTolFrac: 0.15,      // tooltip 宽/高相对（web 侧）容差
    panelSizeTolPx: 32,     // 子面板宽/高容差（intro/desc/icon）
    panelSizeTolFrac: 0.25,
    lineCountWarn: 3,       // 文本视觉行数差告警（同口径：web Range 行框 vs native VisualLine）
    pixelDiffWarnRatio: 0.40,
    meanAbsDiffWarn: 24,
    bgSampleTol: 10         // 判定"图标/面板区域非背景"的通道容差
};

// 预设：loose=差异测绘期（宽松，暴露所有信号，不代表一致性）；
//       acceptance=验收口径（~3px/1% 测量舍入范围，定位 warn2/hard8）。
// 通过 loose ≠ 一致；一致性结论只能用 acceptance 读数。
const PRESETS = {
    loose: DEFAULT_THRESHOLDS,
    acceptance: Object.assign({}, DEFAULT_THRESHOLDS, {
        posTolWarnPx: 2, posTolHardPx: 8,
        sizeTolPx: 3, sizeTolFrac: 0.01,
        panelSizeTolPx: 3, panelSizeTolFrac: 0.01,
        lineCountWarn: 1
    })
};
const CANVAS_BG = [24, 26, 28];

function fail(msg, evidence) { const e = new Error(msg); e.evidence = evidence; throw e; }

// ---------- 基础几何 ----------
function normRect(r) {
    if (!r) return null;
    return { left: +r.left, top: +r.top, right: +r.right, bottom: +r.bottom,
        width: +r.width, height: +r.height };
}
function rectDelta(a, b) {
    if (!a && !b) return null;
    if (!a || !b) return { missing: !a ? 'web' : 'native' };
    return {
        dLeft: b.left - a.left, dTop: b.top - a.top,
        dRight: b.right - a.right, dBottom: b.bottom - a.bottom,
        dWidth: b.width - a.width, dHeight: b.height - a.height
    };
}
function sizeExceeds(delta, refW, refH, tolPx, tolFrac) {
    if (!delta) return false;
    if (delta.missing) return true;
    const wLim = Math.max(tolPx, Math.abs(refW) * tolFrac);
    const hLim = Math.max(tolPx, Math.abs(refH) * tolFrac);
    return Math.abs(delta.dWidth) > wLim || Math.abs(delta.dHeight) > hLim;
}
function edgeExceeds(delta, px) {
    if (!delta || delta.missing) return false;
    return Math.abs(delta.dLeft) > px || Math.abs(delta.dTop) > px
        || Math.abs(delta.dRight) > px || Math.abs(delta.dBottom) > px;
}
// 视口闭包：任一边超出即算越界（含部分裁剪，±0.5px 量化容差）。
function outsideViewport(r, vp) {
    if (!r) return true;
    return r.left < -0.5 || r.top < -0.5 || r.right > vp.w + 0.5 || r.bottom > vp.h + 0.5
        || r.width <= 0 || r.height <= 0;
}

// ---------- 文本 ----------
function normLine(s) { return String(s || '').replace(/\s+/g, ' ').trim(); }
function normLines(arr) { return Array.isArray(arr) ? arr.map(normLine).filter(Boolean) : null; }
// 去全部空白后的拼接——折行/空格差异不影响缺内容判定（root 要求：
// 缺内容判定不得依赖逐行包裹匹配）。
function squashJoin(arr) { return arr.map(s => String(s || '').replace(/\s+/g, '')).join(''); }
// 视觉行对比（同口径：web Range 行框聚合 vs native VisualLine）。
// 任一侧为 null = 采集不可信（unknown）→ 只标记，不算行数差、不判缺内容。
// 缺内容 = web 某视觉行 squash 后在 native 全文拼接中找不到（与折行无关）。
function textCompare(web, nat) {
    const wI = normLines(web && web.intro), nI = normLines(nat && nat.intro);
    const wD = normLines(web && web.desc), nD = normLines(nat && nat.desc);
    // desc 通道仅当 web 声明存在该面板（'ok'/'unknown'）或 native 实际有行才适用；
    // merge 布局 web descStatus='absent' 且 native 无 desc 行 → 不适用，不算 unknown。
    const descApplicable = (web && web.descStatus !== 'absent') || (nD && nD.length > 0);
    const natIntroAll = nI ? squashJoin(nI) : null;
    const natDescAll = nD ? squashJoin(nD) : null;
    const missingIn = (lines, natAll) => (lines && natAll !== null)
        ? lines.filter(t => t.replace(/\s+/g, '').length > 0 && !natAll.includes(t.replace(/\s+/g, '')))
        : [];
    return {
        introLines: (wI && nI) ? { web: wI.length, native: nI.length, delta: nI.length - wI.length } : null,
        descLines: (descApplicable && wD && nD) ? { web: wD.length, native: nD.length, delta: nD.length - wD.length } : null,
        introUnknown: wI === null || nI === null,
        descUnknown: descApplicable && (wD === null || nD === null),
        descAbsent: !descApplicable,
        introMissing: missingIn(wI, natIntroAll),
        descMissing: descApplicable ? missingIn(wD, natDescAll) : [],
        titleWeb: web && web.title || null,
        titleNative: nat && nat.title || null
    };
}

// ---------- 像素 ----------
function isBlankImage(img) {
    // 全画布 ≈ 背景色 → 判定未绘制
    const d = img.data;
    let diff = 0;
    for (let i = 0; i < d.length; i += 4) {
        if (Math.abs(d[i] - CANVAS_BG[0]) > 6 || Math.abs(d[i + 1] - CANVAS_BG[1]) > 6
            || Math.abs(d[i + 2] - CANVAS_BG[2]) > 6) diff++;
        if (diff > 40) return false; // 提前判出
    }
    return true;
}

function regionStats(web, nat, rect) {
    const w = web.width, h = web.height;
    const x0 = Math.max(0, Math.floor(rect.left)), y0 = Math.max(0, Math.floor(rect.top));
    const x1 = Math.min(w, Math.ceil(rect.right)), y1 = Math.min(h, Math.ceil(rect.bottom));
    if (x1 <= x0 || y1 <= y0) return { pixels: 0, diffPixels: 0, meanAbs: 0 };
    let diff = 0, sum = 0, n = 0;
    for (let y = y0; y < y1; y++) {
        for (let x = x0; x < x1; x++) {
            const i = (y * w + x) * 4;
            const dd = Math.max(
                Math.abs(web.data[i] - nat.data[i]),
                Math.abs(web.data[i + 1] - nat.data[i + 1]),
                Math.abs(web.data[i + 2] - nat.data[i + 2]));
            sum += dd; n++;
            if (dd > 16) diff++;
        }
    }
    return { pixels: n, diffPixels: diff, diffRatio: n ? diff / n : 0, meanAbs: n ? sum / n : 0 };
}

function unionRect(a, b) {
    if (!a) return b; if (!b) return a;
    const l = Math.min(a.left, b.left), t = Math.min(a.top, b.top);
    return { left: l, top: t, right: Math.max(a.right, b.right), bottom: Math.max(a.bottom, b.bottom),
        width: Math.max(a.right, b.right) - l, height: Math.max(a.bottom, b.bottom) - t };
}

function sideBySide(web, nat, gap) {
    gap = gap || 8;
    const w = web.width + nat.width + gap, h = Math.max(web.height, nat.height);
    const out = Buffer.alloc(w * h * 4);
    for (let i = 0; i < out.length; i += 4) { out[i] = 10; out[i + 1] = 11; out[i + 2] = 12; out[i + 3] = 255; }
    // 逐行拷贝（源/目标 stride 不同）
    const blitRow = (img, ox) => {
        for (let y = 0; y < img.height; y++) {
            const s = y * img.width * 4, d = (y * w + ox) * 4;
            img.data.copy(out, d, s, s + img.width * 4);
        }
    };
    blitRow(web, 0); blitRow(nat, web.width + gap);
    return { width: w, height: h, data: out };
}

function overlay(web, nat) {
    const w = Math.min(web.width, nat.width), h = Math.min(web.height, nat.height);
    const out = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        for (let c = 0; c < 3; c++)
            out[i + c] = (web.data[i + c] + nat.data[i + c]) >> 1;
        out[i + 3] = 255;
    }
    return { width: w, height: h, data: out };
}

function diffImage(web, nat) {
    const w = Math.min(web.width, nat.width), h = Math.min(web.height, nat.height);
    const out = Buffer.alloc(w * h * 4);
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const i = (y * w + x) * 4;
        const d = Math.max(
            Math.abs(web.data[i] - nat.data[i]),
            Math.abs(web.data[i + 1] - nat.data[i + 1]),
            Math.abs(web.data[i + 2] - nat.data[i + 2]));
        // 0→黑，>64→亮红，中间灰→橙渐变，便于肉眼定位差异带
        if (d <= 8) { out[i] = out[i + 1] = out[i + 2] = d * 4; }
        else if (d <= 64) { out[i] = 128 + d; out[i + 1] = d * 2; out[i + 2] = 0; }
        else { out[i] = 255; out[i + 1] = Math.max(0, 96 - d); out[i + 2] = 32; }
        out[i + 3] = 255;
    }
    return { width: w, height: h, data: out };
}

// ---------- 单 case 对比 ----------
function compareCase(caseDir, thresholds, presetName) {
    const t = Object.assign({}, PRESETS[presetName] || DEFAULT_THRESHOLDS, thresholds || {});
    const cid = path.basename(caseDir);
    const hard = [], warn = [];
    const read = f => { try { return JSON.parse(fs.readFileSync(path.join(caseDir, f), 'utf8')); } catch (e) { return null; } };
    const webJ = read('web.json'), natJ = read('native.json');
    const metrics = { caseId: cid };

    if (!webJ) hard.push('webJsonMissing');
    if (!natJ) hard.push('nativeJsonMissing');
    if (natJ && natJ.error) hard.push('nativeError:' + String(natJ.error).split('\n')[0].slice(0, 120));

    const wg = webJ && webJ.geometry, ng = natJ && natJ.geometry;
    const vp = (webJ && webJ.viewport) || (natJ && natJ.viewport) || { w: 1024, h: 576 };

    if (wg && ng) {
        if (!!wg.shown !== !!ng.shown) hard.push('shownMismatch:web=' + wg.shown + ',native=' + ng.shown);
        const wr = normRect(wg.tooltipRect), nr = normRect(ng.tooltipRect);
        metrics.tooltip = rectDelta(wr, nr);
        if (wg.placement && ng.placement && wg.placement !== ng.placement) {
            // 候选方向在视口夹取后可落到相同矩形。现役CSS不消费方向标签，
            // 也没有方向箭头；保留诊断，但不把相同绘制位置误报为硬失败。
            const samePaint = wr && nr && !edgeExceeds(metrics.tooltip, t.posTolHardPx)
                && !sizeExceeds(metrics.tooltip, wr.width, wr.height, t.sizeTolPx, t.sizeTolFrac);
            (samePaint ? warn : hard).push((samePaint ? 'placementLabelDrift:' : 'placementMismatch:')
                + wg.placement + '!=' + ng.placement);
        }
        if (wg.shown && outsideViewport(wr, vp)) hard.push('webOverflow:' + JSON.stringify(wr));
        if (ng.shown && outsideViewport(nr, vp)) hard.push('nativeOverflow:' + JSON.stringify(nr));
        if (wr && nr) {
            if (sizeExceeds(metrics.tooltip, wr.width, wr.height, t.sizeTolPx, t.sizeTolFrac))
                hard.push('sizeDeviation:d=' + metrics.tooltip.dWidth.toFixed(1) + 'x' + metrics.tooltip.dHeight.toFixed(1));
            if (edgeExceeds(metrics.tooltip, t.posTolHardPx)) hard.push('positionDeviation');
            else if (edgeExceeds(metrics.tooltip, t.posTolWarnPx)) warn.push('positionDrift');
        }
        for (const name of ['introPanelRect', 'descPanelRect', 'iconRect']) {
            const wrect = normRect(wg[name]);
            const nrect = normRect(ng[name]);
            const d = rectDelta(wrect, nrect);
            metrics[name] = d;
            if (d && !d.missing && sizeExceeds(d, wrect.width, wrect.height, t.panelSizeTolPx, t.panelSizeTolFrac))
                warn.push('panelSizeDrift:' + name);
            // 面板级越界同样是硬失败（部分裁剪也算）
            if (wg.shown && wrect && outsideViewport(wrect, vp)) hard.push('webPanelOverflow:' + name);
            if (ng.shown && nrect && outsideViewport(nrect, vp)) hard.push('nativePanelOverflow:' + name);
        }

        metrics.text = textCompare(wg.text, ng.text);
        const tx = metrics.text;
        // 硬门：仅当两侧都可信采集。unknown 标 warn 不放绿。
        if (!tx.introUnknown && tx.introLines.web > 0 && tx.introLines.native === 0)
            hard.push('contentMissing:nativeIntroEmpty');
        if (!tx.descUnknown && tx.descLines && tx.descLines.web > 0 && tx.descLines.native === 0 && (wg.layout && wg.layout.split))
            hard.push('contentMissing:nativeDescEmpty');
        if (tx.introUnknown) warn.push('textUnknown:intro');
        if (tx.descUnknown) warn.push('textUnknown:desc');
        if (tx.introMissing.length + tx.descMissing.length > 0)
            hard.push('textLineDiff:' + (tx.introMissing.length + tx.descMissing.length));
        if ((tx.descLines && Math.abs(tx.descLines.delta) >= t.lineCountWarn)
            || (tx.introLines && Math.abs(tx.introLines.delta) >= t.lineCountWarn))
            warn.push('lineCountDrift:intro=' + (tx.introLines ? tx.introLines.delta : '?')
                + ',desc=' + (tx.descLines ? tx.descLines.delta : '?'));

        const ws = wg.scroll || {}, ns = ng.scroll || {};
        metrics.scroll = { web: ws, native: ns };
        if (ws.scrollable != null && ns.scrollable != null && !!ws.scrollable !== !!ns.scrollable)
            hard.push('scrollMismatch:web=' + ws.scrollable + ',native=' + ns.scrollable);
        if (ws.reachBottom === false || ns.reachBottom === false) hard.push('scrollUnreachable');
    }

    // ---- 像素 ----
    const webPng = path.join(caseDir, 'web.png'), natPng = path.join(caseDir, 'native.png');
    let webImg = null, natImg = null;
    if (fs.existsSync(webPng)) { try { webImg = png.decode(fs.readFileSync(webPng)); } catch (e) { hard.push('webPngUndecodable:' + e.message); } }
    else hard.push('webPngMissing');
    if (fs.existsSync(natPng)) { try { natImg = png.decode(fs.readFileSync(natPng)); } catch (e) { hard.push('nativePngUndecodable:' + e.message); } }
    else hard.push('nativePngMissing');

    if (webImg && natImg) {
        metrics.image = { web: { w: webImg.width, h: webImg.height }, native: { w: natImg.width, h: natImg.height } };
        if (wg && wg.shown && isBlankImage(webImg)) hard.push('webBlankRender');
        if (ng && ng.shown && isBlankImage(natImg)) hard.push('nativeBlankRender');
        if (webImg.width !== natImg.width || webImg.height !== natImg.height)
            warn.push('canvasSizeMismatch:' + webImg.width + 'x' + webImg.height + '!=' + natImg.width + 'x' + natImg.height);

        const union = unionRect(normRect(wg && wg.tooltipRect), normRect(ng && ng.tooltipRect));
        if (union) {
            metrics.pixels = regionStats(webImg, natImg, union);
            if (metrics.pixels.diffRatio > t.pixelDiffWarnRatio) warn.push('pixelDivergence:' + metrics.pixels.diffRatio.toFixed(3));
            if (metrics.pixels.meanAbs > t.meanAbsDiffWarn) warn.push('meanAbsDiff:' + metrics.pixels.meanAbs.toFixed(1));
        }
        fs.writeFileSync(path.join(caseDir, 'side-by-side.png'), png.encode(sideBySide(webImg, natImg, 8)));
        if (webImg.width === natImg.width && webImg.height === natImg.height) {
            fs.writeFileSync(path.join(caseDir, 'overlay.png'), png.encode(overlay(webImg, natImg)));
            fs.writeFileSync(path.join(caseDir, 'diff.png'), png.encode(diffImage(webImg, natImg)));
        }
    }

    const verdict = hard.length ? 'fail' : (warn.length ? 'warn' : 'pass');
    const record = { caseId: cid, verdict, hard, warn, preset: presetName || 'loose', thresholds: t, metrics };
    fs.writeFileSync(path.join(caseDir, 'compare.json'), JSON.stringify(record, null, 1));
    return record;
}

// ---------- CLI ----------
function parseArgs(argv) {
    const out = {};
    for (let i = 2; i < argv.length; i++) {
        const a = argv[i];
        if (a === '--out') out.out = argv[++i];
        else if (a === '--cases') out.cases = argv[++i].split(',').filter(Boolean);
        else if (a === '--thresholds') out.thresholds = JSON.parse(fs.readFileSync(argv[++i], 'utf8'));
        else if (a === '--preset') out.preset = argv[++i];
        else fail('unknown arg: ' + a);
    }
    if (!out.out) fail('required: --out');
    return out;
}

function main() {
    const args = parseArgs(process.argv);
    const casesRoot = path.join(path.resolve(args.out), 'cases');
    const presetName = args.preset || 'loose';
    if (!PRESETS[presetName]) fail('unknown preset: ' + presetName + ' (loose|acceptance)');
    const cids = fs.readdirSync(casesRoot, { withFileTypes: true })
        .filter(e => e.isDirectory()).map(e => e.name)
        .filter(c => !args.cases || args.cases.includes(c));
    const summary = [];
    for (const cid of cids) {
        const r = compareCase(path.join(casesRoot, cid), args.thresholds, presetName);
        summary.push({ caseId: cid, verdict: r.verdict, hard: r.hard, warn: r.warn });
        process.stdout.write('[cmp] ' + cid + ' ' + r.verdict
            + (r.hard.length ? ' HARD:' + r.hard.join('|') : '')
            + (r.warn.length ? ' warn:' + r.warn.join('|') : '') + '\n');
    }
    const counts = { pass: 0, warn: 0, fail: 0 };
    summary.forEach(s => counts[s.verdict]++);
    fs.writeFileSync(path.join(path.resolve(args.out), 'summary.json'), JSON.stringify({
        schema: 'cf7.tooltip-parity-summary.v1', at: new Date().toISOString(), preset: presetName, counts, cases: summary
    }, null, 1));
    process.stdout.write('compare done: ' + JSON.stringify(counts) + '\n');
    process.exit(counts.fail ? 2 : 0);
}

if (require.main === module) main();
module.exports = { compareCase, DEFAULT_THRESHOLDS, PRESETS, png };
