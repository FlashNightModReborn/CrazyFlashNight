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

async function checkLeeStoryEntry(page, label, instanceId) {
    // Use the production HTML/script closure, including its outbound command filter.
    // The isolated intelligence dev harness intentionally does not load that glue.
    const content = JSON.parse(fs.readFileSync(path.join(ROOT, 'data', 'intelligence_h5', '黑龙令.json'), 'utf8'));
    await page.click('.intel-catalog-item[data-name="黑龙令"]');
    await answerQuery(page, 'snapshot', {
        value: 4, maxValue: 4, decryptLevel: 5, pcName: '验收员', contentMode: 'h5',
        item: {name: '黑龙令', displayName: '黑龙令'},
        pages: content.pages.map(p => Object.assign({}, p, {
            unlocked: true, value: Math.min(Number(p.pageKey), 4), encryptLevel: p.pageKey === '5' ? 5 : 0
        }))
    });
    await page.click('.intel-page-indicator');
    await page.click('.intel-page-btn[data-index="4"]');
    const entry = page.locator('.intel-story-entry');
    await entry.waitFor({state: 'visible'});
    const intro = await page.locator('.intel-lee-story').textContent();
    check(intro.includes('开始挑战') && intro.includes('装备 → 技能') && !/觉醒|隐藏结局|借雷|龙息/.test(intro), label + ' inline intro contains controls without story spoilers');
    await entry.click();
    await waitOutbox(page, m => m.cmd === 'open_lee_story', 'real Lee button ' + label);
    let requests = (await outbox(page)).filter(m => m.cmd === 'open_lee_story');
    const request = requests[0];
    check(requests.length === 1 && request.panelInstanceId === instanceId
        && request.itemName === '黑龙令' && request.pageKey === '5' && !!request.callId,
        label + ' real Lee button passes production outbound filter with exact identity');
    await entry.evaluate(button => button.click());
    check((await outbox(page)).filter(m => m.cmd === 'open_lee_story').length === 1 && await entry.isDisabled(),
        label + ' Lee entry sends once while waiting');
    await hostSend(page, Object.assign({}, request, {type:'panel_resp', success:false, error:'locked'}));
    check(await entry.isEnabled(), label + ' Lee refusal restores the real button');

    // Full production page: preparation -> snapshot -> one canonical save command.
    await entry.click();
    const prepare = (await outbox(page)).filter(m => m.cmd === 'open_lee_story').pop();
    await hostSend(page, Object.assign({}, prepare, {type:'panel_resp',success:true,token:'bookshelf.lee.direct'}));
    await waitOutbox(page, m => m.domain === 'bookshelf' && m.cmd === 'snapshot', 'Lee shared snapshot');
    const snapshot = (await outbox(page)).filter(m => m.domain === 'bookshelf' && m.cmd === 'snapshot').pop();
    await hostSend(page, Object.assign({}, snapshot, {type:'panel_resp',success:true,phase:'editing',leeEntry:true,canSwitch:true,inRun:false,pendingRun:''}));
    await waitOutbox(page, m => m.domain === 'bookshelf' && m.cmd === 'commit', 'Lee direct save intent');
    const commit = (await outbox(page)).filter(m => m.domain === 'bookshelf' && m.cmd === 'commit').pop();
    check(commit.panel === 'intelligence' && commit.payload.kind === 'play' && commit.payload.target === 'lee-trial'
        && !commit.payload.runSlot && !commit.payload.snapshot, label + ' start goes directly through shared save authority');
    await entry.evaluate(button => button.click());
    check((await outbox(page)).filter(m => m.domain === 'bookshelf' && m.cmd === 'commit').length === 1, label + ' direct start is single flight');
    await hostSend(page, Object.assign({}, commit, {type:'panel_resp',success:false,error:'timeout',requiresReconcile:true,recoveryToken:'bookshelf.lee.direct'}));
    check((await entry.textContent()) === '核对出发结果', label + ' unknown write offers reconciliation only');
    await entry.click();
    await waitOutbox(page, m => m.domain === 'bookshelf' && m.cmd === 'query', 'Lee read-only reconciliation');
    const query = (await outbox(page)).filter(m => m.domain === 'bookshelf' && m.cmd === 'query').pop();
    await hostSend(page, Object.assign({}, query, {type:'panel_resp',success:false,phase:'expired',requiresReconcile:false,nextToken:'bookshelf.lee.next'}));
    check(await entry.isEnabled() && (await outbox(page)).filter(m => m.domain === 'bookshelf' && m.cmd === 'commit').length === 1,
        label + ' terminal rejection releases UI without automatically replaying start');
    const rejected = await page.evaluate(instance => {
        const valid = {type:'panel', panel:'intelligence', cmd:'open_lee_story',
            panelInstanceId:instance, itemName:'黑龙令', pageKey:'5', callId:'lee.invalid'};
        return [{panelInstanceId:'foreign'}, {panelInstanceId:''}, {panelInstanceId:null},
            {itemName:'资料'}, {pageKey:'4'}, {pageKey:5}, {callId:''}, {callId:'x'.repeat(161)},
            {nativeCause:'page_close'}, {hostCloseReason:'navigate_character_build'}]
            .every(change => Bridge.send(Object.assign({}, valid, change)) === false);
    }, instanceId);
    check(rejected && !(await outbox(page)).some(m => m.callId === 'lee.invalid'),
        label + ' foreign or malformed Lee intent rejected by production glue');
    await page.evaluate(instance => Bridge.send({type:'panel', panel:'intelligence', cmd:'open_lee_story',
        panelInstanceId:instance, itemName:'黑龙令', pageKey:'5', callId:'lee.canonical',
        decryptLevel:999, unlocked:true, action:'bookshelfCommit'}), instanceId);
    const canonical = (await outbox(page)).find(m => m.callId === 'lee.canonical');
    check(canonical && Object.keys(canonical).sort().join(',') === 'callId,cmd,itemName,pageKey,panel,panelInstanceId,type',
        label + ' Lee navigation strips forged authority fields');
            const badWrites = await page.evaluate(instance => {
                const valid={type:'panel',panel:'intelligence',domain:'bookshelf',cmd:'commit',callId:'lee.forbidden',
                    panelInstanceId:instance,payload:{v:1,token:'bookshelf.lee.direct',kind:'play',target:'lee-trial'}};
                return [{kind:'return',target:'slot_a'},{kind:'play',target:'repair-campus'},{kind:'settle',target:'slot_a'},{runSlot:'forged'}, {snapshot:{}}]
                    .every(p => Bridge.send(Object.assign({},valid,{payload:Object.assign({},valid.payload,p)})) === false)
                    && Bridge.send(Object.assign({},valid,{panelInstanceId:'retired'})) === false;
            },instanceId);
            check(badWrites, label + ' production filter denies other save actions and authority payloads');
            if (shotPath) await page.screenshot({path:shotPath.replace(/\.png$/, '-lee-' + label + '.png')});
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

                await checkLeeStoryEntry(page, label, 'intel-' + w + '-a');

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

                await hostSend(page, {type:'panel_cmd', panel:'intelligence', cmd:'close'});
                const closedRejected = await page.evaluate(instance => Bridge.send({type:'panel', panel:'intelligence',
                    cmd:'open_lee_story', panelInstanceId:instance, itemName:'黑龙令', pageKey:'5', callId:'lee.closed'}) === false,
                    'intel-' + w + '-a');
                check(closedRejected && !(await outbox(page)).some(m => m.callId === 'lee.closed'),
                    label + ' closed reader cannot send Lee intent');
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
                const successPage = await browser.newPage({viewport:{width:1280,height:800}});
                try {
                    await successPage.addInitScript(INIT);
                    await successPage.goto('http://127.0.0.1:' + server.address().port + '/composition-intelligence.html');
                    const catalog=await readIntelligenceCatalog(successPage);
                    await openIntelligence(successPage,'intel-direct-success',catalog);
                    await checkLeeStoryEntry(successPage,'direct-success','intel-direct-success');
                    await successPage.locator('.intel-story-entry').click();
                    const prep=(await outbox(successPage)).filter(m=>m.cmd==='open_lee_story').pop();
                    await hostSend(successPage,Object.assign({},prep,{type:'panel_resp',success:true,token:'bookshelf.settle.1'}));
                    await waitOutbox(successPage,m=>m.domain==='bookshelf' && m.cmd==='snapshot' && m.payload.token==='bookshelf.settle.1','settle snapshot');
                    const snapSettle=(await outbox(successPage)).filter(m=>m.domain==='bookshelf' && m.cmd==='snapshot').pop();
                    await hostSend(successPage,Object.assign({},snapSettle,{type:'panel_resp',success:true,phase:'editing',leeEntry:true,canSwitch:true,inRun:false,pendingRun:'bookrun_leftover_1',pendingBookId:'lee-trial'}));
                    await waitOutbox(successPage,m=>m.cmd==='commit' && m.payload.token==='bookshelf.settle.1' && m.payload.kind==='settle','auto settle commit');
                    const settleCommit=(await outbox(successPage)).filter(m=>m.cmd==='commit').pop();
                    await hostSend(successPage,Object.assign({},settleCommit,{type:'panel_resp',success:true,phase:'applied',kind:'settle',target:'bookrun_leftover_1',nextToken:'bookshelf.success',requiresReconcile:false}));
                    await waitOutbox(successPage,m=>m.domain==='bookshelf' && m.cmd==='snapshot' && m.payload.token==='bookshelf.success','success snapshot');
                    const snap=(await outbox(successPage)).filter(m=>m.domain==='bookshelf' && m.cmd==='snapshot').pop();
                    await hostSend(successPage,Object.assign({},snap,{type:'panel_resp',success:true,phase:'editing',leeEntry:true,canSwitch:true,inRun:false,pendingRun:''}));
                    await waitOutbox(successPage,m=>m.cmd==='commit' && m.payload.token==='bookshelf.success','success commit');
                    const start=(await outbox(successPage)).filter(m=>m.cmd==='commit').pop();
                    await hostSend(successPage,Object.assign({},start,{type:'panel_resp',success:false,phase:'save_pending',requiresReconcile:true,recoveryToken:'bookshelf.success'}));
                    await waitOutbox(successPage,m=>m.cmd==='query' && m.payload.token==='bookshelf.success','automatic save receipt query');
                    const query=(await outbox(successPage)).filter(m=>m.cmd==='query').pop();
                    await hostSend(successPage,Object.assign({},query,{type:'panel_resp',success:true,phase:'switching',kind:'play',target:'lee-trial',requiresReconcile:true}));
                    await waitOutbox(successPage,m=>m.cmd==='close' && m.panelInstanceId==='intel-direct-success','admitted direct start closes reader');
                    check((await outbox(successPage)).filter(m=>m.cmd==='commit' && m.payload.token==='bookshelf.success').length===1,
                        'pending source save progresses automatically through read-only query with one start');
                    check(await successPage.locator('.bookshelf-panel').count()===0,'direct start never opens an intermediate bookshelf');
                } finally { await successPage.close(); }
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
