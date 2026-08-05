#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const playwrightModule = path.join(projectRoot, 'launcher', 'perf', 'node_modules', 'playwright');

function parseArgs(argv) {
    const args = { browser: 'edge', viewport: '1366x768', headed: false };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--browser') {
            args.browser = argv[i + 1] || 'edge';
            i += 1;
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || '1366x768';
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
    if (args.browser !== 'edge' && args.browser !== 'chrome') {
        printHelp(1, 'browser must be edge or chrome');
        return null;
    }
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/run-bootstrap-harness.js [--browser edge|chrome] [--viewport 1366x768] [--headed]');
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
    const executable = candidates.find(candidate => fs.existsSync(candidate));
    if (!executable) throw new Error('Cannot find ' + name + ' executable.');
    return executable;
}

function parseViewport(value) {
    const match = String(value || '').match(/^(\d+)x(\d+)$/);
    if (!match) throw new Error('viewport must use WIDTHxHEIGHT, for example 1366x768');
    return { width: Number(match[1]), height: Number(match[2]) };
}

function contentType(filePath) {
    const types = {
        '.html': 'text/html; charset=utf-8',
        '.css': 'text/css; charset=utf-8',
        '.js': 'text/javascript; charset=utf-8',
        '.mjs': 'text/javascript; charset=utf-8',
        '.json': 'application/json; charset=utf-8',
        '.svg': 'image/svg+xml',
        '.png': 'image/png',
        '.jpg': 'image/jpeg',
        '.jpeg': 'image/jpeg',
        '.webp': 'image/webp',
        '.woff2': 'font/woff2',
        '.mp4': 'video/mp4',
        '.bin': 'application/octet-stream'
    };
    return types[path.extname(filePath).toLowerCase()] || 'application/octet-stream';
}

function startServer() {
    const server = http.createServer((request, response) => {
        try {
            const requestUrl = new URL(request.url, 'http://127.0.0.1');
            const relativePath = decodeURIComponent(requestUrl.pathname).replace(/^\/+/, '');
            const filePath = path.resolve(webRoot, relativePath || 'bootstrap.html');
            if (filePath !== webRoot && !filePath.startsWith(webRoot + path.sep)) {
                response.writeHead(403).end('forbidden');
                return;
            }
            if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
                response.writeHead(404).end('not found');
                return;
            }
            const body = fs.readFileSync(filePath);
            const send = () => {
                response.writeHead(200, {
                    'content-type': contentType(filePath),
                    'cache-control': 'no-store'
                });
                response.end(body);
            };
            // 强制 list_resp 先于 PM19 的异步种子加载完成，稳定覆盖晚订阅重放路径。
            if (requestUrl.pathname === '/modules/assets/pm19/seed-bank.json') setTimeout(send, 150);
            else send();
        } catch (error) {
            response.writeHead(500).end(String(error));
        }
    });
    return new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function closeServer(server) {
    if (!server) return;
    await new Promise(resolve => server.close(resolve));
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
    const server = await startServer();
    const port = server.address().port;
    let browser = null;
    const checks = [];
    const failedRequests = [];
    const pageErrors = [];
    const consoleLogs = [];

    async function check(id, action) {
        try {
            const detail = await action();
            checks.push({ id, passed: true, detail: detail == null ? '' : detail });
        } catch (error) {
            checks.push({ id, passed: false, detail: error && error.message ? error.message : String(error) });
        }
    }

    try {
        browser = await chromium.launch({ executablePath, headless: !args.headed });
        const page = await browser.newPage({ viewport });
        await page.emulateMedia({ reducedMotion: 'reduce' });
        page.on('requestfailed', request => {
            const failure = request.failure();
            failedRequests.push(request.url() + ' :: ' + (failure && failure.errorText || 'failed'));
        });
        page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
        page.on('console', message => consoleLogs.push(message.type() + ': ' + message.text()));
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({
            status: 204,
            headers: { 'access-control-allow-origin': '*' },
            body: ''
        }));
        await page.addInitScript(() => {
            const listeners = [];
            const events = [];
            const emit = payload => {
                events.push({ direction: 'in', cmd: payload.cmd, at: performance.now() });
                const event = { data: JSON.stringify(payload) };
                listeners.slice().forEach(listener => listener(event));
            };
            const webview = {
                addEventListener(type, listener) {
                    if (type === 'message') listeners.push(listener);
                },
                postMessage(raw) {
                    const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
                    events.push({ direction: 'out', cmd: message.cmd, at: performance.now() });
                    if (message.cmd === 'list') {
                        setTimeout(() => {
                            emit({
                                cmd: 'list_resp', slots: [], introEnabled: false,
                                sfxEnabled: false, ambientEnabled: false, uiFontScale: 1.35
                            });
                            emit({ cmd: 'state', state: 'Ready', msg: 'harness-ready' });
                            emit({ cmd: 'flash_ready' });
                        }, 0);
                    } else if (message.cmd === 'fontpack_status') {
                        setTimeout(() => emit({ cmd: 'fontpack_status_resp', ok: true, groups: [] }), 0);
                    }
                }
            };
            window.chrome = window.chrome || {};
            window.chrome.webview = webview;
            window.__bootstrapHarnessEvents = events;
        });

        await page.goto('http://127.0.0.1:' + port + '/bootstrap.html', { waitUntil: 'load' });

        await check('host-list-response', async () => {
            await page.waitForFunction(() => document.querySelectorAll('#cards .card').length === 10, null, { timeout: 10000 });
            const events = await page.evaluate(() => window.__bootstrapHarnessEvents.slice());
            if (!events.some(event => event.direction === 'in' && event.cmd === 'list_resp')) {
                throw new Error('host list_resp was not delivered');
            }
            return '10 preset cards rendered from a zero-delay host response';
        });

        await check('pm19-late-subscription-replay', async () => {
            await page.waitForFunction(() => {
                const log = document.getElementById('bg-gl-log');
                return log && log.textContent.includes('黑铁网络接入') && log.textContent.includes('行向量捕获开始');
            }, null, { timeout: 10000 });
            const syncCount = await page.locator('#bg-gl-log').evaluate(element =>
                (element.textContent.match(/全轨道同步 · 通路打开/g) || []).length);
            if (syncCount !== 1) throw new Error('expected one synchronized transition, got ' + syncCount);
            return 'list/state/flash_ready replayed once after delayed PM19 initialization';
        });

        await check('tooltip-binding', async () => {
            await page.locator('#btn-about').hover();
            await page.waitForTimeout(380);
            const tooltip = page.locator('.boot-tooltip.on');
            if (await tooltip.count() !== 1) throw new Error('tooltip did not become visible');
            const text = (await tooltip.textContent()) || '';
            if (!text.includes('免责声明')) throw new Error('unexpected tooltip text: ' + text);
            await page.mouse.move(1, 1);
            return text;
        });

        await check('native-button-enter', async () => {
            await page.locator('#btn-switch-slot').click();
            const button = page.locator('#cards .btn-newchar').first();
            await button.focus();
            await button.press('Enter');
            await page.waitForFunction(() => !document.getElementById('view-welcome').hidden
                && document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            const focusedCards = await page.locator('#cards .card.kb-focus').count();
            if (focusedCards !== 0) throw new Error('native Enter leaked into card-navigation focus');
            return 'focused card button activated its own action';
        });

        await check('container-keyboard-navigation', async () => {
            await page.locator('#btn-switch-slot').click();
            const cards = page.locator('#cards');
            await cards.focus();
            await cards.press('ArrowRight');
            if (await page.locator('#cards .card.kb-focus').count() !== 1) {
                throw new Error('ArrowRight did not establish one visual card focus');
            }
            await cards.press('Enter');
            await page.waitForFunction(() => !document.getElementById('view-welcome').hidden
                && document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            return 'container ArrowRight + Enter selected the focused card';
        });

        const brokenImages = await page.evaluate(() => Array.from(document.images)
            .filter(image => image.currentSrc && (!image.complete || image.naturalWidth === 0))
            .map(image => image.currentSrc));
        if (brokenImages.length) failedRequests.push('broken images: ' + brokenImages.join(', '));
    } finally {
        if (browser) await browser.close();
        await closeServer(server);
    }

    const payload = {
        browser: args.browser,
        executablePath,
        viewport: args.viewport,
        checks,
        failedRequests,
        pageErrors,
        consoleLogs
    };
    process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
    if (checks.some(check => !check.passed) || failedRequests.length || pageErrors.length) process.exit(1);
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
