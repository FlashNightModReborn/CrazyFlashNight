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
            await page.waitForFunction(() => document.querySelectorAll('#cards .card').length === 1, null, { timeout: 10000 });
            const events = await page.evaluate(() => window.__bootstrapHarnessEvents.slice());
            if (!events.some(event => event.direction === 'in' && event.cmd === 'list_resp')) {
                throw new Error('host list_resp was not delivered');
            }
            return 'one identity-free new-save card rendered from a zero-delay empty host response';
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
            const intro = page.locator('.chk-intro');
            await intro.hover();
            await page.waitForTimeout(380);
            if (await tooltip.count() !== 1) throw new Error('pointer tooltip did not appear before click');
            await intro.click();
            await page.waitForTimeout(380);
            if (await tooltip.count() !== 0) throw new Error('pointer click resurrected its tooltip through focusin');
            await button.evaluate(element => element.blur());
            if (await page.locator('.boot-tooltip.on').count() !== 0) throw new Error('blur did not hide tooltip');
            await page.locator('#btn-switch-slot').click();
            const cardButton = page.locator('#cards .btn-newchar').first();
            await cardButton.focus();
            await page.waitForTimeout(380);
            const delegatedText = (await page.locator('.boot-tooltip.on').textContent()) || '';
            if (!delegatedText.includes('自动分配槽位')) throw new Error('delegated focus tooltip did not appear');
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
                const background = Array.from(document.querySelectorAll('.topbar, .view, .bottom, #log'));
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
                        && rect.width >= innerWidth - 26 && rect.height >= innerHeight - 26,
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
                backgroundClear:Array.from(document.querySelectorAll('.topbar, .view, .bottom, #log'))
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
                window.__bootstrapHarnessAlerts = [];
                window.__bootstrapHarnessPromptDefaults = [];
                window.__bootstrapHarnessPromptValue = null;
                window.alert = message => window.__bootstrapHarnessAlerts.push(String(message));
                window.prompt = (message, defaultValue) => {
                    window.__bootstrapHarnessPromptDefaults.push(String(defaultValue));
                    return window.__bootstrapHarnessPromptValue;
                };
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
            await page.waitForFunction(() => document.querySelectorAll('#cards .btn-rename').length === 5);
            if (await page.locator('#cards .empty-slot .btn-rename').count()) {
                throw new Error('identity-free new-save card exposed rename');
            }
            for (const selector of ['.corrupt', '.tombstoned', '.inconsistent']) {
                if (await page.locator('#cards ' + selector + ' .btn-rename').count() !== 1) {
                    throw new Error(selector + ' card did not expose exactly one rename action');
                }
            }

            const healthyCard = page.locator('#cards .card').filter({ has:page.locator('.btn-start') }).first();
            const healthyNames = await healthyCard.evaluate(card => ({
                title:card.querySelector('.slot').textContent,
                secondary:card.querySelector('.progress').textContent
            }));
            if (healthyNames.title !== '阿一' || !healthyNames.secondary.includes('存档名 · 健康档')) {
                throw new Error('save card did not prioritize characterName over displayName: '
                    + JSON.stringify(healthyNames));
            }

            const renameButton = page.locator('#cards .card').filter({ hasText: '健康档' }).locator('.btn-rename');
            const outboundRenameCount = () => page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'rename_slot').length);
            const beforeInvalid = await outboundRenameCount();
            // 无效名两次点击：各弹一次终端风 alert modal（原生 alert 已迁移到 confirm-dialog 模块），
            // 必须读文本并关闭后才能继续点击 inert 背景里的卡片按钮。
            const expectAlertModal = async (fragment, label) => {
                await page.waitForFunction(() => {
                    const host = document.getElementById('modal-host');
                    return host && host.style.display !== 'none';
                });
                const text = await page.evaluate(() => document.getElementById('modal-content').textContent);
                if (!text.includes(fragment)) {
                    throw new Error(label + ' alert modal missing expected copy: ' + text);
                }
                await page.evaluate(() => window.BootstrapApp.tryCloseModal());
                await page.waitForFunction(() => document.getElementById('modal-host').style.display === 'none');
                return text;
            };
            const invalidAlerts = [];
            await page.evaluate(() => { window.__bootstrapHarnessPromptValue = '坏\u0001名字'; });
            await renameButton.click();
            invalidAlerts.push(await expectAlertModal('显示名无效', 'control-character name'));
            await page.evaluate(() => { window.__bootstrapHarnessPromptValue = '界'.repeat(33); });
            await renameButton.click();
            invalidAlerts.push(await expectAlertModal('显示名无效', '33-grapheme name'));
            if (await outboundRenameCount() !== beforeInvalid) {
                throw new Error('control-character or 33-grapheme name reached Host');
            }

            const emojiName = 'é'.repeat(31) + '👩‍🚀';
            await page.evaluate(value => { window.__bootstrapHarnessPromptValue = value; }, emojiName);
            const promptCountBeforeEmoji = await page.evaluate(() => window.__bootstrapHarnessPromptDefaults.length);
            await renameButton.evaluate(button => { button.click(); button.click(); });
            let renameEvents = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'rename_slot'));
            if (renameEvents.length !== beforeInvalid + 1
                    || renameEvents.at(-1).payload.slotKey !== 'crazyflasher7_saves'
                    || renameEvents.at(-1).payload.displayName !== emojiName) {
                throw new Error('valid 32-grapheme emoji rename was not sent exactly once');
            }
            const promptCountAfterEmoji = await page.evaluate(() => window.__bootstrapHarnessPromptDefaults.length);
            if (promptCountAfterEmoji !== promptCountBeforeEmoji + 1) {
                throw new Error('double activation opened more than one rename prompt');
            }
            const listBeforeFailure = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'list').length);
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'rename_slot_resp', ok:false, slotKey:'crazyflasher7_saves', error:'harness reject'
            }));
            await expectAlertModal('harness reject', 'rename failure');
            const listAfterFailure = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'list').length);
            if (listAfterFailure !== listBeforeFailure) throw new Error('failed rename triggered an optimistic list refresh');

            await page.evaluate(() => { window.__bootstrapHarnessPromptValue = '  重复名  '; });
            await renameButton.click();
            renameEvents = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'rename_slot'));
            if (renameEvents.length !== beforeInvalid + 2 || renameEvents.at(-1).payload.displayName !== '重复名') {
                throw new Error('duplicate display name was rejected or was not trimmed');
            }
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'rename_slot_resp', ok:false, slotKey:'crazyflasher7_saves', error:'harness duplicate probe complete'
            }));
            await expectAlertModal('harness duplicate probe complete', 'duplicate rename failure');

            await page.evaluate(() => { window.__bootstrapHarnessPromptValue = '   '; });
            await renameButton.click();
            renameEvents = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'rename_slot'));
            if (renameEvents.length !== beforeInvalid + 3 || renameEvents.at(-1).payload.displayName !== '') {
                throw new Error('clearing the display name did not request restore-follow semantics');
            }
            const listBeforeSuccess = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'list').length);
            await page.evaluate(() => window.__bootstrapHarnessEmit({
                cmd:'rename_slot_resp', ok:true, slotKey:'crazyflasher7_saves',
                displayName:null, followsCharacterName:true
            }));
            await page.waitForFunction(expected => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'list').length === expected + 1,
                listBeforeSuccess);
            await page.waitForFunction(() => document.querySelectorAll('#cards .card').length === 1
                && document.querySelector('#cards .card').classList.contains('empty-slot'));
            const evidence = await page.evaluate(() => ({
                defaults:window.__bootstrapHarnessPromptDefaults.slice()
            }));
            if (!evidence.defaults.length || evidence.defaults[0] !== '健康档') {
                throw new Error('rename prompt did not default to the current displayName');
            }
            if (invalidAlerts.length !== 2) {
                throw new Error('invalid rename values did not each present a terminal-style alert modal');
            }
            await page.locator('#btn-back-welcome').click();
            return 'rename covers invalid/emoji/duplicate values and empty restore-follow; Host response alone controls refresh';
        });

        await check('native-button-enter', async () => {
            await page.locator('#btn-switch-slot').click();
            const button = page.locator('#cards .btn-newchar').first();
            await button.focus();
            await button.press('Enter');
            await page.waitForFunction(() => !document.getElementById('view-character-create').hidden
                && document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            const focusedCards = await page.locator('#cards .card.kb-focus').count();
            if (focusedCards !== 0) throw new Error('native Enter leaked into card-navigation focus');
            const opens = await page.evaluate(() => window.__bootstrapHarnessEvents
                .filter(event => event.direction === 'out' && event.cmd === 'character_create_open').length);
            if (opens !== 1) throw new Error('expected one character_create_open, got ' + opens);
            // The character-create view is deliberately visibility-hidden and inert
            // until its live snapshot and first paper-doll frame are ready. Escape is
            // the supported cancellation path while that preparation mask owns focus.
            await page.keyboard.press('Escape');
            await page.waitForFunction(() => !document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            return 'focused card button opened exactly once and preparation remained cancellable by Escape';
        });

        await check('container-keyboard-navigation', async () => {
            const cards = page.locator('#cards');
            await cards.focus();
            await cards.press('ArrowRight');
            if (await page.locator('#cards .card.kb-focus').count() !== 1) {
                throw new Error('ArrowRight did not establish one visual card focus');
            }
            await cards.press('Enter');
            await page.waitForFunction(() => !document.getElementById('view-character-create').hidden
                && document.getElementById('view-slots').hidden, null, { timeout: 3000 });
            return 'container ArrowRight + Enter opened the identity-free new-save entry';
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
