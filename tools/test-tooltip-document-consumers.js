'use strict';

// 定向 Node 测试：生产消费者对 data.document 的最小接线。
// 装入真实模块（workbench-primitives / tooltip / tooltip-document /
// kshop-tooltip-presenter / inventory-workbench-owned-view /
// npcshop-secondary-pages）于同一 vm 上下文 + 最小假 DOM；
// 断言 document 接管时面板 chrome（icon/meta/suffix/rootClass/价格锁定横幅）
// 原样保留、document 缺失/不合法时回落 legacy、cache 命中与迟到回包不串卡。
// 不启动浏览器/游戏。

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

let passed = 0;
function test(name, run) {
    run();
    passed++;
    process.stdout.write('ok - ' + name + '\n');
}

// ── 最小假 DOM（与 test-tooltip-document-binding.js 同构）──

function makeEl(tag) {
    const el = {
        tagName: (tag || 'div').toUpperCase(),
        className: '',
        id: '',
        children: [],
        parentNode: null,
        style: {
            setProperty() {}, removeProperty() {},
            left: '', top: '', display: '', width: ''
        },
        _attrs: {},
        _listeners: {},
        _innerHTML: '',
        textContent: '',
        scrollTop: 0, scrollHeight: 0, clientHeight: 0,
        isConnected: true,
        classList: {
            _set: {},
            add(c) { this._set[c] = 1; },
            remove() { for (const c of arguments) delete this._set[c]; },
            toggle(c, f) {
                if (f === undefined) f = !this._set[c];
                if (f) this._set[c] = 1; else delete this._set[c];
            },
            contains(c) { return !!this._set[c]; }
        },
        setAttribute(k, v) { this._attrs[k] = String(v); },
        getAttribute(k) { return k in this._attrs ? this._attrs[k] : null; },
        removeAttribute(k) { delete this._attrs[k]; },
        hasAttribute(k) { return k in this._attrs; },
        addEventListener(t, f) { (this._listeners[t] = this._listeners[t] || []).push(f); },
        removeEventListener(t, f) {
            const l = this._listeners[t] || [];
            const i = l.indexOf(f);
            if (i >= 0) l.splice(i, 1);
        },
        dispatch(t, e) {
            e = e || {};
            if (e.preventDefault === undefined) e.preventDefault = () => { e._prevented = true; };
            if (e.stopPropagation === undefined) e.stopPropagation = () => { e._stopped = true; };
            if (e.target === undefined) e.target = el;
            (this._listeners[t] || []).slice().forEach(f => f(e));
        },
        appendChild(c) { this.children.push(c); c.parentNode = this; return c; },
        insertBefore(c) { this.children.unshift(c); c.parentNode = this; return c; },
        querySelector(sel) { return findDesc(this, n => matchSel(n, sel)); },
        querySelectorAll(sel) {
            const out = [];
            walkDesc(this, n => { if (matchSel(n, sel)) out.push(n); });
            return out;
        },
        contains(n) {
            for (let cur = n; cur; cur = cur.parentNode) if (cur === this) return true;
            return false;
        },
        getBoundingClientRect() {
            return { left: 0, top: 0, right: 200, bottom: 120, width: 200, height: 120 };
        },
        closest() { return null; }
    };
    Object.defineProperty(el, 'innerHTML', {
        get() { return this._innerHTML; },
        set(v) { this._innerHTML = String(v); this.children = []; }
    });
    return el;
}
function walkDesc(root, fn) {
    for (const c of root.children) { fn(c); if (c.children) walkDesc(c, fn); }
}
function findDesc(root, fn) {
    for (const c of root.children) {
        if (fn(c)) return c;
        const r = findDesc(c, fn);
        if (r) return r;
    }
    return null;
}
function matchSel(el, sel) {
    return String(sel).split(',').some(part => {
        part = part.trim();
        if (part.charAt(0) === '.') {
            return (el.className || '').split(/\s+/).indexOf(part.substring(1)) >= 0;
        }
        return el.tagName === part.toUpperCase();
    });
}

const tooltipEl = makeEl('div');
tooltipEl.id = 'panel-tooltip';
const documentEl = makeEl('html');
const documentStub = {
    readyState: 'complete',
    currentScript: { src: 'https://cf7.local/web/modules/tooltip.js' },
    documentElement: documentEl,
    head: makeEl('head'),
    body: makeEl('body'),
    activeElement: null,
    getElementById(id) { return id === 'panel-tooltip' ? tooltipEl : null; },
    createElement(tag) { return makeEl(tag); },
    querySelectorAll() { return []; },
    addEventListener() {}, removeEventListener() {},
    elementFromPoint() { return null; }
};
// documentElement.contains 要覆盖挂进文档树的触发节点（presenter 用它做存活检查）
documentEl.contains = function(n) {
    if (n === documentEl || n === tooltipEl || tooltipEl.contains(n)) return true;
    for (const c of documentEl.children) {
        if (c === n || (c.contains && c.contains(n))) return true;
    }
    return false;
};

const windowStub = {
    innerWidth: 1024, innerHeight: 576,
    addEventListener() {}, removeEventListener() {}
};

const modulesDir = path.join(__dirname, '..', 'launcher', 'web', 'modules');
function loadCtx() {
    const ctx = {
        document: documentStub,
        window: windowStub,
        setTimeout, clearTimeout,
        requestAnimationFrame(f) { f(); return 0; },
        Date, console
    };
    ctx.globalThis = ctx;
    vm.createContext(ctx);
    for (const f of [
        'workbench-primitives.js',
        'tooltip-document.js',
        'tooltip.js',
        'kshop-tooltip-presenter.js',
        'inventory-workbench-owned-view.js',
        'npcshop-secondary-pages.js',
        'panel-runtime.js',
        'character-build/character-build-candidate-tooltip.js'
    ]) {
        vm.runInContext(fs.readFileSync(path.join(modulesDir, f), 'utf8'), ctx);
    }
    return ctx;
}

const ctx = loadCtx();
// tooltip.js 是顶层 `var PanelTooltip` → 挂 ctx（浏览器里等价 window 全局）；
// 生产消费者引用的也是这个裸全局。UMD 模块则挂 ctx.window.*。
const PanelTooltip = ctx.PanelTooltip;
const Presenter = ctx.window.KShopTooltipPresenter;
const OwnedView = ctx.window.InventoryWorkbenchOwnedView;
const SecondaryPages = ctx.window.NpcShopSecondaryPages;
assert(PanelTooltip && Presenter && OwnedView && SecondaryPages,
    '真实生产模块必须全部挂载到 window');

const DOC = {
    version: 1,
    title: 'M4A1-消音',
    icon: { kind: 'item', name: 'M4A1' },
    profile: 'dense',
    sections: [
        { role: 'intro', runs: [{ text: '武器    步枪\n$20000' }] },
        { role: 'description', runs: [{ text: '制式步枪的消音改进型。' }] }
    ]
};

function reset() {
    PanelTooltip.hide();
    tooltipEl._innerHTML = '';
    tooltipEl.children = [];
}

function makePresenter(overrides) {
    const shopCallbacks = {};
    const inventoryCallbacks = {};
    const state = Object.assign({
        isLocked: item => item.idx === 9,
        isOpen: () => true,
        isDragSuppressed: () => false,
        isOwnedSelectionSuppressed: () => false,
        findCatalogItem: idx => ({ idx, displayname: 'item-' + idx, icon: 'ic', majorType: '武器' })
    }, overrides && overrides.state);
    const intent = Object.assign({
        requestShop(cmd, payload, cb) { shopCallbacks[payload.idx] = cb; },
        requestInventory(cmd, payload, cb) { inventoryCallbacks[payload.source.slot] = cb; },
        ownedSlotRef(containerId, slot) {
            return { containerId, slot: slot.physicalSlot, expectedLease: String(slot.slotLease || '') };
        }
    }, overrides && overrides.intent);
    const presenter = new Presenter.TooltipPresenter({ state, intent });
    return { presenter, shopCallbacks, inventoryCallbacks };
}

function attachNode() {
    const node = makeEl('div');
    documentEl.appendChild(node);
    return node;
}

// ── kshop presenter（真实生产模块）──

test('kshop catalog：响应带 document → document 渲染且 chrome 全保留', () => {
    reset();
    const { presenter, shopCallbacks } = makePresenter();
    const item = { idx: 9, displayname: 'M4A1-消音', icon: 'M4A1', majorType: '武器',
        level: 10, price: 20000 };
    const card = attachNode();
    presenter.bindCatalog(card, item);
    card.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: card });
    assert(shopCallbacks[9], 'fetch 应发出');
    shopCallbacks[9]({
        success: true,
        introHTML: '<b>legacy-intro-不应出现</b>',
        descHTML: 'legacy-desc-不应出现',
        document: DOC
    });
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('ntt-doc') >= 0, '应走 document 渲染');
    assert(html.indexOf('legacy-intro-不应出现') < 0, 'document 优先于 introHTML');
    assert(html.indexOf('M4A1-消音') >= 0);
    // chrome：rootClass / 锁定 suffix / meta / icon 块
    assert(html.indexOf('kshop-tt-rich-context') >= 0, 'rootClass 保留');
    assert(html.indexOf('kshop-tt-lock-banner') >= 0, 'idx=9 锁定 → suffix 横幅保留');
    assert(html.indexOf('ntt-icon') >= 0, 'icon 块保留');
});

test('kshop catalog：无 document → legacy 路径原样工作', () => {
    reset();
    const { presenter, shopCallbacks } = makePresenter();
    const item = { idx: 3, displayname: '普通货', icon: 'x', majorType: '物品' };
    const card = attachNode();
    presenter.bindCatalog(card, item);
    card.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: card });
    shopCallbacks[3]({
        success: true,
        introHTML: '<b>旧注释标题</b>',
        descHTML: '旧注释正文'
    });
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('ntt-doc') < 0);
    assert(html.indexOf('旧注释标题') >= 0);
    assert(html.indexOf('旧注释正文') >= 0);
});

test('kshop catalog：不合法 document → 回落 legacy 不丢内容', () => {
    reset();
    const { presenter, shopCallbacks } = makePresenter();
    const item = { idx: 4, displayname: 'x', icon: 'x', majorType: '物品' };
    const card = attachNode();
    presenter.bindCatalog(card, item);
    card.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: card });
    shopCallbacks[4]({
        success: true,
        introHTML: '<b>legacy-生效</b>',
        descHTML: '',
        document: { version: 2, title: '不支持' }
    });
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('ntt-doc') < 0);
    assert(html.indexOf('legacy-生效') >= 0);
});

test('kshop catalog：同 cache 两物品不串卡；A 迟到回包不覆盖 B', () => {
    reset();
    const { presenter, shopCallbacks } = makePresenter();
    const itemA = { idx: 5, displayname: 'A物', icon: 'a', majorType: '物品' };
    const itemB = { idx: 6, displayname: 'B物', icon: 'b', majorType: '物品' };
    const cardA = attachNode(), cardB = attachNode();
    presenter.bindCatalog(cardA, itemA);
    presenter.bindCatalog(cardB, itemB);

    cardA.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: cardA });
    cardA.dispatch('mouseleave', {});
    cardB.dispatch('mouseenter', { clientX: 50, clientY: 50, currentTarget: cardB });
    const docB = { version: 1, title: 'B文档', sections: [{ role: 'body', runs: [{ text: 'B内容' }] }] };
    shopCallbacks[6]({ success: true, document: docB });
    assert(tooltipEl.innerHTML.indexOf('B内容') >= 0);
    const beforeB = tooltipEl.innerHTML;
    // A 的迟到回包不得覆盖 B
    shopCallbacks[5]({ success: true, document: { version: 1, title: 'A迟到',
        sections: [{ role: 'body', runs: [{ text: 'A迟到内容' }] }] } });
    assert.strictEqual(tooltipEl.innerHTML, beforeB);

    // 回悬 A：cache 命中 → A 自己的 document（不串 B）
    cardB.dispatch('mouseleave', {});
    cardA.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: cardA });
    assert(tooltipEl.innerHTML.indexOf('A迟到内容') >= 0,
        'A 的 cache 命中应渲染 A 的 document');
    assert(tooltipEl.innerHTML.indexOf('B内容') < 0);
});

test('kshop owned：requestInventory 响应 document → ntt-doc + owned chrome', () => {
    reset();
    const { presenter, inventoryCallbacks } = makePresenter();
    const slot = { occupied: true, physicalSlot: 7, slotLease: 'L7',
        item: { name: 'ak', displayName: 'AK-47', icon: 'AK', majorType: '武器', quantity: 1 } };
    const node = attachNode();
    presenter.bindOwned(node, '背包', slot);
    node.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: node });
    const cb = inventoryCallbacks[7];
    assert(cb, 'owned fetch 应发出');
    cb({
        success: true,
        introHTML: '<b>legacy</b>', descHTML: '',
        iconName: 'AK',
        document: DOC
    });
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('ntt-doc') >= 0);
    assert(html.indexOf('inventory-owned-tt-context') >= 0, 'owned rootClass 保留');
});

test('kshop showItemDetail：pinned 链路 document 随 cache 对象到位', () => {
    reset();
    const { presenter, shopCallbacks } = makePresenter();
    const anchor = attachNode();
    presenter.showItemDetail(8, anchor);
    assert(shopCallbacks[8], 'pinned fetch 应发出');
    shopCallbacks[8]({
        success: true,
        introHTML: '<b>legacy-pinned</b>',
        descHTML: '',
        document: { version: 1, title: 'PIN文档',
            sections: [{ role: 'body', runs: [{ text: 'pinned文档内容' }] }] }
    });
    // pinned 内容渲染在 inspector body 子元素内（假 DOM 不序列化 children 进
    // tooltipEl.innerHTML，须定位 body 元素断言）
    const body = findDesc(tooltipEl,
        n => (n.className || '').indexOf('panel-tooltip-inspector-body') >= 0);
    assert(body, 'pinned inspector body 应存在');
    assert(body.innerHTML.indexOf('pinned文档内容') >= 0,
        'pinned updateContent 应渲染 document');
    assert(body.innerHTML.indexOf('ntt-doc') >= 0);
    assert(body.innerHTML.indexOf('legacy-pinned') < 0);
    // 缓存的 rich 对象带 document：再次 showItemDetail 走 cache 仍是 document
    reset();
    presenter.showItemDetail(8, anchor);
    const body2 = findDesc(tooltipEl,
        n => (n.className || '').indexOf('panel-tooltip-inspector-body') >= 0);
    assert(body2 && body2.innerHTML.indexOf('pinned文档内容') >= 0,
        'cache 命中路径同样渲染 document');
});

// ── inventory-workbench-owned-view（真实生产模块）──

test('owned-view richTooltip：data.document 接管且 rootClass/layout 保留', () => {
    const item = { name: 'm4', displayName: 'M4', icon: 'M4', majorType: '武器' };
    const html = OwnedView.richTooltip(item, {
        introHTML: '<b>legacy</b>', descHTML: '',
        iconName: 'M4A1', itemType: '武器',
        document: DOC
    }, PanelTooltip);
    assert(html.indexOf('ntt-doc') >= 0);
    assert(html.indexOf('inventory-owned-tt-context') >= 0);
    assert(html.indexOf('legacy') < 0);
});

test('owned-view richTooltip：无 document → legacy 原样', () => {
    const html = OwnedView.richTooltip({ name: 'x', displayName: 'X' }, {
        introHTML: '<b>旧X</b>', descHTML: '旧desc'
    }, PanelTooltip);
    assert(html.indexOf('ntt-doc') < 0);
    assert(html.indexOf('旧X') >= 0);
});

// ── character-build candidate tooltip（真实生产消费者 + 真实 mux 校验）──
// 回归：InventoryTask 自 document 化后在成功回包中多转发一个 document 键，
// 旧 validResponse 白名单（ownKeys 严格键数）不认 → mux 拒发回调 →
// 候选注释永停"加载中…"。

const CandidateTooltipApi = ctx.window.CF7 && ctx.window.CF7.CharacterBuildCandidateTooltip
    || ctx.window.CharacterBuildCandidateTooltip;
assert(CandidateTooltipApi && CandidateTooltipApi.CandidateTooltip,
    'character-build-candidate-tooltip.js 加载失败');
const CandidateTooltip = CandidateTooltipApi.CandidateTooltip;
const ResponseRouter = ctx.window.PanelRuntime.sharedResponseRouter;

const CANDIDATE_DOC = {
    version: 1, title: 'MACSIII', icon: { kind: 'item', name: 'MACSIII' },
    profile: 'dense', layoutType: 'wide',
    sections: [
        { role: 'intro', runs: [{ text: '武器 长枪\n$568299' }] },
        { role: 'description', runs: [{ text: '全自动链锯单元 M.A.C.S. III。' }] }
    ]
};

function newCandidateTip() {
    const sent = [];
    const tip = new CandidateTooltip({
        tooltip: PanelTooltip,
        send: function(message) { sent.push(message); return true; },
        timeoutMs: 60000
    });
    assert(tip.reset('ni03-panel', 7), 'reset 应开启会话');
    const node = attachNode();
    tip.bind(node, {
        key: 'cand-1', name: 'MACSIII', type: '武器',
        presentation: { displayName: 'MACSIII', icon: 'MACSIII', majorType: '武器' },
        raw: { source: { containerId: '背包', slot: 3, expectedLease: 'L3' } }
    });
    node.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: node });
    assert(tooltipEl.innerHTML.indexOf('加载中') >= 0, '回包前应处于加载态');
    assert.strictEqual(sent.length, 1, '应发出一条 tooltip 请求');
    return { tip, sent };
}

// 与 InventoryTask 真实封皮一致：TryNormalizeCharacterTooltipResponse 输出的
// 数据键 + RespondAsync 封皮键；extra 可注入 document / 未知键
function candidateResp(callId, extra) {
    const r = {
        type: 'panel_resp', panel: 'workbench', domain: 'inventory',
        cmd: 'tooltip', callId, panelInstanceId: 'ni03-panel',
        success: true, v: 1,
        itemName: 'MACSIII', displayname: 'MACSIII', iconName: 'MACSIII',
        itemType: '武器',
        descHTML: 'legacy-desc-占位', introHTML: '<b>legacy-intro-占位</b>'
    };
    if (extra) for (const k in extra) r[k] = extra[k];
    return r;
}

test('character-build candidate：真实回包带 document → 回调交付并离开加载态', () => {
    reset();
    const { tip, sent } = newCandidateTip();
    ResponseRouter.handleResponse(candidateResp(sent[0].callId, { document: CANDIDATE_DOC }));
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('加载中') < 0, 'document 回包后应离开加载态');
    assert(html.indexOf('ntt-doc') >= 0, '应走 document 渲染');
    assert(html.indexOf('全自动链锯单元') >= 0, 'document 文本应渲染');
    tip.destroy();
});

test('character-build candidate：HTML-only 回包（无 document）→ legacy 正常渲染', () => {
    reset();
    const { tip, sent } = newCandidateTip();
    ResponseRouter.handleResponse(candidateResp(sent[0].callId));
    const html = tooltipEl.innerHTML;
    assert(html.indexOf('加载中') < 0, 'HTML-only 回包后应离开加载态');
    assert(html.indexOf('legacy-intro-占位') >= 0 || html.indexOf('legacy-desc-占位') >= 0,
        'legacy HTML 应渲染');
    tip.destroy();
});

test('character-build candidate：回包混入未知键 → 拒绝并留在加载态', () => {
    reset();
    const { tip, sent } = newCandidateTip();
    ResponseRouter.handleResponse(candidateResp(sent[0].callId,
        { document: CANDIDATE_DOC, evil: 1 }));
    assert(tooltipEl.innerHTML.indexOf('加载中') >= 0, '畸形响应不得离开加载态');
    assert(tooltipEl.innerHTML.indexOf('ntt-doc') < 0, '畸形响应不得渲染 document');
    tip.destroy();
});

// ── npcshop-secondary-pages（真实生产模块）──

test('npcshop tooltipRich：rich.document 接管且 metaHTML/rootClass 保留', () => {
    const Workbench = ctx.window.WorkbenchPrimitives;
    const html = SecondaryPages.tooltipRich(
        { name: 'n', displayName: 'N物', icon: 'n', majorType: '材料', price: 5 },
        { introHTML: '<b>legacy</b>', descHTML: '', document: DOC },
        PanelTooltip, Workbench);
    assert(html.indexOf('ntt-doc') >= 0);
    assert(html.indexOf('npcshop-tooltip') >= 0, 'rootClass 保留');
    assert(html.indexOf('legacy') < 0);
});

reset();
console.log('\n' + passed + ' tests passed');
