'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const adapterPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'minigames', 'lockbox', 'chest-s0-adapter.js');
const S0 = require(adapterPath);

const cases = [];

function test(id, title, run) {
    cases.push({ id, title, run });
}

function identity(overrides) {
    return Object.assign({
        flowHandle: 'flow-1',
        panelInstanceId: 'panel-1',
        documentEpoch: 1,
        source: S0.SOURCE,
        fixture: S0.FIXTURE
    }, overrides || {});
}

function recorder(decide) {
    const messages = [];
    return {
        messages,
        send(message) {
            messages.push(JSON.parse(JSON.stringify(message)));
            return decide ? decide(message, messages.length) : true;
        }
    };
}

function activeAdapter(overrides) {
    const transport = recorder(overrides && overrides.decide);
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    assert.strictEqual(adapter.initialize(identity(overrides && overrides.identity)).ok, true);
    assert.strictEqual(adapter.bind().ok, true);
    return { adapter, transport };
}

function keys(value) {
    return Object.keys(value).sort();
}

function assertIdentityPayload(payload, extraKeys) {
    const expected = ['documentEpoch', 'fixture', 'flowHandle', 'panelInstanceId', 'source'].concat(extraKeys || []).sort();
    assert.deepStrictEqual(keys(payload), expected);
    assert.strictEqual(payload.flowHandle, 'flow-1');
    assert.strictEqual(payload.panelInstanceId, 'panel-1');
    assert.strictEqual(payload.documentEpoch, 1);
    assert.strictEqual(payload.source, S0.SOURCE);
    assert.strictEqual(payload.fixture, S0.FIXTURE);
}

function resultAck(result, overrides) {
    return Object.assign(identity(), {
        flowCallId: 1,
        result,
        applied: true,
        authorityTerminal: true
    }, overrides || {});
}

function authorityTerminal(overrides) {
    return Object.assign(identity(), {
        flowCallId: 1,
        terminal: S0.AUTHORITY_TERMINAL
    }, overrides || {});
}

test('W01', 'default disabled and exact five-field identity schema', function() {
    const disabledTransport = recorder();
    const disabled = S0.createAdapter({ send: disabledTransport.send });
    assert.strictEqual(disabled.initialize(identity()).code, 'disabled');
    assert.strictEqual(disabledTransport.messages.length, 0);

    const invalidInputs = [
        identity({ source: 'runtime' }),
        identity({ fixture: 'insurance-safe-s0-v2' }),
        identity({ documentEpoch: 0 }),
        identity({ flowHandle: '' }),
        identity({ panelInstanceId: ' panel-1' }),
        Object.assign(identity(), { chestSession: 'must-not-enter-web' }),
        Object.assign(identity(), { reward: { currency: 1 } }),
        Object.assign(identity(), { profile: 'standard' })
    ];
    invalidInputs.forEach(function(value) {
        const transport = recorder();
        const adapter = S0.createAdapter({ enabled: true, send: transport.send });
        assert.strictEqual(adapter.initialize(value).ok, false);
        assert.strictEqual(transport.messages.length, 0);
    });

    const transport = recorder();
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    assert.strictEqual(adapter.initialize(identity()).state, S0.STATES.UNBOUND);
    assert.strictEqual(adapter.bind().state, S0.STATES.ACTIVE);
    assert.strictEqual(transport.messages.length, 1);
    assert.strictEqual(transport.messages[0].cmd, 'bind');
    assertIdentityPayload(transport.messages[0].payload);
});

test('W02', 'core outcomes map to one limited result per flow', function() {
    const mappings = [
        ['success', 'success'],
        ['partial_success', 'success'],
        ['fail', 'failure']
    ];
    mappings.forEach(function(pair) {
        const fixture = activeAdapter();
        assert.strictEqual(fixture.adapter.submitCoreOutcome(pair[0]).ok, true);
        assert.strictEqual(fixture.adapter.submitCoreOutcome(pair[0]).code, 'result_not_allowed');
        const resultMessages = fixture.transport.messages.filter(function(message) { return message.cmd === 'result'; });
        assert.strictEqual(resultMessages.length, 1);
        assertIdentityPayload(resultMessages[0].payload, ['flowCallId', 'result']);
        assert.strictEqual(resultMessages[0].payload.result, pair[1]);
        assert.strictEqual(resultMessages[0].payload.flowCallId, 1);
    });

    const cancelled = activeAdapter();
    assert.strictEqual(cancelled.adapter.submitUserCancel().ok, true);
    assert.strictEqual(cancelled.transport.messages[1].payload.result, 'cancel');

    const rejected = activeAdapter();
    assert.strictEqual(rejected.adapter.submitCoreOutcome('perfect').code, 'unsupported_core_outcome');
    assert.strictEqual(rejected.adapter.submitCoreOutcome({ outcome: 'success', score: 99 }).code, 'unsupported_core_outcome');
    assert.strictEqual(rejected.transport.messages.filter(function(message) { return message.cmd === 'result'; }).length, 0);
});

test('W03', 'pending and reconcile states never guess, close, or unpause', function() {
    const fixture = activeAdapter();
    assert.strictEqual(fixture.adapter.submitCoreOutcome('success').state, S0.STATES.RESULT_PENDING);
    assert.strictEqual(fixture.adapter.markResultUnknown().state, S0.STATES.RECONCILE_REQUIRED);
    let snapshot = fixture.adapter.getSnapshot();
    assert.strictEqual(snapshot.canClose, false);
    assert.strictEqual(snapshot.canReleasePause, false);
    assert.strictEqual(snapshot.requiresReconcile, true);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity()).code, 'close_not_allowed');
    assert.strictEqual(fixture.adapter.requestResultQuery().ok, true);
    const query = fixture.transport.messages[2];
    assert.strictEqual(query.cmd, 'result_query');
    assertIdentityPayload(query.payload, ['unknownFlowCallId']);
    assert.strictEqual(query.payload.unknownFlowCallId, 1);

    const stale = Object.assign(identity(), {
        flowCallId: 1,
        observedCallWatermark: 0,
        disposition: 'success',
        authorityTerminal: true
    });
    assert.strictEqual(fixture.adapter.handleReconcileReply(stale).code, 'stale_watermark');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RECONCILE_REQUIRED);

    stale.observedCallWatermark = 1;
    assert.strictEqual(fixture.adapter.handleReconcileReply(stale).state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity()).state, S0.STATES.CLOSE_PENDING);
    assert.strictEqual(fixture.adapter.completeClose().state, S0.STATES.CLOSED);
    assert.strictEqual(fixture.adapter.getSnapshot().canReleasePause, true);
    const commands = fixture.transport.messages.map(function(message) { return message.cmd; });
    assert.strictEqual(commands.indexOf('unpause'), -1);
    assert.strictEqual(commands.indexOf('close') === -1, true);
    assert.strictEqual(commands[commands.length - 1], 'close_ack');
    assertIdentityPayload(fixture.transport.messages[fixture.transport.messages.length - 1].payload);
});

test('W04N', 'Node protocol model: bind delivery unknown resolves only by exact bound query', function() {
    const transport = recorder(function(message) {
        return message.cmd !== 'bind';
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    assert.strictEqual(adapter.initialize(identity()).ok, true);
    assert.strictEqual(adapter.bind().state, S0.STATES.OPEN_BIND_UNKNOWN);
    let snapshot = adapter.getSnapshot();
    assert.strictEqual(snapshot.bound, true);
    assert.strictEqual(snapshot.canClose, false);
    assert.strictEqual(snapshot.canReleasePause, false);
    assert.strictEqual(adapter.answerBindQuery(identity()).ok, true);
    assert.strictEqual(adapter.getSnapshot().state, S0.STATES.ACTIVE);
    const reply = transport.messages[1];
    assert.strictEqual(reply.cmd, 'bind_query_result');
    assertIdentityPayload(reply.payload, ['binding']);
    assert.strictEqual(reply.payload.binding, 'bound');
});

test('W05N', 'Node protocol model: same-name reopen and stale messages preserve current flow', function() {
    const fixture = activeAdapter();
    assert.strictEqual(fixture.adapter.initialize(identity({ panelInstanceId: 'panel-2' })).code, 'flow_busy');
    assert.strictEqual(fixture.adapter.answerBindQuery(identity({ panelInstanceId: 'stale-panel' })).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.ACTIVE);
    assert.strictEqual(fixture.adapter.submitCoreOutcome('fail').ok, true);
    assert.strictEqual(fixture.adapter.handleResultAck(resultAck('failure', { panelInstanceId: 'stale-panel' })).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RESULT_PENDING);
    assert.strictEqual(fixture.adapter.handleResultAck(resultAck('failure')).state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity({ panelInstanceId: 'stale-panel' })).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.TERMINAL_KNOWN);
});

test('B01', 'document epoch change enters reconcile without false unbound evidence', function() {
    const fixture = activeAdapter();
    const before = fixture.transport.messages.length;
    assert.strictEqual(fixture.adapter.observeDocumentEpoch(2).code, 'document_epoch_changed');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RECONCILE_REQUIRED);
    assert.strictEqual(fixture.adapter.getSnapshot().bound, true);
    assert.strictEqual(fixture.adapter.observeDocumentEpoch(1).code, 'stale_document_epoch');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RECONCILE_REQUIRED);
    assert.strictEqual(fixture.adapter.answerBindQuery(identity({ documentEpoch: 2 })).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.answerBindQuery(identity()).code, 'reconcile_required');
    assert.strictEqual(fixture.transport.messages.length, before);
    const serialized = JSON.stringify(fixture.transport.messages);
    assert.strictEqual(serialized.indexOf('"binding":"unbound"'), -1);
});

test('B02', 'flowCallId and documentEpoch use positive signed 32-bit bounds', function() {
    assert.strictEqual(S0.isValidFlowCallId(1), true);
    assert.strictEqual(S0.isValidFlowCallId(S0.MAX_INT32), true);
    [0, -1, S0.MAX_INT32 + 1, 1.5, '1', NaN, Infinity].forEach(function(value) {
        assert.strictEqual(S0.isValidFlowCallId(value), false);
    });
    assert.strictEqual(S0.isValidDocumentEpoch(1), true);
    assert.strictEqual(S0.isValidDocumentEpoch(S0.MAX_INT32), true);
    [0, S0.MAX_INT32 + 1, 2.5, '2'].forEach(function(value) {
        assert.strictEqual(S0.isValidDocumentEpoch(value), false);
    });

    const prototypeFixture = activeAdapter();
    ['toString', 'constructor', '__proto__'].forEach(function(value) {
        assert.strictEqual(prototypeFixture.adapter.submitCoreOutcome(value).code, 'unsupported_core_outcome');
    });
    assert.strictEqual(prototypeFixture.adapter.getSnapshot().state, S0.STATES.ACTIVE);

    const fixture = activeAdapter();
    fixture.adapter.submitCoreOutcome('success');
    assert.strictEqual(fixture.adapter.handleResultAck(resultAck('success', { flowCallId: S0.MAX_INT32 + 1 })).code, 'stale_flow_call');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RESULT_PENDING);
});

test('B03', 'transport failures stay unknown and never auto-resend', function() {
    const transport = recorder(function(message) {
        if (message.cmd === 'result') throw new Error('transport down');
        return true;
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    adapter.initialize(identity());
    adapter.bind();
    assert.strictEqual(adapter.submitCoreOutcome('success').state, S0.STATES.RECONCILE_REQUIRED);
    assert.strictEqual(adapter.submitCoreOutcome('success').code, 'result_not_allowed');
    assert.strictEqual(transport.messages.filter(function(message) { return message.cmd === 'result'; }).length, 1);
    assert.strictEqual(adapter.getSnapshot().canClose, false);
    assert.strictEqual(adapter.getSnapshot().canReleasePause, false);
});

test('B04', 'S0 forbids mutable gameplay and debug capabilities', function() {
    const fixture = activeAdapter();
    ['reroll', 'profile', 'hint', 'debug', 'export'].forEach(function(name) {
        assert.strictEqual(fixture.adapter.isCapabilityAllowed(name), false);
    });
    assert.strictEqual(fixture.adapter.isCapabilityAllowed('unknown'), false);
});

test('B05', 'telemetry is allow-listed and strips identities, seeds, raw results, and rewards', function() {
    const telemetry = S0.buildTelemetry({
        eventCategory: 'result',
        resultCategory: 'success',
        durationMs: 4200,
        errorCategory: 'none',
        flowHandle: 'flow-secret',
        sessionId: 'session-secret',
        panelInstanceId: 'panel-secret',
        fixture: S0.FIXTURE,
        source: S0.SOURCE,
        seed: 123,
        result: { outcome: 'success', score: 99 },
        reward: { currency: 999 }
    });
    assert.deepStrictEqual(telemetry, {
        eventCategory: 'result',
        resultCategory: 'success',
        durationBucket: '1_5s',
        errorCategory: 'none'
    });
    const serialized = JSON.stringify(telemetry).toLowerCase();
    ['flow', 'session', 'instance', 'fixture', 'source', 'seed', 'score', 'reward', 'currency', 'outcome'].forEach(function(fragment) {
        assert.strictEqual(serialized.indexOf(fragment), -1, 'telemetry leaked ' + fragment);
    });
    assert.deepStrictEqual(S0.buildTelemetry({
        eventCategory: 'flow-secret',
        resultCategory: 'raw-secret',
        durationMs: -1,
        errorCategory: 'stack-trace-secret'
    }), {
        eventCategory: 'unknown',
        resultCategory: 'unknown',
        durationBucket: 'unknown',
        errorCategory: 'unknown'
    });
    assert.deepStrictEqual(S0.buildTelemetry({
        eventCategory: 'toString',
        resultCategory: 'constructor',
        durationMs: 0,
        errorCategory: 'hasOwnProperty'
    }), {
        eventCategory: 'unknown',
        resultCategory: 'unknown',
        durationBucket: 'lt_1s',
        errorCategory: 'unknown'
    });
});

test('B06', 'exact close ack failure remains unknown with pause retained', function() {
    const transport = recorder(function(message) {
        return message.cmd !== 'close_ack';
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    adapter.initialize(identity());
    adapter.bind();
    adapter.submitUserCancel();
    adapter.handleResultAck(resultAck('cancel'));
    assert.strictEqual(adapter.acceptExactClose(identity()).ok, true);
    assert.strictEqual(adapter.completeClose().state, S0.STATES.CLOSE_UNKNOWN);
    assert.strictEqual(adapter.getSnapshot().canReleasePause, false);
    assert.strictEqual(adapter.getSnapshot().requiresReconcile, true);
});

test('B07', 'UMD browser export works and initialized identity is detached from caller mutation', function() {
    const context = {};
    context.globalThis = context;
    vm.runInNewContext(fs.readFileSync(adapterPath, 'utf8'), context, { filename: adapterPath });
    assert(context.LockboxChestS0Adapter, 'browser global export missing');
    assert.strictEqual(context.LockboxChestS0Adapter.SOURCE, S0.SOURCE);
    assert.strictEqual(Object.isFrozen(S0.STATES), true);
    assert.throws(function() {
        S0.STATES.ACTIVE = S0.STATES.TERMINAL_KNOWN;
    }, TypeError);

    const transport = recorder();
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    const initData = identity();
    assert.strictEqual(adapter.initialize(initData).ok, true);
    initData.flowHandle = 'mutated-flow';
    initData.panelInstanceId = 'mutated-panel';
    initData.documentEpoch = 99;
    assert.strictEqual(adapter.bind().ok, true);
    assertIdentityPayload(transport.messages[0].payload);
});

test('B08', 'authoritative acknowledgements reject extra fields and mismatched dispositions', function() {
    const fixture = activeAdapter();
    fixture.adapter.submitCoreOutcome('success');
    const taintedAck = Object.assign(resultAck('success'), { reward: { currency: 1 } });
    assert.strictEqual(fixture.adapter.handleResultAck(taintedAck).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RESULT_PENDING);
    fixture.adapter.markResultUnknown();
    const mismatched = Object.assign(identity(), {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'failure',
        authorityTerminal: true
    });
    assert.strictEqual(fixture.adapter.handleReconcileReply(mismatched).code, 'disposition_mismatch');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RECONCILE_REQUIRED);
});

test('B09', 'success applied is not closable until exact authority terminal arrives', function() {
    const fixture = activeAdapter();
    fixture.adapter.submitCoreOutcome('success');
    assert.strictEqual(fixture.adapter.handleResultAck(resultAck('success', { authorityTerminal: false })).state, S0.STATES.RESULT_APPLIED);
    assert.strictEqual(fixture.adapter.getSnapshot().canClose, false);
    assert.strictEqual(fixture.adapter.getSnapshot().canReleasePause, false);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity()).code, 'close_not_allowed');

    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal({ panelInstanceId: 'stale-panel' })).code, 'stale_identity');
    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal({ flowCallId: 2 })).code, 'stale_flow_call');
    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal({ terminal: 'OPENING_ANIMATION' })).code, 'unsupported_authority_terminal');
    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal({ terminal: 'toString' })).code, 'unsupported_authority_terminal');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.RESULT_APPLIED);

    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal()).state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(fixture.adapter.handleAuthorityTerminal(authorityTerminal()).code, 'authority_terminal_not_allowed');
    assert.strictEqual(fixture.adapter.getSnapshot().state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity()).state, S0.STATES.CLOSE_PENDING);

    const alreadyTerminal = activeAdapter();
    alreadyTerminal.adapter.submitCoreOutcome('success');
    assert.strictEqual(alreadyTerminal.adapter.handleResultAck(resultAck('success', { authorityTerminal: true })).state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(alreadyTerminal.adapter.getSnapshot().canClose, true);

    const expired = activeAdapter();
    expired.adapter.submitCoreOutcome('success');
    assert.strictEqual(expired.adapter.handleResultAck(resultAck('success', { authorityTerminal: false })).state, S0.STATES.RESULT_APPLIED);
    assert.strictEqual(expired.adapter.handleAuthorityTerminal(authorityTerminal({ terminal: 'EXPIRED' })).state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(expired.adapter.getSnapshot().canClose, true);
    assert.deepStrictEqual(S0.AUTHORITY_TERMINALS, ['COMPLETED_NO_REWARD', 'EXPIRED']);
});

test('B10', 'reconciled success also waits for terminal while non-success requires terminal proof', function() {
    const success = activeAdapter();
    success.adapter.submitCoreOutcome('success');
    success.adapter.markResultUnknown();
    const successReply = Object.assign(identity(), {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'success',
        authorityTerminal: false
    });
    assert.strictEqual(success.adapter.handleReconcileReply(successReply).state, S0.STATES.RESULT_APPLIED);
    assert.strictEqual(success.adapter.acceptExactClose(identity()).code, 'close_not_allowed');
    assert.strictEqual(success.adapter.handleAuthorityTerminal(authorityTerminal()).state, S0.STATES.TERMINAL_KNOWN);

    const cancelled = activeAdapter();
    cancelled.adapter.submitUserCancel();
    cancelled.adapter.markResultUnknown();
    const cancelReply = Object.assign(identity(), {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'cancel',
        authorityTerminal: false
    });
    assert.strictEqual(cancelled.adapter.handleReconcileReply(cancelReply).code, 'authority_terminal_required');
    assert.strictEqual(cancelled.adapter.getSnapshot().state, S0.STATES.RECONCILE_REQUIRED);
    cancelReply.authorityTerminal = true;
    assert.strictEqual(cancelled.adapter.handleReconcileReply(cancelReply).state, S0.STATES.TERMINAL_KNOWN);

    const failure = activeAdapter();
    failure.adapter.submitCoreOutcome('fail');
    assert.strictEqual(failure.adapter.handleResultAck(resultAck('failure', { authorityTerminal: false })).code, 'authority_terminal_required');
    assert.strictEqual(failure.adapter.getSnapshot().state, S0.STATES.RESULT_PENDING);
});

test('B11', 'all authority ack schemas reject missing, mistyped, and extra fields', function() {
    const resultFixture = activeAdapter();
    resultFixture.adapter.submitCoreOutcome('success');
    const missingResultFlag = resultAck('success');
    delete missingResultFlag.authorityTerminal;
    assert.strictEqual(resultFixture.adapter.handleResultAck(missingResultFlag).code, 'stale_identity');
    assert.strictEqual(resultFixture.adapter.handleResultAck(resultAck('success', { authorityTerminal: 'false' })).code, 'invalid_authority_terminal');
    assert.strictEqual(resultFixture.adapter.handleResultAck(Object.assign(resultAck('success'), { reward: 1 })).code, 'stale_identity');
    assert.strictEqual(resultFixture.adapter.getSnapshot().state, S0.STATES.RESULT_PENDING);

    const reconcileFixture = activeAdapter();
    reconcileFixture.adapter.submitCoreOutcome('success');
    reconcileFixture.adapter.markResultUnknown();
    const reconcileReply = Object.assign(identity(), {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'success',
        authorityTerminal: false
    });
    const missingReconcileFlag = Object.assign({}, reconcileReply);
    delete missingReconcileFlag.authorityTerminal;
    assert.strictEqual(reconcileFixture.adapter.handleReconcileReply(missingReconcileFlag).code, 'stale_identity');
    assert.strictEqual(reconcileFixture.adapter.handleReconcileReply(Object.assign({}, reconcileReply, { authorityTerminal: 0 })).code, 'invalid_authority_terminal');
    assert.strictEqual(reconcileFixture.adapter.handleReconcileReply(Object.assign({}, reconcileReply, { rawResult: 'success' })).code, 'stale_identity');
    assert.strictEqual(reconcileFixture.adapter.handleReconcileReply(reconcileReply).state, S0.STATES.RESULT_APPLIED);

    assert.strictEqual(reconcileFixture.adapter.handleAuthorityTerminal(Object.assign(authorityTerminal(), { reward: 1 })).code, 'stale_identity');
    const missingTerminal = authorityTerminal();
    delete missingTerminal.terminal;
    assert.strictEqual(reconcileFixture.adapter.handleAuthorityTerminal(missingTerminal).code, 'stale_identity');
    assert.strictEqual(reconcileFixture.adapter.getSnapshot().state, S0.STATES.RESULT_APPLIED);
});

test('B12', 'pre-result authoritative EXPIRED is terminal and permits one exact close ack', function() {
    const fixture = activeAdapter();
    const terminal = fixture.adapter.handleAuthorityTerminal(
        authorityTerminal({ terminal: 'EXPIRED' }));
    assert.strictEqual(terminal.ok, true);
    assert.strictEqual(terminal.state, S0.STATES.TERMINAL_KNOWN);
    assert.strictEqual(fixture.adapter.acceptExactClose(identity()).ok, true);
    assert.strictEqual(fixture.adapter.completeClose().ok, true);
    assert.strictEqual(fixture.transport.messages[fixture.transport.messages.length - 1].cmd,
        'close_ack');
});

test('B13', 'a lost close ack is retried with the same exact identity before pause release', function() {
    let closeAttempts = 0;
    const transport = recorder(function(message) {
        if (message.cmd !== 'close_ack') return true;
        closeAttempts += 1;
        return closeAttempts > 1;
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    adapter.initialize(identity());
    adapter.bind();
    adapter.handleAuthorityTerminal(authorityTerminal({ terminal: 'EXPIRED' }));
    assert.strictEqual(adapter.acceptExactClose(identity()).ok, true);
    assert.strictEqual(adapter.completeClose().state, S0.STATES.CLOSE_UNKNOWN);
    assert.strictEqual(adapter.getSnapshot().canReleasePause, false);
    const retried = adapter.retryCloseAck();
    assert.strictEqual(retried.ok, true);
    assert.strictEqual(retried.code, 'closed_after_retry');
    assert.strictEqual(adapter.getSnapshot().canReleasePause, true);
    const closeMessages = transport.messages.filter(function(message) {
        return message.cmd === 'close_ack';
    });
    assert.strictEqual(closeMessages.length, 2);
    assert.deepStrictEqual(closeMessages[0].payload, closeMessages[1].payload);
});

test('B14', 'bind query delivery loss remains retryable with the same exact identity', function() {
    let queryAttempts = 0;
    const transport = recorder(function(message) {
        if (message.cmd !== 'bind_query_result') return true;
        queryAttempts += 1;
        return queryAttempts > 1;
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    adapter.initialize(identity());
    adapter.bind();
    assert.strictEqual(adapter.markBindUnknown().ok, true);
    assert.strictEqual(adapter.answerBindQuery(identity()).code, 'query_delivery_unknown');
    assert.strictEqual(adapter.getSnapshot().state, S0.STATES.OPEN_BIND_UNKNOWN);
    const retried = adapter.answerBindQuery(identity());
    assert.strictEqual(retried.ok, true);
    assert.strictEqual(retried.binding, 'bound');
    assert.strictEqual(adapter.getSnapshot().state, S0.STATES.ACTIVE);
    const replies = transport.messages.filter(function(message) {
        return message.cmd === 'bind_query_result';
    });
    assert.strictEqual(replies.length, 2);
    assert.deepStrictEqual(replies[0].payload, replies[1].payload);
});

test('B15', 'CLOSED remains an exact proof tombstone across replay delivery failures', function() {
    let closeAttempts = 0;
    const transport = recorder(function(message) {
        if (message.cmd !== 'close_ack') return true;
        closeAttempts += 1;
        return closeAttempts !== 2;
    });
    const adapter = S0.createAdapter({ enabled: true, send: transport.send });
    adapter.initialize(identity());
    adapter.bind();
    adapter.handleAuthorityTerminal(authorityTerminal({ terminal: 'EXPIRED' }));
    assert.strictEqual(adapter.acceptExactClose(identity()).ok, true);
    assert.strictEqual(adapter.completeClose().state, S0.STATES.CLOSED);
    assert.strictEqual(adapter.replayCloseAck().code, 'close_replay_delivery_unknown');
    assert.strictEqual(adapter.getSnapshot().state, S0.STATES.CLOSED);
    assert.strictEqual(adapter.getSnapshot().canReleasePause, true);
    assert.strictEqual(adapter.replayCloseAck().code, 'closed_replayed');
    const closeMessages = transport.messages.filter(function(message) {
        return message.cmd === 'close_ack';
    });
    assert.strictEqual(closeMessages.length, 3);
    assert.deepStrictEqual(closeMessages[0].payload, closeMessages[2].payload);
});

let passed = 0;
const failures = [];

cases.forEach(function(item) {
    try {
        item.run();
        passed += 1;
        process.stdout.write('PASS ' + item.id + ' ' + item.title + '\n');
    } catch (error) {
        failures.push({ id: item.id, title: item.title, error });
        process.stderr.write('FAIL ' + item.id + ' ' + item.title + ' :: ' + (error && error.stack ? error.stack : error) + '\n');
    }
});

process.stdout.write(JSON.stringify({
    ok: failures.length === 0,
    passed,
    failed: failures.length,
    total: cases.length
}, null, 2) + '\n');

if (failures.length) process.exitCode = 1;
