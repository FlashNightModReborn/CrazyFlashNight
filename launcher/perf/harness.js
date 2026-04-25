// CF7:ME Web overlay 性能测试 harness。
//
// 用法：
//   node harness.js --mode all                  全跑所有场景 × 所有 ablation
//   node harness.js --mode all --sample 6000    每次量测 6 秒（默认 4000ms）
//   node harness.js --mode all --scenario panel-map   只跑 panel-map 场景
//   node harness.js --mode all --ablation backdrop-filter-off   只跑特定 ablation
//   node harness.js --mode watch --scenario idle      浏览器可见，交互调试
//
// 报告产物在 reports/<timestamp>/：
//   summary.json / summary.md / visual-diff.html / screenshots/*.png

'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const { startServer, stopServer } = require('./lib/server');
const { runOne, loadModulesFromDir } = require('./lib/runner');
const { toRow, writeJson, writeMarkdown, writeVisualHtml } = require('./lib/report');

const ROOT = path.resolve(__dirname, '..', 'web');
const REPORT_ROOT = path.resolve(__dirname, 'reports');

function parseArgs() {
    const args = process.argv.slice(2);
    // 默认 headed：headless Chromium 在无显示器时不产生 compositor frame，
    // backdrop-filter / mix-blend-mode 这些 GPU-端开销无法呈现。
    // 可见窗口走真 iGPU 路径，rAF 间隔成为可信信号。
    const out = {
        mode: 'all',
        sampleMs: 4000,
        warmupMs: 2000,        // Kimi 建议 ≥2000ms（layer tree + 字体 + 图片解码）
        repeats: 5,            // 5 次重复取中位数 + CV，统计稳健
        dryRun: true,          // 每个 ablation 先跑一次预热丢弃
        settleMs: 600,         // ablation 注入后的稳定等待
        headless: false,
        videos: true,
    };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a === '--mode') out.mode = args[++i];
        else if (a === '--sample') out.sampleMs = Number(args[++i]);
        else if (a === '--warmup') out.warmupMs = Number(args[++i]);
        else if (a === '--repeats') out.repeats = Number(args[++i]);
        else if (a === '--no-dry-run') out.dryRun = false;
        else if (a === '--no-videos') out.videos = false;
        else if (a === '--settle') out.settleMs = Number(args[++i]);
        else if (a === '--scenario') out.onlyScenario = args[++i];
        else if (a === '--ablation') out.onlyAblation = args[++i];
        else if (a === '--watch') { out.mode = 'watch'; out.headless = false; }
        else if (a === '--headless') out.headless = true;
        else if (a === '--headed') out.headless = false;
        else if (a === '--quick') { out.repeats = 1; out.dryRun = false; out.warmupMs = 500; }
        else if (a === '--help') { printHelp(); process.exit(0); }
    }
    return out;
}

function applyModeDefaults(opts) {
    if (opts.mode === 'all') return;
    if (opts.mode === 'baseline') {
        opts.onlyAblation = 'baseline';
        return;
    }
    if (opts.mode === 'ablate') {
        opts.mode = 'all';
        return;
    }
    if (opts.mode === 'watch') {
        opts.repeats = 1;
        opts.dryRun = false;
        opts.videos = false;
        opts.headless = false;
        return;
    }
    throw new Error('unsupported --mode "' + opts.mode + '". Use all, baseline, ablate, or watch. For report recovery use node recover.js.');
}

function printHelp() {
    console.log(fs.readFileSync(__filename, 'utf8').split('\n').filter(l => l.startsWith('//')).slice(0, 12).join('\n'));
}

async function main() {
    const opts = parseArgs();
    applyModeDefaults(opts);

    fs.mkdirSync(REPORT_ROOT, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const reportDir = path.join(REPORT_ROOT, stamp);
    const screenshotDir = path.join(reportDir, 'screenshots');
    const videoDir = path.join(reportDir, 'videos');
    fs.mkdirSync(screenshotDir, { recursive: true });
    fs.mkdirSync(videoDir, { recursive: true });

    // 增量持久化路径：partial.json 在每个 ablation 完成后立即覆写
    // 一次崩溃最多丢 1 个 ablation 的数据，剩余已落盘。recover 模式可读它生成报表。
    const partialJsonPath = path.join(reportDir, 'partial.json');
    const metaPath = path.join(reportDir, 'meta.json');

    let scenarios = loadModulesFromDir(path.join(__dirname, 'scenarios'));
    let ablations = loadModulesFromDir(path.join(__dirname, 'ablations'));
    // baseline 永远第一个
    ablations.sort((a, b) => (a.name === 'baseline' ? -1 : b.name === 'baseline' ? 1 : 0));

    if (opts.onlyScenario) scenarios = scenarios.filter(s => s.name === opts.onlyScenario);
    if (opts.onlyAblation) ablations = ablations.filter(a => a.name === opts.onlyAblation || a.name === 'baseline');

    if (scenarios.length === 0) { console.error('no scenarios match'); process.exit(2); }
    if (ablations.length === 0) { console.error('no ablations match'); process.exit(2); }

    console.log(`[harness] scenarios=${scenarios.map(s=>s.name).join(',')}`);
    console.log(`[harness] ablations=${ablations.map(a=>a.name).join(',')}`);
    console.log(`[harness] sampleMs=${opts.sampleMs} warmupMs=${opts.warmupMs} repeats=${opts.repeats} dryRun=${opts.dryRun}`);
    console.log(`[harness] reportDir=${reportDir}`);

    const srv = await startServer(ROOT);
    console.log(`[harness] static server: ${srv.url}`);

    const browser = await chromium.launch({
        headless: opts.headless,
        args: [
            // 解除 vsync 上限：rAF 间隔反映真实帧工作量而非 1/refresh
            '--disable-gpu-vsync',
            '--disable-frame-rate-limit',
            // 强制硬件加速路径（ANGLE/D3D11 ≈ WebView2）
            '--use-angle=d3d11',
            '--enable-gpu-rasterization',
            '--ignore-gpu-blocklist',
            // 避免 headless 在后台被节流
            '--disable-features=CalculateNativeWinOcclusion',
            '--disable-renderer-backgrounding',
            '--disable-backgrounding-occluded-windows',
            '--disable-background-timer-throttling',
        ],
    });

    fs.writeFileSync(metaPath, JSON.stringify({
        startedAt: new Date().toISOString(),
        opts,
        scenarios: scenarios.map(s => s.name),
        ablations: ablations.map(a => a.name),
    }, null, 2));

    const allRows = [];
    function flushPartial() {
        try { fs.writeFileSync(partialJsonPath, JSON.stringify(allRows, null, 2)); }
        catch (e) { console.error('[harness] partial.json write failed:', e.message); }
    }

    try {
        for (const scenario of scenarios) {
            // 在 baseline 之外的 ablation 顺序随机化，抵消序列依赖（GC / 缓存阶段性行为）
            const baselineFirst = ablations.find(a => a.name === 'baseline');
            const others = ablations.filter(a => a.name !== 'baseline');
            for (let i = others.length - 1; i > 0; i--) {
                const j = Math.floor(Math.random() * (i + 1));
                [others[i], others[j]] = [others[j], others[i]];
            }
            const ordered = baselineFirst ? [baselineFirst, ...others] : others;
            for (const ablation of ordered) {
                const t0 = Date.now();
                process.stdout.write(`[run] ${scenario.name} × ${ablation.name} ... `);
                const r = await runOne(browser, srv.url, scenario, ablation, {
                    sampleMs: opts.sampleMs,
                    warmupMs: opts.warmupMs,
                    repeats: opts.repeats,
                    dryRun: opts.dryRun,
                    settleMs: opts.settleMs,
                    screenshotDir,
                    videoDir: opts.videos ? videoDir : null,
                    reportDir,
                });
                const dt = Date.now() - t0;
                if (r.error) {
                    console.log(`ERROR (${dt}ms): ${r.error}`);
                } else {
                    const c = r.result.cdp || {};
                    const cpuPerSec = (c.TaskDuration || 0) / Math.max(0.001, (r.result.sampleMs || 1) / 1000);
                    const cv = r.result.taskDurationCV || 0;
                    console.log(`cpu/s=${cpuPerSec.toFixed(3)} cv=${cv} runs=${r.result.runs || 1} (${dt}ms)`);
                }
                allRows.push(toRow(r));
                flushPartial();
            }
        }
    } finally {
        await browser.close();
        await stopServer(srv);
    }

    const jsonOut = path.join(reportDir, 'summary.json');
    const mdOut = path.join(reportDir, 'summary.md');
    const htmlOut = path.join(reportDir, 'visual-diff.html');
    writeJson(allRows, jsonOut);
    writeMarkdown(allRows, mdOut);
    writeVisualHtml(allRows, htmlOut);

    console.log('');
    console.log(`[harness] JSON : ${jsonOut}`);
    console.log(`[harness] MD   : ${mdOut}`);
    console.log(`[harness] HTML : ${htmlOut}`);
    console.log(`[harness] open the HTML in a browser for visual triage.`);
}

main().catch(e => { console.error(e); process.exit(1); });
