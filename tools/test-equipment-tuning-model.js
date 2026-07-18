#!/usr/bin/env node
'use strict';

const assert = require('assert');
const Model = require('../launcher/web/modules/equipment-tuning-model.js');

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
