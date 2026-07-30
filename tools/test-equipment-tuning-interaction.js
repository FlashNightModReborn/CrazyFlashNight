#!/usr/bin/env node
'use strict';

const assert = require('assert');
const {interactionLockProjection} = require(
    '../launcher/web/modules/equipment-tuning-interaction.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed += 1;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

function projection(state) {
    return interactionLockProjection(Object.assign({
        operation:'install_mod',
        sourceKind:'inventory',
        hasPreviewToken:true,
        mux:{pendingCount:0}
    }, state || {}));
}

test('idle authority opens every editing family and a token-backed commit', () => {
    const value = projection();
    [
        'source', 'tabs', 'tier', 'stepper', 'number', 'range', 'mark',
        'cap', 'candidate', 'conversionCandidate', 'slot', 'detach',
        'confirmation', 'inspect', 'commit'
    ].forEach(key => assert.strictEqual(value[key], true, key));
    assert.strictEqual(value.retry, false);
    assert.strictEqual(value.reconcile, false);
    assert.strictEqual(value.phase, 'idle');
});

test('every hard authority phase closes all editing families', () => {
    const cases = [
        [{detaching:true}, 'detaching'],
        [{refreshRetryPending:true}, 'retry_pending'],
        [{loadoutBarrier:{}}, 'loadout_barrier'],
        [{busy:true}, 'write_pending'],
        [{inventoryWritePending:true}, 'write_pending'],
        [{conversionLoading:true}, 'conversion_loading'],
        [{readPending:true}, 'read_pending'],
        [{mux:{pendingCount:1}}, 'read_pending']
    ];
    cases.forEach(([state, phase]) => {
        const value = projection(state);
        assert.strictEqual(value.phase, phase);
        assert.ok(value.reason);
        [
            'source', 'tabs', 'tier', 'stepper', 'number', 'range',
            'mark', 'cap', 'candidate', 'conversionCandidate',
            'slot', 'detach', 'confirmation', 'inspect', 'commit'
        ].forEach(key => assert.strictEqual(value[key], false, phase + ':' + key));
        assert.strictEqual(value.retry, false);
        assert.strictEqual(value.reconcile, false);
    });
});

test('failed refresh exposes retry as the only legal recovery action', () => {
    const value = projection({
        refreshRetryRequired:true,
        needsReconcile:true,
        loadoutBarrier:{kind:'unknown'}
    });
    assert.strictEqual(value.phase, 'retry_required');
    assert.strictEqual(value.retry, true);
    assert.strictEqual(value.reconcile, false);
    assert.strictEqual(value.commit, false);
    assert.ok(value.reason.includes('背包同步失败'));
});

test('reconcile exposes only the exact authority query recovery', () => {
    const value = projection({needsReconcile:true});
    assert.strictEqual(value.phase, 'reconcile_required');
    assert.strictEqual(value.reconcile, true);
    assert.strictEqual(value.retry, false);
    assert.strictEqual(value.tabs, false);
    assert.strictEqual(value.commit, false);
});

test('overlapping refresh and loadout phases preserve exact recovery precedence', () => {
    const retrying = projection({
        sourceKind:'loadout',
        refreshRetryPending:true,
        refreshRetryRequired:true,
        needsReconcile:true,
        loadoutBarrier:{kind:'unknown'}
    });
    assert.strictEqual(retrying.phase, 'retry_pending');
    assert.strictEqual(retrying.retry, false);
    assert.strictEqual(retrying.reconcile, false);

    const proving = projection({
        sourceKind:'loadout',
        refreshRetryPending:true,
        loadoutBarrier:{kind:'known'}
    });
    assert.strictEqual(proving.phase, 'loadout_barrier');

    const failedWatermark = projection({
        sourceKind:'loadout',
        needsReconcile:true,
        loadoutBarrier:{kind:'unknown'}
    });
    assert.strictEqual(failedWatermark.phase, 'reconcile_required');
    assert.strictEqual(failedWatermark.reconcile, true);
});

test('an in-flight enhance preview keeps only the draft controls open', () => {
    const value = projection({
        operation:'enhance',
        readPending:true,
        previewPendingOperation:'enhance',
        mux:{pendingCount:1}
    });
    assert.strictEqual(value.enhanceDraft, true);
    ['stepper', 'number', 'range', 'mark', 'cap'].forEach(
        key => assert.strictEqual(value[key], true, key));
    ['tabs', 'candidate', 'detach', 'confirmation', 'commit', 'inspect'].forEach(
        key => assert.strictEqual(value[key], false, key));
});

test('commit remains closed without a current authority token', () => {
    const value = projection({hasPreviewToken:false});
    assert.strictEqual(value.phase, 'idle');
    assert.strictEqual(value.tabs, true);
    assert.strictEqual(value.commit, false);
});

process.stdout.write('equipment tuning interaction tests passed: '
    + passed + '\n');
