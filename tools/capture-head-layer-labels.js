#!/usr/bin/env node
'use strict';

// 头部层级打标截图器：对全部不遮发头部装备，按「游戏内现状 / 调整后」两种
// 层级顺序各抓一张紧贴头部的 PNG，供人工或视觉模型逐件打标。
//
// 用法：
//   node tools/capture-head-layer-labels.js [--hair 发型-男式-黑韩式头]
//       [--gender 男|女] [--out tmp/head-layer-labels] [--pixel-ratio 3]
//       [--only 名称1,名称2] [--headed]
//   node tools/capture-head-layer-labels.js --all-hair [--out tmp/head-layer-labels]
//
// 单发型输出：<out>/<order>/<装备名>.png 与 <out>/index.json。
// --all-hair 输出：<out>/<性别>/<发型>/<order>/<装备名>.png（跳过光头与遮发头盔）。

const fs = require('fs');
const http = require('http');
const path = require('path');

const projectRoot = path.resolve(__dirname, '..');
const webRoot = path.join(projectRoot, 'launcher', 'web');
const playwrightModule = path.join(projectRoot, 'launcher', 'perf', 'node_modules', 'playwright');
const PAGE_PATH = '/modules/dressup/dev/head-layer-review-harness.html';

function parseArgs(argv) {
    const args = {
        hair: '发型-男式-黑韩式头',
        gender: '男',
        out: path.join('tmp', 'head-layer-labels'),
        pixelRatio: 3,
        only: null,
        allHair: false,
        headed: false
    };
    for (let i = 0; i < argv.length; i += 1) {
        const arg = argv[i];
        const next = argv[i + 1] || '';
        if (arg === '--hair') { args.hair = next; i += 1; }
        else if (arg === '--gender') { args.gender = next; i += 1; }
        else if (arg === '--out') { args.out = next; i += 1; }
        else if (arg === '--pixel-ratio') { args.pixelRatio = Number(next) || 3; i += 1; }
        else if (arg === '--only') { args.only = new Set(next.split(',').filter(Boolean)); i += 1; }
        else if (arg === '--all-hair') { args.allHair = true; }
        else if (arg === '--headed') { args.headed = true; }
        else if (arg === '--help' || arg === '-h') {
            console.log('usage: node tools/capture-head-layer-labels.js [--hair <skinKey>] [--gender 男|女] [--out <dir>] [--pixel-ratio 3] [--only a,b] [--all-hair] [--headed]');
            process.exit(0);
        } else {
            console.error('unknown arg: ' + arg);
            process.exit(1);
        }
    }
    return args;
}

function findBrowser() {
    const candidates = [
        path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env.LOCALAPPDATA ? path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Edge', 'Application', 'msedge.exe') : null
    ].filter(Boolean);
    for (const candidate of candidates) {
        if (fs.existsSync(candidate)) return candidate;
    }
    throw new Error('Cannot find Edge executable.');
}

function mimeType(filePath) {
    const ext = path.extname(filePath).toLowerCase();
    if (ext === '.html') return 'text/html; charset=utf-8';
    if (ext === '.js') return 'application/javascript; charset=utf-8';
    if (ext === '.css') return 'text/css; charset=utf-8';
    if (ext === '.json') return 'application/json; charset=utf-8';
    if (ext === '.png') return 'image/png';
    if (ext === '.jpg' || ext === '.jpeg') return 'image/jpeg';
    if (ext === '.svg') return 'image/svg+xml';
    if (ext === '.woff2') return 'font/woff2';
    return 'application/octet-stream';
}

function createStaticServer(rootDir) {
    const server = http.createServer((req, res) => {
        const rawPath = (req.url || '/').split('?')[0] || '/';
        let decoded;
        try {
            decoded = decodeURIComponent(rawPath);
        } catch (error) {
            res.writeHead(400);
            res.end('bad request');
            return;
        }
        const safeRel = decoded.replace(/^\/+/, '').replace(/\//g, path.sep);
        const filePath = path.resolve(rootDir, safeRel || 'index.html');
        if (!filePath.startsWith(rootDir)) {
            res.writeHead(403);
            res.end('forbidden');
            return;
        }
        fs.stat(filePath, (statErr, stat) => {
            if (statErr || !stat.isFile()) {
                res.writeHead(404);
                res.end('not found');
                return;
            }
            res.writeHead(200, { 'content-type': mimeType(filePath) });
            fs.createReadStream(filePath).pipe(res);
        });
    });
    return new Promise((resolve, reject) => {
        server.on('error', reject);
        server.listen(0, '127.0.0.1', () => resolve(server));
    });
}

async function main() {
    const args = parseArgs(process.argv.slice(2));
    if (!fs.existsSync(playwrightModule)) {
        throw new Error('Missing Playwright dependency. Run: npm --prefix launcher/perf ci --ignore-scripts');
    }
    const { chromium } = require(playwrightModule);

    // --all-hair：从 manifest 读发型目录，按 性别×发型 展开任务列表；
    // 男式发型只跑男性 rig，女式同理，光头跳过。
    let tasks = [{ gender: args.gender, hair: args.hair, outDir: args.out }];
    if (args.allHair) {
        const manifest = JSON.parse(fs.readFileSync(
            path.join(webRoot, 'assets', 'dressup', 'manifest.json'), 'utf8'));
        const hairById = manifest.appearance && manifest.appearance.hairById || {};
        tasks = [];
        Object.keys(hairById).forEach(id => {
            const hair = String(hairById[id]);
            let gender = null;
            if (hair.indexOf('发型-男式-') === 0) gender = '男';
            else if (hair.indexOf('发型-女式-') === 0) gender = '女';
            if (!gender) return;
            tasks.push({
                gender: gender,
                hair: hair,
                outDir: path.join(args.out, gender, hair)
            });
        });
    }

    const server = await createStaticServer(webRoot);
    const port = server.address().port;
    const url = 'http://127.0.0.1:' + port + PAGE_PATH;
    let browser = null;
    let totalCaptured = 0;
    try {
        browser = await chromium.launch({
            executablePath: findBrowser(),
            headless: !args.headed
        });
        const page = await browser.newPage({ viewport: { width: 900, height: 900 } });
        await page.goto(url, { waitUntil: 'load' });
        await page.waitForFunction(
            () => window.headLayerReview && window.headLayerReview.ready === true,
            { timeout: 30000 }
        );
        let allItems = await page.evaluate(() => window.headLayerReview.list());
        if (args.only) allItems = allItems.filter(item => args.only.has(item.name));
        const items = args.allHair
            ? allItems.filter(item => !item.helmet)
            : allItems;

        for (const task of tasks) {
            const outDir = path.resolve(projectRoot, task.outDir);
            const index = {
                hair: task.hair,
                gender: task.gender,
                pixelRatio: args.pixelRatio,
                generatedAt: new Date().toISOString(),
                items: []
            };
            for (const item of items) {
                const entry = { name: item.name, helmet: item.helmet, files: {} };
                for (const order of ['flash', 'doll']) {
                    const dataUrl = await page.evaluate(
                        ({ name, order, hair, gender, pixelRatio }) =>
                            window.headLayerReview.capture(name, order, hair, gender, pixelRatio),
                        { name: item.name, order, hair: task.hair, gender: task.gender, pixelRatio: args.pixelRatio }
                    );
                    if (!dataUrl || !dataUrl.startsWith('data:image/png;base64,')) {
                        entry.files[order] = null;
                        continue;
                    }
                    const dir = path.join(outDir, order);
                    fs.mkdirSync(dir, { recursive: true });
                    const file = path.join(dir, item.name + '.png');
                    fs.writeFileSync(file, Buffer.from(dataUrl.slice('data:image/png;base64,'.length), 'base64'));
                    entry.files[order] = path.relative(projectRoot, file);
                }
                index.items.push(entry);
                totalCaptured++;
                process.stdout.write((entry.files.flash && entry.files.doll ? 'OK  ' : 'ERR ')
                    + task.gender + '/' + task.hair + '/' + item.name + '\n');
            }
            fs.mkdirSync(outDir, { recursive: true });
            fs.writeFileSync(path.join(outDir, 'index.json'), JSON.stringify(index, null, 2));
            console.log('captured ' + index.items.length + ' items [' + task.gender + ' '
                + task.hair + '] -> ' + path.relative(projectRoot, outDir));
        }
        console.log('total: ' + tasks.length + ' task(s), ' + totalCaptured + ' item(s)');
    } finally {
        if (browser) await browser.close();
        await new Promise(resolve => server.close(resolve));
    }
}

main().catch(error => {
    console.error(error && error.stack || error);
    process.exit(1);
});
