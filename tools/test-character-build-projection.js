'use strict';

const assert = require('assert');
const Projection = require(
    '../launcher/web/modules/character-build/character-build-projection.js');
const DropTargets = require(
    '../launcher/web/modules/loadout-picker/loadout-picker-drop-policy.js');

let passed = 0;
function check(name, callback) {
    callback();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}

function equipmentRow(slotKey, name) {
    return {
        slotKey:slotKey,
        occupied:true,
        quantity:1,
        disabled:false,
        item:{
            name:name,
            displayName:name,
            itemKind:'equipment',
            majorType:'武器',
            use:slotKey,
            enhancementLevel:2,
            quantity:1
        }
    };
}

check('snapshot projection preserves authoritative facets by reference', function() {
    const facets = {
        scope:'all',
        filterFacets:[],
        filterItemCount:0
    };
    const view = Projection.viewSnapshot({
        equipment:[equipmentRow('长枪', '测试长枪')],
        drugs:[],
        portrait:{gender:'男'},
        candidateFacets:facets,
        stateHealth:'ok'
    });
    assert.strictEqual(view.candidateFacets, facets);
    assert.strictEqual(view.equipment['长枪'].name, '测试长枪');
    assert.strictEqual(view.equipment['长枪'].tunable, true);
    assert.strictEqual(view.blocked, false);
});

check('legacy snapshot omission remains unknown input', function() {
    assert.strictEqual(Projection.viewSnapshot({
        equipment:[],
        drugs:[],
        stateHealth:'ok'
    }).candidateFacets, null);
});

check('cooling potion slots stay selectable and reserve blocking for data failure', function() {
    const view = Projection.viewSnapshot({
        equipment:[],
        drugs:[{
            slot:0,bank:0,lane:0,active:true,keyLabel:'7',
            ready:false,totalSteps:90,currentStep:30,
            progressPercent:33,animationFrame:34,remainingMs:2000,
            occupied:true,quantity:2,
            item:{name:'测试药剂',displayName:'测试药剂',itemKind:'stack',
                majorType:'消耗品',use:'药剂',quantity:2}
        }],
        portrait:{},stateHealth:'ok'
    });
    assert.strictEqual(view.drugs.drug1.blocked, false);
    assert.strictEqual(view.drugMeta.drug1.ready, false);

    const unavailable = Projection.viewSnapshot({
        equipment:[],
        drugs:[{
            slot:0,bank:0,lane:0,active:true,keyLabel:'7',
            ready:true,totalSteps:0,currentStep:0,
            progressPercent:100,animationFrame:1,remainingMs:0,
            occupied:true,quantity:2,disabled:true,
            item:{name:'损坏药剂槽',displayName:'损坏药剂槽',itemKind:'stack',
                majorType:'消耗品',use:'药剂',quantity:2}
        }],
        portrait:{},stateHealth:'degraded'
    });
    assert.strictEqual(unavailable.drugs.drug1.blocked, true);
});

check('candidate projection keeps stable physical-slot lease key', function() {
    const rows = Projection.viewCandidates({
        candidates:[{
            physicalSlot:9,
            disabled:false,
            source:{expectedLease:'lease.9'},
            item:{
                name:'候选',
                displayName:'候选',
                itemKind:'equipment',
                use:'长枪'
            }
        }]
    });
    assert.strictEqual(rows[0].key, 'backpack:9:lease.9');
    assert.strictEqual(rows[0].raw.physicalSlot, 9);
});

check('incompatible backpack rows stay inspectable but expose player-facing blocking copy', function() {
    const rows = Projection.viewCandidates({
        candidates:[{
            physicalSlot:4,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{expectedLease:'lease.4'},
            item:{
                name:'测试药剂',
                displayName:'测试药剂',
                itemKind:'stack',
                use:'药剂',
                quantity:2
            }
        }]
    });
    assert.strictEqual(rows[0].blocked, true);
    assert.strictEqual(
        rows[0].blockedReason,
        '与当前槽位不兼容；可查看说明，但不能装备。');
    assert.strictEqual(rows[0].summary, rows[0].blockedReason);
    assert.strictEqual(rows[0].raw.blockedReason, 'incompatible_item');
});

check('one authoritative equipment backpack is reprojected across slots without mutating wire rows', function() {
    const payload = {
        target:{kind:'equipment',slotKey:'长枪'},
        candidateScope:'backpack',
        candidates:[{
            physicalSlot:4,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{expectedLease:'lease.4'},
            item:{name:'候选刀',displayName:'候选刀',itemKind:'equipment',use:'刀'},
            equipmentEligibility:{slots:['刀'],blockedReason:''}
        },{
            physicalSlot:5,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{expectedLease:'lease.5'},
            item:{name:'高阶手枪',displayName:'高阶手枪',itemKind:'equipment',use:'手枪'},
            equipmentEligibility:{slots:['手枪','手枪2'],blockedReason:'level_locked'}
        },{
            physicalSlot:6,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{expectedLease:'lease.6'},
            item:{name:'材料',displayName:'材料',itemKind:'stack',use:'材料'},
            equipmentEligibility:{slots:[],blockedReason:''}
        }]
    };
    const blade = Projection.viewCandidates(payload, {kind:'equipment',slotKey:'刀'});
    assert.strictEqual(blade[0].blocked, false);
    assert.strictEqual(blade[1].raw.blockedReason, 'incompatible_item');
    assert.strictEqual(blade[2].raw.blockedReason, 'incompatible_item');
    const handgun = Projection.viewCandidates(
        payload, {kind:'equipment',slotKey:'手枪2'});
    assert.strictEqual(handgun[0].raw.blockedReason, 'incompatible_item');
    assert.strictEqual(handgun[1].raw.blockedReason, 'level_locked');
    assert.strictEqual(handgun[1].blocked, true);
    assert.strictEqual(payload.candidates[0].blockedReason, 'incompatible_item');
    assert.strictEqual(payload.candidates[1].blockedReason, 'incompatible_item');
});

check('neutral backpack overview preserves authoritative cross-slot rows and overview copy', function() {
    const payload = {
        target:{kind:'backpack'},
        candidateScope:'backpack',
        candidates:[{
            physicalSlot:2,
            disabled:false,
            blockedReason:'',
            source:{expectedLease:'lease.2'},
            item:{name:'候选刀',displayName:'候选刀',itemKind:'equipment',use:'刀'},
            equipmentEligibility:{slots:['刀'],blockedReason:''}
        },{
            physicalSlot:3,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{expectedLease:'lease.3'},
            item:{name:'测试材料',displayName:'测试材料',itemKind:'stack',use:'材料'},
            equipmentEligibility:{slots:[],blockedReason:''}
        }]
    };
    const rows = Projection.viewCandidates(payload, {kind:'backpack'});
    assert.strictEqual(rows[0].blocked, false);
    assert.strictEqual(rows[0].delta, '总览');
    assert(rows[0].summary.indexOf('拖到高亮栏位') >= 0);
    assert.strictEqual(rows[0].raw, payload.candidates[0]);
    assert.strictEqual(rows[1].blocked, true);
    assert(rows[1].blockedReason.indexOf('不能用于角色构筑') >= 0);
});

check('backpack item-use action stays selectable without weakening equipment source shape', function() {
    const wire = {
        target:{kind:'backpack'},
        candidateScope:'backpack',
        backpackVersion:12,
        candidates:[{
            physicalSlot:7,
            disabled:true,
            blockedReason:'incompatible_item',
            source:{containerId:'背包',slot:7,expectedLease:'equip.7'},
            useAction:{command:'open',label:'打开',source:{
                physicalSlot:7,slotLease:'use.7',itemName:'福袋',backpackVersion:12
            }},
            useBlockedReason:'',
            item:{name:'福袋',displayName:'福袋',itemKind:'stack',use:'礼包'}
        }]
    };
    const rows = Projection.viewCandidates(wire, {kind:'backpack'});
    assert.strictEqual(rows[0].blocked, false);
    assert.deepStrictEqual(rows[0].useAction, {command:'open',label:'打开'});
    assert.strictEqual(rows[0].raw.source, wire.candidates[0].source);
    assert.strictEqual(rows[0].raw.useAction.source.slotLease, 'use.7');
});

check('blocked potion use remains inspectable with a player-facing lane reason', function() {
    const payload = {
        target:{kind:'backpack'},candidateScope:'backpack',
        candidates:[{
            physicalSlot:8,disabled:true,blockedReason:'incompatible_item',
            source:{containerId:'背包',slot:8,expectedLease:'equip.8'},
            useAction:{command:'consume',label:'服用',source:{
                physicalSlot:8,slotLease:'use.8',itemName:'测试药剂',backpackVersion:2
            }},
            useBlockedReason:'no_available_lane',
            item:{name:'测试药剂',displayName:'测试药剂',itemKind:'stack',use:'药剂'}
        }]
    };
    const row = Projection.viewCandidates(payload, {kind:'backpack'})[0];
    assert.strictEqual(row.blocked, false);
    assert.strictEqual(row.useAction.command, 'consume');
    assert(row.useBlockedReason.indexOf('四条药剂通道当前都不能承接') >= 0);
    assert.strictEqual(row.summary, row.useBlockedReason);
});

check('backpack, equipment and drug selectors map without guessing', function() {
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'backpack'}),
        {kind:'backpack'});
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'weapon', id:'手雷'}),
        {kind:'equipment', slotKey:'手雷'});
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug4'}),
        {kind:'drug', drugSlot:3});
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug5'}),
        {kind:'drug', drugSlot:4});
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug8'}),
        {kind:'drug', drugSlot:7});
    assert.strictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug9'}),
        null);
});

check('neutral overview derives exact equipment and drug drop targets without a selected slot', function() {
    const slots = [
        {rovingKey:'weapon:刀',kind:'weapon',id:'刀'},
        {rovingKey:'weapon:长枪',kind:'weapon',id:'长枪'},
        {rovingKey:'weapon:手枪',kind:'weapon',id:'手枪'},
        {rovingKey:'weapon:手枪2',kind:'weapon',id:'手枪2'},
        {rovingKey:'drug:drug1',kind:'drug',id:'drug1'},
        {rovingKey:'drug:drug2',kind:'drug',id:'drug2'},
        {rovingKey:'drug:drug3',kind:'drug',id:'drug3'},
        {rovingKey:'drug:drug4',kind:'drug',id:'drug4'},
        {rovingKey:'drug:drug5',kind:'drug',id:'drug5'},
        {rovingKey:'drug:drug6',kind:'drug',id:'drug6'},
        {rovingKey:'drug:drug7',kind:'drug',id:'drug7'},
        {rovingKey:'drug:drug8',kind:'drug',id:'drug8'}
    ];
    const blade = {blocked:false,raw:{item:{itemKind:'equipment',use:'刀'},
        equipmentEligibility:{slots:['刀'],blockedReason:''}}};
    const drug = {blocked:false,raw:{item:{itemKind:'stack',use:'药剂',quantity:3},
        equipmentEligibility:{slots:[],blockedReason:''}}};
    const material = {blocked:true,raw:{item:{itemKind:'stack',use:'材料',quantity:2},
        equipmentEligibility:{slots:[],blockedReason:''}}};
    const handgun = {blocked:false,raw:{item:{itemKind:'equipment',use:'手枪'},
        equipmentEligibility:{slots:['手枪','手枪2'],blockedReason:''}}};
    assert.deepStrictEqual(
        DropTargets.resolve('backpack', '', blade, slots).slots,
        ['weapon:刀']);
    assert.deepStrictEqual(
        DropTargets.resolve('backpack', '', drug, slots).slots,
        ['drug:drug1','drug:drug2','drug:drug3','drug:drug4',
            'drug:drug5','drug:drug6','drug:drug7','drug:drug8']);
    assert.deepStrictEqual(
        DropTargets.resolve('backpack', '', material, slots).slots,
        []);
    assert.deepStrictEqual(
        DropTargets.resolve('compatible', 'weapon:手枪', handgun, slots).slots,
        ['weapon:手枪','weapon:手枪2']);
    assert.deepStrictEqual(
        DropTargets.resolve('compatible', 'drug:drug1', drug, slots).slots,
        ['drug:drug1','drug:drug2','drug:drug3','drug:drug4',
            'drug:drug5','drug:drug6','drug:drug7','drug:drug8']);
    assert.deepStrictEqual(
        DropTargets.resolve('compatible', 'weapon:长枪',
            {blocked:false,raw:{item:{itemKind:'equipment',use:'长枪'}}}, slots).slots,
        ['weapon:长枪']);
});

process.stdout.write(
    'Character Build projection: ' + passed + '/' + passed + ' passed\n');
