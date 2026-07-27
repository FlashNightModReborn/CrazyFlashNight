'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
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

function createPanelsFixture(lazyLoader) {
    const handlers = {};
    const sent = [];
    function element() {
        return {
            style:{},
            listeners:{},
            appendChild() {},
            setAttribute() {},
            removeAttribute() {},
            addEventListener(type, handler) { this.listeners[type] = handler; }
        };
    }
    const elements = {
        'panel-container':element(),
        'panel-backdrop':element(),
        'panel-content':element()
    };
    const context = {
        Bridge:{
            on(type, handler) { handlers[type] = handler; },
            send(message) { sent.push(message); }
        },
        Icons:{load(callback) { callback(); }},
        LazyLoader:lazyLoader || {load() { throw new Error('unexpected lazy load'); }},
        document:{
            documentElement:{style:{setProperty() {}}},
            getElementById(id) { return elements[id]; }
        },
        console:{log() {}, error() {}},
        setTimeout() {}
    };
    const source = fs.readFileSync(path.join(
        __dirname, '..', 'launcher', 'web', 'modules', 'panels.js'), 'utf8');
    vm.runInNewContext(source, context, {filename:'panels.js'});
    context.Panels.init();
    return {Panels:context.Panels, handlers, sent, elements};
}

function pendingLazyLoader() {
    return {
        load() {
            return {
                then() {
                    return {catch() {}};
                }
            };
        }
    };
}

function resolvedLazyLoader() {
    return {
        load() {
            return {
                then(resolve) {
                    resolve();
                    return {catch() {}};
                }
            };
        }
    };
}

function rejectedLazyLoader() {
    return {
        load() {
            return {
                then() {
                    return {catch(reject) { reject(new Error('fixture lazy failure')); }};
                }
            };
        }
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

test('pending workbench lazy cancel reports the latest exact Host instance', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.stale'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.current'}
    });
    fixture.handlers.panel_esc({});
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(fixture.sent[0])),
        {
            type:'panel',
            cmd:'close',
            panel:'workbench',
            reason:'lazy_user_cancel',
            panelInstanceId:'panel.workbench.current'
        });
});

test('active panel receives distinct escape and backdrop close reasons', () => {
    const fixture = createPanelsFixture();
    const reasons = [];
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onRequestClose(reason) { reasons.push(reason); }
    });
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_esc({});
    fixture.elements['panel-backdrop'].listeners.click({});
    assert.deepStrictEqual(reasons, ['escape', 'backdrop']);
});

test('workbench mount rejection tears down and returns exact mount_failed close', () => {
    const fixture = createPanelsFixture();
    let closes = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onOpen() { return false; },
        onClose() { closes += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.mount-failed'}
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent[0])), {
        type:'panel',
        cmd:'close',
        panel:'workbench',
        reason:'mount_failed',
        panelInstanceId:'panel.workbench.mount-failed'
    });
});

test('active workbench rebind rejection returns exact replacement mount_failed close', () => {
    const fixture = createPanelsFixture();
    let closes = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onRebind() { return false; },
        onClose() { closes += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.original'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.replacement-failed'}
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent[0])), {
        type:'panel',
        cmd:'close',
        panel:'workbench',
        reason:'mount_failed',
        panelInstanceId:'panel.workbench.replacement-failed'
    });
});

test('async workbench rejection requires the exact active instance', () => {
    const fixture = createPanelsFixture();
    let closes = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onClose() { closes += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.async'}
    });
    assert.strictEqual(
        fixture.Panels.rejectActiveMount('workbench', 'panel.workbench.stale'),
        false);
    assert.strictEqual(fixture.Panels.isOpen(), true);
    assert.strictEqual(
        fixture.Panels.rejectActiveMount('workbench', 'panel.workbench.async'),
        true);
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent[0])), {
        type:'panel',
        cmd:'close',
        panel:'workbench',
        reason:'mount_failed',
        panelInstanceId:'panel.workbench.async'
    });
});

test('pending workbench lazy cancel keeps the exact field missing when Host omitted it', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({cmd:'open', panel:'workbench', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench', reason:'disconnected'
    });
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(fixture.sent[0].panelInstanceId, '');
    assert.strictEqual(fixture.sent[0].reason, 'lazy_user_cancel');
});

test('workbench lazy load and registration failures retain exact Host identity', () => {
    const cases = [
        {
            reason:'lazy_load_failed',
            loader:rejectedLazyLoader(),
            register() {}
        },
        {
            reason:'lazy_register_failed',
            loader:resolvedLazyLoader(),
            register() { throw new Error('fixture register failure'); }
        },
        {
            reason:'lazy_register_missing',
            loader:resolvedLazyLoader(),
            register() {}
        }
    ];
    cases.forEach(row => {
        const fixture = createPanelsFixture(row.loader);
        fixture.Panels.registerLazy('workbench', ['workbench.js'], row.register);
        fixture.handlers.panel_cmd({
            cmd:'open', panel:'workbench',
            initData:{panelInstanceId:'panel.workbench.' + row.reason}
        });
        assert.strictEqual(fixture.sent.length, 1);
        assert.strictEqual(fixture.sent[0].reason, row.reason);
        assert.strictEqual(
            fixture.sent[0].panelInstanceId, 'panel.workbench.' + row.reason);
    });
});

test('workbench force close rejects missing and stale identity after replacement', () => {
    const fixture = createPanelsFixture();
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onRebind() {},
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.old'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.replacement'}
    });
    fixture.handlers.panel_cmd({cmd:'force_close', reason:'disconnected'});
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.old', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), true);
    assert.strictEqual(closes, 0);
    assert.strictEqual(forceCloses, 0);

    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.replacement', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
});

test('pending workbench does not swallow generic force close for active ordinary panel', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.pending'}
    });
    fixture.handlers.panel_cmd({cmd:'force_close', reason:'disconnected'});
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 0);
});

test('targeted pending workbench force close also clears the ordinary panel underneath', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.pending'}
    });
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.pending', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 0);
});

test('generic force close cancels an ordinary replacement and clears the old workbench', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.Panels.registerLazy('help', ['help.js'], () => {});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.active'}
    });
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({cmd:'force_close', reason:'disconnected'});
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 0);
});

test('stale targeted identity preserves an ordinary active panel and workbench replacement', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.replacement'}
    });
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.stale', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), true);
    assert.strictEqual(closes, 0);
    assert.strictEqual(forceCloses, 0);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(fixture.sent[0].panelInstanceId, 'panel.workbench.replacement');
});

test('exact active workbench close preserves a different pending ordinary replacement', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    let closes = 0;
    let forceCloses = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onClose() { closes += 1; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.Panels.registerLazy('help', ['help.js'], () => {});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.active'}
    });
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.active', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(fixture.sent[0].panel, 'help');
});

test('ordinary panels retain generic force-close compatibility', () => {
    const fixture = createPanelsFixture();
    let forceCloses = 0;
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onForceClose() { forceCloses += 1; }
    });
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_cmd({cmd:'force_close', reason:'disconnected'});
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(forceCloses, 1);
});

process.stdout.write('Panel runtime ' + passed + '/' + passed + ' passed\n');
