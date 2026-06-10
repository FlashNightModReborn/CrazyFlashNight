'use strict';

const fs = require('fs');
const http = require('http');
const path = require('path');
const url = require('url');

const ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(ROOT, 'launcher', 'web');
const { chromium } = require(path.join(ROOT, 'launcher', 'perf', 'node_modules', 'playwright'));

function edgePath() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    return candidates.find(fs.existsSync);
}

function server() {
    return new Promise(resolve => {
        const s = http.createServer((req, res) => {
            const pathname = decodeURIComponent(url.parse(req.url).pathname);
            const file = path.normalize(path.join(WEB_ROOT, pathname));
            const rel = path.relative(WEB_ROOT, file);
            if (rel.startsWith('..') || path.isAbsolute(rel)) { res.writeHead(403); res.end(); return; }
            fs.readFile(file, (err, data) => {
                if (err) { res.writeHead(404); res.end(); return; }
                const ext = path.extname(file);
                const mime = ext === '.html' ? 'text/html; charset=utf-8' : ext === '.css' ? 'text/css; charset=utf-8' : ext === '.js' ? 'text/javascript; charset=utf-8' : 'application/octet-stream';
                res.writeHead(200, {'Content-Type': mime}); res.end(data);
            });
        });
        s.listen(0, '127.0.0.1', () => resolve(s));
    });
}

(async function() {
    const s = await server();
    const browser = await chromium.launch({ executablePath: edgePath(), headless: true });
    const viewports = [{width:1024,height:576},{width:1366,height:768},{width:1920,height:1080}];
    let failed = 0;
    for (const viewport of viewports) {
        const page = await browser.newPage({ viewport });
        page.on('pageerror', e => console.error('[page-error]', e.message));
        await page.route('https://cfn-assets.local/**', r => r.fulfill({status:204, body:''}));
        await page.goto('http://127.0.0.1:' + s.address().port + '/modules/team/dev/harness.html', {waitUntil:'load'});
        const handle = await page.waitForFunction(() => window.__qaResult && window.__qaResult.qa, {timeout:30000});
        const qa = await handle.jsonValue();
        console.log('[team-harness ' + viewport.width + 'x' + viewport.height + '] ' + qa.passed + '/' + qa.total + ' passed');
        qa.results.forEach(x => console.log('  ' + (x.pass ? 'PASS' : 'FAIL') + ' ' + x.id + ' ' + x.title + (x.detail ? ' :: ' + x.detail : '')));
        failed += qa.failed;
        await page.close();
    }
    await browser.close();
    s.close();
    process.exit(failed ? 1 : 0);
})().catch(err => { console.error('[team-harness] fatal', err); process.exit(2); });
