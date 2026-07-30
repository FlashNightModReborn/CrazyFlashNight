#!/usr/bin/env node
'use strict';

const assert = require('assert');
const Confirmation = require(
    '../launcher/web/modules/equipment-tuning-confirmation.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed += 1;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

function memoryStorage(initial) {
    const values = Object.assign({}, initial || {});
    return {
        getItem:key => Object.prototype.hasOwnProperty.call(values, key)
            ? values[key] : null,
        setItem:(key, value) => { values[key] = String(value); },
        value:key => values[key]
    };
}

test('player-facing choices and persistent boundary use the decided language', () => {
    assert.deepStrictEqual(Confirmation.CHOICES.map(choice => ({
        value:choice.value,
        label:choice.label
    })), [
        {value:'safe', label:'逐次确认'},
        {value:'fast', label:'单件快捷'}
    ]);
    assert.strictEqual(
        Confirmation.BOUNDARY_TEXT,
        '批量、连锁与卸下全部始终需要确认'
    );
    const help = Confirmation.helpDetail();
    assert.ok(help.includes('逐次确认'));
    assert.ok(help.includes('单件快捷'));
    assert.ok(help.includes(Confirmation.BOUNDARY_TEXT));
    assert.ok(!help.includes('安全 / 快速'));
    const spec = Confirmation.helpSpec();
    assert.strictEqual(spec.kind, 'equipment-tuning-help');
    assert.ok(spec.message.includes('不会解锁配件能力'));
    assert.ok(spec.detail.includes(Confirmation.BOUNDARY_TEXT));
});

test('one port synchronizes every mounted consumer and persists one key', () => {
    const storage = memoryStorage();
    const port = new Confirmation.ConfirmationPort({storage});
    const first = [];
    const second = [];
    const stopFirst = port.subscribe((mode, meta) => first.push([mode, meta.origin]));
    const stopSecond = port.subscribe((mode, meta) => second.push([mode, meta.origin]));

    assert.deepStrictEqual(first, [['safe', 'subscribe']]);
    assert.deepStrictEqual(second, [['safe', 'subscribe']]);
    assert.strictEqual(port.set('fast'), 'fast');
    assert.strictEqual(storage.value('cf7.equipmentTuning.modConfirmationMode'), 'fast');
    assert.deepStrictEqual(first.at(-1), ['fast', 'set']);
    assert.deepStrictEqual(second.at(-1), ['fast', 'set']);
    assert.deepStrictEqual(port.debugState(), {mode:'fast', subscriberCount:2});

    assert.strictEqual(stopFirst(), true);
    assert.strictEqual(port.set('unexpected'), 'safe');
    assert.strictEqual(first.length, 2);
    assert.deepStrictEqual(second.at(-1), ['safe', 'set']);
    assert.strictEqual(stopSecond(), true);
    assert.deepStrictEqual(port.debugState(), {mode:'safe', subscriberCount:0});
});

test('external preference drift is observed once before a new subscriber mounts', () => {
    const storage = memoryStorage();
    const port = new Confirmation.ConfirmationPort({storage});
    storage.setItem('cf7.equipmentTuning.modConfirmationMode', 'fast');
    const events = [];
    port.subscribe((mode, meta) => events.push([mode, meta.origin]));
    assert.deepStrictEqual(events, [['fast', 'subscribe']]);
});

test('disabled reason projection covers every authority-sensitive phase', () => {
    const cases = [
        [{detaching:true}, '正在结束调制会话'],
        [{refreshRetryPending:true}, '正在重试同步背包'],
        [{refreshRetryRequired:true}, '背包同步失败'],
        [{needsReconcile:true}, '正在核对调制结果'],
        [{loadoutBarrier:{}}, '正在核对调制结果'],
        [{loadoutBarrier:{}, refreshRetryPending:true}, '正在核对调制结果'],
        [{busy:true}, '调制写入尚未完成'],
        [{inventoryWritePending:true}, '调制写入尚未完成'],
        [{readPending:true}, '正在读取调制状态'],
        [{conversionLoading:true}, '正在读取调制状态'],
        [{mux:{pendingCount:1}}, '正在读取调制状态']
    ];
    cases.forEach(([state, prefix]) => {
        const projected = Confirmation.project('fast', state);
        assert.strictEqual(projected.value, 'fast');
        assert.strictEqual(projected.disabled, true);
        assert.ok(projected.reason.startsWith(prefix), prefix);
        assert.strictEqual(projected.boundaryText, Confirmation.BOUNDARY_TEXT);
    });
    assert.deepStrictEqual(Confirmation.project('invalid', {}), {
        value:'safe',
        disabled:false,
        reason:'',
        boundaryText:Confirmation.BOUNDARY_TEXT
    });
});

process.stdout.write('equipment tuning confirmation tests passed: '
    + passed + '\n');
