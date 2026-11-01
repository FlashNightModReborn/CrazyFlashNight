'use strict';

const assert = require('assert');
const Runtime = require('../launcher/web/modules/modifier-runtime.js');

const token = 'modifier.test.1';
const operationId = 'mod.test.1';

function snapshot(overrides) {
    return Object.assign({
        v: 1, operation: 'snapshot', token, success: true, revision: 2, phase: 'editing',
        state: {money: 100, kcoin: 200, maxLevel: 60, inWorld: true, stageActive: 'Active',
            challengeMode: false, saveAvailable: true},
        itemCount: 1, unitCount: 1, itemPageSize: 64, unitPageSize: 24
    }, overrides || {});
}
function items(overrides) {
    return Object.assign({
        v: 1, operation: 'items', token, success: true, revision: 2, query: '', page: 1,
        pageSize: 64, total: 1,
        items: [{id: 1, name: '普通hp药剂', displayName: '普通HP药剂', icon: '普通hp药剂',
            type: '消耗品', use: '药剂'}]
    }, overrides || {});
}
function units(overrides) {
    return Object.assign({
        v: 1, operation: 'units', token, success: true, revision: 2, query: '', page: 1,
        pageSize: 24, total: 1,
        units: [{id: 1, name: '僵尸', spriteName: '敌人-金发女僵尸1', key: '僵尸.金发女',
            level: 2, hostile: true}]
    }, overrides || {});
}
function write(cmd, overrides) {
    return Object.assign({
        v: 1, operation: cmd, token, success: true, revision: 3, operationId,
        message: 'ok'
    }, overrides || {});
}

assert.ok(Runtime.normalizeSnapshot(snapshot(), token));
assert.strictEqual(Runtime.normalizeSnapshot(snapshot({token: 'modifier.other.1'}), token), null);
assert.strictEqual(Runtime.normalizeSnapshot(snapshot({state: {money: -1}}), token), null);
assert.strictEqual(Runtime.normalizeSnapshot(snapshot({phase: 'nope'}), token), null);

assert.ok(Runtime.normalizeItems(items(), token));
assert.strictEqual(Runtime.normalizeItems(items({items: [{id: 1}]}), token), null);
assert.strictEqual(Runtime.normalizeItems(items({pageSize: 1, items: new Array(2).fill(items().items[0])}), token), null);

assert.ok(Runtime.normalizeUnits(units(), token));
assert.strictEqual(Runtime.normalizeUnits(units({units: [{id: 1, name: 'x'}]}), token), null);

assert.ok(Runtime.normalizeWrite(write('grantMoney'), 'grantMoney', token, operationId));
assert.strictEqual(Runtime.normalizeWrite(write('grantMoney', {operationId: 'mod.other.1'}),
    'grantMoney', token, operationId), null);
assert.ok(Runtime.normalizeWrite(write('spawnUnit', {spawned: 3}), 'spawnUnit', token, operationId));
assert.strictEqual(Runtime.normalizeWrite(write('spawnUnit', {spawned: 1.5}), 'spawnUnit', token, operationId), null);
assert.ok(Runtime.normalizeWrite({v: 1, operation: 'query', token, success: false, revision: 2,
    operationId, queriedOperation: operationId, error: 'not_applied', requiresReconcile: false},
    'query', token, operationId));
assert.strictEqual(Runtime.normalizeWrite({v: 1, operation: 'query', token, success: false, revision: 2,
    operationId, queriedOperation: 'mod.other.1', error: 'not_applied'},
    'query', token, operationId), null);
assert.strictEqual(Runtime.normalizeWrite(write('grantMoney', {success: false, error: null}),
    'grantMoney', token, operationId), null);
assert.strictEqual(Runtime.normalizeWrite(write('grantMoney', {success: false}), 'grantMoney', token, operationId), null);

assert.ok(Runtime.isLevelAction('finish_stage'));
assert.ok(!Runtime.isLevelAction('finish_everything'));
assert.deepStrictEqual(Runtime.LEVEL_ACTIONS.slice(0, 2), ['unlock_stages', 'kill_all']);
assert.ok(Runtime.OPERATION.test(operationId));
assert.ok(!Runtime.OPERATION.test('modifier.op.1'));

console.log('modifier runtime tests passed');
