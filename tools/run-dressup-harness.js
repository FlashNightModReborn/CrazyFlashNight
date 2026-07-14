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
        equipment: {},
        rig: '',
        stateLabel: '',
        initFile: '',
        skinOverrideFile: '',
        freezeMs: null,
        shot: '',
        canvasShot: '',
        sampleExplicit: false,
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
            args.sampleExplicit = true;
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
        } else if (arg === '--equip') {
            const value = argv[i + 1] || '';
            const separator = value.indexOf('=');
            if (separator <= 0 || separator === value.length - 1) {
                printHelp(1, 'invalid --equip value, expected slot=item: ' + value);
                return null;
            }
            args.equipment[value.slice(0, separator)] = value.slice(separator + 1);
            i += 1;
        } else if (arg === '--rig') {
            args.rig = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--state-label') {
            args.stateLabel = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--init-file') {
            args.initFile = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--skin-override-file') {
            args.skinOverrideFile = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--freeze-ms') {
            args.freezeMs = Number(argv[i + 1]);
            if (!Number.isFinite(args.freezeMs) || args.freezeMs < 0) {
                printHelp(1, 'invalid --freeze-ms value: ' + argv[i + 1]);
                return null;
            }
            i += 1;
        } else if (arg === '--shot') {
            args.shot = argv[i + 1] || '';
            i += 1;
        } else if (arg === '--canvas-shot') {
            args.canvasShot = argv[i + 1] || '';
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
    if (args.initFile) {
        const initPath = path.resolve(projectRoot, args.initFile);
        const init = JSON.parse(fs.readFileSync(initPath, 'utf8'));
        args.gender = args.gender || init.gender || '';
        args.rig = args.rig || init.rig || '';
        args.stateLabel = args.stateLabel || init.stateLabel || '';
        args.manifest = args.manifest || init.manifest || '';
        if (args.freezeMs === null && Number.isFinite(init.captureTimeMs)) args.freezeMs = Number(init.captureTimeMs);
        args.equipment = Object.assign({}, init.equipment || {}, args.equipment);
    }
    if (Object.keys(args.equipment).length && !args.sampleExplicit) args.sample = '';
    return args;
}

function printHelp(exitCode, error) {
    if (error) console.error(error);
    console.error('usage: node tools/run-dressup-harness.js [--browser edge|chrome] [--viewport 1280x720] [--sample animated|nested|nested-a] [--skin-key <key>] [--field 身体] [--gender 男|女] [--equip slot=item ...] [--init-file <json>] [--rig dialogue|battle] [--state-label <label>] [--freeze-ms <time>] [--manifest assets/dressup/manifest.json] [--skin-override-file <json>] [--shot <page.png>] [--canvas-shot <canvas.png>] [--headed]');
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

function isPathInside(baseDir, candidate) {
    const relative = path.relative(baseDir, candidate);
    return relative === '' || (!relative.startsWith('..' + path.sep) && relative !== '..' && !path.isAbsolute(relative));
}

function loadSkinOverrides(fileName) {
    if (!fileName) return { configPath: '', files: {} };
    const configPath = path.resolve(projectRoot, fileName);
    if (!isPathInside(projectRoot, configPath)) {
        throw new Error('Skin override config must stay inside the project root: ' + fileName);
    }
    const parsed = JSON.parse(fs.readFileSync(configPath, 'utf8'));
    const entries = parsed && parsed.overrides ? parsed.overrides : parsed;
    if (!entries || Array.isArray(entries) || typeof entries !== 'object') {
        throw new Error('Skin override config must be an object map or contain an overrides object.');
    }
    const files = {};
    Object.keys(entries).forEach(rawKey => {
        let key = String(rawKey || '').replace(/\\/g, '/').replace(/^\/+/, '');
        key = key.replace(/^assets\/dressup\//, '');
        if (!/^skins\/[^/]+\.(?:png|webp|jpe?g)$/i.test(key)) {
            throw new Error('Invalid dressup skin override key: ' + rawKey);
        }
        const filePath = path.resolve(projectRoot, String(entries[rawKey] || ''));
        if (!isPathInside(projectRoot, filePath)) {
            throw new Error('Skin override asset must stay inside the project root: ' + entries[rawKey]);
        }
        if (!fs.existsSync(filePath) || !fs.statSync(filePath).isFile()) {
            throw new Error('Skin override asset does not exist: ' + entries[rawKey]);
        }
        files[key] = filePath;
    });
    return { configPath, files };
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
    const skinOverrides = loadSkinOverrides(args.skinOverrideFile);
    const overrideHits = {};
    const server = await createStaticServer(webRoot);
    const port = server.address().port;
    const query = new URLSearchParams();
    if (args.sample && !args.skinKey) query.set('sample', args.sample);
    if (args.manifest) query.set('manifest', args.manifest);
    if (args.skinKey) query.set('skinKey', args.skinKey);
    if (args.field) query.set('field', args.field);
    if (args.gender) query.set('gender', args.gender);
    const injected = {};
    if (Object.keys(args.equipment).length) injected.equipment = args.equipment;
    if (args.rig) injected.rig = args.rig;
    if (args.stateLabel) injected.stateLabel = args.stateLabel;
    if (Object.keys(injected).length) query.set('init', JSON.stringify(injected));
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
        if (Object.keys(skinOverrides.files).length) {
            await page.route('**/assets/dressup/skins/**', route => {
                const requestUrl = new URL(route.request().url());
                const marker = '/assets/dressup/';
                const pathname = decodeURIComponent(requestUrl.pathname).replace(/\\/g, '/');
                const markerIndex = pathname.indexOf(marker);
                const key = markerIndex >= 0 ? pathname.slice(markerIndex + marker.length) : '';
                const overridePath = skinOverrides.files[key];
                if (!overridePath) return route.continue();
                overrideHits[key] = (overrideHits[key] || 0) + 1;
                return route.fulfill({ path: overridePath });
            });
        }
        if (args.freezeMs !== null) {
            await page.addInitScript(fixedMs => {
                Object.defineProperty(window.performance, 'now', {
                    configurable: true,
                    value: function() { return fixedMs; }
                });
            }, args.freezeMs);
        }
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
        if (args.freezeMs !== null) {
            // Renderer 内部的 image.onload 会重绘 Canvas，但不会再次刷新 Panel
            // status；因此不能拿初次 render 的 pendingImages 当完成门。冻结时等
            // 网络静默，确保当前固定帧的本地 PNG 请求与重绘都已收口。
            await page.waitForLoadState('networkidle', { timeout: 20000 });
        }
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
        const expectsAnimation = args.freezeMs === null
            && (args.sample === 'animated' || args.sample === 'nested' || args.sample === 'nested-a' || args.skinKey);
        let secondProbe = firstProbe;
        const probeAttempts = expectsAnimation ? 12 : 1;
        for (let attempt = 0; attempt < probeAttempts; attempt += 1) {
            await page.waitForTimeout(expectsAnimation ? 150 : 100);
            secondProbe = await page.evaluate(canvasProbeScript());
            if (firstProbe && secondProbe && firstProbe.hash !== secondProbe.hash) break;
        }
        const statusText = await page.locator('.dressup-status').innerText();
        const headerText = await page.locator('.dressup-header-status').innerText();
        const status = JSON.parse(statusText);
        const animationChanged = firstProbe && secondProbe && firstProbe.hash !== secondProbe.hash;
        if (args.shot) {
            const shotPath = path.resolve(projectRoot, args.shot);
            fs.mkdirSync(path.dirname(shotPath), { recursive: true });
            await page.screenshot({ path: shotPath, fullPage: true });
        }
        if (args.canvasShot) {
            const canvasShotPath = path.resolve(projectRoot, args.canvasShot);
            fs.mkdirSync(path.dirname(canvasShotPath), { recursive: true });
            const dataUrl = await page.locator('.dressup-canvas').evaluate(canvas => canvas.toDataURL('image/png'));
            fs.writeFileSync(canvasShotPath, Buffer.from(dataUrl.split(',', 2)[1], 'base64'));
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
        } else if (expectsAnimation && !animationChanged) {
            qa.failed = true;
            qa.reason = (args.skinKey || args.sample) + ' sample did not change canvas hash';
        } else if (args.gender && status.gender !== args.gender) {
            qa.failed = true;
            qa.reason = 'gender was not applied';
        } else if (!status.equipment || Object.keys(args.equipment).some(slot => status.equipment[slot] !== args.equipment[slot])) {
            qa.failed = true;
            qa.reason = 'equipment selection was not applied';
        } else if (Object.keys(args.equipment).length && status.missing !== 0) {
            qa.failed = true;
            qa.reason = 'equipment render has missing holders';
        } else if (args.rig && status.rig !== args.rig) {
            qa.failed = true;
            qa.reason = 'rig was not applied';
        } else if (args.stateLabel && status.stateLabel !== args.stateLabel) {
            qa.failed = true;
            qa.reason = 'state label was not applied';
        } else if (args.skinKey && (!status.keyMap || status.keyMap[args.field || '身体'] !== args.skinKey)) {
            qa.failed = true;
            qa.reason = 'skin-key was not applied to keyMap';
        }

        const missingOverrideKeys = Object.keys(skinOverrides.files).filter(key => !overrideHits[key]);
        if (!qa.failed && missingOverrideKeys.length) {
            qa.failed = true;
            qa.reason = 'skin overrides were not requested: ' + missingOverrideKeys.join(', ');
        }

        const payload = {
            browser: args.browser,
            executablePath,
            qa,
            skinOverrides: {
                config: skinOverrides.configPath ? path.relative(projectRoot, skinOverrides.configPath).replace(/\\/g, '/') : '',
                count: Object.keys(skinOverrides.files).length,
                hits: overrideHits,
                missing: missingOverrideKeys
            },
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
