#!/usr/bin/env node
'use strict';

const assert = require('assert');
const Model = require('../launcher/web/modules/equipment-tuning-model.js');
const CharacterBuildTuning = require(
    '../launcher/web/modules/character-build/character-build-tuning.js').CharacterBuildTuning;

let checks = 0;
function equal(actual, expected, message) {
    assert.deepStrictEqual(actual, expected, message);
    checks += 1;
}

const source = {containerId:'背包',slot:2,expectedLease:'lease.source'};
const sourceItem = {itemKind:'equipment',use:'手枪',enhancementLevel:5};
const candidates = [
    {occupied:true,physicalSlot:2,slotLease:'lease.source',item:sourceItem},
    {occupied:true,physicalSlot:3,slotLease:'lease.target',item:{itemKind:'equipment',use:'手枪',enhancementLevel:7}},
    {occupied:true,physicalSlot:4,slotLease:'lease.same-level',item:{itemKind:'equipment',use:'手枪',enhancementLevel:5}},
    {occupied:true,physicalSlot:5,slotLease:'lease.other-use',item:{itemKind:'equipment',use:'长枪',enhancementLevel:8}},
    {occupied:false,physicalSlot:6,slotLease:'lease.empty',item:null},
    {occupied:true,physicalSlot:3,slotLease:'lease.target',item:{itemKind:'equipment',use:'手枪',enhancementLevel:9}}
];

equal(Model.wireRef(candidates[1]), {containerId:'背包',slot:3,expectedLease:'lease.target'},
    'wire ref uses physical slot and lease');
equal(Model.sameRef(source, {containerId:'背包',slot:2,expectedLease:'rotated'}), true,
    'identity ignores rotating lease');
equal(Model.normalizeTuningSource({
    sourceKind:'inventory',containerId:'背包',slot:2,expectedLease:'lease.source'
}), {
    sourceKind:'inventory',containerId:'背包',slot:2,expectedLease:'lease.source'
}, 'inventory tuning source keeps its exact slot lease');
equal(Model.normalizeTuningSource({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'手枪2',expectedLoadoutRevision:7
}), {
    sourceKind:'loadout',sessionGeneration:17,slotKey:'手枪2',expectedLoadoutRevision:7
}, 'loadout tuning source uses the exact slot and loadout revision');
equal(Model.normalizeTuningSource({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'饰品',expectedLoadoutRevision:7
}), null, 'loadout tuning source rejects keys outside the frozen eleven slots');
equal(Model.normalizeTuningSource({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',
    expectedLoadoutRevision:7,containerId:'背包'
}), null, 'loadout tuning source cannot alias an inventory container');
equal(Model.normalizeTuningSource({
    sourceKind:'loadout',slotKey:'长枪',expectedLoadoutRevision:7
}), null, 'loadout tuning source cannot omit the active Character Build generation');
equal(Model.normalizeTuningSource({
    sourceKind:'inventory',containerId:'背包',slot:2,
    expectedLease:'lease.source',sessionGeneration:17
}), null, 'inventory source rejects loadout generation fields');
equal(Model.normalizeTuningSource({
    sourceKind:'inventory',containerId:'战备箱',slot:2,expectedLease:'lease.other'
}), null, 'first-round tuning source cannot widen beyond the backpack');
equal(Model.tuningSourceKey({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:9
}), 'loadout:17:颈部装备', 'loadout focus identity binds generation while staying stable across revision refreshes');
equal(Model.sameLoadoutIdentity(
    {sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:5},
    {sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:9}
), true, 'loadout barrier identity allows only revision to advance');
equal(Model.sameLoadoutIdentity(
    {sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:5},
    {sourceKind:'loadout',sessionGeneration:18,slotKey:'颈部装备',expectedLoadoutRevision:9}
), false, 'loadout barrier identity rejects generation changes');
equal(Model.sameLoadoutIdentity(
    {sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:5},
    {sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9}
), false, 'loadout barrier identity rejects slot changes');

let adapterGeneration = 17;
let refreshCallback = null;
let refreshCalls = 0;
let adoptedPayloads = 0;
const adapterSession = {
    debugState:function() {
        return {sessionGeneration:adapterGeneration, loadoutRevision:9};
    },
    getState:function() { return 'idle'; },
    refreshSnapshot:function(callback) {
        refreshCalls += 1;
        refreshCallback = callback;
        return 'loadout.snapshot.test';
    }
};
const tuningAdapter = new CharacterBuildTuning({
    session:adapterSession,
    view:{},
    adoptSnapshot:function() { adoptedPayloads += 1; }
});
tuningAdapter._active = true;
tuningAdapter._slotKey = '长枪';
tuningAdapter._entrySource = {
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:7
};
equal(tuningAdapter._refreshLoadout({
    sourceKind:'loadout',sessionGeneration:18,slotKey:'长枪',expectedLoadoutRevision:9
}, function() {}), false, 'loadout adapter rejects a new generation before requesting refresh');
equal(refreshCalls, 0, 'generation rejection sends no ordinary loadout snapshot');
equal(tuningAdapter._refreshLoadout({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'手枪',expectedLoadoutRevision:9
}, function() {}), false, 'loadout adapter rejects a different slot before requesting refresh');
let refreshResult = null;
equal(tuningAdapter._refreshLoadout({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}, function(result) { refreshResult = result; }), true,
'loadout adapter accepts the original identity while allowing revision advance');
adapterGeneration = 18;
refreshCallback({payload:{equipment:[{
    slotKey:'长枪',occupied:true,item:{itemKind:'equipment',name:'测试长枪'}
}]}}, true);
equal(refreshResult && refreshResult.success, false,
    'loadout adapter rejects a generation change that races the refresh callback');
equal(adoptedPayloads, 0,
    'cross-generation refresh is rejected before Character Build adopts its projection');
const scheduledScrollRestores = [];
const originalSetTimeout = global.setTimeout;
const scrollProbe = {scrollTop:0};
const scrollAdapter = new CharacterBuildTuning({
    session:adapterSession,
    view:{
        root:{querySelector:function() { return scrollProbe; }},
        debugState:function() { return {candidateCount:0}; }
    }
});
try {
    global.setTimeout = function(callback) {
        scheduledScrollRestores.push(callback);
        return scheduledScrollRestores.length;
    };
    scrollAdapter._scrollRestoreGeneration = 1;
    scrollAdapter._restoreScroll({scrollTop:73}, 1, 1);
    equal(scrollProbe.scrollTop, 73,
        'tuning return restores the captured candidate scroll position');
    equal(scheduledScrollRestores.length, 1,
        'an empty candidate projection schedules one bounded restore retry');
    scrollAdapter._scrollRestoreGeneration = 2;
    scrollProbe.scrollTop = 19;
    scheduledScrollRestores.shift()();
    equal(scrollProbe.scrollTop, 19,
        'a later tuning generation cancels stale scroll restore timers');
} finally {
    global.setTimeout = originalSetTimeout;
}
equal(Model.tuningSourceSupports({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}, 'enhance'), true, 'loadout source admits first-round single-item tuning');
equal(Model.tuningSourceSupports({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}, 'convert'), false, 'loadout source keeps cross-container conversion out of scope');
equal(Model.tuningSnapshotRequest({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}), {
    source:{sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9}
}, 'read-only snapshot prototype emits the normalized loadout authority shape');
equal(Model.loadoutSlotKeys.length, 11, 'loadout source whitelist remains exactly eleven slots');
equal(Model.normalizeConversionCandidates(candidates, source, sourceItem), [candidates[1]],
    'conversion projection filters source/use/level/duplicates atomically');
equal(Model.previewIntentKey('enhance', {targetLevel:8.9}), 'enhance|8', 'enhance intent is discrete');
equal(Model.previewIntentKey('convert', {target:{containerId:'背包',slot:3,expectedLease:'lease.target'}}),
    'convert|背包|3|lease.target', 'conversion intent includes exact lease');
equal(Model.previewIntentKey('replace_mod', {candidateKey:'new',replaceCandidateKey:'old'}),
    'replace_mod|new|old', 'mod intent includes both opaque keys');
equal(Model.isOperation('detach_all_mods'), true, 'all-mod detach is supported');
equal(Model.isOperation('formula'), false, 'unknown operation rejected');
equal(Model.isOperationGroup('replace_mod'), false, 'replacement stays inside mod top-level group');

equal(Model.quickCommitEligible({
    materials:[{itemName:'导轨',delta:-1}],removedMods:[]
}, {operation:'install_mod',candidateName:'导轨'}), true, 'simple install can fast commit');
equal(Model.quickCommitEligible({
    materials:[{itemName:'新导轨',delta:-1},{itemName:'旧导轨',delta:1}],removedMods:['旧导轨']
}, {operation:'replace_mod',candidateName:'新导轨',replaceCandidateName:'旧导轨'}), true,
    'one-for-one replacement can fast commit');
equal(Model.quickCommitEligible({
    materials:[{itemName:'新导轨',delta:-1},{itemName:'旧导轨',delta:1},{itemName:'副件',delta:1}],
    removedMods:['旧导轨','副件']
}, {operation:'replace_mod',candidateName:'新导轨',replaceCandidateName:'旧导轨'}), false,
    'collateral replacement cannot fast commit');
equal(Model.quickCommitEligible({
    materials:[{itemName:'旧导轨',delta:1}],removedMods:['旧导轨']
}, {operation:'detach_mod',candidateName:'旧导轨'}), true, 'single detach can fast commit');

const snapshot = {
    equipment:{level:6,hardMaxLevel:13},
    enhance:{currentLevel:6,availableMaxLevel:10,hardMaxLevel:13}
};
equal(Model.enhancementAvailableMax(snapshot), 10, 'authority available cap');
equal(Model.enhancementHardMax(snapshot), 13, 'authority hard cap');
equal(Model.nextEnhancementLevel(snapshot), 7, 'next level respects both caps');
equal(Model.nextEnhancementLevel({equipment:{level:13},enhance:{currentLevel:13,availableMaxLevel:13,hardMaxLevel:13}}),
    13, 'hard cap has no phantom next level');
equal(Model.materialCount([{itemName:'强化石',count:208589}], '强化石'), 208589,
    'material array count');
equal(Model.materialDeltaFor([{itemName:'强化石',delta:-3}], '强化石'),
    {itemName:'强化石',delta:-3}, 'material delta lookup');
equal(Model.compactQuantity(12500), '1.2万', 'compact quantity floors one decimal');
equal(Model.equipmentDiff({level:5,tier:'I',mods:['旧']},{level:7,tier:'II',mods:['新']}),
    '+5 → +7 · I → II · 卸下 旧 · 安装 新', 'equipment delta summary');
equal(Model.commitLabel({operation:'enhance',after:{source:{equipment:{level:8}}},
    materials:[{itemName:'强化石',delta:-3}]}), '强化至 +8 · 3 强化石', 'enhancement commit label');
equal(Model.commitLabel({operation:'detach_all_mods'}), '卸下全部配件', 'non-enhance commit label');
equal(Model.modStatus({available:false,reason:'material_missing'}).id, 'material_missing',
    'authoritative unavailable reason maps to filter state');
const tree = Model.buildModFilterTree([
    {grade:'low',gradeLabel:'低级',scope:'gun',scopeLabel:'枪械',role:'power',roleLabel:'火力',available:true},
    {grade:'medium',gradeLabel:'中等',scope:'gun',scopeLabel:'枪械',role:'utility',roleLabel:'功能',
        available:false,reason:'material_missing'}
]);
equal(tree.children.map(node => node.id), ['grade','scope','role','status'], 'mod filter branches');
equal(Model.modMatchesFilter({grade:'medium'}, ['grade','medium']), true, 'mod grade filter match');
equal(Model.modMatchesFilter({grade:'low'}, ['grade','medium']), false, 'mod grade filter reject');

console.log('Equipment tuning model ' + checks + '/' + checks + ' passed');
