'use strict';

const assert = require('assert');
const Projection = require(
    '../launcher/web/modules/character-build/character-build-projection.js');

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

check('equipment and drug selectors map without guessing', function() {
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'weapon', id:'手雷'}),
        {kind:'equipment', slotKey:'手雷'});
    assert.deepStrictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug4'}),
        {kind:'drug', drugSlot:3});
    assert.strictEqual(
        Projection.targetForSelection({kind:'drug', id:'drug5'}),
        null);
});

process.stdout.write(
    'Character Build projection: ' + passed + '/' + passed + ' passed\n');
