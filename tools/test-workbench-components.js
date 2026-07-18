'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Components = require('../launcher/web/modules/workbench-components.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
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

class FakeNode {
    constructor(tagName, ownerDocument) {
        this.tagName = String(tagName || 'div').toUpperCase();
        this.ownerDocument = ownerDocument;
        this.nodeType = 1;
        this.parentNode = null;
        this.children = [];
        this.attributes = {};
        this.classList = new FakeClassList();
        this.listeners = {};
        this.disabled = false;
        this.textContent = '';
        this.title = '';
        this.type = '';
    }
    get firstChild() { return this.children[0] || null; }
    set className(value) {
        this.classList = new FakeClassList();
        String(value || '').split(/\s+/).forEach(name => this.classList.add(name));
    }
    get className() { return Object.keys(this.classList.values).join(' '); }
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
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null; }
    hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) {
        const list = this.listeners[type] || [];
        const index = list.indexOf(handler);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type) {
        const event = {type, target:this, preventDefault() { this.defaultPrevented = true; }};
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
    querySelector() { return null; }
    querySelectorAll() { return []; }
    contains(node) {
        if (node === this) return true;
        return this.children.some(child => child.contains(node));
    }
    focus() { this.ownerDocument.activeElement = this; }
}

class FakeDocument {
    constructor() { this.listeners = {}; this.activeElement = null; }
    createElement(tagName) { return new FakeNode(tagName, this); }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) {
        const list = this.listeners[type] || [];
        const index = list.indexOf(handler);
        if (index >= 0) list.splice(index, 1);
    }
}

test('exports the four shared primitives', () => {
    assert.deepStrictEqual(Object.keys(Components).sort(), [
        'ChoiceGroup', 'CommitBar', 'OwnedInventoryPane', 'SecondaryPage'
    ]);
});

test('production module consumes the shared DisposableStack contract', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'workbench-components.js'), 'utf8');
    assert(source.includes("require('./workbench-lifecycle.js')"));
    assert(source.includes('WorkbenchLifecycle.DisposableStack'));
    assert(!source.includes('this._disposers'));
});

test('SecondaryPage owns an idempotent mount/open/close lifecycle', () => {
    const document = new FakeDocument();
    const host = document.createElement('main');
    const back = document.createElement('button');
    const events = [];
    const page = new Components.SecondaryPage({
        document,
        className:'feature-page',
        role:'dialog',
        ariaLabel:'Secondary',
        onOpen:context => events.push('open:' + context.id),
        onClose:reason => events.push('close:' + reason),
        onBack:() => events.push('back')
    });
    assert.strictEqual(page.mount(host), true);
    assert.strictEqual(page.mount(host), true);
    assert.strictEqual(host.children.length, 1);
    assert.strictEqual(page.bindClose(back), true);
    assert.strictEqual(page.open({id:'one'}), true);
    assert.strictEqual(page.isActive(), true);
    assert.strictEqual(page.root.classList.contains('active'), true);
    assert.strictEqual(page.root.getAttribute('aria-hidden'), 'false');
    back.dispatch('click');
    assert.strictEqual(page.isActive(), false);
    assert.deepStrictEqual(events, ['open:one', 'back', 'close:back']);
    assert.strictEqual(page.destroy(), true);
    assert.strictEqual(page.destroy(), false);
    assert.strictEqual(host.children.length, 0);
    back.dispatch('click');
    assert.deepStrictEqual(events, ['open:one', 'back', 'close:back']);
});

test('ChoiceGroup keeps value, pressed state, callbacks, and disabled state together', () => {
    const document = new FakeDocument();
    const host = document.createElement('header');
    const changes = [];
    const group = new Components.ChoiceGroup({
        document,
        className:'mode-switch',
        value:'shop',
        ariaLabel:'Mode',
        choices:[
            {value:'shop', label:'Shop', dataAttribute:'data-mode'},
            {value:'owned', label:'Owned', className:'workbench-mode-btn owned'}
        ],
        onChange:value => changes.push(value)
    });
    group.mount(host);
    assert.strictEqual(group.getButton('shop').getAttribute('aria-pressed'), 'true');
    group.getButton('owned').dispatch('click');
    assert.strictEqual(group.getValue(), 'owned');
    assert.deepStrictEqual(changes, ['owned']);
    assert.strictEqual(group.getButton('owned').classList.contains('active'), true);
    group.update({disabled:true, value:'shop'});
    assert.strictEqual(group.getButton('shop').disabled, true);
    group.getButton('owned').dispatch('click');
    assert.deepStrictEqual(changes, ['owned']);
    group.update({disabled:false});
    assert.strictEqual(group.setValue('shop', {silent:true}), true);
    assert.deepStrictEqual(changes, ['owned']);
    assert.strictEqual(group.destroy(), true);
    assert.strictEqual(host.children.length, 0);
});

test('CommitBar centralizes status, gate state, and commit listener teardown', () => {
    const document = new FakeDocument();
    const host = document.createElement('main');
    let commits = 0;
    const bar = new Components.CommitBar({document, label:'Confirm', onCommit:() => commits++});
    bar.mount(host);
    bar.update({status:'Ready', state:'ready', canCommit:true});
    assert.strictEqual(bar.statusNode.textContent, 'Ready');
    assert.strictEqual(bar.root.classList.contains('is-ready'), true);
    bar.primaryButton.dispatch('click');
    assert.strictEqual(commits, 1);
    bar.update({label:'Working', busy:true, state:'busy'});
    assert.strictEqual(bar.primaryButton.textContent, 'Working');
    assert.strictEqual(bar.primaryButton.disabled, true);
    bar.primaryButton.dispatch('click');
    assert.strictEqual(commits, 1);
    bar.destroy();
    assert.strictEqual(host.children.length, 0);
});

test('OwnedInventoryPane reconciles exact snapshots and serializes quick transfers', () => {
    const snapshots = [];
    const selections = [];
    const transferCalls = [];
    const transferCallbacks = [];
    const shell = {syncSnapshot(snapshot, presentation) { snapshots.push({snapshot, presentation}); }};
    const view = {root:null, ownedInventoryShell:shell};
    const pane = new Components.OwnedInventoryPane({
        view,
        shell,
        keyOf:slot => slot.id,
        onSelectionChange:items => selections.push(items.map(item => item.id)),
        onQuickTransfer(intent, done) {
            transferCalls.push(intent);
            transferCallbacks.push(done);
            return true;
        }
    });
    const first = {id:'a', occupied:true};
    const second = {id:'b', occupied:true};
    pane.update({slots:[first, second]}, {meta:'2 / 2'});
    pane.setSelected(first, true);
    assert.strictEqual(pane.isSelected(first), true);
    pane.update({slots:[second]}, {meta:'1 / 2'});
    assert.strictEqual(pane.isSelected(first), false);
    assert.deepStrictEqual(selections, [['a'], []]);
    assert.strictEqual(snapshots.length, 2);

    assert.strictEqual(pane.quickTransfer(second, 'warehouse', {key:'b>warehouse'}), true);
    assert.strictEqual(pane.quickTransfer({id:'c'}, 'warehouse', {key:'c>warehouse'}), true);
    assert.strictEqual(transferCalls.length, 1);
    assert.deepStrictEqual(pane.debugState().quickTransfer, {
        pending:1, inFlight:'b>warehouse', completed:0, accepted:0
    });
    transferCallbacks[0]({success:true});
    assert.strictEqual(transferCalls.length, 2);
    transferCallbacks[1]({success:false});
    assert.deepStrictEqual(pane.debugState().quickTransfer, {
        pending:0, inFlight:null, completed:2, accepted:1
    });

    pane.quickTransfer(second, 'warehouse', {key:'late'});
    const late = transferCallbacks[2];
    pane.cancelQuickTransfers();
    late({success:true});
    assert.strictEqual(pane.debugState().quickTransfer.completed, 2);
    assert.strictEqual(pane.destroy(), true);
    assert.strictEqual(view.ownedInventoryPane, null);
});

test('shared lifecycle teardown keeps listener ownership flat across updates and repeated destroy', () => {
    const document = new FakeDocument();
    const back = document.createElement('button');
    const page = new Components.SecondaryPage({document});
    page.bindClose(back);
    page.update({active:true});
    page.update({active:false});
    assert.strictEqual(back.listenerCount('click'), 1);
    page.destroy();
    page.destroy();
    assert.strictEqual(back.listenerCount('click'), 0);

    const group = new Components.ChoiceGroup({document, choices:[{value:'a', label:'A'}]});
    const firstButton = group.getButton('a');
    assert.strictEqual(firstButton.listenerCount('click'), 1);
    group.setChoices([{value:'b', label:'B'}]);
    assert.strictEqual(firstButton.listenerCount('click'), 0);
    const secondButton = group.getButton('b');
    group.update({value:'b'});
    group.update({disabled:true});
    assert.strictEqual(secondButton.listenerCount('click'), 1);
    group.destroy();
    group.destroy();
    assert.strictEqual(secondButton.listenerCount('click'), 0);

    const bar = new Components.CommitBar({document});
    for (let i = 0; i < 5; i++) bar.update({label:'Commit ' + i, canCommit:true});
    assert.strictEqual(bar.primaryButton.listenerCount('click'), 1);
    bar.destroy();
    bar.destroy();
    assert.strictEqual(bar.primaryButton.listenerCount('click'), 0);
});

process.stdout.write('workbench components: ' + passed + '/' + passed + ' passed\n');
