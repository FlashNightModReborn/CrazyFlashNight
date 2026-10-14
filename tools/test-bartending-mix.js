#!/usr/bin/env node
'use strict';

// 调酒吧台 BartendingPanel 的无浏览器冒烟与契约测试：stub 最小 DOM/fetch/宿主请求桥，
// 驱动 VA-11 纯正手动调酒链路，断言：
//   - 五色提取物分配器按固定顺序渲染，带化学代号（ADL/BRN/PWD/FLN/KRM）与剩余库存；
//   - 栏位 1 / 栏位 2 双 10 格液位矩阵（共 20 格）随投料点亮，总容量上限严格为 20（如 20 格满配「禅星」）；
//   - 投料阶段保持悬念（不提前发起 preview）；
//   - 5 秒实时计时摇壶：点「调制」起摇，<5s「停止」为轻摇 Mix，≥5s「停止」为猛摇 Blend，点「直调」为不摇；
//   - 调配失败（原料不符 / 摇壶超时或不足 / 误摇免摇酒 / 酒精过载）触发「莫洛托夫雏形（酒手雷）」险情诊断，
//     严禁出杯（不发 preview/commit），点「重做」无损倾倒清零；
//   - 左侧酒单手册 Drinktionary 为纯只读翻阅：点选酒品打开配方与风味详情页，绝不自动代填吧台原料；
//   - 隐藏特调「烈焰摩艾」初始以机密页展示，手动「直调」成功后自动破译收录。
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
            add(c) {
                this._set[c] = true;
                const parts = String(el.className || '').split(/\s+/).filter(Boolean);
                if (parts.indexOf(c) < 0) parts.push(c);
                el.className = parts.join(' ');
            },
            remove(c) {
                delete this._set[c];
                const parts = String(el.className || '').split(/\s+/).filter(function(x) { return x && x !== c; });
                el.className = parts.join(' ');
            },
            contains(c) {
                const parts = String(el.className || '').split(/\s+/).filter(Boolean);
                return !!this._set[c] || parts.indexOf(c) >= 0;
            }
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
        click() {
            if (el.disabled) return;
            (el._listeners.click || []).forEach(function(fn) { fn({}); });
        },
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
    const toasts = [];
    const cues = [];
    return {
        calls: calls,
        toasts: toasts,
        cues: cues,
        request(cmd, payload, cb) {
            calls.push({cmd: cmd, payload: payload});
            const response = respond(cmd, payload, snapshot, materials);
            setImmediate(function() { cb(response); });
            return 'call.' + calls.length;
        },
        toast(msg) { toasts.push(msg); },
        cue(name) { cues.push(name); },
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
    Date: Date,
    setImmediate: setImmediate,
    setTimeout: setTimeout, clearTimeout: clearTimeout,
    setInterval: function() { return 1; },
    clearInterval: function() {},
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
        recipes:fakeSnapshotRecipes(), balance:{money:12000, kpoints:50},
        skills:{}, procurement:{}, note:'ok'}, fakeMaterials(99));
    const shell = makeEl('div');
    BartendingPanel.mount(shell, host);
    return {host: host, shell: shell};
}

function slotPlus(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findButton(slots[slotIndex], '+');
}
function slotValue(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findByClass(slots[slotIndex], 'bart-slot-value')[0].textContent;
}
function slotStock(shell, slotIndex) {
    const slots = findByClass(shell, 'bart-slot');
    return findByClass(slots[slotIndex], 'bart-slot-stock')[0].textContent;
}
function serveButton(shell) { return findButton(shell, '上酒'); }
function slotIndexOf(name) { return spec.ingredientSlots.indexOf(name); }

function pourAndMix(shell, recipe, extraKarmotrine) {
    for (const name of spec.ingredientSlots) {
        let target = recipe.ingredients[name] || 0;
        if (name === '卡莫特林' && extraKarmotrine) target += extraKarmotrine;
        const idx = slotIndexOf(name);
        for (let i = 0; i < target; i++) slotPlus(shell, idx).click();
    }
    const tech = recipe.technique;
    if (tech) {
        if (tech.ice) findButton(shell, '加冰').click();
        if (tech.aged) findButton(shell, 'aged' === 'ice' ? '加冰' : '陈化').click();
        if (tech.shake === 'none') {
            findButton(shell, '直调').click();
        } else {
            findButton(shell, '调制').click();
            BartendingPanel.advanceShake(tech.shake === 'hard' ? 5200 : 1800);
            findButton(shell, '停止').click();
        }
    }
}

async function main() {
    console.log('[test-bartending-mix] 1. mount + 5 chemical slots + 20-slot dual matrix + light shake (<5s) flow');
    let ctx = mountPanel();
    await flush();

    let state = BartendingPanel.debugState();
    check(state.specLoaded === true, 'spec loaded');
    check(state.materialsLoaded === true, 'materials loaded');

    let slots = findByClass(ctx.shell, 'bart-slot');
    check(slots.length === 5, 'five ingredient slots rendered');
    check(slotStock(ctx.shell, 0) === '剩余 99', 'slot shows owned count');
    check(findByClass(ctx.shell, 'bart-cell').length === 20, '20-slot dual matrix (栏位1 + 栏位2) rendered');
    check(findButton(ctx.shell, '按名称') != null
        && findButton(ctx.shell, '按口味') != null
        && findButton(ctx.shell, '按种类') != null
        && findButton(ctx.shell, '瓶装饮品') != null, 'VA-11 4 Drinktionary filter tabs rendered');

    const sugar = spec.recipes[0]; // 糖分冲击 (Sugar Rush): 艾德海德2 粉末德尔塔1, light, optional karmotrine
    slotPlus(ctx.shell, slotIndexOf('艾德海德')).click();
    slotPlus(ctx.shell, slotIndexOf('艾德海德')).click();
    slotPlus(ctx.shell, slotIndexOf('粉末德尔塔')).click();
    await flush();
    state = BartendingPanel.debugState();
    check(state.revealed === false && state.matched === null, 'pouring does not prematurely spoil or match before shaking');
    check(findByClass(ctx.shell, 'bart-cell').filter(function(c) { return c.classList.contains('filled'); }).length === 3,
        '3 matrix cells lit up after pouring 3 extracts');
    check(findByClass(ctx.shell, 'bart-cell').filter(function(c) { return c.classList.contains('is-newest'); }).length === 1,
        'latest poured cell receives .is-newest ignition animation class');
    check(findByClass(ctx.shell, 'bart-liquid-layer').length === 2,
        'shaker sight-glass renders 2 proportional color layers (ADL + PWD)');
    check(state.audioLog.filter(function(a) { return a.effect === 'addingredient'; }).length === 3,
        'pouring 3 extracts triggers 3 pitch-climbing addingredient audio cues');

    // 启动实时摇壶，摇制 1.8s (<5s = 轻摇 Mix) 后停止
    findButton(ctx.shell, '调制').click();
    state = BartendingPanel.debugState();
    check(state.shaking === true && state.mix.shake === 'light', 'clicking 调制 starts real-time shaker in light mode');
    BartendingPanel.advanceShake(1800);
    findButton(ctx.shell, '停止').click();
    await flush();

    state = BartendingPanel.debugState();
    check(state.shaking === false && state.revealed === true, 'clicking 停止 opens shaker and reveals');
    check(state.matched === sugar.recipeIndex, '1.8s (<5s) shake matches 糖分冲击 (Sugar Rush)');
    check(slotValue(ctx.shell, slotIndexOf('艾德海德')) === '2', 'slot count reflects pour');
    check(state.audioLog.some(function(a) { return a.effect === 'shaketick'; })
        && state.audioLog.some(function(a) { return a.effect === 'cocktail_reveal'; }),
        'shaking and stopping triggers shaketick loop + cocktail_reveal chord');

    let previews = ctx.host.calls.filter(function(c) { return c.cmd === 'preview'; });
    check(previews.length === 1 && previews[0].payload.recipeIndex === sugar.recipeIndex,
        'preview issued for revealed matched recipe');
    check(previews[0].payload.technique.karmotrine === false,
        'optional karmotrine off when slot empty');

    let done = serveButton(ctx.shell);
    check(done && done.disabled === false, '上酒 enabled after matched preview');
    done.click();
    await flush();
    check(ctx.host.calls.some(function(c) { return c.cmd === 'commit'; }), 'commit issued on 上酒');
    state = BartendingPanel.debugState();
    check(state.audioLog.some(function(a) { return a.effect === 'glassserve'; }),
        'successful 上酒 triggers glassserve bar-slide audio cue');
    check(state.matched === null && state.revealed === false
        && slotValue(ctx.shell, slotIndexOf('艾德海德')) === '0',
        'mix reset after successful commit');

    console.log('[test-bartending-mix] 2. real-time shaker >=5s transitions to hard blend + 20-slot Zen Star capacity');
    ctx = mountPanel();
    await flush();
    const zenStar = spec.recipes.filter(function(r) { return r.title === '禅星'; })[0]; // 4+4+4+4+4 = 20 格满配
    pourAndMix(ctx.shell, zenStar, 0);
    await flush();
    state = BartendingPanel.debugState();
    check(state.mix.totalPoured === 20 && state.matched === zenStar.recipeIndex,
        '20-slot capacity supports 禅星 (Zen Star 4×5=20)');
    check(findByClass(ctx.shell, 'bart-liquid-layer').length === 5,
        'shaker sight-glass renders all 5 chemical color layers for Zen Star');
    check(state.audioLog.some(function(a) { return a.effect === 'iceadd'; }),
        'Zen Star triggers iceadd clink');
    check(slotPlus(ctx.shell, 0).disabled === true, '+ buttons disabled when 20-slot shaker is full');

    console.log('[test-bartending-mix] 3. failed mixes trigger Molotov / Alcohol Grenade (酒手雷) hazard state');
    ctx = mountPanel();
    await flush();
    // 案例 A：把本该轻摇 (<5s) 的糖分冲击摇满 5.5 秒（猛摇 Blend）→ 过度调和变成莫洛托夫酒手雷
    slotPlus(ctx.shell, slotIndexOf('艾德海德')).click();
    slotPlus(ctx.shell, slotIndexOf('艾德海德')).click();
    slotPlus(ctx.shell, slotIndexOf('粉末德尔塔')).click();
    findButton(ctx.shell, '调制').click();
    BartendingPanel.advanceShake(5500);
    check(BartendingPanel.debugState().mix.shake === 'hard', 'shaker transitions to hard (Blend) at >=5000ms');
    check(BartendingPanel.debugState().audioLog.some(function(a) { return a.effect === 'mixdone_blend'; }),
        '>=5s crossover triggers mixdone_blend chime');
    findButton(ctx.shell, '停止').click();
    await flush();

    state = BartendingPanel.debugState();
    check(state.revealed === true && state.matched === null, 'overshaken Sugar Rush fails match');
    check(state.molotov && state.molotov.code === 'overshaken_blend',
        'Molotov forensics diagnoses overshaken_blend (≥5s on light recipe)');
    check(state.audioLog.some(function(a) { return a.effect === 'molotov_explosion'; }),
        'Molotov hazard triggers molotov_explosion fuse+combustion audio cue');
    check(findByClass(ctx.shell, 'bart-result')[0].classList.contains('is-molotov'),
        'coaster enters .is-molotov hazard state');
    check(ctx.host.calls.filter(function(c) { return c.cmd === 'preview'; }).length === 0,
        'no preview issued when mix turns into Molotov');
    check(serveButton(ctx.shell).disabled === true, '上酒 strictly disabled during Molotov hazard');

    // 点「重做」无损倾倒清零
    findButton(ctx.shell, '重做').click();
    state = BartendingPanel.debugState();
    check(state.revealed === false && state.molotov === null && state.mix.totalPoured === 0,
        '重做 safely disposes Molotov and clears shaker');
    check(state.audioLog.some(function(a) { return a.effect === 'reset_drain'; }),
        '重做 triggers reset_drain sink flush audio cue');

    // 案例 B：狂野乱投原料 → wild_concoction 酒手雷
    slotPlus(ctx.shell, slotIndexOf('弗拉内吉')).click();
    slotPlus(ctx.shell, slotIndexOf('卡莫特林')).click();
    findButton(ctx.shell, '调制').click();
    BartendingPanel.advanceShake(1200);
    findButton(ctx.shell, '停止').click();
    await flush();
    state = BartendingPanel.debugState();
    check(state.molotov && state.molotov.code === 'wild_concoction',
        'random invalid ratio diagnoses wild_concoction Molotov');
    findButton(ctx.shell, '重做').click();

    console.log('[test-bartending-mix] 4. pure read-only Drinktionary detail view + secret Flaming Moai discovery');
    ctx = mountPanel();
    await flush();
    const cards = findByClass(ctx.shell, 'bart-drink');
    const janeCard = cards.filter(function(c) {
        return findByClass(c, 'bart-drink-name')[0].textContent === '滴血简';
    })[0];
    janeCard.click();
    await flush();
    state = BartendingPanel.debugState();
    check(state.inspectedIndex !== null, 'clicking drink card opens Drinktionary detail page');
    check(state.mix.totalPoured === 0 && state.matched === null,
        'hardcore VA-11 mode: Drinktionary click is strictly read-only and never auto-fills shaker');
    check(findByClass(ctx.shell, 'bart-detail').length === 1, 'detail view rendered in left pane');
    findButton(ctx.shell, '← 返回酒单').click();
    check(BartendingPanel.debugState().inspectedIndex === null, '← 返回酒单 returns to catalog grid');

    // 隐藏特调「烈焰摩艾」初始未解锁，显示为 ??? · 隐藏特调；通过「直调」调制后自动破译
    const moai = spec.recipes.filter(function(r) { return r.title === '烈焰摩艾'; })[0];
    check(BartendingPanel.debugState().unlockedSecrets.indexOf(moai.recipeId) < 0,
        'Flaming Moai starts locked in secret Drinktionary');
    pourAndMix(ctx.shell, moai, 0);
    await flush();
    state = BartendingPanel.debugState();
    check(state.matched === moai.recipeIndex, 'directReveal (直调) matches unshaken 烈焰摩艾');
    check(state.unlockedSecrets.indexOf(moai.recipeId) >= 0,
        'mixing 烈焰摩艾 unlocks its secret Drinktionary entry');

    console.log('[test-bartending-mix] 5. Drinktionary filters (按名称/按口味/按种类/瓶装饮品)');
    findButton(ctx.shell, '按口味').click();
    await flush();
    let chips = findByClass(ctx.shell, 'bart-chip');
    check(chips.length === spec.flavors.length, 'flavor chips rendered');
    const sourChip = chips.filter(function(c) { return c.textContent === '酸'; })[0];
    sourChip.click();
    await flush();
    let names = findByClass(ctx.shell, 'bart-drink-name').map(function(el) { return el.textContent; });
    check(names.length === spec.recipes.filter(function(r) { return r.flavor === '酸'; }).length,
        'flavor filter narrows list to 酸 drinks');
    check(names.indexOf('糖分冲击') < 0 && names.indexOf('钢琴女郎') >= 0,
        'filter keeps 酸 drinks only');

    findButton(ctx.shell, '瓶装饮品').click();
    await flush();
    names = findByClass(ctx.shell, 'bart-drink-name').map(function(el) { return el.textContent; });
    check(names.length === spec.recipes.filter(function(r) { return r.bottled === true; }).length,
        '瓶装饮品 tab lists bottled drinks');
    check(names.indexOf('扎啤') >= 0, '瓶装饮品 tab contains 扎啤');

    BartendingPanel.unmount();
    if (failures) { console.error('[test-bartending-mix] ' + failures + ' failure(s)'); process.exit(1); }
    console.log('[test-bartending-mix] all checks passed');
}

main().catch(function(error) {
    console.error('[test-bartending-mix] ' + (error && error.stack || error));
    process.exit(1);
});
