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
            kicker:'权威核算',
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
        this.quantityHint = textNode(this._document, 'small', 'crafting-quantity-hint', '等待权威上限');
        this.quantityHeading.appendChild(this.quantityHint);

        var self = this;
        this.quantity = new WorkbenchComponents.QuantityControl({
            document:this._document,
            className:'workbench-quantity-control crafting-quantity-inputs',
            ariaLabel:'合成份数',
            inputAriaLabel:'输入合成份数',
            rangeAriaLabel:'拖动选择合成份数',
            maxLabel:'最大',
            maxAriaLabel:'设为当前权威可合成上限',
            showPlusFive:true,
            showMax:true,
            showRange:true,
            onChange:function(value, reason, event) {
                if (typeof self._options.onQuantityChange === 'function') {
                    self._options.onQuantityChange(value, reason, event);
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

        this.root.appendChild(this.chrome.root);
        this.root.appendChild(this.scroller);
        this.commitBar.mount(this.root);
        this.render({});
    }

    Presenter.prototype._renderHero = function(model) {
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
        copy.appendChild(textNode(this._document, 'p', '', model.outputSummary || ''));
        hero.appendChild(icon);
        hero.appendChild(copy);
        this.heroHost.appendChild(hero);
    };

    Presenter.prototype._renderMaterials = function(model) {
        clear(this.materialHost);
        var list = this._document.createElement('section');
        list.className = 'crafting-material-list';
        list.appendChild(textNode(this._document, 'h3', '', '所需材料'));
        var rows = model.materials || [];
        if (!rows.length) {
            list.appendChild(textNode(this._document, 'div', 'crafting-material-empty', '该配方不消耗材料'));
        } else if (typeof this._options.renderMaterialRow === 'function') {
            for (var i = 0; i < rows.length; i++) {
                list.appendChild(this._options.renderMaterialRow(rows[i]));
            }
        }
        this.materialHost.appendChild(list);
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
        this.chrome.setTitle(model.title || '合成详情', model.kicker || '权威核算');
        this.chrome.setMeta(model.meta || (selected ? '等待权威预览' : '请选择配方'));

        this.empty.hidden = hasPreview;
        this.empty.textContent = model.emptyText || (selected ? '等待权威预览' : '从左侧选择一项配方');
        this.heroHost.hidden = !hasPreview;
        this.materialHost.hidden = !hasPreview;
        this.summaryHost.hidden = !hasPreview;
        if (hasPreview) {
            this._renderHero(model);
            this._renderMaterials(model);
            this._renderSummary(model);
        }

        this.quantityPanel.hidden = !batchEligible;
        this.quantityHint.textContent = Number(model.presetMax) > 0
            ? '当前最多 ' + Number(model.presetMax) + ' 份'
            : model.pending ? '正在核算当前上限' : '当前资源不足 1 份';
        this.quantity.update({
            min:1,
            max:99,
            presetMax:Math.max(0, Math.min(99, Math.floor(Number(model.presetMax) || 0))),
            sliderMax:99,
            value:Math.max(1, Math.min(99, Math.floor(Number(model.craftCount) || 1))),
            disabled:!!model.quantityDisabled || !batchEligible,
            showPlusFive:true,
            showMax:true,
            showRange:true
        });

        this.commitBar.update({
            label:model.commitLabel || '确认合成',
            status:model.commitStatus || (selected ? '等待权威预览' : '请先选择配方'),
            canCommit:model.canCommit === true,
            disabled:model.canCommit !== true,
            busy:!!model.commitBusy,
            state:model.commitState || (model.canCommit ? 'ready' : 'blocked')
        });
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

    Presenter.prototype.destroy = function() {
        if (this._destroyed) return false;
        this._destroyed = true;
        this.quantity.destroy();
        this.commitBar.destroy();
        return true;
    };

    return {Presenter:Presenter};
})();
