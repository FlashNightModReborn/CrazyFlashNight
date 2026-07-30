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
