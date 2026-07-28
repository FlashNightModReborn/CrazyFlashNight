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

    function isViewAllowed(profile, view) {
        profile = typeof profile === 'string' ? profile
            : profile && typeof profile.profile === 'string' ? profile.profile : '';
        return profile === 'warehouse' ? view === 'storage'
            : profile === 'battlebox'
                && (view === 'storage' || view === 'tuning' || view === 'build');
    }

    function resolveReturnTarget(initData) {
        var target = initData && initData.returnTo;
        if (!target || target.panel !== 'crafting' || !target.initData
                || typeof target.initData.category !== 'string' || !target.initData.category) return null;
        var recipeIndex = Math.floor(Number(target.initData.preferredRecipeIndex));
        var craftCount = Math.floor(Number(target.initData.preferredCraftCount));
        return {
            panel:'crafting',
            initData:{
                category:target.initData.category,
                preferredRecipeIndex:isNaN(recipeIndex) ? -1 : recipeIndex,
                preferredCraftCount:isNaN(craftCount) ? 1 : Math.max(1, Math.min(99, craftCount))
            }
        };
    }

    function resolveLaunchContext(initData) {
        initData = initData || {};
        var profile = resolveProfile(initData);
        var view = resolveView(initData);
        var panelInstanceId = typeof initData.panelInstanceId === 'string'
            ? initData.panelInstanceId : '';
        var returnTarget = resolveReturnTarget(initData);
        var validInstance = /^[A-Za-z0-9._~-]{1,128}$/.test(panelInstanceId);
        var nestedCrafting = !panelInstanceId && returnTarget
            && profile && profile.profile === 'battlebox' && view === 'storage';
        if (!profile || !view || !isViewAllowed(profile, view)
                || (!validInstance && !nestedCrafting)
                || (validInstance && returnTarget)) return null;
        return {
            profile:profile,
            view:view,
            panelInstanceId:panelInstanceId,
            returnTarget:returnTarget,
            hostOwner:nestedCrafting ? 'crafting' : 'workbench'
        };
    }

    function createCloseMessage(hostOwner, panelInstanceId, reason) {
        if (hostOwner === 'crafting') {
            return {type:'panel', cmd:'close', panel:'crafting'};
        }
        var message = {
            type:'panel', cmd:'close', panel:'workbench',
            panelInstanceId:String(panelInstanceId || '')
        };
        if (reason === 'navigate_skills') message.reason = reason;
        return message;
    }

    function normalizeConfirmationMode(mode) { return mode === 'fast' ? 'fast' : 'safe'; }

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
        isViewAllowed:isViewAllowed,
        resolveReturnTarget:resolveReturnTarget,
        resolveLaunchContext:resolveLaunchContext,
        createCloseMessage:createCloseMessage,
        normalizeConfirmationMode:normalizeConfirmationMode,
        ConfirmationPreference:ConfirmationPreference
    };
});
