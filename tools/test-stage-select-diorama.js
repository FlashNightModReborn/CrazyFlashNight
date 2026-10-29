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
        await page.evaluate(() => StageSelectPanel._debugApplySnapshot({unlockedStages:StageSelectCore.state._runtimeSnapshot.unlockedStages,stageDetails: { '第一防线': {
            detail: '军警为阻止蜂拥而来的僵尸所设立的第一道防线，现在已经变成僵尸游荡的场所了', limitDetail: ''
        } } }));
        // 实际悬停并检查重叠区域的命中层级，防止地点名称/标记穿到卡片正文上。
        const ordinaryIds = await page.locator('.stage-select-card-anchor:not(.is-map-entry)').evaluateAll(els => els.map(el => el.dataset.stageId));
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
        const trail = await page.evaluate(() => {
            const anchor = document.querySelector('.stage-select-card-anchor.is-card-open');
            const id = anchor.dataset.stageId;
            const stage = document.querySelector('#stage-select-stage').getBoundingClientRect();
            const client = (x, y) => ({ x: stage.left + x * stage.width / 1024, y: stage.top + y * stage.height / 576 });
            const hit = document.querySelector('.stage-select-stage-button[data-stage-id="' + id + '"] > .stage-select-hit-zone').getBoundingClientRect();
            const connection = anchor._cardConnection;
            return { id, points: [
                { x: hit.left + hit.width / 2, y: hit.top + hit.height / 2 },
                client(connection.x1, connection.y1),
                client(connection.x2, connection.y2)
            ] };
        });
        for (const point of trail.points) {
            await page.mouse.move(point.x, point.y, { steps: 8 });
            await page.waitForTimeout(20);
            assert.equal(await page.evaluate(() => StageSelectPanel._debugGetState().openCardStageId), trail.id, 'hover must survive the real node-to-card route');
        }
        report.checks.push('real pointer route keeps the compact card open through the geometric connection');
        const hoverDifficulty = page.locator('.stage-select-card-anchor.is-card-open [data-difficulty="简单"]');
        await hoverDifficulty.click();
        await page.waitForFunction(() => Panels.getActive() === null);
        assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1).difficulty), '简单');
        report.checks.push('all 14 hover cards cover overlapping labels/markers; hover difficulty remains clickable');
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
        await ready();
        await page.mouse.move(1000, 560);
        await page.waitForTimeout(180);
        // 单击 = 锁定快捷卡：不进详情、不发 enter，三维以地名为支点推近，地名留在光标下。
        const pinLabel = page.locator('[data-stage-id="stage_0_0"] > .stage-select-stage-name');
        const pinBefore = await pinLabel.boundingBox();
        await pinLabel.click();
        await page.waitForFunction(() => !StageSelectDiorama.stats().moving);
        const pinState = await page.evaluate(() => StageSelectPanel._debugGetState());
        assert.equal(pinState.quick.pinnedStageId, 'stage_0_0');
        assert.equal(pinState.inspectorOpen, false);
        assert.equal(pinState.quick.pinZoomed, true, 'first pin dollies the overview camera toward the node');
        const pinAfter = await pinLabel.boundingBox();
        assert.ok(Math.abs(pinAfter.x - pinBefore.x) <= 8 && Math.abs(pinAfter.y - pinBefore.y) <= 8, 'pivot zoom keeps the pinned label under the cursor');
        await page.screenshot({ path: path.join(out, 'base-gate-pinned.png') });
        await page.keyboard.press('Escape');
        await page.waitForFunction(() => !StageSelectDiorama.stats().moving && !StageSelectPanel._debugGetState().quick.pinnedStageId);
        report.checks.push('real mouse single click pins the quick card with pivot zoom and Escape restores the overview');
        await page.locator('[data-stage-id="stage_0_0"] > .stage-select-stage-name').dblclick();
        await page.waitForFunction(() => StageSelectPanel._debugGetState().selectedStageId === 'stage_0_0');
        await page.screenshot({ path: path.join(out, 'base-gate-inspector.png') });
        await page.locator('#stage-select-inspector-difficulties [data-difficulty="简单"]').click();
        assert.equal(await page.evaluate(() => Panels.getActive()), 'stage-select');
        await page.locator('#stage-focus-enter').click();
        await page.waitForFunction(() => Panels.getActive() === null);
        assert.equal(await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1).stageName), '新手练习场');
        report.checks.push('real mouse selects ordinary entry; difficulty sends existing payload and closes');
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
        await ready();
        await page.locator('[data-stage-id="stage_0_10"] > .stage-select-stage-name').hover();
        await page.locator('.stage-select-card-anchor[data-stage-id="stage_0_10"] .stage-select-map-action').click();
        await page.waitForFunction(() => Panels.getActive() === null);
        let msg = await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1));
        assert.equal(msg.entryKind, 'map');
        assert.ok(!msg.difficulty);
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地门口' }));
        await ready();
        await page.locator('[data-stage-id="stage_0_15"] > .stage-select-stage-name').dblclick();
        await page.waitForFunction(() => StageSelectPanel._debugGetState().selectedStageId === 'stage_0_15');
        await page.locator('#stage-focus-enter').click();
        await page.waitForFunction(() => Panels.getActive() === null);
        msg = await page.evaluate(() => StageSelectHarnessHost.enterMessages.at(-1));
        assert.equal(msg.entryKind, 'map');
        assert.ok(!msg.difficulty);
        report.checks.push('both diplomacy entries support hover card action and focus view entry');
        await page.evaluate(() => StageSelectHarnessHost.open({ mode: 'runtime', frameLabel: '基地车库' }));
        await ready();
        report.reportedCards = [];
        for (const id of ['stage_10_2', 'stage_10_12']) {
            await page.mouse.move(1000, 560);
            await page.waitForTimeout(180);
            // 三维以地名牌为主要瞄准目标：地名经长引线贴近舞台边缘时，快捷卡贴地名停靠并允许压住本节点信标。
            await page.locator('.stage-select-stage-button[data-stage-id="'+id+'"] > .stage-select-stage-name').hover();
            const card = page.locator('.stage-select-card-anchor[data-stage-id="'+id+'"] > .stage-select-card');
            await card.waitFor({ state: 'visible' });
            const contract = await card.evaluate(el => {
                const actions = el.querySelector(':scope > .stage-select-difficulties');
                const content = el.querySelector(':scope > .stage-select-card-content');
                const cardRect = el.getBoundingClientRect();
                const buttons = [...actions.querySelectorAll('button')].map(button => {
                    const r = button.getBoundingClientRect(), style = getComputedStyle(button);
                    return { text: button.textContent, left: r.left, top: r.top, right: r.right, bottom: r.bottom,
                        whiteSpace: style.whiteSpace, singleLine: !button.classList.contains('stage-select-map-action') || style.whiteSpace === 'nowrap',
                        clipped: button.scrollWidth > button.clientWidth + 1 };
                });
                const sizes = el.parentElement._cardLayoutSizes;
                return { id: el.parentElement.dataset.stageId, side: el.parentElement.dataset.placement,
                    cardDirection: getComputedStyle(el).flexDirection, contentDirection: getComputedStyle(content).flexDirection,
                    actionDirection: getComputedStyle(actions).flexDirection, actionWidth: actions.clientWidth,
                    cornerDisplay: getComputedStyle(el.querySelector('.stage-select-card-corner')).display,
                    animationName: getComputedStyle(el).animationName,
                    sameSizeForEverySide: ['above', 'below', 'left', 'right'].every(side =>
                        sizes[side].width === sizes.above.width && sizes[side].height === sizes.above.height),
                    cardBounds: { left: cardRect.left, top: cardRect.top, right: cardRect.right, bottom: cardRect.bottom }, buttons };
            });
            report.reportedCards.push(contract);
            assert.equal(contract.cardDirection, 'column');
            assert.equal(contract.contentDirection, 'column');
            assert.equal(contract.actionDirection, 'row');
            assert.ok(contract.actionWidth > 100, 'side card retains the full-width horizontal action row');
            assert.equal(contract.cornerDisplay, 'none');
            assert.equal(contract.sameSizeForEverySide, true);
            assert.equal(contract.animationName, 'stageSelectCardFade');
            assert.ok(contract.buttons.length > 0);
            for (const button of contract.buttons) {
                assert.equal(button.clipped, false, button.text + ' must not be clipped');
                assert.equal(button.singleLine, true, 'diplomacy action must stay on one line');
                assert.ok(button.left >= contract.cardBounds.left - 1 && button.right <= contract.cardBounds.right + 1
                    && button.top >= contract.cardBounds.top - 1 && button.bottom <= contract.cardBounds.bottom + 1,
                    button.text + ' must fit within the card');
            }
            await card.evaluate(el => Promise.all(el.getAnimations().map(animation => animation.finished.catch(() => {}))));
            await page.screenshot({ path: path.join(out, id + '-hover.png') });
        }
        // 2026-10-29 Flash 手感合同：快捷卡只停上/下方（难度行方向可盲点），三维战区同样不得侧向停靠。
        assert.ok(report.reportedCards.every(card => card.side === 'above' || card.side === 'below'), 'quick cards never dock sideways');
        await page.emulateMedia({ reducedMotion: 'reduce' });
        assert.equal(await page.locator('.stage-select-card-anchor.is-card-open > .stage-select-card').evaluate(el => getComputedStyle(el).animationName), 'none');
        await page.emulateMedia({ reducedMotion: 'no-preference' });
        report.checks.push('reported combat/diplomacy cards share one horizontal-action structure; all side sizes match, text fits, corner is absent and opacity fade honors reduced motion');
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
        await page.evaluate(() => StageSelectRenderer.setFrame('地下2层', 'qa'));
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
            StageSelectPanel._debugApplySnapshot({ unlockedStages: { ...StageSelectCore.state._runtimeSnapshot.unlockedStages, '新手练习场': false },
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
