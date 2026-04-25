// 真 WebView2 模式：连接已运行的 launcher 的 WebView2 调试端口，跑同一套场景 × ablation。
// 用途：headless Chromium 在无显示器时无法体现 GPU/合成成本（backdrop-filter / mix-blend-mode 在
// 真 iGPU 才表现压力）。本入口连真机 WebView2，给出 ground-truth 数据。
//
// 前置：
//   1. config.toml 加 `webView2AdditionalArgs = "--remote-debugging-port=9222"`
//   2. 启动游戏到 Ready 状态
//   3. 运行：node harness-webview2.js
//
// 由于 launcher 中只有一个 WebView2 实例，本入口不开新 page，而是 attach 到已存在的页面。
// ablation 通过临时注入 <style> 实现，离开时移除。
// 不会重启 panel —— 你需要手动打开要测的 panel（map/lockbox 等）后再运行此脚本。

'use strict';

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');
const { runMeasurement, attachInPageProbe } = require('./lib/metrics');
const { loadModulesFromDir } = require('./lib/runner');
const { toRow, writeJson, writeMarkdown, writeVisualHtml } = require('./lib/report');

const REPORT_ROOT = path.resolve(__dirname, 'reports-webview2');

function parseArgs() {
    const args = process.argv.slice(2);
    const out = {
        port: 9222,
        sampleMs: 4000,
        warmupMs: 800,
        scenarioHint: null,  // 真 WebView2 下场景是用户手动控制的，仅作 label
    };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a === '--port') out.port = Number(args[++i]);
        else if (a === '--sample') out.sampleMs = Number(args[++i]);
        else if (a === '--warmup') out.warmupMs = Number(args[++i]);
        else if (a === '--scenario') out.scenarioHint = args[++i];
        else if (a === '--ablation') out.onlyAblation = args[++i];
    }
    return out;
}

async function injectAblation(page, ablation) {
    if (ablation.css) {
        return await page.evaluate((css) => {
            const id = '__cf7_ablation_style';
            let el = document.getElementById(id);
            if (!el) { el = document.createElement('style'); el.id = id; document.head.appendChild(el); }
            el.textContent = css;
            return id;
        }, ablation.css);
    }
    if (ablation.js) {
        await page.evaluate(ablation.js);
    }
    return null;
}

async function clearAblation(page) {
    await page.evaluate(() => {
        const el = document.getElementById('__cf7_ablation_style');
        if (el) el.remove();
        document.documentElement.classList.remove(
            'perf-low-effects', 'perf-no-css-animations', 'perf-no-visualizers'
        );
    });
}

async function main() {
    const opts = parseArgs();
    fs.mkdirSync(REPORT_ROOT, { recursive: true });
    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const reportDir = path.join(REPORT_ROOT, stamp);
    const screenshotDir = path.join(reportDir, 'screenshots');
    fs.mkdirSync(screenshotDir, { recursive: true });

    let ablations = loadModulesFromDir(path.join(__dirname, 'ablations'));
    ablations.sort((a, b) => (a.name === 'baseline' ? -1 : b.name === 'baseline' ? 1 : 0));
    if (opts.onlyAblation) ablations = ablations.filter(a => a.name === opts.onlyAblation || a.name === 'baseline');

    console.log(`[webview2] connecting to http://localhost:${opts.port}/`);
    const browser = await chromium.connectOverCDP('http://localhost:' + opts.port);
    const contexts = browser.contexts();
    if (contexts.length === 0) { console.error('no contexts on remote'); process.exit(2); }
    const ctx = contexts[0];
    const pages = ctx.pages();
    if (pages.length === 0) { console.error('no pages in remote context'); process.exit(2); }
    const page = pages[0];
    console.log(`[webview2] attached: ${await page.url()}`);

    await attachInPageProbe(page).catch(() => { /* 可能已加载，忽略 */ });

    const client = await ctx.newCDPSession(page);
    const allRows = [];
    const scenarioLabel = opts.scenarioHint || 'manual';

    try {
        for (const ablation of ablations) {
            await clearAblation(page);
            await page.waitForTimeout(500);
            await injectAblation(page, ablation).catch(() => {});
            await page.waitForTimeout(300);

            process.stdout.write(`[run] ${scenarioLabel} × ${ablation.name} ... `);
            const result = await runMeasurement(page, client, {
                sampleMs: opts.sampleMs,
                warmupMs: opts.warmupMs,
                label: scenarioLabel + '|' + ablation.name,
            });

            const screenshotPath = path.join(screenshotDir, scenarioLabel + '__' + ablation.name + '.png');
            try { await page.screenshot({ path: screenshotPath }); } catch {}

            const row = toRow({
                scenario: scenarioLabel,
                ablation: ablation.name,
                result,
                screenshot: path.relative(reportDir, screenshotPath),
                errors: [],
            });
            console.log(`cpu/s=${row.cpuPerSec} script/s=${row.scriptPerSec} longTasks=${row.longTasks}`);
            allRows.push(row);
        }
    } finally {
        await clearAblation(page).catch(() => {});
        await browser.close().catch(() => {});
    }

    writeJson(allRows, path.join(reportDir, 'summary.json'));
    writeMarkdown(allRows, path.join(reportDir, 'summary.md'));
    writeVisualHtml(allRows, path.join(reportDir, 'visual-diff.html'));
    console.log(`[webview2] reports in ${reportDir}`);
}

main().catch(e => { console.error(e); process.exit(1); });
