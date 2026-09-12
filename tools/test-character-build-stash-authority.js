'use strict';

const assert = require('assert');
const PanelRuntime = require('../launcher/web/modules/panel-runtime.js');
const Authority = require(
    '../launcher/web/modules/character-build/character-build-stash-authority.js');
const Build = require('../launcher/web/modules/character-build.js');

let passed = 0;
function check(name, callback) {
    callback();
    passed++;
    process.stdout.write('PASS ' + name + '\n');
}

function snapshotPayload() {
    const cooldown = {ready:true, totalSteps:0, currentStep:0,
        progressPercent:0, animationFrame:1, remainingMs:0};
    const layout = {v:2, bankCount:2, laneCount:4, physicalSlotCount:8,
        activeBank:0, switchKeyLabel:'T', switchCooldown:cooldown};
    const drugs = [];
    for (let slot = 0; slot < 8; slot++) {
        drugs.push({slot:slot, bank:Math.floor(slot / 4), lane:slot % 4,
            active:Math.floor(slot / 4) === 0, keyLabel:String(slot % 4 + 1),
            ready:true, totalSteps:0, currentStep:0, progressPercent:0,
            animationFrame:1, remainingMs:0, occupied:false, quantity:0});
    }
    return {
        equipment:Array.from({length:11}, () => ({occupied:false})),
        drugs:drugs, drugLayout:layout,
        portrait:{gender:'男', equipment:{}, appearance:{}},
        stateHealth:'ok', diagnostics:[]
    };
}

function commonFields(request, extra) {
    return Object.assign({
        type:'panel_resp', panel:'workbench', domain:'loadout',
        cmd:request.cmd, callId:request.callId,
        panelInstanceId:'panel.workbench.7',
        v:1, success:true, writeEpoch:0, sessionGeneration:3,
        loadoutRevision:0, liveRevision:0, drugRevision:0,
        liveRefreshDirty:false, active:true
    }, extra || {});
}

function itemUseFields(request, extra) {
    return Object.assign({
        type:'panel_resp', panel:'workbench', domain:'item_use',
        cmd:request.cmd, callId:request.callId,
        panelInstanceId:'panel.workbench.7'
    }, extra || {});
}

function harness(options) {
    options = options || {};
    const sent = [];
    const router = new PanelRuntime.PanelResponseRouter();
    const toasts = [];
    const authority = Authority.create({
        send:message => { sent.push(message); return true; },
        router:router,
        timeoutMs:60000,
        sessionNonce:'test',
        setTimer:() => ({timer:true}),
        clearTimer:() => {},
        getBuild:() => options.build || null,
        panelInstanceId:'panel.workbench.7',
        onStatus:() => {},
        toast:message => toasts.push(message)
    });
    return {authority, router, sent, toasts};
}

function openHeadless(run) {
    const acquired = [];
    run.authority.acquire(handle => acquired.push(handle));
    const snapshot = run.sent.find(message => message.cmd === 'snapshot');
    assert(snapshot, 'headless acquire must issue a snapshot open request');
    run.router.handleResponse(commonFields(snapshot, {payload:snapshotPayload()}));
    assert.strictEqual(acquired.length, 1);
    return acquired[0];
}

check('headless acquire opens a real session and yields the exact generation', function() {
    const run = harness();
    const handle = openHeadless(run);
    assert.strictEqual(handle.headless, true);
    assert.strictEqual(handle.generation, 3);
    assert.strictEqual(typeof handle.itemUse.bind, 'function');
    run.authority.release();
    const second = [];
    run.authority.acquire(handle => second.push(handle));
    assert.strictEqual(second.length, 1, 're-acquire reuses the open session');
    assert.strictEqual(second[0].generation, 3, 'no second generation is minted');
});

check('headless item-use requests carry the exact panelInstanceId + generation', function() {
    const run = harness();
    const handle = openHeadless(run);
    handle.itemUse.requestStashPage(0, () => {});
    const page = run.sent.find(message => message.domain === 'item_use');
    assert(page, 'stash page request must ride the item_use domain');
    assert.strictEqual(page.panelInstanceId, 'panel.workbench.7');
    assert.strictEqual(page.payload.sessionGeneration, 3);
    assert.strictEqual(page.payload.panelInstanceId, 'panel.workbench.7');
});

check('a pending stash write and an unreconciled result both block closing', function() {
    const run = harness();
    const handle = openHeadless(run);
    handle.itemUse.requestStashPage(0, () => {});
    const page = run.sent.filter(message => message.cmd === 'stashPage').pop();
    run.router.handleResponse(itemUseFields(page, {
        success:true,
        data:{storeId:'stash.saved', revision:7, offset:0, total:1, entries:[]}
    }));
    const results = [];
    assert(handle.itemUse.invokeStash('stashTake', {
        storeId:'stash.saved', expectedRevision:7,
        entries:[{entryId:'stash.saved.e1', revision:1, quantity:1}]
    }, (value, committed) => results.push({value, committed})));
    run.authority.release();
    assert.strictEqual(run.authority.canClose(), false,
        'released write_pending must still block close');
    const write = run.sent.filter(message => message.cmd === 'stashTake').pop();
    run.router.handleResponse(itemUseFields(write, {
        success:false, error:'client_timeout', requiresReconcile:true
    }));
    assert.strictEqual(run.authority.canClose(), false,
        'needs_reconcile must keep blocking close');
    const finalizeResults = [];
    assert.strictEqual(run.authority.finalize(
        accepted => finalizeResults.push(accepted)), null,
        'finalize must refuse to issue while a write is unresolved');
    assert.deepStrictEqual(finalizeResults, [false]);
    assert.strictEqual(run.sent.filter(m => m.cmd === 'finalize').length, 0,
        'no finalize request may be sent while the take result is unknown');
    const query = run.sent.filter(message => message.cmd === 'stashQuery').pop();
    run.router.handleResponse(itemUseFields(query, {
        success:true, data:{state:'pending'}
    }));
    assert.strictEqual(run.authority.canClose(), false, 'pending query result still blocks');
    handle.itemUse.reconcile();
    const retry = run.sent.filter(message => message.cmd === 'stashQuery').pop();
    run.router.handleResponse(itemUseFields(retry, {
        success:true, data:{state:'committed', result:{taken:1}}
    }));
    assert.deepStrictEqual(results, [{value:{taken:1}, committed:true}]);
    assert.strictEqual(run.authority.canClose(), true);
});

check('headless finalize produces the session finalize proof before close', function() {
    const run = harness();
    openHeadless(run);
    const finalized = [];
    const callId = run.authority.finalize(accepted => finalized.push(accepted));
    assert(callId, 'finalize must issue the loadout finalize request');
    const request = run.sent.find(message => message.cmd === 'finalize');
    assert(request, 'finalize request must ride the loadout domain');
    assert.strictEqual(request.payload.sessionGeneration, 3);
    run.router.handleResponse(commonFields(request, {
        closed:true, active:false, liveChanged:false,
        persistence:{success:true, changed:false}
    }));
    assert.deepStrictEqual(finalized, [true]);
    assert.strictEqual(run.authority.canClose(), true);
});

check('releasing a source preserves headless finalize responsibility exactly once', function() {
    const run = harness();
    openHeadless(run);
    run.authority.release();
    const finalized = [];
    assert(run.authority.finalize(ok => finalized.push(ok)));
    assert.strictEqual(run.authority.canClose(), false, 'finalizing is still busy');
    const request = run.sent.find(message => message.cmd === 'finalize');
    assert(request, 'returning to the physical container must not drop finalize');
    run.router.handleResponse(commonFields(request, {
        closed:true, active:false, liveChanged:false,
        persistence:{success:true, changed:false}
    }));
    assert.deepStrictEqual(finalized, [true]);
    run.authority.finalize(ok => finalized.push(ok));
    assert.deepStrictEqual(finalized, [true, true]);
    assert.strictEqual(run.sent.filter(message => message.cmd === 'finalize').length, 1);
    run.authority.destroy();
});

check('destroy isolates a late open response from the released authority', function() {
    const run = harness();
    const acquired = [];
    run.authority.acquire(handle => acquired.push(handle));
    const snapshot = run.sent.find(message => message.cmd === 'snapshot');
    run.authority.destroy();
    assert.deepStrictEqual(acquired, [null],
        'destroy flushes pending acquire waiters with null');
    // A late snapshot response must not rebind a new handle on the corpse.
    run.router.handleResponse(commonFields(snapshot, {payload:snapshotPayload()}));
    assert.strictEqual(acquired.length, 1);
    const late = [];
    run.authority.acquire(handle => late.push(handle));
    assert.deepStrictEqual(late, [null]);
});

check('borrowed acquire takes the build exact channel and holds it across suspend', function() {
    const sent = [];
    const router = new PanelRuntime.PanelResponseRouter();
    const itemUse = new (require(
        '../launcher/web/modules/character-build/character-build-item-use.js').Controller)({
        send:message => { sent.push(message); return true; },
        router:router,
        operationNonce:'borrowed'
    });
    assert.strictEqual(itemUse.bind('panel.workbench.7', 9), true);
    let closes = 0;
    const realClose = itemUse.close.bind(itemUse);
    itemUse.close = function() { closes++; return realClose(); };
    const build = {
        holds:0,
        itemUseAuthority:function() {
            return {itemUse:itemUse, panelInstanceId:'panel.workbench.7', generation:9};
        },
        whenItemUseReady:function(callback) { callback(this.itemUseAuthority()); return true; },
        holdItemUse:function() { this.holds++; return this.holds; },
        releaseItemUse:function() { if (this.holds > 0) this.holds--; return this.holds; }
    };
    const run = harness({build:build});
    const acquired = [];
    run.authority.acquire(handle => acquired.push(handle));
    assert.strictEqual(acquired[0].headless, false);
    assert.strictEqual(acquired[0].generation, 9);
    assert.strictEqual(acquired[0].itemUse, itemUse);
    assert.strictEqual(build.holds, 1);
    assert.strictEqual(sent.length, 0,
        'borrowed acquire must not mint a second session');
    run.authority.release();
    assert.strictEqual(build.holds, 0);
    run.authority.acquire(handle => acquired.push(handle));
    assert.strictEqual(build.holds, 1, 're-acquire holds again');
    run.authority.destroy();
    assert.strictEqual(build.holds, 0, 'destroy releases the hold');
    assert.strictEqual(itemUse.debugState().state, 'idle',
        'borrowed destroy must not tear down the build-owned channel');
    assert.strictEqual(closes, 0);
});

check('borrowed waiters flush on whenItemUseReady and survive until then', function() {
    let ready = null;
    const waiters = [];
    const build = {
        holds:0,
        itemUseAuthority:function() { return null; },
        whenItemUseReady:function(callback) { waiters.push(callback); return true; },
        holdItemUse:function() { this.holds++; },
        releaseItemUse:function() { if (this.holds > 0) this.holds--; }
    };
    const run = harness({build:build});
    const acquired = [];
    run.authority.acquire(handle => acquired.push(handle));
    run.authority.acquire(handle => acquired.push(handle));
    assert.strictEqual(acquired.length, 0, 'acquire waits for the build session');
    assert.strictEqual(waiters.length, 1, 'waiters coalesce onto one readiness hook');
    waiters[0]({itemUse:{debugState:() => ({state:'idle'})}, generation:11});
    assert.strictEqual(acquired.length, 2);
    assert.strictEqual(acquired[0].generation, 11);
    assert.strictEqual(build.holds, 1);
});

check('build suspend keeps a held channel alive and closes it after release', function() {
    const itemUse = {state:'idle', closes:0,
        close:function() { this.closes++; this.state = 'closed'; return true; }};
    const controller = {
        _candidateRecoverySequence:0,
        _mountGeneration:0,
        _candidateTooltip:null,
        _candidateCache:null,
        _stopItemUseCooldownPolling:function() { return true; },
        _itemUse:itemUse,
        _itemUseHolds:1,
        _itemUseBindKey:'k',
        _itemUseResumeSelection:null,
        _rewardAuthority:null,
        _session:{suspendView:function() { return true; }},
        _tuning:null,
        _resizeObserver:null,
        _renderer:null,
        _view:null
    };
    Build.CharacterBuildController.prototype.suspend.call(controller);
    assert.strictEqual(itemUse.closes, 0,
        'a stash hold must keep the exact channel bound across suspend');
    controller._itemUseHolds = 0;
    Build.CharacterBuildController.prototype.suspend.call(controller);
    assert.strictEqual(itemUse.closes, 1,
        'releasing the hold restores the old suspend-close behaviour');
});

check('a late settle while suspended only caches the snapshot, never remounts', function() {
    const controller = {
        _snapshotPayload:null,
        _selectedCandidate:{stale:true},
        _candidateCache:{stale:true},
        _candidateTooltip:null,
        _view:null,
        _panelInstanceId:'panel.workbench.7',
        _session:{getSessionGeneration:function() { return 3; }},
        _createView:function() { throw new Error('must not remount'); }
    };
    Build.CharacterBuildController.prototype._applySnapshot.call(
        controller, {fresh:true}, false);
    assert.deepStrictEqual(controller._snapshotPayload, {fresh:true});
    assert.strictEqual(controller._selectedCandidate, null);
    assert.strictEqual(controller._candidateCache, null);
});

check('finalize on a borrowed authority is a no-op for the session owner', function() {
    const build = {
        holds:0,
        itemUseAuthority:function() {
            return {itemUse:{debugState:() => ({state:'idle'})}, generation:4};
        },
        whenItemUseReady:function(callback) { callback(this.itemUseAuthority()); return true; },
        holdItemUse:function() { this.holds++; },
        releaseItemUse:function() { if (this.holds > 0) this.holds--; }
    };
    const run = harness({build:build});
    const finalized = [];
    run.authority.finalize(accepted => finalized.push(accepted));
    assert.deepStrictEqual(finalized, [true]);
    assert.strictEqual(run.sent.length, 0,
        'borrowed finalize must not issue a second loadout finalize');
});

process.stdout.write('CharacterBuild stash authority: ' + passed + ' checks passed\n');
