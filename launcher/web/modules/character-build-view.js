/* Character-build DOM/focus/presentation; transport and writes stay outside. */
(function(root, factory) {
    'use strict';
    var focus = typeof module !== 'undefined' && module.exports
        ? require('./workbench-focus.js')
        : root && (root.WorkbenchFocus || root.CF7 && root.CF7.WorkbenchFocus);
    var components = typeof module !== 'undefined' && module.exports
        ? require('./workbench-components.js')
        : root && (root.WorkbenchComponents || root.CF7 && root.CF7.WorkbenchComponents);
    var loadoutPicker = typeof module !== 'undefined' && module.exports
        ? require('./loadout-picker/loadout-picker.js')
        : root && root.LoadoutPicker;
    var facetCounts = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-facet-counts.js')
        : root && root.CharacterBuildFacetCounts;
    var stats = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-stats-view.js')
        : root && root.CharacterBuildStatsView;
    var preview = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-doll-preview.js')
        : root && root.CharacterBuildDollPreview;
    var template = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-template.js')
        : root && root.CharacterBuildTemplate;
    var loadoutPresenter = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-loadout-presenter.js')
        : root && root.CharacterBuildLoadoutPresenter;
    var openManyView = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-item-use-openmany-view.js')
        : root && root.CharacterBuildItemUseOpenManyView;
    var drugControls = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-drug-controls.js')
        : root && root.CharacterBuildDrugControls;
    var api = factory(
        focus, components, facetCounts,
        stats, preview, template, loadoutPresenter, loadoutPicker, openManyView, drugControls);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildView = api;
        root.CharacterBuildView = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchFocus, WorkbenchComponents,
        FacetCountsModule, StatsViewModule, DollPreviewModule, TemplateModule,
        LoadoutPresenterModule, LoadoutPickerModule, OpenManyViewModule, DrugControls) {
    'use strict';
    if (!WorkbenchFocus || typeof WorkbenchFocus.RovingGridFocus !== 'function') {
        throw new Error('character-build-view.js requires RovingGridFocus');
    }
    if (!WorkbenchComponents
            || typeof WorkbenchComponents.SecondaryPage !== 'function'
            || typeof WorkbenchComponents.ChoiceGroup !== 'function') {
        throw new Error('character-build-view.js requires SecondaryPage and ChoiceGroup');
    }
    if (!FacetCountsModule || typeof FacetCountsModule.normalize !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildFacetCounts');
    }
    if (!StatsViewModule || !StatsViewModule.StatsView) {
        throw new Error('character-build-view.js requires CharacterBuildStatsView');
    }
    if (!DollPreviewModule || typeof DollPreviewModule.create !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildDollPreview');
    }
    if (!TemplateModule || typeof TemplateModule.create !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildTemplate');
    }
    if (!LoadoutPresenterModule || typeof LoadoutPresenterModule.install !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildLoadoutPresenter');
    }
    if (!LoadoutPickerModule || typeof LoadoutPickerModule.install !== 'function'
            || typeof LoadoutPickerModule.initState !== 'function') {
        throw new Error('character-build-view.js requires LoadoutPicker');
    if (!OpenManyViewModule || typeof OpenManyViewModule.syncButton !== 'function'
            || typeof OpenManyViewModule.tryUse !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildItemUseOpenManyView');
    }
    }

    var ARMOR_SLOTS = TemplateModule.armorSlots, WEAPON_SLOTS = TemplateModule.weaponSlots,
        DRUG_SLOTS = TemplateModule.drugSlots;
    var candidateViewSequence = 0;
    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function closest(target, selector, root) {
        if (!target || typeof target.closest !== 'function') return null;
        var match = target.closest(selector);
        return match && (!root || root.contains(match)) ? match : null;
    }
    function listen(records, target, type, handler, options) {
        target.addEventListener(type, handler, options);
        records.push(function() {
            target.removeEventListener(type, handler, options);
        });
    }
    function CharacterBuildView(options) {
        options = options || {};
        var self = this;
        this._document = options.document || (typeof document !== 'undefined' ? document : null);
        if (!this._document) throw new Error('CharacterBuildView requires a document');
        this._snapshot = null;
        this._mounted = false;
        this._destroyed = false;
        this._listeners = [];
        this._density = options.density === 'compact' ? 'compact' : 'full';
        this._onRequestClose = typeof options.onRequestClose === 'function'
            ? options.onRequestClose : function() { return true; };
        this._onSlotSelect = typeof options.onSlotSelect === 'function'
            ? options.onSlotSelect : function() {};
        this._onCandidateSelect = typeof options.onCandidateSelect === 'function'
            ? options.onCandidateSelect : function() {};
        this._onCandidateScopeChange = typeof options.onCandidateScopeChange === 'function'
            ? options.onCandidateScopeChange : function() { return true; };
        this._onCommitCandidate = typeof options.onCommitCandidate === 'function'
            ? options.onCommitCandidate : function() {};
        this._onUseCandidate = typeof options.onUseCandidate === 'function'
            ? options.onUseCandidate : function() {};
        this._onOpenInbox = typeof options.onOpenInbox === 'function'
            ? options.onOpenInbox : function() {};
        this._onSlotDropEquip = typeof options.onSlotDropEquip === 'function'
            ? options.onSlotDropEquip
            : function(slotKey, candidate) {
                return slotKey === self._selectedSlotKey
                    ? self._onCommitCandidate(candidate) : false;
            };
        if (typeof options.renderOwnedSlot !== 'function') {
            throw new Error('CharacterBuildView requires InventoryUI.renderOwnedSlot');
        }
        this._renderOwnedSlot = options.renderOwnedSlot;
        this._iconHtml = typeof options.iconHtml === 'function'
            ? options.iconHtml : function() { return ''; };
        this._onStatsModeChange = typeof options.onStatsModeChange === 'function'
            ? options.onStatsModeChange : function() {};
        this._onDollViewportChange = typeof options.onDollViewportChange === 'function'
            ? options.onDollViewportChange : function() {};
        this._onCustomizationDrugClick = typeof options.onCustomizationDrugClick === 'function'
            ? options.onCustomizationDrugClick : null;
        this._statsReturnFocus = null;
        var viewSequence = ++candidateViewSequence;
        LoadoutPickerModule.initState(this, {
            candidateScope:options.candidateScope,
            viewSequence:viewSequence
        });
        this._tooltip = options.tooltip || null;
        this._fetchLoadoutTooltip = typeof options.fetchLoadoutTooltip === 'function'
            ? options.fetchLoadoutTooltip : null;
        this._loadoutTooltipCache = {};
        this._loadoutTooltipEpoch = 0;
        this._loadoutTooltipScope = this._tooltip
                && typeof this._tooltip.createScope === 'function'
            ? this._tooltip.createScope('character-build-loadout-' + viewSequence, {
                profile:'dense-inspect'
            }) : null;
        this._stats = null;
        this._facetCounts = FacetCountsModule.normalize(null);
        this._itemUseState = 'idle';
        this._selectedUseCandidate = null;
        this._inboxSummary = null;
        this._stickyNotice = null;
        this._createDOM();
        this.exitButton = this.root.querySelector('[data-persist-and-exit]');
        if (this.exitButton && options.onPersistAndExit) this.exitButton.onclick = options.onPersistAndExit;
        LoadoutPickerModule.createScopeGroup(this);
        this.setDensity(this._density);
        this._statsView = new StatsViewModule.StatsView({
            host:this._statsGrid,
            scroll:this._statsScroll,
            hint:this._statsScrollHint,
            copy:this._statsScrollCopy,
            glyph:this._statsScrollGlyph
        });
        this._createFocusControllers();
        this._onQuickUnequip = options.onUnequip; this._onQuickTune = options.onTune;
        this._bindInteractions();
        this._installSlotQuickBar();
        LoadoutPickerModule.createActionView(this, {
            onCommit:this._onCommitCandidate,
            resolveSmartSlot:function(c) { return self._resolveSmartSlot(c); },
            onSmartCommit:function(k, c) { return self._onSlotDropEquip(k, c); },
            onTune:options.onTune, onUnequip:options.onUnequip, onReconcile:options.onReconcile
        });
        LoadoutPickerModule.createCandidateState(this, {
            bindTooltip:function(node, candidate) {
                return typeof options.bindCandidateTooltip === 'function'
                    ? options.bindCandidateTooltip(node, candidate, function() {
                        return self._candidateDragActive;
                    }) : null;
            },
            onBlocked:function(candidate, context) {
                if (candidate.tunable === true && self._interactionState === 'idle') {
                    if (self._selectedCandidateKey === candidate.key) self.clearCandidateSelection();
                    else self._selectCandidate(candidate.key);
                }
                return self._explainBlockedCandidate(candidate, context);
            },
            onRetry:function(requestKey) { return self._retryCandidates(requestKey); }
        });
        this._installCandidateDrag();
        this._setCandidateState('unselected', [], '');
    }
    CharacterBuildView.prototype._createDOM = function() {
        var root = this.root = this._document.createElement('section');
        root.className = 'character-build-workbench';
        root.setAttribute('role', 'region');
        root.setAttribute('aria-label', '角色构筑编辑');
        root.setAttribute('data-render-model', 'single-canvas-candidate-overlay');
        root.setAttribute('data-density', this._density);
        root.innerHTML = TemplateModule.create();

        this._underlay = root.querySelector('[data-build-underlay]');
        this._canvas = root.querySelector('.character-build-doll-canvas');
        this._dollHome = root.querySelector('[data-doll-stage-home]');
        this._dollStage = root.querySelector('.character-build-doll-stage');
        this._dollButtonHost = root.querySelector('[data-doll-preview-action-host]');
        this._overlayCopy = root.querySelector('[data-overlay-copy]');
        this._armorGrid = root.querySelector('[data-armor-grid]');
        this._weaponGrid = root.querySelector('[data-weapon-grid]');
        this._drugGrid = root.querySelector('[data-drug-grid]');
        this._drugBankGrids = Array.prototype.slice.call(
            root.querySelectorAll('[data-drug-bank-grid]'));
        this._drugBanks = Array.prototype.slice.call(
            root.querySelectorAll('[data-drug-bank]'));
        this._drugSwitchStatus = root.querySelector('[data-drug-switch-status]');
        this._notice = root.querySelector('[data-build-notice]');
        this._notice.setAttribute('role', 'status');
        this._notice.setAttribute('aria-live', 'polite');
        this._slotFocusSummary = root.querySelector('[data-focus-summary]');
        this._candidateList = root.querySelector('[data-candidate-list]');
        this._candidateCount = root.querySelector('[data-candidate-count]');
        this._candidateScopeMount = root.querySelector('[data-build-candidate-scope-mount]');
        this._candidateFocusSummary = root.querySelector('[data-candidate-focus-summary]');
        this._useButton = root.querySelector('[data-build-action="use"]');
        this._inboxButton = root.querySelector('[data-build-action="inbox"]');
        this._useManyButton = root.querySelector('[data-build-action="useMany"]');
        this._statsRoot = root.querySelector('.character-build-stats-page');
        this._statsScroll = root.querySelector('[data-scroll-region="stats"]');
        this._statsGrid = root.querySelector('[data-stats-grid]');
        this._statsScrollHint = root.querySelector('[data-stats-scroll-hint]');
        this._statsScrollCopy = root.querySelector('[data-stats-scroll-copy]'); this._statsScrollGlyph = root.querySelector('[data-stats-scroll-glyph]');

        var self = this;
        this._statsPage = new WorkbenchComponents.SecondaryPage({
            root:this._statsRoot,
            document:this._document,
            role:'dialog',
            ariaLabel:'个人信息统计',
            onClose:function(reason) { self._leaveStatsMode(reason); }
        });
        this._statsPage.mount(root);
        this._dollPreview = DollPreviewModule.create({
            document:this._document, root:root, stage:this._dollStage,
            canvas:this._canvas, home:this._dollHome, buttonHost:this._dollButtonHost,
            underlays:function() {
                var shell = root.closest('.inventory-workbench-panel');
                var header = shell && shell.querySelector('.workbench-header');
                return header ? [self._underlay, header] : self._underlay;
            },
            onViewportChange:this._onDollViewportChange
        });
    };

    CharacterBuildView.prototype._createFocusControllers = function() {
        var self = this;
        this._armorRoving = new WorkbenchFocus.RovingGridFocus({
            root:this._armorGrid,
            columns:3,
            onActiveChange:function(key) { self._focusSlot(key); }
        });
        this._weaponRoving = new WorkbenchFocus.RovingGridFocus({
            root:this._weaponGrid,
            columns:3,
            onActiveChange:function(key) { self._focusSlot(key); }
        });
        this._drugRoving = new WorkbenchFocus.RovingGridFocus({
            root:this._drugGrid,
            columns:4,
            onActiveChange:function(key) { self._focusSlot(key); }
        });
        this._slotRovings = [this._armorRoving, this._weaponRoving, this._drugRoving];
        this._candidateRoving = new WorkbenchFocus.RovingGridFocus({
            root:this._candidateList,
            columns:function() { return self._document.defaultView.getComputedStyle(self._candidateList).gridTemplateColumns.split(/\s+/).length; },
            onActiveChange:function(key) { self._focusCandidate(key); }
        });
    };

    CharacterBuildView.prototype._bindInteractions = function() {
        var self = this;
        var capturedUseEnter = null;
        // Capture the pre-keydown selection state. The shared candidate handler
        // selects on the first Enter before the event bubbles to this root.
        listen(this._listeners, this.root, 'keydown', function(event) {
            var node = event && event.key === 'Enter' && !event.repeat
                ? closest(event.target, '[data-candidate-key]', self._candidateList)
                : null;
            capturedUseEnter = node ? {
                event:event,
                key:String(node.getAttribute('data-candidate-key') || ''),
                wasSelected:String(node.getAttribute('data-candidate-key') || '')
                    === self._selectedCandidateKey
            } : null;
        }, true);
        listen(this._listeners, this._armorGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._armorGrid);
            if (slot) self._selectUserSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._weaponGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._weaponGrid);
            if (slot) self._selectUserSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._drugGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._drugGrid);
            if (!slot) return;
            if (self.root.getAttribute('data-build-subview') === 'tuning'
                    && self.root.getAttribute('data-build-tuning-mode') === 'customization'
                    && self._onCustomizationDrugClick) {
                var slotMatch = /^drug([1-8])$/.exec(String(slot.getAttribute('data-slot-id') || ''));
                if (slotMatch) {
                    self._onCustomizationDrugClick(Number(slotMatch[1]) - 1);
                    return;
                }
            }
            self._selectUserSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._candidateList, 'click', function(event) {
            if (self._candidateDrag && self._candidateDrag.consumeClick()) {
                if (event.preventDefault) event.preventDefault();
                if (event.stopPropagation) event.stopPropagation();
                return;
            }
            var candidate = closest(event.target, '[data-roving-key]', self._candidateList);
            if (self._interactionState !== 'idle') return;
            if (!candidate) { self.clearCandidateSelection(); return; }
            var key = candidate.getAttribute('data-roving-key');
            if (key !== self._selectedCandidateKey) self._selectCandidate(key, 'pointer');
        });
        listen(this._listeners, this._candidateList, 'dblclick', function(event) {
            var node = closest(event.target, '[data-candidate-key]', self._candidateList);
            if (!node || self._interactionState !== 'idle') return;
            var candidate = self._candidateByKey(node.getAttribute('data-candidate-key'));
            if (!candidate || candidate.blocked === true || candidate.useAction) return;
            if (event.preventDefault) event.preventDefault();
            if (event.stopPropagation) event.stopPropagation();
            if (self._selectCandidate(candidate.key)) self._actionView.commitCandidate(candidate);
        });
        listen(this._listeners, this.root, 'focusin', function(event) {
            var node = closest(event.target, '[data-roving-key]', self.root);
            if (!node) return;
            var key = node.getAttribute('data-roving-key');
            if (node.hasAttribute('data-candidate-key')) self._focusCandidate(key);
            else self._focusSlot(key);
        });
        listen(this._listeners, this.root, 'click', function(event) {
            var button = closest(event.target, '[data-build-action]', self.root);
            if (!button || button.disabled) return;
            var action = button.getAttribute('data-build-action');
            if (action === 'use') self._tryUseCandidate(self._selectedUseCandidate);
            else if (action === 'useMany') OpenManyViewModule.tryUse(self, self._selectedUseCandidate);
            else if (action === 'inbox') self._onOpenInbox();
        });
        listen(this._listeners, this.root, 'keydown', function(event) {
            var captured = capturedUseEnter && capturedUseEnter.event === event
                ? capturedUseEnter : null;
            capturedUseEnter = null;
            if (captured && captured.wasSelected
                    && captured.key === self._selectedCandidateKey) {
                var selected = self._candidateByKey(captured.key);
                if (selected && selected.useAction) {
                    event.preventDefault();
                    if (event.stopImmediatePropagation) event.stopImmediatePropagation();
                    self._tryUseCandidate(selected);
                    return;
                }
            }
            if (!event || (event.key !== 'Escape' && event.key !== 'Esc')
                    || self._statsPage.isActive()) return;
            if (self._isFocusInSlotQuickBar && self._isFocusInSlotQuickBar() && self._dismissSlotQuickBar(true)) {
                event.preventDefault(); if (event.stopPropagation) event.stopPropagation(); return;
            }
            if (self._selectedCandidateKey || (self._dismissSlotQuickBar && self._dismissSlotQuickBar(true))) {
                event.preventDefault(); if (event.stopPropagation) event.stopPropagation();
                if (self._selectedCandidateKey) self.clearCandidateSelection();
                return;
            }
            event.preventDefault();
            if (event.stopPropagation) event.stopPropagation();
            self._requestOuterClose('escape');
        });
        listen(this._listeners, this._statsScroll, 'scroll', function() {
            self._syncStatsScrollAffordance();
        });
        if (this._document.defaultView) {
            listen(this._listeners, this._document.defaultView, 'resize', function() {
                self._syncStatsScrollAffordance();
                self._dollPreview.resize();
                self.syncDollViewport('resize');
            });
        }
    };

    CharacterBuildView.prototype._selectUserSlot = function(key, reason) {
        if (this._interactionState !== 'idle') return false;
        this._stickyNotice = null;
        // Re-selecting the same worn slot is an explicit source choice, not
        // a request to keep the backpack candidate selected.
        if (key === this._selectedSlotKey) {
            if (this.root.getAttribute('data-build-subview') === 'tuning') {
                return this._selectSlot(key, true);
            }
            this.clearCandidateSelection();
        }
        return this._selectSlot(key, reason);
    };

    CharacterBuildView.prototype._tryUseCandidate = function(candidate) {
        if (!candidate || !candidate.useAction) return false;
        if (candidate.useBlockedReason) {
            this._showStatusNotice('blocked', candidate.useBlockedReason);
            return false;
        }
        if (this._itemUseState !== 'idle'
                && this._itemUseState !== 'needs_reconcile') return false;
        return this._onUseCandidate(candidate) !== false;
    };

    CharacterBuildView.prototype._syncItemUseActions = function() {
        if (!this._useButton || !this._inboxButton) return false;
        var candidate = this._selectedUseCandidate;
        var action = candidate && candidate.useAction;
        var reconciling = this._itemUseState === 'needs_reconcile';
        var submitting = this._itemUseState === 'write_pending';
        var confirming = this._itemUseState === 'query_pending';
        var actionCommand = action && String(action.command || '');
        var pendingLabel = actionCommand === 'consume'
            ? (confirming ? '正在确认服用…' : '正在服用…')
            : actionCommand === 'open'
                ? (confirming ? '正在确认开箱…' : '正在打开…')
                : actionCommand === 'openMany'
                    ? (confirming ? '正在确认批量开箱…' : '正在批量打开…')
                    : '处理中…';
        var commit = this.root.querySelector('[data-build-action="commit"]');
        var tune = this.root.querySelector('[data-build-action="tune"]');
        var unequip = this.root.querySelector('[data-build-action="unequip"]');
        if (commit) commit.hidden = !!action && !this._selectedSlotKey;
        if (unequip) unequip.hidden = !!action;
        if (action && tune) tune.hidden = true;
        this._useButton.hidden = !action;
        this._useButton.textContent = reconciling ? '重新确认'
            : submitting || confirming ? pendingLabel
            : action ? String(action.label || '使用') : '使用';
        this._useButton.disabled = !action || !!candidate.useBlockedReason
            || (this._itemUseState !== 'idle' && !reconciling)
            || (this._interactionState !== 'idle' && !reconciling);
        this._useButton.setAttribute('aria-label', candidate && candidate.useBlockedReason
            ? candidate.useBlockedReason : reconciling
                ? '重新确认上次物品使用结果'
                : submitting || confirming
                    ? pendingLabel.replace(/…$/, '') + String(candidate && candidate.name || '所选物品')
                : action ? String(action.label || '使用') + String(candidate.name || '所选物品')
                    : '使用所选物品');
        OpenManyViewModule.syncButton(this, {
            candidate:candidate, action:action, reconciling:reconciling,
            submitting:submitting, confirming:confirming, pendingLabel:pendingLabel
        });
        if (candidate && candidate.useBlockedReason) {
            this._useButton.setAttribute('title', candidate.useBlockedReason);
        } else this._useButton.removeAttribute('title');

        var remaining = Number(this._inboxSummary && this._inboxSummary.remainingCount) || 0;
        this._inboxButton.hidden = false;
        this._inboxButton.textContent = remaining > 0 ? '暂存 ' + remaining : '暂存物资';
        this._inboxButton.disabled = this._itemUseState !== 'idle'
            || this._interactionState !== 'idle';
        return true;
    };

    CharacterBuildView.prototype.setItemUseCandidate = function(candidate) {
        this._selectedUseCandidate = candidate && candidate.useAction ? candidate : null;
        return this._syncItemUseActions();
    };

    CharacterBuildView.prototype.captureItemUseFocus = function() {
        var active = this._document && this._document.activeElement;
        if (active === this._useButton) return 'action';
        return active && this._candidateList && this._candidateList.contains(active)
            ? 'candidate' : '';
    };

    CharacterBuildView.prototype.restoreItemUseCandidate = function(candidate, focusMode) {
        if (this._destroyed || !candidate || !candidate.key
                || !this._selectCandidate(candidate.key)) return false;
        this._activeCandidateKey = String(candidate.key);
        this._candidateRoving.refresh({preferredKey:this._activeCandidateKey});
        if (focusMode === 'candidate') {
            this._candidateState.focusCandidate(
                this._activeCandidateKey, this._candidateList.parentNode);
        } else if (focusMode === 'action' && this._useButton
                && !this._useButton.hidden && !this._useButton.disabled) {
            try { this._useButton.focus({preventScroll:true}); }
            catch (_) { this._useButton.focus(); }
        }
        return true;
    };

    CharacterBuildView.prototype.setItemUseState = function(state) {
        this._itemUseState = String(state || 'idle');
        return this._syncItemUseActions();
    };

    CharacterBuildView.prototype.setInboxSummary = function(summary) {
        this._inboxSummary = summary || null;
        return this._syncItemUseActions();
    };

    CharacterBuildView.prototype.showActionNotice = function(kind, message) {
        if (this._destroyed || !message) return false;
        this._stickyNotice = {kind:kind || 'error', message:String(message)};
        this._showStatusNotice(this._stickyNotice.kind, this._stickyNotice.message);
        return true;
    };
    CharacterBuildView.prototype.showItemUseResult = function(message) {
        return CharacterBuildView.prototype.showActionNotice.call(this, 'success', message);
    };

    CharacterBuildView.prototype.mount = function(host) {
        if (this._destroyed || !host) return false;
        if (this.root.parentNode !== host) host.appendChild(this.root);
        this._mounted = true;
        return true;
    };
    CharacterBuildView.prototype.syncDollViewport = function(reason) {
        this._onDollViewportChange(this._dollPreview.isOpen() ? 'expanded' : 'embedded', this._dollStage, this._dollPreview, reason || 'resize');
    };

    CharacterBuildView.prototype.setDensity = function(mode) {
        if (this._destroyed) return false;
        this._density = mode === 'compact' ? 'compact' : 'full';
        this.root.setAttribute('data-density', this._density);
        this._candidateList.classList.toggle('item-grid-compact', this._density === 'compact');
        return true;
    };

    CharacterBuildView.prototype._renderStats = function(stats) { return this._statsView.render(stats || {}); };
    CharacterBuildView.prototype._syncStatsScrollAffordance = function() {
        return this._statsView.syncScrollAffordance();
    };
    CharacterBuildView.prototype._enterStatsMode = function(opener) {
        this._statsReturnFocus = opener || this._document.activeElement;
        this.root.setAttribute('data-view', 'stats');
        this._onStatsModeChange(true, this._statsRoot, this._statsReturnFocus);
        return this._statsScroll;
    };

    CharacterBuildView.prototype._leaveStatsMode = function() {
        var returnFocus = this._statsReturnFocus;
        this._statsReturnFocus = null;
        this.root.removeAttribute('data-view');
        this._onStatsModeChange(false, this._statsRoot, returnFocus);
        if (returnFocus && typeof returnFocus.focus === 'function') {
            try { returnFocus.focus({preventScroll:true}); }
            catch (_) { returnFocus.focus(); }
        }
    };

    CharacterBuildView.prototype.openStats = function(opener) {
        if (this._destroyed) return false;
        if (this._statsPage.isActive()) return true;
        this._renderStats(this._stats);
        this._statsScroll.scrollTop = 0;
        var initialFocus = this._enterStatsMode(opener);
        var opened = this._statsPage.open({
            opener:this._statsReturnFocus,
            initialFocus:initialFocus,
            underlay:this._underlay
        });
        if (!opened) this._leaveStatsMode();
        else this._syncStatsScrollAffordance();
        return opened;
    };

    CharacterBuildView.prototype.closeStats = function(reason) {
        return this._statsPage.close(reason || 'back');
    };

    CharacterBuildView.prototype._requestOuterClose = function(reason) {
        return this._onRequestClose({
            reason:reason || 'close',
            selectedSlotKey:this._selectedSlotKey,
            selectedCandidateKey:this._selectedCandidateKey
        }) !== false;
    };

    CharacterBuildView.prototype._showStatusNotice = function(kind, message) {
        if (kind !== 'success' && (!this._stickyNotice || this._stickyNotice.message !== message)) this._stickyNotice = null;
        this._notice.textContent = message;
        this._notice.setAttribute('data-notice-kind', kind || 'error');
    };
    CharacterBuildView.prototype._showBrowsingNotice = function(message) {
        var sticky = this._stickyNotice;
        this._notice.textContent = sticky ? sticky.message : message;
        this._notice.setAttribute('data-notice-kind', sticky ? sticky.kind : 'browsing');
    };

    CharacterBuildView.prototype.setSnapshot = function(snapshot) {
        if (this._destroyed) return false;
        this._loadoutTooltipEpoch++;
        this._loadoutTooltipCache = {};
        this._snapshot = snapshot || {};
        this._stickyNotice = null;
        this._facetCounts = FacetCountsModule.normalize(this._snapshot.candidateFacets);
        this.root.setAttribute('data-backpack-full',
            FacetCountsModule.backpackCapacity(this._facetCounts).full ? 'true' : 'false');
        if (this.root.getAttribute('data-build-subview') !== 'tuning') this._selectedSlotKey = '';
        this._selectedCandidateKey = '';
        this._candidateRequestKey = '';
        this._candidateLoadFailed = this.root.getAttribute('data-build-subview') === 'tuning';
        this._candidateFailureCode = '';
        this._candidateRecoveryPending = false;
        this.root.setAttribute('data-build-state', this._snapshot.blocked ? 'blocked' : 'ready');
        this._renderSlotGroup(
            this._armorGrid, ARMOR_SLOTS, this._snapshot.equipment, 'armor', this._armorRoving);
        this._renderSlotGroup(
            this._weaponGrid, WEAPON_SLOTS, this._snapshot.equipment, 'weapon', this._weaponRoving);
        var drugSlots = DrugControls.drugDefinitions(this._snapshot, DRUG_SLOTS);
        this._renderSlotGroup(
            this._drugBankGrids[0], drugSlots.slice(0, 4),
            this._snapshot.drugs, 'drug', this._drugRoving);
        this._renderSlotGroup(
            this._drugBankGrids[1], drugSlots.slice(4, 8),
            this._snapshot.drugs, 'drug', this._drugRoving);
        var activeBank = Number(this._snapshot.drugLayout
            && this._snapshot.drugLayout.activeBank);
        this.root.setAttribute('data-active-drug-bank', String(activeBank));
        for (var bank = 0; bank < this._drugBanks.length; bank++) {
            var active = bank === activeBank;
            this._drugBanks[bank].setAttribute('data-active', active ? 'true' : 'false');
            this._drugBanks[bank].setAttribute('aria-current', active ? 'true' : 'false');
            var bankState = this._drugBanks[bank].querySelector(
                '[data-drug-bank-state]');
            if (bankState) bankState.textContent = active ? '当前组' : '备用组';
        }
        this._drugSwitchStatus.textContent = DrugControls.switchSummary(
            this._snapshot.drugLayout);
        this._focusSlot(this._activeSlotKey);
        this._setCandidateState('unselected', [], '');
        this._notice.textContent = this._snapshot.blocked
            ? text(this._snapshot.blockedReason, '当前候选不满足装备条件。')
            : '正在打开背包总览；选择槽位后会切换为该栏位的兼容候选。';
        this._notice.setAttribute('data-notice-kind', this._snapshot.blocked ? 'blocked' : 'browsing');
        this._syncSlotSelection();
        this._syncCandidateSelection();
        return true;
    };


    CharacterBuildView.prototype.setStats = function(stats) {
        if (this._destroyed || !stats || typeof stats !== 'object') return false;
        this._stats = stats;
        this._renderStats(stats);
        return true;
    };

    CharacterBuildView.prototype.getCanvas = function() { return this._canvas; };
    CharacterBuildView.prototype.getStatsRoot = function() { return this._statsRoot; };
    CharacterBuildView.prototype.getSelectedSlotKey = function() { return this._selectedSlotKey; };
    CharacterBuildView.prototype.focusDrugSlot = function(drugId) {
        if (this._destroyed) return false;
        var key = 'drug:' + String(drugId || 'drug1');
        if (typeof this.restoreSlot === 'function' && this.restoreSlot(key)) return true;
        return typeof this._selectUserSlot === 'function' ? !!this._selectUserSlot(key, 'programmatic') : false;
    };
    CharacterBuildView.prototype.setSlotTransitionFailure = function() { this._showStatusNotice('error', '调制仍保持在原装备；可稍后重试切换。'); return true; };
    CharacterBuildView.prototype.refreshSlotNavigation = function() { this._armorRoving.refresh({preferredKey:this._activeSlotKey}); this._weaponRoving.refresh({preferredKey:this._activeSlotKey}); this._drugRoving.refresh({preferredKey:this._activeSlotKey}); return true; };

    CharacterBuildView.prototype.consumeEscape = function() {
        if (this._dollPreview.isOpen()) return this._dollPreview.close('escape');
        if (this._statsPage.isActive()) return this.closeStats('escape');
        if (this._isFocusInSlotQuickBar && this._isFocusInSlotQuickBar() && this._dismissSlotQuickBar(true)) return true;
        return this.clearCandidateSelection() || !!(this._dismissSlotQuickBar && this._dismissSlotQuickBar(true));
    };

    CharacterBuildView.prototype.debugState = function() {
        return {
            mounted:this._mounted,
            density:this._density,
            candidateScope:this._candidateScope,
            candidateScopePending:this._candidateScopePending(),
            selectedSlotKey:this._selectedSlotKey,
            selectedCandidateKey:this._selectedCandidateKey,
            activeSlotKey:this._activeSlotKey,
            activeCandidateKey:this._activeCandidateKey,
            candidateRequestKey:this._candidateRequestKey,
            candidateLoadFailed:this._candidateLoadFailed,
            candidateFailureCode:this._candidateFailureCode,
            candidateRecoveryPending:this._candidateRecoveryPending,
            candidateDrag:{
                active:this._candidateDragActive,
                controller:this._candidateDrag && this._candidateDrag.debugState
                    ? this._candidateDrag.debugState() : null
            },
            candidateCount:this._candidateState.debugState().count,
            candidateState:this._candidateState.debugState(),
            itemUseState:this._itemUseState,
            inboxRemaining:Number(this._inboxSummary
                && this._inboxSummary.remainingCount) || 0,
            statsOpen:this._statsPage.isActive(),
            dollPreviewOpen:this._dollPreview.isOpen(),
            renderModel:this.root.getAttribute('data-render-model')
        };
    };

    CharacterBuildView.prototype.destroy = function() {
        if (this._destroyed) return false;
        if (this._stashClose) this._stashClose();
        this._destroyed = true;
        if (this._candidateDrag) this._candidateDrag.destroy();
        this._candidateDrag = null;
        this._candidateDragBroker = null;
        this._setCandidateDragActive(false);
        if (this._candidateScopeGroup) this._candidateScopeGroup.destroy();
        this._candidateScopeGroup = null;
        this._armorRoving.destroy();
        this._weaponRoving.destroy();
        this._drugRoving.destroy();
        this._candidateRoving.destroy();
        this._actionView.destroy();
        this._candidateState.destroy();
        if (this._loadoutTooltipScope && this._loadoutTooltipScope.dispose) {
            this._loadoutTooltipScope.dispose();
        }
        this._loadoutTooltipScope = null;
        this._dollPreview.destroy();
        this._statsPage.destroy();
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
        this._mounted = false;
        return true;
    };
    LoadoutPresenterModule.install(CharacterBuildView.prototype);
    LoadoutPickerModule.install(CharacterBuildView.prototype, {
        slotGrid:LoadoutPresenterModule.slotGridHooks(),
        pane:{
            syncFocusSummary:function(host, key) {
                return FacetCountsModule.syncFocusSummary(
                    host.root, host._slotFocusSummary, host._facetCounts, key);
            }
        }
    });
    return {
        CharacterBuildView:CharacterBuildView,
        equipmentSlots:ARMOR_SLOTS.concat(WEAPON_SLOTS),
        armorSlots:ARMOR_SLOTS.slice(),
        weaponSlots:WEAPON_SLOTS.slice(),
        drugSlots:DRUG_SLOTS.slice()
    };
});
