#!/usr/bin/env node
'use strict';

// Quick-transfer source strategies: physical container slots keep prefix batch semantics and
// gain an optional source quantity; the shared stash source keys on entryId/revision, forbids
// deposit/reverse intake, and settles non-prefix accepted/blocked rows. Also covers the
// inventory-runtime wire passthrough of source quantity (move/merge/autoTransfer/batch only).

const assert = require('assert');
const path = require('path');
const Quick = require(path.resolve(__dirname, '..', 'launcher', 'web', 'modules',
    'inventory-workbench-quick-transfer.js'));
const Runtime = require(path.resolve(__dirname, '..', 'launcher', 'web', 'modules',
    'inventory-runtime.js'));

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

function stackSlot(index, name, quantity, lease) {
    return {occupied:true, physicalSlot:index, slotLease:lease || ('lease-' + index),
        item:{name:name, displayName:name, itemKind:'stack', quantity:quantity,
            enhancementLevel:0, rarity:'normal'}};
}
function equipSlot(index, name, lease) {
    return {occupied:true, physicalSlot:index, slotLease:lease || ('lease-' + index),
        item:{name:name, displayName:name, itemKind:'equipment', quantity:1,
            enhancementLevel:1, rarity:'normal'}};
}
function stashEntry(entryId, name, quantity, revision) {
    return {occupied:true, entryId:entryId, revision:revision, quantity:quantity,
        item:{name:name, displayName:name, itemKind:'stack', quantity:quantity,
            enhancementLevel:0, rarity:'normal'}};
}

function containerFixture(options) {
    options = options || {};
    const slots = {'背包:1':stackSlot(1, '药剂', 10), '背包:2':stackSlot(2, '材料', 5),
        '背包:3':equipSlot(3, '步枪'), '仓库:4':stackSlot(4, '仓库件', 7)};
    const calls = [];
    const batchCalls = [];
    const notices = [];
    const errors = [];
    let generation = 1;
    let current = true;
    const authority = {ready:true, busyOwner:null, refreshRequired:false};
    const controller = new Quick.QuickTransferController({
        rightContainerId:'仓库', limit:options.limit || 24,
        getAuthorityState:() => authority,
        getGeneration:() => generation,
        isGenerationCurrent:value => current && value === generation,
        getSlot:(containerId, id) => slots[containerId + ':' + id] || null,
        slotRef:(containerId, slot, quantity) => {
            const ref = {containerId, slot:slot.physicalSlot, expectedLease:slot.slotLease};
            if (quantity != null) ref.quantity = quantity;
            return ref;
        },
        autoTransfer:(source, target, done) => { calls.push({source, target, done}); return true; },
        autoTransferBatch:(sources, target, done) => {
            batchCalls.push({sources, target, done}); return true;
        },
        onNotice:reason => notices.push(reason), onError:error => errors.push(error)
    });
    return {controller, slots, calls, batchCalls, notices, errors, authority,
        setGeneration(value) { generation = value; }, setCurrent(value) { current = value; }};
}

function stashFixture(entryList, options) {
    options = options || {};
    const entries = {};
    entryList.forEach(entry => { entries[entry.entryId] = entry; });
    const calls = [];
    const batchCalls = [];
    const notices = [];
    const errors = [];
    let generation = 1;
    let current = true;
    const authority = {ready:true, busyOwner:null, refreshRequired:false};
    const controller = new Quick.QuickTransferController({
        rightContainerId:'stash', sourceKind:'stash', limit:32,
        keyOf:(containerId, slot) => 'stash:' + String(slot && slot.entryId),
        slotId:slot => String(slot && slot.entryId),
        identityOf:(containerId, slot) => String(slot && slot.revision),
        getAuthorityState:() => authority,
        getGeneration:() => generation,
        isGenerationCurrent:value => current && value === generation,
        getSlot:(containerId, id) => entries[String(id)] || null,
        slotRef:(containerId, slot, quantity) => ({entryId:String(slot.entryId),
            revision:slot.revision, quantity:quantity != null ? quantity : slot.quantity}),
        autoTransfer:(source, target, done) => { calls.push({source, target, done}); return true; },
        autoTransferBatch:(sources, target, done) => {
            batchCalls.push({sources, target, done}); return true;
        },
        onNotice:reason => notices.push(reason), onError:error => errors.push(error)
    });
    return {controller, entries, calls, batchCalls, notices, errors, authority,
        setGeneration(value) { generation = value; }, setCurrent(value) { current = value; }};
}

test('single transfer passes an optional quantity through the slotRef port', () => {
    const f = containerFixture();
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1'], false, 3), true);
    assert.strictEqual(f.calls.length, 1);
    assert.deepStrictEqual(f.calls[0].source,
        {containerId:'背包', slot:1, expectedLease:'lease-1', quantity:3});
    assert.strictEqual(f.calls[0].target, '仓库');
    f.calls[0].done({success:true});
    assert.strictEqual(f.controller.debugState().completed, 1);
});

test('single transfer without quantity keeps the closed three-field source ref', () => {
    const f = containerFixture();
    f.controller.enqueue('背包', f.slots['背包:2']);
    assert.deepStrictEqual(f.calls[0].source,
        {containerId:'背包', slot:2, expectedLease:'lease-2'});
    assert.strictEqual('quantity' in f.calls[0].source, false);
});

test('batch keeps ordered prefix semantics and per-source quantity', () => {
    const f = containerFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1'], true, 4);
    f.controller.enqueue('背包', f.slots['背包:2'], true);
    assert.strictEqual(f.controller.commit(), true);
    assert.deepStrictEqual(f.batchCalls[0].sources, [
        {containerId:'背包', slot:1, expectedLease:'lease-1', quantity:4},
        {containerId:'背包', slot:2, expectedLease:'lease-2'}
    ]);
    f.batchCalls[0].done({success:true, completedCount:1,
        failure:{index:1, error:'target_full'}});
    assert.strictEqual(f.controller.debugState().completed, 1);
    assert.strictEqual(f.errors.length, 1);
    assert.strictEqual(f.errors[0].error, 'target_full');
    assert.deepStrictEqual(f.errors[0].failure, {index:1, error:'target_full'});
});

test('quantity is a strict positive safe integer bounded by the current stack', () => {
    const f = containerFixture();
    [0, -1, 1.5, NaN, Infinity, '3', 11, 9007199254740992].forEach(quantity => {
        assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1'], false, quantity), false,
            'quantity ' + String(quantity) + ' rejected');
    });
    assert.deepStrictEqual(f.notices, Array(8).fill('invalid_quantity'));
    assert.strictEqual(f.calls.length, 0);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:3'], false, 1), false,
        'equipment cannot be split');
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1'], false, 10), true);
    f.calls[0].done({success:true});
});

test('stash source forbids deposit mode and backpack reverse intake', () => {
    const f = stashFixture([stashEntry('e1', '材料', 8, 11)]);
    assert.strictEqual(f.controller.debugState().sourceKind, 'stash');
    assert.strictEqual(f.controller.setMode('deposit'), false);
    assert.deepStrictEqual(f.notices, ['mode_not_supported']);
    const event = {ctrlKey:true, preventDefault() {}, stopPropagation() {}};
    assert.strictEqual(f.controller.acceptClick(event, {profile:'warehouse',
        viewMode:'storage', containerId:'背包', slot:stackSlot(1, '背包件', 2)}), true);
    assert.deepStrictEqual(f.notices, ['mode_not_supported', 'withdraw_source']);
    assert.strictEqual(f.controller.enqueue('背包', stackSlot(1, '背包件', 2), false), false);
    assert.deepStrictEqual(f.notices.slice(-1), ['withdraw_source']);
    assert.strictEqual(f.calls.length, 0);
});

test('stash single withdraw sends entryId identity and validates the settle rows', () => {
    const f = stashFixture([stashEntry('e1', '材料', 8, 11)]);
    assert.strictEqual(f.controller.enqueue('stash', f.entries.e1, false, 3), true);
    assert.strictEqual(f.calls.length, 1);
    assert.deepStrictEqual(f.calls[0].source, {entryId:'e1', revision:11, quantity:3});
    assert.strictEqual(f.calls[0].target, '背包');
    f.calls[0].done({success:true,
        accepted:[{entryId:'e1', quantity:3, destination:'背包'}], blocked:[]});
    assert.strictEqual(f.controller.debugState().completed, 1);
    assert.strictEqual(f.controller.isBusy(), false);

    assert.strictEqual(f.controller.enqueue('stash', f.entries.e1, false, 2), true);
    f.calls[1].done({success:true, accepted:[],
        blocked:[{entryId:'e1', reason:'target_full'}]});
    assert.strictEqual(f.errors.length, 1);
    assert.strictEqual(f.errors[0].error, 'stash_blocked');
    assert.deepStrictEqual(f.errors[0].blocked,
        [{entryId:'e1', reason:'target_full'}]);

    assert.strictEqual(f.controller.enqueue('stash', f.entries.e1, false), true);
    f.calls[2].done({success:false, error:'stale_stash'});
    assert.strictEqual(f.errors[1].error, 'stale_stash');
    assert.strictEqual(f.controller.isBusy(), false);
});

test('stash batch settle accepts non-prefix accepted/blocked coverage', () => {
    const f = stashFixture([stashEntry('e1', '材料', 8, 11), stashEntry('e2', '药剂', 4, 12),
        stashEntry('e3', '布料', 6, 13)]);
    f.controller.setMode('withdraw');
    f.controller.enqueue('stash', f.entries.e1, true);
    f.controller.enqueue('stash', f.entries.e2, true, 2);
    f.controller.enqueue('stash', f.entries.e3, true);
    assert.strictEqual(f.controller.commit(), true);
    assert.deepStrictEqual(f.batchCalls[0].sources.map(source => source.entryId),
        ['e1', 'e2', 'e3']);
    assert.strictEqual(f.batchCalls[0].sources[1].quantity, 2);
    assert.strictEqual(f.batchCalls[0].target, '背包');
    f.batchCalls[0].done({success:true,
        accepted:[{entryId:'e1', quantity:8, destination:'背包'},
            {entryId:'e3', quantity:6, destination:'材料'}],
        blocked:[{entryId:'e2', reason:'target_full'}]});
    assert.strictEqual(f.controller.debugState().completed, 2);
    assert.strictEqual(f.controller.getMode(), null);
    assert.strictEqual(f.controller.isBusy(), false);
    assert.strictEqual(f.errors.length, 1);
    assert.strictEqual(f.errors[0].error, 'stash_blocked');
    assert.strictEqual(f.errors[0].completedCount, 2);
    assert.deepStrictEqual(f.errors[0].blocked,
        [{entryId:'e2', reason:'target_full'}]);
});

test('malformed stash settles halt instead of counting as success', () => {
    const settles = [
        {success:true, accepted:[{entryId:'e1', quantity:8, destination:'背包'},
            {entryId:'e1', quantity:8, destination:'背包'}], blocked:[]},
        {success:true, accepted:[{entryId:'e9', quantity:8, destination:'背包'}], blocked:[]},
        {success:true, accepted:[{entryId:'e1', quantity:7, destination:'背包'}], blocked:[]},
        {success:true, accepted:[{entryId:'e1', quantity:8, destination:''}], blocked:[]},
        {success:true, accepted:[{entryId:'e1', quantity:8}], blocked:[]},
        {success:true, accepted:[{entryId:'e1', quantity:8, destination:'背包'}]},
        {success:true, accepted:[], blocked:[]},
        {success:true},
        {success:true, accepted:[],
            blocked:[{entryId:'e1', quantity:7, reason:'inventory_full'}]},
        {success:true, accepted:[],
            blocked:[{entryId:'e1', quantity:8}]},
        {success:true, accepted:[],
            blocked:[{entryId:'e1', reason:'x', extra:1}]},
        {success:true, accepted:[{entryId:'e1', quantity:8, destination:'背包', slot:50}],
            blocked:[]}
    ];
    settles.forEach(settle => {
        const f = stashFixture([stashEntry('e1', '材料', 8, 11)]);
        f.controller.enqueue('stash', f.entries.e1);
        f.calls[0].done(settle);
        assert.strictEqual(f.errors.length, 1, JSON.stringify(settle));
        assert.strictEqual(f.errors[0].error, 'invalid_response', JSON.stringify(settle));
        assert.strictEqual(f.controller.debugState().completed, 0);
    });
});

test('container signature and stash revision join the stale check', () => {
    const f = containerFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1'], true);
    f.slots['背包:1'] = stackSlot(1, '药剂', 9);
    assert.strictEqual(f.controller.commit(), false);
    assert.strictEqual(f.batchCalls.length, 0);
    assert.strictEqual(f.errors[0].error, 'stale_state');

    const s = stashFixture([stashEntry('e1', '材料', 8, 11)]);
    s.controller.setMode('withdraw');
    s.controller.enqueue('stash', s.entries.e1, true);
    s.entries.e1 = stashEntry('e1', '材料', 8, 12);
    assert.strictEqual(s.controller.commit(), false);
    assert.strictEqual(s.batchCalls.length, 0);
    assert.strictEqual(s.errors[0].error, 'stale_state');
});

test('container lease rotation alone is not stale; the wire ref re-reads the current lease', () => {
    const f = containerFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1'], true);
    f.slots['背包:1'] = stackSlot(1, '药剂', 10, 'lease-rotated');
    assert.strictEqual(f.controller.commit(), true);
    assert.deepStrictEqual(f.batchCalls[0].sources,
        [{containerId:'背包', slot:1, expectedLease:'lease-rotated'}]);
    f.batchCalls[0].done({success:true, completedCount:1});
    assert.strictEqual(f.controller.debugState().completed, 1);
});

test('stale stash revision halts the pending entry before the wire', () => {
    const s = stashFixture([stashEntry('e1', '材料', 8, 11), stashEntry('e2', '药剂', 4, 12)]);
    s.controller.setMode('withdraw');
    s.controller.enqueue('stash', s.entries.e1, true);
    s.controller.enqueue('stash', s.entries.e2, true);
    s.entries.e2 = stashEntry('e2', '药剂', 4, 99);
    assert.strictEqual(s.controller.commit(), false);
    assert.strictEqual(s.batchCalls.length, 0);
    assert.strictEqual(s.errors[0].error, 'stale_state');
    assert.strictEqual(s.controller.isBusy(), false);
});

test('configure rejects a source switch while busy and clears selection when idle', () => {
    const f = containerFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1'], true);
    assert.strictEqual(f.controller.configure({sourceKind:'stash', rightContainerId:'stash'}), true);
    assert.deepStrictEqual(f.notices, ['selection_cleared']);
    assert.strictEqual(f.controller.getMode(), null);
    assert.strictEqual(f.controller.debugState().pending, 0);
    assert.strictEqual(f.controller.debugState().sourceKind, 'stash');
    assert.strictEqual(f.controller.debugState().limit, 24);

    const busy = containerFixture();
    busy.controller.setMode('deposit');
    busy.controller.enqueue('背包', busy.slots['背包:1'], true);
    busy.controller.enqueue('背包', busy.slots['背包:2'], true);
    busy.controller.commit();
    assert.strictEqual(busy.controller.isBusy(), true);
    assert.strictEqual(busy.controller.configure({sourceKind:'stash'}), false);
    assert.deepStrictEqual(busy.notices, ['in_flight']);
    assert.strictEqual(busy.controller.debugState().sourceKind, 'container');
});

test('unsettled or stale-generation stash writes keep the conflict lock', () => {
    const f = stashFixture([stashEntry('e1', '材料', 8, 11), stashEntry('e2', '药剂', 4, 12)]);
    f.controller.setMode('withdraw');
    f.controller.enqueue('stash', f.entries.e1, true);
    f.controller.enqueue('stash', f.entries.e2, true);
    f.controller.commit();
    assert.strictEqual(f.controller.isBusy(), true);
    assert.strictEqual(f.controller.exit(), false);
    assert.strictEqual(f.controller.configure({sourceKind:'container'}), false);
    assert.deepStrictEqual(f.notices, ['in_flight']);
    f.setCurrent(false);
    f.batchCalls[0].done({success:true,
        accepted:[{entryId:'e1', quantity:8, destination:'背包'},
            {entryId:'e2', quantity:4, destination:'背包'}], blocked:[]});
    assert.strictEqual(f.controller.isBusy(), true, 'stale generation cannot unlock');
});

function DeferredTransport() { this.calls = []; }
DeferredTransport.prototype.request = function(cmd, payload, callback) {
    this.calls.push({cmd, payload:JSON.parse(JSON.stringify(payload)), callback});
};
DeferredTransport.prototype.respond = function(index, response) {
    assert(this.calls[index], 'missing deferred call ' + index);
    this.calls[index].callback(response);
};
function makeSnapshot(request, seq) {
    const limit = Math.min(Number(request.limit), 6);
    return {containerId:String(request.containerId), capacity:6, accessibleCapacity:6,
        viewCapacity:6, filterKey:'all', pageSizeHint:50, locked:false,
        snapshotSeq:seq, containerEpoch:1, containerVersion:seq,
        offset:0, limit:limit,
        slots:Array.from({length:limit}, (_, index) =>
            ({physicalSlot:index, occupied:false, slotLease:'lease.' + seq + '.' + index})),
        filterFacets:[], filterItemCount:0, setFacets:[], setFilterItemCount:0};
}
function exactResponse(call, seq) {
    return {success:true, snapshots:call.payload.requests.map(
        (request, index) => makeSnapshot(request, seq + index))};
}
function openCoordinator() {
    const transport = new DeferredTransport();
    const coordinator = new Runtime.InventoryCoordinator({
        requests:[{containerId:'背包', offset:0, limit:2, filterKey:'all'},
            {containerId:'仓库', offset:0, limit:2, filterKey:'all'}],
        request:transport.request.bind(transport)
    });
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    return {transport, coordinator};
}
function stackRef(quantity, itemQuantity) {
    const ref = {containerId:'背包', slot:0, expectedLease:'lease.source', occupied:true,
        item:{itemKind:'stack', name:'药剂', quantity:itemQuantity || 10}};
    if (quantity !== undefined) ref.quantity = quantity;
    return ref;
}

test('runtime wires source quantity only into move/merge/autoTransfer sources', () => {
    const opened = openCoordinator();
    const {transport, coordinator} = opened;
    const results = [];
    assert.strictEqual(coordinator.autoTransfer(stackRef(3), '仓库',
        result => results.push(result)), true);
    assert.deepStrictEqual(transport.calls[1].payload.source,
        {containerId:'背包', slot:0, expectedLease:'lease.source', quantity:3});
    transport.respond(1, {success:true, snapshots:transport.calls[0].payload.requests.map(
        (request, index) => makeSnapshot(request, 20 + index))});
    assert.strictEqual(results[0].success, true);

    assert.strictEqual(coordinator.autoTransfer(stackRef(), '仓库', () => {}), true);
    assert.deepStrictEqual(transport.calls[2].payload.source,
        {containerId:'背包', slot:0, expectedLease:'lease.source'});
    transport.respond(2, {success:true, snapshots:transport.calls[0].payload.requests.map(
        (request, index) => makeSnapshot(request, 30 + index))});
});

test('runtime rejects malformed source quantity before taking the write owner', () => {
    const {transport, coordinator} = openCoordinator();
    [0, -2, 1.5, '2', 11, 9007199254740992].forEach(quantity => {
        assert.strictEqual(coordinator.autoTransfer(stackRef(quantity), '仓库', () => {}), false);
    });
    const equipmentRef = {containerId:'背包', slot:0, expectedLease:'lease.eq', occupied:true,
        item:{itemKind:'equipment', name:'步枪', quantity:1}, quantity:1};
    assert.strictEqual(coordinator.autoTransfer(equipmentRef, '仓库', () => {}), false);
    assert.strictEqual(coordinator.autoTransferBatch([stackRef(0)], '仓库', () => {}), false);
    assert.strictEqual(coordinator.autoTransferBatch([stackRef(2), stackRef(99)], '仓库',
        () => {}), false);
    assert.strictEqual(transport.calls.length, 1, 'no write request was issued');
    assert.strictEqual(coordinator.debugState().busyOwner, null);
});

test('runtime batch carries per-source quantity in one ordered request', () => {
    const {transport, coordinator} = openCoordinator();
    assert.strictEqual(coordinator.autoTransferBatch([stackRef(2), stackRef()], '仓库',
        () => {}), true);
    assert.deepStrictEqual(transport.calls[1].payload.sources, [
        {containerId:'背包', slot:0, expectedLease:'lease.source', quantity:2},
        {containerId:'背包', slot:0, expectedLease:'lease.source'}
    ]);
    transport.respond(1, {success:true, completedCount:2,
        snapshots:transport.calls[0].payload.requests.map(
            (request, index) => makeSnapshot(request, 40 + index))});
});

test('runtime keeps quantity out of swap discard and target refs', () => {
    const {transport, coordinator} = openCoordinator();
    const target = {containerId:'仓库', slot:0, expectedLease:'lease.target', occupied:true,
        item:{itemKind:'equipment', name:'异名装备', quantity:1}};
    const results = [];
    assert.strictEqual(coordinator.transfer({operationId:'inventory.transfer',
        sourceRef:stackRef(3), targetRef:target}, result => results.push(result)), true);
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].error, 'invalid_intent');
    assert.strictEqual(transport.calls.length, 1, 'partial swap never reaches the wire');

    assert.strictEqual(coordinator.transfer({operationId:'inventory.transfer',
        sourceRef:stackRef(10), targetRef:target}, result => results.push(result)), true);
    assert.strictEqual(transport.calls[1].cmd, 'swap');
    assert.deepStrictEqual(transport.calls[1].payload.source,
        {containerId:'背包', slot:0, expectedLease:'lease.source'});
    transport.respond(1, {success:true, snapshots:transport.calls[0].payload.requests.map(
        (request, index) => makeSnapshot(request, 50 + index))});

    assert.strictEqual(coordinator.transfer({operationId:'inventory.transfer',
        sourceRef:stackRef(4),
        targetRef:{containerId:'仓库', slot:0, expectedLease:'lease.empty', occupied:false}},
        result => results.push(result)), true);
    assert.strictEqual(transport.calls[2].cmd, 'move');
    assert.strictEqual(transport.calls[2].payload.source.quantity, 4);
    assert.deepStrictEqual(transport.calls[2].payload.target,
        {containerId:'仓库', slot:0, expectedLease:'lease.empty'});
    transport.respond(2, {success:true, snapshots:transport.calls[0].payload.requests.map(
        (request, index) => makeSnapshot(request, 60 + index))});

    const mergeTarget = {containerId:'仓库', slot:1, expectedLease:'lease.merge', occupied:true,
        item:{itemKind:'stack', name:'药剂', quantity:4}};
    assert.strictEqual(coordinator.transfer({operationId:'inventory.transfer',
        sourceRef:stackRef(2), targetRef:mergeTarget}, result => results.push(result)), true);
    assert.strictEqual(transport.calls[3].cmd, 'merge');
    assert.strictEqual(transport.calls[3].payload.source.quantity, 2);
    transport.respond(3, {success:true, snapshots:transport.calls[0].payload.requests.map(
        (request, index) => makeSnapshot(request, 70 + index))});

    assert.strictEqual(coordinator.discard(
        {containerId:'背包', slot:0, expectedLease:'lease.source', quantity:1}, () => {}), false);
    assert.strictEqual(transport.calls.length, 4, 'discard with quantity never reaches the wire');
});

process.stdout.write('passed ' + passed + ' tests\n');
