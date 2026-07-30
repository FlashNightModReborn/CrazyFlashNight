'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Pages = require('../launcher/web/modules/npcshop-secondary-pages.js');

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

test('presenters reject missing explicit ports before touching authority', () => {
    assert.throws(() => new Pages.SettlementPresenter({}), /document, components, and host/);
    assert.throws(() => new Pages.HelpPresenter({}), /document, components, and host/);
    assert.throws(() => new Pages.SpaceOrganizerPresenter({}), /presentation adapters and host/);
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

process.stdout.write('NPC secondary pages: ' + passed + '/' + passed + ' passed\n');
