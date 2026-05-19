'use strict';

// Headless map harness QA runner：用 launcher/perf 自带的 playwright + http server
// 跑 map harness QA suite (map-ui1~24)，作为离线视觉/逻辑回归门控。
//
// 用法：node tools/run-map-harness-headless.js
//   可选 --case=map-ui10 仅跑单条；--keep-open 保留窗口（headed 调试）；
//   --timeout=120000 调整等待 ms
//
// 注意：必须从 repo root 服务而非 launcher/web，否则 map-panel.js resolveAssetUrl
// 找不到 /launcher/web/ marker，把 'assets/map/...' 解析为页面相对路径 (e.g.
// /modules/map/dev/assets/...) 而 404；roommate 头像就会渲染成 is-missing。

const path = require('path');
const { chromium } = require(path.join(__dirname, '..', 'launcher', 'perf', 'node_modules', 'playwright'));
const { startServer, stopServer } = require(path.join(__dirname, '..', 'launcher', 'perf', 'lib', 'server'));

const REPO_ROOT = path.resolve(__dirname, '..');

function parseArgs() {
    const args = process.argv.slice(2);
    const out = { case: '', headless: true, timeout: 120000 };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a.startsWith('--case=')) out.case = a.slice(7);
        else if (a === '--keep-open') out.headless = false;
        else if (a.startsWith('--timeout=')) out.timeout = Number(a.slice(10));
    }
    return out;
}

async function main() {
    const opts = parseArgs();
    const serverHandle = await startServer(REPO_ROOT, 0);
    const harnessUrl = serverHandle.url + 'launcher/web/modules/map/dev/harness.html?qa=1' + (opts.case ? '&case=' + encodeURIComponent(opts.case) : '');
    console.log('[map-harness] server', serverHandle.url);
    console.log('[map-harness] navigate', harnessUrl);

    const browser = await chromium.launch({ headless: opts.headless });
    const context = await browser.newContext({ viewport: { width: 1600, height: 900 } });
    const page = await context.newPage();

    page.on('pageerror', err => console.error('[page-error]', err.message));
    page.on('console', msg => {
        if (msg.type() === 'error' || msg.type() === 'warning') {
            console.log('[' + msg.type() + ']', msg.text());
        }
    });

    let bundle = null;
    try {
        await page.goto(harnessUrl, { waitUntil: 'load', timeout: 30000 });
        bundle = await page.waitForFunction(
            () => (window.__qaResult && window.__qaResult.qa) ? window.__qaResult.qa : null,
            { timeout: opts.timeout, polling: 250 }
        );
        bundle = await bundle.jsonValue();
    } catch (err) {
        console.error('[map-harness] error waiting for QA bundle:', err.message);
        const dump = await page.evaluate(() => {
            try {
                return {
                    qaResultExists: !!window.__qaResult,
                    qa: window.__qaResult ? window.__qaResult.qa : null,
                    logsTail: window.__qaResult ? (window.__qaResult.logs || []).slice(-5) : []
                };
            } catch (e) { return { evalErr: String(e) }; }
        });
        console.error('[map-harness] dump', JSON.stringify(dump, null, 2));
    }

    if (!opts.headless) {
        console.log('[map-harness] keep-open mode: press Ctrl+C to exit');
        await new Promise(() => {});
    }

    await browser.close();
    await stopServer(serverHandle);

    if (!bundle) {
        console.error('[map-harness] no QA bundle obtained');
        process.exit(2);
    }

    console.log('\n[map-harness] ' + bundle.passed + '/' + bundle.total + ' passed (failed=' + bundle.failed + ')');
    for (const item of bundle.results) {
        const mark = item.pass ? 'PASS' : 'FAIL';
        console.log('  ' + mark + ' ' + item.id + ' ' + item.title + (item.detail ? ' :: ' + item.detail : ''));
    }

    process.exit(bundle.failed > 0 ? 1 : 0);
}

main().catch(err => {
    console.error('[map-harness] fatal', err);
    process.exit(3);
});
