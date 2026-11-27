/**
 * Crafting-only detail presenter.
 *
 * Owns the stable right-pane chrome, scroller, one shared QuantityControl and
 * the fixed CommitBar. Crafting authority, tokens and request ordering remain
 * in crafting.js.
 */
var CraftingDetailPresenter = (function() {
    'use strict';

    function clear(node) {
        while (node && node.firstChild) node.removeChild(node.firstChild);
    }

    function textNode(documentRef, tagName, className, value) {
        var node = documentRef.createElement(tagName);
        if (className) node.className = className;
        node.textContent = value == null ? '' : String(value);
        return node;
    }

    function Presenter(options) {
        options = options || {};
        this._options = options;
        this._document = options.document || document;
        this._destroyed = false;

        this.root = this._document.createElement('div');
        this.root.className = 'workbench-view crafting-detail-view';
        this.chrome = new Workbench.ViewChrome({
            title:'合成详情',
            kicker:'',
            meta:'请选择配方'
        });
        this.scroller = this._document.createElement('div');
        this.scroller.className = 'crafting-detail-body';

        this.empty = textNode(this._document, 'div', 'crafting-detail-empty', '从左侧选择一项配方');
        this.heroHost = this._document.createElement('div');
        this.heroHost.className = 'crafting-detail-hero-host';
        this.quantityPanel = this._document.createElement('section');
        this.quantityPanel.className = 'crafting-quantity-panel';
        this.quantityHeading = this._document.createElement('div');
        this.quantityHeading.className = 'crafting-quantity-heading';
        this.quantityHeading.appendChild(textNode(this._document, 'b', '', '合成份数'));
        this.quantityHint = textNode(this._document, 'small', 'crafting-quantity-hint', '计算中');
        this.quantityHeading.appendChild(this.quantityHint);

        var self = this;
        this.quantity = new WorkbenchComponents.QuantityControl({
            document:this._document,
            className:'workbench-quantity-control crafting-quantity-inputs',
            ariaLabel:'合成份数',
            inputAriaLabel:'输入合成份数',
            rangeAriaLabel:'拖动选择合成份数',
            maxLabel:'最大',
            maxAriaLabel:'设为当前可合成上限',
            showPlusFive:false,
            showMax:true,
            showRange:true,
            onChange:function(value, reason, event) {
                if (typeof self._options.onQuantityChange === 'function') {
                    self._options.onQuantityChange(value, reason, event);
                }
            },
            onDraftChange:function(dirty) {
                if (typeof self._options.onQuantityDraftChange === 'function') {
                    self._options.onQuantityDraftChange(dirty);
                }
            }
        });
        this.quantityPanel.appendChild(this.quantityHeading);
        this.quantityPanel.appendChild(this.quantity.root);

        this.materialHost = this._document.createElement('div');
        this.materialHost.className = 'crafting-detail-material-host';
        this.summaryHost = this._document.createElement('div');
        this.summaryHost.className = 'crafting-detail-summary-host';

        this.scroller.appendChild(this.empty);
        this.scroller.appendChild(this.heroHost);
        this.scroller.appendChild(this.quantityPanel);
        this.scroller.appendChild(this.materialHost);
        this.scroller.appendChild(this.summaryHost);

        this.commitBar = new WorkbenchComponents.CommitBar({
            document:this._document,
            className:'crafting-commit-bar',
            label:'确认合成',
            status:'请先选择配方',
            disabled:true,
            canCommit:false,
            onCommit:function(event) {
                if (typeof self._options.onCommit === 'function') self._options.onCommit(event);
            }
        });
        this.commitBar.statusNode.classList.add('crafting-commit-status');
        this.commitBar.primaryButton.classList.add('crafting-commit-btn');
        this.commitBar.primaryButton.setAttribute('data-title', '确认合成');
        // 合成提交意图音：CommitBar 的 disabled 与 commitCraft 本地拦截条件一致，抑制由绑定层兜底
        this.commitBar.primaryButton.setAttribute('data-audio-cue', 'activate');

        this.root.appendChild(this.chrome.root);
        this.root.appendChild(this.scroller);
        this.commitBar.mount(this.root);
        this.render({});
    }

    Presenter.prototype._releaseTooltips = function(root) {
        if (!root || typeof this._options.releaseTooltips !== 'function') return 0;
        return Number(this._options.releaseTooltips(root)) || 0;
    };

    Presenter.prototype._renderHero = function(model) {
        this._releaseTooltips(this.heroHost);
        clear(this.heroHost);
        var output = model.output || {};
        var hero = this._document.createElement('section');
        hero.className = 'crafting-output-card';
        var icon = this._document.createElement('button');
        icon.type = 'button';
        icon.className = 'crafting-output-icon crafting-output-inspect-trigger';
        icon.setAttribute('aria-label', '检视 ' + String(output.displayName || '合成产物'));
        icon.setAttribute('data-title', '打开装备检视器');
        icon.innerHTML = typeof this._options.iconHtml === 'function'
            ? this._options.iconHtml(output.icon, 'kshop-icon') : '';
        var self = this;
        icon.addEventListener('click', function() {
            if (typeof self._options.onInspect === 'function') self._options.onInspect(output);
        });
        if (typeof this._options.bindTooltip === 'function') this._options.bindTooltip(icon, output);

        var copy = this._document.createElement('div');
        copy.className = 'crafting-output-copy';
        copy.appendChild(textNode(this._document, 'h2', '', output.displayName || '产物'));
        var outputMeta = this._document.createElement('p');
        outputMeta.className = 'crafting-output-meta';
        var outputSegments = model.outputMeta || [];
        var outputMetaLabels = [];
        for (var i = 0; i < outputSegments.length; i++) {
            if (i > 0) {
                var separator = textNode(this._document, 'span',
                    'crafting-output-meta-separator', '·');
                separator.setAttribute('aria-hidden', 'true');
                outputMeta.appendChild(separator);
            }
            outputMeta.appendChild(textNode(this._document, 'span',
                'crafting-output-meta-' + String(outputSegments[i].kind || 'plain'),
                outputSegments[i].text || ''));
            outputMetaLabels.push(String(outputSegments[i].text || ''));
        }
        outputMeta.setAttribute('aria-label', outputMetaLabels.join('；'));
        copy.appendChild(outputMeta);
        var plannedCrafts = Math.max(0, Math.min(99,
            Math.floor(Number(model.plannedCrafts) || 0)));
        var planControl = this._document.createElement('div');
        planControl.className = 'crafting-plan-control';
        planControl.setAttribute('role', 'group');
        planControl.setAttribute('aria-label', '待合成标记数量');
        planControl.hidden = !model.recipeId;
        var planDecrement = this._document.createElement('button');
        planDecrement.type = 'button';
        planDecrement.className = 'workbench-mode-btn crafting-plan-step';
        planDecrement.textContent = '−';
        planDecrement.setAttribute('data-plan-action', 'decrement');
        planDecrement.setAttribute('aria-label', model.planDecrementAriaLabel
            || '减少一件待合成标记');
        planDecrement.setAttribute('data-audio-cue', 'activate');
        planDecrement.disabled = !!model.planDisabled || plannedCrafts <= 0;
        planDecrement.addEventListener('click', function(event) {
            if (typeof self._options.onPlanAdjust === 'function') {
                self._options.onPlanAdjust(-1, event);
            }
        });
        planControl.appendChild(planDecrement);
        var planButton = this._document.createElement('button');
        planButton.type = 'button';
        planButton.className = 'workbench-mode-btn crafting-plan-btn';
        planButton.textContent = model.planLabel || '标记待合成';
        planButton.setAttribute('data-plan-action', 'toggle');
        planButton.setAttribute('aria-pressed', model.planPressed ? 'true' : 'false');
        planButton.setAttribute('aria-label', model.planAriaLabel || planButton.textContent);
        planButton.setAttribute('data-audio-cue', 'toggle');
        planButton.disabled = !!model.planDisabled;
        planButton.addEventListener('click', function(event) {
            if (typeof self._options.onPlanToggle === 'function') {
                self._options.onPlanToggle(event);
            }
        });
        planControl.appendChild(planButton);
        var planIncrement = this._document.createElement('button');
        planIncrement.type = 'button';
        planIncrement.className = 'workbench-mode-btn crafting-plan-step';
        planIncrement.textContent = '+';
        planIncrement.setAttribute('data-plan-action', 'increment');
        planIncrement.setAttribute('aria-label', model.planIncrementAriaLabel
            || '增加一件待合成标记');
        planIncrement.setAttribute('data-audio-cue', 'activate');
        planIncrement.disabled = !!model.planDisabled || plannedCrafts >= 99;
        planIncrement.addEventListener('click', function(event) {
            if (typeof self._options.onPlanAdjust === 'function') {
                self._options.onPlanAdjust(1, event);
            }
        });
        planControl.appendChild(planIncrement);
        copy.appendChild(planControl);
        var planStatus = textNode(this._document, 'small',
            'crafting-plan-status', model.planStatus || '');
        planStatus.hidden = !model.planStatus;
        planStatus.setAttribute('role', 'status');
        planStatus.setAttribute('aria-live', 'polite');
        planStatus.setAttribute('data-state', model.planStatusKind || 'idle');
        copy.appendChild(planStatus);
        hero.appendChild(icon);
        hero.appendChild(copy);
        this.heroHost.appendChild(hero);
    };

    Presenter.prototype._renderMaterials = function(model) {
        var activeEl = this._document.activeElement;
        var restoreBbFocus = !!(activeEl && this.materialHost.contains(activeEl)
            && activeEl.classList && activeEl.classList.contains('crafting-battlebox-toggle'));
        this._releaseTooltips(this.materialHost);
        clear(this.materialHost);
        var list = this._document.createElement('section');
        list.className = 'crafting-material-list';
        var head = this._document.createElement('div');
        head.className = 'crafting-material-head';
        head.appendChild(textNode(this._document, 'h3', '', '所需材料'));
        var bbToggle = null;
        if (model.battleBoxAccessible === true && typeof this._options.onToggleBattleBox === 'function') {
            var self = this;
            var toggle = this._document.createElement('button');
            toggle.type = 'button';
            toggle.className = 'workbench-mode-btn crafting-battlebox-toggle';
            toggle.setAttribute('role', 'switch');
            toggle.setAttribute('aria-checked', model.useBattleBox === true ? 'true' : 'false');
            toggle.setAttribute('data-audio-cue', 'toggle');
            toggle.disabled = !!model.battleBoxToggleDisabled;
            toggle.textContent = model.useBattleBox === true ? '已启用战备箱直扣' : '使用战备箱材料';
            toggle.setAttribute('aria-label', model.useBattleBox === true
                ? '已启用战备箱直扣：合成时可自动从已解锁战备箱扣除所需材料'
                : '使用战备箱材料：默认只扣除背包、药剂栏与材料栏，开启后可直扣已解锁战备箱材料');
            toggle.addEventListener('click', function() {
                self._options.onToggleBattleBox();
            });
            head.appendChild(toggle);
            bbToggle = toggle;
        }
        list.appendChild(head);
        var rows = model.materials || [];
        if (!rows.length) {
            list.appendChild(textNode(this._document, 'div', 'crafting-material-empty', '该配方不消耗材料'));
        } else if (typeof this._options.renderMaterialRow === 'function') {
            for (var i = 0; i < rows.length; i++) {
                list.appendChild(this._options.renderMaterialRow(rows[i]));
            }
        }
        this.materialHost.appendChild(list);
        if (restoreBbFocus && bbToggle && !bbToggle.disabled && typeof bbToggle.focus === 'function') {
            try { bbToggle.focus({preventScroll:true}); } catch (_) { bbToggle.focus(); }
        }
    };

    Presenter.prototype._renderSummary = function(model) {
        clear(this.summaryHost);
        var summary = this._document.createElement('section');
        summary.className = 'crafting-cost-summary';
        var money = textNode(this._document, 'span', '', '金币 ');
        money.appendChild(textNode(this._document, 'b', '', model.moneyText || '0'));
        var kpoints = textNode(this._document, 'span', '', 'K 点 ');
        kpoints.appendChild(textNode(this._document, 'b', '', model.kpointsText || '0'));
        var capacity = textNode(this._document, 'span',
            'crafting-capacity ' + (model.enoughSpace ? 'ok' : 'bad'),
            model.enoughSpace ? '容量可用' : '背包空间不足');
        summary.appendChild(money);
        summary.appendChild(kpoints);
        summary.appendChild(capacity);
        this.summaryHost.appendChild(summary);
    };

    Presenter.prototype.render = function(model) {
        if (this._destroyed) return false;
        model = model || {};
        var preserveScroll = model.preserveScroll !== false;
        var scrollTop = preserveScroll ? this.scroller.scrollTop : 0;
        var scrollLeft = preserveScroll ? this.scroller.scrollLeft : 0;
        var selected = model.selected === true;
        var hasPreview = !!model.output;
        var batchEligible = selected && model.batchEligible === true;
        var previewState = model.previewState || (hasPreview ? 'ready' : selected ? 'waiting' : 'empty');

        this.root.setAttribute('data-preview-state', previewState);
        this.chrome.setTitle(model.title || '合成详情', model.kicker || '');
        this.chrome.setMeta(model.meta || (selected ? '正在计算…' : '请选择配方'));

        this.empty.hidden = hasPreview;
        this.empty.textContent = model.emptyText || (selected ? '正在计算合成预览…' : '从左侧选择一项配方');
        this.heroHost.hidden = !hasPreview;
        this.materialHost.hidden = !hasPreview;
        this.summaryHost.hidden = !hasPreview;
        if (hasPreview) {
            this._renderHero(model);
            this._renderMaterials(model);
            this._renderSummary(model);
        }

        this.quantityPanel.hidden = !batchEligible;
        var presetMax = Math.max(0, Math.min(99,
            Math.floor(Number(model.presetMax) || 0)));
        this.quantityHint.textContent = model.pending ? '核算中'
            : presetMax >= 99 ? '单次最多 99' : '可合成 ' + presetMax;
        this.quantity.update({
            min:1,
            max:99,
            presetMax:presetMax,
            sliderMax:99,
            value:Math.max(1, Math.min(99, Math.floor(Number(model.craftCount) || 1))),
            disabled:!!model.quantityDisabled || !batchEligible,
            showPlusFive:false,
            showMax:true,
            showRange:true
        });

        var interactiveCommit = model.canCommit === true || model.canQueueCommit === true;
        this.commitBar.update({
            label:model.commitLabel || '确认合成',
            status:model.commitStatus || (selected ? '正在计算…' : '请先选择配方'),
            canCommit:interactiveCommit,
            disabled:!interactiveCommit,
            busy:!!model.commitBusy && !model.canQueueCommit,
            state:model.commitState || (model.canCommit ? 'ready' : 'blocked')
        });
        this.commitBar.primaryButton.setAttribute('aria-busy', model.commitBusy ? 'true' : 'false');
        this.commitBar.root.classList.toggle('busy', !!model.commitBusy);
        if (model.commitQueued) this.commitBar.primaryButton.setAttribute('data-commit-queued', 'true');
        else this.commitBar.primaryButton.removeAttribute('data-commit-queued');
        this.commitBar.primaryButton.setAttribute('aria-label',
            model.commitAriaLabel || '确认合成');
        this.commitBar.primaryButton.setAttribute('data-title',
            model.commitTitle || '确认合成');

        this.scroller.scrollTop = scrollTop;
        this.scroller.scrollLeft = scrollLeft;
        return true;
    };

    Presenter.prototype.getView = function() {
        var self = this;
        return {
            instanceKey:'crafting:detail',
            instancePolicy:'singletonByBinding',
            allowedSlots:['R'],
            viewKind:'detail',
            root:this.root,
            chrome:this.chrome,
            mount:function(container) { container.appendChild(self.root); },
            unmount:function() { if (self.root.parentNode) self.root.parentNode.removeChild(self.root); },
            render:function(options) {
                if (typeof self._options.onRender === 'function') self._options.onRender(options);
            }
        };
    };

    Presenter.prototype.debugState = function() {
        return {
            destroyed:this._destroyed,
            previewState:this.root.getAttribute('data-preview-state'),
            quantityValue:this.quantity.getValue(),
            quantityAttached:this.quantity.root.parentNode === this.quantityPanel,
            commitAttached:this.commitBar.root.parentNode === this.root
        };
    };

    Presenter.prototype.hasPendingQuantityDraft = function() {
        return !!(this.quantity && typeof this.quantity.hasPendingDraft === 'function'
            && this.quantity.hasPendingDraft());
    };

    Presenter.prototype.revertQuantityDraft = function() {
        return !!(this.quantity && typeof this.quantity.revertDraft === 'function'
            && this.quantity.revertDraft());
    };

    Presenter.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this._releaseTooltips(this.root);
        this.quantity.destroy();
        this.commitBar.destroy();
        return true;
    };

    return {Presenter:Presenter};
})();
