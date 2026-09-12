'use strict';

// 定向 Node 测试：tooltip.js 的 COMMON document 集成（vm + 最小假 DOM）。
// 覆盖 buildItemRichHtml({document})、bindAsync document 模式、owner/迟到回包
// 拒绝、showDocument* 入口与 pinned 标题。不启动浏览器/游戏。

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const PanelTooltipDocument = require('../launcher/web/modules/tooltip-document.js');

let passed = 0;
function test(name, run) {
    run();
    passed++;
    process.stdout.write('ok - ' + name + '\n');
}

// ── 最小假 DOM ──

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
        querySelector(sel) {
            return findDesc(this, n => matchSel(n, sel));
        },
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
    // 支持 '.a, .b' 逗号组与单 '.class' / 'tag' token——够 tooltip.js 内部用
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
const headEl = makeEl('head');
const appendedScripts = [];
const documentStub = {
    readyState: 'complete',
    currentScript: { src: 'https://cf7.local/web/modules/tooltip.js' },
    documentElement: documentEl,
    head: headEl,
    body: makeEl('body'),
    activeElement: null,
    getElementById(id) { return id === 'panel-tooltip' ? tooltipEl : null; },
    createElement(tag) {
        const el = makeEl(tag);
        if (tag === 'script') appendedScripts.push(el);
        return el;
    },
    querySelectorAll() { return []; },
    addEventListener() {}, removeEventListener() {},
    elementFromPoint() { return null; }
};
documentEl.contains = n => n === tooltipEl || tooltipEl.contains(n) || n === documentEl;

const windowStub = {
    innerWidth: 1024, innerHeight: 576,
    addEventListener() {}, removeEventListener() {}
    // 故意不提供 PointerEvent → bindAsync 走 mouse 事件路径
};

const src = fs.readFileSync(
    path.join(__dirname, '..', 'launcher', 'web', 'modules', 'tooltip.js'), 'utf8');

function loadTooltip(withDocModule) {
    const ctx = {
        document: documentStub,
        window: windowStub,
        setTimeout: setTimeout,
        clearTimeout: clearTimeout,
        requestAnimationFrame: function(f) { f(); return 0; },
        Date: Date,
        console: console
    };
    if (withDocModule) ctx.PanelTooltipDocument = PanelTooltipDocument;
    ctx.globalThis = ctx;
    vm.createContext(ctx);
    return vm.runInContext(src + '\n;PanelTooltip', ctx);
}

// 先在无 PanelTooltipDocument 的环境加载：验证 init 自动注入同目录模块
const PanelTooltipBootstrap = loadTooltip(false);
const PanelTooltip = loadTooltip(true);

const DOC = {
    version: 1,
    title: 'M4A1-消音',
    icon: { kind: 'item', name: 'M4A1' },
    profile: 'dense',
    sections: [
        { role: 'intro', runs: [{ text: '武器    步枪' }] },
        { role: 'description', runs: [{ text: '说明。' }] }
    ]
};

function reset() {
    PanelTooltip.hide();
    tooltipEl._innerHTML = '';
    tooltipEl.children = [];
}

// ── 加载与基础入口 ──

test('init 自动注入同目录 tooltip-document.js（模块缺席时）', () => {
    // PanelTooltipBootstrap 在无 PanelTooltipDocument 的 ctx 中加载 → 触发注入
    assert.strictEqual(appendedScripts.length, 1);
    assert.strictEqual(appendedScripts[0].src,
        'https://cf7.local/web/modules/tooltip-document.js');
    // 模块缺席时 document 入口安全回落
    assert.strictEqual(PanelTooltipBootstrap.normalizeDocument(DOC), null);
    assert.strictEqual(PanelTooltipBootstrap.buildDocumentHtml(DOC), '');
    assert.strictEqual(PanelTooltipBootstrap.showDocumentAtMouse(
        DOC, { clientX: 1, clientY: 1 }, {}), false);
    // 注入只发生一次（主 ctx 里模块已就位，不再重复注入）
    assert.strictEqual(appendedScripts.length, 1);
});

test('buildItemRichHtml({document})：document 优先，chrome 透传', () => {
    const html = PanelTooltip.buildItemRichHtml({
        document: DOC,
        introHTML: '<b>legacy-不应出现</b>',
        metaHTML: '<span class="m">meta行</span>',
        suffix: '<div class="s">锁定</div>'
    });
    assert(html.indexOf('ntt-doc') >= 0);
    assert(html.indexOf('legacy-不应出现') < 0);
    assert(html.indexOf('meta行') >= 0);
    assert(html.indexOf('锁定') >= 0);
});

test('buildItemRichHtml({document})：无效 document 回落 legacy', () => {
    const html = PanelTooltip.buildItemRichHtml({
        document: { version: 9 },
        introHTML: '<b>legacy-回落</b>'
    });
    assert(html.indexOf('ntt-doc') < 0);
    assert(html.indexOf('legacy-回落') >= 0);
});

test('normalizeDocument / buildDocumentHtml 直通', () => {
    assert(PanelTooltip.normalizeDocument(DOC));
    assert.strictEqual(PanelTooltip.normalizeDocument({ version: 9, title: 'x' }), null);
    assert(PanelTooltip.buildDocumentHtml(DOC).indexOf('ntt-doc') >= 0);
});

test('showDocumentAtMouse：显示 + profile 映射 dense→dense-inspect', () => {
    reset();
    const owner = {};
    const ok = PanelTooltip.showDocumentAtMouse(DOC,
        { clientX: 100, clientY: 100 }, owner);
    assert.strictEqual(ok, true);
    assert.strictEqual(tooltipEl._attrs['data-tooltip-profile'], 'dense-inspect');
    assert(tooltipEl.innerHTML.indexOf('ntt-doc') >= 0);
    assert.strictEqual(PanelTooltip.isVisible(owner), true);
});

test('showDocumentAtMouse：非法 document 返回 false，不动当前显示', () => {
    reset();
    const owner = {};
    PanelTooltip.showDocumentAtMouse(DOC, { clientX: 1, clientY: 1 }, owner);
    const before = tooltipEl.innerHTML;
    assert.strictEqual(PanelTooltip.showDocumentAtMouse(
        { version: 9, title: 'x' }, { clientX: 5, clientY: 5 }, {}), false);
    assert.strictEqual(tooltipEl.innerHTML, before);
});

test('showDocumentPinned：pinned profile + header 标题取 doc.title', () => {
    reset();
    const anchor = makeEl('div');
    const ok = PanelTooltip.showDocumentPinned(DOC, anchor, { owner: {} });
    assert.strictEqual(ok, true);
    assert.strictEqual(tooltipEl._attrs['data-tooltip-profile'], 'pinned-inspector');
    const title = findDesc(tooltipEl,
        n => (n.className || '').indexOf('panel-tooltip-inspector-title') >= 0);
    assert(title, 'pinned shell header 应存在');
    assert.strictEqual(title.textContent, 'M4A1-消音');
    const body = findDesc(tooltipEl,
        n => (n.className || '').indexOf('panel-tooltip-inspector-body') >= 0);
    assert(body.innerHTML.indexOf('ntt-doc') >= 0);
});

test('updateContentDocument：owner 匹配才刷新；不匹配拒绝', () => {
    reset();
    const owner = {};
    PanelTooltip.showDocumentAtMouse(DOC, { clientX: 1, clientY: 1 }, owner);
    const ok = PanelTooltip.updateContentDocument(
        { version: 1, title: '新标题', sections: [{ role: 'body', runs: [{ text: '新内容' }] }] },
        owner);
    assert.strictEqual(ok, true);
    assert(tooltipEl.innerHTML.indexOf('新内容') >= 0);
    const before = tooltipEl.innerHTML;
    assert.strictEqual(PanelTooltip.updateContentDocument(
        { version: 1, title: 'x', sections: [{ role: 'body', runs: [{ text: '不应出现' }] }] },
        {}), false);
    assert.strictEqual(tooltipEl.innerHTML, before);
});

// ── bindAsync document 模式 ──

test('bindAsync document:"prefer"：回包 document 渲染，迟到回包拒绝', () => {
    reset();
    const nodeA = makeEl('div');
    const nodeB = makeEl('div');
    const fetchCbs = { a: null, b: null };
    const bindOpts = (store, key) => ({
        key: key,
        item: { name: key },
        document: 'prefer',
        renderBasic: () => '<b>basic-' + key + '</b>',
        renderRich: () => '<b>legacy-' + key + '</b>',
        fetch: (item, cb) => { store.cb = cb; }
    });
    const storeA = { cb: null }, storeB = { cb: null };
    PanelTooltip.bindAsync(nodeA, bindOpts(storeA, 'ka'));
    PanelTooltip.bindAsync(nodeB, bindOpts(storeB, 'kb'));

    nodeA.dispatch('mouseenter', { clientX: 10, clientY: 10, currentTarget: nodeA });
    assert(tooltipEl.innerHTML.indexOf('basic-ka') >= 0);
    // A 的 document 回包 → document 渲染
    storeA.cb({ success: true, document: DOC, descHTML: 'ignored' });
    assert(tooltipEl.innerHTML.indexOf('ntt-doc') >= 0);
    assert(tooltipEl.innerHTML.indexOf('M4A1-消音') >= 0);

    // B 接管 → A 的迟到回包不得覆盖
    nodeA.dispatch('mouseleave', {});
    nodeB.dispatch('mouseenter', { clientX: 50, clientY: 50, currentTarget: nodeB });
    assert(tooltipEl.innerHTML.indexOf('basic-kb') >= 0);
    const before = tooltipEl.innerHTML;
    // A 再来一个回包（模拟迟到）——A 已不是 owner
    storeA.cb({ success: true, document: { version: 1, title: '迟到', sections: [{ role: 'body', runs: [{ text: '迟到内容' }] }] } });
    assert.strictEqual(tooltipEl.innerHTML, before, '迟到回包不得覆盖 B 的内容');
});

test('bindAsync document 未开启：响应带 document 仍走 renderRich（向后兼容）', () => {
    reset();
    const node = makeEl('div');
    const store = { cb: null };
    PanelTooltip.bindAsync(node, {
        key: 'k', item: {},
        renderBasic: () => 'basic',
        renderRich: () => '<b>legacy-rich</b>',
        fetch: (i, cb) => { store.cb = cb; }
    });
    node.dispatch('mouseenter', { clientX: 5, clientY: 5, currentTarget: node });
    store.cb({ success: true, document: DOC });
    assert(tooltipEl.innerHTML.indexOf('legacy-rich') >= 0);
    assert(tooltipEl.innerHTML.indexOf('ntt-doc') < 0);
});

test('bindAsync document:"only"：无效 document → renderFailure', () => {
    reset();
    const node = makeEl('div');
    const store = { cb: null };
    let failureRendered = false;
    PanelTooltip.bindAsync(node, {
        key: 'k', item: {},
        document: 'only',
        renderBasic: () => 'basic',
        renderRich: () => '<b>不应出现</b>',
        renderFailure: () => { failureRendered = true; return '<i>fail</i>'; },
        fetch: (i, cb) => { store.cb = cb; }
    });
    node.dispatch('mouseenter', { clientX: 5, clientY: 5, currentTarget: node });
    store.cb({ success: true, document: { version: 9, title: 'bad' } });
    assert(failureRendered, 'only 模式下无效 document 应走 renderFailure');
    assert(tooltipEl.innerHTML.indexOf('fail') >= 0);
    assert(tooltipEl.innerHTML.indexOf('不应出现') < 0);
});

test('bindAsync renderDocument 自定义渲染器优先', () => {
    reset();
    const node = makeEl('div');
    const store = { cb: null };
    let sawDoc = null;
    PanelTooltip.bindAsync(node, {
        key: 'k', item: { name: '项' },
        document: true,
        renderDocument: (item, doc, response) => {
            sawDoc = doc;
            return '<div class="custom-doc">' + doc.title + '/chrome</div>';
        },
        renderBasic: () => 'basic',
        renderRich: () => 'legacy',
        fetch: (i, cb) => { store.cb = cb; }
    });
    node.dispatch('mouseenter', { clientX: 5, clientY: 5, currentTarget: node });
    store.cb({ success: true, document: DOC });
    assert(sawDoc, 'renderDocument 应收到归一化 doc');
    assert.strictEqual(sawDoc.title, 'M4A1-消音');
    assert(tooltipEl.innerHTML.indexOf('custom-doc') >= 0);
});

test('bindAsync：binding destroy 后回包拒绝（generation 守卫）', () => {
    reset();
    const node = makeEl('div');
    const store = { cb: null };
    const binding = PanelTooltip.bindAsync(node, {
        key: 'k', item: {},
        document: 'prefer',
        renderBasic: () => 'basic',
        fetch: (i, cb) => { store.cb = cb; }
    });
    node.dispatch('mouseenter', { clientX: 5, clientY: 5, currentTarget: node });
    binding.destroy();
    assert.strictEqual(PanelTooltip.isVisible(), false);
    store.cb({ success: true, document: DOC });
    assert.strictEqual(PanelTooltip.isVisible(), false, 'destroy 后迟到回包不得复活 tooltip');
});

test('hide(owner)：owner 不匹配拒绝', () => {
    reset();
    const owner = {};
    PanelTooltip.showDocumentAtMouse(DOC, { clientX: 1, clientY: 1 }, owner);
    assert.strictEqual(PanelTooltip.hide({}), false);
    assert.strictEqual(PanelTooltip.isVisible(owner), true);
    assert.strictEqual(PanelTooltip.hide(owner), true);
    assert.strictEqual(PanelTooltip.isVisible(), false);
});

reset();
console.log('\n' + passed + ' tests passed');
