#!/usr/bin/env node
'use strict';

/**
 * tooltip-parity Web 端采集器。
 * 真实 Edge headless 渲染冻结的 baseline 生产 tooltip 链路，逐 case 输出
 * web.png（viewport 截图）+ web.json（几何/文本/滚动数据）。
 *
 * 用法：
 *   node web-shoot.js --baseline <dir> --samples <f> --scenarios <f>
 *                     --out <dir> [--mode legacy|doc] [--cases a,b,c]
 *
 * baseline 目录约定（见 parity-compare notes.md）：
 *   manifest.json {schema:'cf7.tooltip-parity-baseline.v1', sourceSha, files:{<repoRel>:{sha256}}}
 *   文件按仓库相对路径存放。manifest 列出的 URL 路径一律由 baseline 服务，
 *   缺失即失败；未列出的路径回退工作树（数据资产），命中内容 sha256 全部记录。
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const {chromium} = require('playwright');
const {startServer} = require('../lib/server.js');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const FIXTURE_URL = 'launcher/perf/tooltip-parity/fixture.html';
const BASELINE_SCHEMA = 'cf7.tooltip-parity-baseline.v1';
const SAMPLES_SCHEMA = 'cf7.tooltip-parity-samples.v1';
const SCENARIOS_SCHEMA = 'cf7.tooltip-parity-scenarios.v1';

const MIME = {
    '.html': 'text/html; charset=utf-8', '.css': 'text/css; charset=utf-8',
    '.js': 'application/javascript; charset=utf-8', '.json': 'application/json; charset=utf-8',
    '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
    '.webp': 'image/webp', '.woff2': 'font/woff2', '.woff': 'font/woff', '.ttf': 'font/ttf'
};

function fail(msg, evidence) { const e = new Error(msg); e.evidence = evidence; throw e; }
function assert(c, msg, ev) { if (!c) fail(msg, ev); }

function sha256(buf) { return crypto.createHash('sha256').update(buf).digest('hex'); }

function parseArgs(argv) {
    const out = { mode: 'legacy', cases: null };
    for (let i = 2; i < argv.length; i++) {
        const a = argv[i];
        const next = () => argv[++i];
        if (a === '--baseline') (out.baselines || (out.baselines = [])).push(next());
        else if (a === '--samples') out.samples = next();
        else if (a === '--scenarios') out.scenarios = next();
        else if (a === '--out') out.out = next();
        else if (a === '--mode') out.mode = next();
        else if (a === '--cases') out.cases = next().split(',').filter(Boolean);
        else if (a === '--no-png') out.noPng = true;
        else fail('unknown arg: ' + a);
    }
    assert(out.baselines && out.baselines.length && out.samples && out.scenarios && out.out,
        'required: --baseline <dir> [--baseline <dir>...] --samples --scenarios --out', out);
    return out;
}

function edgePath() {
    const candidates = [
        process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].filter(Boolean);
    return candidates.find(c => fs.existsSync(c)) || '';
}

// 支持两种 baseline manifest：
//  A) 本 harness schema：files = { <repoRel>: {sha256} }，文件按 repoRel 存放；
//  B) parity-web 官方冻结格式：files = [{path, file, gitBlob, sha256}]，
//     文件按扁平名 <file> 存放，pin 到 <path>。
// 多个 --baseline 目录可叠加（官方冻结 + 本岗位补充），同路径重复 pin 即失败。
function loadOneBaseline(dir, into) {
    const manifestPath = path.join(dir, 'manifest.json');
    assert(fs.existsSync(manifestPath), 'baseline manifest.json missing', manifestPath);
    const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
    const entries = [];
    if (manifest.schema === BASELINE_SCHEMA) {
        for (const rel of Object.keys(manifest.files || {}))
            entries.push({ rel, abs: path.join(dir, rel), sha256: manifest.files[rel].sha256 });
    } else if (Array.isArray(manifest.files)) {
        for (const f of manifest.files)
            entries.push({ rel: f.path, abs: path.join(dir, f.file || f.path), sha256: String(f.sha256 || '').toLowerCase() });
    } else {
        fail('unrecognized baseline manifest schema', manifestPath);
    }
    for (const e of entries) {
        assert(fs.existsSync(e.abs), 'manifest lists missing baseline file', e.rel);
        const body = fs.readFileSync(e.abs);
        const actual = sha256(body);
        assert(actual === e.sha256, 'baseline file sha256 mismatch (freeze violated)', e.rel);
        const urlPath = '/' + e.rel.replace(/\\/g, '/');
        assert(!into.pinned[urlPath], 'duplicate baseline pin', urlPath);
        into.pinned[urlPath] = { abs: e.abs, sha256: actual, body, baselineDir: dir };
    }
    into.manifests.push({ dir, manifest });
}

function loadBaselines(dirs) {
    const acc = { manifests: [], pinned: {} };
    for (const d of dirs) loadOneBaseline(path.resolve(d), acc);
    return acc;
}

function loadJson(file, schema, key) {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    assert(data.schema === schema, file + ' schema mismatch', data.schema);
    assert(Array.isArray(data[key]) && data[key].length > 0, file + ' empty ' + key);
    return data;
}

function caseId(sample, scenario) {
    const raw = String(sample.id) + '__' + String(scenario.id);
    return raw.replace(/[^\w\-\.一-鿿]+/g, '_');
}

async function main() {
    const args = parseArgs(process.argv);
    const baseline = loadBaselines(args.baselines);
    const samplesDoc = loadJson(path.resolve(args.samples), SAMPLES_SCHEMA, 'samples');
    const scenariosDoc = loadJson(path.resolve(args.scenarios), SCENARIOS_SCHEMA, 'scenarios');
    const outRoot = path.resolve(args.out);
    fs.mkdirSync(outRoot, { recursive: true });

    const executablePath = edgePath();
    assert(executablePath, 'Microsoft Edge executable not found');
    const server = await startServer(ROOT);
    const served = {};   // urlPath → {origin:'baseline'|'repo', sha256}
    const browser = await chromium.launch({ executablePath, headless: true });
    const pageErrors = [];
    const results = [];
    try {
        const contexts = new Map();
        async function contextFor(dpi) {
            if (contexts.has(dpi)) return contexts.get(dpi);
            const context = await browser.newContext({ deviceScaleFactor: dpi });
            await context.route('**/*', route => {
                try {
                    const u = new URL(route.request().url());
                    const p = decodeURIComponent(u.pathname);
                    const pin = baseline.pinned[p];
                    if (pin) {
                        served[p] = { origin: 'baseline', sha256: pin.sha256 };
                        route.fulfill({ body: pin.body, contentType: MIME[path.extname(p).toLowerCase()] || 'application/octet-stream' });
                        return;
                    }
                    // 未冻结路径：记录 sha（数据资产身份可审计），放行到静态服务器。
                    const repoFile = path.join(ROOT, p.replace(/^\//, ''));
                    if (fs.existsSync(repoFile) && fs.statSync(repoFile).isFile()) {
                        served[p] = { origin: 'repo', sha256: sha256(fs.readFileSync(repoFile)) };
                    }
                    route.continue();
                } catch (e) {
                    route.continue();
                }
            });

            contexts.set(dpi, context);
            return context;
        }

        for (const sample of samplesDoc.samples) {
            for (const scenario of scenariosDoc.scenarios) {
                if (args.cases && !args.cases.includes(caseId(sample, scenario))) continue;
                const cid = caseId(sample, scenario);
                const vp = scenario.viewport || { w: 1024, h: 576 };
                const caseDir = path.join(outRoot, 'cases', cid);
                fs.mkdirSync(caseDir, { recursive: true });

                const dpi = Number(vp.dpi || 1);
                assert(Number.isFinite(dpi) && dpi >= 1 && dpi <= 3, 'invalid DPI', vp);
                // viewport 输入为物理像素；vh/media query 必须在 CSS 像素域运行。
                const cssWidth = vp.w / dpi, cssHeight = vp.h / dpi;
                assert(Number.isInteger(cssWidth) && Number.isInteger(cssHeight),
                    'physical viewport must divide exactly by DPI; choose an integral CSS viewport', vp);
                const context = await contextFor(dpi);
                const page = await context.newPage();
                page.on('pageerror', e => pageErrors.push(cid + ': ' + String(e && e.stack || e)));
                try {
                    await page.setViewportSize({ width: cssWidth, height: cssHeight });
                    await page.goto(server.url + FIXTURE_URL, { waitUntil: 'load' });
                    await page.waitForFunction(() => window.__parity && window.__parity.version);
                    await page.evaluate(() => window.__parity.iconsReady());
                    const geo = await page.evaluate(
                        ({ s, sc, m }) => window.__parity.show(s, sc, m),
                        { s: sample, sc: scenario, m: args.mode });
                    assert(geo && geo.shown, 'web tooltip show rejected', { cid, geo });
                    const viewportProbe = await page.evaluate(() => ({
                        cssWidth: innerWidth, cssHeight: innerHeight, devicePixelRatio,
                        descFontWeight: getComputedStyle(document.querySelector('.flash-tt-desc') || document.body).fontWeight
                    }));
                    assert(viewportProbe.devicePixelRatio === dpi, 'browser DPI mismatch', viewportProbe);
                    // DOM 几何转物理像素再与 Native 比较，原 CSS 数值仍单独保存。
                    const cssGeometry = JSON.parse(JSON.stringify(geo));
                    for (const key of ['tooltipRect','introPanelRect','descPanelRect','iconRect','iconImgRect','scrollViewportRect']) {
                        if (geo[key]) for (const coord of ['left','top','right','bottom','width','height'])
                            if (typeof geo[key][coord] === 'number') geo[key][coord] *= dpi;
                    }
                    geo.effectivePhysicalScale = geo.overlayScale * dpi;

                    // --no-png：几何/DOM 不变时只重采 web.json（视觉行等元数据），
                    // 复用既有 web.png——不重截 851 张图。
                    if (!args.noPng) {
                        const png = await page.screenshot({ type: 'png' });
                        assert(png.readUInt32BE(16) === vp.w && png.readUInt32BE(20) === vp.h,
                            'screenshot physical dimensions mismatch', {cid, vp});
                        fs.writeFileSync(path.join(caseDir, 'web.png'), png);
                    } else {
                        assert(fs.existsSync(path.join(caseDir, 'web.png')),
                            '--no-png but web.png missing', cid);
                    }
                    const record = {
                        caseId: cid, mode: args.mode,
                        sampleId: sample.id, scenarioId: scenario.id,
                        viewport: vp, anchor: scenario.anchor || null,
                        viewportProbe, cssGeometry, geometry: geo
                    };
                    fs.writeFileSync(path.join(caseDir, 'web.json'), JSON.stringify(record, null, 1));
                    results.push({ caseId: cid, ok: true });
                    process.stdout.write('[web] ' + cid + ' placement=' + geo.placement
                        + ' tip=' + (geo.tooltipRect ? Math.round(geo.tooltipRect.width) + 'x' + Math.round(geo.tooltipRect.height) : '-') + '\n');
                } finally {
                    await page.close();
                }
            }
        }
    } finally {
        await browser.close();
        await server.server.close();
    }

    fs.writeFileSync(path.join(outRoot, 'web-meta.json'), JSON.stringify({
        schema: 'cf7.tooltip-parity-web-meta.v1',
        mode: args.mode,
        baselines: baseline.manifests.map(m => ({ dir: m.dir, sourceSha: m.manifest.sourceSha || (m.manifest.source && m.manifest.source.commit) || null, fileCount: Object.keys(m.manifest.files || {}).length || (m.manifest.files || []).length })),
        served,
        pageErrors,
        results
    }, null, 1));
    if (pageErrors.length) process.stderr.write('pageerrors=' + pageErrors.length + '\n');
    process.stdout.write('web shoot done: ' + results.length + ' cases → ' + outRoot + '\n');
}

main().catch(e => {
    console.error('FAIL:', e.message);
    if (e.evidence) console.error(JSON.stringify(e.evidence).slice(0, 2000));
    process.exit(1);
});
