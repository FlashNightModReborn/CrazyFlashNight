'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const {load} = require('../../tooltip-engine/tests/helpers.cjs');
const {itemInput} = require('../../tooltip-engine/fixtures.cjs');
const {compile} = require('../../../tools/tooltip-catalog.cjs');

const itemNames = ['战术手电', '镭射瞄准具', '灰蛊裂隙弹', '谐振波射线弹', '三蝶手稿',
    'dominator', 'MP510', '061ABSR', 'GM6_LYNX', '钛合金QJZ171'];

function currentSamples() {
    const data = JSON.parse(compile(root).catalog);
    const {buildProjection} = load();
    return itemNames.map(name => ({
        id:name, name, itemType:data.items[name].type,
        document:buildProjection(itemInput(data, name, {presentation:'web'}), data).document
    })).concat({
        id:'flashlight-known-shops', name:'战术手电', itemType:data.items['战术手电'].type,
        document:buildProjection(itemInput(data, '战术手电', {presentation:'web', projection:{
            obtainRecords:[{kind:'shop',npc:'前治安官'}, {kind:'shop',npc:'迷之盔甲君'}]
        }}), data).document
    });
}

function section(role, prefix, count) {
    return {role, runs:[{text:Array.from({length:count}, (_, i) => prefix + (i + 1)).join('\n')}]};
}

function synthetic(id, intro, desc, subs) {
    const sections = [section('intro', 'INTRO-', intro)];
    if (desc) sections.push(section('description', 'DESC-', desc));
    subs.forEach((count, i) => sections.push(section('sub', 'SUB-' + (i + 1) + '-', count)));
    return {id, name:id, itemType:'武器', document:{version:1, profile:'dense', layoutType:'wide',
        title:id, icon:{kind:'item',name:'战术手电'}, sections}};
}

function measure() {
    const el = PanelTooltip.getElement();
    const node = el.querySelector('[data-tooltip-reading-viewport]');
    const debug = PanelTooltip.debugState();
    const bounds = el.getBoundingClientRect();
    const inner = node.getBoundingClientRect();
    const nested = [...node.querySelectorAll('*')].filter(n =>
        /^(auto|scroll)$/.test(getComputedStyle(n).overflowY) && n.scrollHeight > n.clientHeight + 1);
    const panels = [...el.querySelectorAll('.flash-tt-intro-panel,.flash-tt-desc,.flash-tt-sub-panel,.flash-tt-suffix')];
    const tails = panels.map(panel => {
        const walker = document.createTreeWalker(panel, NodeFilter.SHOW_TEXT);
        let current, last;
        while ((current = walker.nextNode())) if (current.textContent.trim()) last = current;
        if (!last) return null;
        const end = last.textContent.trimEnd().length;
        const range = document.createRange();
        range.setStart(last, end - 1);
        range.setEnd(last, end);
        const box = range.getBoundingClientRect();
        const clip = node.contains(last) ? inner : bounds;
        return {text:last.textContent.trim().slice(-20), seen:box.height > 0
            && box.top >= Math.max(0,clip.top) - 1 && box.bottom <= Math.min(innerHeight,clip.bottom) + 1
            && box.left >= Math.max(0,clip.left) - 1 && box.right <= Math.min(innerWidth,clip.right) + 1};
    }).filter(Boolean);
    return {target:debug.readingTarget, phase:debug.inspectionState, max:node.scrollHeight - node.clientHeight,
        offset:node.scrollTop, view:node.clientHeight, tails, nested:nested.length,
        inside:bounds.left >= -1 && bounds.top >= -1 && bounds.right <= innerWidth+1 && bounds.bottom <= innerHeight+1,
        host:document.querySelector('#outer').scrollTop, pointer:getComputedStyle(el).pointerEvents};
}

// Use the actual equipment-grid binding. Only the asynchronous domain reply is supplied by the fixture.
function bindEquipment(sample) {
    const owner = document.querySelector('#owner');
    owner.textContent = sample.name;
    function View() {}
    EquipmentTuningRender.install(View, EquipmentTuningModel);
    const view = new View();
    view._tooltipEpoch = 1;
    view._viewSessionId = 'reading';
    view._snapshot = {inventoryRevision:1,materialRevision:1};
    view._source = null;
    view._tooltipCache = {};
    view._tooltipScope = PanelTooltip.createScope('equipment-reading', {profile:'dense-inspect'});
    view._setInfoSubject = function() {};
    view._mux = {
        debugState:() => ({active:true,pendingCount:0}),
        request:(command, payload, done) => {
            if (command !== 'tooltip') throw Error(command);
            setTimeout(() => done({success:true, itemType:sample.itemType, document:sample.document}), 10);
        }
    };
    view._bindCandidateTooltip(owner, {candidateKey:sample.id, itemName:sample.name, displayName:sample.name,
        icon:sample.document.icon?.name || sample.name, available:false, reason:'装备配件槽已满'});
}

async function runReading(browser, baseUrl) {
    const samples = currentSamples();
    const cases = samples.map(sample => ({sample, width:1280, height:720, dpr:1.25}));
    const special = [
        synthetic('short', 1, 1, [1]), synthetic('long-desc', 1, 75, []),
        synthetic('sub-only', 1, 0, [75]), synthetic('multi-sub', 1, 0, [36,38,44]),
        synthetic('desc-plus-sub', 1, 75, [55]), synthetic('tall-main', 86, 18, [30]),
        synthetic('stacked', 5, 75, [41])
    ];
    special.forEach(sample => cases.push({sample, width:sample.id === 'stacked' ? 390 : 960, height:540, dpr:1}));
    cases.push({sample:samples.at(-1), width:1600,height:900,dpr:1});
    const results = [];
    for (const {sample,width,height,dpr} of cases) {
        const page = await browser.newPage({viewport:{width,height},deviceScaleFactor:dpr});
        try {
            const errors = [];
            page.on('pageerror', e => errors.push(String(e)));
            await page.goto(baseUrl + 'perf/tooltip-interaction/reading-fixture.html');
            await page.evaluate(() => new Promise(resolve => Icons.load(resolve)));
            await page.evaluate(bindEquipment, sample);
            await page.locator('#owner').hover();
            await page.waitForSelector('.equipment-tuning-tooltip');
            await page.evaluate(() => document.fonts.ready);
            await page.waitForTimeout(120);
            const first = await page.evaluate(measure);
            assert.equal(first.nested, 0, sample.id + ' has a nested scroller');
            assert.equal(first.inside, true, sample.id + ' shell outside viewport ' + JSON.stringify(first));
            assert.equal(first.pointer, 'none');
            if (['stacked','tall-main'].includes(sample.id)) assert.equal(first.target, 'whole');
            if (sample.id === 'flashlight-known-shops' && width === 1280) assert(first.max > 1);
            if (sample.id === 'short') assert(first.max <= 1);
            if (['sub-only','multi-sub','desc-plus-sub','long-desc'].includes(sample.id)) assert(first.max > 1);
            const seen = first.tails.map(t => t.seen);
            let last = first;
            if (first.max > 1) {
                await page.waitForFunction(() => PanelTooltip.debugState().inspectionState === 'inspect');
                for (let i = 0; i < 100 && last.offset < last.max - 1; i++) {
                    const offset = last.offset;
                    await page.mouse.wheel(0, Math.max(30, Math.floor(last.view * .67) * dpr));
                    await page.waitForFunction(old => PanelTooltip.debugState().offset > old, offset, {timeout:2000});
                    last = await page.evaluate(measure);
                    last.tails.forEach((t, j) => { seen[j] ||= t.seen; });
                }
                assert(Math.abs(last.offset-last.max) <= 1, sample.id + ' bottom');
                await page.mouse.wheel(0, 260);
                await page.waitForTimeout(60);
                assert.equal((await page.evaluate(measure)).host, first.host, sample.id + ' leaked to host');
                if (sample.id === 'multi-sub') {
                    await page.locator('#owner').focus();
                    await page.keyboard.press('PageUp');
                    assert((await page.evaluate(measure)).offset < last.offset, 'PageUp on grouped side');
                    await page.keyboard.press('PageDown');
                    assert(Math.abs((await page.evaluate(measure)).offset-last.max) <= 1);
                    // Same session should retain its cursor, then switch target when the main panel grows.
                    await page.evaluate(doc => PanelTooltip.updateContentDocument(doc), sample.document);
                    assert(Math.abs((await page.evaluate(measure)).offset-last.max) <= 1);
                    await page.evaluate(doc => PanelTooltip.updateContentDocument(doc), special.find(s=>s.id === 'tall-main').document);
                    const changed = await page.evaluate(measure);
                    assert.equal(changed.target, 'whole');
                    assert.equal(changed.offset, 0);
                    assert.equal(changed.phase, 'inspect');
                }
            }
            assert(seen.every(Boolean), sample.id + ' unreachable panel tails ' + JSON.stringify({seen,first,last}));
            assert.deepEqual(errors, []);
            results.push({id:sample.id,width,height,dpr,target:first.target,max:first.max,offset:last.offset,tails:last.tails.map(t=>t.text)});
        } finally { await page.close(); }
    }
    return results;
}
// Print the current engine documents in the existing parity harness input format.
if (require.main === module) {
    process.stdout.write(JSON.stringify({schema:'cf7.tooltip-parity-samples.v1',
        source:'current-tooltip-engine', samples:currentSamples()}, null, 2) + '\n');
}
module.exports = {runReading,currentSamples};

