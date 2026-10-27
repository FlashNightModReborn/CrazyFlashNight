'use strict';
const fs = require('fs');
const path = require('path');
const { startServer } = require('./lib/stage-select-dev-server');
const root = path.resolve(__dirname, '..');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));

function args(argv) {
    const result = { viewport: '1024x576', only: '', out: '', stage: '' };
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === '--viewport') result.viewport = argv[++i] || result.viewport;
        else if (argv[i] === '--only') result.only = argv[++i] || '';
        else if (argv[i] === '--out') result.out = argv[++i] || '';
        else if (argv[i] === '--stage') result.stage = argv[++i] || '';
        else throw new Error('Unknown argument: ' + argv[i]);
    }
    return result;
}

function safeName(value) {
    return value.replace(/[<>:"/\\|?*\x00-\x1f]/g, '_');
}

async function main() {
    const options = args(process.argv.slice(2));
    const match = options.viewport.match(/^(\d+)x(\d+)$/);
    if (!match) throw new Error('Viewport must use WIDTHxHEIGHT');
    const viewport = { width: Number(match[1]), height: Number(match[2]) };
    const out = options.out ? path.resolve(root, options.out) : path.join(root, 'tmp/stage-select-experience', options.viewport);
    fs.mkdirSync(out, { recursive: true });
    const { server, origin } = await startServer(path.join(root, 'launcher/web'));
    const browser = await chromium.launch({ executablePath: path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless: true });
    const page = await browser.newPage({ viewport });
    const report = { scope: 'Full-screen production DOM and real GLB with mock Host; not game/WebView2 E2E.', viewport: options.viewport, captures: [], errors: [] };
    page.on('pageerror', error => report.errors.push(error.message));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
    const capture = async (frame, kind) => {
        const filename = String(report.captures.filter(item => item.frame === frame).length + 1).padStart(2, '0') + '-' + safeName(frame) + '-' + kind + '.png';
        await page.screenshot({ path: path.join(out, filename) });
        report.captures.push({ frame, kind, file: filename });
    };
    const settle = async label => {
        await page.waitForFunction(wanted => {
            const state = StageSelectPanel._debugGetState();
            return state.frameLabel === wanted && state.runtimeSnapshot
                && (!state.diorama.active || state.diorama.state === 'ready' || state.diorama.state === 'fallback');
        }, label, { timeout: 25000 });
        await page.waitForTimeout(100);
    };
    try {
        const query = new URLSearchParams({ player: '1', viewport: options.viewport, fixture: 'allUnlocked', review: '1' });
        await page.goto(origin + '/modules/stage-select/dev/harness.html?' + query);
        const frames = await page.evaluate(() => StageSelectData.getManifest().frameOrder);
        const wanted = options.only ? frames.filter(label => options.only.split(',').includes(label)) : frames;
        if (!wanted.length) throw new Error('No matching frames');
        await page.evaluate(label => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: label }), wanted[0]);
        await settle(wanted[0]);
        for (const label of wanted) {
            try {
                await page.evaluate(value => StageSelectPanel._debugSetFrame(value, 'experience-capture'), label);
                await settle(label);
                await capture(label, 'overview');
                const hover = await page.evaluate(wantedStage => {
                    const selector = wantedStage ? '.stage-select-card-anchor[data-stage-id="' + wantedStage + '"]' : '.stage-select-card-anchor:not(.is-locked)';
                    const node = document.querySelector(selector);
                    if (!node) return null;
                    const target = document.querySelector('.stage-select-stage-button[data-stage-id="' + node.dataset.stageId + '"] > .stage-select-hit-zone');
                    if (!target) return null;
                    const rect = target.getBoundingClientRect();
                    return { id: node.dataset.stageId, x: rect.left + rect.width / 2, y: rect.top + rect.height / 2 };
                }, options.stage);
                if (hover) {
                    await page.mouse.move(hover.x, hover.y);
                    const card = page.locator('.stage-select-card-anchor[data-stage-id="' + hover.id + '"] > .stage-select-card');
                    await card.waitFor({ state: 'visible', timeout: 4000 });
                    await card.evaluate(el => Promise.all(el.getAnimations().map(animation => animation.finished.catch(() => {}))));
                    await capture(label, 'hover');
                    await page.mouse.move(viewport.width - 8, viewport.height - 8);
                    await page.waitForTimeout(180);
                }
                const selected = await page.evaluate(wantedStage => {
                    const selector = wantedStage ? '.stage-select-stage-button[data-stage-id="' + wantedStage + '"]' : '.stage-select-stage-button:not(.is-direct-entry):not(.is-locked)';
                    const node = document.querySelector(selector);
                    if (!node) return '';
                    node.click();
                    return node.dataset.stageId;
                }, options.stage);
                if (options.stage && !selected) throw new Error('Stage not found or not focusable: ' + options.stage);
                if (selected) {
                    await page.locator('.stage-focus-surface').waitFor({ state: 'visible', timeout: 5000 });
                    await page.waitForFunction(() => !StageSelectDiorama.stats().moving);
                    await capture(label, 'focus');
                    await page.evaluate(() => StageSelectInspector.clearSelection());
                    await page.waitForFunction(() => !StageSelectDiorama.stats().moving);
                }
                const tour = page.locator('.stage-select-header .stage-camera-toggle:visible:not([disabled])').first();
                if (await tour.count()) {
                    await tour.click();
                    await page.locator('.stage-camera-editor').waitFor({ state: 'visible' });
                    const next = page.locator('[data-camera="next-poi"]:visible');
                    if (await next.count()) await next.click();
                    await page.waitForTimeout(450);
                    await capture(label, 'tour');
                    await page.locator('.stage-camera-editor [data-camera="close"]').click();
                }
            } catch (error) {
                report.errors.push(label + ': ' + error.message);
                await page.screenshot({ path: path.join(out, safeName(label) + '-failure.png') });
            }
        }
    } finally {
        await browser.close();
        server.close();
    }
    const cards = report.captures.map(item => '<figure><figcaption>' + item.frame + ' · ' + item.kind + '</figcaption><img src="' + item.file + '"></figure>').join('\n');
    const html = '<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
        + '<title>选关全量体验审阅 ' + options.viewport + '</title><style>'
        + 'body{margin:0;background:#111713;color:#dde5d8;font:14px/1.5 "Microsoft YaHei",sans-serif}header{position:sticky;top:0;z-index:2;padding:14px 20px;background:#111713ee;border-bottom:1px solid #42513f}main{padding:16px;display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:16px}figure{margin:0;background:#192019;border:1px solid #354031}figcaption{padding:8px 10px;color:#cbd8c2}img{display:block;width:100%;height:auto}.errors{padding:0 20px;color:#f0b0a0}</style>'
        + '<header><strong>选关全量体验审阅 · ' + options.viewport + '</strong><div>Edge + 生产 DOM / GLB + mock Host；用于逐页人眼审阅，不代表标准游戏入口验收。</div></header>'
        + (report.errors.length ? '<pre class="errors">' + report.errors.join('\n').replace(/&/g, '&amp;').replace(/</g, '&lt;') + '</pre>' : '')
        + '<main>' + cards + '</main></html>';
    fs.writeFileSync(path.join(out, 'index.html'), html);
    report.pass = report.errors.length === 0;
    fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify({ pass: report.pass, out, captures: report.captures.length, errors: report.errors }, null, 2));
    if (report.errors.length) process.exitCode = 1;
}

main().catch(error => { console.error(error); process.exitCode = 1; });
