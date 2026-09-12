'use strict';

const assert = require('assert');
const StashSource = require('../launcher/web/modules/inventory-workbench-stash-source.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

function entry(entryId, revision, quantity, item) {
    return {
        entryId:entryId,
        revision:revision,
        quantity:quantity,
        item:item || {name:'n-' + entryId, displayName:'物资 ' + entryId, itemKind:'stack'}
    };
}
function page(offset, total, entries, extra) {
    return Object.assign({
        storeId:'store', revision:7, offset:offset, total:total,
        entries:entries, migrationRequired:false, pendingOperationId:''
    }, extra || {});
}

/** 只模拟冻结接口需要的 ItemUse 面：页面回包由测试手动结清，便于迟到隔离。 */
function fakeItemUse() {
    const f = {
        state:'idle',
        pageCalls:[], pendingPages:[],
        invokeCalls:[], invokeImpl:null,
        tooltipCalls:[], tooltipData:null,
        reconcileCalls:0,
        requestStashPage(offset, callback, spec) {
            f.pageCalls.push({offset:offset, spec:spec});
            f.pendingPages.push(callback);
            return 'page-' + f.pendingPages.length;
        },
        respondPage(index, data, response) {
            const cb = f.pendingPages[index];
            if (!cb) return;
            f.pendingPages[index] = null;
            cb(data, response);
        },
        respondLastPage(data, response) {
            for (let i = f.pendingPages.length - 1; i >= 0; i--) {
                if (f.pendingPages[i]) { f.respondPage(i, data, response); return; }
            }
        },
        invokeStash(command, fields, callback) {
            f.invokeCalls.push({command:command, fields:fields});
            f.takeCallback = callback;
            if (f.invokeImpl) return f.invokeImpl(command, fields, callback);
            return 'invoke-' + f.invokeCalls.length;
        },
        requestStashTooltip(storeId, row, callback) {
            f.tooltipCalls.push({storeId:storeId, row:row});
            callback(f.tooltipData);
            return 'tooltip-' + f.tooltipCalls.length;
        },
        reconcile() { f.reconcileCalls++; return 'reconcile-call'; },
        debugState() { return {state:f.state}; }
    };
    return f;
}

function sourceOf(f, events) {
    return StashSource.create({itemUse:f, onChange:(s, snap) => events.push({state:s, snap:snap})});
}

test('纯空权威页原样采用且绝不发写', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    let got;
    assert.strictEqual(source.refresh((snap, resp) => { got = {snap:snap, resp:resp}; }), 'page-1');
    f.respondLastPage(page(0, 0, [], {storeId:'', revision:0}));
    const snap = source.getSnapshot();
    assert(snap, 'empty page must adopt');
    assert.strictEqual(got.snap, snap);
    assert.strictEqual(snap.storeId, '');
    assert.strictEqual(snap.revision, 0);
    assert.deepStrictEqual(snap.slots, []);
    assert.strictEqual(snap.capacity, 0);
    assert.strictEqual(source.getState().ready, true);
    assert.strictEqual(source.getState().loading, false);
    assert.strictEqual(f.invokeCalls.length, 0, 'read path must never issue writes');
    source.destroy();
});

test('migrationRequired/pendingOperationId 原样进入快照且不自动迁移', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 0, [], {storeId:'', revision:0,
        migrationRequired:true, pendingOperationId:'op.9'}));
    const snap = source.getSnapshot();
    assert(snap);
    assert.strictEqual(snap.migrationRequired, true);
    assert.strictEqual(snap.pendingOperationId, 'op.9');
    assert.strictEqual(f.invokeCalls.length, 0, 'no auto stashMigrate from the adapter');
    source.destroy();
});

test('有数据缺 storeId 的坏页被拒绝且旧快照不被吞掉', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 1, [entry('e1', 1, 4)]));
    const good = source.getSnapshot();
    assert(good);
    let got;
    source.refresh((snap, resp) => { got = {snap:snap, resp:resp}; });
    f.respondLastPage({storeId:'', revision:0, offset:0, total:1, entries:[entry('x', 1, 1)]},
        {success:true});
    assert.strictEqual(got.snap, null, 'failed adopt reports null snapshot');
    assert.strictEqual(source.getSnapshot(), good, 'old snapshot stays the same reference');
    assert.strictEqual(source.getState().error, 'invalid_response');
    source.destroy();
});

test('默认 {major:"all"} 显式上线换取全局 facet，切筛选归零页', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    assert.deepStrictEqual(f.pageCalls[0].spec, {major:'all'});
    f.respondLastPage(page(0, 40, [], {filterSpec:{major:'all'}, filterItemCount:40,
        unfilteredTotal:40, filterFacets:[]}));
    source.setFilter({branch:'category', major:'weapon'}, () => {});
    assert.strictEqual(f.pageCalls[1].offset, 0);
    assert.deepStrictEqual(f.pageCalls[1].spec, {branch:'category', major:'weapon'});
    f.respondLastPage(page(0, 3, [entry('w1', 1, 2)],
        {filterSpec:{branch:'category', major:'weapon'}, filterItemCount:3, unfilteredTotal:40}));
    const snap = source.getSnapshot();
    assert.strictEqual(snap.filterKey, 'weapon');
    assert.strictEqual(snap.unfilteredTotal, 40);
    assert.strictEqual(snap.filterItemCount, 3);
    source.setFilter('not-a-spec', (snap2) => { assert.strictEqual(snap2, null); });
    assert.strictEqual(f.pageCalls.length, 2, 'invalid spec must not issue a request');
    source.destroy();
});

test('跨页请求与 32 项窗口直接落到 requestStashPage offset', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 64, [entry('a', 1, 1)]));
    source.setPage(32, () => {});
    assert.strictEqual(f.pageCalls[1].offset, 32);
    f.respondLastPage(page(32, 64, [entry('b', 1, 1)]));
    assert.strictEqual(source.getSnapshot().offset, 32);
    assert.strictEqual(source.getSnapshot().limit, 32);
    source.destroy();
});

test('迟到回包被 generation 隔离，快照引用不漂移', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    source.setPage(32, () => {});
    const pageB = page(32, 64, [entry('b', 1, 1)]);
    f.respondPage(1, pageB, {success:true});
    const adopted = source.getSnapshot();
    assert.strictEqual(adopted.offset, 32);
    f.respondPage(0, page(0, 64, [entry('a', 1, 1)]), {success:true});
    assert.strictEqual(source.getSnapshot(), adopted, 'stale first response must not adopt');
    source.destroy();
});

test('权威翻空页收敛到最后有效页', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 5, [entry('a', 1, 1)]));
    source.setPage(32, () => {});
    // 权威说 offset32 已空、total 缩到 5：适配器应回读 offset0。
    f.respondLastPage(page(32, 5, []));
    assert.strictEqual(f.pageCalls.length, 3);
    assert.strictEqual(f.pageCalls[2].offset, 0);
    f.respondLastPage(page(0, 5, [entry('a', 1, 1)]));
    assert.strictEqual(source.getSnapshot().offset, 0);
    source.destroy();
});

test('展示行只带真实身份，绝不伪造 physicalSlot/slotLease', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 2, [
        entry('eq', 3, 1, {name:'rifle', displayName:'步枪', itemKind:'equipment'}),
        entry('st', 2, 9, {name:'medkit', displayName:'医疗包', itemKind:'stack'})
    ]));
    const rows = source.getSnapshot().slots;
    assert.strictEqual(rows.length, 2);
    for (const row of rows) {
        assert.strictEqual(row.occupied, true);
        assert.strictEqual(row.containerId, 'stash');
        assert.strictEqual(row.physicalSlot, undefined);
        assert.strictEqual(row.slotLease, undefined);
        assert.strictEqual(typeof row.entryId, 'string');
    }
    assert.strictEqual(source.getRow('st'), rows[1]);
    assert.strictEqual(source.getRow('ghost'), null);
    source.destroy();
});

test('ref 真实身份与数量白名单：equipment 恒 1、数堆 ≤ 当前数', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 2, [
        entry('eq', 3, 1, {name:'rifle', itemKind:'equipment'}),
        entry('st', 2, 9, {name:'medkit', itemKind:'stack'})
    ]));
    const rows = source.getSnapshot().slots;
    assert.deepStrictEqual(source.ref(rows[0]), {entryId:'eq', revision:3, quantity:1});
    assert.strictEqual(source.ref(rows[0], 2), null, 'equipment quantity is pinned to 1');
    assert.deepStrictEqual(source.ref(rows[1]), {entryId:'st', revision:2, quantity:9});
    assert.deepStrictEqual(source.ref(rows[1], 4), {entryId:'st', revision:2, quantity:4});
    for (const bad of [0, -1, 10, 1.5, NaN, 'x', 9007199254740992]) {
        assert.strictEqual(source.ref(rows[1], bad), null, 'rejects ' + bad);
    }
    assert.strictEqual(source.ref({entryId:'ghost', revision:1, quantity:1}), null);
    assert.strictEqual(source.ref({entryId:'st', revision:99, quantity:1}), null,
        'stale revision row rejected');
    source.destroy();
});

test('take 原样走 invokeStash：storeId/expectedRevision/entries 与启动返回透传', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 2, [entry('e1', 1, 5), entry('e2', 4, 1)]));
    const rows = source.getSnapshot().slots;
    const refs = [source.ref(rows[0], 3), source.ref(rows[1])];
    let settled;
    const started = source.take(refs, null, (result, committed) => { settled = {result:result, committed:committed}; });
    assert.strictEqual(started, 'invoke-1');
    const call = f.invokeCalls[0];
    assert.strictEqual(call.command, 'stashTake');
    assert.strictEqual(call.fields.storeId, 'store');
    assert.strictEqual(call.fields.expectedRevision, 7);
    assert.deepStrictEqual(call.fields.entries, [
        {entryId:'e1', revision:1, quantity:3},
        {entryId:'e2', revision:4, quantity:1}
    ]);
    assert.strictEqual(Object.prototype.hasOwnProperty.call(call.fields, 'target'), false);
    const pageCalls = f.pageCalls.length;
    f.takeCallback({success:true, accepted:[{entryId:'e1', quantity:3}], blocked:[]}, true);
    assert.strictEqual(settled.committed, true);
    assert.strictEqual(settled.result.accepted.length, 1);
    assert.strictEqual(f.pageCalls.length, pageCalls,
        'take settle never triggers an adapter-side refresh');
    source.destroy();
});

test('定点 target 严格三字段白名单，仅单行允许', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 2, [entry('e1', 1, 5), entry('e2', 4, 1)]));
    const rows = source.getSnapshot().slots;
    const one = source.ref(rows[0], 2);
    const started = source.take([one], {containerId:'背包', slot:3, expectedLease:'lease-a'}, () => {});
    assert.strictEqual(started, 'invoke-1');
    assert.deepStrictEqual(f.invokeCalls[0].fields.target,
        {containerId:'背包', slot:3, expectedLease:'lease-a'});
    const two = [source.ref(rows[0]), source.ref(rows[1])];
    assert.strictEqual(source.take(two, {containerId:'背包', slot:0, expectedLease:'x'}, () => {}), null,
        'multi-entry take must not carry a target');
    for (const bad of [
        {containerId:'背包', slot:0, expectedLease:'x', extra:1},
        {containerId:'背包', slot:50, expectedLease:'x'},
        {containerId:'背包', slot:-1, expectedLease:'x'},
        {containerId:'背包', slot:1.5, expectedLease:'x'},
        {containerId:'背包', slot:0, expectedLease:''},
        {containerId:'战备箱', slot:0, expectedLease:'x'},
        {slot:0, expectedLease:'x'},
        '背包:0'
    ]) {
        assert.strictEqual(source.take([one], bad, () => {}), null, 'rejects ' + JSON.stringify(bad));
    }
    assert.strictEqual(f.invokeCalls.length, 1, 'rejected takes never reach ItemUse');
    source.destroy();
});

test('take 逐条校验真实身份：幽灵/过期/超量/空批一律不启动', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    assert.strictEqual(source.take([{entryId:'e1', revision:1, quantity:1}], null, () => {}), null,
        'no snapshot yet');
    source.refresh(() => {});
    f.respondLastPage(page(0, 1, [entry('e1', 1, 5)]));
    assert.strictEqual(source.take([], null, () => {}), null);
    assert.strictEqual(source.take([{entryId:'ghost', revision:1, quantity:1}], null, () => {}), null);
    assert.strictEqual(source.take([{entryId:'e1', revision:9, quantity:1}], null, () => {}), null,
        'revision drift rejected');
    assert.strictEqual(source.take([{entryId:'e1', revision:1, quantity:6}], null, () => {}), null,
        'quantity above current rejected');
    const over = [];
    for (let i = 0; i < 33; i++) over.push({entryId:'e1', revision:1, quantity:1});
    assert.strictEqual(source.take(over, null, () => {}), null, 'batch capped at page size');
    assert.strictEqual(f.invokeCalls.length, 0);
    source.destroy();
});

test('needsReconcile 只读 ItemUse 权威状态，reconcile 只做 query 委托', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 1, [entry('e1', 1, 1)]));
    f.state = 'write_pending';
    assert.strictEqual(source.getState().needsReconcile, false);
    f.state = 'needs_reconcile';
    assert.strictEqual(source.getState().needsReconcile, true);
    assert.strictEqual(source.reconcile(), 'reconcile-call');
    assert.strictEqual(f.reconcileCalls, 1);
    // 未知/未决写的恢复只走 ItemUse.reconcile（内部发 stashQuery），适配器不发新写。
    assert.strictEqual(f.invokeCalls.length, 0);
    f.state = 'idle';
    assert.strictEqual(source.getState().needsReconcile, false);
    source.destroy();
});

test('tooltip 委托 exact row 并将原生响应适配为共享注释数据', () => {
    const f = fakeItemUse(); const events = [];
    f.tooltipData = {success:true,tooltip:{iconName:'medkit', introHTML:'<b>x</b>', document:{v:1}}};
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 1, [entry('e1', 1, 1)]));
    const row = source.getSnapshot().slots[0];
    let data = 'unset';
    assert.strictEqual(source.tooltip(row, value => { data = value; }), 'tooltip-1');
    assert.strictEqual(f.tooltipCalls[0].storeId, 'store');
    assert.strictEqual(f.tooltipCalls[0].row, row);
    assert.deepStrictEqual(data, Object.assign({success:true}, f.tooltipData.tooltip));
    let stale = 'unset';
    source.tooltip({entryId:'e1', revision:9, quantity:1, item:{}}, value => { stale = value; });
    assert.strictEqual(stale, null, 'stale row object is not a tooltip source');
    assert.strictEqual(f.tooltipCalls.length, 1);
    source.destroy();
});

test('load 回调至多一次：同步拒绝与重复结清都收敛', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    let calls = 0;
    f.state = 'closed';
    assert.strictEqual(source.refresh(() => { calls++; }), null);
    assert.strictEqual(calls, 1);
    f.state = 'idle';
    source.refresh(() => { calls++; });
    f.respondLastPage(page(0, 1, [entry('e1', 1, 1)]));
    f.respondLastPage(page(0, 1, [entry('e1', 1, 1)]), {success:true});
    assert.strictEqual(calls, 2, 'duplicate settle must not re-fire the caller');
    source.destroy();
});

test('destroy 后迟到回包与操作一律不可采用', () => {
    const f = fakeItemUse(); const events = [];
    const source = sourceOf(f, events);
    source.refresh(() => {});
    f.respondLastPage(page(0, 1, [entry('e1', 1, 1)]));
    const adopted = source.getSnapshot();
    source.refresh(() => {});
    source.destroy();
    f.respondLastPage(page(0, 1, [entry('e1', 2, 1)]));
    assert.strictEqual(source.getSnapshot(), adopted, 'post-destroy adopt forbidden');
    assert.strictEqual(source.take([{entryId:'e1', revision:1, quantity:1}], null, () => {}), null);
    assert.strictEqual(source.destroy(), false);
});

console.log('InventoryWorkbenchStashSource adapter: identity, empty-page, filter, paging, ' +
    'late-response isolation, take target whitelist and reconcile delegation all passed.');
