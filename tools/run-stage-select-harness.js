#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        viewport: '1366x768',
        caseId: '',
        headed: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--browser') {
            args.browser = argv[i + 1] || 'edge';
            i += 1;
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || '1366x768';
            i += 1;
        } else if (arg === '--case') {
            args.caseId = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--headed') {
            args.headed = true;
        } else if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        } else {
            printHelp(1, 'unknown arg: ' + arg);
            return null;
        }
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/run-stage-select-harness.js [--browser edge|chrome] [--viewport 1366x768] [--case <id>] [--headed]');
    process.exit(exitCode);
}

function findBrowser(name) {
    const candidates = name === 'chrome' ? [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ] : [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    for (let i = 0; i < candidates.length; i += 1) {
        if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    }
    throw new Error('Cannot find ' + name + ' executable.');
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    return {
        width: match ? Number(match[1]) : 1366,
        height: match ? Number(match[2]) : 768
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const { chromium } = require(playwrightModule);
    const executablePath = findBrowser(args.browser);
    const viewport = parseViewport(args.viewport);
    const harnessPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'stage-select', 'dev', 'harness.html');
    const query = new URLSearchParams({ qa: '1', viewport: args.viewport });
    if (args.caseId) query.set('case', args.caseId);
    const { server, origin } = await require('./lib/stage-select-dev-server').startServer(path.join(projectRoot, 'launcher/web'));
    const url = origin + '/modules/stage-select/dev/harness.html?' + query.toString();

    const browser = await chromium.launch({
        executablePath,
        headless: !args.headed,
        args: []
    });
    const page = await browser.newPage({ viewport });
    const failedRequests = [];
    const cancelledRequests = [];
    const pageErrors = [];
    page.on('requestfailed', request => {
        const failure = request.failure();
        const text = request.url() + ' :: ' + (failure && failure.errorText || 'failed');
        // 快速切换地图或关闭浏览器会取消已被替换的图片请求；单独保留，区别于加载失败。
        if (request.resourceType() === 'image' && failure && failure.errorText === 'net::ERR_ABORTED') cancelledRequests.push(text);
        else failedRequests.push(text);
    });
    page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({
        status: 204,
        headers: { 'access-control-allow-origin': '*' },
        body: ''
    }));

    await page.goto(url, { waitUntil: 'load' });
    await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa, null, { timeout: 20000 });
    const result = await page.evaluate(() => window.__qaResult.qa);
    const brokenImages = await page.evaluate(() => Array.from(document.images)
        .filter(img => img.currentSrc && (!img.complete || img.naturalWidth === 0))
        .map(img => img.currentSrc));
    await browser.close();
    server.close();

    const payload = {
        browser: args.browser,
        executablePath,
        viewport: args.viewport,
        qa: result,
        failedRequests,
        cancelledRequests,
        brokenImages,
        pageErrors
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
    if (!result || result.failed || failedRequests.length || brokenImages.length || pageErrors.length) {
        process.exit(1);
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
