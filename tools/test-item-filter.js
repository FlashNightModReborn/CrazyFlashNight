#!/usr/bin/env node
'use strict';

const assert = require('assert');
const path = require('path');
const ItemFilter = require(path.resolve(__dirname, '..', 'launcher', 'web', 'modules', 'item-filter.js'));

const items = [
    {majorType:'武器', use:'长枪', weaponType:'突击步枪', setId:'service_rifle', setName:'制式武器套装'},
    {majorType:'武器', use:'长枪', weaponType:'霰弹枪', setId:'service_rifle', setName:'制式武器套装'},
    {majorType:'武器', use:'刀', actionType:'刀剑'},
    {majorType:'消耗品', use:'材料'},
    {majorType:'收集品', use:'材料'}
];

const tree = ItemFilter.build(items, item => ItemFilter.catalogPath(item));
assert.deepStrictEqual(tree.children.map(node => node.id), ['weapon', 'consumable', 'collection']);
assert.strictEqual(ItemFilter.nodeAt(tree, ['weapon']).count, 3);
assert.strictEqual(ItemFilter.nodeAt(tree, ['weapon', '长枪']).count, 2);
assert.strictEqual(ItemFilter.nodeAt(tree, ['weapon', '长枪', '突击步枪']).count, 1);
assert.deepStrictEqual(ItemFilter.validPath(tree, ['weapon', '不存在']), ['weapon']);
assert.strictEqual(ItemFilter.matchesPath(items[0], ['weapon', '长枪'], item => ItemFilter.catalogPath(item)), true);
assert.strictEqual(ItemFilter.matchesPath(items[3], ['collection'], item => ItemFilter.catalogPath(item)), false);

const setTree = ItemFilter.buildSetTree(items);
assert.strictEqual(setTree.count, 2);
assert.strictEqual(ItemFilter.nodeAt(setTree, ['service_rifle']).count, 2);
assert.strictEqual(ItemFilter.matchesPath(items[0], ['service_rifle'], ItemFilter.setPath), true);
assert.strictEqual(ItemFilter.matchesPath(items[2], ['service_rifle'], ItemFilter.setPath), false);

const hydrated = ItemFilter.fromFacets(tree.children, tree.count);
assert.strictEqual(ItemFilter.nodeAt(hydrated, ['collection', '材料']).count, 1);
assert.strictEqual(hydrated.count, 5);

const exhaustedSelection = ItemFilter.fromFacets([], 0);
const selectedLeaf = ItemFilter.ensurePath(exhaustedSelection, ['consumable', '消耗品'],
    (id, index) => index === 0 ? '消耗品' : id);
assert.strictEqual(selectedLeaf.path.join('/'), 'consumable/消耗品');
assert.strictEqual(selectedLeaf.count, 0);
assert.deepStrictEqual(ItemFilter.validPath(exhaustedSelection, ['consumable', '消耗品']),
    ['consumable', '消耗品']);
assert.strictEqual(exhaustedSelection.count, 0);

const manual = ItemFilter.manualSections([
    {id:'featured', label:'精选', entries:[1, 2]},
    {id:'supplies', label:'补给', entries:[3]}
], 5);
assert.deepStrictEqual(manual.children.map(node => node.path.join('/')), ['featured', 'supplies']);
assert.deepStrictEqual(manual.children.map(node => node.count), [2, 1]);

const branches = ItemFilter.branchTree([
    {id:'category', label:'类别', tree:tree},
    {id:'curated', label:'专柜', tree:manual}
], items.length);
assert.deepStrictEqual(branches.children.map(node => node.path.join('/')), ['category', 'curated']);
assert.strictEqual(ItemFilter.nodeAt(branches, ['category', 'weapon', '刀']).count, 1);
assert.strictEqual(ItemFilter.nodeAt(branches, ['curated', 'featured']).count, 2);

const orderedSetTree = ItemFilter.buildSetTree([
    {setId:'late_set', setName:'后序套装', setOrder:20},
    {setId:'early_set', setName:'前序套装', setOrder:10}
]);
const orderedBranches = ItemFilter.branchTree([
    {id:'set', label:'套装', tree:orderedSetTree}
], 2);
assert.deepStrictEqual(orderedBranches.children[0].children.map(node => node.id), ['early_set', 'late_set']);
assert.deepStrictEqual(orderedBranches.children[0].children.map(node => node.order), [10, 20]);

const singleUseTree = ItemFilter.build([
    {majorType:'武器', use:'长枪', weaponType:'突击步枪'},
    {majorType:'武器', use:'长枪', weaponType:'霰弹枪'}
], item => ItemFilter.catalogPath(item));
assert.deepStrictEqual(ItemFilter.expandSingleChildren(singleUseTree, ['weapon']), ['weapon', '长枪']);

const multiItems = [
    {name:'多用途材料', paths:[
        [{id:'type',label:'类型',order:0},{id:'general',label:'通用材料',order:2}],
        [{id:'purpose',label:'用途',order:1},{id:'recipe',label:'合成配方',order:0},
            {id:'recipe:武器合成',label:'武器合成',order:4}],
        // An identical authored membership must not inflate any node count.
        [{id:'purpose',label:'用途',order:1},{id:'recipe',label:'合成配方',order:0},
            {id:'recipe:武器合成',label:'武器合成',order:4}]
    ]},
    {name:'改装材料', paths:[
        [{id:'type',label:'类型',order:0},{id:'equipment_mod',label:'改装材料',order:0},
            {id:'grade',label:'档级',order:0},{id:'high',label:'高等',order:2}],
        [{id:'type',label:'类型',order:0},{id:'equipment_mod',label:'改装材料',order:0},
            {id:'scope',label:'适用范围',order:1},{id:'firearm',label:'枪械',order:1}],
        [{id:'purpose',label:'用途',order:1},{id:'direct',label:'直接系统用途',order:1},
            {id:'system:equipment_tuning',label:'装备改装',order:0}]
    ]},
    // Repeated logical identity contributes paths but never a duplicate count.
    {name:'多用途材料', paths:[
        [{id:'purpose',label:'用途',order:1},{id:'direct',label:'直接系统用途',order:1},
            {id:'system:equipment_tuning',label:'装备改装',order:0}]
    ]}
];
const multiTree = ItemFilter.buildMany(multiItems, item => item.paths, item => item.name);
assert.strictEqual(multiTree.count, 2);
assert.deepStrictEqual(multiTree.children.map(node => node.id), ['type', 'purpose']);
assert.strictEqual(ItemFilter.nodeAt(multiTree, ['type']).count, 2);
assert.strictEqual(ItemFilter.nodeAt(multiTree, ['purpose']).count, 2);
assert.strictEqual(ItemFilter.nodeAt(multiTree, ['purpose', 'recipe', 'recipe:武器合成']).count, 1);
assert.strictEqual(ItemFilter.nodeAt(multiTree,
    ['purpose', 'direct', 'system:equipment_tuning']).count, 2);
assert.strictEqual(ItemFilter.nodeAt(multiTree, ['type', 'equipment_mod']).count, 1);
assert.strictEqual(ItemFilter.matchesAnyPath(multiItems[0],
    ['purpose', 'recipe'], item => item.paths), true);
assert.strictEqual(ItemFilter.matchesAnyPath(multiItems[0],
    ['type', 'equipment_mod'], item => item.paths), false);
assert.strictEqual(ItemFilter.matchesAnyPath(multiItems[1], [], item => item.paths), true);

console.log('item-filter model 37/37 passed');
