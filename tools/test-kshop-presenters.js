#!/usr/bin/env node
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const ItemFilter = require('../launcher/web/modules/item-filter.js');
const Catalog = require('../launcher/web/modules/kshop-catalog-presenter.js');
const Cart = require('../launcher/web/modules/kshop-cart-controller.js');
const Tooltip = require('../launcher/web/modules/kshop-tooltip-presenter.js');
const Owned = require('../launcher/web/modules/kshop-owned-inventory-presenter.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write(`ok ${passed} - ${name}\n`);
}

const catalog = [
    {idx:1, item:'knife', displayname:'短刀', majorType:'武器', subType:'刀', type:'常规', level:5, price:20},
    {idx:2, item:'potion', displayname:'药剂', majorType:'消耗品', subType:'药剂', type:'补给', level:1, price:3},
    {idx:3, item:'badge', displayname:'徽章', majorType:'收集品', subType:'套装', type:'专柜', level:1, price:8,
        setId:'vanguard', setName:'先遣队'}
];

test('catalog stackability is domain-specific', () => {
    assert.strictEqual(Catalog.isStackable(catalog[0]), false);
    assert.strictEqual(Catalog.isStackable(catalog[1]), true);
    assert.strictEqual(Catalog.isStackable(catalog[2]), true);
});

test('catalog lock combines forward and reverse levels', () => {
    assert.strictEqual(Catalog.isLocked(catalog[0], 3, 1), true);
    assert.strictEqual(Catalog.isLocked(catalog[0], 3, 2), false);
});

test('catalog lookup accepts numeric wire ids without owning the array', () => {
    assert.strictEqual(Catalog.findCatalogItem(catalog, '2'), catalog[1]);
    assert.strictEqual(Catalog.findCatalogItem(catalog, 99), null);
});

test('catalog tree exposes category, set and curated branches', () => {
    const tree = Catalog.buildCategoryTree(catalog, ItemFilter);
    assert.deepStrictEqual(tree.children.map(node => node.id), ['category', 'set', 'curated']);
    assert.strictEqual(tree.count, 3);
});

test('catalog matcher handles root, category, set and curated paths', () => {
    assert.strictEqual(Catalog.matchesCategory(catalog[0], [], ItemFilter), true);
    assert.strictEqual(Catalog.matchesCategory(catalog[0], ['category', 'weapon'], ItemFilter), true);
    assert.strictEqual(Catalog.matchesCategory(catalog[2], ['set'], ItemFilter), true);
    assert.strictEqual(Catalog.matchesCategory(catalog[1], ['curated', '补给'], ItemFilter), true);
    assert.strictEqual(Catalog.matchesCategory(catalog[0], ['curated', '补给'], ItemFilter), false);
});

test('catalog activation is single-click add while drag remains an independent offer path', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'kshop-catalog-presenter.js'), 'utf8');
    assert.match(source, /dispatchAdd\(item, 'single_click'\)/);
    assert.doesNotMatch(source, /addEventListener\('dblclick'/);
    assert.match(source, /consumeDragClick/);
});

test('settlement edit gate does not overwrite QuantityControl bounds', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'kshop-views.js'), 'utf8');
    assert.match(source, /remove\.disabled = !editable/);
    assert.doesNotMatch(source, /querySelectorAll\('button'\)[\s\S]{0,160}disabled = !editable/);
});

test('cart payload is normalized and detached from authority state', () => {
    const source = [{idx:'2', qty:'4'}];
    const payload = Cart.buildPayload(source);
    assert.deepStrictEqual(payload, [{idx:2, qty:4}]);
    payload[0].qty = 9;
    assert.strictEqual(source[0].qty, '4');
});

test('cart add merges stackables and rejects duplicate singles', () => {
    assert.deepStrictEqual(Cart.addItem([{idx:2, qty:2}], 2, 3, true).cart, [{idx:2, qty:5}]);
    const duplicate = Cart.addItem([{idx:1, qty:1}], 1, 1, false);
    assert.strictEqual(duplicate.changed, false);
    assert.strictEqual(duplicate.error, 'duplicate_single');
});

test('cart quantity changes are immutable and remove at zero', () => {
    const source = [{idx:2, qty:2}];
    const adjusted = Cart.adjustItem(source, 2, -2, false);
    assert.deepStrictEqual(adjusted.cart, []);
    assert.deepStrictEqual(source, [{idx:2, qty:2}]);
    assert.deepStrictEqual(Cart.setItemQuantity(source, 2, 7).cart, [{idx:2, qty:7}]);
});

test('cart totals ignore catalog entries that disappeared', () => {
    assert.strictEqual(Cart.quantity([{idx:1, qty:2}, {idx:2, qty:4}]), 6);
    assert.strictEqual(Cart.total([{idx:2, qty:4}, {idx:99, qty:8}], id => Catalog.findCatalogItem(catalog, id)), 12);
});

test('checkout preview requires the complete v1 authority envelope', () => {
    const valid = {success:true, v:1, checkoutToken:'token', purchaseLines:[], canCommit:true,
        total:3, balance:10, projectedBalance:7, blockingError:''};
    assert.strictEqual(Cart.validPreview(valid), true);
    assert.strictEqual(Cart.validPreview({...valid, checkoutToken:''}), false);
    assert.strictEqual(Cart.validPreview({...valid, projectedBalance:'bad'}), false);
});

test('cart controller emits replacement intent and never owns authority', () => {
    let authority = [];
    let dirty = 0;
    const controller = new Cart.CartController({
        state:{
            getCart:() => authority,
            findCatalogItem:id => Catalog.findCatalogItem(catalog, id),
            isStackable:Catalog.isStackable,
            isLocked:() => false,
            canEdit:() => true,
            canStartWrite:() => true
        },
        intent:{
            replaceCart:next => { authority = next; },
            markDirty:() => { dirty++; },
            refreshControls:() => {},
            toast:() => {}, playCue:() => {}
        }
    });
    assert.strictEqual(controller.addCatalogIntent(2, 3), true);
    assert.deepStrictEqual(authority, [{idx:2, qty:3}]);
    assert.strictEqual(dirty, 1);
    controller.adjust(2, -1, false);
    assert.deepStrictEqual(authority, [{idx:2, qty:2}]);
    assert.strictEqual(dirty, 2);
});

test('owned slot refs preserve lease and physical identity', () => {
    assert.deepStrictEqual(Owned.ownedSlotRef('背包', {
        physicalSlot:'4', slotLease:'lease-4', occupied:true, item:{name:'药剂'}
    }), {containerId:'背包', slot:4, expectedLease:'lease-4', occupied:true, item:{name:'药剂'}});
});

test('owned snapshot presentation distinguishes lock, filter and capacity', () => {
    assert.deepStrictEqual(Owned.presentationForSnapshot('战备箱', {
        accessibleCapacity:0, filterKey:'all', slots:[], capacity:0
    }), {emptyText:'战备箱尚未解锁', meta:'未解锁'});
    assert.deepStrictEqual(Owned.presentationForSnapshot('背包', {
        accessibleCapacity:3, filterKey:'weapon', slots:[{occupied:true}, {occupied:false}], capacity:20
    }), {emptyText:'当前分类暂无物品', meta:'1 / 20'});
});

test('tooltip keys naturally invalidate on lease changes', () => {
    const slot = {physicalSlot:7, slotLease:'a'};
    assert.strictEqual(Tooltip.ownedTooltipKey('背包', slot), '背包:7:a');
    slot.slotLease = 'b';
    assert.strictEqual(Tooltip.ownedTooltipKey('背包', slot), '背包:7:b');
});

test('tooltip fact models normalize sparse projections', () => {
    assert.deepStrictEqual(Tooltip.catalogBasicFacts({displayname:'短刀', level:0}, true), {
        name:'短刀', type:'', subtype:'', level:'0', price:'0', locked:true
    });
    assert.deepStrictEqual(Tooltip.ownedBasicFacts({name:'药剂', quantity:'3', enhancementLevel:'0'}), {
        name:'药剂', type:'物品', quantity:3, enhancementLevel:0
    });
});

test('tooltip balance metadata is confirmed-only and player-facing', () => {
    const html = Tooltip.balanceMetaHtml({balanceSummary:{
        state:'confirmed', weightLayers:2, formula:1, level:20
    }});
    assert.match(html, /同级加权/);
    assert.match(html, /◆\+2/);
    assert.doesNotMatch(html, /DPS|合成强化|balance-tooltip-(?:label|dps|tags)/);
    assert.strictEqual(Tooltip.balanceMetaHtml({balanceSummary:{state:'review', weightLayers:8, formula:1, level:20}}), '');
    assert.strictEqual(Tooltip.balanceMetaHtml({balanceSummary:{state:'confirmed', weightLayers:'unknown', formula:1, level:20}}), '');
    assert.strictEqual(Tooltip.balanceMetaHtml({balanceSummary:{state:'confirmed', weightLayers:2, formula:2, level:20}}), '');
    assert.strictEqual(Tooltip.balanceMetaHtml({balanceSummary:{state:'confirmed', weightLayers:2, formula:1, level:20, averageDPS:88.04}}), '');
});

test('presenter modules contain no mux, bridge or authority coordinator', () => {
    const moduleNames = [
        'kshop-catalog-presenter.js', 'kshop-cart-controller.js',
        'kshop-tooltip-presenter.js', 'kshop-owned-inventory-presenter.js'
    ];
    for (const name of moduleNames) {
        const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', name), 'utf8');
        assert.doesNotMatch(source, /KShopRequestMux|KShopWriteCoordinator|InventoryCoordinator|Bridge\.send/);
    }
});

test('facade initializes after the documented module load order', () => {
    const Runtime = require('../launcher/web/modules/kshop-runtime.js');
    const InventoryRuntime = require('../launcher/web/modules/inventory-runtime.js');
    let registration = null;
    Object.assign(global, {
        KShopRequestMux:Runtime.KShopRequestMux,
        KShopWriteCoordinator:Runtime.KShopWriteCoordinator,
        InventoryRuntime,
        KShopCatalogPresenter:Catalog,
        KShopCartController:Cart,
        KShopTooltipPresenter:Tooltip,
        KShopOwnedInventoryPresenter:Owned,
        Panels:{register:(id, contract) => { registration = {id, contract}; }}
    });
    const facadePath = require.resolve('../launcher/web/modules/kshop.js');
    delete require.cache[facadePath];
    require(facadePath);
    assert.strictEqual(registration.id, 'kshop');
    assert.strictEqual(typeof registration.contract.create, 'function');
    assert.strictEqual(typeof registration.contract.onOpen, 'function');
    for (const key of ['KShopRequestMux', 'KShopWriteCoordinator', 'InventoryRuntime',
        'KShopCatalogPresenter', 'KShopCartController', 'KShopTooltipPresenter',
        'KShopOwnedInventoryPresenter', 'Panels']) delete global[key];
});

test('KShop facade stays below the physical slimming gate', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'kshop.js'), 'utf8');
    assert.ok(source.split(/\r?\n/).length < 1200);
    assert.doesNotMatch(source, /function (renderCatalogCard|bindCatalogTooltip|renderOwnedSlot|renderCartRow|requestCheckoutPreview)\s*\(/);
});

process.stdout.write(`KShop presenter tests passed: ${passed}/${passed}\n`);
