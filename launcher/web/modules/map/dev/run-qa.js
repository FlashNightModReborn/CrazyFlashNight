#!/usr/bin/env node
'use strict';

// 用法：
//   node launcher/web/modules/map/dev/run-qa.js
//   node launcher/web/modules/map/dev/run-qa.js map-ui26
//   node launcher/web/modules/map/dev/run-qa.js --case=map-ui26
//
// 复用 launcher/perf 的 Playwright 与本地静态 server，避免 file:// 下资源解析漂移。
// 任一 QA fail、页面异常或资源请求失败都会返回非 0。

const path = require('path');
const fs = require('fs');

const repoRoot = path.resolve(__dirname, '..', '..', '..', '..', '..');
const playwrightModule = path.join(repoRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const { startServer, stopServer } = require(path.join(repoRoot, 'launcher', 'perf', 'lib', 'server'));

function parseArgs(argv) {
    const out = {
        caseId: '',
        browser: 'chromium',
        headed: false,
        timeout: 120000,
        viewport: '1600x900'
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (!arg) continue;
        if (arg === '--case') {
            out.caseId = argv[i + 1] || '';
            i += 1;
        } else if (arg.startsWith('--case=')) {
            out.caseId = arg.slice(7);
        } else if (arg === '--browser') {
            out.browser = argv[i + 1] || out.browser;
            i += 1;
        } else if (arg.startsWith('--browser=')) {
            out.browser = arg.slice(10) || out.browser;
        } else if (arg === '--headed') {
            out.headed = true;
        } else if (arg === '--timeout') {
            out.timeout = Number(argv[i + 1] || out.timeout);
            i += 1;
        } else if (arg.startsWith('--timeout=')) {
            out.timeout = Number(arg.slice(10) || out.timeout);
        } else if (arg === '--viewport') {
            out.viewport = argv[i + 1] || out.viewport;
            i += 1;
        } else if (arg.startsWith('--viewport=')) {
            out.viewport = arg.slice(11) || out.viewport;
        } else if (!out.caseId && arg.indexOf('--') !== 0) {
            out.caseId = arg;
        }
    }
    return out;
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    return {
        width: match ? Number(match[1]) : 1600,
        height: match ? Number(match[2]) : 900
    };
}

function findInstalledBrowser(name) {
    const chromeCandidates = [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ];
    const edgeCandidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    const candidates = name === 'chrome' ? chromeCandidates : edgeCandidates;
    for (let i = 0; i < candidates.length; i += 1) {
        if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    }
    return '';
}

async function main() {
    const opts = parseArgs(process.argv.slice(2));
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }

    const { chromium } = require(playwrightModule);
    const serverHandle = await startServer(repoRoot, 0);
    const query = new URLSearchParams({ qa: '1', viewport: opts.viewport });
    if (opts.caseId) query.set('case', opts.caseId);
    const url = serverHandle.url + 'launcher/web/modules/map/dev/harness.html?' + query.toString();
    const viewport = parseViewport(opts.viewport);
    const launchOptions = { headless: !opts.headed };
    const executablePath = opts.browser === 'edge' || opts.browser === 'chrome'
        ? findInstalledBrowser(opts.browser)
        : '';
    if (executablePath) launchOptions.executablePath = executablePath;

    const browser = await chromium.launch(launchOptions);
    const page = await browser.newPage({ viewport });
    const pageErrors = [];
    const consoleErrors = [];
    const failedRequests = [];

    page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
    page.on('console', msg => {
        if (msg.type() === 'error') consoleErrors.push(msg.text());
    });
    page.on('requestfailed', request => {
        const failure = request.failure();
        failedRequests.push(request.url() + ' :: ' + (failure && failure.errorText || 'failed'));
    });
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({
        status: 204,
        headers: { 'access-control-allow-origin': '*' },
        body: ''
    }));

    let bundle = null;
    try {
        await page.goto(url, { waitUntil: 'load', timeout: 30000 });
        const handle = await page.waitForFunction(
            () => (window.__qaResult && window.__qaResult.qa) ? window.__qaResult.qa : null,
            null,
            { timeout: opts.timeout, polling: 250 }
        );
        bundle = await handle.jsonValue();
    } finally {
        await browser.close();
        await stopServer(serverHandle);
    }

    if (!bundle) {
        console.error('[map-dev-qa] no QA bundle obtained');
        process.exit(2);
    }

    console.log('[map-dev-qa] ' + bundle.passed + '/' + bundle.total + ' passed (failed=' + bundle.failed + ')');
    (bundle.results || []).forEach(item => {
        const mark = item.pass ? 'PASS' : 'FAIL';
        console.log('  ' + mark + ' ' + item.id + ' ' + item.title + (item.detail ? ' :: ' + item.detail : ''));
    });

    if (pageErrors.length) console.error('[map-dev-qa] page errors:\n' + pageErrors.join('\n'));
    if (consoleErrors.length) console.error('[map-dev-qa] console errors:\n' + consoleErrors.join('\n'));
    if (failedRequests.length) console.error('[map-dev-qa] failed requests:\n' + failedRequests.join('\n'));

    const failed = (bundle.failed || 0) + pageErrors.length + consoleErrors.length + failedRequests.length;
    process.exit(failed ? 1 : 0);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
