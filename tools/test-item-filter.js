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

console.log('item-filter model 26/26 passed');
