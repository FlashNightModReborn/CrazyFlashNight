/** Character Build adapter for the shared EquipmentTuningView. */
(function(root, factory) {
    'use strict';
    var tuningView = typeof module !== 'undefined' && module.exports
        ? null : root && root.EquipmentTuningView;
    var tuningModel = typeof module !== 'undefined' && module.exports
        ? require('../equipment-tuning-model.js') : root && root.EquipmentTuningModel;
    var actionView = typeof module !== 'undefined' && module.exports
        ? require('../loadout-picker/loadout-picker-action-view.js') : root && root.LoadoutPickerActionView;
    var sourceMarker = typeof module !== 'undefined' && module.exports
        ? require('../equipment-tuning-source-marker.js') : root && root.EquipmentTuningSourceMarker;
    var tuningAdapter = typeof module !== 'undefined' && module.exports
        ? require('./character-build-tuning-adapter.js') : root && root.CharacterBuildTuningAdapter;
    var tuningPorts = typeof module !== 'undefined' && module.exports
        ? require('./character-build-tuning-ports.js') : root && root.CharacterBuildTuningPorts;
    var api = factory(
        tuningView, tuningModel, actionView, sourceMarker, tuningAdapter, tuningPorts, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildTuning = api;
        root.CharacterBuildTuning = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(EquipmentTuningView, EquipmentTuningModel, LoadoutPickerActionView,
        EquipmentTuningSourceMarker, TuningAdapter, TuningPorts, global) {
    'use strict';
    if (!EquipmentTuningModel || !EquipmentTuningModel.normalizeTuningSource) {
        throw new Error('CharacterBuildTuning requires EquipmentTuningModel');
    }
    if (!LoadoutPickerActionView || !LoadoutPickerActionView.tuningCapability) {
        throw new Error('CharacterBuildTuning requires LoadoutPickerActionView');
    }
    if (!EquipmentTuningSourceMarker || !TuningAdapter
            || !TuningAdapter.CandidateFlow || !TuningPorts
            || !TuningPorts.loadConversionCandidates) {
        throw new Error('CharacterBuildTuning requires source marker, candidate flow, and ports');
    }
    var findEquipment = TuningAdapter.findEquipment, sourceFor = TuningAdapter.loadoutSourceFor;

    function CharacterBuildTuning(options) {
        options = options || {};
        if (!options.session || !options.view) {
            throw new Error('CharacterBuildTuning requires session and view ports');
        }
        this._session = options.session;
        this._buildView = options.view;
        this._tuningModule = options.tuningViewModule || EquipmentTuningView;
        this._ports = options.ports || {};
        this._send = options.send;
        this._timeoutMs = options.timeoutMs;
        this._sessionNonce = options.sessionNonce;
        this._adoptSnapshot = options.adoptSnapshot || function() {};
        this._onLockChange = options.onLockChange || function() {};
        this._active = false; this._slotKey = ''; this._entrySource = null;
        this._panelInstanceId = ''; this._pane = null; this._paneChildren = [];
        this._paneLabelledBy = ''; this._mount = null; this._root = null;
        this._tuningView = null; this._writeHandle = null; this._returnState = null;
        this._inspector = null;
        this._exitGeneration = 0;
        this._density = options.density === 'compact' ? 'compact' : 'full';
        this._projectCandidates = options.projectCandidates || function() { return []; };
        this._bindCandidateTooltip = typeof options.bindCandidateTooltip === 'function'
            ? options.bindCandidateTooltip : null;
        this._candidateFlow = new TuningAdapter.CandidateFlow({
            session:this._session,
            view:this._buildView,
            ports:this._ports,
            projectCandidates:this._projectCandidates,
            invalidateTooltip:options.invalidateCandidateTooltip
        });
    }

    CharacterBuildTuning.prototype._createPane = function(item) {
        var document = this._buildView.root.ownerDocument;
        var root = document.createElement('section');
        root.className = 'character-build-tuning-shell';
        root.innerHTML = '<header class="character-build-tuning-heading">'
            + '<div class="character-build-tuning-title"><span>'
            + (this._candidateFlow.isActive() ? '候选装备调制' : '当前装备调制')
            + '</span><h2></h2></div><div class="character-build-tuning-tools"><div data-build-density-mount></div><button type="button" data-build-tuning-return>← 返回候选</button></div></header>'
            + '<div class="character-build-tuning-mount"></div>';
        root.querySelector('h2').textContent = String(item.displayName || '未命名装备');
        var self = this;
        root.querySelector('[data-build-tuning-return]').addEventListener('click', function() { self.exit(); });
        root.addEventListener('keydown', function(event) {
            if (event && (event.key === 'Escape' || event.key === 'Esc')) {
                event.preventDefault();
                event.stopPropagation();
                self.consumeEscape();
            }
        });
        this._root = root;
        this._mount = root.querySelector('.character-build-tuning-mount');
        this.setDensity(this._density);
        return root;
    };
    CharacterBuildTuning.prototype._hideCandidatePane = function() {
        var pane = this._buildView.root.querySelector('[data-build-pane="candidates"]');
        if (!pane) return false;
        this._pane = pane;
        this._paneChildren = Array.prototype.slice.call(pane.children);
        this._paneLabelledBy = pane.getAttribute('aria-labelledby') || '';
        for (var i = 0; i < this._paneChildren.length; i++) {
            this._paneChildren[i].hidden = true;
            this._paneChildren[i].setAttribute('inert', '');
        }
        pane.removeAttribute('aria-labelledby');
        pane.setAttribute('aria-label',
            this._candidateFlow.isActive() ? '候选装备调制' : '当前装备调制');
        pane.setAttribute('data-build-pane', 'tuning');
        pane.classList.add('character-build-tuning-pane');
        this._buildView.root.setAttribute('data-build-subview', 'tuning');
        return true;
    };
    CharacterBuildTuning.prototype._syncLoadoutSlots = function() {
        if (!this._buildView.root.querySelectorAll) return false;
        var loadoutActive = this._active && !this._candidateFlow.isActive();
        var locked = loadoutActive && (!this._tuningView || !this._tuningView.canClose());
        EquipmentTuningSourceMarker.projectLoadout(
            this._buildView.root,
            loadoutActive ? this._slotKey : '',
            loadoutActive ? locked : null
        );
        if (this._active && this._buildView.refreshSlotNavigation) this._buildView.refreshSlotNavigation();
        return true;
    };
    CharacterBuildTuning.prototype._notifyStateChange = function() {
        this._onLockChange(); this._syncLoadoutSlots();
    };
    CharacterBuildTuning.prototype._beginWrite = function(owner) {
        if (!this._active || this._writeHandle) return false;
        var handle = this._ports.beginExternalWrite
            ? this._ports.beginExternalWrite(owner) : {local:true};
        if (!handle) return false;
        this._writeHandle = handle;
        this._notifyStateChange();
        return handle;
    };
    CharacterBuildTuning.prototype._completeWrite = function(handle, needsRefresh, callback, snapshots) {
        if (!handle || handle !== this._writeHandle) return false;
        var self = this;
        function complete(result) {
            if (handle !== self._writeHandle) return;
            self._writeHandle = null;
            self._notifyStateChange();
            if (callback) callback(result);
        }
        var completed = this._candidateFlow.isActive()
            ? this._candidateFlow.completeWrite(handle, !!needsRefresh, complete)
            : this._ports.completeExternalWrite
                ? this._ports.completeExternalWrite(
                    handle, snapshots || null, complete, !!needsRefresh)
                : (complete({success:true, refreshed:false}), true);
        if (!completed && handle === this._writeHandle) {
            this._writeHandle = null;
            this._notifyStateChange();
        }
        return !!completed;
    };
    CharacterBuildTuning.prototype._refreshInventory = function(callback) {
        if (this._candidateFlow.isActive()) {
            return this._candidateFlow.refreshInventory(callback);
        }
        return this._ports.refreshExternalInventory
            ? this._ports.refreshExternalInventory(callback)
            : (callback({success:true, refreshed:false}), true);
    };
    CharacterBuildTuning.prototype._resolveCandidateSlot = function(containerId, slot) {
        return this._candidateFlow.resolveSlot(containerId, slot);
    };
    CharacterBuildTuning.prototype._refreshLoadout = function(source, callback) {
        var self = this;
        return TuningAdapter.refreshLoadout({
            session:this._session, slotKey:this._slotKey,
            entrySource:this._entrySource,
            active:function() { return self._active; },
            adopt:function(payload) { self._adoptSnapshot(payload, false); },
            sync:function() { self._syncLoadoutSlots(); }
        }, source, callback);
    };
    CharacterBuildTuning.prototype._enter = function(
            slotKey, item, panelInstanceId, source, inventorySlot) {
        if (!this._tuningModule || !this._tuningModule.create || this._active
                || !source || !LoadoutPickerActionView.tuningCapability(item).available
                || this._session.getState() !== 'idle' || !String(panelInstanceId || '')) return false;
        if (!inventorySlot) {
            var scroll = this._buildView.root.querySelector('.character-build-candidate-scroll');
            this._returnState = {
                slotKey:(this._buildView.getSelectedSlotKey().indexOf('weapon:') === 0
                    ? 'weapon:' : 'armor:') + slotKey,
                scrollTop:scroll ? scroll.scrollTop : 0
            };
        }
        this._slotKey = String(slotKey);
        this._entrySource = source;
        this._panelInstanceId = String(panelInstanceId);
        this._buildView.clearCandidateSelection();
        if (!this._hideCandidatePane()) return false;
        this._active = true;
        this._pane.appendChild(this._createPane(item)); if (this._ports.syncDensityToggle) this._ports.syncDensityToggle();
        var options = {
            instanceKey:'character-build-tuning:' + this._slotKey,
            send:this._send,
            timeoutMs:this._timeoutMs,
            sessionNonce:this._sessionNonce,
            beginWrite:this._beginWrite.bind(this),
            completeWrite:this._completeWrite.bind(this),
            refreshInventory:this._refreshInventory.bind(this),
            resolveSlot:this._resolveCandidateSlot.bind(this),
            refreshLoadout:this._refreshLoadout.bind(this),
            loadConversionCandidates:TuningPorts.loadConversionCandidates.bind(null, this),
            bindSourceTooltip:TuningPorts.bindSourceTooltip.bind(null, this),
            onStateChange:this._notifyStateChange.bind(this),
            toast:this._ports.toast || function() {}
        };
        if (this._ports.shell && global.EquipmentInspector && global.EquipmentInspector.open) {
            options.openInspector = TuningPorts.openInspector.bind(null, this);
            options.closeInspector = TuningPorts.closeInspector.bind(null, this);
        }
        this._tuningView = this._tuningModule.create(options);
        this._tuningView.mount(this._mount);
        if (!this._tuningView.openSession(this._panelInstanceId)
                || !(inventorySlot
                    ? this._tuningView.handleInventorySelection(inventorySlot)
                    : this._tuningView.handleLoadoutSelection(source, item))) {
            this._finishExit();
            return false;
        }
        this._syncLoadoutSlots();
        var returnButton = this._root.querySelector('[data-build-tuning-return]');
        if (returnButton) returnButton.focus();
        return true;
    };
    CharacterBuildTuning.prototype.enter = function(slotKey, item, panelInstanceId) {
        return this._enter(slotKey, item, panelInstanceId,
            sourceFor(this._session, slotKey), null);
    };
    CharacterBuildTuning.prototype.enterCandidate = function(
            candidate, target, panelInstanceId) {
        var entry = this._candidateFlow.begin(candidate, target, panelInstanceId);
        if (!entry) return false;
        var entered = this._enter(
            target.slotKey, entry.item, panelInstanceId, entry.source, entry.slot);
        if (!entered && this._candidateFlow.isActive()) this._candidateFlow.deactivate();
        return entered;
    };
    CharacterBuildTuning.prototype.selectSlot = function(slotKey, item, viewKey) {
        var source = sourceFor(this._session, slotKey);
        var candidateSource = this._candidateFlow.isActive();
        if (!this._active || !this._tuningView || !this._tuningView.canClose()
                || !source || !LoadoutPickerActionView.tuningCapability(item).available) return false;
        if (candidateSource || this._slotKey !== String(slotKey)) {
            var previousSlotKey = this._slotKey, previousSource = this._entrySource;
            this._slotKey = String(slotKey); this._entrySource = source;
            if (!this._tuningView.handleLoadoutSelection(source, item)) {
                this._slotKey = previousSlotKey; this._entrySource = previousSource; return false;
            }
            if (candidateSource) {
                var candidateState = this._candidateFlow.deactivate();
                this._returnState = {
                    slotKey:String(viewKey || ''),
                    scrollTop:candidateState ? Number(candidateState.scrollTop) || 0 : 0
                };
            }
        }
        if (this._returnState) this._returnState.slotKey = String(viewKey || '');
        var sourceLabel = this._candidateFlow.isActive() ? '候选装备调制' : '当前装备调制';
        var label = this._root && this._root.querySelector('.character-build-tuning-title > span');
        var heading = this._root && this._root.querySelector('.character-build-tuning-heading h2');
        if (label) label.textContent = sourceLabel;
        if (heading) heading.textContent = String(item.displayName || '未命名装备');
        if (this._pane) this._pane.setAttribute('aria-label', sourceLabel);
        this._syncLoadoutSlots();
        return true;
    };
    CharacterBuildTuning.prototype._finishExit = function(options) {
        options = options || {};
        this._exitGeneration++;
        var state = this._returnState;
        var postSource = this._candidateFlow.postSource(this._tuningView);
        var candidateState = this._candidateFlow.deactivate();
        TuningPorts.closeInspector(this);
        if (this._tuningView) this._tuningView.destroy();
        this._tuningView = null;
        if (this._root && this._root.parentNode) this._root.parentNode.removeChild(this._root);
        if (this._pane) {
            this._pane.classList.remove('character-build-tuning-pane');
            this._pane.setAttribute('data-build-pane', 'candidates');
            this._pane.removeAttribute('aria-label');
            if (this._paneLabelledBy) this._pane.setAttribute('aria-labelledby', this._paneLabelledBy);
        }
        for (var i = 0; i < this._paneChildren.length; i++) {
            this._paneChildren[i].hidden = false;
            this._paneChildren[i].removeAttribute('inert');
        }
        this._buildView.root.removeAttribute('data-build-subview'); if (this._ports.syncDensityToggle) this._ports.syncDensityToggle();
        this._active = false; this._slotKey = ''; this._entrySource = null;
        this._panelInstanceId = ''; this._pane = null; this._paneChildren = [];
        this._root = null; this._mount = null; this._returnState = null;
        this._syncLoadoutSlots();
        this._buildView.setInteractionState(this._session.getState());
        if (candidateState && options.restore !== false) {
            this._buildView.restoreCandidateTuning(
                this._candidateFlow.returnPlan(candidateState, postSource),
                candidateState);
        } else if (state && options.restore !== false) {
            this._buildView.restoreSlot(state.slotKey);
            var scroll = this._buildView.root.querySelector('.character-build-candidate-scroll');
            if (scroll) scroll.scrollTop = state.scrollTop;
        }
        this._onLockChange();
        return true;
    };
    CharacterBuildTuning.prototype.exit = function(callback, options) {
        callback = typeof callback === 'function' ? callback : function() {};
        options = options || {};
        if (!this._active) { callback(true); return true; }
        if (this._writeHandle || !this._tuningView || !this._tuningView.canClose()) {
            if (this._ports.toast) this._ports.toast('调制写入或对账尚未完成，请稍候返回。');
            callback(false);
            return false;
        }
        var self = this, exitGeneration = ++this._exitGeneration;
        return this._tuningView.detachSession(function(detached) {
            if (exitGeneration !== self._exitGeneration || !self._active) return;
            if (detached) self._finishExit(options);
            callback(!!detached);
        });
    };
    CharacterBuildTuning.prototype.setDensity = function(mode) {
        this._density = mode === 'compact' ? 'compact' : 'full';
        if (this._mount) this._mount.classList.toggle('item-grid-compact', this._density === 'compact');
        return true;
    };
    CharacterBuildTuning.prototype.openHelp = function() { return !!(this._tuningView && this._tuningView.openHelp(this._ports.openModal)); };
    CharacterBuildTuning.prototype.isActive = function() { return this._active; };
    CharacterBuildTuning.prototype.consumeEscape = function() {
        if (!this._active) return false;
        if (this._tuningView && typeof this._tuningView.consumeEscape === 'function' && this._tuningView.consumeEscape()) return true;
        return this.exit();
    };
    CharacterBuildTuning.prototype.isLocked = function() {
        return !!this._writeHandle || !!(this._active
            && (!this._tuningView || !this._tuningView.canClose()));
    };
    CharacterBuildTuning.prototype.lockReason = function() {
        return this.isLocked() ? '当前装备调制正在读取、写入或对账，完成后才能切换。' : '';
    };
    CharacterBuildTuning.prototype.canExit = function() {
        return !this._active || !!(!this._writeHandle
            && this._tuningView && this._tuningView.canClose());
    };
    CharacterBuildTuning.prototype.destroy = function() {
        return this._active ? this._finishExit({restore:false}) : false;
    };
    CharacterBuildTuning.prototype.debugState = function() {
        return {
            active:this._active,
            slotKey:this._slotKey,
            entrySessionGeneration:this._entrySource
                ? this._entrySource.sessionGeneration : 0,
            candidateSource:this._candidateFlow.isActive(),
            writePending:!!this._writeHandle,
            tuning:this._tuningView ? this._tuningView.debugState() : null
        };
    };
    return {
        CharacterBuildTuning:CharacterBuildTuning,
        sourceFor:sourceFor,
        tuningCapability:LoadoutPickerActionView.tuningCapability,
        findLoadoutItem:TuningAdapter.findLoadoutItem,
        findEquipment:findEquipment
    };
});
