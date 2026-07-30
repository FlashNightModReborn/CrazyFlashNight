'use strict';

const assert = require('assert');
const PanelRuntime = require(
    '../launcher/web/modules/panel-runtime.js');
const TooltipModule = require(
    '../launcher/web/modules/character-build/character-build-candidate-tooltip.js');

let passed = 0;
function test(name, run) {
    run();
    passed++;
    process.stdout.write('ok - ' + name + '\n');
}
function timers() {
    const rows = [];
    return {
        rows,
        setTimer(callback) {
            const row = {callback, cleared:false};
            rows.push(row);
            return row;
        },
        clearTimer(row) { row.cleared = true; },
        expire() {
            const row = rows.slice().reverse().find(value => !value.cleared);
            assert(row, 'expected live timer');
            row.callback();
        }
    };
}
function candidate(slot, lease, key) {
    return {
        key:key || 'backpack:' + slot + ':' + lease,
        name:'候选物品',
        type:'武器',
        presentation:{
            name:'候选物品',
            displayName:'候选物品',
            icon:'候选图标',
            majorType:'武器'
        },
        raw:{
            source:{
                containerId:'背包',
                slot:slot,
                expectedLease:lease
            }
        }
    };
}
function success(message) {
    return {
        success:true,
        v:1,
        itemName:'候选物品',
        displayname:'候选物品',
        iconName:'候选图标',
        itemType:'武器',
        descHTML:'说明',
        introHTML:'<b>候选物品</b>',
        type:'panel_resp',
        domain:'inventory',
        cmd:'tooltip',
        callId:message.callId,
        panel:'workbench',
        panelInstanceId:message.panelInstanceId
    };
}
function tooltipDouble() {
    const state = {scopes:[], options:[]};
    const api = {
        createScope(label) {
            const scope = {
                label,
                disposed:false,
                bindAsync(node, options) {
                    state.options.push(options);
                    return {
                        destroy() { return true; },
                        refresh() {}
                    };
                },
                dispose() {
                    scope.disposed = true;
                    return true;
                }
            };
            state.scopes.push(scope);
            return scope;
        },
        buildItemRichHtml(options) {
            return 'rich:' + options.introHTML + ':' + options.descHTML;
        },
        dynamicIconHtml() { return ''; },
        staticIconUrl() { return null; },
        inferLayoutType() { return 'wide'; }
    };
    return {api, state};
}
function fixture() {
    const sent = [];
    const clock = timers();
    const router = new PanelRuntime.PanelResponseRouter();
    const tooltip = tooltipDouble();
    const adapter = new TooltipModule.CandidateTooltip({
        send(message) { sent.push(message); return true; },
        setTimer:clock.setTimer,
        clearTimer:clock.clearTimer,
        timeoutMs:100,
        sessionNonce:'candidate-tooltip-test',
        router,
        tooltip:tooltip.api
    });
    assert(adapter.reset('panel.workbench.build.1', 7));
    return {adapter, sent, clock, router, tooltip};
}

test('exact inventory envelope carries only candidate tooltip context', function() {
    const value = fixture();
    const row = candidate(2, 'lease.candidate.2');
    value.adapter.bind({}, row);
    let response = null;
    value.tooltip.state.options[0].fetch(row.presentation, data => {
        response = data;
    });
    const message = value.sent[0];
    assert.deepStrictEqual(Object.keys(message).sort(), [
        'callId', 'cmd', 'domain', 'panel', 'panelInstanceId',
        'payload', 'type'
    ]);
    assert.deepStrictEqual(message.payload, {
        v:1,
        source:{
            containerId:'背包',
            slot:2,
            expectedLease:'lease.candidate.2'
        },
        context:{
            kind:'character_build_candidate',
            sessionGeneration:7
        }
    });
    assert(value.router.handleResponse(success(message)));
    assert.strictEqual(response.success, true);
});

test('cache key includes candidate identity generation slot and lease', function() {
    const value = fixture();
    value.adapter.bind({}, candidate(3, 'lease.A', 'candidate-A'));
    const keyA = value.tooltip.state.options[0].key;
    assert(keyA.includes('7'));
    assert(keyA.includes('candidate-A'));
    assert(keyA.includes('3'));
    assert(keyA.includes('lease.A'));
    value.adapter.reset('panel.workbench.build.1', 8);
    value.adapter.bind({}, candidate(3, 'lease.A', 'candidate-A'));
    assert.notStrictEqual(
        value.tooltip.state.options[1].key,
        keyA);
});

test('extra response key fails closed before exact response completes', function() {
    const value = fixture();
    const row = candidate(4, 'lease.candidate.4');
    value.adapter.bind({}, row);
    let callbacks = 0;
    value.tooltip.state.options[0].fetch(row.presentation, () => {
        callbacks++;
    });
    const message = value.sent[0];
    const malformed = success(message);
    malformed.extra = true;
    assert.strictEqual(value.router.handleResponse(malformed), false);
    assert.strictEqual(callbacks, 0);
    assert.strictEqual(value.router.handleResponse(success(message)), true);
    assert.strictEqual(callbacks, 1);
});

test('invalidation cancels pending and late response cannot revive binding', function() {
    const value = fixture();
    const row = candidate(5, 'lease.candidate.5');
    value.adapter.bind({}, row);
    let callbacks = 0;
    value.tooltip.state.options[0].fetch(row.presentation, () => {
        callbacks++;
    });
    const message = value.sent[0];
    const oldScope = value.tooltip.state.scopes[0];
    assert(value.adapter.invalidate());
    assert.strictEqual(oldScope.disposed, true);
    assert.strictEqual(value.router.handleResponse(success(message)), false);
    assert.strictEqual(callbacks, 0);
    assert.strictEqual(value.adapter.debugState().cacheCount, 0);
});

test('timeout is terminal and never replays or retries', function() {
    const value = fixture();
    const row = candidate(6, 'lease.candidate.6');
    value.adapter.bind({}, row);
    let response = null;
    value.tooltip.state.options[0].fetch(row.presentation, data => {
        response = data;
    });
    value.clock.expire();
    assert.strictEqual(value.sent.length, 1);
    assert.strictEqual(response.success, false);
    assert.strictEqual(response.error, 'client_timeout');
});

test('forged source is not bound or sent', function() {
    const value = fixture();
    const row = candidate(50, 'lease.out.of.range');
    const binding = value.adapter.bind({}, row);
    assert.strictEqual(binding.destroy(), false);
    assert.strictEqual(value.tooltip.state.options.length, 0);
    assert.strictEqual(value.sent.length, 0);
});

process.stdout.write(
    'Character Build candidate tooltip: ' + passed + '/' + passed + ' passed\n');
