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
    assert.deepStrictEqual(Object.keys(Focus).sort(), ['FocusScope', 'debugActiveCount', 'focusables']);
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
