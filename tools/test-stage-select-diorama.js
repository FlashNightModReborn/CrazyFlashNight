'use strict';
const fs = require('fs');
const path = require('path');
const assert = require('assert/strict');
const { startServer } = require('./lib/stage-select-dev-server');
const root = path.resolve(__dirname, '..');
const { chromium } = require(path.join(root, 'launcher/perf/node_modules/playwright'));
const out = path.join(root, 'tmp/stage-select-diorama');

async function main() {
    fs.mkdirSync(out, { recursive: true });
    const { server, origin } = await startServer(path.join(root, 'launcher/web'));
    const edge = path.join(process.env['ProgramFiles(x86)'], 'Microsoft/Edge/Application/msedge.exe');
    let browser, page;
    const report = { scope: 'Real GLB and browser input with mock Host; not game/WebView2 E2E.', checks: [] };
    try {
        browser = await chromium.launch({ executablePath: edge, headless: true });
        page = await browser.newPage({ viewport: { width: 1024, height: 576 } });
        const errors = [];
        page.on('pageerror', error => errors.push(error.message));
        await page.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
        await page.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576&fixture=allUnlocked');
        await page.evaluate(() => {
            document.body.classList.add('stage-select-qa');
            document.querySelector('#debug-log')?.remove();
            document.querySelector('#qa-panel')?.remove();
            StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' });
        });
        const ready = () => page.waitForFunction(() => StageSelectPanel._debugGetState().diorama.state === 'ready'
            && StageSelectPanel._debugGetState().runtimeSnapshot, null, { timeout: 20000 });
        await ready();
        await page.waitForTimeout(100);
        report.cold = await page.evaluate(() => StageSelectDiorama.stats());
        assert.equal(report.cold.width, 1024);
        assert.equal(report.cold.height, 576);
        assert.ok(report.cold.triangles > 150000 && report.cold.calls < 100);
        await page.screenshot({ path: path.join(out, 'base-gate-1024.png') });
        report.checks.push('real GLB, 16 verified camera anchors, fixed 1024x576 buffer');
        const layout = await page.evaluate(() => {
            const nodes = [...document.querySelectorAll('.stage-select-stage-button')];
            const boxes = [];
            const failures = [];
            for (const node of nodes) {
                for (const selector of ['.stage-select-stage-name', '.stage-select-hit-zone']) {
                    const el = node.querySelector(selector), r = el.getBoundingClientRect();
                    const hit = document.elementFromPoint(r.x+r.width/2, r.y+r.height/2);
                    if (!node.contains(hit)) failures.push(node.dataset.stageId + selector + ' covered by ' + hit?.className);
                    if (r.left < 0 || r.top < 0 || r.right > innerWidth || r.bottom > innerHeight) failures.push(node.dataset.stageId + ' outside');
                    boxes.push({ id: node.dataset.stageId, selector, x: r.x, y: r.y, w: r.width, h: r.height });
                }
            }
            const overlaps = [];
            for (let i=0; i<boxes.length; i++) for (let j=i+1; j<boxes.length; j++) {
                const a=boxes[i], b=boxes[j];
                if (a.id !== b.id && Math.min(a.x+a.w,b.x+b.w)-Math.max(a.x,b.x)>0 && Math.min(a.y+a.h,b.y+b.h)-Math.max(a.y,b.y)>0)
                    overlaps.push([a.id+a.selector,b.id+b.selector]);
            }
            return { count: nodes.length, failures, overlaps, boxes };
        });
        report.layout = layout;
        assert.equal(layout.count, 16);
        assert.deepEqual(layout.failures, []);
        assert.deepEqual(layout.overlaps, []);
        report.checks.push('all 32 marker/name centers hit correct entry; no overlap or overflow');
        await page.evaluate(() => StageSelectPanel._debugApplySnapshot({ stageDetails: { '第一防线': {
            detail: '军警为阻止蜂拥而来的僵尸所设立的第一道防线，现在已经变成僵尸游荡的场所了', limitDetail: ''
        } } }));
        // 实际悬停并检查重叠区域的命中层级，防止地点名称/标记穿到卡片正文上。
        const ordinaryIds = await page.locator('.stage-select-card-anchor').evaluateAll(els => els.map(el => el.dataset.stageId));
        let coveredLocations = 0;
        for (const id of ordinaryIds) {
            await page.mouse.move(1000, 560);
            await page.waitForTimeout(180);
            await page.locator('.stage-select-stage-button[data-stage-id="'+id+'"] > .stage-select-stage-name').hover();
            const card = page.locator('.stage-select-card-anchor[data-stage-id="'+id+'"] > .stage-select-card');
            await card.waitFor({ state: 'visible' });
            const hitChecks = await card.evaluate(el => {
                const c = el.getBoundingClientRect(), failures = [];
                let overlaps = 0;
                for (const item of document.querySelectorAll('.stage-select-stage-name, .stage-select-hit-zone')) {
                    const r = item.getBoundingClientRect();
                    const l=Math.max(c.left,r.left), t=Math.max(c.top,r.top), right=Math.min(c.right,r.right), bottom=Math.min(c.bottom,r.bottom);
                    if (right-l <= 2 || bottom-t <= 2) continue;
                    overlaps++;
                    if (!el.contains(document.elementFromPoint((l+right)/2,(t+bottom)/2))) failures.push(item.parentElement.dataset.stageId);
                }
                return { overlaps, failures };
            });
            coveredLocations += hitChecks.overlaps;
            assert.deepEqual(hitChecks.failures, [], 'card must cover locations for '+id);
            if (id === 'stage_0_4') await page.screenshot({ path: path.join(out, 'base-gate-hover-layering.png') });
        }
        assert.ok(coveredLocations > 0, 'exercise actual overlapping city labels');
        const hoverDifficulty = page.locator('.stage-select-card-anchor.is-card-open [data-difficulty="简单"]');
        await hoverDifficulty.click();
        await page.waitForFunction(() => Panels.getActive() === null);
        assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1).difficulty), '简单');
        report.checks.push('all 14 hover cards cover overlapping labels/markers; hover difficulty remains clickable');
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
        await ready();
        await page.mouse.move(1000, 560);
        await page.waitForTimeout(180);
        await page.locator('[data-stage-id="stage_0_0"] > .stage-select-stage-name').click();
        await page.waitForFunction(() => StageSelectPanel._debugGetState().selectedStageId === 'stage_0_0');
        await page.screenshot({ path: path.join(out, 'base-gate-inspector.png') });
        await page.locator('#stage-select-inspector-difficulties [data-difficulty="简单"]').click();
        assert.equal(await page.evaluate(() => Panels.getActive()), 'stage-select');
        await page.locator('#stage-focus-enter').click();
        await page.waitForFunction(() => Panels.getActive() === null);
        assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1).stageName), '新手练习场');
        report.checks.push('real mouse selects ordinary entry; difficulty sends existing payload and closes');
        for (const id of ['stage_0_10', 'stage_0_15']) {
            await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
            await ready();
            await page.locator('[data-stage-id="'+id+'"] > .stage-select-stage-name').click();
            await page.waitForFunction(() => Panels.getActive() === null);
            const msg = await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1));
            assert.equal(msg.entryKind, 'map');
            assert.ok(!msg.difficulty);
        }
        report.checks.push('both diplomacy entries remain one-click map actions');
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
        await ready();
        const beforeIdle = await page.evaluate(() => StageSelectDiorama.stats());
        await page.waitForTimeout(700);
        assert.equal((await page.evaluate(() => StageSelectDiorama.stats())).frames, beforeIdle.frames);
        report.checks.push('idle does not render frames');
        for (let i=0; i<30; i++) {
            await page.evaluate(() => { StageSelectHarnessHost.close(); StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }); });
            await ready();
        }
        report.after30 = await page.evaluate(() => StageSelectDiorama.stats());
        assert.equal(report.after30.geometries, beforeIdle.geometries);
        assert.equal(report.after30.textures, beforeIdle.textures);
        assert.equal(await page.locator('.stage-select-diorama-canvas').count(), 1);
        report.checks.push('30 opens keep one canvas and bounded geometry/texture cache');
        await page.evaluate(() => StageSelectRenderer.setFrame('基地车库', 'qa'));
        assert.equal(await page.evaluate(() => StageSelectDiorama.stats().active), false);
        assert.equal(await page.locator('.stage-select-diorama').isVisible(), false);
        await page.evaluate(() => StageSelectRenderer.setFrame('基地门口', 'qa'));
        await ready();
        await page.evaluate(() => document.querySelector('.stage-select-diorama-canvas').getContext('webgl2').getExtension('WEBGL_lose_context').loseContext());
        await page.waitForFunction(() => StageSelectDiorama.stats().state === 'error');
        assert.equal(await page.evaluate(() => StageSelectDiorama.stats().state), 'error');
        assert.equal(await page.locator('#stage-select-bg').evaluate(el => getComputedStyle(el).visibility), 'hidden');
        await page.locator('.stage-select-diorama-status button').click();
        await ready();
        report.checks.push('switch away hides 3D; context loss exposes retry, no 2D fallback; retry recovers');
        await page.evaluate(() => {
            StageSelectPanel._debugApplySnapshot({ unlockedStages: { '新手练习场': false },
                stageDetails: { '新手练习场': { lockReason: '三维测试锁定原因' } } });
        });
        const lockedHit = await page.locator('[data-stage-id="stage_0_0"] > .stage-select-hit-zone').boundingBox();
        // 锁定节点 aria-disabled 阻止 Playwright locator.click，但产品允许指针查看锁定原因。
        await page.mouse.click(lockedHit.x+lockedHit.width/2, lockedHit.y+lockedHit.height/2);
        assert.match(await page.locator('#stage-select-inspector-lock').innerText(), /三维测试锁定原因/);
        assert.equal(await page.locator('#stage-select-inspector-difficulties .stage-select-difficulty').count(), 0);
        await page.keyboard.press('Escape');
        await page.locator('.stage-select-stage-button[data-stage-id="stage_0_0"]').focus();
        await page.keyboard.press('ArrowUp');
        assert.equal(await page.evaluate(() => document.activeElement.dataset.stageId), 'stage_0_1');
        report.checks.push('locked inspector keeps live reason; keyboard up follows projected city positions');
        // 冷加载尚未完成时关闭，迟到结果只能进入固定单缓存，不可重新显示面板。
        const late = await browser.newPage({ viewport: { width: 1024, height: 576 } });
        await late.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
        let releaseLoad;
        const hold = new Promise(resolve => { releaseLoad = resolve; });
        await late.route('**/city.glb', async route => { await hold; await route.continue(); });
        await late.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576');
        await late.waitForFunction(() => StageSelectDiorama.stats().pending);
        await late.evaluate(() => StageSelectHarnessHost.close());
        releaseLoad();
        await late.waitForFunction(() => !StageSelectDiorama.stats().pending);
        assert.equal(await late.evaluate(() => Panels.getActive()), null);
        assert.equal(await late.locator('.stage-select-diorama').isVisible(), false);
        await late.close();
        report.checks.push('late cold load after close never reopens or reveals the scene');
        const broken = await browser.newPage({ viewport: { width: 1024, height: 576 } });
        await broken.route('https://cfn-fonts.local/**', route => route.fulfill({ status: 204, body: '' }));
        await broken.route('**/city.glb', route => route.fulfill({ status: 404, body: '' }));
        await broken.goto(origin + '/modules/stage-select/dev/harness.html?viewport=1024x576');
        await broken.waitForFunction(() => StageSelectDiorama.stats().state === 'error');
        assert.equal(await broken.locator('#stage-select-button-layer').evaluate(el => el.inert), true);
        await broken.unroute('**/city.glb');
        await broken.locator('.stage-select-diorama-status button').click();
        await broken.waitForFunction(() => StageSelectDiorama.stats().state === 'ready');
        await broken.close();
        report.checks.push('missing GLB disables city entries; visible retry loads successfully');
        assert.deepEqual(errors, []);
        report.pass = true;
    } catch (error) {
        report.pass = false;
        report.error = error.stack;
        if (page) {
            report.failureState = await page.evaluate(() => StageSelectPanel._debugGetState());
            await page.screenshot({ path: path.join(out, 'failure.png') });
        }
        process.exitCode = 1;
    } finally {
        if (browser) await browser.close();
        server.close();
        fs.writeFileSync(path.join(out, 'report.json'), JSON.stringify(report, null, 2));
        console.log(JSON.stringify(report, null, 2));
    }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
