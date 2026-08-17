/* Character-build DOM/focus/presentation; transport and writes stay outside. */
(function(root, factory) {
    'use strict';
    var focus = typeof module !== 'undefined' && module.exports
        ? require('./workbench-focus.js')
        : root && (root.WorkbenchFocus || root.CF7 && root.CF7.WorkbenchFocus);
    var components = typeof module !== 'undefined' && module.exports
        ? require('./workbench-components.js')
        : root && (root.WorkbenchComponents || root.CF7 && root.CF7.WorkbenchComponents);
    var actions = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-action-view.js')
        : root && root.CharacterBuildActionView;
    var candidateState = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-candidate-state.js')
        : root && root.CharacterBuildCandidateState;
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
    var candidatePane = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-candidate-pane.js')
        : root && root.CharacterBuildCandidatePane;
    var candidateDrag = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-candidate-drag.js')
        : root && root.CharacterBuildCandidateDrag;
    var api = factory(
        focus, components, actions, candidateState, facetCounts,
        stats, preview, template, loadoutPresenter, candidatePane, candidateDrag);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildView = api;
        root.CharacterBuildView = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchFocus, WorkbenchComponents, ActionViewModule, CandidateStateModule,
        FacetCountsModule, StatsViewModule, DollPreviewModule, TemplateModule,
        LoadoutPresenterModule, CandidatePaneModule, CandidateDragModule) {
    'use strict';
    if (!WorkbenchFocus || typeof WorkbenchFocus.RovingGridFocus !== 'function') {
        throw new Error('character-build-view.js requires RovingGridFocus');
    }
    if (!WorkbenchComponents
            || typeof WorkbenchComponents.SecondaryPage !== 'function'
            || typeof WorkbenchComponents.ChoiceGroup !== 'function') {
        throw new Error('character-build-view.js requires SecondaryPage and ChoiceGroup');
    }
    if (!ActionViewModule || !ActionViewModule.ActionView) {
        throw new Error('character-build-view.js requires CharacterBuildActionView');
    }
    if (!CandidateStateModule || !CandidateStateModule.CandidateState) {
        throw new Error('character-build-view.js requires CharacterBuildCandidateState');
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
    if (!CandidatePaneModule || typeof CandidatePaneModule.install !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildCandidatePane');
    }
    if (!CandidateDragModule || typeof CandidateDragModule.install !== 'function') {
        throw new Error('character-build-view.js requires CharacterBuildCandidateDrag');
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
    function listen(records, target, type, handler) {
        target.addEventListener(type, handler);
        records.push(function() { target.removeEventListener(type, handler); });
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
        this._statsReturnFocus = null;
        this._selectedSlotKey = '';
        this._selectedCandidateKey = '';
        this._activeSlotKey = '';
        this._activeCandidateKey = '';
        this._candidateRequestKey = '';
        this._candidateScope = CandidatePaneModule.normalizeScope(
            options.candidateScope) || 'backpack';
        this._candidateScopeGroup = null;
        var viewSequence = ++candidateViewSequence;
        this._candidateFence = 'candidate-view-' + viewSequence;
        this._candidateSequence = 0;
        this._candidateLoadFailed = false;
        this._candidateFailureCode = '';
        this._candidateRecoveryPending = false;
        this._candidateDrag = null;
        this._candidateDragBroker = null;
        this._candidateDragActive = false;
        this._dragCandidate = null;
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
        this._interactionState = 'opening';
        this._lockedFocusKey = '';
        this._createDOM();
        this._candidateScopeGroup = new WorkbenchComponents.ChoiceGroup({
            document:this._document,
            value:this._candidateScope,
            ariaLabel:'背包候选范围',
            className:'character-build-candidate-scope',
            choices:[
                {value:'compatible', label:'兼容',
                    ariaLabel:'只显示与当前槽位兼容的背包候选'},
                {value:'backpack', label:'背包',
                    ariaLabel:'显示背包全部物品'}
            ],
            onChange:function(scope) { return self._changeCandidateScope(scope); }
        });
        this._candidateScopeGroup.mount(this._candidateScopeMount);
        this.setDensity(this._density);
        this._statsView = new StatsViewModule.StatsView({
            host:this._statsGrid,
            scroll:this._statsScroll,
            hint:this._statsScrollHint,
            copy:this._statsScrollCopy,
            glyph:this._statsScrollGlyph
        });
        this._createFocusControllers();
        this._bindInteractions();
        this._actionView = new ActionViewModule.ActionView({
            root:this.root, candidateList:this._candidateList, overlayCopy:this._overlayCopy,
            getCandidate:function(key) { return self._candidateByKey(key || self._selectedCandidateKey); },
            getCandidateKey:function() { return self._selectedCandidateKey; },
            getSlotKey:function() { return self._selectedSlotKey; },
            selectCandidate:function(key) { return self._selectCandidate(key); },
            clearCandidateSelection:function() { return self.clearCandidateSelection(); },
            onCommit:this._onCommitCandidate,
            onTune:typeof options.onTune === 'function' ? options.onTune : function() {},
            onUnequip:typeof options.onUnequip === 'function' ? options.onUnequip : function() {},
            onReconcile:typeof options.onReconcile === 'function' ? options.onReconcile : function() {}
        });
        this._candidateState = new CandidateStateModule.CandidateState({
            document:this._document,
            host:this._candidateList,
            countNode:this._candidateCount,
            renderOwnedSlot:this._renderOwnedSlot,
            iconHtml:this._iconHtml,
            bindTooltip:function(node, candidate) {
                return typeof options.bindCandidateTooltip === 'function'
                    ? options.bindCandidateTooltip(node, candidate, function() {
                        return self._candidateDragActive;
                    }) : null;
            },
            onBlocked:function(candidate, context) {
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
        this._notice = root.querySelector('[data-build-notice]');
        this._notice.setAttribute('role', 'status');
        this._notice.setAttribute('aria-live', 'polite');
        this._slotFocusSummary = root.querySelector('[data-focus-summary]');
        this._candidateList = root.querySelector('[data-candidate-list]');
        this._candidateCount = root.querySelector('[data-candidate-count]');
        this._candidateScopeMount = root.querySelector('[data-build-candidate-scope-mount]');
        this._candidateFocusSummary = root.querySelector('[data-candidate-focus-summary]');
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
        this._candidateRoving = new WorkbenchFocus.RovingGridFocus({
            root:this._candidateList,
            columns:function() { return self._document.defaultView.getComputedStyle(self._candidateList).gridTemplateColumns.split(/\s+/).length; },
            onActiveChange:function(key) { self._focusCandidate(key); }
        });
    };

    CharacterBuildView.prototype._bindInteractions = function() {
        var self = this;
        listen(this._listeners, this._armorGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._armorGrid);
            if (slot) self._selectSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._weaponGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._weaponGrid);
            if (slot) self._selectSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._drugGrid, 'click', function(event) {
            var slot = closest(event.target, '[data-roving-key]', self._drugGrid);
            if (slot) self._selectSlot(slot.getAttribute('data-roving-key'), 'click');
        });
        listen(this._listeners, this._candidateList, 'click', function(event) {
            if (self._candidateDrag && self._candidateDrag.consumeClick()) {
                if (event.preventDefault) event.preventDefault();
                if (event.stopPropagation) event.stopPropagation();
                return;
            }
            var candidate = closest(event.target, '[data-roving-key]', self._candidateList);
            if (!candidate || self._interactionState !== 'idle') return;
            var key = candidate.getAttribute('data-roving-key');
            if (key === self._selectedCandidateKey) self.clearCandidateSelection();
            else self._selectCandidate(key, 'pointer');
        });
        // 双击 = 选中并直接提交。双击前的两次 click 会选中再清预览，
        // 这里按事件目标强制重选后提交，不依赖当前选择态。
        listen(this._listeners, this._candidateList, 'dblclick', function(event) {
            var node = closest(event.target, '[data-candidate-key]', self._candidateList);
            if (!node || self._interactionState !== 'idle') return;
            var candidate = self._candidateByKey(node.getAttribute('data-candidate-key'));
            if (!candidate || candidate.blocked === true) return;
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
        listen(this._listeners, this.root, 'keydown', function(event) {
            if (!event || (event.key !== 'Escape' && event.key !== 'Esc')
                    || self._statsPage.isActive()) return;
            if (self._selectedCandidateKey) {
                event.preventDefault();
                if (event.stopPropagation) event.stopPropagation();
                self.clearCandidateSelection();
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
        this._notice.textContent = message;
        this._notice.setAttribute('data-notice-kind', kind || 'error');
    };

    CharacterBuildView.prototype._showBrowsingNotice = function(message) {
        this._notice.textContent = message;
        this._notice.setAttribute('data-notice-kind', 'browsing');
    };

    CharacterBuildView.prototype.setSnapshot = function(snapshot) {
        if (this._destroyed) return false;
        this._loadoutTooltipEpoch++;
        this._loadoutTooltipCache = {};
        this._snapshot = snapshot || {};
        this._facetCounts =
            FacetCountsModule.normalize(this._snapshot.candidateFacets);
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
        this._renderSlotGroup(
            this._drugGrid, DRUG_SLOTS, this._snapshot.drugs, 'drug', this._drugRoving);
        this._focusSlot(this._activeSlotKey);
        this._setCandidateState('unselected', [], '');
        this._notice.textContent = this._snapshot.blocked
            ? text(this._snapshot.blockedReason, '当前候选不满足权威条件。')
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
    CharacterBuildView.prototype.setSlotTransitionFailure = function() { this._showStatusNotice('error', '调制仍保持在原装备；可稍后重试切换。'); return true; };
    CharacterBuildView.prototype.refreshSlotNavigation = function() { this._armorRoving.refresh({preferredKey:this._activeSlotKey}); this._weaponRoving.refresh({preferredKey:this._activeSlotKey}); this._drugRoving.refresh({preferredKey:this._activeSlotKey}); return true; };

    CharacterBuildView.prototype.consumeEscape = function() {
        if (this._dollPreview.isOpen()) return this._dollPreview.close('escape');
        if (this._statsPage.isActive()) return this.closeStats('escape');
        return this.clearCandidateSelection();
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
            statsOpen:this._statsPage.isActive(),
            dollPreviewOpen:this._dollPreview.isOpen(),
            renderModel:this.root.getAttribute('data-render-model')
        };
    };

    CharacterBuildView.prototype.destroy = function() {
        if (this._destroyed) return false;
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
    CandidateDragModule.install(CharacterBuildView.prototype);
    CandidatePaneModule.install(CharacterBuildView.prototype);
    return {
        CharacterBuildView:CharacterBuildView,
        equipmentSlots:ARMOR_SLOTS.concat(WEAPON_SLOTS),
        armorSlots:ARMOR_SLOTS.slice(),
        weaponSlots:WEAPON_SLOTS.slice(),
        drugSlots:DRUG_SLOTS.slice()
    };
});
