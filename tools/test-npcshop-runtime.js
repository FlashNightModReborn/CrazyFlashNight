'use strict';

const assert = require('assert');
const Runtime = require('../launcher/web/modules/npcshop-runtime.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    console.log('PASS ' + name);
}

function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

function ordinaryInit() {
    return {mode:'runtime',source:'character_build',debug:false,shopId:'迷之盔甲君',
        panelInstanceId:'npcshop.test~ordinary'};
}

function materialInit() {
    return {mode:'runtime',source:'crafting_materials',debug:false,shopId:'迷之盔甲君',
        panelInstanceId:'npcshop.test~material',preferredItemName:'战术握把',
        preferredCatalogIndex:57,canReturnCraftingMaterials:true,
        navigationOrigin:'crafting_materials'};
}

test('NPCShop initData is an exact ordinary/material-origin strict union', () => {
    assert.strictEqual(Runtime.parseInitData(ordinaryInit()).kind,'ordinary');
    assert.strictEqual(Runtime.parseInitData(materialInit()).kind,'crafting_materials');
    for (const malformed of [
        Object.assign({},ordinaryInit(),{extra:true}),
        Object.assign({},ordinaryInit(),{source:'crafting_materials'}),
        Object.assign({},materialInit(),{source:'character_build'}),
        Object.assign({},materialInit(),{canReturnCraftingMaterials:false}),
        Object.assign({},materialInit(),{navigationOrigin:'map'}),
        Object.assign({},materialInit(),{preferredCatalogIndex:10001}),
        Object.assign({},materialInit(),{preferredItemName:''}),
        Object.assign({},materialInit(),{panelInstanceId:'bad instance'})
    ]) assert.strictEqual(Runtime.parseInitData(malformed),null);

    const partial = materialInit();
    delete partial.preferredCatalogIndex;
    assert.strictEqual(Runtime.parseInitData(partial),null);
});

test('NPCShop target catalog index accepts the exact closed interval only', () => {
    assert.strictEqual(Runtime.SHOP_CATALOG_INDEX_MAX,10000);
    assert.strictEqual(Runtime.isShopCatalogIndex(0),true);
    assert.strictEqual(Runtime.isShopCatalogIndex(10000),true);
    for (const value of [-1,10001,1.5,'57',NaN,Infinity]) {
        assert.strictEqual(Runtime.isShopCatalogIndex(value),false);
    }
});

test('NPCShop same-name sale projection accepts only plain equipment', () => {
    assert.strictEqual(Runtime.isPlainProjectedItem(null), true);
    assert.strictEqual(Runtime.isPlainProjectedItem({itemKind:'material'}), true);
    assert.strictEqual(Runtime.isPlainProjectedItem({itemKind:'equipment'}), true);
    assert.strictEqual(Runtime.isPlainProjectedItem({itemKind:'equipment', enhancementLevel:2}), false);
    assert.strictEqual(Runtime.isPlainProjectedItem({itemKind:'equipment', tierSlotUsed:true}), false);
    assert.strictEqual(Runtime.isPlainProjectedItem({itemKind:'equipment', modSlotUsed:1}), false);
});

test('NPCShop explicit material return emits the exact five-key envelope', () => {
    const input = {callId:'material-return.test-1',panelInstanceId:'npcshop.test~material'};
    assert.deepStrictEqual(Runtime.createReturnCraftingMaterialsMessage(input),{
        type:'panel',panel:'npcshop',cmd:'return_crafting_materials',
        callId:'material-return.test-1',panelInstanceId:'npcshop.test~material'
    });
    assert.strictEqual(Runtime.createReturnCraftingMaterialsMessage(
        Object.assign({},input,{callId:'bad call'})),null);
    assert.strictEqual(Runtime.createReturnCraftingMaterialsMessage(
        Object.assign({},input,{panelInstanceId:'bad instance'})),null);
    assert.strictEqual(Runtime.NAVIGATION_WATCHDOG_MS,6500);
});

test('NPCShop diagnostics normalize into a closed redacted envelope', () => {
    const input = {event:'snapshot_rejected',cmd:'snapshot',
        callId:'npc.diagnostic.1',panelInstanceId:'npcshop.test~diagnostic',
        generation:7,error:'malformed_response'};
    assert.deepStrictEqual(Runtime.createDiagnosticMessage(input),{
        type:'debug',scope:'npcshop',event:'snapshot_rejected',outcome:'host_error',
        cmd:'snapshot',webCallId:'npc.diagnostic.1',
        panelInstanceId:'npcshop.test~diagnostic',generation:7,
        error:'malformed_response'
    });
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{event:'unexpected'})),null);
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{cmd:'sell'})),null);
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{callId:'bad call'})),null);
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{panelInstanceId:'bad instance'})),null);
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{generation:1.5})),null);
    assert.strictEqual(Runtime.createDiagnosticMessage(
        Object.assign({},input,{error:'secret-material-name'})).error,'other');
});

test('NPCShop snapshot diagnostics retain correlation without business payloads', () => {
    const entry = {callId:'npc.diagnostic.2',generation:9,
        session:{panelInstanceId:'npcshop.test~entry'}};
    assert.deepStrictEqual(Runtime.createSnapshotDiagnostic(
        'snapshot_rejected',{success:false,error:'malformed_response'},entry,
        'npcshop.test~fallback'),{
        domain:'npcshop',event:'snapshot_rejected',cmd:'snapshot',
        callId:'npc.diagnostic.2',generation:9,
        panelInstanceId:'npcshop.test~entry',error:'malformed_response'
    });
    assert.strictEqual(Runtime.createSnapshotDiagnostic(
        'snapshot_adopted',{success:true},{callId:'npc.diagnostic.3',generation:10},
        'npcshop.test~fallback').panelInstanceId,'npcshop.test~fallback');
});

test('NPCShop diagnostic emitter mirrors locally and sends only bounded Host records', () => {
    const local = [], sent = [];
    const emit = Runtime.createDiagnosticEmitter({
        local:record => local.push(record), send:message => sent.push(message)});
    const snapshot = {domain:'npcshop',event:'snapshot_adopted',cmd:'snapshot',
        callId:'npc.diagnostic.4',panelInstanceId:'npcshop.test~emitter',
        generation:11,error:''};
    emit(snapshot);
    emit(Object.assign({},snapshot,{event:'request_issued',cmd:'tradePreview'}));
    emit({domain:'inventory',event:'request_issued',cmd:'snapshot'});
    assert.strictEqual(local.length,3);
    assert.strictEqual(sent.length,1);
    assert.deepStrictEqual(sent[0],Runtime.createDiagnosticMessage(snapshot));
});

test('NPCShop request mux forwards correlated issued and accepted diagnostics', () => {
    const diagnostics = [];
    const mux = new Runtime.RequestMux({domain:'npcshop',panel:'npcshop',
        sessionNonce:'diagnostic',send:() => true,
        diagnostic:record => diagnostics.push(record)});
    const panelInstanceId = 'npcshop.test~mux-diagnostic';
    assert.strictEqual(mux.openSession({ownerPanel:'npcshop',panelInstanceId}),true);
    let adopted = null;
    const callId = mux.request('snapshot',{shopId:'迷之盔甲君'},
        response => { adopted = response; });
    assert.strictEqual(mux.handleResponse({
        type:'panel_resp',domain:'npcshop',panel:'npcshop',panelInstanceId,
        callId,cmd:'snapshot',success:true,shopId:'迷之盔甲君',catalog:[],
        views:{material:{slots:[]},intelligence:{slots:[]}}
    }),true);
    assert.strictEqual(adopted.success,true);
    assert.deepStrictEqual(diagnostics.map(value => value.event),
        ['request_issued','response_accepted']);
    for (const record of diagnostics) {
        assert.strictEqual(record.domain,'npcshop');
        assert.strictEqual(record.callId,callId);
        assert.strictEqual(record.panelInstanceId,panelInstanceId);
        assert.strictEqual(record.generation,1);
        assert.ok(Runtime.createDiagnosticMessage(record));
    }
});

test('NPCShop return public failure is exact, enumerated and correlated', () => {
    const expected = {callId:'material-return.test-1',panelInstanceId:'npcshop.test~material'};
    const failure = {type:'panel_resp',panel:'npcshop',cmd:'return_crafting_materials',
        callId:expected.callId,panelInstanceId:expected.panelInstanceId,
        success:false,error:'return_unavailable'};
    assert.strictEqual(Runtime.validateReturnCraftingMaterialsFailure(failure,expected),true);
    for (const mutate of [
        value => { value.extra = true; },
        value => { value.success = true; },
        value => { value.error = 'catalog_not_current'; },
        value => { value.callId = 'material-return.foreign'; },
        value => { value.panelInstanceId = 'npcshop.foreign'; },
        value => { value.panel = 'crafting'; }
    ]) {
        const malformed = clone(failure);
        mutate(malformed);
        assert.strictEqual(Runtime.validateReturnCraftingMaterialsFailure(malformed,expected),false);
    }
});

test('NPCShop Host close requests admit only the four frozen outer reasons', () => {
    const lifecycle = new Runtime.OwnerLifecycle({panel:'npcshop',muxes:[]});
    assert.strictEqual(lifecycle.open('npcshop.test~close'),true);
    for (const reason of ['button','escape','backdrop','toggle']) {
        assert.strictEqual(Runtime.isCloseReason(reason),true);
        assert.deepStrictEqual(lifecycle.closeMessage(reason),{
            type:'panel',cmd:'close',panel:'npcshop',
            panelInstanceId:'npcshop.test~close',reason
        });
    }
    for (const reason of ['', 'space', 'settlement', 'disconnected']) {
        assert.strictEqual(Runtime.isCloseReason(reason),false);
        assert.strictEqual(lifecycle.closeMessage(reason),null);
    }
    lifecycle.close();
    assert.strictEqual(lifecycle.closeMessage('button'),null);
});

console.log('NPCShop navigation runtime boundary ' + passed + '/' + passed + ' passed');
