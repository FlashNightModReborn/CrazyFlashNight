'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const projectRoot = path.resolve(__dirname, '..');
const actualWirePath = path.join(projectRoot, 'launcher', 'web', 'modules', 'minigames', 'lockbox', 'chest-s0-actual-wire.js');
const bootstrapPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'minigames', 'lockbox', 'chest-s0-dev-bootstrap.js');
const panelsPath = path.join(projectRoot, 'launcher', 'web', 'modules', 'panels.js');
const S0 = require(path.join(projectRoot, 'launcher', 'web', 'modules', 'minigames', 'lockbox', 'chest-s0-adapter.js'));
const ActualWire = require(actualWirePath);

const cases = [];

function test(id, title, run) {
    cases.push({ id, title, run });
}

function arm(capability, overrides) {
    return Object.assign({
        protocolVersion: 1,
        capability: capability || 'host-capability-1',
        connectionGeneration: 7,
        gameProcessId: 4242,
        documentEpoch: 1,
        source: S0.SOURCE,
        fixture: S0.FIXTURE
    }, overrides || {});
}

function openData(capability, overrides) {
    return Object.assign(arm(capability), {
        flowHandle: 'flow-actual-1',
        panelInstanceId: 'panel-actual-1'
    }, overrides || {});
}

function identity(value) {
    return {
        flowHandle: value.flowHandle,
        panelInstanceId: value.panelInstanceId,
        documentEpoch: value.documentEpoch,
        source: value.source,
        fixture: value.fixture
    };
}

function createBridge(decide) {
    const handlers = Object.create(null);
    const messages = [];
    return {
        messages,
        on(type, handler) {
            if (!handlers[type]) handlers[type] = [];
            handlers[type].push(handler);
        },
        off(type, handler) {
            const list = handlers[type] || [];
            const index = list.indexOf(handler);
            if (index >= 0) list.splice(index, 1);
        },
        send(message) {
            messages.push(JSON.parse(JSON.stringify(message)));
            return decide ? decide(message, messages.length) : true;
        },
        dispatch(type, cmd, payload, extra) {
            const message = Object.assign({ type, cmd, payload }, extra || {});
            (handlers[type] || []).slice().forEach(function(handler) { handler(message); });
        }
    };
}

function createElement() {
    const attributes = Object.create(null);
    const listeners = Object.create(null);
    const hiddenNodes = [];
    for (let i = 0; i < 6; i += 1) {
        hiddenNodes.push({
            style: {},
            disabled: false,
            setAttribute(name, value) { this[name] = value; },
            getAttribute(name) { return Object.prototype.hasOwnProperty.call(this, name) ? this[name] : null; },
            removeAttribute(name) { delete this[name]; }
        });
    }
    return {
        attributes,
        hiddenNodes,
        style: {},
        isConnected: true,
        setAttribute(name, value) { attributes[name] = value; },
        getAttribute(name) { return Object.prototype.hasOwnProperty.call(attributes, name) ? attributes[name] : null; },
        hasAttribute(name) { return Object.prototype.hasOwnProperty.call(attributes, name); },
        removeAttribute(name) { delete attributes[name]; },
        querySelectorAll() { return hiddenNodes; },
        addEventListener(type, handler) { listeners[type] = handler; },
        removeEventListener(type, handler) {
            if (listeners[type] === handler) delete listeners[type];
        },
        contains() { return true; }
    };
}

function createPanels(baseSpec) {
    let active = null;
    let spec = baseSpec;
    const decorators = [];
    const element = createElement();
    return {
        element,
        installRegistrationDecorator(id, decorator) {
            assert.strictEqual(id, 'lockbox');
            decorators.push(decorator);
            spec = decorator(spec) || spec;
            return true;
        },
        getActive() { return active; },
        open(initData) {
            if (active === 'lockbox') {
                if (spec.onRebind) spec.onRebind(element, initData);
                return;
            }
            spec.onOpen(element, initData);
            active = 'lockbox';
        },
        close() {
            if (active !== 'lockbox') return;
            // Production Panels.close hides the DOM and clears _active before onClose.
            active = null;
            if (spec.onClose) spec.onClose();
        },
        forceClose() {
            if (active !== 'lockbox') return;
            const activeSpec = spec;
            this.close();
            if (activeSpec.onForceClose) activeSpec.onForceClose();
        },
        requestClose() {
            if (spec.onRequestClose) return spec.onRequestClose();
        },
        getSpec() { return spec; }
    };
}

function flush() {
    return new Promise(function(resolve) { setImmediate(resolve); });
}

function deferred() {
    let resolve;
    let reject;
    const promise = new Promise(function(resolvePromise, rejectPromise) {
        resolve = resolvePromise;
        reject = rejectPromise;
    });
    return { promise, resolve, reject };
}

function delay(milliseconds) {
    return new Promise(function(resolve) { setTimeout(resolve, milliseconds); });
}

function installFakeClock() {
    const originalSetTimeout = global.setTimeout;
    const originalClearTimeout = global.clearTimeout;
    const timers = [];
    let nextId = 1;
    global.setTimeout = function(callback, milliseconds) {
        const timer = {
            id: nextId,
            callback,
            milliseconds,
            cleared: false,
            fired: false
        };
        nextId += 1;
        timers.push(timer);
        return timer;
    };
    global.clearTimeout = function(timer) {
        if (timer) timer.cleared = true;
    };
    return {
        timers,
        pending() {
            return timers.filter(function(timer) { return !timer.cleared && !timer.fired; });
        },
        fire(timer) {
            if (!timer || timer.cleared || timer.fired) return false;
            timer.fired = true;
            timer.callback();
            return true;
        },
        restore() {
            global.setTimeout = originalSetTimeout;
            global.clearTimeout = originalClearTimeout;
        }
    };
}

function messagesBy(bridge, type, cmd) {
    return bridge.messages.filter(function(message) {
        return message.type === type && message.cmd === cmd;
    });
}

function eventIdentity(event) {
    return {
        flowHandle: event.flowHandle,
        panelInstanceId: event.panelInstanceId,
        documentEpoch: event.documentEpoch
    };
}

test('AW01', 'arm and open schemas are exact and Host-owned', function() {
    assert.strictEqual(ActualWire.validateArmPayload(arm()).ok, true);
    assert.strictEqual(ActualWire.validateOpenInitData(openData(), arm()).ok, true);
    assert.strictEqual(ActualWire.validateArmPayload(Object.assign(arm(), { probeRunId: 'web-must-not-add' })).code, 'arm_schema_mismatch');
    assert.strictEqual(ActualWire.validateOpenInitData(Object.assign(openData(), { requestToken: 'host-private' }), arm()).code, 'open_schema_mismatch');
    assert.strictEqual(ActualWire.validateOpenInitData(openData('other-capability'), arm()).code, 'arm_mismatch');
    assert.strictEqual(ActualWire.validateArmPayload(arm('__proto__')).ok, true);
    assert.strictEqual(ActualWire.validateArmPayload(arm('cap', { documentEpoch: 0 })).code, 'invalid_document_epoch');
    assert.strictEqual(ActualWire.validateArmPayload(arm('cap', { connectionGeneration: 1.5 })).code, 'invalid_connection_generation');
    assert.strictEqual(ActualWire.validateArmPayload(arm('cap', { gameProcessId: 0 })).code, 'invalid_game_process_id');
});

test('AW02', 'exact arm decorates an already-resolved real panel and binds only after DOM commit', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; },
        onRequestClose() { base.legacyClose = (base.legacyClose || 0) + 1; }
    });
    let consumed = 0;
    const installed = ActualWire.install({
        arm: arm(),
        bridge,
        panels,
        onConsume() { consumed += 1; }
    });
    assert.strictEqual(installed.ok, true);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 0);
    panels.open(openData());
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(consumed, 1);
    await flush();
    const binds = messagesBy(bridge, S0.MESSAGE_TYPE, 'bind');
    assert.strictEqual(binds.length, 1);
    assert.deepStrictEqual(Object.keys(binds[0].payload).sort(), [
        'documentEpoch', 'fixture', 'flowHandle', 'panelInstanceId', 'source'
    ].sort());
    assert.strictEqual(JSON.stringify(binds).includes('host-capability-1'), false);
    assert.strictEqual(panels.element.attributes['data-lockbox-s0-flow'], 'active');
    panels.element.hiddenNodes.forEach(function(node) {
        assert.strictEqual(node.style.display, 'none');
        assert.strictEqual(node['aria-hidden'], 'true');
    });
    const evidence = installed.getEvidence();
    assert.strictEqual(evidence.executionMode, 'actual-webview2-dev-wire');
    assert.strictEqual(evidence.hostEvidenceRequired, true);
    assert.strictEqual(evidence.selfAttestedCrossStack, false);
    assert.strictEqual(evidence.selfAttestedProductionHost, false);
    assert.strictEqual(JSON.stringify(evidence).includes('host-capability-1'), false);

    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success', score: 999 } } }
    });
    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    const results = messagesBy(bridge, S0.MESSAGE_TYPE, 'result');
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].payload.result, 'success');
    assert.strictEqual(Object.prototype.hasOwnProperty.call(results[0].payload, 'score'), false);

    const id = identity(openData());
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, id, {
        flowCallId: 1,
        result: 'success',
        applied: true,
        authorityTerminal: false
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RESULT_APPLIED);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, id, {
        flowCallId: 1,
        terminal: S0.AUTHORITY_TERMINAL
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.TERMINAL_KNOWN);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(base.closed, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    panels.element.hiddenNodes.forEach(function(node) {
        assert.strictEqual(node.style.display, undefined);
        assert.strictEqual(node.disabled, false);
        assert.strictEqual(node.getAttribute('aria-hidden'), null);
    });
    assert.strictEqual(panels.element.attributes['data-lockbox-s0-flow'], undefined);
});

test('AW03', 'same-name, cancel, stale control, rearm, and epoch paths fail closed', async function() {
    const bridge = createBridge();
    const base = { opened: 0, legacyClose: 0 };
    const rejected = [];
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() {},
        onRequestClose() { base.legacyClose += 1; }
    });
    const installed = ActualWire.install({
        arm: arm('cap-A'),
        bridge,
        panels,
        onRejected(payload) { rejected.push(payload); },
        onTeardown() { return true; }
    });
    panels.open(openData('cap-A'));
    await flush();
    panels.open(openData('cap-A', { flowHandle: 'late-flow', panelInstanceId: 'late-panel' }));
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 1);
    panels.requestClose();
    assert.strictEqual(base.legacyClose, 0);
    assert.strictEqual(panels.getActive(), 'lockbox');
    const cancel = messagesBy(bridge, S0.MESSAGE_TYPE, 'result');
    assert.strictEqual(cancel.length, 1);
    assert.strictEqual(cancel[0].payload.result, 'cancel');

    const idA = identity(openData('cap-A'));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, idA, {
        panelInstanceId: 'stale-panel',
        flowCallId: 1,
        result: 'cancel',
        applied: true,
        authorityTerminal: true
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RESULT_PENDING);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, idA, {
        flowCallId: 1,
        result: 'cancel',
        applied: true,
        authorityTerminal: true
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', idA);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.doesNotThrow(function() {
        panels.open(openData('cap-A', { flowHandle: 'stale-flow', panelInstanceId: 'stale-panel' }));
    });
    assert.strictEqual(rejected[rejected.length - 1].code, 'wire_not_armed');
    assert.strictEqual(panels.element.hasAttribute('inert'), true);
    panels.close();
    assert.strictEqual(panels.element.hasAttribute('inert'), false);
    assert.strictEqual(installed.rearm(arm('cap-A')).code, 'capability_reused');
    assert.strictEqual(installed.rearm(arm('cap-B', { documentEpoch: 2 })).ok, true);
    const second = openData('cap-B', {
        connectionGeneration: 7,
        gameProcessId: 4242,
        documentEpoch: 2,
        flowHandle: 'flow-actual-2',
        panelInstanceId: 'panel-actual-2'
    });
    panels.open(second);
    await flush();
    const idB = identity(second);
    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_unknown', Object.assign({}, idB, {
        flowCallId: 1,
        reward: 1
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RESULT_PENDING);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, 0);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_unknown', Object.assign({}, idB, {
        flowCallId: 1
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);
    const resultQueries = messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query');
    assert.strictEqual(resultQueries.length, 1);
    assert.deepStrictEqual(resultQueries[0].payload, Object.assign({}, idB, {
        unknownFlowCallId: 1
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'document_epoch', Object.assign({}, idB, { observedEpoch: 3 }));
    const afterEpoch = installed.getEvidence().flow.adapter;
    assert.strictEqual(afterEpoch.state, S0.STATES.RECONCILE_REQUIRED);
    assert.strictEqual(afterEpoch.bound, true);
    assert.strictEqual(afterEpoch.canReleasePause, false);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', idB);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);

    panels.getSpec().onForceClose();
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
});

test('AW09', 'force close proves Web DOM teardown independently and clears current for fresh rearm', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0, forced: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; },
        onForceClose() { base.forced += 1; }
    });
    const installed = ActualWire.install({
        arm: arm('force-close-cap-A'),
        bridge,
        panels,
        onTeardown(payload) {
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'teardown_ack',
                payload
            });
        }
    });
    panels.open(openData('force-close-cap-A'));
    await flush();
    assert.strictEqual(installed.getEvidence().state, 'CONSUMED');

    // Production Panels force_close closes the DOM first and then invokes onForceClose.
    panels.close();
    panels.getSpec().onForceClose();
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(base.closed, 1);
    assert.strictEqual(base.forced, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 0);
    const teardown = messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack');
    assert.strictEqual(teardown.length, 1);
    assert.deepStrictEqual(Object.keys(teardown[0].payload).sort(), [
        'protocolVersion', 'capability', 'connectionGeneration', 'gameProcessId',
        'documentEpoch', 'source', 'fixture', 'reason'
    ].sort());
    assert.strictEqual(teardown[0].payload.reason, 'force_close');
    assert.strictEqual(installed.rearm(arm('force-close-cap-B', { documentEpoch: 2 })).ok, true);
});

test('AW10', 'consumed runtime rejection reports exact control, tears down, and permits fresh rearm', async function() {
    const bridge = createBridge();
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const runtimeRejected = [];
    const teardown = [];
    const installed = ActualWire.install({
        arm: arm('runtime-reject-cap-A'),
        bridge,
        panels,
        onRuntimeRejected(payload) {
            runtimeRejected.push(payload);
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'runtime_rejected',
                payload
            });
        },
        onTeardown(payload) {
            teardown.push(payload);
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'teardown_ack',
                payload
            });
        }
    });
    panels.open(openData('wrong-runtime-capability'));
    await flush();

    assert.strictEqual(runtimeRejected.length, 1);
    assert.strictEqual(runtimeRejected[0].capability, 'runtime-reject-cap-A');
    assert.strictEqual(runtimeRejected[0].code, 'arm_mismatch');
    assert.strictEqual(teardown.length, 1);
    assert.strictEqual(teardown[0].reason, 'runtime_rejected');
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'rejected').length, 0);
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'runtime_rejected').length, 1);
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(installed.rearm(arm('runtime-reject-cap-B', { documentEpoch: 2 })).ok, true);
});

test('AW14', 'lost forced-teardown proof is retained and resent by an exact Host query', async function() {
    let teardownAttempts = 0;
    const bridge = createBridge(function(message) {
        if (message.type !== ActualWire.CONTROL_TYPE || message.cmd !== 'teardown_ack') return true;
        teardownAttempts += 1;
        return teardownAttempts > 1;
    });
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('teardown-retry-capability'),
        bridge,
        panels,
        onRuntimeRejected(payload) {
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'runtime_rejected',
                payload
            });
        },
        onTeardown(payload) {
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'teardown_ack',
                payload
            });
        }
    });
    const rejectedOpen = openData('wrong-runtime-capability');
    panels.open(rejectedOpen);
    await flush();
    assert.strictEqual(installed.getEvidence().state, 'TEARDOWN_UNKNOWN');
    assert.strictEqual(panels.getActive(), null);

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', identity(rejectedOpen));
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 2);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(installed.rearm(arm('teardown-retry-fresh', { documentEpoch: 2 })).ok, true);
});

test('AW15', 'a locally unknown result query retries until Host reconciliation is received', async function() {
    let queryAttempts = 0;
    const bridge = createBridge(function(message) {
        if (message.type !== S0.MESSAGE_TYPE) return true;
        if (message.cmd === 'result') return false;
        if (message.cmd === 'result_query') {
            queryAttempts += 1;
            return queryAttempts > 1;
        }
        return true;
    });
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('result-query-retry-capability'),
        bridge,
        panels
    });
    const opened = openData('result-query-retry-capability');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);
    await delay(300);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length >= 2, true);

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'reconcile_reply', Object.assign({}, id, {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'success',
        authorityTerminal: false
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RESULT_APPLIED);
});

test('AW11', 'pre-result EXPIRED crosses the actual wire and emits one exact close ack', async function() {
    const bridge = createBridge();
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('pre-result-expired-cap'),
        bridge,
        panels
    });
    const opened = openData('pre-result-expired-cap');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 0);

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, id, {
        flowCallId: 1,
        terminal: 'EXPIRED'
    }));
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.TERMINAL_KNOWN);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);
    assert.deepStrictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack')[0].payload, id);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
});

test('AW12', 'a fresh Host arm supersedes an unused one-shot arm after a panel-busy begin rejection', async function() {
    const bridge = createBridge();
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('panel-busy-old-cap'),
        bridge,
        panels
    });
    const fresh = arm('panel-busy-fresh-cap');
    assert.strictEqual(installed.rearm(fresh).ok, true);
    assert.strictEqual(installed.rearm(fresh).code, 'capability_reused');
    assert.strictEqual(installed.getEvidence().state, 'ARMED');
    assert.strictEqual(installed.rearm(arm('panel-busy-old-cap')).code, 'capability_reused');
    assert.strictEqual(installed.getEvidence().state, 'ARMED');
    assert.strictEqual(installed.getEvidence().events.filter(function(event) {
        return event.event === 'arm_superseded';
    }).length, 1);
    panels.open(openData('panel-busy-fresh-cap'));
    await flush();
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 1);
});

test('AW13', 'close_query recovers a lost exact close ack without reopening the DOM', async function() {
    let closeAttempts = 0;
    const bridge = createBridge(function(message) {
        if (message.type !== S0.MESSAGE_TYPE || message.cmd !== 'close_ack') return true;
        closeAttempts += 1;
        return closeAttempts > 1;
    });
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('close-retry-capability'),
        bridge,
        panels
    });
    const opened = openData('close-retry-capability');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, id, {
        flowCallId: 1,
        terminal: 'EXPIRED'
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.CLOSE_UNKNOWN);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', id);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 2);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
});

test('AW26', 'production-order onClose exception cannot strand exact close proof', async function() {
    const bridge = createBridge();
    const panels = createPanels({
        onOpen() {},
        onClose() { throw new Error('sensitive-close-cleanup-detail'); }
    });
    const installed = ActualWire.install({
        arm: arm('close-cleanup-exception-cap'),
        bridge,
        panels
    });
    const opened = openData('close-cleanup-exception-cap');
    const id = identity(opened);
    panels.open(opened);
    await flush();

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, id, {
        flowCallId: 1,
        terminal: 'EXPIRED'
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);

    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);
    const evidence = installed.getEvidence();
    assert.strictEqual(evidence.state, 'IDLE');
    const cleanupEvents = evidence.events.filter(function(event) {
        return event.event === 'panel_cleanup_exception';
    });
    assert.deepStrictEqual(cleanupEvents.map(function(event) { return event.code; }), [
        'original_on_close'
    ]);
    assert.deepStrictEqual(eventIdentity(cleanupEvents[0]), {
        flowHandle: id.flowHandle,
        panelInstanceId: id.panelInstanceId,
        documentEpoch: id.documentEpoch
    });
    assert.strictEqual(JSON.stringify(evidence).includes('sensitive-close-cleanup-detail'), false);
});

test('AW27', 'production force teardown survives both cleanup callbacks throwing', async function() {
    const bridge = createBridge();
    const base = { closeCalls: 0, forceCalls: 0 };
    const panels = createPanels({
        onOpen() {},
        onClose() {
            base.closeCalls += 1;
            throw new Error('sensitive-force-on-close-detail');
        },
        onForceClose() {
            base.forceCalls += 1;
            throw new Error('sensitive-force-cleanup-detail');
        }
    });
    const installed = ActualWire.install({
        arm: arm('force-cleanup-exception-cap'),
        bridge,
        panels,
        onTeardown(payload) {
            return bridge.send({
                type: ActualWire.CONTROL_TYPE,
                cmd: 'teardown_ack',
                payload
            });
        }
    });
    const opened = openData('force-cleanup-exception-cap');
    panels.open(opened);
    await flush();

    panels.forceClose();

    assert.strictEqual(base.closeCalls, 1);
    assert.strictEqual(base.forceCalls, 1);
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 0);
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 1);
    const evidence = installed.getEvidence();
    assert.strictEqual(evidence.state, 'IDLE');
    assert.deepStrictEqual(evidence.events.filter(function(event) {
        return event.event === 'panel_cleanup_exception';
    }).map(function(event) { return event.code; }), [
        'original_on_close',
        'original_on_force_close'
    ]);
    assert.strictEqual(JSON.stringify(evidence).includes('sensitive-force-on-close-detail'), false);
    assert.strictEqual(JSON.stringify(evidence).includes('sensitive-force-cleanup-detail'), false);
});

test('AW16', 'send-true close proof is replayable after fresh rearm without closing the new DOM', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; }
    });
    const installed = ActualWire.install({
        arm: arm('silent-close-old'),
        bridge,
        panels
    });
    const opened = openData('silent-close-old');
    const oldIdentity = identity(opened);
    panels.open(opened);
    await flush();
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, oldIdentity, {
        flowCallId: 1,
        terminal: 'EXPIRED'
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', oldIdentity);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', Object.assign({}, oldIdentity, {
        panelInstanceId: 'wrong-old-panel'
    }));
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);

    assert.strictEqual(installed.rearm(arm('silent-close-fresh', { documentEpoch: 2 })).ok, true);
    const fresh = openData('silent-close-fresh', {
        flowHandle: 'flow-actual-fresh',
        panelInstanceId: 'panel-actual-fresh',
        documentEpoch: 2
    });
    panels.open(fresh);
    await flush();
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', oldIdentity);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 2);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(base.closed, 1);
    assert.strictEqual(installed.getEvidence().state, 'CONSUMED');
    const closeQueryEvidence = installed.getEvidence().events.filter(function(event) {
        return event.event === 'control_close_query';
    }).pop();
    assert.deepStrictEqual(eventIdentity(closeQueryEvidence), {
        flowHandle: oldIdentity.flowHandle,
        panelInstanceId: oldIdentity.panelInstanceId,
        documentEpoch: oldIdentity.documentEpoch
    });
});

test('AW17', 'send-true teardown proof replays by old identity without disturbing a fresh flow', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; }
    });
    const installed = ActualWire.install({
        arm: arm('silent-teardown-old'),
        bridge,
        panels,
        onRuntimeRejected(payload) {
            return bridge.send({ type: ActualWire.CONTROL_TYPE, cmd: 'runtime_rejected', payload });
        },
        onTeardown(payload) {
            return bridge.send({ type: ActualWire.CONTROL_TYPE, cmd: 'teardown_ack', payload });
        }
    });
    const rejected = openData('wrong-silent-teardown-capability');
    const oldIdentity = identity(rejected);
    panels.open(rejected);
    await flush();
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');

    assert.strictEqual(installed.rearm(arm('silent-teardown-fresh', { documentEpoch: 2 })).ok, true);
    const fresh = openData('silent-teardown-fresh', {
        flowHandle: 'flow-teardown-fresh',
        panelInstanceId: 'panel-teardown-fresh',
        documentEpoch: 2
    });
    panels.open(fresh);
    await flush();
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', Object.assign({}, oldIdentity, {
        flowHandle: 'wrong-old-flow'
    }));
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 1);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_query', oldIdentity);
    assert.strictEqual(messagesBy(bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 2);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(base.closed, 1);
    assert.strictEqual(installed.getEvidence().state, 'CONSUMED');
    const evidence = installed.getEvidence().events;
    const retryEvidence = evidence.filter(function(event) {
        return event.event === 'teardown_ack_retry';
    }).pop();
    const queryEvidence = evidence.filter(function(event) {
        return event.event === 'control_close_query';
    }).pop();
    assert.deepStrictEqual(eventIdentity(retryEvidence), {
        flowHandle: oldIdentity.flowHandle,
        panelInstanceId: oldIdentity.panelInstanceId,
        documentEpoch: oldIdentity.documentEpoch
    });
    assert.deepStrictEqual(eventIdentity(queryEvidence), {
        flowHandle: oldIdentity.flowHandle,
        panelInstanceId: oldIdentity.panelInstanceId,
        documentEpoch: oldIdentity.documentEpoch
    });
});

test('AW18', 'S0 suppresses raw Lockbox sessions and emits only four-field telemetry', async function() {
    const bridge = createBridge();
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('telemetry-s0-capability'),
        bridge,
        panels,
        resultAckTimeoutMs: 1000
    });
    const ordinary = {
        mode: 'dev', profile: 'standard', source: 'runtime', familySeed: 9,
        variantIndex: 0, debug: false
    };
    panels.open(ordinary);
    await flush();
    bridge.send({
        type: 'panel', cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { sessionId: 'ordinary-visible' } }
    });
    const ordinarySessionCount = messagesBy(bridge, 'panel', 'minigame_session').length;
    panels.close();

    const opened = openData('telemetry-s0-capability');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    bridge.send({
        type: 'panel', cmd: 'minigame_session',
        payload: {
            game: 'lockbox', kind: 'open',
            data: { sessionId: 's0-secret-open', requested: { familySeed: 123456 } }
        }
    });
    bridge.send({
        type: 'panel', cmd: 'minigame_session',
        payload: {
            game: 'lockbox', kind: 'result',
            data: {
                sessionId: 's0-secret-result',
                requested: { familySeed: 987654 },
                resolved: { profile: 'secret-profile' },
                metrics: { observeMs: 1200, executeMs: 900, picksUsed: 7 },
                result: { outcome: 'success', score: 999, reward: { coins: 50 } }
            }
        }
    });
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, id, {
        flowCallId: 1,
        result: 'success',
        applied: true,
        authorityTerminal: true
    }));

    const sessions = messagesBy(bridge, 'panel', 'minigame_session');
    const ordinaryMessages = sessions.filter(function(message) {
        return message.payload.kind === 'result' && message.payload.data.sessionId === 'ordinary-visible';
    });
    const sanitized = sessions.filter(function(message) {
        return message.payload.kind === 's0_telemetry';
    });
    assert.strictEqual(ordinaryMessages.length, 1);
    assert.strictEqual(sanitized.length, 2);
    assert.strictEqual(sessions.length, ordinarySessionCount + sanitized.length);
    sessions.slice(ordinarySessionCount).forEach(function(message) {
        assert.strictEqual(message.payload.kind, 's0_telemetry');
    });
    sanitized.forEach(function(message) {
        assert.deepStrictEqual(Object.keys(message.payload).sort(), ['data', 'game', 'kind']);
        assert.deepStrictEqual(Object.keys(message.payload.data).sort(), [
            'durationBucket', 'errorCategory', 'eventCategory', 'resultCategory'
        ]);
    });
    const serialized = JSON.stringify(sanitized);
    ['s0-secret', 'familySeed', 'requested', 'resolved', 'metrics', 'picksUsed',
        'score', 'reward', 'coins', '987654'].forEach(function(fragment) {
        assert.strictEqual(serialized.indexOf(fragment), -1, 'S0 telemetry leaked ' + fragment);
    });
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.TERMINAL_KNOWN);
});

test('AW19', 'send-true result silence times out into query without replaying the write', async function() {
    const bridge = createBridge();
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('silent-result-capability'),
        bridge,
        panels,
        resultAckTimeoutMs: 20
    });
    const opened = openData('silent-result-capability');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    bridge.send({
        type: 'panel', cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    await delay(60);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length >= 1, true);
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);

    bridge.dispatch(ActualWire.CONTROL_TYPE, 'reconcile_reply', Object.assign({}, id, {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'not_applied',
        authorityTerminal: true
    }));
    const queriesAfterReply = messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length;
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
    assert.strictEqual(installed.rearm(arm('silent-result-fresh', { documentEpoch: 2 })).ok, true);
    panels.open(openData('silent-result-fresh', {
        flowHandle: 'flow-result-fresh', panelInstanceId: 'panel-result-fresh', documentEpoch: 2
    }));
    await flush();
    await delay(60);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, queriesAfterReply);
});

test('AW20', 'cancel send-false immediately starts causal query and never replays cancel', async function() {
    const bridge = createBridge(function(message) {
        return !(message.type === S0.MESSAGE_TYPE && message.cmd === 'result');
    });
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const installed = ActualWire.install({
        arm: arm('cancel-query-capability'),
        bridge,
        panels,
        resultAckTimeoutMs: 20
    });
    const opened = openData('cancel-query-capability');
    const id = identity(opened);
    panels.open(opened);
    await flush();
    panels.requestClose();
    const results = messagesBy(bridge, S0.MESSAGE_TYPE, 'result');
    assert.strictEqual(results.length, 1);
    assert.strictEqual(results[0].payload.result, 'cancel');
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length >= 1, true);
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'reconcile_reply', Object.assign({}, id, {
        flowCallId: 1,
        observedCallWatermark: 1,
        disposition: 'not_applied',
        authorityTerminal: true
    }));
    await delay(40);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 1);
    assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.TERMINAL_KNOWN);
});

test('AW21', 'duplicate result and cancel input cannot replace the first ack deadline', async function() {
    const clock = installFakeClock();
    try {
        const bridge = createBridge();
        const panels = createPanels({ onOpen() {}, onClose() {} });
        const installed = ActualWire.install({
            arm: arm('fixed-result-deadline-capability'),
            bridge,
            panels,
            resultAckTimeoutMs: 40
        });
        const opened = openData('fixed-result-deadline-capability');
        const id = identity(opened);
        panels.open(opened);
        await flush();
        bridge.send({
            type: 'panel', cmd: 'minigame_session',
            payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
        });
        const firstDeadline = clock.pending()[0];
        assert(firstDeadline);
        assert.strictEqual(firstDeadline.milliseconds, 40);

        bridge.send({
            type: 'panel', cmd: 'minigame_session',
            payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
        });
        panels.requestClose();
        assert.strictEqual(clock.pending().length, 1);
        assert.strictEqual(clock.pending()[0], firstDeadline);
        assert.strictEqual(clock.timers.length, 1);

        assert.strictEqual(clock.fire(firstDeadline), true);
        assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 1);
        assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, 1);
        assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);
        bridge.dispatch(ActualWire.CONTROL_TYPE, 'reconcile_reply', Object.assign({}, id, {
            flowCallId: 1,
            observedCallWatermark: 1,
            disposition: 'not_applied',
            authorityTerminal: true
        }));
        bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
        assert.strictEqual(installed.getEvidence().state, 'IDLE');
    } finally {
        clock.restore();
    }
});

test('AW22', 'document epoch change cancels result timers and starts no impossible old-epoch query', async function() {
    const clock = installFakeClock();
    try {
        const bridge = createBridge();
        const panels = createPanels({ onOpen() {}, onClose() {}, onForceClose() {} });
        const installed = ActualWire.install({
            arm: arm('epoch-stops-query-capability'),
            bridge,
            panels,
            resultAckTimeoutMs: 40,
            onTeardown() { return true; }
        });
        const opened = openData('epoch-stops-query-capability');
        const id = identity(opened);
        panels.open(opened);
        await flush();
        bridge.send({
            type: 'panel', cmd: 'minigame_session',
            payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
        });
        const abandonedDeadline = clock.pending()[0];
        assert(abandonedDeadline);
        bridge.dispatch(ActualWire.CONTROL_TYPE, 'document_epoch', Object.assign({}, id, {
            observedEpoch: 2
        }));

        assert.strictEqual(abandonedDeadline.cleared, true);
        assert.strictEqual(clock.pending().length, 0);
        assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, 0);
        const queryEvents = installed.getEvidence().events.filter(function(event) {
            return event.event === 'result_query' || event.event === 'result_query_retry';
        });
        assert.strictEqual(queryEvents.length, 0);
        assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.RECONCILE_REQUIRED);

        panels.getSpec().onForceClose();
        assert.strictEqual(installed.getEvidence().state, 'IDLE');
    } finally {
        clock.restore();
    }
});

test('AW23', 'a late exact result ack after timeout reaches terminal and cancels query retries', async function() {
    const clock = installFakeClock();
    try {
        const bridge = createBridge();
        const panels = createPanels({ onOpen() {}, onClose() {} });
        const installed = ActualWire.install({
            arm: arm('late-result-ack-capability'),
            bridge,
            panels,
            resultAckTimeoutMs: 40
        });
        const opened = openData('late-result-ack-capability');
        const id = identity(opened);
        panels.open(opened);
        await flush();
        bridge.send({
            type: 'panel', cmd: 'minigame_session',
            payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
        });
        const ackDeadline = clock.pending()[0];
        assert.strictEqual(clock.fire(ackDeadline), true);
        assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, 1);
        const retryTimer = clock.pending()[0];
        assert(retryTimer);
        assert.strictEqual(retryTimer.milliseconds, 250);

        bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, id, {
            flowCallId: 1,
            result: 'success',
            applied: true,
            authorityTerminal: true
        }));
        assert.strictEqual(retryTimer.cleared, true);
        assert.strictEqual(clock.pending().length, 0);
        assert.strictEqual(installed.getEvidence().flow.adapter.state, S0.STATES.TERMINAL_KNOWN);
        assert.strictEqual(clock.fire(retryTimer), false);
        assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result_query').length, 1);
        bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', id);
        assert.strictEqual(installed.getEvidence().state, 'IDLE');
    } finally {
        clock.restore();
    }
});

test('AW07', 'an unused arm does not hijack ordinary Lockbox opens or telemetry', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; }
    });
    panels.element.style.pointerEvents = 'auto';
    panels.element.setAttribute('aria-busy', 'legacy');
    panels.element.setAttribute('inert', 'legacy');
    let consumed = 0;
    const installed = ActualWire.install({
        arm: arm('ordinary-pass-through-capability'),
        bridge,
        panels,
        onConsume() { consumed += 1; }
    });
    panels.open({
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        familySeed: 123,
        variantIndex: 0,
        debug: true
    });
    await flush();
    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(consumed, 0);
    assert.strictEqual(installed.getEvidence().state, 'ARMED');
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 0);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'result').length, 0);
    panels.close();
    assert.strictEqual(base.closed, 1);
    assert.strictEqual(panels.element.style.pointerEvents, 'auto');
    assert.strictEqual(panels.element.getAttribute('aria-busy'), 'legacy');
    assert.strictEqual(panels.element.getAttribute('inert'), 'legacy');
});

test('AW30', 'single and partial S0 field collisions remain ordinary Lockbox open and rebind data', async function() {
    const bridge = createBridge();
    const base = { opened: 0, rebound: 0, closed: 0, forced: 0, openedData: [], reboundData: [] };
    let throwCleanup = false;
    const panels = createPanels({
        onOpen(el, initData) { base.opened += 1; base.openedData.push(initData); },
        onRebind(el, initData) { base.rebound += 1; base.reboundData.push(initData); },
        onClose() {
            base.closed += 1;
            if (throwCleanup) throw new Error('sensitive-rejected-open-cleanup-detail');
        },
        onForceClose() { base.forced += 1; }
    });
    let consumed = 0;
    let rejected = 0;
    let runtimeRejected = 0;
    let teardown = 0;
    const installed = ActualWire.install({
        arm: arm('partial-collision-arm'),
        bridge,
        panels,
        onConsume() { consumed += 1; },
        onRejected() { rejected += 1; },
        onRuntimeRejected() { runtimeRejected += 1; },
        onTeardown() { teardown += 1; return true; }
    });

    const realPanelHostInit = {
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        familySeed: 321,
        variantIndex: 0,
        debug: false,
        panelInstanceId: 'ordinary-panelhost-armed'
    };
    panels.open(realPanelHostInit);
    await flush();
    assert.strictEqual(base.opened, 1);
    assert.strictEqual(base.openedData[0], realPanelHostInit);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(installed.getEvidence().state, 'ARMED');

    const partialCollision = Object.assign({}, realPanelHostInit, {
        protocolVersion: 1,
        capability: 'ordinary-lockbox-capability',
        connectionGeneration: 7,
        gameProcessId: 4242,
        documentEpoch: 1,
        flowHandle: 'ordinary-lockbox-flow',
        panelInstanceId: 'ordinary-lockbox-panel'
    });
    panels.open(partialCollision);
    assert.strictEqual(base.rebound, 1);
    assert.strictEqual(base.reboundData[0], partialCollision);
    assert.strictEqual(installed.getEvidence().state, 'ARMED');
    panels.close();

    panels.open(partialCollision);
    await flush();
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(base.openedData[1], partialCollision);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(installed.getEvidence().state, 'ARMED');
    assert.strictEqual(consumed, 0);
    assert.strictEqual(rejected, 0);
    assert.strictEqual(runtimeRejected, 0);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 0);
    panels.close();
    assert.strictEqual(base.closed, 2);
    assert.strictEqual(base.forced, 0);

    const malformedDedicatedSource = {
        mode: 'dev',
        profile: 'standard',
        source: S0.SOURCE,
        familySeed: 777,
        variantIndex: 0,
        debug: false,
        panelInstanceId: 'malformed-source-panel'
    };
    panels.open(malformedDedicatedSource);
    await flush();
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(consumed, 1);
    assert.strictEqual(runtimeRejected, 1);
    assert.strictEqual(teardown, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(base.closed, 3);

    const malformedDedicatedFixture = {
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        fixture: S0.FIXTURE,
        familySeed: 778,
        variantIndex: 0,
        debug: false,
        panelInstanceId: 'malformed-fixture-panel'
    };
    throwCleanup = true;
    panels.open(malformedDedicatedFixture);
    await flush();
    throwCleanup = false;
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(consumed, 1);
    assert.strictEqual(rejected, 0);
    assert.strictEqual(runtimeRejected, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 0);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(base.closed, 4);
    assert.strictEqual(base.forced, 0);
    assert.strictEqual(teardown, 1);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 0);
    assert.strictEqual(JSON.stringify(installed.getEvidence()).includes(
        'sensitive-rejected-open-cleanup-detail'), false);

    const malformedBeforeOrdinaryTakeover = Object.assign({}, malformedDedicatedFixture, {
        panelInstanceId: 'malformed-before-ordinary-takeover'
    });
    const ordinaryTakeoverAfterRejectedOpen = {
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        familySeed: 779,
        variantIndex: 0,
        debug: false,
        panelInstanceId: 'ordinary-takeover-after-rejected-open'
    };
    panels.open(malformedBeforeOrdinaryTakeover);
    assert.strictEqual(panels.getActive(), 'lockbox');
    panels.open(ordinaryTakeoverAfterRejectedOpen);
    assert.strictEqual(base.rebound, 2);
    assert.strictEqual(base.reboundData[1], ordinaryTakeoverAfterRejectedOpen);
    assert.strictEqual(panels.element.hasAttribute('inert'), false);
    // A later reserved rebind is rejected in place, but must not schedule a close against the
    // already-active ordinary panel or call its ordinary rebind hook.
    panels.open(malformedDedicatedFixture);
    await flush();
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(base.rebound, 2);
    assert.strictEqual(consumed, 1);
    assert.strictEqual(rejected, 0);
    assert.strictEqual(runtimeRejected, 1);
    assert.strictEqual(teardown, 1);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(base.closed, 4);
    assert.strictEqual(base.forced, 0);
    panels.close();
    assert.strictEqual(base.closed, 5);
});

test('AW31', 'real ordinary PanelHost init remains untouched after an exact S0 close reaches IDLE', async function() {
    const bridge = createBridge();
    const base = { opened: 0, closed: 0, forced: 0, openedData: [] };
    const panels = createPanels({
        onOpen(el, initData) { base.opened += 1; base.openedData.push(initData); },
        onClose() { base.closed += 1; },
        onForceClose() { base.forced += 1; }
    });
    let consumed = 0;
    let rejected = 0;
    let runtimeRejected = 0;
    const installed = ActualWire.install({
        arm: arm('idle-transition-arm'),
        bridge,
        panels,
        onConsume() { consumed += 1; },
        onRejected() { rejected += 1; },
        onRuntimeRejected() { runtimeRejected += 1; }
    });

    const trackedOpen = openData('idle-transition-arm');
    panels.open(trackedOpen);
    await flush();
    const trackedIdentity = identity(trackedOpen);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 1);
    bridge.send({
        type: 'panel',
        cmd: 'minigame_session',
        payload: { game: 'lockbox', kind: 'result', data: { result: { outcome: 'success' } } }
    });
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'result_ack', Object.assign({}, trackedIdentity, {
        flowCallId: 1,
        result: 'success',
        applied: true,
        authorityTerminal: false
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'authority_terminal', Object.assign({}, trackedIdentity, {
        flowCallId: 1,
        terminal: S0.AUTHORITY_TERMINAL
    }));
    bridge.dispatch(ActualWire.CONTROL_TYPE, 'close_request', trackedIdentity);
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'close_ack').length, 1);

    const realPanelHostInit = {
        mode: 'dev',
        profile: 'standard',
        source: 'runtime',
        familySeed: 654,
        variantIndex: 0,
        debug: false,
        panelInstanceId: 'ordinary-panelhost-idle'
    };
    panels.open(realPanelHostInit);
    await flush();
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(base.openedData[1], realPanelHostInit);
    assert.strictEqual(panels.getActive(), 'lockbox');
    assert.strictEqual(installed.getEvidence().state, 'IDLE');
    assert.strictEqual(consumed, 1);
    assert.strictEqual(rejected, 0);
    assert.strictEqual(runtimeRejected, 0);
    assert.strictEqual(messagesBy(bridge, S0.MESSAGE_TYPE, 'bind').length, 1);
    assert.strictEqual(base.forced, 0);
    panels.close();
    assert.strictEqual(base.closed, 2);
    assert.strictEqual(base.forced, 0);
});

function capturePanelCommandLog(data) {
    const handlers = Object.create(null);
    const logs = [];
    const context = {
        console: {
            log() { logs.push(Array.prototype.slice.call(arguments)); },
            error() {}
        },
        Bridge: {
            on(type, handler) { handlers[type] = handler; },
            send() { return true; }
        },
        setTimeout() { return 0; }
    };
    context.globalThis = context;
    vm.runInNewContext(fs.readFileSync(panelsPath, 'utf8'), context, {
        filename: panelsPath
    });
    handlers.panel_cmd(data);
    const commandLog = logs.filter(function(args) {
        return args[0] === '[Panels] panel_cmd received:';
    });
    assert.strictEqual(commandLog.length, 1);
    return JSON.parse(commandLog[0][1]);
}

test('AW08', 'ordinary panel logging keeps its fields while redacting only capability', function() {
    const source = fs.readFileSync(panelsPath, 'utf8');
    assert(source.includes('safePanelCommandLog(data)'));
    assert(source.includes("console.log('[Panels] panel_cmd received:', safePanelCommandLog(data));"));
    assert.strictEqual(source.includes("console.log('[Panels] panel_cmd received:', JSON.stringify(data));"), false);

    const logged = capturePanelCommandLog({
        cmd: 'open',
        panel: 'ordinary-panel',
        initData: {
            capability: 'ordinary-capability-secret',
            flowHandle: 'ordinary-flow-visible',
            panelInstanceId: 'ordinary-panel-visible',
            fixture: 'ordinary-fixture-visible',
            source: 'ordinary-source-visible'
        }
    });
    assert.strictEqual(logged.initData.capability, '[redacted]');
    assert.strictEqual(logged.initData.flowHandle, 'ordinary-flow-visible');
    assert.strictEqual(logged.initData.panelInstanceId, 'ordinary-panel-visible');
    assert.strictEqual(logged.initData.fixture, 'ordinary-fixture-visible');
    assert.strictEqual(logged.initData.source, 'ordinary-source-visible');
});

test('AW28', 'S0 panel logging replaces the complete production initData with one constant', function() {
    const initData = openData('s0-log-capability-secret', {
        flowHandle: 's0-log-flow-secret',
        panelInstanceId: 's0-log-panel-secret'
    });
    const logged = capturePanelCommandLog({
        cmd: 'open',
        panel: 'lockbox',
        initData
    });
    assert.strictEqual(logged.initData, '[redacted]');
    const serialized = JSON.stringify(logged);
    assert.strictEqual(serialized.includes('s0-log-capability-secret'), false);
    assert.strictEqual(serialized.includes('s0-log-flow-secret'), false);
    assert.strictEqual(serialized.includes('s0-log-panel-secret'), false);
    assert.strictEqual(serialized.includes(S0.SOURCE), false);
    assert.strictEqual(serialized.includes(S0.FIXTURE), false);
});

test('AW29', 'nested browser-host-shim S0 identity receives the same whole-initData redaction', function() {
    const logged = capturePanelCommandLog({
        cmd: 'open',
        panel: 'lockbox',
        initData: {
            mode: 'dev',
            profile: 'standard',
            source: 'runtime',
            familySeed: 1392508929,
            __lockboxChestS0: {
                harness: 'browser-host-shim',
                identity: {
                    flowHandle: 's0.browser.host.flow.node-secret',
                    panelInstanceId: 's0.browser.host.panel.node-secret',
                    documentEpoch: 1,
                    source: S0.SOURCE,
                    fixture: S0.FIXTURE
                }
            }
        }
    });
    assert.strictEqual(logged.initData, '[redacted]');
    const serialized = JSON.stringify(logged);
    assert.strictEqual(serialized.includes('__lockboxChestS0'), false);
    assert.strictEqual(serialized.includes('s0.browser.host.flow.node-secret'), false);
    assert.strictEqual(serialized.includes('s0.browser.host.panel.node-secret'), false);
    assert.strictEqual(serialized.includes(S0.SOURCE), false);
    assert.strictEqual(serialized.includes(S0.FIXTURE), false);
});

function bootstrapContext(locationValue, fixtureOptions) {
    fixtureOptions = fixtureOptions || {};
    const handlers = Object.create(null);
    const messages = [];
    const loads = [];
    let installedArm = null;
    let installedOptions = null;
    const bridge = {
        messages,
        on(type, handler) {
            if (!handlers[type]) handlers[type] = [];
            handlers[type].push(handler);
        },
        off(type, handler) {
            const list = handlers[type] || [];
            const index = list.indexOf(handler);
            if (index >= 0) list.splice(index, 1);
        },
        send(message) { messages.push(JSON.parse(JSON.stringify(message))); return true; }
    };
    const fakeActualWire = {
        install(options) {
            installedOptions = options;
            installedArm = options.arm;
            return {
                ok: true,
                code: 'armed',
                rearm() { return { ok: false, code: 'wire_busy' }; },
                getEvidence() { return { executionMode: 'actual-webview2-dev-wire' }; }
            };
        }
    };
    const context = {
        console,
        Promise,
        setTimeout,
        clearTimeout,
        location: locationValue,
        chrome: {
            webview: {
                postMessage() {},
                addEventListener() {}
            }
        },
        Bridge: bridge,
        Panels: fixtureOptions.panels || {},
        LazyLoader: fixtureOptions.lazyLoader || {
            load(urls) { loads.push(urls.slice()); return Promise.resolve(); }
        },
        LockboxChestS0Adapter: fixtureOptions.adapter || {},
        LockboxChestS0ActualWire: fixtureOptions.actualWire || fakeActualWire
    };
    context.globalThis = context;
    vm.runInNewContext(fs.readFileSync(bootstrapPath, 'utf8'), context, { filename: bootstrapPath });
    return {
        context,
        messages,
        loads,
        bridge,
        getInstalledArm() { return installedArm; },
        getInstalledOptions() { return installedOptions; },
        dispatch(message) {
            (handlers[ActualWire.CONTROL_TYPE] || []).slice().forEach(function(handler) {
                handler(message);
            });
        }
    };
}

test('AW04', 'production bootstrap stays dormant and malformed arm cannot load code', async function() {
    const fixture = bootstrapContext({
        protocol: 'https:',
        hostname: 'overlay.local',
        port: '',
        pathname: '/overlay.html',
        search: '',
        hash: '',
        href: 'https://overlay.local/overlay.html'
    });
    let snapshot = fixture.context.LockboxChestS0DevBootstrap.getSnapshot();
    assert.strictEqual(snapshot.state, 'DORMANT');
    assert.strictEqual(snapshot.loadAttempted, false);
    assert.strictEqual(fixture.loads.length, 0);
    assert.strictEqual(fixture.messages.length, 0);
    fixture.dispatch({
        type: ActualWire.CONTROL_TYPE,
        cmd: 'arm',
        payload: Object.assign(arm(), { probeRunId: 'forbidden-extra' })
    });
    await flush();
    snapshot = fixture.context.LockboxChestS0DevBootstrap.getSnapshot();
    assert.strictEqual(snapshot.state, 'DORMANT');
    assert.strictEqual(snapshot.invalidArmCount, 1);
    assert.strictEqual(fixture.loads.length, 0);
    assert.strictEqual(fixture.messages.length, 0);
});

test('AW05', 'only the exact production overlay arm lazy-loads and returns exact armed payload', async function() {
    const fixture = bootstrapContext({
        protocol: 'https:',
        hostname: 'overlay.local',
        port: '',
        pathname: '/overlay.html',
        search: '',
        hash: '',
        href: 'https://overlay.local/overlay.html'
    });
    const payload = arm('bootstrap-capability');
    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload });
    await flush();
    await flush();
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.loads)), [[
        'modules/minigames/lockbox/chest-s0-adapter.js',
        'modules/minigames/lockbox/chest-s0-actual-wire.js'
    ]]);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.getInstalledArm())), payload);
    assert.strictEqual(fixture.messages.length, 1);
    assert.strictEqual(fixture.messages[0].type, ActualWire.CONTROL_TYPE);
    assert.strictEqual(fixture.messages[0].cmd, 'armed');
    assert.deepStrictEqual(Object.keys(fixture.messages[0].payload).sort(), ActualWire.ARM_KEYS.slice().sort());
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'ARMED');
});

test('AW25', 'fresh arm during deferred load preserves its owner and actual wire accepts the later retry', async function() {
    const moduleLoad = deferred();
    const observedLoads = [];
    const panels = createPanels({ onOpen() {}, onClose() {} });
    const fixture = bootstrapContext({
        protocol: 'https:',
        hostname: 'overlay.local',
        port: '',
        pathname: '/overlay.html',
        search: '',
        hash: '',
        href: 'https://overlay.local/overlay.html'
    }, {
        panels,
        adapter: S0,
        actualWire: ActualWire,
        lazyLoader: {
            load(urls) {
                observedLoads.push(urls.slice());
                return moduleLoad.promise;
            }
        }
    });
    const loadOwner = arm('deferred-load-owner-capability');
    const retryWhileLoading = arm('deferred-loading-retry-capability');
    const retryAfterInstall = arm('deferred-installed-retry-capability');

    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: loadOwner });
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'LOADING');
    assert.strictEqual(observedLoads.length, 1);
    assert.strictEqual(fixture.messages.length, 0);

    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: retryWhileLoading });
    assert.strictEqual(fixture.messages.length, 1);
    assert.strictEqual(fixture.messages[0].cmd, 'rejected');
    assert.strictEqual(fixture.messages[0].payload.code, 'wire_loading');
    assert.strictEqual(fixture.messages[0].payload.capability, retryWhileLoading.capability);
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'LOADING');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().actualWireLoaded, false);
    assert.strictEqual(observedLoads.length, 1, 'the retry must not start a competing module load');

    moduleLoad.resolve();
    await flush();
    await flush();
    assert.strictEqual(fixture.messages.length, 2);
    assert.strictEqual(fixture.messages[1].cmd, 'armed');
    assert.strictEqual(fixture.messages[1].payload.capability, loadOwner.capability);
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'ARMED');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().actualWireLoaded, true);

    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: retryAfterInstall });
    assert.strictEqual(observedLoads.length, 1);
    assert.strictEqual(fixture.messages.length, 3);
    assert.strictEqual(fixture.messages[2].cmd, 'armed');
    assert.strictEqual(fixture.messages[2].payload.capability, retryAfterInstall.capability);
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'ARMED');

    const opened = openData(retryAfterInstall.capability, {
        flowHandle: 'deferred-rearm-flow',
        panelInstanceId: 'deferred-rearm-panel'
    });
    panels.open(opened);
    await flush();
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'CONSUMED');
    assert.strictEqual(messagesBy(fixture.bridge, S0.MESSAGE_TYPE, 'bind').length, 1);
});

test('AW06', 'dev/browser URLs cannot arm the production bootstrap', async function() {
    const fixture = bootstrapContext({
        protocol: 'http:',
        hostname: '127.0.0.1',
        port: '8123',
        pathname: '/modules/minigames/lockbox/dev/s0-harness.html',
        search: '',
        hash: '',
        href: 'http://127.0.0.1:8123/modules/minigames/lockbox/dev/s0-harness.html'
    });
    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: arm('wrong-page-capability') });
    await flush();
    assert.strictEqual(fixture.loads.length, 0);
    assert.strictEqual(fixture.messages.length, 1);
    assert.strictEqual(fixture.messages[0].cmd, 'rejected');
    assert.strictEqual(fixture.messages[0].payload.code, 'page_not_allowlisted');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().actualWireLoaded, false);
});

test('AW24', 'real bootstrap recovers from initial panel busy and old teardown replay preserves fresh state', async function() {
    const base = { opened: 0, closed: 0, forced: 0 };
    const panels = createPanels({
        onOpen() { base.opened += 1; },
        onClose() { base.closed += 1; },
        onForceClose() { base.forced += 1; }
    });
    panels.open({
        mode: 'dev', profile: 'standard', source: 'runtime', familySeed: 4,
        variantIndex: 0, debug: false
    });
    const fixture = bootstrapContext({
        protocol: 'https:',
        hostname: 'overlay.local',
        port: '',
        pathname: '/overlay.html',
        search: '',
        hash: '',
        href: 'https://overlay.local/overlay.html'
    }, {
        panels,
        adapter: S0,
        actualWire: ActualWire
    });

    fixture.dispatch({
        type: ActualWire.CONTROL_TYPE,
        cmd: 'arm',
        payload: arm('bootstrap-busy-capability')
    });
    await flush();
    await flush();
    assert.strictEqual(fixture.loads.length, 1);
    assert.strictEqual(fixture.messages.length, 1);
    assert.strictEqual(fixture.messages[0].cmd, 'rejected');
    assert.strictEqual(fixture.messages[0].payload.code, 'panel_orchestration_busy');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'DORMANT');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().actualWireLoaded, false);

    panels.close();
    const oldArm = arm('bootstrap-old-flow-capability');
    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: oldArm });
    assert.strictEqual(fixture.loads.length, 1, 'loaded modules must be reused for the fresh arm');
    assert.strictEqual(fixture.messages[fixture.messages.length - 1].cmd, 'armed');
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'ARMED');

    const rejectedOpen = openData('wrong-bootstrap-old-flow-capability');
    const oldIdentity = identity(rejectedOpen);
    panels.open(rejectedOpen);
    await flush();
    await flush();
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'IDLE');
    assert.strictEqual(messagesBy(fixture.bridge, ActualWire.CONTROL_TYPE, 'runtime_rejected').length, 1);
    assert.strictEqual(messagesBy(fixture.bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 1);

    const freshArm = arm('bootstrap-fresh-flow-capability', { documentEpoch: 2 });
    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'arm', payload: freshArm });
    const freshOpen = openData('bootstrap-fresh-flow-capability', {
        flowHandle: 'bootstrap-fresh-flow',
        panelInstanceId: 'bootstrap-fresh-panel',
        documentEpoch: 2
    });
    panels.open(freshOpen);
    await flush();
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'CONSUMED');
    assert.strictEqual(panels.getActive(), 'lockbox');

    fixture.dispatch({ type: ActualWire.CONTROL_TYPE, cmd: 'close_query', payload: oldIdentity });
    assert.strictEqual(messagesBy(fixture.bridge, ActualWire.CONTROL_TYPE, 'teardown_ack').length, 2);
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'CONSUMED');
    assert.strictEqual(panels.getActive(), 'lockbox');
    const freshEvidence = fixture.context.__lockboxChestS0ActualWireEvidence();
    assert.strictEqual(freshEvidence.flow.flowHandle, freshOpen.flowHandle);
    assert.strictEqual(freshEvidence.flow.panelInstanceId, freshOpen.panelInstanceId);

    panels.getSpec().onForceClose();
    assert.strictEqual(fixture.context.LockboxChestS0DevBootstrap.getSnapshot().state, 'IDLE');
    assert.strictEqual(panels.getActive(), null);
    assert.strictEqual(base.opened, 2);
    assert.strictEqual(base.closed, 3);
    assert.strictEqual(base.forced, 1);
});

(async function main() {
    let passed = 0;
    const failures = [];
    for (const item of cases) {
        try {
            await item.run();
            passed += 1;
            process.stdout.write('PASS ' + item.id + ' ' + item.title + '\n');
        } catch (error) {
            failures.push({ id: item.id, title: item.title, error });
            process.stderr.write('FAIL ' + item.id + ' ' + item.title + ' :: '
                + (error && error.stack ? error.stack : error) + '\n');
        }
    }
    process.stdout.write(JSON.stringify({
        ok: failures.length === 0,
        passed,
        failed: failures.length,
        total: cases.length
    }, null, 2) + '\n');
    if (failures.length) process.exitCode = 1;
})();
