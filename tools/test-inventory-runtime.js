#!/usr/bin/env node
'use strict';

const assert = require('assert');
const path = require('path');
const InventoryRuntime = require(path.resolve(
    __dirname, '..', 'launcher', 'web', 'modules', 'inventory-runtime.js'
));

let passed = 0;

function test(name, body) {
    body();
    passed += 1;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function DeferredTransport() {
    this.calls = [];
}

DeferredTransport.prototype.request = function(cmd, payload, callback) {
    this.calls.push({cmd:cmd, payload:clone(payload), callback:callback});
};

DeferredTransport.prototype.respond = function(index, response) {
    assert(this.calls[index], 'missing deferred call ' + index);
    this.calls[index].callback(response);
};

function createCoordinator(transport, requests) {
    return new InventoryRuntime.InventoryCoordinator({
        requests: requests || [
            {containerId:'背包', offset:0, limit:2, filterKey:'all'},
            {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
        ],
        request: transport.request.bind(transport)
    });
}

function makeSnapshot(request, seq, options) {
    options = options || {};
    const requestedOffset = Number(request.offset);
    const requestedLimit = Number(request.limit);
    const capacity = options.capacity == null ? 6 : Number(options.capacity);
    const viewCapacity = options.viewCapacity == null ? capacity : Number(options.viewCapacity);
    let offset = requestedOffset;
    if (viewCapacity <= 0) offset = 0;
    else if (offset >= viewCapacity) offset = Math.floor((viewCapacity - 1) / requestedLimit) * requestedLimit;
    const limit = Math.min(requestedLimit, Math.max(0, viewCapacity - offset));
    const snapshot = {
        containerId:String(request.containerId),
        capacity:capacity,
        accessibleCapacity:capacity,
        viewCapacity:viewCapacity,
        filterKey:String(request.filterKey || 'all'),
        snapshotSeq:Number(seq),
        offset:offset,
        limit:limit,
        slots:Array.from({length:limit}, function(_, index) {
            return {physicalSlot:offset + index, occupied:false, slotLease:'lease.' + seq + '.' + index};
        })
    };
    if (request.filterSpec != null) snapshot.filterSpec = clone(request.filterSpec);
    return snapshot;
}

function exactResponse(call, seqBase, optionsByContainer) {
    const options = optionsByContainer || {};
    return {
        success:true,
        snapshots:call.payload.requests.map(function(request, index) {
            return makeSnapshot(request, seqBase + index, options[request.containerId]);
        })
    };
}

function assertFailedBootstrap(coordinator, callbackResults) {
    const state = coordinator.debugState();
    assert.strictEqual(state.opened, true);
    assert.strictEqual(state.ready, false);
    assert.strictEqual(state.refreshRequired, true);
    assert.strictEqual(state.busyOwner, null);
    assert.deepStrictEqual(state.containers, []);
    assert.strictEqual(callbackResults.length, 1);
    assert.strictEqual(callbackResults[0].success, false);
}

function invalidBootstrapCase(mutator, requests) {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, requests);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    const response = exactResponse(transport.calls[0], 10);
    mutator(response.snapshots, transport.calls[0].payload.requests);
    transport.respond(0, response);
    assertFailedBootstrap(coordinator, results);
}

test('reopen drops the old bootstrap response without callback or state mutation', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    const oldResults = [];
    const newResults = [];
    coordinator.open(function(result) { oldResults.push(result); });
    coordinator.open(function(result) { newResults.push(result); });

    transport.respond(0, exactResponse(transport.calls[0], 100));
    assert.strictEqual(oldResults.length, 0);
    assert.strictEqual(newResults.length, 0);
    assert.strictEqual(coordinator.debugState().busyOwner, 'bootstrap');
    assert.deepStrictEqual(coordinator.debugState().containers, []);

    transport.respond(1, exactResponse(transport.calls[1], 10));
    assert.strictEqual(oldResults.length, 0);
    assert.strictEqual(newResults.length, 1);
    assert.strictEqual(newResults[0].success, true);
    assert.strictEqual(coordinator.isReady(), true);
    assert.strictEqual(coordinator.getWindow('背包').snapshotSeq, 10);
});

test('close drops a late bootstrap response and leaves the coordinator closed', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    coordinator.close();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    assert.strictEqual(results.length, 0);
    assert.deepStrictEqual(coordinator.debugState(), {
        opened:false,
        ready:false,
        busyOwner:null,
        refreshRequired:false,
        containers:[],
        requests:[
            {containerId:'背包', offset:0, limit:2, filterKey:'all'},
            {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
        ]
    });
});

test('snapshot exact-set rejects a partial batch', function() {
    invalidBootstrapCase(function(snapshots) { snapshots.pop(); });
});

test('snapshot exact-set rejects a duplicate container', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[1] = clone(snapshots[0]); });
});

test('snapshot exact-set rejects an unknown container', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[1].containerId = '未知容器'; });
});

test('snapshot exact-set rejects a wrong offset', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].offset = 1; });
});

test('snapshot exact-set rejects a wrong returned limit', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].limit = 1;
        snapshots[0].slots = snapshots[0].slots.slice(0, 1);
    });
});

test('snapshot exact-set rejects a filterKey mismatch', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].filterKey = 'weapon'; });
});

test('snapshot exact-set rejects a filterSpec mismatch', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].filterSpec = {branch:'category', major:'weapon', use:'刀'};
    }, [{
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon', use:'长枪'}
    }]);
});

test('snapshot exact-set rejects an unexpected filterSpec', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].filterSpec = {branch:'category', major:'all'};
    }, [{containerId:'背包', offset:0, limit:2, filterKey:'all'}]);
});

test('invalid refresh is atomic and retry applies the next exact batch together', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    assert.strictEqual(coordinator.refresh(), true);
    const invalid = exactResponse(transport.calls[1], 20);
    invalid.snapshots[1].offset = 1;
    transport.respond(1, invalid);

    assert.strictEqual(coordinator.isReady(), false);
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
    assert.strictEqual(coordinator.getWindow('背包').snapshotSeq, 10);
    assert.strictEqual(coordinator.getWindow('仓库').snapshotSeq, 11);

    assert.strictEqual(coordinator.retryRefresh(), true);
    transport.respond(2, exactResponse(transport.calls[2], 30));
    assert.strictEqual(coordinator.isReady(), true);
    assert.strictEqual(coordinator.debugState().refreshRequired, false);
    assert.strictEqual(coordinator.getWindow('背包').snapshotSeq, 30);
    assert.strictEqual(coordinator.getWindow('仓库').snapshotSeq, 31);
});

test('failed desired query stays desired while the last applied window stays unchanged', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    assert.strictEqual(coordinator.setWindow('背包', 2, 2), true);
    const invalid = exactResponse(transport.calls[1], 20);
    invalid.snapshots[0].offset = 3;
    transport.respond(1, invalid);

    assert.strictEqual(coordinator.getRequest('背包').offset, 2);
    assert.strictEqual(coordinator.getWindow('背包').offset, 0);
    assert.strictEqual(coordinator.isReady(), false);
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
});

test('authority offset clamp is the only accepted request offset deviation', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [
        {containerId:'背包', offset:4, limit:2, filterKey:'all'}
    ]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    transport.respond(0, exactResponse(transport.calls[0], 10, {'背包':{capacity:6, viewCapacity:3}}));
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.getWindow('背包').offset, 2);
    assert.strictEqual(coordinator.getWindow('背包').limit, 1);
    assert.strictEqual(coordinator.getRequest('背包').offset, 2);
    assert.strictEqual(coordinator.getRequest('背包').limit, 2);
});

test('late projection response cannot clear a reopened bootstrap owner or report success', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const projectionResults = [];
    assert.strictEqual(coordinator.readProjection({
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon'}
    }, function(result) { projectionResults.push(result); }), true);

    coordinator.open();
    transport.respond(1, exactResponse(transport.calls[1], 20));
    assert.strictEqual(projectionResults.length, 0);
    assert.strictEqual(coordinator.debugState().busyOwner, 'bootstrap');
    assert.deepStrictEqual(coordinator.debugState().containers, []);
    transport.respond(2, exactResponse(transport.calls[2], 30));
    assert.strictEqual(coordinator.isReady(), true);
});

test('external completion requires the exact owner handle in the same session', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const first = coordinator.beginExternalWrite('external.first');
    assert(first && typeof first === 'object');
    assert.strictEqual(coordinator.completeExternalWrite(null, false), false);
    assert.strictEqual(coordinator.completeExternalWrite({}, false), false);
    assert.strictEqual(coordinator.debugState().busyOwner, 'external.first');
    assert.strictEqual(coordinator.completeExternalWrite(first, false), true);

    const second = coordinator.beginExternalWrite('external.second');
    assert(second && second !== first);
    assert.strictEqual(coordinator.completeExternalWrite(first, false), false);
    assert.strictEqual(coordinator.debugState().busyOwner, 'external.second');
    assert.strictEqual(coordinator.completeExternalWrite(second, false), true);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
});

test('external owner handle is single-use while its refresh is in flight', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const results = [];
    const handle = coordinator.beginExternalWrite('external.refresh');
    assert(handle);
    assert.strictEqual(coordinator.completeExternalWrite(handle, true, function(result) {
        results.push(result);
    }), true);
    assert.strictEqual(coordinator.completeExternalWrite(handle, false), false);
    assert.strictEqual(coordinator.debugState().busyOwner, 'external.refresh');
    transport.respond(1, exactResponse(transport.calls[1], 20));
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
});

test('external handle from a closed session cannot release reopened bootstrap', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const oldHandle = coordinator.beginExternalWrite('shop.checkoutCommit');
    assert(oldHandle);

    coordinator.open();
    assert.strictEqual(coordinator.completeExternalWrite(oldHandle, false), false);
    assert.strictEqual(coordinator.debugState().busyOwner, 'bootstrap');
    assert.deepStrictEqual(coordinator.debugState().containers, []);
    transport.respond(1, exactResponse(transport.calls[1], 30));
    assert.strictEqual(coordinator.isReady(), true);
});

test('late write response cannot mutate or report into a reopened session', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const writeResults = [];
    assert.strictEqual(coordinator.discard({
        containerId:'背包', slot:0, expectedLease:'lease.10.0'
    }, function(result) { writeResults.push(result); }), true);

    coordinator.open();
    const writeRequest = coordinator.getRequest('背包');
    transport.respond(1, {success:true, snapshots:[makeSnapshot(writeRequest, 100)]});
    assert.strictEqual(writeResults.length, 0);
    assert.strictEqual(coordinator.debugState().busyOwner, 'bootstrap');
    assert.deepStrictEqual(coordinator.debugState().containers, []);
    transport.respond(2, exactResponse(transport.calls[2], 30));
    assert.strictEqual(coordinator.getWindow('背包').snapshotSeq, 30);
});

console.log('inventory-runtime model ' + passed + '/' + passed + ' passed');
