'use strict';

const util = require('util');

const modulePaths = [
    '../launcher/web/modules/workbench-lifecycle.js',
    '../launcher/web/modules/workbench-focus.js',
    '../launcher/web/modules/workbench-primitives.js',
    '../launcher/web/modules/workbench-profile.js',
    '../launcher/web/modules/workbench-components.js',
    '../launcher/web/modules/workbench.js'
].map(require.resolve);

let passed = 0;
let failed = 0;

function printable(value) {
    return util.inspect(value, {depth:4, breakLength:120});
}

function test(name, fn) {
    const failures = [];
    const check = {
        equal(actual, expected, message) {
            if (actual !== expected) failures.push(message + ': expected ' + printable(expected) + ', got ' + printable(actual));
        },
        deepEqual(actual, expected, message) {
            if (!util.isDeepStrictEqual(actual, expected)) {
                failures.push(message + ': expected ' + printable(expected) + ', got ' + printable(actual));
            }
        },
        ok(value, message) {
            if (!value) failures.push(message + ': expected truthy, got ' + printable(value));
        },
        throws(fn, matcher, message) {
            try {
                fn();
                failures.push(message + ': expected an exception');
            } catch (error) {
                const rendered = String(error && error.message || error);
                if (matcher && !matcher.test(rendered)) {
                    failures.push(message + ': unexpected exception ' + printable(rendered));
                }
            }
        }
    };
    try {
        fn(check);
    } catch (error) {
        failures.push('unexpected exception: ' + (error && error.stack || error));
    }
    if (!failures.length) {
        passed++;
        process.stdout.write('ok ' + (passed + failed) + ' - ' + name + '\n');
        return;
    }
    failed++;
    process.stdout.write('not ok ' + (passed + failed) + ' - ' + name + '\n');
    failures.forEach((failure, index) => process.stdout.write('  ' + (index + 1) + ') ' + failure + '\n'));
}

class FakeClassList {
    constructor() { this.values = {}; }
    add(...names) { names.forEach(name => { if (name) this.values[name] = true; }); }
    remove(...names) { names.forEach(name => { delete this.values[name]; }); }
    contains(name) { return !!this.values[name]; }
    toggle(name, force) {
        const enabled = force == null ? !this.contains(name) : !!force;
        if (enabled) this.add(name); else this.remove(name);
        return enabled;
    }
}

function matchesAttribute(node, selector) {
    const match = selector.match(/^\[([^=\]]+)(?:=["']?([^"'\]]+)["']?)?\]$/);
    if (!match) return false;
    const value = node.getAttribute(match[1]);
    return value != null && (match[2] == null || value === match[2]);
}

function matchesSimple(node, selector) {
    selector = String(selector || '').trim();
    if (!selector || node.nodeType !== 1) return false;
    if (selector === '*') return true;
    if (selector.charAt(0) === '[') return matchesAttribute(node, selector);
    if (selector.charAt(0) === '.') {
        return selector.split('.').filter(Boolean).every(name => node.classList.contains(name));
    }
    const tagAndClasses = selector.split('.');
    if (tagAndClasses.length > 1) {
        return node.tagName === tagAndClasses.shift().toUpperCase()
            && tagAndClasses.every(name => node.classList.contains(name));
    }
    return node.tagName === selector.toUpperCase();
}

function matchesAny(node, selector) {
    return String(selector || '').split(',').some(part => matchesSimple(node, part));
}

class FakeTextNode {
    constructor(text, ownerDocument) {
        this.nodeType = 3;
        this.textContent = String(text);
        this.ownerDocument = ownerDocument;
        this.parentNode = null;
    }
}

class FakeNode {
    constructor(tagName, ownerDocument) {
        this.nodeType = 1;
        this.tagName = String(tagName || 'div').toUpperCase();
        this.ownerDocument = ownerDocument;
        this.parentNode = null;
        this.children = [];
        this.attributes = {};
        this.classList = new FakeClassList();
        this.listeners = {};
        this.style = {};
        this.disabled = false;
        this.hidden = false;
        this.inert = false;
        this.textContent = '';
        this.type = '';
        this._innerHTML = '';
        this.focusCalls = [];
    }
    get firstChild() { return this.children[0] || null; }
    get parentElement() { return this.parentNode && this.parentNode.nodeType === 1 ? this.parentNode : null; }
    get isConnected() {
        return !!(this.ownerDocument && this.ownerDocument.documentElement
            && this.ownerDocument.documentElement.contains(this));
    }
    set className(value) {
        this.classList = new FakeClassList();
        String(value || '').split(/\s+/).forEach(name => this.classList.add(name));
    }
    get className() { return Object.keys(this.classList.values).join(' '); }
    set innerHTML(value) {
        this._innerHTML = String(value || '');
        while (this.firstChild) this.removeChild(this.firstChild);
        const tagPattern = /<(b|span)\b([^>]*)>/gi;
        let match;
        while ((match = tagPattern.exec(this._innerHTML))) {
            const node = this.ownerDocument.createElement(match[1]);
            const classMatch = match[2].match(/class=["']([^"']+)["']/i);
            if (classMatch) node.className = classMatch[1];
            this.appendChild(node);
        }
    }
    get innerHTML() { return this._innerHTML; }
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
    remove() { if (this.parentNode) this.parentNode.removeChild(this); }
    contains(node) {
        for (let current = node; current; current = current.parentNode) {
            if (current === this) return true;
        }
        return false;
    }
    setAttribute(name, value) {
        this.attributes[name] = String(value);
        if (this.ownerDocument && this.ownerDocument.attributeMutations) {
            this.ownerDocument.attributeMutations.push({
                node:this,
                operation:'set',
                name:String(name),
                value:String(value)
            });
        }
    }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
    }
    hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
    removeAttribute(name) {
        delete this.attributes[name];
        if (this.ownerDocument && this.ownerDocument.attributeMutations) {
            this.ownerDocument.attributeMutations.push({
                node:this,
                operation:'remove',
                name:String(name)
            });
        }
    }
    matches(selector) { return matchesAny(this, selector); }
    closest(selector) {
        for (let current = this; current && current.nodeType === 1; current = current.parentNode) {
            if (matchesAny(current, selector)) return current;
        }
        return null;
    }
    _descendants() {
        const result = [];
        (function visit(node) {
            node.children.forEach(child => {
                if (child.nodeType !== 1) return;
                result.push(child);
                visit(child);
            });
        })(this);
        return result;
    }
    _focusableCandidate(node) {
        if ((node.tagName === 'BUTTON' || node.tagName === 'INPUT'
                || node.tagName === 'SELECT' || node.tagName === 'TEXTAREA') && !node.disabled) return true;
        if (node.tagName === 'A' && node.hasAttribute('href')) return true;
        if (node.hasAttribute('tabindex') && node.getAttribute('tabindex') !== '-1') return true;
        return node.getAttribute('contenteditable') === 'true';
    }
    querySelectorAll(selector) {
        const all = this._descendants();
        if (selector === '*') return all;
        if (String(selector).indexOf('button:not([disabled])') >= 0) {
            return all.filter(node => this._focusableCandidate(node));
        }
        return all.filter(node => matchesAny(node, selector));
    }
    querySelector(selector) {
        const parts = String(selector || '').trim().split(/\s+/);
        if (parts.length > 1) {
            const last = parts.pop();
            return this._descendants().find(node => {
                if (!matchesSimple(node, last)) return false;
                let ancestor = node.parentNode;
                for (let i = parts.length - 1; i >= 0; i--) {
                    while (ancestor && !matchesSimple(ancestor, parts[i])) ancestor = ancestor.parentNode;
                    if (!ancestor) return false;
                    ancestor = ancestor.parentNode;
                }
                return true;
            }) || null;
        }
        return this._descendants().find(node => matchesSimple(node, parts[0])) || null;
    }
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
            currentTarget:this,
            preventDefault() { this.defaultPrevented = true; },
            stopPropagation() { this.propagationStopped = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(entry => entry.handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
    _blockedByAncestor() {
        for (let current = this; current; current = current.parentNode) {
            if (current.hidden || current.inert || current.getAttribute && current.getAttribute('aria-hidden') === 'true') {
                return true;
            }
        }
        return false;
    }
    getClientRects() { return this._blockedByAncestor() ? [] : [{}]; }
    focus(options) {
        this.focusCalls.push(options);
        this.ownerDocument.activeElement = this;
    }
}

class FakeDocument {
    constructor() {
        this.listeners = {};
        this.createdElements = [];
        this.attributeMutations = [];
        this.documentElement = new FakeNode('html', this);
        this.body = new FakeNode('body', this);
        this.documentElement.appendChild(this.body);
        this.activeElement = this.body;
        this.defaultView = {
            getComputedStyle:node => ({
                display:node._blockedByAncestor() ? 'none' : 'block',
                visibility:node._blockedByAncestor() ? 'hidden' : 'visible'
            })
        };
    }
    createElement(tagName) {
        const node = new FakeNode(tagName, this);
        this.createdElements.push(node);
        return node;
    }
    createTextNode(text) { return new FakeTextNode(text, this); }
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

function loadEnvironment() {
    modulePaths.forEach(modulePath => { delete require.cache[modulePath]; });
    delete global.WorkbenchLifecycle;
    delete global.WorkbenchFocus;
    delete global.WorkbenchPrimitives;
    delete global.WorkbenchComponents;
    delete global.Workbench;
    delete global.CF7;
    const document = new FakeDocument();
    global.document = document;
    const Focus = require('../launcher/web/modules/workbench-focus.js');
    const Components = require('../launcher/web/modules/workbench-components.js');
    const Workbench = require('../launcher/web/modules/workbench.js');
    return {document, Focus, Components, Workbench};
}

function makeShell(environment) {
    const opener = environment.document.createElement('button');
    environment.document.body.appendChild(opener);
    opener.focus();
    const shell = new environment.Workbench.DualPaneShell({profile:'catalog-decision'});
    environment.document.body.appendChild(shell.getRoot());
    return {shell, opener};
}

function modalSpec(kind, onClose) {
    return {
        kind,
        actions:[{id:'confirm', label:'Confirm', primary:true}],
        onClose
    };
}

function assertScopeResources(check, environment, expected, label) {
    check.equal(environment.Focus.debugActiveCount(), expected, label + ' active scope count');
    check.equal(environment.document.listenerCount('keydown'), expected, label + ' keydown listener count');
    check.equal(environment.document.listenerCount('focusin'), expected, label + ' focusin listener count');
}

function assertRestored(check, node, label) {
    check.equal(node.inert, false, label + ' inert property restored');
    check.equal(node.hasAttribute('inert'), false, label + ' inert attribute restored');
    check.equal(node.hasAttribute('aria-hidden'), false, label + ' aria-hidden restored');
}

test('DualPaneShell requires a closed profile and switches it atomically', check => {
    const environment = loadEnvironment();
    function expectMissingProfileFailsBeforeDom(label, construct) {
        const createdBefore = environment.document.createdElements.length;
        const mutationsBefore = environment.document.attributeMutations.length;
        let missingError = null;
        try {
            construct();
        } catch (error) {
            missingError = error;
        }
        check.ok(missingError instanceof TypeError, label + ' fails with TypeError');
        check.equal(environment.document.createdElements.length, createdBefore,
            label + ' fails before creating an element');
        check.equal(environment.document.attributeMutations.length, mutationsBefore,
            label + ' fails before mutating an attribute');
    }
    expectMissingProfileFailsBeforeDom('omitted constructor options', () => {
        new environment.Workbench.DualPaneShell();
    });
    expectMissingProfileFailsBeforeDom('empty constructor options', () => {
        new environment.Workbench.DualPaneShell({});
    });
    expectMissingProfileFailsBeforeDom('unknown constructor profile', () => {
        new environment.Workbench.DualPaneShell({profile:'feature-magic'});
    });

    const constructorMutationStart = environment.document.attributeMutations.length;
    const {shell} = makeShell(environment);
    const root = shell.getRoot();
    const constructorProfileMutations = environment.document.attributeMutations
        .slice(constructorMutationStart)
        .filter(mutation => mutation.node === root && mutation.name === 'data-profile');
    check.equal(constructorProfileMutations.length, 1,
        'constructor mutates root data-profile exactly once');
    check.deepEqual(constructorProfileMutations[0], {
        node:root,
        operation:'set',
        name:'data-profile',
        value:'catalog-decision'
    }, 'constructor projects only the validated profile');
    check.equal(shell.getRoot().getAttribute('data-profile'), 'catalog-decision',
        'constructor projects the chosen profile');
    const transitionMutationStart = environment.document.attributeMutations.length;
    let invalidError = null;
    try {
        shell.setProfile('not-real');
    } catch (error) {
        invalidError = error;
    }
    check.ok(invalidError instanceof TypeError, 'invalid transition profile fails fast');
    check.equal(environment.document.attributeMutations.length, transitionMutationStart,
        'invalid transition performs no attribute mutation');
    check.equal(shell.getRoot().getAttribute('data-profile'), 'catalog-decision',
        'invalid transition leaves the current profile unchanged');
    check.equal(shell.setProfile('transfer-pair'), true, 'valid transition succeeds');
    const transitionProfileMutations = environment.document.attributeMutations
        .slice(transitionMutationStart)
        .filter(mutation => mutation.node === root && mutation.name === 'data-profile');
    check.equal(transitionProfileMutations.length, 1,
        'valid transition projects data-profile exactly once');
    check.equal(shell.getRoot().getAttribute('data-profile'), 'transfer-pair',
        'valid transition updates the profile in one projection');
    shell.destroy();
});

test('shell modal portal remains interactive above an active SecondaryPage', check => {
    const environment = loadEnvironment();
    const {shell} = makeShell(environment);
    const document = environment.document;
    const pageRoot = document.createElement('section');
    const pageButton = document.createElement('button');
    pageRoot.appendChild(pageButton);
    const page = new environment.Components.SecondaryPage({
        root:pageRoot,
        document,
        role:'dialog'
    });
    page.mount(shell.getRoot());
    page.open({initialFocus:pageButton});

    check.equal(shell._modalLayer.inert, false, 'secondary page does not inert the shared modal portal');
    check.equal(shell._modalLayer.hasAttribute('inert'), false, 'modal portal has no inert attribute');
    shell.openModal(modalSpec('secondary-confirm'));
    const confirm = shell._modalLayer.querySelector('.workbench-modal-action.primary');

    check.ok(confirm, 'modal confirm action is mounted');
    check.equal(shell._modalLayer.inert, false, 'open modal portal remains pointer interactive');
    check.equal(shell._modalLayer.hasAttribute('inert'), false, 'open modal portal remains outside inert ancestry');
    check.equal(pageRoot.inert, true, 'modal suppresses the active secondary page');
    check.equal(pageRoot.getAttribute('aria-hidden'), 'true', 'modal hides the active secondary page from accessibility');
    check.equal(document.activeElement, confirm, 'modal owns initial focus above the secondary page');
    check.ok(environment.Focus.focusables(shell._modalLayer).indexOf(confirm) >= 0,
        'modal confirm remains in the shared focusable set');
    assertScopeResources(check, environment, 2, 'secondary page plus modal');

    shell.closeModal('confirmed');
    check.equal(pageRoot.inert, false, 'closing modal restores secondary page interactivity');
    check.equal(pageRoot.hasAttribute('inert'), false, 'closing modal removes secondary page inert attribute');
    check.equal(pageRoot.getAttribute('aria-hidden'), 'false', 'closing modal restores secondary page accessibility');
    check.equal(document.activeElement, pageButton, 'closing modal restores focus to its secondary-page opener');
    assertScopeResources(check, environment, 1, 'after modal close over secondary page');

    page.destroy();
    shell.destroy();
    assertScopeResources(check, environment, 0, 'after secondary modal test cleanup');
});

test('shared HelpAction owns one standard header entry and restores focus after Escape', check => {
    const environment = loadEnvironment();
    const {shell} = makeShell(environment);
    const help = new environment.Components.HelpAction({
        shell,
        spec:{
            kind:'test-help',
            ariaLabel:'Open test help',
            title:'Help',
            message:'Shared workbench guidance'
        }
    });
    const button = help.button;
    check.ok(button.classList.contains('workbench-help-btn'), 'standard help class is present');
    check.equal(button.getAttribute('aria-label'), 'Open test help', 'domain aria label is applied');
    check.equal(button.listenerCount('click'), 1, 'one click listener is installed');

    button.focus();
    button.dispatch('click');
    check.equal(shell.getModalKind(), 'test-help', 'help opens through the shared shell modal');
    check.equal(shell._header.inert, true, 'help modal suppresses header interaction');
    check.equal(shell._body.inert, true, 'help modal suppresses body interaction');
    check.ok(shell._modalLayer.querySelector('.workbench-modal-action.primary'),
        'default close action is supplied');
    assertScopeResources(check, environment, 1, 'while shared help is open');

    environment.document.dispatch('keydown', {key:'Escape'});
    check.equal(shell.hasModal(), false, 'Escape closes shared help');
    check.equal(environment.document.activeElement, button, 'focus returns to help entry');
    assertScopeResources(check, environment, 0, 'after shared help closes');

    help.update(null);
    check.equal(button.hidden, true, 'empty spec hides the standard entry');
    help.destroy();
    check.equal(button.listenerCount('click'), 0, 'destroy removes the help listener');
    check.equal(button.parentNode, null, 'destroy removes the help entry');
    shell.destroy();
});

test('modal replacement tolerates an onClose reentrant open without orphaning a scope', check => {
    const environment = loadEnvironment();
    const {shell} = makeShell(environment);
    shell.openModal(modalSpec('A', reason => {
        if (reason === 'replace') shell.openModal(modalSpec('C'));
    }));
    let replacementError = null;
    try { shell.openModal(modalSpec('B')); } catch (error) { replacementError = error; }

    check.equal(replacementError, null, 'replacement completes without throwing');
    check.equal(shell._modalLayer.children.length, 1, 'exactly one modal backdrop survives replacement');
    check.equal(shell.hasModal(), true, 'one modal remains active after replacement');
    assertScopeResources(check, environment, 1, 'after replacement');

    try { shell.closeModal('test-close'); } catch (error) { check.ok(false, 'closing replacement threw ' + error.message); }
    check.equal(shell._modalLayer.children.length, 0, 'closing replacement clears every backdrop');
    check.equal(shell.hasModal(), false, 'closing replacement clears shell modal state');
    assertScopeResources(check, environment, 0, 'after replacement close');
    assertRestored(check, shell._header, 'header after replacement close');
    assertRestored(check, shell._body, 'body after replacement close');
});

test('DualPaneShell.destroy cannot be reentered by modal onClose to resurrect a scope', check => {
    const environment = loadEnvironment();
    const {shell} = makeShell(environment);
    shell.openModal(modalSpec('A', reason => {
        if (reason === 'close') shell.openModal(modalSpec('resurrected'));
    }));
    try { shell.destroy(); } catch (error) { check.ok(false, 'destroy threw ' + error.message); }

    check.equal(shell.hasModal(), false, 'destroy leaves no active modal');
    check.equal(shell._modalLayer.children.length, 0, 'destroy leaves no modal DOM');
    assertScopeResources(check, environment, 0, 'after shell destroy');
    assertRestored(check, shell._header, 'header after shell destroy');
    assertRestored(check, shell._body, 'body after shell destroy');

    // Keep this case isolated even while the production implementation is red.
    try { shell.closeModal('test-cleanup'); } catch (_) {}
});

test('DualPaneShell.destroy completes view teardown when modal onClose throws', check => {
    const environment = loadEnvironment();
    const {shell} = makeShell(environment);
    function makeView(key) {
        const root = environment.document.createElement('div');
        return {
            instanceKey:key,
            viewKind:'test',
            unmountCount:0,
            mount(host) { host.appendChild(root); },
            unmount() { this.unmountCount++; },
            render() {}
        };
    }
    const left = makeView('left');
    const right = makeView('right');
    shell.mountInitial(left, right);
    shell.openModal(modalSpec('throwing', () => { throw new Error('teardown-boom'); }));
    let caught = null;
    try { shell.destroy(); } catch (error) { caught = error; }

    check.ok(!caught || caught.message === 'teardown-boom', 'destroy only propagates the original callback error');
    check.equal(left.unmountCount, 1, 'left view unmounted despite callback failure');
    check.equal(right.unmountCount, 1, 'right view unmounted despite callback failure');
    check.equal(shell.getHost('L').currentView, null, 'left host cleared despite callback failure');
    check.equal(shell.getHost('R').currentView, null, 'right host cleared despite callback failure');
    check.deepEqual(Object.keys(shell._views), [], 'view registry cleared despite callback failure');
    check.equal(shell._modalLayer.children.length, 0, 'modal DOM cleared despite callback failure');
    assertScopeResources(check, environment, 0, 'after throwing shell destroy');

    shell.getHost('L').unmount();
    shell.getHost('R').unmount();
});

test('closing a parent SecondaryPage keeps descendant page state and FocusScope state synchronized', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const outerRoot = document.createElement('section');
    const outerButton = document.createElement('button');
    const innerRoot = document.createElement('section');
    const innerButton = document.createElement('button');
    document.body.appendChild(background);
    document.body.appendChild(outerRoot);
    outerRoot.appendChild(outerButton);
    outerRoot.appendChild(innerRoot);
    innerRoot.appendChild(innerButton);
    let innerCloseCount = 0;
    const outer = new environment.Components.SecondaryPage({root:outerRoot, document, role:'dialog'});
    const inner = new environment.Components.SecondaryPage({
        root:innerRoot,
        document,
        role:'dialog',
        onClose() { innerCloseCount++; }
    });
    outer.mount(document.body);
    inner.mount(outerRoot);
    outer.open({initialFocus:outerButton});
    inner.open({initialFocus:innerButton});
    assertScopeResources(check, environment, 2, 'before parent close');

    outer.close('domain-close');
    check.equal(outer.isActive(), false, 'outer page is inactive');
    check.equal(inner.isActive(), false, 'inner page owner is inactive when its scope is closed by ancestor');
    check.equal(innerRoot.getAttribute('aria-hidden'), 'true', 'inner page is hidden when ancestor closes it');
    check.equal(innerRoot.classList.contains('active'), false, 'inner active class is cleared');
    check.equal(innerCloseCount, 1, 'inner domain close callback runs once');
    assertScopeResources(check, environment, 0, 'after parent close');

    outer.open({initialFocus:outerButton});
    inner.open({initialFocus:innerButton});
    check.equal(inner.isActive(), true, 'inner page can reopen after ancestor close');
    assertScopeResources(check, environment, 2, 'after nested reopen');
    inner.destroy();
    outer.destroy();
});

test('stacked sibling SecondaryPages expose only the top dialog and restore the lower page', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const firstRoot = document.createElement('section');
    const secondRoot = document.createElement('section');
    firstRoot.appendChild(document.createElement('button'));
    secondRoot.appendChild(document.createElement('button'));
    document.body.appendChild(background);
    document.body.appendChild(firstRoot);
    document.body.appendChild(secondRoot);
    const first = new environment.Components.SecondaryPage({root:firstRoot, document, role:'dialog'});
    const second = new environment.Components.SecondaryPage({root:secondRoot, document, role:'dialog'});
    first.mount(document.body);
    second.mount(document.body);
    first.open();
    second.open();

    check.equal(second.isActive(), true, 'top sibling page is active');
    check.equal(secondRoot.inert, false, 'active sibling root is not inert');
    check.equal(secondRoot.hasAttribute('inert'), false, 'active sibling root has no inert attribute');
    check.equal(secondRoot.getAttribute('aria-hidden'), 'false', 'active sibling root is exposed to accessibility tree');
    check.equal(firstRoot.inert, true, 'lower active sibling is inert while covered');
    check.equal(firstRoot.hasAttribute('inert'), true, 'lower active sibling has inert attribute while covered');
    check.equal(firstRoot.getAttribute('aria-hidden'), 'true', 'lower active sibling is hidden from accessibility tree');
    check.equal(background.inert, true, 'background remains suppressed while siblings are stacked');

    second.close('top-close');
    check.equal(first.isActive(), true, 'lower sibling remains active after top close');
    check.equal(firstRoot.inert, false, 'restored lower sibling is non-inert');
    check.equal(firstRoot.hasAttribute('inert'), false, 'restored lower sibling has no inert attribute');
    check.equal(firstRoot.getAttribute('aria-hidden'), 'false', 'restored lower sibling returns to accessibility tree');
    check.equal(background.inert, true, 'background stays suppressed while lower sibling remains active');
    check.equal(background.getAttribute('aria-hidden'), 'true', 'background stays aria-hidden while lower sibling remains active');
    first.close('lower-close');

    check.equal(first.isActive(), false, 'first sibling is inactive after unwind');
    check.equal(second.isActive(), false, 'second sibling is inactive after unwind');
    check.equal(firstRoot.getAttribute('aria-hidden'), 'true', 'first closed root remains aria-hidden');
    check.equal(secondRoot.getAttribute('aria-hidden'), 'true', 'second closed root remains aria-hidden');
    assertRestored(check, background, 'background after sibling unwind');
    assertScopeResources(check, environment, 0, 'after sibling unwind');
    first.destroy();
    second.destroy();
});

test('closing a covered sibling cannot make it visible when the top page later closes', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const backgroundButton = document.createElement('button');
    const firstRoot = document.createElement('section');
    const secondRoot = document.createElement('section');
    firstRoot.appendChild(document.createElement('button'));
    secondRoot.appendChild(document.createElement('button'));
    background.appendChild(backgroundButton);
    document.body.appendChild(background);
    document.body.appendChild(firstRoot);
    document.body.appendChild(secondRoot);
    const first = new environment.Components.SecondaryPage({root:firstRoot, document, role:'dialog'});
    const second = new environment.Components.SecondaryPage({root:secondRoot, document, role:'dialog'});
    first.mount(document.body);
    second.mount(document.body);
    backgroundButton.focus();
    first.open();
    second.open();

    first.close('covered-close');
    check.equal(first.isActive(), false, 'covered sibling closes its own lifecycle');
    check.equal(firstRoot.getAttribute('aria-hidden'), 'true', 'covered closed sibling stays hidden');
    check.equal(firstRoot.inert, true, 'top page still suppresses the covered closed sibling');
    check.equal(secondRoot.getAttribute('aria-hidden'), 'false', 'top sibling remains exposed');

    second.close('top-close');
    check.equal(firstRoot.getAttribute('aria-hidden'), 'true', 'closed lower sibling is not resurrected by restoration');
    check.equal(firstRoot.inert, false, 'closed lower sibling releases temporary inert state');
    check.equal(document.activeElement, backgroundButton, 'focus skips the closed lower sibling and returns to its opener');
    assertRestored(check, background, 'background after covered sibling unwind');
    assertScopeResources(check, environment, 0, 'after covered sibling unwind');
    first.destroy();
    second.destroy();
});

test('SecondaryPage onOpen close reentry cannot leave an invisible active FocusScope', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const root = document.createElement('section');
    root.appendChild(document.createElement('button'));
    document.body.appendChild(background);
    document.body.appendChild(root);
    let page;
    page = new environment.Components.SecondaryPage({
        root,
        document,
        onOpen() { page.close('reentrant-onOpen'); }
    });
    page.mount(document.body);
    page.open();

    check.equal(page.isActive(), false, 'page remains closed after onOpen closes it');
    check.equal(root.getAttribute('aria-hidden'), 'true', 'closed page remains aria-hidden');
    check.equal(root.classList.contains('active'), false, 'closed page has no active class');
    assertScopeResources(check, environment, 0, 'after onOpen close reentry');
    assertRestored(check, background, 'background after onOpen close reentry');
    page.destroy();
});

test('SecondaryPage onClose reentrant reopen is rejected without creating a partial session', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const root = document.createElement('section');
    const initial = document.createElement('button');
    root.appendChild(initial);
    document.body.appendChild(background);
    document.body.appendChild(root);
    let reopen = true;
    let reentrantOpenResult = null;
    let page;
    page = new environment.Components.SecondaryPage({
        root,
        document,
        onClose(reason) {
            if (reopen && reason === 'cycle') reentrantOpenResult = page.open({initialFocus:initial});
        }
    });
    page.mount(document.body);
    page.open({initialFocus:initial});
    page.close('cycle');

    check.equal(reentrantOpenResult, false, 'open is rejected while close transition owns the page');
    check.equal(page.isActive(), false, 'page remains closed after rejected onClose reopen');
    check.equal(root.getAttribute('aria-hidden'), 'true', 'closed page remains aria-hidden');
    check.equal(root.classList.contains('active'), false, 'closed page has no active class');
    assertScopeResources(check, environment, 0, 'after rejected onClose reopen');
    assertRestored(check, background, 'background after rejected onClose reopen');

    reopen = false;
    check.equal(page.open({initialFocus:initial}), true, 'page may open again after close transition completes');
    assertScopeResources(check, environment, 1, 'after later explicit reopen');
    page.close('final');
    assertScopeResources(check, environment, 0, 'after final close');
    assertRestored(check, background, 'background after final close');
    page.destroy();
});

test('SecondaryPage hides underlay action strips while preserving exact page actions and nested restoration', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const shell = document.createElement('main');
    shell.className = 'workbench-shell';
    const header = document.createElement('header');
    header.className = 'workbench-header';
    const headerActions = document.createElement('div');
    headerActions.className = 'workbench-header-actions';
    const mainHelp = document.createElement('button');
    mainHelp.setAttribute('data-header-action', 'help');
    headerActions.appendChild(mainHelp);
    header.appendChild(headerActions);
    const content = document.createElement('section');
    shell.appendChild(header);
    shell.appendChild(content);
    document.body.appendChild(shell);

    function pageFixture(label) {
        const root = document.createElement('section');
        const actions = document.createElement('div');
        actions.className = 'workbench-secondary-actions';
        const back = document.createElement('button');
        const help = document.createElement('button');
        const close = document.createElement('button');
        actions.appendChild(back);
        actions.appendChild(help);
        actions.appendChild(close);
        root.appendChild(actions);
        const page = new environment.Components.SecondaryPage({root, document, ariaLabel:label});
        page.mount(shell);
        page.bindBack(back);
        page.bindHelp(help);
        page.bindClose(close);
        return {page, root, actions, back, help, close};
    }

    const first = pageFixture('first');
    const second = pageFixture('second');
    first.page.open({initialFocus:first.back});
    check.equal(header.inert, true, 'lower header is inert while first page owns focus');
    check.equal(headerActions.hidden, true, 'lower header actions are visually hidden');
    check.equal(headerActions.hasAttribute('hidden'), true, 'hidden state reaches the terminal utility');
    check.deepEqual(
        first.actions.children.map(node => node.getAttribute('data-secondary-action')),
        ['back', 'help', 'close'],
        'active page exposes the exact Back/Help/Close action set'
    );
    check.equal(first.actions.hidden, false, 'active page actions remain visible');

    second.page.open({initialFocus:second.back});
    check.equal(first.root.inert, true, 'lower secondary page is inert');
    check.equal(first.actions.hidden, true, 'lower secondary actions are visually hidden');
    first.page.close('out-of-order', {restoreFocus:false});
    check.equal(headerActions.hidden, true, 'shared header stays hidden while upper page remains active');
    check.equal(first.actions.hidden, true, 'upper page suppression survives lower page close');

    second.page.close('done', {restoreFocus:false});
    check.equal(header.inert, false, 'header inert state restores after final page close');
    check.equal(headerActions.hidden, false, 'header actions restore their original visibility');
    check.equal(headerActions.hasAttribute('hidden'), false, 'temporary hidden attribute is removed exactly');
    check.equal(first.actions.hidden, false, 'nested action strip ref-count returns to its original state');
    first.page.destroy();
    second.page.destroy();
    assertScopeResources(check, environment, 0, 'after secondary action suppression cleanup');
});

test('SecondaryPage close callback close-and-reopen is not closed a second time by _requestClose', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const root = document.createElement('section');
    const back = document.createElement('button');
    const initial = document.createElement('button');
    root.appendChild(initial);
    document.body.appendChild(background);
    document.body.appendChild(root);
    const page = new environment.Components.SecondaryPage({root, document});
    page.mount(document.body);
    page.bindBack(back, () => {
        page.close('domain-old-session');
        page.open({opener:back, initialFocus:initial});
    });
    page.open({initialFocus:initial});
    back.dispatch('click');

    check.equal(page.isActive(), true, 'domain callback reopened session remains active');
    check.equal(root.getAttribute('aria-hidden'), 'false', 'domain-reopened page remains accessible');
    assertScopeResources(check, environment, 1, 'after domain callback reopen');
    check.equal(background.inert, true, 'domain-reopened session still suppresses background');
    page.destroy();
});

test('SecondaryPage.destroy completes lifetime and DOM teardown when onClose throws', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const background = document.createElement('main');
    const back = document.createElement('button');
    background.appendChild(back);
    document.body.appendChild(background);
    let throwOnClose = true;
    const page = new environment.Components.SecondaryPage({
        document,
        onClose() { if (throwOnClose) throw new Error('secondary-teardown-boom'); }
    });
    page.mount(document.body);
    page.bindBack(back);
    page.open();
    let caught = null;
    try { page.destroy(); } catch (error) { caught = error; }

    check.ok(!caught || caught.message === 'secondary-teardown-boom', 'destroy only propagates original onClose error');
    check.equal(page._destroyed, true, 'page is marked destroyed despite onClose error');
    check.equal(page.root.parentNode, null, 'owned page root is removed despite onClose error');
    check.equal(back.listenerCount('click'), 0, 'lifetime close listener is removed despite onClose error');
    assertScopeResources(check, environment, 0, 'after throwing SecondaryPage destroy');
    assertRestored(check, background, 'background after throwing SecondaryPage destroy');

    throwOnClose = false;
    page.destroy();
});

test('focusables and initial focus exclude candidates under hidden, inert, or aria-hidden ancestors', check => {
    const environment = loadEnvironment();
    const document = environment.document;
    const root = document.createElement('section');
    const visible = document.createElement('button');
    const ariaHiddenParent = document.createElement('div');
    const ariaHiddenButton = document.createElement('button');
    const inertParent = document.createElement('div');
    const inertButton = document.createElement('button');
    const hiddenParent = document.createElement('div');
    const hiddenButton = document.createElement('button');
    ariaHiddenParent.setAttribute('aria-hidden', 'true');
    inertParent.inert = true;
    inertParent.setAttribute('inert', '');
    hiddenParent.hidden = true;
    hiddenParent.setAttribute('hidden', '');
    ariaHiddenParent.appendChild(ariaHiddenButton);
    inertParent.appendChild(inertButton);
    hiddenParent.appendChild(hiddenButton);
    root.appendChild(visible);
    root.appendChild(ariaHiddenParent);
    root.appendChild(inertParent);
    root.appendChild(hiddenParent);
    document.body.appendChild(root);

    check.deepEqual(environment.Focus.focusables(root), [visible], 'only candidates with an exposed ancestor chain are focusable');
    const scope = new environment.Focus.FocusScope({root, document});
    scope.activate({initialFocus:ariaHiddenButton});
    check.equal(document.activeElement, visible, 'invalid initial focus falls back to an exposed candidate');
    scope.destroy();
    assertScopeResources(check, environment, 0, 'after ancestor visibility test');
});

process.stdout.write('workbench focus integration: ' + passed + ' passed, ' + failed + ' failed\n');
if (failed) process.exitCode = 1;
