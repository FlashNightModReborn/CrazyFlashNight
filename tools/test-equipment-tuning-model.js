#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
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

equal(Model.wireRef(candidates[1]), {
    sourceKind:'inventory',containerId:'背包',slot:3,expectedLease:'lease.target'
}, 'wire ref uses the exact four-key inventory authority shape');
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
equal(Model.diagnosticAuthoritySourceKey({
    sourceKind:'inventory',containerId:'背包',slot:2,expectedLease:'lease.source'
}), 'inventory:背包:2:lease.source', 'inventory diagnostic identity includes the exact authority lease');
equal(Model.diagnosticAuthoritySourceKey({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'颈部装备',expectedLoadoutRevision:9
}), 'loadout:17:颈部装备:9', 'loadout diagnostic identity includes the exact authority revision');
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
equal(Model.tuningSourceSupports({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}, 'enhance'), true, 'loadout source admits first-round single-item tuning');
equal(Model.tuningSourceSupports({
    sourceKind:'loadout',sessionGeneration:17,slotKey:'长枪',expectedLoadoutRevision:9
}, 'convert'), true, 'loadout source admits a backpack-target enhancement exchange');
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
equal(Model.errorMessage('level_locked'), '调制后的装备需要更高角色等级。',
    'loadout post-state level rejection has a specific player-facing message');

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
const diffPresentations = [
    {itemName:'rule.old',displayName:'旧件展示名',icon:'旧件图标'},
    {itemName:'rule.new',displayName:'新件展示名',icon:'新件图标'}
];
equal(Model.equipmentDiff(
    {level:5,tier:'I',mods:['rule.old']},
    {level:7,tier:'II',mods:['rule.new']},
    diffPresentations),
    '+5 → +7 · I → II · 卸下 旧件展示名 · 安装 新件展示名',
    'equipment delta resolves internal mod rules through canonical display identities');
equal(Model.equipmentDiff(
    {level:5,tier:'I',mods:['secret.internal.old']},
    {level:5,tier:'I',mods:['secret.internal.new']},
    diffPresentations),
    '卸下 未知配件 · 安装 未知配件',
    'unknown mod rules use one neutral label without leaking internal identity');
equal(Model.commitLabel({operation:'enhance',after:{source:{equipment:{level:8}}},
    materials:[{itemName:'强化石',delta:-3}]}), '强化至 +8 · 3 强化石', 'enhancement commit label');
equal(Model.commitLabel({operation:'detach_all_mods'}), '卸下全部配件', 'non-enhance commit label');

const statsDeltaChanged = Model.statsDeltaRows(
    [{key:'damage',label:'伤害加成',value:10},{key:'hp',label:'HP',value:50}],
    [{key:'damage',label:'伤害加成',value:10.4},{key:'hp',label:'HP',value:50}]);
equal(statsDeltaChanged.length, 1, 'stats delta filters unchanged rows');
equal(statsDeltaChanged[0].key, 'damage', 'stats delta row key');
equal(statsDeltaChanged[0].direction, 'better', 'higher damage reads as better');
equal(Math.abs(statsDeltaChanged[0].delta - 0.4) < 1e-9, true, 'stats delta numeric delta');
equal(Model.statsDeltaRows(
    [{key:'weight',label:'重量',value:5}],
    [{key:'weight',label:'重量',value:3}])[0].direction, 'better',
    'lower-is-better stat dropping reads as better');
equal(Model.statsDeltaRows(
    [{key:'weight',label:'重量',value:3}],
    [{key:'weight',label:'重量',value:5}])[0].direction, 'worse',
    'lower-is-better stat rising reads as worse');
equal(Model.statsDeltaRows(
    [{key:'fireRate',label:'射速（发/秒）',value:10}],
    [{key:'fireRate',label:'射速（发/秒）',value:12.9}])[0].direction, 'better',
    'runtime fire rate rising reads as better');
equal(Model.statsDeltaRows(
    [{key:'level',label:'等级限制',value:1}],
    [{key:'level',label:'等级限制',value:12}])[0].direction, 'neutral',
    'level requirement change stays neutral');
const statsDeltaAdded = Model.statsDeltaRows(
    [],
    [{key:'vampirism',label:'吸血',value:3}]);
equal(statsDeltaAdded.length === 1
    && statsDeltaAdded[0].before === null && statsDeltaAdded[0].after === 3
    && statsDeltaAdded[0].direction === 'better', true,
    'added stat row reports null before with better direction');
const statsDeltaRemoved = Model.statsDeltaRows(
    [{key:'vampirism',label:'吸血',value:3}],
    []);
equal(statsDeltaRemoved.length === 1
    && statsDeltaRemoved[0].before === 3 && statsDeltaRemoved[0].after === null
    && statsDeltaRemoved[0].direction === 'worse', true,
    'removed stat row reports null after with worse direction');
equal(Model.statsDeltaRows(null, undefined), [], 'stats delta tolerates missing inputs');
equal(Model.statsDeltaRows(
    [{key:'hp',label:'HP',value:50}],
    [{key:'damage',label:'伤害加成',value:10},{key:'hp',label:'HP',value:60}]).map(r => r.key),
    ['damage','hp'], 'stats delta keeps after-row order with removed rows trailing');

equal(Model.modStatus({available:false,reason:'material_missing'}).id, 'material_missing',
    'authoritative unavailable reason maps to filter state');
const tree = Model.buildModFilterTree([
    {grade:'low',gradeLabel:'低级',scope:'gun',scopeLabel:'枪械',role:'power',roleLabel:'火力',available:true,owned:2},
    {grade:'medium',gradeLabel:'中等',scope:'gun',scopeLabel:'枪械',role:'utility',roleLabel:'功能',
        available:false,reason:'material_missing',owned:0}
]);
equal(tree.children.map(node => node.id), ['ownership','grade','scope','role','status'], 'mod filter branches include ownership first');
equal(Model.defaultModFilterPath(), ['ownership','owned'], 'mod catalog defaults to owned candidates');
equal(Model.modMatchesFilter({owned:1}, ['ownership','owned']), true, 'owned filter includes held mods');
equal(Model.modMatchesFilter({owned:0}, ['ownership','owned']), false, 'owned filter excludes catalog-only mods');
equal(Model.modMatchesFilter({grade:'medium'}, ['grade','medium']), true, 'mod grade filter match');
equal(Model.modMatchesFilter({grade:'low'}, ['grade','medium']), false, 'mod grade filter reject');
equal(
    Model.modSlotCapacityProjection({modSlotCapacity:4}, 1),
    {state:'known',value:4},
    'plugin capacity accepts the authoritative four-slot equipment projection'
);
equal(
    Model.modSlotCapacityProjection({modSlotCapacity:0}, 0),
    {state:'known',value:0},
    'authoritative zero means no plugin slots'
);
equal(
    Model.modSlotCapacityProjection({}, 1),
    {state:'absent',value:null},
    'missing capacity stays absent instead of inferring from installed plugins'
);
equal(
    Model.modSlotCapacityProjection({modSlotCapacity:1}, 2),
    {state:'malformed',value:null},
    'installed plugins beyond capacity fail closed'
);
equal(
    Model.modSlotCapacityProjection({modSlotCapacity:'4'}, 1),
    {state:'malformed',value:null},
    'capacity does not coerce a non-authoritative string'
);
equal(
    Model.modSlotCapacityProjection({
        modSlotCapacity:Model.MAX_VISIBLE_MOD_SLOT_CAPACITY + 1
    }, 0),
    {state:'malformed',value:null},
    'pathological authority capacity fails closed before unbounded DOM projection'
);

const tuningServiceBytes = fs.readFileSync(path.join(
    __dirname,
    '..',
    'scripts',
    '类定义',
    'org',
    'flashNight',
    'arki',
    'item',
    'EquipmentTuningService.as'
));
equal(
    Array.from(tuningServiceBytes.subarray(0, 3)),
    [0xEF, 0xBB, 0xBF],
    'AS2 tuning service keeps its mandatory UTF-8 BOM'
);
const tuningServiceSource = tuningServiceBytes.toString('utf8');
const equipmentProjectionSource = (
    tuningServiceSource.match(
        /private static function buildEquipmentProjection[\s\S]*?\r?\n    }\r?\n/
    ) || []
)[0] || '';
equal(
    /projectionProbe:BaseItem = new BaseItem\([\s\S]*?ObjectUtil\.clone\(value\)[\s\S]*?projectionProbe\.getData\(\)[\s\S]*?data\.data\.modslot/.test(
        equipmentProjectionSource
    ),
    true,
    'AS2 tuning projection derives plugin capacity from the projected equipment value'
);
equal(
    /modSlotCapacityKnown:Boolean = data != null[\s\S]*?data\.data\.hasOwnProperty\("modslot"\)[\s\S]*?data\.data\.modslot != undefined/.test(
        equipmentProjectionSource
    ),
    true,
    'AS2 tuning snapshot treats an absent modslot field as unknown'
);
equal(
    /isNaN\(rawModSlotCapacity\)[\s\S]*?Number\.POSITIVE_INFINITY[\s\S]*?Number\.NEGATIVE_INFINITY[\s\S]*?rawModSlotCapacity < 0[\s\S]*?Math\.floor\(rawModSlotCapacity\) != rawModSlotCapacity/.test(
        equipmentProjectionSource
    )
        && !/rawModSlotCapacity\s*>\s*3/.test(equipmentProjectionSource),
    true,
    'AS2 tuning snapshot accepts any finite nonnegative integer without a UI-owned slot cap'
);
equal(
    /if \(modSlotCapacityKnown\)[\s\S]*?projection\.modSlotCapacity = modSlotCapacity/.test(
        equipmentProjectionSource
    ),
    true,
    'AS2 tuning snapshot emits capacity only from a known valid authority value'
);
equal(
    /if \(includeStats\)[\s\S]*?projection\.stats = EquipmentStatProjector\.project/.test(
        equipmentProjectionSource
    )
        && /buildEquipmentProjection\(source\.item, afterSource, source\.item\.lastUpdate, true\)/.test(
            tuningServiceSource
        ),
    true,
    'AS2 tuning preview projects structured stats rows for before/after comparison'
);
equal(
    /buildCandidateStatPreview\(candidate, params\)/.test(tuningServiceSource)
        && /response\.statsBefore = statPreview\.before/.test(tuningServiceSource),
    true,
    'AS2 tuning tooltip attaches candidate stat preview rows when source is present'
);

const tuningServiceTestBytes = fs.readFileSync(path.join(
    __dirname,
    '..',
    'scripts',
    '类定义',
    'org',
    'flashNight',
    'arki',
    'item',
    'EquipmentTuningServiceTest.as'
));
equal(
    Array.from(tuningServiceTestBytes.subarray(0, 3)),
    [0xEF, 0xBB, 0xBF],
    'AS2 tuning service test keeps its mandatory UTF-8 BOM'
);
const tuningServiceTestSource = tuningServiceTestBytes.toString('utf8');
const malformedModSlotFixturePatterns = [
    /name:"测试负数槽手枪"[\s\S]*?modslot:-1/,
    /name:"测试小数槽手枪"[\s\S]*?modslot:1\.5/,
    /name:"测试非数值槽手枪"[\s\S]*?modslot:"not-a-number"/,
    /name:"测试NaN槽手枪"[\s\S]*?modslot:Number\("not-a-number"\)/,
    /name:"测试正无穷槽手枪"[\s\S]*?modslot:Number\.POSITIVE_INFINITY/,
    /name:"测试负无穷槽手枪"[\s\S]*?modslot:Number\.NEGATIVE_INFINITY/
];
const malformedModSlotReplayPatterns = [
    /getRawItemData\("测试负数槽手枪"\)\.data\.modslot\s*=\s*-1/,
    /getRawItemData\("测试小数槽手枪"\)\.data\.modslot\s*=\s*1\.5/,
    /getRawItemData\("测试非数值槽手枪"\)\.data\.modslot\s*=\s*[\s\S]*?"not-a-number"/,
    /getRawItemData\("测试NaN槽手枪"\)\.data\.modslot\s*=\s*[\s\S]*?Number\("not-a-number"\)/,
    /getRawItemData\("测试正无穷槽手枪"\)\.data\.modslot\s*=\s*[\s\S]*?Number\.POSITIVE_INFINITY/,
    /getRawItemData\("测试负无穷槽手枪"\)\.data\.modslot\s*=\s*[\s\S]*?Number\.NEGATIVE_INFINITY/
];
equal(
    /female\.snapshot\.equipment\.modSlotCapacity == 4/.test(
        tuningServiceTestSource
    )
        && /delete ItemUtil\.getRawItemData\("测试未知槽手枪"\)\.data\.modslot/.test(
            tuningServiceTestSource
        )
        && /!unknown\.snapshot\.equipment\.hasOwnProperty\("modSlotCapacity"\)/.test(
            tuningServiceTestSource
        )
        && malformedModSlotFixturePatterns.every(function(pattern) {
            return pattern.test(tuningServiceTestSource);
        })
        && malformedModSlotReplayPatterns.every(function(pattern) {
            return pattern.test(tuningServiceTestSource);
        })
        && /malformedSlots:Array = \[2, 3, 4, 5, 6, 7\]/.test(
            tuningServiceTestSource
        )
        && /var malformedCurrentOmitted:Boolean = malformed\.success[\s\S]*?!malformed\.snapshot\.equipment\.hasOwnProperty\([\s\S]*?"modSlotCapacity"\)/.test(
            tuningServiceTestSource
        )
        && /malformedCapacityOmitted\s*=\s*[\s\S]*?malformedCurrentOmitted && malformedCapacityOmitted/.test(
            tuningServiceTestSource
        ),
    true,
    'AS2 regression covers four authoritative slots and omits missing or malformed capacities'
);

console.log('Equipment tuning model ' + checks + '/' + checks + ' passed');
