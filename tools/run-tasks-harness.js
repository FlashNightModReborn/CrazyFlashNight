'use strict';

// 任务面板 harness 无头跑测 / 截图工具（用 launcher/perf 自带 playwright + Edge）。
//
// 用法：
//   node tools/run-tasks-harness.js --qa
//       跑 ?qa=1 自断言套件（task-ui1~task-ui12），打印结果，failed>0 时退出码 1。
//   node tools/run-tasks-harness.js --shot=tmp/task.png [--query="view=list&filter=副本&detail=6"] [--viewport=1280x720]
//       打开面板、应用 query 状态、对 #shell 截图到指定文件。
//
// 站点根 = launcher/web（不是 repo root）：task-panel.js / css 用绝对路径 /modules/tasks/assets/...，
// 必须以 launcher/web 为站点根才解析得到。

const path = require('path');
const fs = require('fs');
const http = require('http');
const url = require('url');

const REPO_ROOT = path.resolve(__dirname, '..');
const WEB_ROOT = path.join(REPO_ROOT, 'launcher', 'web');
const { chromium } = require(path.join(REPO_ROOT, 'launcher', 'perf', 'node_modules', 'playwright'));

const MIME = {
    '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
    '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
    '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.gif': 'image/gif',
    '.svg': 'image/svg+xml', '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf'
};

function parseArgs() {
    const args = process.argv.slice(2);
    const out = { qa: false, shot: '', query: '', viewport: '1280x720', timeout: 60000, keepOpen: false };
    for (let i = 0; i < args.length; i++) {
        const a = args[i];
        if (a === '--qa') out.qa = true;
        else if (a.startsWith('--shot=')) out.shot = a.slice(7);
        else if (a.startsWith('--sel=')) out.sel = a.slice(6);
        else if (a.startsWith('--query=')) out.query = a.slice(8);
        else if (a.startsWith('--viewport=')) out.viewport = a.slice(11);
        else if (a.startsWith('--timeout=')) out.timeout = Number(a.slice(10));
        else if (a === '--keep-open') out.keepOpen = true;
    }
    return out;
}

function findEdge() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.LOCALAPPDATA || '', 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ];
    for (const c of candidates) if (c && fs.existsSync(c)) return c;
    throw new Error('找不到 msedge.exe');
}

function startServer(root) {
    return new Promise((resolve) => {
        const server = http.createServer((req, res) => {
            let pathname = decodeURIComponent(url.parse(req.url).pathname);
            if (pathname === '/') pathname = '/index.html';
            const filePath = path.join(root, pathname);
            if (!filePath.startsWith(root)) { res.writeHead(403); res.end(); return; }
            fs.readFile(filePath, (err, data) => {
                if (err) { res.writeHead(404); res.end('404 ' + pathname); return; }
                res.writeHead(200, { 'Content-Type': MIME[path.extname(filePath).toLowerCase()] || 'application/octet-stream' });
                res.end(data);
            });
        });
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

function parseViewport(v) {
    const m = String(v || '').match(/^(\d+)x(\d+)$/);
    return { width: m ? Number(m[1]) : 1280, height: m ? Number(m[2]) : 720 };
}

async function main() {
    const opts = parseArgs();
    const server = await startServer(WEB_ROOT);
    const port = server.address().port;
    const base = 'http://127.0.0.1:' + port + '/modules/tasks/dev/harness.html';
    const viewport = parseViewport(opts.viewport);
    const executablePath = findEdge();

    let qs = [];
    if (opts.qa) qs.push('qa=1');
    if (opts.query) qs.push(opts.query);
    qs.push('vp=' + viewport.width + 'x' + viewport.height);
    const harnessUrl = base + '?' + qs.join('&');

    console.log('[tasks-harness] url', harnessUrl);
    const browser = await chromium.launch({ executablePath, headless: !opts.keepOpen });
    const context = await browser.newContext({ viewport });
    const page = await context.newPage();
    page.on('pageerror', err => console.error('[page-error]', err.message));
    page.on('console', msg => {
        if (msg.type() === 'error') console.log('[console-error]', msg.text());
    });
    // 头像虚拟主机 + 字体在 harness 不可达，静默 204 避免噪声
    await page.route('https://cfn-assets.local/**', r => r.fulfill({ status: 204, body: '' }));
    await page.route('https://cfn-fonts.local/**', r => r.fulfill({ status: 204, body: '' }));

    let exitCode = 0;
    try {
        await page.goto(harnessUrl, { waitUntil: 'load', timeout: 30000 });

        if (opts.qa) {
            const handle = await page.waitForFunction(
                () => (window.__qaResult && window.__qaResult.qa) ? window.__qaResult.qa : null,
                { timeout: opts.timeout, polling: 200 }
            );
            const bundle = await handle.jsonValue();
            console.log('\n[tasks-harness] ' + bundle.passed + '/' + bundle.total + ' passed (failed=' + bundle.failed + ')');
            for (const item of bundle.results) {
                console.log('  ' + (item.pass ? 'PASS' : 'FAIL') + ' ' + item.id + ' ' + item.title + (item.detail ? ' :: ' + item.detail : ''));
            }
            exitCode = bundle.failed > 0 ? 1 : 0;
        }

        if (opts.shot) {
            // 等面板渲染稳定 + 入场动画播完
            await page.waitForSelector('#panel-container', { state: 'attached', timeout: 10000 });
            await page.waitForTimeout(1400);
            const shotPath = path.isAbsolute(opts.shot) ? opts.shot : path.join(REPO_ROOT, opts.shot);
            fs.mkdirSync(path.dirname(shotPath), { recursive: true });
            const target = opts.sel ? await page.$(opts.sel) : await page.$('#shell');
            if (target) await target.screenshot({ path: shotPath });
            else await page.screenshot({ path: shotPath });
            console.log('[tasks-harness] screenshot →', shotPath);
        }

        if (opts.keepOpen) { console.log('[tasks-harness] keep-open, Ctrl+C 退出'); await new Promise(() => {}); }
    } catch (err) {
        console.error('[tasks-harness] error:', err.message);
        exitCode = 2;
    } finally {
        await browser.close();
        server.close();
    }
    process.exit(exitCode);
}

main().catch(err => { console.error('[tasks-harness] fatal', err); process.exit(3); });
