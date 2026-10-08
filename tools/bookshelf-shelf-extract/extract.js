#!/usr/bin/env node
'use strict';
// Offline art extraction for the bookshelf shelf scene: renders frames of the
// original bookshelf UI SWF and the CF1 movie with the vendored Ruffle build
// (wmode transparent), captures them in headless Edge, and cuts configured
// crops. The repo SWFs are never modified; patched copies live in memory.
// Output: tools/bookshelf-shelf-extract/out/ (consumed by the graybox
// generator; pinned by tools/import-bookshelf-shelf.py).
const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { patchGotoFrame, frameLabels } = require('./patch-swf.js');

const ROOT = path.resolve(__dirname, '..', '..');
const OUT = path.join(__dirname, 'out');
const SHELF_SWF = path.join(ROOT, 'flashswf/UI/书架界面.swf');
const CF1_SWF = path.join(ROOT, 'flashswf/originals/crazy-flasher-1.swf');
const CROPS = path.join(__dirname, 'crops.json');
const SCALE = 4;

const sha = data => crypto.createHash('sha256').update(data).digest('hex');

const PAGE = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;background:transparent}ruffle-player{display:block}</style>
<script>window.RufflePlayer={config:{autoplay:'on',wmode:'transparent',scale:'showAll',forceScale:true,letterbox:'off',logLevel:'error',splashScreen:false,unmuteOverlay:'hidden',contextMenu:'off',backgroundExecutionMode:'none',publicPath:'/flashswf/_ruffle/'}};</script>
<script src="/flashswf/_ruffle/ruffle.js"></script>`;

async function main() {
    const crops = fs.existsSync(CROPS) ? JSON.parse(fs.readFileSync(CROPS, 'utf8')) : { shelf: {}, notes: '' };
    const shelfSource = fs.readFileSync(SHELF_SWF);
    const cf1Source = fs.readFileSync(CF1_SWF);
    const shelfLabels = frameLabels(shelfSource);
    console.log('shelf labels:', JSON.stringify(shelfLabels));

    const server = http.createServer((req, res) => {
        const url = new URL(req.url, 'http://localhost');
        if (url.pathname === '/extract.html') {
            res.setHeader('Content-Type', 'text/html; charset=utf-8'); res.end(PAGE); return;
        }
        const file = path.resolve(ROOT, '.' + decodeURIComponent(url.pathname));
        if (path.relative(ROOT, file).startsWith('..')) { res.writeHead(403); res.end(); return; }
        fs.readFile(file, (err, data) => {
            if (err) { res.writeHead(404); res.end(); return; }
            const types = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.swf': 'application/x-shockwave-flash' };
            res.setHeader('Content-Type', types[path.extname(file)] || 'application/octet-stream'); res.end(data);
        });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const edge = [process.env['ProgramFiles(x86)'], process.env.ProgramFiles].filter(Boolean)
        .map(p => path.join(p, 'Microsoft/Edge/Application/msedge.exe')).find(fs.existsSync);
    const { chromium } = require(path.join(ROOT, 'launcher/perf/node_modules/playwright'));
    const browser = await chromium.launch({ executablePath: edge, headless: true });
    fs.rmSync(OUT, { recursive: true, force: true });
    fs.mkdirSync(OUT, { recursive: true });

    async function capture(name, swfBytes, stageW, stageH, settleMs) {
        const page = await browser.newPage({ viewport: { width: stageW * SCALE + 40, height: stageH * SCALE + 40 } });
        try {
            await page.goto('http://127.0.0.1:' + server.address().port + '/extract.html');
            await page.waitForFunction(() => window.RufflePlayer && window.RufflePlayer.newest);
            await page.evaluate(async ({ data, w, h }) => {
                const player = window.RufflePlayer.newest().createPlayer();
                player.style.width = w + 'px'; player.style.height = h + 'px';
                document.body.appendChild(player);
                window.__ready = false;
                await player.ruffle().load({ data: Uint8Array.from(atob(data), c => c.charCodeAt(0)), swfFileName: 'extract.swf' });
                window.__ready = true;
            }, { data: swfBytes.toString('base64'), w: stageW * SCALE, h: stageH * SCALE });
            await page.waitForFunction(() => window.__ready);
            await page.waitForTimeout(settleMs || 700);
            const png = await page.locator('ruffle-player').screenshot({ omitBackground: true });
            fs.writeFileSync(path.join(OUT, name), png);
            console.log('captured', name, png.length, 'bytes');
            return png;
        } finally { await page.close(); }
    }

    // Bookshelf UI: frame 1 (default stop) plus every labeled frame via patched copies.
    await capture('shelf-frame-1.png', shelfSource, 500, 460);
    const wanted = ['空', '光明巴比伦', '无名丝带', '尘都诡谈', '末日异闻录'];
    for (const { frame, label } of shelfLabels) {
        if (!wanted.includes(label)) continue;
        const patched = patchGotoFrame(shelfSource, frame - 1);
        await capture('shelf-label-' + label + '.png', patched, 500, 460);
    }
    // CF1 title: unpatched movie halts on its scripted stop frames.
    await capture('cf1-title-a.png', cf1Source, 400, 300, 900);
    await capture('cf1-title-b.png', cf1Source, 400, 300, 2500);

    // Configured crops + average colors, derived from the captured frames in-page.
    const sets = (crops.sets || []).filter(set => set.rects && Object.keys(set.rects).length);
    if (sets.length) {
        const page = await browser.newPage();
        try {
            for (const set of sets) {
                const full = fs.readFileSync(path.join(OUT, set.source));
                const result = await page.evaluate(async ({ data, rects, scale }) => {
                    const img = new Image();
                    await new Promise((resolve, reject) => { img.onload = resolve; img.onerror = reject; img.src = 'data:image/png;base64,' + data; });
                    const out = {};
                    for (const [name, rect] of Object.entries(rects)) {
                        const c = document.createElement('canvas');
                        c.width = Math.round(rect.w * scale); c.height = Math.round(rect.h * scale);
                        const g = c.getContext('2d');
                        g.drawImage(img, rect.x * scale, rect.y * scale, rect.w * scale, rect.h * scale, 0, 0, c.width, c.height);
                        const px = g.getImageData(0, 0, c.width, c.height).data;
                        let r = 0, gg = 0, b = 0, n = 0;
                        for (let i = 0; i < px.length; i += 4) {
                            if (px[i + 3] < 128) continue;
                            r += px[i]; gg += px[i + 1]; b += px[i + 2]; n++;
                        }
                        out[name] = { png: c.toDataURL('image/png').split(',')[1],
                            average: n ? '#' + [r, gg, b].map(v => Math.round(v / n).toString(16).padStart(2, '0')).join('') : null };
                    }
                    return out;
                }, { data: full.toString('base64'), rects: set.rects, scale: SCALE });
                for (const [name, crop] of Object.entries(result)) {
                    fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(crop.png, 'base64'));
                    console.log('crop', name, crop.average);
                }
                crops.averages = Object.assign(crops.averages || {},
                    Object.fromEntries(Object.entries(result).map(([k, v]) => [k, v.average])));
            }
        } finally { await page.close(); }
    }

    const report = {
        schema: 'bookshelf-shelf-extract-report/1',
        generatedAt: new Date().toISOString(),
        sources: [
            { file: 'flashswf/UI/书架界面.swf', sha256: sha(shelfSource), bytes: shelfSource.length,
                frameLabels: shelfLabels, note: 'labeled frames rendered from in-memory gotoAndStop-patched copies; repo SWF unchanged' },
            { file: 'flashswf/originals/crazy-flasher-1.swf', sha256: sha(cf1Source), bytes: cf1Source.length,
                note: 'unpatched; title captured at its scripted stop frame' }
        ],
        renderer: 'vendored Ruffle 0.3.0 (flashswf/_ruffle), wmode transparent, headless Edge',
        cropsConfig: crops,
        files: Object.fromEntries(fs.readdirSync(OUT).filter(f => f.endsWith('.png')).sort()
            .map(f => { const d = fs.readFileSync(path.join(OUT, f)); return [f, { bytes: d.length, sha256: sha(d) }]; }))
    };
    fs.writeFileSync(path.join(OUT, 'extract-report.json'), JSON.stringify(report, null, 2) + '\n');
    console.log('extract report written;', Object.keys(report.files).length, 'png files');
    await browser.close(); server.close();
}
main().catch(error => { console.error(error); process.exitCode = 1; });
