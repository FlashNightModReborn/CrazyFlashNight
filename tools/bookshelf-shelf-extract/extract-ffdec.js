#!/usr/bin/env node
'use strict';
// FFDec channel for the bookshelf shelf art: exports the original vector
// sprites from flashswf/UI/书架界面.swf (read-only) and rasterizes them at
// high resolution through the Playwright/canvas pipeline already used by the
// graybox generator. The .exe launcher needs registry entries, so the jar is
// invoked directly with the Animate-bundled JRE; ffdec-cli drops into an
// interactive console without explicit command args and hangs on stdin, so
// stdin is always closed (ignore).
// Output: tools/bookshelf-shelf-extract/out-ffdec/ (pinned via the shelf
// manifest artSources chain by tools/import-bookshelf-shelf.py).
const fs = require('fs');
const os = require('os');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { execFileSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(__dirname, 'out-ffdec');
const SHELF_SWF = path.join(ROOT, 'flashswf/UI/书架界面.swf');
const FFDEC = path.join(ROOT, 'tools/ffdec/ffdec-cli.jar');
// Sprite identities verified by reading the spine text on the rasterized
// exports (2026-10-08): 59 尘都诡谈, 61 末日异闻录, 63 无名丝带,
// 65 光明巴比伦, 67 金属有血, 69 守护之力.
const SPRITES = { '57': 'shelf-body', '59': 'spine-dust', '61': 'spine-apocalypse',
    '63': 'spine-ribbon', '65': 'spine-babylon', '67': 'spine-metal', '69': 'spine-guardian' };
const RASTER_HEIGHT = { 'shelf-body': 2256, 'spine': 848 }; // 16x native vector units

const sha = data => crypto.createHash('sha256').update(data).digest('hex');

function findJava() {
    const candidates = [];
    if (process.env.CF7_JAVA_HOME) candidates.push(path.join(process.env.CF7_JAVA_HOME, 'bin/java.exe'), process.env.CF7_JAVA_HOME);
    for (const root of [process.env.ProgramFiles, process.env['ProgramFiles(x86)']].filter(Boolean)) {
        candidates.push(path.join(root, 'Adobe/Adobe Animate 2024/jre/bin/java.exe'));
        candidates.push(path.join(root, 'Adobe/Adobe Animate 2023/jre/bin/java.exe'));
    }
    candidates.push('java');
    const found = candidates.find(candidate => {
        try { execFileSync(candidate, ['-version'], { stdio: ['ignore', 'pipe', 'pipe'] }); return true; }
        catch { return false; }
    });
    if (!found) throw new Error('Java runtime not found (set CF7_JAVA_HOME; Animate jre expected)');
    return found;
}

function main() {
    const java = findJava();
    if (!fs.existsSync(FFDEC)) throw new Error('ffdec-cli.jar missing: ' + FFDEC);
    const source = fs.readFileSync(SHELF_SWF);
    const work = fs.mkdtempSync(path.join(os.tmpdir(), 'cf7-ffdec-'));
    try {
        execFileSync(java, ['-jar', FFDEC, '-onerror', 'ignore', '-format', 'sprite:svg',
            '-selectid', Object.keys(SPRITES).join(','), '-export', 'sprite', work, SHELF_SWF],
            { stdio: ['ignore', 'pipe', 'pipe'], cwd: path.dirname(FFDEC) });
        const svgs = fs.readdirSync(work, { recursive: true }).filter(name => String(name).endsWith('.svg'));
        const byId = {};
        for (const name of svgs) {
            const match = String(name).match(/DefineSprite_(\d+)/);
            if (match && SPRITES[match[1]]) byId[match[1]] = path.join(work, name);
        }
        const missing = Object.keys(SPRITES).filter(id => !byId[id]);
        if (missing.length) throw new Error('ffdec export incomplete, missing sprite ids: ' + missing);
        fs.rmSync(OUT, { recursive: true, force: true });
        fs.mkdirSync(OUT, { recursive: true });
        return { java, byId, source };
    } finally { /* keep svg dir until rasterized below */ }
}

async function rasterize(svgs, source) {
    // ffdec sprite SVGs carry their own viewBox; rasterize through a page canvas.
    const server = http.createServer((req, res) => { res.writeHead(404); res.end(); });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const edge = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles].filter(Boolean)
        .map(p => path.join(p, 'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const { chromium } = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
    const browser = await chromium.launch({ executablePath: edge, headless: true });
    const files = {}, averages = {};
    try {
        const page = await browser.newPage();
        for (const [id, svgPath] of Object.entries(svgs)) {
            const name = SPRITES[id];
            const svg = fs.readFileSync(svgPath, 'utf8');
            const height = name === 'shelf-body' ? RASTER_HEIGHT['shelf-body'] : RASTER_HEIGHT['spine'];
            const rendered = await page.evaluate(async ({ svg, height }) => {
                const img = new Image();
                const url = 'data:image/svg+xml;base64,' + btoa(unescape(encodeURIComponent(svg)));
                await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; img.src = url; });
                const aspect = img.naturalWidth / img.naturalHeight;
                const canvas = document.createElement('canvas');
                canvas.height = height; canvas.width = Math.round(height * aspect);
                const g = canvas.getContext('2d');
                g.drawImage(img, 0, 0, canvas.width, canvas.height);
                const px = g.getImageData(0, 0, canvas.width, canvas.height).data;
                let r = 0, gg = 0, b = 0, n = 0;
                for (let i = 0; i < px.length; i += 4) {
                    if (px[i + 3] < 128) continue;
                    r += px[i]; gg += px[i + 1]; b += px[i + 2]; n++;
                }
                return { png: canvas.toDataURL('image/png').split(',')[1],
                    average: n ? '#' + [r, gg, b].map(v => Math.round(v / n).toString(16).padStart(2, '0')).join('') : null };
            }, { svg, height });
            const png = Buffer.from(rendered.png, 'base64');
            fs.writeFileSync(path.join(OUT, name + '.png'), png);
            fs.writeFileSync(path.join(OUT, name + '.svg'), svg);
            files[name + '.png'] = { bytes: png.length, sha256: sha(png) };
            files[name + '.svg'] = { bytes: Buffer.byteLength(svg), sha256: sha(Buffer.from(svg)) };
            averages[name] = rendered.average;
            console.log('ffdec sprite', id, '->', name + '.png', png.length, 'bytes, avg', rendered.average);
        }
    } finally { await browser.close(); server.close(); }
    return { files, averages };
}

(async () => {
    const { java, byId, source } = main();
    const { files, averages } = await rasterize(byId, source);
    const report = {
        schema: 'bookshelf-shelf-ffdec-report/1',
        generatedAt: new Date().toISOString(),
        source: { file: 'flashswf/UI/书架界面.swf', sha256: sha(source), bytes: source.length },
        tool: { ffdec: 'tools/ffdec/ffdec-cli.jar', java, sprites: SPRITES },
        averages,
        files: Object.fromEntries(Object.entries(files).sort(([a], [b]) => a.localeCompare(b)))
    };
    fs.writeFileSync(path.join(OUT, 'ffdec-report.json'), JSON.stringify(report, null, 2) + '\n');
    // Clean the temp svg dir only after everything succeeded.
    const tempRoot = path.dirname(byId[Object.keys(byId)[0]]);
    if (tempRoot.includes('cf7-ffdec-')) fs.rmSync(tempRoot, { recursive: true, force: true });
    console.log('ffdec channel:', Object.keys(SPRITES).length, 'sprites,', Object.keys(files).length, 'files');
})().catch(error => { console.error(error); process.exitCode = 1; });
