'use strict';

const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const { chromium } = require('playwright');
const { ROOT, DEFAULT_OUT, buildFullCatalogSamples, buildShowcaseSamples } = require('./samples');

const PRESETS = ['legacy339', 'tier12', 'tier13', 'tier14'];
const DEFAULT_VIEWPORTS = '1024x576@1,1067x600@1.5,1280x720@1.25,1366x768@1,1920x1080@1';
const FIXTURE = '/launcher/perf/tooltip-efficiency/fixture.html';
const MIME = {
    html: 'text/html; charset=utf-8', css: 'text/css; charset=utf-8',
    js: 'application/javascript; charset=utf-8', json: 'application/json; charset=utf-8',
    svg: 'image/svg+xml', webp: 'image/webp', png: 'image/png', gif: 'image/gif',
    woff2: 'font/woff2', woff: 'font/woff', ttf: 'font/ttf', otf: 'font/otf'
};

function parseArgs(argv, defaults) {
    const parsed = { ...defaults };
    for (let i = 0; i < argv.length; i++) {
        const key = argv[i].slice(2);
        if (!argv[i].startsWith('--') || !Object.hasOwn(defaults, key)) throw new Error('未知参数 ' + argv[i]);
        if (typeof defaults[key] === 'boolean') {
            parsed[key] = true;
        } else {
            const value = argv[++i];
            if (!value || value.startsWith('--')) throw new Error('缺少 --' + key + ' 的值');
            parsed[key] = value;
        }
    }
    return parsed;
}

function parseViewports(value) {
    const viewports = value.split(',').map(input => {
        const match = /^([1-9]\d*)x([1-9]\d*)@(\d+(?:\.\d+)?)$/.exec(input);
        if (!match) throw new Error('视口格式须为 W×H@DPR，例如 1067x600@1.5');
        const [width, height, dpr] = match.slice(1).map(Number);
        if (width <= 16 || height <= 16 || !Number.isFinite(dpr) || dpr <= 0) throw new Error('无效视口 ' + input);
        return { label: `${width}x${height}@${dpr}`, width, height, dpr };
    });
    if (new Set(viewports.map(v => v.label)).size !== viewports.length) throw new Error('重复视口');
    return viewports;
}

function serve(request, response) {
    const url = new URL(request.url, 'http://localhost');
    let pathname;
    try {
        pathname = decodeURIComponent(url.pathname);
    } catch {
        response.writeHead(400).end();
        return;
    }
    const file = path.resolve(ROOT, '.' + pathname);
    const relative = path.relative(ROOT, file).split(path.sep).join('/');
    if (pathname !== FIXTURE && !relative.startsWith('launcher/web/')) {
        response.writeHead(404).end();
        return;
    }
    const stream = fs.createReadStream(file);
    stream.on('open', () => {
        response.writeHead(200, { 'Content-Type': MIME[path.extname(file).slice(1)] || 'application/octet-stream' });
        stream.pipe(response);
    });
    stream.on('error', () => {
        if (!response.headersSent) response.writeHead(404);
        response.end();
    });
}

async function withFixture(viewport, work) {
    const server = http.createServer(serve);
    await new Promise((resolve, reject) => {
        server.once('error', reject);
        server.listen(0, '127.0.0.1', resolve);
    });
    let browser;
    try {
        browser = await chromium.launch({ channel: 'msedge', ignoreDefaultArgs: ['--hide-scrollbars'] });
        const context = await browser.newContext({
            viewport: { width: viewport.width, height: viewport.height },
            deviceScaleFactor: viewport.dpr,
            locale: 'zh-CN'
        });
        // Match the Host virtual mapping for acquisition portraits.
        await context.route('https://cfn-assets.local/portraits/icons/*', async route => {
            const filename = decodeURIComponent(new URL(route.request().url()).pathname.split('/').at(-1));
            if (!/^[^/\\:]+\.webp$/i.test(filename)) return route.fulfill({ status: 404 });
            const portrait = path.join(ROOT, 'flashswf/portraits/icons', filename);
            if (!fs.existsSync(portrait)) return route.fulfill({ status: 404 });
            await route.fulfill({ path: portrait, contentType: 'image/webp' });
        });
        const page = await context.newPage();
        const pageErrors = [];
        page.on('pageerror', error => pageErrors.push(error.message));
        await page.goto(`http://127.0.0.1:${server.address().port}${FIXTURE}`);
        const cdp = await context.newCDPSession(page);
        const result = await work({ browser, page, cdp });
        if (pageErrors.length) throw new Error('夹具页面错误\n' + [...new Set(pageErrors)].join('\n'));
        return result;
    } finally {
        try {
            if (browser) await browser.close();
        } finally {
            server.close();
        }
    }
}

async function prepareViewport({ page, cdp }, viewport, probe) {
    const { width, height, dpr } = viewport;
    const current = page.viewportSize();
    if (current.width !== width || current.height !== height) await page.setViewportSize({ width, height });
    await cdp.send('Emulation.setDeviceMetricsOverride', { width, height, deviceScaleFactor: dpr, mobile: false });
    const actual = await page.evaluate(sample => window.efficiency.prepare(sample), probe);
    if (actual.width !== width || actual.height !== height || actual.dpr !== dpr) {
        throw new Error('浏览器实际视口不符 ' + JSON.stringify({ viewport, actual }));
    }
    return actual;
}

async function usePreset(page, preset) {
    return page.evaluate(name => window.efficiency.setPreset(name), preset);
}

function writeJson(file, value) {
    fs.writeFileSync(file, JSON.stringify(value, null, 2) + '\n');
}

function summarize(rows, viewport) {
    const heights = rows.map(row => row.tipH).sort((a, b) => a - b);
    const quantile = p => heights[Math.ceil(heights.length * p) - 1] ?? null;
    const overflowCount = rows.filter(row => row.overflowPx > 0).length;
    const idealCount = rows.filter(row => row.whPenalty === 0).length;
    const maxH = quantile(1);
    return {
        ...viewport, count: rows.length, overflowCount, overflowRate: rows.length ? overflowCount / rows.length : null,
        scrollableCount: rows.filter(row => row.scrollable).length,
        outsideCount: rows.filter(row => !row.insideViewport).length,
        p50H: quantile(0.5), p95H: quantile(0.95), maxH, idealCount,
        idealRate: rows.length ? idealCount / rows.length : null,
        meanPenalty: rows.length ? rows.reduce((sum, row) => sum + row.whPenalty, 0) / rows.length : null,
        top15: [...rows].sort((a, b) => b.overflowPx - a.overflowPx || b.tipH - a.tipH || b.whPenalty - a.whPenalty).slice(0, 15)
    };
}

const fixed = (n, digits = 2) => n == null ? '—' : n.toFixed(digits);
const percent = n => n == null ? '—' : fixed(n * 100) + '%';
const cell = name => String(name).replace(/\|/g, '\\|').replace(/[\r\n]+/g, ' ');

function report(summary) {
    const lines = [
        '# Tooltip 排版效率', '',
        `范围 **${summary.scope}** · 预设 **${summary.preset}** · Edge ${summary.edgeVersion}`,
        '', `提交 \`${summary.provenance.repoBaseline}\`，目录 \`${summary.provenance.catalogContentVersion}\`。`,
        '', '外框与栏位尺寸用 CSS px。溢出用活跃阅读视口的 scrollHeight 减 clientHeight，差值大于 0 即计入溢出率。理想宽高比为 [0.8, 1.5)。',
        '', '| 视口 | 成功 | 溢出数 / 率 | 可滚 | 越界 | P50 高 | P95 高 | maxH | 理想占比 | meanPenalty | 测量秒数 |',
        '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|'
    ];
    for (const v of summary.viewports) {
        lines.push(`| ${v.label} | ${v.count} | ${v.overflowCount} / ${percent(v.overflowRate)} | ${v.scrollableCount} | ${v.outsideCount} | ${fixed(v.p50H)} | ${fixed(v.p95H)} | ${fixed(v.maxH)} | ${percent(v.idealRate)} | ${fixed(v.meanPenalty, 3)} | ${fixed(v.measureMs / 1000)} |`);
    }
    for (const v of summary.viewports) {
        lines.push('', `## ${v.label} 最重 Top 15`, '',
            '| 物品 | W×H | 列数 | 阅读目标 | 内容高 / 视口高 | 溢出 | W/H | 惩罚 |',
            '|---|---:|---:|---|---:|---:|---:|---:|');
        for (const r of v.top15) {
            lines.push(`| ${cell(r.name)} | ${fixed(r.tipW)}×${fixed(r.tipH)} | ${r.sideColumns} | ${r.readingTarget || '—'} | ${r.contentH} / ${r.viewH} | ${r.overflowPx} | ${fixed(r.whRatio)} | ${r.whPenalty} |`);
        }
    }
    lines.push('', `构建失败 ${summary.buildErrors.length} 项，渲染失败 ${summary.renderErrors.length} 项。`);
    for (const e of [...summary.buildErrors, ...summary.renderErrors]) {
        lines.push(`- ${e.viewport ? e.viewport + ' ' : ''}${e.name} · ${e.message}`);
    }
    return lines.join('\n') + '\n';
}

async function main() {
    const started = performance.now();
    const args = parseArgs(process.argv.slice(2), { scope: 'showcase', preset: 'legacy339', viewports: DEFAULT_VIEWPORTS, out: '', limit: '' });
    if (!['showcase', 'full'].includes(args.scope)) throw new Error('未知范围 ' + args.scope);
    if (!PRESETS.includes(args.preset)) throw new Error('未知预设 ' + args.preset);
    if (args.limit && (!/^[1-9]\d*$/.test(args.limit) || !Number.isSafeInteger(Number(args.limit)))) throw new Error('--limit 须为正整数');
    const viewports = parseViewports(args.viewports);
    const outDir = path.resolve(args.out || path.join(DEFAULT_OUT, args.preset === 'legacy339' ? args.scope : args.scope + '-' + args.preset));
    const build = args.scope === 'full' ? buildFullCatalogSamples : buildShowcaseSamples;
    const { samples, errors: buildErrors, counts, provenance } = build();
    const selected = samples.slice(0, args.limit ? Number(args.limit) : samples.length);
    if (!selected.length) throw new Error('无可渲染样本');
    const brief = selected.map(({ id, document }) => ({ id, document }));
    const byId = new Map(selected.map(sample => [sample.id, sample]));
    const probe = brief.find(sample => sample.document.icon?.name);
    const summary = {
        schema: 'cf7.tooltip-efficiency-summary.v1', scope: args.scope, preset: args.preset,
        provenance, ...counts, selected: brief.length, built: samples.length, buildErrors,
        renderErrors: [], viewports: []
    };
    for (const error of buildErrors) console.error('文档构建失败', error.name, error.message);
    const raw = [];
    await withFixture(viewports[0], async fixture => {
        const { browser, page } = fixture;
        summary.edgeVersion = browser.version();
        if (!await usePreset(page, args.preset)) throw new Error('当前生产代码不支持预设 ' + args.preset);
        for (const viewport of viewports) {
            const actual = await prepareViewport(fixture, viewport, probe);
            const measuredAt = performance.now();
            const rows = [];
            for (let i = 0; i < brief.length; i += 64) {
                const batch = await page.evaluate(samples => window.efficiency.batch(samples), brief.slice(i, i + 64));
                for (const { id, error, ...metrics } of batch) {
                    const { name, displayName } = byId.get(id);
                    if (error) {
                        console.error(viewport.label, name, error);
                        summary.renderErrors.push({ viewport: viewport.label, id, name, message: error });
                    } else {
                        rows.push({ id, name, displayName, ...metrics });
                    }
                }
            }
            const measureMs = Math.round(performance.now() - measuredAt);
            const stats = summarize(rows, { ...viewport, overlayScale: actual.scale, measureMs });
            summary.viewports.push(stats);
            raw.push({ viewport, rows });
            console.log(`${viewport.label} · ${stats.count} 项 · 溢出 ${percent(stats.overflowRate)} · maxH ${fixed(stats.maxH)} · ${fixed(measureMs / 1000)}s`);
        }
    });
    summary.elapsedMs = Math.round(performance.now() - started);
    fs.mkdirSync(outDir, { recursive: true });
    writeJson(path.join(outDir, 'summary.json'), summary);
    writeJson(path.join(outDir, 'raw.json'), {
        schema: 'cf7.tooltip-efficiency-raw.v1', scope: args.scope, preset: args.preset, provenance, viewports: raw,
        buildErrors, renderErrors: summary.renderErrors
    });
    fs.writeFileSync(path.join(outDir, 'report.md'), report(summary));
    console.log(`已写入 ${outDir}（总计 ${fixed(summary.elapsedMs / 1000)}s）`);
    if (summary.renderErrors.length) process.exitCode = 1;
}

if (require.main === module) main().catch(error => { console.error(error); process.exitCode = 1; });

module.exports = { PRESETS, parseArgs, parseViewports, withFixture, prepareViewport, usePreset, writeJson };
