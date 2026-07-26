#!/usr/bin/env node
'use strict';

const assert = require('assert');
const Library = require('../launcher/web/modules/skills-library.js');
const Trainer = require('../launcher/web/modules/skills-trainer.js');
const Loadout = require('../launcher/web/modules/skills-loadout.js');
const Interactions = require('../launcher/web/modules/skills-interactions.js');
const Presenter = require('../launcher/web/modules/skills-render.js');
const Diagnostics = require('../launcher/web/modules/skills-diagnostics.js');

let checks = 0;
function equal(actual, expected, message) {
    assert.deepStrictEqual(actual, expected, message);
    checks += 1;
}

const learned = [
    {skillKey:'旋风斩', type:'剑术主动', level:2, maxLevel:8, stateHealth:'ok', equippable:true,
        equippedSlots:[2], orderIndex:20},
    {skillKey:'铁布衫', type:'内功被动', level:1, maxLevel:5, stateHealth:'ok', passive:true,
        equippable:false, enabled:true, equippedSlots:[], orderIndex:10},
    {skillKey:'坏数据', type:'科技', level:1, maxLevel:1, stateHealth:'duplicate', writeBlocked:true,
        equippable:false, equippedSlots:[], orderIndex:30}
];
const trainerEntries = [
    {skillKey:'闪现', type:'超能力', currentLevel:0, maxLevel:10, stateHealth:'ok', equippable:true},
    {skillKey:'剑气', type:'剑术', currentLevel:10, maxLevel:10, stateHealth:'ok', equippable:true}
];
const snapshot = {
    learned,
    trainer:{entries:trainerEntries},
    loadout:[
        {slot:1, skillKey:'旋风斩', stateHealth:'ok', writeBlocked:false},
        {slot:2, skillKey:'', stateHealth:'ok', writeBlocked:false},
        {slot:3, skillKey:'遗留', stateHealth:'unknown', writeBlocked:false}
    ]
};

equal(Library.sourceEntries(snapshot, 'manage'), learned, 'manage source');
equal(Library.sourceEntries(snapshot, 'trainer'), trainerEntries, 'trainer source');
equal(Library.entryByKey(snapshot, 'manage', '铁布衫'), learned[1], 'lookup by opaque skill key');
equal(Library.visibleEntries(snapshot, 'manage', '', Library.emptyFilterPaths()).map(x => x.skillKey),
    ['铁布衫','旋风斩','坏数据'], 'authoritative order index');
equal(Library.visibleEntries(snapshot, 'manage', '剑术', Library.emptyFilterPaths()).map(x => x.skillKey),
    ['旋风斩'], 'query covers type');
equal(Library.visibleEntries(snapshot, 'manage', '', {form:['passive'],status:[],school:[]}).map(x => x.skillKey),
    ['铁布衫'], 'composable form facet');
equal(Library.visibleEntries(snapshot, 'trainer', '', {form:[],status:['unlearned'],school:[]}).map(x => x.skillKey),
    ['闪现'], 'trainer status facet');
equal(Library.filterDefinitions('trainer').map(x => x.label), ['形态','学习','流派'], 'view-specific labels');
equal(Library.reorderBlockReason(learned[0], 'source', {writesDisabled:false,easyMode:false}),
    'equipped_skill_locked', 'normal-mode equipped source lock');
equal(Library.reorderBlockReason(learned[0], 'source', {writesDisabled:false,easyMode:true}),
    '', 'easy-mode source can reorder');
equal(Library.reorderBlockReason(learned[0], 'target', {writesDisabled:false,easyMode:true}),
    'equipped_skill_locked', 'equipped target remains locked');
equal(Library.healthLabel(learned[2], 'manage'), '重复', 'duplicate health label');
equal(Library.compactStateLabel(learned[1], 'manage'), 'ON', 'compact passive state');

equal(Trainer.affordableMaxLevel({currentLevel:1,maxLevel:10,upgradeSP:30}, 160), 6,
    'available SP caps the target at the highest affordable level');
equal(Trainer.affordableMaxLevel({currentLevel:1,maxLevel:10,upgradeSP:30}, 20), 1,
    'insufficient SP leaves no learned-skill upgrade target');
equal(Trainer.affordableMaxLevel({currentLevel:2,maxLevel:10,upgradeSP:0}, 0), 10,
    'zero-cost upgrades keep the metadata maximum');
equal(Trainer.affordableMaxLevel({currentLevel:0,maxLevel:20,upgradeSP:30}, 0), 1,
    'initial learn remains fixed to level one');
equal(Trainer.initialDesiredLevel({currentLevel:0,maxLevel:20,upgradeSP:30}, 0), 1, 'initial learn fixed to one');
equal(Trainer.initialDesiredLevel({currentLevel:4,maxLevel:5,upgradeSP:10}, 10), 5, 'next affordable learned level');
equal(Trainer.initialDesiredLevel({currentLevel:4,maxLevel:10,upgradeSP:10}, 0), 4,
    'no affordable upgrade keeps the current level as a non-target state');
equal(Trainer.normalizedDesiredLevel({currentLevel:4,maxLevel:10,upgradeSP:10}, 99, 30), 7,
    'desired level upper clamp uses the affordable maximum');
equal(Trainer.normalizedDesiredLevel({currentLevel:4,maxLevel:10,upgradeSP:10}, 2, 30), 5,
    'desired level lower clamp keeps the next affordable level');
equal(Trainer.targetMarkLevels(1, 6), [1,2,3,4,5,6], 'short range shows every mark');
equal(Trainer.targetMarkLevels(2, 20), [2,5,10,15,20], 'long range uses five-level landmarks');
const preview = {skillKey:'闪现', desiredLevel:1, canCommit:true, learnToken:'opaque'};
equal(Trainer.previewMatches(preview, trainerEntries[0], 1), true, 'preview intent matches');
equal(Trainer.hasFreshPreviewToken({preview,desiredLevel:1,receivedAt:1000,
    config:{previewTokenFreshMs:5000}}, trainerEntries[0], 5999), true, 'token inside freshness window');
equal(Trainer.hasFreshPreviewToken({preview,desiredLevel:1,receivedAt:1000,
    config:{previewTokenFreshMs:5000}}, trainerEntries[0], 6000), false, 'freshness boundary is strict');
equal(Trainer.previewDebounceMs({previewDebounceMs:0}), 0, 'zero debounce supported in harness');
equal(Trainer.previewTokenFreshMs({previewTokenFreshMs:40000}), 25000, 'unsafe token window rejected');

equal(Loadout.slotByNumber(snapshot, '2'), snapshot.loadout[1], 'numeric slot lookup');
equal(Loadout.moveBlockReason(snapshot.loadout[0], snapshot.loadout[1], false), '', 'valid slot move');
equal(Loadout.moveBlockReason(snapshot.loadout[0], snapshot.loadout[2], false), 'slot_locked',
    'unknown target blocks move');
equal(Loadout.equipPlan(learned[0], snapshot.loadout[1],
    {mode:'safe',revision:7,writesDisabled:false}).direct, true, 'safe mode still fills empty slot directly');
const replacePlan = Loadout.equipPlan(learned[0],
    {slot:4,skillKey:'闪现',writeBlocked:false}, {mode:'safe',revision:7,writesDisabled:false});
equal({direct:replacePlan.direct,replacing:replacePlan.replacingSkill,payload:replacePlan.payload},
    {direct:false,replacing:true,payload:{skillKey:'旋风斩',slot:4,expectedRevision:7}},
    'safe replacement produces confirmation plan');
equal(Loadout.unequipPlan(snapshot.loadout[0], {mode:'fast',revision:9,writeBlocked:false}),
    {allowed:true,direct:true,payload:{slot:1,expectedRevision:9}}, 'fast unload plan');
const storage = {value:'fast',getItem(){return this.value;},setItem(_,value){this.value=value;}};
equal(Loadout.readConfirmationMode(storage, 'key'), 'fast', 'read confirmation preference');
equal(Loadout.writeConfirmationMode(storage, 'key', 'invalid'), 'safe', 'invalid preference normalizes safe');
equal(storage.value, 'safe', 'normalized preference persisted');

equal(Interactions.skillOffer(learned[0], false),
    {subjectKind:'skill',sourceRef:{skillKey:'旋风斩',equippable:true}}, 'skill drag offer');
equal(Interactions.quickSlotOffer(snapshot.loadout[0]),
    {subjectKind:'quick_slot',sourceRef:{slot:1,skillKey:'旋风斩'}}, 'quick-slot drag offer');
equal(Interactions.probeEquip(Interactions.skillOffer(learned[0], false), snapshot.loadout[1], false),
    {accepted:true,operationId:'equip_skill',targetRef:{slot:2}}, 'equip drop intent');
equal(Interactions.probeMove(Interactions.quickSlotOffer(snapshot.loadout[0]), snapshot.loadout[1],
    number => Loadout.slotByNumber(snapshot, number), false),
    {accepted:true,operationId:'move_quick_slot',targetRef:{sourceSlot:1,targetSlot:2}}, 'slot move intent');
equal(Interactions.probeReorder(Interactions.skillOffer(learned[1], false), learned[0],
    key => Library.entryByKey(snapshot, 'manage', key), () => ''),
    {accepted:true,operationId:'reorder_skill',targetRef:{skillKey:'旋风斩',targetIndex:20}},
    'library reorder intent');
equal(Interactions.rejectMessage('equipped_skill_locked'), '已装备技能需先卸载，才能交换列表顺序。',
    'shared rejection language');

equal(Diagnostics.redact({
    trainerSession:'secret',
    nested:{learnToken:'opaque', keep:'visible'},
    rows:[{sessionNonce:'hidden', reason:'ok'}]
}), {nested:{keep:'visible'},rows:[{reason:'ok'}]}, 'diagnostics recursively remove capabilities');
const record = Diagnostics.buildRecord({
    reason:'malformed', view:'trainer', selectedKey:'闪现', trainerExpired:true,
    coordinator:{panelInstanceId:'panel.1',state:'needs_reconcile',lastAppliedWriteEpoch:3,
        mux:{pendingCount:2},activeWrite:{callId:'write.1'}},
    snapshot:{revision:8,diagnostics:[{learnToken:'secret',code:'bad_row'}]}
});
equal({
    reason:record.reason,view:record.view,selectedSkill:record.selectedSkill,
    trainerExpired:record.trainerExpired,pendingCount:record.pendingCount,
    diagnostics:record.snapshotDiagnostics
}, {
    reason:'malformed',view:'trainer',selectedSkill:'闪现',
    trainerExpired:true,pendingCount:2,diagnostics:[{code:'bad_row'}]
}, 'diagnostic record is stable and capability-free');
assert.throws(() => Presenter.create(null), /explicit state and intent ports/);
checks += 1;

console.log('Skills UI modules ' + checks + '/' + checks + ' passed');
