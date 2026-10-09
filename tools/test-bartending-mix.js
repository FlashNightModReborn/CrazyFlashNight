#!/usr/bin/env node
'use strict';

// 调酒吧台 BartendingPanel 的无浏览器冒烟测试：stub 最小 DOM/fetch/宿主请求桥，
// 驱动「投放原料 → 命中配方 → preview → 完成 → commit」链路，断言：
//   - 原料槽按固定顺序渲染 5 种原料并显示剩余数目；
//   - 自由投放与点选酒品均命中同一 spec 配方；
//   - 配方不成立时「完成」保持禁用（不发起 preview/commit）；
//   - 命中后 preview 携带与 spec 一致的 technique（含 optional 卡莫特林投放）；
//   - 摇壶按 未摇制→轻摇→猛摇→轻摇 循环，「重做」清空投放。
//
// 用法：node tools/test-bartending-mix.js

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const specPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'bartending-spec.json');
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));

let failures = 0;
function check(cond, label) {
    if (cond) { console.log('  PASS ' + label); }
    else { failures += 1; console.error('  FAIL ' + label); }
}

/* ── 最小 DOM stub ── */
function makeEl(tag) {
    const el = {
        tagName: String(tag || 'div').toUpperCase(),
        children: [], childNodes: [],
        className: '', textContent: '', innerHTML: '', value: '',
        disabled: false, type: '', parentNode: null,
        _listeners: {},
        _attrs: {},
        style: {},
        classList: {
            _set: {},
            add(c) { this._set[c] = true; },
            remove(c) { delete this._set[c]; },
            contains(c) { return !!this._set[c]; }
        },
        setAttribute(k, v) { this._attrs[k] = String(v); },
        getAttribute(k) { return this._attrs[k]; },
        appendChild(c) { c.parentNode = el; el.children.push(c); el.childNodes = el.children; return c; },
        removeChild(c) {
            const i = el.children.indexOf(c);
            if (i >= 0) el.children.splice(i, 1);
            c.parentNode = null; return c;
        },
        addEventListener(type, fn) { (el._listeners[type] = el._listeners[type] || []).push(fn); },
        click() { (el._listeners.click || []).forEach(function(fn) { fn({}); }); },
        queryAll(pred, out) {
            out = out || [];
            if (pred(el)) out.push(el);
            el.children.forEach(function(c) { c.queryAll(pred, out); });
            return out;
        }
    };
    let _text = '';
    let _html = '';
    Object.defineProperty(el, 'textContent', {
        get() { return _text; },
        set(v) { _text = String(v); el.children.length = 0; }
    });
    Object.defineProperty(el, 'innerHTML', {
        get() { return _html; },
        set(v) { _html = String(v); el.children.length = 0; }
    });
    el.textContent = '';
    return el;
}
function findAll(root, pred) { return root.queryAll(pred); }
function findButton(root, label) {
    return findAll(root, function(el) { return el.tagName === 'BUTTON' && el.textContent === label; })[0] || null;
}
function findByClass(root, cls) {
    return findAll(root, function(el) {
        return String(el.className).split(/\s+/).indexOf(cls) >= 0;
    });
}

/* ── 假宿主 ── */
function makeHost(snapshot, materials) {
    const calls = [];
    return {
        calls: calls,
        request(cmd, payload, cb) {
            calls.push({cmd: cmd, payload: payload});
            const response = respond(cmd, payload, snapshot, materials);
            setImmediate(function() { cb(response); });
            return 'call.' + calls.length;
        },
        toast() {}, cue() {},
        iconHtml(icon, cls) { return '<i data-icon="' + icon + '" class="' + cls + '"></i>'; },
        formatNumber(n) { return String(n); },
        requestClose() {}
    };
}

function respond(cmd, payload, snapshot, materials) {
    if (cmd === 'snapshot') return snapshot;
    if (cmd === 'materials') return {success:true, v:1, view:'materials', materials: materials};
    if (cmd === 'preview') {
        return {success:true, v:1, category:payload.category,
            recipeIndex:payload.recipeIndex, craftCount:payload.craftCount,
            canCommit:true, craftToken:'tok.test',
            materials:[], technique:payload.technique};
    }
    if (cmd === 'commit') {
        return {success:true, v:1, operation:'commit', category:payload.category,
            crafted:{displayName:'测试酒'}};
    }
    return {success:false, error:'unsupported_cmd'};
}

function fakeSnapshotRecipes() {
    return spec.recipes.map(function(r) {
        return {recipeId:r.recipeId, recipeIndex:r.recipeIndex, title:r.title,
            output:{name:r.title, displayName:r.title, icon:r.title},
            owned:{total:0}, availability:'ready', canCraftOne:true,
            baseCost:{money:0, kpoints:0}, technique:r.technique};
    });
}

function fakeMaterials(owned) {
    return spec.ingredientSlots.map(function(name) {
        return {name:name, displayName:name, icon:name, owned:owned,
            sourceCount:0, useCount:0, hasSourceSummary:false};
    });
}

/* ── 装载模块 ── */
const sandbox = {
    console: console,
    document: {createElement: makeEl},
    fetch: function() {
        return Promise.resolve({ok:true, json:function() { return Promise.resolve(spec); }});
    },
    setImmediate: setImmediate, setTimeout: setTimeout, clearTimeout: clearTimeout,
    module: undefined, window: {}
};
sandbox.globalThis = sandbox;
vm.createContext(sandbox);
vm.runInContext(fs.readFileSync(
    path.join(projectRoot, 'launcher', 'web', 'modules', 'bartending.js'), 'utf8'),
    sandbox, {filename:'bartending.js'});
const BartendingPanel = sandbox.BartendingPanel;
if (!BartendingPanel) { console.error('BartendingPanel not exported'); process.exit(1); }

function settle() {
    return new Promise(function(resolve) { setImmediate(resolve); });
}
async function flush(times) {
    for (let i = 0; i < (times || 4); i++) await settle();
}

function mountPanel() {
    const host = makeHost({success:true, v:1, category:'调酒',
        recipes:fakeSnapshotRecipes(), balance:{money:0, kpoints:0},
        skills:{}, procurement:{}, note:'ok'}, fakeMaterials(99));
    const shell = makeEl('div');
    BartendingPanel.mount(shell, host);
    return {host: host, shell: shell};
}

function slotPlus(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findButton(slots[slotIndex], '+');
}
function slotMinus(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findButton(slots[slotIndex], '−');
}
function slotValue(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findByClass(slots[slotIndex], 'bart-slot-value')[0].textContent;
}
function slotStock(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findByClass(slots[slotIndex], 'bart-slot-stock')[0].textContent;
}
function confirmButton(shell) { return findButton(shell, '完成'); }
function slotIndexOf(name) { return spec.ingredientSlots.indexOf(name); }

function pour(shell, recipe) {
    for (const name of spec.ingredientSlots) {
        const target = recipe.ingredients[name] || 0;
        const idx = slotIndexOf(name);
        for (let i = 0; i < target; i++) slotPlus(shell, idx).click();
    }
    const tech = recipe.technique;
    if (tech) {
        if (tech.ice) findButton(shell, '加冰').click();
        if (tech.aged) findButton(shell, '陈化').click();
        // 摇壶从 none 起步：轻=1 次点击，猛=2 次，none=不点
        const clicks = tech.shake === 'light' ? 1 : tech.shake === 'hard' ? 2 : 0;
        const shaker = findByClass(shell, 'bart-shaker')[0];
        for (let i = 0; i < clicks; i++) shaker.click();
    }
}

async function main() {
    console.log('[test-bartending-mix] smoke: mount + slots + freeform match');
    let ctx = mountPanel();
    await flush();

    let state = BartendingPanel.debugState();
    check(state.specLoaded === true, 'spec loaded');
    check(state.materialsLoaded === true, 'materials loaded');

    let slots = findByClass(ctx.shell, 'bart-slot');
    check(slots.length === 5, 'five ingredient slots rendered');
    check(slotStock(ctx.shell, 0) === '剩余 99', 'slot shows owned count');
    check(findButton(ctx.shell, '按口味') != null
        && findButton(ctx.shell, '按类型') != null
        && findButton(ctx.shell, '瓶装饮料') != null, 'filter tabs rendered');
    check(findButton(ctx.shell, '按名字') == null, 'no name-search tab');

    const sugar = spec.recipes[0]; // 糖分冲击: 艾德海德2 粉末德尔塔1, light, optional karmotrine
    pour(ctx.shell, sugar);
    await flush();
    state = BartendingPanel.debugState();
    check(state.matched === sugar.recipeIndex, 'freeform pour matches 糖分冲击');
    check(slotValue(ctx.shell, slotIndexOf('艾德海德')) === '2', 'slot count reflects pour');

    let previews = ctx.host.calls.filter(function(c) { return c.cmd === 'preview'; });
    check(previews.length === 1 && previews[0].payload.recipeIndex === sugar.recipeIndex,
        'preview issued for matched recipe');
    check(previews[0].payload.technique.karmotrine === false,
        'optional karmotrine off when slot empty');

    let done = confirmButton(ctx.shell);
    check(done && done.disabled === false, '完成 enabled after matched preview');
    done.click();
    await flush();
    check(ctx.host.calls.some(function(c) { return c.cmd === 'commit'; }), 'commit issued');
    state = BartendingPanel.debugState();
    check(state.matched === null
        && slotValue(ctx.shell, slotIndexOf('艾德海德')) === '0',
        'mix reset after successful commit');

    console.log('[test-bartending-mix] smoke: shaker cycle + reset + wrong recipe blocked');
    ctx = mountPanel();
    await flush();
    const shaker = findByClass(ctx.shell, 'bart-shaker')[0];
    check(findByClass(shaker, 'bart-shaker-state')[0].textContent === '未摇制', 'shaker starts 未摇制');
    shaker.click();
    check(findByClass(ctx.shell, 'bart-shaker-state')[0].textContent === '轻摇', 'click → 轻摇');
    findByClass(ctx.shell, 'bart-shaker')[0].click();
    check(findByClass(ctx.shell, 'bart-shaker-state')[0].textContent === '猛摇', 'click → 猛摇');
    findByClass(ctx.shell, 'bart-shaker')[0].click();
    check(findByClass(ctx.shell, 'bart-shaker-state')[0].textContent === '轻摇', 'click → back to 轻摇');

    slotPlus(ctx.shell, slotIndexOf('艾德海德')).click(); // 1 份艾德海德：无任何配方命中
    await flush();
    state = BartendingPanel.debugState();
    check(state.matched === null, 'wrong mix has no match');
    check(ctx.host.calls.filter(function(c) { return c.cmd === 'preview'; }).length === 0,
        'no preview for unmatched mix');
    check(confirmButton(ctx.shell).disabled === true, '完成 disabled without match');
    findButton(ctx.shell, '重做').click();
    check(slotValue(ctx.shell, slotIndexOf('艾德海德')) === '0', '重做 clears pour');

    console.log('[test-bartending-mix] smoke: drink card click loads recipe');
    ctx = mountPanel();
    await flush();
    const bleedingJane = spec.recipes.filter(function(r) { return r.title === '滴血简'; })[0];
    const cards = findByClass(ctx.shell, 'bart-drink');
    const card = cards.filter(function(c) {
        return findByClass(c, 'bart-drink-name')[0].textContent === '滴血简';
    })[0];
    card.click();
    await flush();
    state = BartendingPanel.debugState();
    check(state.matched === bleedingJane.recipeIndex, 'card click loads recipe → match');
    check(state.mix.shake === 'hard' && state.mix.ice === false,
        'card click applies technique (hard, no ice)');

    console.log('[test-bartending-mix] smoke: filters');
    findButton(ctx.shell, '按口味').click();
    await flush();
    let chips = findByClass(ctx.shell, 'bart-chip');
    check(chips.length === spec.flavors.length, 'flavor chips rendered');
    const sourChip = chips.filter(function(c) { return c.textContent === '酸'; })[0];
    sourChip.click();
    await flush();
    let names = findByClass(ctx.shell, 'bart-drink-name').map(function(el) { return el.textContent; });
    check(names.length === spec.recipes.filter(function(r) { return r.flavor === '酸'; }).length,
        'flavor filter narrows list');
    check(names.indexOf('糖分冲击') < 0 && names.indexOf('钢琴女郎') >= 0,
        'filter keeps 酸 drinks only');

    findButton(ctx.shell, '瓶装饮料').click();
    await flush();
    names = findByClass(ctx.shell, 'bart-drink-name').map(function(el) { return el.textContent; });
    check(names.length === spec.recipes.filter(function(r) { return r.bottled === true; }).length,
        'bottled tab lists bottled drinks');
    check(names.indexOf('扎啤') >= 0, 'bottled tab contains 扎啤');

    BartendingPanel.unmount();
    if (failures) { console.error('[test-bartending-mix] ' + failures + ' failure(s)'); process.exit(1); }
    console.log('[test-bartending-mix] all checks passed');
}

main().catch(function(error) {
    console.error('[test-bartending-mix] ' + (error && error.stack || error));
    process.exit(1);
});
