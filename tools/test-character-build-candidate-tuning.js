#!/usr/bin/env node
'use strict';

const assert = require('assert');
const CandidateTuning = require(
    '../launcher/web/modules/character-build/character-build-tuning-adapter.js');
const CharacterBuildView = require(
    '../launcher/web/modules/character-build-view.js').CharacterBuildView;
const CandidateState = require(
    '../launcher/web/modules/character-build/character-build-candidate-state.js').CandidateState;

let checks = 0;
function check(name, callback) {
    callback();
    checks += 1;
    process.stdout.write('PASS ' + name + '\n');
}

function candidate(slot, lease, overrides) {
    const row = {
        key:'backpack:' + slot + ':' + lease,
        name:'候选长枪',
        physicalSlot:slot,
        blocked:false,
        presentation:{
            name:'候选长枪',
            displayName:'候选长枪',
            itemKind:'equipment',
            majorType:'武器',
            use:'长枪',
            enhancementLevel:3
        },
        raw:{
            physicalSlot:slot,
            disabled:false,
            source:{
                containerId:'背包',
                slot:slot,
                expectedLease:lease
            }
        }
    };
    return Object.assign(row, overrides || {});
}

check('exact candidate source becomes the existing inventory tuning source', function() {
    assert.deepStrictEqual(CandidateTuning.sourceFor(candidate(7, 'lease.7')), {
        sourceKind:'inventory',
        containerId:'背包',
        slot:7,
        expectedLease:'lease.7'
    });
});

check('near-shaped and mismatched candidate sources fail closed', function() {
    const extra = candidate(7, 'lease.7');
    extra.raw.source.extra = true;
    assert.strictEqual(CandidateTuning.sourceFor(extra), null);
    const mismatch = candidate(7, 'lease.7');
    mismatch.raw.source.slot = 8;
    assert.strictEqual(CandidateTuning.sourceFor(mismatch), null);
});

check('blocked non-equipment and untunable candidates expose readable zero-intent reasons', function() {
    const blocked = candidate(7, 'lease.7', {
        blocked:true,
        raw:{disabled:true, blockedReason:'level_locked',
            physicalSlot:7, source:{containerId:'背包', slot:7, expectedLease:'lease.7'}}
    });
    assert.deepStrictEqual(CandidateTuning.capability(blocked), {
        available:false,
        code:'blocked',
        reason:'该候选当前等级不足，不能调制',
        source:null
    });
    const stack = candidate(8, 'lease.8');
    stack.presentation = {
        itemKind:'stack', majorType:'消耗品', use:'手雷',
        enhancementLevel:0, quantity:168
    };
    assert.strictEqual(CandidateTuning.capability(stack).reason, '数量型手雷不能调制');
    assert.strictEqual(CandidateTuning.sourceFor(stack), null);
    const levelZero = candidate(9, 'lease.9');
    levelZero.presentation.enhancementLevel = 0;
    assert.strictEqual(CandidateTuning.capability(levelZero).reason,
        '该装备缺少有效的强化等级');
    assert.strictEqual(CandidateTuning.sourceFor(levelZero), null);
});

check('same physical slot with a new lease is the exact semantic return', function() {
    const before = candidate(7, 'lease.old');
    const state = CandidateTuning.returnState(before, 1);
    const after = [
        candidate(3, 'lease.3'),
        candidate(7, 'lease.new'),
        candidate(9, 'lease.9')
    ];
    assert.deepStrictEqual(
        CandidateTuning.resolveReturn(state, after, CandidateTuning.sourceFor(after[1])),
        {kind:'exact', index:1, candidate:after[1]});
});

check('removed source uses fixed next-then-previous adjacent fallback', function() {
    const before = candidate(7, 'lease.old');
    const state = CandidateTuning.returnState(before, 1);
    const next = [candidate(3, 'lease.3'), candidate(9, 'lease.9')];
    assert.deepStrictEqual(
        CandidateTuning.resolveReturn(state, next, null),
        {kind:'adjacent', index:1, candidate:next[1]});
    const previous = [candidate(3, 'lease.3')];
    assert.deepStrictEqual(
        CandidateTuning.resolveReturn(state, previous, null),
        {kind:'adjacent', index:0, candidate:previous[0]});
    assert.deepStrictEqual(
        CandidateTuning.resolveReturn(state, [], null),
        {kind:'empty', index:-1, candidate:null});
});

check('ambiguous physical candidates fail closed instead of guessing a lease', function() {
    const state = CandidateTuning.returnState(candidate(7, 'lease.old'), 0);
    const ambiguous = [candidate(7, 'lease.new'), candidate(7, 'lease.shadow')];
    assert.deepStrictEqual(
        CandidateTuning.resolveReturn(
            state, ambiguous, CandidateTuning.sourceFor(ambiguous[0])),
        {kind:'empty', index:-1, candidate:null});
});

check('empty return restores the slot then focuses its candidate heading', function() {
    const heading = {
        tabindex:'',
        focused:false,
        setAttribute:function(name, value) { this[name] = value; },
        focus:function() { this.focused = true; }
    };
    const scroll = {scrollTop:0};
    const view = {
        _destroyed:false,
        restoredSlot:'',
        notice:'',
        root:{querySelector:function(selector) {
            return selector === '#character-build-candidate-title' ? heading : scroll;
        }},
        restoreSlot:function(slotKey) { this.restoredSlot = slotKey; return true; },
        _showStatusNotice:function(kind, message) { this.notice = kind + ':' + message; }
    };
    assert.strictEqual(
        CharacterBuildView.prototype.restoreCandidateTuning.call(view, {
            kind:'empty',
            index:-1,
            candidate:null
        }, {
            slotKey:'weapon:长枪',
            scrollTop:37
        }),
        true);
    assert.strictEqual(view.restoredSlot, 'weapon:长枪');
    assert.strictEqual(heading.tabindex, '-1');
    assert.strictEqual(heading.focused, true);
    assert.strictEqual(scroll.scrollTop, 37);
    assert.match(view.notice, /当前槽位已没有可恢复的候选/);
});

check('candidate focus keeps visible scroll and applies nearest correction only outside', function() {
    const scroll = {
        scrollTop:70,
        getBoundingClientRect:function() { return {top:100, bottom:300}; }
    };
    const node = {
        top:140,
        bottom:200,
        focused:false,
        getAttribute:function() { return 'candidate-key'; },
        getBoundingClientRect:function() { return {top:this.top, bottom:this.bottom}; },
        focus:function() { this.focused = true; }
    };
    const state = {_host:{querySelectorAll:function() { return [node]; }}};
    assert.strictEqual(
        CandidateState.prototype.focusCandidate.call(state, 'candidate-key', scroll),
        true);
    assert.strictEqual(node.focused, true);
    assert.strictEqual(scroll.scrollTop, 70);
    node.top = 350;
    node.bottom = 410;
    CandidateState.prototype.focusCandidate.call(state, 'candidate-key', scroll);
    assert.strictEqual(scroll.scrollTop, 180);
    node.top = 40;
    node.bottom = 90;
    CandidateState.prototype.focusCandidate.call(state, 'candidate-key', scroll);
    assert.strictEqual(scroll.scrollTop, 120);
    scroll.scrollTop = 70;
    scroll.clientHeight = 100;
    node.top = 350;
    node.bottom = 410;
    CandidateState.prototype.focusCandidate.call(state, 'candidate-key', scroll);
    assert.strictEqual(scroll.scrollTop, 125);
});

check('slot adapter preserves the exact lease for EquipmentTuningView', function() {
    assert.deepStrictEqual(CandidateTuning.slotFor(candidate(12, 'lease.12')), {
        occupied:true,
        physicalSlot:12,
        slotLease:'lease.12',
        item:candidate(12, 'lease.12').presentation
    });
});

function flowFixture(mode) {
    const oldCandidate = candidate(7, 'lease.old');
    const nextCandidate = candidate(7, 'lease.new');
    const state = {
        candidates:[oldCandidate],
        selectedCandidateKey:oldCandidate.key,
        candidateRequestKey:'candidate-view-1:weapon:长枪:1',
        selectedSlotKey:'weapon:长枪',
        sets:0,
        cacheCalls:0,
        invalidations:0,
        pending:null
    };
    const session = {
        debugState:function() {
            return {
                state:'idle',
                panelInstanceId:'panel.build.1',
                sessionGeneration:4
            };
        },
        requestCandidates:function(target, callback) {
            if (mode === 'late') {
                state.pending = callback;
                return 'call.candidates.late';
            }
            callback({
                success:true,
                payload:{projected:[nextCandidate]}
            }, true, 'equipment:' + target.slotKey);
            return 'call.candidates.1';
        }
    };
    const view = {
        root:{querySelector:function() { return {scrollTop:41}; }},
        debugState:function() {
            return {
                selectedCandidateKey:state.selectedCandidateKey,
                candidateRequestKey:state.candidateRequestKey,
                selectedSlotKey:state.selectedSlotKey
            };
        },
        getCandidates:function() { return state.candidates.slice(); },
        setCandidates:function(requestKey, candidates) {
            assert.strictEqual(requestKey, state.candidateRequestKey);
            state.candidates = candidates.slice();
            state.selectedCandidateKey = '';
            state.sets += 1;
            return true;
        }
    };
    const flow = new CandidateTuning.CandidateFlow({
        session:session,
        view:view,
        projectCandidates:function(payload) { return payload.projected; },
        invalidateTooltip:function() { state.invalidations += 1; },
        ports:{
            completeExternalWrite:function(operation, snapshots, callback, needsRefresh) {
                state.cacheCalls += 1;
                assert.strictEqual(operation.id, 'write.1');
                assert.strictEqual(snapshots, null);
                assert.strictEqual(needsRefresh, true);
                callback({success:true, refreshed:true});
                return true;
            }
        }
    });
    assert.ok(flow.begin(
        oldCandidate,
        {kind:'equipment', slotKey:'长枪'},
        'panel.build.1'));
    return {flow:flow, state:state, nextCandidate:nextCandidate};
}

check('candidate flow refreshes the exact target after the narrow cache completion', function() {
    const fixture = flowFixture('success');
    let result = null;
    assert.strictEqual(fixture.flow.completeWrite(
        {id:'write.1'}, true, function(value) { result = value; }), true);
    assert.deepStrictEqual(result, {success:true, refreshed:true});
    assert.strictEqual(fixture.state.cacheCalls, 1);
    assert.strictEqual(fixture.state.sets, 1);
    assert.strictEqual(fixture.state.invalidations, 2);
    assert.strictEqual(
        fixture.flow.resolveSlot('背包', 7).slotLease,
        'lease.new');
    fixture.state.candidates.push(candidate(7, 'lease.duplicate'));
    assert.strictEqual(fixture.flow.resolveSlot('背包', 7), null);
    const entry = fixture.flow.deactivate();
    assert.strictEqual(
        fixture.flow.returnPlan(
            entry, CandidateTuning.sourceFor(fixture.nextCandidate)).kind,
        'empty');
});

check('deactivate fences a late candidate refresh from reviving retired view state', function() {
    const fixture = flowFixture('late');
    let result = null;
    fixture.flow.completeWrite(
        {id:'write.1'}, true, function(value) { result = value; });
    fixture.flow.deactivate();
    fixture.state.pending({
        success:true,
        payload:{projected:[fixture.nextCandidate]}
    }, true, 'equipment:长枪');
    assert.strictEqual(result, null);
    assert.strictEqual(fixture.state.sets, 0);
});

process.stdout.write(
    'Character Build candidate tuning: ' + checks + '/' + checks + ' passed\n');
