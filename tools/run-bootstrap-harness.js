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
            // 延迟入口模块才能覆盖晚订阅；只延迟种子时 V2 已经完成订阅。
            if (requestUrl.pathname === '/modules/bg-gl/main.mjs'
                    || requestUrl.pathname === '/assets/pm19/seed-bank.json') setTimeout(send, 150);
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

async function backgroundState(page) {
    return page.evaluate(async () => (await import('./modules/bg-gl/main.mjs')).inspect());
}

function assertMagicBoard(board, original) {
    if (!board || board.length !== 361 || new Set(board).size !== 361
            || board.some(value => !Number.isInteger(value))) throw new Error('invalid PM19 board');
    if (original && board.some(value => !new Set(original).has(value))) {
        throw new Error('PM19 exchange changed the original element set');
    }
    let diagonal = 0, reverse = 0;
    for (let r = 0; r < 19; r += 1) {
        let row = 0, column = 0;
        for (let c = 0; c < 19; c += 1) { row += board[r * 19 + c]; column += board[c * 19 + r]; }
        if (row !== 190000361 || column !== 190000361) throw new Error('PM19 row/column sum drift');
        diagonal += board[r * 20]; reverse += board[(r + 1) * 18];
    }
    if (diagonal !== 190000361 || reverse !== 190000361) throw new Error('PM19 diagonal sum drift');
}

async function main() {
    const checkoutEquipment = JSON.parse(require('./tooltip-catalog.cjs').compile().archive);
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
    const cancelledIntroStreams = [];
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
        await page.addInitScript(data => { window.CF7CheckoutEquipment = data; }, checkoutEquipment);
        await page.emulateMedia({ reducedMotion: 'reduce' });
        page.on('requestfailed', request => {
            const failure = request.failure();
            // Reloading the player or leaving a skipped intro cancels its in-flight media stream.
            // The navigation case below independently requires a decoded frame from this exact file.
            if (request.resourceType() === 'media' && request.url() === 'http://127.0.0.1:' + port + '/assets/intro.mp4'
                    && failure?.errorText === 'net::ERR_ABORTED') {
                cancelledIntroStreams.push(request.url());
                return;
            }
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
                events.push({ direction: 'in', cmd: payload.cmd, payload, at: performance.now() });
                const event = { data: JSON.stringify(payload) };
                listeners.slice().forEach(listener => listener(event));
            };
            const webview = {
                addEventListener(type, listener) {
                    if (type === 'message') listeners.push(listener);
                },
                postMessage(raw) {
                    const message = typeof raw === 'string' ? JSON.parse(raw) : raw;
                    events.push({ direction: 'out', cmd: message.cmd, payload: message, at: performance.now() });
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
                    } else if (message.cmd === 'config_set') {
                        setTimeout(() => emit({
                            cmd:'config_set_resp', requestId:message.requestId, key:message.key,
                            ok:true, currentValue:message.value
                        }), 0);
                    } else if (message.cmd === 'log') {
                        // 列车 C 场景：模拟不识 'log' 的老宿主回执，供 web 侧能力探测停用水槽。
                        setTimeout(() => emit({ cmd:'log_resp', ok:false, error:'unknown_cmd' }), 0);
                    }
                }
            };
            window.chrome = window.chrome || {};
            window.chrome.webview = webview;
            window.__bootstrapHarnessEvents = events;
            window.__bootstrapHarnessEmit = emit;
        });

        await page.goto('http://127.0.0.1:' + port + '/bootstrap.html', { waitUntil: 'load' });

        await check('host-list-response', async () => {
            await page.waitForFunction(() => window.__bootstrapHarnessEvents.some(event => event.direction === 'in' && event.cmd === 'list_resp')
                && document.querySelectorAll('#cards .save-row').length === 0
                && document.getElementById('save-empty').textContent.includes('暂无存档'), null, { timeout: 10000 });
            const events = await page.evaluate(() => window.__bootstrapHarnessEvents.slice());
            if (!events.some(event => event.direction === 'in' && event.cmd === 'list_resp')) {
                throw new Error('host list_resp was not delivered');
            }
            return 'empty Host list displays an empty state and allocates zero list rows';
        });

        await check('pm19-late-subscription-replay', async () => {
            // 安装测试侧只读引用，再用同步条件轮询；Promise 本身不能代表就绪。
            await page.evaluate(async () => {
                window.__pm19Harness = await import('./modules/bg-gl/main.mjs');
            });
            await page.waitForFunction(() => {
                const state = window.__pm19Harness.inspect();
                return state.canvas && state.commits === 1
                    && document.body.dataset.bgGlLifecycle === 'paused-static';
            }, null, { timeout: 10000 });
            const state = await backgroundState(page);
            if (state.version !== 4 || state.hostState !== 'Ready' || state.cues !== 1
                    || state.retired || state.userIntent || state.scheduled || state.commits !== 1
                    || state.pendingSync) {
                throw new Error('late replay must initialize once without treating prewarm Ready as confirmation: '
                    + JSON.stringify({ ...state, board:state.board && state.board.length }));
            }
            assertMagicBoard(state.board);
            // prewarm Ready 无 userIntent 不过 syncGate：不触发 sync/confirm，cues 不增。
            await page.evaluate(() => {
                window.__bootstrapHarnessEmit({ cmd:'list_resp', slots:[], introEnabled:false });
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Ready' });
                window.__bootstrapHarnessEmit({ cmd:'flash_ready' });
            });
            const repeated = await backgroundState(page);
            if (repeated.cues !== state.cues || repeated.commits !== state.commits || repeated.retired
                    || repeated.pendingSync) {
                throw new Error('duplicate host replay restarted, retired or sync-armed the background');
            }
            return 'delayed module replays host state once; prewarm Ready triggers no sync/confirm and never retires';
        });

        await check('pm19-static-resize-and-session-pause', async () => {
            const before = await backgroundState(page);
            await page.setViewportSize({ width:viewport.width - 16, height:viewport.height });
            await page.waitForTimeout(180);
            const resized = await backgroundState(page);
            if (resized.callbacks !== before.callbacks || resized.time !== before.time
                    || resized.scheduled || JSON.stringify(resized.board) !== JSON.stringify(before.board)) {
                throw new Error('reduced motion resize advanced the clock or board: '
                    + JSON.stringify({ before:{ ...before, board:before.board && before.board.length },
                        resized:{ ...resized, board:resized.board && resized.board.length } }));
            }
            await page.setViewportSize(viewport);
            await page.locator('#btn-about').click();
            await page.locator('#pm19-pause').check();
            await page.keyboard.press('Escape');
            await page.emulateMedia({ reducedMotion:'no-preference' });
            const paused = await backgroundState(page);
            await page.waitForTimeout(180);
            const still = await backgroundState(page);
            if (!still.paused || still.scheduled || still.callbacks !== paused.callbacks
                    || still.time !== paused.time || still.commits !== paused.commits) {
                throw new Error('session pause left background work running');
            }
            const writes = await page.evaluate(() => window.__bootstrapHarnessEvents.filter(event =>
                event.direction === 'out' && event.cmd === 'config_set'));
            if (writes.length) throw new Error('session pause persisted a preference');
            await page.locator('#btn-about').click();
            await page.locator('#pm19-pause').uncheck();
            await page.keyboard.press('Escape');
            return 'resize preserves the committed board; session pause stops scheduling and writes no config';
        });

        await check('frontdoor-stage-and-fullscreen-owner', async () => {
            const button = page.locator('#btn-fullscreen');
            const emit = msg => page.evaluate(value => window.__bootstrapHarnessEmit(value), msg);
            const requests = () => page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'set_fullscreen').map(event => event.payload.enabled));
            // 空目录首启：主按钮即“新建角色”，次级只留存档库入口，不再重复新建链接。
            const actions = ['#btn-confirm-start','#btn-switch-slot','#hud-toggle'];
            let reference;
            try {
                const firstRun = await page.evaluate(() => ({
                    primary: document.getElementById('btn-confirm-start').textContent,
                    duplicateHidden: document.getElementById('btn-welcome-new').hidden,
                    library: document.getElementById('btn-switch-slot').textContent,
                    logsInTopbar: !!document.querySelector('.topbar #btn-logs, .topbar [data-open-logs]')
                }));
                if (firstRun.primary !== '新建角色' || !firstRun.duplicateHidden
                        || firstRun.library !== '导入或管理存档' || firstRun.logsInTopbar) {
                    throw new Error('first-run homepage kept duplicate or developer actions: ' + JSON.stringify(firstRun));
                }
                await emit({cmd:'fullscreen_state',enabled:false});
                await button.click();
                if (!(await requests()).at(-1) || await button.getAttribute('aria-pressed') !== 'false') {
                    throw new Error('fullscreen button did not request or waited for a different window owner');
                }
                await emit({cmd:'fullscreen_state',enabled:true});
                if (!await button.evaluate(el => el.textContent === '退出全屏' && el.getAttribute('aria-pressed') === 'true')) {
                    throw new Error('fullscreen state did not reach the visible button');
                }
                const before = (await requests()).length;
                await page.locator('#btn-display').click();
                await page.keyboard.press('Escape');
                if ((await requests()).length !== before || await page.locator('#modal-content').isVisible()) {
                    throw new Error('Escape left fullscreen before dismissing settings');
                }
                await page.keyboard.press('Escape');
                if ((await requests()).at(-1) !== false) throw new Error('homepage Escape did not request window restoration');
                for (const size of [{width:1024,height:576},{width:640,height:360},{width:1640,height:720},{width:800,height:1000}]) {
                    await page.setViewportSize(size);
                    await page.waitForFunction(() => {
                        const frame = document.getElementById('launcher-stage').getBoundingClientRect();
                        const scale = Math.min(innerWidth / 1024, innerHeight / 576);
                        return Math.abs(frame.width / 1024 - scale) < .001
                            && Math.abs(frame.width + 2 * frame.left - innerWidth) < 1
                            && Math.abs(frame.height + 2 * frame.top - innerHeight) < 1;
                    });
                    const positions = await page.evaluate(selectors => {
                        const frame = document.getElementById('launcher-stage').getBoundingClientRect(), scale = frame.width / 1024;
                        return selectors.map(id => {
                            const el = document.querySelector(id), rect = el.getBoundingClientRect();
                            if (!el.contains(document.elementFromPoint(rect.left + rect.width / 2, rect.top + rect.height / 2))) {
                                throw new Error('unreachable button ' + id);
                            }
                            return [(rect.left - frame.left) / scale, (rect.top - frame.top) / scale, rect.width / scale, rect.height / scale];
                        }).flat();
                    }, actions);
                    if (reference && positions.some((value,i) => Math.abs(value - reference[i]) > 1)) {
                        throw new Error('window size changed the logical homepage layout');
                    }
                    reference = positions;
                }
            } finally {
                await emit({cmd:'fullscreen_state',enabled:false});
                await page.setViewportSize(viewport);
            }
            return 'one centered canvas, same hit targets, acknowledged window mode and layered Escape';
        });

        await check('pm19-visible-cycle-and-coverage', async () => {
            const start = await backgroundState(page);
            await page.waitForFunction(value => window.__pm19Harness.inspect().commits > value,
            start.commits, { timeout:15000 });
            const exchanged = await backgroundState(page);
            assertMagicBoard(exchanged.board, start.board);
            if (exchanged.time < 9900 || exchanged.commits !== start.commits + 1) {
                throw new Error('orbit committed before its eight-second wait and two-second cue: '
                    + JSON.stringify({ start:{ ...start, board:start.board && start.board.length },
                        exchanged:{ ...exchanged, board:exchanged.board && exchanged.board.length } }));
            }
            for (const className of ['intro-video', 'character-create-active']) {
                await page.evaluate(name => document.body.classList.add(name), className);
                await page.waitForFunction(() => document.body.dataset.bgGlLifecycle === 'paused-covered');
                const covered = await backgroundState(page);
                await page.waitForTimeout(160);
                const after = await backgroundState(page);
                if (after.scheduled || after.time !== covered.time || after.commits !== covered.commits
                        || after.callbacks !== covered.callbacks) {
                    throw new Error(className + ' left hidden background work running');
                }
                await page.evaluate(name => document.body.classList.remove(name), className);
            }
            await page.emulateMedia({ reducedMotion:'reduce' });
            return 'one complete legal exchange; video/character-create coverage freezes all background work';
        });

        await check('pm19-portrait-and-control-columns', async () => {
            await page.setViewportSize({ width:1366, height:900 });
            await page.waitForTimeout(180);
            const pixels = await page.evaluate(() => {
                const mask = document.querySelector('.art-figure-mask').getBoundingClientRect();
                const hero = document.querySelector('.hero-copy').getBoundingClientRect();
                const side = document.body.dataset.artSide;
                if (mask.width < 400 || !(side === 'left' ? hero.left >= mask.right : hero.right <= mask.left)) {
                    throw new Error('portrait and controls overlap on ' + side);
                }
                const canvas = document.getElementById('bg-gl');
                const bounds = canvas.getBoundingClientRect(), scale = canvas.width / bounds.width;
                const x = side === 'left' ? Math.ceil((mask.right - bounds.left) * scale) : 0;
                const width = side === 'left' ? canvas.width - x : Math.floor((mask.left - bounds.left) * scale);
                const data = canvas.getContext('2d').getImageData(x, 0, width, canvas.height).data;
                let count = 0;
                for (let i = 3; i < data.length; i += 4) if (data[i] > 8) count++;
                return count;
            });
            await page.setViewportSize(viewport);
            if (pixels < 50) throw new Error('exposed PM19 canvas is empty');
            return 'portrait and controls occupy opposite sides; exposed canvas has ' + pixels + ' painted pixels';
        });

        await check('home-host-states-and-short-window-readout', async () => {
            const original = await page.evaluate(() => ({
                font: Number(getComputedStyle(document.documentElement).getPropertyValue('--user-fs-scale')) || 1.35,
                bannerHidden: document.getElementById('welcome-fontpack').hidden
            }));
            try {
                await page.setViewportSize({ width:1066, height:600 });
                await page.evaluate(() => {
                    for (const [state, label] of [['Idle', '就绪'], ['RepairPending', '等待修复存档'], ['Ready', '游戏就绪']]) {
                        window.__bootstrapHarnessEmit({ cmd:'state', state, msg:'host-detail' });
                        const badge = document.getElementById('state-badge');
                        if (badge.textContent !== label || !badge.title.includes('host-detail')
                                || document.getElementById('hud-last').textContent !== label) {
                            throw new Error('host state was not rendered in both readouts: ' + state);
                        }
                    }
                    window.__bootstrapHarnessEmit({ cmd:'boot',
                        messages:'[BootstrapAS] socket ready, firing handshake|[BootstrapAS] handshake hs=Success' });
                    const channel = document.getElementById('hud-chan'), latest = document.getElementById('hud-last');
                    if (!channel.textContent.includes('连接就绪，开始握手') || channel.children.length > 5
                            || latest.textContent !== '握手成功' || latest.title !== 'handshake hs=Success') {
                        throw new Error('batched Flash boot signals lost their readable labels or original details');
                    }
                    document.getElementById('welcome-fontpack').hidden = false;
                });
                for (const font of [1.35, 1.75]) {
                    await page.evaluate(uiFontScale => {
                        window.__bootstrapHarnessEmit({ cmd:'list_resp', slots:[], uiFontScale });
                        document.getElementById('view-welcome').scrollTop = 0;
                    }, font);
                    await page.waitForFunction(() => {
                        const rect = selector => document.querySelector(selector).getBoundingClientRect();
                        const header = rect('.topbar'), footer = rect('.bottom'), logo = rect('.title-logo-wrap img');
                        const controls = rect('.welcome-controls'), readout = rect('.hud-line');
                        return logo.height > 0 && logo.top >= header.bottom - 1 && controls.bottom <= readout.top
                            && readout.height > 0 && readout.bottom <= footer.top;
                    }, null, { timeout:3000 });
                    await page.locator('#btn-display').click();
                    const install = page.locator('#welcome-fontpack-install');
                    if (!await install.isVisible() || !await page.locator('#chk-intro').isVisible()) {
                        throw new Error('opening settings lost the font action or intro option');
                    }
                    await page.keyboard.press('Escape');
                    if (!await page.locator('#btn-display').evaluate(el => document.activeElement === el)) {
                        throw new Error('closing settings lost the opener');
                    }
                }
            } finally {
                await page.evaluate(({ font, bannerHidden }) => {
                    window.__bootstrapHarnessEmit({ cmd:'list_resp', slots:[], uiFontScale:font });
                    document.getElementById('welcome-fontpack').hidden = bannerHidden;
                    document.getElementById('view-welcome').scrollTop = 0;
                }, original);
                await page.setViewportSize(viewport);
            }
            return 'localized host states, visible controls and channel readouts, reachable optional action at both font sizes';
        });

        await check('pm19-confirm-keeps-business-authority', async () => {
            await page.emulateMedia({ reducedMotion:'no-preference' });
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'list_resp', introEnabled:false,
                lastPlayedSlot:'pm19-fixture', slots:[{ slot:'pm19-fixture', characterName:'测试角色',
                    displayName:'测试存档', size:4096, lastModified:'2026-09-13T00:00:00', corrupt:false }] }));
            await page.locator('#btn-confirm-start').click();
            const state = await backgroundState(page);
            const starts = await page.evaluate(() => window.__bootstrapHarnessEvents.filter(event =>
                event.direction === 'out' && event.cmd === 'start_game'));
            if (!state.userIntent || starts.length !== 1 || starts[0].payload.slot !== 'pm19-fixture'
                    || starts[0].payload.requireFlashReveal !== true || state.blocked || !state.scheduled) {
                throw new Error('confirm must send the original single launch and keep its visible background active');
            }
            await page.waitForTimeout(1800);
            const waiting = await backgroundState(page);
            // loading <12s 无换盘；>12s 的 unfreeze 换盘属预期提交（harness 时长内不触发）。
            if (waiting.callbacks <= state.callbacks || waiting.time <= state.time
                    || waiting.visualKind !== 'loading' || waiting.commits !== state.commits) {
                throw new Error('transparent loading must animate the committed board without hidden swaps');
            }
            const indicator = await page.locator('#intro-ov .loading-indicator').boundingBox();
            // V3: lore 事件流在 loading 相可见且必须自带遮罩（光不许从文字下过）——
            // 把它的矩形排除在"隐藏前景遮罩未清"判定之外；其余超规格遮罩仍判失败。
            const loreBox = await page.locator('#bg-gl-log.visible').boundingBox().catch(() => null);
            if (loreBox && loreBox.y < indicator.y + indicator.height) throw new Error('loading lore overlaps player controls');
            const foreignMask = waiting.canvas.masks.some(mask => {
                if (mask.w <= indicator.width + 8 && mask.h <= indicator.height + 8) return false;
                if (loreBox && Math.abs(mask.x - loreBox.x) <= 12 && Math.abs(mask.y - loreBox.y) <= 12
                        && Math.abs(mask.w - loreBox.width) <= 24 && Math.abs(mask.h - loreBox.height) <= 24) return false;
                return true;
            });
            if (foreignMask) {
                throw new Error('loading retained the hidden welcome-card or side-column mask: '
                    + JSON.stringify({ masks: waiting.canvas.masks, indicator, loreBox }));
            }
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'state', state:'Error', msg:'flash_exited_pre_reveal' }));
            await page.locator('#view-welcome .launch-feedback').waitFor({ state:'visible' });
            await page.waitForTimeout(1900);
            const error = await backgroundState(page);
            if (await page.locator('#bg-gl-log').isVisible() || await page.locator('#btn-confirm-start').textContent() !== '重试启动')
                throw new Error('returning to welcome retained the lore stream or lost the retry action');
            if (error.visualKind !== 'error' || error.cue || error.commits !== waiting.commits
                    || !(await page.locator('#btn-confirm-start.retry').isVisible())) {
                throw new Error('error feedback ended before the host left Error');
            }
            const faultPixels = await page.evaluate(() => {
                const canvas = document.getElementById('bg-gl');
                const data = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
                let red = 0;
                for (let i = 0; i < data.length; i += 4) {
                    if (data[i + 3] > 24 && data[i] > data[i + 1] * 1.45 && data[i] > data[i + 2] * 1.35) red++;
                }
                return red / (canvas.width * canvas.height);
            });
            if (faultPixels < .002) throw new Error('fault performance was erased by foreground masks: ' + faultPixels);
            await page.setViewportSize({ width:640, height:360 });
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'list_resp', uiFontScale:1.75,
                lastPlayedSlot:'pm19-fixture', slots:[{ slot:'pm19-fixture', characterName:'测试角色', size:4096 }] }));
            try { await page.waitForFunction(() => ['#btn-confirm-start', '#view-welcome .launch-feedback'].every(selector => {
                const r = document.querySelector(selector).getBoundingClientRect();
                return r.width > 0 && r.y >= 0 && r.bottom <= innerHeight - 20;
            }), null, { timeout:3000 }); }
            catch (error) {
                const bounds = await page.evaluate(() => ['#btn-confirm-start', '#view-welcome .launch-feedback']
                    .map(selector => ({ selector, rect:document.querySelector(selector).getBoundingClientRect().toJSON() })));
                await page.setViewportSize(viewport);
                await page.reload({ waitUntil:'load' });
                throw new Error('compact error controls clipped: ' + JSON.stringify(bounds));
            }
            await page.emulateMedia({ reducedMotion:'reduce' });
            await page.evaluate(() => document.getElementById('bg-gl').dispatchEvent(new Event('contextlost')));
            if (!(await backgroundState(page)).failed
                    || !(await page.locator('#view-welcome .launch-feedback').isVisible())) {
                throw new Error('background failure hid the business error feedback');
            }
            await page.locator('#btn-confirm-start').click();
            const retries = await page.evaluate(() => window.__bootstrapHarnessEvents.filter(event =>
                event.direction === 'out' && event.cmd === 'retry'));
            if (retries.length !== 1) throw new Error('error recovery did not send exactly one original retry');
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'state', state:'Spawning' }));
            if (await page.locator('.launch-feedback:visible').count()) throw new Error('new attempt retained stale error copy');
            await page.evaluate(() => {
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Idle' });
                window.__bootstrapHarnessEmit({ cmd:'list_resp', slots:[], introEnabled:false });
            });
            if ((await backgroundState(page)).userIntent) throw new Error('cancel did not clear background intent');
            await page.setViewportSize(viewport);
            await page.reload({ waitUntil:'load' });
            await page.evaluate(async () => { window.__pm19Harness = await import('./modules/bg-gl/main.mjs'); });
            await page.waitForFunction(() => !!window.__pm19Harness.inspect().canvas);
            return 'single start/retry; loading stays animated; Error persists; reduced motion/context loss preserve visible recovery';
        });

        await check('pm19-retire-during-seed-load', async () => {
            const late = await browser.newPage({ viewport });
            let held;
            await late.route('https://cfn-fonts.local/**', route => route.fulfill({ status:204, body:'' }));
            await late.route('**/assets/pm19/seed-bank.json', route => { held = route; });
            try {
                await Promise.all([
                    late.waitForRequest('**/assets/pm19/seed-bank.json'),
                    late.goto('http://127.0.0.1:' + port + '/bootstrap.html', { waitUntil:'domcontentloaded' })
                ]);
                await late.evaluate(() => document.body.classList.add('cf7-host-hidden'));
                await late.waitForFunction(() => document.body.dataset.bgGlLifecycle === 'host-retired');
                await held.continue();
                held = null;
                await late.waitForTimeout(350);
                const state = await backgroundState(late);
                if (!state.retired || state.canvas || state.board || state.scheduled || state.commits) {
                    throw new Error('late seed completion revived a retired background');
                }
            } finally {
                if (held) await held.continue();
                await late.close();
            }
            return 'retirement before seed completion prevents all late engine/canvas creation';
        });

        await check('host-reveal-retires-gpu-background', async () => {
            if (await page.locator('#bg-gl').count() !== 1) {
                throw new Error('PM19 canvas was not active before host reveal');
            }
            await page.evaluate(() => document.body.classList.add('cf7-host-hidden'));
            await page.waitForFunction(() => document.body.dataset.bgGlLifecycle === 'host-retired'
                && !document.getElementById('bg-gl')
                && !document.getElementById('bg-gl-readout')
                && !document.getElementById('bg-gl-log'), null, { timeout: 3000 });
            const state = await backgroundState(page);
            if (!state.retired || state.scheduled || state.board || state.canvas) {
                throw new Error('host retirement retained background resources');
            }
            await page.evaluate(() => document.body.classList.remove('cf7-host-hidden'));
            await page.emulateMedia({ reducedMotion:'no-preference' });
            await page.waitForTimeout(160);
            if (!(await backgroundState(page)).retired || await page.locator('#bg-gl').count()) {
                throw new Error('retired background revived after host visibility returned');
            }
            await page.emulateMedia({ reducedMotion:'reduce' });
            return 'host reveal cancels scheduling and releases board/caches; visibility cannot revive it';
        });

        await check('tooltip-binding', async () => {
            await page.locator('#btn-about').hover();
            await page.waitForTimeout(380);
            const tooltip = page.locator('.boot-tooltip.on');
            if (await tooltip.count() !== 1) throw new Error('tooltip did not become visible');
            const text = (await tooltip.textContent()) || '';
            for (const token of ['项目说明', '作者与致谢', '版本记录']) {
                if (!text.includes(token)) throw new Error('unexpected tooltip text: ' + text);
            }
            await page.mouse.move(1, 1);
            return text;
        });

        await check('tooltip-keyboard-focus', async () => {
            const button = page.locator('#btn-display');
            await button.focus();
            await page.waitForTimeout(380);
            const tooltip = page.locator('.boot-tooltip.on');
            if (await tooltip.count() !== 1) throw new Error('focus did not reveal tooltip');
            const describedBy = await button.getAttribute('aria-describedby');
            if (!describedBy || !describedBy.split(/\s+/).includes('boot-tooltip-layer')) {
                throw new Error('focused trigger is not associated with tooltip');
            }
            const nextButton = page.locator('#btn-fullscreen');
            await nextButton.focus();
            await page.waitForTimeout(380);
            const staleDescription = await button.getAttribute('aria-describedby');
            const nextDescription = await nextButton.getAttribute('aria-describedby');
            if ((staleDescription || '').split(/\s+/).includes('boot-tooltip-layer')
                    || !(nextDescription || '').split(/\s+/).includes('boot-tooltip-layer')) {
                throw new Error('switching focused triggers left a stale aria-describedby owner');
            }
            await nextButton.evaluate(element => element.blur());
            await button.click();
            const intro = page.locator('.chk-intro');
            await intro.hover();
            await page.waitForTimeout(380);
            if (await tooltip.count() !== 1) throw new Error('pointer tooltip did not appear before click');
            await intro.click();
            await page.waitForTimeout(380);
            if (await tooltip.count() !== 0) throw new Error('pointer click resurrected its tooltip through focusin');
            await page.keyboard.press('Escape');
            await button.evaluate(element => element.blur());
            if (await page.locator('.boot-tooltip.on').count() !== 0) throw new Error('blur did not hide tooltip');
            await page.locator('#btn-switch-slot').click();
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'list_resp', slots:[{slot:'tooltip-slot', characterName:'提示样本'}]
            }));
            const cardButton = page.locator('#save-actions .btn-start');
            await cardButton.focus();
            await page.waitForTimeout(380);
            const delegatedText = (await page.locator('.boot-tooltip.on').textContent()) || '';
            if (!delegatedText.includes('直接启动所选存档')) throw new Error('delegated focus tooltip did not appear');
            const delegatedBy = await cardButton.getAttribute('aria-describedby');
            if (!delegatedBy || !delegatedBy.split(/\s+/).includes('boot-tooltip-layer')) {
                throw new Error('delegated focused trigger is not associated with tooltip');
            }
            await cardButton.evaluate(element => element.blur());
            await page.locator('#btn-back-welcome').click();
            return 'direct/delegated focusin/focusout mirror hover and maintain aria-describedby';
        });

        await check('about-markdown-tabs-and-audio', async () => {
            await page.locator('#btn-about').focus();
            await page.locator('#btn-about').press('Enter');
            const modal = page.locator('#modal-content');
            await modal.waitFor({ state:'visible' });
            const modalSemantics = await page.evaluate(() => {
                const content = document.getElementById('modal-content');
                const labelledBy = content.getAttribute('aria-labelledby');
                const background = Array.from(document.querySelectorAll('#launcher-stage > .topbar, #launcher-stage > .view, #launcher-stage > .bottom, #log'));
                const rect = content.getBoundingClientRect();
                const style = getComputedStyle(content);
                return {
                    role:content.getAttribute('role'),
                    ariaModal:content.getAttribute('aria-modal'),
                    labelledBy,
                    labelExists:!!(labelledBy && document.getElementById(labelledBy)),
                    activeInside:content.contains(document.activeElement),
                    backgroundInert:background.length > 0 && background.every(node => node.inert),
                    backgroundHidden:background.length > 0
                        && background.every(node => node.getAttribute('aria-hidden') === 'true'),
                    fullScreenSurface:content.classList.contains('about-surface')
                        && Math.abs(rect.width / content.offsetWidth - rect.height / content.offsetHeight) < .002
                        && content.offsetWidth >= 1024 - 26 && content.offsetHeight >= 576 - 26,
                    completeBorder:['borderTopWidth', 'borderRightWidth', 'borderBottomWidth', 'borderLeftWidth']
                        .every(property => parseFloat(style[property]) >= 1),
                    unclipped:style.clipPath === 'none',
                    overflow:style.overflow
                };
            });
            if (modalSemantics.role !== 'dialog' || modalSemantics.ariaModal !== 'true'
                    || !modalSemantics.labelExists || !modalSemantics.activeInside
                    || !modalSemantics.backgroundInert || !modalSemantics.backgroundHidden
                    || !modalSemantics.fullScreenSurface || !modalSemantics.completeBorder
                    || !modalSemantics.unclipped || modalSemantics.overflow !== 'hidden') {
                throw new Error('Other modal lacks modal focus/background semantics: '
                    + JSON.stringify(modalSemantics));
            }

            const focusableSelector = 'button:not([disabled]), input:not([disabled]), select:not([disabled]), '
                + 'textarea:not([disabled]), a[href], [tabindex]:not([tabindex="-1"])';
            const focusables = modal.locator(focusableSelector);
            const focusableCount = await focusables.count();
            if (focusableCount < 2) throw new Error('Other modal exposes too few focusable controls');
            for (let i = 0; i < focusableCount + 2; i += 1) {
                await page.keyboard.press('Tab');
                const stayedInside = await page.evaluate(() =>
                    document.getElementById('modal-content').contains(document.activeElement));
                if (!stayedInside) throw new Error('Tab escaped behind the Other modal at step ' + i);
            }
            await focusables.last().focus();
            await page.keyboard.press('Tab');
            if (!(await focusables.first().evaluate(node => node === document.activeElement))) {
                throw new Error('Tab did not wrap from the last modal control to the first');
            }
            await focusables.first().focus();
            await page.keyboard.press('Shift+Tab');
            if (!(await focusables.last().evaluate(node => node === document.activeElement))) {
                throw new Error('Shift+Tab did not wrap from the first modal control to the last');
            }
            const tabs = modal.getByRole('tab');
            await page.waitForFunction(() => document.querySelectorAll('#modal-content [role="tab"]').length === 3,
                null, { timeout:3000 });
            const labels = (await tabs.allTextContents()).map(value => value.trim());
            const expectedLabels = ['项目说明', '作者与致谢', '版本记录'];
            if (JSON.stringify(labels) !== JSON.stringify(expectedLabels)) {
                throw new Error('unexpected Other tabs: ' + JSON.stringify(labels));
            }
            const documentTab = modal.getByRole('tab', { name:'项目说明', exact:true });
            await documentTab.focus();
            await documentTab.press('ArrowRight');
            if (!(await modal.getByRole('tab', { name:'作者与致谢', exact:true })
                .evaluate(node => node === document.activeElement && node.getAttribute('aria-selected') === 'true'))) {
                throw new Error('ArrowRight did not select and focus the credits tab');
            }
            await page.keyboard.press('End');
            if (!(await modal.getByRole('tab', { name:'版本记录', exact:true })
                .evaluate(node => node === document.activeElement && node.getAttribute('aria-selected') === 'true'))) {
                throw new Error('End did not select and focus the versions tab');
            }
            await page.keyboard.press('Home');
            if (!(await documentTab.evaluate(node =>
                node === document.activeElement && node.getAttribute('aria-selected') === 'true'))) {
                throw new Error('Home did not return focus and selection to the first tab');
            }
            await page.keyboard.press('ArrowLeft');
            if (!(await modal.getByRole('tab', { name:'版本记录', exact:true })
                .evaluate(node => node === document.activeElement && node.getAttribute('aria-selected') === 'true'))) {
                throw new Error('ArrowLeft did not wrap to the versions tab');
            }

            async function activateTab(label) {
                const tab = modal.getByRole('tab', { name:label, exact:true });
                await tab.click();
                await page.waitForFunction(value => {
                    const candidates = Array.from(document.querySelectorAll('#modal-content [role="tab"]'));
                    const active = candidates.find(node => node.textContent.trim() === value);
                    if (!active || active.getAttribute('aria-selected') !== 'true') return false;
                    const controlled = active.getAttribute('aria-controls');
                    const panel = controlled && document.getElementById(controlled);
                    return panel && !panel.hidden && panel.textContent.trim().length >= 24;
                }, label, { timeout:5000 });
                return tab.evaluate(node => {
                    const panel = document.getElementById(node.getAttribute('aria-controls'));
                    const siblingPanels = Array.from(panel.parentElement.querySelectorAll('[data-about-pane]'))
                        .filter(candidate => candidate !== panel);
                    return {
                        text:panel.textContent.replace(/\s+/g, ' ').trim(),
                        rendered:!!panel.querySelector('h3,h4,h5,h6,p,ul,ol,blockquote,table'),
                        nestedHeadingLeak:!!panel.querySelector('h1,h2'),
                        readyLiveRegion:!!panel.querySelector('.about-markdown[role],.about-markdown[aria-live]'),
                        isolated:siblingPanels.every(candidate => candidate.hidden
                            && getComputedStyle(candidate).display === 'none')
                    };
                });
            }

            const explanation = await activateTab('项目说明');
            const sfx = modal.locator('#about-sfx');
            const ambient = modal.locator('#about-ambient');
            if (await sfx.count() !== 1 || await ambient.count() !== 1) {
                throw new Error('audio settings disappeared from the Other modal');
            }
            await sfx.check();
            await ambient.check();
            await page.waitForFunction(() => {
                const events = window.__bootstrapHarnessEvents.filter(event =>
                    event.direction === 'out' && event.cmd === 'config_set');
                return events.some(event => event.payload.key === 'sfxEnabled' && event.payload.value === true)
                    && events.some(event => event.payload.key === 'ambientEnabled' && event.payload.value === true)
                    && window.BootstrapAudio.isSfxEnabled() && window.BootstrapAudio.isAmbientEnabled();
            }, null, { timeout:3000 });
            const authors = await activateTab('作者与致谢');
            const versions = await activateTab('版本记录');
            if (!explanation.rendered || !/(?:本地|单机)/.test(explanation.text)) {
                throw new Error('description Markdown was not rendered: ' + explanation.text.slice(0, 120));
            }
            if (!authors.rendered || !authors.text.includes('AndyLaw') || !/(?:致谢|感谢)/.test(authors.text)
                    || !authors.text.includes('音效') || !authors.text.includes('nocopyrightsounds.co.uk')) {
                throw new Error('author/credits Markdown was not rendered: ' + authors.text.slice(0, 120));
            }
            if (authors.text.includes('未推断或扩充') || authors.text.includes('修订只需更新本 Markdown 文件')) {
                throw new Error('developer-facing archaeology disclaimer leaked into player credits');
            }
            if (!explanation.isolated || !authors.isolated || !versions.isolated) {
                throw new Error('inactive About tab panels still participate in layout: '
                    + JSON.stringify({ explanation, authors, versions }));
            }
            const infoScrollbars = await modal.locator('#about-pane-document, #about-pane-credits')
                .evaluateAll(panes => panes.map(pane => {
                    const style = getComputedStyle(pane);
                    const button = getComputedStyle(pane, '::-webkit-scrollbar-button');
                    return {
                        id:pane.id,
                        width:style.scrollbarWidth,
                        color:style.scrollbarColor,
                        buttonDisplay:button.display,
                        buttonWidth:button.width,
                        buttonHeight:button.height
                    };
                }));
            if (infoScrollbars.length !== 2 || infoScrollbars.some(scrollbar =>
                    scrollbar.width !== 'thin' || scrollbar.color === 'auto'
                    || scrollbar.buttonDisplay !== 'none'
                    || scrollbar.buttonWidth !== '0px' || scrollbar.buttonHeight !== '0px')) {
                throw new Error('About information panes exposed native scrollbar chrome: '
                    + JSON.stringify(infoScrollbars));
            }
            const creditPalette = await modal.locator('#about-pane-credits').evaluate(pane => {
                const color = name => {
                    const node = pane.querySelector('[data-credit="' + name + '"]');
                    return node ? getComputedStyle(node).color : '';
                };
                return {
                    andylaw:color('andylaw'),
                    andylawGames:color('andylaw-games'),
                    ffdec:color('ffdec')
                };
            });
            if (creditPalette.andylaw !== 'rgb(204, 255, 0)'
                    || creditPalette.andylawGames !== 'rgb(255, 255, 255)'
                    || creditPalette.ffdec !== 'rgb(15, 253, 236)') {
                throw new Error('Flash-aligned author credit palette drifted: '
                    + JSON.stringify(creditPalette));
            }
            if (!versions.rendered || !/(?:版本|VERSION)/i.test(versions.text)
                    || !['2024-02-09', '2023-11-21', '2023-08-11', '2023-07-27']
                        .every(token => versions.text.includes(token))) {
                throw new Error('version-history Markdown was not rendered: ' + versions.text.slice(0, 120));
            }
            if (!['E 阶段开发中', '稳定玩家包', '下一期更新视频提纲']
                    .every(token => versions.text.includes(token)) || versions.text.includes('2.72')) {
                throw new Error('version-stage semantics drifted: ' + versions.text.slice(0, 220));
            }
            const versionBrowser = await modal.locator('#about-pane-versions').evaluate(pane => {
                const options = Array.from(pane.querySelectorAll('.about-version-option'));
                const entries = Array.from(pane.querySelectorAll('.about-version-entry'));
                const visible = entries.filter(entry => !entry.hidden);
                const selected = options.filter(option => option.getAttribute('aria-pressed') === 'true');
                const rect = pane.querySelector('.about-version-browser').getBoundingClientRect();
                const paneRect = pane.getBoundingClientRect();
                return {
                    optionLabels:options.map(option => option.textContent.trim()),
                    entryCount:entries.length,
                    visibleCount:visible.length,
                    selectedCount:selected.length,
                    selectedLabel:selected[0] ? selected[0].textContent.trim() : '',
                    visibleText:visible[0] ? visible[0].textContent.replace(/\s+/g, ' ').trim() : '',
                    fillsPane:rect.width >= paneRect.width - 2 && rect.height >= paneRect.height * .72,
                    disclaimerLeak:visible[0] ? /不冒充|免责|可能不准确|证据不足/.test(visible[0].textContent) : true,
                    currentRowInsideBrowser:!!pane.querySelector('.about-version-browser .about-current-version')
                };
            });
            if (versionBrowser.entryCount < 10 || versionBrowser.visibleCount !== 1
                    || versionBrowser.selectedCount !== 1 || versionBrowser.selectedLabel !== '2.718'
                    || !versionBrowser.visibleText.includes('下一期更新视频提纲')
                    || !versionBrowser.fillsPane || versionBrowser.disclaimerLeak
                    || versionBrowser.currentRowInsideBrowser
                    || !['2.71', '2.66', '2.65', '2.60', '2.50', '2.45', '2.40', '2.3', '2.2', '2.0']
                        .every(label => versionBrowser.optionLabels.includes(label))) {
                throw new Error('interactive single-version browser contract drifted: '
                    + JSON.stringify(versionBrowser));
            }
            const option271 = modal.getByRole('button', { name:'2.71', exact:true });
            await option271.click();
            const selected271 = await modal.locator('.about-version-entry:not([hidden])').textContent();
            const release271Href = await modal.getByRole('link', { name:'下载 2.71 整包', exact:true })
                .getAttribute('href');
            if (!selected271.includes('7.2.71.zip') || !selected271.includes('下载 2.71 整包')
                    || selected271.includes('下一期更新视频提纲')
                    || release271Href !== 'https://github.com/FlashNightModReborn/CrazyFlashNight/releases/tag/%E9%97%AA%E5%AE%A2%E5%BF%AB%E6%89%937%E9%87%8D%E7%BD%AE%E8%AE%A1%E5%88%922.71%E6%95%B4%E5%8C%85') {
                throw new Error('version selection did not isolate the 2.71 player entry');
            }
            await option271.press('ArrowDown');
            const selected266 = await modal.locator('.about-version-entry:not([hidden])').textContent();
            if (!selected266.includes('战宠出战数量') || !selected266.includes('任务完成后感叹号')) {
                throw new Error('version keyboard navigation did not select the 2.66 fixes');
            }
            if (authors.nestedHeadingLeak || versions.nestedHeadingLeak) {
                throw new Error('Markdown heading levels were not nested below the modal title');
            }
            if (authors.readyLiveRegion || versions.readyLiveRegion) {
                throw new Error('ready Markdown body remained a live region and may be announced in full');
            }
            const currentVersion = await modal.locator('#about-pane-versions').evaluate(pane => {
                const row = pane.querySelector('.about-current-version');
                const markdown = pane.querySelector('#about-versions-content');
                const meta = window.APP_META || {};
                return {
                    rowText:row ? row.textContent.replace(/\s+/g, ' ').trim() : '',
                    rowInsideMarkdown:!!(row && row.closest('.about-markdown')),
                    markdownText:markdown ? markdown.textContent.replace(/\s+/g, ' ').trim() : '',
                    meta:{ version:String(meta.version || ''), channel:String(meta.channel || ''), tail:String(meta.tail || '') }
                };
            });
            if (!currentVersion.meta.version || !currentVersion.meta.channel || !currentVersion.meta.tail
                    || !currentVersion.rowText || currentVersion.rowInsideMarkdown
                    || !currentVersion.rowText.includes(currentVersion.meta.version)
                    || !currentVersion.rowText.includes(currentVersion.meta.channel)
                    || !currentVersion.rowText.includes(currentVersion.meta.tail)) {
                throw new Error('current version is not rendered dynamically outside Markdown: '
                    + JSON.stringify(currentVersion));
            }
            if (currentVersion.markdownText.includes('当前启动器')) {
                throw new Error('version-history Markdown duplicated the dynamic current-version row');
            }
            const markdownResources = await page.evaluate(() => performance.getEntriesByType('resource')
                .map(entry => decodeURIComponent(new URL(entry.name).pathname))
                .filter(name => /\/(?:about-authors|version-history)\.md$/i.test(name)));
            if (!markdownResources.some(name => /\/about-authors\.md$/i.test(name))
                    || !markdownResources.some(name => /\/version-history\.md$/i.test(name))) {
                throw new Error('Other tabs did not fetch both Markdown sources: '
                    + JSON.stringify(markdownResources));
            }
            await page.keyboard.press('Escape');
            await page.locator('#modal-host').waitFor({ state:'hidden' });
            const restored = await page.evaluate(() => ({
                focusId:document.activeElement && document.activeElement.id,
                backgroundClear:Array.from(document.querySelectorAll('#launcher-stage > .topbar, #launcher-stage > .view, #launcher-stage > .bottom, #log'))
                    .every(node => !node.inert && node.getAttribute('aria-hidden') !== 'true')
            }));
            if (restored.focusId !== 'btn-about' || !restored.backgroundClear) {
                throw new Error('closing Other did not restore opener/background: ' + JSON.stringify(restored));
            }
            return 'full-screen complete-border modal; focus trapped/restored; Markdown drives a single-version browser and audio round-trip';
        });

        await check('about-inline-keyboard-entry', async () => {
            const inlineEntry = page.locator('#briefing-about');
            if (await inlineEntry.evaluate(node => node.tagName) !== 'BUTTON') {
                throw new Error('homepage inline Other entry is not a native button');
            }
            await inlineEntry.focus();
            await inlineEntry.press('Enter');
            await page.locator('#modal-content').waitFor({ state:'visible' });
            const focusInside = await page.evaluate(() =>
                document.getElementById('modal-content').contains(document.activeElement));
            if (!focusInside) throw new Error('inline Other entry did not move focus into the modal');
            await page.keyboard.press('Escape');
            await page.locator('#modal-host').waitFor({ state:'hidden' });
            const restoredId = await page.evaluate(() => document.activeElement && document.activeElement.id);
            if (restoredId !== 'briefing-about') {
                throw new Error('inline Other entry did not regain focus after Escape: ' + restoredId);
            }
            return 'homepage inline Other entry is a native keyboard button with opener focus restoration';
        });

        await check('slot-display-name-rename', async () => {
            await page.evaluate(() => {
                const host = document.getElementById('modal-host');
                if (host && host.style.display !== 'none') window.BootstrapApp.tryCloseModal();
            });
            await page.evaluate(() => {
                window.__bootstrapHarnessEmit({
                    cmd: 'list_resp',
                    slots: [
                        { slot:'crazyflasher7_saves', displayName:'健康档', characterName:'阿一', size:100, lastModified:'2026-08-29T10:00:00', corrupt:false, tombstoned:false, inconsistent:false },
                        { slot:'slot_duplicate', displayName:'重复名', characterName:'阿二', size:90, lastModified:'2026-08-29T09:00:00', corrupt:false, tombstoned:false, inconsistent:false },
                        { slot:'slot_tombstone', displayName:'删除标记档', size:0, tombstoned:true, corrupt:false, inconsistent:false },
                        { slot:'slot_inconsistent', displayName:'不一致档', size:80, tombstoned:false, corrupt:false, inconsistent:true },
                        { slot:'slot_corrupt', displayName:'损坏档', size:70, tombstoned:false, corrupt:true, inconsistent:false }
                    ]
                });
            });
            await page.locator('#btn-switch-slot').click();
            const rows = page.locator('#cards .save-row');
            const rename = page.locator('#save-actions .btn-rename');
            if (await rows.count() !== 3) throw new Error('expected two healthy rows and one corrupt row');
            await page.locator('#save-deleted').click();
            if (await rows.count() !== 1 || await page.locator('[data-slot="slot_tombstone"]').count())
                throw new Error('clean deletion markers leaked into the pending-work group');
            await page.locator('#cards [data-slot="slot_inconsistent"]').click();
            if (await rename.isVisible() || await page.locator('.btn-start').isVisible() || await page.locator('.btn-rebuild').isVisible())
                throw new Error('deleted residue offered ordinary character actions');
            await page.locator('#save-live').click();
            await page.locator('#cards').locator('[data-slot="slot_corrupt"]').click();
            if (!await rename.isVisible() || await page.locator('.btn-start').isVisible()) throw new Error('incorrect corrupt-slot actions');
            await page.locator('#cards').locator('[data-slot="crazyflasher7_saves"]').click();
            if (await page.locator('#save-title').textContent() !== '阿一'
                    || await page.locator('.save-row[aria-pressed="true"] .save-alias').textContent() !== '健康档') {
                throw new Error('character and display names must be distinguishable');
            }

            const outbound = cmd => page.evaluate(command => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === command).map(event => event.payload), cmd);
            const enterName = async value => {
                await rename.click();
                const field = page.locator('#confirm-field');
                if (await field.inputValue() !== '健康档') throw new Error('rename prefill did not match this slot');
                await field.fill(value);
                await field.press('Enter');
            };
            const dismiss = async fragment => {
                const message = page.locator('#confirm-dialog-message');
                await message.filter({hasText:fragment}).waitFor();
                await page.locator('#confirm-dialog-ok').click();
            };
            const reject = async reason => {
                await page.evaluate(error => window.__bootstrapHarnessEmit({
                    cmd:'rename_slot_resp', ok:false, slotKey:'crazyflasher7_saves', error
                }), reason);
                await dismiss(reason);
            };
            const before = (await outbound('rename_slot')).length;
            for (const name of ['坏\u0001名字', '界'.repeat(33)]) {
                await enterName(name);
                await dismiss('1–32');
            }
            if ((await outbound('rename_slot')).length !== before) throw new Error('invalid rename reached Host');
            const emojiName = 'é'.repeat(31) + '👩‍🚀';
            await enterName(emojiName);
            await rename.evaluate(button => button.click());
            const emojiWrites = await outbound('rename_slot');
            if (!await rename.isDisabled() || emojiWrites.length !== before + 1
                    || emojiWrites.at(-1).slotKey !== 'crazyflasher7_saves' || emojiWrites.at(-1).displayName !== emojiName) {
                throw new Error('32-grapheme name must dispatch once with the original physical key');
            }
            const lists = (await outbound('list')).length;
            await reject('harness reject');
            if ((await outbound('list')).length !== lists) throw new Error('failed rename triggered list refresh');
            await enterName('重复名');
            if ((await outbound('rename_slot')).at(-1).displayName !== '重复名') throw new Error('duplicate names should be accepted');
            await reject('duplicate probe complete');
            await enterName('   ');
            if ((await outbound('rename_slot')).at(-1).displayName !== '') throw new Error('blank should restore follow-character behavior');
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'rename_slot_resp', ok:true, slotKey:'crazyflasher7_saves', displayName:null, followsCharacterName:true
            }));
            await page.waitForFunction(() => document.querySelectorAll('#cards .save-row').length === 0);
            if ((await outbound('list')).length !== lists + 1) throw new Error('success should refresh exactly once');
            await page.locator('#btn-back-welcome').click();
            return 'live, corrupt and deleted detail actions, exact keys and Host-controlled refresh; invalid, emoji, duplicate and blank display names';
        });

        await check('archive-delete-and-import', async () => {
            const live = {slot:'Field_Beta', characterName:'乙'};
            const old = {slot:'legacy_test', characterName:'旧角色'};
            const list = slots => page.evaluate(rows => window.__bootstrapHarnessEmit({
                cmd:'list_resp', lastPlayedSlot:'LEGACY_TEST', slots:rows
            }), slots);
            const emit = msg => page.evaluate(value => window.__bootstrapHarnessEmit(value), msg);
            const outgoing = cmd => page.evaluate(command => window.__bootstrapHarnessEvents.filter(
                event => event.direction === 'out' && event.cmd === command).map(event => event.payload), cmd);
            await list([live,old]);
            if (await page.locator('#welcome-slot-name').textContent() !== '旧角色') throw new Error('case-varied last played key selected a different file');
            await page.locator('#btn-switch-slot').click();
            const oldRow = page.locator('.save-row[data-slot="legacy_test"]');
            await oldRow.click();
            const before = (await outgoing('delete')).length;
            if (await page.locator('.btn-delete').innerText() !== '移出列表') throw new Error('legacy removal promised file deletion');
            await page.locator('.btn-delete').click();
            if (!(await page.locator('#confirm-dialog-detail').innerText()).includes('更新启动器')) throw new Error('legacy confirmation omitted the Flash copy');
            await page.locator('#confirm-dialog-cancel').click();
            if ((await outgoing('delete')).length !== before) throw new Error('cancel sent a delete');
            await page.locator('.btn-delete').click();
            await page.locator('#confirm-dialog-ok').click();
            if ((await outgoing('delete')).at(-1).slot !== old.slot) throw new Error('delete lost the selected physical key');
            await emit({cmd:'delete_resp',ok:true,slot:live.slot});
            if (!await oldRow.isVisible() || !await page.locator('.btn-delete').isDisabled()) throw new Error('wrong receipt applied to old row');
            await emit({cmd:'delete_resp',ok:true,slot:old.slot});
            await page.waitForFunction(() => document.querySelectorAll('.save-row').length === 0);
            await list([live,{...old,tombstoned:true}]);
            if (await oldRow.count() || await page.locator('.save-row').count() !== 1
                    || await page.locator('#welcome-slot-name').textContent() !== '乙') throw new Error('deleted slot retained in list or welcome');
            if (await page.locator('#save-deleted').isVisible() || await oldRow.count())
                throw new Error('a completed deletion retained a recyclable slot');

            const importTo = async key => {
                await emit({cmd:'import_target',suggestedSlot:key,sourceData:'{}'});
                await page.locator('#confirm-dialog-ok').click();
            };
            const imports = (await outgoing('import_commit')).length;
            await importTo('LEGACY_TEST');
            await page.locator('#confirm-dialog-message').filter({hasText:'该槽位已删除'}).waitFor();
            await page.locator('#confirm-dialog-ok').click();
            if ((await outgoing('import_commit')).length !== imports || (await outgoing('reset')).length) throw new Error('import unprotected the tombstone');
            await importTo('field_beta');
            await page.locator('#confirm-dialog-message').filter({hasText:'存档已存在'}).waitFor();
            await page.locator('#confirm-dialog-ok').click();
            if ((await outgoing('import_commit')).at(-1).slot !== live.slot) throw new Error('overwrite lost the Host spelling');
            await importTo(live.slot);
            await list([{...live,tombstoned:true},{...old,tombstoned:true}]);
            await page.locator('#confirm-dialog-ok').click();
            await page.locator('#confirm-dialog-message').filter({hasText:'该槽位已删除'}).waitFor();
            await page.locator('#confirm-dialog-ok').click();
            if ((await outgoing('import_commit')).length !== imports + 1) throw new Error('target deleted during confirmation was overwritten');
            await page.locator('#save-live').click();
            if (await page.locator('.save-row').count() || !await page.locator('#btn-new').isVisible()) throw new Error('empty state consumed a row');
            await page.locator('#btn-back-welcome').click();
            return 'cancel, matched delete, list/default filtering, protected imports and case-insensitive physical target confirmation';
        });

        await check('editor-late-load-and-save', async () => {
            const emit = msg => page.evaluate(value => window.__bootstrapHarnessEmit(value), msg);
            await emit({cmd:'list_resp', slots:[{slot:'slot-a',characterName:'甲'}, {slot:'slot-b',characterName:'乙'}]});
            await emit({cmd:'state',state:'Idle'});
            await page.locator('#btn-switch-slot').click();
            const open = async key => {
                await page.locator('.save-row[data-slot="' + key + '"]').click();
                await page.locator('#save-actions .btn-edit').click();
            };
            const outgoing = cmd => page.evaluate(command => window.__bootstrapHarnessEvents.filter(
                event => event.direction === 'out' && event.cmd === command).map(event => event.payload), cmd);
            await open('slot-a');
            await page.locator('#ed-cancel').click();
            await open('slot-b');
            if (!await page.locator('#ed-save').isDisabled() || (await outgoing('load')).at(-1).slot !== 'slot-a') {
                throw new Error('late A must drain before B is requested');
            }
            const read = (slot, source) => emit({cmd:'load_resp',ok:true,slot,data:JSON.stringify({source})});
            await read('slot-a','old A');
            if ((await outgoing('load')).at(-1).slot !== 'slot-b' || !await page.locator('#ed-save').isDisabled()) throw new Error('late A populated B');
            await read('slot-a','duplicate A');
            if (!await page.locator('#ed-save').isDisabled()) throw new Error('wrong-slot duplicate armed save');
            await read('slot-b','current B');
            await page.locator('#tab-advanced').click();
            if (JSON.parse(await page.locator('#raw-ta').inputValue()).source !== 'current B') throw new Error('incorrect B payload');
            const writes = (await outgoing('save')).length;
            await page.locator('#ed-save').evaluate(button => { button.click(); button.click(); });
            const saved = await outgoing('save');
            if (saved.length !== writes + 1 || saved.at(-1).slot !== 'slot-b' || JSON.parse(saved.at(-1).data).source !== 'current B') {
                throw new Error('save must issue once for B with its own data');
            }
            await emit({cmd:'save_resp',ok:true,slot:'slot-a'});
            if (!await page.locator('#ed-cancel').isDisabled()) throw new Error('wrong save receipt unlocked B');
            await emit({cmd:'save_resp',ok:true,slot:'slot-b'});
            await page.locator('#modal-host').waitFor({state:'hidden'});
            await page.locator('#btn-back-welcome').click();
            return 'delayed and wrong-key reads cannot unlock or write B; duplicate clicks and wrong save replies are ignored';
        });

        await check('save-fixed-canvas', async () => {
            const emit = msg => page.evaluate(value => window.__bootstrapHarnessEmit(value), msg);
            await emit({cmd:'list_resp', uiFontScale:1.75, slots:[{slot:'layout-slot',characterName:'排版样本'}]});
            await emit({cmd:'state',state:'Idle'});
            await page.locator('#btn-switch-slot').click();
            const checkSizes = async (selector, buttons) => {
                for (const size of [{width:800,height:450}, {width:1366,height:768}, {width:2560,height:1080}]) {
                    await page.setViewportSize(size);
                    await page.waitForFunction(({selector,buttons}) => {
                        const el = document.querySelector(selector), box = el.getBoundingClientRect();
                        const parent = el.parentElement, area = parent.getBoundingClientRect();
                        const stage = document.getElementById('launcher-stage'), frame = stage.getBoundingClientRect();
                        const scale = Math.min(innerWidth/1024, innerHeight/576);
                        return stage.offsetWidth === 1024 && stage.offsetHeight === 576
                            && Math.abs(frame.width - scale * 1024) < .2 && Math.abs(frame.height - scale * 576) < .2
                            && Math.abs(frame.left * 2 + frame.width - innerWidth) < 1 && Math.abs(frame.top * 2 + frame.height - innerHeight) < 1
                            && Math.abs(box.width - area.width) < 1 && Math.abs(box.height - area.height) < 1
                            && buttons.every(id => {
                                const b = document.querySelector(id), r = b.getBoundingClientRect();
                                return b.contains(document.elementFromPoint(r.left + r.width/2, r.top + r.height/2));
                            });
                    }, {selector,buttons}, {timeout:3000});
                }
            };
            try {
                await checkSizes('#save-shell',['#btn-new','#btn-import','#save-actions .btn-edit','#save-actions .btn-delete']);
                await page.locator('#save-actions .btn-edit').click();
                await emit({cmd:'load_resp',ok:true,slot:'layout-slot',data:'{"version":"3.0"}'});
                await checkSizes('#modal-content',['#ed-save','#ed-cancel','#ed-close','#tab-tree']);
            } finally {
                await page.setViewportSize(viewport);
                await page.evaluate(() => window.BootstrapApp.tryCloseModal());
                await page.locator('#btn-back-welcome').click();
            }
            return 'centered 1024×576 logical canvas and hit-tested list/editor actions at 800×450, 1366×768 and 2560×1080';
        });

        await check('archive-directory-and-editor-density', async () => {
            const emit = msg => page.evaluate(value => window.__bootstrapHarnessEmit(value), msg);
            const slots = Array.from({length:20}, (_, i) => ({
                slot:'layout_' + String(i).padStart(2,'0'), characterName:'角色' + i,
                displayName:'归档' + i, mainProgress:'第 ' + i + ' 章', size:1200,
                lastModified:'2026-08-29T10:00:00'
            }));
            const key = 'old_' + 'a'.repeat(124);
            try {
                await page.setViewportSize({width:800,height:450});
                await emit({cmd:'list_resp',slots,uiFontScale:1.35});
                await page.locator('#btn-switch-slot').click();
                const geometry = await page.locator('#cards').evaluate(list => {
                    const box = list.getBoundingClientRect();
                    return {
                        fullRows:[...list.querySelectorAll('.save-row')].filter(el => {
                            const row = el.getBoundingClientRect();
                            return row.top >= box.top - 1 && row.bottom <= box.bottom + 1;
                        }).length,
                        docked:!list.contains(document.getElementById('save-detail')),
                        overflow:list.scrollWidth > list.clientWidth + 1
                    };
                });
                await page.mouse.move(1, 1);
                const scrollSkin = await page.evaluate(() => ['cards','save-detail'].map(id => {
                    const pane = document.getElementById(id);
                    const pseudo = name => getComputedStyle(pane, '::-webkit-scrollbar' + name);
                    return [pseudo('').width, pseudo('-track').backgroundColor, pseudo('-thumb').backgroundColor,
                        pseudo('-button').display, pseudo('-button').height];
                }));
                if (JSON.stringify(scrollSkin[0]) !== JSON.stringify(scrollSkin[1])
                    || scrollSkin[0][0] !== '7px' || scrollSkin[0][1] === 'rgba(0, 0, 0, 0)'
                    || scrollSkin[0][1] === scrollSkin[0][2] || scrollSkin[0][3] !== 'none' || scrollSkin[0][4] !== '0px')
                    throw new Error('archive scrollbar skin: ' + JSON.stringify(scrollSkin));
                if (geometry.fullRows < 10 || !geometry.docked || geometry.overflow) throw new Error('directory layout: ' + JSON.stringify(geometry));

                await emit({cmd:'list_resp',slots:slots.slice(0,11),uiFontScale:1.35});
                const editAction = page.locator('#save-actions .btn-edit');
                await editAction.focus();
                for (const font of [1.9,1.35]) {
                    await page.evaluate(value => window.BootstrapApp.setUiFontScale(value), font);
                    await page.waitForFunction(() => {
                        const detail = document.getElementById('save-detail');
                        return detail.getBoundingClientRect().left >= document.getElementById('cards').getBoundingClientRect().right
                            && document.activeElement === detail.querySelector('.btn-edit');
                    }, null, {timeout:3000});
                }

                const shortSlots = [
                    slots[0], {...slots[1],slot:key,characterName:'长'.repeat(30),displayName:'档'.repeat(32)}
                ];
                await emit({cmd:'list_resp',uiFontScale:1.9,slots:shortSlots});
                const selected = page.locator('.save-row[data-slot="' + key + '"]');
                await selected.click();
                if (!await selected.evaluate(b => !b.parentElement.contains(document.getElementById('save-detail')) && b.getAttribute('aria-pressed') === 'true')
                        || await page.locator('#save-key').textContent() !== key) throw new Error('short directory lost its right-hand actions or exact key');
                await emit({cmd:'state',state:'Idle'});
                await page.locator('#save-actions .btn-edit').focus();
                await page.keyboard.press('Enter');
                await emit({cmd:'load_resp',ok:true,slot:key,data:JSON.stringify({version:'3.0','0':['角色','男',500,8],'7':[0,0,0,0,0]})});
                await emit({cmd:'list_resp',uiFontScale:1.35,slots:shortSlots});
                const panel = page.locator('#ed-panel');
                const visibleFields = await panel.evaluate(el => {
                    const box = el.getBoundingClientRect();
                    return [...el.querySelectorAll('.schema-form input[data-idx], .schema-form select[data-idx]')].filter(input => {
                        const r = input.getBoundingClientRect();
                        return r.top >= box.top - 1 && r.bottom <= box.bottom + 1
                            && input.contains(document.elementFromPoint(r.left + r.width/2, r.top + r.height/2));
                    }).length;
                });
                if (visibleFields < 12) throw new Error('only ' + visibleFields + ' editable fields visible');
                const level = panel.getByLabel('等级',{exact:true});
                if (await level.inputValue() !== '8' || !await level.getAttribute('aria-describedby')) throw new Error('level control lost its value or limits');
                await level.focus();
                const rangeClearsInput = await level.evaluate(input => {
                    const hint = document.getElementById(input.getAttribute('aria-describedby'));
                    return hint.getBoundingClientRect().top >= input.getBoundingClientRect().bottom;
                });
                if (!rangeClearsInput) throw new Error('the numeric range covers the editable value');
                await page.locator('#tab-advanced').click();
                await page.locator('#ed-search-toggle').click();
                await page.getByLabel('搜索字段或内容').press('Escape');
                if (await page.locator('#ed-search').count() || !await page.locator('#ed-save').isVisible()
                        || !await page.locator('#ed-search-toggle').evaluate(el => el === document.activeElement)) throw new Error('Escape did not return focus from search to the editor');
                await page.locator('#tab-simple').click();
                await level.fill('9');
                await page.locator('#ed-save').click();
                const write = await page.evaluate(() => window.__bootstrapHarnessEvents.filter(e => e.direction === 'out' && e.cmd === 'save').at(-1).payload);
                if (write.slot !== key || write.data['0'][3] !== 9) throw new Error('form write lost original key or field');
                await emit({cmd:'save_resp',ok:true,slot:key});
                await page.locator('#modal-host').waitFor({state:'hidden'});
                return geometry.fullRows + ' complete directory rows and ' + visibleFields + ' editable controls at 800×450; long key, keyboard actions and labeled field write verified';
            } finally {
                await page.setViewportSize(viewport);
                await page.evaluate(() => window.BootstrapApp.tryCloseModal());
                await page.locator('#btn-back-welcome').click();
            }
        });

        await check('native-button-enter', async () => {
            await page.locator('#btn-switch-slot').click();
            const button = page.locator('#btn-new');
            await button.focus();
            await button.press('Enter');
            await page.waitForFunction(() => !document.getElementById('view-character-create').hidden
                && document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            const opens = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'character_create_open').length);
            if (opens !== 1) throw new Error('expected one character_create_open, got ' + opens);
            // The character-create view is deliberately visibility-hidden and inert
            // until its live snapshot and first paper-doll frame are ready. Escape is
            // the supported cancellation path while that preparation mask owns focus.
            await page.keyboard.press('Escape');
            await page.waitForFunction(() => !document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            return 'focused new-save button opened exactly once and preparation remained cancellable by Escape';
        });

        await check('catalog-search-sort-repair-and-exact-undo', async () => {
            const emit = payload => page.evaluate(msg => window.__bootstrapHarnessEmit(msg), payload);
            const sent = cmd => page.evaluate(c => window.__bootstrapHarnessEvents.filter(e => e.direction === 'out' && e.cmd === c).map(e => e.payload), cmd);
            const fixture = [
                {slot:'alpha-test', characterName:'甲', gender:'男', difficulty:'平衡模式', appearance:{face:'男脸',hair:'短发'},
                 editUndoToken:'7a4b62551c9648779e4af94e8ee2b520', lastPlayed:'2026-10-04T09:00:00Z'},
                {slot:'beta-test', characterName:'乙', lastPlayed:'2026-10-05T09:00:00Z'},
                {slot:'broken-test', corrupt:true}
            ];
            await emit({cmd:'list_resp', archiveRequestIds:true, slots:fixture});
            if (await page.locator('.save-row').first().getAttribute('data-slot') !== 'beta-test') throw new Error('recent play sort lost its latest slot');
            await page.locator('#save-search').fill('alpha');
            if (await page.locator('.save-row').count() !== 1 || !(await page.locator('#save-character-meta').innerText()).includes('短发'))
                throw new Error('search did not retain the exact physical row and character facts');
            await page.locator('#save-actions [data-action="undo"]').click();
            await page.locator('#confirm-dialog-ok').click();
            const request = (await sent('undo_edit')).at(-1);
            if (request.slot !== fixture[0].slot || request.undoToken !== fixture[0].editUndoToken || !request.requestId)
                throw new Error('undo must preserve the token, exact key and one live request');
            const lists = (await sent('list')).length;
            await emit({cmd:'undo_edit_resp', ok:true, slot:request.slot, requestId:'wrong'});
            if ((await sent('list')).length !== lists) throw new Error('stale undo acknowledged');
            await emit({cmd:'undo_edit_resp', ok:true, slot:request.slot, requestId:request.requestId});
            if ((await sent('list')).length !== lists+1) throw new Error('confirmed undo did not reconcile');
            await emit({cmd:'list_resp', slots:fixture});
            await page.locator('#save-search').fill('');
            await page.locator('#save-sort').selectOption('slot');
            if (await page.locator('.save-row').first().getAttribute('data-slot') !== 'alpha-test') throw new Error('slot sort changed key order');
            await page.locator('.save-row[data-slot="broken-test"]').click();
            const cancels = (await sent('cancel_launch')).length;
            await page.locator('#save-actions [data-action="repair"]').click();
            await page.locator('#rc-export').click();
            const exported = (await sent('export')).at(-1);
            if (exported.slot !== 'broken-test' || !exported.forceRaw || await page.locator('#rc-force').count()) throw new Error('catalog repair did not use exact raw export');
            await page.locator('#rc-back').click();
            if ((await sent('cancel_launch')).length !== cancels) throw new Error('catalog repair closed a game launch');
            await page.locator('#save-sort').selectOption('recent');
            return 'search, character metadata, sort, editor undo identities and non-launching catalog repair verified';
        });

        await check('archive-equipment-busts-and-level', async () => {
            const emit = message => page.evaluate(value => window.__bootstrapHarnessEmit(value), message);
            const face = {face:'男变装-基本脸型',hair:'发型-男式-Andy发型'};
            const live = {slot:'portrait-a',characterName:'阿七',displayName:'远征',mainProgress:'阿七 Lv.35',
                gender:'男',appearance:{...face,upper:'浅灰背心'}};
            const other = {...live,slot:'portrait-b',appearance:{...face,equipment:{body:'剑圣胸甲'}}};
            const legacy = {slot:'portrait-old',characterName:'巡逻员',mainProgress:'任务进行中'};
            await emit({cmd:'list_resp',slots:[live,other,legacy]});
            const row = key => page.locator('.save-row[data-slot="' + key + '"]');
            const detail = page.locator('#save-detail-portrait');
            const image = async tile => {
                const img = tile.locator('img:not([hidden]):not(.save-equip img)');
                await img.waitFor({state:'visible',timeout:6000});
                return img.getAttribute('src');
            };
            await row(live.slot).click();
            const shirt = await image(detail);
            if (await image(row(live.slot)) !== shirt
                    || !(await page.locator('#save-progress-detail').innerText()).includes('Lv.35'))
                throw new Error('the list and detail disagree on the legacy outfit or level');
            await row(other.slot).click();
            const armor = await image(detail);
            if (armor === shirt || armor !== await image(row(other.slot)))
                throw new Error('the same face and hair with a different chest item must produce a different bust');
            const helmet = {...other,appearance:{...face,equipment:{body:'剑圣胸甲',head:'黑色摩托头盔'}}};
            await emit({cmd:'list_resp',slots:[live,helmet,legacy]});
            const helmetArt = await image(detail);
            if (helmetArt === armor || helmetArt !== await image(row(other.slot)))
                throw new Error('changing only a helmet reused the old outfit');
            const small = await row(live.slot).locator('.save-avatar').boundingBox();
            await page.locator('#save-large-busts').click();
            const large = await row(live.slot).locator('.save-avatar').boundingBox();
            if (large.width <= small.width) throw new Error('large-bust browsing did not enlarge the gear');
            await page.locator('#save-large-busts').click();
            await row(legacy.slot).click();
            if (await detail.locator('img:not([hidden])').count() || await detail.getAttribute('data-initial') !== '巡'
                    || await page.locator('#save-progress-detail').innerText() !== '任务进行中')
                throw new Error('partial legacy data fabricated an outfit or lost stored progress');
            const sidearm = {...other,appearance:{...face,equipment:{secondary1:'M1911',hand:'训练手套'}}};
            await emit({cmd:'list_resp',slots:[live,sidearm,legacy]});
            await row(other.slot).click();
            if (await row(other.slot).locator('.save-equip[data-item="M1911"]').count() !== 1
                    || await page.locator('#save-equipment .save-equip[data-item="训练手套"]').count() !== 1)
                throw new Error('a sidearm or gloves must identify an outfit without a chest item');
            await emit({cmd:'list_resp',slots:[{...live,corrupt:true},other,legacy]});
            await row(live.slot).click();
            if (await detail.locator('img:not([hidden])').count() || await page.locator('.btn-start').isVisible())
                throw new Error('a damaged archive inherited a playable character');
            return 'original mercenary busts distinguish chest and head equipment with identical face/hair, including refreshed slots and old Host fields';
        });

        await check('archive-equipment-art-and-inspection', async () => {
            const emit = slots => page.evaluate(list => window.__bootstrapHarnessEmit({cmd:'list_resp',slots:list}), slots);
            const equipment = {primary:'特勤霰弹枪',grenade:'压缩胶囊之盗贼',body:'重装特勤背心',head:'重装特勤头盔',foot:'重装特勤战靴'};
            const first = {slot:'archive-outfit-a',characterName:'巡逻员',displayName:'第一班',appearance:{equipment}};
            const legacy = {slot:'archive-outfit-b',characterName:'巡逻员',appearance:{upper:'旧装<甲>'}};
            await emit([first,legacy]);
            const row = page.locator('.save-row[data-slot="archive-outfit-a"]');
            await row.click();
            const gear = page.locator('#save-equipment');
            if (await row.locator('.save-equip').count() !== 2 || await gear.locator('button').count() !== 5
                    || await row.locator('.save-alias').innerText() !== '第一班')
                throw new Error('row and detail must preserve the alias, two preview icons and the complete outfit');
            const body = gear.getByRole('button',{name:'上装 · 重装特勤背心',exact:true});
            await page.waitForFunction(() => {
                const img = document.querySelector('#save-equipment [data-item="重装特勤背心"] img');
                return img?.complete && img.naturalWidth > 0 && img.getAttribute('src') === window.Icons.resolveStatic('Codex-重装特勤背心');
            }, null, {timeout:6000});
            const card = page.locator('#panel-tooltip');
            await row.locator('[data-item="特勤霰弹枪"]').hover();
            await page.waitForFunction(() => window.PanelTooltip.isVisible() && document.querySelector('#panel-tooltip').textContent.includes('第一防线'));
            await body.click();
            await card.locator('.panel-tooltip-inspector-header').waitFor({state:'visible'});
            const text = await card.innerText();
            if (!['重装特勤背心','等级限制 21','基础属性','铭牌仍写着POLICE'].every(value => text.includes(value)))
                throw new Error('pinned archive tooltip lost authored content or stat context');
            await page.keyboard.press('Escape');
            if (await page.evaluate(() => window.PanelTooltip.isVisible()) || !await page.locator('#cards').isVisible())
                throw new Error('Escape should dismiss only the pinned gear');
            await page.mouse.move(1, 1);
            const capsule = gear.getByRole('button',{name:'手雷 · 实体投影之盗贼',exact:true});
            await capsule.focus();
            await page.keyboard.press('Tab');
            await page.waitForFunction(() => document.activeElement?.dataset.item === '重装特勤背心' &&
                window.PanelTooltip.isVisible() && document.querySelector('#panel-tooltip').textContent.includes('铭牌仍写着POLICE'));
            await capsule.hover();
            await card.locator('.ntt-doc span[style*="color"]').filter({hasText:'降兵'}).first().waitFor({state:'visible'});
            if ((await card.innerText()).includes('<font')) throw new Error('source markup leaked into the description');
            await page.locator('.save-row[data-slot="archive-outfit-b"]').click();
            const fallback = gear.getByRole('button',{name:'上装 · 旧装<甲>',exact:true});
            await fallback.hover();
            await page.waitForFunction(() => window.PanelTooltip.isVisible() &&
                document.querySelector('#panel-tooltip').textContent.includes('旧装<甲>'));
            if (await fallback.locator('img').count() || (await card.innerText()).includes('铭牌仍写着POLICE'))
                throw new Error('unknown legacy gear should keep its literal name and have no stale artwork or description');
            await emit([{...first,appearance:{equipment:{primary:'AK47火麒麟'}}}]);
            await gear.locator('[data-item="AK47火麒麟"]').hover();
            await card.locator('.flash-tt-icon [data-icon-layer-index]').first().waitFor({state:'visible',timeout:5000});
            if (await row.locator('.save-equip img').count() !== 1 || await row.locator('[data-icon-layer-index]').count())
                throw new Error('only the inspected item should expand into its animated layers');
            return 'real inventory art, authored description, legacy fallback, pointer and keyboard inspection before game entry';
        });

        await check('archive-signatures-match-home-and-survive-catalog-changes', async () => {
            const first = {slot:'signature-a',characterName:'阿七',appearance:{upper:'剑圣胸甲'}};
            const other = {...first,slot:'signature-b'};
            const emit = slots => page.evaluate(list => window.__bootstrapHarnessEmit({cmd:'list_resp',slots:list,lastPlayedSlot:'signature-a'}), slots);
            const row = key => page.locator('.save-row[data-slot="'+key+'"]');
            const bars = async badge => {
                await badge.locator('i').nth(18).waitFor({state:'attached',timeout:5000});
                return badge.locator('i').evaluateAll(nodes => nodes.map(node => node.style.height).join(','));
            };
            await emit([first,other]);
            const origin = await bars(row(first.slot).locator('.slot-sig'));
            if (origin === await bars(row(other.slot).locator('.slot-sig')))
                throw new Error('same-name same-equipment save copies should be visually distinguishable in this fixture');
            await row(first.slot).click();
            await page.locator('#btn-back-welcome').click();
            if (await bars(page.locator('#welcome-slot-sig')) !== origin) throw new Error('home and archive fingerprints differ');
            await page.locator('#btn-switch-slot').click();
            await emit([other,{...first,displayName:'新名称',appearance:{upper:'重装特勤背心'}}]);
            await page.locator('#save-sort').selectOption('name');
            if (await bars(row(first.slot).locator('.slot-sig')) !== origin) throw new Error('rename, outfit or reordering changed a fingerprint');
            await page.locator('#save-sort').selectOption('recent');
            return '19 bars are stable across home, selection, rename, kit changes, sorting and catalog refresh';
        });

        await check('archive-large-font-keeps-progress-and-paints-visible-signatures', async () => {
            const previousSize = page.viewportSize();
            const slots = Array.from({length:100}, (_,i) => ({
                slot:'density-'+i, characterName:'巡逻员', mainProgress:'巡逻员 Lv.99', storyProgress:780,
                lastModified:new Date(Date.now() - (i+1)*3600000).toISOString(), appearance:{upper:'重装特勤背心'}
            }));
            const update = scale => page.evaluate(input => window.__bootstrapHarnessEmit(input),
                {cmd:'list_resp',slots,uiFontScale:scale});
            const button = page.locator('#save-large-busts');
            const first = page.locator('.save-row').first();
            const last = page.locator('.save-row').last();
            try {
                await page.setViewportSize({width:800,height:450});
                await update(1.9);
                await first.locator('.slot-sig i').nth(18).waitFor({state:'attached'});
                if (await last.locator('.slot-sig i').count()) throw new Error('off-screen fingerprints painted before scrolling');
                for (const large of [false,true]) {
                    if ((await button.getAttribute('aria-pressed') === 'true') !== large) await button.click();
                    if (!await first.evaluate(row => ['.save-progress','time'].every(selector => {
                        const cell = row.querySelector(selector);
                        return cell.scrollWidth <= cell.clientWidth;
                    }))) throw new Error('progress or recent time clipped at the maximum font size');
                }
                await last.scrollIntoViewIfNeeded();
                await last.locator('.slot-sig i').nth(18).waitFor({state:'attached'});
            } finally {
                if (await button.getAttribute('aria-pressed') === 'true') await button.click();
                await page.setViewportSize(previousSize);
                await update(1.35);
            }
            return 'normal and enlarged busts retain level, story and time at 800×450 with 100 saves';
        });

        await check('container-keyboard-navigation', async () => {
            const slots = [{slot:'nav-a',characterName:'甲'},{slot:'nav-b',characterName:'乙',displayName:'远征'}];
            const emit = message => page.evaluate(value => window.__bootstrapHarnessEmit(value), message);
            const sent = cmd => page.evaluate(key => window.__bootstrapHarnessEvents
                .filter(e => e.direction === 'out' && e.cmd === key).map(e => e.payload), cmd);
            for (const intro of [false,true]) {
                await emit({cmd:'list_resp',slots,introEnabled:intro});
                if (!await page.locator('#cards').isVisible()) await page.locator('#btn-switch-slot').click();
                const first = page.locator('.save-row[data-slot="nav-a"]');
                await first.click();
                await first.press('ArrowDown');
                const selected = page.locator('.save-row[aria-pressed="true"]');
                if (await selected.getAttribute('data-slot') !== 'nav-b') throw new Error('ArrowDown lost the intended slot');
                const before = (await sent('start_game')).length;
                const reveals = (await sent('reveal_ok')).length;
                await selected.press('Enter');
                const requests = await sent('start_game'), request = requests.at(-1);
                if (requests.length !== before + 1 || request.slot !== 'nav-b' || request.requireFlashReveal !== true
                        || !!request.deferReveal !== intro) throw new Error('directory launch lost slot, intro setting or reveal fence');
                if (intro) {
                    await page.waitForFunction(() => {
                        const video = document.getElementById('intro-video');
                        return video.readyState >= video.HAVE_CURRENT_DATA && video.videoWidth > 0;
                    }, null, {timeout:10000});
                    if (await page.locator('#intro-skip').isVisible()) await page.locator('#intro-skip').click();
                    await page.waitForFunction(count => window.__bootstrapHarnessEvents.filter(e => e.direction === 'out'
                        && e.cmd === 'reveal_ok').length === count + 1, reveals);
                }
                if (await page.locator('.loading-title').innerText() !== '乙 · 远征') throw new Error('loading shows the wrong save');
                await emit({cmd:'state',state:'WaitingGameReady'});
                await emit({cmd:'state',state:'Ready'});
                if (!await page.locator('#intro-ov.loading').isVisible()
                        || await page.locator('#loading-stages').getAttribute('data-stage') !== '3')
                    throw new Error('Ready incorrectly handed off the screen');
                const cancels = (await sent('cancel_launch')).length;
                if (intro) await page.keyboard.press('Escape'); else await page.locator('#loading-cancel').click();
                if ((await sent('cancel_launch')).length !== cancels + 1) throw new Error('cancel did not reach the current launch once');
                await emit({cmd:'state',state:'Idle'});
            }
            return 'both intro settings preserve the chosen slot, single launch, player title, real state and click/Esc cancel';
        });

        // PM19 V3：以下断言共用 pm19-arrival-kind 内 reload 出的全新控制器实例；
        // reducedMotion 静态态下 cue 只创建不播放，kind 驻留在 inspect()。
        await check('pm19-arrival-kind', async () => {
            // 主页面背景已被 host reveal retire；reload 复用同一 page 的
            // init script/route/reducedMotion，得到未 retire 的新实例。
            await page.reload({ waitUntil:'load' });
            await page.evaluate(async () => { window.__pm19Harness = await import('./modules/bg-gl/main.mjs'); });
            await page.waitForFunction(() => {
                const state = window.__pm19Harness.inspect();
                return state.cue && state.cues === 1;
            }, null, { timeout:10000 });
            const state = await backgroundState(page);
            if (state.cue.kind !== 'arrival' || state.cue.duration !== 2000 || state.cues !== 1
                    || state.visualKind !== 'arrival' || state.pendingSync || state.userIntent) {
                throw new Error('first list_resp must park exactly one unplayed arrival cue: '
                    + JSON.stringify({ cue:state.cue, visualKind:state.visualKind }));
            }
            return 'reduced motion keeps the arrival cue created-but-unplayed (kind arrival, 2000ms)';
        });

        await check('pm19-sync-gated-by-intent', async () => {
            // confirm 监听绑在真实按钮上，DOM click() 绕过视图遮挡的 actionability；
            // hostState 已是 prewarm Ready（state 去重 early-return），先离开再回来模拟真实启动序列。
            await page.evaluate(() => {
                window.__bootstrapHarnessEmit({ cmd:'list_resp', introEnabled:false,
                    lastPlayedSlot:'pm19-fixture', slots:[{ slot:'pm19-fixture', characterName:'测试角色',
                        displayName:'测试存档', size:4096, lastModified:'2026-09-13T00:00:00', corrupt:false }] });
                // 生产顺序是确认在先、业务随即接管 loading 相（showLoadingOverlay 加 intro-playing），
                // 叙事层在 loading 前的空档武装；兜底补 class 防业务路径变化。
                document.getElementById('btn-confirm-start').click();
                if (!document.body.classList.contains('intro-playing')) document.body.classList.add('intro-playing');
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Spawning', msg:'harness-spawn' });
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Ready', msg:'harness-ready' });
            });
            const state = await backgroundState(page);
            const parked = state.pendingSync === true || (state.cue && state.cue.kind === 'sync');
            if (!parked || state.visualKind !== 'sync' || !state.userIntent) {
                throw new Error('Ready under intent+loading must park or start the sync cue: '
                    + JSON.stringify({ cue:state.cue, pendingSync:state.pendingSync,
                        visualKind:state.visualKind, userIntent:state.userIntent }));
            }
            return 'gated sync reaches the cue layer; prewarm stays covered by pm19-late-subscription-replay';
        });

        await check('pm19-stage-text', async () => {
            await page.evaluate(() => {
                document.body.classList.add('intro-playing');
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Embedding', msg:'harness-embed' });
            });
            await page.waitForFunction(() => {
                const el = document.querySelector('#intro-ov .loading-text');
                return el && el.textContent === '正在载入游戏画面'
                    && document.getElementById('loading-stages').dataset.stage === '2';
            }, null, { timeout:3000 });
            return 'loading stage text follows the real host state';
        });

        await check('pm19-lore-lifecycle', async () => {
            await page.evaluate(() => document.body.classList.add('intro-playing'));
            await page.waitForFunction(() => {
                const log = document.getElementById('bg-gl-log');
                return log && log.classList.contains('visible')
                    && log.querySelectorAll('.ln').length >= 1;
            }, null, { timeout:3000 });
            const state = await backgroundState(page);
            if (!Array.isArray(state.lore) || !state.lore.length) {
                throw new Error('inspect().lore must expose a non-empty line snapshot during loading');
            }
            // FIFO 无 TTL：静默等待 1.3s 行数不减少；state 头行驻留计时随 tick 增长。
            // tick 在 reduced-motion 下按纪律停摆，本段临时切回 no-preference 再恢复。
            await page.emulateMedia({ reducedMotion:'no-preference' });
            const before = await page.evaluate(() => ({
                count: document.querySelectorAll('#bg-gl-log .ln').length,
                head: (document.querySelector('#bg-gl-log .ln:last-child .dim') || { textContent: '' }).textContent,
            }));
            await page.waitForTimeout(1300);
            const after = await page.evaluate(() => ({
                count: document.querySelectorAll('#bg-gl-log .ln').length,
                head: (document.querySelector('#bg-gl-log .ln:last-child .dim') || { textContent: '' }).textContent,
            }));
            await page.emulateMedia({ reducedMotion:'reduce' });
            if (after.count < before.count) {
                throw new Error('FIFO queue lost lines to a hidden TTL: '
                    + JSON.stringify({ before, after }));
            }
            if (after.head === before.head && /^\w+ · \+\d+\.\d+s/.test(before.head)) {
                throw new Error('head state line dwell did not tick: '
                    + JSON.stringify({ before, after }));
            }
            // retire 后 #bg-gl-log 不存在的复验由 host-reveal-retires-gpu-background 既有断言覆盖。
            return 'lore FIFO persists without TTL and head dwell ticks live';
        });

        await check('pm19-lore-masked', async () => {
            await page.waitForFunction(() => {
                const el = document.getElementById('bg-gl-log');
                const canvas = window.__pm19Harness.inspect().canvas;
                if (!el || !canvas) return false;
                const rect = el.getBoundingClientRect();
                const frame = document.getElementById('bg-gl').getBoundingClientRect(), ratio = canvas.width / frame.width;
                return canvas.masks.some(mask => Math.abs(mask.x - (rect.x - frame.x) * ratio) <= 8
                    && Math.abs(mask.y - (rect.y - frame.y) * ratio) <= 8
                    && Math.abs(mask.w - rect.width * ratio) <= 8 && Math.abs(mask.h - rect.height * ratio) <= 8);
            }, null, { timeout:3000 });
            return 'the loading mask set covers the lore stream within 8px';
        });

        await check('pm19-boot-lines', async () => {
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'boot', frame:53,
                messages:'[BootstrapAS] 合成表数据加载完毕|[BootstrapAS] S2_ENTER|其它噪声|[BootstrapAS] 读取存档数据……'
            }));
            await page.waitForFunction(() => {
                const lines = window.__pm19Harness.inspect().lore || [];
                return lines.some(line => line.text === '合成表数据加载完毕')
                    && lines.some(line => line.text === '读取存档数据……');
            }, null, { timeout:3000 });
            const lines = (await backgroundState(page)).lore || [];
            if (lines.some(line => /S2_ENTER|其它噪声/.test(line.text + ' ' + line.suffix))) {
                throw new Error('boot stream leaked a signal token or prefix-less noise');
            }
            const bootLine = lines.find(line => line.text === '合成表数据加载完毕');
            if (bootLine.suffix && bootLine.suffix !== 'boot · 批次 f53') {
                throw new Error('boot line carried an unexpected suffix: ' + bootLine.suffix);
            }
            return 'two Chinese boot lines narrated; S2_ENTER token and prefix-less noise dropped';
        });

        await check('pm19-comm-suffix', async () => {
            // 600ms 沉降让 lore 洪水窗口排空，socket 后缀断言不被省后缀机制吞掉。
            await page.waitForTimeout(600);
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'state', state:'WaitingGameReady',
                socketPort:1924, httpPort:1192, flashConnected:true
            }));
            await page.waitForFunction(() => {
                const state = window.__pm19Harness.inspect();
                const last = state.lore && state.lore[state.lore.length - 1];
                return !!(state.comm && state.comm.socketPort === 1924
                    && last && (last.text + ' ' + last.suffix).includes('socket=1924'));
            }, null, { timeout:3000 });
            const state = await backgroundState(page);
            if (state.comm.httpPort !== 1192 || state.comm.flashConnected !== true) {
                throw new Error('comm snapshot dropped httpPort/flashConnected: ' + JSON.stringify(state.comm));
            }
            return 'WaitingGameReady lore suffix carries socket=1924; inspect().comm snapshots all three fields';
        });

        await check('pm19-degraded-reveal', async () => {
            await page.waitForTimeout(600);
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'flash_ready', degraded:true }));
            await page.waitForFunction(() => {
                const lines = window.__pm19Harness.inspect().lore || [];
                return lines.some(line => line.text.includes('降级开门'));
            }, null, { timeout:3000 });
            const line = (await backgroundState(page)).lore.find(entry => entry.text.includes('降级开门'));
            if (!line || line.suffix !== 'degraded:true') {
                throw new Error('degraded reveal lost its dim suffix: ' + JSON.stringify(line));
            }
            return 'degraded flash_ready narrates 降级开门 with degraded:true dim suffix';
        });

        await check('pm19-weblog-sink', async () => {
            // sink 的 2s 泵自 lore 挂载起就批量外发；mock 对每条 log 即回 log_resp unknown_cmd，
            // 能力探测在首个回执后永久停用——运行到这里 dead 早已成立，只验证据链。
            await page.waitForFunction(() => {
                const sent = window.__bootstrapHarnessEvents
                    .some(event => event.direction === 'out' && event.cmd === 'log');
                return sent && window.__pm19Harness.inspect().logSinkDead === true;
            }, null, { timeout:10000 });
            const first = await page.evaluate(() => {
                const event = window.__bootstrapHarnessEvents
                    .find(entry => entry.direction === 'out' && entry.cmd === 'log');
                return event ? String(event.payload.text || '') : '';
            });
            if (!first.includes('质数幻方种子库验讫')) {
                throw new Error('first weblog batch did not carry lore text: ' + first.slice(0, 160));
            }
            const sentBefore = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'log').length);
            // dead 后泵仍排水但不再出站；再产一行 lore 佐证。
            await page.evaluate(() => window.__bootstrapHarnessEmit({ cmd:'state', state:'Spawning', msg:'sink-probe' }));
            await page.waitForTimeout(2400);
            const sentAfter = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'log').length);
            if (sentAfter !== sentBefore) {
                throw new Error('weblog sink kept sending after unknown_cmd: ' + sentBefore + ' -> ' + sentAfter);
            }
            return 'lore lines batched to host once; unknown_cmd receipt permanently disabled the sink';
        });

        await check('pm19-orbit-readout', async () => {
            // 前序 check 经真实确认流程进过 loading 相：_introActive 是 bootstrap-main 内部旗标，
            // 不移除它 ESC 会被 intro 层吃掉（发 cancel_launch）而非关 modal；Idle 广播走正规解除路径。
            await page.evaluate(() => {
                window.__bootstrapHarnessEmit({ cmd:'state', state:'Idle' });
                document.body.classList.remove('intro-playing', 'intro-video');
                document.getElementById('btn-about').click();
            });
            await page.waitForFunction(() => {
                const el = document.getElementById('pm19-orbit');
                return !!(el && /^轨道 #\d+ · 中心质数 \d+ · Σ=190,000,361 · 单轨 743,178,240 态$/.test(el.textContent));
            }, null, { timeout:5000 });
            const text = (await page.locator('#pm19-orbit').textContent()) || '';
            const center = Number((/中心质数 (\d+)/.exec(text) || [])[1]);
            const KNOWN_CENTERS = [9961981, 10037957, 10031191, 9973049, 10025497, 10008491, 10007293, 10011367];
            if (!KNOWN_CENTERS.includes(center)) {
                throw new Error('orbit center is not a packaged prime: ' + text);
            }
            await page.keyboard.press('Escape');
            await page.locator('#modal-host').waitFor({ state:'hidden' });
            return text;
        });

        await check('pm19-kinds-known', async () => {
            const unknown = consoleLogs.filter(line => line.indexOf('unknown cue kind') !== -1);
            if (unknown.length) {
                throw new Error('renderer warned about unknown cue kinds: ' + unknown.join(' | '));
            }
            return 'no unknown-kind renderer warnings across the whole run';
        });

        await check('pm19-exchange-variants', async () => {
            // 既有场景均为静态或 <8s 活动态，观察不到偶数拍；按规格退化为控制器源码存在性断言。
            const source = await page.evaluate(async () =>
                (await fetch('modules/bg-gl/main.mjs')).text());
            if (source.indexOf("'exchange-pair'") === -1 || !/cycles\s*%\s*2/.test(source)) {
                throw new Error('exchange-pair even-tick alternation is missing from the controller');
            }
            return 'skipped the live even-tick cue (no scene stays active >8s); exchange-pair parity verified in controller source';
        });

        await check('archive-correlated-replies', async () => {
            await page.reload();
            const emit = message => page.evaluate(m => window.__bootstrapHarnessEmit(m), message);
            const last = cmd => page.evaluate(name => window.__bootstrapHarnessEvents
                .filter(e => e.direction === 'out' && e.cmd === name).at(-1).payload, cmd);
            await page.waitForFunction(() => window.__bootstrapHarnessEvents.some(e => e.cmd === 'list_resp'));
            await emit({cmd:'state',state:'Idle'});
            const slots = ['first','second'].map(slot => ({slot,characterName:'同名角色',displayName:slot}));
            await emit({cmd:'list_resp',archiveRequestIds:true,slots});
            await page.locator('#btn-switch-slot').click();
            const open = async slot => {
                await page.locator('.save-row[data-slot="' + slot + '"]').click();
                await page.locator('#save-actions .btn-edit').click();
                return last('load');
            };
            const first = await open('second');
            await page.locator('#ed-cancel').click();
            const middle = await open('first');
            await page.locator('#ed-cancel').click();
            const current = await open('second');
            const ids = [first,middle,current].map(x => x.requestId);
            if (new Set(ids).size !== 3 || !ids.every(Number.isSafeInteger)) throw new Error('reads lack distinct IDs');
            const data = JSON.stringify({version:'3.0','0':['当前','男',1000,11]});
            for (const old of [first,middle]) await emit({...old,cmd:'load_resp',ok:true,data});
            await emit({cmd:'load_resp',slot:'second',ok:false,error:'late failure'});
            if (!await page.locator('#ed-save').isDisabled()) throw new Error('an old read unlocked the editor');
            await emit({...current,cmd:'load_resp',ok:true,data});
            await page.locator('#ed-panel').getByLabel('等级',{exact:true}).fill('12');
            await page.locator('#ed-save').click();
            const save = await last('save');
            if (save.slot !== 'second' || save.data['0'][3] !== 12) throw new Error('wrong write');
            await emit({cmd:'save_resp',slot:save.slot,ok:true,requestId:first.requestId});
            if (!await page.locator('#ed-cancel').isDisabled()) throw new Error('old receipt released the write');
            await emit({cmd:'save_resp',slot:save.slot,ok:false,requestId:save.requestId,error:'slot_tombstoned'});
            if (!(await page.locator('#ed-status').textContent()).includes('slot_tombstoned')) throw new Error('no exact rejection');
            page.once('dialog', d => d.accept());
            await page.locator('#ed-cancel').click();
            await emit({cmd:'list_resp',ok:false,error:'test'});
            if (await page.locator('.save-row').count() !== 2) throw new Error('list failure erased the directory');
            return 'same-name, same-slot reopen, late messages, exact write rejection and failed directory refresh';
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
        cancelledIntroStreams,
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
