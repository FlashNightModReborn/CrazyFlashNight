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
        pageSizeHint:50,
        locked:capacity <= 0,
        snapshotSeq:Number(seq),
        containerEpoch:1,
        containerVersion:Number(seq),
        offset:offset,
        limit:limit,
        slots:Array.from({length:limit}, function(_, index) {
            return {physicalSlot:offset + index, occupied:false, slotLease:'lease.' + seq + '.' + index};
        }),
        filterFacets:[],
        filterItemCount:0,
        setFacets:[],
        setFilterItemCount:0
    };
    if (request.filterSpec != null) snapshot.filterSpec = clone(request.filterSpec);
    if (request.scope === 'equipment') snapshot.scope = 'equipment';
    return snapshot;
}

function makeMod(name) {
    const internalName = name || '精准握把';
    return {
        name:internalName,
        displayName:'人体工学 ' + internalName,
        icon:'图标-' + internalName,
        grade:'medium',
        gradeLabel:'中级',
        gradeColor:'#ffff00',
        role:'control',
        roleLabel:'精准与操控',
        symbol:'diamond-outline',
        scope:'weapon'
    };
}

function makeItem(options) {
    options = options || {};
    const item = {
        name:options.name || '内部沙鹰',
        displayName:options.displayName || '沙漠之鹰',
        icon:options.icon || '沙鹰专用图标',
        majorType:'武器',
        use:'长枪',
        actionType:'射击',
        weaponType:'步枪',
        setId:options.setId || '',
        setName:options.setName || '',
        setOrder:options.setOrder || 0,
        itemKind:'equipment',
        quantity:1,
        enhancementLevel:2,
        maxEnhancementLevel:13,
        isMaxEnhancement:false,
        tierSlotAvailable:true,
        tierSlotUsed:false,
        modSlotCapacity:3,
        modSlotUsed:1,
        modSlots:[makeMod()],
        modMeta:null,
        rarity:'rare'
    };
    if (options.balanceSummary) {
        item.balanceSummary = {
            state:'confirmed', weightLayers:1, formula:1, level:30
        };
    }
    return item;
}

function makeConfirm(item) {
    return {
        itemKind:item.itemKind,
        name:item.name,
        displayName:item.displayName,
        quantity:item.quantity,
        enhancementLevel:item.enhancementLevel,
        rarity:item.rarity,
        tier:'',
        modSignature:'4:test;',
        lastUpdate:123456
    };
}

function makeStackItem() {
    const item = makeItem({name:'辅助握持板', displayName:'人体工学握把', icon:'握把专用图标'});
    item.majorType = '材料';
    item.use = '装备插件';
    item.actionType = '';
    item.weaponType = '';
    item.itemKind = 'stack';
    item.quantity = 7;
    item.enhancementLevel = 0;
    item.isMaxEnhancement = false;
    item.tierSlotAvailable = false;
    item.tierSlotUsed = false;
    item.modSlotCapacity = 0;
    item.modSlotUsed = 0;
    item.modSlots = [];
    item.modMeta = makeMod('辅助握持板');
    return item;
}

function occupy(snapshot, index, item) {
    item = item || makeItem();
    snapshot.slots[index].occupied = true;
    snapshot.slots[index].item = item;
    snapshot.slots[index].confirmProjection = makeConfirm(item);
    return snapshot.slots[index];
}

function addFacetProjection(snapshot, count) {
    count = count == null ? 1 : count;
    snapshot.filterFacets = count ? [{
        id:'weapon', label:'武器', order:0, count:count, children:[{
            id:'长枪', label:'长枪', order:0, count:count, children:[{
                id:'步枪', label:'步枪', order:0, count:count, children:[]
            }]
        }]
    }] : [];
    snapshot.filterItemCount = count;
    snapshot.setFacets = [];
    snapshot.setFilterItemCount = 0;
    return snapshot;
}

function invalidOccupiedBootstrapCase(mutator, requests) {
    invalidBootstrapCase(function(snapshots, sentRequests) {
        occupy(snapshots[0], 0, makeItem({balanceSummary:true}));
        addFacetProjection(snapshots[0], 1);
        mutator(snapshots, sentRequests);
    }, requests);
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

function physicalSurfaceBatches(accessibleCapacity) {
    const batches = [[
        {containerId:'背包', offset:0, limit:50, filterKey:'all'},
        {containerId:'战备箱', offset:0, limit:100, filterKey:'all'}
    ]];
    if (accessibleCapacity > 100) batches.push([
        {containerId:'战备箱', offset:100, limit:100, filterKey:'all'}
    ]);
    if (accessibleCapacity > 200) batches.push([
        {containerId:'战备箱', offset:200,
            limit:accessibleCapacity - 200, filterKey:'all'}
    ]);
    return batches;
}

function physicalSurfaceSnapshot(request, accessibleCapacity, snapshotSeq) {
    const bag = request.containerId === '背包';
    const access = bag ? 50 : accessibleCapacity;
    const limit = Math.min(request.limit, Math.max(0, access - request.offset));
    return {
        containerId:request.containerId,
        capacity:bag ? 50 : 400,
        accessibleCapacity:access,
        viewCapacity:access,
        filterKey:'all',
        pageSizeHint:bag ? 50 : 40,
        locked:!bag && access === 0,
        snapshotSeq:snapshotSeq,
        containerEpoch:bag ? 10 : 20,
        containerVersion:1,
        offset:request.offset,
        limit:limit,
        slots:Array.from({length:limit}, function(_, index) {
            return {physicalSlot:request.offset + index, occupied:false,
                slotLease:'surface.' + (bag ? 'bag.' : 'battle.') + (request.offset + index)};
        }),
        filterFacets:[],
        filterItemCount:0,
        setFacets:[],
        setFilterItemCount:0
    };
}

function exercisePhysicalSurfaceOwner(owner, mutateResponse, mutateRequestReturn) {
    const accessibleCapacity = owner.accessibleCapacity == null
        ? 120 : Number(owner.accessibleCapacity);
    const batches = physicalSurfaceBatches(accessibleCapacity);
    const calls = [];
    let result = null;
    let callbackCount = 0;
    const started = InventoryRuntime.readPhysicalInventorySurface(function(cmd, payload, callback) {
        const ordinal = calls.length;
        calls.push({cmd:cmd, payload:clone(payload)});
        const requestCallId = 'surface.call.' + ordinal;
        const response = {
            success:true,
            v:1,
            sessionNonce:'surface.session.1',
            snapshots:payload.requests.map(function(request, index) {
                return physicalSurfaceSnapshot(request, accessibleCapacity,
                    10 + ordinal * 3 + index);
            }),
            type:'panel_resp',
            domain:'inventory',
            cmd:'snapshot',
            callId:requestCallId,
            panel:owner.responsePanel || owner.expectedPanel,
            panelInstanceId:owner.responsePanelInstanceId || 'surface.owner.1'
        };
        if (typeof mutateResponse === 'function') mutateResponse(response, ordinal);
        callback(response);
        if (owner.duplicateSyncCallback && ordinal === 0) callback(clone(response));
        return typeof mutateRequestReturn === 'function'
            ? mutateRequestReturn(requestCallId, ordinal) : requestCallId;
    }, {
        isActive:function() { return true; },
        expectedPanel:owner.expectedPanel,
        expectedPanelInstanceId:owner.expectedPanelInstanceId
    }, function(value) { callbackCount += 1; result = value; });
    return {started:started, result:result, callbackCount:callbackCount,
        calls:calls, batches:batches};
}

function authorityVisibleResponse(call, surface, seqBase, optionsByContainer) {
    const options = optionsByContainer || {};
    const response = exactResponse(call, seqBase, Object.keys(options).reduce(function(out, containerId) {
        out[containerId] = {viewCapacity:options[containerId].viewCapacity};
        return out;
    }, {}));
    response.v = 1;
    response.callId = call.callId;
    response.sessionNonce = surface.sessionNonce;
    response.snapshots.forEach(function(snapshot) {
        const full = surface.snapshots.find(function(entry) {
            return entry.containerId === snapshot.containerId;
        });
        const containerOptions = options[snapshot.containerId] || {};
        snapshot.capacity = full.capacity;
        snapshot.accessibleCapacity = full.accessibleCapacity;
        snapshot.pageSizeHint = full.pageSizeHint;
        snapshot.locked = full.locked;
        snapshot.containerEpoch = full.containerEpoch;
        snapshot.containerVersion = full.containerVersion;
        const physicalSlots = containerOptions.physicalSlots || Array.from(
            {length:snapshot.limit}, function(_, index) { return snapshot.offset + index; });
        snapshot.slots = physicalSlots.map(function(physicalSlot) {
            return clone(full.slots[physicalSlot]);
        });
        snapshot.limit = snapshot.slots.length;
    });
    return response;
}

function occupyPhysicalSurface(surface, containerId, physicalSlot, item) {
    surface.snapshots.filter(function(snapshot) { return snapshot.containerId === containerId; })
        .forEach(function(snapshot) {
            const index = snapshot.slots.findIndex(function(slot) {
                return slot.physicalSlot === physicalSlot;
            });
            if (index >= 0) occupy(snapshot, index, clone(item));
        });
    surface.windows.filter(function(snapshot) { return snapshot.containerId === containerId; })
        .forEach(function(snapshot) {
            const index = snapshot.slots.findIndex(function(slot) {
                return slot.physicalSlot === physicalSlot;
            });
            if (index >= 0) occupy(snapshot, index, clone(item));
        });
}

test('physical surface owner contract accepts exact KShop and NPC consumers', function() {
    const kshop = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1'
    });
    const npc = exercisePhysicalSurfaceOwner({expectedPanel:'npcshop'});
    [kshop, npc].forEach(function(run) {
        assert.strictEqual(run.started, true);
        assert.strictEqual(run.result.success, true);
        assert.strictEqual(run.callbackCount, 1);
        assert.strictEqual(run.calls.length, 2);
        assert.deepStrictEqual(run.calls.map(function(call) { return call.payload.requests; }),
            run.batches);
    });
});

test('physical surface bootstrap preserves the caller visible page', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1'
    }).result;
    const results = [];
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:[
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:'战备箱', offset:40, limit:40, filterKey:'all'}
        ],
        request:function() { throw new Error('physical bootstrap must not use window transport'); },
        readPhysicalSurface:function(_isActive, callback) {
            callback(clone(surface));
            return true;
        }
    });
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.isReady(), true);
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').offset, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').limit, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').slots[0].physicalSlot, 40);

    coordinator.close();
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(results.length, 2);
    assert.strictEqual(results[1].success, true);
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').slots[0].physicalSlot, 40);
});

test('physical surface refresh clamps a stale page after authority capacity shrink', function() {
    const largeSurface = exercisePhysicalSurfaceOwner({
        expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1',
        accessibleCapacity:120
    }).result;
    const smallSurface = exercisePhysicalSurfaceOwner({
        expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1',
        accessibleCapacity:40
    }).result;
    let currentSurface = largeSurface;
    const results = [];
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:[
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:'战备箱', offset:80, limit:40, filterKey:'all'}
        ],
        request:function() { throw new Error('physical bootstrap must not use window transport'); },
        readPhysicalSurface:function(_isActive, callback) {
            callback(clone(currentSurface));
            return true;
        }
    });
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 80);
    assert.strictEqual(coordinator.getWindow('战备箱').slots[0].physicalSlot, 80);

    currentSurface = smallSurface;
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(results.length, 2);
    assert.strictEqual(results[1].success, true);
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 0);
    assert.strictEqual(coordinator.getWindow('战备箱').offset, 0);
    assert.strictEqual(coordinator.getWindow('战备箱').limit, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').slots[0].physicalSlot, 0);
});

test('filtered physical refresh performs an authority-backed visible read and preserves its exact breadcrumb', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
    }).result.surface;
    const requests = [
        {containerId:'背包', offset:0, limit:50, filterKey:'all',
            filterSpec:{branch:'category', major:'all'}},
        {containerId:'战备箱', offset:40, limit:40, filterKey:'weapon',
            filterSpec:{branch:'category', major:'weapon'}}
    ];
    const visibleCalls = [];
    const results = [];
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            const call = {cmd:cmd, payload:clone(payload), callId:'visible.filtered.1'};
            visibleCalls.push(call);
            callback(authorityVisibleResponse(call, surface, 100, {
                背包:{viewCapacity:50}, 战备箱:{viewCapacity:80}
            }));
            return call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            callback({success:true, surface:clone(surface)});
            return true;
        }
    });
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(visibleCalls.length, 1);
    assert.deepStrictEqual(visibleCalls[0].payload, {v:1, requests:requests});
    assert.deepStrictEqual(coordinator.getRequest('背包').filterSpec,
        {branch:'category', major:'all'});
    assert.strictEqual(coordinator.getRequest('战备箱').filterKey, 'weapon');
    assert.deepStrictEqual(coordinator.getRequest('战备箱').filterSpec,
        {branch:'category', major:'weapon'});
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 40);
    assert.strictEqual(coordinator.getWindow('战备箱').offset, 40);
    assert.strictEqual(results[0].surface.windows.length, 3);
});

test('filtered physical refresh accepts only the authority clamp and never resets the filter', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:40
    }).result.surface;
    const requests = [
        {containerId:'背包', offset:0, limit:50, filterKey:'all'},
        {containerId:'战备箱', offset:80, limit:40, filterKey:'weapon',
            filterSpec:{branch:'category', major:'weapon'}}
    ];
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            const call = {cmd:cmd, payload:clone(payload), callId:'visible.clamp.1'};
            callback(authorityVisibleResponse(call, surface, 100, {
                背包:{viewCapacity:50}, 战备箱:{viewCapacity:20}
            }));
            return call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            callback({success:true, surface:clone(surface)});
            return true;
        }
    });
    let result = null;
    coordinator.open(function(value) { result = value; });
    assert(result && result.success);
    assert.strictEqual(coordinator.getRequest('战备箱').offset, 0);
    assert.strictEqual(coordinator.getRequest('战备箱').filterKey, 'weapon');
    assert.deepStrictEqual(coordinator.getRequest('战备箱').filterSpec,
        {branch:'category', major:'weapon'});
});

test('equipment scope also requires the post-surface authority projection', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:40
    }).result.surface;
    const requests = [{containerId:'背包', offset:0, limit:50, filterKey:'all', scope:'equipment'}];
    let authorityReads = 0;
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            authorityReads += 1;
            const call = {cmd:cmd, payload:clone(payload), callId:'visible.scope.1'};
            callback(authorityVisibleResponse(call, surface, 100, {背包:{viewCapacity:50}}));
            return call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            callback({success:true, surface:clone(surface)});
            return true;
        }
    });
    let result = null;
    coordinator.open(function(value) { result = value; });
    assert(result && result.success);
    assert.strictEqual(authorityReads, 1);
    assert.strictEqual(coordinator.getRequest('背包').scope, 'equipment');
    assert.strictEqual(coordinator.getWindow('背包').scope, 'equipment');
});

test('filtered physical projection rejects drift from its full-surface receipt', function() {
    const mutations = [
        function(response) { response.v = 2; },
        function(response) { response.sessionNonce += '.drift'; },
        function(response) { response.snapshots[1].capacity += 1; },
        function(response) { response.snapshots[1].pageSizeHint = 50; },
        function(response) {
            var snapshot = response.snapshots[1];
            snapshot.accessibleCapacity = 0;
            snapshot.viewCapacity = 0;
            snapshot.locked = true;
            snapshot.offset = 0;
            snapshot.limit = 0;
            snapshot.slots = [];
        },
        function(response) { response.snapshots[1].containerVersion += 1; },
        function(response) { response.snapshots[1].containerEpoch += 1; },
        function(response, surface) {
            response.snapshots[1].snapshotSeq = Math.max.apply(null,
                surface.windows.map(function(window) { return window.snapshotSeq; }));
        },
        function(response) { response.snapshots[1].slots[0].slotLease += '.drift'; },
        function(response) {
            response.snapshots[1].filterFacets = [
                {id:'all', label:'漂移后的分类', order:0, count:0, children:[]}
            ];
        },
        function(response) {
            response.snapshots[1].slots[0].item.displayName = '漂移后的显示名';
            response.snapshots[1].slots[0].confirmProjection.displayName = '漂移后的显示名';
        },
        function(response) { response.snapshots[1].slots[0].confirmProjection.lastUpdate += 1; }
    ];
    mutations.forEach(function(mutate) {
        const surface = exercisePhysicalSurfaceOwner({
            expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
        }).result.surface;
        occupyPhysicalSurface(surface, '战备箱', 40, makeItem());
        const requests = [
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:'战备箱', offset:0, limit:40, filterKey:'weapon',
                filterSpec:{branch:'category', major:'weapon'}}
        ];
        const results = [];
        const coordinator = new InventoryRuntime.InventoryCoordinator({
            requests:requests,
            request:function(cmd, payload, callback) {
                const call = {cmd:cmd, payload:clone(payload), callId:'visible.drift.1'};
                const response = authorityVisibleResponse(call, surface, 100, {
                    背包:{viewCapacity:50}, 战备箱:{viewCapacity:1, physicalSlots:[40]}
                });
                mutate(response, surface);
                callback(response);
                return call.callId;
            },
            readPhysicalSurface:function(_isActive, callback) {
                callback({success:true, surface:clone(surface)});
                return true;
            }
        });
        coordinator.open(function(result) { results.push(result); });
        assert.strictEqual(results.length, 1);
        assert.strictEqual(results[0].success, false);
        assert.strictEqual(coordinator.isReady(), false);
        assert.strictEqual(coordinator.debugState().refreshRequired, true);
        assert.strictEqual(coordinator.debugState().physicalSurface, null);
    });
});

test('malformed constrained physical surface fails once without throwing or replacing the prior window', function() {
    const validSurface = exercisePhysicalSurfaceOwner({
        expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
    }).result.surface;
    const requests = [{containerId:'背包', offset:0, limit:50, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon'}}];
    let malformed = false;
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            const call = {cmd:cmd, payload:clone(payload), callId:'visible.malformed.1'};
            callback(authorityVisibleResponse(call, validSurface, 100, {背包:{viewCapacity:50}}));
            return call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            callback(malformed
                ? {success:true, surface:{schema:InventoryRuntime.physicalSurfaceSchema,
                    sessionNonce:validSurface.sessionNonce, windows:[]}}
                : {success:true, surface:clone(validSurface)});
            return true;
        }
    });
    let initial = null;
    coordinator.open(function(result) { initial = result; });
    assert(initial && initial.success);
    const priorWindow = coordinator.getWindow('背包');
    const handle = coordinator.beginExternalWrite('test.malformed-surface');
    const results = [];
    malformed = true;
    assert.doesNotThrow(function() {
        coordinator.completeExternalWrite(handle, true, function(result) { results.push(result); });
    });
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, false);
    assert.strictEqual(coordinator.getWindow('背包'), priorWindow);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
    assert.strictEqual(coordinator.isReady(), false);
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
    assert.strictEqual(coordinator.debugState().physicalSurface, null);
});

test('constrained follow-up request contract rejects throw null mismatch and duplicate sync callbacks', function() {
    const behaviors = [
        function() { return null; },
        function() { throw new Error('synthetic request failure'); },
        function(callback, response) { callback(response); return null; },
        function(callback, response) {
            response.callId = 'visible.contract.mismatch'; callback(response); return 'visible.contract.expected';
        },
        function(callback, response) {
            callback(response); callback(clone(response)); return response.callId;
        }
    ];
    behaviors.forEach(function(behavior, index) {
        const surface = exercisePhysicalSurfaceOwner({
            expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
        }).result.surface;
        const requests = [{containerId:'背包', offset:0, limit:50, filterKey:'weapon'}];
        const results = [];
        const coordinator = new InventoryRuntime.InventoryCoordinator({
            requests:requests,
            request:function(cmd, payload, callback) {
                const call = {cmd:cmd, payload:clone(payload), callId:'visible.contract.' + index};
                const response = authorityVisibleResponse(call, surface, 100, {背包:{viewCapacity:50}});
                return behavior(callback, response);
            },
            readPhysicalSurface:function(_isActive, callback) {
                callback({success:true, surface:clone(surface)});
                return true;
            }
        });
        assert.doesNotThrow(function() {
            coordinator.open(function(result) { results.push(result); });
        });
        assert.strictEqual(results.length, 1);
        assert.strictEqual(results[0].success, false);
        assert.strictEqual(results[0].error,
            'inventory_surface_projection_request_contract_invalid');
        assert.strictEqual(coordinator.debugState().busyOwner, null);
        assert.strictEqual(coordinator.debugState().refreshRequired, true);
        assert.strictEqual(coordinator.debugState().physicalSurface, null);
    });
});

test('failed constrained projection retries the full physical then exact visible sequence', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
    }).result.surface;
    const requests = [{containerId:'背包', offset:0, limit:50, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon'}}];
    let physicalReads = 0;
    let visibleReads = 0;
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            visibleReads += 1;
            const call = {cmd:cmd, payload:clone(payload), callId:'visible.retry.' + visibleReads};
            const response = authorityVisibleResponse(call, surface, 100 * visibleReads,
                {背包:{viewCapacity:50}});
            if (visibleReads === 2) response.snapshots[0].slots[0].slotLease += '.drift';
            callback(response);
            return call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            physicalReads += 1;
            callback({success:true, surface:clone(surface)});
            return true;
        }
    });
    let initial = null;
    coordinator.open(function(result) { initial = result; });
    assert(initial && initial.success);
    assert.deepStrictEqual([physicalReads, visibleReads], [1, 1]);
    const handle = coordinator.beginExternalWrite('test.filtered-retry');
    let failed = null;
    coordinator.completeExternalWrite(handle, true, function(result) { failed = result; });
    assert(failed && failed.success === false);
    assert.deepStrictEqual([physicalReads, visibleReads], [2, 2]);
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
    let retried = null;
    assert.strictEqual(coordinator.retryRefresh(function(result) { retried = result; }), true);
    assert(retried && retried.success);
    assert.deepStrictEqual([physicalReads, visibleReads], [3, 3]);
    assert.strictEqual(coordinator.isReady(), true);
    assert.strictEqual(coordinator.debugState().refreshRequired, false);
    assert.deepStrictEqual(coordinator.getRequest('背包').filterSpec,
        {branch:'category', major:'weapon'});
    assert(coordinator.debugState().physicalSurface);
});

test('late filtered follow-up cannot commit after the coordinator closes', function() {
    const surface = exercisePhysicalSurfaceOwner({
        expectedPanel:'npcshop', expectedPanelInstanceId:'surface.owner.1', accessibleCapacity:120
    }).result.surface;
    const requests = [{containerId:'背包', offset:0, limit:50, filterKey:'weapon'}];
    let followUp = null;
    const results = [];
    const coordinator = new InventoryRuntime.InventoryCoordinator({
        requests:requests,
        request:function(cmd, payload, callback) {
            followUp = {call:{cmd:cmd, payload:clone(payload), callId:'visible.late.1'}, callback:callback};
            return followUp.call.callId;
        },
        readPhysicalSurface:function(_isActive, callback) {
            callback({success:true, surface:clone(surface)});
            return true;
        }
    });
    coordinator.open(function(result) { results.push(result); });
    assert(followUp);
    coordinator.close();
    followUp.callback(authorityVisibleResponse(followUp.call, surface, 100,
        {背包:{viewCapacity:50}}));
    assert.strictEqual(results.length, 0);
    assert.strictEqual(coordinator.debugState().opened, false);
    assert.deepStrictEqual(coordinator.debugState().containers, []);
    assert.strictEqual(coordinator.debugState().physicalSurface, null);
});

test('physical surface owner contract requires one bounded expected panel', function() {
    const run = exercisePhysicalSurfaceOwner({expectedPanel:null});
    assert.strictEqual(run.started, false);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_owner_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 0);
    const invalidInstance = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:''
    });
    assert.strictEqual(invalidInstance.started, false);
    assert.deepStrictEqual(invalidInstance.result,
        {success:false, error:'inventory_surface_owner_invalid'});
    assert.strictEqual(invalidInstance.callbackCount, 1);
    assert.strictEqual(invalidInstance.calls.length, 0);
});

test('physical surface owner contract rejects unavailable or invalid request returns', function() {
    const results = [];
    const unavailable = InventoryRuntime.readPhysicalInventorySurface(null,
        {expectedPanel:'kshop'}, function(result) { results.push(result); });
    assert.strictEqual(unavailable, false);
    assert.deepStrictEqual(results,
        [{success:false, error:'inventory_surface_unavailable'}]);
    const cases = [
        {name:'null', request:function() { return null; }},
        {name:'undefined', request:function() {}},
        {name:'false', request:function() { return false; }},
        {name:'true', request:function() { return true; }},
        {name:'object', request:function() { return {callId:'surface.call.0'}; }},
        {name:'empty', request:function() { return ''; }},
        {name:'oversized', request:function() { return new Array(162).join('x'); }},
        {name:'throw', request:function() { throw new Error('not sent'); }}
    ];
    cases.forEach(function(entry) {
        let callbackCount = 0;
        let result = null;
        let sends = 0;
        const started = InventoryRuntime.readPhysicalInventorySurface(function() {
            sends += 1;
            return entry.request();
        }, {expectedPanel:'kshop'}, function(value) {
            callbackCount += 1;
            result = value;
        });
        assert.strictEqual(started, false, entry.name);
        assert.strictEqual(sends, 1, entry.name);
        assert.strictEqual(callbackCount, 1, entry.name);
        assert.deepStrictEqual(result,
            {success:false, error:'inventory_surface_request_contract_invalid'}, entry.name);
    });
});

test('physical surface owner contract rejects a response from the wrong panel', function() {
    const run = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', responsePanel:'npcshop'
    });
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 1);
});

test('physical surface async response failure preserves the successful initial return', function() {
    let pending = null;
    const results = [];
    const started = InventoryRuntime.readPhysicalInventorySurface(function(_cmd, _payload, callback) {
        pending = callback;
        return 'surface.call.0';
    }, {expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1'},
    function(result) { results.push(result); });
    assert.strictEqual(started, true);
    assert.strictEqual(results.length, 0);
    assert.strictEqual(typeof pending, 'function');
    pending({success:true, v:1, sessionNonce:'surface.session.1', snapshots:[],
        type:'panel_resp', domain:'inventory', cmd:'snapshot', callId:'surface.call.0',
        panel:'npcshop', panelInstanceId:'surface.owner.1'});
    assert.deepStrictEqual(results,
        [{success:false, error:'inventory_surface_invalid'}]);
});

test('physical surface owner contract rejects a response callId mismatch', function() {
    const run = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1'
    }, function(response, ordinal) {
        if (ordinal === 0) response.callId = 'surface.call.wrong';
    });
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 1);
});

test('physical surface owner contract rejects a duplicate matched callId across batches', function() {
    const run = exercisePhysicalSurfaceOwner({expectedPanel:'npcshop'},
        function(response, ordinal) {
            if (ordinal === 1) response.callId = 'surface.call.0';
        }, function(requestCallId, ordinal) {
            return ordinal === 1 ? 'surface.call.0' : requestCallId;
        });
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 2);
});

test('physical surface synchronous synthetic failure preserves a valid initial start', function() {
    let result = null;
    let callbackCount = 0;
    const started = InventoryRuntime.readPhysicalInventorySurface(function(_cmd, _payload, callback) {
        const callId = 'surface.synthetic.0';
        callback({type:'panel_resp', domain:'inventory', panel:'kshop',
            panelInstanceId:'surface.owner.1', cmd:'snapshot', callId:callId,
            success:false, error:'disconnected', clientSynthetic:true});
        return callId;
    }, {expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1'},
    function(value) { callbackCount += 1; result = value; });
    assert.strictEqual(started, true);
    assert.deepStrictEqual(result,
        {success:false, error:'inventory_surface_invalid'});
    assert.strictEqual(callbackCount, 1);
});

test('physical surface rejects duplicate synchronous callbacks before applying either response', function() {
    const run = exercisePhysicalSurfaceOwner({
        expectedPanel:'kshop', expectedPanelInstanceId:'surface.owner.1',
        duplicateSyncCallback:true
    });
    assert.strictEqual(run.started, false);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_request_contract_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 1);
});

test('physical surface owner contract rejects panel-instance drift across batches', function() {
    const run = exercisePhysicalSurfaceOwner({expectedPanel:'npcshop'},
        function(response, ordinal) {
            if (ordinal === 1) response.panelInstanceId = 'surface.owner.2';
        });
    assert.strictEqual(run.started, true);
    assert.deepStrictEqual(run.result,
        {success:false, error:'inventory_surface_invalid'});
    assert.strictEqual(run.callbackCount, 1);
    assert.strictEqual(run.calls.length, 2);
});

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

test('snapshot rejects an unknown top-level authority descriptor', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].authorityDescriptor = {inventoryRef:'must-not-cross'};
    });
});

test('snapshot rejects a missing required production field', function() {
    invalidBootstrapCase(function(snapshots) { delete snapshots[0].pageSizeHint; });
});

test('snapshot rejects wrong pageSizeHint and locked leaf types', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].pageSizeHint = '50';
        snapshots[0].locked = 0;
    });
});

test('snapshot rejects wrong epoch and version leaf types', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].containerEpoch = '1';
        snapshots[0].containerVersion = 10.5;
    });
});

test('snapshot rejects Number-coercible item-count leaves', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].filterItemCount = '0';
        snapshots[0].setFilterItemCount = '0';
    });
});

test('realistic filtered equipment projection proves every nested leaf', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [{
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon', use:'长枪'}
    }]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    const response = exactResponse(transport.calls[0], 10, {'背包':{capacity:8, viewCapacity:2}});
    response.snapshots[0].slots[0].physicalSlot = 1;
    response.snapshots[0].slots[1].physicalSlot = 6;
    occupy(response.snapshots[0], 0, makeItem({balanceSummary:true}));
    occupy(response.snapshots[0], 1, makeItem({name:'内部雷神', displayName:'双面雷神'}));
    addFacetProjection(response.snapshots[0], 2);
    response.snapshots[0].setFacets = [{
        id:'desert', label:'沙漠套装', order:1, count:1, children:[]
    }];
    response.snapshots[0].setFilterItemCount = 1;
    transport.respond(0, response);

    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.isReady(), true);
    assert.strictEqual(coordinator.getWindow('背包').slots[1].physicalSlot, 6);
    const mod = coordinator.getWindow('背包').slots[0].item.modSlots[0];
    assert.strictEqual(new Set([mod.name, mod.displayName, mod.icon]).size, 3);
});

test('realistic stack and loose-plugin metadata projection remains compatible', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [{
        containerId:'背包', offset:0, limit:2, filterKey:'all'
    }]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    const response = exactResponse(transport.calls[0], 10);
    occupy(response.snapshots[0], 0, makeStackItem());
    response.snapshots[0].filterFacets = [{
        id:'material', label:'材料', order:0, count:1, children:[{
            id:'装备插件', label:'装备插件', order:0, count:1, children:[]
        }]
    }];
    response.snapshots[0].filterItemCount = 1;
    transport.respond(0, response);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.getWindow('背包').slots[0].item.modMeta.role, 'control');
});

test('applied snapshot is detached from post-proof response mutation', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    const response = exactResponse(transport.calls[0], 10);
    occupy(response.snapshots[0], 0, makeItem({balanceSummary:true}));
    addFacetProjection(response.snapshots[0], 1);
    transport.respond(0, response);

    const applied = coordinator.getWindow('背包');
    assert.notStrictEqual(applied, response.snapshots[0]);
    assert.notStrictEqual(applied.slots, response.snapshots[0].slots);
    assert.notStrictEqual(applied.slots[0].item, response.snapshots[0].slots[0].item);
    response.snapshots[0].containerVersion = 999999;
    response.snapshots[0].slots[0].physicalSlot = 5;
    response.snapshots[0].slots[0].item.displayName = '验证后篡改';
    response.snapshots[0].slots[0].item.balanceSummary.level = 999999;
    response.snapshots[0].filterFacets[0].label = '验证后篡改';

    assert.strictEqual(applied.containerVersion, 10);
    assert.strictEqual(applied.slots[0].physicalSlot, 0);
    assert.strictEqual(applied.slots[0].item.displayName, '沙漠之鹰');
    assert.strictEqual(applied.slots[0].item.balanceSummary.level, 30);
    assert.strictEqual(applied.filterFacets[0].label, '武器');
});

test('set filter may project ordered non-contiguous physical slots', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [{
        containerId:'背包', offset:0, limit:2, filterKey:'all',
        filterSpec:{branch:'set', setId:'desert'}
    }]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    const response = exactResponse(transport.calls[0], 10, {'背包':{capacity:8, viewCapacity:2}});
    response.snapshots[0].slots[0].physicalSlot = 2;
    response.snapshots[0].slots[1].physicalSlot = 7;
    transport.respond(0, response);
    assert.strictEqual(results[0].success, true);
});

test('equipment scope may project ordered non-contiguous physical slots', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [{
        containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'equipment'
    }]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    const response = exactResponse(transport.calls[0], 10, {'背包':{capacity:8, viewCapacity:2}});
    response.snapshots[0].slots[0].physicalSlot = 1;
    response.snapshots[0].slots[1].physicalSlot = 5;
    transport.respond(0, response);
    assert.strictEqual(results[0].success, true);
});

test('unfiltered projection rejects a non-contiguous physical slot', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].slots[1].physicalSlot = 2; });
});

test('snapshot rejects a fractional physical slot', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].slots[0].physicalSlot = 0.5; });
});

test('snapshot rejects an out-of-capacity physical slot', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].slots[1].physicalSlot = 6; });
});

test('filtered projection rejects duplicate physical slots', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].physicalSlot = 1;
        snapshots[0].slots[1].physicalSlot = 1;
    }, [{containerId:'背包', offset:0, limit:2, filterKey:'weapon'}]);
});

test('filtered projection rejects descending physical slots', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].physicalSlot = 4;
        snapshots[0].slots[1].physicalSlot = 1;
    }, [{containerId:'背包', offset:0, limit:2, filterKey:'weapon'}]);
});

test('snapshot rejects a non-opaque slot lease', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].slots[0].slotLease = 'bad lease'; });
});

test('occupied slot requires both item and confirmProjection', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        delete snapshots[0].slots[0].confirmProjection;
    });
});

test('occupied slot rejects a missing item even when confirmProjection exists', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        delete snapshots[0].slots[0].item;
    });
});

test('empty slot rejects an item or confirmProjection payload', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item = makeItem();
        snapshots[0].slots[0].confirmProjection = makeConfirm(snapshots[0].slots[0].item);
    });
});

test('slot rejects an unknown nested key', function() {
    invalidBootstrapCase(function(snapshots) { snapshots[0].slots[0].descriptor = {}; });
});

test('item projection rejects missing and unknown leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        delete snapshots[0].slots[0].item.icon;
        snapshots[0].slots[0].item.rawDescriptor = {damage:999999};
    });
});

test('item projection rejects wrong text and boolean leaf types', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.displayName = {html:'unsafe'};
        snapshots[0].slots[0].item.tierSlotUsed = 1;
    });
});

test('item projection rejects blank and wrapped-case undefined identity leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.name = ' Undefined ';
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.displayName = '   ';
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.icon = 'uNdEfInEd';
    });
});

test('item projection rejects impossible equipment quantity and enhancement state', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.quantity = 2;
        snapshots[0].slots[0].confirmProjection.quantity = 2;
        snapshots[0].slots[0].item.isMaxEnhancement = true;
    });
});

test('mod projection rejects unknown, missing, wrong, blank and undefined identity leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const mod = snapshots[0].slots[0].item.modSlots[0];
        mod.scope = ['weapon'];
        mod.authorityDescriptor = true;
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        delete snapshots[0].slots[0].item.modSlots[0].displayName;
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.modSlots[0].icon = {unsafe:true};
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.modSlots[0].displayName = '   ';
    });
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].slots[0].item.modSlots[0].icon = ' Undefined ';
    });
});

test('mod projection enforces bounded list and used-count relationship', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const item = snapshots[0].slots[0].item;
        item.modSlots = [makeMod('a'), makeMod('b'), makeMod('c'), makeMod('d')];
        item.modSlotUsed = 4;
    });
});

test('confirm projection rejects mismatched identity and unknown leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const confirm = snapshots[0].slots[0].confirmProjection;
        confirm.name = '另一件物品';
        confirm.descriptor = 'leak';
    });
});

test('confirm projection rejects unsafe numeric and text leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const confirm = snapshots[0].slots[0].confirmProjection;
        confirm.lastUpdate = Infinity;
        confirm.modSignature = 'x'.repeat(1025);
    });
});

test('optional balanceSummary accepts only the exact confirmed finite projection', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const summary = snapshots[0].slots[0].item.balanceSummary;
        summary.formula = 2;
        summary.auditRef = 'must-not-cross-to-web';
    });
});

test('facet projection rejects malformed recursive leaves', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const leaf = snapshots[0].filterFacets[0].children[0].children[0];
        leaf.count = '1';
        leaf.descriptor = {};
    });
});

test('facet projection rejects duplicate sibling ids', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        const root = snapshots[0].filterFacets[0];
        snapshots[0].filterFacets.push(clone(root));
        snapshots[0].filterItemCount = 2;
    });
});

test('facet projection rejects hierarchy deeper than category use subtype', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].filterFacets[0].children[0].children[0].children.push({
            id:'too-deep', label:'too-deep', order:0, count:1, children:[]
        });
    });
});

test('facet projection rejects a count beyond accessible capacity', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].filterFacets[0].count = 7;
    });
});

test('set facets must be flat', function() {
    invalidOccupiedBootstrapCase(function(snapshots) {
        snapshots[0].setFacets = [{
            id:'desert', label:'沙漠套装', order:0, count:2, children:[{
                id:'nested', label:'nested', order:0, count:1, children:[]
            }]
        }];
        snapshots[0].setFilterItemCount = 2;
    });
});

test('response filterSpec rejects extra keys after exact request matching', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].filterSpec.descriptor = 'leak';
    }, [{
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon', use:'长枪'}
    }]);
});

test('response filterSpec rejects coerced leaf types', function() {
    invalidBootstrapCase(function(snapshots) {
        snapshots[0].filterSpec.use = 7;
    }, [{
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon', use:'7'}
    }]);
});

test('nested failure in the second snapshot leaves the entire prior batch untouched', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const backpackBefore = coordinator.getWindow('背包');
    const warehouseBefore = coordinator.getWindow('仓库');

    assert.strictEqual(coordinator.refresh(), true);
    const invalid = exactResponse(transport.calls[1], 20);
    occupy(invalid.snapshots[1], 0, makeItem());
    invalid.snapshots[1].slots[0].item.modSlots[0].grade = {unsafe:true};
    transport.respond(1, invalid);

    assert.strictEqual(coordinator.isReady(), false);
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
    assert.strictEqual(coordinator.getWindow('背包'), backpackBefore);
    assert.strictEqual(coordinator.getWindow('仓库'), warehouseBefore);
});

test('equipment scope is exact, backpack-only, and carried by projections', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [
        {containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'equipment'}
    ]);
    const results = [];
    coordinator.open(function(result) { results.push(result); });
    assert.strictEqual(transport.calls[0].payload.requests[0].scope, 'equipment');
    transport.respond(0, exactResponse(transport.calls[0], 10));
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.getRequest('背包').scope, 'equipment');
    assert.strictEqual(coordinator.getWindow('背包').scope, 'equipment');

    const bad = createCoordinator(new DeferredTransport());
    assert.strictEqual(bad.configureRequests([
        {containerId:'仓库', offset:0, limit:2, filterKey:'all', scope:'equipment'}
    ]), false);
    assert.strictEqual(bad.configureRequests([
        {containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'developer'}
    ]), false);
});

test('snapshot exact-set rejects a missing equipment scope echo', function() {
    invalidBootstrapCase(function(snapshots) {
        delete snapshots[0].scope;
    }, [{containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'equipment'}]);
});

test('replaceWindowRequest atomically enters equipment scope', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const results = [];
    assert.strictEqual(coordinator.replaceWindowRequest('背包', {
        containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'equipment'
    }, function(result) { results.push(result); }), true);
    assert.strictEqual(transport.calls[1].payload.requests[0].scope, 'equipment');
    transport.respond(1, exactResponse(transport.calls[1], 20));
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(coordinator.getRequest('背包').scope, 'equipment');
    assert.strictEqual(coordinator.getWindow('背包').scope, 'equipment');
});

test('replaceWindowRequest failure restores the exact prior request and retry stays safe', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport, [
        {
            containerId:'背包', offset:2, limit:2, filterKey:'weapon',
            filterSpec:{branch:'category', major:'weapon', use:'长枪'}
        }
    ]);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const prior = coordinator.getRequest('背包');
    const results = [];
    assert.strictEqual(coordinator.replaceWindowRequest('背包', {
        containerId:'背包', offset:0, limit:2, filterKey:'all', scope:'equipment'
    }, function(result) { results.push(result); }), true);
    const invalid = exactResponse(transport.calls[1], 20);
    delete invalid.snapshots[0].scope;
    transport.respond(1, invalid);

    assert.strictEqual(results[0].success, false);
    assert.strictEqual(results[0].rolledBack, true);
    assert.deepStrictEqual(coordinator.getRequest('背包'), prior);
    assert.strictEqual(coordinator.getWindow('背包').filterSpec.use, '长枪');
    assert.strictEqual(coordinator.debugState().refreshRequired, true);
    assert.strictEqual(coordinator.retryRefresh(), true);
    assert.deepStrictEqual(transport.calls[2].payload.requests[0], prior);
    transport.respond(2, exactResponse(transport.calls[2], 30));
    assert.strictEqual(coordinator.isReady(), true);
});

test('readProjection forwards equipment scope without replacing the visible request', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const visible = coordinator.getRequest('背包');
    const results = [];
    assert.strictEqual(coordinator.readProjection({
        containerId:'背包', offset:0, limit:2, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon'}, scope:'equipment'
    }, function(result) { results.push(result); }), true);
    assert.strictEqual(transport.calls[1].payload.requests[0].scope, 'equipment');
    transport.respond(1, exactResponse(transport.calls[1], 20));
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(results[0].snapshot.scope, 'equipment');
    assert.deepStrictEqual(coordinator.getRequest('背包'), visible);
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

test('character-build external completion atomically applies the full backpack snapshot', function() {
    const transport = new DeferredTransport();
    const requests = [
        {containerId:'背包', offset:0, limit:50, filterKey:'all'},
        {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
    ];
    const coordinator = createCoordinator(transport, requests);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10, {
        背包:{capacity:50, viewCapacity:50}
    }));
    const warehouseBefore = coordinator.getWindow('仓库');
    const handle = coordinator.beginExternalWrite('character-build.equipEquipment');
    const backpack = makeSnapshot(requests[0], 20, {capacity:50, viewCapacity:50});
    let completion = null;
    assert.strictEqual(coordinator.completeExternalSnapshots(
        handle, [backpack], result => { completion = result; }), true);
    assert(completion && completion.success && completion.applied);
    assert.notStrictEqual(coordinator.getWindow('背包'), backpack);
    assert.deepStrictEqual(coordinator.getWindow('背包'), backpack);
    assert.strictEqual(coordinator.getWindow('仓库'), warehouseBefore);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
    assert.strictEqual(coordinator.debugState().refreshRequired, false);
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

test('category-all breadcrumb is an active window for transfer discard and sort refreshes', function() {
    ['transfer', 'discard', 'sortAndMerge'].forEach(function(kind) {
        const transport = new DeferredTransport();
        const requests = [
            {containerId:'背包', offset:0, limit:2, filterKey:'all',
                filterSpec:{branch:'category', major:'all'}},
            {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
        ];
        const coordinator = createCoordinator(transport, requests);
        coordinator.open();
        transport.respond(0, exactResponse(transport.calls[0], 10));
        const results = [];
        let started = false;
        if (kind === 'transfer') {
            started = coordinator.transfer({operationId:'inventory.transfer',
                sourceRef:{containerId:'背包', slot:0, expectedLease:'lease.source',
                    occupied:true, item:{itemKind:'stack', name:'药剂'}},
                targetRef:{containerId:'仓库', slot:0, expectedLease:'lease.target', occupied:false}
            }, function(result) { results.push(result); });
        } else if (kind === 'discard') {
            started = coordinator.discard({containerId:'背包', slot:0,
                expectedLease:'lease.source'}, function(result) { results.push(result); });
        } else {
            started = coordinator.sortAndMerge('背包', 'byType',
                function(result) { results.push(result); });
        }
        assert.strictEqual(started, true);
        assert.strictEqual(transport.calls.length, 2);
        transport.respond(1, {success:true, snapshots:[]});
        assert.strictEqual(transport.calls.length, 3);
        assert.strictEqual(transport.calls[2].cmd, 'snapshot');
        assert.deepStrictEqual(transport.calls[2].payload, {v:1, requests:requests});
        assert.strictEqual(results.length, 0);
        transport.respond(2, exactResponse(transport.calls[2], 30));
        assert.strictEqual(results.length, 1);
        assert.strictEqual(results[0].success, true);
        assert.strictEqual(results[0].viewRefreshSucceeded, true);
        assert.deepStrictEqual(coordinator.getRequest('背包').filterSpec,
            {branch:'category', major:'all'});
    });
});

test('auto-transfer accepts an exact category-all window batch without losing the breadcrumb', function() {
    const transport = new DeferredTransport();
    const requests = [
        {containerId:'背包', offset:0, limit:2, filterKey:'all',
            filterSpec:{branch:'category', major:'all'}},
        {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
    ];
    const coordinator = createCoordinator(transport, requests);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const results = [];
    assert.strictEqual(coordinator.autoTransfer({containerId:'背包', slot:0,
        expectedLease:'lease.source', occupied:true,
        item:{itemKind:'stack', name:'药剂'}}, '仓库', function(result) {
            results.push(result);
    }), true);
    assert.deepStrictEqual(transport.calls[1].payload.windows, requests);
    transport.respond(1, {success:true, snapshots:requests.map(function(request, index) {
        return makeSnapshot(request, 20 + index);
    })});
    assert.strictEqual(transport.calls.length, 2);
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.deepStrictEqual(coordinator.getRequest('背包').filterSpec,
        {branch:'category', major:'all'});
});

test('auto-transfer batch sends one ordered wire command and adopts its snapshots once', function() {
    const transport = new DeferredTransport();
    const requests = [
        {containerId:'背包', offset:0, limit:2, filterKey:'all'},
        {containerId:'仓库', offset:0, limit:2, filterKey:'all'}
    ];
    const coordinator = createCoordinator(transport, requests);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const sources = [0, 1].map(function(slotIndex) {
        return {containerId:'背包', slot:slotIndex, expectedLease:'lease.source.' + slotIndex,
            occupied:true, item:makeItem({name:'批量源' + slotIndex})};
    });
    const results = [];
    assert.strictEqual(coordinator.autoTransferBatch(sources, '仓库', function(result) {
        results.push(result);
    }), true);
    assert.strictEqual(transport.calls.length, 2);
    assert.strictEqual(coordinator.debugState().busyOwner, 'inventory.autoTransferBatch');
    assert.strictEqual(transport.calls[1].cmd, 'autoTransferBatch');
    assert.deepStrictEqual(transport.calls[1].payload, {
        v:1,
        sources:[
            {containerId:'背包', slot:0, expectedLease:'lease.source.0'},
            {containerId:'背包', slot:1, expectedLease:'lease.source.1'}
        ],
        targetContainerId:'仓库',
        policy:'mergeThenEmpty',
        windows:requests
    });
    transport.respond(1, {
        success:true,
        completedCount:2,
        snapshots:requests.map(function(request, index) { return makeSnapshot(request, 20 + index); })
    });
    assert.strictEqual(transport.calls.length, 2);
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].completedCount, 2);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
    assert.strictEqual(coordinator.getWindow('背包').snapshotSeq, 20);
    assert.strictEqual(coordinator.getWindow('仓库').snapshotSeq, 21);
});

test('auto-transfer batch adopts an authoritative partial prefix response', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const results = [];
    const sources = [0, 1].map(function(slotIndex) {
        return {containerId:'背包', slot:slotIndex, expectedLease:'lease.partial.' + slotIndex,
            occupied:true, item:makeItem({name:'部分批量源' + slotIndex})};
    });
    coordinator.autoTransferBatch(sources, '仓库', function(result) { results.push(result); });
    const windows = transport.calls[1].payload.windows;
    transport.respond(1, {
        success:true,
        completedCount:1,
        failure:{index:1, error:'target_full'},
        snapshots:windows.map(function(request, index) { return makeSnapshot(request, 30 + index); })
    });
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].success, true);
    assert.strictEqual(results[0].completedCount, 1);
    assert.deepStrictEqual(results[0].failure, {index:1, error:'target_full'});
    assert.strictEqual(transport.calls.length, 2);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
});

test('auto-transfer batch releases authoritative no-op capacity failures without reconcile', function() {
    ['target_full', 'slot_locked'].forEach(function(error) {
        const transport = new DeferredTransport();
        const coordinator = createCoordinator(transport);
        coordinator.open();
        transport.respond(0, exactResponse(transport.calls[0], 10));
        const results = [];
        coordinator.autoTransferBatch([{
            containerId:'背包', slot:0, expectedLease:'lease.noop', occupied:true, item:makeItem()
        }], '仓库', function(result) { results.push(result); });
        transport.respond(1, {success:false, error:error});
        assert.strictEqual(transport.calls.length, 2);
        assert.deepStrictEqual(results, [{success:false, error:error}]);
        assert.strictEqual(coordinator.debugState().busyOwner, null);
        assert.strictEqual(coordinator.debugState().ready, true);
        assert.strictEqual(coordinator.debugState().refreshRequired, false);
    });
});

test('auto-transfer batch reconciles every ambiguous failure before reporting it', function() {
    const transport = new DeferredTransport();
    const coordinator = createCoordinator(transport);
    coordinator.open();
    transport.respond(0, exactResponse(transport.calls[0], 10));
    const results = [];
    coordinator.autoTransferBatch([{
        containerId:'背包', slot:0, expectedLease:'lease.ambiguous', occupied:true, item:makeItem()
    }], '仓库', function(result) { results.push(result); });
    transport.respond(1, {success:false, error:'timeout'});
    assert.strictEqual(results.length, 0);
    assert.strictEqual(transport.calls.length, 3);
    assert.strictEqual(transport.calls[2].cmd, 'snapshot');
    assert.strictEqual(coordinator.debugState().busyOwner, 'inventory.autoTransferBatch');
    transport.respond(2, exactResponse(transport.calls[2], 40));
    assert.deepStrictEqual(results, [{success:false, error:'timeout',
        reconciled:true, refreshError:null}]);
    assert.strictEqual(coordinator.debugState().busyOwner, null);
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
