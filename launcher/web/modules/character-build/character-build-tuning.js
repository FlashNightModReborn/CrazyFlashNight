/** Character Build adapter for the shared EquipmentTuningView. */
(function(root, factory) {
    'use strict';
    var tuningView = typeof module !== 'undefined' && module.exports
        ? null : root && root.EquipmentTuningView;
    var tuningModel = typeof module !== 'undefined' && module.exports
        ? require('../equipment-tuning-model.js') : root && root.EquipmentTuningModel;
    var actionView = typeof module !== 'undefined' && module.exports
        ? require('./character-build-action-view.js') : root && root.CharacterBuildActionView;
    var api = factory(tuningView, tuningModel, actionView, root);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildTuning = api;
        root.CharacterBuildTuning = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(EquipmentTuningView, EquipmentTuningModel, CharacterBuildActionView, global) {
    'use strict';
    if (!EquipmentTuningModel || !EquipmentTuningModel.normalizeTuningSource) {
        throw new Error('CharacterBuildTuning requires EquipmentTuningModel');
    }
    if (!CharacterBuildActionView || !CharacterBuildActionView.tuningCapability) {
        throw new Error('CharacterBuildTuning requires CharacterBuildActionView');
    }
    function findLoadoutItem(payload, slotKey) {
        var rows = payload && payload.equipment || [];
        for (var i = 0; i < rows.length; i++) {
            if (rows[i] && rows[i].slotKey === slotKey && rows[i].occupied === true
                    && rows[i].item) return rows[i].item;
        }
        return null;
    }
    function findEquipment(payload, slotKey) {
        var item = findLoadoutItem(payload, slotKey);
        return CharacterBuildActionView.tuningCapability(item).available ? item : null;
    }

    function sourceFor(session, slotKey) {
        var state = session && session.debugState ? session.debugState() : null;
        return EquipmentTuningModel.normalizeTuningSource({
            sourceKind:'loadout',
            sessionGeneration:state && state.sessionGeneration,
            slotKey:String(slotKey || ''),
            expectedLoadoutRevision:state && state.loadoutRevision
        });
    }

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
        this._scrollRestoreGeneration = 0;
        this._exitGeneration = 0;
        this._density = options.density === 'compact' ? 'compact' : 'full';
    }

    CharacterBuildTuning.prototype._createPane = function(item) {
        var document = this._buildView.root.ownerDocument;
        var root = document.createElement('section');
        root.className = 'character-build-tuning-shell';
        root.innerHTML = '<header class="character-build-tuning-heading">'
            + '<div class="character-build-tuning-title"><span>当前装备调制</span><h2></h2></div><div class="character-build-tuning-tools"><div data-build-density-mount></div><button type="button" data-build-tuning-return>← 返回候选</button></div></header>'
            + '<div class="character-build-tuning-mount"></div>';
        root.querySelector('h2').textContent = String(item.displayName || item.name || this._slotKey);
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
        pane.setAttribute('aria-label', '当前装备调制');
        pane.setAttribute('data-build-pane', 'tuning');
        pane.classList.add('character-build-tuning-pane');
        this._buildView.root.setAttribute('data-build-subview', 'tuning');
        return true;
    };
    CharacterBuildTuning.prototype._syncLoadoutSlots = function() {
        if (!this._active) return false;
        var nodes = this._buildView.root.querySelectorAll('.character-build-slot');
        var locked = !this._tuningView || !this._tuningView.canClose();
        for (var i = 0; i < nodes.length; i++) {
            var eligible = nodes[i].getAttribute('data-slot-kind') !== 'drug'
                && nodes[i].getAttribute('data-empty') !== 'true'
                && nodes[i].getAttribute('data-blocked') !== 'true';
            nodes[i].disabled = locked || !eligible;
            nodes[i].setAttribute('aria-disabled', nodes[i].disabled ? 'true' : 'false');
        }
        if (this._buildView.refreshSlotNavigation) this._buildView.refreshSlotNavigation();
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
    CharacterBuildTuning.prototype._completeWrite = function(handle, _, callback) {
        if (!handle || handle !== this._writeHandle) return false;
        var completed = this._ports.completeExternalWrite
            ? this._ports.completeExternalWrite(handle, null) : true;
        if (!completed) return false;
        this._writeHandle = null;
        this._notifyStateChange();
        if (callback) callback({success:true, refreshed:false});
        return true;
    };
    CharacterBuildTuning.prototype._refreshLoadout = function(source, callback) {
        var requestedSource = EquipmentTuningModel.normalizeTuningSource(source);
        var currentSource = sourceFor(this._session, this._slotKey);
        if (!this._active || !requestedSource || !this._entrySource
                || !EquipmentTuningModel.sameLoadoutIdentity(
                    requestedSource, this._entrySource)
                || !EquipmentTuningModel.sameLoadoutIdentity(
                    currentSource, this._entrySource)
                || this._session.getState() !== 'idle') return false;
        var self = this;
        var callId = this._session.refreshSnapshot(function(response, accepted) {
            if (!self._active) return;
            if (!accepted || !response || !response.payload) {
                callback({success:false, error:response && response.error || 'loadout_snapshot_failed'});
                return;
            }
            var nextSource = sourceFor(self._session, self._slotKey);
            var item = findEquipment(response.payload, self._slotKey);
            if (!nextSource || !EquipmentTuningModel.sameLoadoutIdentity(
                    nextSource, self._entrySource) || !item) {
                callback({success:false, error:'loadout_projection_incomplete'});
                return;
            }
            self._adoptSnapshot(response.payload, false);
            self._syncLoadoutSlots();
            callback({success:true, source:nextSource, item:item});
        });
        return !!callId;
    };
    CharacterBuildTuning.prototype._openInspector = function(item, gender, role) {
        var shell = this._ports.shell;
        if (!shell || !global.EquipmentInspector || !global.EquipmentInspector.open) return false;
        this._closeInspector();
        if (global.PanelTooltip && global.PanelTooltip.hide) global.PanelTooltip.hide();
        var projection = global.InventoryWorkbenchOwnedView
            && global.InventoryWorkbenchOwnedView.primitiveProjection
            ? global.InventoryWorkbenchOwnedView.primitiveProjection(item) : item;
        var self = this, controller = null;
        controller = global.EquipmentInspector.open({
            shell:shell,
            item:projection,
            gender:gender,
            kind:'equipment-inspector',
            kicker:role === 'conversion-target' ? '交换目标检视' : '当前装备检视',
            closeLabel:'返回调制',
            context:'character-build-tuning',
            onClose:function() {
                if (self._inspector === controller) self._inspector = null;
            }
        });
        this._inspector = controller;
        return !!controller;
    };
    CharacterBuildTuning.prototype._closeInspector = function() {
        if (!this._inspector) return false;
        var controller = this._inspector;
        this._inspector = null;
        if (controller.close) controller.close();
        else if (controller.destroy) controller.destroy();
        return true;
    };
    CharacterBuildTuning.prototype.enter = function(slotKey, item, panelInstanceId) {
        var source = sourceFor(this._session, slotKey);
        if (!this._tuningModule || !this._tuningModule.create || this._active
                || !source || !CharacterBuildActionView.tuningCapability(item).available
                || this._session.getState() !== 'idle' || !String(panelInstanceId || '')) return false;
        this._scrollRestoreGeneration++;
        var scroll = this._buildView.root.querySelector('.character-build-candidate-scroll');
        this._returnState = {
            slotKey:'armor:' + slotKey,
            scrollTop:scroll ? scroll.scrollTop : 0
        };
        if (this._buildView.getSelectedSlotKey().indexOf('weapon:') === 0) {
            this._returnState.slotKey = 'weapon:' + slotKey;
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
            refreshLoadout:this._refreshLoadout.bind(this),
            onStateChange:this._notifyStateChange.bind(this),
            toast:this._ports.toast || function() {}
        };
        if (this._ports.shell && global.EquipmentInspector && global.EquipmentInspector.open) {
            options.openInspector = this._openInspector.bind(this);
            options.closeInspector = this._closeInspector.bind(this);
        }
        this._tuningView = this._tuningModule.create(options);
        this._tuningView.mount(this._mount);
        if (!this._tuningView.openSession(this._panelInstanceId)
                || !this._tuningView.handleLoadoutSelection(source, item)) {
            this._finishExit();
            return false;
        }
        this._syncLoadoutSlots();
        var returnButton = this._root.querySelector('[data-build-tuning-return]');
        if (returnButton) returnButton.focus();
        return true;
    };
    CharacterBuildTuning.prototype.selectSlot = function(slotKey, item, viewKey) {
        var source = sourceFor(this._session, slotKey);
        if (!this._active || !this._tuningView || !this._tuningView.canClose()
                || !source || !CharacterBuildActionView.tuningCapability(item).available) return false;
        if (this._slotKey !== String(slotKey)) {
            var previousSlotKey = this._slotKey, previousSource = this._entrySource;
            this._slotKey = String(slotKey); this._entrySource = source;
            if (!this._tuningView.handleLoadoutSelection(source, item)) {
                this._slotKey = previousSlotKey; this._entrySource = previousSource; return false;
            }
        }
        if (this._returnState) this._returnState.slotKey = String(viewKey || '');
        var heading = this._root && this._root.querySelector('.character-build-tuning-heading h2');
        if (heading) heading.textContent = String(item.displayName || item.name || this._slotKey);
        this._syncLoadoutSlots();
        return true;
    };
    CharacterBuildTuning.prototype._restoreScroll = function(state, attempts, generation) {
        if (!state || generation !== this._scrollRestoreGeneration
                || !this._buildView || !this._buildView.root) return;
        var scroll = this._buildView.root.querySelector('.character-build-candidate-scroll');
        if (scroll) scroll.scrollTop = state.scrollTop;
        if (attempts > 0 && this._buildView.debugState().candidateCount === 0) {
            var self = this;
            setTimeout(function() {
                self._restoreScroll(state, attempts - 1, generation);
            }, 25);
        }
    };
    CharacterBuildTuning.prototype._finishExit = function(options) {
        options = options || {};
        this._exitGeneration++;
        var state = this._returnState;
        var restoreGeneration = ++this._scrollRestoreGeneration;
        this._closeInspector();
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
        this._buildView.setInteractionState(this._session.getState());
        if (state && options.restore !== false) {
            this._buildView.restoreSlot(state.slotKey);
            this._restoreScroll(state, 8, restoreGeneration);
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
        if (!this._active) { this._scrollRestoreGeneration++; return false; }
        var destroyed = this._finishExit({restore:false});
        this._scrollRestoreGeneration++;
        return destroyed;
    };
    CharacterBuildTuning.prototype.debugState = function() {
        return {
            active:this._active,
            slotKey:this._slotKey,
            entrySessionGeneration:this._entrySource
                ? this._entrySource.sessionGeneration : 0,
            writePending:!!this._writeHandle,
            tuning:this._tuningView ? this._tuningView.debugState() : null
        };
    };
    return {
        CharacterBuildTuning:CharacterBuildTuning,
        sourceFor:sourceFor,
        tuningCapability:CharacterBuildActionView.tuningCapability,
        findLoadoutItem:findLoadoutItem,
        findEquipment:findEquipment
    };
});
