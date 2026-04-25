// 报表生成：JSON + Markdown + HTML（含截图视觉验收对比）。

'use strict';

const fs = require('fs');
const path = require('path');

function pct(a, b) {
    if (!b || b === 0) return 'n/a';
    return ((a - b) / b * 100).toFixed(1) + '%';
}

function toRow(r) {
    if (r.error) {
        return { scenario: r.scenario, ablation: r.ablation, error: r.error };
    }
    const video = r.video || null;
    const repeats = r.result.runs || 1;
    const cv = r.result.taskDurationCV || 0;
    const f = r.result.frames || {};
    const c = r.result.cdp || {};
    const t = r.result.trace || {};
    const pf = r.result.perCompositeFrame || {};
    const sampleSec = Math.max(0.001, (r.result.sampleMs || 1000) / 1000);
    // 主指标：每秒主线程 CPU 时间（s/s）。> 1.0 表示多核占用饱和；越低越省。
    // 这是 headless / 真实环境都可信的信号。
    const cpuPerSec = (c.TaskDuration || 0) / sampleSec;
    return {
        scenario: r.scenario,
        ablation: r.ablation,
        sampleSec: Number(sampleSec.toFixed(2)),
        repeats,
        cv: Number(cv.toFixed(3)),
        // 主指标
        cpuPerSec: Number(cpuPerSec.toFixed(3)),
        scriptPerSec: Number(((c.ScriptDuration || 0) / sampleSec).toFixed(3)),
        layoutsPerSec: Number(((c.LayoutCount || 0) / sampleSec).toFixed(1)),
        recalcsPerSec: Number(((c.RecalcStyleCount || 0) / sampleSec).toFixed(1)),
        layoutDurationPerSec: Number(((c.LayoutDuration || 0) / sampleSec).toFixed(3)),
        recalcDurationPerSec: Number(((c.RecalcStyleDuration || 0) / sampleSec).toFixed(3)),
        longTasks: r.result.longTasks,
        // 副指标（headless 下不一定有信号）
        rafFps: f.fps,
        rafMeanMs: f.meanMs,
        compositeFrames: t.composite || 0,
        paintUsPerFrame: pf.paintUs || 0,
        rasterUsPerFrame: pf.rasterUs || 0,
        // 累计原始数据（调试用）
        taskDuration: Number((c.TaskDuration || 0).toFixed(3)),
        scriptDuration: Number((c.ScriptDuration || 0).toFixed(3)),
        screenshot: r.screenshot,
        video,
        errors: (r.errors || []).length,
    };
}

function writeJson(rows, outPath) {
    fs.writeFileSync(outPath, JSON.stringify(rows, null, 2));
}

function writeMarkdown(rows, outPath) {
    const byScenario = {};
    for (const r of rows) {
        if (!byScenario[r.scenario]) byScenario[r.scenario] = [];
        byScenario[r.scenario].push(r);
    }
    const lines = ['# Web overlay 性能消融测试报告',
        '',
        `生成时间: ${new Date().toISOString()}`,
        '',
        '所有 Δ% 列以 baseline 为参照（负值 = 改善，meanMs/p95/longTasks 越小越好）。',
        ''];
    for (const scenario of Object.keys(byScenario)) {
        const list = byScenario[scenario];
        const baseline = list.find(r => r.ablation === 'baseline');
        lines.push(`## ${scenario}`);
        lines.push('');
        lines.push('| ablation | runs | cpu/s | Δcpu | CV | script/s | recalc/s | layoutDur/s | longTasks |');
        lines.push('|---|---|---|---|---|---|---|---|---|');
        // 标记是否信号超出噪声：|Δcpu| > 2 × baseline CV
        for (const r of list) {
            if (r.error) {
                lines.push(`| ${r.ablation} | ERROR | ${r.error} | | | | | | |`);
                continue;
            }
            const dCpu = baseline && !baseline.error && baseline.cpuPerSec > 0
                ? pct(r.cpuPerSec, baseline.cpuPerSec) : '—';
            const dCpuNum = baseline && !baseline.error && baseline.cpuPerSec > 0
                ? Math.abs((r.cpuPerSec - baseline.cpuPerSec) / baseline.cpuPerSec) : 0;
            const noise = baseline ? baseline.cv : 0;
            // 三档信号显著性：>2×CV 强信号、>1×CV 弱信号、其余噪声
            let dCpuMarker = dCpu;
            if (r.ablation !== 'baseline') {
                if (dCpuNum > noise * 2) dCpuMarker = '**' + dCpu + '** ✓✓';
                else if (dCpuNum > noise) dCpuMarker = '**' + dCpu + '** ✓';
            }
            lines.push(`| ${r.ablation} | ${r.repeats} | ${r.cpuPerSec} | ${dCpuMarker} | ${r.cv} | ${r.scriptPerSec} | ${r.recalcsPerSec} | ${r.layoutDurationPerSec} | ${r.longTasks} |`);
        }
        lines.push('');
        lines.push('> ✓✓ 强信号 |Δ| > 2×CV；✓ 弱信号 |Δ| > CV；无标记 = 噪声范围内。CV = (max-min)/median。');
        lines.push('');
    }
    fs.writeFileSync(outPath, lines.join('\n'));
}

function writeVisualHtml(rows, outPath) {
    const byScenario = {};
    for (const r of rows) {
        if (r.error) continue;
        if (!byScenario[r.scenario]) byScenario[r.scenario] = [];
        byScenario[r.scenario].push(r);
    }
    const html = [];
    html.push('<!doctype html><html><head><meta charset="utf-8"><title>CF7 perf visual diff</title>');
    html.push(`<style>
        body { font-family: system-ui, sans-serif; background: #1a1a1a; color: #eee; margin: 0; padding: 20px; }
        h1 { color: #72e6ff; }
        h2 { color: #c8ff4c; margin-top: 30px; border-bottom: 1px solid #333; padding-bottom: 5px; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(400px, 1fr)); gap: 16px; }
        .card { background: #222; border: 1px solid #333; border-radius: 6px; padding: 10px; }
        .card.baseline { border-color: #72e6ff; }
        .card h3 { margin: 0 0 6px 0; font-size: 14px; color: #fff; }
        .card .meta { font-size: 11px; color: #888; margin-bottom: 8px; }
        .card .delta { font-weight: bold; }
        .card .delta.good { color: #4ade80; }
        .card .delta.bad { color: #f87171; }
        .card img, .card video { width: 100%; height: auto; border: 1px solid #444; cursor: zoom-in; display: block; }
        .card img.zoom, .card video.zoom { position: fixed; top: 0; left: 0; width: 100vw; height: 100vh; object-fit: contain; background: #000; z-index: 999; cursor: zoom-out; }
    </style>`);
    html.push(`<script>
        document.addEventListener('click', e => {
            if (e.target.tagName === 'IMG' || e.target.tagName === 'VIDEO') {
                e.target.classList.toggle('zoom');
            }
        });
    </script>`);
    html.push('</head><body>');
    html.push('<h1>CF7:ME Web overlay 性能消融——视觉验收</h1>');
    html.push('<p>每个场景下：第一张是 baseline（蓝边），其余是 ablation 后的截图与帧时间增减。点击图片放大。</p>');

    for (const scenario of Object.keys(byScenario)) {
        const list = byScenario[scenario];
        const baseline = list.find(r => r.ablation === 'baseline');
        html.push(`<h2>${scenario}</h2><div class="grid">`);
        for (const r of list) {
            const isBaseline = r.ablation === 'baseline';
            const delta = baseline && !isBaseline ? pct(r.meanMs, baseline.meanMs) : '';
            const cls = !isBaseline && delta && delta.startsWith('-') ? 'good' : (delta && !delta.startsWith('-') ? 'bad' : '');
            html.push(`<div class="card${isBaseline ? ' baseline' : ''}">`);
            const dCpu = baseline && !isBaseline && baseline.cpuPerSec > 0
                ? pct(r.cpuPerSec, baseline.cpuPerSec) : '';
            html.push(`<h3>${r.ablation}${isBaseline ? ' (baseline)' : ''}</h3>`);
            html.push(`<div class="meta">cpu/s=${r.cpuPerSec} script/s=${r.scriptPerSec} recalc/s=${r.recalcsPerSec} longTasks=${r.longTasks} rafFps=${r.rafFps}</div>`);
            if (dCpu) {
                const cls2 = dCpu.startsWith('-') ? 'good' : 'bad';
                html.push(`<div class="delta ${cls2}">Δ cpu/s ${dCpu}</div>`);
            }
            if (r.video) {
                const videoSrc = r.video.replace(/\\/g, '/');
                html.push(`<video src="${videoSrc}" autoplay loop muted playsinline preload="metadata"></video>`);
            } else if (r.screenshot) {
                html.push(`<img src="${r.screenshot.replace(/\\/g, '/')}" alt="${r.ablation}">`);
            } else {
                html.push(`<div style="color:#666">(no media)</div>`);
            }
            html.push(`</div>`);
        }
        html.push(`</div>`);
    }
    html.push('</body></html>');
    fs.writeFileSync(outPath, html.join('\n'));
}

module.exports = { toRow, writeJson, writeMarkdown, writeVisualHtml };
