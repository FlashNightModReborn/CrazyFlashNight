'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Config = require('../launcher/web/modules/inventory-workbench-config.js');
const Header = require('../launcher/web/modules/inventory-workbench-header.js');
const Quick = require('../launcher/web/modules/inventory-workbench-quick-transfer.js');
const OwnedView = require('../launcher/web/modules/inventory-workbench-owned-view.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

test('profile and view resolution reject unknown launch shapes', () => {
    assert.deepStrictEqual(Config.resolveProfile({profile:'warehouse'}), {
        profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50,
        rightCapacity:1200, pageColumns:6
    });
    assert.strictEqual(Config.resolveProfile({profile:'unknown'}), null);
    assert.strictEqual(Config.resolveView({view:'tuning'}), 'tuning');
    assert.strictEqual(Config.resolveView({view:'debug'}), null);
});

test('return target is normalized without retaining caller-owned objects', () => {
    const source = {returnTo:{panel:'crafting', initData:{category:'weapon', preferredRecipeIndex:'4.9', preferredCraftCount:200}}};
    const target = Config.resolveReturnTarget(source);
    assert.deepStrictEqual(target, {panel:'crafting', initData:{category:'weapon', preferredRecipeIndex:4, preferredCraftCount:99}});
    assert.notStrictEqual(target, source.returnTo);
    assert.strictEqual(Config.resolveReturnTarget({returnTo:{panel:'npcshop', initData:{category:'x'}}}), null);
});

test('confirmation preference defaults safely and normalizes writes', () => {
    const values = {};
    const preference = new Config.ConfirmationPreference({
        getItem:key => values[key],
        setItem:(key, value) => { values[key] = value; }
    });
    assert.strictEqual(preference.read(), 'safe');
    assert.strictEqual(preference.write('fast'), 'fast');
    assert.strictEqual(preference.read(), 'fast');
    assert.strictEqual(preference.write('unsafe'), 'safe');
    const blocked = new Config.ConfirmationPreference({getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }});
    assert.strictEqual(blocked.read(), 'safe');
    assert.strictEqual(blocked.write('fast'), 'fast');
});

class FakeNode {
    constructor(tag) { this.tagName = tag; this.children = []; this.listeners = {}; this.attributes = {}; this.disabled = false; this.hidden = false; }
    appendChild(node) { this.children.push(node); return node; }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] || null; }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) { this.listeners[type] = (this.listeners[type] || []).filter(item => item !== handler); }
    click() { (this.listeners.click || []).slice().forEach(handler => handler({target:this})); }
}
class FakeDocument { createElement(tag) { return new FakeNode(tag); } }

test('tuning header coordinates view, preference, disabled state, and listener teardown', () => {
    const actions = [];
    const changes = [];
    const controller = new Header.TuningHeaderController({
        document:new FakeDocument(), shell:{addHeaderAction:node => actions.push(node)},
        view:'storage', confirmationMode:'safe', onSwitch:view => changes.push('view:' + view),
        onHelp:() => changes.push('help'), onConfirmationChange:mode => changes.push('mode:' + mode)
    });
    assert.strictEqual(actions.length, 3);
    assert.strictEqual(controller.confirmationRoot.hidden, true);
    controller.switchButton.click();
    assert.deepStrictEqual(changes, ['view:tuning']);
    controller.update({view:'tuning', disabled:true});
    assert.strictEqual(controller.helpButton.hidden, false);
    assert.strictEqual(controller.switchButton.disabled, true);
    controller.update({confirmationMode:'fast'});
    assert.strictEqual(controller.switchButton.disabled, true, 'partial updates preserve the disabled gate');
    assert.strictEqual(controller.confirmationRoot.children[2].getAttribute('aria-pressed'), 'true');
    controller.destroy();
    controller.helpButton.click();
    assert.deepStrictEqual(changes, ['view:tuning']);
});

function slot(index, name, quantity) {
    return {occupied:true, physicalSlot:index, slotLease:'lease-' + index,
        item:{name:name, displayName:name, itemKind:'equipment', quantity:quantity || 1, enhancementLevel:1, rarity:'normal'}};
}

function quickFixture(options) {
    options = options || {};
    const slots = {'背包:1':slot(1, 'A'), '背包:2':slot(2, 'B'), '仓库:3':slot(3, 'C')};
    const calls = [];
    const notices = [];
    const errors = [];
    const changes = [];
    let generation = 1;
    let current = true;
    const authority = {ready:true, busyOwner:null, refreshRequired:false};
    const controller = new Quick.QuickTransferController({
        rightContainerId:'仓库', limit:options.limit || 24,
        getAuthorityState:() => authority,
        getGeneration:() => generation,
        isGenerationCurrent:value => current && value === generation,
        getSlot:(containerId, physicalSlot) => slots[containerId + ':' + physicalSlot],
        slotRef:(containerId, value) => ({containerId, slot:value.physicalSlot, expectedLease:value.slotLease}),
        autoTransfer:(source, target, done) => { calls.push({source, target, done}); return options.rejectStart ? false : true; },
        onChange:state => changes.push(state), onNotice:reason => notices.push(reason), onError:error => errors.push(error)
    });
    return {controller, slots, calls, notices, errors, changes, authority,
        setGeneration(value) { generation = value; }, setCurrent(value) { current = value; }};
}

test('quick transfer serializes intents and preserves target direction', () => {
    const f = quickFixture();
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1']), true);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), true);
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(f.calls[0].target, '仓库');
    assert.deepStrictEqual(f.controller.debugState().inFlight, '背包:1');
    assert.strictEqual(f.controller.debugState().pending, 1);
    f.calls[0].done({success:true});
    assert.strictEqual(f.calls.length, 2);
    f.calls[1].done({success:true});
    assert.strictEqual(f.controller.isBusy(), false);
    assert.strictEqual(f.controller.debugState().completed, 2);
});

test('queued duplicate toggles off while inflight duplicate is rejected', () => {
    const f = quickFixture();
    f.controller.enqueue('背包', f.slots['背包:1']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1']), false);
    assert.deepStrictEqual(f.notices, ['already_in_flight']);
    f.controller.enqueue('背包', f.slots['背包:2']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), true);
    assert.strictEqual(f.controller.debugState().pending, 0);
});

test('stale queued projection halts atomically before the authority port', () => {
    const f = quickFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1']);
    f.controller.enqueue('背包', f.slots['背包:2']);
    f.slots['背包:2'] = slot(2, 'moved');
    f.calls[0].done({success:true});
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(f.errors.length, 1);
    assert.strictEqual(f.errors[0].error, 'stale_state');
    assert.strictEqual(f.controller.getMode(), null);
    assert.strictEqual(f.controller.isBusy(), false);
});

test('mode click gate consumes only warehouse quick-transfer intents', () => {
    const f = quickFixture();
    const event = {ctrlKey:false, prevented:false, stopped:false,
        preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
    assert.strictEqual(f.controller.acceptClick(event, {profile:'battlebox', viewMode:'storage', containerId:'背包', slot:f.slots['背包:1']}), false);
    f.controller.setMode('deposit');
    assert.strictEqual(f.controller.acceptClick(event, {profile:'warehouse', viewMode:'storage', containerId:'仓库', slot:f.slots['仓库:3']}), true);
    assert.strictEqual(event.prevented, true);
    assert.deepStrictEqual(f.notices, ['deposit_source']);
});

test('queue limit and rejected authority start expose deterministic failures', () => {
    const f = quickFixture({limit:1});
    f.controller.enqueue('背包', f.slots['背包:1']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), false);
    assert.deepStrictEqual(f.notices, ['queue_full']);
    const rejected = quickFixture({rejectStart:true});
    assert.strictEqual(rejected.controller.enqueue('背包', rejected.slots['背包:1']), true);
    assert.strictEqual(rejected.errors[0].error, 'busy');
    assert.strictEqual(rejected.controller.isBusy(), false);
});

test('owned-view presentation rules centralize locked, filtered, and capacity copy', () => {
    assert.deepStrictEqual(OwnedView.presentationFor('战备箱', {accessibleCapacity:0, slots:[]}),
        {emptyText:'战备箱尚未解锁', meta:'未解锁'});
    assert.deepStrictEqual(OwnedView.presentationFor('背包', {filterKey:'weapon', accessibleCapacity:50,
        slots:[{occupied:true},{occupied:false}]}), {emptyText:'当前分类暂无物品', meta:'1 / 50'});
    assert.strictEqual(OwnedView.countOccupied([{occupied:true},{occupied:false},{occupied:true}]), 2);
});

test('facade delegates and stays below the physical line budget', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'inventory-workbench.js'), 'utf8');
    const extracted = ['inventory-workbench-config.js', 'inventory-workbench-header.js',
        'inventory-workbench-quick-transfer.js', 'inventory-workbench-owned-view.js']
        .map(file => fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', file), 'utf8')).join('\n');
    assert(source.includes('InventoryWorkbenchQuickTransfer.QuickTransferController'));
    assert(source.includes('InventoryWorkbenchHeader.TuningHeaderController'));
    assert(source.includes('InventoryWorkbenchOwnedView.createView'));
    assert(!/Bridge\.send|RequestMux|InventoryCoordinator/.test(extracted), 'extracted modules must not own transport or authority');
    assert(source.split(/\r?\n/).length < 1000);
});

process.stdout.write('Inventory workbench modules: ' + passed + '/' + passed + ' passed\n');
