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
    dispatch(type, init) {
        const event = Object.assign({type, target:this, preventDefault() { this.defaultPrevented = true; }}, init || {});
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
    dispatch(type, init) {
        const event = Object.assign({type, target:this}, init || {});
        (this.listeners[type] || []).slice().forEach(handler => handler(event));
        return event;
    }
    listenerCount(type) { return (this.listeners[type] || []).length; }
}

test('exports the eight shared primitives', () => {
    assert.deepStrictEqual(Object.keys(Components).sort(), [
        'ChoiceGroup', 'CommitBar', 'Dropdown', 'HelpAction', 'OwnedInventoryPane', 'ProcurementHighlight', 'QuantityControl', 'SecondaryPage'
    ]);
});

test('production module consumes the shared DisposableStack contract', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'workbench-components.js'), 'utf8');
    assert(source.includes("require('./workbench-lifecycle.js')"));
    assert(source.includes('WorkbenchLifecycle.DisposableStack'));
    assert(!source.includes('this._disposers'));
});

test('HelpAction exposes the stable header identity without coupling help to capability', () => {
    const document = new FakeDocument();
    const actions = [];
    const modals = [];
    const shell = {
        addHeaderAction(node) { actions.push(node); },
        openModal(spec) { modals.push(spec); }
    };
    const help = new Components.HelpAction({
        document,
        shell,
        spec:{ariaLabel:'查看测试帮助'}
    });
    assert.strictEqual(actions.length, 1);
    assert.strictEqual(help.button.getAttribute('data-header-action'), 'help');
    assert.strictEqual(help.button.disabled, false);
    assert.strictEqual(help.open(), true);
    assert.strictEqual(modals.length, 1);
    assert.strictEqual(help.button.disabled, false);
    help.update(null);
    assert.strictEqual(help.button.hidden, true);
    assert.strictEqual(help.open(), false);
    assert.strictEqual(help.destroy(), true);
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
    assert.strictEqual(page.bindBack(back), true);
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

test('SecondaryPage keeps Back, Help, and Close as distinct exact actions', () => {
    const document = new FakeDocument();
    const host = document.createElement('main');
    const back = document.createElement('button');
    const help = document.createElement('button');
    const close = document.createElement('button');
    const events = [];
    const page = new Components.SecondaryPage({
        document,
        onClose:reason => events.push('lifecycle:' + reason)
    });
    page.mount(host);
    page.bindBack(back, () => events.push('back'));
    page.bindHelp(help, () => events.push('help'));
    page.bindClose(close, () => events.push('close'));
    assert.strictEqual(back.getAttribute('data-secondary-action'), 'back');
    assert.strictEqual(help.getAttribute('data-secondary-action'), 'help');
    assert.strictEqual(close.getAttribute('data-secondary-action'), 'close');

    page.open();
    help.dispatch('click');
    assert.strictEqual(page.isActive(), true);
    assert.deepStrictEqual(events, ['help']);
    back.dispatch('click');
    assert.deepStrictEqual(events, ['help', 'back', 'lifecycle:back']);

    page.open();
    close.dispatch('click');
    assert.deepStrictEqual(events, ['help', 'back', 'lifecycle:back', 'close', 'lifecycle:close']);
    page.destroy();
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

test('ChoiceGroup rolls presentation back when onChange rejects or throws', () => {
    const document = new FakeDocument();
    let mode = 'reject';
    const group = new Components.ChoiceGroup({
        document,
        value:'safe',
        choices:[
            {value:'safe', label:'Safe'},
            {value:'fast', label:'Fast'}
        ],
        onChange() {
            if (mode === 'reject') return false;
            if (mode === 'throw') throw new Error('storage unavailable');
            return true;
        }
    });

    assert.strictEqual(group.setValue('fast'), false);
    assert.strictEqual(group.getValue(), 'safe');
    assert.strictEqual(group.getButton('safe').getAttribute('aria-pressed'), 'true');
    assert.strictEqual(group.getButton('fast').getAttribute('aria-pressed'), 'false');

    mode = 'throw';
    assert.throws(() => group.setValue('fast'), /storage unavailable/);
    assert.strictEqual(group.getValue(), 'safe');
    assert.strictEqual(group.getButton('safe').classList.contains('active'), true);

    mode = 'accept';
    assert.strictEqual(group.setValue('fast'), true);
    assert.strictEqual(group.getValue(), 'fast');
    group.destroy();
});

test('Dropdown owns listbox keyboard, outside-close, and listener teardown', () => {
    const document = new FakeDocument();
    const host = document.createElement('header');
    const outside = document.createElement('button');
    const changes = [];
    const dropdown = new Components.Dropdown({
        document,
        value:'archive',
        labelPrefix:'排序：',
        ariaLabel:'材料排序',
        choices:[
            {value:'archive', label:'档案顺序'},
            {value:'owned', label:'持有数'},
            {value:'name', label:'名称'}
        ],
        onChange:value => changes.push(value)
    });
    dropdown.mount(host);
    assert.strictEqual(dropdown.trigger.getAttribute('aria-haspopup'), 'listbox');
    assert.strictEqual(dropdown.trigger.getAttribute('aria-expanded'), 'false');
    assert.strictEqual(dropdown.trigger.textContent, '排序：档案顺序');
    assert.strictEqual(document.listenerCount('pointerdown'), 1);

    let event = dropdown.trigger.dispatch('keydown', {key:'ArrowDown'});
    assert.strictEqual(event.defaultPrevented, true);
    assert.strictEqual(dropdown.isOpen(), true);
    assert.strictEqual(dropdown.trigger.getAttribute('aria-expanded'), 'true');
    assert.strictEqual(document.activeElement, dropdown.getOption('archive'));
    dropdown.getOption('owned').dispatch('keydown', {key:'Enter'});
    assert.strictEqual(dropdown.getValue(), 'owned');
    assert.strictEqual(dropdown.isOpen(), false);
    assert.strictEqual(document.activeElement, dropdown.trigger);
    assert.deepStrictEqual(changes, ['owned']);

    dropdown.trigger.dispatch('keydown', {key:'ArrowUp'});
    assert.strictEqual(document.activeElement, dropdown.getOption('owned'));
    dropdown.getOption('owned').dispatch('keydown', {key:'Escape'});
    assert.strictEqual(dropdown.isOpen(), false);
    assert.strictEqual(document.activeElement, dropdown.trigger);

    dropdown.open();
    const option = dropdown.getOption('owned');
    option.focus();
    option.dispatch('keydown', {key:'Tab'});
    assert.strictEqual(dropdown.isOpen(), false);
    assert.strictEqual(document.activeElement, option, 'Tab close must not steal focus');
    dropdown.open();
    document.dispatch('pointerdown', {target:outside});
    assert.strictEqual(dropdown.isOpen(), false);

    assert.strictEqual(dropdown.destroy(), true);
    assert.strictEqual(document.listenerCount('pointerdown'), 0);
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

test('QuantityControl unifies valid direct input, slider, preset maximum, and bounded buttons', () => {
    const document = new FakeDocument();
    const changes = [];
    const control = new Components.QuantityControl({
        document,
        min:1,
        max:10,
        presetMax:7,
        value:2,
        onChange:(value, reason) => changes.push([value, reason])
    });
    assert.strictEqual(control.getValue(), 2);
    assert.strictEqual(control.numberInput.value, '2');
    assert.strictEqual(control.rangeInput.max, '10');

    control.numberInput.value = '';
    control.numberInput.dispatch('input');
    assert.strictEqual(control.numberInput.value, '');
    assert.strictEqual(control.rangeInput.value, '2');
    assert.strictEqual(control.numberInput.getAttribute('aria-invalid'), 'true');
    control.numberInput.value = '8';
    control.numberInput.dispatch('input');
    assert.strictEqual(control.numberInput.value, '8');
    assert.strictEqual(control.rangeInput.value, '8');
    assert.strictEqual(control.numberInput.getAttribute('aria-invalid'), 'false');
    control.numberInput.dispatch('change');
    control.rangeInput.value = '4';
    control.rangeInput.dispatch('input');
    assert.strictEqual(control.numberInput.value, '4');
    control.rangeInput.dispatch('change');
    control.plusFiveButton.dispatch('click');
    control.maxButton.dispatch('click');
    control.numberInput.value = '99';
    control.numberInput.dispatch('change');

    assert.strictEqual(control.getValue(), 7);
    assert.strictEqual(control.numberInput.value, '99');
    assert.strictEqual(control.numberInput.getAttribute('aria-invalid'), 'true');
    assert.strictEqual(control.feedback.hidden, false);
    control.numberInput.value = '10';
    control.numberInput.dispatch('input');
    control.numberInput.dispatch('change');
    assert.strictEqual(control.getValue(), 10);
    assert.deepStrictEqual(changes, [
        [8, 'number'], [4, 'range'], [9, 'increment_five'], [7, 'maximum'], [10, 'number']
    ]);
    control.update({presetMax:0, value:5});
    assert.strictEqual(control.maxButton.disabled, true);
    control.maxButton.dispatch('click');
    assert.strictEqual(control.getValue(), 5);
    control.update({onChange:() => { throw new Error('preview failed'); }});
    control.numberInput.focus();
    assert.throws(
        () => control.setValue(6, {notify:true, reason:'number'}),
        /preview failed/
    );
    assert.strictEqual(control._changeFocusOrigin, null,
        'a failed preview callback must not retain a stale focus origin');
    control.update({disabled:true, value:10});
    control.minusButton.dispatch('click');
    assert.strictEqual(control.getValue(), 10);
    assert.strictEqual(control.numberInput.disabled, true);
    assert.strictEqual(control.destroy(), true);
    assert.strictEqual(control.numberInput.listenerCount('change'), 0);
    assert.strictEqual(control.rangeInput.listenerCount('change'), 0);
});

test('QuantityControl gives low values usable travel while authority and feasible bounds remain distinct', () => {
    const document = new FakeDocument();
    const changes = [];
    const control = new Components.QuantityControl({
        document,
        min:1,
        max:999999,
        sliderMax:999999,
        presetMax:100,
        value:1,
        onChange:(value, reason) => changes.push([value, reason])
    });
    assert.strictEqual(control.numberInput.max, '999999');
    assert.strictEqual(control.rangeInput.min, '0');
    assert.strictEqual(control.rangeInput.max, '1000');
    assert.strictEqual(control.root.getAttribute('data-slider-scale'), 'log');
    assert.strictEqual(control.root.getAttribute('data-slider-max'), '999999');
    assert.strictEqual(control.root.getAttribute('data-preset-max'), '100');
    assert.strictEqual(control.rangeMarker.hidden, false);

    control.setValue(10);
    const tenPosition = Number(control.rangeInput.value);
    assert(tenPosition >= 150 && tenPosition <= 180,
        'quantity 10 should occupy a meaningful low-end track segment, got ' + tenPosition);
    assert.strictEqual(control.rangeInput.getAttribute('aria-valuetext'), '10；当前可直接结算 100');

    control.rangeInput.value = '500';
    control.rangeInput.dispatch('input');
    const midpointQuantity = Number(control.numberInput.value);
    assert(midpointQuantity >= 900 && midpointQuantity <= 1100,
        'log midpoint should resolve near 1,000, got ' + midpointQuantity);
    control.rangeInput.dispatch('change');
    assert.strictEqual(control.getValue(), midpointQuantity);
    assert.deepStrictEqual(changes, [[midpointQuantity, 'range']]);

    control.numberInput.value = '999999';
    control.numberInput.dispatch('change');
    assert.strictEqual(control.getValue(), 999999);
    assert.strictEqual(control.rangeInput.value, '1000');

    control.update({sliderMax:999999, presetMax:0, value:7});
    assert.strictEqual(control.numberInput.disabled, false);
    assert.strictEqual(control.rangeInput.hidden, false);
    assert.strictEqual(control.rangeInput.min, '0');
    assert.strictEqual(control.rangeInput.max, '1000');
    assert.strictEqual(control.rangeInput.getAttribute('aria-valuemin'), '1');
    assert.strictEqual(control.rangeInput.getAttribute('aria-valuemax'), '999999');
    assert.strictEqual(control.getValue(), 7);
    assert.strictEqual(control.maxButton.disabled, true);
});

test('QuantityControl rejects malformed drafts without preview callbacks', () => {
    const document = new FakeDocument();
    const changes = [];
    const control = new Components.QuantityControl({
        document, min:1, max:50, presetMax:20, value:4,
        onChange:(value, reason) => changes.push([value, reason])
    });
    ['', '1.5', '-2', '51', 'hello'].forEach(value => {
        control.numberInput.value = value;
        control.numberInput.dispatch('input');
        control.numberInput.dispatch('change');
        assert.strictEqual(control.getValue(), 4);
        assert.strictEqual(control.numberInput.getAttribute('aria-invalid'), 'true');
        assert.strictEqual(control.feedback.hidden, false);
    });
    assert.deepStrictEqual(changes, []);
    control.numberInput.value = '05';
    control.numberInput.dispatch('input');
    control.numberInput.dispatch('change');
    assert.strictEqual(control.getValue(), 5);
    assert.deepStrictEqual(changes, [[5, 'number']]);
});

test('QuantityControl range keyboard changes actual quantities rather than logarithmic positions', () => {
    const document = new FakeDocument();
    const changes = [];
    const control = new Components.QuantityControl({
        document, min:1, max:999999, presetMax:100, sliderMax:999999, value:1,
        onChange:(value, reason) => changes.push([value, reason])
    });
    let event = control.rangeInput.dispatch('keydown', {key:'ArrowRight'});
    assert.strictEqual(event.defaultPrevented, true);
    assert.strictEqual(control.getValue(), 2);
    control.rangeInput.dispatch('keydown', {key:'ArrowRight', shiftKey:true});
    assert.strictEqual(control.getValue(), 7);
    control.rangeInput.dispatch('keydown', {key:'PageUp'});
    assert.strictEqual(control.getValue(), 10);
    control.rangeInput.dispatch('keydown', {key:'End'});
    assert.strictEqual(control.getValue(), 999999);
    control.rangeInput.dispatch('keydown', {key:'PageDown'});
    assert.strictEqual(control.getValue(), 500000);
    control.rangeInput.dispatch('keydown', {key:'Home'});
    assert.strictEqual(control.getValue(), 1);
    assert(changes.every(change => change[1] === 'range_keyboard'));
});

test('QuantityControl covers linear/log boundary and effective-limit edge states', () => {
    const document = new FakeDocument();
    [
        {authority:1, effective:0, scale:'linear', hidden:true},
        {authority:50, effective:0, scale:'linear', hidden:false},
        {authority:200, effective:50, scale:'linear', hidden:false},
        {authority:201, effective:201, scale:'log', hidden:false},
        {authority:999999, effective:100, scale:'log', hidden:false}
    ].forEach(entry => {
        const control = new Components.QuantityControl({
            document, min:1, max:entry.authority, sliderMax:entry.authority,
            presetMax:entry.effective, value:1
        });
        assert.strictEqual(control.root.getAttribute('data-slider-scale'), entry.scale);
        assert.strictEqual(control.rangeInput.hidden, entry.hidden);
        assert.strictEqual(control.rangeInput.getAttribute('aria-valuemax'), String(entry.authority));
        assert.strictEqual(control.maxButton.disabled, entry.effective < 1 || entry.effective === 1);
        if (entry.effective > 0 && entry.effective < entry.authority) {
            assert.strictEqual(control.rangeMarker.hidden, false);
        }
        control.destroy();
    });
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

test('OwnedInventoryPane projects inspectability and action authority to its consumer', () => {
    const document = new FakeDocument();
    const root = document.createElement('section');
    const projections = [];
    const transfers = [];
    const pane = new Components.OwnedInventoryPane({
        root,
        onInteractionChange(projection) {
            projections.push(projection);
        },
        onQuickTransfer(intent) {
            transfers.push(intent);
            return true;
        }
    });

    assert.deepStrictEqual(projections[0], {
        inspectable:true,
        actionable:true,
        reason:''
    });
    assert.strictEqual(root.getAttribute('aria-disabled'), 'false');
    assert.strictEqual(root.getAttribute('data-owned-inspectable'), 'true');
    assert.strictEqual(root.getAttribute('data-owned-actionable'), 'true');

    pane.setInteraction({
        inspectable:true,
        actionable:false,
        reason:'正在重新同步'
    });
    assert.deepStrictEqual(projections[1], {
        inspectable:true,
        actionable:false,
        reason:'正在重新同步'
    });
    assert.strictEqual(root.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(root.getAttribute('data-owned-inspectable'), 'true');
    assert.strictEqual(root.getAttribute('data-owned-actionable'), 'false');
    assert.strictEqual(root.getAttribute('data-owned-disabled-reason'), '正在重新同步');
    assert.strictEqual(pane.quickTransfer({physicalSlot:2}, 'warehouse'), false);
    assert.strictEqual(transfers.length, 0);
    assert.deepStrictEqual(pane.debugState().interaction, {
        inspectable:true,
        actionable:false,
        reason:'正在重新同步'
    });

    pane.setDisabled(false);
    assert.strictEqual(root.getAttribute('aria-disabled'), 'false');
    assert.strictEqual(root.getAttribute('data-owned-disabled-reason'), null);
    assert.strictEqual(pane.quickTransfer({physicalSlot:2}, 'warehouse'), true);
    assert.strictEqual(transfers.length, 1);
    pane.destroy();
});

test('shared lifecycle teardown keeps listener ownership flat across updates and repeated destroy', () => {
    const document = new FakeDocument();
    const back = document.createElement('button');
    const page = new Components.SecondaryPage({document});
    page.bindBack(back);
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
