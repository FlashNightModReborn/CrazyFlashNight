'use strict';
// Real production panel and exported GLB, with the existing mock Host transport.
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { startServer } = require('./lib/stage-select-dev-server');
const root = path.resolve(__dirname, '..');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const out = path.join(root, 'tmp/stage-select-desert');

async function main() {
    fs.mkdirSync(out, { recursive: true });
    const { server, origin } = await startServer(path.join(root, 'launcher/web'));
    const browser = await chromium.launch({ executablePath: path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless: true });
    const page = await browser.newPage({ viewport: { width: 1024, height: 576 } });
    page.setDefaultTimeout(60000);
    const errors = [], report = { scope: 'Real exported GLB in production Web panel; mock Host only. Not WebView2/Flash E2E.', checks: [] };
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
    const ready = () => page.waitForFunction(() => StageSelectDiorama.stats().state === 'ready' && !StageSelectDiorama.stats().pending && !StageSelectDiorama.stats().moving);
    const open = async () => { await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地房顶' })); await ready(); };
    const canvasFits = async (id) => {
        const size = await page.locator('.stage-select-diorama-canvas').evaluate(canvas => {
            const rect = node => { const r = node.getBoundingClientRect(); return { x: r.x, y: r.y, width: r.width, height: r.height }; };
            return { canvas: rect(canvas), viewport: rect(canvas.parentElement) };
        });
        for (const field of ['x', 'y', 'width', 'height']) {
            assert.ok(Math.abs(size.canvas[field] - size.viewport[field]) <= 1, id + ': canvas ' + field + ' must match its viewport: ' + JSON.stringify(size));
        }
        (report.canvasBounds ||= []).push({ id, ...size });
    };
    const boundaryCovered = async (id) => {
        const evidence = await page.evaluate(() => StageSelectDiorama.stats().surround);
        assert.equal(evidence?.state, 'ready', id + ': missing terrain surround');
        assert.equal(evidence.groundPlaneViewportCovered, true, id + ': a viewport corner reaches outside the presentation terrain');
        assert.equal(evidence.sourceAttributesChanged, false);
        assert.equal(evidence.hiddenCutWalls.length, 1, 'Only the confirmed regional cut-earth wall batch is replaced');
        assert.equal(evidence.hiddenCutWalls[0].triangles, 1124);
        (report.boundaryViews ||= []).push({ id, groundPlaneViewportCorners: evidence.groundPlaneViewportCorners });
    };
    try {
        await page.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576&frame=' + encodeURIComponent('基地房顶') + '&fixture=allUnlocked&player=1&review=desert-candidate');
        await ready();
        report.initial = await page.evaluate(() => StageSelectDiorama.stats());
        assert.equal(Object.keys(report.initial.focusFraming).length, 9);
        for (const [id, frame] of Object.entries(report.initial.focusFraming)) {
            assert.equal(frame.source, 'owner-vertices', id + ': current GLB must provide a real geometry owner');
            assert.ok(frame.vertices > 0);
            assert.ok(frame.projectedWidth <= frame.span / 1.15 + 0.0001);
            assert.ok(frame.projectedHeight <= frame.span / frame.viewportAspect / 1.15 + 0.0001);
        }
        report.browserRenderer = await page.evaluate(() => {
            const gl = document.querySelector('.stage-select-diorama-canvas').getContext('webgl2');
            const debug = gl.getExtension('WEBGL_debug_renderer_info');
            return { userAgent: navigator.userAgent, renderer: debug ? gl.getParameter(debug.UNMASKED_RENDERER_WEBGL) : gl.getParameter(gl.RENDERER) };
        });
        assert.equal(await page.locator('.stage-select-stage-button').count(), 11);
        assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 1);
        await canvasFits('overview');
        await boundaryCovered('overview');
        await page.screenshot({ path: path.join(out, 'overview.png') });
        report.layout = await page.locator('.stage-select-stage-button').evaluateAll(nodes => nodes.map(n => {
            const r = n.getBoundingClientRect(), label = n.querySelector('.stage-select-stage-name').getBoundingClientRect();
            return { id: n.dataset.stageId, marker: [r.x, r.y, r.width, r.height], label: [label.x, label.y, label.width, label.height] };
        }));
        const initialFrames = report.initial.frames;
        await page.waitForTimeout(250);
        assert.equal((await page.evaluate(() => StageSelectDiorama.stats())).frames, initialFrames, 'Idle scene must not continuously render');
        report.checks.push('11 gameplay entries retained; one canvas; idle scene has no continuous render loop');
        for (const [width, height] of [[1024, 576], [1366, 768], [1920, 1080]]) {
            await page.setViewportSize({ width, height });
            await page.evaluate(size => StageSelectHarnessHost.setViewport(size), width + 'x' + height);
            await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
            await canvasFits('overview-' + width); await boundaryCovered('overview-' + width);
            await page.screenshot({ path: path.join(out, 'overview-' + width + 'x' + height + '.png') });
        }
        await page.setViewportSize({ width: 1024, height: 576 });
        await page.evaluate(() => StageSelectHarnessHost.setViewport('1024x576'));
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        report.checks.push('Presentation surround covers all overview corners at 1024x576, 1366x768 and 1920x1080 without changing the camera or geographic anchors');
        for (const index of [0, 1, 2, 3, 4, 5, 6, 7]) {
            const id = 'stage_34_' + index;
            await page.locator('[data-stage-id="' + id + '"].stage-select-stage-button > .stage-select-stage-name').click();
            await ready();
            const state = await page.evaluate(() => StageSelectDiorama.stats());
            assert.equal(state.focusId, id);
            assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 1);
            await canvasFits(id);
            await boundaryCovered(id);
            if (index === 0) {
                const pose = await page.evaluate(() => StageSelectDiorama.snapshotCamera());
                assert.ok(pose.span >= 1.5 && pose.span < 5, 'Small desert landmarks must use the closer focus range: ' + JSON.stringify(pose));
                (report.smallLandmarkFocus ||= []).push({ id, ...pose });
            }
            if ([0, 1, 3, 4, 5, 7].includes(index)) await page.screenshot({ path: path.join(out, id + '-focus.png') });
            if (index === 0) {
                await page.getByRole('button', { name: '游览地点', exact: true }).click();
                await page.waitForFunction(() => StageSelectDiorama.stats().editing);
                await page.mouse.move(300, 300); await page.mouse.wheel(0, -10000);
                await page.waitForFunction(() => Math.abs(StageSelectDiorama.snapshotCamera().span - 1.5) < 0.001);
                await page.getByRole('button', { name: '结束游览', exact: true }).first().click();
                await ready();
                report.checks.push('Small-landmark tour zoom reaches the configured minimum span of 1.5');
            }
            if (index === 7) {
                const beforePreview = await page.evaluate(() => StageSelectHarnessHost.enterMessages.length);
                // Diplomacy keeps its direct map-entry business behavior. Only the
                // existing camera is temporarily previewed in this isolated fixture.
                await page.evaluate(() => StageSelectDiorama.focus('stage_34_10', document.querySelector('.stage-focus-viewport')));
                await ready(); await canvasFits('diplomacy-internal-preview'); await boundaryCovered('diplomacy-internal-preview');
                await page.locator('.stage-focus-viewport').screenshot({ path: path.join(out, 'stage_34_10-internal-preview.png') });
                assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.length), beforePreview);
                await page.evaluate(() => StageSelectDiorama.focus('stage_34_7', document.querySelector('.stage-focus-viewport')));
                await ready();
                report.checks.push('Diplomacy visual bounds checked through a reversible internal preview without sending an entry request');
            }
            await page.getByRole('button', { name: '返回总览', exact: true }).click();
            await ready();
            assert.equal((await page.evaluate(() => StageSelectDiorama.stats())).focusId, '');
        }
        report.checks.push('All eight 3D combat entries focus and return using the same canvas, whose visible bounds match each viewport');
        await page.locator('[data-stage-id="stage_34_3"].stage-select-stage-button > .stage-select-stage-name').click();
        await ready();
        const beforeDifficulty = await page.evaluate(() => StageSelectHarnessHost.enterMessages.length);
        await page.locator('#stage-select-inspector-difficulties [data-difficulty="冒险"]').click();
        assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.length), beforeDifficulty);
        await page.getByRole('button', { name: '返回总览', exact: true }).click();
        await ready();
        report.checks.push('Changing difficulty in a 3D focus view sends no entry request');
        for (const index of [8, 9]) {
            await page.locator('[data-stage-id="stage_34_' + index + '"].stage-select-stage-button > .stage-select-stage-name').click();
            await page.waitForFunction(() => document.querySelector('.stage-focus-surface'));
            assert.equal((await page.evaluate(() => StageSelectDiorama.stats())).focusId, '');
            await page.screenshot({ path: path.join(out, 'wormhole-' + index + '.png') });
            await page.getByRole('button', { name: '返回总览', exact: true }).click();
            await ready();
        }
        report.checks.push('Wormhole outer/entrance remain 2D focus entries without a fabricated 3D anchor');
        await page.locator('[data-nav-id="nav_34_1"]').click();
        await page.waitForFunction(() => StageSelectPanel._debugGetState().frameLabel === '沙漠虫洞');
        assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 0);
        await page.locator('[data-nav-id="nav_46_0"]').click();
        await ready();
        assert.equal((await page.evaluate(() => StageSelectPanel._debugGetState())).frameLabel, '基地房顶');
        report.checks.push('Wormhole navigation and return retain existing local-frame protocol');
        await page.locator('[data-stage-id="stage_34_10"].stage-select-stage-button').click();
        await page.waitForFunction(() => Panels.getActive() === null);
        report.diplomacy = await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1));
        assert.equal(report.diplomacy.stageName, '外交-军阀');
        assert.equal(report.diplomacy.entryKind, 'map');
        assert.ok(!report.diplomacy.difficulty);
        report.checks.push('Diplomacy entry preserves the existing map-entry request');
        report.cycles = [];
        for (let i = 0; i < 3; i++) {
            await open();
            const s = await page.evaluate(() => StageSelectDiorama.stats());
            report.cycles.push({ geometries: s.geometries, textures: s.textures, calls: s.calls });
            await page.evaluate(() => StageSelectHarnessHost.close());
            assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 0);
        }
        assert.equal(new Set(report.cycles.map(row => JSON.stringify(row))).size, 1);
        await open();
        await page.evaluate(() => document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
        await page.waitForFunction(() => StageSelectDiorama.stats().state === 'fallback');
        assert.equal(await page.locator('.stage-select-stage-button').count(), 11);
        await page.screenshot({ path: path.join(out, 'fallback.png') });
        await page.getByRole('button', { name: '重试', exact: true }).click();
        await ready();
        report.checks.push('Three reopen cycles have stable resource counts; context loss retains 2D entries; retry reloads');
        assert.deepEqual(errors, []);
        report.pass = true;
    } catch (error) {
        report.pass = false; report.error = error.stack; report.pageErrors = errors;
        report.lastState = await page.evaluate(() => window.StageSelectDiorama && StageSelectDiorama.stats()).catch(() => null);
        process.exitCode = 1;
        await page.screenshot({ path: path.join(out, 'failure.png') });
    } finally {
        await browser.close(); server.close();
        fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
        console.log(JSON.stringify(report));
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
