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
    var stats = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-stats-view.js')
        : root && root.CharacterBuildStatsView;
    var preview = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-doll-preview.js')
        : root && root.CharacterBuildDollPreview;
    var template = typeof module !== 'undefined' && module.exports
        ? require('./character-build/character-build-template.js')
        : root && root.CharacterBuildTemplate;
    var api = factory(focus, components, actions, stats, preview, template);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.CharacterBuildView = api;
        root.CharacterBuildView = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(WorkbenchFocus, WorkbenchComponents, ActionViewModule, StatsViewModule,
        DollPreviewModule, TemplateModule) {
    'use strict';
    if (!WorkbenchFocus || typeof WorkbenchFocus.RovingGridFocus !== 'function') {
        throw new Error('character-build-view.js requires RovingGridFocus');
    }
    if (!WorkbenchComponents || typeof WorkbenchComponents.SecondaryPage !== 'function') {
        throw new Error('character-build-view.js requires SecondaryPage');
    }
    if (!ActionViewModule || !ActionViewModule.ActionView) {
        throw new Error('character-build-view.js requires CharacterBuildActionView');
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

    var ARMOR_SLOTS = [
        {id:'头部装备', label:'头部'}, {id:'上装装备', label:'上装'},
        {id:'下装装备', label:'下装'}, {id:'手部装备', label:'手部'},
        {id:'脚部装备', label:'脚部'}, {id:'颈部装备', label:'颈部'}
    ];
    var WEAPON_SLOTS = [
        {id:'长枪', label:'长枪'}, {id:'手枪', label:'手枪'},
        {id:'手枪2', label:'手枪 2'}, {id:'刀', label:'刀'},
        {id:'手雷', label:'手雷'}
    ];
    var DRUG_SLOTS = [
        {id:'drug1', label:'药剂 I'}, {id:'drug2', label:'药剂 II'},
        {id:'drug3', label:'药剂 III'}, {id:'drug4', label:'药剂 IV'}
    ];
    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function itemAt(collection, id) {
        return collection && Object.prototype.hasOwnProperty.call(collection, id)
            ? collection[id] : null;
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
        this._candidateSequence = 0;
        this._candidateLoadFailed = false;
        this._candidates = [];
        this._stats = null;
        this._interactionState = 'opening';
        this._lockedFocusKey = '';
        this._createDOM();
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
        var self = this;
        this._actionView = new ActionViewModule.ActionView({
            root:this.root, candidateList:this._candidateList,
            getCandidate:function(key) { return self._candidateByKey(key || self._selectedCandidateKey); },
            getCandidateKey:function() { return self._selectedCandidateKey; },
            getSlotKey:function() { return self._selectedSlotKey; },
            selectCandidate:function(key) { return self._selectCandidate(key); },
            onCommit:typeof options.onCommitCandidate === 'function'
                ? options.onCommitCandidate : function() {},
            onTune:typeof options.onTune === 'function' ? options.onTune : function() {},
            onUnequip:typeof options.onUnequip === 'function' ? options.onUnequip : function() {},
            onReconcile:typeof options.onReconcile === 'function' ? options.onReconcile : function() {}
        });
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
            var candidate = closest(event.target, '[data-roving-key]', self._candidateList);
            if (candidate && self._interactionState === 'idle') self._selectCandidate(candidate.getAttribute('data-roving-key'), 'pointer');
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

    CharacterBuildView.prototype._renderSlotGroup = function(grid, definitions, collection, kind, roving) {
        var activeElement = this._document.activeElement;
        var restoreFocus = !!(activeElement && grid.contains(activeElement));
        var fragment = this._document.createDocumentFragment();
        for (var i = 0; i < definitions.length; i++) {
            var definition = definitions[i];
            var item = itemAt(collection, definition.id);
            var key = kind + ':' + definition.id;
            var slot = this._document.createElement('button');
            slot.type = 'button';
            slot.className = 'character-build-slot';
            slot.setAttribute('role', 'gridcell');
            slot.setAttribute('data-roving-key', key);
            slot.setAttribute('data-slot-id', definition.id);
            slot.setAttribute('data-slot-protocol-key', definition.id);
            slot.setAttribute('data-slot-kind', kind);
            slot.setAttribute('data-empty', item ? 'false' : 'true');
            slot.setAttribute('data-tunable', item && item.tunable === true ? 'true' : 'false');
            if (item && item.tuningReason) {
                slot.setAttribute('data-tuning-reason', text(item.tuningReason));
            }
            slot.setAttribute('data-focus-label', definition.label);
            slot.setAttribute('data-focus-name', item ? item.name : '空槽');
            slot.setAttribute('aria-selected', key === this._selectedSlotKey ? 'true' : 'false');
            if (item && item.blocked) slot.setAttribute('data-blocked', 'true');
            var meta = item ? item.meta || item.type || '已装备' : '点击查看可用候选';
            slot.setAttribute('data-focus-meta', meta);
            var card = this._renderOwnedSlot(definition.label, {
                occupied:!!item,
                physicalSlot:i,
                item:item && item.presentation || {}
            }, {iconHtml:this._iconHtml, allowDiscard:false, tagName:'span'});
            card.classList.add('character-build-slot-card');
            slot.setAttribute('aria-label', card.getAttribute('aria-label'));
            card.setAttribute('aria-hidden', 'true');
            slot.appendChild(card);
            var label = this._document.createElement('span');
            label.className = 'character-build-slot-label';
            label.textContent = definition.label;
            slot.appendChild(label);
            fragment.appendChild(slot);
        }
        grid.innerHTML = '';
        grid.appendChild(fragment);
        roving.refresh({
            preferredKey:this._activeSlotKey.indexOf(kind + ':') === 0 ? this._activeSlotKey : '',
            focus:restoreFocus
        });
        return true;
    };

    CharacterBuildView.prototype._renderCandidates = function(candidates) {
        candidates = Array.isArray(candidates) ? candidates : [];
        var activeElement = this._document.activeElement;
        var restoreFocus = !!(activeElement && this._candidateList.contains(activeElement));
        var fragment = this._document.createDocumentFragment();
        for (var i = 0; i < candidates.length; i++) {
            var candidate = candidates[i] || {};
            var key = text(candidate.key, 'candidate-' + i);
            var button = this._renderOwnedSlot('背包', {
                occupied:true,
                physicalSlot:candidate.physicalSlot == null ? i : candidate.physicalSlot,
                item:candidate.presentation || {}
            }, {iconHtml:this._iconHtml, allowDiscard:false});
            button.classList.add('character-build-candidate');
            button.setAttribute('role', 'option');
            button.setAttribute('data-roving-key', key);
            button.setAttribute('data-candidate-key', key);
            button.setAttribute('aria-selected', key === this._selectedCandidateKey ? 'true' : 'false');
            button.setAttribute('aria-label', button.getAttribute('aria-label') + '，'
                + text(candidate.type, '背包候选') + '，' + text(candidate.summary, '可预览'));
            if (candidate.blocked) {
                button.setAttribute('data-blocked', 'true');
                button.setAttribute('aria-disabled', 'true');
            }
            var delta = this._document.createElement('strong');
            delta.className = 'character-build-candidate-delta';
            delta.setAttribute('data-badge-kind',
                candidate.badgeKind === 'preview' ? 'preview' : 'delta');
            delta.textContent = candidate.delta || '±0';
            button.appendChild(delta);
            fragment.appendChild(button);
        }
        if (!candidates.length) {
            var empty = this._document.createElement('div');
            empty.className = 'character-build-candidate-empty';
            empty.setAttribute('role', 'status');
            empty.textContent = '选择一个装备或药剂槽';
            fragment.appendChild(empty);
        }
        this._candidateList.innerHTML = '';
        this._candidateList.appendChild(fragment);
        this._candidateRoving.refresh({preferredKey:this._activeCandidateKey, focus:restoreFocus});
        this._candidateCount.textContent = candidates.length + ' 项';
        this._syncCandidateSelection();
    };

    CharacterBuildView.prototype._syncCandidateSelection = function() {
        var buttons = this._candidateList.querySelectorAll('[data-candidate-key]');
        for (var i = 0; i < buttons.length; i++) {
            var selected = buttons[i].getAttribute('data-candidate-key') === this._selectedCandidateKey;
            buttons[i].setAttribute('aria-selected', selected ? 'true' : 'false');
            buttons[i].classList.toggle('workbench-source-selected', selected);
        }
        var candidate = this._candidateByKey(this._selectedCandidateKey);
        var overlay = this._overlayCopy.parentNode;
        overlay.hidden = !candidate;
        this._overlayCopy.textContent = candidate
            ? '预览 · ' + text(candidate.name, '候选')
            : '';
        this._actionView.sync();
    };

    CharacterBuildView.prototype._candidateByKey = function(key) {
        if (!this._selectedSlotKey) return null;
        var candidates = this._candidates;
        for (var i = 0; i < candidates.length; i++) {
            if (text(candidates[i] && candidates[i].key, 'candidate-' + i) === key) return candidates[i];
        }
        return null;
    };

    CharacterBuildView.prototype._syncSlotSelection = function() {
        var slots = this.root.querySelectorAll('.character-build-slot');
        for (var i = 0; i < slots.length; i++) {
            var selected = slots[i].getAttribute('data-roving-key') === this._selectedSlotKey;
            slots[i].setAttribute('aria-selected', selected ? 'true' : 'false');
            var card = slots[i].querySelector('.character-build-slot-card');
            if (card) {
                card.classList.toggle('workbench-source-selected', selected);
            }
        }
        this._actionView.sync();
    };

    CharacterBuildView.prototype.setInteractionState = function(state) {
        state = String(state || 'opening');
        var previous = this._interactionState;
        var active = closest(this._document.activeElement, '[data-roving-key]', this.root);
        if (previous === 'idle' && state !== 'idle') {
            this._lockedFocusKey = active ? active.getAttribute('data-roving-key') : '';
        }
        this._interactionState = state;
        this._actionView.setState(state);
        this.root.setAttribute('aria-busy',
            state !== 'idle' && state !== 'flush_failed' ? 'true' : 'false');
        this._armorRoving.refresh({preferredKey:this._activeSlotKey});
        this._weaponRoving.refresh({preferredKey:this._activeSlotKey});
        this._drugRoving.refresh({preferredKey:this._activeSlotKey});
        this._candidateRoving.refresh({preferredKey:this._activeCandidateKey});
        if (state === 'write_pending') {
            this._showStatusNotice(
                'write',
                '正在写入构筑；槽位、候选与页面切换暂时锁定。');
        } else if (state === 'mutation_reconcile') {
            this._showStatusNotice(
                'reconcile',
                '写入结果未知；仅可重新确认结果，不会重复提交。');
        } else if (state === 'idle' && previous !== 'idle') {
            var node = this._lockedFocusKey && this.root.querySelector(
                '[data-roving-key="' + this._lockedFocusKey.replace(/"/g, '\\"') + '"]');
            this._lockedFocusKey = '';
            this._showBrowsingNotice('交互已恢复；可继续选择槽位或候选。');
            if (node && !node.disabled) {
                try { node.focus({preventScroll:true}); } catch (_) { node.focus(); }
            }
        }
        return true;
    };
    CharacterBuildView.prototype._focusSlot = function(key) {
        if (!key) return false;
        this._activeSlotKey = String(key);
        var node = this.root.querySelector('[data-roving-key="' + this._activeSlotKey.replace(/"/g, '\\"') + '"]');
        this._slotFocusSummary.textContent = node
            ? '浏览：' + node.getAttribute('data-focus-label') + ' · '
                + node.getAttribute('data-focus-name') + ' · Enter 选择'
            : '浏览：尚未选择槽位';
        this._slotFocusSummary.title = node
            ? node.getAttribute('data-focus-label') + ' · '
                + node.getAttribute('data-focus-name') + ' · '
                + node.getAttribute('data-focus-meta')
            : '';
        return true;
    };

    CharacterBuildView.prototype._focusCandidate = function(key) {
        if (!key) return false;
        this._activeCandidateKey = String(key);
        var candidate = this._candidateByKey(this._activeCandidateKey);
        this._candidateFocusSummary.textContent = candidate
            ? '浏览：' + text(candidate.name, '未命名候选') + ' · '
                + text(candidate.summary, 'Enter 或 Space 固定预览；仅再次按 Enter 才提交。')
            : '方向键只浏览摘要；Enter 或 Space 固定预览，仅再次按 Enter 才提交。';
        this._candidateFocusSummary.title = this._candidateFocusSummary.textContent;
        return true;
    };

    CharacterBuildView.prototype._selectSlot = function(key) {
        if (!key) return false;
        var nextKey = String(key);
        var changed = this._selectedSlotKey !== nextKey;
        var previous = {
            selectedSlotKey:this._selectedSlotKey,
            selectedCandidateKey:this._selectedCandidateKey,
            activeCandidateKey:this._activeCandidateKey,
            candidateRequestKey:this._candidateRequestKey,
            candidateLoadFailed:this._candidateLoadFailed,
            candidates:this._candidates.slice()
        };
        var previousCandidate = this._candidateByKey(previous.selectedCandidateKey);
        this._selectedSlotKey = nextKey;
        this._syncSlotSelection();
        if (changed || this._candidateLoadFailed) {
            this.clearCandidateSelection();
            this._activeCandidateKey = '';
            this._candidates = [];
            this._candidateLoadFailed = false;
            this._candidateRequestKey = this._selectedSlotKey + ':' + (++this._candidateSequence);
            this._renderCandidates([]);
            this._showBrowsingNotice('正在读取当前槽位的背包候选…');
            var parts = this._selectedSlotKey.split(':');
            var selection = {
                key:this._selectedSlotKey,
                kind:parts.shift(),
                id:parts.join(':'),
                requestKey:this._candidateRequestKey
            };
            var result = this._onSlotSelect(selection), deferredSelection = result && result.deferSelection === true;
            if (result === false || result == null || deferredSelection) {
                this._selectedSlotKey = previous.selectedSlotKey;
                this._selectedCandidateKey = previous.selectedCandidateKey;
                this._activeCandidateKey = previous.activeCandidateKey;
                this._candidateRequestKey = previous.candidateRequestKey;
                this._candidateLoadFailed = previous.candidateLoadFailed;
                this._candidates = previous.candidates;
                this._renderCandidates(this._candidates);
                this._syncSlotSelection();
                if (previousCandidate) {
                    this._onCandidateSelect(previousCandidate, {
                        slotKey:previous.selectedSlotKey,
                        requestKey:previous.candidateRequestKey
                    });
                }
                this._showStatusNotice(
                    deferredSelection ? 'pending' : 'error',
                    deferredSelection ? '正在退出当前调制；完成后将打开目标槽位。' : '槽位切换未完成；当前选择与候选保持不变。');
                return deferredSelection;
            }
            if (result && result.deferCandidates === true) {
                this._candidateLoadFailed = true;
                this._showBrowsingNotice(
                    '已切换调制目标；返回候选后将读取当前槽位。');
            }
            if (Array.isArray(result)) this.setCandidates(selection.requestKey, result);
        }
        return true;
    };

    CharacterBuildView.prototype._selectCandidate = function(key) {
        if (!key || this._interactionState !== 'idle') return false;
        var candidate = this._candidateByKey(key);
        if (!candidate || candidate.blocked === true) return false;
        this._selectedCandidateKey = String(key);
        this._syncCandidateSelection();
        this._onCandidateSelect(candidate, {
            slotKey:this._selectedSlotKey,
            requestKey:this._candidateRequestKey
        });
        return true;
    };

    CharacterBuildView.prototype.clearCandidateSelection = function() {
        if (!this._selectedCandidateKey) return false;
        this._selectedCandidateKey = '';
        this._syncCandidateSelection();
        this._onCandidateSelect(null, {
            slotKey:this._selectedSlotKey,
            requestKey:this._candidateRequestKey
        });
        this._showBrowsingNotice('候选预览已清除，当前装备保持不变。');
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
        this._snapshot = snapshot || {};
        if (this.root.getAttribute('data-build-subview') !== 'tuning') this._selectedSlotKey = '';
        this._selectedCandidateKey = '';
        this._candidateRequestKey = '';
        this._candidateLoadFailed = this.root.getAttribute('data-build-subview') === 'tuning';
        this._candidates = [];
        this.root.setAttribute('data-build-state', this._snapshot.blocked ? 'blocked' : 'ready');
        this._renderSlotGroup(
            this._armorGrid, ARMOR_SLOTS, this._snapshot.equipment, 'armor', this._armorRoving);
        this._renderSlotGroup(
            this._weaponGrid, WEAPON_SLOTS, this._snapshot.equipment, 'weapon', this._weaponRoving);
        this._renderSlotGroup(
            this._drugGrid, DRUG_SLOTS, this._snapshot.drugs, 'drug', this._drugRoving);
        this._renderCandidates([]);
        this._notice.textContent = this._snapshot.blocked
            ? text(this._snapshot.blockedReason, '当前候选不满足权威条件。')
            : '选择槽位与候选可查看临时预览，当前装备保持不变。';
        this._notice.setAttribute('data-notice-kind', this._snapshot.blocked ? 'blocked' : 'browsing');
        this._syncSlotSelection();
        this._syncCandidateSelection();
        return true;
    };

    CharacterBuildView.prototype.setCandidates = function(requestKey, candidates) {
        if (this._destroyed || !requestKey || requestKey !== this._candidateRequestKey
                || !this._selectedSlotKey) return false;
        this._candidates = Array.isArray(candidates) ? candidates.slice() : [];
        this._candidateLoadFailed = false;
        this._selectedCandidateKey = '';
        this._activeCandidateKey = '';
        this._renderCandidates(this._candidates);
        if (this._snapshot && this._snapshot.blocked) {
            this._notice.textContent = text(
                this._snapshot.blockedReason, '部分角色数据不可用；请检查候选阻断原因。');
            this._notice.setAttribute('data-notice-kind', 'blocked');
        } else {
            this._showBrowsingNotice(this._candidates.length
                ? '已读取当前槽位候选；选择候选只会更新临时预览。'
                : '当前背包没有可用于该槽位的候选。');
        }
        return true;
    };

    CharacterBuildView.prototype.setCandidateFailure = function(requestKey) {
        if (this._destroyed || !requestKey || requestKey !== this._candidateRequestKey
                || !this._selectedSlotKey) return false;
        this._candidateLoadFailed = true;
        this._candidates = [];
        this._renderCandidates([]);
        this._showStatusNotice('error', '候选读取失败；再次选择当前槽位即可重试。');
        return true;
    };

    CharacterBuildView.prototype.restoreSlot = function(key) {
        if (this._destroyed || !key) return false;
        var node = this.root.querySelector('[data-roving-key="' + String(key).replace(/"/g, '\\"') + '"]');
        if (!node) return false;
        this._activeSlotKey = String(key);
        this._candidateList.parentNode.scrollTop = 0;
        this._selectSlot(this._activeSlotKey);
        try { node.focus({preventScroll:true}); } catch (_) { node.focus(); }
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
            selectedSlotKey:this._selectedSlotKey,
            selectedCandidateKey:this._selectedCandidateKey,
            activeSlotKey:this._activeSlotKey,
            activeCandidateKey:this._activeCandidateKey,
            candidateRequestKey:this._candidateRequestKey,
            candidateLoadFailed:this._candidateLoadFailed,
            candidateCount:this._candidates.length,
            statsOpen:this._statsPage.isActive(),
            dollPreviewOpen:this._dollPreview.isOpen(),
            renderModel:this.root.getAttribute('data-render-model')
        };
    };

    CharacterBuildView.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._armorRoving.destroy();
        this._weaponRoving.destroy();
        this._drugRoving.destroy();
        this._candidateRoving.destroy();
        this._actionView.destroy();
        this._dollPreview.destroy();
        this._statsPage.destroy();
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
        this._mounted = false;
        return true;
    };

    return {
        CharacterBuildView:CharacterBuildView,
        equipmentSlots:ARMOR_SLOTS.concat(WEAPON_SLOTS),
        armorSlots:ARMOR_SLOTS.slice(),
        weaponSlots:WEAPON_SLOTS.slice(),
        drugSlots:DRUG_SLOTS.slice()
    };
});
