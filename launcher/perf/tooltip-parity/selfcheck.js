#!/usr/bin/env node
'use strict';

/**
 * tooltip-parity 已知错误自校验：
 * 在临时目录构造受控 web/native 对（合成 PNG + JSON），逐项注入已知错误，
 * 断言 compare.compareCase 报出预期硬失败码；同时验证全等输入判 pass。
 * 任何一条未检出 → 退出码 1（说明比较器失灵，不能信任后续结论）。
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const { compareCase, png } = require('./compare.js');

const W = 128, H = 96;
const BG = [24, 26, 28];

function makeImage(drawRect) {
    const data = Buffer.alloc(W * H * 4);
    for (let i = 0; i < data.length; i += 4) { data[i] = BG[0]; data[i + 1] = BG[1]; data[i + 2] = BG[2]; data[i + 3] = 255; }
    if (drawRect) {
        for (let y = drawRect.top; y < drawRect.bottom; y++)
            for (let x = drawRect.left; x < drawRect.right; x++) {
                const i = (y * W + x) * 4;
                data[i] = 150; data[i + 1] = 150; data[i + 2] = 150; data[i + 3] = 255;
            }
    }
    return { width: W, height: H, data };
}

const TIP = { left: 20, top: 20, right: 80, bottom: 70, width: 60, height: 50 };
const INTRO = { left: 20, top: 20, right: 50, bottom: 70, width: 30, height: 50 };

function geo(over) {
    return Object.assign({
        shown: true, profile: 'dense-inspect', placement: 'right',
        tooltipRect: TIP, introPanelRect: INTRO,
        descPanelRect: null, iconRect: null,
        layout: { split: false, merge: true, stacked: false },
        // web 侧字段：intro/desc 为视觉行数组（null=unknown），descStatus 'absent'=无该面板
        text: { title: 't', intro: ['alpha', 'beta'], desc: null, introStatus: 'ok', descStatus: 'absent' },
        scroll: { scrollable: false, totalLines: 0, visibleLines: 0, scrollLine: 0, maxScrollLine: 0, reachBottom: true }
    }, over || {});
}

function writeCase(root, cid, web, nat, webPngBuf, natPngBuf) {
    const dir = path.join(root, 'cases', cid);
    fs.mkdirSync(dir, { recursive: true });
    if (web) fs.writeFileSync(path.join(dir, 'web.json'), JSON.stringify({ caseId: cid, viewport: { w: W, h: H }, geometry: web }));
    if (nat) fs.writeFileSync(path.join(dir, 'native.json'), JSON.stringify({ caseId: cid, viewport: { w: W, h: H }, geometry: nat }));
    if (webPngBuf) fs.writeFileSync(path.join(dir, 'web.png'), webPngBuf);
    if (natPngBuf) fs.writeFileSync(path.join(dir, 'native.png'), natPngBuf);
    return dir;
}

function expect(cid, record, wantVerdict, wantHard) {
    const got = record.verdict;
    const missing = (wantHard || []).filter(h => !record.hard.some(x => x.indexOf(h) === 0));
    const ok = got === wantVerdict && missing.length === 0;
    console.log((ok ? 'PASS ' : 'FAIL ') + cid + ' verdict=' + got
        + (record.hard.length ? ' hard=' + record.hard.join('|') : '')
        + (missing.length ? ' MISSING_EXPECTED=' + missing.join('|') : ''));
    return ok;
}

function main() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'ttparity-selfcheck-'));
    const goodPng = png.encode(makeImage(TIP));
    const blankPng = png.encode(makeImage(null));
    let allOk = true;

    // 0. 全等输入 → pass（同时也验证 PNG codec 往返）
    {
        const dir = writeCase(root, 'good-identical', geo(), geo(), goodPng, goodPng);
        allOk &= expect('good-identical', compareCase(dir), 'pass');
    }
    // 1. 尺寸偏差（native 高度 +60px，>24px 且 >15%）→ sizeDeviation
    {
        const nat = geo({ tooltipRect: { left: 20, top: 20, right: 80, bottom: 130, width: 60, height: 110 } });
        const dir = writeCase(root, 'bad-size', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-size', compareCase(dir), 'fail', ['sizeDeviation']);
    }
    // 2. 方向标签不同但实际矩形相同 → 诊断告警
    {
        const nat = geo({ placement: 'left' });
        const dir = writeCase(root, 'bad-placement', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-placement', compareCase(dir), 'warn', []);
    }
    // 3. 内容缺失：native intro 全空 → contentMissing
    {
        const nat = geo({ text: { title: 't', intro: [], desc: [], introStatus: 'ok', descStatus: 'absent' } });
        const dir = writeCase(root, 'bad-content', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-content', compareCase(dir), 'fail', ['contentMissing']);
    }
    // 3b. web intro 采集不可信（null/unknown）→ 不判缺内容、不放绿，warn textUnknown
    {
        const web = geo({ text: { title: 't', intro: null, desc: null, introStatus: 'unknown', descStatus: 'absent' } });
        const dir = writeCase(root, 'unknown-intro', web, geo(), goodPng, goodPng);
        const r = compareCase(dir);
        allOk &= expect('unknown-intro', r, 'warn', []);
        if (r.hard.some(x => x.indexOf('contentMissing') === 0)) { console.log('FAIL unknown-intro 误判缺内容'); allOk = false; }
        if (!r.warn.some(x => x.indexOf('textUnknown') === 0)) { console.log('FAIL unknown-intro missing textUnknown'); allOk = false; }
    }
    // 4. 渲染全空（native.png 纯背景）→ nativeBlankRender
    {
        const dir = writeCase(root, 'bad-blank', geo(), geo(), goodPng, blankPng);
        allOk &= expect('bad-blank', compareCase(dir), 'fail', ['nativeBlankRender']);
    }
    // 5. PNG 损坏 → nativePngUndecodable
    {
        const dir = writeCase(root, 'bad-corrupt', geo(), geo(), goodPng, Buffer.from('not a png at all'));
        allOk &= expect('bad-corrupt', compareCase(dir), 'fail', ['nativePngUndecodable']);
    }
    // 6. 滚动不符 → scrollMismatch / scrollUnreachable
    {
        const nat = geo({ scroll: { scrollable: true, totalLines: 9, visibleLines: 5, scrollLine: 0, maxScrollLine: 4, reachBottom: false } });
        const dir = writeCase(root, 'bad-scroll', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-scroll', compareCase(dir), 'fail', ['scrollMismatch', 'scrollUnreachable']);
    }
    // 7. 溢出：native 完全在视口外 → nativeOverflow
    {
        const nat = geo({ tooltipRect: { left: -500, top: -500, right: -400, bottom: -400, width: 100, height: 100 } });
        const dir = writeCase(root, 'bad-overflow', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-overflow', compareCase(dir), 'fail', ['nativeOverflow']);
    }
    // 8. 小位置漂移（12px < posTolHard）→ warn 而非 fail
    {
        const nat = geo({ tooltipRect: { left: 32, top: 20, right: 92, bottom: 70, width: 60, height: 50 } });
        const dir = writeCase(root, 'warn-drift', geo(), nat, goodPng, goodPng);
        allOk &= expect('warn-drift', compareCase(dir), 'warn', []);
        const r = compareCase(dir);
        if (!r.warn.some(x => x.indexOf('positionDrift') === 0)) { console.log('FAIL warn-drift missing positionDrift'); allOk = false; }
    }
    // 9. acceptance 预设：同一 12px 漂移 → 超 posTolHard(8) → fail；且 5px 尺寸差 → sizeDeviation fail
    {
        const nat = geo({ tooltipRect: { left: 32, top: 20, right: 92, bottom: 70, width: 60, height: 50 } });
        const dir = writeCase(root, 'acc-drift', geo(), nat, goodPng, goodPng);
        allOk &= expect('acc-drift', compareCase(dir, null, 'acceptance'), 'fail', ['positionDeviation']);
    }
    {
        const nat = geo({ tooltipRect: { left: 20, top: 20, right: 80, bottom: 75, width: 60, height: 55 } });
        const dir = writeCase(root, 'acc-size', geo(), nat, goodPng, goodPng);
        allOk &= expect('acc-size', compareCase(dir, null, 'acceptance'), 'fail', ['sizeDeviation']);
        // 同输入 loose 下只测绘不硬失败（5px < 24px 且 <15% 连 warn 都没有→pass）
        allOk &= expect('acc-size-loose', compareCase(dir, null, 'loose'), 'pass');
    }
    // 10. 全文相同但视觉折行数不同，保留 lineCountDrift 告警
    {
        const nat = geo({ text: { title: 't', intro: ['a', 'b', 'c', 'd', 'e', 'f'], desc: [], introStatus: 'ok', descStatus: 'absent' } });
        const web = geo({text:{title:'t',intro:['abcdef'],desc:[],introStatus:'ok',descStatus:'absent'}});
        const dir = writeCase(root, 'line-drift', web, nat, goodPng, goodPng);
        const r = compareCase(dir);
        allOk &= expect('line-drift', r, 'warn', []);
        if (!r.warn.some(x => x.indexOf('lineCountDrift') === 0)) { console.log('FAIL line-drift missing lineCountDrift'); allOk = false; }
    }
    // 11. 部分裁剪（右边缘超视口 12px，非完全离屏）→ nativeOverflow 硬失败
    {
        const nat = geo({ tooltipRect: { left: 80, top: 20, right: 140, bottom: 70, width: 60, height: 50 } });
        const dir = writeCase(root, 'bad-partialclip', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-partialclip', compareCase(dir), 'fail', ['nativeOverflow']);
    }
    // 12. 面板部分裁剪：native descPanelRect 底边超视口 → nativePanelOverflow 硬失败
    {
        const nat = geo({ layout: { split: true, merge: false, stacked: false },
            descPanelRect: { left: 20, top: 60, right: 80, bottom: 120, width: 60, height: 60 } });
        const dir = writeCase(root, 'bad-panelclip', geo(), nat, goodPng, goodPng);
        allOk &= expect('bad-panelclip', compareCase(dir), 'fail', ['nativePanelOverflow']);
    }
    // 13. 折行差异不报缺内容：web 2 行 vs native 3 行但 squash 全文相等 → 无 textLineDiff
    {
        const web = geo({ layout: { split: true, merge: false, stacked: false },
            text: { title: 't', intro: ['alpha', 'beta'], desc: ['abc def', 'ghi jkl'], introStatus: 'ok', descStatus: 'ok' } });
        const nat = geo({ layout: { split: true, merge: false, stacked: false },
            text: { title: 't', intro: ['alpha', 'beta'], desc: ['abc', 'def ghi', 'jkl'], introStatus: 'ok', descStatus: 'ok' } });
        const dir = writeCase(root, 'wrap-equal', web, nat, goodPng, goodPng);
        const r = compareCase(dir);
        allOk &= expect('wrap-equal', r, 'pass', []);
        if (r.warn.some(x => x.indexOf('textLineDiff') === 0)) { console.log('FAIL wrap-equal 误报缺内容'); allOk = false; }
        // acceptance 下行数差 ≥1 → lineCountDrift warn（行数口径仍生效，缺内容不误报）
        const ra = compareCase(dir, null, 'acceptance');
        allOk &= expect('wrap-equal-acc', ra, 'warn', []);
        if (!ra.warn.some(x => x.indexOf('lineCountDrift') === 0)) { console.log('FAIL wrap-equal-acc missing lineCountDrift'); allOk = false; }
        if (ra.warn.some(x => x.indexOf('textLineDiff') === 0)) { console.log('FAIL wrap-equal-acc 误报缺内容'); allOk = false; }
    }
    // 14. 真实缺内容：web 有片段 native 全文拼接中没有 → textLineDiff warn
    {
        const web = geo({ text: { title: 't', intro: ['alpha', 'beta', 'gamma'], desc: null, introStatus: 'ok', descStatus: 'absent' } });
        const dir = writeCase(root, 'real-missing', web, geo(), goodPng, goodPng);
        const r = compareCase(dir);
        allOk &= expect('real-missing', r, 'fail', ['textLineDiff']);
        if (!r.hard.some(x => x.indexOf('textLineDiff') === 0)) { console.log('FAIL real-missing missing textLineDiff'); allOk = false; }
    }

    // 候选方向不同但夹取后位置相同：只保留标签诊断；真正移位仍硬失败。
    {
        const same = writeCase(root, 'same-position-label', geo({placement:'left'}),
            geo({placement:'right'}), goodPng, goodPng);
        const r = compareCase(same, null, 'acceptance');
        allOk &= expect('same-position-label', r, 'warn', []);
        if (!r.warn.some(x => x.startsWith('placementLabelDrift:'))) allOk = false;
        const moved = writeCase(root, 'different-position-label', geo({placement:'left'}),
            geo({placement:'right',tooltipRect:{left:40,top:20,right:100,bottom:70,width:60,height:50}}), goodPng, goodPng);
        allOk &= expect('different-position-label', compareCase(moved,null,'acceptance'), 'fail', ['positionDeviation']);
    }

    fs.rmSync(root, { recursive: true, force: true });
    console.log(allOk ? 'selfcheck OK' : 'selfcheck FAILED');
    process.exit(allOk ? 0 : 1);
}

main();
