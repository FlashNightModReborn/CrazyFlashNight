'use strict';

const assert = require('assert');
const Focus = require('../launcher/web/modules/workbench-focus.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

class FakeNode {
    constructor(tagName, ownerDocument) {
        this.nodeType = 1;
        this.tagName = String(tagName || 'div').toUpperCase();
        this.ownerDocument = ownerDocument;
        this.parentNode = null;
        this.children = [];
        this.attributes = {};
        this.disabled = false;
        this.hidden = false;
        this.inert = false;
        this.focusCalls = [];
        this.listeners = {};
    }
    appendChild(node) {
        if (node.parentNode) node.parentNode.removeChild(node);
        node.parentNode = this;
        this.children.push(node);
        return node;
    }
    removeChild(node) {
        const index = this.children.indexOf(node);
        if (index >= 0) this.children.splice(index, 1);
        node.parentNode = null;
        return node;
    }
    contains(node) {
        for (let current = node; current; current = current.parentNode) {
            if (current === this) return true;
        }
        return false;
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
    }
    hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(type, handler, options) {
        (this.listeners[type] = this.listeners[type] || []).push({handler, options});
    }
    removeEventListener(type, handler, options) {
        const list = this.listeners[type] || [];
        const index = list.findIndex(entry => entry.handler === handler && entry.options === options);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type, init) {
        const event = Object.assign({
            type,
            target:this,
            key:'',
            preventDefault() { this.defaultPrevented = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(entry => entry.handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
    focus(options) {
        this.focusCalls.push(options);
        this.ownerDocument.activeElement = this;
    }
    _descendants() {
        const result = [];
        function visit(node) {
            node.children.forEach(child => {
                result.push(child);
                visit(child);
            });
        }
        visit(this);
        return result;
    }
    querySelectorAll() {
        return this._descendants().filter(node => {
            const tag = node.tagName;
            if ((tag === 'BUTTON' || tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA')
                    && !node.disabled) return true;
            if (tag === 'A' && node.hasAttribute('href')) return true;
            if (node.hasAttribute('tabindex') && node.getAttribute('tabindex') !== '-1') return true;
            return node.getAttribute('contenteditable') === 'true';
        });
    }
    querySelector(selector) {
        selector = String(selector || '');
        return this._descendants().find(node => {
            if (selector.charAt(0) === '#') return node.getAttribute('id') === selector.slice(1);
            if (selector.charAt(0) === '.') {
                const classes = String(node.getAttribute('class') || '').split(/\s+/);
                return classes.indexOf(selector.slice(1)) >= 0;
            }
            return node.tagName === selector.toUpperCase();
        }) || null;
    }
}

class FakeDocument {
    constructor() {
        this.listeners = {};
        this.documentElement = new FakeNode('html', this);
        this.body = new FakeNode('body', this);
        this.documentElement.appendChild(this.body);
        this.activeElement = this.body;
    }
    createElement(tagName) { return new FakeNode(tagName, this); }
    addEventListener(type, handler, options) {
        (this.listeners[type] = this.listeners[type] || []).push({handler, options});
    }
    removeEventListener(type, handler, options) {
        const list = this.listeners[type] || [];
        const index = list.findIndex(entry => entry.handler === handler && entry.options === options);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type, init) {
        const event = Object.assign({
            type,
            target:this.activeElement,
            key:'',
            shiftKey:false,
            preventDefault() { this.defaultPrevented = true; },
            stopPropagation() { this.propagationStopped = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(entry => entry.handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
}

function fixture() {
    const document = new FakeDocument();
    const underlay = document.createElement('main');
    const opener = document.createElement('button');
    underlay.appendChild(opener);
    const root = document.createElement('section');
    document.body.appendChild(underlay);
    document.body.appendChild(root);
    opener.focus();
    return {document, underlay, opener, root};
}

function assertNoActiveScopes() {
    assert.strictEqual(Focus.debugActiveCount(), 0, 'focus scope leaked between tests');
}

test('exports FocusScope helpers', () => {
    assert.deepStrictEqual(Object.keys(Focus).sort(), ['FocusScope', 'RovingGridFocus', 'debugActiveCount', 'focusables']);
    assertNoActiveScopes();
});

function rovingItem(document, key, tabindex) {
    const item = document.createElement('button');
    item.setAttribute('data-roving-key', key);
    if (tabindex != null) item.setAttribute('tabindex', tabindex);
    return item;
}

test('RovingGridFocus owns one tab stop and follows column-aware arrow keys', () => {
    const {document, root} = fixture();
    const items = ['a','b','c','d','e','f'].map(key => {
        const item = rovingItem(document, key);
        root.appendChild(item);
        return item;
    });
    const changes = [];
    const grid = new Focus.RovingGridFocus({
        root,
        document,
        columns:3,
        items:() => root.children,
        onActiveChange:key => changes.push(key)
    });
    assert.deepStrictEqual(items.map(item => item.getAttribute('tabindex')), ['0','-1','-1','-1','-1','-1']);
    items[0].focus();
    root.dispatch('focusin', {target:items[0]});
    const right = root.dispatch('keydown', {target:items[0], key:'ArrowRight'});
    assert.strictEqual(right.defaultPrevented, true);
    assert.strictEqual(document.activeElement, items[1]);
    root.dispatch('keydown', {target:items[1], key:'ArrowDown'});
    assert.strictEqual(document.activeElement, items[4]);
    root.dispatch('keydown', {target:items[4], key:'ArrowLeft'});
    assert.strictEqual(document.activeElement, items[3]);
    root.dispatch('keydown', {target:items[3], key:'ArrowUp'});
    assert.strictEqual(document.activeElement, items[0]);
    root.dispatch('keydown', {target:items[0], key:'ArrowLeft'});
    assert.strictEqual(document.activeElement, items[0], 'left edge must not wrap into another row');
    assert.deepStrictEqual(changes, ['b','e','d','a']);
    grid.destroy();
    assertNoActiveScopes();
});

test('RovingGridFocus accepts explicit irregular adjacency without spatial inference', () => {
    const {document, root} = fixture();
    const head = rovingItem(document, 'head');
    const neck = rovingItem(document, 'neck');
    const body = rovingItem(document, 'body');
    [head, neck, body].forEach(item => root.appendChild(item));
    const grid = new Focus.RovingGridFocus({
        root,
        document,
        items:() => root.children,
        neighbors:{
            head:{down:'body', right:'neck'},
            neck:{left:'head', down:'body'},
            body:{up:'head'}
        }
    });
    grid.setActive('head');
    root.dispatch('keydown', {target:head, key:'ArrowDown'});
    assert.strictEqual(grid.getActiveKey(), 'body');
    root.dispatch('keydown', {target:body, key:'ArrowUp'});
    assert.strictEqual(grid.getActiveKey(), 'head');
    root.dispatch('keydown', {target:head, key:'ArrowRight'});
    assert.strictEqual(grid.getActiveKey(), 'neck');
    root.dispatch('keydown', {target:neck, key:'ArrowRight'});
    assert.strictEqual(grid.getActiveKey(), 'neck', 'missing explicit edge must stay put');
    grid.destroy();
    assertNoActiveScopes();
});

test('RovingGridFocus restores a stable key after DOM replacement and tears down exactly', () => {
    const {document, root} = fixture();
    const originalA = rovingItem(document, 'a', '5');
    const originalB = rovingItem(document, 'b');
    root.appendChild(originalA);
    root.appendChild(originalB);
    const grid = new Focus.RovingGridFocus({root, document, columns:2, items:() => root.children});
    grid.setActive('b');
    assert.strictEqual(document.activeElement, originalB);

    root.removeChild(originalA);
    root.removeChild(originalB);
    const nextA = rovingItem(document, 'a');
    const nextB = rovingItem(document, 'b');
    root.appendChild(nextA);
    root.appendChild(nextB);
    assert.strictEqual(grid.refresh({focus:true}), true);
    assert.strictEqual(grid.getActiveKey(), 'b');
    assert.strictEqual(document.activeElement, nextB);
    assert.strictEqual(nextB.getAttribute('tabindex'), '0');
    assert.strictEqual(originalA.getAttribute('tabindex'), '5', 'detached nodes are restored during refresh');
    assert.strictEqual(root.listenerCount('keydown'), 1);
    assert.strictEqual(root.listenerCount('focusin'), 1);

    assert.strictEqual(grid.destroy(), true);
    assert.strictEqual(grid.destroy(), false);
    assert.strictEqual(root.listenerCount('keydown'), 0);
    assert.strictEqual(root.listenerCount('focusin'), 0);
    assert.strictEqual(originalA.getAttribute('tabindex'), '5');
    assert.strictEqual(nextA.hasAttribute('tabindex'), false);
    assert.strictEqual(grid.refresh(), false);
    assertNoActiveScopes();
});

test('initialFocus resolves selectors and falls back from an unfocusable target', () => {
    const {document, root} = fixture();
    const fallback = document.createElement('button');
    const preferred = document.createElement('button');
    preferred.setAttribute('class', 'preferred');
    root.appendChild(fallback);
    root.appendChild(preferred);
    const scope = new Focus.FocusScope({root, document, initialFocus:'.preferred'});

    assert.strictEqual(scope.activate(), true);
    assert.strictEqual(document.activeElement, preferred);
    assert.deepStrictEqual(preferred.focusCalls[0], {preventScroll:true});
    assert.strictEqual(scope.deactivate('first'), true);

    preferred.setAttribute('aria-disabled', 'true');
    assert.strictEqual(scope.activate({initialFocus:preferred}), true);
    assert.strictEqual(document.activeElement, fallback);
    scope.destroy();
    assertNoActiveScopes();
});

test('Tab and Shift+Tab wrap inside the top scope', () => {
    const {document, root} = fixture();
    const first = document.createElement('button');
    const middle = document.createElement('button');
    const last = document.createElement('a');
    last.setAttribute('href', '#last');
    root.appendChild(first);
    root.appendChild(middle);
    root.appendChild(last);
    const scope = new Focus.FocusScope({root, document});
    scope.activate();

    last.focus();
    const forward = document.dispatch('keydown', {key:'Tab'});
    assert.strictEqual(forward.defaultPrevented, true);
    assert.strictEqual(document.activeElement, first);

    const backward = document.dispatch('keydown', {key:'Tab', shiftKey:true});
    assert.strictEqual(backward.defaultPrevented, true);
    assert.strictEqual(document.activeElement, last);

    const outside = document.createElement('button');
    document.body.appendChild(outside);
    outside.focus();
    document.dispatch('focusin', {target:outside});
    assert.strictEqual(document.activeElement, first);

    scope.destroy();
    assertNoActiveScopes();
});

test('Escape invokes the callback, supports veto, and otherwise deactivates', () => {
    const {document, opener, root} = fixture();
    const button = document.createElement('button');
    root.appendChild(button);
    let calls = 0;
    const scope = new Focus.FocusScope({
        root,
        document,
        onEscape(event, activeScope) {
            calls++;
            assert.strictEqual(activeScope, scope);
            return calls === 1 ? false : undefined;
        }
    });
    scope.activate();

    const vetoed = document.dispatch('keydown', {key:'Escape'});
    assert.strictEqual(calls, 1);
    assert.strictEqual(scope.isActive(), true);
    assert.strictEqual(vetoed.defaultPrevented, true);
    assert.strictEqual(vetoed.propagationStopped, true);

    const accepted = document.dispatch('keydown', {key:'Escape'});
    assert.strictEqual(calls, 2);
    assert.strictEqual(scope.isActive(), false);
    assert.strictEqual(accepted.defaultPrevented, true);
    assert.strictEqual(document.activeElement, opener);
    scope.destroy();
    assertNoActiveScopes();
});

test('an active field draft owns only the first Escape inside its focus scope', () => {
    const {document, root} = fixture();
    const input = document.createElement('input');
    input.setAttribute('data-workbench-escape-owner', 'field');
    root.appendChild(input);
    const outside = document.createElement('input');
    outside.setAttribute('data-workbench-escape-owner', 'field');
    document.body.appendChild(outside);
    let calls = 0;
    const scope = new Focus.FocusScope({
        root,
        document,
        onEscape() { calls++; }
    });
    scope.activate({initialFocus:input});

    const delegated = document.dispatch('keydown', {key:'Escape', target:input});
    assert.strictEqual(calls, 0);
    assert.strictEqual(scope.isActive(), true);
    assert.strictEqual(delegated.defaultPrevented, undefined);
    assert.strictEqual(delegated.propagationStopped, undefined);

    input.removeAttribute('data-workbench-escape-owner');
    const accepted = document.dispatch('keydown', {key:'Escape', target:input});
    assert.strictEqual(calls, 1);
    assert.strictEqual(scope.isActive(), false);
    assert.strictEqual(accepted.defaultPrevented, true);

    scope.activate({initialFocus:input});
    const external = document.dispatch('keydown', {key:'Escape', target:outside});
    assert.strictEqual(calls, 2, 'an external draft marker must not intercept the scope Escape');
    assert.strictEqual(scope.isActive(), false);
    assert.strictEqual(external.defaultPrevented, true);
    scope.destroy();
    assertNoActiveScopes();
});

test('underlay inert and aria-hidden state is restored exactly', () => {
    const {document, underlay, root} = fixture();
    const secondUnderlay = document.createElement('aside');
    document.body.appendChild(secondUnderlay);
    underlay.setAttribute('aria-hidden', 'false');
    underlay.inert = false;
    secondUnderlay.setAttribute('aria-hidden', 'legacy');
    secondUnderlay.setAttribute('inert', '');
    secondUnderlay.inert = true;
    const scope = new Focus.FocusScope({root, document, underlay:[underlay, secondUnderlay]});

    scope.activate();
    assert.strictEqual(underlay.inert, true);
    assert.strictEqual(underlay.getAttribute('inert'), '');
    assert.strictEqual(underlay.getAttribute('aria-hidden'), 'true');
    assert.strictEqual(secondUnderlay.inert, true);
    assert.strictEqual(secondUnderlay.getAttribute('aria-hidden'), 'true');

    scope.deactivate('close');
    assert.strictEqual(underlay.inert, false);
    assert.strictEqual(underlay.hasAttribute('inert'), false);
    assert.strictEqual(underlay.getAttribute('aria-hidden'), 'false');
    assert.strictEqual(secondUnderlay.inert, true);
    assert.strictEqual(secondUnderlay.hasAttribute('inert'), true);
    assert.strictEqual(secondUnderlay.getAttribute('aria-hidden'), 'legacy');
    scope.destroy();
    assertNoActiveScopes();
});

test('context opener overrides activeElement and is restored on deactivate', () => {
    const {document, root} = fixture();
    const activeBeforeOpen = document.createElement('button');
    const explicitOpener = document.createElement('button');
    const initial = document.createElement('button');
    document.body.appendChild(activeBeforeOpen);
    document.body.appendChild(explicitOpener);
    root.appendChild(initial);
    activeBeforeOpen.focus();
    const scope = new Focus.FocusScope({root, document});

    scope.activate({opener:explicitOpener});
    assert.strictEqual(document.activeElement, initial);
    scope.deactivate('done');
    assert.strictEqual(document.activeElement, explicitOpener);
    assert.strictEqual(explicitOpener.focusCalls.length, 1);
    scope.destroy();
    assertNoActiveScopes();
});

test('nested scopes give the child top priority and unwind child-first', () => {
    const {document, underlay, opener, root:outerRoot} = fixture();
    const outerButton = document.createElement('button');
    const innerRoot = document.createElement('section');
    const innerButton = document.createElement('button');
    outerRoot.appendChild(outerButton);
    outerRoot.appendChild(innerRoot);
    innerRoot.appendChild(innerButton);
    const outer = new Focus.FocusScope({root:outerRoot, document, underlay});
    const inner = new Focus.FocusScope({root:innerRoot, document, underlay:outerButton});

    outer.activate();
    inner.activate({opener:outerButton});
    assert.strictEqual(Focus.debugActiveCount(), 2);
    assert.strictEqual(document.activeElement, innerButton);
    document.dispatch('keydown', {key:'Escape'});
    assert.strictEqual(inner.isActive(), false);
    assert.strictEqual(outer.isActive(), true);
    assert.strictEqual(Focus.debugActiveCount(), 1);
    assert.strictEqual(document.activeElement, outerButton);

    inner.activate({opener:outerButton});
    assert.strictEqual(Focus.debugActiveCount(), 2);
    outer.deactivate('ancestor-close');
    assert.strictEqual(inner.isActive(), false);
    assert.strictEqual(outer.isActive(), false);
    assert.strictEqual(Focus.debugActiveCount(), 0);
    assert.strictEqual(document.activeElement, opener);
    assert.strictEqual(underlay.inert, false);
    assert.strictEqual(outerButton.inert, false);

    inner.destroy();
    outer.destroy();
    assertNoActiveScopes();
});

test('destroy is idempotent and releases listeners, temporary tabindex, and activation', () => {
    const {document, root} = fixture();
    const scope = new Focus.FocusScope({root, document});
    scope.activate();
    assert.strictEqual(document.activeElement, root);
    assert.strictEqual(root.getAttribute('tabindex'), '-1');
    assert.strictEqual(document.listenerCount('keydown'), 1);
    assert.strictEqual(document.listenerCount('focusin'), 1);

    assert.strictEqual(scope.destroy(), true);
    assert.strictEqual(scope.destroy(), false);
    assert.strictEqual(scope.deactivate('late'), false);
    assert.strictEqual(scope.activate(), false);
    assert.strictEqual(root.hasAttribute('tabindex'), false);
    assert.strictEqual(document.listenerCount('keydown'), 0);
    assert.strictEqual(document.listenerCount('focusin'), 0);
    assertNoActiveScopes();
});

process.stdout.write('workbench focus: ' + passed + '/' + passed + ' passed\n');
