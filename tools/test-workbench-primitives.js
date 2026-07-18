'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const primitivesPath = require.resolve('../launcher/web/modules/workbench-primitives.js');
const workbenchPath = require.resolve('../launcher/web/modules/workbench.js');
const Primitives = require(primitivesPath);

// Exercise the CommonJS dependency path rather than the browser global left by
// the primitives UMD wrapper.
delete global.WorkbenchPrimitives;
delete require.cache[workbenchPath];
const Workbench = require(workbenchPath);
delete global.Workbench;

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

function matchesSingle(node, selector) {
    selector = String(selector || '').trim();
    if (!selector || node.nodeType !== 1) return false;
    if (selector === '*') return true;
    const attribute = selector.match(/^\[([^=\]]+)(?:=["']?([^"'\]]+)["']?)?\]$/);
    if (attribute) {
        const value = node.getAttribute(attribute[1]);
        return value != null && (attribute[2] == null || value === attribute[2]);
    }
    const tagAttribute = selector.match(/^([a-z0-9-]+)\[([^=\]]+)(?:=["']?([^"'\]]+)["']?)?\]$/i);
    if (tagAttribute) {
        if (node.tagName !== tagAttribute[1].toUpperCase()) return false;
        const value = node.getAttribute(tagAttribute[2]);
        return value != null && (tagAttribute[3] == null || value === tagAttribute[3]);
    }
    return node.tagName === selector.toUpperCase();
}

function matches(node, selector) {
    return String(selector || '').split(',').some(part => matchesSingle(node, part));
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
        this.textContent = '';
        this.innerHTML = '';
        this.capturedPointers = [];
        this.releasedPointers = [];
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
    contains(node) {
        for (let current = node; current; current = current.parentNode) {
            if (current === this) return true;
        }
        return false;
    }
    closest(selector) {
        for (let current = this; current && current.nodeType === 1; current = current.parentNode) {
            if (matches(current, selector)) return current;
        }
        return null;
    }
    querySelectorAll(selector) {
        const result = [];
        function visit(node) {
            node.children.forEach(child => {
                if (child.nodeType === 1) {
                    if (matches(child, selector)) result.push(child);
                    visit(child);
                }
            });
        }
        visit(this);
        return result;
    }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name) ? this.attributes[name] : null;
    }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) {
        const list = this.listeners[type] || [];
        const index = list.indexOf(handler);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type, init) {
        const event = Object.assign({
            type,
            target: this,
            currentTarget: this,
            button: 0,
            isPrimary: true,
            preventDefault() { this.defaultPrevented = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
    setPointerCapture(pointerId) { this.capturedPointers.push(pointerId); }
    releasePointerCapture(pointerId) { this.releasedPointers.push(pointerId); }
}

class FakeDocument {
    constructor() {
        this.listeners = {};
        this.body = this.createElement('body');
    }
    createElement(tagName) { return new FakeNode(tagName, this); }
    createTextNode(text) { return new FakeTextNode(text, this); }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) {
        const list = this.listeners[type] || [];
        const index = list.indexOf(handler);
        if (index >= 0) list.splice(index, 1);
    }
    dispatch(type, init) {
        const event = Object.assign({
            type,
            target: this,
            preventDefault() { this.defaultPrevented = true; }
        }, init || {});
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
}

function withDocument(fn) {
    const previous = global.document;
    const document = new FakeDocument();
    global.document = document;
    try {
        return fn(document);
    } finally {
        if (previous === undefined) delete global.document;
        else global.document = previous;
    }
}

test('exports four primitives and workbench preserves constructor identity', () => {
    assert.deepStrictEqual(Object.keys(Primitives).sort(), [
        'EntityTile', 'InteractionBroker', 'ItemCard', 'PointerDragController'
    ]);
    Object.keys(Primitives).forEach(name => {
        assert.strictEqual(Workbench[name], Primitives[name], name);
    });
});

test('physical split stays below the audit limit and fails clearly without its dependency', () => {
    const workbenchSource = fs.readFileSync(workbenchPath, 'utf8');
    const primitivesSource = fs.readFileSync(primitivesPath, 'utf8');
    assert(workbenchSource.split(/\r?\n/).length < 1000);
    ['EntityTile', 'ItemCard', 'InteractionBroker', 'PointerDragController'].forEach(name => {
        assert(!new RegExp('function\\s+' + name + '\\s*\\(').test(workbenchSource), name + ' leaked into workbench.js');
        assert(new RegExp('function\\s+' + name + '\\s*\\(').test(primitivesSource), name + ' missing from primitives');
    });
    assert.throws(
        () => vm.runInNewContext(workbenchSource, {}, {filename:'workbench.js'}),
        /workbench\.js requires workbench-primitives\.js to load first/
    );
    assert.throws(
        () => vm.runInNewContext(workbenchSource, {
            WorkbenchPrimitives:{EntityTile:function() {}},
            WorkbenchFocus:{FocusScope:function() {}}
        }, {filename:'workbench.js'}),
        /workbench-primitives\.js missing ItemCard/
    );
    const browser = {WorkbenchPrimitives:Primitives, WorkbenchFocus:{FocusScope:function() {}}};
    vm.runInNewContext(workbenchSource, browser, {filename:'workbench.js'});
    assert.strictEqual(browser.Workbench.EntityTile, Primitives.EntityTile);
    assert.strictEqual(browser.Workbench.PointerDragController, Primitives.PointerDragController);
});

test('EntityTile owns role, state, action labels and keyboard activation semantics', () => withDocument(document => {
    const tile = document.createElement('article');
    const action = document.createElement('button');
    action.textContent = '购买';
    tile.appendChild(action);
    const activations = [];
    let disabled = false;
    const binding = Primitives.EntityTile.bindActivation(tile, {
        itemName:'青锋剑',
        label:'售价 120',
        selected:true,
        disabled:() => disabled,
        onActivate:(event, context) => activations.push(context.origin)
    });

    assert.strictEqual(tile.getAttribute('role'), 'option');
    assert.strictEqual(tile.getAttribute('tabindex'), '0');
    assert.strictEqual(tile.getAttribute('aria-selected'), 'true');
    assert.strictEqual(tile.getAttribute('aria-disabled'), 'false');
    assert.strictEqual(tile.getAttribute('aria-label'), '青锋剑，售价 120');
    assert.strictEqual(action.getAttribute('aria-label'), '青锋剑，购买');

    tile.dispatch('click');
    const enter = tile.dispatch('keydown', {key:'Enter'});
    const space = tile.dispatch('keydown', {key:' '});
    assert.strictEqual(enter.defaultPrevented, true);
    assert.strictEqual(space.defaultPrevented, true);
    assert.deepStrictEqual(activations, ['pointer', 'keyboard', 'keyboard']);

    tile.dispatch('click', {target:action});
    tile.dispatch('click', {button:1});
    assert.deepStrictEqual(activations, ['pointer', 'keyboard', 'keyboard']);

    disabled = true;
    const disabledKey = tile.dispatch('keydown', {key:'Enter'});
    tile.dispatch('click');
    assert.strictEqual(disabledKey.defaultPrevented, undefined);
    assert.deepStrictEqual(activations, ['pointer', 'keyboard', 'keyboard']);

    binding.destroy();
    binding.destroy();
    assert.strictEqual(tile.listenerCount('click'), 0);
    assert.strictEqual(tile.listenerCount('keydown'), 0);
    assert.strictEqual(tile.__workbenchEntityTileBinding, null);
}));

test('ItemCard renders the shared catalog semantics for both skins', () => withDocument(() => {
    const kshop = Primitives.ItemCard.renderCatalog({
        skin:'kshop', id:7, name:'青锋剑', meta:'武器', priceText:'120', selected:true
    });
    assert.strictEqual(kshop.tagName, 'ARTICLE');
    assert.strictEqual(kshop.getAttribute('data-idx'), '7');
    assert.strictEqual(kshop.getAttribute('role'), 'option');
    assert.strictEqual(kshop.getAttribute('tabindex'), '0');
    assert.strictEqual(kshop.getAttribute('aria-selected'), 'true');
    assert.strictEqual(kshop.getAttribute('aria-disabled'), 'false');
    assert.strictEqual(kshop.getAttribute('aria-label'), '青锋剑，120');
    assert.strictEqual(kshop.classList.contains('kshop-card'), true);

    const npcshop = Primitives.ItemCard.renderCatalog({
        skin:'npcshop', id:3, name:'秘银甲', price:800, locked:true,
        lockTitle:'声望不足', lockReason:'需要声望 10'
    });
    assert.strictEqual(npcshop.getAttribute('data-catalog-index'), '3');
    assert.strictEqual(npcshop.getAttribute('role'), 'option');
    assert.strictEqual(npcshop.getAttribute('tabindex'), '-1');
    assert.strictEqual(npcshop.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(npcshop.classList.contains('locked'), true);
    assert.throws(() => Primitives.ItemCard.renderCatalog({skin:'unknown'}), /Unsupported ItemCard skin/);
}));

test('InteractionBroker keeps selection semantics and emits a neutral accepted intent', () => withDocument(document => {
    const sourceNode = document.createElement('article');
    const otherNode = document.createElement('article');
    const intents = [];
    const rejects = [];
    const selections = [];
    const broker = new Primitives.InteractionBroker({
        onIntent:intent => intents.push(intent),
        onReject:rejection => rejects.push(rejection.reason),
        onSelectionChange:selected => selections.push(selected ? selected.item.id : null)
    });
    const sourceView = {
        instanceKey:'bag:1',
        exportOffer:item => ({subjectKind:'item', sourceRef:{id:item.id}})
    };
    const targetView = {
        probeAccept:() => ({accepted:true, operationId:'move_item', targetRef:{slot:2}, hint:'swap'})
    };
    const item = {id:'sword'};

    assert.strictEqual(broker.select(sourceView, item, sourceNode), true);
    assert.strictEqual(sourceNode.classList.contains('workbench-source-selected'), true);
    assert.strictEqual(sourceNode.getAttribute('aria-selected'), 'true');
    assert.deepStrictEqual(broker.debugState(), {selectedInstanceKey:'bag:1'});
    assert.strictEqual(broker.isSelectedNode(sourceNode), true);

    broker.select(sourceView, {id:'shield'}, otherNode);
    assert.strictEqual(sourceNode.classList.contains('workbench-source-selected'), false);
    assert.strictEqual(sourceNode.getAttribute('aria-selected'), 'false');
    const result = broker.dispatch(sourceView, item, targetView, {index:2}, 'keyboard');
    assert.strictEqual(result.accepted, true);
    assert.deepStrictEqual(intents[0], {
        operationId:'move_item',
        subjectKind:'item',
        sourceRef:{id:'sword'},
        targetRef:{slot:2},
        hint:'swap',
        origin:'keyboard'
    });
    assert.strictEqual(otherNode.getAttribute('aria-selected'), 'false');
    assert.deepStrictEqual(selections, ['sword', 'shield', null]);
    assert.deepStrictEqual(broker.activateSelected(targetView, {}, 'click'), {
        accepted:false, reason:'nothing_selected'
    });

    const noOffer = broker.dispatch({}, item, targetView, {}, 'pointer');
    assert.deepStrictEqual(noOffer, {accepted:false, reason:'no_offer'});
    const rejected = broker.dispatch(sourceView, item, {probeAccept:() => ({accepted:false, reason:'full'})}, {}, 'pointer');
    assert.deepStrictEqual(rejected, {accepted:false, reason:'full'});
    assert.deepStrictEqual(rejects, ['no_offer', 'full']);
}));

test('PointerDragController dispatches drag and tears down every transient resource', () => withDocument(document => {
    const sourceElement = document.createElement('section');
    const sourceNode = document.createElement('article');
    const targetNode = document.createElement('article');
    sourceElement.appendChild(sourceNode);
    const source = {view:{instanceKey:'bag'}, item:{id:'sword'}, node:sourceNode};
    const target = {view:{instanceKey:'warehouse'}, node:targetNode, hit:{slot:4}, accepted:true};
    const selections = [];
    const dispatches = [];
    const starts = [];
    const ends = [];
    const broker = {
        select:(view, item, node) => selections.push({view, item, node}),
        dispatch:(sourceView, item, targetView, hit, origin) => {
            dispatches.push({sourceView, item, targetView, hit, origin});
        }
    };
    const ghost = document.createElement('div');
    const controller = new Primitives.PointerDragController({
        sourceElement,
        getSource:() => source,
        resolveTarget:() => target,
        renderGhost:() => ghost,
        onDragStart:value => starts.push(value),
        onDragEnd:value => ends.push(value),
        broker,
        threshold:5,
        timeoutMs:5000
    });

    assert.strictEqual(sourceElement.listenerCount('pointerdown'), 1);
    sourceElement.dispatch('pointerdown', {
        target:sourceNode, pointerId:9, clientX:10, clientY:10
    });
    assert.strictEqual(selections.length, 1);
    assert.deepStrictEqual(sourceNode.capturedPointers, [9]);
    assert.strictEqual(document.listenerCount('pointermove'), 1);
    assert.strictEqual(document.listenerCount('pointerup'), 1);
    assert.strictEqual(document.listenerCount('pointercancel'), 1);

    document.dispatch('pointermove', {pointerId:9, clientX:12, clientY:12});
    assert.strictEqual(starts.length, 0);
    document.dispatch('pointermove', {pointerId:9, clientX:20, clientY:20});
    assert.strictEqual(starts.length, 1);
    assert.strictEqual(document.body.contains(ghost), true);
    assert.strictEqual(ghost.style.left, '34px');
    assert.strictEqual(ghost.style.top, '34px');
    assert.strictEqual(targetNode.classList.contains('workbench-drop-active'), true);
    assert.deepStrictEqual(controller.debugState(), {
        active:true, dragging:true, hasGhost:true, hasTarget:true
    });

    const up = document.dispatch('pointerup', {pointerId:9, clientX:20, clientY:20});
    assert.strictEqual(up.defaultPrevented, true);
    assert.strictEqual(dispatches.length, 1);
    assert.strictEqual(dispatches[0].origin, 'drag');
    assert.deepStrictEqual(dispatches[0].hit, {slot:4});
    assert.strictEqual(controller.consumeClick(), true);
    assert.deepStrictEqual(controller.debugState(), {
        active:false, dragging:false, hasGhost:false, hasTarget:false
    });
    assert.strictEqual(document.body.contains(ghost), false);
    assert.strictEqual(targetNode.classList.contains('workbench-drop-active'), false);
    assert.deepStrictEqual(sourceNode.releasedPointers, [9]);
    assert.strictEqual(document.listenerCount('pointermove'), 0);
    assert.strictEqual(document.listenerCount('pointerup'), 0);
    assert.strictEqual(document.listenerCount('pointercancel'), 0);
    assert.strictEqual(ends.length, 1);

    controller.destroy();
    controller.destroy();
    assert.strictEqual(sourceElement.listenerCount('pointerdown'), 0);
}));

test('PointerDragController cancel before threshold is idempotent and does not emit drag end', () => withDocument(document => {
    const sourceElement = document.createElement('section');
    const sourceNode = document.createElement('article');
    sourceElement.appendChild(sourceNode);
    let dragEnds = 0;
    const controller = new Primitives.PointerDragController({
        sourceElement,
        getSource:() => ({view:{}, item:{id:'a'}, node:sourceNode}),
        resolveTarget:() => null,
        broker:{select() {}, dispatch() {}},
        onDragEnd:() => dragEnds++,
        timeoutMs:5000
    });
    sourceElement.dispatch('pointerdown', {
        target:sourceNode, pointerId:2, clientX:0, clientY:0
    });
    controller.cancel('manual');
    controller.cancel('again');
    assert.strictEqual(dragEnds, 0);
    assert.deepStrictEqual(sourceNode.releasedPointers, [2]);
    assert.strictEqual(document.listenerCount('pointermove'), 0);
    assert.strictEqual(document.listenerCount('pointerup'), 0);
    assert.strictEqual(document.listenerCount('pointercancel'), 0);
    controller.destroy();
    controller.destroy();
    assert.strictEqual(sourceElement.listenerCount('pointerdown'), 0);
}));

process.stdout.write('workbench primitives: ' + passed + '/' + passed + ' passed\n');
