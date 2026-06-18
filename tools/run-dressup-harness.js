#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const perfRoot = path.join(projectRoot, 'launcher', 'perf');
const playwrightModule = path.join(perfRoot, 'node_modules', 'playwright');

function parseArgs(argv) {
    const args = {
        browser: 'edge',
        viewport: '1280x720',
        sample: 'animated',
        manifest: '',
        skinKey: '',
        field: '',
        gender: '',
        shot: '',
        headed: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        if (arg === '--browser') {
            args.browser = argv[i + 1] || 'edge';
            i += 1;
        } else if (arg === '--viewport') {
            args.viewport = argv[i + 1] || '1280x720';
            i += 1;
        } else if (arg === '--sample') {
            args.sample = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--manifest') {
            args.manifest = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--skin-key') {
            args.skinKey = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--field') {
            args.field = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--gender') {
            args.gender = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--shot') {
            args.shot = argv[i + 1] || '';
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
    console.error('usage: node tools/run-dressup-harness.js [--browser edge|chrome] [--viewport 1280x720] [--sample animated|nested|nested-a] [--skin-key <key>] [--field 身体] [--gender 男|女] [--manifest assets/dressup/manifest.json] [--shot <png>] [--headed]');
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
        width: match ? Number(match[1]) : 1280,
        height: match ? Number(match[2]) : 720
    };
}

function mimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.js') return 'application/javascript; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
    if (ext === '.svg') return 'image/svg+xml; charset=utf-8';
    if (ext === '.woff2') return 'font/woff2';
    return 'application/octet-stream';
}

function createStaticServer(rootDir) {
    const server = http.createServer((req, res) => {
        const rawPath = (req.url || '/').split('?')[0] || '/';
        const decoded = decodeURIComponent(rawPath);
        const safeRel = decoded.replace(/^\/+/, '').replace(/\//g, path.sep);
        const filePath = path.resolve(rootDir, safeRel || 'overlay.html');
        if (!filePath.startsWith(rootDir)) {
            res.writeHead(403);
            res.end('forbidden');
            return;
        }
        fs.stat(filePath, (statErr, stat) => {
            if (statErr || !stat.isFile()) {
                res.writeHead(404);
                res.end('not found');
                return;
            }
            res.writeHead(200, { 'content-type': mimeType(filePath) });
            fs.createReadStream(filePath).pipe(res);
        });
    });
    return new Promise((resolve, reject) => {
        server.on('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

function canvasProbeScript() {
    return () => {
        const canvas = document.querySelector('.dressup-canvas');
        if (!canvas || !canvas.width || !canvas.height) return null;
        const ctx = canvas.getContext('2d');
        const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
        let alphaPixels = 0;
        let hash = 2166136261;
        for (let i = 0; i < data.length; i += 4) {
            const alpha = data[i + 3] || 0;
            if (alpha > 8) alphaPixels += 1;
            hash ^= data[i] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= data[i + 1] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= data[i + 2] || 0;
            hash = Math.imul(hash, 16777619) >>> 0;
            hash ^= alpha;
            hash = Math.imul(hash, 16777619) >>> 0;
        }
        return {
            width: canvas.width,
            height: canvas.height,
            alphaPixels,
            hash
        };
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
    const server = await createStaticServer(webRoot);
    const port = server.address().port;
    const query = new URLSearchParams();
    if (args.sample && !args.skinKey) query.set('sample', args.sample);
    if (args.manifest) query.set('manifest', args.manifest);
    if (args.skinKey) query.set('skinKey', args.skinKey);
    if (args.field) query.set('field', args.field);
    if (args.gender) query.set('gender', args.gender);
    const url = `http://127.0.0.1:${port}/modules/dressup/dev/panel-harness.html?${query.toString()}`;

    const failedRequests = [];
    const pageErrors = [];
    const consoleLogs = [];
    let browser = null;

    try {
        browser = await chromium.launch({
            executablePath,
            headless: !args.headed
        });
        const page = await browser.newPage({ viewport });
        page.on('requestfailed', request => {
            const failure = request.failure();
            if (/^https?:\/\/cfn-fonts\.local\//i.test(request.url())) return;
            failedRequests.push(request.url() + ' :: ' + ((failure && failure.errorText) || 'failed'));
        });
        page.on('pageerror', error => pageErrors.push(error && error.message ? error.message : String(error)));
        page.on('console', msg => consoleLogs.push(msg.type() + ': ' + msg.text()));
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({
            status: 204,
            headers: { 'access-control-allow-origin': '*' },
            body: ''
        }));

        await page.goto(url, { waitUntil: 'load' });
        await page.waitForSelector('.dressup-panel', { timeout: 20000 });
        await page.waitForFunction(canvasProbeScript(), null, { timeout: 20000 });
        await page.waitForFunction(() => {
            const status = document.querySelector('.dressup-status');
            return status && status.textContent && status.textContent.indexOf('"holders"') >= 0;
        }, null, { timeout: 20000 });
        await page.waitForFunction(() => {
            const canvas = document.querySelector('.dressup-canvas');
            if (!canvas || !canvas.width || !canvas.height) return false;
            const ctx = canvas.getContext('2d');
            const data = ctx.getImageData(0, 0, canvas.width, canvas.height).data;
            for (let i = 3; i < data.length; i += 16) {
                if (data[i] > 8) return true;
            }
            return false;
        }, null, { timeout: 20000 });

        const firstProbe = await page.evaluate(canvasProbeScript());
        await page.waitForTimeout(650);
        const secondProbe = await page.evaluate(canvasProbeScript());
        const statusText = await page.locator('.dressup-status').innerText();
        const headerText = await page.locator('.dressup-header-status').innerText();
        const status = JSON.parse(statusText);
        const animationChanged = firstProbe && secondProbe && firstProbe.hash !== secondProbe.hash;
        if (args.shot) {
            const shotPath = path.resolve(projectRoot, args.shot);
            fs.mkdirSync(path.dirname(shotPath), { recursive: true });
            await page.screenshot({ path: shotPath, fullPage: true });
        }
        await browser.close();
        browser = null;

        const qa = {
            failed: false,
            url,
            viewport: args.viewport,
            headerText,
            firstProbe,
            secondProbe,
            animationChanged,
            status
        };
        if (!firstProbe || firstProbe.alphaPixels < 500) {
            qa.failed = true;
            qa.reason = 'canvas appears blank';
        } else if ((args.sample === 'animated' || args.sample === 'nested' || args.sample === 'nested-a' || args.skinKey) && !animationChanged) {
            qa.failed = true;
            qa.reason = (args.skinKey || args.sample) + ' sample did not change canvas hash';
        } else if (args.gender && status.gender !== args.gender) {
            qa.failed = true;
            qa.reason = 'gender was not applied';
        } else if (args.skinKey && (!status.keyMap || status.keyMap[args.field || '身体'] !== args.skinKey)) {
            qa.failed = true;
            qa.reason = 'skin-key was not applied to keyMap';
        }

        const payload = {
            browser: args.browser,
            executablePath,
            qa,
            failedRequests,
            pageErrors,
            consoleLogs: consoleLogs.slice(-30)
        };
        process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
        if (qa.failed || failedRequests.length || pageErrors.length) {
            process.exit(1);
        }
    } finally {
        if (browser) await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
}

main().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(1);
});
