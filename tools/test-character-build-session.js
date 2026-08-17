'use strict';

const assert = require('assert');
const Build = require('../launcher/web/modules/character-build.js');
const Pose = require('../launcher/web/modules/character-build/character-build-pose.js');
const SessionModule = require('../launcher/web/modules/character-build-session.js');

let passed = 0;
function test(name, run) {
    run();
    passed += 1;
    process.stdout.write('ok - ' + name + '\n');
}

function createTimers() {
    const timers = [];
    return {
        timers,
        setTimer(callback) {
            const timer = {callback, cleared:false};
            timers.push(timer);
            return timer;
        },
        clearTimer(timer) { timer.cleared = true; },
        expireLatest() {
            const timer = timers.slice().reverse().find(row => !row.cleared);
            assert(timer, 'expected a live request timer');
            timer.callback();
        }
    };
}

function projection() {
    return {
        equipment:Array.from({length:11}, (_, index) => ({
            slotKey:'slot-' + index,
            occupied:false,
            item:null
        })),
        drugs:Array.from({length:4}, (_, index) => ({
            slot:index,
            occupied:false,
            item:null
        })),
        portrait:{gender:'男', appearance:{}, equipment:{}},
        stateHealth:'ok',
        diagnostics:[]
    };
}

function itemProjection(overrides) {
    return Object.assign({
        name:'内部测试物品',
        displayName:'测试展示物品',
        icon:'测试物品图标',
        itemKind:'equipment',
        quantity:1,
        enhancementLevel:0,
        rarity:'普通',
        modSlots:[],
        modMeta:null
    }, overrides || {});
}

function modProjection(overrides) {
    return Object.assign({
        name:'插件内部名',displayName:'插件展示名',icon:'插件图标'
    },overrides || {});
}

function statsProjection() {
    return {
        v:1,
        groups:[{id:'core', title:'核心', rows:[{id:'hp', label:'生命', value:'100'}]}],
        stateHealth:'ok',
        diagnostics:[]
    };
}

function tooltipProjection(target, overrides) {
    return Object.assign({
        v:1,
        target,
        itemName:'内部测试物品',
        displayName:'测试展示物品',
        iconName:'测试物品图标',
        itemType:'武器',
        descHTML:'<TEXTFORMAT>完整说明</TEXTFORMAT>',
        introHTML:'<TEXTFORMAT>完整属性</TEXTFORMAT>'
    }, overrides || {});
}

function fullBackpack(sequence) {
    return {
        containerId:'背包',
        capacity:50,
        accessibleCapacity:50,
        viewCapacity:50,
        filterKey:'all',
        pageSizeHint:50,
        locked:false,
        snapshotSeq:sequence == null ? 9 : sequence,
        containerEpoch:2,
        containerVersion:4,
        offset:0,
        limit:50,
        slots:Array.from({length:50}, (_, physicalSlot) => ({
            physicalSlot,
            slotLease:'lease.' + physicalSlot + '.' + (sequence || 9),
            occupied:false,
            item:null
        }))
    };
}

function responseFor(message, overrides) {
    const result = {
        type:'panel_resp',
        panel:'workbench',
        domain:'loadout',
        cmd:message.cmd,
        callId:message.callId,
        panelInstanceId:message.panelInstanceId,
        v:1,
        success:true,
        writeEpoch:0,
        sessionGeneration:7,
        loadoutRevision:3,
        liveRevision:3,
        drugRevision:2,
        liveRefreshDirty:false,
        active:true
    };
    return Object.assign(result, overrides || {});
}

function createFixture(send, options) {
    options = options || {};
    const messages = [];
    const errors = [];
    const states = [];
    const timers = createTimers();
    const mux = Build.createRequestMux({
        send(message) {
            messages.push(message);
            return send ? send(message) : true;
        },
        setTimer:timers.setTimer,
        clearTimer:timers.clearTimer,
        timeoutMs:100
    });
    const session = new SessionModule.CharacterBuildSession({
        mux,
        onError(response, command) { errors.push({response, command}); },
        onState(state, reason) { states.push({state, reason}); },
        onCandidateAuthorityReset:options.onCandidateAuthorityReset
    });
    return {messages, errors, states, timers, mux, session};
}

function openClean(fixture, revisions) {
    revisions = revisions || {};
    let result = null;
    assert(fixture.session.open('panel.workbench.fixture', (response, accepted) => {
        result = {response, accepted};
    }));
    assert.strictEqual(fixture.messages.length, 1);
    assert.deepStrictEqual(fixture.messages[0].payload, {v:1});
    fixture.mux.handleResponse(responseFor(fixture.messages[0], {
        payload:projection(),
        loadoutRevision:revisions.loadout == null ? 3 : revisions.loadout,
        liveRevision:revisions.live == null ? 3 : revisions.live,
        drugRevision:revisions.drug == null ? 2 : revisions.drug,
        liveRefreshDirty:revisions.dirty === true
    }));
    assert(result && result.accepted);
    assert.strictEqual(fixture.session.getState(), 'idle');
}

test('B2B command whitelist contains six bounded reads and four frozen mutations', () => {
    assert.deepStrictEqual(
        Array.from(SessionModule.commands),
        [
            'snapshot', 'candidates', 'tooltip', 'flushLive', 'statsSnapshot', 'finalize',
            'equipEquipment', 'unequipEquipment', 'equipDrug', 'unequipDrug'
        ]
    );
    assert.strictEqual(SessionModule.commands.includes('open'), false);
    assert.strictEqual(SessionModule.commands.some(command =>
        /replace|mutation/i.test(command)), false);
});

test('pose selector gives a selected weapon slot preview precedence', () => {
    const equipment = {
        '长枪':'long-gun',
        '手枪':'pistol',
        '手枪2':'second-pistol',
        '刀':'blade',
        '手雷':'grenade'
    };
    const expected = {
        '长枪':{stateLabel:'长枪站立', attackMode:'长枪'},
        '手枪':{stateLabel:'双枪站立', attackMode:'双枪'},
        '手枪2':{stateLabel:'双枪站立', attackMode:'双枪'},
        '刀':{stateLabel:'兵器站立', attackMode:'兵器'},
        '手雷':{stateLabel:'手雷站立', attackMode:'手雷'}
    };
    Object.keys(expected).forEach(slotKey => {
        assert.deepStrictEqual(Pose.select(equipment, {kind:'equipment', slotKey}),
            expected[slotKey]);
    });
    assert.deepStrictEqual(Pose.select(equipment, {
        kind:'equipment', slotKey:'头部装备'
    }), {stateLabel:'长枪站立', attackMode:'长枪'});
});

test('pose selector distinguishes single and dual pistols after candidate overlay', () => {
    assert.deepStrictEqual(Pose.select({'手枪':'pistol'}, {
        kind:'equipment', slotKey:'手枪'
    }), {stateLabel:'手枪站立', attackMode:'手枪'});
    assert.deepStrictEqual(Pose.select({'手枪2':'second-pistol'}, {
        kind:'equipment', slotKey:'手枪2'
    }), {stateLabel:'手枪2站立', attackMode:'手枪2'});
    assert.deepStrictEqual(Pose.select({
        '手枪':'pistol',
        '手枪2':'candidate-second-pistol'
    }, {kind:'equipment', slotKey:'手枪2'}), {
        stateLabel:'双枪站立', attackMode:'双枪'
    });
});

test('unselected pose priority is stable and ignores grenade combat state', () => {
    const cases = [
        [{'长枪':'long-gun','手枪':'pistol','手枪2':'second','刀':'blade'},
            {stateLabel:'长枪站立', attackMode:'长枪'}],
        [{'手枪':'pistol','手枪2':'second','刀':'blade'},
            {stateLabel:'双枪站立', attackMode:'双枪'}],
        [{'手枪2':'second','刀':'blade'},
            {stateLabel:'手枪2站立', attackMode:'手枪2'}],
        [{'手枪':'pistol','刀':'blade'},
            {stateLabel:'手枪站立', attackMode:'手枪'}],
        [{'刀':'blade'}, {stateLabel:'兵器站立', attackMode:'兵器'}],
        [{'手雷':'grenade'}, {stateLabel:'空手站立', attackMode:'空手'}],
        [{}, {stateLabel:'空手站立', attackMode:'空手'}]
    ];
    cases.forEach(row => assert.deepStrictEqual(Pose.select(row[0], null), row[1]));
    assert.deepStrictEqual(Pose.select({'长枪':'long-gun'}, {
        kind:'drug', drugSlot:2
    }), {stateLabel:'长枪站立', attackMode:'长枪'});
});

test('production request route uses the exact seven-key top-level envelope', () => {
    const fixture = createFixture();
    fixture.session.open('panel.workbench.exact');
    const message = fixture.messages[0];
    assert.deepStrictEqual(Object.keys(message).sort(), [
        'callId', 'cmd', 'domain', 'panel', 'panelInstanceId', 'payload', 'type'
    ]);
    assert.deepStrictEqual(message.payload, {v:1});
    assert.strictEqual(message.panelInstanceId, 'panel.workbench.exact');
});

test('lost initial response retries with a new callId and no guessed generation', () => {
    const fixture = createFixture();
    let opened = false;
    fixture.session.open('panel.workbench.lost', (_, accepted) => { opened = accepted; });
    const first = fixture.messages[0];
    fixture.timers.expireLatest();
    assert.strictEqual(fixture.session.getState(), 'opening_reconcile');
    assert.strictEqual(fixture.messages.length, 2);
    const retry = fixture.messages[1];
    assert.notStrictEqual(retry.callId, first.callId);
    assert.deepStrictEqual(retry.payload, {v:1});
    fixture.mux.handleResponse(responseFor(retry, {
        sessionGeneration:41,
        payload:projection()
    }));
    assert.strictEqual(opened, true);
    assert.strictEqual(fixture.session.getState(), 'idle');
    assert.strictEqual(fixture.session.debugState().sessionGeneration, 41);
});

test('local send=false is definitive pre-open failure and releases the mux session', () => {
    const fixture = createFixture(() => false);
    fixture.session.open('panel.workbench.not-sent');
    assert.strictEqual(fixture.messages.length, 1);
    assert.strictEqual(fixture.session.getState(), 'closed');
    assert.strictEqual(fixture.session.debugState().panelInstanceId, '');
    assert.strictEqual(fixture.session.debugState().mux.active, false);
});

test('definitive backend open rejection closes the logical session', () => {
    const fixture = createFixture();
    let result = null;
    fixture.session.open('panel.workbench.rejected', (response, accepted) => {
        result = {response, accepted};
    });
    fixture.mux.handleResponse(responseFor(fixture.messages[0], {
        success:false,
        error:'service_not_ready',
        active:false,
        sessionGeneration:0,
        loadoutRevision:0,
        liveRevision:0,
        drugRevision:0
    }));
    assert(result && result.accepted === false);
    assert.strictEqual(result.response.error, 'service_not_ready');
    assert.strictEqual(fixture.session.getState(), 'closed');
    assert.strictEqual(fixture.session.debugState().panelInstanceId, '');
    assert.strictEqual(fixture.session.debugState().mux.active, false);
});

test('subsequent snapshot and candidates carry exact generation and revisions in payload', () => {
    const fixture = createFixture();
    openClean(fixture);
    fixture.session.refreshSnapshot();
    assert.deepStrictEqual(fixture.messages[1].payload, {v:1, sessionGeneration:7});
    fixture.mux.handleResponse(responseFor(fixture.messages[1], {payload:projection()}));
    const target = {kind:'equipment', slotKey:'头部装备'};
    fixture.session.requestCandidates(target);
    assert.deepStrictEqual(fixture.messages[2].payload, {
        v:1,
        sessionGeneration:7,
        expectedLoadoutRevision:3,
        expectedDrugRevision:2,
        slotKey:'头部装备',
        candidateScope:'compatible'
    });
    fixture.mux.handleResponse(responseFor(fixture.messages[2], {
        payload:{
            target,
            candidateScope:'compatible',
            candidates:[],
            backpackVersion:8,
            stateHealth:'ok',
            diagnostics:[]
        }
    }));
    assert.strictEqual(fixture.session.getState(), 'idle');
});

test('neutral backpack overview carries no slot selector and requires exact backpack target echo', () => {
    const fixture = createFixture();
    openClean(fixture);
    const target = {kind:'backpack'};
    let accepted = null;
    fixture.session.requestCandidates(target, 'backpack', (_, ok, key, scope) => {
        accepted = {ok, key, scope};
    });
    const request = fixture.messages[1];
    assert.deepStrictEqual(request.payload, {
        v:1,
        sessionGeneration:7,
        candidateScope:'backpack',
        expectedLoadoutRevision:3,
        expectedDrugRevision:2
    });
    fixture.mux.handleResponse(responseFor(request, {payload:{
        target,
        candidateScope:'backpack',
        candidates:[{
            physicalSlot:4, disabled:false, blockedReason:'',
            source:{containerId:'背包', slot:4, expectedLease:'lease.4'},
            item:itemProjection({majorType:'武器', use:'刀'}),
            equipmentEligibility:{slots:['刀'], blockedReason:''}
        }],
        backpackVersion:8,
        stateHealth:'ok',
        diagnostics:[]
    }}));
    assert.deepStrictEqual(accepted, {ok:true, key:'backpack', scope:'backpack'});
});

test('candidate cache is revision fenced and reprojects one authoritative equipment backpack', () => {
    const controller = Object.create(Build.CharacterBuildController.prototype);
    let state = {
        sessionGeneration:7,
        loadoutRevision:3,
        drugRevision:2
    };
    controller._session = {debugState:() => Object.assign({}, state)};
    controller._panelInstanceId = 'panel.cache.1';
    controller._candidateCache = null;
    const candidates = [{key:'backpack:4:lease.4'}];
    const payload = {stateHealth:'ok', backpackVersion:12};
    assert.strictEqual(controller._storeCandidateCache(
        {kind:'equipment', slotKey:'手枪'}, 'compatible', payload, candidates), true);
    assert.deepStrictEqual(controller._readCandidateCache(
        {kind:'equipment', slotKey:'手枪2'}, 'compatible'), candidates);
    assert.strictEqual(controller._readCandidateCache(
        {kind:'equipment', slotKey:'长枪'}, 'compatible'), null);
    const universalPayload = {
        target:{kind:'equipment', slotKey:'长枪'},
        candidateScope:'backpack',
        candidates:[{
            physicalSlot:4, disabled:false, blockedReason:'',
            source:{containerId:'背包', slot:4, expectedLease:'lease.4'},
            item:{name:'候选刀', displayName:'候选刀', icon:'候选刀',
                itemKind:'equipment', majorType:'武器', use:'刀', quantity:1},
            equipmentEligibility:{slots:['刀'], blockedReason:''}
        },{
            physicalSlot:5, disabled:true, blockedReason:'incompatible_item',
            source:{containerId:'背包', slot:5, expectedLease:'lease.5'},
            item:{name:'高阶手枪', displayName:'高阶手枪', icon:'高阶手枪',
                itemKind:'equipment', majorType:'武器', use:'手枪', quantity:1},
            equipmentEligibility:{slots:['手枪','手枪2'], blockedReason:'level_locked'}
        }],
        backpackVersion:12,stateHealth:'ok',diagnostics:[]
    };
    assert.strictEqual(controller._storeCandidateCache(
        {kind:'equipment', slotKey:'长枪'}, 'backpack',
        universalPayload, []), true);
    const bladeRows = controller._readCandidateCache(
        {kind:'equipment', slotKey:'刀'}, 'backpack');
    assert.strictEqual(bladeRows[0].blocked, false);
    assert.strictEqual(bladeRows[1].blocked, true);
    const pistolRows = controller._readCandidateCache(
        {kind:'equipment', slotKey:'手枪2'}, 'backpack');
    assert.strictEqual(pistolRows[0].raw.blockedReason, 'incompatible_item');
    assert.strictEqual(pistolRows[1].raw.blockedReason, 'level_locked');
    state = Object.assign({}, state, {loadoutRevision:4});
    assert.strictEqual(controller._readCandidateCache(
        {kind:'equipment', slotKey:'手枪2'}, 'backpack'), null);
    state = Object.assign({}, state, {loadoutRevision:3});
    assert.strictEqual(controller._storeCandidateCache(
        {kind:'equipment', slotKey:'刀'}, 'backpack',
        {stateHealth:'degraded', backpackVersion:13}, candidates), false);
    assert.strictEqual(controller._candidateCache, null);
    assert.strictEqual(Build.candidateCacheTarget(
        {kind:'equipment', slotKey:'长枪'}), '');
    assert.strictEqual(Build.candidateCacheTarget(
        {kind:'equipment', slotKey:'长枪'}, 'backpack'), 'equipment:backpack');
    assert.strictEqual(Build.candidateCacheTarget(
        {kind:'backpack'}, 'backpack'), 'backpack');
    assert.strictEqual(Build.candidateCacheTarget(
        {kind:'drug', drugSlot:0}), '');
});

test('equipped and drug tooltip reads carry exact target and revision fences', () => {
    const fixture = createFixture();
    openClean(fixture);
    const equipment = {kind:'equipment', slotKey:'长枪'};
    let accepted = null;
    fixture.session.requestLoadoutTooltip(equipment, (response, ok, key) => {
        accepted = {response, ok, key};
    });
    const equipmentRequest = fixture.messages[1];
    assert.deepStrictEqual(equipmentRequest.payload, {
        v:1,
        sessionGeneration:7,
        slotKey:'长枪',
        expectedLoadoutRevision:3,
        expectedDrugRevision:2
    });
    fixture.mux.handleResponse(responseFor(equipmentRequest, {
        payload:tooltipProjection(equipment)
    }));
    assert(accepted && accepted.ok);
    assert.strictEqual(accepted.key, 'equipment:长枪');

    const drug = {kind:'drug', drugSlot:2};
    accepted = null;
    fixture.session.requestLoadoutTooltip(drug, (response, ok, key) => {
        accepted = {response, ok, key};
    });
    const drugRequest = fixture.messages[2];
    assert.deepStrictEqual(drugRequest.payload, {
        v:1,
        sessionGeneration:7,
        drugSlot:2,
        expectedLoadoutRevision:3,
        expectedDrugRevision:2
    });
    fixture.mux.handleResponse(responseFor(drugRequest, {
        payload:tooltipProjection(drug)
    }));
    assert(accepted && accepted.ok);
    assert.strictEqual(accepted.key, 'drug:2');
});

test('tooltip response exact shape and revision echo fail closed without advancing watermarks', () => {
    const fixture = createFixture();
    openClean(fixture);
    const target = {kind:'equipment', slotKey:'长枪'};
    let accepted = true;
    fixture.session.requestLoadoutTooltip(target, (_, ok) => { accepted = ok; });
    const malformed = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(malformed, {
        payload:Object.assign(tooltipProjection(target), {extra:'forbidden'})
    }));
    assert.strictEqual(accepted, false);
    assert.strictEqual(fixture.session.debugState().loadoutRevision, 3);
    assert.strictEqual(fixture.errors.at(-1).response.error, 'malformed_response');

    accepted = true;
    fixture.session.requestLoadoutTooltip(target, (_, ok) => { accepted = ok; });
    const drifted = fixture.messages[2];
    fixture.mux.handleResponse(responseFor(drifted, {
        loadoutRevision:4,
        payload:tooltipProjection(target)
    }));
    assert.strictEqual(accepted, false);
    assert.strictEqual(fixture.session.debugState().loadoutRevision, 3);
});

test('starting a write cancels an in-flight equipped tooltip read', () => {
    const fixture = createFixture();
    openClean(fixture);
    const target = {kind:'equipment', slotKey:'长枪'};
    const callbacks = [];
    fixture.session.requestLoadoutTooltip(target, (response, accepted) => {
        callbacks.push({response, accepted});
    });
    const tooltipRequest = fixture.messages[1];
    assert(fixture.session.unequipEquipment('长枪'));
    assert.strictEqual(fixture.mux.handleResponse(responseFor(tooltipRequest, {
        payload:tooltipProjection(target)
    })), false);
    assert.strictEqual(callbacks.length, 1);
    assert.strictEqual(callbacks[0].accepted, false);
    assert.strictEqual(callbacks[0].response.error, 'mutation_start');
    assert.strictEqual(fixture.session.getState(), 'write_pending');
});

test('A to B to A tooltip supersession releases each canceled binding for retry', () => {
    const fixture = createFixture();
    openClean(fixture);
    const longGun = {kind:'equipment', slotKey:'长枪'};
    const blade = {kind:'equipment', slotKey:'刀'};
    const callbacks = [];
    fixture.session.requestLoadoutTooltip(longGun, (response, accepted) => {
        callbacks.push({owner:'longGun:first', error:response && response.error, accepted});
    });
    const first = fixture.messages[1];
    fixture.session.requestLoadoutTooltip(blade, (response, accepted) => {
        callbacks.push({owner:'blade', error:response && response.error, accepted});
    });
    const second = fixture.messages[2];
    fixture.session.requestLoadoutTooltip(longGun, (response, accepted) => {
        callbacks.push({owner:'longGun:retry', error:response && response.error, accepted});
    });
    const retry = fixture.messages[3];
    assert.strictEqual(fixture.mux.handleResponse(responseFor(first, {
        payload:tooltipProjection(longGun)
    })), false);
    assert.strictEqual(fixture.mux.handleResponse(responseFor(second, {
        payload:tooltipProjection(blade)
    })), false);
    fixture.mux.handleResponse(responseFor(retry, {
        payload:tooltipProjection(longGun)
    }));
    assert.deepStrictEqual(callbacks.map(row => [row.owner, row.error || '', row.accepted]), [
        ['longGun:first', 'superseded', false],
        ['blade', 'superseded', false],
        ['longGun:retry', '', true]
    ]);
});

test('candidate scope is closed, inherited by refresh callers, and response echo is exact', () => {
    const fixture = createFixture();
    openClean(fixture);
    const target = {kind:'equipment', slotKey:'长枪'};
    assert.strictEqual(fixture.session.getCandidateScope(), 'compatible');
    assert.strictEqual(fixture.session.setCandidateScope('all'), false);
    assert.strictEqual(fixture.session.getCandidateScope(), 'compatible');
    assert.strictEqual(fixture.session.setCandidateScope('backpack'), true);

    let result = null;
    fixture.session.requestCandidates(target, (response, accepted, targetKey, scope) => {
        result = {response, accepted, targetKey, scope};
    });
    const request = fixture.messages[1];
    assert.strictEqual(request.payload.candidateScope, 'backpack');
    fixture.mux.handleResponse(responseFor(request, {payload:{
        target,
        candidateScope:'backpack',
        candidates:[{
            physicalSlot:4,
            disabled:false,
            blockedReason:'',
            source:{containerId:'背包',slot:4,expectedLease:'lease.4'},
            item:itemProjection({majorType:'武器',use:'长枪'}),
            equipmentEligibility:{slots:['长枪'],blockedReason:''}
        }],
        backpackVersion:8,
        stateHealth:'ok',
        diagnostics:[]
    }}));
    assert(result && result.accepted === true);
    assert.strictEqual(result.targetKey, 'equipment:长枪');
    assert.strictEqual(result.scope, 'backpack');

    result = null;
    fixture.session.requestCandidates(target, 'backpack', (response, accepted) => {
        result = {response, accepted};
    });
    const mismatch = fixture.messages[2];
    fixture.mux.handleResponse(responseFor(mismatch, {payload:{
        target,
        candidateScope:'compatible',
        candidates:[],
        backpackVersion:8,
        stateHealth:'ok',
        diagnostics:[]
    }}));
    assert(result && result.accepted === false);
    assert.strictEqual(fixture.errors.at(-1).response.error, 'malformed_response');
});

test('universal equipment backpack eligibility shape fails closed in Web admission', () => {
    const malformed = [
        row => { delete row.equipmentEligibility; },
        row => { row.equipmentEligibility.slots = ['未知槽位']; },
        row => { row.equipmentEligibility.slots = ['手枪','手枪']; },
        row => { row.equipmentEligibility.slots = ['手枪2','手枪']; },
        row => { row.equipmentEligibility.blockedReason = 'cooldown_active'; }
    ];
    malformed.forEach(mutate => {
        const fixture = createFixture();
        openClean(fixture);
        fixture.session.setCandidateScope('backpack');
        const target = {kind:'equipment',slotKey:'长枪'};
        let accepted = true;
        fixture.session.requestCandidates(target, (_, ok) => { accepted = ok; });
        const row = {
            physicalSlot:4,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{containerId:'背包',slot:4,expectedLease:'lease.4'},
            item:itemProjection({majorType:'武器',use:'手枪'}),
            equipmentEligibility:{slots:['手枪','手枪2'],blockedReason:''}
        };
        mutate(row);
        fixture.mux.handleResponse(responseFor(fixture.messages[1], {payload:{
            target,
            candidateScope:'backpack',
            candidates:[row],
            backpackVersion:8,
            stateHealth:'ok',
            diagnostics:[]
        }}));
        assert.strictEqual(accepted, false);
        assert.strictEqual(fixture.errors.at(-1).response.error, 'malformed_response');
    });
});

test('candidate authority reset is centralized on candidates and snapshot admission only', () => {
    const resets = [];
    const fixture = createFixture(null, {
        onCandidateAuthorityReset:reason => resets.push(reason)
    });
    openClean(fixture);
    const target = {kind:'equipment',slotKey:'长枪'};
    fixture.session.requestCandidates(target, 'compatible');
    assert.deepStrictEqual(resets, ['candidates']);
    fixture.mux.handleResponse(responseFor(fixture.messages[1], {payload:{
        target,
        candidateScope:'compatible',
        candidates:[],
        backpackVersion:8,
        stateHealth:'ok',
        diagnostics:[]
    }}));
    fixture.session.requestLoadoutTooltip(target);
    assert.deepStrictEqual(resets, ['candidates']);
    fixture.mux.handleResponse(responseFor(fixture.messages[2], {
        payload:tooltipProjection(target)
    }));
    fixture.session.refreshSnapshot();
    assert.deepStrictEqual(resets, ['candidates','snapshot']);
    fixture.mux.handleResponse(responseFor(fixture.messages[3], {
        success:false,
        error:'service_not_ready'
    }));
    assert.deepStrictEqual(resets, ['candidates','snapshot']);
});

test('latest candidate request fences a late response from the previous scope', () => {
    const fixture = createFixture();
    openClean(fixture);
    const target = {kind:'equipment', slotKey:'长枪'};
    const accepted = [];
    fixture.session.requestCandidates(target, 'compatible', (_, ok, __, scope) => {
        if (ok) accepted.push(scope);
    });
    const compatible = fixture.messages[1];
    fixture.session.requestCandidates(target, 'backpack', (_, ok, __, scope) => {
        if (ok) accepted.push(scope);
    });
    const backpack = fixture.messages[2];
    fixture.mux.handleResponse(responseFor(compatible, {payload:{
        target,candidateScope:'compatible',candidates:[],backpackVersion:8,
        stateHealth:'ok',diagnostics:[]
    }}));
    fixture.mux.handleResponse(responseFor(backpack, {payload:{
        target,candidateScope:'backpack',candidates:[],backpackVersion:8,
        stateHealth:'ok',diagnostics:[]
    }}));
    assert.deepStrictEqual(accepted, ['backpack']);
});

test('snapshot adoption rejects blank and wrapped-case undefined loadout item identities', () => {
    [
        ['name',' Undefined '],
        ['displayName','   '],
        ['icon','uNdEfInEd']
    ].forEach(([field,value]) => {
        const fixture=createFixture();
        openClean(fixture);
        const before=fixture.session.getSnapshot();
        let accepted=true;
        fixture.session.refreshSnapshot((_,ok) => { accepted=ok; });
        const response=projection();
        response.equipment[0]={
            slotKey:'头部装备',occupied:true,item:itemProjection({[field]:value})
        };
        fixture.mux.handleResponse(responseFor(fixture.messages[1],{payload:response}));
        assert.strictEqual(accepted,false);
        assert.strictEqual(fixture.session.getSnapshot(),before);
        assert.strictEqual(fixture.errors.at(-1).response.error,'malformed_response');
    });
});

test('candidate adoption rejects blank and wrapped-case undefined item identities', () => {
    [
        ['name',' Undefined '],
        ['displayName','   '],
        ['icon','uNdEfInEd']
    ].forEach(([field,value]) => {
        const fixture=createFixture();
        openClean(fixture);
        const target={kind:'equipment',slotKey:'头部装备'};
        let accepted=true;
        fixture.session.requestCandidates(target,(_,ok) => { accepted=ok; });
        fixture.mux.handleResponse(responseFor(fixture.messages[1],{
            payload:{
                target,
                candidateScope:'compatible',
                candidates:[{item:itemProjection({[field]:value})}],
                backpackVersion:8,
                stateHealth:'ok',
                diagnostics:[]
            }
        }));
        assert.strictEqual(accepted,false);
        assert.strictEqual(fixture.errors.at(-1).response.error,'malformed_response');
    });
});

test('snapshot, candidate and mutation adoption reject malformed nested mod triples', () => {
    let fixture=createFixture();
    openClean(fixture);
    let accepted=true;
    fixture.session.refreshSnapshot((_,ok) => { accepted=ok; });
    let response=projection();
    response.equipment[0]={slotKey:'头部装备',occupied:true,
        item:itemProjection({modSlots:[modProjection({displayName:' Undefined '})]})};
    fixture.mux.handleResponse(responseFor(fixture.messages[1],{payload:response}));
    assert.strictEqual(accepted,false);
    assert.strictEqual(fixture.errors.at(-1).response.error,'malformed_response');

    fixture=createFixture();
    openClean(fixture);
    const target={kind:'equipment',slotKey:'头部装备'};
    accepted=true;
    fixture.session.requestCandidates(target,(_,ok) => { accepted=ok; });
    fixture.mux.handleResponse(responseFor(fixture.messages[1],{payload:{
        target,
        candidateScope:'compatible',
        candidates:[{item:itemProjection({modMeta:modProjection({icon:'   '})})}],
        backpackVersion:8,stateHealth:'ok',diagnostics:[]
    }}));
    assert.strictEqual(accepted,false);
    assert.strictEqual(fixture.errors.at(-1).response.error,'malformed_response');

    fixture=createFixture();
    openClean(fixture);
    let result=null;
    fixture.session.unequipEquipment('长枪',(mutationResponse,ok,unknown) => {
        result={response:mutationResponse,accepted:ok,unknown};
    });
    const mutation=fixture.messages[1];
    const backpack=fullBackpack(12);
    backpack.slots[0]={physicalSlot:0,slotLease:'lease.mod.0',occupied:true,
        item:itemProjection({modSlots:[modProjection({name:'uNdEfInEd'})]})};
    fixture.mux.handleResponse(responseFor(mutation,{
        writeEpoch:1,loadoutRevision:4,liveRevision:3,liveRefreshDirty:true,
        changed:true,operation:'unequipEquipment',affectedBackpackSlot:0,
        payload:projection(),inventorySnapshots:[backpack]
    }));
    assert(result && result.accepted===false && result.unknown===true);
    assert.strictEqual(fixture.session.getState(),'needs_reconcile');
});

test('unknown flush uses a watermarked fresh snapshot before stats', () => {
    const fixture = createFixture();
    openClean(fixture, {loadout:4, live:3, drug:2, dirty:true});
    let statsAccepted = false;
    fixture.session.prepareStats((_, accepted) => { statsAccepted = accepted; });
    const flush = fixture.messages[1];
    assert.strictEqual(flush.cmd, 'flushLive');
    assert.deepStrictEqual(flush.payload, {
        v:1,
        sessionGeneration:7,
        expectedLoadoutRevision:4
    });
    fixture.timers.expireLatest();
    const reconcile = fixture.messages[2];
    assert.strictEqual(reconcile.cmd, 'snapshot');
    assert.deepStrictEqual(reconcile.payload, {
        v:1,
        sessionGeneration:7,
        reconcileAfterCallId:flush.callId
    });
    fixture.mux.handleResponse(responseFor(reconcile, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        liveRefreshDirty:false,
        payload:projection()
    }));
    const stats = fixture.messages[3];
    assert.strictEqual(stats.cmd, 'statsSnapshot');
    assert.deepStrictEqual(stats.payload, {
        v:1,
        sessionGeneration:7,
        expectedLoadoutRevision:4,
        expectedLiveRevision:4
    });
    fixture.mux.handleResponse(responseFor(stats, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        payload:statsProjection()
    }));
    assert.strictEqual(statsAccepted, true);
    assert.strictEqual(fixture.session.getState(), 'idle');
});

test('close after unknown flush reconciles by snapshot then finalizes without replaying flush', () => {
    const fixture = createFixture();
    openClean(fixture, {loadout:4, live:3, drug:2, dirty:true});
    fixture.session._requestFlush();
    const flush = fixture.messages[1];
    fixture.timers.expireLatest();
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
    let accepted = false;
    fixture.session.finalize((_, ok) => { accepted = ok; });
    const reconcile = fixture.messages[2];
    assert.strictEqual(reconcile.cmd, 'snapshot');
    assert.strictEqual(reconcile.payload.reconcileAfterCallId, flush.callId);
    assert.strictEqual(fixture.messages.filter(row => row.cmd === 'flushLive').length, 1);
    fixture.mux.handleResponse(responseFor(reconcile, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        payload:projection()
    }));
    const finalize = fixture.messages[3];
    assert.strictEqual(finalize.cmd, 'finalize');
    assert.deepStrictEqual(finalize.payload, {
        v:1,
        sessionGeneration:7,
        expectedLoadoutRevision:4
    });
    fixture.mux.handleResponse(responseFor(finalize, {
        writeEpoch:2,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        active:false,
        closed:true,
        liveChanged:false,
        persistence:{success:true, changed:false}
    }));
    assert.strictEqual(accepted, true);
    assert.strictEqual(fixture.session.canClose(), true);
});

test('close joins an in-flight flush reconciliation and supersedes the pending stats read', () => {
    const fixture = createFixture();
    openClean(fixture, {loadout:4, live:3, drug:2, dirty:true});
    fixture.session.prepareStats();
    const flush = fixture.messages[1];
    fixture.timers.expireLatest();
    const reconcile = fixture.messages[2];
    fixture.session.finalize();
    assert.strictEqual(fixture.messages.length, 3);
    fixture.mux.handleResponse(responseFor(reconcile, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        payload:projection()
    }));
    assert.deepStrictEqual(fixture.messages.map(row => row.cmd),
        ['snapshot', 'flushLive', 'snapshot', 'finalize']);
    assert.strictEqual(reconcile.payload.reconcileAfterCallId, flush.callId);
    assert.strictEqual(fixture.messages.filter(row => row.cmd === 'flushLive').length, 1);
});

test('leave joins an in-flight flush reconciliation without issuing stats or another write', () => {
    const fixture = createFixture();
    openClean(fixture, {loadout:4, live:3, drug:2, dirty:true});
    fixture.session.prepareStats();
    fixture.timers.expireLatest();
    const reconcile = fixture.messages[2];
    let canLeave = false;
    fixture.session.prepareLeave((_, accepted) => { canLeave = accepted; });
    assert.strictEqual(fixture.messages.length, 3);
    fixture.mux.handleResponse(responseFor(reconcile, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:4,
        drugRevision:2,
        payload:projection()
    }));
    assert.strictEqual(canLeave, true);
    assert.deepStrictEqual(fixture.messages.map(row => row.cmd),
        ['snapshot', 'flushLive', 'snapshot']);
    assert.strictEqual(fixture.session.getState(), 'idle');
});

test('unknown finalize only closes after same-generation watermarked retry proof', () => {
    const fixture = createFixture();
    openClean(fixture);
    let accepted = false;
    fixture.session.finalize(value => { accepted = value && value.success === true; });
    const first = fixture.messages[1];
    fixture.timers.expireLatest();
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
    assert.strictEqual(fixture.session.canClose(), false);
    fixture.session.finalize((response, ok) => { accepted = ok && response.success === true; });
    const retry = fixture.messages[2];
    assert.deepStrictEqual(retry.payload, {
        v:1,
        sessionGeneration:7,
        expectedLoadoutRevision:3,
        reconcileAfterCallId:first.callId
    });
    fixture.mux.handleResponse(responseFor(retry, {
        writeEpoch:2,
        active:false,
        closed:true,
        liveChanged:false,
        persistence:{success:true, changed:false}
    }));
    assert.strictEqual(accepted, true);
    assert.strictEqual(fixture.session.canClose(), true);
});

test('legacy persistenceSucceeded cannot substitute the nested persistence proof', () => {
    const fixture = createFixture();
    openClean(fixture);
    let accepted = true;
    fixture.session.finalize((_, ok) => { accepted = ok; });
    const finalize = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(finalize, {
        active:false,
        closed:true,
        liveChanged:false,
        persistence:{success:true, changed:false},
        persistenceSucceeded:true
    }));
    assert.strictEqual(accepted, false);
    assert.strictEqual(fixture.session.canClose(), false);
    assert.strictEqual(fixture.session.getState(), 'flush_failed');
});

test('fresh ordinary snapshot recovers a deterministic flush failure after view suspension', () => {
    const fixture = createFixture();
    openClean(fixture);
    fixture.session.finalize();
    const finalize = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(finalize, {
        success:false,
        error:'flush_failed',
        active:true
    }));
    assert.strictEqual(fixture.session.getState(), 'flush_failed');
    const refreshCallId = fixture.session.refreshSnapshot();
    assert(refreshCallId);
    const refresh = fixture.messages[2];
    assert.strictEqual(refresh.cmd, 'snapshot');
    fixture.mux.handleResponse(responseFor(refresh, {payload:projection()}));
    assert.strictEqual(fixture.session.getState(), 'idle');
});

test('four mutations emit only the frozen revision and lease-bound payload shapes', () => {
    const fixture = createFixture();
    openClean(fixture);
    const source = {containerId:'背包', slot:9, expectedLease:'lease.source.9'};
    const calls = [
        () => fixture.session.equipEquipment('长枪', source),
        () => fixture.session.unequipEquipment('长枪'),
        () => fixture.session.equipDrug(2, source),
        () => fixture.session.unequipDrug(2)
    ];
    const expected = [
        {v:1, sessionGeneration:7, expectedLoadoutRevision:3, slotKey:'长枪', source},
        {v:1, sessionGeneration:7, expectedLoadoutRevision:3, slotKey:'长枪'},
        {v:1, sessionGeneration:7, expectedDrugRevision:2, drugSlot:2, source},
        {v:1, sessionGeneration:7, expectedDrugRevision:2, drugSlot:2}
    ];
    calls.forEach((issue, index) => {
        assert(issue());
        const message = fixture.messages[index + 1];
        assert.deepStrictEqual(message.payload, expected[index]);
        fixture.mux.handleResponse(responseFor(message, {
            success:false,
            error:'stale_source'
        }));
        assert.strictEqual(fixture.session.getState(), 'idle');
    });
});

test('mutation is single-flight and deterministic success adopts both write-after snapshots', () => {
    const fixture = createFixture();
    openClean(fixture);
    const source = {containerId:'背包', slot:9, expectedLease:'lease.source.9'};
    let result = null;
    assert(fixture.session.equipEquipment('长枪', source, (response, accepted, unknown) => {
        result = {response, accepted, unknown};
    }));
    const mutation = fixture.messages[1];
    assert.strictEqual(fixture.session.getState(), 'write_pending');
    assert.strictEqual(fixture.session.equipDrug(0, source), null);
    assert.strictEqual(fixture.session.requestCandidates({kind:'equipment', slotKey:'长枪'}), null);
    assert.strictEqual(fixture.session.prepareStats(), null);
    assert.strictEqual(fixture.session.finalize(), null);
    fixture.mux.handleResponse(responseFor(mutation, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:3,
        drugRevision:2,
        liveRefreshDirty:true,
        changed:true,
        operation:'equipEquipment',
        affectedBackpackSlot:9,
        payload:projection(),
        inventorySnapshots:[fullBackpack(10)]
    }));
    assert(result && result.accepted && result.unknown === false);
    assert.strictEqual(fixture.session.getState(), 'idle');
    assert.strictEqual(fixture.session.getSnapshot(), result.response.payload);
    assert.strictEqual(fixture.session.debugState().loadoutRevision, 4);
});

test('deterministic mutation failure restores idle and keeps the old authority', () => {
    const fixture = createFixture();
    openClean(fixture);
    const before = fixture.session.getSnapshot();
    let result = null;
    fixture.session.unequipEquipment('长枪', (response, accepted, unknown) => {
        result = {response, accepted, unknown};
    });
    const mutation = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(mutation, {
        success:false,
        error:'backpack_full'
    }));
    assert(result && result.accepted === false && result.unknown === false);
    assert.strictEqual(fixture.session.getState(), 'idle');
    assert.strictEqual(fixture.session.getSnapshot(), before);
    assert.deepStrictEqual(fixture.messages.map(message => message.cmd),
        ['snapshot', 'unequipEquipment']);
});

test('timeout mutation reconciles only by exact post-watermark loadout plus backpack and never replays', () => {
    const fixture = createFixture();
    openClean(fixture);
    const source = {containerId:'背包', slot:9, expectedLease:'lease.source.9'};
    let unknown = false;
    fixture.session.equipEquipment('长枪', source, (_, accepted, needsReconcile) => {
        unknown = !accepted && needsReconcile;
    });
    const mutation = fixture.messages[1];
    fixture.timers.expireLatest();
    assert.strictEqual(unknown, true);
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
    assert.strictEqual(fixture.session.refreshSnapshot(), null);
    assert(fixture.session.reconcileMutation());
    const malformed = fixture.messages[2];
    assert.deepStrictEqual(malformed.payload, {
        v:1,
        sessionGeneration:7,
        reconcileAfterCallId:mutation.callId
    });
    fixture.mux.handleResponse(responseFor(malformed, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:3,
        liveRefreshDirty:true,
        reconcileAfterCallId:mutation.callId,
        payload:projection()
    }));
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
    assert(fixture.session.reconcileMutation());
    const reconcile = fixture.messages[3];
    fixture.mux.handleResponse(responseFor(reconcile, {
        writeEpoch:1,
        loadoutRevision:4,
        liveRevision:3,
        liveRefreshDirty:true,
        reconcileAfterCallId:mutation.callId,
        payload:projection(),
        inventorySnapshots:[fullBackpack(11)]
    }));
    assert.strictEqual(fixture.session.getState(), 'idle');
    assert.strictEqual(fixture.messages.filter(message =>
        message.cmd === 'equipEquipment').length, 1);
    assert.strictEqual(fixture.messages.filter(message =>
        message.cmd === 'snapshot' && message.payload.reconcileAfterCallId).length, 2);
});

test('malformed mutation success is unknown even without a Host reconcile marker', () => {
    const fixture = createFixture();
    openClean(fixture);
    let result = null;
    fixture.session.unequipDrug(0, (response, accepted, unknown) => {
        result = {response, accepted, unknown};
    });
    const mutation = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(mutation, {
        writeEpoch:1,
        drugRevision:3,
        changed:true,
        operation:'unequipDrug',
        affectedBackpackSlot:4,
        payload:projection()
    }));
    assert(result && result.accepted === false && result.unknown === true);
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
    assert.strictEqual(fixture.session.getSnapshot() !== result.response.payload, true);
});

test('mutation adoption rejects malformed item identities in the backpack proof', () => {
    [
        ['name',' Undefined '],
        ['displayName','   '],
        ['icon','uNdEfInEd']
    ].forEach(([field,value]) => {
        const fixture=createFixture();
        openClean(fixture);
        let result=null;
        fixture.session.unequipEquipment('长枪',(response,accepted,unknown) => {
            result={response,accepted,unknown};
        });
        const mutation=fixture.messages[1];
        const backpack=fullBackpack(12);
        backpack.slots[0]={
            physicalSlot:0,
            slotLease:'lease.identity.0',
            occupied:true,
            item:itemProjection({[field]:value})
        };
        fixture.mux.handleResponse(responseFor(mutation,{
            writeEpoch:1,
            loadoutRevision:4,
            liveRevision:3,
            liveRefreshDirty:true,
            changed:true,
            operation:'unequipEquipment',
            affectedBackpackSlot:0,
            payload:projection(),
            inventorySnapshots:[backpack]
        }));
        assert(result && result.accepted===false && result.unknown===true);
        assert.strictEqual(fixture.session.getState(),'needs_reconcile');
    });
});

test('Host requiresReconcile marker preserves the exact mutation watermark', () => {
    const fixture = createFixture();
    openClean(fixture);
    let result = null;
    fixture.session.unequipEquipment('长枪', (response, accepted, unknown) => {
        result = {response, accepted, unknown};
    });
    const mutation = fixture.messages[1];
    fixture.mux.handleResponse(responseFor(mutation, {
        success:false,
        error:'delivery_unknown',
        writeEpoch:1,
        requiresReconcile:true,
        reconcileAfterCallId:mutation.callId
    }));
    assert(result && result.accepted === false && result.unknown === true);
    assert.deepStrictEqual(fixture.session.debugState().unknown, {
        kind:'mutation',
        callId:mutation.callId
    });
    assert.strictEqual(fixture.session.getState(), 'needs_reconcile');
});

process.stdout.write('Character-build session ' + passed + '/' + passed + ' passed\n');
