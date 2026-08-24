/**
 * Merc loadout picker view （设计 §5）：佣兵装备托管的 LoadoutPicker 消费者。
 *
 * 组合根职责：槽位图标网格（护具 6..11 / 武装 12..15 两组 3 列紧凑网格；手雷 16
 * 只读行由宿主注入、不进 picker 网格）+ 常驻候选栏（五态、兼容/背包 scope、
 * 独立滚动区）+ 拖拽接线 + 动作条（交付/替换/取回方言）。协议、会话、revision、
 * 写闸门、对账锁全部留在 merc-panel.js；本层只做「浏览-选择-拖拽-五态-回滚」
 * 交互编排，经 ports 回调宿主。
 *
 * 宿主注入（createView options）：
 * - policy                 MercLoadoutDropPolicy.create() 产物（eligibleSlots 白名单裁决）
 * - badgeOf(state)         三态徽章 DOM（TeamShared.buildCustodyBadge）
 * - slotNameOf(id)         槽位中文名（MercData.SLOT_NAMES）
 * - operateReasonOf(merc)  canOperate/combatLocked/出战/阵亡/对账锁 → 可读原因（'' 可操作）
 * - iconHtml(name, cls)    图标渲染（Icons.html 包装）
 * - releaseGrid(grid)      槽位网格重建前释放 tooltip 绑定
 * - bindSlotTooltip(slot, presentation, slotId)         槽位 loadout_tooltip 挂接
 * - bindCandidateTooltip(node, candidate, isSuppressed) 候选 loadout_tooltip 挂接（lease-bound source）
 * - renderGrenade(mount, merc)                          手雷只读行渲染（宿主全权）
 * - onSlotSelect(selection) / onCandidateScopeChange(scope, selection)
 *   → 候选读取通道；返回 callId（异步，迟到回包经 requestKey 栅栏不复活）、
 *     数组（同步命中）或 false（准入门拒 → picker 乐观切换回滚）
 * - onCandidateSelect(candidate|null)  纸娃娃预览联动（宿主经 MercPortraits 临时并入渲染态）
 * - onCommit(candidate, slotKey) / onSlotDropEquip(slotKey, candidate)  提交（交付/替换由宿主按槽位态解析）
 * - onWithdraw(slotId, btn)            取回（直接 loadout_withdraw，不走候选）
 * - overlayHost                        预览 overlay 挂载点（培养页纸娃娃视口）
 */
(function(root, factory) {
    'use strict';
    var picker = typeof module !== 'undefined' && module.exports
        ? require('../loadout-picker/loadout-picker.js')
        : root && root.LoadoutPicker;
    var components = typeof module !== 'undefined' && module.exports
        ? require('../workbench-components.js')
        : root && (root.WorkbenchComponents || root.CF7 && root.CF7.WorkbenchComponents);
    var focus = typeof module !== 'undefined' && module.exports
        ? require('../workbench-focus.js')
        : root && root.WorkbenchFocus;
    var policy = typeof module !== 'undefined' && module.exports
        ? require('./merc-loadout-drop-policy.js')
        : root && root.MercLoadoutDropPolicy;
    var api = factory(picker, components, focus, policy);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) {
        root.CF7 = root.CF7 || {};
        root.CF7.MercLoadoutPicker = api;
        root.MercLoadoutPicker = api;
    }
})(typeof window !== 'undefined' ? window : globalThis,
function(LoadoutPickerModule, WorkbenchComponents, WorkbenchFocus, DropPolicyModule) {
    'use strict';
    if (!LoadoutPickerModule || typeof LoadoutPickerModule.install !== 'function'
            || typeof LoadoutPickerModule.initState !== 'function') {
        throw new Error('merc-loadout-picker.js requires LoadoutPicker');
    }
    if (!WorkbenchComponents || typeof WorkbenchComponents.ChoiceGroup !== 'function') {
        throw new Error('merc-loadout-picker.js requires ChoiceGroup');
    }
    if (!WorkbenchFocus || typeof WorkbenchFocus.RovingGridFocus !== 'function') {
        throw new Error('merc-loadout-picker.js requires RovingGridFocus');
    }
    if (!DropPolicyModule || typeof DropPolicyModule.create !== 'function') {
        throw new Error('merc-loadout-picker.js requires MercLoadoutDropPolicy');
    }

    var ARMOR_IDS = ['6', '7', '8', '9', '10', '11'];
    var WEAPON_IDS = ['12', '13', '14', '15'];
    var CORRUPT_REASON = '托管快照异常，已失败关闭；请保留存档并反馈';
    var NO_CUSTODY_REASON = '该槽位没有托管装备，无可取回';
    var POLICY = DropPolicyModule.create();
    var viewSequence = 0;

    var PANE_TEXTS = {
        scopeBackpackReading:'正在读取背包总览；可把装备拖到高亮的兼容槽位…',
        scopeCompatibleReading:'正在读取与当前槽位兼容的可交付候选…',
        writePending:'正在写入托管装备；槽位、候选与操作暂时锁定。',
        focusBlockedSuffix:' · 不可交付 · 点击查看原因',
        focusOverviewSelected:'已选择 · 拖到高亮槽位 / Space 取消',
        focusOverviewUnselected:'Enter 选择 · 可拖到高亮槽位',
        focusPinnedSelected:'已固定预览 · Enter 提交 / Space 取消',
        focusPinnedUnselected:'Enter 固定预览 · 双击直接提交',
        focusOverviewIdle:'背包总览 · 拖到高亮槽位，或选择槽位进入兼容筛选',
        focusCompatibleIdle:'单击预览 · 双击直接提交 · 可拖到高亮槽位',
        slotReading:'正在读取当前槽位的可交付候选…',
        blockedFallback:'此装备当前不可交付。',
        readyBackpack:'背包总览已就绪；可拖到高亮槽位，选择槽位则进入兼容筛选。',
        readyCompatible:'已读取当前槽位候选；选择候选只会更新临时预览。',
        emptyBackpack:'当前背包没有可交付的装备。',
        emptyCompatible:'当前背包没有可用于该槽位的候选。'
    };
    var STATE_COPY = {
        unselected:{ statement:'先选择槽位', nextStep:'从左侧护具或武装区选择一个槽位；手雷为消耗品，不参与托管。' },
        loading:{ statement:'正在查找可交付装备', nextStep:'请稍候；读取完成前不会提交旧候选。' },
        empty:{ statement:'此槽位暂无可用候选', nextStep:'可切换到「背包」总览，查看全部装备与锁定原因。' },
        error:{ statement:'暂时无法读取候选', nextStep:'检查连接后重试；重试只读取当前槽位，不会改动装备。' },
        ready:{ statement:'候选与数量已同步', nextStep:'单击预览纸娃娃；双击、拖拽或主按钮才会提交。' }
    };
    var STATE_TEXTS = {
        blockedReasonFallback:'此装备当前不可交付；当前装备保持不变。',
        retryLabel:'重试当前槽位',
        retryAriaLabel:'重新读取当前槽位候选',
        backpackLabel:'背包',
        candidateTypeFallback:'装备候选',
        candidateSummaryFallback:'可预览',
        hostReadyLabelPrefix:'装备候选。'
    };
    var ACTION_TEXTS = {
        commitNoSlot:'先选择槽位',
        commitNoSlotAria:'先选择目标槽位',
        commitEquip:'确认交付',
        commitEquipAria:'交付所选候选到当前槽位',
        overlayPreviewPrefix:'预览 · ',
        overlaySelectedPrefix:'已选 · ',
        overlayNameFallback:'候选',
        unnamedCandidate:'未命名候选'
    };

    function text(value, fallback) {
        return String(value == null || value === '' ? fallback || '' : value);
    }
    function escapeHtml(value) {
        return String(value == null ? '' : value)
            .replace(/&/g, '&amp;').replace(/</g, '&lt;')
            .replace(/>/g, '&gt;').replace(/"/g, '&quot;');
    }
    function closest(target, selector, boundary) {
        if (!target || typeof target.closest !== 'function') return null;
        var result = target.closest(selector);
        return result && boundary.contains(result) ? result : null;
    }
    function listen(records, target, type, handler) {
        target.addEventListener(type, handler);
        records.push(function() { target.removeEventListener(type, handler); });
    }
    function defaultIconHtml(name, className) {
        var icons = typeof Icons !== 'undefined' ? Icons : null;
        var html = icons && typeof icons.html === 'function' ? icons.html(name, className) : '';
        return html || '<span class="' + (className || 'inventory-owned-icon')
            + ' inventory-icon-fallback" aria-hidden="true">◇</span>';
    }

    /* 培养页装备区自有的轻量 owned-card 渲染（team 闭包不加载 inventory-ui.js）；
     * 类名沿用 inventory-owned 体系，由 panels.css 的 inventory.css 段落投影。 */
    function renderCard(doc, iconHtml, label, slot, options) {
        options = options || {};
        var node = doc.createElement(options.tagName === 'span' ? 'span' : 'article');
        node.className = 'item-card item-card-owned inventory-slot-card '
            + (slot.occupied ? 'occupied' : 'empty');
        node.setAttribute('data-container-id', label);
        node.setAttribute('data-physical-slot', slot.physicalSlot);
        if (!slot.occupied) {
            node.setAttribute('aria-label', label + ' 空槽');
            return node;
        }
        var item = slot.item || {};
        var enhancement = Number(item.enhancementLevel) || 0;
        node.classList.add('equipment');
        node.setAttribute('aria-label', label + '：' + text(item.displayName, '未知装备')
            + (enhancement > 0 ? '，强化等级 ' + enhancement : ''));
        var icon = typeof iconHtml === 'function'
            ? iconHtml(item.icon || '', 'inventory-owned-icon') : '';
        node.innerHTML = '<span class="item-card-icon inventory-slot-icon-frame">'
            + '<span class="inventory-slot-icon">' + icon + '</span>'
            + (enhancement > 0
                ? '<span class="inventory-slot-value level" aria-label="强化等级 '
                    + enhancement + '">' + enhancement + '</span>' : '')
            + '</span>'
            + '<span class="item-card-body inventory-slot-copy"><b>'
            + escapeHtml(text(item.displayName, '未知装备')) + '</b>'
            + (item.metaLine
                ? '<span class="merc-loadout-card-meta">' + escapeHtml(item.metaLine) + '</span>' : '')
            + '</span>';
        return node;
    }

    function MercLoadoutPickerView(options) {
        options = options || {};
        var self = this;
        this._document = options.document || (typeof document !== 'undefined' ? document : null);
        if (!this._document) throw new Error('MercLoadoutPickerView requires a document');
        this._badgeOf = typeof options.badgeOf === 'function' ? options.badgeOf : function() { return null; };
        this._slotNameOf = typeof options.slotNameOf === 'function'
            ? options.slotNameOf : function(id) { return String(id); };
        this._operateReasonOf = typeof options.operateReasonOf === 'function'
            ? options.operateReasonOf : function() { return ''; };
        this._iconHtml = typeof options.iconHtml === 'function' ? options.iconHtml : defaultIconHtml;
        this._releaseGridCb = typeof options.releaseGrid === 'function' ? options.releaseGrid : function() {};
        this._bindSlotTipCb = typeof options.bindSlotTooltip === 'function'
            ? options.bindSlotTooltip : function() {};
        this._bindCandidateTipCb = typeof options.bindCandidateTooltip === 'function'
            ? options.bindCandidateTooltip : null;
        this._renderGrenadeCb = typeof options.renderGrenade === 'function'
            ? options.renderGrenade : function() {};
        this._loadoutAuthorityKey = '';
        this._onSlotSelectCb = typeof options.onSlotSelect === 'function'
            ? options.onSlotSelect : function() { return false; };
        this._onScopeChangeCb = typeof options.onCandidateScopeChange === 'function'
            ? options.onCandidateScopeChange : function() { return false; };
        this._onCandidateSelectCb = typeof options.onCandidateSelect === 'function'
            ? options.onCandidateSelect : function() {};
        this._onCommitCb = typeof options.onCommit === 'function' ? options.onCommit : function() {};
        this._onDropEquipCb = typeof options.onSlotDropEquip === 'function'
            ? options.onSlotDropEquip : function() { return false; };
        this._onWithdrawCb = typeof options.onWithdraw === 'function' ? options.onWithdraw : function() {};
        this._renderOwnedSlot = function(label, slot, opts) {
            return renderCard(self._document, self._iconHtml, label, slot, opts);
        };
        this._tooltip = null;
        this._merc = null;
        this._loadoutSlots = {};
        this._operateReason = '';
        this._writePending = false;
        this._destroyed = false;
        this._listeners = [];
        this._armorDefs = defsOf(this, ARMOR_IDS);
        this._weaponDefs = defsOf(this, WEAPON_IDS);
        LoadoutPickerModule.initState(this, { viewSequence: ++viewSequence });
        this._createDOM(options.overlayHost || null);
        LoadoutPickerModule.createScopeGroup(this, { classPrefix: 'merc-loadout' });
        this._createFocusControllers();
        this._bindInteractions();
        LoadoutPickerModule.createActionView(this, {
            onCommit: function(candidate) { self._commitSelected(candidate); },
            onUnequip: function() { self._withdrawSelected(); },
            texts: ACTION_TEXTS
        });
        this._wrapActionViewSync();
        LoadoutPickerModule.createCandidateState(this, {
            bindTooltip: function(node, candidate) {
                return self._bindCandidateTipCb
                    ? self._bindCandidateTipCb(node, candidate, function() {
                        return self._candidateDragActive;
                    }) : null;
            },
            onBlocked: function(candidate, context) {
                return self._explainBlockedCandidate(candidate, context);
            },
            onRetry: function(requestKey) { return self._retryCandidates(requestKey); },
            copy: STATE_COPY,
            texts: STATE_TEXTS,
            classPrefix: 'merc-loadout'
        });
        this._installCandidateDrag();
        this._setCandidateState('unselected', [], '');
        // 直接投影 idle（不走 setInteractionState 的迁移通知，避免首开噪声）
        this._interactionState = 'idle';
        this._actionView.setState('idle');
        this.root.setAttribute('aria-busy', 'false');
    }

    function defsOf(view, ids) {
        var defs = [];
        for (var i = 0; i < ids.length; i++) {
            defs.push({ id: ids[i], label: view._slotNameOf(ids[i]) });
        }
        return defs;
    }

    MercLoadoutPickerView.prototype._createDOM = function(overlayHost) {
        var root = this.root = this._document.createElement('section');
        root.className = 'merc-loadout-picker';
        root.setAttribute('role', 'region');
        root.setAttribute('aria-label', '佣兵装备托管');
        root.setAttribute('data-render-model', 'slot-grid-candidate-pane');
        root.innerHTML = ''
            + '<div class="merc-loadout-columns">'
            + '  <div class="merc-loadout-slot-col">'
            + '    <div class="merc-loadout-slot-focus-summary" data-merc-slot-focus-summary>浏览：尚未选择槽位</div>'
            + '    <section class="merc-loadout-slot-section"><h3>护具</h3>'
            + '      <div class="merc-loadout-slot-grid item-grid-compact" data-merc-armor-grid role="grid" aria-label="六格护具栏"></div></section>'
            + '    <section class="merc-loadout-slot-section"><h3>武装</h3>'
            + '      <div class="merc-loadout-slot-grid item-grid-compact" data-merc-weapon-grid role="grid" aria-label="四格武装栏"></div></section>'
            + '    <div class="merc-loadout-grenade-row" data-merc-grenade-mount></div>'
            + '  </div>'
            + '  <aside class="merc-loadout-candidate-pane">'
            + '    <header class="merc-loadout-candidate-head">'
            + '      <div class="merc-loadout-candidate-heading-copy"><span>背包候选</span>'
            + '        <b class="merc-loadout-candidate-count" data-merc-candidate-count>未选择</b></div>'
            + '      <div class="merc-loadout-candidate-scope-row merc-loadout-pane-tools"><span>浏览方式</span>'
            + '        <div data-merc-candidate-scope-mount></div></div>'
            + '    </header>'
            + '    <div class="merc-loadout-candidate-focus-summary" data-merc-candidate-focus-summary>'
            +        '背包总览 · 拖到高亮槽位，或选择槽位进入筛选</div>'
            + '    <div class="merc-loadout-candidate-actions" role="toolbar" aria-label="托管操作">'
            + '      <button type="button" data-build-action="commit" aria-label="先选择目标槽位" disabled>交付</button>'
            + '      <button type="button" data-build-action="unequip" aria-label="取回该槽托管装备" disabled>取回</button></div>'
            + '    <div class="merc-loadout-candidate-scroll" data-scroll-region="merc-loadout-candidates">'
            + '      <div class="merc-loadout-candidate-list inventory-owned-grid" data-merc-candidate-list role="listbox" aria-label="可交付装备候选"></div></div>'
            + '    <div class="merc-loadout-inline-notice" data-merc-loadout-notice data-notice-kind="browsing">'
            +        '选择左侧槽位查看兼容候选，或切到「背包」总览跨槽拖拽。</div>'
            + '  </aside>'
            + '</div>';
        this._slotFocusSummary = root.querySelector('[data-merc-slot-focus-summary]');
        this._armorGrid = root.querySelector('[data-merc-armor-grid]');
        this._weaponGrid = root.querySelector('[data-merc-weapon-grid]');
        this._grenadeMount = root.querySelector('[data-merc-grenade-mount]');
        this._candidateList = root.querySelector('[data-merc-candidate-list]');
        this._candidateCount = root.querySelector('[data-merc-candidate-count]');
        this._candidateScopeMount = root.querySelector('[data-merc-candidate-scope-mount]');
        this._candidateFocusSummary = root.querySelector('[data-merc-candidate-focus-summary]');
        this._notice = root.querySelector('[data-merc-loadout-notice]');
        this._notice.setAttribute('role', 'status');
        this._notice.setAttribute('aria-live', 'polite');
        var overlay = this._document.createElement('div');
        overlay.className = 'merc-loadout-candidate-overlay';
        overlay.setAttribute('data-layer', 'candidate-preview');
        overlay.setAttribute('aria-live', 'polite');
        overlay.hidden = true;
        var copy = this._document.createElement('b');
        copy.setAttribute('data-merc-overlay-copy', '');
        overlay.appendChild(copy);
        (overlayHost || root).appendChild(overlay);
        this._overlayNode = overlay;
        this._overlayCopy = copy;
    };

    MercLoadoutPickerView.prototype._createFocusControllers = function() {
        var self = this;
        this._armorRoving = new WorkbenchFocus.RovingGridFocus({
            root: this._armorGrid,
            columns: 3,
            onActiveChange: function(key) { self._focusSlot(key); }
        });
        this._weaponRoving = new WorkbenchFocus.RovingGridFocus({
            root: this._weaponGrid,
            columns: 3,
            onActiveChange: function(key) { self._focusSlot(key); }
        });
        this._slotRovings = [this._armorRoving, this._weaponRoving];
        this._candidateRoving = new WorkbenchFocus.RovingGridFocus({
            root: this._candidateList,
            columns: function() {
                return self._document.defaultView.getComputedStyle(self._candidateList)
                    .gridTemplateColumns.split(/\s+/).length;
            },
            onActiveChange: function(key) { self._focusCandidate(key); }
        });
    };

    MercLoadoutPickerView.prototype._bindInteractions = function() {
        var self = this;
        function gridClick(grid) {
            listen(self._listeners, grid, 'click', function(event) {
                var slot = closest(event.target, '[data-roving-key]', grid);
                if (!slot || slot.disabled || self._interactionState !== 'idle') return;
                var key = slot.getAttribute('data-roving-key');
                var state = self._slotStateOf(slot.getAttribute('data-slot-id'));
                if (state === 'custody_corrupt') {
                    self._showStatusNotice('blocked', CORRUPT_REASON);
                    return;
                }
                self._selectSlot(key);
            });
        }
        gridClick(this._armorGrid);
        gridClick(this._weaponGrid);
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
            else self._selectCandidate(key);
        });
        // 双击 = 选中并直接提交（双击前的两次 click 会选中再清预览，这里按事件目标强制重选）
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
    };

    /* 动作条动词方言：交付/替换随选中槽托管态切换；取回仅 custody 槽可用；
     * 损坏占位 fail-closed（禁用 + 可读原因），写入由 AS2 权威拒绝。 */
    MercLoadoutPickerView.prototype._wrapActionViewSync = function() {
        var self = this;
        var actionView = this._actionView;
        var sync = actionView.sync;
        actionView.sync = function() {
            sync.call(this);
            self._syncActionVerbs();
        };
    };
    MercLoadoutPickerView.prototype._syncActionVerbs = function() {
        var commitBtn = this.root.querySelector('[data-build-action="commit"]');
        var unequipBtn = this.root.querySelector('[data-build-action="unequip"]');
        if (!commitBtn || !unequipBtn) return;
        var slotKey = this._selectedSlotKey;
        var slotId = slotKey ? String(slotKey).split(':')[1] : '';
        var state = slotId ? this._slotStateOf(slotId) : '';
        if (!slotKey || !state) {
            unequipBtn.disabled = true;
            commitBtn.removeAttribute('title');
            commitBtn.removeAttribute('data-blocked-reason');
            return;
        }
        var corrupt = state === 'custody_corrupt';
        commitBtn.textContent = state === 'custody' ? '确认替换' : '确认交付';
        commitBtn.setAttribute('aria-label', state === 'custody'
            ? '确认替换该槽托管装备' : '确认交付所选装备到该槽');
        if (corrupt) {
            commitBtn.disabled = true;
            commitBtn.title = CORRUPT_REASON;
            commitBtn.setAttribute('data-blocked-reason', CORRUPT_REASON);
            this._showStatusNotice('blocked', CORRUPT_REASON);
        } else {
            commitBtn.removeAttribute('title');
            commitBtn.removeAttribute('data-blocked-reason');
        }
        unequipBtn.disabled = this._interactionState !== 'idle' || state !== 'custody';
        if (state === 'custody') {
            unequipBtn.removeAttribute('title');
            unequipBtn.removeAttribute('data-blocked-reason');
        } else {
            var reason = corrupt ? CORRUPT_REASON : NO_CUSTODY_REASON;
            unequipBtn.title = reason;
            unequipBtn.setAttribute('data-blocked-reason', reason);
        }
    };

    // ── picker 宿主契约：通道回调路由（准入门拒 → false → 乐观切换回滚）──
    MercLoadoutPickerView.prototype._onSlotSelect = function(selection) {
        if (this._operateReason) {
            this._showStatusNotice('blocked', this._operateReason);
            return false;
        }
        var state = this._slotStateOf(selection && String(selection.key || '').split(':')[1]);
        if (state === 'custody_corrupt') return false;
        return this._onSlotSelectCb(selection);
    };
    MercLoadoutPickerView.prototype._onCandidateScopeChange = function(scope, selection) {
        if (this._operateReason) {
            this._showStatusNotice('blocked', this._operateReason);
            return false;
        }
        return this._onScopeChangeCb(scope, selection);
    };
    MercLoadoutPickerView.prototype._onCandidateSelect = function(candidate, context) {
        this._onCandidateSelectCb(candidate, context);
    };
    MercLoadoutPickerView.prototype._onSlotDropEquip = function(slotKey, candidate) {
        return this._onDropEquipCb(slotKey, candidate);
    };
    MercLoadoutPickerView.prototype._commitSelected = function(candidate) {
        if (!candidate || !this._selectedSlotKey) return false;
        this._onCommitCb(candidate, this._selectedSlotKey);
        return true;
    };
    MercLoadoutPickerView.prototype._withdrawSelected = function() {
        var slotKey = this._selectedSlotKey;
        if (!slotKey) return false;
        var slotId = String(slotKey).split(':')[1];
        if (this._slotStateOf(slotId) !== 'custody') return false;
        this._onWithdrawCb(slotId, this.root.querySelector('[data-build-action="unequip"]'));
        return true;
    };

    // picker 面板状态条（aria-live 唯一复读出口；kind = browsing/blocked/error/write/...）
    MercLoadoutPickerView.prototype._showStatusNotice = function(kind, message) {
        this._notice.textContent = message;
        this._notice.setAttribute('data-notice-kind', kind || 'error');
    };
    MercLoadoutPickerView.prototype._showBrowsingNotice = function(message) {
        this._notice.textContent = message;
        this._notice.setAttribute('data-notice-kind', 'browsing');
    };

    MercLoadoutPickerView.prototype._slotStateOf = function(id) {
        var info = this._loadoutSlots && this._loadoutSlots[String(id)];
        return info && info.state || 'preset';
    };
    MercLoadoutPickerView.prototype._slotItem = function(eq, state) {
        if (!eq) return null;
        var name = text(eq.displayname || eq.displayName || eq.name, '未知装备');
        return {
            name: name,
            meta: state === 'custody' ? '托管'
                : state === 'custody_corrupt' ? '托管异常' : '预设',
            presentation: {
                displayName: name,
                icon: eq.icon || eq.name || '',
                enhancementLevel: Number(eq.level) || 0,
                itemKind: 'equipment',
                raw: eq.raw || eq.name || '',
                name: eq.name || '',
                displayname: name,
                level: Number(eq.level) || 0
            },
            blocked: state === 'custody_corrupt'
        };
    };
    MercLoadoutPickerView.prototype._renderSlots = function() {
        var merc = this._merc;
        var equips = {};
        if (merc && merc.equips) {
            for (var e = 0; e < merc.equips.length; e++) equips[merc.equips[e].slot] = merc.equips[e];
        }
        this._loadoutSlots = merc && merc.loadout && merc.loadout.slots ? merc.loadout.slots : {};
        var armor = {}, weapon = {};
        var i, id;
        for (i = 0; i < ARMOR_IDS.length; i++) {
            id = ARMOR_IDS[i];
            armor[id] = this._slotItem(equips[Number(id)], this._slotStateOf(id));
        }
        for (i = 0; i < WEAPON_IDS.length; i++) {
            id = WEAPON_IDS[i];
            weapon[id] = this._slotItem(equips[Number(id)], this._slotStateOf(id));
        }
        this._renderSlotGroup(this._armorGrid, this._armorDefs, armor, 'armor', this._armorRoving);
        this._renderSlotGroup(this._weaponGrid, this._weaponDefs, weapon, 'weapon', this._weaponRoving);
    };

    /**
     * 局部刷新入口（写成功 / 快照到达 / 佣兵切换）：槽位网格与门控投影重算；
     * picker 状态（选中槽 / scope / 选中候选）保留，活跃候选随新 revision 经
     * requestKey 栅栏重拉（迟到回包不复活）；门控锁定（canOperate/combatLocked/
     * 出战/阵亡/对账）时整区 locked 并给可读原因。
     */
    MercLoadoutPickerView.prototype.setMerc = function(merc) {
        if (this._destroyed) return false;
        var loadoutRevision = merc && merc.loadout
            ? Number(merc.loadout.loadoutRevision) || 0 : 0;
        var authorityKey = merc
            ? text(merc.id, '') + ':' + String(merc.slotIndex) + ':' + String(loadoutRevision)
            : '';
        var authorityChanged = authorityKey !== this._loadoutAuthorityKey;
        this._loadoutAuthorityKey = authorityKey;
        this._merc = merc || null;
        var reason = merc ? text(this._operateReasonOf(merc), '') : '装备托管数据不可用，请重新同步';
        this._operateReason = reason;
        this._snapshot = { blocked: !!reason, blockedReason: reason };
        this._renderSlots();
        this._renderGrenadeCb(this._grenadeMount, merc);
        var next = reason ? 'locked' : (this._writePending ? 'write_pending' : 'idle');
        if (next !== this._interactionState) this.setInteractionState(next);
        else this._actionView.setState(next);   // 网格重建后重投影禁用态
        if (reason) {
            this._selectedSlotKey = '';
            this._selectedCandidateKey = '';
            this._activeCandidateKey = '';
            this._candidateRequestKey = '';
            this._candidateLoadFailed = false;
            this._syncSlotSelection();
            this._setCandidateState('unselected', [], '');
            this._showStatusNotice('blocked', reason);
            return true;
        }
        // loadout authority 变化时，即使浏览锚点未变，也必须重拉候选与 revision；同一
        // revision 的随后快照刷新不得重复发起读取，否则会在 ready 与 loading 间制造竞态。
        if (this._selectedSlotKey) {
            this.restoreSlot(this._selectedSlotKey, authorityChanged);
        } else if (this._candidateScope === 'backpack' && this._candidateRequestKey
                && (authorityChanged || this._candidateLoadFailed)) {
            this.showBackpackOverview();
        }
        return true;
    };

    MercLoadoutPickerView.prototype.setWritePending = function(pending) {
        this._writePending = pending === true;
        if (this._destroyed || this._operateReason) return false;
        var next = this._writePending ? 'write_pending' : 'idle';
        if (next !== this._interactionState) this.setInteractionState(next);
        return true;
    };

    MercLoadoutPickerView.prototype.mount = function(host) {
        if (this._destroyed || !host) return false;
        if (this.root.parentNode !== host) host.appendChild(this.root);
        return true;
    };
    MercLoadoutPickerView.prototype.getSelectedSlotKey = function() { return this._selectedSlotKey; };
    MercLoadoutPickerView.prototype.getGrenadeMount = function() { return this._grenadeMount; };
    // 预览 overlay 挂载于外部 doll 视口：视口随培养页重建清空时由宿主原样挂回
    MercLoadoutPickerView.prototype.getOverlayNode = function() { return this._overlayNode; };
    MercLoadoutPickerView.prototype.debugState = function() {
        return {
            selectedSlotKey: this._selectedSlotKey,
            selectedCandidateKey: this._selectedCandidateKey,
            candidateScope: this._candidateScope,
            candidateRequestKey: this._candidateRequestKey,
            candidateState: this._candidateState.debugState(),
            interactionState: this._interactionState,
            operateReason: this._operateReason,
            writePending: this._writePending,
            candidateDrag: {
                active: this._candidateDragActive,
                controller: this._candidateDrag && this._candidateDrag.debugState
                    ? this._candidateDrag.debugState() : null
            }
        };
    };
    MercLoadoutPickerView.prototype.destroy = function() {
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
        this._candidateRoving.destroy();
        this._actionView.destroy();
        this._candidateState.destroy();
        for (var i = this._listeners.length - 1; i >= 0; i--) this._listeners[i]();
        this._listeners = [];
        if (this._overlayNode && this._overlayNode.parentNode) {
            this._overlayNode.parentNode.removeChild(this._overlayNode);
        }
        this._overlayNode = null;
        if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
        return true;
    };

    LoadoutPickerModule.install(MercLoadoutPickerView.prototype, {
        slotGrid: {
            classPrefix: 'merc-loadout',
            releaseGrid: function(view, grid) { view._releaseGridCb(grid); },
            projectSlot: function() {},
            bindSlotTooltip: function(view, slot, key, label, presentation, kind, id) {
                view._bindSlotTipCb(slot, presentation, id);
            },
            decorateSlot: function(view, slot, kind, id) {
                var state = view._slotStateOf(id);
                slot.setAttribute('data-loadout-state', state);
                var badge = view._badgeOf(state);
                if (badge) slot.appendChild(badge);
            }
        },
        drag: {
            policy: POLICY,
            subjectKind: 'merc-loadout-candidate',
            sourceInstanceKey: 'merc:loadout-candidates',
            targetInstanceKey: 'merc:loadout-slots',
            classPrefix: 'merc-loadout',
            texts: { ghostFallback: '托管装备候选' }
        },
        pane: {
            syncFocusSummary: function(host, key) {
                if (host._slotFocusSummary) {
                    var id = key ? String(key).split(':')[1] : '';
                    host._slotFocusSummary.textContent = key
                        ? '浏览：' + host._slotNameOf(id)
                        : '浏览：尚未选择槽位';
                }
                return key || '';
            },
            texts: PANE_TEXTS,
            classPrefix: 'merc-loadout',
            candidateTitleSelector: '.merc-loadout-candidate-heading-copy'
        }
    });

    return {
        createView: function(options) { return new MercLoadoutPickerView(options); },
        ARMOR_IDS: ARMOR_IDS.slice(),
        WEAPON_IDS: WEAPON_IDS.slice()
    };
});
