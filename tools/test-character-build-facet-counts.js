'use strict';

const assert = require('assert');
const FacetCounts = require('../launcher/web/modules/character-build/character-build-facet-counts.js');

let passed = 0;
function check(name, callback) {
    callback();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}
function facet(id, count, children) {
    return {id:id, label:id, order:0, count:count, children:children || []};
}
function projection() {
    return {
        scope:'all',
        filterFacets:[
            facet('armor', 2, [
                facet('头部装备', 2)
            ]),
            facet('weapon', 4, [
                facet('手枪', 2, [facet('自动手枪', 2)]),
                facet('手枪2', 1, [facet('特殊副手', 1)]),
                facet('刀', 1)
            ]),
            facet('consumable', 3, [
                facet('手雷', 1),
                facet('药剂', 2)
            ])
        ],
        filterItemCount:9
    };
}

check('valid all-scope facet projection is known', function() {
    const model = FacetCounts.normalize(projection());
    assert.strictEqual(model.known, true);
    assert.strictEqual(model.total, 9);
});
check('armor target consumes exact use count', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'armor', '头部装备'),
        2);
});
check('known missing use projects explicit zero', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'armor', '脚部装备'),
        0);
});
check('secondary pistol mirrors pistol alias and exact secondary use', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'weapon', '手枪2'),
        3);
});
check('primary pistol does not consume secondary-only use', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'weapon', '手枪'),
        2);
});
check('grenade count can come from stack taxonomy', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'weapon', '手雷'),
        1);
});
check('all four drug slots consume the same candidate category', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'drug', 'drug4'),
        2);
});
check('missing projection is unknown rather than zero', function() {
    const model = FacetCounts.normalize(null);
    assert.strictEqual(model.known, false);
    assert.strictEqual(FacetCounts.countForTarget(model, 'weapon', '刀'), null);
});
check('unknown and zero have different visible and accessible copy', function() {
    assert.strictEqual(FacetCounts.badgeText(null), '—');
    assert.strictEqual(FacetCounts.badgeText(0), '0');
    assert.strictEqual(FacetCounts.accessibleText(null), '背包候选数量暂不可用');
    assert.strictEqual(FacetCounts.accessibleText(0), '背包候选 0 个');
});
check('wrong scope fails closed', function() {
    const value = projection();
    value.scope = 'equipment';
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('extra field fails closed', function() {
    const value = projection();
    value.extra = true;
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('root count mismatch fails closed', function() {
    const value = projection();
    value.filterItemCount = 8;
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('child count above parent fails closed', function() {
    const value = projection();
    value.filterFacets[0].children[0].count = 3;
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('duplicate sibling id fails closed', function() {
    const value = projection();
    value.filterFacets[0].children.push(facet('头部装备', 0));
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('control characters fail closed', function() {
    const value = projection();
    value.filterFacets[0].children[0].id = '头部\u0001装备';
    assert.strictEqual(FacetCounts.normalize(value).known, false);
});
check('normalization does not mutate authority payload', function() {
    const value = projection();
    const before = JSON.stringify(value);
    FacetCounts.normalize(value);
    assert.strictEqual(JSON.stringify(value), before);
});

process.stdout.write(
    'Character Build facet counts: ' + passed + '/' + passed + ' passed\n');
