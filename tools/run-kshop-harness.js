#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const WORKBENCH_SOURCE = path.join(WEB_ROOT, 'modules', 'workbench.js');
const INVENTORY_RUNTIME_SOURCE = path.join(WEB_ROOT, 'modules', 'inventory-runtime.js');
const GAME_UI_BEHAVIOR_SOURCE = path.join(WEB_ROOT, 'modules', 'game-ui-behavior.js');
const KSHOP_SOURCE = path.join(WEB_ROOT, 'modules', 'kshop.js');
const visualArg = process.argv.find(arg => arg.startsWith('--visual='));
const shotArg = process.argv.find(arg => arg.startsWith('--shot='));
const viewportArg = process.argv.find(arg => arg.startsWith('--viewport='));

function parseViewport() {
    if (!viewportArg) return {width:1366,height:768};
    const match = viewportArg.slice('--viewport='.length).match(/^(\d+)x(\d+)$/);
    if (!match) throw new Error('Invalid --viewport, expected WIDTHxHEIGHT');
    return {width:Number(match[1]),height:Number(match[2])};
}

function auditArchitectureBoundaries() {
    const source = fs.readFileSync(WORKBENCH_SOURCE, 'utf8');
    const forbidden = ['ShopTask', 'InventoryTask', 'callId', 'saveCart', 'checkout', 'claim', 'sortAndMerge'];
    const hits = forbidden.filter(token => source.includes(token));
    if (hits.length) throw new Error('Workbench boundary violation: ' + hits.join(', '));
    const rendererStart = source.indexOf('function GridRenderer(');
    const rendererEnd = source.indexOf('function ContainerViewAdapter(', rendererStart);
    const rendererBody = source.slice(rendererStart, rendererEnd);
    if (/pending|requestMux|timerMap/.test(rendererBody)) {
        throw new Error('GridRenderer boundary violation: transport state detected');
    }
    if (/BackpackView|WarehouseView|背包\s*[×xX]\s*仓库|仓库\s*[×xX]\s*背包/.test(source)) {
        throw new Error('Workbench boundary violation: concrete owned-view pair branch detected');
    }
    const inventorySource = fs.readFileSync(INVENTORY_RUNTIME_SOURCE, 'utf8');
    const resolverStart = inventorySource.indexOf('function operationForIntent(');
    const resolverEnd = inventorySource.indexOf('function wireRef(', resolverStart);
    const resolverBody = inventorySource.slice(resolverStart, resolverEnd);
    if (/containerId\s*===|containerId\s*!==/.test(resolverBody)) {
        throw new Error('Inventory operation resolver branches on concrete container pair');
    }
    const kshopSource = fs.readFileSync(KSHOP_SOURCE, 'utf8');
    if (kshopSource.includes('same_container_unsupported')) {
        throw new Error('KShop still rejects generic same-container owned transfer');
    }
    const behaviorSource = fs.readFileSync(GAME_UI_BEHAVIOR_SOURCE, 'utf8');
    const behaviorEvents = ['selectstart', 'dragstart', 'contextmenu'];
    if (!behaviorEvents.every(eventName => behaviorSource.includes(eventName))
            || !behaviorSource.includes('[data-browser-native]')) {
        throw new Error('Game UI behavior guard is missing a required native-browser boundary');
    }
    return {
        forbiddenTokens:forbidden,
        gridRendererTransportFree:true,
        ownedPairBranchFree:true,
        sameContainerTransfer:true,
        nativeBehaviorGuard:behaviorEvents
    };
}

function edgePath() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ].filter(Boolean);
    return candidates.find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB_ROOT, pathname));
            const relative = path.relative(WEB_ROOT, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const extension = path.extname(file);
                const mime = extension === '.html' ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                    : extension === '.js' ? 'text/javascript; charset=utf-8'
                    : 'application/octet-stream';
                response.writeHead(200, {'Content-Type': mime});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

(async function() {
    const architectureAudit = auditArchitectureBoundaries();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');
    const { chromium } = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    const page = await browser.newPage({viewport:parseViewport()});
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    const visualMode = visualArg ? visualArg.slice('--visual='.length) : '';
    const targetQuery = visualMode ? '?visual=' + encodeURIComponent(visualMode) : '?qa=1';
    await page.goto('http://127.0.0.1:' + server.address().port + '/modules/kshop/dev/harness.html' + targetQuery, {waitUntil:'load'});
    if (visualMode) {
        await page.waitForFunction(() => window.__visualReady === true, null, {timeout:20000});
        if (shotArg) {
            const shotPath = path.resolve(ROOT, shotArg.slice('--shot='.length));
            await page.screenshot({path:shotPath,fullPage:true});
        }
        const visualState = await page.evaluate(() => ({
            state:KShop.debugState(),
            shellRect:(() => { const r=document.querySelector('.workbench-shell').getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; })(),
            bodyOverflow:document.body.scrollWidth > document.body.clientWidth || document.body.scrollHeight > document.body.clientHeight
        }));
        await browser.close();
        server.close();
        process.stdout.write(JSON.stringify({browser:'edge',executablePath,visualMode,visualState,pageErrors,failedRequests},null,2)+'\n');
        if (pageErrors.length || failedRequests.length) process.exit(1);
        return;
    }
    await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa, null, {timeout:20000});
    const qa = await page.evaluate(() => window.__qaResult.qa);
    await browser.close();
    server.close();

    const output = {browser:'edge',executablePath,architectureAudit,qa,pageErrors,failedRequests};
    process.stdout.write(JSON.stringify(output, null, 2) + '\n');
    if (qa.failed || pageErrors.length || failedRequests.length) process.exit(1);
})().catch(error => {
    console.error(error && error.stack ? error.stack : String(error));
    process.exit(2);
});
