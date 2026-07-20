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
        var compactQuantity = Model.compactQuantity;
        var normalizeModSymbol = Model.normalizeModSymbol;
        var buildModFilterTree = Model.buildModFilterTree;
        var modMatchesFilter = Model.modMatchesFilter;
        var commitLabel = Model.commitLabel;
        var equipmentDiff = Model.equipmentDiff;
        var errorMessage = Model.errorMessage;

    TuningView.prototype.render = function(renderOptions) {
        if (!this._root) return;
        renderOptions = renderOptions || {};
        var preserveScroll = renderOptions.preserveScroll !== false;
        var previousBody = this._root.querySelector('.equipment-tuning-body');
        var previousPreview = this._root.querySelector('.equipment-tuning-preview');
        var bodyScroll = preserveScroll && previousBody ? {top:previousBody.scrollTop,left:previousBody.scrollLeft} : null;
        var previewScroll = preserveScroll && previousPreview ? {top:previousPreview.scrollTop,left:previousPreview.scrollLeft} : null;
        if (this._modNavigator) { this._modNavigator.destroy(); this._modNavigator = null; }
        clear(this._root);
        var root = element('div', 'equipment-tuning-view');
        root.setAttribute('data-operation', this._operation === 'replace_mod' ? 'install_mod' : this._operation);
        root.setAttribute('data-reconcile', this._needsReconcile ? 'required' : 'clear');
        root.appendChild(this._renderHeader());
        root.appendChild(this._renderTabs());
        root.appendChild(this._renderBody());
        root.appendChild(this._renderPreview());
        this._root.appendChild(root);
        var nextBody = root.querySelector('.equipment-tuning-body');
        var nextPreview = root.querySelector('.equipment-tuning-preview');
        if (bodyScroll && nextBody) { nextBody.scrollTop = bodyScroll.top; nextBody.scrollLeft = bodyScroll.left; }
        if (previewScroll && nextPreview) { nextPreview.scrollTop = previewScroll.top; nextPreview.scrollLeft = previewScroll.left; }
    };

    TuningView.prototype._renderHeader = function() {
        var header = element('section', 'equipment-tuning-summary');
        if (!this._sourceItem) {
            var emptyMark = element('div', 'equipment-tuning-empty-mark'); emptyMark.textContent = '＋';
            var emptyCopy = element('div', 'equipment-tuning-summary-copy');
            emptyCopy.innerHTML = '<b>选择背包装备</b><small>仅背包内武器与防具可调制</small>';
            header.appendChild(emptyMark); header.appendChild(emptyCopy);
            return header;
        }
        var item = this._sourceItem;
        var self = this;
        var icon = element('button', 'equipment-tuning-main-icon equipment-tuning-inspect-trigger');
        icon.type = 'button';
        icon.disabled = !this._canInspect(item);
        icon.setAttribute('aria-label', '检视当前装备：' + String(item.displayName || item.name || '装备'));
        icon.innerHTML = iconHtml(item.icon || item.name, 'kshop-icon');
        icon.addEventListener('click', function() { self.inspectCurrentEquipment(); });
        var copy = element('div', 'equipment-tuning-main-copy equipment-tuning-summary-copy');
        var equipment = this._snapshot && this._snapshot.equipment;
        var level = equipment ? Number(equipment.level || 0) : Number(item.enhancementLevel || 0);
        copy.innerHTML = '<b>' + escapeHtml(item.displayName || item.name) + '</b>'
            + '<span>强化 +' + level + (equipment && equipment.tier ? ' · ' + escapeHtml(equipment.tier) : '') + '</span>'
            + '<small>' + escapeHtml(this._status) + '</small>';
        header.appendChild(icon);
        header.appendChild(copy);
        var installedState = this._renderInstalledState(equipment);
        if (installedState.childNodes.length) header.appendChild(installedState);
        return header;
    };

    TuningView.prototype._renderInstalledState = function(equipment) {
        var state = element('div', 'equipment-tuning-installed-state');
        if (!equipment) return state;
        var self = this;
        var tierName = String(equipment.tier || '');
        var tierCandidate = candidateForTier(this._snapshot && this._snapshot.tierCandidates, tierName);
        if (tierName) {
            var tier = element('button', 'equipment-tuning-status-icon tier');
            tier.type = 'button';
            tier.setAttribute('aria-label', '当前进阶：' + tierName + '，点击查看进阶');
            tier.innerHTML = iconHtml(tierCandidate && tierCandidate.itemName || tierName, 'kshop-icon')
                + '<span class="equipment-tuning-status-mark" aria-hidden="true">阶</span>';
            tier.addEventListener('click', function() { self.setOperation('install_tier'); });
            if (tierCandidate) this._bindCandidateTooltip(tier, tierCandidate);
            state.appendChild(tier);
        }
        var candidates = this._snapshot && this._snapshot.modCandidates || [];
        var installed = equipment.mods instanceof Array ? equipment.mods : [];
        installed.forEach(function(name) {
            var candidate = candidateForItem(candidates, name);
            var button = element('button', 'equipment-tuning-status-icon mod grade-'
                + String(candidate && candidate.grade || 'unknown'));
            button.type = 'button';
            button.setAttribute('aria-label', '已安装配件：' + String(name) + '，点击选择替换');
            if (candidate && candidate.gradeColor) {
                button.style.setProperty('--equipment-mod-grade-color', String(candidate.gradeColor));
            }
            button.innerHTML = iconHtml(name, 'kshop-icon')
                + '<i class="equipment-tuning-status-role inventory-mod-glyph symbol-'
                + normalizeModSymbol(candidate && candidate.symbol) + '" aria-hidden="true"></i>';
            button.disabled = self._busy || self._readPending || self._needsReconcile
                || !candidate || !candidate.candidateKey;
            button.addEventListener('click', function() {
                if (candidate && candidate.candidateKey) {
                    self._selectReplacementCandidate(candidate);
                }
            });
            if (candidate) self._bindCandidateTooltip(button, candidate);
            state.appendChild(button);
        });
        return state;
    };

    TuningView.prototype._renderTabs = function() {
        var tabs = element('nav', 'equipment-tuning-tabs');
        var self = this;
        [['enhance','强化度'],['convert','交换'],['install_tier','进阶'],['install_mod','配件']].forEach(function(pair) {
            var button = element('button', 'equipment-tuning-tab' + (self._operation === pair[0]
                || (pair[0] === 'install_mod' && (self._operation === 'replace_mod'
                    || self._operation === 'detach_mod' || self._operation === 'detach_all_mods')) ? ' active' : ''));
            button.type = 'button'; button.textContent = pair[1]; button.disabled = self._busy || self._readPending;
            button.addEventListener('click', function() { self.setOperation(pair[0]); });
            tabs.appendChild(button);
        });
        return tabs;
    };

    TuningView.prototype._renderBody = function() {
        var body = element('section', 'equipment-tuning-body');
        if (this._refreshRetryRequired) {
            var refreshRetry = element('button', 'equipment-tuning-retry');
            refreshRetry.type = 'button';
            refreshRetry.textContent = this._refreshRetryPending ? '正在重试刷新…' : '重试背包刷新';
            refreshRetry.disabled = this._refreshRetryPending;
            var refreshSelf = this;
            refreshRetry.addEventListener('click', function() { refreshSelf.retryInventoryRefresh(); });
            body.appendChild(empty(this._status));
            body.appendChild(refreshRetry);
            return body;
        }
        if (!this._source) { body.appendChild(empty('从左侧选择一件装备后，Flash 会返回权威候选。')); return body; }
        if (!this._snapshot) {
            var retry = element('button', 'equipment-tuning-retry'); retry.type = 'button';
            retry.textContent = this._needsReconcile ? '重新对账' : '重试同步';
            var self = this; retry.addEventListener('click', function() { self.requestSnapshot(self._lastCommitCallId); });
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
        var minus = actionButton('−', function() { self._chooseEnhancementLevel(target - 1); });
        minus.classList.add('equipment-tuning-level-step');
        var input = element('input', 'equipment-tuning-level-input');
        input.type = 'number'; input.min = String(Math.min(max, current + 1)); input.max = String(max); input.value = String(target);
        input.setAttribute('data-browser-native', '1');
        input.addEventListener('change', function() { self._chooseEnhancementLevel(input.value); });
        var plus = actionButton('+', function() { self._chooseEnhancementLevel(target + 1); });
        plus.classList.add('equipment-tuning-level-step');
        input.disabled = this._busy || (this._readPending && this._previewPendingOperation !== 'enhance') || current >= max;
        minus.disabled = input.disabled || target <= current + 1;
        plus.disabled = input.disabled || target >= max;
        stepper.appendChild(minus); stepper.appendChild(input); stepper.appendChild(plus);
        var slider = element('input', 'equipment-tuning-level-slider');
        slider.type = 'range'; slider.min = String(Math.min(max, current + 1)); slider.max = String(max); slider.step = '1'; slider.value = String(target);
        slider.setAttribute('data-browser-native', '1');
        slider.disabled = input.disabled;
        slider.addEventListener('change', function() { self._chooseEnhancementLevel(slider.value); });
        var controls = element('div', 'equipment-tuning-level-controls');
        controls.appendChild(stepper); controls.appendChild(slider);
        panel.appendChild(controls);
        var marks = element('div', 'equipment-tuning-level-marks');
        for (var level = current + 1; level <= max; level++) {
            (function(markLevel) {
                var mark = element('button', 'equipment-tuning-level-mark' + (markLevel === target ? ' active' : ''));
                mark.type = 'button'; mark.textContent = String(markLevel); mark.disabled = input.disabled;
                mark.addEventListener('click', function() { self._chooseEnhancementLevel(markLevel); });
                marks.appendChild(mark);
            })(level);
        }
        panel.appendChild(marks);
        var cap = actionButton('升至当前上限 +' + max, function() { self._chooseEnhancementLevel(max); });
        cap.classList.add('equipment-tuning-level-cap'); cap.disabled = input.disabled || target >= max; panel.appendChild(cap);
        body.appendChild(panel);
    };

    TuningView.prototype._chooseEnhancementLevel = function(level) {
        if (!this._snapshot || this._busy
                || (this._readPending && this._previewPendingOperation !== 'enhance') || this._needsReconcile) return false;
        var enhance = this._snapshot.enhance || {};
        var current = Number(enhance.currentLevel || 0), max = Math.min(
            enhancementAvailableMax(this._snapshot), enhancementHardMax(this._snapshot));
        level = Math.max(current + 1, Math.min(max, Math.floor(Number(level))));
        if (!isFinite(level) || current >= max) return false;
        this._targetLevel = level;
        this._preview = null;
        this.render();
        return this.scheduleEnhancementPreview(level, 160);
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
            var retry = actionButton('重新读取候选', this._setConversionProjection.bind(this, true));
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
                if (candidate.available) self.requestPreview(operation, {
                    candidateKey:candidate.candidateKey,
                    candidateName:candidate.itemName,
                    replaceCandidateKey:self._replaceCandidateKey,
                    replaceCandidateName:self._replaceCandidateName,
                    quickCommit:self._modConfirmationMode === 'fast'
                });
            });
            self._bindCandidateTooltip(button, candidate);
            list.appendChild(button);
        });
        body.appendChild(list);
    };

    TuningView.prototype._bindCandidateTooltip = function(node, candidate) {
        if (!node || !candidate || !candidate.candidateKey || typeof PanelTooltip === 'undefined'
                || !PanelTooltip || typeof PanelTooltip.bindAsyncHover !== 'function') return;
        var self = this;
        PanelTooltip.bindAsyncHover(node, {
            cache:this._tooltipCache,
            key:'equipment-tuning:' + this._viewSessionId + ':'
                + String(this._source && this._source.expectedLease || '') + ':' + String(candidate.candidateKey),
            item:candidate,
            isSuppressed:function() { return self._busy || !self._mux.debugState().active; },
            renderBasic:function(value) {
                return '<div class="kshop-tt-header"><b>' + escapeHtml(value.itemName || value.candidateKey)
                    + '</b></div><div class="kshop-tt-loading">加载中…</div>';
            },
            renderRich:function(value, rich) {
                var rawHtml = rich && rich.html ? String(rich.html) : '';
                var textHtml = rawHtml ? '' : escapeHtml(rich && rich.text || '');
                if (!PanelTooltip.buildItemRichHtml) {
                    return rawHtml && PanelTooltip.convertAS2Html
                        ? PanelTooltip.convertAS2Html(rawHtml) : (rawHtml || textHtml);
                }
                var options = {
                    iconHtml:PanelTooltip.dynamicIconHtml ? PanelTooltip.dynamicIconHtml(value.itemName) : '',
                    iconUrl:PanelTooltip.staticIconUrl ? PanelTooltip.staticIconUrl(value.itemName) : '',
                    descHTML:rich && rich.descHTML ? String(rich.descHTML) : '',
                    rootClass:'equipment-tuning-tooltip',
                    layoutType:PanelTooltip.inferLayoutType
                        ? PanelTooltip.inferLayoutType(rich && (rich.itemType || rich.itemUse) || 'material') : ''
                };
                if (rich && rich.introHTML) options.introHTML = String(rich.introHTML);
                else if (rawHtml) options.introHTML = rawHtml;
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
        var installed = equipment.mods || [];
        var candidates = this._snapshot.modCandidates || [];
        var replacementKey = this._replaceCandidateKey;
        var replacementMode = !!replacementKey;
        if (installed.length) {
            var heading = element('h3', 'equipment-tuning-section-title');
            heading.textContent = replacementMode ? '已安装 · 已选择待替换配件' : '已安装 · 点击选择替换';
            body.appendChild(heading);
            var installedList = element('div', 'equipment-tuning-installed');
            var self = this;
            installed.forEach(function(name) {
                var candidate = candidateForItem(candidates, name);
                var candidateKey = candidate && candidate.candidateKey;
                var selected = candidateKey && candidateKey === replacementKey;
                var entry = element('div', 'equipment-tuning-installed-entry');
                var button = element('button', 'equipment-tuning-installed-card equipment-tuning-detach grade-'
                    + String(candidate && candidate.grade || 'unknown') + (selected ? ' selected' : ''));
                button.type = 'button';
                button.setAttribute('aria-label', '已安装配件：' + String(name) + '，点击选择替换');
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
                    if (candidateKey) self._selectReplacementCandidate(candidate);
                });
                button.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
                if (candidate) self._bindCandidateTooltip(button, candidate);
                entry.appendChild(button);
                var detach = element('button', 'equipment-tuning-installed-quick-detach');
                detach.type = 'button';
                detach.textContent = '×';
                detach.setAttribute('aria-label', '卸下配件：' + String(name));
                detach.setAttribute('data-title', '卸下：' + String(name));
                detach.disabled = self._busy || self._readPending || self._needsReconcile || !candidateKey;
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
            if (replacementMode) {
                var detachSelected = actionButton('仅卸下所选', function() {
                    self.requestPreview('detach_mod', {
                        candidateKey:replacementKey,
                        candidateName:self._replaceCandidateName,
                        quickCommit:self._modConfirmationMode === 'fast'
                    });
                });
                detachSelected.classList.add('equipment-tuning-detach-selected');
                detachSelected.setAttribute('aria-label','仅卸下所选配件');
                detachSelected.setAttribute('data-title','仅卸下所选配件');
                detachSelected.disabled = self._busy || self._readPending || self._needsReconcile;
                installedList.appendChild(detachSelected);
                var cancelReplacement = actionButton('取消替换', function() { self._clearReplacementCandidate(); });
                cancelReplacement.classList.add('equipment-tuning-replace-cancel');
                cancelReplacement.setAttribute('aria-label','取消替换');
                cancelReplacement.setAttribute('data-title','取消替换');
                cancelReplacement.disabled = self._busy || self._readPending || self._needsReconcile;
                installedList.appendChild(cancelReplacement);
            }
            var all = actionButton('卸下全部', function() { self.requestPreview('detach_all_mods'); });
            all.classList.add('danger', 'equipment-tuning-detach-all');
            all.setAttribute('aria-label','卸下全部配件');
            all.setAttribute('data-title','卸下全部配件');
            all.disabled = self._busy || self._readPending || self._needsReconcile; installedList.appendChild(all);
            body.appendChild(installedList);
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
        if (!this._preview) {
            section.classList.add('is-empty');
            if (this._operation === 'enhance') section.classList.add('enhance-compact');
            section.appendChild(empty(this._needsReconcile ? '上次提交结果未知，必须完成权威对账。'
                : (this._operation === 'enhance'
                    ? (this._readPending ? '正在计算强化消耗…' : '选择目标强化度后确认。')
                    : '选择操作后在此确认材料与结果。')));
            return section;
        }
        var compactEnhance = this._preview.operation === 'enhance';
        if (compactEnhance) {
            section.classList.add('enhance-compact');
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
        var commit = actionButton(this._busy ? '提交中…' : commitLabel(this._preview), this.commit.bind(this));
        commit.classList.add('equipment-tuning-commit');
        commit.disabled = this._busy || this._readPending || this._needsReconcile || !this._preview.tuningToken;
        section.appendChild(commit);
        return section;
    };


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
    function clear(node) { while (node && node.firstChild) node.removeChild(node.firstChild); }
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
