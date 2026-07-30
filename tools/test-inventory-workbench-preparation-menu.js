'use strict';

const assert = require('assert');
const Menu = require(
    '../launcher/web/modules/inventory-workbench-preparation-menu.js');
const Header = require(
    '../launcher/web/modules/inventory-workbench-header.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

class FakeNode {
    constructor(document, tag) {
        this.ownerDocument = document;
        this.tagName = String(tag || '').toUpperCase();
        this.children = [];
        this.parentNode = null;
        this.listeners = {};
        this.attributes = {};
        this.hidden = false;
        this.tabIndex = 0;
        this.textContent = '';
        this.id = '';
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
    setAttribute(name, value) {
        this.attributes[name] = String(value);
        if (name === 'id') this.id = String(value);
    }
    getAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name)
            ? this.attributes[name]
            : null;
    }
    hasAttribute(name) {
        return Object.prototype.hasOwnProperty.call(this.attributes, name);
    }
    removeAttribute(name) {
        delete this.attributes[name];
    }
    addEventListener(type, handler) {
        (this.listeners[type] = this.listeners[type] || []).push(handler);
    }
    removeEventListener(type, handler) {
        this.listeners[type] = (this.listeners[type] || [])
            .filter(value => value !== handler);
    }
    contains(node) {
        if (node === this) return true;
        return this.children.some(child => child.contains(node));
    }
    focus() {
        this.ownerDocument.activeElement = this;
        this.ownerDocument.dispatch('focusin', {target:this});
    }
    dispatch(type, options) {
        const event = Object.assign({
            type:type,
            target:this,
            currentTarget:this,
            key:'',
            shiftKey:false,
            defaultPrevented:false,
            propagationStopped:false,
            preventDefault() { this.defaultPrevented = true; },
            stopPropagation() { this.propagationStopped = true; }
        }, options || {});
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    click() {
        return this.dispatch('click');
    }
}

class FakeDocument {
    constructor() {
        this.listeners = {};
        this.activeElement = null;
        this.body = new FakeNode(this, 'body');
    }
    createElement(tag) {
        return new FakeNode(this, tag);
    }
    addEventListener(type, handler) {
        (this.listeners[type] = this.listeners[type] || []).push(handler);
    }
    removeEventListener(type, handler) {
        this.listeners[type] = (this.listeners[type] || [])
            .filter(value => value !== handler);
    }
    dispatch(type, options) {
        const event = Object.assign({type:type, target:null}, options || {});
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    listenerCount(type) {
        return (this.listeners[type] || []).length;
    }
}

class FakeUiData {
    constructor(q) {
        this.q = q;
        this.handlers = [];
        this.onCount = 0;
        this.offCount = 0;
    }
    get(key) {
        return key === 'q' ? this.q : undefined;
    }
    on(key, handler) {
        assert.strictEqual(key, 'q');
        this.onCount++;
        this.handlers.push(handler);
    }
    off(key, handler) {
        assert.strictEqual(key, 'q');
        this.offCount++;
        this.handlers = this.handlers.filter(value => value !== handler);
    }
    emit(value) {
        this.q = value;
        this.handlers.slice().forEach(handler => handler(value));
    }
}

function item(controller, identity) {
    return controller._items[identity].node;
}

function project(controller) {
    const projection = Header.InventoryWorkbenchHeaderProjection({
        view:'build',
        preparationNavigationV1:true,
        preparationAvailability:controller.getAvailability()
    });
    controller.applyProjection(projection.preparationItems);
    return projection;
}

function createController(q) {
    const document = new FakeDocument();
    const host = document.createElement('nav');
    const uiData = new FakeUiData(q);
    const selected = [];
    let controller = null;
    controller = new Menu.PreparationMenuController({
        document,
        host,
        uiData,
        onSelect:(identity, opener) => {
            selected.push({identity, opener});
            return true;
        },
        onChange:() => project(controller)
    });
    project(controller);
    return {document, host, uiData, selected, controller};
}

test('frozen route tuple matches C# identities, labels, order, and destination kinds', () => {
    assert.deepStrictEqual(
        Menu.ROUTES.map(route => [
            route.identity,
            route.label,
            route.destinationKind
        ]),
        [
            ['equipment', '装备', 'current'],
            ['battlebox', '战备箱', 'local-view'],
            ['tuning', '装备调制', 'local-view'],
            ['skills', '技能', 'post-close'],
            ['materials', '材料', 'post-close'],
            ['intelligence', '情报', 'post-close']
        ]);
    assert(Object.isFrozen(Menu.ROUTES));
    assert(Menu.ROUTES.every(Object.isFrozen));
});

test('q projection is exact at 13/14 and malformed values fail closed', () => {
    for (const blocked of [13, '13', undefined, '', '14x', 14.5, {}, []]) {
        const state = Menu.projectAvailability(blocked, false, '');
        assert.deepStrictEqual(state.battlebox, {
            visible:true,
            disabled:true,
            reason:Menu.PROGRESSION_REASON
        });
        assert.deepStrictEqual(state.tuning, state.battlebox);
    }
    const ready = Menu.projectAvailability('14', false, '');
    assert.deepStrictEqual(ready.battlebox, {
        visible:true,
        disabled:false,
        reason:''
    });
    assert.deepStrictEqual(ready.equipment, {
        visible:true,
        disabled:true,
        reason:'当前'
    });
    assert.deepStrictEqual(Object.keys(ready), Header.PREPARATION_KEYS);
    Object.values(ready).forEach(value => {
        assert.deepStrictEqual(
            Object.keys(value),
            ['visible', 'disabled', 'reason']);
    });
});

test('write lock retains every item and supplies a concrete readable reason', () => {
    const locked = Menu.projectAvailability(14, true, '等待权威写入完成');
    Object.values(locked).forEach(value => assert.strictEqual(value.visible, true));
    assert.strictEqual(locked.equipment.reason, '当前');
    for (const identity of Header.PREPARATION_KEYS.slice(1)) {
        assert.strictEqual(locked[identity].disabled, true);
        assert.strictEqual(locked[identity].reason, '等待权威写入完成');
    }
    const fallback = Menu.projectAvailability(14, true, '');
    assert(fallback.skills.reason.length > 0);
});

test('trigger and current item expose exact menu semantics without dispatching equipment', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    assert.strictEqual(controller.trigger.textContent, '整备 ▾');
    assert.strictEqual(controller.trigger.getAttribute('aria-haspopup'), 'menu');
    assert.strictEqual(controller.trigger.getAttribute('aria-expanded'), 'false');
    const enterOpen = controller.trigger.dispatch('keydown', {key:'Enter'});
    assert.strictEqual(enterOpen.defaultPrevented, true);
    assert.strictEqual(controller.isOpen(), true);
    const enterClose = controller.trigger.dispatch('keydown', {key:'Enter'});
    assert.strictEqual(enterClose.defaultPrevented, true);
    assert.strictEqual(controller.isOpen(), false);
    const spaceOpen = controller.trigger.dispatch('keydown', {key:' '});
    assert.strictEqual(spaceOpen.defaultPrevented, true);
    assert.strictEqual(controller.isOpen(), true);
    const spaceClose = controller.trigger.dispatch('keydown', {key:'Spacebar'});
    assert.strictEqual(spaceClose.defaultPrevented, true);
    assert.strictEqual(controller.isOpen(), false);
    controller.trigger.dispatch('keydown', {key:'ArrowDown'});
    assert.strictEqual(controller.isOpen(), true);
    assert.strictEqual(controller.trigger.getAttribute('aria-expanded'), 'true');
    assert.strictEqual(fixture.document.activeElement, item(controller, 'equipment'));
    assert.strictEqual(
        item(controller, 'equipment').getAttribute('aria-current'),
        'page');
    assert.strictEqual(
        item(controller, 'equipment').getAttribute('aria-disabled'),
        'true');
    const enter = item(controller, 'equipment').dispatch(
        'keydown',
        {key:'Enter'});
    assert.strictEqual(enter.defaultPrevented, true);
    assert.deepStrictEqual(fixture.selected, []);
    assert.strictEqual(controller.isOpen(), true);
    controller.destroy();
});

test('Arrow/Home/End wrap all readable items and enabled activation emits fixed identity', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    controller.trigger.dispatch('keydown', {key:'Enter'});
    item(controller, 'equipment').dispatch('keydown', {key:'ArrowUp'});
    assert.strictEqual(
        fixture.document.activeElement,
        item(controller, 'intelligence'));
    item(controller, 'intelligence').dispatch('keydown', {key:'Home'});
    assert.strictEqual(
        fixture.document.activeElement,
        item(controller, 'equipment'));
    item(controller, 'equipment').dispatch('keydown', {key:'End'});
    assert.strictEqual(
        fixture.document.activeElement,
        item(controller, 'intelligence'));
    item(controller, 'intelligence').dispatch('keydown', {key:'ArrowDown'});
    assert.strictEqual(
        fixture.document.activeElement,
        item(controller, 'equipment'));
    item(controller, 'equipment').dispatch('keydown', {key:'ArrowDown'});
    item(controller, 'battlebox').dispatch('keydown', {key:' '});
    assert.deepStrictEqual(
        fixture.selected.map(value => value.identity),
        ['battlebox']);
    assert.strictEqual(controller.isOpen(), false);
    controller.destroy();
});

test('all five destinations preserve fixed identity while disabled routes remain inert', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    for (const identity of [
        'battlebox',
        'tuning',
        'skills',
        'materials',
        'intelligence'
    ]) {
        controller.open(false);
        item(controller, identity).click();
    }
    assert.deepStrictEqual(
        fixture.selected.map(value => value.identity),
        ['battlebox', 'tuning', 'skills', 'materials', 'intelligence']);
    controller.updateLock(true, '正在对账');
    project(controller);
    controller.open(false);
    item(controller, 'skills').click();
    assert.strictEqual(fixture.selected.length, 5);
    assert.strictEqual(controller.isOpen(), true);
    controller.destroy();
});

test('dynamic q and lock updates mutate stable nodes without closing or moving focus', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    controller.open(true);
    item(controller, 'equipment').dispatch('keydown', {key:'ArrowDown'});
    const battlebox = item(controller, 'battlebox');
    assert.strictEqual(fixture.document.activeElement, battlebox);
    fixture.uiData.emit('13');
    assert.strictEqual(item(controller, 'battlebox'), battlebox);
    assert.strictEqual(fixture.document.activeElement, battlebox);
    assert.strictEqual(controller.isOpen(), true);
    assert.strictEqual(battlebox.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(
        controller._items.battlebox.reason.textContent,
        Menu.PROGRESSION_REASON);
    controller.updateLock(true, '等待角色构筑写入');
    project(controller);
    assert.strictEqual(fixture.document.activeElement, battlebox);
    assert.strictEqual(controller.isOpen(), true);
    controller.destroy();
});

test('Escape restores trigger while Tab and Shift+Tab close without trapping', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    controller.open(true);
    const escape = item(controller, 'equipment').dispatch(
        'keydown',
        {key:'Escape'});
    assert.strictEqual(escape.defaultPrevented, true);
    assert.strictEqual(escape.propagationStopped, true);
    assert.strictEqual(fixture.document.activeElement, controller.trigger);
    for (const shiftKey of [false, true]) {
        controller.open(true);
        const tab = item(controller, 'equipment').dispatch(
            'keydown',
            {key:'Tab', shiftKey});
        assert.strictEqual(tab.defaultPrevented, false);
        assert.strictEqual(tab.propagationStopped, false);
        assert.strictEqual(controller.isOpen(), false);
        assert.strictEqual(
            fixture.document.activeElement,
            item(controller, 'equipment'));
    }
    controller.destroy();
});

test('outside click, suppression, and repeated open never leak document listeners', () => {
    const fixture = createController(14);
    const controller = fixture.controller;
    const outside = fixture.document.createElement('button');
    controller.open(false);
    controller.open(false);
    assert.strictEqual(fixture.document.listenerCount('pointerdown'), 1);
    assert.strictEqual(fixture.document.listenerCount('focusin'), 1);
    fixture.document.dispatch('pointerdown', {target:outside});
    assert.strictEqual(controller.isOpen(), false);
    assert.strictEqual(fixture.document.listenerCount('pointerdown'), 0);
    assert.strictEqual(fixture.document.listenerCount('focusin'), 0);
    controller.open(false);
    controller.setSuppressed(true);
    assert.strictEqual(controller.wrapper.hidden, true);
    assert.strictEqual(controller.wrapper.hasAttribute('inert'), true);
    assert.strictEqual(fixture.document.listenerCount('pointerdown'), 0);
    controller.setSuppressed(false);
    assert.strictEqual(controller.wrapper.hidden, false);
    assert.strictEqual(controller.wrapper.hasAttribute('inert'), false);
    controller.destroy();
});

test('destroy unsubscribes q and removes every active document listener exactly once', () => {
    const fixture = createController(14);
    fixture.controller.open(false);
    assert.strictEqual(fixture.uiData.onCount, 1);
    assert.strictEqual(fixture.uiData.handlers.length, 1);
    assert.strictEqual(fixture.controller.destroy(), true);
    assert.strictEqual(fixture.controller.destroy(), false);
    assert.strictEqual(fixture.uiData.offCount, 1);
    assert.strictEqual(fixture.uiData.handlers.length, 0);
    assert.strictEqual(fixture.document.listenerCount('pointerdown'), 0);
    assert.strictEqual(fixture.document.listenerCount('focusin'), 0);
    assert.strictEqual(fixture.host.children.length, 0);
});

process.stdout.write(
    'Inventory preparation menu: ' + passed + '/' + passed + ' passed\n');
