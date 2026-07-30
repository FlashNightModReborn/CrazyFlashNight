#!/usr/bin/env node
'use strict';

const assert = require('assert');
const ActionModule = require(
    '../launcher/web/modules/character-build/character-build-action-view.js');
const TuningModule = require(
    '../launcher/web/modules/character-build/character-build-tuning.js');

let checks = 0;
function equal(actual, expected, message) {
    assert.deepStrictEqual(actual, expected, message);
    checks += 1;
}

function item(overrides) {
    return Object.assign({
        itemKind:'equipment',
        majorType:'武器',
        use:'长枪',
        enhancementLevel:1
    }, overrides || {});
}

equal(ActionModule.tuningCapability(item()).available, true,
    'level-one weapon is presentationally tunable');
equal(ActionModule.tuningCapability(item({
    majorType:'防具', use:'头部装备', enhancementLevel:13
})).available, true, 'armor is presentationally tunable');
equal(ActionModule.tuningCapability({
    itemKind:'stack',
    majorType:'消耗品',
    use:'手雷',
    quantity:168,
    enhancementLevel:0
}), {
    available:false,
    code:'not_equipment',
    reason:'数量型手雷不能调制'
}, 'production-shaped stack grenade is unavailable with a readable reason');
equal(ActionModule.tuningCapability(item({majorType:'消耗品'})).code,
    'unsupported_type', 'only weapon and armor major types pass the capability');
equal(ActionModule.tuningCapability(item({enhancementLevel:0})).code,
    'invalid_level', 'zero-level equipment fails closed');
equal(ActionModule.tuningCapability(item({enhancementLevel:1.5})).code,
    'invalid_level', 'fractional equipment level fails closed');

const payload = {equipment:[
    {slotKey:'长枪', occupied:true, item:item({name:'测试长枪'})},
    {slotKey:'手雷', occupied:true, item:{
        itemKind:'stack', majorType:'消耗品', use:'手雷',
        name:'战术核弹手雷', quantity:168, enhancementLevel:0
    }}
]};
equal(TuningModule.findEquipment(payload, '长枪').name, '测试长枪',
    'tunable lookup accepts a valid equipped weapon');
equal(TuningModule.findEquipment(payload, '手雷'), null,
    'tunable lookup rejects the equipped stack grenade');
equal(TuningModule.findLoadoutItem(payload, '手雷').quantity, 168,
    'raw loadout lookup preserves the untunable destination item');

const reboundSources = [];
const rebindAdapter = new TuningModule.CharacterBuildTuning({
    session:{
        debugState:function() { return {sessionGeneration:7, loadoutRevision:11}; },
        getState:function() { return 'idle'; }
    },
    view:{
        root:{querySelectorAll:function() { return []; }},
        refreshSlotNavigation:function() {}
    }
});
rebindAdapter._active = true;
rebindAdapter._slotKey = '长枪';
rebindAdapter._entrySource = {
    sourceKind:'loadout',
    sessionGeneration:7,
    slotKey:'长枪',
    expectedLoadoutRevision:11
};
rebindAdapter._returnState = {slotKey:'weapon:长枪', scrollTop:0};
rebindAdapter._tuningView = {
    canClose:function() { return true; },
    handleLoadoutSelection:function(source) {
        reboundSources.push(source);
        return true;
    },
    debugState:function() { return {}; }
};
equal(rebindAdapter.selectSlot('脚部装备', item({
    majorType:'防具', use:'脚部装备', name:'测试装甲鞋'
}), 'armor:脚部装备'), true, 'stable tuning rebind still accepts a valid second equipment slot');
equal({
    slotKey:rebindAdapter.debugState().slotKey,
    sourceSlot:reboundSources[0].slotKey,
    returnKey:rebindAdapter._returnState.slotKey
}, {
    slotKey:'脚部装备',
    sourceSlot:'脚部装备',
    returnKey:'armor:脚部装备'
}, 'accepted rebind advances source and ordinary return identity together');
equal(rebindAdapter.selectSlot('手雷', payload.equipment[1].item, 'weapon:手雷'), false,
    'stack grenade cannot enter the in-place tuning rebind path');
equal(rebindAdapter.debugState().slotKey, '脚部装备',
    'rejected untunable rebind preserves the prior tuning source');

function fakeElement(attributes) {
    const attrs = Object.assign({}, attributes || {});
    return {
        disabled:false,
        hidden:false,
        textContent:'',
        getAttribute:function(name) {
            return Object.prototype.hasOwnProperty.call(attrs, name) ? attrs[name] : null;
        },
        closest:function(selector) {
            return selector === '[data-build-action]'
                && attrs['data-build-action'] ? this : null;
        },
        setAttribute:function(name, value) { attrs[name] = String(value); },
        removeAttribute:function(name) { delete attrs[name]; }
    };
}

let selectedCandidate = null;
let selectedSlotKey = 'weapon:手雷';
let selectedSlot = fakeElement({
    'data-empty':'false',
    'data-slot-kind':'weapon',
    'data-tunable':'false',
    'data-tuning-reason':'数量型手雷不能调制'
});
const commitButton = fakeElement({'data-build-action':'commit'});
const tuneButton = fakeElement({'data-build-action':'tune'});
const unequipButton = fakeElement({'data-build-action':'unequip'});
const root = {
    querySelector:function(selector) {
        if (selector === '[data-build-action="commit"]') return commitButton;
        if (selector === '[data-build-action="tune"]') return tuneButton;
        if (selector === '[data-build-action="unequip"]') return unequipButton;
        if (selector.indexOf('[data-roving-key=') === 0) return selectedSlot;
        return null;
    },
    querySelectorAll:function() { return []; },
    addEventListener:function() {},
    removeEventListener:function() {},
    setAttribute:function() {},
    contains:function() { return true; }
};
let tuneIntents = 0;
const actionView = new ActionModule.ActionView({
    root:root,
    candidateList:{},
    getCandidate:function() { return selectedCandidate; },
    getCandidateKey:function() { return ''; },
    getSlotKey:function() { return selectedSlotKey; },
    selectCandidate:function() {},
    onCommit:function() {},
    onTune:function() { tuneIntents += 1; },
    onUnequip:function() {},
    onReconcile:function() {}
});
actionView.setState('idle');
equal({
    hidden:tuneButton.hidden,
    disabled:tuneButton.disabled,
    label:tuneButton.textContent,
    ariaDisabled:tuneButton.getAttribute('aria-disabled'),
    title:tuneButton.getAttribute('title')
}, {
    hidden:false,
    disabled:true,
    label:'不可调制',
    ariaDisabled:'true',
    title:'数量型手雷不能调制'
}, 'occupied untunable equipment keeps a disabled, readable action');

selectedSlotKey = 'drug:drug1';
selectedSlot = fakeElement({
    'data-empty':'false',
    'data-slot-kind':'drug',
    'data-tunable':'false'
});
actionView.sync();
equal(tuneButton.hidden, true, 'drug slots hide the unrelated tuning action');

selectedSlotKey = 'weapon:手枪';
selectedSlot = fakeElement({
    'data-empty':'true',
    'data-slot-kind':'weapon',
    'data-tunable':'false'
});
actionView.sync();
equal(tuneButton.hidden, true, 'empty equipment slots hide the tuning action');

selectedSlotKey = 'weapon:长枪';
selectedSlot = fakeElement({
    'data-empty':'false',
    'data-slot-kind':'weapon',
    'data-tunable':'true'
});
actionView.sync();
equal({
    hidden:tuneButton.hidden,
    disabled:tuneButton.disabled,
    label:tuneButton.textContent,
    ariaLabel:tuneButton.getAttribute('aria-label'),
    title:tuneButton.getAttribute('title')
}, {
    hidden:false,
    disabled:false,
    label:'调制',
    ariaLabel:'调制当前装备',
    title:null
}, 'valid equipment exposes the ordinary tuning action');

selectedCandidate = {
    name:'候选长枪',
    tunable:true,
    tuningReason:'',
    blocked:false
};
selectedSlot = fakeElement({
    'data-empty':'false',
    'data-slot-kind':'weapon',
    'data-tunable':'false',
    'data-tuning-reason':'当前装备不能调制'
});
actionView.sync();
equal({
    disabled:tuneButton.disabled,
    label:tuneButton.textContent,
    ariaLabel:tuneButton.getAttribute('aria-label')
}, {
    disabled:false,
    label:'调制候选',
    ariaLabel:'调制所选候选：候选长枪'
}, 'selected tunable candidate takes action-target precedence over the equipped loadout');
actionView._handleClick({target:tuneButton});
equal(tuneIntents, 1, 'candidate tuning activation emits one explicit intent');

selectedCandidate = {
    name:'无效候选',
    tunable:false,
    tuningReason:'候选位置凭据已失效，请重新选择当前槽位',
    blocked:false
};
actionView.sync();
actionView._handleClick({target:tuneButton});
equal({
    disabled:tuneButton.disabled,
    label:tuneButton.textContent,
    title:tuneButton.getAttribute('title'),
    tuneIntents:tuneIntents
}, {
    disabled:true,
    label:'不可调制',
    title:'候选位置凭据已失效，请重新选择当前槽位',
    tuneIntents:1
}, 'untunable candidate stays readable and emits zero tuning intent');
actionView.destroy();

function exitAdapter(mode) {
    const state = {detachCalls:0, restores:[], destroyed:0, pending:null};
    let pending = false;
    const buildView = {
        root:{
            querySelector:function() { return null; },
            removeAttribute:function() {}
        },
        debugState:function() { return {candidateCount:1}; },
        restoreSlot:function(key) { state.restores.push(key); },
        setInteractionState:function() {}
    };
    const adapter = new TuningModule.CharacterBuildTuning({
        session:{getState:function() { return 'idle'; }},
        view:buildView
    });
    adapter._active = true;
    adapter._returnState = {slotKey:'weapon:长枪', scrollTop:37};
    adapter._tuningView = {
        canClose:function() { return !pending && mode !== 'busy'; },
        detachSession:function(callback) {
            state.detachCalls += 1;
            if (mode === 'pending') {
                pending = true;
                state.pending = function(result) {
                    pending = false;
                    callback(result);
                };
            } else {
                callback(mode !== 'failure');
            }
            return true;
        },
        destroy:function() { state.destroyed += 1; }
    };
    return {adapter:adapter, state:state};
}

let fixture = exitAdapter('success');
let exitResult = null;
equal(fixture.adapter.exit(function(result) { exitResult = result; }, {restore:false}), true,
    'destination exit starts one exact detach');
equal({
    callback:exitResult,
    active:fixture.adapter.isActive(),
    detachCalls:fixture.state.detachCalls,
    restores:fixture.state.restores
}, {
    callback:true,
    active:false,
    detachCalls:1,
    restores:[]
}, 'successful destination detach closes tuning without restoring the old slot');

fixture = exitAdapter('success');
fixture.adapter.exit(function() {});
equal(fixture.state.restores, ['weapon:长枪'],
    'ordinary return still restores the captured slot exactly once');

fixture = exitAdapter('failure');
exitResult = null;
fixture.adapter.exit(function(result) { exitResult = result; }, {restore:false});
equal({
    callback:exitResult,
    active:fixture.adapter.isActive(),
    detachCalls:fixture.state.detachCalls,
    restores:fixture.state.restores,
    destroyed:fixture.state.destroyed
}, {
    callback:false,
    active:true,
    detachCalls:1,
    restores:[],
    destroyed:0
}, 'detach failure preserves the old tuning source and UI');

fixture = exitAdapter('pending');
let secondCallback = null;
fixture.adapter.exit(function(result) { exitResult = result; }, {restore:false});
equal(fixture.adapter.exit(function(result) { secondCallback = result; }, {restore:false}), false,
    'a detach already in flight rejects a second transition');
equal({
    active:fixture.adapter.isActive(),
    detachCalls:fixture.state.detachCalls,
    secondCallback:secondCallback
}, {
    active:true,
    detachCalls:1,
    secondCallback:false
}, 'in-flight detach leaves the old state mounted');
fixture.state.pending(true);
equal({
    callback:exitResult,
    active:fixture.adapter.isActive(),
    restores:fixture.state.restores
}, {
    callback:true,
    active:false,
    restores:[]
}, 'the first exact detach alone completes the deferred transition');

fixture = exitAdapter('pending');
let lateCallback = null;
fixture.adapter.exit(function(result) { lateCallback = result; }, {restore:false});
fixture.adapter.destroy();
fixture.state.pending(true);
equal({
    callback:lateCallback,
    active:fixture.adapter.isActive(),
    destroyed:fixture.state.destroyed,
    restores:fixture.state.restores
}, {
    callback:null,
    active:false,
    destroyed:1,
    restores:[]
}, 'destroy fences a late detach callback from touching the retired build view');

console.log('Character Build tuning capability ' + checks + '/' + checks + ' passed');
