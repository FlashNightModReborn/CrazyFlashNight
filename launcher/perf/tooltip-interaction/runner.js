#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {chromium} = require('playwright');
const {startServer, stopServer} = require('../lib/server.js');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const LAUNCHER = path.join(ROOT, 'launcher');
const TOOLTIP_SOURCE = path.join(ROOT, 'launcher', 'web', 'modules', 'tooltip.js');
const TOOLTIP_CSS = path.join(ROOT, 'launcher', 'web', 'css', 'panels', 'foundation-rest.css');

function edgePath() {
    const candidates = [
        process.env.PROGRAMFILES && path.join(process.env.PROGRAMFILES, 'Microsoft', 'Edge', 'Application', 'msedge.exe'),
        process.env['PROGRAMFILES(X86)'] && path.join(process.env['PROGRAMFILES(X86)'], 'Microsoft', 'Edge', 'Application', 'msedge.exe')
    ].filter(Boolean);
    return candidates.find(candidate => fs.existsSync(candidate)) || '';
}

function assert(condition, message, evidence) {
    if (!condition) {
        const error = new Error(message);
        error.evidence = evidence;
        throw error;
    }
}

function staticAudit() {
    const source = fs.readFileSync(TOOLTIP_SOURCE, 'utf8');
    const css = fs.readFileSync(TOOLTIP_CSS, 'utf8');
    const requirements = [
        [source.includes("var DEFAULT_INSPECTION_DELAY = 1000"), 'default inspection delay must stay 1000ms'],
        [source.includes("var PROFILE_DENSE = 'dense-inspect'"), 'dense profile missing'],
        [source.includes("var PROFILE_PINNED = 'pinned-inspector'"), 'pinned profile missing'],
        [source.includes('function showPinned('), 'showPinned API missing'],
        [source.includes('onPointerSuperseded'), 'new pointer owner preemption missing'],
        [source.includes('consumeAtBoundary'), 'wheel boundary ownership missing'],
        [css.includes('#panel-tooltip[data-tooltip-profile="dense-inspect"]'), 'dense CSS profile missing'],
        [css.includes('pointer-events:none'), 'dense tooltip must stay outside hit testing'],
        [css.includes('#panel-tooltip[data-tooltip-profile="pinned-inspector"]'), 'pinned CSS profile missing'],
        [css.includes('.flash-tt-desc::-webkit-scrollbar'), 'dense description scrollbar skin missing'],
        [css.includes('.panel-tooltip-inspector-body::-webkit-scrollbar'), 'pinned inspector scrollbar skin missing'],
        [css.includes('::-webkit-scrollbar-button'), 'native scrollbar buttons are not suppressed'],
        [css.includes('--tt-scroll-thumb-inspect'), 'inspection scrollbar state token missing'],
        [source.includes("_profile === PROFILE_PINNED) return"), 'applyDescWidth must skip the pinned inspector'],
        [source.includes("key === 'Escape' && _visible && _profile === PROFILE_DENSE"), 'pointer-path Escape exit from dense inspection missing'],
        [css.includes('.flash-tt-suffix'), 'suffix strip skin missing'],
        [css.includes('panel-tooltip-inspection-collapse'), 'inspect status collapse animation missing'],
        [css.includes('.panel-tooltip-inspector-keycap'), 'pinned inspector Esc keycap missing'],
        [css.includes('--tt-shell-bg'), 'pinned inspector shell theme token missing']
    ];
    for (const [ok, message] of requirements) assert(ok, message);
    return {passed:requirements.length,total:requirements.length};
}

async function moveToTile(page, index, options = {}) {
    const center = await page.evaluate(i => window.__tooltipHarness.tileCenter(i), index);
    assert(center, 'tile center missing: ' + index);
    await page.mouse.move(center.x, center.y, {steps:options.steps || 1});
    if (options.wait != null) await page.waitForTimeout(options.wait);
    return center;
}

async function snapshot(page) {
    return page.evaluate(() => window.__tooltipHarness.snapshot());
}

async function reset(page, options) {
    await page.mouse.move(900, 500);
    await page.evaluate(opts => window.__tooltipHarness.reset(opts), options);
    await page.waitForTimeout(30);
}

async function trajectory(page, name, indices, waitMs) {
    await reset(page, {inspectionDelay:300,longContent:true});
    const samples = [];
    for (const index of indices) {
        const center = await moveToTile(page, index, {wait:waitMs});
        const state = await snapshot(page);
        const hitIndex = await page.evaluate(point => {
            const hit = document.elementFromPoint(point.x, point.y);
            const tile = hit && hit.closest && hit.closest('.fixture-tile');
            return tile ? Number(tile.getAttribute('data-tile-index')) : -1;
        }, center);
        assert(state.state.profile === 'dense-inspect', name + ': wrong profile', state);
        assert(state.text.includes('tile-' + index), name + ': tooltip did not follow newest owner', state);
        assert(state.state.inspectionState !== 'inspect', name + ': scan trajectory entered inspect', state);
        assert(state.tooltipPointerEvents === 'none', name + ': tooltip re-entered hit chain', state);
        assert(hitIndex === index, name + ': physical pointer did not hit intended tile', {index,hitIndex,state});
        samples.push({index,inspectionState:state.state.inspectionState,hitIndex});
    }
    return {name,waitMs,samples};
}

async function runBrowserAudit(page) {
    const checks = [];
    const record = (name, evidence) => checks.push({name,pass:true,evidence});

    await reset(page, {inspectionDelay:1000,longContent:true});
    await moveToTile(page, 0, {wait:80});
    let state = await snapshot(page);
    assert(state.state.inspectionState === 'pending', 'overflowing dense tooltip did not advertise pending inspection', state);
    assert(state.ownerStates[0] === 'pending', 'owner cursor feedback did not advertise pending inspection', state);
    const pendingScrollbar = state.descScrollbar;
    assert(pendingScrollbar && pendingScrollbar.width === '6px'
            && pendingScrollbar.buttonDisplay === 'none'
            && pendingScrollbar.buttonWidth === '0px'
            && pendingScrollbar.gutterWidth === 6,
        'dense scrollbar did not replace the native 15px chrome', pendingScrollbar);
    const animationName = await page.$eval('[data-tile-index="0"]', node => getComputedStyle(node).animationName);
    assert(animationName.includes('panel-tooltip-owner-pending'), 'pending owner animation missing', animationName);
    await page.waitForTimeout(980);
    state = await snapshot(page);
    assert(state.state.inspectionState === 'inspect', 'default 1s dwell did not enter inspection', state);
    assert(state.ownerStates[0] === 'inspect', 'owner did not project inspect state', state);
    assert(state.inspectionStatusRect && state.contentRect
            && state.inspectionStatusRect.bottom <= state.contentRect.top + 0.5,
        'inspection status overlaps tooltip content', state);
    assert(state.tooltipRect && state.inspectionStatusRect.top >= state.tooltipRect.top - 0.5,
        'inspection status escapes the tooltip box', state);
    assert(state.inspectionStatusPosition !== 'absolute'
            && state.inspectionStatusBackgroundImage !== 'none'
            && state.inspectionStatusRect.height < 30,
        'inspection status regressed to a hard floating banner', state);
    const inspectOwnerVisual = await page.$eval('[data-tile-index="0"]', node => {
        const style = getComputedStyle(node);
        return {
            outlineWidth:style.outlineWidth,
            outlineStyle:style.outlineStyle,
            outlineOffset:style.outlineOffset,
            animationName:style.animationName
        };
    });
    assert(parseFloat(inspectOwnerVisual.outlineWidth) >= 2
            && inspectOwnerVisual.outlineStyle === 'solid'
            && inspectOwnerVisual.animationName.includes('panel-tooltip-owner-inspect-enter'),
        'inspect owner confirmation is not visually distinct', inspectOwnerVisual);
    assert(state.descScrollbar
            && state.descScrollbar.thumbBackground !== pendingScrollbar.thumbBackground,
        'dense scrollbar did not change from pending to inspect state', {
            pending:pendingScrollbar,
            inspect:state.descScrollbar
        });
    record('default-1s-inspection', {state:state.state,animationName,inspectOwnerVisual});
    record('inspection-status-layout', {
        contentRect:state.contentRect,statusRect:state.inspectionStatusRect,
        position:state.inspectionStatusPosition,background:state.inspectionStatusBackgroundImage
    });
    record('dense-scrollbar-skin', {pending:pendingScrollbar,inspect:state.descScrollbar});

    const beforeWheel = state;
    await page.mouse.wheel(0, 220);
    await page.waitForTimeout(50);
    state = await snapshot(page);
    assert(state.descScrollTop > beforeWheel.descScrollTop, 'owner wheel did not scroll tooltip description', {beforeWheel,state});
    assert(state.hostScrollTop === beforeWheel.hostScrollTop, 'owner wheel leaked to host scroll region', {beforeWheel,state});
    await page.evaluate(() => {
        const desc = document.querySelector('#panel-tooltip .flash-tt-desc,#panel-tooltip .kshop-tt-desc');
        if (desc) desc.scrollTop = desc.scrollHeight;
    });
    const boundaryBefore = await snapshot(page);
    await page.mouse.wheel(0, 420);
    await page.waitForTimeout(50);
    const boundaryAfter = await snapshot(page);
    assert(boundaryAfter.hostScrollTop === boundaryBefore.hostScrollTop,
        'wheel leaked to host at tooltip scroll boundary', {boundaryBefore,boundaryAfter});
    record('wheel-ownership-and-boundary', {beforeWheel,state,boundaryBefore,boundaryAfter});

    // 指针路径的 Esc 只退出检视回到 scan：浮层继续跟随指针，且不得冒泡给面板层
    await page.keyboard.press('Escape');
    await page.waitForTimeout(30);
    state = await snapshot(page);
    assert(state.state.inspectionState === 'scan' && state.ownerStates[0] === '',
        'pointer Escape did not exit dense inspection back to scan', state);
    assert(state.tooltipRect && state.tooltipRect.width > 0 && state.text.includes('tile-0'),
        'pointer Escape dismissed the hover tooltip instead of just the inspection', state);
    record('pointer-escape-exits-inspection', state.state);

    await reset(page, {inspectionDelay:180,longContent:false});
    await moveToTile(page, 0, {wait:260});
    state = await snapshot(page);
    assert(state.state.inspectionState === 'scan' && state.ownerStates[0] === '',
        'short tooltip entered a meaningless inspect state', state);
    record('short-content-stays-scan', state.state);

    await reset(page, {inspectionDelay:1000,longContent:true,richDelay:600});
    await moveToTile(page, 0, {wait:450});
    const basicState = await snapshot(page);
    assert(basicState.state.inspectionState === 'scan', 'basic placeholder started empty progress', basicState);
    await page.waitForTimeout(230);
    const richPending = await snapshot(page);
    assert(richPending.state.inspectionState === 'pending', 'late rich content did not resume remaining dwell', richPending);
    await page.waitForTimeout(390);
    const richInspect = await snapshot(page);
    assert(richInspect.state.inspectionState === 'inspect', 'late rich content restarted a full extra dwell', richInspect);
    record('basic-to-rich-dwell-continuity', {basic:basicState.state,pending:richPending.state,inspect:richInspect.state});

    await reset(page, {inspectionDelay:320,longContent:true});
    await moveToTile(page, 0, {wait:180});
    const ownerA = await snapshot(page);
    await moveToTile(page, 1, {wait:30});
    const ownerB = await snapshot(page);
    assert(ownerB.text.includes('tile-1'), 'new owner did not preempt old owner immediately', {ownerA,ownerB});
    assert(ownerB.ownerStates[0] === '' && ownerB.ownerStates[1] === 'pending',
        'old owner inspection projection survived preemption', {ownerA,ownerB});
    await page.waitForTimeout(170);
    const oldDeadline = await snapshot(page);
    assert(oldDeadline.state.inspectionState !== 'inspect', 'old owner timer activated inspection on new owner', oldDeadline);
    await page.waitForTimeout(170);
    const newDeadline = await snapshot(page);
    assert(newDeadline.state.inspectionState === 'inspect', 'new owner did not get its own full dwell', newDeadline);
    record('new-owner-preemption', {ownerA:ownerA.state,ownerB:ownerB.state,oldDeadline:oldDeadline.state,newDeadline:newDeadline.state});

    await reset(page, {inspectionDelay:300,longContent:true});
    const motionCenter = await moveToTile(page, 0, {wait:180});
    await page.mouse.move(motionCenter.x + 26, motionCenter.y, {steps:1});
    await page.waitForTimeout(165);
    const motionPending = await snapshot(page);
    assert(motionPending.state.inspectionState === 'pending',
        'fast in-owner motion did not reset inspection dwell', motionPending);
    await page.waitForTimeout(155);
    const motionSettled = await snapshot(page);
    assert(motionSettled.state.inspectionState === 'inspect',
        'inspection did not resume after fast motion settled', motionSettled);
    record('fast-motion-resets-dwell', {pending:motionPending.state,settled:motionSettled.state});

    const trajectories = [];
    trajectories.push(await trajectory(page, 'horizontal-fast', [0,1,2,3,4], 8));
    trajectories.push(await trajectory(page, 'horizontal-slow', [0,1,2,3,4], 95));
    // 轨迹只取滚动容器当前可见的三行；越过 clipping edge 测到的是宿主而非 tile。
    trajectories.push(await trajectory(page, 'vertical-fast', [0,5,10], 8));
    trajectories.push(await trajectory(page, 'vertical-slow', [0,5,10], 95));
    trajectories.push(await trajectory(page, 'diagonal-fast', [0,6,12], 8));
    trajectories.push(await trajectory(page, 'diagonal-slow', [0,6,12], 95));
    record('physical-pointer-trajectories', trajectories);

    await reset(page, {inspectionDelay:200,longContent:true});
    let pinned = await page.evaluate(() => window.__tooltipHarness.openPinned(7));
    assert(pinned.state.pinned && pinned.state.profile === 'pinned-inspector', 'pinned inspector did not open', pinned);
    assert(pinned.tooltipPointerEvents === 'auto', 'pinned inspector is not independently interactive', pinned);
    assert(pinned.inspectorScrollbar && pinned.inspectorScrollbar.width === '7px'
            && pinned.inspectorScrollbar.buttonDisplay === 'none'
            && pinned.inspectorScrollbar.buttonWidth === '0px'
            && pinned.inspectorScrollbar.gutterWidth === 7,
        'pinned inspector scrollbar is not an interactive 7px skin', pinned.inspectorScrollbar);
    record('pinned-scrollbar-skin', pinned.inspectorScrollbar);
    const pinnedChrome = await page.evaluate(() => {
        const title = document.querySelector('.panel-tooltip-inspector-title');
        const hint = document.querySelector('.panel-tooltip-inspector-keycap');
        const body = document.querySelector('.panel-tooltip-inspector-body');
        const desc = document.querySelector('#panel-tooltip .flash-tt-desc, #panel-tooltip .kshop-tt-desc');
        return {
            title:title ? title.textContent : null,
            hint:hint ? hint.textContent : null,
            bodyWidth:body ? body.clientWidth : 0,
            descWidth:desc ? desc.getBoundingClientRect().width : 0
        };
    });
    assert(pinnedChrome.title === '物品检视', 'pinned inspector default title missing', pinnedChrome);
    assert(pinnedChrome.hint === 'Esc', 'pinned inspector Esc hint chip missing', pinnedChrome);
    assert(pinnedChrome.descWidth >= pinnedChrome.bodyWidth - 12,
        'pinned description no longer fills the inspector shell', pinnedChrome);
    record('pinned-chrome-and-layout', pinnedChrome);
    const pinnedText = pinned.text;
    await moveToTile(page, 2, {wait:80});
    const afterHover = await snapshot(page);
    assert(afterHover.state.pinned && afterHover.text === pinnedText,
        'scan hover overwrote explicit pinned inspector', {pinned,afterHover});
    const tipRect = afterHover.tooltipRect;
    await page.mouse.move(tipRect.left + tipRect.width / 2, tipRect.top + tipRect.height - 24);
    await page.mouse.wheel(0, 180);
    await page.waitForTimeout(50);
    const pinnedScrolled = await snapshot(page);
    assert(pinnedScrolled.descScrollTop > 0 || pinnedScrolled.inspectorBodyScrollTop > 0,
        'pinned inspector did not scroll independently', pinnedScrolled);
    await page.click('.panel-tooltip-inspector-close');
    let closed = await snapshot(page);
    assert(!closed.state.pinned && !closed.state.pointerOwnerActive && !closed.state.keyboardOwnerActive,
        'close button did not terminate pinned ownership', closed);
    await page.evaluate(() => window.__tooltipHarness.openPinned(8));
    await page.keyboard.press('Escape');
    closed = await snapshot(page);
    assert(!closed.state.pinned, 'Escape did not close pinned inspector', closed);
    await page.evaluate(() => window.__tooltipHarness.openPinned(9));
    await page.click('body', {position:{x:4,y:4}});
    await page.waitForTimeout(30);
    closed = await snapshot(page);
    assert(!closed.state.pinned, 'outside click did not close pinned inspector', closed);
    record('pinned-inspector-lifecycle', {afterHover:afterHover.state,pinnedScrolled:pinnedScrolled.state,closed:closed.state});

    await reset(page, {inspectionDelay:1000,longContent:true});
    await page.mouse.move(900, 500);
    await page.evaluate(() => document.body.focus());
    await page.keyboard.press('Tab');
    await page.waitForTimeout(60);
    const keyboardOpen = await snapshot(page);
    assert(keyboardOpen.state.inspectionState === 'inspect', 'keyboard focus did not enter readable inspection immediately', keyboardOpen);
    await page.keyboard.press('PageDown');
    const keyboardScrolled = await snapshot(page);
    assert(keyboardScrolled.descScrollTop > keyboardOpen.descScrollTop, 'PageDown did not scroll description', {keyboardOpen,keyboardScrolled});
    await page.keyboard.press('Escape');
    const keyboardClosed = await snapshot(page);
    assert(!keyboardClosed.state.pointerOwnerActive && !keyboardClosed.state.keyboardOwnerActive,
        'keyboard Escape did not release tooltip owners', keyboardClosed);
    record('keyboard-inspection', {open:keyboardOpen.state,closed:keyboardClosed.state});

    await reset(page, {profile:'simple-tooltip',longContent:false});
    const simple = await page.evaluate(() => window.__tooltipHarness.showSimple());
    assert(simple.state.profile === 'simple-tooltip' && simple.tooltipPointerEvents === 'auto',
        'simple tooltip profile regressed', simple);
    const beforeDispose = await snapshot(page);
    await page.evaluate(() => window.__tooltipHarness.disposeScope());
    const afterDispose = await snapshot(page);
    assert(afterDispose.state.bindingCount === 0 && afterDispose.state.activeScopeCount === 0,
        'scope disposal left tooltip bindings behind', {beforeDispose,afterDispose});
    record('simple-profile-and-scope-disposal', {simple:simple.state,afterDispose:afterDispose.state});

    return {passed:checks.length,total:checks.length,checks};
}

async function run() {
    const staticResult = staticAudit();
    const executablePath = edgePath();
    assert(executablePath, 'Microsoft Edge executable not found');
    const server = await startServer(LAUNCHER);
    const browser = await chromium.launch({executablePath,headless:true});
    const page = await browser.newPage({viewport:{width:1366,height:768}});
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(String(error && error.stack || error)));
    try {
        await page.goto(server.url + 'perf/tooltip-interaction/fixture.html', {waitUntil:'load'});
        await page.waitForFunction(() => window.__tooltipHarnessReady === true);
        const browserResult = await runBrowserAudit(page);
        assert(pageErrors.length === 0, 'browser page errors', pageErrors);
        return {browser:'edge',executablePath,static:staticResult,browserResult,pageErrors};
    } finally {
        await browser.close();
        await stopServer(server);
    }
}

if (require.main === module) {
    run().then(result => {
        process.stdout.write(JSON.stringify(result, null, 2) + '\n');
    }).catch(error => {
        console.error(error && error.stack || String(error));
        if (error && error.evidence) console.error(JSON.stringify(error.evidence, null, 2));
        process.exitCode = 1;
    });
}

module.exports = {run,staticAudit};
