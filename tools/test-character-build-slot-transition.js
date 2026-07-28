#!/usr/bin/env node
'use strict';

const assert = require('assert');
const SlotTransition = require(
    '../launcher/web/modules/character-build/character-build-slot-transition.js');
const TuningModule = require(
    '../launcher/web/modules/character-build/character-build-tuning.js');
const BuildModule = require(
    '../launcher/web/modules/character-build.js');

let checks = 0;
function equal(actual, expected, message) {
    assert.deepStrictEqual(actual, expected, message);
    checks += 1;
}

function equipment(overrides) {
    return Object.assign({
        itemKind:'equipment',
        majorType:'武器',
        use:'长枪',
        name:'测试长枪',
        enhancementLevel:5
    }, overrides || {});
}

function controllerWith(item, options) {
    options = options || {};
    let active = true;
    const state = {
        exits:[],
        rebinds:[],
        restores:[],
        transitionStates:[],
        portraits:0,
        detachCallback:null
    };
    const controller = {
        _mountGeneration:options.mountGeneration || 7,
        _panelInstanceId:options.panelInstanceId || 'panel.character-build.7',
        _snapshotPayload:{equipment:[{
            slotKey:options.targetSlot || '脚部装备',
            occupied:true,
            item:item
        }]},
        _selectedSlotKey:'weapon:长枪',
        _selectedTarget:{kind:'equipment', slotKey:'长枪'},
        _view:{
            restoreSlot:function(key) {
                state.restores.push(key);
                return true;
            },
            setSlotTransitionFailure:function() {
                state.transitionStates.push('failure');
                return true;
            }
        },
        _ports:{toast:function() {}},
        _renderPortrait:function() { state.portraits += 1; },
        _tuning:{
            isActive:function() { return active; },
            selectSlot:function(slotKey, selectedItem, viewKey) {
                state.rebinds.push({
                    slotKey:slotKey,
                    item:selectedItem,
                    viewKey:viewKey
                });
                return options.rebindAccepted !== false;
            },
            exit:function(callback, exitOptions) {
                state.exits.push(exitOptions);
                state.detachCallback = function(detached) {
                    if (detached) active = false;
                    callback(detached);
                };
                if (Object.prototype.hasOwnProperty.call(options, 'detachResult')) {
                    state.detachCallback(options.detachResult);
                }
                return options.exitStarted !== false;
            }
        }
    };
    return {controller:controller, state:state};
}

async function flushMicrotasks() {
    await Promise.resolve();
    await Promise.resolve();
}

async function main() {
    const tunable = controllerWith(equipment(), {targetSlot:'脚部装备'});
    const armorSelection = {
        key:'armor:脚部装备',
        kind:'armor',
        id:'脚部装备',
        requestKey:'armor:脚部装备:2'
    };
    const armorTarget = {kind:'equipment', slotKey:'脚部装备'};
    equal(SlotTransition.handle(
        tunable.controller, armorSelection, armorTarget, TuningModule), {
            deferCandidates:true
        }, 'stable tuning rebind defers the hidden candidate read until exit');
    equal({
        exits:tunable.state.exits.length,
        rebinds:tunable.state.rebinds.length,
        slotKey:tunable.controller._selectedSlotKey,
        target:tunable.controller._selectedTarget,
        portraits:tunable.state.portraits
    }, {
        exits:0,
        rebinds:1,
        slotKey:'weapon:长枪',
        target:{kind:'equipment', slotKey:'长枪'},
        portraits:0
    }, 'the leaf moves only the tuning source and leaves controller selection to its owner');

    const activeController = Object.create(
        BuildModule.CharacterBuildController.prototype);
    let candidateRequests = 0;
    activeController._mountGeneration = 7;
    activeController._panelInstanceId = 'panel.character-build.7';
    activeController._snapshotPayload = tunable.controller._snapshotPayload;
    activeController._selectedSlotKey = 'weapon:长枪';
    activeController._selectedTarget = {kind:'equipment', slotKey:'长枪'};
    activeController._tuning = tunable.controller._tuning;
    activeController._session = {
        requestCandidates:function() {
            candidateRequests += 1;
            return null;
        }
    };
    activeController._view = {};
    activeController._ports = {toast:function() {}};
    activeController._renderPortrait = function() { return true; };
    equal(activeController._selectSlot(armorSelection), {
        deferCandidates:true
    }, 'real controller accepts the tuning-only rebind transaction');
    equal({
        slotKey:activeController._selectedSlotKey,
        target:activeController._selectedTarget,
        candidateRequests:candidateRequests
    }, {
        slotKey:'armor:脚部装备',
        target:armorTarget,
        candidateRequests:0
    }, 'active tuning cannot split source identity through a second candidate transport step');
    equal(activeController._selectSlot({
        key:'unknown:slot', kind:'unknown', id:'slot', requestKey:'unknown:slot:1'
    }), false, 'an unknown slot is rejected before it can detach or mutate either face');
    equal({
        slotKey:activeController._selectedSlotKey,
        target:activeController._selectedTarget,
        candidateRequests:candidateRequests
    }, {
        slotKey:'armor:脚部装备',
        target:armorTarget,
        candidateRequests:0
    }, 'invalid selection leaves the last coherent tuning identity intact');

    const sendFailure = Object.create(
        BuildModule.CharacterBuildController.prototype);
    sendFailure._tuning = null;
    sendFailure._selectedSlotKey = 'weapon:长枪';
    sendFailure._selectedTarget = {kind:'equipment', slotKey:'长枪'};
    sendFailure._session = {
        requestCandidates:function() { return null; }
    };
    sendFailure._view = {setCandidateFailure:function() {
        throw new Error('an unissued request must roll back instead of publishing failure');
    }};
    const portraits = [];
    sendFailure._renderPortrait = function(candidate) {
        portraits.push({
            candidate:candidate,
            slotKey:this._selectedSlotKey,
            target:this._selectedTarget
        });
        return true;
    };
    equal(sendFailure._selectSlot(armorSelection), null,
        'an unissued candidate request rejects the controller transition');
    equal({
        slotKey:sendFailure._selectedSlotKey,
        target:sendFailure._selectedTarget,
        portraitSlots:portraits.map(function(entry) { return entry.slotKey; })
    }, {
        slotKey:'weapon:长枪',
        target:{kind:'equipment', slotKey:'长枪'},
        portraitSlots:['armor:脚部装备','weapon:长枪']
    }, 'controller selection and portrait roll back with the View transaction');

    const grenade = {
        itemKind:'stack',
        majorType:'消耗品',
        use:'手雷',
        name:'战术核弹手雷',
        quantity:168,
        enhancementLevel:0
    };
    const grenadeSelection = {
        key:'weapon:手雷',
        kind:'weapon',
        id:'手雷',
        requestKey:'weapon:手雷:3'
    };
    const grenadeTarget = {kind:'equipment', slotKey:'手雷'};
    const detached = controllerWith(grenade, {
        targetSlot:'手雷',
        detachResult:true
    });
    equal(SlotTransition.handle(
        detached.controller, grenadeSelection, grenadeTarget, TuningModule), {
            deferSelection:true
        },
    'untunable target keeps the initiating View transaction rolled back');
    equal({
        exitOptions:detached.state.exits,
        rebinds:detached.state.rebinds.length,
        restores:detached.state.restores,
        selected:detached.controller._selectedSlotKey
    }, {
        exitOptions:[{restore:false}],
        rebinds:0,
        restores:[],
        selected:'weapon:长枪'
    }, 'successful synchronous detach still defers ordinary selection to a microtask');
    await flushMicrotasks();
    equal(detached.state.restores, ['weapon:手雷'],
        'detach success resumes ordinary selection exactly once');

    const pendingFailure = controllerWith(grenade, {targetSlot:'手雷'});
    equal(SlotTransition.handle(
        pendingFailure.controller, grenadeSelection, grenadeTarget, TuningModule), {
            deferSelection:true
        }, 'an admitted async detach reports a neutral deferred View transaction');
    equal(pendingFailure.state.transitionStates, [],
        'an in-flight detach does not announce failure before authority responds');
    pendingFailure.state.detachCallback(false);
    equal(pendingFailure.state.transitionStates, ['failure'],
        'an asynchronous detach rejection replaces pending with an exact failure');

    const failed = controllerWith(grenade, {
        targetSlot:'手雷',
        detachResult:false
    });
    equal(SlotTransition.handle(
        failed.controller, grenadeSelection, grenadeTarget, TuningModule), false,
    'detach failure rejects the untunable transition');
    await flushMicrotasks();
    equal({
        restores:failed.state.restores,
        selected:failed.controller._selectedSlotKey,
        target:failed.controller._selectedTarget,
        active:failed.controller._tuning.isActive()
    }, {
        restores:[],
        selected:'weapon:长枪',
        target:{kind:'equipment', slotKey:'长枪'},
        active:true
    }, 'detach failure preserves the old left and right tuning identity');

    const staleGeneration = controllerWith(grenade, {targetSlot:'手雷'});
    SlotTransition.handle(
        staleGeneration.controller, grenadeSelection, grenadeTarget, TuningModule);
    staleGeneration.controller._mountGeneration += 1;
    staleGeneration.state.detachCallback(true);
    await flushMicrotasks();
    equal(staleGeneration.state.restores, [],
        'mount-generation change suppresses a late detach callback');

    const stalePanel = controllerWith(grenade, {targetSlot:'手雷'});
    SlotTransition.handle(
        stalePanel.controller, grenadeSelection, grenadeTarget, TuningModule);
    stalePanel.controller._panelInstanceId = 'panel.character-build.8';
    stalePanel.state.detachCallback(true);
    await flushMicrotasks();
    equal(stalePanel.state.restores, [],
        'panel-instance change suppresses a late detach callback');

    console.log('Character Build slot transition ' + checks + '/' + checks + ' passed');
}

main().catch(function(error) {
    console.error(error && error.stack || error);
    process.exitCode = 1;
});
