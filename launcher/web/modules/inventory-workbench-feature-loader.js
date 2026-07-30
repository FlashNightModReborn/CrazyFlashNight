/** Closed, view-level script closures for the standalone inventory workbench. */
(function(root, factory) {
    'use strict';
    var api = factory(root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.InventoryWorkbenchFeatureLoader = api;
})(typeof window !== 'undefined' ? window : globalThis, function(root) {
    'use strict';

    var TUNING_DEPS = [
        'modules/asset-timeline.js',
        'modules/dressup-doll-renderer.js',
        'modules/workbench-inspection-viewport.js',
        'modules/equipment-inspector.js',
        'modules/equipment-tuning-runtime.js',
        'modules/equipment-tuning-model.js',
        'modules/equipment-tuning-decision-presenter.js',
        'modules/equipment-tuning-render.js',
        'modules/equipment-tuning-confirmation.js',
        'modules/equipment-tuning-interaction.js',
        'modules/equipment-tuning-write-lifecycle.js',
        'modules/equipment-tuning-source-marker.js',
        'modules/equipment-tuning-view.js',
        'modules/inventory-tuning-scope.js'
    ];
    var BUILD_DEPS = TUNING_DEPS.concat([
        'modules/character-build/character-build-mutation.js',
        'modules/character-build-session.js',
        'modules/character-build/character-build-action-view.js',
        'modules/character-build/character-build-tuning-adapter.js',
        'modules/character-build/character-build-candidate-tooltip.js',
        'modules/character-build/character-build-candidate-state.js',
        'modules/character-build/character-build-facet-counts.js',
        'modules/character-build/character-build-stats-view.js',
        'modules/character-build/character-build-doll-preview.js',
        'modules/character-build/character-build-template.js',
        'modules/character-build-view.js',
        'modules/character-build/character-build-tuning.js',
        'modules/character-build/character-build-slot-transition.js',
        'modules/character-build/character-build-pose.js',
        'modules/character-build/character-build-projection.js',
        'modules/character-build.js'
    ]);

    function tuningReady() {
        return !!(root.EquipmentTuningRuntime
            && root.EquipmentTuningView
            && root.InventoryTuningScope
            && root.EquipmentInspector);
    }

    function buildReady() {
        return tuningReady()
            && !!(root.CharacterBuild
                && typeof root.CharacterBuild.CharacterBuildController === 'function');
    }

    function loadClosure(deps, ready, label) {
        if (ready()) return Promise.resolve();
        var loader = root.LazyLoader;
        if (!loader || typeof loader.load !== 'function') {
            return Promise.reject(new Error('LazyLoader is unavailable'));
        }
        var pending;
        try {
            pending = loader.load(deps);
        } catch (error) {
            return Promise.reject(error);
        }
        if (!pending || typeof pending.then !== 'function') {
            return Promise.reject(new Error(label + ' load returned a non-thenable'));
        }
        return pending.then(function() {
            if (!ready()) throw new Error(label + ' closure did not initialize');
        });
    }

    function descriptor(view) {
        return view === 'tuning'
            ? {view:view, title:'装备调制', deps:TUNING_DEPS,
                ready:tuningReady, label:'tuning feature'}
            : view === 'build'
                ? {view:view, title:'角色构筑', deps:BUILD_DEPS,
                    ready:buildReady, label:'character-build feature'}
                : null;
    }

    function loadView(view) {
        var feature = descriptor(view);
        return feature
            ? loadClosure(feature.deps, feature.ready, feature.label)
            : Promise.reject(new Error('unsupported inventory workbench feature'));
    }

    function FeatureGate(options) {
        this._options = options || {};
        this._pending = null;
        this._generation = 0;
    }
    FeatureGate.prototype.isLoading = function() { return !!this._pending; };
    FeatureGate.prototype.run = function(view, mount, context) {
        if (this._pending || typeof mount !== 'function') return false;
        var feature = descriptor(view);
        if (!feature || feature.ready()) return mount();
        var self = this;
        var generation = ++this._generation;
        this._pending = {view:view, generation:generation};
        if (this._options.onLoading) this._options.onLoading(feature, context);
        loadView(view).then(function() {
            if (generation !== self._generation
                    || self._options.isLive && !self._options.isLive()) return;
            self._pending = null;
            var accepted = mount();
            if (accepted === false) throw new Error(feature.label + ' mount was rejected');
            if (self._options.onLoaded) self._options.onLoaded(feature, context);
        }).catch(function(error) {
            if (generation !== self._generation
                    || self._options.isLive && !self._options.isLive()) return;
            self._pending = null;
            if (self._options.onError) self._options.onError(feature, error, context);
        });
        return true;
    };
    FeatureGate.prototype.cancel = function() {
        this._generation++;
        this._pending = null;
    };

    function createPanelGate(options) {
        options = options || {};
        return new FeatureGate({
            isLive:options.isLive,
            onLoading:function(feature) {
                options.shell.setStatus('正在加载' + feature.title, 'loading');
                options.refresh();
            },
            onLoaded:function() { options.refresh(); options.update(); },
            onError:function(feature, error, context) {
                if (typeof console !== 'undefined' && console.error) {
                    console.error('[InventoryWorkbench] feature load failed:', error);
                }
                options.refresh();
                if (context && context.initial) {
                    options.toast('工作台资源加载失败，已安全关闭。');
                    options.reject();
                    return;
                }
                options.shell.setStatus(feature.title + '加载失败', 'error');
                options.toast(feature.title + '资源加载失败，仍停留在当前视图。');
            }
        });
    }

    return {
        loadTuning:function() { return loadView('tuning'); },
        loadBuild:function() { return loadView('build'); },
        isTuningReady:tuningReady,
        isBuildReady:buildReady,
        createGate:function(options) { return new FeatureGate(options); },
        createPanelGate:createPanelGate
    };
});
