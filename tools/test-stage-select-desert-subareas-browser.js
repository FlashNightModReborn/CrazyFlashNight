'use strict';
const fs = require('fs'), path = require('path'), assert = require('assert/strict');
const { startServer } = require('./lib/stage-select-dev-server');
const root = path.resolve(__dirname, '..');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const fixture = process.argv.includes('--fixture-subareas');
const out = path.join(root, 'tmp/stage-select-desert-subareas' + (fixture ? '-fixture' : ''));
const counts = { stage_34_1: 3, stage_34_4: 4, stage_34_5: 4 };
async function main() {
    fs.mkdirSync(out, { recursive: true });
    const config = JSON.parse(fs.readFileSync(path.join(root, 'launcher/web/assets/stage-diorama/desert-region/config.json'), 'utf8'));
    if (fixture) for (const [id, count] of Object.entries(counts)) {
        const bounds = config.pins[id].focusBounds, width = (bounds.max[0] - bounds.min[0]) / count;
        config.pins[id].subareas = Array.from({ length: count }, (_, i) => {
            const min = bounds.min.slice(), max = bounds.max.slice(); min[0] += width * i; max[0] = min[0] + width;
            return { id: 'fixture-area-' + i, label: '测试分段 ' + (i + 1), subStageIndex: i, sourceBackground: 'fixture-only-' + i + '.png',
                worldBounds: { min, max }, worldCenter: min.map((n, axis) => (n + max[axis]) / 2) };
        });
    }
    for (const [id, count] of Object.entries(counts)) assert.equal(config.pins[id].subareas?.length, count, id + ': production subarea data is required');
    const { server, origin } = await startServer(path.join(root, 'launcher/web'));
    const browser = await chromium.launch({ executablePath: path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe'), headless: true });
    const page = await browser.newPage({ viewport: { width: 1024, height: 576 } }); page.setDefaultTimeout(60000);
    const errors = [], report = { scope: fixture ? 'UI lifecycle fixture with synthetic subareas over a real GLB; not real partition geometry acceptance' : 'Production subarea metadata and real GLB with mock Host; not Flash/WebView2 E2E', checks: [], stages: [] };
    page.on('pageerror', error => errors.push(error.message));
    await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
    if (fixture) await page.route('**/stage-diorama/desert-region/config.json', route => route.fulfill({ contentType: 'application/json', body: JSON.stringify(config) }));
    const ready = () => page.waitForFunction(() => StageSelectDiorama.stats().state === 'ready' && !StageSelectDiorama.stats().moving && !StageSelectDiorama.stats().pending);
    const messages = () => page.evaluate(() => [StageSelectHarnessHost.enterMessages.length, StageSelectHarnessHost.jumpMessages.length, StageSelectHarnessHost.returnMessages.length]);
    const pose = () => page.evaluate(() => StageSelectDiorama.snapshotCamera());
    const observation = () => page.evaluate(() => StageSelectDiorama.stats().subareaObservation);
    const near = (a, b) => { for (const key of ['position', 'target']) a[key].forEach((n, i) => assert.ok(Math.abs(n - b[key][i]) < 1e-7)); assert.ok(Math.abs(a.span - b.span) < 1e-7); };
    const unobscured = (frame, rectangles) => {
        assert.ok(frame.projectedPixels && frame.viewport);
        const sx = (rectangles.viewport.right - rectangles.viewport.x) / frame.viewport.width;
        const sy = (rectangles.viewport.bottom - rectangles.viewport.y) / frame.viewport.height;
        const bounds = { left: rectangles.viewport.x + frame.projectedPixels.left * sx,
            right: rectangles.viewport.x + frame.projectedPixels.right * sx,
            top: rectangles.viewport.y + frame.projectedPixels.top * sy,
            bottom: rectangles.viewport.y + frame.projectedPixels.bottom * sy };
        assert.ok(bounds.left >= rectangles.viewport.x && bounds.right <= rectangles.viewport.right);
        assert.ok(bounds.top >= rectangles.viewport.y && bounds.bottom <= rectangles.bar.y - 5,
            'Own geometry projection must stay above the observation controls: ' + JSON.stringify({ bounds, rectangles }));
        return { ...bounds, bottomClearance: rectangles.bar.y - bounds.bottom, source: frame.source };
    };
    const bar = page.locator('.stage-desert-area-controls');
    const openStage = async id => { await page.locator('[data-stage-id="' + id + '"].stage-select-stage-button > .stage-select-stage-name').click(); await ready(); };
    try {
        await page.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576&frame=' + encodeURIComponent('基地房顶') + '&fixture=allUnlocked&player=1&review=subareas');
        await ready();
        const initial = await page.evaluate(() => StageSelectDiorama.stats());
        report.sceneHash = initial.loadedHashes['scene.glb']; report.focusFraming = initial.focusFraming;
        for (const [id, count] of Object.entries(counts)) {
            const frames = initial.focusFraming[id].subareas;
            assert.equal(frames.length, count);
            assert.deepEqual(frames.map(frame => frame.subStageIndex), Array.from({ length: count }, (_, i) => i));
            for (const frame of frames) {
                if (!fixture) { assert.equal(frame.source, 'owner-vertices', id + '/' + frame.id + ': production partition mesh metadata is required'); assert.ok(frame.vertices > 0); }
                assert.ok(frame.projectedWidth <= frame.span / 1.15 + .0001);
                assert.ok(frame.projectedHeight <= frame.span / frame.viewportAspect / 1.15 + .0001, id + '/' + frame.id + ': high geometry must stay inside the frame');
            }
        }
        const stored = await page.evaluate(() => JSON.stringify(Object.entries(localStorage)));
        assert.equal(await bar.count(), 0);
        for (const [id, count] of Object.entries(counts)) {
            await openStage(id); const whole = await pose(), before = await messages();
            assert.equal(await bar.count(), 1); assert.equal(await bar.locator('button').count(), count + 1);
            assert.equal(await bar.locator(':scope > span').innerText(), '观察范围');
            assert.equal(await bar.locator('[title]').count(), 0);
            assert.deepEqual(await bar.locator('button').allTextContents(), ['整关', ...Array.from({ length: count }, (_, i) => '第' + (i + 1) + '段')]);
            const rectangles = await bar.evaluate(node => {
                const rect = element => { const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, right: r.right, bottom: r.bottom }; };
                return { bar: rect(node), viewport: rect(node.parentElement) };
            });
            assert.ok(rectangles.bar.x >= rectangles.viewport.x && rectangles.bar.right <= rectangles.viewport.right);
            assert.ok(rectangles.bar.y >= rectangles.viewport.y && rectangles.bar.bottom <= rectangles.viewport.bottom);
            const stageFrame = await page.evaluate(stageId => StageSelectDiorama.stats().focusFraming[stageId], id);
            await page.locator('#stage-select-inspector-difficulties [data-difficulty="冒险"]').click();
            await page.screenshot({ path: path.join(out, id + '-whole.png') });
            const stage = { id, rectangles, whole, wholeSelfGeometryProjection: unobscured(stageFrame, rectangles), subareas: [] };
            for (let i = 0; i < count; i++) {
                const area = config.pins[id].subareas[i], button = bar.locator('[data-subarea="' + area.id + '"]');
                if (i === 1) { await button.focus(); await page.keyboard.press('Enter'); } else await button.click();
                await ready(); const camera = await pose(); assert.notDeepEqual(camera, whole);
                const framed = stageFrame.subareas.find(frame => frame.id === area.id);
                assert.ok(Math.abs(camera.span - framed.span) < 1e-7);
                assert.equal((await observation()).selectedSubareaId, area.id);
                assert.equal(await page.evaluate(() => StageSelectDiorama.stats().focusId), id);
                assert.equal(await page.evaluate(() => StageSelectCore.state._selectedStageId), id);
                assert.equal(await page.locator('#stage-select-inspector-difficulties .is-chosen').getAttribute('data-difficulty'), '冒险');
                assert.equal(await bar.locator('[aria-pressed="true"]').count(), 1);
                assert.deepEqual(await messages(), before);
                stage.subareas.push({ id: area.id, subStageIndex: area.subStageIndex, sourceBackground: area.sourceBackground,
                    selfGeometryProjection: unobscured(framed, rectangles), camera });
                await page.screenshot({ path: path.join(out, id + '-area-' + (i + 1) + '.png') });
            }
            assert.equal(new Set(stage.subareas.map(area => JSON.stringify([area.camera.target.map(n => Number(n.toFixed(6))), Number(area.camera.span.toFixed(6))]))).size, count, 'Each partition must have a distinct camera');
            const selected = await observation(), selectedCamera = await pose();
            const stageName = await page.locator('.stage-select-inspector-name').innerText();
            await page.evaluate(name => StageSelectPanel._debugApplySnapshot({ stageDetails: { [name]: { task: true, highestDifficulty: '冒险' } } }), stageName);
            await ready(); assert.deepEqual(await observation(), selected); near(await pose(), selectedCamera);
            await page.getByRole('button', { name: '游览地点', exact: true }).click();
            await page.waitForFunction(() => StageSelectDiorama.stats().editing); assert.equal(await bar.isVisible(), false);
            await page.getByRole('button', { name: '结束游览', exact: true }).first().click(); await ready();
            assert.equal(await bar.isVisible(), true); assert.deepEqual(await observation(), selected); near(await pose(), selectedCamera);
            stage.resizes = [];
            const originalSize = await page.locator('.stage-focus-viewport').evaluate(host => ({ width: host.clientWidth, height: host.clientHeight }));
            for (const size of [{ width: originalSize.width - 80, height: originalSize.height - 60 },
                { width: originalSize.width + 40, height: originalSize.height - 24 }, originalSize]) {
                await page.locator('.stage-focus-viewport').evaluate((host, value) => {
                    host.style.width = value.width + 'px'; host.style.height = value.height + 'px';
                }, size);
                await page.waitForFunction(({ id, size }) => {
                    const layout = StageSelectDiorama.stats().subareaObservation.layout;
                    return StageSelectDiorama.stats().focusId === id && layout?.width === size.width && layout?.height === size.height;
                }, { id, size });
                await ready();
                const adjustedFrame = await page.evaluate(({ id, area }) => StageSelectDiorama.stats().focusFraming[id].subareas.find(frame => frame.id === area),
                    { id, area: selected.selectedSubareaId });
                const adjustedRects = await bar.evaluate(node => {
                    const rect = element => { const r = element.getBoundingClientRect(); return { x: r.x, y: r.y, right: r.right, bottom: r.bottom }; };
                    return { bar: rect(node), viewport: rect(node.parentElement) };
                });
                assert.equal((await observation()).selectedSubareaId, selected.selectedSubareaId);
                stage.resizes.push({ size, selfGeometryProjection: unobscured(adjustedFrame, adjustedRects) });
            }
            await page.locator('.stage-focus-viewport').evaluate(host => { host.style.removeProperty('width'); host.style.removeProperty('height'); });
            await ready(); near(await pose(), selectedCamera); assert.deepEqual(await observation(), selected);
            await bar.locator('[data-subarea="whole"]').click(); await ready(); near(await pose(), whole);
            assert.deepEqual(await messages(), before);
            await page.getByRole('button', { name: '返回总览', exact: true }).click(); await ready(); assert.equal(await bar.count(), 0);
            report.stages.push(stage);
        }
        report.checks.push('3/4/4 ordered controls change only the camera; mouse and Enter work; selected stage, difficulty and business messages remain unchanged; snapshots and tour return preserve the selected section; actual owner geometry projections stay above the controls in whole and section views');
        await openStage('stage_34_8'); assert.equal(await bar.count(), 0);
        await page.getByRole('button', { name: '返回总览', exact: true }).click(); await ready();
        await openStage('stage_34_1'); assert.equal((await observation()).selectedSubareaId, 'whole'); near(await pose(), report.stages[0].whole);
        await bar.locator('button').nth(2).click(); await ready();
        await page.evaluate(() => document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
        await page.waitForFunction(() => StageSelectDiorama.stats().state === 'fallback'); assert.equal(await bar.count(), 0);
        await page.getByRole('button', { name: '返回总览', exact: true }).click();
        await page.getByRole('button', { name: '重试', exact: true }).click(); await ready();
        assert.equal(await bar.count(), 0); await openStage('stage_34_1');
        assert.equal((await observation()).selectedSubareaId, 'whole'); assert.equal(await bar.count(), 1);
        await page.evaluate(() => StageSelectHarnessHost.close()); assert.equal(await bar.count(), 0);
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地房顶' })); await ready();
        assert.equal(await bar.count(), 0); await openStage('stage_34_1'); assert.equal((await observation()).selectedSubareaId, 'whole'); near(await pose(), report.stages[0].whole);
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' })); await ready();
        await openStage('stage_0_9'); assert.equal(await bar.count(), 0);
        assert.equal(await page.evaluate(() => JSON.stringify(Object.entries(localStorage))), stored);
        assert.deepEqual(errors, []);
        report.checks.push('Logical viewport resize and restoration keep the selected section clear of controls without accumulating camera offsets; repeated entry restores the same whole-stage camera; overview, 2D, old 3D, close and context loss retire controls; section choices never write presets');
        report.pass = true;
    } catch (error) {
        report.pass = false; report.error = error.stack; report.pageErrors = errors; process.exitCode = 1;
        await page.screenshot({ path: path.join(out, 'failure.png') });
    } finally { await browser.close(); server.close(); fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2)); console.log(JSON.stringify(report)); }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
