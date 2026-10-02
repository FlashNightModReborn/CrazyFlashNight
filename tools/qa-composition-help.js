#!/usr/bin/env node
'use strict';
// qa-composition-help.js — composition-help.html 页面层 Playwright harness。
// 本地 HTTP 仅服务 launcher/web；addInitScript 模拟 window.chrome.webview 传输
// （捕获 postMessage + message listener），Host 侧用页面内 __hostSend 下发标准
// panel_cmd。这是页面层验证，不是游戏 E2E。
// 用法: node tools/qa-composition-help.js [--screenshot <path>]

const fs = require('fs');
const http = require('http');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const VIEWPORTS = [[720, 540], [960, 720]];
const shotArg = process.argv.find(a => a.startsWith('--screenshot'));
const shotPath = shotArg ? process.argv[process.argv.indexOf(shotArg) + 1] : null;
const checks = [];

function check(ok, title, detail) {
    checks.push({ok: !!ok, title, detail: detail == null ? '' : String(detail)});
    if (!ok) throw new Error(title + (detail == null ? '' : ': ' + detail));
}

function edgeExecutable() {
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
                            : ext === '.md' ? 'text/markdown; charset=utf-8' : 'application/octet-stream';
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

async function openHelp(page, instanceId, guidance) {
    const initData = {panelInstanceId: instanceId};
    if (guidance) initData.guidance = guidance;
    await hostSend(page, {type: 'panel_cmd', cmd: 'open', panel: 'help',
        initData});
    await page.waitForSelector('.help-panel', {state: 'visible', timeout: 8000});
    await page.waitForFunction(() => {
        const c = document.querySelector('.help-content');
        return c && c.querySelector('.guidance-tutorials');
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
        await page.goto('http://127.0.0.1:' + port + '/composition-help.html');
        await waitOutbox(page, m => m.type === 'composition_help_ready', 'ready ' + label);
        check(true, label + ' composition_help_ready emitted');

        await openHelp(page, 'inst-' + w + '-a');
        const content = await page.evaluate(() =>
            document.querySelector('.help-content').textContent);
        check(/[一-鿿]/.test(content), label + ' help body renders Chinese markdown');

        const tabs = await page.$$('.help-tab-btn');
        check(tabs.length === 4, label + ' four tab buttons', tabs.length);
        await page.click('.help-tab-btn[data-tab="worldview"]');
        await page.waitForFunction(() =>
            document.querySelector('.help-tab-btn[data-tab="worldview"]')
                .classList.contains('active'), {timeout: 5000});
        await page.waitForFunction(() => document.querySelector('.help-content h1')?.textContent === '世界观');
        check(true, label + ' tab click switches active tab');

        const scrollable = await page.evaluate(() => {
            const c = document.querySelector('.help-content');
            return c.scrollHeight > c.clientHeight + 1;
        });
        if (h === 540) check(scrollable, label + ' actual worldview body overflows');
        if (scrollable) {
            const box = await (await page.$('.help-content')).boundingBox();
            await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
            await page.mouse.wheel(0, 400);
            await page.waitForFunction(() => document.querySelector('.help-content').scrollTop > 0);
            const top = await page.evaluate(() => document.querySelector('.help-content').scrollTop);
            check(top > 0, label + ' wheel scrolls help content', top);
        }

        await page.keyboard.press('Tab');
        const focused = await page.evaluate(() =>
            document.activeElement && document.activeElement.tagName);
        check(focused === 'BUTTON', label + ' Tab focuses a real button', focused);

        // 出站过滤：非 help/task/诊断命令必须被丢弃
        await page.evaluate(() => {
            Bridge.send({type: 'task', task: 'save', payload: {x: 1}});
            Bridge.send({type: 'panel', cmd: 'close', panel: 'kshop'});
            Bridge.send({type: 'viewportMetrics'});
            Bridge.task('save_game', {op: 'write'});
        });
        let box0 = await outbox(page);
        check(!box0.some(m => m.type === 'task'), label + ' task/save RPC filtered');
        check(!box0.some(m => m.type === 'panel' && m.panel !== 'help'),
            label + ' non-help panel command filtered');
        check(!box0.some(m => m.type === 'viewportMetrics' || m.type === 'gpuInfo'),
            label + ' diagnostics filtered');
        await page.evaluate(() => {
            const base = {type:'tutorial_preference',cmd:'disable_auto_open',version:1,callId:'probe',panelInstanceId:'inst-' + innerWidth + '-a'};
            Bridge.send({...base,cmd:'host_set'});
            Bridge.send({...base,value:false});
            Bridge.send({...base,panelInstanceId:'foreign'});
        });
        check(!(await outbox(page)).some(m=>m.type==='tutorial_preference'), label + ' broader and foreign preference commands filtered');

        await page.click('.help-close-btn');
        await waitOutbox(page, m => m.type === 'panel' && m.cmd === 'close', 'close ' + label);
        box0 = await outbox(page);
        const closeA = box0.filter(m => m.type === 'panel' && m.cmd === 'close').pop();
        check(closeA.panel === 'help' && closeA.panelInstanceId === 'inst-' + w + '-a',
            label + ' close bound to current instance', JSON.stringify(closeA));

        await openHelp(page, 'inst-' + w + '-b');
        if (takeShot) await page.screenshot({path: takeShot});
        await page.click('.help-close-btn');
        box0 = await outbox(page);
        const closeB = box0.filter(m => m.type === 'panel' && m.cmd === 'close').pop();
        check(closeB.panelInstanceId === 'inst-' + w + '-b',
            label + ' reopen binds new instance', JSON.stringify(closeB));

        const keys = {left:'左方向键',right:'右方向键',up:'上方向键',down:'下方向键',attack:'Z',jump:'X',interact:'T'};
        for (const guideId of ['start','map']) {
            const instanceId = 'inst-' + w + '-' + guideId;
            await openHelp(page, instanceId, {guideId,keys});
            const selected = await page.evaluate(() => ({
                menu:document.querySelector('.guidance-menu [aria-current="page"]').textContent,
                title:document.querySelector('.guidance-page h2').textContent,
                keys:Array.from(document.querySelectorAll('.guidance-copy kbd')).map(n=>n.textContent)
            }));
            check(selected.title === (guideId === 'start' ? '开始游戏' : '地图与任务') && selected.menu === selected.title,
                label + ' automatic tutorial selects exact ' + guideId);
            check(await page.locator('.guidance-skip-bar').isVisible(), label + ' automatic tutorial offers explicit skip ' + guideId);
            const skipBounds = await page.locator('.guidance-skip-btn').boundingBox();
            check(skipBounds.y >= 0 && skipBounds.y + skipBounds.height <= h,
                label + ' skip remains in the viewport while tutorial scrolls ' + guideId);
            const disableBounds = await page.locator('.guidance-disable-btn').boundingBox();
            check(disableBounds.x >= 0 && disableBounds.x + disableBounds.width <= w
                && disableBounds.y >= 0 && disableBounds.y + disableBounds.height <= h,
                label + ' global disable remains in viewport ' + guideId);
            if (guideId === 'start') check(selected.keys.includes('Z') && selected.keys.includes('T') && !selected.keys.includes('E'),
                label + ' automatic tutorial uses opening key bindings');
            await page.getByRole('button',{name:'移动与战斗',exact:true}).click();
            const diagram = await page.locator('.guidance-diagram').textContent();
            check(diagram.includes('←') && diagram.includes('↑') && diagram.includes('Z') && diagram.includes('X'),
                label + ' shared combat diagram binds current keys');
            if (takeShot && guideId === 'start') await page.screenshot({path:takeShot.replace(/\.png$/,'.combat.png')});
            await page.click('.help-tab-btn[data-tab="worldview"]');
            await page.click('.help-tab-btn[data-tab="tutorials"]');
            check(await page.locator('.guidance-page h2').textContent() === selected.title,
                label + ' tutorial context survives tabs ' + guideId);
            if (takeShot) await page.screenshot({path:takeShot.replace(/\.png$/,'.'+guideId+'.png')});
            await page.locator('.guidance-skip-btn').focus();
            await page.keyboard.press('Enter');
            const close = (await outbox(page)).filter(m=>m.type==='panel' && m.cmd==='close').pop();
            check(close.panelInstanceId === instanceId, label + ' automatic tutorial exact close ' + guideId);
            check(!await page.locator('.help-panel').isVisible(), label + ' keyboard skip closes tutorial ' + guideId);
        }
        await openHelp(page,'inst-' + w + '-manual');
        check(!await page.locator('.guidance-skip-bar').isVisible(), label + ' manual help does not inherit auto tutorial skip');
        await page.getByRole('button',{name:'拾取物品',exact:true}).click();
        check((await page.locator('.guidance-copy kbd').allTextContents()).includes('E'), label + ' manual reopen clears old bindings');
        await page.click('.help-close-btn');
        const preferenceInstance = 'inst-' + w + '-global';
        await openHelp(page,preferenceInstance,{guideId:'map',keys});
        const closesBefore = (await outbox(page)).filter(m=>m.type==='panel' && m.cmd==='close').length;
        await page.locator('.guidance-disable-btn').focus();await page.keyboard.press('Enter');
        let preference = (await outbox(page)).filter(m=>m.type==='tutorial_preference').pop();
        check(preference && preference.cmd==='disable_auto_open' && preference.version===1
            && preference.panelInstanceId===preferenceInstance && Object.keys(preference).length===5,
            label + ' global disable emits only exact narrow preference command');
        check(await page.locator('.help-panel').isVisible() && await page.locator('.guidance-disable-btn').isDisabled()
            && (await outbox(page)).filter(m=>m.type==='panel' && m.cmd==='close').length===closesBefore,
            label + ' preference waits for persistence before close');
        const respond = (request,extra={}) => ({type:'tutorial_preference_result',version:1,
            callId:request.callId,panelInstanceId:request.panelInstanceId,ok:true,tutorialsAutoOpen:false,error:null,...extra});
        await hostSend(page,respond(preference,{panelInstanceId:'foreign'}));
        await hostSend(page,respond(preference,{callId:'foreign-call'}));
        check(await page.locator('.guidance-disable-btn').isDisabled() && await page.locator('.help-panel').isVisible(),
            label + ' foreign preference replies cannot close help');
        await hostSend(page,respond(preference,{ok:false,tutorialsAutoOpen:true,error:'save_failed'}));
        check(await page.locator('.guidance-disable-btn').isEnabled() && await page.locator('.help-panel').isVisible()
            && (await page.locator('.guidance-skip-note').textContent()).includes('保存失败'),
            label + ' save failure preserves tutorial and permits deliberate retry');
        await page.evaluate(() => {
            const original = window.setTimeout;
            window.setTimeout = function(fn,ms) {
                if(ms===10000) { window.__preferenceTimeout=fn;return original(fn,600000); }
                return original.apply(window,arguments);
            };
            window.__restorePreferenceTimer=()=>{window.setTimeout=original;};
        });
        await page.click('.guidance-disable-btn');
        preference = (await outbox(page)).filter(m=>m.type==='tutorial_preference').pop();
        const requestCount = (await outbox(page)).filter(m=>m.type==='tutorial_preference').length;
        await page.evaluate(()=>{window.__preferenceTimeout();document.querySelector('.guidance-disable-btn').click();});
        check(await page.locator('.guidance-disable-btn').isDisabled()
            && (await page.locator('.guidance-skip-note').textContent()).includes('尚未确认')
            && (await outbox(page)).filter(m=>m.type==='tutorial_preference').length===requestCount,
            label + ' unknown preference result keeps write disabled and never replays');
        if(takeShot) await page.screenshot({path:takeShot.replace(/\.png$/,'.global-pending.png')});
        await hostSend(page,respond(preference));
        check(!await page.locator('.help-panel').isVisible()
            && (await outbox(page)).filter(m=>m.type==='panel' && m.cmd==='close').pop().panelInstanceId===preferenceInstance,
            label + ' durable global opt-out closes its exact tutorial');
        await openHelp(page,'inst-' + w + '-after-global');
        await hostSend(page,respond(preference));
        check(await page.locator('.help-panel').isVisible() && !await page.locator('.guidance-skip-bar').isVisible(),
            label + ' late preference reply cannot close reopened manual help');
        await page.evaluate(()=>window.__restorePreferenceTimer());
        await page.click('.help-close-btn');
        for (const invalid of [{guideId:'combat',keys},{guideId:'map',keys:{interact:'T'}},{guideId:'map',keys,extra:true}]) {
            await hostSend(page,{type:'panel_cmd',cmd:'open',panel:'help',initData:{panelInstanceId:'inst-invalid-'+w,guidance:invalid}});
            check(!await page.locator('.help-panel').isVisible(), label + ' malformed tutorial init rejects mount');
        }

        check(errors.length === 0, label + ' no pageerror', errors.join(' | '));
    } finally {
        await page.close();
    }
}

(async function main() {
    check(fs.existsSync(path.join(WEB, 'composition-help.html')), 'composition-help.html exists');
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless: true});
    try {
        for (let i = 0; i < VIEWPORTS.length; i++) {
            await runViewport(browser, server.address().port, VIEWPORTS[i],
                i === VIEWPORTS.length - 1 ? shotPath : null);
        }
        const passed = checks.filter(c => c.ok).length;
        console.log(JSON.stringify({
            harness: 'qa-composition-help',
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
