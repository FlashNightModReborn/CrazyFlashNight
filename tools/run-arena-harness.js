#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');
const serverModule = path.join(perfRoot, 'lib', 'server');

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        viewport: '1600x900',
        caseId: '',
        headed: false,
        timeout: 120000
    };

    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (!arg) continue;
        if (arg === '--browser') {
            args.browser = argv[i + 1] || args.browser;
            i += 1;
        } else if (arg.indexOf('--browser=') === 0) {
            args.browser = arg.slice(10) || args.browser;
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || args.viewport;
            i += 1;
        } else if (arg.indexOf('--viewport=') === 0) {
            args.viewport = arg.slice(11) || args.viewport;
        } else if (arg === '--case') {
            args.caseId = argv[i + 1] || '';
            i += 1;
        } else if (arg.indexOf('--case=') === 0) {
            args.caseId = arg.slice(7);
        } else if (arg === '--timeout') {
            args.timeout = Number(argv[i + 1] || args.timeout);
            i += 1;
        } else if (arg.indexOf('--timeout=') === 0) {
            args.timeout = Number(arg.slice(10) || args.timeout);
        } else if (arg === '--headed') {
            args.headed = true;
        } else if (arg === '--help' || arg === '-h') {
            printHelp(0);
            return null;
        } else if (!args.caseId && arg.indexOf('--') !== 0) {
            args.caseId = arg;
        } else {
            printHelp(1, 'unknown arg: ' + arg);
            return null;
        }
    }

    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/run-arena-harness.js [--browser edge|chrome] [--viewport 1600x900] [--case <id>] [--timeout <ms>] [--headed]');
    process.exit(exitCode);
}

function findBrowser(name) {
    const candidates = (name === 'chrome' ? [
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe')
    ] : [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ]).filter(Boolean);

    for (let i = 0; i < candidates.length; i += 1) {
        if (candidates[i] && fs.existsSync(candidates[i])) return candidates[i];
    }
    throw new Error('Cannot find ' + name + ' executable.');
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    return {
        width: match ? Number(match[1]) : 1600,
        height: match ? Number(match[2]) : 900
    };
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!args) return;
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }

    const { chromium } = require(playwrightModule);
    const { startServer, stopServer } = require(serverModule);
    const executablePath = findBrowser(args.browser);
    const viewport = parseViewport(args.viewport);
    const serverHandle = await startServer(projectRoot, 0);
    const query = new URLSearchParams({ qa: '1', viewport: args.viewport });
    if (args.caseId) query.set('case', args.caseId);
    const url = serverHandle.url + 'launcher/web/modules/arena/dev/harness.html?' + query.toString();

    const browser = await chromium.launch({
        executablePath,
        headless: !args.headed
    });
    const page = await browser.newPage({ viewport });
    const failedRequests = [];
    const httpErrors = [];
    const pageErrors = [];
    const consoleErrors = [];
    let bundle = null;

    page.on('requestfailed', request => {
        const failure = request.failure();
        failedRequests.push(request.url() + ' :: ' + (failure && failure.errorText || 'failed'));
    });
    page.on('response', response => {
        if (response.status() >= 400) {
            httpErrors.push(response.status() + ' ' + response.url());
        }
    });
    page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
    page.on('console', msg => {
        if (msg.type() === 'error' && msg.text().indexOf('Failed to load resource') < 0) {
            consoleErrors.push(msg.text());
        }
    });
    await page.route('**/favicon.ico', route => route.fulfill({
        status: 204,
        headers: { 'access-control-allow-origin': '*' },
        body: ''
    }));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({
        status: 204,
        headers: { 'access-control-allow-origin': '*' },
        body: ''
    }));

    try {
        await page.goto(url, { waitUntil: 'load', timeout: 30000 });
        const handle = await page.waitForFunction(
            () => (window.__qaResult && window.__qaResult.qa) ? window.__qaResult.qa : null,
            null,
            { timeout: args.timeout, polling: 250 }
        );
        bundle = await handle.jsonValue();
    } catch (error) {
        const dump = await page.evaluate(() => {
            try {
                return {
                    qaResult: window.__qaResult || null,
                    title: document.title,
                    status: document.getElementById('harness-status') ? document.getElementById('harness-status').textContent : ''
                };
            } catch (e) {
                return { error: String(e) };
            }
        }).catch(() => null);
        console.error('[arena-harness] wait failed:', error && error.message ? error.message : String(error));
        console.error('[arena-harness] dump:', JSON.stringify(dump, null, 2));
    } finally {
        await browser.close();
        await stopServer(serverHandle);
    }

    if (!bundle) {
        process.exit(2);
    }

    console.log('[arena-harness] ' + bundle.passed + '/' + bundle.total + ' passed (failed=' + bundle.failed + ')');
    (bundle.results || []).forEach(item => {
        const mark = item.pass ? 'PASS' : 'FAIL';
        console.log('  ' + mark + ' ' + item.id + ' ' + item.title + (item.detail ? ' :: ' + item.detail : ''));
    });

    if (pageErrors.length) console.error('[arena-harness] page errors:\n' + pageErrors.join('\n'));
    if (consoleErrors.length) console.error('[arena-harness] console errors:\n' + consoleErrors.join('\n'));
    if (failedRequests.length) console.error('[arena-harness] failed requests:\n' + failedRequests.join('\n'));
    if (httpErrors.length) console.error('[arena-harness] http errors:\n' + httpErrors.join('\n'));

    const failed = (bundle.failed || 0) + pageErrors.length + consoleErrors.length + failedRequests.length + httpErrors.length;
    process.exit(failed ? 1 : 0);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
