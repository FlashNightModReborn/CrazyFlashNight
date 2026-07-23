'use strict';

const assert = require('assert');
const Runtime = require('../launcher/web/modules/panel-runtime.js');

let passed = 0;
function test(name, run) {
    run();
    passed += 1;
    process.stdout.write('ok - ' + name + '\n');
}

function createTimers() {
    const timers = [];
    return {
        timers,
        setTimer(callback) { const timer = {callback, cleared:false}; timers.push(timer); return timer; },
        clearTimer(timer) { timer.cleared = true; }
    };
}

test('response router installs one bridge listener and unregisters handlers', () => {
    const listeners = [];
    const bridge = {
        on(type, handler) { listeners.push([type, handler]); },
        off(type, handler) { listeners.push(['off:' + type, handler]); }
    };
    const router = new Runtime.PanelResponseRouter();
    assert.strictEqual(router.install(bridge), true);
    assert.strictEqual(router.install(bridge), true);
    assert.strictEqual(listeners.filter(row => row[0] === 'panel_resp').length, 1);
    const seen = [];
    const unregister = router.register(data => { seen.push(data.callId); return true; });
    listeners[0][1]({type:'panel_resp', callId:'one'});
    unregister();
    listeners[0][1]({type:'panel_resp', callId:'two'});
    assert.deepStrictEqual(seen, ['one']);
    assert.strictEqual(router.uninstall(), true);
});

test('request mux isolates close/reopen generations and rejects late responses', () => {
    const sent = [];
    const timers = createTimers();
    const mux = new Runtime.PanelRequestMux({
        callPrefix:'test', sessionNonce:'nonce', send:message => sent.push(message),
        setTimer:timers.setTimer, clearTimer:timers.clearTimer,
        validateResponse:(data, entry) => data.callId === entry.callId && data.cmd === entry.cmd
    });
    mux.openSession({panelInstanceId:'one'});
    const firstGeneration = mux.debugState().generation;
    const calls = [];
    const oldCallId = mux.request('snapshot', {}, response => calls.push(response.callId));
    mux.closeSession();
    assert.strictEqual(timers.timers[0].cleared, true);
    mux.openSession({panelInstanceId:'two'});
    const secondGeneration = mux.debugState().generation;
    const newCallId = mux.request('snapshot', {}, response => calls.push(response.callId));
    assert.strictEqual(secondGeneration, firstGeneration + 1);
    assert.notStrictEqual(newCallId, oldCallId);
    assert.strictEqual(mux.handleResponse({type:'panel_resp', cmd:'snapshot', callId:oldCallId}), false);
    assert.deepStrictEqual(calls, []);
    assert.strictEqual(mux.debugState().pendingCount, 1);
    assert.strictEqual(mux.handleResponse({type:'panel_resp', cmd:'snapshot', callId:newCallId}), true);
    assert.deepStrictEqual(calls, [newCallId]);
    assert.strictEqual(mux.debugState().pendingCount, 0);
});

test('latest-wins cancels the previous kind and accepts the newest call', () => {
    const timers = createTimers();
    const mux = new Runtime.PanelRequestMux({
        callPrefix:'test', sessionNonce:'nonce', send:() => true,
        setTimer:timers.setTimer, clearTimer:timers.clearTimer,
        validateResponse:(data, entry) => data.callId === entry.callId && data.cmd === entry.cmd
    });
    mux.openSession({});
    const seen = [];
    const first = mux.request('preview', {value:1}, {kind:'preview', latestWins:true}, response => seen.push(response.callId));
    const second = mux.request('preview', {value:2}, {kind:'preview', latestWins:true}, response => seen.push(response.callId));
    assert.notStrictEqual(first, second);
    assert.strictEqual(mux.handleResponse({type:'panel_resp', cmd:'preview', callId:first}), false);
    assert.strictEqual(mux.handleResponse({type:'panel_resp', cmd:'preview', callId:second}), true);
    assert.deepStrictEqual(seen, [second]);
});

test('completed calls suppress duplicate responses', () => {
    const timers = createTimers();
    const mux = new Runtime.PanelRequestMux({
        callPrefix:'test', sessionNonce:'nonce', send:() => true,
        setTimer:timers.setTimer, clearTimer:timers.clearTimer,
        validateResponse:(data, entry) => data.callId === entry.callId && data.cmd === entry.cmd
    });
    mux.openSession({});
    const seen = [];
    const callId = mux.request('snapshot', {}, response => seen.push(response.marker));
    assert.strictEqual(mux.handleResponse({
        type:'panel_resp', cmd:'snapshot', callId, marker:'first'
    }), true);
    assert.strictEqual(timers.timers[0].cleared, true);
    assert.strictEqual(mux.pendingCount(), 0);
    assert.strictEqual(mux.handleResponse({
        type:'panel_resp', cmd:'snapshot', callId, marker:'duplicate'
    }), false);
    assert.deepStrictEqual(seen, ['first']);
});

test('timeout and send failure are synthetic and deterministic', () => {
    const timers = createTimers();
    const responses = [];
    const mux = new Runtime.PanelRequestMux({
        callPrefix:'test', sessionNonce:'nonce', send:() => true,
        setTimer:timers.setTimer, clearTimer:timers.clearTimer
    });
    mux.openSession({});
    const timedOutCallId = mux.request('write', {}, {write:true}, response => responses.push(response));
    timers.timers[0].callback();
    assert.strictEqual(responses[0].error, 'client_timeout');
    assert.strictEqual(responses[0].requiresReconcile, true);
    assert.strictEqual(mux.pendingCount(), 0);
    assert.strictEqual(mux.handleResponse({
        type:'panel_resp', cmd:'write', callId:timedOutCallId, success:true
    }), false);
    assert.strictEqual(responses.length, 1);
    mux.closeSession();

    const failed = new Runtime.PanelRequestMux({callPrefix:'test', sessionNonce:'nonce', send:() => false});
    failed.openSession({});
    failed.request('snapshot', {}, response => responses.push(response));
    assert.strictEqual(responses[1].error, 'not_sent');
    assert.strictEqual(failed.pendingCount(), 0);
});

test('domain response transform can normalize a malformed success envelope', () => {
    const mux = new Runtime.PanelRequestMux({
        callPrefix:'test', sessionNonce:'nonce', send:() => true,
        validateResponse:(data, entry) => data.callId === entry.callId,
        transformResponse:(data, entry) => typeof data.success === 'boolean' ? data : {
            type:'panel_resp', callId:entry.callId, cmd:entry.cmd,
            success:false, error:'malformed_response'
        }
    });
    mux.openSession({});
    let response = null;
    const callId = mux.request('snapshot', {}, value => { response = value; });
    assert.strictEqual(mux.handleResponse({type:'panel_resp', callId}), true);
    assert.strictEqual(response.error, 'malformed_response');
});

process.stdout.write('Panel runtime ' + passed + '/' + passed + ' passed\n');
