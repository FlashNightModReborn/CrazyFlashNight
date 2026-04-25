// 单次试验：场景 × ablation 组合的执行单元。
// 每次启动独立 browser context 保证隔离；用同一 browser 实例减少启动开销。

'use strict';

const fs = require('fs');
const path = require('path');
const { attachInPageProbe, runMeasurement } = require('./metrics');

async function applyAblation(page, ablation) {
    // Ablation 三级：
    // 1) targetedJs: 取得页内已使用该 CSS 属性的元素，inline style 覆盖（最精确）
    // 2) css: 全局 stylesheet 注入（雷达级，可能引入 cascade 副作用）
    // 3) js: 任意 JS（如打开/激活降级类）
    if (ablation.targetedJs) {
        await page.evaluate(ablation.targetedJs);
    }
    if (ablation.css) {
        await page.addStyleTag({ content: ablation.css });
    }
    if (ablation.js) {
        await page.evaluate(ablation.js);
    }
}

// 中位数 + p25/p75（用于多次重复后取稳健代表值）
function medianStats(values) {
    if (!values.length) return { median: 0, p25: 0, p75: 0, min: 0, max: 0, n: 0 };
    const sorted = values.slice().sort((a, b) => a - b);
    const at = (q) => sorted[Math.min(sorted.length - 1, Math.max(0, Math.floor(sorted.length * q)))];
    return {
        median: at(0.5),
        p25: at(0.25),
        p75: at(0.75),
        min: sorted[0],
        max: sorted[sorted.length - 1],
        n: sorted.length,
    };
}

// 把 N 次 runMeasurement 的输出合并为单一稳健代表值。
function aggregateRuns(runs) {
    if (!runs.length) return null;
    const pick = (path) => runs.map(r => path.split('.').reduce((o, k) => o && o[k], r) || 0);
    const taskDur = medianStats(pick('cdp.TaskDuration'));
    const scriptDur = medianStats(pick('cdp.ScriptDuration'));
    const layoutCount = medianStats(pick('cdp.LayoutCount'));
    const recalcCount = medianStats(pick('cdp.RecalcStyleCount'));
    const layoutDur = medianStats(pick('cdp.LayoutDuration'));
    const recalcDur = medianStats(pick('cdp.RecalcStyleDuration'));
    const longTasks = medianStats(pick('longTasks'));
    const sampleMs = medianStats(pick('sampleMs'));
    return {
        sampleMs: sampleMs.median,
        runs: runs.length,
        taskDurationStats: taskDur,
        cdp: {
            TaskDuration: taskDur.median,
            ScriptDuration: scriptDur.median,
            LayoutCount: layoutCount.median,
            RecalcStyleCount: recalcCount.median,
            LayoutDuration: layoutDur.median,
            RecalcStyleDuration: recalcDur.median,
        },
        longTasks: longTasks.median,
        // CV：变异系数 (max-min)/median，用于评估测量稳定性
        taskDurationCV: taskDur.median > 0
            ? Number(((taskDur.max - taskDur.min) / taskDur.median).toFixed(3))
            : 0,
        // 取最后一次的 frames/trace/paintEvents 作为代表
        frames: runs[runs.length - 1].frames,
        trace: runs[runs.length - 1].trace,
        paintEvents: runs[runs.length - 1].paintEvents || 0,
    };
}

async function runOne(browser, baseUrl, scenario, ablation, options = {}) {
    const repeats = Math.max(1, options.repeats || 1);
    const captureLastVideo = !!options.videoDir;
    const ctxOpts = {
        viewport: { width: options.viewportWidth || 1600, height: options.viewportHeight || 900 },
        deviceScaleFactor: options.deviceScaleFactor || 1,
    };
    if (captureLastVideo) {
        ctxOpts.recordVideo = {
            dir: options.videoDir,
            size: { width: 1280, height: 720 },
        };
    }
    const context = await browser.newContext(ctxOpts);
    const page = await context.newPage();
    await attachInPageProbe(page);

    const consoleErrors = [];
    page.on('pageerror', e => consoleErrors.push(String(e)));
    page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
    });

    const client = await context.newCDPSession(page);

    try {
        await page.goto(baseUrl + 'overlay.html', { waitUntil: 'load', timeout: 15000 });
    } catch (e) {
        await context.close();
        return { error: 'goto: ' + String(e), scenario: scenario.name, ablation: ablation.name };
    }
    // 给模块初始化预留时间
    await page.waitForTimeout(500);

    // 先 setup 场景，再注入 ablation（因部分 ablation 需作用于场景产生的 DOM）
    if (scenario.setup) {
        try { await scenario.setup(page); } catch (e) { /* 容错：场景失败仍量基线 */ }
    }
    if (ablation && ablation.name !== 'baseline') {
        try { await applyAblation(page, ablation); } catch (e) { /* 容错 */ }
    }
    // 让 layout/合成稳定（被注入 !important 后 Blink 需要时间稳定 layer tree）
    await page.waitForTimeout(options.settleMs ?? 600);

    // Dry-run 预热：第一次跑通 V8 JIT / 字体加载 / 图片解码，结果丢弃
    if (options.dryRun) {
        try {
            await runMeasurement(page, client, {
                warmupMs: 500,
                sampleMs: Math.min(1500, options.sampleMs ?? 1500),
                label: 'dry-run',
            });
        } catch {}
        await page.waitForTimeout(200);
    }

    // 多次重复采样，事后取中位数排除单点抖动
    const runs = [];
    for (let i = 0; i < repeats; i++) {
        const r = await runMeasurement(page, client, {
            warmupMs: options.warmupMs ?? 800,
            sampleMs: options.sampleMs ?? 4000,
            label: scenario.name + '|' + ablation.name + '#' + i,
        });
        runs.push(r);
        // run 间留 GC 喘息时间
        if (i < repeats - 1) await page.waitForTimeout(200);
    }
    const result = repeats > 1 ? aggregateRuns(runs) : runs[0];

    // 截图（用于视觉验收 HTML）
    let screenshotPath = null;
    if (options.screenshotDir) {
        screenshotPath = path.join(options.screenshotDir,
            scenario.name + '__' + ablation.name + '.png');
        try {
            await page.screenshot({ path: screenshotPath, fullPage: false });
        } catch (e) { screenshotPath = null; }
    }

    // 取视频 path 必须在 close 之前，写盘在 close 之后
    let videoSource = null;
    if (options.videoDir && page.video) {
        try { videoSource = await page.video().path(); } catch { videoSource = null; }
    }
    await context.close();

    // 重命名视频到稳定路径
    let videoPath = null;
    if (videoSource && fs.existsSync(videoSource)) {
        const target = path.join(options.videoDir, scenario.name + '__' + ablation.name + '.webm');
        try { fs.renameSync(videoSource, target); videoPath = target; }
        catch { videoPath = videoSource; }
    }

    return {
        scenario: scenario.name,
        ablation: ablation.name,
        result,
        screenshot: screenshotPath ? path.relative(options.reportDir || '.', screenshotPath) : null,
        video: videoPath ? path.relative(options.reportDir || '.', videoPath) : null,
        errors: consoleErrors.slice(0, 10),
    };
}

function loadModulesFromDir(dir) {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir)
        .filter(f => f.endsWith('.js'))
        .map(f => {
            const mod = require(path.join(dir, f));
            mod._file = f;
            return mod;
        });
}

module.exports = { runOne, loadModulesFromDir, medianStats, aggregateRuns };
