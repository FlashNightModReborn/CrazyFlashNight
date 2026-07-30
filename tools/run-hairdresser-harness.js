#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');

function read(relative) {
    return fs.readFileSync(path.join(ROOT, relative), 'utf8');
}

function staticAudit() {
    const runtime = read('launcher/web/modules/hairdresser-runtime.js');
    const panel = read('launcher/web/modules/hairdresser.js');
    const css = read('launcher/web/css/hairdresser.css');
    const harness = read('launcher/web/modules/hairdresser/dev/harness.html');
    const manifest = JSON.parse(read('launcher/web/assets/dressup/manifest.json'));
    const hairstyle = read('data/items/hairstyle.xml');
    const rows = Array.from(hairstyle.matchAll(/<Hair\s+id="(\d+)">[\s\S]*?<Identifier>([^<]+)<\/Identifier>[\s\S]*?<Name>([^<]+)<\/Name>/g))
        .map(match => ({id:Number(match[1]),identifier:match[2],name:match[3]}));

    if (!runtime.includes("require('./panel-runtime.js')")
        || !runtime.includes('new PanelRuntime.PanelRequestMux')
        || !runtime.includes("panel: 'hairdresser'")
        || !runtime.includes("domain: 'hairdresser'")
        || !runtime.includes("COMMAND = /^(snapshot|commit)$/")) {
        throw new Error('strict shared hairdresser mux contract missing');
    }
    if (!runtime.includes("write: cmd === 'commit'")
        || !runtime.includes("sendError: 'not_sent'")
        || !runtime.includes("context.error === 'client_timeout'")) {
        throw new Error('hairdresser write timeout/reconcile classification missing');
    }
    if (!panel.includes("request('snapshot', {v: 1}")
        || !panel.includes("hairIdentifier: expected")
        || !panel.includes("expectedCurrentHair: expectedCurrent")
        || !panel.includes('snapshot.currentHair === expected')
        || !panel.includes('refreshSnapshot(true)')
        || !panel.includes("Bridge.send({type: 'panel', cmd: 'close', panel: 'hairdresser'})")) {
        throw new Error('snapshot/local-preview/commit/reconcile/close flow missing');
    }
    if (!panel.includes("fitFields: _previewFields")
        || !panel.includes("drawFields: _previewFields")
        || !panel.includes('strictFields: true')
        || !panel.includes('animate: false')
        || !panel.includes("_previewIssue = 'gender_unsupported'")
        || !panel.includes("bald ? ['脸型'] : ['脸型', '发型']")) {
        throw new Error('strict face/hair-only non-animated preview contract missing');
    }
    if (/\.(?:sort|reverse|splice)\s*\(\s*\)/.test(panel)
        || /gender.*(?:filter|guess)|(?:filter|guess).*gender/i.test(panel)
        || /new\s+(?:Catalog|Appearance|Pricing|Token|Lease)/.test(panel)) {
        throw new Error('catalog order/filter or generic framework regression found');
    }
    if (!css.includes('#panel-container[data-panel="hairdresser"] #panel-content')
        || !css.includes('.hairdresser-preview-fallback')
        || !css.includes('.hairdresser-panel button:focus-visible')
        || !css.includes('@media (prefers-reduced-motion: reduce)')) {
        throw new Error('hairdresser standalone/accessibility CSS contract missing');
    }
    if (!harness.includes('/data/items/hairstyle.xml')
        || !harness.includes("mode:'unknown_applied'")
        || !harness.includes("mode:'unknown_not_applied'")
        || !harness.includes("mode:'drop_applied'")
        || !harness.includes('fresh currentHair comparison overrides contradictory Host hint')) {
        throw new Error('hairdresser authority/reconcile harness matrix missing');
    }
    if (rows.length !== 77 || rows.some((row, index) => row.id !== index)) {
        throw new Error('AS2 hairstyle source no longer contains ordered ids 0..76');
    }
    const duplicateRows = rows.filter(row => row.identifier === '发型-男式-平头');
    if (duplicateRows.length !== 2 || duplicateRows[0].id !== 20 || duplicateRows[1].id !== 32) {
        throw new Error('required duplicate hairstyle rows 20 and 32 changed');
    }
    if (!manifest.appearance || manifest.appearance.faceById['0'] !== '女变装-基本脸型'
        || manifest.appearance.faceById['1'] !== '男变装-基本脸型'
        || manifest.appearance.hairById['0'] !== '光头'
        || manifest.appearance.hairById['20'] !== '发型-男式-平头'
        || manifest.appearance.hairById['32'] !== '发型-男式-平头') {
        throw new Error('dressup appearance mapping no longer covers frozen face/hair ids');
    }
}

function runtimeAudit() {
    const HairdresserRuntime = require(path.join(WEB, 'modules', 'hairdresser-runtime.js'));
    let owner = null;
    const router = {
        register(value) {
            owner = value;
            return function() { owner = null; };
        }
    };
    let sent = null;
    let received = null;
    const mux = new HairdresserRuntime.RequestMux({
        router,
        sessionNonce:'node.audit',
        timeoutMs:1000,
        send(message) { sent = message; return true; }
    });
    if (!mux.openSession()) throw new Error('hairdresser Node mux session did not open');
    if (mux.request('unsupported', {}, function() {}) !== null) {
        throw new Error('hairdresser Node mux accepted an unsupported command');
    }
    const callId = mux.request('snapshot', {v:99}, response => { received = response; });
    if (!callId || !sent || sent.payload.v !== 1 || sent.domain !== 'hairdresser'
        || sent.panel !== 'hairdresser' || sent.cmd !== 'snapshot') {
        throw new Error('hairdresser Node mux did not normalize the snapshot envelope');
    }
    owner.handleResponse({
        type:'panel_resp',domain:'hairdresser',cmd:'snapshot',callId,
        success:true,v:1,gender:'男',face:'1',currentHair:'光头',catalog:[]
    });
    if (!received || received.success !== true || mux.debugState().pendingCount !== 0) {
        throw new Error('hairdresser Node mux did not complete its matching response');
    }
    mux.destroy();

    let rejected = null;
    const rejectedMux = new HairdresserRuntime.RequestMux({
        router:{register(value) { return function() {}; }},
        sessionNonce:'node.reject',
        timeoutMs:1000,
        send() { return false; }
    });
    rejectedMux.openSession();
    rejectedMux.request(
        'commit',
        {v:1,hairIdentifier:'光头',expectedCurrentHair:'发型-男式-平头'},
        response => { rejected = response; });
    rejectedMux.destroy();
    if (!rejected || rejected.error !== 'not_sent' || rejected.requiresReconcile === true) {
        throw new Error('hairdresser Node mux confused pre-dispatch rejection with an unknown write');
    }
}

function edgePath() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA
            ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : ''
    ].find(candidate => candidate && fs.existsSync(candidate));
}

function contentType(file) {
    const ext = path.extname(file).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.js') return 'text/javascript; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.xml') return 'application/xml; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.svg') return 'image/svg+xml';
    return 'application/octet-stream';
}

function serve() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(ROOT, pathname));
            const relative = path.relative(ROOT, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403);
                response.end();
                return;
            }
            fs.readFile(file, (error, data) => {
                if (error) {
                    response.writeHead(404);
                    response.end();
                    return;
                }
                response.writeHead(200, {'Content-Type':contentType(file)});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function runViewport(browser, server, viewport) {
    const page = await browser.newPage({viewport});
    const pageErrors = [];
    const failedRequests = [];
    page.on('pageerror', error => pageErrors.push(error.message || String(error)));
    page.on('requestfailed', request => failedRequests.push(request.url()));
    try {
        const address = `http://127.0.0.1:${server.address().port}`;
        await page.goto(address + '/launcher/web/modules/hairdresser/dev/harness.html', {waitUntil:'load'});
        await page.waitForFunction(() => window.__qaDone === true, null, {timeout:30000});
        const state = await page.evaluate(() => ({result:window.__qaResult,error:window.__qaError}));
        const label = viewport.width + 'x' + viewport.height;
        if (state.error) throw new Error(label + ': ' + state.error);
        if (pageErrors.length) throw new Error(label + ' page errors: ' + pageErrors.join(' | '));
        if (failedRequests.length) throw new Error(label + ' failed requests: ' + failedRequests.join(' | '));
        const failed = state.result && state.result.checks
            ? state.result.checks.filter(check => !check.ok) : [];
        if (!state.result || state.result.passed !== state.result.total) {
            throw new Error(label + ' harness failed: ' + JSON.stringify(failed));
        }
        return state.result;
    } finally {
        await page.close();
    }
}

(async function main() {
    staticAudit();
    runtimeAudit();
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await serve();
    const browser = await chromium.launch({executablePath,headless:true});
    const viewports = [
        {width:1024,height:576},
        {width:1366,height:768},
        {width:1920,height:1080}
    ];
    const results = [];
    try {
        for (const viewport of viewports) {
            results.push(await runViewport(browser, server, viewport));
        }
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
    const first = results[0];
    if (results.some(result => result.total !== first.total)) {
        throw new Error('hairdresser harness check count changed across viewports');
    }
    console.log(
        `Hairdresser harness ${first.passed}/${first.total} passed across ${viewports.length} viewports: `
        + viewports.map(viewport => viewport.width + 'x' + viewport.height).join(', ')
    );
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
