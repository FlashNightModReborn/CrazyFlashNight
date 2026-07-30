/** Pure launch-profile and local confirmation-preference rules for InventoryWorkbench. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchConfig = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    var MOD_CONFIRMATION_STORAGE_KEY = 'cf7.equipmentTuning.modConfirmationMode';

    function resolveProfile(initData) {
        var profile = initData && initData.profile != null ? String(initData.profile) : 'battlebox';
        if (profile !== 'warehouse' && profile !== 'battlebox') return null;
        return profile === 'warehouse'
            ? {profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50,
                rightCapacity:1200, pageColumns:6}
            : {profile:'battlebox', title:'战备箱', rightContainerId:'战备箱', rightLimit:40,
                rightCapacity:0, pageColumns:3};
    }

    function resolveView(initData) {
        var view = initData && initData.view != null ? String(initData.view) : 'storage';
        return view === 'storage' || view === 'tuning' || view === 'build' ? view : null;
    }

    function resolveReturnFocusAction(initData) {
        if (!initData || !Object.prototype.hasOwnProperty.call(
                initData, 'returnFocusAction')) return '';
        if (typeof initData.returnFocusAction !== 'string') return null;
        return initData.returnFocusAction === 'skills'
                || initData.returnFocusAction === 'preparation-menu'
            ? initData.returnFocusAction : null;
    }

    function resolvePreparationNavigationV1(initData) {
        if (!initData || !Object.prototype.hasOwnProperty.call(
                initData, 'preparationNavigationV1')) return false;
        return typeof initData.preparationNavigationV1 === 'boolean'
            ? initData.preparationNavigationV1 : null;
    }

    function isViewAllowed(profile, view) {
        profile = typeof profile === 'string' ? profile
            : profile && typeof profile.profile === 'string' ? profile.profile : '';
        return profile === 'warehouse' ? view === 'storage'
            : profile === 'battlebox'
                && (view === 'storage' || view === 'tuning' || view === 'build');
    }

    function resolveLaunchContext(initData) {
        initData = initData || {};
        var profile = resolveProfile(initData);
        var view = resolveView(initData);
        var panelInstanceId = typeof initData.panelInstanceId === 'string'
            ? initData.panelInstanceId : '';
        var returnFocusAction = resolveReturnFocusAction(initData);
        var preparationNavigationV1 =
            resolvePreparationNavigationV1(initData);
        var validInstance = /^[A-Za-z0-9._~-]{1,128}$/.test(panelInstanceId);
        if (!profile || !view || !isViewAllowed(profile, view)
                || preparationNavigationV1 === null
                || returnFocusAction === null
                || returnFocusAction && returnFocusAction !==
                    (preparationNavigationV1 ? 'preparation-menu' : 'skills')
                || !validInstance || initData.returnTo != null
                || initData.ownerContext != null) return null;
        return {
            profile:profile,
            view:view,
            panelInstanceId:panelInstanceId,
            returnFocusAction:returnFocusAction,
            preparationNavigationV1:preparationNavigationV1
        };
    }

    function createCloseMessage(panelInstanceId, reason) {
        var message = {
            type:'panel', cmd:'close', panel:'workbench',
            panelInstanceId:String(panelInstanceId || '')
        };
        if (reason === 'navigate_skills' || reason === 'navigate_materials'
                || reason === 'navigate_intelligence') message.reason = reason;
        return message;
    }

    function normalizeConfirmationMode(mode) { return mode === 'fast' ? 'fast' : 'safe'; }

    function normalizeViewEntry(value) {
        value = value || {};
        var viewId = String(value.viewId || '');
        if (viewId !== 'storage' && viewId !== 'tuning' && viewId !== 'build') return null;
        return {
            viewId:viewId,
            origin:String(value.origin || 'launch'),
            returnTarget:String(value.returnTarget || 'game'),
            focusKey:String(value.focusKey || '')
        };
    }

    /** Fixed, feature-local history; it carries no handlers or arbitrary destinations. */
    function WorkbenchViewStack(initialEntry) {
        this._entries = [];
        this._revision = 0;
        this.reset(initialEntry);
    }
    WorkbenchViewStack.prototype.reset = function(initialEntry) {
        var entry = normalizeViewEntry(initialEntry);
        if (!entry) throw new Error('Inventory workbench initial view entry rejected');
        this._entries = [entry];
        this._revision++;
        return this.current();
    };
    WorkbenchViewStack.prototype.current = function() {
        var entry = this._entries[this._entries.length - 1];
        return entry ? Object.assign({}, entry) : null;
    };
    WorkbenchViewStack.prototype.previous = function() {
        var entry = this._entries[this._entries.length - 2];
        return entry ? Object.assign({}, entry) : null;
    };
    WorkbenchViewStack.prototype._ancestorIndex = function(viewId) {
        viewId = String(viewId || '');
        for (var i = this._entries.length - 2; i >= 0; i--) {
            if (this._entries[i].viewId === viewId) return i;
        }
        return -1;
    };
    WorkbenchViewStack.prototype.plan = function(viewId, origin, focusKey) {
        var current = this.current();
        var entry = normalizeViewEntry({
            viewId:viewId,
            origin:origin || 'local-switch',
            returnTarget:current ? current.viewId : 'game',
            focusKey:focusKey || ''
        });
        if (!entry || !current || entry.viewId === current.viewId) return null;
        var ancestorIndex = current.origin === 'launch'
            ? -1 : this._ancestorIndex(entry.viewId);
        var returning = ancestorIndex >= 0;
        return {
            mode:returning
                ? ancestorIndex === this._entries.length - 2 ? 'back' : 'unwind'
                : 'push',
            fromViewId:current.viewId,
            depth:this._entries.length,
            revision:this._revision,
            entry:entry,
            ancestorIndex:ancestorIndex,
            restoreFocusKey:returning
                ? this._entries[ancestorIndex + 1].focusKey : ''
        };
    };
    WorkbenchViewStack.prototype.commit = function(plan) {
        var entry = plan && normalizeViewEntry(plan.entry);
        var current = this.current();
        if (!entry || !current || plan.fromViewId !== current.viewId
                || plan.depth !== this._entries.length
                || plan.revision !== this._revision) return false;
        if (plan.mode === 'back') {
            if (current.origin === 'launch'
                    || current.returnTarget !== entry.viewId
                    || !this.previous() || this.previous().viewId !== entry.viewId) return false;
            this._entries.pop();
        } else if (plan.mode === 'unwind') {
            var index = Number(plan.ancestorIndex);
            if (current.origin === 'launch' || index < 0
                    || index >= this._entries.length - 1
                    || !this._entries[index]
                    || this._entries[index].viewId !== entry.viewId) return false;
            this._entries.length = index + 1;
        } else if (plan.mode === 'push') {
            this._entries.push(entry);
        } else {
            return false;
        }
        this._revision++;
        return this.current();
    };
    WorkbenchViewStack.prototype.returnPlan = function(origin) {
        var current = this.current();
        if (!current || current.origin === 'launch') return null;
        return this.plan(
            current.returnTarget,
            origin || 'escape',
            current.focusKey);
    };
    WorkbenchViewStack.prototype.canReturnTo = function(viewId) {
        var current = this.current();
        return !!(current && current.origin !== 'launch'
            && this._ancestorIndex(viewId) >= 0);
    };
    WorkbenchViewStack.prototype.snapshot = function() {
        return this._entries.map(function(entry) { return Object.assign({}, entry); });
    };

    /** Storage is an injected presentation preference port; no panel authority lives here. */
    function ConfirmationPreference(storage, key) {
        this._storage = storage || null;
        this.key = key || MOD_CONFIRMATION_STORAGE_KEY;
    }
    ConfirmationPreference.prototype.read = function() {
        try {
            return normalizeConfirmationMode(this._storage && this._storage.getItem(this.key));
        } catch (_) {
            return 'safe';
        }
    };
    ConfirmationPreference.prototype.write = function(mode) {
        mode = normalizeConfirmationMode(mode);
        try { if (this._storage) this._storage.setItem(this.key, mode); } catch (_) {}
        return mode;
    };

    return {
        MOD_CONFIRMATION_STORAGE_KEY:MOD_CONFIRMATION_STORAGE_KEY,
        resolveProfile:resolveProfile,
        resolveView:resolveView,
        resolveReturnFocusAction:resolveReturnFocusAction,
        resolvePreparationNavigationV1:resolvePreparationNavigationV1,
        isViewAllowed:isViewAllowed,
        resolveLaunchContext:resolveLaunchContext,
        createCloseMessage:createCloseMessage,
        normalizeConfirmationMode:normalizeConfirmationMode,
        WorkbenchViewStack:WorkbenchViewStack,
        ConfirmationPreference:ConfirmationPreference
    };
});
