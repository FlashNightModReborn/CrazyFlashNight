#!/usr/bin/env node
'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const PLAYWRIGHT = path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright');
const shotArg = process.argv.find(arg => arg.startsWith('--shot='));

function edgePath() {
    return [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ].filter(Boolean).find(fs.existsSync);
}

function createServer() {
    return new Promise(resolve => {
        const server = http.createServer((request, response) => {
            const pathname = decodeURIComponent(url.parse(request.url).pathname);
            const file = path.normalize(path.join(ROOT, pathname));
            const relative = path.relative(ROOT, file);
            if (relative.startsWith('..') || path.isAbsolute(relative)) { response.writeHead(403); response.end(); return; }
            fs.readFile(file, (error, data) => {
                if (error) { response.writeHead(404); response.end(); return; }
                const ext = path.extname(file);
                const type = ext === '.html' ? 'text/html; charset=utf-8' : ext === '.css' ? 'text/css; charset=utf-8' : ext === '.js' ? 'text/javascript; charset=utf-8' : 'application/octet-stream';
                response.writeHead(200, {'Content-Type':type}); response.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

(async function() {
    if (!fs.existsSync(PLAYWRIGHT)) throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    const executablePath = edgePath();
    if (!executablePath) throw new Error('Microsoft Edge executable not found');
    const {chromium} = require(PLAYWRIGHT);
    const server = await createServer();
    const browser = await chromium.launch({executablePath, headless:true});
    try {
        const page = await browser.newPage({viewport:{width:1440,height:900}, deviceScaleFactor:1});
        const pageErrors = [], failedRequests = [];
        page.on('pageerror', error => pageErrors.push(error.message || String(error)));
        page.on('requestfailed', request => failedRequests.push(request.url()));
        await page.goto('http://127.0.0.1:' + server.address().port + '/tools/visual/item-grid-matrix.html', {waitUntil:'load'});
        await page.waitForFunction(() => window.__qaDone === true, null, {timeout:20000});
        const qa = await page.evaluate(() => window.__qaResult);
        if (shotArg) {
            const shotPath = path.resolve(ROOT, shotArg.slice('--shot='.length));
            fs.mkdirSync(path.dirname(shotPath), {recursive:true});
            await page.screenshot({path:shotPath, fullPage:true});
        }
        const output = {browser:'edge', executablePath, qa, pageErrors, failedRequests};
        process.stdout.write(JSON.stringify(output, null, 2) + '\n');
        if (!qa || qa.failed || pageErrors.length || failedRequests.length) process.exitCode = 1;
    } finally {
        await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
})().catch(error => { console.error(error && error.stack ? error.stack : String(error)); process.exit(2); });
