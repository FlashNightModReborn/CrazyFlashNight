#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');
const serverModule = path.join(perfRoot, 'lib', 'server');

// 默认视口对齐工作台逻辑画布 1024x576（见 agentsDoc/workbench-ui-system.md）
const DEFAULT_VIEWPORT = '1024x576';

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        viewport: DEFAULT_VIEWPORT,
        viewportProvided: false,
        viewports: '',
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
        } else if (arg === '--viewports') {
            args.viewports = argv[i + 1] || args.viewports;
            i += 1;
        } else if (arg.indexOf('--viewports=') === 0) {
            args.viewports = arg.slice(12);
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || args.viewport;
            args.viewportProvided = true;
            i += 1;
        } else if (arg.indexOf('--viewport=') === 0) {
            args.viewport = arg.slice(11) || args.viewport;
            args.viewportProvided = true;
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
    console.error('usage: node tools/run-arena-harness.js [--browser edge|chrome] [--viewport 1024x576] [--viewports 1024x576,1366x768,1920x1080] [--case <id>] [--timeout <ms>] [--headed]');
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
        width: match ? Number(match[1]) : 1024,
        height: match ? Number(match[2]) : 576
    };
}

// --viewports（逗号分隔 <W>x<H>）存在时优先于 --viewport；非法条目直接失败，不静默回退
function resolveViewportSpecs(args) {
    if (!args.viewports) {
        return [Object.assign({ label: args.viewport }, parseViewport(args.viewport))];
    }
    const labels = args.viewports.split(',')
        .map(item => item.trim().toLowerCase())
        .filter(Boolean);
    const invalid = labels.filter(label => !/^\d+x\d+$/.test(label));
    if (!labels.length || invalid.length) {
        console.error('[arena-harness] invalid --viewports value: ' + args.viewports + ' (expect comma-separated <W>x<H>, e.g. 1024x576,1366x768,1920x1080)');
        process.exit(1);
    }
    return labels.map(label => Object.assign({ label }, parseViewport(label)));
}

// 单视口完整跑一遍选定 case 集合：独立 server + 独立 browser/page，返回原始结果供汇总
async function runViewportSession(deps, args, spec, logPrefix) {
    const serverHandle = await deps.startServer(projectRoot, 0);
    const query = new URLSearchParams({ qa: '1', viewport: spec.label });
    if (args.caseId) query.set('case', args.caseId);
    const url = serverHandle.url + 'launcher/web/modules/arena/dev/harness.html?' + query.toString();

    const browser = await deps.chromium.launch({
        executablePath: deps.executablePath,
        headless: !args.headed
    });
    const page = await browser.newPage({ viewport: { width: spec.width, height: spec.height } });
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
        console.error(logPrefix + 'wait failed:', error && error.message ? error.message : String(error));
        console.error(logPrefix + 'dump:', JSON.stringify(dump, null, 2));
    } finally {
        await browser.close();
        await deps.stopServer(serverHandle);
    }

    return { spec, bundle, pageErrors, consoleErrors, failedRequests, httpErrors };
}

function failureCount(session) {
    if (!session.bundle) return 0;
    return (session.bundle.failed || 0)
        + session.pageErrors.length
        + session.consoleErrors.length
        + session.failedRequests.length
        + session.httpErrors.length;
}

function reportSession(session, multi) {
    const bundle = session.bundle;
    if (!bundle) return;
    const headline = multi
        ? '[arena-harness] viewport ' + session.spec.label + ': '
        : '[arena-harness] ';
    console.log(headline + bundle.passed + '/' + bundle.total + ' passed (failed=' + bundle.failed + ')');
    (bundle.results || []).forEach(item => {
        const mark = item.pass ? 'PASS' : 'FAIL';
        console.log('  ' + mark + ' ' + item.id + ' ' + item.title + (item.detail ? ' :: ' + item.detail : ''));
    });

    const errPrefix = multi ? '[arena-harness][' + session.spec.label + '] ' : '[arena-harness] ';
    if (session.pageErrors.length) console.error(errPrefix + 'page errors:\n' + session.pageErrors.join('\n'));
    if (session.consoleErrors.length) console.error(errPrefix + 'console errors:\n' + session.consoleErrors.join('\n'));
    if (session.failedRequests.length) console.error(errPrefix + 'failed requests:\n' + session.failedRequests.join('\n'));
    if (session.httpErrors.length) console.error(errPrefix + 'http errors:\n' + session.httpErrors.join('\n'));
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
    const multi = !!args.viewports;
    if (multi && args.viewportProvided) {
        console.log('[arena-harness] both --viewport and --viewports given; --viewports takes priority, ignoring --viewport=' + args.viewport);
    }
    const specs = resolveViewportSpecs(args);
    const deps = { chromium, startServer, stopServer, executablePath };

    const sessions = [];
    for (let i = 0; i < specs.length; i += 1) {
        const spec = specs[i];
        const logPrefix = multi ? '[arena-harness][' + spec.label + '] ' : '[arena-harness] ';
        if (multi) {
            console.log('[arena-harness] === viewport ' + spec.label + ' (' + (i + 1) + '/' + specs.length + ') ===');
        }
        const session = await runViewportSession(deps, args, spec, logPrefix);
        sessions.push(session);
        reportSession(session, multi);
    }

    let noBundleCount = 0;
    let failedTotal = 0;
    let passedViewports = 0;
    sessions.forEach(session => {
        if (!session.bundle) {
            noBundleCount += 1;
            return;
        }
        if (failureCount(session) === 0) passedViewports += 1;
        failedTotal += failureCount(session);
    });

    if (multi) {
        console.log('[arena-harness] viewports ' + passedViewports + '/' + sessions.length + ' passed' + (noBundleCount ? ' (no-result=' + noBundleCount + ')' : ''));
    }

    if (noBundleCount) process.exit(2);
    process.exit(failedTotal ? 1 : 0);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
