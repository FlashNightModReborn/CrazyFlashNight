#!/usr/bin/env node
'use strict';
// qa-composition-intelligence.js — composition-intelligence.html 页面层 Playwright harness。
// 本地 HTTP 仅服务 launcher/web；addInitScript 模拟 window.chrome.webview 传输
// （捕获 postMessage + message listener），Host 侧用页面内 __hostSend 下发标准
// panel_cmd / panel_resp。这是页面层验证，不是游戏 E2E。
// 用法: node tools/qa-composition-intelligence.js [--screenshot <path>]

const fs = require('fs');
const http = require('http');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const VIEWPORTS = [[720, 540], [1280, 800]];
const shotArg = process.argv.find(a => a.startsWith('--screenshot'));
const shotPath = shotArg ? process.argv[process.argv.indexOf(shotArg) + 1] : null;
const checks = [];

function check(ok, title, detail) {
    checks.push({ok: !!ok, title, detail: detail == null ? '' : String(detail)});
    if (!ok) throw new Error(title + (detail == null ? '' : ': ' + detail));
}

function edgeExecutable() {
    if (process.env.CF7_QA_BROWSER_EXE && fs.existsSync(process.env.CF7_QA_BROWSER_EXE))
        return process.env.CF7_QA_BROWSER_EXE;
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(new URL(request.url, 'http://127.0.0.1').pathname);
            const file = path.normalize(path.join(WEB, pathname));
            const relative = path.relative(WEB, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) {
                response.writeHead(403); response.end(); return;
            }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const ext = path.extname(file);
                const type = ext === '.html' ? 'text/html; charset=utf-8'
                    : ext === '.css' ? 'text/css; charset=utf-8'
                        : ext === '.js' ? 'text/javascript; charset=utf-8'
                            : ext === '.json' ? 'application/json; charset=utf-8' : 'application/octet-stream';
                response.writeHead(200, {'Content-Type': type});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

const INIT = () => {
    window.__outbox = [];
    window.__listeners = [];
    window.chrome = {webview: {
        postMessage: msg => { window.__outbox.push(msg); },
        addEventListener: (type, fn) => { if (type === 'message') window.__listeners.push(fn); }
    }};
    window.__hostSend = msg => {
        window.__listeners.forEach(fn => { try { fn({data: msg}); } catch (e) { console.error(e); } });
    };
};

const hostSend = (page, msg) => page.evaluate(m => window.__hostSend(m), msg);
const outbox = page => page.evaluate(() => window.__outbox.slice());

async function waitOutbox(page, pred, label) {
    await page.waitForFunction(p => window.__outbox.some(m => eval('(' + p + ')')(m)),
        pred.toString(), {timeout: 8000}).catch(() => { throw new Error('timeout waiting outbox: ' + label); });
}

// 页面出站查询（panel/cmd:callId）→ 取回 callId → 回 canned panel_resp。
// 注意：waitForFunction 的谓词在浏览器端 eval，不能引用 Node 闭包变量。
async function answerQuery(page, cmd, respBody) {
    const pred = new Function('m',
        'return m.type === "panel" && m.panel === "intelligence" && m.cmd === ' + JSON.stringify(cmd) + ';');
    await waitOutbox(page, pred, 'query ' + cmd);
    const box = await outbox(page);
    const req = box.filter(m => m.type === 'panel' && m.panel === 'intelligence' && m.cmd === cmd).pop();
    await hostSend(page, Object.assign({
        type: 'panel_resp', panel: 'intelligence', cmd, callId: req.callId, success: true
    }, respBody));
}

async function readIntelligenceCatalog(page) {
    const xml = fs.readFileSync(path.join(ROOT, 'data', 'items', '收集品_情报.xml'), 'utf8');
    return page.evaluate(source => {
        const doc = new DOMParser().parseFromString(source, 'application/xml');
        if (doc.querySelector('parsererror')) throw new Error('Invalid intelligence item XML');
        return Array.from(doc.querySelectorAll('item')).map((item, index) => {
            const text = tag => item.querySelector(tag)?.textContent || '';
            const name = text('name');
            const maxValue = Number(text('maxvalue')) || 99;
            return {
                name, iconName: text('icon'), index, maxValue,
                displayName: name === '资料' ? '验收档案' : (text('displayname') || name),
                value: Math.min(42, maxValue), pageCount: 1, unlockedCount: 1
            };
        });
    }, xml);
}

async function checkItemIcons(page, label, expectedCount) {
    await page.waitForFunction(count => {
        const header = document.querySelector('.intel-icon');
        const icons = Array.from(document.querySelectorAll('.intel-catalog-icon'));
        return header && header.complete && header.naturalWidth > 0
            && icons.length === count && icons.every(img => img.complete && img.naturalWidth > 0);
    }, expectedCount, {timeout: 8000}).catch(async () => {
        const detail = await page.evaluate(() => ({
            loader: typeof Icons,
            headerSrc: document.querySelector('.intel-icon')?.getAttribute('src'),
            decoded: Array.from(document.querySelectorAll('.intel-catalog-icon')).filter(img => img.naturalWidth > 0).length,
            placeholders: document.querySelectorAll('.intel-catalog-icon-placeholder').length
        }));
        check(false, label + ' real item icons decode', JSON.stringify(detail));
    });
    check(true, label + ' header real icon decoded');
    check(true, label + ' all ' + expectedCount + ' catalog real icons decoded');
    check(await page.evaluate(() => document.querySelectorAll('.intel-catalog-icon-placeholder').length === 0),
        label + ' catalog has no missing-icon placeholders');
}

async function openIntelligence(page, instanceId, catalog) {
    await hostSend(page, {type: 'panel_cmd', cmd: 'open', panel: 'intelligence',
        initData: {panelInstanceId: instanceId, mode: 'prod', source: 'runtime', debug: false}});
    await page.waitForSelector('.intelligence-panel', {state: 'visible', timeout: 8000});
    // prod 模式：state → populateCatalog → snapshot + glossary_catalog
    await answerQuery(page, 'state', {
        decryptLevel: 3, pcName: '验收员',
        items: catalog
    });
    await answerQuery(page, 'snapshot', {
        value: 42, maxValue: 99, decryptLevel: 3, pcName: '验收员', contentMode: 'legacy',
        item: {name: '资料', displayName: '验收档案'},
        pages: [{pageKey: 'p1', unlocked: true, blocks: [{kind: 'text', text: '验收正文段落'}]}]
    });
    await answerQuery(page, 'glossary_catalog', {items: [], lockedCount: 0});
    await page.waitForFunction(() => {
        const el = document.querySelector('.intel-name');
        return el && el.textContent === '验收档案';
    }, {timeout: 8000});
}

async function runViewport(browser, port, viewport, takeShot) {
    const [w, h] = viewport;
    const label = w + 'x' + h;
    const page = await browser.newPage({viewport: {width: w, height: h}});
    const errors = [];
    page.on('pageerror', e => errors.push(String(e)));
    try {
        await page.addInitScript(INIT);
        await page.goto('http://127.0.0.1:' + port + '/composition-intelligence.html');
        await waitOutbox(page, m => m.type === 'composition_intelligence_ready', 'ready ' + label);
        check(true, label + ' composition_intelligence_ready emitted');

        const catalog = await readIntelligenceCatalog(page);
        check(catalog.length > 0 && catalog.some(item => item.name === '资料'), label + ' canonical item metadata loaded');
        await openIntelligence(page, 'intel-' + w + '-a', catalog);
        check(true, label + ' prod open renders catalog+snapshot from panel_resp');
        await checkItemIcons(page, label + ' cold open', catalog.length);

        const meta = await page.evaluate(() => document.querySelector('.intel-meta').textContent);
        check(/已发现 1 \/ 1/.test(meta), label + ' unlocked page count renders', meta);

        await page.locator('.intel-catalog-item[data-name="资料"]').hover();
        await answerQuery(page, 'tooltip', {
            itemName: '资料', introHTML: '<b>验收档案</b>', descHTML: '真实图标悬停回归'
        });
        await page.waitForFunction(() => {
            const img = document.querySelector('#panel-tooltip .intel-tt-rich img');
            return img && img.complete && img.naturalWidth > 0;
        }, null, {timeout: 8000});
        check(true, label + ' rich hover tooltip real icon decoded');
        await page.mouse.move(0, 0);

        // 出站过滤：写业务/诊断/其他面板命令必须被丢弃
        await page.evaluate(() => {
            Bridge.send({type: 'task', task: 'font_pack', payload: {op: 'download_group'}});
            Bridge.send({type: 'panel', cmd: 'close', panel: 'help'});
            Bridge.send({type: 'panel', panel: 'intelligence', cmd: 'finishTask', callId: 'forge-1'});
            Bridge.send({type: 'viewportMetrics'});
            Bridge.task('font_pack', {op: 'download_group', group: 'expressive'});
        });
        let box = await outbox(page);
        check(!box.some(m => m.type === 'task'), label + ' task/font_pack RPC filtered');
        check(!box.some(m => m.type === 'panel' && m.panel !== 'intelligence'),
            label + ' foreign panel command filtered');
        check(!box.some(m => m.cmd === 'finishTask'), label + ' non-whitelist write-ish cmd filtered');
        check(!box.some(m => m.type === 'viewportMetrics' || m.type === 'gpuInfo'),
            label + ' diagnostics filtered');

        // 只读查询带 callId 放行（tooltip）
        await page.evaluate(() => {
            Bridge.send({type: 'panel', panel: 'intelligence', cmd: 'tooltip', callId: 'probe-1', itemName: '资料'});
        });
        box = await outbox(page);
        check(box.some(m => m.cmd === 'tooltip' && m.callId === 'probe-1'),
            label + ' whitelisted read-only query passes');

        // 伪造实例的 close 被胶水拒绝
        await page.evaluate(() => {
            Bridge.send({type: 'panel', cmd: 'close', panel: 'intelligence', panelInstanceId: 'foreign'});
        });
        box = await outbox(page);
        check(!box.some(m => m.type === 'panel' && m.cmd === 'close' && m.panelInstanceId === 'foreign'),
            label + ' foreign-instance close filtered');

        await page.click('.intel-close-btn');
        await waitOutbox(page, m => m.type === 'panel' && m.cmd === 'close', 'close ' + label);
        box = await outbox(page);
        const closeA = box.filter(m => m.type === 'panel' && m.cmd === 'close').pop();
        check(closeA.panel === 'intelligence' && closeA.panelInstanceId === 'intel-' + w + '-a',
            label + ' close bound to current instance', JSON.stringify(closeA));
        check(closeA.reason === undefined, label + ' ordinary close carries no fabricated reason');

        await openIntelligence(page, 'intel-' + w + '-b', catalog);
        await checkItemIcons(page, label + ' reopen', catalog.length);
        if (takeShot) await page.screenshot({path: takeShot});
        await page.click('.intel-close-btn');
        box = await outbox(page);
        const closeB = box.filter(m => m.type === 'panel' && m.cmd === 'close').pop();
        check(closeB.panelInstanceId === 'intel-' + w + '-b',
            label + ' reopen binds new instance', JSON.stringify(closeB));

        check(errors.length === 0, label + ' no pageerror', errors.join(' | '));
    } finally {
        await page.close();
    }
}

(async function main() {
    check(fs.existsSync(path.join(WEB, 'composition-intelligence.html')), 'composition-intelligence.html exists');
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    // 优先系统 Edge（与 qa-composition-help 一致）；无 Edge 的机器退回 Playwright 自带
    // chromium-headless-shell（node launcher/perf/node_modules/playwright/cli.js install）。
    const browser = executablePath
        ? await chromium.launch({executablePath, headless: true})
        : await chromium.launch({headless: true});
    try {
        for (let i = 0; i < VIEWPORTS.length; i++) {
            await runViewport(browser, server.address().port, VIEWPORTS[i],
                i === VIEWPORTS.length - 1 ? shotPath : null);
        }
        const passed = checks.filter(c => c.ok).length;
        console.log(JSON.stringify({
            harness: 'qa-composition-intelligence',
            scope: 'page-level only, not game E2E',
            passed: passed + '/' + checks.length,
            checks
        }, null, 2));
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
