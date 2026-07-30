/** DOM renderer for EquipmentTuningView; controller state stays in equipment-tuning-view.js. */
var EquipmentTuningRender = (function() {
    'use strict';

    function install(TuningView, Model) {
        if (!TuningView || !TuningView.prototype) throw new Error('EquipmentTuningRender requires a view constructor.');
        if (!Model) throw new Error('EquipmentTuningRender requires EquipmentTuningModel.');
        var wireRef = Model.wireRef;
        var sameRef = Model.sameRef;
        var operationLabel = Model.operationLabel;
        var isOperationGroup = Model.isOperationGroup;
        var nextEnhancementLevel = Model.nextEnhancementLevel;
        var candidateForItem = Model.candidateForItem;
        var candidateForTier = Model.candidateForTier;
        var exactQuantity = Model.exactQuantity;
        var materialCount = Model.materialCount;
        var materialDeltaFor = Model.materialDeltaFor;
        var enhancementAvailableMax = Model.enhancementAvailableMax;
        var enhancementHardMax = Model.enhancementHardMax;
        var candidateInstalled = Model.candidateInstalled;
        var modSlotCapacityProjection = Model.modSlotCapacityProjection;
        var compactQuantity = Model.compactQuantity;
        var normalizeModSymbol = Model.normalizeModSymbol;
        var buildModFilterTree = Model.buildModFilterTree;
        var modMatchesFilter = Model.modMatchesFilter;
        var commitLabel = Model.commitLabel;
        var equipmentDiff = Model.equipmentDiff;
        var errorMessage = Model.errorMessage;
        var tuningSourceKey = Model.tuningSourceKey;
        var tuningSourceSupports = Model.tuningSourceSupports;
        var Confirmation = typeof EquipmentTuningConfirmation !== 'undefined'
            ? EquipmentTuningConfirmation : null;
        var Components = typeof WorkbenchComponents !== 'undefined'
            ? WorkbenchComponents : null;

    function activeFocusKey(root) {
        var active = root && root.ownerDocument ? root.ownerDocument.activeElement : null;
        if (!active || !root.contains(active)) return '';
        for (var node = active; node && node !== root; node = node.parentNode) {
            if (!node.getAttribute) continue;
            var key = node.getAttribute('data-tuning-focus-key');
            if (key) return key;
        }
        return '';
    }

    function restoreFocusKey(root, key) {
        if (!root || !key) return false;
        var nodes = root.querySelectorAll('[data-tuning-focus-key]');
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].getAttribute('data-tuning-focus-key') !== key
                    || nodes[i].disabled || !focusRestoreVisible(nodes[i], root)) continue;
            try { nodes[i].focus({preventScroll:true}); }
            catch (_) { nodes[i].focus(); }
            return !!(root.ownerDocument && root.ownerDocument.activeElement === nodes[i]);
        }
        return false;
    }

    function focusRestoreVisible(node, root) {
        if (!node || !root) return false;
        var view = node.ownerDocument && node.ownerDocument.defaultView;
        for (var current = node; current; current = current.parentNode) {
            if (current.hidden || current.inert
                    || current.getAttribute && (current.getAttribute('aria-hidden') === 'true'
                        || current.hasAttribute('inert'))) return false;
            if (view && view.getComputedStyle && current.nodeType === 1) {
                var style = view.getComputedStyle(current);
                if (style.display === 'none' || style.visibility === 'hidden'
                        || style.visibility === 'collapse') return false;
            }
            if (current === root) break;
        }
        return !node.getClientRects || node.getClientRects().length > 0;
    }

    function ownsFocusKey(root, target) {
        for (var node = target; node && node !== root; node = node.parentNode) {
            if (node.getAttribute && node.getAttribute('data-tuning-focus-key')) return true;
        }
        return false;
    }

    TuningView.prototype.render = function(renderOptions) {
        if (!this._root) return;
        renderOptions = renderOptions || {};
        if (renderOptions.previewOnly
                && this._root.querySelector('.equipment-tuning-view')) {
            this._refreshPreviewSurface(renderOptions);
            return;
        }
        var preserveScroll = renderOptions.preserveScroll !== false;
        var activeKey = preserveScroll ? activeFocusKey(this._root) : '';
        var activeElement = this._root.ownerDocument && this._root.ownerDocument.activeElement;
        if (!preserveScroll) {
            this._renderFocusKey = '';
            this._renderFocusDeferred = false;
        } else if (activeKey) {
            this._renderFocusKey = activeKey;
            this._renderFocusDeferred = false;
        } else if (activeElement && (activeElement !== this._root.ownerDocument.body
                || !this._renderFocusDeferred)) {
            this._renderFocusKey = '';
            this._renderFocusDeferred = false;
        }
        var focusKey = activeKey || this._renderFocusKey || '';
        var previousBody = this._root.querySelector('.equipment-tuning-body');
        var previousPreview = this._root.querySelector('.equipment-tuning-preview');
        var previousDetail = this._root.querySelector('.equipment-tuning-detail');
        var bodyScroll = preserveScroll && previousBody ? {top:previousBody.scrollTop,left:previousBody.scrollLeft} : null;
        var previewScroll = preserveScroll && previousPreview ? {top:previousPreview.scrollTop,left:previousPreview.scrollLeft} : null;
        var detailScroll = preserveScroll && previousDetail ? {top:previousDetail.scrollTop,left:previousDetail.scrollLeft} : null;
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        clear(this._root, this._tooltipScope);
        var root = element('div', 'equipment-tuning-view');
        var self = this;
        root.addEventListener('pointerdown', function(event) {
            if (ownsFocusKey(root, event && event.target)) return;
            self._renderFocusKey = '';
            self._renderFocusDeferred = false;
            self._previewFocusIntent = null;
        });
        root.setAttribute('data-operation', this._operation === 'replace_mod' ? 'install_mod' : this._operation);
        root.setAttribute('data-source-kind', this._source && this._source.sourceKind || 'none');
        root.setAttribute('data-reconcile', this._needsReconcile ? 'required' : 'clear');
        root.appendChild(this._renderHeader());
        root.appendChild(this._renderTabs());
        root.appendChild(this._renderInfoPanel());
        var detail = element('section', 'equipment-tuning-detail');
        detail.setAttribute('aria-label', '调制选项与权威预览');
        detail.appendChild(this._renderBody());
        detail.appendChild(this._renderPreview());
        root.appendChild(detail);
        root.appendChild(this._ensureCommitBar().root);
        this._root.appendChild(root);
        var nextBody = root.querySelector('.equipment-tuning-body');
        var nextPreview = root.querySelector('.equipment-tuning-preview');
        var nextDetail = root.querySelector('.equipment-tuning-detail');
        this._updateCommitBar();
        this._applyInteractionProjection(root);
        this._syncModIntentPresentation(root);
        if (restoreFocusKey(root, focusKey)) {
            this._renderFocusKey = '';
            this._renderFocusDeferred = false;
        } else {
            this._renderFocusKey = focusKey;
            this._renderFocusDeferred = !!focusKey;
        }
        if (bodyScroll && nextBody) { nextBody.scrollTop = bodyScroll.top; nextBody.scrollLeft = bodyScroll.left; }
        if (previewScroll && nextPreview) { nextPreview.scrollTop = previewScroll.top; nextPreview.scrollLeft = previewScroll.left; }
        if (detailScroll && nextDetail) { nextDetail.scrollTop = detailScroll.top; nextDetail.scrollLeft = detailScroll.left; }
    };

    TuningView.prototype._ensureCommitBar = function() {
        if (this._commitBar) return this._commitBar;
        var self = this;
        var id = ('equipment-tuning-lock-' + this.instanceKey)
            .replace(/[^A-Za-z0-9_-]/g, '-');
        this._commitBar = new Components.CommitBar({
            document:this._root.ownerDocument,
            className:'equipment-tuning-commit-bar',
            label:'等待预览',
            status:'选择操作后查看权威材料与结果。',
            canCommit:false,
            onCommit:function() { self.commit(); }
        });
        this._commitBar.statusNode.id = id;
        this._commitBar.statusNode.setAttribute('role', 'status');
        this._commitBar.statusNode.setAttribute('aria-live', 'polite');
        this._commitBar.primaryButton.classList.add('equipment-tuning-commit');
        this._commitBar.primaryButton.setAttribute('data-tuning-focus-key', 'commit');
        this._commitBar.primaryButton.setAttribute('aria-describedby', id);
        setCapability(this._commitBar.primaryButton, 'commit', false);
        return this._commitBar;
    };

    TuningView.prototype._updateCommitBar = function() {
        var bar = this._ensureCommitBar();
        var projection = this.getInteractionProjection();
        var ready = !!(this._preview && this._preview.tuningToken);
        var status = projection.reason || this._status;
        if (!status && this._preview) {
            status = this._preview.noOp ? '当前预览无需写入。'
                : ready ? '材料与结果已确认，可以提交。'
                    : '当前预览没有可提交的权威令牌。';
        }
        if (!status) status = '选择操作后查看权威材料与结果。';
        bar.update({
            label:this._busy ? '提交中…'
                : ready ? commitLabel(this._preview) : '等待权威预览',
            status:status,
            busy:projection.phase === 'write_pending',
            canCommit:projection.commit,
            state:projection.commit ? 'ready'
                : projection.phase === 'idle' ? 'blocked'
                    : projection.phase.indexOf('retry') >= 0
                        || projection.phase === 'reconcile_required' ? 'error' : 'busy'
        });
        return bar;
    };

    TuningView.prototype._refreshPreviewSurface = function(options) {
        var root = this._root.querySelector('.equipment-tuning-view');
        var detail = root && root.querySelector('.equipment-tuning-detail');
        var preview = root && root.querySelector('.equipment-tuning-preview');
        if (!root || !detail || !preview) {
            this.render({preserveScroll:true});
            return false;
        }
        var detailScroll = this._detailScrollAnchor
            || {top:detail.scrollTop, left:detail.scrollLeft};
        if (this._readPending && !this._detailScrollAnchor) {
            this._detailScrollAnchor = detailScroll;
        }
        var previewScroll = {top:preview.scrollTop, left:preview.scrollLeft};
        this._updatePreviewSection(preview);
        this._syncEnhancementDraft(this._targetLevel);
        this._syncEnhancementPreview();
        this._renderConfirmationControl();
        var status = root.querySelector('[data-tuning-status]');
        if (status) status.textContent = this._status;
        this._updateCommitBar();
        this._applyInteractionProjection(root);
        this._syncModIntentPresentation(root);
        detail.scrollTop = detailScroll.top;
        detail.scrollLeft = detailScroll.left;
        preview.scrollTop = previewScroll.top;
        preview.scrollLeft = previewScroll.left;
        if (!this._readPending) this._detailScrollAnchor = null;
        if (options && options.focusNext) this._focusCommitAfterPreview();
        return true;
    };

    TuningView.prototype._syncModIntentPresentation = function(root) {
        root = root || this._root.querySelector('.equipment-tuning-view');
        if (!root) return false;
        var active = root.querySelectorAll(
            '.is-intent-pending,[data-pending-action],[data-pending-phase]'
        );
        for (var i = 0; i < active.length; i++) {
            active[i].classList.remove('is-intent-pending');
            active[i].removeAttribute('data-pending-action');
            active[i].removeAttribute('data-pending-phase');
            active[i].removeAttribute('aria-busy');
        }
        root.removeAttribute('data-tuning-intent-phase');
        var intent = this._modIntent;
        if (!intent || !intent.phase) return true;
        root.setAttribute('data-tuning-intent-phase', intent.phase);
        if (intent.phase === 'preview_ready') return true;
        var candidateNodes = root.querySelectorAll('[data-candidate-key]');
        var candidateNode = null;
        var replaceNode = null;
        for (i = 0; i < candidateNodes.length; i++) {
            var candidateKey = candidateNodes[i].getAttribute('data-candidate-key');
            if (!candidateNode && candidateKey === intent.candidateKey
                    && candidateNodes[i].classList.contains('equipment-tuning-candidate')) {
                candidateNode = candidateNodes[i];
            }
            if (!replaceNode && candidateKey === intent.replaceCandidateKey
                    && candidateNodes[i].closest('.equipment-tuning-installed-entry')) {
                replaceNode = candidateNodes[i].closest('.equipment-tuning-installed-entry');
            }
        }
        if (candidateNode) {
            candidateNode.classList.add('is-intent-pending');
            candidateNode.setAttribute('data-pending-phase', intent.phase);
            candidateNode.setAttribute('aria-busy', 'true');
        }
        var target = null;
        var action = intent.operation === 'detach_mod' ? 'detach'
            : intent.operation === 'replace_mod' ? 'replace' : 'install';
        if (intent.phase === 'committed_syncing') {
            for (i = 0; i < candidateNodes.length; i++) {
                if (candidateNodes[i].getAttribute('data-candidate-key')
                        === intent.candidateKey) {
                    target = candidateNodes[i].closest(
                        '.equipment-tuning-installed-entry'
                    );
                    if (target) break;
                }
            }
        } else if (intent.operation === 'replace_mod'
                || intent.operation === 'detach_mod') {
            target = replaceNode;
            if (!target && intent.operation === 'detach_mod') {
                for (i = 0; i < candidateNodes.length; i++) {
                    if (candidateNodes[i].getAttribute('data-candidate-key')
                            === intent.candidateKey) {
                        target = candidateNodes[i].closest(
                            '.equipment-tuning-installed-entry'
                        );
                        if (target) break;
                    }
                }
            }
        } else {
            target = root.querySelector(
                '.equipment-tuning-installed-entry[data-mod-slot-state="empty"]'
            );
        }
        if (target) {
            target.classList.add('is-intent-pending');
            target.setAttribute('data-pending-action', action);
            target.setAttribute('data-pending-phase', intent.phase);
            target.setAttribute('aria-busy', 'true');
        }
        return true;
    };

    TuningView.prototype._focusCommitAfterPreview = function() {
        var intent = this._previewFocusIntent;
        this._previewFocusIntent = null;
        if (!intent || !this._commitBar || this._commitBar.primaryButton.disabled) return false;
        var document = this._root && this._root.ownerDocument;
        var active = document && document.activeElement;
        if (active && active.matches
                && active.matches('input,textarea,select,[contenteditable="true"]')) return false;
        try { this._commitBar.primaryButton.focus({preventScroll:true}); }
        catch (_) { this._commitBar.primaryButton.focus(); }
        return document.activeElement === this._commitBar.primaryButton;
    };

    TuningView.prototype._applyInteractionProjection = function(root) {
        root = root || this._root.querySelector('.equipment-tuning-view');
        if (!root) return false;
        var projection = this.getInteractionProjection();
        root.setAttribute('data-interaction-phase', projection.phase);
        root.setAttribute('aria-busy', projection.blocked ? 'true' : 'false');
        if (!projection.blocked) this._interactionAnnouncement = '';
        var statusId = this._ensureCommitBar().statusNode.id;
        var nodes = root.querySelectorAll('[data-tuning-capability]');
        for (var i = 0; i < nodes.length; i++) {
            var node = nodes[i];
            var capability = node.getAttribute('data-tuning-capability');
            var intrinsic = node.getAttribute('data-tuning-intrinsic-disabled') === 'true';
            var explainable = node.getAttribute('data-tuning-explain-disabled') === 'true';
            var authority = projection[capability] === true;
            var enabled = authority && !intrinsic;
            node.disabled = !enabled && !(authority && intrinsic && explainable);
            node.setAttribute('aria-disabled', enabled ? 'false' : 'true');
            if (!authority && projection.reason) {
                if (!node.hasAttribute('data-tuning-base-describedby')) {
                    node.setAttribute('data-tuning-base-describedby',
                        node.getAttribute('aria-describedby') || '');
                }
                var base = node.getAttribute('data-tuning-base-describedby');
                node.setAttribute('aria-describedby',
                    (base ? base + ' ' : '') + statusId);
                node.setAttribute('data-tuning-lock-reason', projection.reason);
            } else {
                if (node.hasAttribute('data-tuning-base-describedby')) {
                    var describedBy = node.getAttribute('data-tuning-base-describedby');
                    if (describedBy) node.setAttribute('aria-describedby', describedBy);
                    else node.removeAttribute('aria-describedby');
                    node.removeAttribute('data-tuning-base-describedby');
                }
                node.removeAttribute('data-tuning-lock-reason');
            }
        }
        return projection;
    };

    TuningView.prototype._renderHeader = function() {
        var header = element('section', 'equipment-tuning-summary');
        if (!this._sourceItem) {
            var emptyMark = element('div', 'equipment-tuning-empty-mark'); emptyMark.textContent = '＋';
            var emptyCopy = element('div', 'equipment-tuning-summary-copy');
            emptyCopy.innerHTML = '<b>选择装备</b><small>只接受当前权威来源中的武器与防具</small>';
            emptyCopy.querySelector('small').setAttribute('data-tuning-status', '');
            header.appendChild(emptyMark); header.appendChild(emptyCopy);
            header.appendChild(this._renderConfirmationControl());
            return header;
        }
        var item = this._sourceItem;
        var self = this;
        var icon = element('button', 'equipment-tuning-main-icon equipment-tuning-inspect-trigger');
        icon.type = 'button';
        icon.disabled = !this._inspectAvailable(item);
        icon.setAttribute('data-tuning-focus-key', 'source:inspect');
        icon.setAttribute('aria-label', '检视当前装备：' + String(item.displayName || item.name || '装备'));
        icon.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon');
        icon.addEventListener('click', function() { self.inspectCurrentEquipment(); });
        setCapability(icon, 'inspect', !this._inspectAvailable(item));
        var copy = element('div', 'equipment-tuning-main-copy equipment-tuning-summary-copy');
        var equipment = this._snapshot && this._snapshot.equipment;
        var level = equipment ? Number(equipment.level || 0) : Number(item.enhancementLevel || 0);
        copy.innerHTML = '<b>' + escapeHtml(item.displayName || item.name) + '</b>'
            + '<span>强化 +' + level + (equipment && equipment.tier ? ' · ' + escapeHtml(equipment.tier) : '') + '</span>'
            + '<small>' + escapeHtml(this._source && this._source.sourceKind === 'loadout'
                ? String(this._source.slotKey || '当前槽位') + ' · ' + this._status
                : this._status) + '</small>';
        copy.querySelector('small').setAttribute('data-tuning-status', '');
        header.appendChild(icon);
        header.appendChild(copy);
        var installedState = this._renderInstalledState(equipment);
        if (installedState.childNodes.length) header.appendChild(installedState);
        var info = element('button', 'equipment-tuning-info-open');
        info.type = 'button';
        info.textContent = '调制说明';
        info.setAttribute('data-tuning-focus-key', 'info:open');
        info.setAttribute('aria-label', '展开当前调制说明');
        info.setAttribute('aria-expanded', this._infoPanelOpen ? 'true' : 'false');
        info.addEventListener('click', this._openInfoPanel.bind(this));
        header.appendChild(info);
        header.appendChild(this._renderConfirmationControl());
        return header;
    };

    TuningView.prototype._renderConfirmationControl = function() {
        if (!this._confirmationControl) {
            var document = this._root.ownerDocument;
            var control = document.createElement('section');
            control.className = 'equipment-tuning-confirmation';
            var choiceId = ('equipment-tuning-confirmation-' + this.instanceKey)
                .replace(/[^A-Za-z0-9_-]/g, '-');
            var boundary = document.createElement('p');
            boundary.className = 'equipment-tuning-confirmation-boundary';
            boundary.id = choiceId + '-boundary';
            var reason = document.createElement('p');
            reason.className = 'equipment-tuning-confirmation-reason';
            reason.id = choiceId + '-reason';
            reason.setAttribute('role', 'status');
            reason.setAttribute('aria-live', 'polite');
            var self = this;
            var choices = Confirmation.CHOICES.map(function(choice) {
                return {
                    value:choice.value,
                    label:choice.label,
                    ariaLabel:choice.ariaLabel,
                    className:'equipment-tuning-confirmation-option',
                    dataAttribute:'data-confirmation-mode'
                };
            });
            this._confirmationChoice = new Components.ChoiceGroup({
                document:document,
                className:'equipment-tuning-confirmation-toggle',
                ariaLabel:'配件提交确认方式',
                value:this._modConfirmationMode,
                choices:choices,
                onChange:function(mode) { return self.setModConfirmationMode(mode); }
            });
            this._confirmationChoice.root.id = choiceId;
            this._confirmationChoice.root.setAttribute(
                'aria-describedby', boundary.id + ' ' + reason.id);
            control.appendChild(this._confirmationChoice.root);
            control.appendChild(boundary);
            control.appendChild(reason);
            this._confirmationControl = control;
            this._confirmationBoundary = boundary;
            this._confirmationReason = reason;
        }
        var state = this.getConfirmationState();
        this._confirmationChoice.update({value:state.value, disabled:state.disabled});
        this._confirmationBoundary.textContent = state.boundaryText;
        this._confirmationReason.textContent = state.reason;
        this._confirmationReason.hidden = !state.reason;
        this._confirmationControl.setAttribute('role', 'group');
        this._confirmationControl.setAttribute('aria-label', '配件提交确认方式');
        this._confirmationControl.setAttribute(
            'data-confirmation-disabled', state.disabled ? 'true' : 'false');
        this._confirmationControl.setAttribute(
            'aria-disabled', state.disabled ? 'true' : 'false');
        if (state.disabled) {
            this._confirmationControl.tabIndex = 0;
            this._confirmationControl.setAttribute('data-tuning-lock-reason', state.reason);
        } else {
            this._confirmationControl.removeAttribute('tabindex');
            this._confirmationControl.removeAttribute('data-tuning-lock-reason');
        }
        for (var i = 0; i < Confirmation.CHOICES.length; i++) {
            var button = this._confirmationChoice.getButton(
                Confirmation.CHOICES[i].value);
            if (button) button.setAttribute(
                'aria-describedby',
                this._confirmationBoundary.id + ' ' + this._confirmationReason.id);
        }
        return this._confirmationControl;
    };

    TuningView.prototype._renderInfoPanel = function() {
        var panel = element('section', 'equipment-tuning-info-panel');
        panel.hidden = !this._infoPanelOpen;
        panel.setAttribute('aria-hidden', this._infoPanelOpen ? 'false' : 'true');
        panel.setAttribute('aria-label', '当前调制说明');
        var subject = this._infoSubject || this._defaultInfoSubject();
        var copy = element('div', 'equipment-tuning-info-copy');
        copy.innerHTML = '<span>调制说明</span><b data-tuning-info-title>'
            + escapeHtml(subject.title || '当前操作') + '</b><p data-tuning-info-copy>'
            + escapeHtml(subject.detail || '暂无进一步说明。') + '</p>';
        panel.appendChild(copy);
        var actions = element('div', 'equipment-tuning-info-actions');
        var self = this;
        var close = actionButton('收起说明', function() { self._closeInfoPanel(); });
        close.setAttribute('data-tuning-focus-key', 'info:close');
        actions.appendChild(close);
        panel.appendChild(actions);
        return panel;
    };

    TuningView.prototype._defaultInfoSubject = function() {
        var snapshot = this._snapshot || {};
        var equipment = snapshot.equipment || {};
        var item = this._sourceItem || {};
        var name = String(item.displayName || item.name || '当前装备');
        var operation = this._operation === 'replace_mod' ? 'install_mod' : this._operation;
        var detail;
        if (operation === 'enhance') {
            detail = '当前 +' + Number(snapshot.enhance && snapshot.enhance.currentLevel || 0)
                + ' · 可用上限 +' + enhancementAvailableMax(snapshot)
                + ' · 选择目标后先预览材料与结果，再提交。';
        } else if (operation === 'install_tier') {
            detail = '当前进阶 ' + String(equipment.tier || '无')
                + ' · 聚焦候选可读取条件、分类与用途。';
        } else if (operation === 'install_mod') {
            detail = '已安装 ' + (equipment.mods instanceof Array ? equipment.mods.length : 0)
                + ' 个配件 · 聚焦候选可读取条件、分类与用途。';
        } else {
            detail = '当前强化 +' + Number(equipment.level || item.enhancementLevel || 0)
                + ' · 选择同类装备后先预览双向交换结果。';
        }
        return {title:name + ' · ' + operationLabel(operation), detail:detail};
    };

    TuningView.prototype._setInfoSubject = function(candidate) {
        if (!candidate) return false;
        this._infoSubject = {
            key:String(candidate.candidateKey || candidate.itemName || ''),
            title:String(candidate.itemName || candidate.candidateKey || '候选'),
            detail:[
                candidate.gradeLabel || candidate.tierName || '',
                candidate.scopeLabel || '',
                candidate.roleLabel || '',
                candidate.reason || (candidate.available === false ? '当前不可用' : '当前可用')
            ].filter(function(value) { return !!String(value || ''); }).join(' · ')
        };
        if (this._infoPanelOpen) this._updateInfoPanel();
        return true;
    };

    TuningView.prototype._updateInfoPanel = function() {
        if (!this._root || !this._infoPanelOpen || !this._infoSubject) return false;
        var title = this._root.querySelector('[data-tuning-info-title]');
        var copy = this._root.querySelector('[data-tuning-info-copy]');
        if (!title || !copy) return false;
        title.textContent = this._infoSubject.title;
        copy.textContent = this._infoSubject.detail || '暂无进一步说明。';
        return true;
    };

    TuningView.prototype._openInfoPanel = function() {
        this._infoPanelOpen = true;
        this._renderFocusKey = 'info:close';
        this._renderFocusDeferred = true;
        var active = this._root && this._root.ownerDocument
            ? this._root.ownerDocument.activeElement : null;
        if (active && this._root.contains(active) && active.blur) active.blur();
        this.render();
        return true;
    };

    TuningView.prototype._closeInfoPanel = function() {
        if (!this._infoPanelOpen) return false;
        this._infoPanelOpen = false;
        if (this._infoSubject && this._infoSubject.key === 'confirmation-help') {
            this._infoSubject = null;
        }
        this._renderFocusKey = 'info:open';
        this._renderFocusDeferred = true;
        var active = this._root && this._root.ownerDocument
            ? this._root.ownerDocument.activeElement : null;
        if (active && this._root.contains(active) && active.blur) active.blur();
        this.render();
        return true;
    };

    TuningView.prototype.consumeEscape = function() {
        if (this._closeInfoPanel()) return true;
        if (this._replaceCandidateKey) return this._clearReplacementCandidate();
        return false;
    };

    TuningView.prototype._renderInstalledState = function(equipment) {
        var state = element('div', 'equipment-tuning-installed-state');
        if (!equipment) return state;
        var self = this;
        var tierName = String(equipment.tier || '');
        var tierCandidates = this._snapshot && this._snapshot.tierCandidates || [];
        var tierCandidate = candidateForTier(tierCandidates, tierName);
        if (tierName || tierCandidates.length) {
            var tier = element(
                'button',
                'equipment-tuning-status-icon tier' + (tierName ? '' : ' empty')
            );
            tier.type = 'button';
            tier.setAttribute(
                'data-tuning-focus-key',
                'summary-tier:' + (tierName || 'empty')
            );
            tier.setAttribute(
                'aria-label',
                tierName
                    ? '进阶槽：' + tierName + '，点击查看进阶'
                    : '进阶槽：空，点击选择进阶'
            );
            tier.innerHTML = tierName
                ? iconHtml(
                    tierCandidate && tierCandidate.itemName || tierName,
                    'kshop-icon'
                ) + '<span class="equipment-tuning-status-mark" aria-hidden="true">阶</span>'
                : '<span class="equipment-tuning-status-mark" aria-hidden="true">阶</span>';
            tier.addEventListener('click', function() { self.setOperation('install_tier'); });
            tier.disabled = self._busy || self._readPending || self._needsReconcile;
            setCapability(tier, 'tier', false);
            if (tierCandidate) this._bindCandidateTooltip(tier, tierCandidate);
            state.appendChild(tier);
        }
        var candidates = this._snapshot && this._snapshot.modCandidates || [];
        var installed = equipment.mods instanceof Array ? equipment.mods : [];
        var capacityProjection =
            modSlotCapacityProjection(equipment, installed.length);
        var capacity = capacityProjection.value;
        var modSlots = element('div', 'equipment-tuning-mod-slots');
        modSlots.setAttribute('data-slot-surface', 'summary');
        modSlots.setAttribute('role', 'group');
        modSlots.setAttribute(
            'aria-label',
            capacityProjection.state === 'known'
                ? (capacity === 0
                    ? '无插件槽'
                    : '插件槽：已用 ' + installed.length + '，共 ' + capacity)
                : capacityProjection.state === 'malformed'
                    ? '插件槽容量未知，已安装配件 ' + installed.length + ' 个'
                    : '已安装配件 ' + installed.length + ' 个'
        );
        if (capacityProjection.state === 'known') {
            modSlots.setAttribute('data-mod-slot-capacity', String(capacity));
            modSlots.setAttribute('data-mod-slot-used', String(installed.length));
        } else if (capacityProjection.state === 'malformed') {
            modSlots.setAttribute('data-mod-slot-capacity-state', 'unknown');
        }
        installed.forEach(function(name, index) {
            var candidate = candidateForItem(candidates, name);
            var button = element('button', 'equipment-tuning-status-icon mod grade-'
                + String(candidate && candidate.grade || 'unknown'));
            button.type = 'button';
            button.setAttribute('data-mod-slot-index', String(index));
            button.setAttribute('data-tuning-focus-key', 'summary-installed-mod:'
                + index + ':' + String(candidate && candidate.candidateKey || name));
            button.setAttribute(
                'aria-label',
                '插件槽 ' + (index + 1) + '：' + String(name) + '，点击选择替换'
            );
            if (candidate && candidate.gradeColor) {
                button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
            }
            button.innerHTML = iconHtml(name, 'kshop-icon')
                + '<i class="equipment-tuning-status-role inventory-mod-glyph symbol-'
                + normalizeModSymbol(candidate && candidate.symbol) + '" aria-hidden="true"></i>';
            button.disabled = self._busy || self._readPending || self._needsReconcile
                || !candidate || !candidate.candidateKey;
            setCapability(button, 'slot', !candidate || !candidate.candidateKey);
            button.addEventListener('click', function() {
                if (candidate && candidate.candidateKey) {
                    self._selectReplacementCandidate(candidate);
                }
            });
            if (candidate) self._bindCandidateTooltip(button, candidate);
            modSlots.appendChild(button);
        });
        if (capacityProjection.state === 'known') {
            for (var slotIndex = installed.length; slotIndex < capacity; slotIndex++) {
                var emptySlot = element(
                    'button',
                    'equipment-tuning-status-icon mod empty equipment-tuning-status-empty'
                );
                emptySlot.type = 'button';
                emptySlot.setAttribute('data-mod-slot-index', String(slotIndex));
                emptySlot.setAttribute(
                    'data-tuning-focus-key',
                    'summary-empty-mod-slot:' + String(slotIndex)
                );
                emptySlot.setAttribute(
                    'aria-label',
                    '插件槽 ' + (slotIndex + 1) + '：空，点击选择要安装的配件'
                );
                emptySlot.disabled =
                    self._busy || self._readPending || self._needsReconcile;
                setCapability(emptySlot, 'slot', false);
                emptySlot.addEventListener('click', (function(index) {
                    return function() { self._selectEmptyModSlot(index); };
                })(slotIndex));
                modSlots.appendChild(emptySlot);
            }
            var count = element('span', 'equipment-tuning-slot-capacity');
            count.setAttribute('aria-hidden', 'true');
            count.textContent = capacity === 0
                ? '无插件槽'
                : installed.length + '/' + capacity;
            modSlots.appendChild(count);
        } else if (capacityProjection.state === 'malformed') {
            var unknown = element('span', 'equipment-tuning-slot-capacity unknown');
            unknown.setAttribute('aria-hidden', 'true');
            unknown.textContent = '容量未知';
            modSlots.appendChild(unknown);
        }
        if (installed.length || capacityProjection.state !== 'absent') {
            state.appendChild(modSlots);
        }
        return state;
    };

    TuningView.prototype._renderTabs = function() {
        var tabs = element('nav', 'equipment-tuning-tabs');
        var self = this;
        [['enhance','强化度'],['convert','交换'],['install_tier','进阶'],['install_mod','配件']].forEach(function(pair) {
            if (self._source && !tuningSourceSupports(self._source, pair[0])) return;
            var button = element('button', 'equipment-tuning-tab' + (self._operation === pair[0]
                || (pair[0] === 'install_mod' && (self._operation === 'replace_mod'
                    || self._operation === 'detach_mod' || self._operation === 'detach_all_mods')) ? ' active' : ''));
            button.type = 'button'; button.textContent = pair[1];
            button.disabled = !self._source || self._busy || self._readPending;
            button.setAttribute('data-tuning-focus-key', 'operation:' + pair[0]);
            button.addEventListener('click', function() { self.setOperation(pair[0]); });
            setCapability(button, 'tabs', !self._source);
            tabs.appendChild(button);
        });
        return tabs;
    };

    TuningView.prototype._renderBody = function() {
        var body = element('section', 'equipment-tuning-body');
        if (this._refreshRetryRequired) {
            var refreshRetry = element('button', 'equipment-tuning-retry');
            refreshRetry.type = 'button';
            var loadout = this._source && this._source.sourceKind === 'loadout';
            refreshRetry.textContent = this._refreshRetryPending ? '正在重试同步…'
                : loadout ? '重试构筑同步' : '重试背包刷新';
            refreshRetry.disabled = this._refreshRetryPending;
            setCapability(refreshRetry, 'retry', false);
            var refreshSelf = this;
            refreshRetry.addEventListener('click', function() { refreshSelf.retryInventoryRefresh(); });
            body.appendChild(empty(this._status));
            body.appendChild(refreshRetry);
            return body;
        }
        if (!this._source) { body.appendChild(empty('选择一件装备后，Flash 会返回权威候选。')); return body; }
        if (!this._snapshot) {
            var retry = element('button', 'equipment-tuning-retry'); retry.type = 'button';
            retry.textContent = this._needsReconcile ? '重新对账' : '重试同步';
            setCapability(retry, this._needsReconcile ? 'reconcile' : 'snapshot', false);
            var self = this; retry.addEventListener('click', function() {
                var capability = self._needsReconcile ? 'reconcile' : 'snapshot';
                if (self._allowInteraction(capability)) {
                    self.requestSnapshot(self._lastCommitCallId);
                }
            });
            body.appendChild(empty(this._status)); body.appendChild(retry); return body;
        }
        if (this._operation === 'enhance' || this._operation === 'convert') {
            if (this._operation === 'enhance') this._renderEnhance(body);
            else this._renderConvert(body);
        }
        else if (this._operation === 'install_tier') this._renderCandidates(body, this._snapshot.tierCandidates || [], 'install_tier');
        else this._renderMods(body);
        return body;
    };

    TuningView.prototype._renderEnhance = function(body) {
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || (this._snapshot.equipment && this._snapshot.equipment.level) || 0);
        var availableMax = enhancementAvailableMax(this._snapshot);
        var hardMax = enhancementHardMax(this._snapshot);
        var max = Math.min(availableMax, hardMax);
        var canEnhance = current < max;
        var target = canEnhance ? Math.max(current + 1, Math.min(max, Number(this._targetLevel || current + 1))) : current;
        var ownedStones = materialCount(this._snapshot.materials, '强化石');
        var reactor = element('section', 'equipment-tuning-enhance-reactor');
        var core = element('div', 'equipment-tuning-stone-core');
        var staticMotion = prefersReducedMotion()
            || !!(this._root && this._root.closest && this._root.closest('.item-grid-compact'));
        core.setAttribute('data-motion', staticMotion ? 'static' : 'animated');
        core.innerHTML = materialIconHtml('强化石', 'equipment-tuning-stone-icon', staticMotion);
        var reactorCopy = element('div', 'equipment-tuning-reactor-copy');
        reactorCopy.innerHTML = '<span>D.L.S. / CRYSTAL RESONANCE</span><b>强化石共振注能</b>';
        var reactorBalance = element('div', 'equipment-tuning-reactor-balance');
        var stoneDelta = this._preview && this._preview.operation === 'enhance'
            ? materialDeltaFor(this._preview.materials, '强化石') : null;
        reactorBalance.innerHTML = '<span>持有 <strong>' + exactQuantity(ownedStones) + '</strong></span>';
        if (stoneDelta) {
            reactorBalance.innerHTML += '<em class="equipment-tuning-reactor-spend">消耗 <b>'
                + exactQuantity(Math.max(0, -Number(stoneDelta.delta || 0))) + '</b> · 强化后剩余 <b>'
                + exactQuantity(stoneDelta.after) + '</b></em>';
        } else if (this._readPending && this._previewPendingOperation === 'enhance') {
            reactorBalance.innerHTML += '<em class="equipment-tuning-reactor-pending">正在计算消耗…</em>';
        }
        reactorCopy.appendChild(reactorBalance);
        var reactorReadout = element('div', 'equipment-tuning-reactor-readout');
        reactorReadout.innerHTML = canEnhance
            ? '<span>目标输出</span><b>+' + current + '<i>→</i>+' + target + '</b>'
            : '<span>' + (current >= hardMax ? '强化上限' : '当前状态') + '</span><b>+'
                + current + (current >= hardMax ? '<i>·</i>已封顶' : '') + '</b>';
        reactor.appendChild(core); reactor.appendChild(reactorCopy); reactor.appendChild(reactorReadout);
        body.appendChild(reactor);
        var panel = element('div', 'equipment-tuning-level-panel');
        if (!canEnhance) {
            panel.classList.add('capped');
            var cappedHeading = element('div', 'equipment-tuning-level-heading');
            cappedHeading.innerHTML = current >= hardMax
                ? '<span>永久强化上限</span><b>+' + hardMax + ' · 已封顶</b>'
                : '<span>当前阶段暂不能继续强化</span><b>当前 +' + current + '</b>';
            panel.appendChild(cappedHeading);
            var cappedCopy = element('p', 'equipment-tuning-cap-copy');
            cappedCopy.textContent = current >= hardMax
                ? '这件装备已经达到最高强化度。'
                : '继续推进剧情或提升铁匠能力后再来查看。';
            panel.appendChild(cappedCopy);
            body.appendChild(panel);
            return;
        }
        var heading = element('div', 'equipment-tuning-level-heading');
        heading.innerHTML = '<span>选择目标强化度</span><b>+' + target + '</b>';
        panel.appendChild(heading);
        var stepper = element('div', 'equipment-tuning-level-stepper');
        var self = this;
        var minus = actionButton('−', function() {
            self._chooseEnhancementLevel(Number(self._targetLevel) - 1, 'stepper');
        });
        minus.classList.add('equipment-tuning-level-step');
        minus.setAttribute('data-enhance-step', 'minus');
        var input = element('input', 'equipment-tuning-level-input');
        input.type = 'number'; input.min = String(Math.min(max, current + 1)); input.max = String(max); input.value = String(target);
        input.setAttribute('data-browser-native', '1');
        input.setAttribute('data-tuning-focus-key', 'enhance:number');
        input.addEventListener('change', function() {
            self._chooseEnhancementLevel(input.value, 'number');
        });
        var plus = actionButton('+', function() {
            self._chooseEnhancementLevel(Number(self._targetLevel) + 1, 'stepper');
        });
        plus.classList.add('equipment-tuning-level-step');
        plus.setAttribute('data-enhance-step', 'plus');
        input.disabled = this._busy || (this._readPending && this._previewPendingOperation !== 'enhance') || current >= max;
        minus.disabled = input.disabled || target <= current + 1;
        plus.disabled = input.disabled || target >= max;
        setCapability(input, 'number', current >= max);
        setCapability(minus, 'stepper', target <= current + 1);
        setCapability(plus, 'stepper', target >= max);
        stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
        var slider = element('input', 'equipment-tuning-level-slider');
        slider.type = 'range'; slider.min = String(Math.min(max, current + 1)); slider.max = String(max); slider.step = '1'; slider.value = String(target);
        slider.setAttribute('data-browser-native', '1');
        slider.setAttribute('data-tuning-focus-key', 'enhance:range');
        slider.disabled = input.disabled;
        setCapability(slider, 'range', current >= max);
        slider.addEventListener('change', function() {
            self._chooseEnhancementLevel(slider.value, 'range');
        });
        var controls = element('div', 'equipment-tuning-level-controls');
        controls.appendChild(stepper); controls.appendChild(slider);
        panel.appendChild(controls);
        var marks = element('div', 'equipment-tuning-level-marks');
        for (var level = current + 1; level <= max; level++) {
            (function(markLevel) {
                var mark = element('button', 'equipment-tuning-level-mark' + (markLevel === target ? ' active' : ''));
                mark.type = 'button'; mark.textContent = String(markLevel); mark.disabled = input.disabled;
                mark.setAttribute('data-enhance-level', String(markLevel));
                mark.setAttribute('data-tuning-focus-key', 'enhance-level:' + markLevel);
                setCapability(mark, 'mark', false);
                mark.addEventListener('click', function() {
                    self._chooseEnhancementLevel(markLevel, 'mark');
                });
                mark.addEventListener('focus', function() {
                    self._setInfoSubject({
                        candidateKey:'enhance:' + markLevel,
                        itemName:'强化至 +' + markLevel,
                        gradeLabel:'当前 +' + current,
                        scopeLabel:'可用上限 +' + max,
                        roleLabel:'先预览材料与结果，再提交'
                    });
                });
                marks.appendChild(mark);
            })(level);
        }
        panel.appendChild(marks);
        var cap = actionButton('升至当前上限 +' + max, function() {
            self._chooseEnhancementLevel(max, 'cap');
        });
        cap.classList.add('equipment-tuning-level-cap'); cap.disabled = input.disabled || target >= max;
        setCapability(cap, 'cap', target >= max);
        panel.appendChild(cap);
        body.appendChild(panel);
    };

    TuningView.prototype._chooseEnhancementLevel = function(level, capability) {
        capability = capability || 'stepper';
        if (!this._snapshot || !this._allowInteraction(capability)) return false;
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || 0), max = Math.min(
            enhancementAvailableMax(this._snapshot), enhancementHardMax(this._snapshot));
        level = Math.max(current + 1, Math.min(max, Math.floor(Number(level))));
        if (!isFinite(level) || current >= max) return false;
        this._previewFocusIntent = null;
        this._targetLevel = level;
        this._preview = null;
        var scheduled = this.scheduleEnhancementPreview(level, 160);
        this.render({previewOnly:true});
        return scheduled;
    };

    TuningView.prototype._renderConvert = function(body) {
        var self = this;
        var pair = element('div', 'equipment-tuning-convert-pair');
        pair.appendChild(conversionEquipmentCard(this._sourceItem, '当前装备'));
        var arrow = element('div', 'equipment-tuning-convert-arrow');
        arrow.textContent = '↔'; arrow.setAttribute('aria-hidden', 'true'); pair.appendChild(arrow);
        pair.appendChild(conversionEquipmentCard(
            this._targetItem,
            this._targetItem ? '交换目标' : '等待选择',
            true,
            this._targetItem ? function() { self.inspectConversionTarget(); } : null,
            !this._canInspect(this._targetItem)
        ));
        body.appendChild(pair);

        var heading = element('div', 'equipment-tuning-conversion-heading');
        heading.innerHTML = '<b>可交换装备</b><span>' + (this._conversionLoading ? '同步中'
            : this._conversionCandidates.length + ' 件') + '</span>';
        body.appendChild(heading);

        if (this._conversionLoading) {
            body.appendChild(empty('正在读取同类装备，不会改变左侧背包筛选。'));
        } else if (this._conversionError) {
            body.appendChild(empty(this._conversionError));
            var retrySelf = this;
            var retry = actionButton('重新读取候选', function() {
                if (retrySelf._allowInteraction('conversionCandidate')) {
                    retrySelf._setConversionProjection(true);
                }
            });
            setCapability(retry, 'conversionCandidate', false);
            retry.classList.add('equipment-tuning-conversion-retry'); body.appendChild(retry);
        } else if (!this._conversionCandidates.length) {
            body.appendChild(empty('背包中没有强化度不同的其他同类装备。'));
        } else {
            var grid = element('div', 'equipment-tuning-conversion-candidates');
            this._conversionCandidates.forEach(function(slot) {
                var item = slot.item || {};
                var selected = self._target && sameRef(self._target, wireRef(slot));
                var button = element('button', 'equipment-tuning-conversion-card' + (selected ? ' selected' : ''));
                button.type = 'button';
                button.setAttribute('data-physical-slot', String(slot.physicalSlot));
                button.setAttribute('data-tuning-focus-key', 'conversion:'
                    + String(slot.physicalSlot) + ':' + String(slot.slotLease || ''));
                button.setAttribute('aria-pressed', selected ? 'true' : 'false');
                button.setAttribute('aria-label', String(item.displayName || item.name || '装备')
                    + '，强化 +' + Number(item.enhancementLevel || 0));
                button.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon')
                    + '<span class="equipment-tuning-conversion-copy"><b>'
                    + escapeHtml(item.displayName || item.name || '未知装备') + '</b><small>'
                    + escapeHtml(item.use || '同类装备') + ' · 强化 +' + Number(item.enhancementLevel || 0)
                    + '</small></span><i class="equipment-tuning-conversion-level">+'
                    + Number(item.enhancementLevel || 0) + '</i>';
                button.addEventListener('click', function() { self.selectConversionTarget(slot); });
                setCapability(button, 'conversionCandidate', false);
                grid.appendChild(button);
            });
            body.appendChild(grid);
        }
        var hint = element('p', 'equipment-tuning-hint');
        hint.textContent = '这里仅列出背包中的同类装备，不会改变左侧的筛选与排序。'; body.appendChild(hint);
    };

    TuningView.prototype._renderCandidates = function(body, candidates, operation) {
        var list = element('div', 'equipment-tuning-candidates');
        var self = this;
        if (!candidates.length) { body.appendChild(empty('当前装备没有可用候选。')); return; }
        candidates.forEach(function(candidate) {
            var button = element('button', 'equipment-tuning-candidate' + (candidate.available ? ' available' : ' blocked'));
            button.type = 'button'; button.disabled = self._busy || self._readPending || self._needsReconcile;
            button.setAttribute('aria-disabled', candidate.available ? 'false' : 'true');
            button.setAttribute('data-grade', String(candidate.grade || 'unknown'));
            button.setAttribute('data-scope', String(candidate.scope || 'unknown'));
            button.setAttribute('data-role', String(candidate.role || 'utility'));
            button.setAttribute(
                'data-candidate-key',
                String(candidate.candidateKey || '')
            );
            button.setAttribute('data-tuning-focus-key', 'candidate:'
                + String(candidate.candidateKey || ''));
            button.setAttribute(
                'data-tuning-disabled-reason',
                candidate.available ? '' : String(candidate.reason || '当前候选不可用。')
            );
            setCapability(
                button,
                operation === 'install_tier' ? 'tier' : 'candidate',
                !candidate.available,
                true
            );
            button.setAttribute('aria-label', String(candidate.itemName || candidate.candidateKey) + '，持有 '
                + Number(candidate.owned || 0) + '，' + String(candidate.gradeLabel || candidate.tierName || '未分类')
                + (candidate.scopeLabel ? '，' + String(candidate.scopeLabel) : '')
                + (candidate.roleLabel ? '，' + String(candidate.roleLabel) : '')
                + (candidate.reason ? '，' + String(candidate.reason) : ''));
            if (candidate.gradeColor) button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
            var owned = Math.max(0, Math.floor(Number(candidate.owned) || 0));
            button.innerHTML = iconHtml(candidate.itemName || candidate.candidateKey, 'kshop-icon')
                + '<i class="equipment-tuning-role-glyph inventory-mod-glyph symbol-'
                + normalizeModSymbol(candidate.symbol) + '" aria-hidden="true"></i>'
                + (owned > 1 ? '<span class="inventory-slot-value quantity equipment-tuning-owned-count" aria-label="持有数量 '
                    + exactQuantity(owned) + '">'
                    + compactQuantity(owned) + '</span>' : '')
                + '<span><b>' + escapeHtml(candidate.itemName || candidate.candidateKey) + '</b><small>持有 '
                + owned + ' · ' + escapeHtml(candidate.gradeLabel || candidate.tierName || '未分类')
                + (candidate.scopeLabel ? ' · ' + escapeHtml(candidate.scopeLabel) : '')
                + (candidate.roleLabel ? ' · ' + escapeHtml(candidate.roleLabel) : '')
                + (candidate.reason ? ' · ' + escapeHtml(candidate.reason) : '') + '</small></span>';
            button.addEventListener('click', function() {
                var capability = operation === 'install_tier' ? 'tier' : 'candidate';
                if (!self._allowInteraction(capability)) return;
                if (candidate.available) self.requestPreview(operation, {
                    candidateKey:candidate.candidateKey,
                    candidateName:candidate.itemName,
                    replaceCandidateKey:self._replaceCandidateKey,
                    replaceCandidateName:self._replaceCandidateName,
                    quickCommit:self._modConfirmationMode === 'fast'
                });
                else self._toast(String(candidate.reason || '当前候选不可用。'));
            });
            self._bindCandidateTooltip(button, candidate);
            list.appendChild(button);
        });
        body.appendChild(list);
    };

    TuningView.prototype._bindCandidateTooltip = function(node, candidate) {
        if (node && candidate) {
            var infoSelf = this;
            node.addEventListener('focus', function() { infoSelf._setInfoSubject(candidate); });
        }
        if (!node || !candidate || !candidate.candidateKey || typeof PanelTooltip === 'undefined'
                || !PanelTooltip || typeof PanelTooltip.bindAsyncHover !== 'function') return;
        var self = this;
        var tooltipBinder = this._tooltipScope || PanelTooltip;
        tooltipBinder.bindAsyncHover(node, {
            cache:this._tooltipCache,
            key:'equipment-tuning:' + this._viewSessionId + ':'
                + tuningSourceKey(this._source) + ':' + String(candidate.candidateKey),
            item:candidate,
            isSuppressed:function() { return self._busy || !self._mux.debugState().active; },
            renderBasic:function(value) {
                return '<div class="kshop-tt-header"><b>' + escapeHtml(value.itemName || value.candidateKey)
                    + '</b></div><div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(value, rich) {
                var introHtml = rich && rich.introHTML ? String(rich.introHTML) : '';
                var descHtml = rich && rich.descHTML ? String(rich.descHTML) : '';
                var textHtml = escapeHtml(rich && rich.text || '');
                if (!PanelTooltip.buildItemRichHtml) {
                    var combinedHtml = introHtml + descHtml;
                    return combinedHtml && PanelTooltip.convertAS2Html
                        ? PanelTooltip.convertAS2Html(combinedHtml) : (combinedHtml || textHtml);
                }
                var options = {
                    iconHtml:PanelTooltip.dynamicIconHtml ? PanelTooltip.dynamicIconHtml(value.itemName) : '',
                    iconUrl:PanelTooltip.staticIconUrl ? PanelTooltip.staticIconUrl(value.itemName) : '',
                    descHTML:descHtml,
                    rootClass:'equipment-tuning-tooltip',
                    layoutType:PanelTooltip.inferLayoutType
                        ? PanelTooltip.inferLayoutType(rich && (rich.itemType || rich.itemUse) || 'material') : ''
                };
                if (introHtml) options.introHTML = introHtml;
                else options.introWebHTML = textHtml;
                return PanelTooltip.buildItemRichHtml(options);
            },
            fetch:function(value, callback) {
                self._mux.request('tooltip', {candidateKey:String(value.candidateKey)}, callback);
            }
        });
    };

    TuningView.prototype._renderMods = function(body) {
        var equipment = this._snapshot.equipment || {};
        var installed = equipment.mods instanceof Array ? equipment.mods : [];
        var candidates = this._snapshot.modCandidates || [];
        var replacementKey = this._replaceCandidateKey;
        var replacementMode = !!replacementKey;
        var capacityProjection =
            modSlotCapacityProjection(equipment, installed.length);
        var capacity = capacityProjection.value;
        var visibleSlotCount = capacityProjection.state === 'known'
            ? capacity : installed.length;
        if (visibleSlotCount || capacityProjection.state !== 'absent') {
            var heading = element('h3', 'equipment-tuning-section-title');
            heading.textContent = replacementMode
                ? '插件槽 · 已选择待替换配件'
                : capacityProjection.state === 'known'
                    ? (capacity === 0
                        ? '插件槽 · 无插件槽'
                        : '插件槽 ' + installed.length + '/' + capacity
                            + ' · 点击已装替换，点击空槽安装')
                    : capacityProjection.state === 'malformed'
                        ? '插件槽 · 容量未知，仅显示已安装配件'
                        : '插件槽 · 仅显示已安装配件';
            body.appendChild(heading);
            var installedList = element('div', 'equipment-tuning-installed');
            installedList.setAttribute('data-slot-surface', 'operation');
            installedList.setAttribute('role', 'group');
            installedList.setAttribute(
                'aria-label',
                capacityProjection.state === 'known'
                    ? (capacity === 0
                        ? '这件装备没有插件槽'
                        : '插件槽：已用 ' + installed.length + '，共 ' + capacity
                            + '；已安装槽可替换或卸下，空槽可选择安装')
                    : capacityProjection.state === 'malformed'
                        ? '插件槽容量未知；仅显示已安装配件'
                        : '仅显示已安装配件'
            );
            if (capacityProjection.state === 'known') {
                installedList.setAttribute('data-mod-slot-capacity', String(capacity));
                installedList.setAttribute('data-mod-slot-used', String(installed.length));
            } else if (capacityProjection.state === 'malformed') {
                installedList.setAttribute('data-mod-slot-capacity-state', 'unknown');
            }
            var self = this;
            installed.forEach(function(name, slotIndex) {
                var candidate = candidateForItem(candidates, name);
                var candidateKey = candidate && candidate.candidateKey;
                var selected = candidateKey && candidateKey === replacementKey;
                var entry = element('div', 'equipment-tuning-installed-entry');
                entry.setAttribute('data-mod-slot-index', String(slotIndex));
                entry.setAttribute('data-mod-slot-state', 'installed');
                entry.setAttribute(
                    'data-candidate-key',
                    String(candidateKey || '')
                );
                var button = element('button', 'equipment-tuning-installed-card equipment-tuning-detach grade-'
                    + String(candidate && candidate.grade || 'unknown') + (selected ? ' selected' : ''));
                button.type = 'button';
                button.setAttribute('data-mod-slot-index', String(slotIndex));
                button.setAttribute(
                    'data-candidate-key',
                    String(candidateKey || '')
                );
                button.setAttribute('data-tuning-focus-key', 'operation-installed-mod:'
                    + slotIndex + ':' + String(candidateKey || name));
                button.setAttribute(
                    'aria-label',
                    '插件槽 ' + (slotIndex + 1) + '：' + String(name)
                        + '，点击选择替换'
                );
                button.setAttribute('aria-pressed', selected ? 'true' : 'false');
                if (candidate && candidate.gradeColor) {
                    button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
                }
                button.innerHTML = iconHtml(name, 'kshop-icon')
                    + '<span><b>' + escapeHtml(name) + '</b><small>'
                    + escapeHtml(candidate && candidate.gradeLabel || '已安装')
                    + (candidate && candidate.roleLabel ? ' · ' + escapeHtml(candidate.roleLabel) : '') + '</small></span>'
                    + '<i class="equipment-tuning-role-glyph inventory-mod-glyph symbol-'
                    + normalizeModSymbol(candidate && candidate.symbol) + '" aria-hidden="true"></i>';
                button.addEventListener('click', function() {
                    if (!candidateKey) return;
                    if (selected) self._clearReplacementCandidate();
                    else self._selectReplacementCandidate(candidate);
                });
                button.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
                setCapability(button, 'slot', !candidateKey);
                if (candidate) self._bindCandidateTooltip(button, candidate);
                entry.appendChild(button);
                var detach = element('button', 'equipment-tuning-installed-quick-detach');
                detach.type = 'button';
                detach.textContent = '×';
                detach.setAttribute('aria-label', '卸下配件：' + String(name));
                detach.setAttribute('data-title', '卸下：' + String(name));
                detach.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
                setCapability(detach, 'detach', !candidateKey);
                detach.addEventListener('click', function(event) {
                    event.stopPropagation();
                    self.requestPreview('detach_mod', {
                        candidateKey:candidateKey,
                        candidateName:String(name),
                        quickCommit:self._modConfirmationMode === 'fast'
                    });
                });
                entry.appendChild(detach);
                installedList.appendChild(entry);
            });
            if (capacityProjection.state === 'known') {
                for (var slotIndex = installed.length; slotIndex < capacity; slotIndex++) {
                    var emptyEntry = element(
                        'div',
                        'equipment-tuning-installed-entry empty'
                    );
                    emptyEntry.setAttribute('data-mod-slot-index', String(slotIndex));
                    emptyEntry.setAttribute('data-mod-slot-state', 'empty');
                    var emptyButton = element(
                        'button',
                        'equipment-tuning-installed-empty'
                    );
                    emptyButton.type = 'button';
                    emptyButton.setAttribute('data-mod-slot-index', String(slotIndex));
                    emptyButton.setAttribute(
                        'data-tuning-focus-key',
                        'empty-mod-slot:' + String(slotIndex)
                    );
                    emptyButton.setAttribute(
                        'aria-label',
                        '插件槽 ' + (slotIndex + 1) + '：空，点击选择要安装的配件'
                    );
                    emptyButton.innerHTML =
                        '<span class="equipment-tuning-installed-empty-glyph" aria-hidden="true">'
                            + '<i></i></span>'
                            + '<span class="equipment-tuning-installed-empty-copy">'
                            + '<b>空插件槽</b><small>点击选择配件</small></span>';
                    emptyButton.disabled =
                        self._busy || self._readPending || self._needsReconcile;
                    setCapability(emptyButton, 'slot', false);
                    emptyButton.addEventListener('click', (function(index) {
                        return function() { self._selectEmptyModSlot(index); };
                    })(slotIndex));
                    emptyEntry.appendChild(emptyButton);
                    installedList.appendChild(emptyEntry);
                }
            }
            var installedRail = element(
                'div',
                'equipment-tuning-installed-rail'
            );
            installedRail.appendChild(installedList);
            if (installed.length) {
                var installedActions = element(
                    'div',
                    'equipment-tuning-installed-actions'
                );
                installedActions.setAttribute('role', 'group');
                installedActions.setAttribute('aria-label', '插件批量操作');
                installedActions.setAttribute(
                    'data-tuning-command-surface',
                    'plugin-batch'
                );
                var all = actionButton('卸下全部', function() {
                    self.requestPreview('detach_all_mods');
                });
                all.classList.add('danger', 'equipment-tuning-detach-all');
                all.setAttribute('aria-label','卸下全部已安装配件');
                all.setAttribute('data-title','卸下全部已安装配件');
                all.disabled = self._busy || self._readPending || self._needsReconcile;
                setCapability(all, 'detach', false);
                installedActions.appendChild(all);
                installedRail.appendChild(installedActions);
            }
            body.appendChild(installedRail);
        }
        var title = element('h3', 'equipment-tuning-section-title');
        title.textContent = replacementMode ? '选择替换配件' : '可安装配件';
        body.appendChild(title);
        var availableCandidates = candidates.filter(function(candidate) { return candidate.installed !== true; }).map(function(candidate) {
            if (!replacementMode) return candidate;
            var projected = {};
            for (var key in candidate) projected[key] = candidate[key];
            var replaceableFrom = candidate.replaceableFrom instanceof Array ? candidate.replaceableFrom : [];
            projected.available = Number(candidate.owned || 0) > 0 && replaceableFrom.indexOf(replacementKey) >= 0;
            projected.reason = projected.available ? ''
                : (Number(candidate.owned || 0) <= 0 ? 'material_missing' : '不能替换所选配件');
            return projected;
        });
        if (typeof ItemFilter !== 'undefined' && ItemFilter.FilterNavigator) {
            var filter = element('section', 'equipment-tuning-mod-filter');
            var breadcrumb = element('div', 'equipment-tuning-mod-breadcrumb');
            filter.appendChild(breadcrumb);
            var self = this;
            this._modNavigator = new ItemFilter.FilterNavigator({
                tree:buildModFilterTree(availableCandidates), path:this._modFilterPath,
                presentation:'drilldown', allLabel:'全部配件', ariaLabel:'配件分类筛选',
                visualStyle:'catalog', autoDescendSingle:false, breadcrumbHost:breadcrumb,
                onChange:function(path) { self._modFilterPath = path.slice(); self.render({preserveScroll:false}); }
            });
            this._modNavigator.root.classList.add('equipment-tuning-mod-navigator');
            filter.appendChild(this._modNavigator.root); body.appendChild(filter);
            availableCandidates = availableCandidates.filter(function(candidate) {
                return modMatchesFilter(candidate, self._modFilterPath);
            });
        }
        var count = element('p', 'equipment-tuning-filter-count');
        count.textContent = '显示 ' + availableCandidates.length + ' / ' + candidates.filter(function(candidate) { return candidate.installed !== true; }).length;
        body.appendChild(count);
        this._renderCandidates(body, availableCandidates, replacementMode ? 'replace_mod' : 'install_mod');
    };

    TuningView.prototype._renderPreview = function() {
        var section = element('section', 'equipment-tuning-preview');
        return this._updatePreviewSection(section);
    };

    TuningView.prototype._updatePreviewSection = function(section) {
        clear(section);
        section.className = 'equipment-tuning-preview';
        section.hidden = false;
        if (!this._preview) {
            section.classList.add('is-empty');
            if (this._operation === 'enhance') {
                section.classList.add('enhance-compact');
                section.hidden = true;
            }
            section.appendChild(empty(this._needsReconcile ? '上次提交结果未知，必须完成权威对账。'
                : (this._operation === 'enhance'
                    ? (this._readPending ? '正在计算强化消耗…' : '选择目标强化度后确认。')
                    : '选择操作后在此确认材料与结果。')));
            return section;
        }
        var compactEnhance = this._preview.operation === 'enhance';
        if (compactEnhance) {
            section.classList.add('enhance-compact');
            section.hidden = true;
        } else {
            var heading = element('div', 'equipment-tuning-preview-heading');
            heading.innerHTML = '<b>' + operationLabel(this._preview.operation) + '</b><span>'
                + (this._preview.noOp ? '无需变更' : (this._preview.tuningToken ? '材料与结果已确认' : '条件不满足')) + '</span>';
            section.appendChild(heading);
            var equipmentDelta = renderEquipmentDelta(this._preview.before, this._preview.after);
            if (equipmentDelta) section.appendChild(equipmentDelta);
            var materials = this._preview.materials || [];
            if (materials.length) {
                var list = element('div', 'equipment-tuning-material-deltas');
                materials.forEach(function(material) {
                    var row = element('div', 'equipment-tuning-material-delta');
                    var materialName = String(material.itemName || '');
                    row.innerHTML = '<span class="equipment-tuning-material-label">'
                        + materialIconHtml(materialName, 'equipment-tuning-material-icon', true)
                        + '<em>' + escapeHtml(materialName) + '</em></span><b>'
                        + Number(material.before || 0) + (Number(material.delta || 0) >= 0 ? ' +' : ' ')
                        + Number(material.delta || 0) + ' → ' + Number(material.after || 0) + '</b>';
                    list.appendChild(row);
                });
                section.appendChild(list);
            }
            if (this._preview.removedMods && this._preview.removedMods.length) {
                var removed = element('p', 'equipment-tuning-removed');
                removed.textContent = '将返还：' + this._preview.removedMods.join('、'); section.appendChild(removed);
            }
        }
        return section;
    };


    function setIntrinsicDisabled(node, disabled) {
        if (!node || !node.setAttribute) return node;
        node.setAttribute('data-tuning-intrinsic-disabled', disabled ? 'true' : 'false');
        return node;
    }

    function setCapability(node, capability, intrinsicDisabled, explainDisabled) {
        if (!node || !node.setAttribute) return node;
        node.setAttribute('data-tuning-capability', String(capability || ''));
        if (explainDisabled) node.setAttribute('data-tuning-explain-disabled', 'true');
        else node.removeAttribute('data-tuning-explain-disabled');
        return setIntrinsicDisabled(node, !!intrinsicDisabled);
    }

    function conversionEquipmentCard(item, label, emptyTarget, onInspect, inspectDisabled) {
        var card = element('div', 'equipment-tuning-convert-item' + (!item ? ' empty' : ''));
        if (!item) {
            card.innerHTML = '<div class="equipment-tuning-empty-mark">?</div><span><small>'
                + escapeHtml(label || '等待选择') + '</small><b>'
                + (emptyTarget ? '从下方选择目标' : '未选择装备') + '</b></span>';
            return card;
        }
        card.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon')
            + '<span><small>' + escapeHtml(label || '装备') + '</small><b>'
            + escapeHtml(item.displayName || item.name || '未知装备') + '</b><em>强化 +'
            + Number(item.enhancementLevel || 0) + '</em></span>';
        if (typeof onInspect === 'function') {
            card.classList.add('inspectable');
            var inspect = element('button', 'equipment-tuning-convert-inspect');
            inspect.type = 'button';
            inspect.textContent = '⌕';
            inspect.disabled = !!inspectDisabled;
            setCapability(inspect, 'inspect', !!inspectDisabled);
            inspect.setAttribute('aria-label', '检视交换目标：' + String(item.displayName || item.name || '装备'));
            inspect.addEventListener('click', function(event) {
                event.preventDefault();
                event.stopPropagation();
                onInspect();
            });
            card.appendChild(inspect);
        }
        return card;
    }

    function element(tag, className) { var node = document.createElement(tag); if (className) node.className = className; return node; }
    function clear(node, tooltipScope) {
        if (tooltipScope && typeof tooltipScope.releaseTree === 'function') tooltipScope.releaseTree(node);
        else if (typeof PanelTooltip !== 'undefined' && PanelTooltip.releaseTree) PanelTooltip.releaseTree(node);
        while (node && node.firstChild) node.removeChild(node.firstChild);
    }
    function empty(text) { var node = element('div', 'equipment-tuning-empty'); node.textContent = text || ''; return node; }
    function actionButton(text, handler) { var button = element('button', 'equipment-tuning-action'); button.type = 'button'; button.textContent = text; if (handler) button.addEventListener('click', handler); return button; }
    function iconHtml(name, cls) {
        var html = typeof Icons !== 'undefined' && Icons.html ? Icons.html(name, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return html || '<span class="kshop-icon-placeholder"></span>';
    }
    function materialIconHtml(name, cls, staticOnly) {
        if (staticOnly && typeof Icons !== 'undefined' && Icons.resolveStatic) {
            var url = Icons.resolveStatic(name);
            if (url) return '<img class="' + escapeHtml(cls || 'kshop-icon') + '" src="'
                + escapeHtml(url) + '" data-icon-name="' + escapeHtml(name)
                + '" data-icon-static="1" alt="">';
        }
        return iconHtml(name, cls);
    }
    function prefersReducedMotion() {
        return typeof window !== 'undefined' && window.matchMedia
            && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }

    function renderEquipmentDelta(before, after) {
        before = before || {}; after = after || {};
        var keys = ['source','target'];
        var list = element('div', 'equipment-tuning-equipment-deltas');
        var count = 0;
        for (var i = 0; i < keys.length; i++) {
            var left = before[keys[i]] && before[keys[i]].equipment;
            var right = after[keys[i]] && after[keys[i]].equipment;
            if (!left || !right) continue;
            var diff = equipmentDiff(left, right);
            if (!diff) continue;
            var row = element('div', 'equipment-tuning-equipment-delta');
            var name = right.displayName || right.name || left.displayName || left.name || (keys[i] === 'source' ? '主装备' : '目标装备');
            row.innerHTML = '<b>' + escapeHtml(name) + '</b><span>' + escapeHtml(diff) + '</span>';
            list.appendChild(row); count++;
        }
        return count ? list : null;
    }

        return TuningView;
    }

    return {install:install};
})();
