'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Pages = require('../launcher/web/modules/npcshop-secondary-pages.js');
const Runtime = require('../launcher/web/modules/npcshop-runtime.js');

let passed = 0;
function test(name, fn) {
    fn(); passed++; process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

test('settlement view model exposes ready commit without inventing authority state', () => {
    const model = Pages.settlementViewModel({canCommit:true, saleLines:[]}, {}, error => 'E:' + error);
    assert.deepStrictEqual(model, {
        status:'整单可提交',
        context:'待购和待售都只是清单；点击“确认交易”后整单才会一次生效。',
        organizeVisible:false, organizeDisabled:false, commitBusy:false,
        canCommit:true, commitState:'ready'
    });
});

test('inventory-full presentation blocks commit and offers organizer', () => {
    const model = Pages.settlementViewModel({blockingError:'inventory_full', canCommit:false},
        {busy:true}, error => error === 'inventory_full' ? '背包空间不足。' : error);
    assert.strictEqual(model.status, '背包空间不足。');
    assert.strictEqual(model.organizeVisible, true);
    assert.strictEqual(model.organizeDisabled, true);
    assert.strictEqual(model.commitState, 'blocked');
    assert(model.context.includes('重新核算'));
});

test('bulk-sale protection copy wins over generic settlement copy', () => {
    const model = Pages.settlementViewModel({saleLines:[{scope:'same_name'}]}, {}, String);
    assert(model.context.includes('自动保护'));
});

test('space status is a deterministic projection of inventory authority state', () => {
    assert.strictEqual(Pages.spaceStatus({returning:true, ready:true}), '重新核对中…');
    assert.strictEqual(Pages.spaceStatus({spaceBusy:true, ready:true}), '准备整理空间…');
    assert.strictEqual(Pages.spaceStatus({refreshRequired:true, ready:true}), '同步失败');
    assert.strictEqual(Pages.spaceStatus({busyOwner:'inventory.autoTransfer', ready:true}), '转移中…');
    assert.strictEqual(Pages.spaceStatus({ready:true}), '点击快速转移');
    assert.strictEqual(Pages.spaceStatus({ready:false}), '同步中…');
});

test('owned panes expose exact inspectable lock reasons for every NPC authority state', () => {
    assert.deepStrictEqual(Pages.ownedInteraction({ready:true}),
        {inspectable:true, actionable:true, reason:''});
    [
        [{ready:false}, '库存正在同步，请稍候。'],
        [{ready:true, busyOwner:'inventory.autoTransfer'}, '库存正在处理另一项操作。'],
        [{ready:true, refreshRequired:true}, '库存同步失败，请先重试。'],
        [{ready:true, transactionBusy:true}, '交易正在由游戏确认。'],
        [{ready:true, reconcileRequired:true}, '商店状态需要重新同步。'],
        [{ready:true, spaceBusy:true}, '正在载入或核对整理空间。'],
        [{ready:true, returning:true}, '正在重新核对商店与库存。'],
        [{ready:true, readOnly:true}, '此栏仅供查看，不能加入待售。']
    ].forEach(([state, reason]) => {
        assert.deepStrictEqual(Pages.ownedInteraction(state),
            {inspectable:true, actionable:false, reason});
    });
});

test('owned tooltip binding returns its lifecycle handle and keeps the exact NPC source', () => {
    let bindingOptions = null, requested = null;
    const binding = {destroy:function() { return true; }};
    const returned = Pages.bindOwnedTooltip({
        node:{id:'bag-slot'}, viewId:'bag',
        slot:{occupied:true, physicalSlot:7, slotLease:'lease.bag.7',
            item:{name:'内部名', displayName:'展示名', icon:'图标名'}},
        tooltip:{bindAsyncHover:function(node, options) {
            assert.strictEqual(node.id, 'bag-slot'); bindingOptions = options; return binding;
        }},
        cache:{}, renderBasic:function() {}, renderRich:function() {},
        request:function(cmd, payload) { requested = {cmd, payload}; }
    });
    assert.strictEqual(returned, binding);
    assert.strictEqual(bindingOptions.key, 'bag:lease.bag.7');
    bindingOptions.fetch(bindingOptions.item, function() {});
    assert.deepStrictEqual(requested, {cmd:'tooltip', payload:{source:{
        containerId:'背包', slot:7, expectedLease:'lease.bag.7'
    }}});
});

test('settlement inspection reuses line identity and exact bag lease without changing the protocol', () => {
    const purchase = Pages.settlementInspection('purchase', {
        catalogIndex:4, itemName:'purchase.internal', displayName:'购入展示名',
        icon:'purchase.icon', itemKind:'equipment'
    }, {item:{majorType:'武器', use:'长枪'}});
    assert.strictEqual(purchase.viewId, 'catalog');
    assert.deepStrictEqual({
        name:purchase.slot.item.name,
        displayName:purchase.slot.item.displayName,
        icon:purchase.slot.item.icon,
        majorType:purchase.slot.item.majorType
    }, {name:'purchase.internal', displayName:'购入展示名', icon:'purchase.icon', majorType:'武器'});
    assert.strictEqual(purchase.slot.collectionKey, 'purchase.internal');

    const sale = Pages.settlementInspection('sale', {
        sourceIdentity:'bag:9', itemName:'sale.internal', displayName:'售出展示名',
        icon:'sale.icon', itemKind:'stack'
    }, {item:{quantity:3}, source:{containerId:'背包', slot:9, expectedLease:'lease.sale.9'}});
    assert.strictEqual(sale.viewId, 'bag');
    assert.strictEqual(sale.slot.physicalSlot, 9);
    assert.strictEqual(sale.slot.slotLease, 'lease.sale.9');
    assert.strictEqual(sale.slot.item.quantity, 3);

    const material = Pages.settlementInspection('sale', {
        sourceIdentity:'material:铁矿', itemName:'material.internal', displayName:'铁矿',
        icon:'material.icon', itemKind:'stack'
    }, {item:{quantity:8}, source:{viewId:'material', key:'铁矿', expectedLease:'lease.material.1'}});
    assert.strictEqual(material.viewId, 'material');
    assert.strictEqual(material.slot.collectionKey, '铁矿');
    assert.strictEqual(material.slot.slotLease, 'lease.material.1');
});

test('presenters reject missing explicit ports before touching authority', () => {
    assert.throws(() => new Pages.SettlementPresenter({}), /document, components, and host/);
    assert.throws(() => new Pages.HelpPresenter({}), /document, components, and host/);
    assert.throws(() => new Pages.SpaceOrganizerPresenter({}), /presentation adapters and host/);
});

test('physical Inventory adapter owns initial windows while preserving the current request', () => {
    let coordinator = null, applied = 0, callbackResult = null, physicalOptions = null;
    function FakeCoordinator(options) {
        this.options = options; this.resets = []; this.closed = 0; this.opened = 0;
        coordinator = this;
    }
    FakeCoordinator.prototype.close = function() { this.closed++; };
    FakeCoordinator.prototype.resetWindow = function(containerId, offset, limit, filterKey) {
        this.resets.push({containerId, offset, limit, filterKey}); return true;
    };
    const sourceSurface = {capacity:290, slots:[{physicalSlot:0}]};
    FakeCoordinator.prototype.open = function(callback) {
        this.opened++; callback({success:true, surface:sourceSurface});
    };
    const request = function() {};
    const adapter = Runtime.createPhysicalInventoryAdapter({
        inventoryRuntime:{InventoryCoordinator:FakeCoordinator,
            readPhysicalInventorySurface:function(actualRequest, options) {
                assert.strictEqual(actualRequest, request); physicalOptions = options; return 'call.1';
            }},
        request, owner:{panelInstanceId:'panel.npc.current'},
        onStateChange:function() {}, onApplied:function(result) {
            applied++; assert.strictEqual(result.success, true);
        }
    });
    assert.strictEqual(adapter.refresh(result => { callbackResult = result; }), true);
    assert.deepStrictEqual(coordinator.options.requests, [
        {containerId:'背包', offset:0, limit:50, filterKey:'all'},
        {containerId:'战备箱', offset:0, limit:40, filterKey:'all'}
    ]);
    assert.deepStrictEqual(coordinator.resets, []);
    assert.strictEqual(coordinator.closed, 0);
    assert.strictEqual(coordinator.opened, 1);
    assert.strictEqual(applied, 1);
    assert.strictEqual(callbackResult.success, true);
    coordinator.options.readPhysicalSurface(function() { return true; }, function() {});
    assert.strictEqual(physicalOptions.expectedPanel, 'npcshop');
    assert.strictEqual(physicalOptions.expectedPanelInstanceId, 'panel.npc.current');
    const receipt = adapter.getReceipt();
    sourceSurface.slots[0].physicalSlot = 9; receipt.slots[0].physicalSlot = 7;
    assert.strictEqual(adapter.getReceipt().slots[0].physicalSlot, 0);
    adapter.close();
    assert.strictEqual(coordinator.closed, 1);
    assert.strictEqual(adapter.getReceipt(), null);
});

test('physical Inventory adapter resets a new session atomically without changing remembered pages', () => {
    let coordinator = null;
    function FakeCoordinator(options) {
        this.requests = JSON.parse(JSON.stringify(options.requests));
        this.opened = false;
        this.configurations = [];
        coordinator = this;
    }
    FakeCoordinator.prototype.debugState = function() { return {opened:this.opened}; };
    FakeCoordinator.prototype.getRequest = function(containerId) {
        return this.requests.filter(request => request.containerId === containerId)[0] || null;
    };
    FakeCoordinator.prototype.configureRequests = function(requests) {
        if (this.opened) return false;
        this.configurations.push(JSON.parse(JSON.stringify(requests)));
        this.requests = JSON.parse(JSON.stringify(requests));
        return true;
    };
    FakeCoordinator.prototype.close = function() { this.opened = false; };
    FakeCoordinator.prototype.open = function() { this.opened = true; };
    const adapter = Runtime.createPhysicalInventoryAdapter({
        inventoryRuntime:{InventoryCoordinator:FakeCoordinator,
            readPhysicalInventorySurface:function() {}},
        request:function() {}, owner:{panelInstanceId:'panel.npc.reset'}
    });
    coordinator.requests[0] = {containerId:'背包', offset:0, limit:30, filterKey:'consumable',
        filterSpec:{branch:'category', major:'consumable'}};
    coordinator.requests[1] = {containerId:'战备箱', offset:40, limit:20, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon'}};
    assert.strictEqual(adapter.resetSession(), true);
    assert.deepStrictEqual(coordinator.configurations, [[
        {containerId:'背包', offset:0, limit:50, filterKey:'all'},
        {containerId:'战备箱', offset:40, limit:40, filterKey:'all'}
    ]]);
    coordinator.open();
    assert.strictEqual(adapter.resetSession(), false);
    assert.strictEqual(coordinator.configurations.length, 1);
});

test('physical Inventory adapter exposes one factory and rejects incomplete dependencies', () => {
    assert.strictEqual(Runtime.PhysicalInventoryAdapter, undefined);
    assert.throws(() => Runtime.createPhysicalInventoryAdapter({}),
        /physical Inventory dependencies are required/);
});

test('NPC facade delegates all three secondary pages and remains below budget', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop.js'), 'utf8');
    const presenterSource = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop-secondary-pages.js'), 'utf8');
    assert(source.includes('NpcShopSecondaryPages.SettlementPresenter'));
    assert(source.includes('NpcShopSecondaryPages.HelpPresenter'));
    assert(source.includes('NpcShopSecondaryPages.SpaceOrganizerPresenter'));
    assert(source.split(/\r?\n/).length < 1000);
    assert(!source.includes('function renderSettlementLines'));
    assert(!source.includes('function renderSpaceGrid'));
    assert(!/Bridge\.send|RequestMux|InventoryCoordinator/.test(presenterSource), 'presenters must not own transport or authority');
});

test('settlement quantities use the shared number and slider control', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop.js'), 'utf8');
    const presenterSource = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop-secondary-pages.js'), 'utf8');
    assert(presenterSource.includes('new this._components.QuantityControl'));
    assert(presenterSource.includes('onSetQuantity(kind, identity, value, reason)'));
    assert(presenterSource.includes('sliderMax:authorityMaximum'));
    assert(presenterSource.includes('presetMax:effective'));
    assert(presenterSource.includes('this._lineRecords = {purchase:{}, sale:{}}'));
    assert(presenterSource.includes("onSetQuantity:requirePort(options, 'onSetQuantity')"));
    assert(source.includes('onSetQuantity:setIntentQuantity'));
    assert(source.includes("reason === 'maximum'"));
    assert(!presenterSource.includes('onPurchaseMax'));
    assert(!presenterSource.includes('onAdjust'));
});

test('NPC secondary inspection survives write locks and releases every removed binding', () => {
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop.js'), 'utf8');
    const presenterSource = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'npcshop-secondary-pages.js'), 'utf8');
    assert(presenterSource.includes('record.row.tabIndex = 0'));
    assert(presenterSource.includes('record.tooltipBinding = bindOwnedTooltip'));
    assert(presenterSource.includes('if (record.tooltipBinding) record.tooltipBinding.destroy();'));
    assert(presenterSource.includes('this._tooltip.releaseTree(grid)'));
    assert(presenterSource.includes('this._tooltip.releaseTree(this.root)'));
    assert(source.includes('requestTooltip:request'));
    assert(source.includes('tooltip:_tooltipScope || PanelTooltip'));
});

process.stdout.write('NPC secondary pages: ' + passed + '/' + passed + ' passed\n');
