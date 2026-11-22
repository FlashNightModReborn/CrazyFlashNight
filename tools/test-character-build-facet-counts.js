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
check('all eight drug slots consume the same candidate category', function() {
    assert.strictEqual(
        FacetCounts.countForTarget(
            FacetCounts.normalize(projection()), 'drug', 'drug8'),
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
check('backpackCapacity classifies normal, near-full, full and unknown states cleanly', function() {
    const unknown = FacetCounts.backpackCapacity(FacetCounts.normalize(null));
    assert.strictEqual(unknown.known, false);
    assert.strictEqual(unknown.state, 'unknown');
    assert.strictEqual(unknown.value, '— / 50');

    const normal = FacetCounts.backpackCapacity({ known: true, total: 9, useCounts: {} });
    assert.strictEqual(normal.known, true);
    assert.strictEqual(normal.state, 'normal');
    assert.strictEqual(normal.full, false);
    assert.strictEqual(normal.nearFull, false);
    assert.strictEqual(normal.value, '9 / 50');
    assert.strictEqual(normal.remaining, 41);

    const nearFull = FacetCounts.backpackCapacity({ known: true, total: 45, useCounts: {} });
    assert.strictEqual(nearFull.state, 'near-full');
    assert.strictEqual(nearFull.nearFull, true);
    assert.strictEqual(nearFull.full, false);
    assert.strictEqual(nearFull.value, '45 / 50');

    const full = FacetCounts.backpackCapacity({ known: true, total: 50, useCounts: {} });
    assert.strictEqual(full.state, 'full');
    assert.strictEqual(full.full, true);
    assert.strictEqual(full.label, '背包（已满）');
    assert.strictEqual(full.value, '50 / 50');
    assert(full.detail.indexOf('背包已满（50/50）') >= 0);
});
check('syncShellMetric updates workbench backpack metric and attributes', function() {
    const attrs = Object.create(null);
    const metricEl = {
        title: '',
        setAttribute(k, v) { attrs[k] = String(v); }
    };
    const calls = [];
    const fakeShell = {
        setMetric(key, label, value) {
            calls.push({ key, label, value });
            return { parentNode: metricEl };
        }
    };
    const fullProjection = {
        scope: 'all',
        filterFacets: [facet('weapon', 50, [facet('刀', 50)])],
        filterItemCount: 50
    };
    const cap = FacetCounts.syncShellMetric(fakeShell, fullProjection);
    assert.strictEqual(cap.full, true);
    assert.deepStrictEqual(calls, [{ key: 'backpack', label: '背包（已满）', value: '50 / 50' }]);
    assert.strictEqual(attrs['data-capacity-state'], 'full');
    assert(metricEl.title.indexOf('卸下装备前请先整理背包') >= 0);
});

process.stdout.write(
    'Character Build facet counts: ' + passed + '/' + passed + ' passed\n');
