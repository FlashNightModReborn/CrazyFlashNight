#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const LootState = require('../loot-state.js');
const LootRuntime = require('../loot-runtime.js');
const LootOrganizer = require('../loot-organizer.js');
const PanelRuntime = require('../../panel-runtime.js');

const identity = {
    panelInstanceId:'panel.loot.test.1', chestSessionId:'chest.test.1', lootContainerId:'loot.test.1',
    containerEpoch:7, source:'map_chest'
};

function slot(index, name, lease, targetDomain) {
    return name ? {physicalSlot:index, occupied:true, slotLease:lease,
        targetDomain:targetDomain || 'inventory',
        item:{name:name, displayName:name, icon:name, itemKind:'stack', quantity:1}}
        : {physicalSlot:index, occupied:false, slotLease:'lease.empty.' + index, item:null};
}
function windowSnapshot(containerId, slots, closeLease) {
    return {containerId, offset:0, limit:slots.length, capacity:slots.length,
        accessibleCapacity:slots.length, snapshotSeq:1, containerVersion:1, closeLease:closeLease || '', slots};
}
function active(revision, lootSlots, extra) {
    extra = extra || {};
    return Object.assign({success:true, error:'', authorityRevision:revision,
        lastAppliedOperationId:extra.lastAppliedOperationId || '', state:'LOOT_ACTIVE',
        remainingCount:lootSlots.filter(x => x.occupied).length,
        closeLease:'close.' + revision,
        snapshots:[windowSnapshot(identity.lootContainerId, lootSlots, 'close.' + revision),
            windowSnapshot('背包', [slot(0), slot(1)]),
            windowSnapshot('药剂栏', [slot(0),slot(1),slot(2),slot(3),
                slot(4),slot(5),slot(6),slot(7)])], tooltip:null,materials:null,
        terminal:null}, extra);
}
function terminal(revision, kind, operationId, remaining) {
    return {success:true,error:'',authorityRevision:revision,lastAppliedOperationId:operationId,
        state:kind,remainingCount:remaining,closeLease:'',snapshots:[],tooltip:null,materials:null,
        terminal:{kind,reason:kind.toLowerCase(),remainingCount:remaining}};
}
function suspended(revision, operationId, remaining) {
    return {success:true,error:'',authorityRevision:revision,lastAppliedOperationId:operationId,
        state:'LOOT_SUSPENDED',remainingCount:remaining,closeLease:'',snapshots:[],tooltip:null,materials:null,
        terminal:null};
}
function rejectedNoWrite(error, revision, remaining, lastAppliedOperationId) {
    return {success:false,error,authorityRevision:revision,
        lastAppliedOperationId:lastAppliedOperationId || '',state:'LOOT_ACTIVE',
        remainingCount:remaining,closeLease:'',snapshots:[],tooltip:null,materials:null,terminal:null};
}

function hostFencedReconcile(revision, remaining, lastAppliedOperationId) {
    return {success:false,error:'reconcile_required',authorityRevision:revision,
        lastAppliedOperationId:lastAppliedOperationId || '',state:'LOOT_ACTIVE',
        remainingCount:remaining,closeLease:'',snapshots:[],tooltip:null,materials:null,terminal:null};
}

function fakeTransport() {
    let sequence = 0;
    const calls = [];
    function request(cmd, fields, options, callback) {
        const entry = {callId:'call.' + (++sequence),cmd};
        const call = {cmd,fields,options,callback,entry}; calls.push(call);
        if (options && options.onIssued) options.onIssued(entry, {});
        return entry.callId;
    }
    return {calls, request, respond(index, response) {
        const call = calls[index]; call.callback(response, call.entry);
    }};
}

const checks = [];
function test(name, fn) {
    fn(); checks.push(name);
}

test('projection requires complete loot window and exact remaining count', () => {
    const valid = LootState.normalizeProjection(active(1, [slot(0,'强化石','lease.0'),slot(1)]), identity);
    assert(valid && valid.remainingCount === 1 && valid.closeLease === 'close.1');
    const corrupt = active(1, [slot(0,'强化石','lease.0'),slot(1)]);
    corrupt.remainingCount = 0;
    assert.strictEqual(LootState.normalizeProjection(corrupt, identity), null);
    const legacyState = active(1,[slot(0),slot(1)]); legacyState.state = 'SNAPSHOT_ACTIVE';
    assert.strictEqual(LootState.normalizeProjection(legacyState, identity), null);
    const stringRevision=active(1,[slot(0),slot(1)]);stringRevision.authorityRevision='1';
    assert.strictEqual(LootState.normalizeProjection(stringRevision,identity),null);
});

test('occupied item triples reject blank and wrapped-case undefined identities', () => {
    ['name','displayName','icon'].forEach((field,index) => {
        const response=active(1,[slot(0,'强化石','lease.identity.'+index),slot(1)]);
        response.snapshots[0].slots[0].item[field]=index===1?'   ':' Undefined ';
        assert.strictEqual(LootState.normalizeProjection(response,identity),null);
    });
});

test('nested mod triples reject blank and wrapped-case undefined identities', () => {
    ['name','displayName','icon'].forEach((field,index) => {
        const response=active(1,[slot(0,'强化石','lease.mod.'+index),slot(1)]);
        response.snapshots[0].slots[0].item.modSlots=[{
            name:'插件内部名',displayName:'插件展示名',icon:'插件图标'
        }];
        response.snapshots[0].slots[0].item.modSlots[0][field]=
            index===1?'   ':' Undefined ';
        assert.strictEqual(LootState.normalizeProjection(response,identity),null);
    });
    const meta=active(1,[slot(0,'强化石','lease.mod.meta'),slot(1)]);
    meta.snapshots[0].slots[0].item.modMeta={
        name:'插件内部名',displayName:'插件展示名',icon:' Undefined '
    };
    assert.strictEqual(LootState.normalizeProjection(meta,identity),null);
});

test('occupied backpack slot requires an authoritative confirm projection', () => {
    const response=active(1,[slot(0),slot(1)]);
    const occupied=slot(0,'强化石','lease.confirm.missing');
    Object.assign(occupied.item,{rarity:'普通',enhancementLevel:0});
    response.snapshots[1].slots[0]=occupied;
    assert.strictEqual(LootState.normalizeProjection(response,identity),null);
});

test('backpack confirm projection must agree exactly with its sanitized item identity and state', () => {
    const corruptions=['itemKind','name','displayName','quantity','enhancementLevel','rarity'];
    corruptions.forEach((field,index) => {
        const response=active(1,[slot(0),slot(1)]);
        const occupied=slot(0,'强化石','lease.confirm.'+index);
        Object.assign(occupied.item,{rarity:'普通',enhancementLevel:0});
        occupied.confirmProjection={
            itemKind:'stack',name:'强化石',displayName:'强化石',quantity:1,
            enhancementLevel:0,rarity:'普通',tier:'',modSignature:'',lastUpdate:1
        };
        occupied.confirmProjection[field]=field==='quantity'||field==='enhancementLevel'
            ? 2 : '伪造值';
        response.snapshots[1].slots[0]=occupied;
        assert.strictEqual(LootState.normalizeProjection(response,identity),null);
    });
    const extra=active(1,[slot(0),slot(1)]);
    const occupied=slot(0,'强化石','lease.confirm.extra');
    Object.assign(occupied.item,{rarity:'普通',enhancementLevel:0});
    occupied.confirmProjection={
        itemKind:'stack',name:'强化石',displayName:'强化石',quantity:1,
        enhancementLevel:0,rarity:'普通',tier:'',modSignature:'',lastUpdate:1,
        unproved:true
    };
    extra.snapshots[1].slots[0]=occupied;
    assert.strictEqual(LootState.normalizeProjection(extra,identity),null);
});

test('all frozen terminal tombstones are strict and carry no snapshots', () => {
    ['CONSUMED','ABANDONED','EXPIRED'].forEach((kind,index) => {
        const value=LootState.normalizeProjection(terminal(index+1,kind,'op.terminal.'+index,index),identity);
        assert(value&&value.terminal.kind===kind&&value.remainingCount===index);
    });
    const corrupt=terminal(4,'EXPIRED','op.terminal.bad',1);corrupt.snapshots=[windowSnapshot('背包',[slot(0)])];
    assert.strictEqual(LootState.normalizeProjection(corrupt,identity),null);
    const noTombstone=terminal(5,'EXPIRED','op.terminal.none',0);noTombstone.terminal=null;
    assert.strictEqual(LootState.normalizeProjection(noTombstone,identity),null);
    const leasedTerminal=terminal(6,'EXPIRED','op.terminal.lease',0);leasedTerminal.closeLease='close.stale';
    assert.strictEqual(LootState.normalizeProjection(leasedTerminal,identity),null);
    const mismatchedRemaining=terminal(7,'ABANDONED','op.terminal.count',1);mismatchedRemaining.terminal.remainingCount=2;
    assert.strictEqual(LootState.normalizeProjection(mismatchedRemaining,identity),null);
});

test('terminal disposition rejects impossible remaining counts', () => {
    assert.strictEqual(LootState.normalizeProjection(
        terminal(8,'CONSUMED','op.consumed.nonempty',1),identity),null);
    assert.strictEqual(LootState.normalizeProjection(
        terminal(9,'ABANDONED','op.abandoned.empty',0),identity),null);
});

test('suspended authority projection is nonterminal and strictly data-free', () => {
    const valid=LootState.normalizeProjection(suspended(2,'op.suspend.1',1),identity);
    assert(valid&&valid.state==='SUSPENDED'&&valid.terminal===null&&valid.remainingCount===1);
    const empty=suspended(2,'op.suspend.empty',0);
    assert.strictEqual(LootState.normalizeProjection(empty,identity),null);
    const settlementIdentity=Object.assign({},identity,{source:'stage_settlement'});
    assert.strictEqual(LootState.normalizeProjection(empty,settlementIdentity),null);
    const emptyProjection=LootState.normalizeProjection(empty,settlementIdentity,true);
    assert(emptyProjection&&emptyProjection.state==='SUSPENDED'
        &&emptyProjection.terminal===null&&emptyProjection.remainingCount===0);
    assert.strictEqual(LootState.normalizeProjection(empty,identity,true),null);
    const leased=suspended(2,'op.suspend.lease',1);leased.closeLease='close.stale';
    assert.strictEqual(LootState.normalizeProjection(leased,identity),null);
    const snapshot=suspended(2,'op.suspend.snapshot',1);
    snapshot.snapshots=[windowSnapshot(identity.lootContainerId,[slot(0,'材料','lease.mat')])];
    assert.strictEqual(LootState.normalizeProjection(snapshot,identity),null);
    const tombstone=suspended(2,'op.suspend.terminal',1);
    tombstone.terminal={kind:'ABANDONED',reason:'explicit_abandon',remainingCount:1};
    assert.strictEqual(LootState.normalizeProjection(tombstone,identity),null);
});

test('operation ids remain unique when the same authority session is rebound', () => {
    const first=fakeTransport(),second=fakeTransport();
    const a=new LootState.Coordinator({identity,capacity:2,operationNonce:'view.a',request:first.request});
    const b=new LootState.Coordinator({identity,capacity:2,operationNonce:'view.b',request:second.request});
    a.open();b.open();
    first.respond(0,active(1,[slot(0,'强化石','lease.0'),slot(1)]));
    second.respond(0,active(1,[slot(0,'强化石','lease.0'),slot(1)]));
    a.claim(a.projection().loot.slots[0]);b.claim(b.projection().loot.slots[0]);
    assert.notStrictEqual(first.calls[1].fields.operationId,second.calls[1].fields.operationId);
});

test('open requests authoritative backpack and whole loot windows', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:2,request:wire.request});
    assert(model.open());
    assert.deepStrictEqual(wire.calls[0].fields, {loot:{offset:0,limit:2},backpack:{offset:0,limit:50}});
    wire.respond(0, active(1,[slot(0,'强化石','lease.0'),slot(1)]));
    assert.strictEqual(model.debugState().phase,'active');
});

test('coordinator rejects snapshots that contradict the bound capacities', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0),slot(1)]));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
});

test('claim is one-way and exact target-full zero-write proof preserves source projection', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open(); wire.respond(0, active(1,[slot(0,'强化石','lease.0'),slot(1)],
        {lastAppliedOperationId:'previous.operation'}));
    const source = model.projection().loot.slots[0];
    assert(model.claim(source));
    assert.strictEqual(wire.calls[1].fields.direction,'loot_to_player');
    assert.strictEqual(wire.calls[1].fields.targetContainerId,'自动');
    assert.deepStrictEqual(wire.calls[1].fields.source,
        {containerId:identity.lootContainerId,slot:0,expectedLease:'lease.0',expectedContainerVersion:1});
    assert.deepStrictEqual(Object.keys(wire.calls[1].fields).sort(),
        ['direction','expectedAuthorityRevision','operationId','source','targetContainerId'].sort());
    wire.respond(1,rejectedNoWrite('target_full',1,1,'previous.operation'));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,1);
    assert.strictEqual(model.debugState().blockReason,'target_full');
});

test('exact inventory-full zero-write proof remains active and can close through suspend', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.inventory-full'),slot(1)]));
    assert(model.claim(model.projection().loot.slots[0]));
    wire.respond(1,rejectedNoWrite('inventory_full',1,1,''));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,1);
    assert.strictEqual(model.debugState().blockReason,'inventory_full');
    assert(model.close(false));
    const close=wire.calls[2];
    const operationId=close.fields.operationId;
    assert.strictEqual(close.fields.abandon,false);
    wire.respond(2,suspended(2,operationId,1));
    assert.strictEqual(model.debugState().phase,'suspended');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,1);
});

test('only a stage-settlement coordinator with a normalized report accepts suspended zero', () => {
    const empty=suspended(2,'op.suspend.empty.coordinator',0);
    const mapWire=fakeTransport();
    const mapModel=new LootState.Coordinator({identity,capacity:2,request:mapWire.request});
    mapModel.open();mapWire.respond(0,empty);
    assert.strictEqual(mapModel.debugState().phase,'reconcile_required');

    const settlementIdentity=Object.assign({},identity,{source:'stage_settlement'});
    const stageWire=fakeTransport();
    const stageModel=new LootState.Coordinator({identity:settlementIdentity,capacity:2,
        settlementReport:{v:1},request:stageWire.request});
    stageModel.open();stageWire.respond(0,empty);
    assert.strictEqual(stageModel.debugState().phase,'suspended');
    assert.strictEqual(stageModel.debugState().remainingCount,0);
});

test('claim batch freezes exact source refs and accepts only the proven partial authority advance', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:3,request:wire.request});
    const before=[slot(0,'黑暗吉他','lease.batch.0'),slot(1,'抗生素','lease.batch.1'),
        slot(2,'强化石','lease.batch.2')];
    model.open();wire.respond(0,active(1,before));
    assert(model.claimBatch(model.projection().loot.slots));
    const write=wire.calls[1],operationId=write.fields.operationId;
    assert.strictEqual(write.cmd,'claimBatch');
    assert.deepStrictEqual(write.fields.sources,[
        {containerId:identity.lootContainerId,slot:0,expectedLease:'lease.batch.0',expectedContainerVersion:1},
        {containerId:identity.lootContainerId,slot:1,expectedLease:'lease.batch.1',expectedContainerVersion:1},
        {containerId:identity.lootContainerId,slot:2,expectedLease:'lease.batch.2',expectedContainerVersion:1}
    ]);
    assert.deepStrictEqual(Object.keys(write.fields).sort(),
        ['direction','expectedAuthorityRevision','operationId','sources','targetContainerId'].sort());
    wire.respond(1,active(3,[before[0],slot(1),slot(2)],
        {lastAppliedOperationId:operationId}));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,1);
    assert.strictEqual(model.projection().loot.slots[0].slotLease,'lease.batch.0');
});

test('claim batch capacity error needs an exact zero-write proof for every frozen source', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    const before=[slot(0,'物资A','lease.batch.full.0'),slot(1,'物资B','lease.batch.full.1')];
    model.open();wire.respond(0,active(4,before,{lastAppliedOperationId:'previous.batch'}));
    assert(model.claimBatch(model.projection().loot.slots));
    wire.respond(1,rejectedNoWrite('target_full',4,2,'previous.batch'));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,2);
    assert.strictEqual(model.debugState().blockReason,'target_full');

    assert(model.claimBatch(model.projection().loot.slots));
    const unproved=rejectedNoWrite('target_full',5,2,'previous.batch');
    wire.respond(2,unproved);
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown.refreshOnly,true);
});

test('unknown claim batch settles only against its exact frozen no-write prestate', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    const before=[slot(0,'物资A','lease.batch.unknown.0'),slot(1,'物资B','lease.batch.unknown.1')];
    model.open();wire.respond(0,active(7,before,{lastAppliedOperationId:'previous.operation'}));
    assert(model.claimBatch(model.projection().loot.slots));
    wire.respond(1,hostFencedReconcile(7,2,'previous.operation'));
    const unknown=model.debugState().unknown;
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.deepStrictEqual(unknown.physicalSlots,[0,1]);
    assert.deepStrictEqual(unknown.slotLeases,['lease.batch.unknown.0','lease.batch.unknown.1']);
    assert(model.query());wire.respond(2,active(7,before,{lastAppliedOperationId:'previous.operation'}));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,2);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claimBatch').length,1);
});

test('claim batch rejects duplicate physical slots before issuing a write', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.batch.duplicate'),slot(1)]));
    const source=model.projection().loot.slots[0];
    assert.strictEqual(model.claimBatch([source,source]),false);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claimBatch').length,0);
});

test('capacity failures without every exact raw prestate field fail closed', () => {
    const corruptions=[
        response => { delete response.authorityRevision; },
        response => { response.authorityRevision=2; },
        response => { response.remainingCount=0; },
        response => { response.lastAppliedOperationId='other.operation'; },
        response => { response.closeLease='close.unexpected'; },
        response => { response.snapshots=[{}]; },
        response => { response.tooltip={}; },
        response => { response.terminal={}; }
    ];
    corruptions.forEach((corrupt,index) => {
        const wire=fakeTransport();
        const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
        model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.capacity.'+index),slot(1)]));
        model.claim(model.projection().loot.slots[0]);
        const response=rejectedNoWrite(index%2?'inventory_full':'target_full',1,1,'');
        corrupt(response);wire.respond(1,response);
        assert.strictEqual(model.debugState().phase,'reconcile_required');
        assert.strictEqual(model.debugState().unknown.refreshOnly,true);
        assert.strictEqual(model.close(false),false);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,0);
    });
});

test('capacity proof requires the exact requested local source lease', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.authority'),slot(1)]));
    assert(model.claim(slot(0,'强化石','lease.forged')));
    wire.respond(1,rejectedNoWrite('target_full',1,1,''));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown.refreshOnly,true);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('stale write failures always reconcile and a fresh authority query unlocks without replay', () => {
    ['stale_lease','stale_state'].forEach((error,index) => {
        const wire=fakeTransport();
        const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
        model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.stale.old.'+index),slot(1)]));
        model.claim(model.projection().loot.slots[0]);
        wire.respond(1,rejectedNoWrite(error,2,1,'other.operation.'+index));
        assert.strictEqual(model.debugState().phase,'reconcile_required');
        assert.strictEqual(model.debugState().unknown.error,error);
        assert.strictEqual(model.debugState().unknown.refreshOnly,true);
        assert.strictEqual(model.debugState().unknown.freshnessWatermark,2);
        assert.strictEqual(model.close(false),false);
        assert(model.query());
        wire.respond(2,active(1,[slot(0,'强化石','lease.stale.old.'+index),slot(1)]));
        assert.strictEqual(model.debugState().phase,'reconcile_required');
        assert.strictEqual(model.debugState().blockReason,'stale_reconcile');
        assert(model.query());
        wire.respond(3,suspended(2,'other.suspend.'+index,1));
        assert.strictEqual(model.debugState().phase,'reconcile_required');
        assert.strictEqual(model.debugState().blockReason,'stale_reconcile');
        assert(model.query());
        wire.respond(4,active(2,[slot(0,'强化石','lease.stale.fresh.'+index),slot(1)],
            {lastAppliedOperationId:'other.operation.'+index}));
        assert.strictEqual(model.debugState().phase,'active');
        assert.strictEqual(model.projection().loot.slots[0].slotLease,'lease.stale.fresh.'+index);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,0);
    });
});

test('refresh-only reconciliation may settle a fresh strict terminal tombstone', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.stale.terminal')]));
    model.claim(model.projection().loot.slots[0]);
    wire.respond(1,rejectedNoWrite('stale_state',2,1,'other.operation'));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();wire.respond(2,terminal(2,'EXPIRED','other.operation',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,0);
});

test('a valid terminal projection may settle a non-stale failed write', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.terminal')]));
    model.claim(model.projection().loot.slots[0]);
    const response=terminal(2,'EXPIRED','other.terminal',1);
    response.success=false;response.error='terminal';
    wire.respond(1,response);
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('prototype property names never satisfy terminal or no-write allowlists', () => {
    const forged=terminal(2,'EXPIRED','op.prototype',1);
    forged.state='constructor';forged.terminal.kind='constructor';
    assert.strictEqual(LootState.normalizeProjection(forged,identity),null);

    const claimWire=fakeTransport();
    const claimModel=new LootState.Coordinator({identity,capacity:2,request:claimWire.request});
    claimModel.open();claimWire.respond(0,active(1,[slot(0,'强化石','lease.prototype'),slot(1)]));
    claimModel.claim(claimModel.projection().loot.slots[0]);
    claimWire.respond(1,{success:false,error:'constructor'});
    assert.strictEqual(claimModel.debugState().phase,'reconcile_required');
    assert.strictEqual(claimModel.debugState().unknown.error,'constructor');

    const closeWire=fakeTransport();
    const closeModel=new LootState.Coordinator({identity,capacity:2,request:closeWire.request});
    closeModel.open();closeWire.respond(0,active(1,[slot(0,'强化石','lease.close.prototype'),slot(1)]));
    closeModel.close(false);closeWire.respond(1,{success:false,error:'constructor'});
    assert.strictEqual(closeModel.debugState().phase,'reconcile_required');
    assert.strictEqual(closeModel.debugState().unknown.error,'constructor');
});

test('claim success requires operation identity and applies fresh snapshots', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'带配件装备','lease.eq'),slot(1)]));
    model.claim(model.projection().loot.slots[0]);
    const op = wire.calls[1].fields.operationId;
    wire.respond(1,active(2,[slot(0),slot(1)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().remainingCount,0);
    assert.strictEqual(model.debugState().phase,'active');
});

test('active refresh is read-only, freezes writes, and applies one fresh strict snapshot', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'强化石','lease.refresh'),slot(1)]));
    let result=null;
    assert(model.refresh((success,response)=>{result={success,response}}));
    assert.strictEqual(model.debugState().pending.kind,'refresh');
    assert.strictEqual(model.claim(model.projection().loot.slots[0]),false);
    assert.strictEqual(model.close(false),false);
    assert.deepStrictEqual(wire.calls[1].fields,
        {loot:{offset:0,limit:2},backpack:{offset:0,limit:50}});
    const fresh=active(1,[slot(0,'强化石','lease.refresh'),slot(1)]);
    fresh.snapshots[1]=windowSnapshot('背包',[slot(0),slot(1)]);
    wire.respond(1,fresh);
    assert(result&&result.success===true);
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().pending,null);
    assert.strictEqual(wire.calls.filter(call=>call.cmd==='claim').length,0);
    assert.strictEqual(wire.calls.filter(call=>call.cmd==='close').length,0);
});

test('active refresh failure retains the last projection and never enables replay through callback', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(2,[slot(0,'强化石','lease.refresh.fail'),slot(1)]));
    const before=model.projection();let succeeded=true;
    assert(model.refresh(success=>{succeeded=success}));
    wire.respond(1,{success:false,error:'snapshot_failed'});
    assert.strictEqual(succeeded,false);
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().blockReason,'snapshot_failed');
    assert.strictEqual(model.projection(),before);
    assert.strictEqual(wire.calls.filter(call=>call.cmd==='claim'||call.cmd==='close').length,0);
    assert(model.refresh());
    wire.respond(2,active(1,[slot(0,'强化石','lease.stale'),slot(1)]));
    assert.strictEqual(model.projection(),before);
    assert.strictEqual(model.debugState().blockReason,'loot_refresh_failed');
});

test('claim success rejects every non-exact authority advance without replay', () => {
    const cases=[
        {
            name:'same revision',
            response:(op) => active(1,[slot(0),slot(1,'物资B','lease.b'),slot(2)],
                {lastAppliedOperationId:op})
        },
        {
            name:'revision jumps by two',
            response:(op) => active(3,[slot(0),slot(1,'物资B','lease.b'),slot(2)],
                {lastAppliedOperationId:op})
        },
        {
            name:'remaining count does not decrement',
            response:(op) => active(2,[slot(0),slot(1,'物资B','lease.b'),
                slot(2,'意外物资','lease.unexpected')],{lastAppliedOperationId:op})
        },
        {
            name:'remaining count decrements by two',
            response:(op) => active(2,[slot(0),slot(1),slot(2)],
                {lastAppliedOperationId:op})
        },
        {
            name:'a different slot empties while the requested slot remains occupied',
            response:(op) => active(2,[slot(0,'物资A','lease.a'),slot(1),slot(2)],
                {lastAppliedOperationId:op})
        }
    ];
    cases.forEach((value,index) => {
        const wire=fakeTransport();
        const model=new LootState.Coordinator({identity,capacity:3,request:wire.request});
        model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.a'),
            slot(1,'物资B','lease.b'),slot(2)]));
        let callbackSuccess=null;
        assert(model.claim(model.projection().loot.slots[0],success => { callbackSuccess=success; }));
        const op=wire.calls[1].fields.operationId;
        wire.respond(1,value.response(op));
        assert.strictEqual(callbackSuccess,false,value.name);
        assert.strictEqual(model.debugState().phase,'reconcile_required',value.name);
        assert.strictEqual(model.debugState().authorityRevision,1,value.name);
        assert.strictEqual(model.debugState().remainingCount,2,value.name);
        assert.strictEqual(model.close(false),false,value.name);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1,value.name);
        assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,0,value.name);
    });
});

test('claim success requires the exact requested physical slot to exist and be empty', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:3,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.a'),
        slot(1,'物资B','lease.b'),slot(2)]));
    assert(model.claim(slot(7,'伪造目标','lease.forged')));
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,active(2,[slot(0),slot(1,'物资B','lease.b'),slot(2)],
        {lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().authorityRevision,1);
    assert.strictEqual(model.debugState().remainingCount,2);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('a rejected malformed claim success cannot be laundered through the next query', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:3,request:wire.request});
    const before=[slot(0,'物资A','lease.a'),slot(1,'物资B','lease.b'),slot(2)];
    model.open();wire.respond(0,active(1,before));
    assert(model.claim(model.projection().loot.slots[0]));
    const op=wire.calls[1].fields.operationId;
    const wrong=active(2,[slot(0,'物资A','lease.a.next'),slot(1),slot(2)],
        {lastAppliedOperationId:op});
    wire.respond(1,wrong);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(2,wrong);
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().authorityRevision,1);
    assert.strictEqual(model.debugState().remainingCount,2);

    const sameRevisionDrift=active(1,[slot(0,'物资A','lease.changed'),
        slot(1,'物资B','lease.b'),slot(2)]);
    assert(model.query());wire.respond(3,sameRevisionDrift);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    const closeLeaseDrift=active(1,before);closeLeaseDrift.closeLease='close.changed';
    closeLeaseDrift.snapshots[0].closeLease='close.changed';
    assert(model.query());wire.respond(4,closeLeaseDrift);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(5,active(1,before));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(6,active(2,[slot(0),
        slot(1,'物资B','lease.b'),slot(2)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,1);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('a synthetic unknown claim may settle only on an exact unchanged authority prestate', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    const before=[slot(0,'物资A','lease.a'),slot(1)];
    model.open();wire.respond(0,active(1,before));
    assert(model.claim(model.projection().loot.slots[0]));
    wire.respond(1,{success:false,error:'reconcile_required',clientSynthetic:true,
        requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(2,active(1,before));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,1);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('an observed higher malformed revision cannot be rolled back by a later query', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.a'),slot(1)]));
    assert(model.claim(model.projection().loot.slots[0]));
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,active(3,[slot(0),slot(1)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(2,active(3,[slot(0),slot(1)],
        {lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(3,active(2,[slot(0),slot(1)],
        {lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(4,terminal(4,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('Host r3 reconciliation fence survives Web queries until r3 terminal authority', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.a')]));
    assert(model.claim(model.projection().loot.slots[0]));
    const op=wire.calls[1].fields.operationId;

    // This is the exact projection-shaped error emitted by the Host when its
    // authority observer has seen r3 but cannot prove the write response.
    wire.respond(1,hostFencedReconcile(3,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown.freshnessWatermark,3);

    // The Host also fences an unprovable query at r3.  Web must retain that
    // floor even though the error body is intentionally not an ACTIVE snapshot.
    assert(model.query());wire.respond(2,hostFencedReconcile(3,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown.freshnessWatermark,3);

    assert(model.query());wire.respond(3,active(2,[slot(0)],
        {lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().authorityRevision,1);

    assert(model.query());wire.respond(4,terminal(2,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().authorityRevision,1);

    assert(model.query());wire.respond(5,terminal(3,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('an unproven higher query raises the freshness floor against later rollback', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    const before=[slot(0,'物资A','lease.a'),slot(1)];
    model.open();wire.respond(0,active(1,before));
    assert(model.claim(model.projection().loot.slots[0]));
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,
        requiresReconcile:true});

    assert(model.query());wire.respond(2,active(5,before,
        {lastAppliedOperationId:'other.operation'}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(3,active(2,[slot(0),slot(1)],
        {lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(4,terminal(6,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('unknown claim accepts only a newer strict terminal tombstone', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'物资A','lease.a')]));
    assert(model.claim(model.projection().loot.slots[0]));
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,
        requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(2,terminal(1,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(3,terminal(2,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'claim').length,1);
});

test('ambiguous claim never replays and a higher unproven query bars rollback', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'金币','lease.gold','collection'),slot(1)]));
    model.claim(model.projection().loot.slots[0]);
    const op = wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());
    assert.deepStrictEqual(wire.calls[2].fields,{});
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'claim').length,1);
    wire.respond(2,active(3,[slot(0),slot(1)],{lastAppliedOperationId:'other.op'}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());
    wire.respond(3,active(2,[slot(0),slot(1)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());
    wire.respond(4,terminal(4,'EXPIRED','other.expire',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'claim').length,1);
});

test('known commit pending rejects same-revision and wrong-operation query proofs', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'金币','lease.gold','collection'),slot(1)]));
    model.claim(model.projection().loot.slots[0]);
    const op = wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'commit_pending',state:'LOOT_COMMIT_PENDING',
        authorityRevision:2,lastAppliedOperationId:op});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown.requiresCausalCompletion,true);
    assert.strictEqual(model.claim(model.projection().loot.slots[0]),false);
    assert.strictEqual(model.close(true),false);

    model.query();
    wire.respond(2,active(1,[slot(0,'金币','lease.gold','collection'),slot(1)],
        {lastAppliedOperationId:'other.op'}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();
    wire.respond(3,active(2,[slot(0),slot(1)],{lastAppliedOperationId:'other.op'}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();
    wire.respond(4,active(2,[slot(0),slot(1)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'claim').length,1);
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'close').length,0);
});

test('known commit pending accepts an exact terminal authority projection', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(4,[slot(0,'强化石','lease.0')]));
    model.claim(model.projection().loot.slots[0]);
    wire.respond(1,{success:false,error:'commit_pending',state:'LOOT_COMMIT_PENDING'});
    model.query();
    wire.respond(2,terminal(5,'EXPIRED','',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'claim').length,1);
});

test('commit pending query upgrades an ambiguous write to causal-only reconciliation', () => {
    const wire = fakeTransport();
    const model = new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'强化石','lease.0')]));
    model.claim(model.projection().loot.slots[0]);
    const op = wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});
    model.query();
    wire.respond(2,{success:false,error:'commit_pending',state:'LOOT_COMMIT_PENDING'});
    assert.strictEqual(model.debugState().unknown.requiresCausalCompletion,true);

    model.query();
    wire.respond(3,active(1,[slot(0,'强化石','lease.0')],
        {lastAppliedOperationId:'other.op'}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();
    wire.respond(4,active(2,[slot(0)],{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(wire.calls.filter(x => x.cmd === 'claim').length,1);
});

test('a causally queried authority terminal supersedes an ambiguous write', () => {
    const wire=fakeTransport();
    const model=new LootState.Coordinator({identity,capacity:2,request:wire.request});
    model.open();wire.respond(0,active(4,[slot(0,'强化石','lease.0'),slot(1)]));
    model.claim(model.projection().loot.slots[0]);
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();
    wire.respond(2,terminal(5,'EXPIRED','',1));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
});

test('ordinary suspended query after initial snapshot failure cannot close reconciliation', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({
        identity,capacity:1,request:wire.request
    });
    let querySucceeded=null;
    model.open();
    wire.respond(0,{success:false,error:'snapshot_failed'});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(model.debugState().unknown,null);

    assert(model.query((ok) => { querySucceeded=ok; }));
    wire.respond(1,suspended(3,'unrelated.suspend.operation',1));
    assert.strictEqual(querySucceeded,false);
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert.strictEqual(wire.calls.filter(x=>x.cmd==='close').length,0);
});

test('strict terminal error tombstone may settle a reconciliation query', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({
        identity,capacity:1,request:wire.request
    });
    let querySucceeded=null;
    model.open();
    wire.respond(0,{success:false,error:'snapshot_failed'});
    assert(model.query((ok) => { querySucceeded=ok; }));
    const tombstone=terminal(3,'EXPIRED','',0);
    tombstone.success=false;
    tombstone.error='terminal_state';
    wire.respond(1,tombstone);
    assert.strictEqual(querySucceeded,true);
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'EXPIRED');
});

test('empty close consumes, nonempty normal close suspends, and danger close abandons', () => {
    let wire = fakeTransport();
    let model = new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0)]));
    assert(model.close(false));
    let op = wire.calls[1].fields.operationId;
    assert.strictEqual(wire.calls[1].fields.abandon,false);
    wire.respond(1,terminal(2,'CONSUMED',op,0));
    assert.strictEqual(model.debugState().terminal.kind,'CONSUMED');

    wire = fakeTransport(); model = new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'材料','lease.mat')]));
    assert(model.close(false));
    op = wire.calls[1].fields.operationId;
    assert(op.indexOf('loot-op.suspend.')===0);
    assert.strictEqual(wire.calls[1].fields.abandon,false);
    wire.respond(1,suspended(2,op,1));
    assert.strictEqual(model.debugState().phase,'suspended');

    wire = fakeTransport(); model = new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0,'材料','lease.mat')]));
    assert(model.close(true));
    op = wire.calls[1].fields.operationId;
    assert.strictEqual(wire.calls[1].fields.abandon,true);
    wire.respond(1,terminal(2,'ABANDONED',op,1));
    assert.strictEqual(model.debugState().terminal.kind,'ABANDONED');
});

test('suspend requires monotonic exact authority result and query settles ack loss', () => {
    let wire=fakeTransport(),model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(4,[slot(0,'材料','lease.mat')]));
    model.close(false);
    let op=wire.calls[1].fields.operationId;
    wire.respond(1,suspended(4,op,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    wire=fakeTransport();model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(4,[slot(0,'材料','lease.mat')]));
    model.close(false);op=wire.calls[1].fields.operationId;
    wire.respond(1,suspended(6,op,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    wire=fakeTransport();model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(4,[slot(0,'材料','lease.mat')]));
    model.close(false);op=wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();wire.respond(2,suspended(5,'other.close.operation',1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();wire.respond(3,suspended(4,op,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();wire.respond(4,suspended(5,op,2));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query();wire.respond(5,suspended(5,op,1));
    assert.strictEqual(model.debugState().phase,'suspended');
    assert.strictEqual(wire.calls.filter(x=>x.cmd==='close').length,1);
});

test('unknown close rejects ACTIVE causal fiction and cannot roll back to an older no-write prestate', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({
        identity,capacity:3,request:wire.request
    });
    const before=[slot(0,'物资A','lease.a'),slot(1,'物资B','lease.b'),slot(2)];
    model.open();wire.respond(0,active(1,before));
    assert(model.close(false));
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,
        requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(2,active(2,before,{lastAppliedOperationId:op}));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(3,active(1,[slot(0,'物资A','lease.a'),slot(1),slot(2)]));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    const lastAppliedDrift=active(1,before,{lastAppliedOperationId:'other.operation'});
    assert(model.query());wire.respond(4,lastAppliedDrift);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    const closeLeaseDrift=active(1,before);closeLeaseDrift.closeLease='close.changed';
    closeLeaseDrift.snapshots[0].closeLease='close.changed';
    assert(model.query());wire.respond(5,closeLeaseDrift);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    const versionDrift=active(1,before);versionDrift.snapshots[0].containerVersion=2;
    assert(model.query());wire.respond(6,versionDrift);
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    assert(model.query());wire.respond(7,active(1,before));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(8,terminal(3,'EXPIRED','other.expire',2));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,1);
});

test('synthetic unknown close accepts an exact unchanged ACTIVE no-write prestate', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({
        identity,capacity:3,request:wire.request
    });
    const before=[slot(0,'物资A','lease.a'),slot(1,'物资B','lease.b'),slot(2)];
    model.open();wire.respond(0,active(1,before));
    assert(model.close(false));
    wire.respond(1,{success:false,error:'reconcile_required',clientSynthetic:true,
        requiresReconcile:true});
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    assert(model.query());wire.respond(2,active(1,before));
    assert.strictEqual(model.debugState().phase,'active');
    assert.strictEqual(model.debugState().remainingCount,2);
    assert.strictEqual(wire.calls.filter(call => call.cmd === 'close').length,1);
});

test('close success disposition is exact for intent and active prestate', () => {
    let wire=fakeTransport(),model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'材料','lease.mat')]));
    model.close(false);let op=wire.calls[1].fields.operationId;
    wire.respond(1,terminal(2,'CONSUMED',op,0));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    wire=fakeTransport();model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0)]));
    model.close(false);op=wire.calls[1].fields.operationId;
    wire.respond(1,suspended(2,op,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');

    wire=fakeTransport();model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open();wire.respond(0,active(1,[slot(0,'材料','lease.mat')]));
    model.close(true);op=wire.calls[1].fields.operationId;
    wire.respond(1,suspended(2,op,1));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
});

test('close ack loss queries terminal tombstone without replay', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); wire.respond(0,active(1,[slot(0)])); model.close(false);
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});
    model.query();
    wire.respond(2,terminal(2,'CONSUMED',op,0));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(wire.calls.filter(x=>x.cmd==='close').length,1);
});

test('unknown normal close requires a newer revision to prove consumed', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({
        identity,capacity:1,request:wire.request
    });
    model.open(); wire.respond(0,active(4,[slot(0)]));
    model.close(false);
    const op=wire.calls[1].fields.operationId;
    wire.respond(1,{success:false,error:'client_timeout',clientSynthetic:true,requiresReconcile:true});

    model.query(); wire.respond(2,terminal(4,'CONSUMED',op,0));
    assert.strictEqual(model.debugState().phase,'reconcile_required');
    model.query(); wire.respond(3,terminal(5,'CONSUMED',op,0));
    assert.strictEqual(model.debugState().phase,'terminal');
    assert.strictEqual(model.debugState().terminal.kind,'CONSUMED');
    assert.strictEqual(wire.calls.filter(x=>x.cmd==='close').length,1);
});

test('force detach ignores late authority responses', () => {
    const wire=fakeTransport(), model=new LootState.Coordinator({identity,capacity:1,request:wire.request});
    model.open(); model.forceDetach(); wire.respond(0,active(1,[slot(0)]));
    assert.strictEqual(model.debugState().phase,'detached');
});

test('runtime identity rejects non-positive and non-native integer epochs', () => {
    [-1,0,'1'].forEach(value => {
        assert.strictEqual(LootRuntime.normalizeIdentity(Object.assign({},identity,
            {containerEpoch:value})),null);
    });
    assert(LootRuntime.normalizeIdentity(identity));
});

test('runtime exact-key and command allowlists ignore prototype properties', () => {
    assert.strictEqual(LootRuntime.hasExactKeys(
        {type:'panel_resp',constructor:true},{type:true,success:true}),false);
    const runtime=new LootRuntime.RequestMux({
        identity,router:new PanelRuntime.PanelResponseRouter(),sessionNonce:'prototype-test',send:()=>true
    });
    runtime.openSession();
    assert.strictEqual(runtime.request('constructor',{},function(){}),null);
    runtime.destroy();
});

test('runtime uses one shared router and exact top-level envelope', () => {
    const sent=[], router=new PanelRuntime.PanelResponseRouter();
    const baseline=router.debugState().handlerCount;
    const runtime=new LootRuntime.RequestMux({identity,router,sessionNonce:'test',send:m=>{sent.push(m);return true;}});
    runtime.openSession(); let received=null;
    runtime.request('snapshot',{loot:{offset:0,limit:2},backpack:{offset:0,limit:50}},r=>{received=r});
    assert.strictEqual(router.debugState().handlerCount,baseline+1);
    assert.deepStrictEqual(Object.assign({},sent[0],{callId:'<id>'}),{
        type:'task',task:'loot_request',domain:'loot',panel:'loot',v:2,cmd:'snapshot',callId:'<id>',
        panelInstanceId:identity.panelInstanceId,
        chestSessionId:identity.chestSessionId,lootContainerId:identity.lootContainerId,
        containerEpoch:identity.containerEpoch,
        loot:{offset:0,limit:2},backpack:{offset:0,limit:50}
    });
    router.handleResponse(Object.assign({type:'panel_resp',task:'loot_response',domain:'loot',panel:'loot',cmd:'snapshot',
        callId:sent[0].callId,chestSessionId:identity.chestSessionId,
        panelInstanceId:identity.panelInstanceId,
        lootContainerId:identity.lootContainerId,containerEpoch:identity.containerEpoch},active(1,[slot(0),slot(1)])));
    assert(received && received.success === true);
    const source={containerId:identity.lootContainerId,slot:0,expectedLease:'lease.0',expectedContainerVersion:1};
    runtime.request('tooltip',{expectedAuthorityRevision:1,source},function(){});
    runtime.request('claim',{expectedAuthorityRevision:1,source,operationId:'op.strict.1',
        direction:'loot_to_player',targetContainerId:'自动'},
        {write:true,operationId:'op.strict.1'},function(){});
    runtime.request('close',{expectedAuthorityRevision:1,operationId:'op.strict.2',
        closeLease:'close.1',abandon:false},{write:true,operationId:'op.strict.2'},function(){});
    runtime.request('query',{},function(){});
    const common=['type','task','domain','panel','v','cmd','callId','panelInstanceId',
        'chestSessionId','lootContainerId','containerEpoch'];
    assert.deepStrictEqual(Object.keys(sent[1]).sort(),common.concat(['expectedAuthorityRevision','source']).sort());
    assert.deepStrictEqual(Object.keys(sent[2]).sort(),common.concat(['expectedAuthorityRevision','source','operationId','direction','targetContainerId']).sort());
    assert.deepStrictEqual(Object.keys(sent[3]).sort(),common.concat(['expectedAuthorityRevision','operationId','closeLease','abandon']).sort());
    assert.deepStrictEqual(Object.keys(sent[4]).sort(),common.sort());
    runtime.destroy();
    assert.strictEqual(router.debugState().handlerCount,baseline);
});

test('organizer inventory mux binds an exact loot panel envelope and rejects stale responses', () => {
    const sent=[],router=new PanelRuntime.PanelResponseRouter();
    const runtime=new LootOrganizer.RequestMux({
        panelInstanceId:identity.panelInstanceId,
        router,sessionNonce:'organizer-test',send:message=>{sent.push(message);return true;},
        onProtocolError:function() {}
    });
    runtime.openSession();let received=null;
    const payload={v:1,requests:[{containerId:'背包',offset:0,limit:50,filterKey:'all'}]};
    const callId=runtime.request('snapshot',payload,response=>{received=response});
    assert.deepStrictEqual(sent[0],{
        type:'panel',domain:'inventory',panel:'loot',panelInstanceId:identity.panelInstanceId,
        cmd:'snapshot',callId,payload
    });
    assert.strictEqual(router.handleResponse({
        type:'panel_resp',domain:'inventory',cmd:'snapshot',callId,
        panelInstanceId:identity.panelInstanceId,success:true,snapshots:[]
    }),false);
    assert.strictEqual(router.handleResponse({
        type:'panel_resp',domain:'inventory',panel:'loot',cmd:'snapshot',callId,
        panelInstanceId:'panel.stale',success:true,snapshots:[]
    }),false);
    assert.strictEqual(received,null);
    assert.strictEqual(runtime.debugState().pendingCount,1);
    assert.strictEqual(router.handleResponse({
        type:'panel_resp',domain:'inventory',panel:'loot',cmd:'snapshot',callId,
        panelInstanceId:identity.panelInstanceId,success:true,snapshots:[]
    }),true);
    assert(received&&received.success===true);
    assert.strictEqual(runtime.debugState().pendingCount,0);
    assert.strictEqual(runtime.request('constructor',{},function(){}),null);
    runtime.destroy();
});

test('organizer inventory mux permits only snapshot, transfer, and discard commands', () => {
    const sent=[],runtime=new LootOrganizer.RequestMux({
        panelInstanceId:identity.panelInstanceId,
        router:new PanelRuntime.PanelResponseRouter(),sessionNonce:'organizer-commands',
        send:message=>{sent.push(message);return true;}
    });
    runtime.openSession();
    assert(runtime.request('snapshot',{v:1,requests:[]},function(){}));
    assert(runtime.request('autoTransfer',{v:1},function(){}));
    assert(runtime.request('discard',{v:1},function(){}));
    assert.strictEqual(runtime.request('move',{v:1},function(){}),null);
    assert.deepStrictEqual(sent.map(message=>message.cmd),['snapshot','autoTransfer','discard']);
    runtime.destroy();
});

test('organizer keeps blocked inventory inspectable with an exact authority reason', () => {
    assert.deepStrictEqual(LootOrganizer.interactionForState({ready:true}),
        {inspectable:true,actionable:true,reason:''});
    [
        [{ready:false},'库存正在同步，请稍候。'],
        [{ready:true,busyOwner:'inventory.autoTransfer'},'库存正在处理另一项操作。'],
        [{ready:true,refreshRequired:true},'库存同步失败，请先重试。'],
        [{ready:true,returning:true},'正在重新核对当前箱子。']
    ].forEach(([state,reason]) => {
        assert.deepStrictEqual(LootOrganizer.interactionForState(state),
            {inspectable:true,actionable:false,reason});
    });
});

test('organizer owned inspection binds pointer and keyboard tooltip without a new authority request', () => {
    let captured = null;
    const binding = {destroy:function() { return true; }};
    const returned = LootOrganizer.bindOwnedInspection({
        tooltip:{bindAsyncHover:function(node, options) { captured = {node, options}; return binding; }},
        node:{id:'owned-slot'},
        containerId:'背包',
        slot:{occupied:true, physicalSlot:3, slotLease:'lease.inspect.3',
            item:{name:'internal', displayName:'展示名', icon:'icon-name', majorType:'材料'}},
        workbench:{ItemCard:{balanceTooltipMetaHtml:function(item) {
            return '<meta>' + item.majorType + '</meta>';
        }}}
    });
    assert.strictEqual(returned, binding);
    assert.strictEqual(captured.node.id, 'owned-slot');
    assert.strictEqual(captured.options.key, 'loot-organizer:背包:lease.inspect.3');
    assert.strictEqual(typeof captured.options.fetch, 'undefined');
    assert(captured.options.renderBasic(captured.options.item).includes('展示名'));
    assert(captured.options.renderBasic(captured.options.item).includes('<meta>材料</meta>'));
});

test('organizer tooltip scope releases replaced trees and is disposed with the presenter', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'loot-organizer.js'), 'utf8');
    assert(source.includes('this._tooltip.releaseTree(grid);'));
    assert(source.includes('this._tooltip.dispose(); this._tooltip = null;'));
    assert(source.includes("options.tooltip.createScope('loot-organizer', {profile:'simple-tooltip'})"));
});

console.log('loot state ' + checks.length + '/' + checks.length + ' passed');
