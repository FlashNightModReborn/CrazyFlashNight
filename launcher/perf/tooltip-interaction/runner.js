#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {chromium} = require('playwright');
const {startServer, stopServer} = require('../lib/server.js');
const {currentSamples, runReading} = require('./reading');

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
        [source.includes('var TT_DEFAULT_W = 280, TT_MAX_W = 420'), 'readable description width tiers missing'],
        [source.includes('var TT_EXPAND_SCORE = 900, TT_EXPAND_LINES = 18'), 'description expansion thresholds missing'],
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
    await page.evaluate(() => PanelTooltip.setLayoutPreset('legacy339'));
    const checks = [];
    const record = (name, evidence) => checks.push({name,pass:true,evidence});

    const mediumWidth = await page.evaluate(() => window.__tooltipHarness.showRich({
        introHTML:'<B>中等长度</B>',
        descHTML:'字'.repeat(200)
    }));
    assert(mediumWidth.descWidth > 0 && mediumWidth.descWidth <= 280,
        'medium description must stay within the narrow reading width', mediumWidth);
    const wrappedWidth = await page.evaluate(() => window.__tooltipHarness.showRich({
        introHTML:'<B>折行拓宽</B>',
        descHTML:'字'.repeat(450)
    }));
    assert(Math.abs(wrappedWidth.descWidth - 420) <= 1,
        'description over 18 rendered lines must expand to the wide tier', wrappedWidth);
    const logicalLinesWidth = await page.evaluate(() => window.__tooltipHarness.showRich({
        introHTML:'<B>多段拓宽</B>',
        descHTML:Array(19).fill('短行内容内容内容内容内容').join('<BR>')
    }));
    assert(Math.abs(logicalLinesWidth.descWidth - 420) <= 1,
        'description over 18 logical lines must expand to the wide tier', logicalLinesWidth);
    const g11Width = await page.evaluate(() => window.__tooltipHarness.showRich({
        introHTML:'<B>G11</B><BR>长枪 / 突击步枪',
        descHTML:'H&K G11是GER国研发的革命性无壳弹药突击步枪，采用独特的4.73×33mm无壳弹药和创新的旋转枪机结构，极大减轻了枪械整体重量，并实现了枪身的高度紧凑化设计。其标志性的超高速三点射模式，可达到瞬时2000发每分钟的射速，使三发子弹在射手尚未感受到明显后坐力之前便已连续射出，形成紧密着弹的弹道，显著提升中远程精确命中率，将狙击枪的精度与自动武器的压制火力完美融合。虽因政治因素未能量产，但G11无疑代表了步枪技术的巅峰成就。<BR><BR>【升阶路线】<BR>可升：G111'
    }));
    assert(g11Width.descWidth > 0 && g11Width.descWidth <= 280,
        'G11 description must stay within the narrow reading width', g11Width);
    const subPanelWidths = await page.evaluate(() => window.__tooltipHarness.showDocument({
        version:1,
        title:'G11',
        profile:'dense',
        sections:[
            {role:'intro',runs:[{text:'长枪 / 突击步枪'}]},
            {role:'description',runs:[{text:'字'.repeat(200)}]},
            {role:'sub',runs:[{text:'【主动战技】激发浮动枪机与旋转膛室的极限性能，以2000发每分钟的瞬时射速连续打出三发高速无壳穿甲弹，造成致命伤害。'}]},
            {role:'sub',kind:'attachments',title:'已安装2个配件',rows:[
                {name:'战术鱼骨零件',depth:1,runs:[{text:'导轨基座'}]},
                {name:'透镜',depth:1,runs:[{text:'瞄具'}]}
            ]},
            {role:'sub',kind:'acquisition',title:'获取方式',rows:[
                {name:'NPC商店'},
                {name:'Boy',depth:1}
            ]}
        ]
    }));
    assert(subPanelWidths.subWidths.length === 3,
        'skill, attachments and acquisition fixtures must all render', subPanelWidths);
    for (const width of subPanelWidths.subWidths) {
        assert(width === subPanelWidths.descWidth && width <= 280,
            'every sub panel must share the narrow description width', subPanelWidths);
    }
    record('readable-width-tiers', {
        medium:mediumWidth.descWidth,
        g11:g11Width.descWidth,
        wrapped:wrappedWidth.descWidth,
        logicalLines:logicalLinesWidth.descWidth,
        subPanels:subPanelWidths.subWidths
    });

    await page.evaluate(() => document.documentElement.style.setProperty('--cf7-overlay-scale', String(5 / 6)));
    await reset(page, {inspectionDelay:1000,longContent:true,fractionalGeometry:true});
    await moveToTile(page, 0, {wait:40});
    const leftPixelPhase = await snapshot(page);
    assert(leftPixelPhase.tooltipFontSize === 12 && leftPixelPhase.tooltipTransform === 'none',
        'tooltip text must render natively without transform resampling', leftPixelPhase);
    assert(Math.abs(leftPixelPhase.descWidth - 350) <= 1,
        'description width must use the same overlay scale as the layout', leftPixelPhase);
    assert(Math.abs(leftPixelPhase.tooltipPixelPhase.x) < 0.01
            && Math.abs(leftPixelPhase.tooltipPixelPhase.y) < 0.01,
        'left-side item tooltip origin must land on device pixels', leftPixelPhase);
    await moveToTile(page, 4, {wait:40});
    const rightPixelPhase = await snapshot(page);
    assert(Math.abs(rightPixelPhase.tooltipPixelPhase.x) < 0.01
            && Math.abs(rightPixelPhase.tooltipPixelPhase.y) < 0.01,
        'right-side item tooltip origin must land on device pixels', rightPixelPhase);
    record('device-pixel-aligned-placement', {
        left:leftPixelPhase.tooltipPixelPhase,
        right:rightPixelPhase.tooltipPixelPhase,
        physicalFontSize:leftPixelPhase.tooltipFontSize,
        descriptionWidth:leftPixelPhase.descWidth
    });

    await page.evaluate(() => document.documentElement.style.removeProperty('--cf7-overlay-scale'));
    await page.evaluate(() => PanelTooltip.setLayoutPreset('tier14'));
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

function layoutSnapshot() {
    const el = PanelTooltip.getElement();
    const rich = el.querySelector('.flash-tt-rich');
    const side = el.querySelector('.flash-tt-side');
    const intro = el.querySelector('.flash-tt-intro-panel');
    const rail = el.querySelector('.flash-tt-rail');
    const icon = el.querySelector('.flash-tt-icon');
    const viewports = [...el.querySelectorAll('[data-tooltip-reading-viewport]')];
    const viewport = viewports[0];
    const panels = [...el.querySelectorAll('.flash-tt-intro-panel,.flash-tt-desc,.flash-tt-sub-panel,.flash-tt-suffix')];
    const columns = [...el.querySelectorAll('.flash-tt-side-col')];
    const scrollers = [...el.querySelectorAll('*')].filter(node =>
        /^(auto|scroll)$/.test(getComputedStyle(node).overflowY) && node.scrollHeight > node.clientHeight + 1);
    const shell = el.getBoundingClientRect();
    const bounds = viewport && viewport.getBoundingClientRect();
    const state = PanelTooltip.debugState();
    const inset = el.dataset.layoutPreset === 'legacy339' || state.pinned ? 7.5 : 8 - 1 / 64;
    const offset = viewport ? viewport.scrollTop : 0;
    const max = viewport ? viewport.scrollHeight - viewport.clientHeight : 0;
    const tails = panels.map(panel => {
        const walker = document.createTreeWalker(panel, NodeFilter.SHOW_TEXT);
        let last = null;
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
            if (node.textContent.trim()) last = node;
        }
        if (!last) return {seen:true};
        const range = document.createRange();
        const end = last.textContent.trimEnd().length;
        range.setStart(last, end - 1);
        range.setEnd(last, end);
        return {range, clip:viewport && viewport.contains(last) ? bounds : shell, seen:false};
    });
    function visitTails() {
        for (const tail of tails) {
            if (tail.seen) continue;
            const box = tail.range.getBoundingClientRect();
            tail.seen = box.height > 0 && box.top >= tail.clip.top - 1 && box.bottom <= tail.clip.bottom + 1
                && box.left >= tail.clip.left - 1 && box.right <= tail.clip.right + 1;
        }
    }
    if (viewport) {
        const step = Math.max(1, Math.floor(viewport.clientHeight * 0.65));
        for (let top = 0; top < max; top += step) {
            viewport.scrollTop = top;
            visitTails();
        }
        viewport.scrollTop = max;
    }
    visitTails();
    const bottom = viewport ? viewport.scrollTop : 0;
    if (viewport) viewport.scrollTop = offset;
    const introLines = [...el.querySelectorAll('.flash-tt-intro-line')].map(node => ({
        text:node.textContent, full:node.classList.contains('flash-tt-intro-line--full'),
        top:node.offsetTop, left:node.offsetLeft
    }));
    const rowGroups = [...el.querySelectorAll('.flash-tt-attach-rows')].map(group => ({
        kind:group.dataset.rowKind, packed:group.classList.contains('flash-tt-attach-rows--2col'),
        gap:getComputedStyle(group).rowGap,
        rows:[...group.children].map(row => ({
            full:row.classList.contains('flash-tt-attach-row--full'),
            top:row.offsetTop, left:row.offsetLeft,
            effect:row.querySelector('.flash-tt-attach-effect')
                ? getComputedStyle(row.querySelector('.flash-tt-attach-effect')).display : null
        }))
    }));
    return {
        preset:el.dataset.layoutPreset, state, pointer:getComputedStyle(el).pointerEvents,
        width:side ? side.offsetWidth : 0, introWidth:intro ? intro.offsetWidth : 0,
        iconWidth:icon ? icon.firstElementChild.getBoundingClientRect().width : 0,
        introText:intro ? intro.textContent : '', text:rich ? rich.textContent : el.textContent,
        introLines, rowGroups,
        columnLeft:columns.map(col => col.getBoundingClientRect().left),
        columnCounts:columns.map(col => col.children.length),
        introLeft:intro && intro.getBoundingClientRect().left, railLeft:rail && rail.getBoundingClientRect().left,
        stacked:!!(rich && rich.classList.contains('flash-tt-rich--stacked')),
        scrollBox:viewport && viewport.className, viewportCount:viewports.length,
        nested:scrollers.filter(node => node !== viewport).length,
        height:viewport && viewport.clientHeight, max, bottom,
        unseen:tails.flatMap((tail, i) => tail.seen ? [] : [panels[i].textContent.slice(-26)]),
        inside:shell.left >= inset && shell.top >= inset
            && shell.right <= innerWidth - inset && shell.bottom <= innerHeight - inset
    };
}

async function runLayoutAudit(page) {
    const keys = ['wholeSideWidth','noSubOneWidthShrink','unclampSingleSideHeight',
        'balanceWidth','compactRows','compactIntro','twoColumnSide'];
    const presets = {legacy339:0,tier12:4,tier13:6,tier14:7};
    const section = (role, text) => ({role,runs:[{text}]});
    const lines = (prefix, count) => Array.from({length:count}, (_, i) => prefix + (i + 1)).join('\n');
    const child = name => ({name,depth:1});
    const effect = text => ({depth:1,runs:[{text}]});
    const doc = (title, sections, extra = {}) => ({version:1, title, profile:'dense', layoutType:'wide', sections, ...extra});
    const read = () => page.evaluate(layoutSnapshot);
    const preset = name => page.evaluate(name => PanelTooltip.setLayoutPreset(name), name);
    async function viewport(width, height) {
        await page.setViewportSize({width,height});
        await page.evaluate(() => {
            document.documentElement.style.setProperty('--cf7-overlay-scale', String(innerHeight / 864));
            window.dispatchEvent(new Event('resize'));
        });
    }
    async function show(document, options = {}) {
        await page.evaluate(({document,options}) => window.__tooltipHarness.showDocument(document, options), {document,options});
        return read();
    }
    function assertReading(snapshot, target) {
        assert(snapshot.state.readingTarget === target && snapshot.viewportCount === 1
            && snapshot.nested === 0 && snapshot.inside && snapshot.unseen.length === 0
            && Math.abs(snapshot.max - snapshot.bottom) <= 1,
        'single closed reading viewport with every panel tail reachable', snapshot);
    }
    const defaults = await page.evaluate(() => PanelTooltip.getLayoutOptions());
    assert(keys.every(key => defaults[key] === true), 'production defaults to tier14', defaults);
    const samples = currentSamples().filter(sample => ['战术手电','三蝶手稿'].includes(sample.id));
    const sampleWidths = [];
    for (const [w,h] of [[1024,576],[1067,600]]) {
        await viewport(w,h);
        for (const sample of samples) {
            await preset('legacy339');
            const legacy = await show(sample.document);
            await preset('tier12');
            const next = await read();
            assert(next.width >= 200 && next.width > legacy.width && next.text === legacy.text,
                sample.id + ' side width and full text', {legacy,next});
            assertReading(next, 'side');
            sampleWidths.push({id:sample.id,viewport:[w,h],legacy:legacy.width,tier12:next.width});
        }
    }

    await viewport(1024, 576);
    const single = doc('单框', [section('intro','短内容'),section('description',lines('短句',32))]);
    const split = {chrome:{splitMode:'split'}};
    await preset('legacy339');
    const clamped = await show(single, split);
    await preset('tier12');
    const unclamped = await read();
    assert(clamped.max > 0 && clamped.height <= 576 * .7 && unclamped.max === 0,
        'single side can use the full height budget', {clamped,unclamped});
    assert(unclamped.width === 280, 'short logical lines stay at the default width', unclamped);
    assertReading(unclamped, 'side');
    const subOnly = await show(doc('纯子框', [section('intro','简介'),section('sub','短子框')]));
    assert(subOnly.width === 200, 'sub-only side preserves the readable width floor', subOnly);
    const balanced = await show(doc('二分扩宽', [
        section('intro','压缩验证'), section('description','字'.repeat(1200))
    ]), {chrome:{splitMode:'split'}, point:{clientX:40, clientY:180}});
    assert(balanced.width > 420 && balanced.width < 560 && balanced.max === 0,
        'Mode A chooses an intermediate width that fits the height budget', balanced);
    const belowBalance = await page.$eval('.flash-tt-side', side => {
        const width = side.style.width;
        side.style.width = (side.offsetWidth - 16) + 'px';
        const overflows = side.scrollHeight > side.clientHeight;
        side.style.width = width;
        return overflows;
    });
    assert(belowBalance, 'Mode A converges within 16 px of a width that overflows', balanced);
    assertReading(balanced, 'side');
    const acquisition = await show(doc('来源估宽', [
        section('intro','简介'),
        {role:'sub',kind:'acquisition',title:'商店',rows:[child('W'.repeat(38))]}
    ]), {point:{clientX:40, clientY:180}});
    const acquisitionFits = await page.$eval('.flash-tt-attach-name', node => {
        return node.offsetHeight <= parseFloat(getComputedStyle(node).lineHeight) + 1;
    });
    assert(acquisition.width > 420 && acquisition.width <= 560 && acquisitionFits,
        'acquisition can use the wider tier to fit its longest unbroken row', acquisition);

    // 锚点感知无碰撞宽度预算（W_clear）：中段悬停大注释不得撑破两翼走廊导致 clamp 盖回鼠标/当前格
    const midArmorDoc = doc('中段防具避让', [
        section('intro', '防具 下装装备\n$200000\n强化等级：13 (+204%)\n等级限制：45\n重量：12kg\n防御：1520'),
        section('description', '【五件套组件】' + '高功率机动组件与承力框架说明文案。'.repeat(28)),
        {role:'sub', kind:'acquisition', title:'获取方式', rows:[
            {name:'合成'}, child('书中配给 ($100000 + 9000K)'), {name:'K点商城'}, child('A兵团官方周边直营店(6000K)')
        ]}
    ]);
    const midRailGunDoc = doc('中段带书签霰弹枪', [
        section('intro', '$163800\n等级限制：21\n重量：8.5kg\n弹夹容量：8\n射速：4发/秒'),
        section('description', '第一防线留下的封闭改装方案。'.repeat(16)),
        section('sub', lines('【主动战技】将霰弹枪展开为枪盾冲撞推进，期间获得减伤与抗打断。', 12)),
        {role:'sub', kind:'acquisition', title:'获取方式', rows:[{name:'合成'}, child('铁枪会 ($1000)')]}
    ], {rail:['长枪','霰弹枪']});
    await preset('tier14');
    const midCheck = await page.evaluate(({midArmorDoc, midRailGunDoc}) => {
        function makeSlot(left, top, width, height) {
            var el = document.createElement('button');
            el.type = 'button';
            el.style.cssText = 'position:fixed;margin:0;padding:0;border:0;left:' + left + 'px;top:' + top
                + 'px;width:' + width + 'px;height:' + height + 'px;z-index:1;';
            document.body.appendChild(el);
            return el;
        }
        var armorSlot = makeSlot(460, 200, 55, 54);
        var bagSlot = makeSlot(595, 210, 50, 50);
        try {
            var armorHtml = PanelTooltip.buildItemRichHtml({document:midArmorDoc, layoutType:'wide'});
            PanelTooltip.showAtMouse(armorHtml, {
                clientX:488, clientY:227, target:armorSlot, currentTarget:armorSlot
            }, null, {profile:'dense-inspect', placement:'left'});
            var armorState = PanelTooltip.debugState();
            var armorRect = PanelTooltip.getElement().getBoundingClientRect();

            var gunHtml = PanelTooltip.buildItemRichHtml({document:midRailGunDoc, layoutType:'wide'});
            PanelTooltip.showAtMouse(gunHtml, {
                clientX:620, clientY:235, target:bagSlot, currentTarget:bagSlot
            }, null, {profile:'dense-inspect', placement:'left'});
            var gunState = PanelTooltip.debugState();
            var gunRect = PanelTooltip.getElement().getBoundingClientRect();

            // 模拟异步 basic → rich updateContent 刷新：先小占位锁左，再换完整文档应自动避让右侧不盖鼠标
            var asyncOwner = {};
            PanelTooltip.showAtMouse('<div class="kshop-tt-header"><b>加载中</b></div>', {
                clientX:488, clientY:227, target:armorSlot, currentTarget:armorSlot
            }, asyncOwner, {profile:'dense-inspect', placement:'left'});
            PanelTooltip.updateContentDocument(midArmorDoc, asyncOwner, {layoutType:'wide'});
            var asyncState = PanelTooltip.debugState();
            var asyncRect = PanelTooltip.getElement().getBoundingClientRect();

            return {
                armor:{state:armorState, width:armorRect.width, left:armorRect.left, right:armorRect.right},
                gun:{state:gunState, width:gunRect.width, left:gunRect.left, right:gunRect.right},
                async:{state:asyncState, width:asyncRect.width, left:asyncRect.left, right:asyncRect.right}
            };
        } finally {
            armorSlot.remove();
            bagSlot.remove();
        }
    }, {midArmorDoc, midRailGunDoc});
    assert(midCheck.armor.state.lastPlacement.pointerOverlap === 0
        && midCheck.armor.state.lastPlacement.anchorOverlap === 0
        && midCheck.armor.state.lastPlacement.insideViewport
        && midCheck.armor.state.lastPlacement.placement === 'right'
        && midCheck.armor.width <= 491.5 && midCheck.armor.state.sideColumns === 1,
    'mid-screen armor slot shrinks to right W_clear corridor with zero pointer/anchor overlap', midCheck.armor);
    assert(midCheck.gun.state.lastPlacement.pointerOverlap === 0
        && midCheck.gun.state.lastPlacement.anchorOverlap === 0
        && midCheck.gun.state.lastPlacement.insideViewport
        && midCheck.gun.state.lastPlacement.placement === 'left'
        && midCheck.gun.width <= 577.5,
    'mid-screen rail gun backpack slot shrinks to left W_clear corridor with zero pointer/anchor overlap', midCheck.gun);
    assert(midCheck.async.state.lastPlacement.pointerOverlap === 0
        && midCheck.async.state.lastPlacement.anchorOverlap === 0
        && midCheck.async.state.lastPlacement.insideViewport
        && midCheck.async.state.lastPlacement.placement === 'right',
    'async basic-to-rich updateContent preserves zero pointer/anchor overlap', midCheck.async);

    await viewport(1280, 600);
    const subject = doc('满改多子框', [
        section('intro','等级：40\n重量:8kg\n固有结构：加长导轨\n威力：50\n射速：3.7\n$460000\n命中：20%\n禁止挂点：枪口'),
        {role:'description',kind:'upgrades',title:'升阶路线',rows:[
            {name:'升自'},child('元件甲'),child('元件乙'),child('元件丙'),child('很长材料'.repeat(12)),child('升阶尾行')
        ],runs:[{text:'回退内容不可双显'}]},
        {role:'sub',kind:'attachments',title:'已安装配件',rows:[
            {name:'灯具',runs:[{text:'短效果'}]}, {name:'镜头',runs:[{text:'多行效果\n配件尾行'}]}
        ]},
        {role:'sub',kind:'modinfo',title:'配件信息',rows:[
            {name:'属性'},effect('威力 +5'),effect('重量 -2'),effect('落单一'),
            {name:'说明'},effect('长行描述'.repeat(15)),effect('短行一\n短行二'),effect('插件信息尾行')
        ]},
        section('sub',lines('战技效果 ',44)),
        {role:'sub',kind:'acquisition',title:'获取方式',rows:[
            {name:'商店'}, child('市集'), child('工坊'), child('很长来源'.repeat(12)), child('来源尾行')
        ]},
        section('sub',lines('安装限制 ',43))
    ], {rail:['长枪','狙击步枪'],magazine:{name:'专用弹夹',ammo:'穿甲弹'}});
    const chrome = {splitMode:'split', iconPlaceholder:'<div class="flash-tt-icon-placeholder"></div>',
        iconFootHTML:'图标尾注', suffix:'底条尾行'};
    const options = {chrome,point:{clientX:1260,clientY:220},placement:'left'};
    await preset('tier14');
    const tied = await show(doc('三块等高', [
        section('intro','简介'), ...['甲','乙','丙'].map(name => section('sub',lines(name,26)))
    ]));
    assert(tied.state.sideColumns === 2 && tied.columnCounts.join() === '2,1',
        'an equal-height cut keeps the heavier column on the left', tied);
    const noGain = await show(doc('双列收益不足', [
        section('intro','简介'),section('sub','字'.repeat(3200)),section('sub','很短')
    ]));
    assert(noGain.state.sideColumns === 1 && noGain.max > 0, 'an unbalanced split must retain one column', noGain);
    assertReading(noGain, 'side');
    const wide = await show(subject, options);
    assertReading(wide, 'side');
    assert(wide.state.sideColumns === 2 && wide.max > 0 && wide.pointer === 'none'
        && wide.state.lastPlacement.placement === 'left'
        && wide.columnLeft[0] < wide.columnLeft[1] && wide.columnLeft[1] < wide.introLeft
        && wide.introLeft < wide.railLeft,
    'full mod overflow has one two-column viewport and retains left-mirror reading order', wide);
    assert(wide.introLines.length === 8 && wide.introLines.map(line => line.full).join() === 'false,false,true,false,false,true,true,true'
        && wide.introLines[0].top === wide.introLines[1].top && wide.introLines[0].left < wide.introLines[1].left,
    'intro only pairs consecutive short attributes', wide.introLines);
    const rowMasks = {
        upgrades:'true,false,false,true,true,true',
        modinfo:'true,false,false,true,true,true,true,true',
        acquisition:'true,false,false,true,true'
    };
    for (const group of wide.rowGroups.filter(group => group.kind !== 'attachments')) {
        assert(group.packed && group.rows.map(row => row.full).join() === rowMasks[group.kind]
            && group.rows[1].top === group.rows[2].top && group.rows[1].left < group.rows[2].left,
        'structured rows pair only when both consecutive children fit', group);
    }
    assert(wide.rowGroups.find(group => group.kind === 'attachments').rows.map(row => row.effect).join() === 'inline,block',
        'single-line attachment effect flows inline and multiline stays block', wide.rowGroups);
    assert(!wide.text.includes('回退内容不可双显') && wide.text.includes('专用弹夹') && wide.text.includes('图标尾注'),
        'chrome and structured body stay complete without fallback duplication', wide.text);

    const modHierarchy = await show(doc('配件层级', [
        section('intro', '等级：40'),
        section('description', lines('用于撑开侧框宽度以触发双列子行打包的常规描述文案，确保净宽超过双列门槛。', 4)),
        {role:'sub', kind:'modinfo', title:'配件信息', rows:[
            {name:'【基础效果】'}, effect('威力 +5'), effect('重量 -2'),
            effect('【按装备类型追加效果】'), effect('对 装备类型：长枪：'),
            effect('  切手技重量系数 → 5'), effect('  切手技冲击力 ×5'),
            effect('  【技能效果】'), effect('  灰蛊蚀刻'),
            effect('    18格，每格易伤+1%'), effect('    持续5秒')
        ]}
    ]), split);
    const modGroup = modHierarchy.rowGroups.find(group => group.kind === 'modinfo');
    assert(modGroup && modGroup.packed
        && modGroup.rows.map(row => row.full).join() === 'true,false,false,true,true,false,false,true,true,false,false'
        && modGroup.rows[1].top === modGroup.rows[2].top && modGroup.rows[1].left < modGroup.rows[2].left
        && modGroup.rows[5].top === modGroup.rows[6].top && modGroup.rows[5].left < modGroup.rows[6].left
        && modGroup.rows[9].top === modGroup.rows[10].top && modGroup.rows[9].left < modGroup.rows[10].left,
    'modinfo keeps headings, colon branches, and parent rows full width while pairing same-indent siblings', modGroup);
    // Restore subject so subsequent preset-switch assertions verify against `wide`.
    await show(subject, options);

    for (const name of Object.keys(presets).concat('tier14','tier13','tier14')) {
        await preset(name);
        const next = await read();
        assert(next.preset === name && keys.every((key,i) => next.state.layoutOptions[key] === (i < presets[name])),
            'preset flags round trip', next.state);
        assert(next.introText === wide.introText && next.text === wide.text
            && next.state.sideColumns === (name === 'tier14' ? 2 : 1)
            && next.columnCounts.join() === (name === 'tier14' ? wide.columnCounts.join() : '')
            && (name === 'tier14' || name === 'tier13' ? next.introLines.length === 8 : next.introLines.length === 0),
        'preset switching restores DOM and then recomputes layout', next);
        assertReading(next, 'side');
    }
    const legacyAt600 = await (async () => { await preset('legacy339'); return read(); })();
    assert(Math.abs(wide.iconWidth - 144 * 600 / 864) <= 1
        && Math.abs(legacyAt600.iconWidth - 192 * 600 / 864) <= 1 && wide.introWidth > legacyAt600.introWidth,
    'short viewport shrinks the wide icon with no text-width shrink', {wide,legacyAt600});
    await preset('tier14');
    await page.evaluate(() => {
        const copy = PanelTooltip.getLayoutOptions();
        copy.compactRows = false;
        if (!PanelTooltip.getLayoutOptions().compactRows || PanelTooltip.setLayoutPreset('invalid')) throw Error('layout API');
        PanelTooltip.setLayoutOptions({twoColumnSide:false,compactIntro:false});
    });
    const custom = await read();
    assert(custom.preset === 'custom' && custom.state.sideColumns === 1 && custom.introLines.length === 0,
        'independent boolean overrides', custom);
    await preset('tier14');
    await viewport(390,600);
    const narrow = await read();
    assert(narrow.stacked && narrow.state.sideColumns === 1 && narrow.text === wide.text, 'resize restores stacked DOM', narrow);
    assertReading(narrow, 'whole');
    await viewport(1280,600);
    await page.evaluate(({subject,chrome}) => PanelTooltip.updateContentDocument(subject, null, chrome), {subject,chrome});
    const restored = await read();
    assert(restored.columnCounts.join() === wide.columnCounts.join() && restored.text === wide.text
        && restored.introLines.length === wide.introLines.length, 'resize and updateContent recreate the same packing', restored);
    assertReading(restored, 'side');
    await viewport(1280,660);
    const tall = await read();
    assert(Math.abs(tall.iconWidth - 192 * 660 / 864) <= 1, 'wide icon restored at 660 CSS px', tall);

    await reset(page, {inspectionDelay:60,projection:{document:subject,chrome}});
    await moveToTile(page, 0);
    await page.waitForFunction(() => PanelTooltip.debugState().inspectionState === 'inspect');
    const wheelPosition = () => page.evaluate(() => ({
        offset:PanelTooltip.debugState().offset,
        top:[...document.querySelectorAll('.flash-tt-side-col')].map(node => node.getBoundingClientRect().top),
        host:document.querySelector('#scroll-host').scrollTop
    }));
    const beforeWheel = await wheelPosition();
    await page.mouse.wheel(0, 180);
    await page.waitForFunction(offset => PanelTooltip.debugState().offset > offset, beforeWheel.offset);
    const afterWheel = await wheelPosition();
    const movement = afterWheel.offset - beforeWheel.offset;
    assert(afterWheel.top.length === 2 && afterWheel.top.every((top,i) => Math.abs(beforeWheel.top[i] - top - movement) <= 1)
        && afterWheel.host === beforeWheel.host, 'owner wheel scrolls both columns by the same offset', {beforeWheel,afterWheel});

    const pinned = await show(subject, {chrome,pinned:true});
    assert(pinned.state.sideColumns === 1 && !pinned.introLines.length && pinned.pointer === 'auto',
        'pinned uses its usual flow and accepts input', pinned);
    assertReading(pinned, 'pinned');
    await page.evaluate(() => {
        PanelTooltip.hide();
        window.__tooltipHarness.showSimple();
    });
    const simple = await read();
    assert(simple.state.profile === 'simple-tooltip' && simple.pointer === 'auto' && simple.viewportCount === 0,
        'simple stays a short composite-hover tooltip', simple);
    await viewport(1366,768);
    await page.evaluate(() => {
        PanelTooltip.hide();
        document.documentElement.style.removeProperty('--cf7-overlay-scale');
    });
    return {sampleWidths, fullHeight:unclamped.height, balancedWidth:balanced.width,
        fullMod:{columns:wide.columnCounts, scrollRange:wide.max}, presets:Object.keys(presets), pinned:true,simple:true};
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
        const layout = await runLayoutAudit(page);
        const browserResult = await runBrowserAudit(page);
        const reading = await runReading(browser, server.url);
        assert(pageErrors.length === 0, 'browser page errors', pageErrors);
        return {browser:'edge',executablePath,static:staticResult,layout,browserResult,reading,pageErrors};
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
