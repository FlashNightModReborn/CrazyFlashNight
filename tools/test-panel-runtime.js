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

function createPanelsFixture(lazyLoader, sendOverride) {
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
            send(message) {
                if (typeof sendOverride === 'function') {
                    return sendOverride(message, sent);
                }
                sent.push(message);
                return true;
            }
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

function controlledLazyLoader() {
    let resolve = null;
    return {
        load() {
            return {
                then(callback) {
                    resolve = callback;
                    return {catch() {}};
                }
            };
        },
        resolve() {
            assert.strictEqual(typeof resolve, 'function');
            resolve();
        }
    };
}

function queuedControlledLazyLoader() {
    const resolves = [];
    return {
        load() {
            return {
                then(callback) {
                    resolves.push(callback);
                    return {catch() {}};
                }
            };
        },
        resolveAll() {
            while (resolves.length) resolves.shift()();
        },
        pendingCount() { return resolves.length; }
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
    let requestReturned = false;
    let failedEntry = null;
    const failedCallId = failed.request('snapshot', {}, (response, entry) => {
        assert.strictEqual(requestReturned, false);
        responses.push(response);
        failedEntry = entry;
    });
    requestReturned = true;
    assert.ok(failedCallId);
    assert.strictEqual(responses[1].error, 'not_sent');
    assert.strictEqual(responses[1].callId, failedCallId);
    assert.strictEqual(failedEntry.callId, failedCallId);
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

test('pending cancel retries the exact tuple after Bridge.send throws and a newer open clears it', () => {
    const closeReasons = [];
    const fixture = createPanelsFixture(
        pendingLazyLoader(),
        (message, sent) => {
            sent.push(message);
            throw new Error('fixture bridge send failure');
        });
    fixture.Panels.registerLazy('skills', ['skills.js'], () => {});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.pending-send-throw'}
    });
    assert.doesNotThrow(() => fixture.handlers.panel_esc({}));
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(
        fixture.sent[0].panelInstanceId,
        'panel.skills.pending-send-throw');
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 2);
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(fixture.sent[1])),
        JSON.parse(JSON.stringify(fixture.sent[0])));
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onRequestClose(reason) { closeReasons.push(reason); }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'help', initData:{}
    });
    assert.strictEqual(fixture.Panels.getActive(), 'help');
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 2);
    assert.deepStrictEqual(closeReasons, ['escape']);
});

test('pending exact close retries after a false send and cancelled lazy work cannot revive', () => {
    const loader = controlledLazyLoader();
    const fixture = createPanelsFixture(
        loader,
        (message, sent) => {
            sent.push(message);
            return sent.length > 1;
        });
    fixture.Panels.registerLazy('skills', ['skills.js'], () => {
        fixture.Panels.register('skills', {
            create() { return {style:{}}; }
        });
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.retry-false'}
    });
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 1);
    fixture.elements['panel-backdrop'].listeners.click({});
    assert.strictEqual(fixture.sent.length, 2);
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(fixture.sent[1])),
        JSON.parse(JSON.stringify(fixture.sent[0])));
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 2);
    loader.resolve();
    assert.strictEqual(fixture.Panels.getActive(), null);
    assert.strictEqual(fixture.Panels.isOpen(), false);
});

test('active panel receives exact host escape/backdrop/toggle close reasons', () => {
    const fixture = createPanelsFixture();
    const reasons = [];
    fixture.Panels.register('help', {
        create() { return {style:{}}; },
        onRequestClose(reason) { reasons.push(reason); }
    });
    fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
    fixture.handlers.panel_esc({reason:'escape'});
    fixture.handlers.panel_esc({reason:'backdrop'});
    fixture.handlers.panel_esc({reason:'toggle'});
    fixture.handlers.panel_esc({reason:'unknown'});
    fixture.elements['panel-backdrop'].listeners.click({});
    assert.deepStrictEqual(
        reasons, ['escape', 'backdrop', 'toggle', 'escape', 'backdrop']);
});

test('pending NPCShop lazy owner preserves exact escape, backdrop, and toggle reasons', () => {
    for (const reason of ['escape', 'backdrop', 'toggle']) {
        const fixture = createPanelsFixture(pendingLazyLoader());
        fixture.Panels.registerLazy('npcshop', ['npcshop.js'], () => {});
        const panelInstanceId = 'panel.npcshop.pending-' + reason;
        fixture.handlers.panel_cmd({cmd:'open',panel:'npcshop',initData:{panelInstanceId}});
        if (reason === 'backdrop') fixture.elements['panel-backdrop'].listeners.click({});
        else fixture.handlers.panel_esc({reason});
        assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent)), [{
            type:'panel',cmd:'close',panel:'npcshop',panelInstanceId,reason
        }]);
        assert.strictEqual(fixture.Panels.getActive(), null);
    }
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

test('active workbench rebind exception returns exact replacement mount_failed close', () => {
    const fixture = createPanelsFixture();
    let closes = 0;
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onRebind() { throw new Error('fixture rebind failure'); },
        onClose() { closes += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.original'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.replacement-threw'}
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent[0])), {
        type:'panel',
        cmd:'close',
        panel:'workbench',
        reason:'mount_failed',
        panelInstanceId:'panel.workbench.replacement-threw'
    });
});

test('new same-panel rebind retires an older pending switch before lazy completion', () => {
    const loader = controlledLazyLoader();
    const fixture = createPanelsFixture(loader);
    const rebound = [];
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onRebind(el, initData) { rebound.push(initData.panelInstanceId); }
    });
    fixture.Panels.registerLazy('skills', ['skills.js'], () => {
        fixture.Panels.register('skills', {
            create() { return {style:{}}; }
        });
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.original'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.stale-pending'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.latest'}
    });
    assert.strictEqual(fixture.Panels.getActive(), 'workbench');
    assert.deepStrictEqual(rebound, ['panel.workbench.latest']);
    loader.resolve();
    assert.strictEqual(fixture.Panels.getActive(), 'workbench');
    assert.strictEqual(fixture.sent.length, 0);
});

test('panel create throw or truthy non-Element fail closed with one exact Host release', () => {
    [
        {
            panel:'workbench',
            initData:{panelInstanceId:'panel.workbench.create-throw'},
            create() { throw new Error('fixture create failure'); },
            expected:{
                type:'panel', cmd:'close', panel:'workbench',
                reason:'mount_failed',
                panelInstanceId:'panel.workbench.create-throw'
            }
        },
        {
            panel:'skills',
            initData:{panelInstanceId:'panel.skills.create-text-node'},
            create() { return {nodeType:3, style:{}}; },
            expected:{
                type:'panel', cmd:'close', panel:'skills',
                panelInstanceId:'panel.skills.create-text-node'
            }
        }
    ].forEach(row => {
        const fixture = createPanelsFixture();
        let closes = 0;
        fixture.Panels.register(row.panel, {
            create:row.create,
            onClose() { closes += 1; }
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:row.panel, initData:row.initData
        });
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(fixture.Panels.getActive(), null);
        assert.strictEqual(fixture.elements['panel-container'].style.display, 'none');
        assert.strictEqual(closes, 1);
        assert.strictEqual(fixture.sent.length, 1);
        fixture.handlers.panel_esc({});
        assert.strictEqual(fixture.sent.length, 1);
        assert.deepStrictEqual(
            JSON.parse(JSON.stringify(fixture.sent[0])),
            row.expected);
    });
});

test('outgoing onClose throw cannot strand an incoming exact panel transition', () => {
    const successful = createPanelsFixture();
    successful.Panels.register('help', {
        create() { return {style:{}}; },
        onClose() { throw new Error('fixture close cleanup failure'); }
    });
    successful.Panels.register('workbench', {
        create() { return {style:{}}; }
    });
    successful.handlers.panel_cmd({
        cmd:'open', panel:'help', initData:{}
    });
    successful.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.after-close-throw'}
    });
    assert.strictEqual(successful.Panels.getActive(), 'workbench');
    assert.strictEqual(
        successful.elements['panel-container'].style.display, '');
    assert.strictEqual(successful.sent.length, 0);

    const rejected = createPanelsFixture();
    rejected.Panels.register('help', {
        create() { return {style:{}}; },
        onClose() { throw new Error('fixture close cleanup failure'); }
    });
    rejected.Panels.register('workbench', {
        create() { return {style:{}}; },
        onOpen() { return false; }
    });
    rejected.handlers.panel_cmd({
        cmd:'open', panel:'help', initData:{}
    });
    rejected.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.rejected-after-close-throw'}
    });
    assert.strictEqual(rejected.Panels.isOpen(), false);
    assert.strictEqual(
        rejected.elements['panel-container'].style.display, 'none');
    assert.strictEqual(rejected.sent.length, 1);
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(rejected.sent[0])),
        {
            type:'panel', cmd:'close', panel:'workbench',
            reason:'mount_failed',
            panelInstanceId:'panel.workbench.rejected-after-close-throw'
        });
});

test('missing Host-owned registries release each owner exactly once and clear visuals', () => {
    [
        {
            panel:'skills',
            initData:{panelInstanceId:'panel.skills.registry-missing'},
            expected:{
                type:'panel', cmd:'close', panel:'skills',
                panelInstanceId:'panel.skills.registry-missing'
            }
        },
        {
            panel:'crafting',
            initData:{category:'武器合成', panelInstanceId:'panel.crafting.registry-missing'},
            expected:{
                type:'panel', cmd:'close', panel:'crafting',
                panelInstanceId:'panel.crafting.registry-missing'
            }
        },
        {
            panel:'kshop',
            initData:{panelInstanceId:'panel.kshop.registry-missing'},
            expected:{
                type:'panel', cmd:'close', panel:'kshop',
                panelInstanceId:'panel.kshop.registry-missing'
            }
        },
        {
            panel:'npcshop',
            initData:{panelInstanceId:'panel.npcshop.registry-missing'},
            expected:{
                type:'panel', cmd:'close', panel:'npcshop',
                panelInstanceId:'panel.npcshop.registry-missing'
            }
        }
    ].forEach(row => {
        const fixture = createPanelsFixture();
        fixture.handlers.panel_cmd({
            cmd:'open', panel:row.panel, initData:row.initData
        });
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(fixture.Panels.getActive(), null);
        assert.strictEqual(fixture.elements['panel-container'].style.display, 'none');
        assert.strictEqual(fixture.sent.length, 1);
        fixture.handlers.panel_esc({});
        assert.strictEqual(fixture.sent.length, 1);
        assert.deepStrictEqual(
            JSON.parse(JSON.stringify(fixture.sent[0])),
            row.expected);
    });
});

test('rebind failure close retries only the rejected replacement tuple', () => {
    const fixture = createPanelsFixture(
        null,
        (message, sent) => {
            sent.push(message);
            return sent.length > 1;
        });
    fixture.Panels.register('skills', {
        create() { return {style:{}}; },
        onRebind() { return false; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.rebind-original'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.rebind-rejected'}
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(
        fixture.sent[0].panelInstanceId, 'panel.skills.rebind-rejected');
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 2);
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(fixture.sent[1])),
        JSON.parse(JSON.stringify(fixture.sent[0])));
});

test('mount failure close retries the same exact tuple after a false send', () => {
    const fixture = createPanelsFixture(
        null,
        (message, sent) => {
            sent.push(message);
            return sent.length > 1;
        });
    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onOpen() { return false; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.mount-retry'}
    });
    assert.strictEqual(fixture.sent.length, 1);
    fixture.elements['panel-backdrop'].listeners.click({});
    assert.strictEqual(fixture.sent.length, 2);
    assert.deepStrictEqual(
        JSON.parse(JSON.stringify(fixture.sent[1])),
        JSON.parse(JSON.stringify(fixture.sent[0])));
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 2);
});

['crafting', 'kshop', 'npcshop'].forEach(panelId => {
    test(panelId + ' top-level owner rejects registry/lazy failures and loading cancel exactly once', () => {
        function expectedClose(instance, reason) {
            const message = {
                type:'panel', panel:panelId, cmd:'close',
                panelInstanceId:instance
            };
            if (reason) message.reason = reason;
            return message;
        }

        const missing = createPanelsFixture();
        const missingInstance = 'panel.' + panelId + '.registry-missing-dynamic';
        missing.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:missingInstance}
        });
        assert.deepStrictEqual(
            JSON.parse(JSON.stringify(missing.sent)),
            [expectedClose(missingInstance)]);
        assert.strictEqual(missing.Panels.getActive(), null);
        assert.strictEqual(missing.Panels.isOpen(), false);
        assert.strictEqual(missing.elements['panel-container'].style.display, 'none');
        missing.handlers.panel_esc({});
        assert.strictEqual(missing.sent.length, 1);

        const rejected = createPanelsFixture(rejectedLazyLoader());
        const rejectedInstance = 'panel.' + panelId + '.lazy-rejected';
        rejected.Panels.registerLazy(panelId, [panelId + '.js'], () => {});
        rejected.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:rejectedInstance}
        });
        assert.deepStrictEqual(
            JSON.parse(JSON.stringify(rejected.sent)),
            [expectedClose(rejectedInstance)]);
        assert.strictEqual(rejected.Panels.getActive(), null);
        assert.strictEqual(rejected.Panels.isOpen(), false);
        rejected.handlers.panel_esc({});
        assert.strictEqual(rejected.sent.length, 1);

        const loader = queuedControlledLazyLoader();
        const cancelled = createPanelsFixture(loader);
        const staleInstance = 'panel.' + panelId + '.loading-stale';
        const currentInstance = 'panel.' + panelId + '.loading-current';
        cancelled.Panels.registerLazy(panelId, [panelId + '.js'], () => {
            cancelled.Panels.register(panelId, {
                create() { return {style:{}}; }
            });
        });
        cancelled.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:staleInstance}
        });
        cancelled.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:currentInstance}
        });
        assert.strictEqual(loader.pendingCount(), 2);
        cancelled.handlers.panel_esc({});
        assert.deepStrictEqual(
            JSON.parse(JSON.stringify(cancelled.sent)),
            [expectedClose(currentInstance, panelId === 'npcshop' ? 'escape' : '')]);
        cancelled.handlers.panel_esc({});
        loader.resolveAll();
        assert.strictEqual(cancelled.sent.length, 1);
        assert.strictEqual(cancelled.Panels.getActive(), null);
        assert.strictEqual(cancelled.Panels.isOpen(), false);
        assert.notStrictEqual(
            cancelled.elements['panel-container'].style.display, '');
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

test('pending Host-owned cancel suppresses an unsafe close when exact identity is missing', () => {
    const fixture = createPanelsFixture(pendingLazyLoader());
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({cmd:'open', panel:'workbench', initData:{}});
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench', reason:'disconnected'
    });
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 0);
    assert.strictEqual(fixture.Panels.getActive(), null);
    assert.strictEqual(fixture.Panels.isOpen(), false);
});

test('workbench lazy load and registration failures retain exact Host identity', () => {
    const cases = [
        {
            reason:'lazy_load_failed',
            loader:{
                load() { throw new Error('fixture synchronous lazy failure'); }
            },
            register() {}
        },
        {
            reason:'lazy_load_failed',
            loader:{
                load() { return {}; }
            },
            register() {}
        },
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

test('all Host-owned surfaces reject generic, missing, and stale close after exact replacement', () => {
    ['workbench', 'loot', 'skills', 'crafting', 'kshop', 'npcshop'].forEach(panelId => {
        const fixture = createPanelsFixture();
        let closes = 0;
        let forceCloses = 0;
        fixture.Panels.register(panelId, {
            create() { return {style:{}}; },
            onRebind() {},
            onClose() { closes += 1; },
            onForceClose() { forceCloses += 1; }
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:'panel.' + panelId + '.old'}
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:'panel.' + panelId + '.replacement'}
        });
        fixture.handlers.panel_cmd({cmd:'force_close', reason:'disconnected'});
        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId, reason:'disconnected'
        });
        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.old', reason:'disconnected'
        });
        assert.strictEqual(fixture.Panels.getActive(), panelId);
        assert.strictEqual(closes, 0);
        assert.strictEqual(forceCloses, 0);

        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.replacement',
            reason:'disconnected'
        });
        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.replacement',
            reason:'disconnected'
        });
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(closes, 1);
        assert.strictEqual(forceCloses, 1);
    });
});

test('committed crafting to NPCShop replacement failure retires displaced source before exact target close', () => {
    const cases = [
        {
            reason:'lazy_load_failed',
            loader:{load() { throw new Error('fixture lazy load failure'); }},
            register() {}
        },
        {
            reason:'lazy_register_failed',
            loader:resolvedLazyLoader(),
            register() { throw new Error('fixture lazy register failure'); }
        },
        {
            reason:'lazy_register_missing',
            loader:resolvedLazyLoader(),
            register() {}
        }
    ];
    cases.forEach(row => {
        const fixture = createPanelsFixture(row.loader);
        let sourceCloses = 0;
        fixture.Panels.register('crafting', {
            create() { return {style:{}}; },
            onClose() { sourceCloses += 1; }
        });
        fixture.Panels.registerLazy('npcshop', ['npcshop.js'], row.register);
        fixture.handlers.panel_cmd({
            cmd:'open', panel:'crafting',
            initData:{panelInstanceId:'panel.crafting.displaced.' + row.reason}
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:'npcshop',
            initData:{panelInstanceId:'panel.npcshop.failed.' + row.reason}
        });
        assert.strictEqual(fixture.Panels.getActive(), null);
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(sourceCloses, 1);
        assert.deepStrictEqual(JSON.parse(JSON.stringify(fixture.sent)), [{
            type:'panel', cmd:'close', panel:'npcshop',
            panelInstanceId:'panel.npcshop.failed.' + row.reason
        }]);
        fixture.handlers.panel_cmd({
            cmd:'close', panel:'npcshop',
            panelInstanceId:'panel.npcshop.failed.' + row.reason
        });
        assert.strictEqual(fixture.Panels.getActive(), null);
        assert.strictEqual(sourceCloses, 1);
    });
});

test('ordinary Host close commits only the exact active instance and ignores late predecessor delivery', () => {
    ['workbench', 'loot', 'skills', 'crafting', 'kshop', 'npcshop'].forEach(panelId => {
        const fixture = createPanelsFixture();
        let closes = 0;
        fixture.Panels.register(panelId, {
            create() { return {style:{}}; },
            onRebind() {},
            onClose() { closes += 1; }
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:'panel.' + panelId + '.old-close'}
        });
        fixture.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:'panel.' + panelId + '.current-close'}
        });
        fixture.handlers.panel_cmd({cmd:'close'});
        fixture.handlers.panel_cmd({cmd:'close', panel:panelId});
        fixture.handlers.panel_cmd({
            cmd:'close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.old-close'
        });
        assert.strictEqual(fixture.Panels.getActive(), panelId);
        assert.strictEqual(closes, 0);
        fixture.handlers.panel_cmd({
            cmd:'close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.current-close'
        });
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(closes, 1);
    });
});

test('ordinary non-capability panels retain generic and matching-target close compatibility', () => {
    ['generic', 'targeted'].forEach(mode => {
        const fixture = createPanelsFixture();
        let closes = 0;
        fixture.Panels.register('help', {
            create() { return {style:{}}; },
            onClose() { closes += 1; }
        });
        fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
        fixture.handlers.panel_cmd(mode === 'generic'
            ? {cmd:'close'} : {cmd:'close', panel:'help'});
        assert.strictEqual(fixture.Panels.isOpen(), false);
        assert.strictEqual(closes, 1);
    });
});

test('all Host-owned pending surfaces require an exact tuple and retire displaced UI', () => {
    ['workbench', 'loot', 'skills', 'crafting', 'kshop', 'npcshop'].forEach(panelId => {
        const fixture = createPanelsFixture(pendingLazyLoader());
        let closes = 0;
        let forceCloses = 0;
        fixture.Panels.register('help', {
            create() { return {style:{}}; },
            onClose() { closes += 1; },
            onForceClose() { forceCloses += 1; }
        });
        fixture.Panels.registerLazy(panelId, [panelId + '.js'], () => {});
        fixture.handlers.panel_cmd({cmd:'open', panel:'help', initData:{}});
        fixture.handlers.panel_cmd({
            cmd:'open', panel:panelId,
            initData:{panelInstanceId:'panel.' + panelId + '.pending'}
        });
        fixture.handlers.panel_cmd({cmd:'force_close', panel:panelId});
        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.stale',
            reason:'disconnected'
        });
        assert.strictEqual(fixture.Panels.getActive(), 'help');

        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.pending',
            reason:'disconnected'
        });
        fixture.handlers.panel_cmd({
            cmd:'force_close', panel:panelId,
            panelInstanceId:'panel.' + panelId + '.pending',
            reason:'disconnected'
        });
        assert.strictEqual(fixture.Panels.getActive(), null);
        assert.strictEqual(closes, 1);
        assert.strictEqual(forceCloses, 1);
        assert.strictEqual(fixture.sent.length, 0);
        fixture.handlers.panel_esc({});
        assert.strictEqual(fixture.sent.length, 0);
    });
});

test('a failed exact close latch cannot act on a newer same-surface instance', () => {
    const fixture = createPanelsFixture(
        pendingLazyLoader(),
        (message, sent) => {
            sent.push(message);
            return false;
        });
    const reasons = [];
    let closes = 0;
    fixture.Panels.registerLazy('workbench', ['workbench.js'], () => {});
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.latch-old'}
    });
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 1);

    fixture.Panels.register('workbench', {
        create() { return {style:{}}; },
        onRequestClose(reason) { reasons.push(reason); },
        onClose() { closes += 1; }
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.latch-new'}
    });
    fixture.elements['panel-backdrop'].listeners.click({});
    assert.strictEqual(fixture.sent.length, 1);
    assert.deepStrictEqual(reasons, ['backdrop']);
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.latch-old', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.getActive(), 'workbench');
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'workbench',
        panelInstanceId:'panel.workbench.latch-new', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
});

test('older same-name lazy completion cannot overwrite the newer exact instance', () => {
    const loader = queuedControlledLazyLoader();
    const fixture = createPanelsFixture(loader);
    let closes = 0;
    fixture.Panels.registerLazy('skills', ['skills.js'], () => {
        fixture.Panels.register('skills', {
            create() { return {style:{}}; },
            onClose() { closes += 1; }
        });
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.lazy-old'}
    });
    fixture.handlers.panel_cmd({
        cmd:'open', panel:'skills',
        initData:{panelInstanceId:'panel.skills.lazy-new'}
    });
    assert.strictEqual(loader.pendingCount(), 2);
    loader.resolveAll();
    assert.strictEqual(fixture.Panels.getActive(), 'skills');
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'skills',
        panelInstanceId:'panel.skills.lazy-old', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.getActive(), 'skills');
    fixture.handlers.panel_cmd({
        cmd:'force_close', panel:'skills',
        panelInstanceId:'panel.skills.lazy-new', reason:'disconnected'
    });
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
});

test('generic force close retires an ordinary active panel but preserves capability pending', () => {
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
    assert.strictEqual(fixture.sent.length, 1);
    assert.strictEqual(
        fixture.sent[0].panelInstanceId, 'panel.workbench.pending');
});

test('targeted pending capability force close retires the displaced ordinary panel', () => {
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
    assert.strictEqual(fixture.Panels.getActive(), null);
    assert.strictEqual(fixture.Panels.isOpen(), false);
    assert.strictEqual(closes, 1);
    assert.strictEqual(forceCloses, 1);
    fixture.handlers.panel_esc({});
    assert.strictEqual(fixture.sent.length, 0);
});

test('generic force close cancels an ordinary replacement and retires its displaced capability', () => {
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
    assert.strictEqual(fixture.Panels.getActive(), null);
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

test('force-close callback throws are isolated after generic and exact state retirement', () => {
    const ordinary = createPanelsFixture();
    ordinary.Panels.register('help', {
        create() { return {style:{}}; },
        onForceClose() { throw new Error('fixture generic force cleanup failure'); }
    });
    ordinary.handlers.panel_cmd({
        cmd:'open', panel:'help', initData:{}
    });
    assert.doesNotThrow(() => ordinary.handlers.panel_cmd({
        cmd:'force_close', reason:'disconnected'
    }));
    assert.strictEqual(ordinary.Panels.isOpen(), false);
    ordinary.Panels.register('next', {
        create() { return {style:{}}; }
    });
    ordinary.handlers.panel_cmd({
        cmd:'open', panel:'next', initData:{}
    });
    assert.strictEqual(ordinary.Panels.getActive(), 'next');

    const exact = createPanelsFixture();
    exact.Panels.register('workbench', {
        create() { return {style:{}}; },
        onForceClose() { throw new Error('fixture exact force cleanup failure'); }
    });
    exact.handlers.panel_cmd({
        cmd:'open', panel:'workbench',
        initData:{panelInstanceId:'panel.workbench.force-callback-throw'}
    });
    assert.doesNotThrow(() => exact.handlers.panel_cmd({
        cmd:'force_close',
        panel:'workbench',
        panelInstanceId:'panel.workbench.force-callback-throw',
        reason:'disconnected'
    }));
    assert.strictEqual(exact.Panels.isOpen(), false);
});

process.stdout.write('Panel runtime ' + passed + '/' + passed + ' passed\n');
