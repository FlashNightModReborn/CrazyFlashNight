'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const Config = require('../launcher/web/modules/inventory-workbench-config.js');
const Navigation = require('../launcher/web/modules/inventory-workbench-navigation.js');
const Header = require('../launcher/web/modules/inventory-workbench-header.js');
const Quick = require('../launcher/web/modules/inventory-workbench-quick-transfer.js');
const OwnedView = require('../launcher/web/modules/inventory-workbench-owned-view.js');
const KShopOwned = require('../launcher/web/modules/kshop-owned-inventory-presenter.js');
const TuningScope = require('../launcher/web/modules/inventory-tuning-scope.js');

let passed = 0;
function test(name, fn) {
    fn();
    passed++;
    process.stdout.write('ok ' + passed + ' - ' + name + '\n');
}

test('profile and view resolution reject unknown launch shapes', () => {
    assert.deepStrictEqual(Config.resolveProfile({profile:'warehouse'}), {
        profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50,
        rightCapacity:1200, pageColumns:6
    });
    assert.strictEqual(Config.resolveProfile({profile:'unknown'}), null);
    assert.strictEqual(Config.resolveView({view:'tuning'}), 'tuning');
    assert.strictEqual(Config.resolveView({view:'build'}), 'build');
    assert.strictEqual(Config.isViewAllowed('battlebox', 'build'), true);
    assert.strictEqual(Config.isViewAllowed('warehouse', 'build'), false);
    assert.strictEqual(Config.resolveView({view:'debug'}), null);
});

test('return target is normalized without retaining caller-owned objects', () => {
    const source = {returnTo:{panel:'crafting', initData:{category:'weapon', preferredRecipeIndex:'4.9', preferredCraftCount:200}}};
    const target = Config.resolveReturnTarget(source);
    assert.deepStrictEqual(target, {panel:'crafting', initData:{category:'weapon', preferredRecipeIndex:4, preferredCraftCount:99}});
    assert.notStrictEqual(target, source.returnTo);
    assert.strictEqual(Config.resolveReturnTarget({returnTo:{panel:'npcshop', initData:{category:'x'}}}), null);
});

test('return focus action is a two-value migration enum, never a selector', () => {
    assert.strictEqual(Config.resolveReturnFocusAction({}), '');
    assert.strictEqual(Config.resolveReturnFocusAction({
        returnFocusAction:'skills'
    }), 'skills');
    assert.strictEqual(Config.resolveReturnFocusAction({
        returnFocusAction:'preparation-menu'
    }), 'preparation-menu');
    for (const invalid of [null, '', 'Skills', '#skills',
        '[data-header-action="skills"]', 'preparation-menu other', 7]) {
        assert.strictEqual(Config.resolveReturnFocusAction({
            returnFocusAction:invalid
        }), null);
    }
    assert.strictEqual(Config.resolveLaunchContext({
        profile:'battlebox', view:'build',
        panelInstanceId:'panel.workbench.selector',
        returnFocusAction:'[data-header-action="skills"]'
    }), null);
});

test('preparation rollout bool is optional, strict, and atomically paired with focus', () => {
    assert.strictEqual(Config.resolvePreparationNavigationV1({}), false);
    assert.strictEqual(Config.resolvePreparationNavigationV1({
        preparationNavigationV1:true
    }), true);
    assert.strictEqual(Config.resolvePreparationNavigationV1({
        preparationNavigationV1:false
    }), false);
    for (const invalid of [null, 1, 'true', {}, []]) {
        assert.strictEqual(Config.resolvePreparationNavigationV1({
            preparationNavigationV1:invalid
        }), null);
    }
    const base = {
        profile:'battlebox',
        view:'build',
        panelInstanceId:'panel.workbench.rollout'
    };
    assert.strictEqual(Config.resolveLaunchContext(Object.assign(
        {}, base, {
            preparationNavigationV1:true,
            returnFocusAction:'skills'
        })), null);
    assert.strictEqual(Config.resolveLaunchContext(Object.assign(
        {}, base, {
            preparationNavigationV1:false,
            returnFocusAction:'preparation-menu'
        })), null);
    assert.strictEqual(Config.resolveLaunchContext(Object.assign(
        {}, base, {
            preparationNavigationV1:'true'
        })), null);
    assert.strictEqual(Config.resolveLaunchContext(Object.assign(
        {}, base, {
            preparationNavigationV1:true,
            returnFocusAction:'preparation-menu'
        })).preparationNavigationV1, true);
});

test('launch context separates exact Host workbenches from the crafting-owned organizer child', () => {
    const exact = Config.resolveLaunchContext({
        profile:'battlebox', view:'build', panelInstanceId:'panel.workbench.exact'
    });
    assert.strictEqual(exact.hostOwner, 'workbench');
    assert.strictEqual(exact.panelInstanceId, 'panel.workbench.exact');
    const nested = Config.resolveLaunchContext({
        profile:'battlebox', view:'storage',
        returnTo:{panel:'crafting', initData:{category:'weapon'}}
    });
    assert.strictEqual(nested.hostOwner, 'crafting');
    assert.strictEqual(nested.panelInstanceId, '');
    assert.strictEqual(Config.resolveLaunchContext({
        profile:'battlebox', view:'build',
        returnTo:{panel:'crafting', initData:{category:'weapon'}}
    }), null);
    assert.strictEqual(Config.resolveLaunchContext({
        profile:'battlebox', view:'storage', panelInstanceId:'panel.workbench.mixed',
        returnTo:{panel:'crafting', initData:{category:'weapon'}}
    }), null);
    assert.strictEqual(Config.resolveLaunchContext({
        profile:'battlebox', view:'storage', panelInstanceId:7
    }), null);
    assert.deepStrictEqual(Config.createCloseMessage('crafting', '', 'escape'),
        {type:'panel',cmd:'close',panel:'crafting'});
    assert.deepStrictEqual(Config.createCloseMessage(
        'workbench', 'panel.workbench.exact', 'navigate_skills'), {
        type:'panel',cmd:'close',panel:'workbench',
        panelInstanceId:'panel.workbench.exact',reason:'navigate_skills'
    });
    assert.deepStrictEqual(Config.createCloseMessage(
        'workbench', 'panel.workbench.exact', 'navigate_materials'), {
        type:'panel',cmd:'close',panel:'workbench',
        panelInstanceId:'panel.workbench.exact',reason:'navigate_materials'
    });
    assert.deepStrictEqual(Config.createCloseMessage(
        'workbench', 'panel.workbench.exact', 'navigate_intelligence'), {
        type:'panel',cmd:'close',panel:'workbench',
        panelInstanceId:'panel.workbench.exact',reason:'navigate_intelligence'
    });
    assert.deepStrictEqual(Config.createCloseMessage(
        'workbench', 'panel.workbench.exact', 'navigate_panel'), {
        type:'panel',cmd:'close',panel:'workbench',
        panelInstanceId:'panel.workbench.exact'
    });
    assert.deepStrictEqual(Config.createCloseMessage(
        'workbench', 'panel.workbench.tuning', 'escape'), {
        type:'panel',cmd:'close',panel:'workbench',
        panelInstanceId:'panel.workbench.tuning'
    });
});

test('view stack records explicit fields and only returns through real history', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'build', origin:'launch', returnTarget:'game',
        focusKey:''
    });
    assert.deepStrictEqual(stack.current(), {
        viewId:'build', origin:'launch', returnTarget:'game',
        focusKey:''
    });
    assert.strictEqual(stack.previous(), null);
    const storagePlan = stack.plan('storage', 'header', 'header:storage');
    assert.strictEqual(stack.commit(storagePlan).viewId, 'storage');
    assert.strictEqual(stack.canReturnTo('build'), true);
    assert.strictEqual(stack.commit(stack.plan('tuning', 'header', 'header:tuning')).viewId, 'tuning');
    assert.strictEqual(stack.previous().viewId, 'storage');
    const tuningReturn = stack.returnPlan('escape');
    assert.strictEqual(tuningReturn.entry.viewId, 'storage');
    assert.strictEqual(tuningReturn.restoreFocusKey, 'header:tuning');
    assert.strictEqual(stack.commit(tuningReturn).viewId, 'storage');
    assert.strictEqual(stack.previous().viewId, 'build');
    const buildReturn = stack.returnPlan('escape');
    assert.strictEqual(buildReturn.entry.viewId, 'build');
    assert.strictEqual(buildReturn.restoreFocusKey, 'header:storage');
    assert.strictEqual(stack.commit(buildReturn).viewId, 'build');
    assert.strictEqual(stack.returnPlan('escape'), null);
    assert.strictEqual(stack.commit(storagePlan), false);
    assert.strictEqual(stack.snapshot().length, 1);
    assert.strictEqual(stack.commit(stack.plan('storage', 'header', 'header:storage')).viewId, 'storage');
    assert.strictEqual(stack.snapshot().length, 2);
    assert.throws(() => new Config.WorkbenchViewStack({viewId:'debug'}));
    assert.strictEqual(stack.plan('debug'), null);
});

test('standalone tuning closes to game and its battlebox round trip stays local', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'tuning', origin:'launch', returnTarget:'game', focusKey:''
    });
    assert.strictEqual(stack.returnPlan('escape'), null);
    const storage = stack.plan('storage', 'header', 'header:storage');
    assert.strictEqual(stack.commit(storage).viewId, 'storage');
    const back = stack.returnPlan('header');
    assert.strictEqual(back.entry.viewId, 'tuning');
    assert.strictEqual(stack.commit(back).viewId, 'tuning');
    assert.strictEqual(stack.snapshot().length, 1);
});

test('explicit return to Build unwinds bounded local history while Escape stays one layer', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'build', origin:'launch', returnTarget:'game', focusKey:''
    });
    stack.commit(stack.plan('storage', 'header', 'header:storage'));
    stack.commit(stack.plan('tuning', 'header', 'workbench:tuning-switch'));
    assert.strictEqual(stack.canReturnTo('build'), true);
    const escape = stack.returnPlan('escape');
    assert.strictEqual(escape.mode, 'back');
    assert.strictEqual(escape.entry.viewId, 'storage');
    assert.strictEqual(escape.restoreFocusKey, 'workbench:tuning-switch');
    const direct = stack.plan('build', 'header', 'header:return-build');
    assert.strictEqual(direct.mode, 'unwind');
    assert.strictEqual(direct.ancestorIndex, 0);
    assert.strictEqual(direct.restoreFocusKey, 'header:storage');
    assert.strictEqual(stack.commit(direct).viewId, 'build');
    assert.deepStrictEqual(stack.snapshot().map(entry => entry.viewId), ['build']);
    assert.strictEqual(stack.commit(escape), false, 'stale one-layer plan cannot replay after unwind');
});

test('navigation transaction commits only after target readiness and rolls failures back', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'build', origin:'launch', returnTarget:'game', focusKey:''
    });
    const callbacks = {};
    let storageView = 'storage';
    let buildAdmission = true;
    let buildThrows = false;
    let commits = [];
    let aborts = 0;
    const navigation = new Navigation.Navigation({
        stack,
        view:'build',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        ports:{
            canEnterBuild:() => true,
            prepareStorageLeave:callback => { callbacks.storageLeave = callback; return true; },
            activateBuild:() => {
                if (buildThrows) throw new Error('mount failed');
                return buildAdmission;
            },
            discardBuild:() => {},
            prepareBuildLeave:callback => { callback(true); return true; },
            ensureStorage:() => true,
            getStorageView:() => storageView,
            switchStorage:() => false,
            onCommit:(next, previous) => commits.push(previous + '>' + next),
            onAbort:() => { aborts++; }
        }
    });
    assert.strictEqual(navigation.request('storage', {origin:'header'}), true);
    assert.deepStrictEqual(commits, ['build>storage']);
    assert.strictEqual(navigation.snapshot().length, 2);
    assert.strictEqual(navigation.request('build', {origin:'escape',
        plan:navigation.returnPlan('escape')}), true);
    assert.strictEqual(navigation.debugState().next, 'build');
    navigation.buildFailed();
    assert.strictEqual(navigation.snapshot().length, 2);
    assert.strictEqual(navigation.canReturnTo('build'), true);
    buildAdmission = false;
    assert.strictEqual(navigation.request('build', {origin:'escape',
        plan:navigation.returnPlan('escape')}), true);
    callbacks.storageLeave(true);
    assert.strictEqual(navigation.snapshot().length, 2);
    buildAdmission = true;
    buildThrows = true;
    assert.strictEqual(navigation.request('build', {origin:'escape',
        plan:navigation.returnPlan('escape')}), true);
    callbacks.storageLeave(true);
    assert.strictEqual(navigation.snapshot().length, 2);
    assert.strictEqual(aborts, 3);
    buildThrows = false;
    assert.strictEqual(navigation.request('build', {origin:'escape',
        plan:navigation.returnPlan('escape')}), true);
    callbacks.storageLeave(true);
    assert.strictEqual(navigation.buildReady(), true);
    assert.deepStrictEqual(commits, ['build>storage', 'storage>build']);
    assert.strictEqual(navigation.snapshot().length, 1);
});

test('destroy invalidates a late storage-to-build prepare callback before activation', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''
    });
    let leaveCallback = null;
    let buildActivations = 0;
    let aborts = 0;
    const navigation = new Navigation.Navigation({
        stack,
        view:'storage',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        ports:{
            canEnterBuild:() => true,
            prepareStorageLeave:callback => {
                leaveCallback = callback;
                return true;
            },
            activateBuild:() => {
                buildActivations++;
                return true;
            },
            onAbort:() => { aborts++; }
        }
    });
    assert.strictEqual(navigation.request('build'), true);
    assert.strictEqual(typeof leaveCallback, 'function');
    assert.strictEqual(navigation.destroy(), true);
    assert.strictEqual(navigation.destroy(), false);
    leaveCallback(true);
    assert.strictEqual(buildActivations, 0,
        'destroyed navigation must not activate Build through a stale callback');
    assert.strictEqual(aborts, 0,
        'teardown invalidation must not restore focus or mutate the replacement view');
    assert.strictEqual(navigation.request('build'), false);
    assert.strictEqual(navigation.buildReady(), false);
    assert.strictEqual(navigation.storageChanged('build'), false);
});

test('destroy invalidates a late build-to-storage prepare callback before storage mount', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'build', origin:'launch', returnTarget:'game', focusKey:''
    });
    let leaveCallback = null;
    let storageMounts = 0;
    let aborts = 0;
    const navigation = new Navigation.Navigation({
        stack,
        view:'build',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        ports:{
            prepareBuildLeave:callback => {
                leaveCallback = callback;
                return true;
            },
            ensureStorage:() => {
                storageMounts++;
                return true;
            },
            getStorageView:() => 'storage',
            onAbort:() => { aborts++; }
        }
    });
    assert.strictEqual(navigation.request('storage'), true);
    assert.strictEqual(typeof leaveCallback, 'function');
    assert.strictEqual(navigation.destroy(), true);
    leaveCallback(true);
    assert.strictEqual(storageMounts, 0,
        'destroyed navigation must not mount storage through a stale callback');
    assert.strictEqual(aborts, 0,
        'teardown invalidation must remain silent for the replacement lifecycle');
    assert.strictEqual(navigation.storageFailed('storage'), false);
    assert.strictEqual(navigation.returnPlan('escape'), null);
});

test('controller divergence supersedes pending navigation and rejects its late callback', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''
    });
    let leaveCallback = null;
    let buildActivations = 0;
    let discardedBuilds = 0;
    const commits = [];
    const superseded = [];
    const navigation = new Navigation.Navigation({
        stack,
        view:'storage',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        ports:{
            canEnterBuild:() => true,
            prepareStorageLeave:callback => {
                leaveCallback = callback;
                return true;
            },
            activateBuild:() => {
                buildActivations++;
                return true;
            },
            discardBuild:() => { discardedBuilds++; },
            switchStorage:() => true,
            onCommit:(next, previous) => commits.push(previous + '>' + next),
            onSupersede:(expected, reported) => superseded.push(expected + '>' + reported)
        }
    });
    assert.strictEqual(navigation.request('build'), true);
    assert.strictEqual(navigation.storageChanged('tuning'), true);
    assert.strictEqual(navigation.debugState(), null);
    assert.deepStrictEqual(commits, ['storage>tuning']);
    assert.deepStrictEqual(superseded, ['build>tuning']);
    assert.strictEqual(discardedBuilds, 1);
    leaveCallback(true);
    assert.strictEqual(buildActivations, 0,
        'a superseded prepare callback must not activate its stale target');
    assert.strictEqual(navigation.rejectIfPending(), false);
    assert.strictEqual(navigation.request('storage'), true);
    assert.strictEqual(navigation.storageChanged('storage'), true);
});

test('navigation timeout aborts an orphan prepare and invalidates its late callback', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''
    });
    let leaveCallback = null;
    let timeoutCallback = null;
    let buildActivations = 0;
    let discardedBuilds = 0;
    let aborts = 0;
    let timeouts = 0;
    const navigation = new Navigation.Navigation({
        stack,
        view:'storage',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        pendingTimeoutMs:1000,
        setTimer:callback => {
            timeoutCallback = callback;
            return 7;
        },
        clearTimer:() => {},
        ports:{
            canEnterBuild:() => true,
            prepareStorageLeave:callback => {
                leaveCallback = callback;
                return true;
            },
            activateBuild:() => {
                buildActivations++;
                return true;
            },
            discardBuild:() => { discardedBuilds++; },
            onAbort:() => { aborts++; },
            onTimeout:() => { timeouts++; }
        }
    });
    assert.strictEqual(navigation.request('build'), true);
    assert.strictEqual(typeof timeoutCallback, 'function');
    timeoutCallback();
    assert.strictEqual(navigation.debugState(), null);
    assert.strictEqual(discardedBuilds, 1);
    assert.strictEqual(aborts, 1);
    assert.strictEqual(timeouts, 1);
    assert.strictEqual(navigation.rejectIfPending(), false);
    leaveCallback(true);
    assert.strictEqual(buildActivations, 0,
        'a timed-out prepare callback must not activate its stale target');
});

test('Build to standalone tuning waits for exact leave and preserves one transaction on failures', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'build', origin:'launch', returnTarget:'game', focusKey:''
    });
    const document = {activeElement:null};
    const opener = {
        hidden:false, disabled:false,
        getAttribute:name => name === 'data-header-action' ? 'preparation-menu' : '',
        closest:() => null,
        focus() { document.activeElement = opener; }
    };
    document.activeElement = opener;
    let leaveCallback = null;
    let storageLeave = null;
    let storageView = '';
    let ensureAccepted = false;
    const ensured = [];
    const commits = [];
    let buildActivations = 0;
    const navigation = new Navigation.Navigation({
        stack, view:'build', document,
        getRoot:() => ({querySelectorAll:() => [opener]}),
        ports:{
            prepareBuildLeave:callback => { leaveCallback = callback; return true; },
            ensureStorage:next => {
                ensured.push(next);
                if (ensureAccepted) storageView = next;
                return ensureAccepted;
            },
            getStorageView:() => storageView,
            canEnterBuild:() => true,
            prepareStorageLeave:callback => { storageLeave = callback; return true; },
            activateBuild:() => { buildActivations++; return true; },
            onCommit:(next, previous) => commits.push(previous + '>' + next)
        }
    });
    assert.strictEqual(navigation.request('tuning', {opener}), true);
    assert.deepStrictEqual(ensured, []);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['build']);
    leaveCallback(false);
    leaveCallback(true);
    assert.deepStrictEqual(ensured, [], 'late detach success cannot enter standalone tuning');
    assert.strictEqual(document.activeElement, opener);

    assert.strictEqual(navigation.request('tuning', {opener}), true);
    leaveCallback(true);
    assert.deepStrictEqual(ensured, ['tuning']);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['build']);
    assert.strictEqual(navigation.debugState(), null);

    ensureAccepted = true;
    assert.strictEqual(navigation.request('tuning', {opener}), true);
    leaveCallback(true);
    assert.deepStrictEqual(ensured, ['tuning', 'tuning']);
    assert.deepStrictEqual(commits, ['build>tuning']);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['build', 'tuning']);

    const returnPlan = navigation.returnPlan('header');
    assert.strictEqual(navigation.request('build', {opener, plan:returnPlan}), true);
    assert.strictEqual(buildActivations, 0);
    storageLeave(true);
    assert.strictEqual(buildActivations, 1);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['build', 'tuning']);
    assert.strictEqual(navigation.buildReady(), true);
    assert.deepStrictEqual(commits, ['build>tuning', 'tuning>build']);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['build']);
});

test('pending navigation explains rejection and storage failure restores exact opener', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''
    });
    const document = {activeElement:null};
    const opener = {
        hidden:false, disabled:false,
        getAttribute:name => name === 'data-header-action' ? 'tuning' : '',
        closest:() => null,
        focus() { document.activeElement = opener; }
    };
    document.activeElement = opener;
    let pendingNotices = 0;
    let aborts = 0;
    const navigation = new Navigation.Navigation({
        stack, view:'storage', document,
        getRoot:() => ({querySelectorAll:() => [opener]}),
        ports:{
            switchStorage:() => true,
            onPending:() => { pendingNotices++; },
            onAbort:() => { aborts++; }
        }
    });
    assert.strictEqual(navigation.request('tuning', {opener}), true);
    assert.strictEqual(navigation.request('build', {opener}), false);
    assert.strictEqual(navigation.rejectIfPending(), true);
    assert.strictEqual(pendingNotices, 2);
    assert.strictEqual(navigation.storageFailed('tuning'), true);
    assert.strictEqual(navigation.debugState(), null);
    assert.strictEqual(navigation.snapshot().length, 1);
    assert.strictEqual(navigation.snapshot()[0].viewId, 'storage');
    assert.strictEqual(document.activeElement, opener);
    assert.strictEqual(aborts, 1);
});

test('rejected storage commit resets history to the controller-reported view', () => {
    const stack = new Config.WorkbenchViewStack({
        viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''
    });
    const commits = [];
    const desyncs = [];
    const navigation = new Navigation.Navigation({
        stack, view:'storage',
        document:{activeElement:null},
        getRoot:() => ({querySelectorAll:() => []}),
        ports:{
            switchStorage:() => true,
            onCommit:(next, previous, plan) => commits.push({next, previous, mode:plan.mode}),
            onDesync:(next, previous, reason) => desyncs.push({next, previous, reason})
        }
    });
    assert.strictEqual(navigation.request('tuning'), true);
    stack.reset({viewId:'storage', origin:'launch', returnTarget:'game', focusKey:''});
    assert.strictEqual(navigation.storageChanged('tuning'), true);
    assert.deepStrictEqual(navigation.snapshot().map(entry => entry.viewId), ['tuning']);
    assert.deepStrictEqual(commits, [{next:'tuning', previous:'storage', mode:'reset'}]);
    assert.deepStrictEqual(desyncs, [{
        next:'tuning', previous:'storage', reason:'pending-commit-rejected'
    }]);
    assert.strictEqual(navigation.returnPlan('escape'), null);
});

test('confirmation preference defaults safely and normalizes writes', () => {
    const values = {};
    const preference = new Config.ConfirmationPreference({
        getItem:key => values[key],
        setItem:(key, value) => { values[key] = value; }
    });
    assert.strictEqual(preference.read(), 'safe');
    assert.strictEqual(preference.write('fast'), 'fast');
    assert.strictEqual(preference.read(), 'fast');
    assert.strictEqual(preference.write('unsafe'), 'safe');
    const blocked = new Config.ConfirmationPreference({getItem() { throw new Error('blocked'); }, setItem() { throw new Error('blocked'); }});
    assert.strictEqual(blocked.read(), 'safe');
    assert.strictEqual(blocked.write('fast'), 'fast');
});

class FakeNode {
    constructor(tag) { this.tagName = tag; this.children = []; this.listeners = {}; this.attributes = {}; this.disabled = false; this.hidden = false; }
    appendChild(node) { this.children.push(node); return node; }
    setAttribute(name, value) { this.attributes[name] = String(value); }
    getAttribute(name) { return this.attributes[name] || null; }
    hasAttribute(name) { return Object.prototype.hasOwnProperty.call(this.attributes, name); }
    removeAttribute(name) { delete this.attributes[name]; }
    addEventListener(type, handler) { (this.listeners[type] = this.listeners[type] || []).push(handler); }
    removeEventListener(type, handler) { this.listeners[type] = (this.listeners[type] || []).filter(item => item !== handler); }
    click() {
        if (this.disabled) return false;
        let defaultPrevented = false;
        const event = {
            target:this,
            currentTarget:this,
            preventDefault() { defaultPrevented = true; }
        };
        (this.listeners.click || []).slice().forEach(handler => handler(event));
        return !defaultPrevented;
    }
}
class FakeDocument { createElement(tag) { return new FakeNode(tag); } }

test('header projection enumerates build, stats, storage, lock, and tuning truth', () => {
    const availability = {
        equipment:{visible:true, disabled:true, reason:'当前'},
        battlebox:{visible:true, disabled:false, reason:''},
        tuning:{visible:true, disabled:false, reason:''},
        skills:{visible:true, disabled:false, reason:''},
        materials:{visible:true, disabled:false, reason:''},
        intelligence:{visible:true, disabled:false, reason:''}
    };
    const visibleActions = projection => Object.keys(projection)
        .filter(key => projection[key] && projection[key].visible);
    const build = Header.InventoryWorkbenchHeaderProjection({
        view:'build', statsMode:false, buildAvailable:true, tuningAvailable:true
    });
    assert.deepStrictEqual(
        visibleActions(build),
        ['storage', 'stats', 'skills', 'help', 'close']);
    const preparation = Header.InventoryWorkbenchHeaderProjection({
        view:'build',
        preparationNavigationV1:true,
        preparationAvailability:availability
    });
    assert.deepStrictEqual(
        visibleActions(preparation),
        ['stats', 'preparation-menu', 'help', 'close']);
    assert.deepStrictEqual(
        Object.keys(preparation.preparationItems),
        Header.PREPARATION_KEYS);
    assert.deepStrictEqual(
        preparation.preparationItems.battlebox,
        {
            visible:true,
            disabled:false,
            reason:'',
            current:false,
            destinationKind:'local-view'
        });
    assert.throws(() => Header.InventoryWorkbenchHeaderProjection({
        view:'build',
        preparationNavigationV1:true,
        preparationAvailability:Object.assign({}, availability, {
            routeTable:true
        })
    }), /rejected/);
    const stats = Header.InventoryWorkbenchHeaderProjection({
        view:'build', statsMode:true, buildAvailable:true
    });
    assert.deepStrictEqual(
        visibleActions(stats),
        ['back-build', 'help', 'close']);
    const storage = Header.InventoryWorkbenchHeaderProjection({
        view:'storage', buildAvailable:true, returnTarget:true, tuningAvailable:true,
        tuningState:{disabled:true, reason:'正在同步'}
    });
    assert.strictEqual(storage['return-build'].visible, true);
    assert.strictEqual(storage['return-panel'].visible, true);
    assert.strictEqual(storage.tuning.visible, true);
    assert.strictEqual(storage.tuning.disabled, true);
    const tuning = Header.InventoryWorkbenchHeaderProjection({
        view:'tuning', buildAvailable:true, tuningAvailable:true
    });
    assert.strictEqual(tuning['return-build'].visible, true);
    assert.strictEqual(tuning.storage.visible, false);
    const locked = Header.InventoryWorkbenchHeaderProjection({
        view:'build', busy:true, reason:'完成对账后才能进入收纳'
    });
    assert.strictEqual(locked.storage.disabled, true);
    assert.strictEqual(locked.storage.reason, '完成对账后才能进入收纳');
    assert.strictEqual(locked.help.disabled, false);
    assert.strictEqual(locked.close.disabled, true);
});

test('header projection keeps reasoned disabled actions explainable without invoking handlers', () => {
    const buttons = {};
    const activations = [];
    const blocked = [];
    ['storage', 'stats', 'skills', 'close'].forEach(id => {
        buttons[id] = Header.createActionButton(
            new FakeDocument(),
            id,
            id,
            () => activations.push(id),
            reason => blocked.push(id + ':' + reason));
    });
    ['back-build', 'return-build', 'return-panel', 'help'].forEach(id => {
        buttons[id] = new FakeNode('button');
    });
    buttons.legacy = new FakeNode('button');
    buttons.close.setAttribute('aria-label', '关闭工作台');
    buttons.close.setAttribute('data-audio-cue', 'cancel');
    const locked = Header.InventoryWorkbenchHeaderProjection({
        view:'build', busy:true, reason:'等待权威结果'
    });
    Header.applyProjection(buttons, locked);
    assert.strictEqual(buttons.storage.hidden, false);
    assert.strictEqual(buttons.storage.disabled, false);
    assert.strictEqual(buttons.storage.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(
        buttons.storage.getAttribute('data-header-disabled-reason'),
        '等待权威结果');
    assert.strictEqual(buttons.stats.disabled, false);
    assert.strictEqual(buttons.skills.disabled, false);
    assert.strictEqual(buttons.close.disabled, false);
    assert.strictEqual(
        buttons.close.getAttribute('aria-label'),
        '关闭工作台，不可用：等待权威结果；完成后才能关闭工作台。');
    assert.strictEqual(buttons.close.getAttribute('data-audio-cue'), 'error');
    assert.strictEqual(
        buttons.close.getAttribute('data-header-base-audio-cue'),
        'cancel');
    assert.strictEqual(buttons.stats.getAttribute('data-audio-cue'), 'error');
    assert.strictEqual(buttons.help.disabled, false);
    assert.strictEqual(buttons['return-build'].hidden, true);
    assert.strictEqual(buttons.legacy.hidden, true);
    assert.strictEqual(buttons.legacy.disabled, true);
    ['storage', 'stats', 'skills', 'close'].forEach(id => buttons[id].click());
    assert.deepStrictEqual(activations, []);
    assert.deepStrictEqual(blocked, [
        'storage:等待权威结果',
        'stats:等待权威结果',
        'skills:等待权威结果',
        'close:等待权威结果；完成后才能关闭工作台。'
    ]);
    Header.applyProjection({close:buttons.close}, {
        close:{
            visible:true,
            disabled:true,
            pressed:null,
            label:'×',
            reason:''
        }
    });
    assert.strictEqual(buttons.close.disabled, true);
    assert.strictEqual(buttons.close.getAttribute('title'), null);
    assert.strictEqual(buttons.close.getAttribute('aria-label'), '关闭工作台，不可用');
    assert.strictEqual(buttons.close.getAttribute('data-audio-cue'), 'cancel');
    Header.applyProjection(buttons, Header.InventoryWorkbenchHeaderProjection({view:'build'}));
    assert.strictEqual(buttons.storage.getAttribute('aria-disabled'), 'false');
    assert.strictEqual(
        buttons.storage.getAttribute('data-header-disabled-reason'),
        null);
    assert.strictEqual(buttons.close.getAttribute('aria-label'), '关闭工作台');
    assert.strictEqual(buttons.close.getAttribute('data-audio-cue'), 'cancel');
    assert.strictEqual(
        buttons.close.getAttribute('data-header-base-audio-cue'),
        null);
    assert.strictEqual(buttons.stats.getAttribute('data-audio-cue'), null);
    assert.strictEqual(
        buttons.stats.getAttribute('data-header-base-audio-cue'),
        null);
    buttons.stats.click();
    assert.deepStrictEqual(activations, ['stats']);
    const unexplained = Header.createActionButton(
        new FakeDocument(), 'unexplained', '无原因禁用',
        () => activations.push('unexplained'),
        reason => blocked.push('unexplained:' + reason));
    unexplained.setAttribute('data-audio-cue', 'confirm');
    Header.applyProjection({unexplained}, {
        unexplained:{
            visible:true,
            disabled:true,
            pressed:null,
            label:'无原因禁用',
            reason:''
        }
    });
    assert.strictEqual(unexplained.disabled, true);
    assert.strictEqual(unexplained.getAttribute('data-audio-cue'), 'confirm');
    unexplained.click();
    assert.deepStrictEqual(activations, ['stats']);
});

test('tuning header owns only view switching, disabled state, and listener teardown', () => {
    const actions = [];
    const changes = [];
    const blocked = [];
    const controller = new Header.TuningHeaderController({
        document:new FakeDocument(), shell:{addHeaderAction:node => actions.push(node)},
        view:'storage', onSwitch:view => changes.push('view:' + view),
        onBlocked:reason => blocked.push(reason)
    });
    assert.strictEqual(actions.length, 1);
    assert.strictEqual(controller.confirmationRoot, undefined);
    controller.switchButton.click();
    assert.deepStrictEqual(changes, ['view:tuning']);
    controller.update({view:'tuning', disabled:true, reason:'正在完成调制对账'});
    assert.strictEqual(controller.switchButton.textContent, '战备箱与背包');
    assert.strictEqual(controller.switchButton.disabled, false);
    assert.strictEqual(controller.switchButton.getAttribute('aria-disabled'), 'true');
    assert.strictEqual(controller.switchButton.getAttribute('title'), '正在完成调制对账');
    controller.switchButton.click();
    assert.deepStrictEqual(blocked, ['正在完成调制对账']);
    assert.deepStrictEqual(changes, ['view:tuning']);
    controller.update({view:'tuning', disabled:true});
    assert.strictEqual(controller.switchButton.disabled, true);
    controller.update({view:'tuning'});
    assert.strictEqual(controller.switchButton.disabled, true, 'partial updates preserve the disabled gate');
    assert.strictEqual(controller.switchButton.textContent, '战备箱与背包');
    controller.destroy();
    controller.switchButton.click();
    assert.deepStrictEqual(changes, ['view:tuning']);
});

function slot(index, name, quantity) {
    return {occupied:true, physicalSlot:index, slotLease:'lease-' + index,
        item:{name:name, displayName:name, itemKind:'equipment', quantity:quantity || 1, enhancementLevel:1, rarity:'normal'}};
}

function quickFixture(options) {
    options = options || {};
    const slots = {'背包:1':slot(1, 'A'), '背包:2':slot(2, 'B'), '仓库:3':slot(3, 'C')};
    const calls = [];
    const notices = [];
    const errors = [];
    const changes = [];
    let generation = 1;
    let current = true;
    const authority = {ready:true, busyOwner:null, refreshRequired:false};
    const controller = new Quick.QuickTransferController({
        rightContainerId:'仓库', limit:options.limit || 24,
        getAuthorityState:() => authority,
        getGeneration:() => generation,
        isGenerationCurrent:value => current && value === generation,
        getSlot:(containerId, physicalSlot) => slots[containerId + ':' + physicalSlot],
        slotRef:(containerId, value) => ({containerId, slot:value.physicalSlot, expectedLease:value.slotLease}),
        autoTransfer:(source, target, done) => { calls.push({source, target, done}); return options.rejectStart ? false : true; },
        onChange:state => changes.push(state), onNotice:reason => notices.push(reason), onError:error => errors.push(error)
    });
    return {controller, slots, calls, notices, errors, changes, authority,
        setGeneration(value) { generation = value; }, setCurrent(value) { current = value; }};
}

test('quick transfer serializes intents and preserves target direction', () => {
    const f = quickFixture();
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1']), true);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), true);
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(f.calls[0].target, '仓库');
    assert.deepStrictEqual(f.controller.debugState().inFlight, '背包:1');
    assert.strictEqual(f.controller.debugState().pending, 1);
    f.calls[0].done({success:true});
    assert.strictEqual(f.calls.length, 2);
    f.calls[1].done({success:true});
    assert.strictEqual(f.controller.isBusy(), false);
    assert.strictEqual(f.controller.debugState().completed, 2);
});

test('queued duplicate toggles off while inflight duplicate is rejected', () => {
    const f = quickFixture();
    f.controller.enqueue('背包', f.slots['背包:1']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:1']), false);
    assert.deepStrictEqual(f.notices, ['already_in_flight']);
    f.controller.enqueue('背包', f.slots['背包:2']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), true);
    assert.strictEqual(f.controller.debugState().pending, 0);
});

test('stale queued projection halts atomically before the authority port', () => {
    const f = quickFixture();
    f.controller.setMode('deposit');
    f.controller.enqueue('背包', f.slots['背包:1']);
    f.controller.enqueue('背包', f.slots['背包:2']);
    assert.strictEqual(f.calls.length, 0);
    assert.strictEqual(f.controller.commit(), true);
    f.slots['背包:2'] = slot(2, 'moved');
    f.calls[0].done({success:true});
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(f.errors.length, 1);
    assert.strictEqual(f.errors[0].error, 'stale_state');
    assert.strictEqual(f.controller.getMode(), null);
    assert.strictEqual(f.controller.isBusy(), false);
});

test('batch mode stages battlebox selections and commits them once', () => {
    const f = quickFixture();
    const event = {ctrlKey:false, prevented:false, stopped:false,
        preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
    f.controller.setMode('deposit');
    assert.strictEqual(f.controller.acceptClick(event, {
        profile:'battlebox', viewMode:'storage', containerId:'背包', slot:f.slots['背包:1']
    }), true);
    assert.strictEqual(f.controller.acceptClick(event, {
        profile:'battlebox', viewMode:'storage', containerId:'背包', slot:f.slots['背包:2']
    }), true);
    assert.strictEqual(f.calls.length, 0);
    assert.strictEqual(f.controller.isBusy(), false);
    assert.strictEqual(f.controller.debugState().staged, 2);
    assert.strictEqual(f.controller.commit(), true);
    assert.strictEqual(f.calls.length, 1);
    assert.strictEqual(f.controller.isBusy(), true);
    f.calls[0].done({success:true});
    assert.strictEqual(f.calls.length, 2);
    f.calls[1].done({success:true});
    assert.strictEqual(f.controller.getMode(), null);
    assert.strictEqual(f.controller.debugState().completed, 2);
});

test('mode click gate consumes wrong-side selections without starting authority writes', () => {
    const f = quickFixture();
    const event = {ctrlKey:false, prevented:false, stopped:false,
        preventDefault() { this.prevented = true; }, stopPropagation() { this.stopped = true; }};
    f.controller.setMode('deposit');
    assert.strictEqual(f.controller.acceptClick(event, {profile:'warehouse', viewMode:'storage', containerId:'仓库', slot:f.slots['仓库:3']}), true);
    assert.strictEqual(event.prevented, true);
    assert.deepStrictEqual(f.notices, ['deposit_source']);
    assert.strictEqual(f.calls.length, 0);
});

test('queue limit and rejected authority start expose deterministic failures', () => {
    const f = quickFixture({limit:1});
    f.controller.enqueue('背包', f.slots['背包:1']);
    assert.strictEqual(f.controller.enqueue('背包', f.slots['背包:2']), false);
    assert.deepStrictEqual(f.notices, ['queue_full']);
    const rejected = quickFixture({rejectStart:true});
    assert.strictEqual(rejected.controller.enqueue('背包', rejected.slots['背包:1']), true);
    assert.strictEqual(rejected.errors[0].error, 'busy');
    assert.strictEqual(rejected.controller.isBusy(), false);
});

test('owned-view presentation rules centralize locked, filtered, and capacity copy', () => {
    assert.deepStrictEqual(OwnedView.presentationFor('战备箱', {accessibleCapacity:0, slots:[]}),
        {emptyText:'战备箱尚未解锁', meta:'未解锁'});
    assert.deepStrictEqual(OwnedView.presentationFor('背包', {filterKey:'weapon', accessibleCapacity:50,
        slots:[{occupied:true},{occupied:false}]}), {emptyText:'当前分类暂无物品', meta:'1 / 50'});
    assert.deepStrictEqual(OwnedView.presentationFor('背包', {scope:'equipment', accessibleCapacity:50, slots:[]}),
        {emptyText:'背包中暂无可调制装备', meta:'0 / 50'});
    assert.strictEqual(OwnedView.countOccupied([{occupied:true},{occupied:false},{occupied:true}]), 2);
});

test('owned inventory authority projection keeps inspection while locking exact write states', () => {
    const ready = {inspectable:true, actionable:true, reason:''};
    assert.deepStrictEqual(OwnedView.authorityInteraction({ready:true}, false), ready);
    assert.deepStrictEqual(OwnedView.authorityInteraction({ready:false}, true),
        {inspectable:true, actionable:false, reason:'库存正在同步，请稍候。'});
    assert.deepStrictEqual(OwnedView.authorityInteraction(
        {ready:true, refreshRequired:true}, true),
        {inspectable:true, actionable:false, reason:'库存同步失败，请先重试。'});
    assert.deepStrictEqual(OwnedView.authorityInteraction(
        {ready:true, busyOwner:'inventory.discard'}, true),
        {inspectable:true, actionable:false, reason:'库存正在处理另一项操作。'});
    assert.deepStrictEqual(OwnedView.authorityInteraction(
        {ready:true, busyOwner:'inventory.autoTransfer'}, true), ready);
    assert.strictEqual(OwnedView.authorityInteraction(
        {ready:true, busyOwner:'inventory.autoTransfer'}, false).actionable, false,
        'auto-transfer may enqueue through the existing tile path but never unlocks discard');
    assert.deepStrictEqual(KShopOwned.interactionForStatus({ready:true}), ready);
    assert.strictEqual(KShopOwned.interactionForStatus(
        {ready:true, busyOwner:'inventory.autoTransfer'}).actionable, false);
    assert.strictEqual(KShopOwned.interactionForStatus(
        {ready:true, refreshRequired:true}).reason, '背包同步失败，请先重试。');
});

test('tuning scope restores exact request, viewport, and focused tile', () => {
    const calls = [];
    let request = {
        containerId:'背包', offset:50, limit:50, filterKey:'weapon',
        filterSpec:{branch:'category', major:'weapon', use:'长枪'}
    };
    const callbacks = [];
    const coordinator = {
        getRequest:() => JSON.parse(JSON.stringify(request)),
        replaceWindowRequest:(containerId, next, callback) => {
            calls.push({containerId, next:JSON.parse(JSON.stringify(next))});
            request = JSON.parse(JSON.stringify(next));
            callbacks.push(callback);
            return true;
        }
    };
    let focused = false;
    const tile = {
        getAttribute:name => name === 'data-workbench-key' ? '17' : null,
        querySelector:() => null,
        focus:() => { focused = true; }
    };
    const root = {
        scrollTop:73, scrollLeft:11, listeners:{},
        addEventListener(type, callback) { this.listeners[type] = callback; },
        removeEventListener(type) { delete this.listeners[type]; },
        contains:() => true, querySelectorAll:() => [tile]
    };
    const transition = new TuningScope.Transition({coordinator, getRoot:() => root});
    transition.attach();
    root.listeners.focusin({target:{closest:selector =>
        selector === '[data-workbench-key]' ? tile : null}});
    const original = JSON.parse(JSON.stringify(request));
    assert.strictEqual(transition.enter(), true);
    assert.deepStrictEqual(calls[0].next,
        {containerId:'背包', offset:0, limit:50, filterKey:'all', scope:'equipment'});
    callbacks[0]({success:true});
    root.scrollTop = 0; root.scrollLeft = 0;
    assert.strictEqual(transition.leave(() => {}), true);
    assert.deepStrictEqual(calls[1].next, original);
    callbacks[1]({success:true});
    assert.strictEqual(transition.restore(), true);
    assert.strictEqual(root.scrollTop, 73);
    assert.strictEqual(root.scrollLeft, 11);
    assert.strictEqual(focused, true);
    assert.strictEqual(transition.debugState().hasReturnState, false);
});

test('direct tuning starts scoped but preserves the default return request', () => {
    const coordinator = {getRequest:() => null, replaceWindowRequest:() => false};
    const transition = new TuningScope.Transition({coordinator, getRoot:() => null});
    const initial = {containerId:'背包', offset:0, limit:50, filterKey:'all'};
    assert.deepStrictEqual(transition.prepareInitial(initial, 'tuning'),
        {containerId:'背包', offset:0, limit:50, filterKey:'all', scope:'equipment'});
    assert.deepStrictEqual(transition.debugState().returnState.request, initial);
});

test('facade owns registration and delegates to the bounded storage controller', () => {
    const facade = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'inventory-workbench.js'), 'utf8');
    const source = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'inventory-storage-workbench.js'), 'utf8');
    const buildSession = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'character-build-session.js'), 'utf8');
    const buildController = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'character-build.js'), 'utf8');
    const buildTuning = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'character-build', 'character-build-tuning.js'), 'utf8');
    const tuningView = fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', 'equipment-tuning-view.js'), 'utf8');
    const extracted = ['inventory-workbench-config.js', 'inventory-workbench-navigation.js',
        'inventory-workbench-preparation-menu.js', 'inventory-workbench-header.js',
        'inventory-workbench-quick-transfer.js', 'inventory-workbench-owned-view.js',
        'inventory-tuning-scope.js']
        .map(file => fs.readFileSync(path.join(__dirname, '..', 'launcher', 'web', 'modules', file), 'utf8')).join('\n');
    assert(source.includes('InventoryWorkbenchQuickTransfer.QuickTransferController'));
    assert(source.includes('InventoryWorkbenchOwnedView.createView'));
    assert(source.includes('new InventoryTuningScope.Transition'));
    assert(source.includes('EquipmentTuningConfirmation.shared.read()'));
    assert(!source.includes('new InventoryWorkbenchConfig.ConfirmationPreference'));
    assert(source.includes('activate:activate'));
    assert(source.includes('deactivate:cleanup'));
    assert(source.includes('beginExternalWrite:beginExternalWrite'));
    assert(source.includes('completeExternalWrite:completeExternalWrite'));
    assert(source.includes(
        'if (_renderedWindows[view.containerId] === snapshot) return false;'
    ));
    assert(source.includes('_renderedWindows[view.containerId] = snapshot;'));
    assert(!/Panels\.register|InventoryWorkbenchHeader|new Workbench\.DualPaneShell|workbench-close-btn/.test(source));
    assert.strictEqual((facade.match(/Panels\.register\('workbench'/g) || []).length, 1);
    assert(facade.includes('new Workbench.DualPaneShell'));
    assert(extracted.includes('new TuningHeaderController'));
    assert(!facade.includes('onConfirmationChange'));
    assert.strictEqual(Header.TuningHeaderController.prototype._createConfirmationToggle, undefined);
    assert(facade.includes('InventoryWorkbenchHeader.renderWorkbenchHeader'));
    assert(extracted.includes('function InventoryWorkbenchHeaderProjection(state)'));
    assert(facade.includes('window.__INVENTORY_WORKBENCH_CONFIG__'));
    assert(facade.includes('timeoutMs:_runtimeConfig.requestTimeoutMs'));
    assert(facade.includes('sessionNonce:_runtimeConfig.sessionNonce'));
    assert(facade.includes("panelId:'workbench'"));
    assert(facade.includes("defaultMode:'compact'"));
    assert(source.includes('installQuickTransferActions();'));
    assert(source.includes('InventoryWorkbenchQuickTransfer.createCommandBar'));
    assert(extracted.includes("className = 'inventory-quick-transfer-bar'"));
    assert(source.includes('body.appendChild(_quickBarView.root)'));
    assert(!/addHeaderAction\(_quick(StatusNode|DepositButton|WithdrawButton|CommitButton)/.test(source));
    assert(source.includes('commitQuickTransfer'));
    assert(/InventoryStorageWorkbench\.activate\(\s*controllerPorts\(\),\s*initialView\s*\)/.test(facade));
    assert(facade.includes('InventoryStorageWorkbench.deactivate()'));
    assert(extracted.includes('function createWorkbenchHeader(options)'));
    assert(extracted.includes("createActionButton(document, 'close', '×'"));
    assert(facade.includes('function requestView(next, options)'));
    assert(facade.includes('new InventoryWorkbenchConfig.WorkbenchViewStack'));
    assert(facade.includes('launch.returnFocusAction'));
    assert(!facade.includes('initData.returnFocusAction'));
    assert(extracted.includes("returnFocusAction === 'skills'"));
    assert(extracted.includes("returnFocusAction === 'preparation-menu'"));
    assert(facade.includes('InventoryWorkbenchNavigation.create'));
    assert(extracted.includes('Navigation.prototype._begin'));
    assert(extracted.includes('Navigation.prototype._finish'));
    assert(extracted.includes('Navigation.prototype._abort'));
    assert(facade.includes("buildAvailable:!!(_navigation && _navigation.canReturnTo('build'))"));
    assert(facade.includes('InventoryStorageWorkbench.consumeEscape()'));
    assert(source.includes('consumeEscape:function()'));
    assert(source.includes('function switchView(nextView, preferredSlot, callback)'));
    assert(source.includes('_tuningView.openSession(_panelInstanceId)'));
    assert(source.includes('nextView === _viewMode'));
    assert(source.includes('scopeState.hasReturnState'));
    assert(!source.includes('handleLoadoutSelection'));
    assert(!source.includes('Panels.open'));
    assert(source.includes('complete(false)'));
    assert(source.includes('complete(true)'));
    assert(facade.includes('function finalizeClose(reason)'));
    assert(extracted.includes("append(buildActions, 'skills', '技能配置'"));
    assert(facade.includes("requestPreparationNavigation('navigate_skills')"));
    assert(facade.includes("case 'battlebox': return requestView("));
    assert(facade.includes("case 'tuning': return requestView("));
    assert(facade.includes("case 'materials': return requestPreparationNavigation('navigate_materials')"));
    assert(facade.includes("case 'intelligence': return requestPreparationNavigation('navigate_intelligence')"));
    assert(/reason === 'navigate_skills'[\s\S]{0,120}reason === 'navigate_materials'[\s\S]{0,120}reason === 'navigate_intelligence'/.test(extracted));
    assert(buildController.includes('new SessionModule.CharacterBuildSession'));
    assert(/prepareLeave[\s\S]*?_tuning\.exit[\s\S]*?_session\.prepareLeave/.test(buildController));
    assert(!/prepareLeave[\s\S]{0,500}?\.finalize\(/.test(buildController));
    assert(buildTuning.includes('this._returnState = null'));
    assert(buildTuning.includes('this._entrySource = null'));
    assert(buildTuning.includes('exitGeneration !== self._exitGeneration'));
    assert(tuningView.includes('this._source = null'));
    assert(tuningView.includes('this._preview = null'));
    assert.deepStrictEqual(
        require('../launcher/web/modules/character-build-session.js').commands,
        [
            'snapshot', 'candidates', 'flushLive', 'statsSnapshot', 'finalize',
            'equipEquipment', 'unequipEquipment', 'equipDrug', 'unequipDrug'
        ]);
    assert(!/Panels\.register|Bridge\.send/.test(buildSession));
    assert(!/Bridge\.send|RequestMux|InventoryCoordinator/.test(extracted), 'extracted modules must not own transport or authority');
    // Readable parent orchestration is budgeted explicitly; do not line-compress the facade merely
    // to satisfy the old pre-extraction threshold. audit-workbench-ui.js carries the same ceiling.
    assert(facade.split(/\r?\n/).length <= 550);
    assert(source.split(/\r?\n/).length <= 900);
});

process.stdout.write('Inventory workbench modules: ' + passed + '/' + passed + ' passed\n');
