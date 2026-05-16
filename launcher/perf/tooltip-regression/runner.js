/**
 * tooltip-regression/runner.js
 *
 * 把 tooltip-truth.json 的 AS2 真值喂进 Playwright + Chromium，
 * 在加载真实 panels.css 的环境里复刻每个 item 的 mock tooltip DOM，
 * 测 introPanel/descPanel/iconEl 的 offsetHeight / offsetWidth，
 * 与 AS2 introBgH/mainBgH/introTH/mainTH/introW/mainW 对比，输出 diff 报告。
 *
 * 真值文件位置：launcher/perf/tooltip-regression/tooltip-truth.json
 *   - 不在 runtime 包（launcher/web/assets/）里，避免发布包多 1.5MB。
 *   - 视作 dev-only 中间产物，不进 git；缺失时跑 parse-gt.py 从
 *     scripts/flashlog.txt 重生成（流程详见 README "重采流程" 段）。
 *
 * 用法：
 *   cd launcher/perf && node tooltip-regression/runner.js
 *   cd launcher/perf && node tooltip-regression/runner.js --limit 50      # 只跑前 50 个
 *   cd launcher/perf && node tooltip-regression/runner.js --json out.json  # 多写一份原始 JSON
 *
 * 输出：
 *   tooltip-regression/reports/<timestamp>/report.md    人读
 *   tooltip-regression/reports/<timestamp>/raw.json     机读
 */

'use strict';

const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');
const { startServer, stopServer } = require('../lib/server.js');

const REPO_ROOT = path.resolve(__dirname, '..', '..', '..');
const LAUNCHER_DIR = path.join(REPO_ROOT, 'launcher');
const FIXTURE_URL_PATH = 'perf/tooltip-regression/fixture.html';
const TRUTH_PATH = path.join(__dirname, 'tooltip-truth.json');

function parseArgs(argv) {
    const args = { limit: 0, json: null, sweep: null, override: null, descFit: false,
                   estimateDesc: false, pixPerUnit: null, sweepPpu: null };
    for (let i = 2; i < argv.length; i++) {
        if (argv[i] === '--limit') args.limit = parseInt(argv[++i], 10) || 0;
        else if (argv[i] === '--json') args.json = argv[++i];
        else if (argv[i] === '--sweep-lh') args.sweep = argv[++i].split(',').map(Number);
        else if (argv[i] === '--lh') args.override = parseFloat(argv[++i]);
        else if (argv[i] === '--desc-fit') args.descFit = true;
        else if (argv[i] === '--estimate-desc') args.estimateDesc = true;
        else if (argv[i] === '--ppu') args.pixPerUnit = parseFloat(argv[++i]);
        else if (argv[i] === '--sweep-ppu') args.sweepPpu = argv[++i].split(',').map(Number);
    }
    return args;
}

function quantileSorted(arr, q) {
    if (arr.length === 0) return 0;
    const idx = Math.max(0, Math.min(arr.length - 1, Math.floor(arr.length * q)));
    return arr[idx];
}

function summarize(name, values) {
    const sorted = values.slice().sort((a, b) => a - b);
    const sum = sorted.reduce((a, b) => a + b, 0);
    const mean = sum / sorted.length;
    return {
        name,
        n: sorted.length,
        min: sorted[0],
        p10: quantileSorted(sorted, 0.10),
        p25: quantileSorted(sorted, 0.25),
        p50: quantileSorted(sorted, 0.50),
        p75: quantileSorted(sorted, 0.75),
        p90: quantileSorted(sorted, 0.90),
        max: sorted[sorted.length - 1],
        mean,
    };
}

function histogram(values, bins) {
    const sorted = values.slice().sort((a, b) => a - b);
    if (sorted.length === 0) return [];
    const min = sorted[0], max = sorted[sorted.length - 1];
    const w = (max - min) / bins || 1;
    const counts = new Array(bins).fill(0);
    for (const v of sorted) {
        let i = Math.min(bins - 1, Math.floor((v - min) / w));
        counts[i]++;
    }
    return counts.map((c, i) => ({
        lo: min + i * w,
        hi: i === bins - 1 ? max : min + (i + 1) * w,
        count: c,
    }));
}

function fmt(n) {
    if (typeof n !== 'number' || !isFinite(n)) return String(n);
    return Math.abs(n - Math.round(n)) < 0.05 ? Math.round(n).toString() : n.toFixed(2);
}

function writeReport(outDir, summary, items) {
    fs.mkdirSync(outDir, { recursive: true });

    const lines = [];
    lines.push('# Tooltip Regression — Web vs AS2 Diff Report');
    lines.push('');
    lines.push('生成时间: ' + new Date().toISOString());
    lines.push('Fixture: launcher/perf/tooltip-regression/fixture.html');
    lines.push('真值: launcher/perf/tooltip-regression/tooltip-truth.json');
    lines.push('Item 数: ' + items.length);
    lines.push('');
    lines.push('## 字段说明');
    lines.push('- `introBgH_diff` = web 端 introPanel.offsetHeight − AS2 introBgH（正值=web 比 AS2 大）');
    lines.push('- `mainBgH_diff` = web 端 descPanel.offsetHeight − AS2 mainBgH（自然态，不含 ELSE floor）');
    lines.push('- `introTH_diff` = web 端 .flash-tt-intro.offsetHeight − AS2 introTH（Flash TextField textHeight）');
    lines.push('  （注意：web introText 含 inline padding 0、line-height 1.6；AS2 是 TextField 12pt 默认行距）');
    lines.push('- `introW_diff` / `mainW_diff` = web panel.offsetWidth − AS2 introW / mainW');
    lines.push('');
    lines.push('## 统计分位（px）');
    lines.push('');
    lines.push('| metric | n | min | p10 | p25 | p50 | p75 | p90 | max | mean |');
    lines.push('|--------|---|-----|-----|-----|-----|-----|-----|-----|------|');
    for (const s of summary) {
        lines.push(`| ${s.name} | ${s.n} | ${fmt(s.min)} | ${fmt(s.p10)} | ${fmt(s.p25)} | ${fmt(s.p50)} | ${fmt(s.p75)} | ${fmt(s.p90)} | ${fmt(s.max)} | ${fmt(s.mean)} |`);
    }
    lines.push('');

    lines.push('## 直方图');
    for (const s of summary) {
        const vals = items.map(it => it.diff[s.name.replace('_diff', '') + '_diff']);
        const h = histogram(vals, 12);
        lines.push('');
        lines.push('### ' + s.name);
        lines.push('');
        lines.push('| bin | count | bar |');
        lines.push('|-----|-------|-----|');
        const maxC = Math.max(...h.map(b => b.count));
        for (const b of h) {
            const bar = '█'.repeat(Math.round(40 * b.count / maxC));
            lines.push(`| ${fmt(b.lo)} .. ${fmt(b.hi)} | ${b.count} | ${bar} |`);
        }
    }

    lines.push('');
    lines.push('## Top 10 worst (|introBgH_diff| 最大)');
    const sortedByIntro = items.slice().sort((a, b) =>
        Math.abs(b.diff.introBgH_diff) - Math.abs(a.diff.introBgH_diff));
    lines.push('');
    lines.push('| item | AS2 introBgH | web introPanelH | diff | AS2 introTH | web introTextH |');
    lines.push('|------|--------------|-----------------|------|-------------|----------------|');
    for (const it of sortedByIntro.slice(0, 10)) {
        lines.push(`| ${it.name} | ${it.as2.introBgH} | ${fmt(it.web.introPanelH)} | ${fmt(it.diff.introBgH_diff)} | ${it.as2.introTH} | ${fmt(it.web.introTextH)} |`);
    }

    lines.push('');
    lines.push('## Top 10 worst (|mainBgH_diff| 最大)');
    const sortedByMain = items.slice().sort((a, b) =>
        Math.abs(b.diff.mainBgH_diff) - Math.abs(a.diff.mainBgH_diff));
    lines.push('');
    lines.push('| item | AS2 mainBgH | web descPanelH | diff | AS2 mainTH | AS2 mainW | web descPanelW |');
    lines.push('|------|-------------|----------------|------|------------|-----------|----------------|');
    for (const it of sortedByMain.slice(0, 10)) {
        lines.push(`| ${it.name} | ${it.as2.mainBgH} | ${fmt(it.web.descPanelH)} | ${fmt(it.diff.mainBgH_diff)} | ${it.as2.mainTH} | ${it.as2.mainW} | ${fmt(it.web.descPanelW)} |`);
    }

    lines.push('');
    lines.push('## CSS 常量速查');
    lines.push('- `.flash-tt-rich` --tt-icon-size: 192px（AS2 BASE_NUM=200, ICON_H_PX=300 含 ICON_SCALE）');
    lines.push('- `.flash-tt-rich` --tt-intro-max-w: 300px（AS2 INTRO_MAX_W=300）');
    lines.push('- `.flash-tt-rich` --tt-intro-min-h: 220px（AS2 BG_HEIGHT_OFFSET+BASE_NUM）');
    lines.push('- `.flash-tt-intro-panel` padding: 10px 14px, border: 1px');
    lines.push('- `.flash-tt-desc` padding: 10px 14px, border: 1px, box-sizing: border-box');
    lines.push('- `#panel-tooltip` font-size: 12px, letter-spacing: 0.3px, line-height: 1.5');
    lines.push('- `.flash-tt-intro/.flash-tt-desc` line-height: var(--tt-intro-line-height|--tt-desc-line-height) = 1.6');

    fs.writeFileSync(path.join(outDir, 'report.md'), lines.join('\n'), 'utf-8');
    fs.writeFileSync(path.join(outDir, 'raw.json'), JSON.stringify({ summary, items }), 'utf-8');
}

async function measureRun(page, items, lhOverride, descFit) {
    if (lhOverride != null) {
        await page.evaluate((lh) => {
            let s = document.getElementById('__lh_override');
            if (!s) {
                s = document.createElement('style');
                s.id = '__lh_override';
                document.head.appendChild(s);
            }
            s.textContent = '.flash-tt-rich, .kshop-tt-rich { --tt-intro-line-height: ' + lh + '; --tt-desc-line-height: ' + lh + '; }';
        }, lhOverride);
    } else {
        await page.evaluate(() => {
            const s = document.getElementById('__lh_override');
            if (s) s.remove();
        });
    }
    if (descFit) {
        await page.evaluate(() => {
            let s = document.getElementById('__desc_fit_override');
            if (!s) {
                s = document.createElement('style');
                s.id = '__desc_fit_override';
                document.head.appendChild(s);
            }
            s.textContent = '.flash-tt-desc, .kshop-tt-desc { width: max-content !important; flex-basis: max-content !important; }';
        });
    } else {
        await page.evaluate(() => {
            const s = document.getElementById('__desc_fit_override');
            if (s) s.remove();
        });
    }

    const results = [];
    const BATCH = 50;
    for (let i = 0; i < items.length; i += BATCH) {
        const batch = items.slice(i, i + BATCH);
        const opts = measureRun._opts || {};
        const measured = await page.evaluate(({ batchData, opts }) => {
            return batchData.map(it => {
                const m = window.__measureItem(it, opts);
                return { name: it.name, m };
            });
        }, { batchData: batch, opts });
        for (let j = 0; j < batch.length; j++) {
            const it = batch[j];
            const web = measured[j].m;
            if (!web) continue;
            results.push({
                name: it.name,
                type: it.type,
                use: it.use,
                as2: {
                    introTH: it.introTH, mainTH: it.mainTH,
                    introBgH: it.introBgH, mainBgH: it.mainBgH, mainBgFlr: it.mainBgFlr,
                    introW: it.introW, mainW: it.mainW,
                },
                web,
                diff: {
                    introBgH_diff: web.introPanelH - it.introBgH,
                    mainBgH_diff: web.descPanelH - it.mainBgH,
                    introTH_diff: web.introTextH - it.introTH,
                    introW_diff: web.introPanelW - it.introW,
                    mainW_diff: web.descPanelW - it.mainW,
                },
            });
        }
    }
    return results;
}

function buildSummary(results) {
    return [
        summarize('introBgH_diff', results.map(r => r.diff.introBgH_diff)),
        summarize('mainBgH_diff', results.map(r => r.diff.mainBgH_diff)),
        summarize('introTH_diff', results.map(r => r.diff.introTH_diff)),
        summarize('introW_diff', results.map(r => r.diff.introW_diff)),
        summarize('mainW_diff', results.map(r => r.diff.mainW_diff)),
    ];
}

function printSummary(label, summary) {
    console.log('');
    console.log(`=== ${label} ===`);
    for (const s of summary) {
        console.log(`  ${s.name.padEnd(20)} p50=${fmt(s.p50).padStart(6)}  p90=${fmt(s.p90).padStart(6)}  mean=${fmt(s.mean).padStart(6)}  min=${fmt(s.min).padStart(6)}  max=${fmt(s.max).padStart(6)}`);
    }
}

async function main() {
    const args = parseArgs(process.argv);
    console.log('[setup] loading truth.json ...');
    const truth = JSON.parse(fs.readFileSync(TRUTH_PATH, 'utf-8'));
    let items = truth.items.filter(it => it.introHtml && it.descHtml);
    if (args.limit > 0) items = items.slice(0, args.limit);
    console.log(`[setup] ${items.length} items (split mode with HTML)`);

    console.log('[setup] starting static server ...');
    const server = await startServer(LAUNCHER_DIR);
    console.log('[setup] server at ' + server.url);

    let browser;
    try {
        browser = await chromium.launch({ headless: true });
        const ctx = await browser.newContext({
            viewport: { width: 1280, height: 800 },
        });
        const page = await ctx.newPage();
        console.log('[setup] opening fixture ...');
        await page.goto(server.url + FIXTURE_URL_PATH);
        await page.waitForFunction(() => window.__readyForMeasurement === true, { timeout: 10000 });

        if (args.sweepPpu && args.sweepPpu.length > 0) {
            // sweep PIX_PER_UNIT 候选
            console.log('');
            console.log('[sweep-ppu] candidates: ' + args.sweepPpu.join(', '));
            const sweepResults = [];
            for (const ppu of args.sweepPpu) {
                console.log(`[sweep-ppu] measuring ppu=${ppu} ...`);
                measureRun._opts = { descWidthMode: 'estimate', pixPerUnit: ppu };
                const r = await measureRun(page, items, args.override, false);
                const s = buildSummary(r);
                sweepResults.push({ ppu, summary: s, results: r });
                printSummary(`ppu=${ppu}`, s);
            }
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const outDir = path.join(__dirname, 'reports', ts + '_sweep_ppu');
            fs.mkdirSync(outDir, { recursive: true });
            const lines = [];
            lines.push('# PIX_PER_UNIT Sweep — desc width 估算系数');
            lines.push('');
            lines.push('| ppu | mainW_p50 | mainW_p90 | mainW_mean | mainBgH_p50 | mainBgH_p90 | |mainW|<10 占比 |');
            lines.push('|-----|-----------|-----------|------------|-------------|-------------|-----------|');
            for (const sr of sweepResults) {
                const sW = sr.summary.find(x => x.name === 'mainW_diff');
                const sH = sr.summary.find(x => x.name === 'mainBgH_diff');
                const within10 = sr.results.filter(r => Math.abs(r.diff.mainW_diff) < 10).length;
                const pct = (within10 / sr.results.length * 100).toFixed(1);
                lines.push(`| ${sr.ppu} | ${fmt(sW.p50)} | ${fmt(sW.p90)} | ${fmt(sW.mean)} | ${fmt(sH.p50)} | ${fmt(sH.p90)} | ${pct}% |`);
            }
            fs.writeFileSync(path.join(outDir, 'sweep-ppu.md'), lines.join('\n'), 'utf-8');
            console.log('[sweep-ppu-report] → ' + path.relative(REPO_ROOT, outDir));
            measureRun._opts = null;
        } else if (args.sweep && args.sweep.length > 0) {
            // sweep 模式：跑多个 line-height 候选值，对比 introBgH_diff / mainBgH_diff 中位数
            console.log('');
            console.log('[sweep] line-height 候选: ' + args.sweep.join(', '));
            const sweepResults = [];
            for (const lh of args.sweep) {
                console.log(`[sweep] measuring line-height=${lh} ...`);
                const r = await measureRun(page, items, lh, args.descFit);
                const s = buildSummary(r);
                sweepResults.push({ lh, summary: s, results: r });
                printSummary(`line-height=${lh}`, s);
            }
            // 写 sweep 报告
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const outDir = path.join(__dirname, 'reports', ts + '_sweep');
            fs.mkdirSync(outDir, { recursive: true });
            const lines = [];
            lines.push('# Line-height Sweep Report');
            lines.push('');
            lines.push('生成时间: ' + new Date().toISOString());
            lines.push('Item 数: ' + items.length);
            lines.push('');
            lines.push('## introBgH_diff 中位数对比');
            lines.push('');
            lines.push('| line-height | p10 | p25 | p50 | p75 | p90 | mean | |diff|<5 占比 |');
            lines.push('|-------------|-----|-----|-----|-----|-----|------|------------|');
            for (const sr of sweepResults) {
                const s = sr.summary.find(x => x.name === 'introBgH_diff');
                const within5 = sr.results.filter(r => Math.abs(r.diff.introBgH_diff) < 5).length;
                const pct = (within5 / sr.results.length * 100).toFixed(1);
                lines.push(`| ${sr.lh} | ${fmt(s.p10)} | ${fmt(s.p25)} | ${fmt(s.p50)} | ${fmt(s.p75)} | ${fmt(s.p90)} | ${fmt(s.mean)} | ${pct}% |`);
            }
            lines.push('');
            lines.push('## mainBgH_diff 中位数对比');
            lines.push('');
            lines.push('| line-height | p10 | p25 | p50 | p75 | p90 | mean | |diff|<5 占比 |');
            lines.push('|-------------|-----|-----|-----|-----|-----|------|------------|');
            for (const sr of sweepResults) {
                const s = sr.summary.find(x => x.name === 'mainBgH_diff');
                const within5 = sr.results.filter(r => Math.abs(r.diff.mainBgH_diff) < 5).length;
                const pct = (within5 / sr.results.length * 100).toFixed(1);
                lines.push(`| ${sr.lh} | ${fmt(s.p10)} | ${fmt(s.p25)} | ${fmt(s.p50)} | ${fmt(s.p75)} | ${fmt(s.p90)} | ${fmt(s.mean)} | ${pct}% |`);
            }
            lines.push('');
            lines.push('## introTH_diff 中位数对比（文字本体高度，不含 padding/border）');
            lines.push('');
            lines.push('| line-height | p10 | p25 | p50 | p75 | p90 | mean |');
            lines.push('|-------------|-----|-----|-----|-----|-----|------|');
            for (const sr of sweepResults) {
                const s = sr.summary.find(x => x.name === 'introTH_diff');
                lines.push(`| ${sr.lh} | ${fmt(s.p10)} | ${fmt(s.p25)} | ${fmt(s.p50)} | ${fmt(s.p75)} | ${fmt(s.p90)} | ${fmt(s.mean)} |`);
            }
            fs.writeFileSync(path.join(outDir, 'sweep.md'), lines.join('\n'), 'utf-8');
            fs.writeFileSync(path.join(outDir, 'sweep.json'), JSON.stringify(sweepResults.map(x => ({ lh: x.lh, summary: x.summary }))), 'utf-8');
            console.log('');
            console.log('[sweep-report] → ' + path.relative(REPO_ROOT, outDir));
        } else {
            // 单次模式
            const tagBits = [];
            if (args.override != null) tagBits.push('lh=' + args.override);
            if (args.estimateDesc) tagBits.push('estimate-desc' + (args.pixPerUnit != null ? `(ppu=${args.pixPerUnit})` : ''));
            const tagStr = tagBits.length ? '(' + tagBits.join(', ') + ')' : '(baseline CSS)';
            console.log('[run] measuring ' + tagStr + ' ...');
            if (args.estimateDesc) {
                measureRun._opts = { descWidthMode: 'estimate', pixPerUnit: args.pixPerUnit };
            }
            const results = await measureRun(page, items, args.override, args.descFit);
            measureRun._opts = null;
            const summary = buildSummary(results);
            const ts = new Date().toISOString().replace(/[:.]/g, '-').slice(0, 19);
            const tag = args.override != null ? `_lh${args.override}` : '';
            const outDir = path.join(__dirname, 'reports', ts + tag);
            writeReport(outDir, summary, results);
            console.log(`[done] measured ${results.length} items`);
            console.log('[report] → ' + path.relative(REPO_ROOT, outDir));
            printSummary(args.override != null ? `line-height=${args.override}` : 'baseline', summary);
            if (args.json) {
                fs.writeFileSync(args.json, JSON.stringify({ summary, items: results }), 'utf-8');
                console.log('[json] → ' + args.json);
            }
        }
    } finally {
        if (browser) await browser.close();
        await stopServer(server);
    }
}

main().catch(err => {
    console.error(err);
    process.exit(1);
});
