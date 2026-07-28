#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB = path.join(ROOT, 'launcher', 'web');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
let checks = 0;

function check(condition, message) {
    checks++;
    if (!condition) throw new Error(message);
    process.stdout.write('ok ' + checks + ' - ' + message + '\n');
}

function edgeExecutable() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)',
            'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files',
            'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(WEB, pathname));
            const relative = path.relative(WEB, file);
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
                const extension = path.extname(file);
                const contentType = extension === '.html' ? 'text/html; charset=utf-8'
                    : extension === '.css' ? 'text/css; charset=utf-8'
                        : extension === '.js' ? 'text/javascript; charset=utf-8'
                            : 'application/octet-stream';
                response.writeHead(200, {'Content-Type':contentType});
                response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function safeExitUi(page) {
    return page.evaluate(() => {
        const panel = document.getElementById('safe-exit-panel');
        const status = document.getElementById('safe-exit-status');
        const buttons = document.getElementById('safe-exit-buttons');
        const confirm = document.querySelector(
            '#safe-exit-buttons [data-key="EXIT_CONFIRM"]');
        const retry = document.getElementById('safe-exit-retry');
        return {
            panel:getComputedStyle(panel).display,
            status:status.textContent,
            statusClass:status.className,
            buttons:getComputedStyle(buttons).display,
            confirm:getComputedStyle(confirm).display,
            confirmDisabled:confirm.disabled,
            retry:getComputedStyle(retry).display,
            retryDisabled:retry.disabled
        };
    });
}

(async function main() {
    if (!fs.existsSync(PLAYWRIGHT)) {
        throw new Error('Missing Playwright; run npm --prefix launcher/perf ci --ignore-scripts');
    }
    const executablePath = edgeExecutable();
    if (!executablePath) throw new Error('Microsoft Edge not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    const page = await browser.newPage({viewport:{width:1024, height:576}});
    try {
        await page.addInitScript(() => {
            const listeners = [];
            window.__hostMessages = listeners;
            window.__postedMessages = [];
            window.chrome = window.chrome || {};
            window.chrome.webview = {
                addEventListener(type, listener) {
                    if (type === 'message') listeners.push(listener);
                },
                postMessage(message) {
                    window.__postedMessages.push(message);
                }
            };
            window.__postHostMessage = data => {
                listeners.slice().forEach(listener => listener({data}));
            };
        });
        await page.goto('http://127.0.0.1:' + server.address().port + '/overlay.html',
            {waitUntil:'load'});
        await page.waitForFunction(() =>
            document.querySelector('[data-key="SAFEEXIT"]').onclick !== null
            || typeof Notch !== 'undefined');

        await page.evaluate(() => {
            window.__postedMessages.length = 0;
            document.querySelector('[data-key="SAFEEXIT"]').click();
        });
        check(await page.evaluate(() => window.__postedMessages.filter(
            message => message.type === 'click' && message.key === 'SAFEEXIT').length) === 1,
        'opening the panel requests exactly one save');

        await page.evaluate(() => UiData.dispatch('sv:1|sv:3'));
        let ui = await safeExitUi(page);
        check(ui.panel !== 'none' && ui.status === '存盘失败'
            && ui.statusClass === 'failed',
        'same-frame sv:1 to sv:3 settles in Failed');
        check(ui.buttons !== 'none' && ui.confirm === 'none' && ui.confirmDisabled
            && ui.retry !== 'none' && !ui.retryDisabled,
        'Failed hides and disables exit while exposing Retry');

        await page.evaluate(() => {
            window.__postedMessages.length = 0;
            document.querySelector(
                '#safe-exit-buttons [data-key="EXIT_CONFIRM"]').click();
            document.getElementById('safe-exit-retry').click();
            document.getElementById('safe-exit-retry').click();
        });
        const retryMessages = await page.evaluate(() => window.__postedMessages.filter(
            message => message.type === 'click'));
        check(retryMessages.length === 1 && retryMessages[0].type === 'click'
            && retryMessages[0].key === 'SAFEEXIT',
        'Retry emits one SAFEEXIT and never EXIT_CONFIRM');
        ui = await safeExitUi(page);
        check(ui.status === '存盘中…' && ui.statusClass === 'saving'
            && ui.buttons === 'none',
        'Retry transitions to Saving before awaiting Host state');

        await page.evaluate(() => {
            UiData.dispatch('sv:1');
            UiData.dispatch('sv:3');
        });
        ui = await safeExitUi(page);
        check(ui.statusClass === 'failed' && ui.confirmDisabled && !ui.retryDisabled,
        'consecutive sv:1 then sv:3 also settles in Failed');

        await page.evaluate(() => {
            UiData.dispatch('sv:1');
            window.__postHostMessage({type:'safe_exit_failed'});
        });
        ui = await safeExitUi(page);
        check(ui.panel !== 'none' && ui.statusClass === 'failed'
            && ui.confirmDisabled && !ui.retryDisabled,
        'safe_exit_failed Bridge message immediately restores Failed');
        console.log('Safe exit Web fallback: ' + checks + '/' + checks + ' passed');
    } finally {
        await page.close();
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => {
    console.error(error.stack || error);
    process.exit(1);
});
