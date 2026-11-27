/** Presentation-only secondary pages for NPCShop. Domain requests stay in npcshop.js. */
(function(root, factory) {
    'use strict';
    var api = factory();
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.NpcShopSecondaryPages = api;
})(typeof window !== 'undefined' ? window : globalThis, function() {
    'use strict';

    function noop() {}
    function requirePort(options, name) {
        if (!options || typeof options[name] !== 'function') throw new Error('NPC secondary page requires ' + name + ' port');
        return options[name];
    }

    // 语义音效命令式入口（契约 §8）：仅本地拦截反馈使用，静态按钮走 data-audio-cue
    function cue(name) {
        var A = (typeof window !== 'undefined') ? window.BootstrapAudio : null;
        if (A && typeof A.cue === 'function') A.cue(name);
    }

    function settlementViewModel(settlement, ui, errorMessage) {
        settlement = settlement || {};
        ui = ui || {};
        errorMessage = typeof errorMessage === 'function' ? errorMessage : function(error) { return String(error || ''); };
        var blockingError = settlement.blockingError || '';
        var sales = settlement.saleLines || [];
        var context = '待购和待售都只是清单；点击“确认交易”后整单才会一次生效。';
        if (blockingError === 'inventory_full') {
            context = '背包空间不足：可先整理背包与战备箱，返回后订单会自动重新核算。';
        } else if (ui.driftNotice) {
            context = String(ui.driftNotice);
        } else if (sales.some(function(line) { return line.scope === 'same_name'; })) {
            context = '同名全售只出售未强化且无插件的基础装备，强化、进阶和带插件装备会自动保护。';
        }
        return {
            status:blockingError ? errorMessage(blockingError) : (ui.driftNotice ? '报价已更新 · 请确认' : '整单可提交'),
            context:context,
            organizeVisible:blockingError === 'inventory_full',
            organizeDisabled:!!(ui.busy || ui.previewBusy || ui.spaceBusy),
            commitBusy:!!(ui.busy || ui.previewBusy),
            canCommit:!!settlement.canCommit && !ui.draftStale,
            commitState:blockingError || ui.draftStale ? 'blocked' : 'ready'
        };
    }

    function settlementInspection(kind, line, intent) {
        line = line || {};
        intent = intent || {};
        var sourceItem = intent.item || {};
        var item = {};
        for (var key in sourceItem) {
            if (Object.prototype.hasOwnProperty.call(sourceItem, key)) item[key] = sourceItem[key];
        }
        item.name = String(line.itemName || '');
        item.itemName = item.name;
        item.displayName = String(line.displayName || '');
        item.icon = String(line.icon || '');
        item.itemKind = String(line.itemKind || item.itemKind || '');
        var source = intent.source || {};
        if (kind === 'sale' && source.containerId === '背包') {
            return {
                viewId:'bag',
                slot:{
                    occupied:true,
                    physicalSlot:Number(source.slot),
                    slotLease:String(source.expectedLease || ''),
                    item:item
                }
            };
        }
        if (kind === 'purchase') {
            return {
                viewId:'catalog',
                slot:{occupied:true, slotLease:'', collectionKey:item.name, item:item}
            };
        }
        return {
            viewId:String(source.viewId || 'material'),
            slot:{
                occupied:true,
                slotLease:String(source.expectedLease || ''),
                collectionKey:String(source.key || line.sourceIdentity || item.name),
                item:item
            }
        };
    }

    function SettlementPresenter(options) {
        options = options || {};
        this._document = options.document;
        this._components = options.components;
        if (!this._document || !this._components || !options.host) {
            throw new Error('SettlementPresenter requires document, components, and host');
        }
        if (!options.tooltip || typeof options.tooltip.bindAsyncHover !== 'function') {
            throw new Error('SettlementPresenter requires NPC tooltip scope');
        }
        this._tooltip = options.tooltip;
        this._tooltipCache = options.tooltipCache || {};
        this._renderTooltipBasic = requirePort(options, 'renderTooltipBasic');
        this._renderTooltipRich = requirePort(options, 'renderTooltipRich');
        this._requestTooltip = requirePort(options, 'requestTooltip');
        this._ports = {
            onBack:requirePort(options, 'onBack'),
            onClose:requirePort(options, 'onClose'),
            onOrganize:requirePort(options, 'onOrganize'),
            onCommit:requirePort(options, 'onCommit'),
            onSetQuantity:requirePort(options, 'onSetQuantity'),
            onBulkSale:requirePort(options, 'onBulkSale'),
            onRemove:requirePort(options, 'onRemove'),
            onPurchaseBounds:requirePort(options, 'onPurchaseBounds'),
            onHelp:requirePort(options, 'onHelp'),
            onGuide:typeof options.onGuide === 'function' ? options.onGuide : noop,
            iconHtml:requirePort(options, 'iconHtml'),
            errorMessage:requirePort(options, 'errorMessage')
        };
        this._lineRecords = {purchase:{}, sale:{}};
        this.root = this._document.createElement('section');
        this.root.className = 'workbench-secondary-page npcshop-settlement-page';
        this.root.innerHTML = '<header class="npcshop-settlement-header"><div class="workbench-secondary-actions">'
            + '<button type="button" data-trade-back data-audio-cue="back">← 返回选购</button>'
            + '<button type="button" data-trade-help aria-label="商店操作帮助">？</button></div>'
            + '<div><h2>交易结算</h2><p data-trade-context>价格与容量由游戏实时核算；确认后整单一次生效。</p></div>'
            + '<button type="button" data-trade-close data-audio-cue="back" aria-label="关闭 NPC 商店">×</button></header>'
            + '<div class="npcshop-settlement-columns"><section><h3>待购</h3><div class="npcshop-settlement-list" data-purchase-lines></div></section>'
            + '<section><h3>待售</h3><div class="npcshop-settlement-list" data-sale-lines></div></section></div>'
            + '<footer class="npcshop-settlement-summary"><div data-trade-economy></div><span data-trade-error></span>'
            + '<button type="button" data-space-organize hidden>整理空间</button>'
            + '<button type="button" data-trade-commit data-audio-cue="activate">确认交易</button></footer>';
        this.secondary = new this._components.SecondaryPage({
            root:this.root, role:'dialog', ariaLabel:'NPC 商店交易结算'
        });
        this.secondary.bindBack(this.root.querySelector('[data-trade-back]'), this._ports.onBack);
        this._helpButton = this.root.querySelector('[data-trade-help]');
        this.secondary.bindHelp(this._helpButton, this._ports.onHelp);
        this.secondary.bindClose(this.root.querySelector('[data-trade-close]'), this._ports.onClose);
        this._organizeButton = this.root.querySelector('[data-space-organize]');
        this._organizeHandler = this._ports.onOrganize;
        this._organizeButton.addEventListener('click', this._organizeHandler);
        this._columns = this.root.querySelector('.npcshop-settlement-columns');
        this._purchaseSection = this._columns.children[0];
        this._saleSection = this._columns.children[1];
        this.commitBar = new this._components.CommitBar({
            root:this.root.querySelector('.npcshop-settlement-summary'),
            statusNode:this.root.querySelector('[data-trade-error]'),
            primaryButton:this.root.querySelector('[data-trade-commit]'),
            label:'确认交易', onCommit:this._ports.onCommit
        });
        this.secondary.mount(options.host);
    }
    SettlementPresenter.prototype.open = function() {
        var lists = this.root.querySelectorAll('.npcshop-settlement-list');
        for (var i = 0; i < lists.length; i++) { lists[i].scrollTop = 0; lists[i].scrollLeft = 0; }
        return this.secondary.open();
    };
    SettlementPresenter.prototype.close = function(reason) { return this.secondary.close(reason || 'return'); };
    SettlementPresenter.prototype.isActive = function() { return this.secondary.isActive(); };
    SettlementPresenter.prototype.setOrganizing = function(active) { this.root.classList.toggle('organizing-space', !!active); };
    SettlementPresenter.prototype.reset = function() {
        this._renderLines('purchase', [], {}); this._renderLines('sale', [], {});
        if (this._purchaseSection) this._purchaseSection.hidden = false;
        if (this._saleSection) this._saleSection.hidden = false;
        if (this._columns) this._columns.classList.remove('is-single-column');
        this.root.querySelector('[data-trade-economy]').textContent = '';
        this.root.querySelector('[data-trade-context]').textContent = '价格与容量由游戏实时核算；确认后整单一次生效。';
        this._organizeButton.hidden = true;
        this.commitBar.update({label:'核算中…', status:'', busy:true, canCommit:false, state:'busy'});
    };
    SettlementPresenter.prototype.renderLoading = function() {
        this.commitBar.update({label:'核算中…', busy:true, canCommit:false, state:'busy'});
    };
    SettlementPresenter.prototype.renderFailure = function(errorCode, recovered) {
        this.commitBar.update({
            label:'无法结算', status:this._ports.errorMessage(errorCode)
                + (recovered ? ' 已恢复上一次可核算的清单，可继续调整或返回选购。' : ''),
            disabled:true, canCommit:false, state:'error'
        });
    };
    SettlementPresenter.prototype.render = function(settlement, intents, ui) {
        if (!settlement) return false;
        intents = intents || {purchases:{}, sales:{}};
        ui = ui || {};
        var purchaseLines = settlement.purchaseLines || [];
        var saleLines = settlement.saleLines || [];
        var purchaseOnly = purchaseLines.length > 0 && saleLines.length === 0;
        var saleOnly = saleLines.length > 0 && purchaseLines.length === 0;
        if (this._purchaseSection) this._purchaseSection.hidden = saleOnly;
        if (this._saleSection) this._saleSection.hidden = purchaseOnly;
        if (this._columns) this._columns.classList.toggle('is-single-column', purchaseOnly || saleOnly);
        this._renderLines('purchase', purchaseLines, intents.purchases || {}, ui);
        this._renderLines('sale', saleLines, intents.sales || {}, ui);
        this.root.querySelector('[data-trade-economy]').innerHTML = '<b>购买 -$' + Number(settlement.buyTotal || 0).toLocaleString() + '</b>'
            + '<b>出售 +$' + Number(settlement.sellTotal || 0).toLocaleString() + '</b>'
            + '<strong>结余 $' + Number(settlement.projectedBalance || 0).toLocaleString() + '</strong>'
            + '<small>需 ' + Number(settlement.requiredSlots || 0) + ' 格 / 可用 ' + Number(settlement.availableSlots || 0) + ' 格</small>';
        var vm = settlementViewModel(settlement, ui, this._ports.errorMessage);
        this.root.querySelector('[data-trade-back]').disabled = !!ui.busy;
        this._helpButton.disabled = !!ui.busy;
        this._organizeButton.hidden = !vm.organizeVisible;
        this._organizeButton.disabled = vm.organizeDisabled;
        this.root.querySelector('[data-trade-context]').textContent = vm.context;
        if (vm.organizeVisible) this._ports.onGuide('inventory_full');
        this.commitBar.update({
            label:'确认交易', status:vm.status, busy:vm.commitBusy,
            canCommit:vm.canCommit, state:vm.commitState
        });
        return true;
    };
    SettlementPresenter.prototype._lineVariant = function(kind, line) {
        if (kind === 'purchase') return 'purchase';
        if (line.scope === 'same_name') return 'same_name';
        return line.itemKind === 'equipment' ? 'equipment' : 'sale';
    };
    SettlementPresenter.prototype._createLineRecord = function(kind, line, identity) {
        var self = this;
        var variant = this._lineVariant(kind, line);
        var record = {identity:identity, variant:variant};
        record.row = this._document.createElement('article');
        record.row.className = 'npcshop-settlement-line';
        record.row.tabIndex = 0;
        record.row.setAttribute('data-line-identity', identity);
        record.icon = this._document.createElement('span');
        record.icon.className = 'npcshop-card-icon';
        record.copy = this._document.createElement('span');
        record.copy.className = 'npcshop-settlement-copy';
        record.name = this._document.createElement('b');
        record.total = this._document.createElement('small');
        record.bound = this._document.createElement('em');
        record.copy.appendChild(record.name);
        record.copy.appendChild(record.total);
        record.copy.appendChild(record.bound);
        record.stepper = this._document.createElement('span');
        record.stepper.className = 'npcshop-stepper';
        record.remove = this._stepButton('×', function() {
            self._ports.onRemove(kind, identity);
        });
        record.remove.classList.add('remove');
        record.remove.setAttribute('aria-label', '从结算清单移除');
        if (variant === 'purchase' || variant === 'sale' || variant === 'equipment') {
            record.control = new this._components.QuantityControl({
                document:this._document,
                min:1,
                max:1,
                value:1,
                showPlusFive:true,
                showMax:true,
                showRange:true,
                onChange:function(value, reason) {
                    self._ports.onSetQuantity(kind, identity, value, reason);
                }
            });
            record.stepper.appendChild(record.control.root);
        }
        if (variant === 'same_name') {
            record.single = this._stepButton('只售此格', function() {
                self._ports.onBulkSale(identity, false);
            });
            record.single.classList.add('wide');
            record.stepper.appendChild(record.single);
        } else if (variant === 'equipment') {
            record.bulk = this._stepButton('同名全售', function() {
                self._ports.onBulkSale(identity, true);
            });
            record.bulk.classList.add('wide');
            record.stepper.appendChild(record.bulk);
        }
        record.stepper.appendChild(record.remove);
        record.row.appendChild(record.icon);
        record.row.appendChild(record.copy);
        record.row.appendChild(record.stepper);
        return record;
    };
    SettlementPresenter.prototype._updateLineRecord = function(record, kind, line, intent, ui) {
        var displayName = line.displayName;
        var iconKey = String(line.icon || '');
        if (record.iconKey !== iconKey) {
            record.iconKey = iconKey;
            record.icon.innerHTML = this._ports.iconHtml(iconKey, 'kshop-icon');
        }
        record.name.textContent = displayName;
        record.total.textContent = (kind === 'purchase' ? '-$' : '+$')
            + Number(line.total || 0).toLocaleString();
        var blocked = !!(ui.busy || ui.previewBusy);
        record.row.setAttribute('aria-label', displayName + '，'
            + (kind === 'purchase' ? '待购物品' : '待售物品') + '，可查看物品说明');
        if (kind === 'purchase') {
            var purchaseLimit = Math.max(1, Math.floor(Number(
                line.purchaseLimit || intent.purchaseLimit || intent.maxQuantity || 1)));
            var current = Math.max(1, Math.floor(Number(intent.quantity || 1)));
            var effective = Math.max(0, Math.floor(Number(
                line.maxPurchasable == null ? intent.maxPurchasable : line.maxPurchasable) || 0));
            var authorityMaximum = Math.max(purchaseLimit, current);
            this._ports.onPurchaseBounds(record.identity, {
                purchaseLimit:purchaseLimit,
                maxPurchasable:effective
            });
            record.bound.hidden = false;
            record.bound.textContent = '当前可直接结算 ' + effective + ' / 单笔上限 ' + purchaseLimit;
            record.control.root.setAttribute('aria-label', displayName + '购买数量');
            record.control.update({
                min:1,
                max:authorityMaximum,
                presetMax:effective,
                sliderMax:authorityMaximum,
                value:current,
                disabled:blocked,
                maxLabel:'可用',
                maxAriaLabel:'设为当前可直接结算上限'
            });
        } else if (record.variant === 'same_name') {
            record.bound.hidden = false;
            record.bound.textContent = '同名匹配 ' + Number(line.matchedCount || 0) + ' 格，售出 '
                + Number(line.eligibleCount || 0) + ' 格，保护 ' + Number(line.protectedCount || 0) + ' 格';
        } else {
            var saleMaximum = Math.max(1, Math.floor(Number(intent.maxQuantity || 1)),
                Math.floor(Number(intent.quantity || 1)));
            record.bound.hidden = true;
            record.bound.textContent = '';
            record.control.root.setAttribute('aria-label', displayName + '出售数量');
            record.control.update({
                min:1,
                max:saleMaximum,
                presetMax:saleMaximum,
                sliderMax:saleMaximum,
                value:intent.quantity,
                disabled:blocked,
                maxLabel:'全部',
                maxAriaLabel:'设为全部可出售数量'
            });
        }
        var rowButtons = record.stepper.querySelectorAll('button');
        for (var buttonIndex = 0; buttonIndex < rowButtons.length; buttonIndex++) {
            if (!record.control || !record.control.root.contains(rowButtons[buttonIndex])) {
                rowButtons[buttonIndex].disabled = blocked;
            }
        }
        this._bindLineInspection(record, kind, line, intent);
    };
    SettlementPresenter.prototype._bindLineInspection = function(record, kind, line, intent) {
        var inspection = settlementInspection(kind, line, intent);
        var slot = inspection.slot;
        var signature = inspection.viewId + ':' + String(slot.physicalSlot) + ':'
            + String(slot.slotLease || slot.collectionKey) + ':' + slot.item.name + ':'
            + slot.item.displayName + ':' + slot.item.icon;
        if (record.tooltipSignature === signature) return;
        if (record.tooltipBinding) record.tooltipBinding.destroy();
        record.tooltipSignature = signature;
        record.tooltipBinding = bindOwnedTooltip({
            node:record.row,
            viewId:inspection.viewId,
            slot:slot,
            tooltip:this._tooltip,
            cache:this._tooltipCache,
            renderBasic:this._renderTooltipBasic,
            renderRich:this._renderTooltipRich,
            request:this._requestTooltip,
            isSuppressed:function(event) {
                var target = event && event.target;
                var tagName = target && String(target.tagName || '').toUpperCase();
                return target !== record.row
                    && (tagName === 'BUTTON' || tagName === 'INPUT'
                        || tagName === 'SELECT' || tagName === 'TEXTAREA');
            }
        });
    };
    SettlementPresenter.prototype._destroyLineRecord = function(record) {
        if (!record) return;
        if (record.tooltipBinding) record.tooltipBinding.destroy();
        record.tooltipBinding = null;
        if (record.control) record.control.destroy();
        if (record.row.parentNode) record.row.parentNode.removeChild(record.row);
    };
    SettlementPresenter.prototype._renderLines = function(kind, lines, intents, ui) {
        ui = ui || {};
        var list = this.root.querySelector(kind === 'purchase' ? '[data-purchase-lines]' : '[data-sale-lines]');
        var previousScrollTop = list.scrollTop;
        var previousScrollLeft = list.scrollLeft;
        var existing = this._lineRecords[kind];
        var next = {};
        var desiredRows = [];
        for (var i = 0; i < lines.length; i++) {
            var line = lines[i];
            var identity = kind === 'purchase' ? String(line.catalogIndex) : String(line.sourceIdentity);
            var intent = intents[identity];
            if (!intent || next[identity]) continue;
            var variant = this._lineVariant(kind, line);
            var record = existing[identity];
            if (record && record.variant !== variant) {
                this._destroyLineRecord(record);
                record = null;
            }
            if (!record) record = this._createLineRecord(kind, line, identity);
            this._updateLineRecord(record, kind, line, intent, ui);
            next[identity] = record;
            desiredRows.push(record.row);
        }
        for (var oldIdentity in existing) {
            if (Object.prototype.hasOwnProperty.call(existing, oldIdentity) && !next[oldIdentity]) {
                this._destroyLineRecord(existing[oldIdentity]);
            }
        }
        this._lineRecords[kind] = next;
        var empty = list.querySelector('.npcshop-settlement-empty');
        if (desiredRows.length && empty && empty.parentNode) empty.parentNode.removeChild(empty);
        for (var rowIndex = 0; rowIndex < desiredRows.length; rowIndex++) {
            var current = list.children[rowIndex] || null;
            if (current !== desiredRows[rowIndex]) list.insertBefore(desiredRows[rowIndex], current);
        }
        if (!desiredRows.length) {
            if (!empty) {
                empty = this._document.createElement('p');
                empty.className = 'npcshop-settlement-empty';
                empty.textContent = '无';
            }
            if (empty.parentNode !== list) list.appendChild(empty);
        }
        list.scrollTop = previousScrollTop;
        list.scrollLeft = previousScrollLeft;
    };
    SettlementPresenter.prototype._stepButton = function(label, handler) {
        var button = this._document.createElement('button');
        button.type = 'button'; button.textContent = label; button.addEventListener('click', handler); return button;
    };
    SettlementPresenter.prototype.destroy = function() {
        this._organizeButton.removeEventListener('click', this._organizeHandler);
        var kinds = ['purchase', 'sale'];
        for (var kindIndex = 0; kindIndex < kinds.length; kindIndex++) {
            var records = this._lineRecords[kinds[kindIndex]];
            for (var identity in records) {
                if (Object.prototype.hasOwnProperty.call(records, identity)) this._destroyLineRecord(records[identity]);
            }
        }
        this._lineRecords = {purchase:{}, sale:{}};
        this.commitBar.destroy();
        this.secondary.destroy();
        return true;
    };

    function helpCard(index, title, body, detail, chipA, chipB) {
        return '<article class="npcshop-help-card"><span class="npcshop-help-index">' + index + '</span><div><h3>' + title + '</h3><p>' + body
            + '</p><small>' + detail + '</small><div class="npcshop-help-flow"><i>' + chipA + '</i><b>→</b><i>' + chipB + '</i></div></div></article>';
    }
    function HelpPresenter(options) {
        options = options || {};
        if (!options.document || !options.components || !options.host) throw new Error('HelpPresenter requires document, components, and host');
        this.root = options.document.createElement('section');
        this.root.className = 'workbench-secondary-page npcshop-help-page';
        this.root.innerHTML = '<header class="npcshop-help-header"><div class="workbench-secondary-actions">'
            + '<button type="button" data-help-back data-audio-cue="back">← 返回商店</button></div>'
            + '<div><h2>商店操作帮助</h2><p>所有选择都可以在确认交易前调整或取消。</p></div>'
            + '<button type="button" data-help-close data-audio-cue="back" aria-label="关闭 NPC 商店">×</button></header>'
            + '<div class="npcshop-help-grid">'
            + helpCard('01','选购与快捷交易','左栏单击商品每次加购 1 件，右栏单击背包或材料加入待售；双击或右键可直接单件快捷交易。','选中的卡片可直接点“×”移出，未点击完成交易前不会扣钱。','加购 / 待售','快捷交易')
            + helpCard('02','底条直结与明细核对','底部交易条实时汇总收支金币，可直接“完成交易”；需要滑条、+5 或“可用”/“全部”调数时点“明细核对”。','“可用”上限由金币、背包容量和商店限制共同决定。','底条直结','明细核对')
            + helpCard('03','同名全售','背包中的基础装备可直接点击“同名全售”，或在结算页切换。','只出售未强化且无插件的同名装备；强化、进阶和带插件装备自动保护。','同名匹配','保护特殊装备')
            + helpCard('04','整理背包','随时可从顶栏“整理背包”在背包与战备箱之间快速转移物品。','返回后订单会自动重算；商品不会直接购买到战备箱。','整理背包','返回重算')
            + '</div><footer class="npcshop-help-rules"><b>记住三件事</b><span>选择 ≠ 交易</span><span>最大数量会动态变化</span><span>移动后的待售项可能被安全移除</span>'
            + '<small>关键提示只自动出现一次；本页可随时从标题栏“？”重新打开。</small></footer>';
        this.backButton = this.root.querySelector('[data-help-back]');
        this.secondary = new options.components.SecondaryPage({root:this.root, role:'dialog', ariaLabel:'NPC 商店操作帮助'});
        this.secondary.bindBack(this.backButton, requirePort(options, 'onBack'));
        this.secondary.bindClose(this.root.querySelector('[data-help-close]'), requirePort(options, 'onClose'));
        this.secondary.mount(options.host);
    }
    HelpPresenter.prototype.open = function(returnLabel) {
        this.backButton.textContent = returnLabel || '← 返回商店';
        this.secondary.open(); this.backButton.focus(); return true;
    };
    HelpPresenter.prototype.close = function(reason) { return this.secondary.close(reason || 'return'); };
    HelpPresenter.prototype.isActive = function() { return this.secondary.isActive(); };
    HelpPresenter.prototype.destroy = function() { return this.secondary.destroy(); };

    function ownedInteraction(state) {
        state = state || {};
        if (state.refreshRequired) return {inspectable:true, actionable:false, reason:'库存同步失败，请先重试。'};
        if (state.reconcileRequired) return {inspectable:true, actionable:false, reason:'商店状态需要重新同步。'};
        if (state.returning) return {inspectable:true, actionable:false, reason:'正在重新核对商店与库存。'};
        if (state.spaceBusy) return {inspectable:true, actionable:false, reason:'正在载入或核对整理空间。'};
        if (!state.ready) return {inspectable:true, actionable:false, reason:'库存正在同步，请稍候。'};
        if (state.busyOwner) return {inspectable:true, actionable:false, reason:'库存正在处理另一项操作。'};
        if (state.transactionBusy) return {inspectable:true, actionable:false, reason:'交易正在由游戏确认。'};
        if (state.readOnly) return {inspectable:true, actionable:false, reason:'此栏仅供查看，不能加入待售。'};
        return {inspectable:true, actionable:true, reason:''};
    }

    function bindCatalogActivation(options) {
        options = options || {};
        var item = options.item || {};
        var atLimit = isFinite(Number(item.maxQuantity)) && Number(item.maxQuantity) <= 0;
        var reason = item.locked
            ? (item.requiredInfo ? '需要情报：' + item.requiredInfo : '尚未解锁')
            : (atLimit ? '已达持有上限' : '');
        var removeBtn = options.node && options.node.querySelector('.npcshop-intent-remove');
        if (removeBtn && typeof options.onRemove === 'function') {
            removeBtn.addEventListener('click', function(event) {
                event.stopPropagation();
                options.onRemove(item);
            });
        }
        if (options.node && !item.locked && !atLimit && typeof options.onQuickTrade === 'function') {
            options.node.addEventListener('dblclick', function(event) {
                if (event.target && event.target.closest && event.target.closest('button')) return;
                event.preventDefault();
                options.onQuickTrade(item, true);
            });
            options.node.addEventListener('contextmenu', function(event) {
                if (event.target && event.target.closest && event.target.closest('button')) return;
                event.preventDefault();
                options.onQuickTrade(item, false);
            });
        }
        return options.workbench.EntityTile.bindActivation(options.node, {
            itemName:item.displayName,
            label:options.node.getAttribute('aria-label') || '',
            selected:!!options.selected,
            inspectable:true,
            actionable:!item.locked && !atLimit,
            reason:reason,
            reasonNode:options.node.querySelector('.item-card-interaction-reason'),
            onBlocked:function() { options.toast(reason); cue('illegal'); },
            onActivate:options.onActivate
        });
    }

    function ensureReasonNode(node) {
        var reason = node.querySelector('.workbench-entity-lock-reason');
        if (!reason) {
            reason = document.createElement('span');
            reason.className = 'workbench-entity-lock-reason';
            reason.hidden = true;
            node.appendChild(reason);
        }
        return reason;
    }

    function projectNode(workbench, node, projection, reasonNode) {
        return workbench.EntityTile.projectInteraction(node, {
            inspectable:projection.inspectable, actionable:projection.actionable,
            reason:projection.reason, reasonNode:reasonNode
        });
    }

    function bindOwnedTooltip(options) {
        var slot = options.slot;
        if (!slot || !slot.occupied) return;
        var viewId = options.viewId;
        var item = slot.item || {};
        var payload = viewId === 'bag'
            ? {source:{containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}}
            : {itemName:String(item.name || '')};
        return options.tooltip.bindAsyncHover(options.node, {
            cache:options.cache,
            key:viewId + ':' + String(slot.slotLease || slot.collectionKey),
            item:item,
            renderBasic:options.renderBasic,
            renderRich:options.renderRich,
            isSuppressed:options.isSuppressed,
            fetch:function(_, callback) { options.request('tooltip', payload, callback); }
        });
    }

    function tooltipBasic(item, escapeHtml, workbench) {
        return '<div class="kshop-tt-header"><b>'
            + escapeHtml(item.displayName || '物品')
            + '</b></div>' + workbench.ItemCard.balanceTooltipMetaHtml(item)
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function tooltipRich(item, rich, tooltip, workbench) {
        return tooltip.buildItemRichHtml({
            iconHtml:tooltip.dynamicIconHtml(item.icon),
            iconUrl:tooltip.staticIconUrl(item.icon),
            introHTML:rich.introHTML || '', descHTML:rich.descHTML || '',
            document:rich.document,
            metaHTML:workbench.ItemCard.balanceTooltipMetaHtml(item),
            rootClass:'npcshop-tooltip',
            layoutType:tooltip.inferLayoutType(item.majorType || item.use)
        });
    }

    function errorMessage(error) {
        var messages = {
            shop_not_found:'未找到该 NPC 的商店。', item_not_found:'商品或待售物品已经变化。', locked:'尚未获得所需情报。', insufficient_money:'金币不足。', inventory_full:'背包空间不足。',
            destination_full:'对应收集项已达持有上限。',
            access_denied:'当前角色暂不能使用这家商店，请确认剧情和关卡条件后重新进入。', stale_state:'物品状态已经变化。', invalid_price:'商品或售卖价格已经变化。', sell_forbidden:'该容器不允许出售。', insufficient_quantity:'物品数量不足。', duplicate_line:'交易清单包含重复物品。',
            invalid_payload:'交易清单包含无效数据。', invalid_quantity:'购买或出售数量无效。', nothing_to_sell:'没有可批量出售的普通装备。', target_full:'目标栏位已满。', slot_locked:'该战备箱槽位尚未解锁。',
            busy:'商店正在处理另一项交易。', reconcile_required:'交易结果需要重新同步。', malformed_response:'交易响应不完整，需要重新核算。', invalid_response:'交易响应无效，需要重新核算。',
            timeout:'商店响应超时。', client_timeout:'商店响应超时。', disconnected:'连接已断开。'
        };
        return messages[error] || '操作失败，请重试。';
    }

    function spaceStatus(state) {
        state = state || {};
        return state.returning ? '重新核对中…' : state.spaceBusy ? '准备整理空间…'
            : state.refreshRequired ? '同步失败' : state.busyOwner ? '转移中…'
            : state.ready ? '点击快速转移' : '同步中…';
    }
    function SpaceOrganizerPresenter(options) {
        options = options || {};
        if (!options.document || !options.components || !options.inventoryUI || !options.workbench || !options.host) {
            throw new Error('SpaceOrganizerPresenter requires presentation adapters and host');
        }
        this._document = options.document;
        this._components = options.components;
        this._inventoryUI = options.inventoryUI;
        this._workbench = options.workbench;
        this._densityController = options.densityController || null;
        if (!options.tooltip || typeof options.tooltip.bindAsyncHover !== 'function') {
            throw new Error('SpaceOrganizerPresenter requires NPC tooltip scope');
        }
        this._tooltip = options.tooltip;
        this._tooltipCache = options.tooltipCache || {};
        this._renderTooltipBasic = requirePort(options, 'renderTooltipBasic');
        this._renderTooltipRich = requirePort(options, 'renderTooltipRich');
        this._requestTooltip = requirePort(options, 'requestTooltip');
        this._ports = {
            getWindow:requirePort(options, 'getWindow'), getRequest:requirePort(options, 'getRequest'),
            setWindow:requirePort(options, 'setWindow'), autoTransfer:requirePort(options, 'autoTransfer'),
            onBack:requirePort(options, 'onBack'), onPageResult:requirePort(options, 'onPageResult'),
            onClose:requirePort(options, 'onClose'),
            onTransferResult:requirePort(options, 'onTransferResult'),
            iconHtml:requirePort(options, 'iconHtml'), toast:requirePort(options, 'toast')
        };
        this._state = {};
        this._interaction = ownedInteraction(this._state);
        this.root = this._document.createElement('section');
        this.root.className = 'npcshop-space-page';
        this.root.innerHTML = '<header class="npcshop-space-header"><div class="workbench-secondary-actions">'
            + '<button type="button" data-space-back data-audio-cue="back">← 返回结算</button></div>'
            + '<div><h2>整理购买空间</h2><p>点击物品即可在背包与战备箱之间快速转移；返回后交易会重新核算。</p></div>'
            + '<span data-space-status>同步中</span>'
            + '<button type="button" data-space-close data-audio-cue="back" aria-label="关闭 NPC 商店">×</button></header>'
            + '<div class="npcshop-space-columns"><section><h3>背包 <small data-space-meta="背包"></small></h3><div class="npcshop-space-grid" data-space-grid="背包"></div></section>'
            + '<section><h3>战备箱 <span data-space-pager></span><small data-space-meta="战备箱"></small></h3><div class="npcshop-space-grid battlebox" data-space-grid="战备箱"></div></section></div>';
        this.secondary = new this._components.SecondaryPage({root:this.root, role:'dialog', ariaLabel:'整理购买空间'});
        this._backButton = this.root.querySelector('[data-space-back]');
        this.secondary.bindBack(this._backButton, this._ports.onBack);
        this.secondary.bindClose(this.root.querySelector('[data-space-close]'), this._ports.onClose);
        this._grids = {
            '背包':this.root.querySelector('[data-space-grid="背包"]'),
            '战备箱':this.root.querySelector('[data-space-grid="战备箱"]')
        };
        if (this._densityController) {
            this._densityController.register(this._grids['背包']);
            this._densityController.register(this._grids['战备箱']);
        }
        var self = this;
        this.pager = new this._inventoryUI.InventoryWindowPager({
            containerId:'战备箱', containerLabel:'战备箱', columns:5,
            defaultOffset:0, defaultLimit:40, defaultCapacity:0,
            getSnapshot:function() { return self._ports.getWindow('战备箱'); },
            getRequest:function() { return self._ports.getRequest('战备箱'); },
            shortcutEnabled:function() { return self.isActive(); },
            onRequest:function(offset, limit, callback) { return self._ports.setWindow('战备箱', offset, limit, callback); },
            onResult:function(result) { self.render(self._state); self._ports.onPageResult(result); }
        });
        this.root.querySelector('[data-space-pager]').appendChild(this.pager.root);
        this.pager.attach();
        this.transferPane = new this._components.OwnedInventoryPane({
            root:this.root,
            keyOf:function(slot) { return slot && slot.physicalSlot; },
            interaction:this._interaction,
            onInteractionChange:function(projection) {
                self._interaction = projection;
                self._projectInteraction();
            },
            onQuickTransfer:function(transfer, done) { return self._ports.autoTransfer(transfer.source, transfer.target, done); },
            onQuickTransferResult:function(result) {
                self._ports.onTransferResult(result);
                self.render(self._state);
            }
        });
        this.secondary.mount(options.host);
    }
    SpaceOrganizerPresenter.prototype.open = function(backLabel) {
        if (this._backButton) this._backButton.textContent = backLabel || '← 返回结算';
        return this.secondary.open();
    };
    SpaceOrganizerPresenter.prototype.close = function(reason) { return this.secondary.close(reason || 'return'); };
    SpaceOrganizerPresenter.prototype.isActive = function() { return this.secondary.isActive(); };
    SpaceOrganizerPresenter.prototype.render = function(state) {
        if (!this.isActive()) return false;
        this._state = state || {};
        this.transferPane.setInteraction(ownedInteraction(this._state));
        this._renderGrid('背包'); this._renderGrid('战备箱');
        this.pager.setDisabled(!this._interaction.actionable); this.pager.refresh();
        this.root.querySelector('[data-space-status]').textContent = spaceStatus(this._state);
        return true;
    };
    SpaceOrganizerPresenter.prototype._renderGrid = function(containerId) {
        var self = this;
        var grid = this._grids[containerId];
        if (typeof this._tooltip.releaseTree === 'function') this._tooltip.releaseTree(grid);
        while (grid.firstChild) grid.removeChild(grid.firstChild);
        var snapshot = this._ports.getWindow(containerId);
        var slots = snapshot && snapshot.slots ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            var node = this._inventoryUI.renderOwnedSlot(containerId, slot, {iconHtml:this._ports.iconHtml, allowDiscard:false});
            if (slot.occupied) {
                node.classList.add('npcshop-space-transferable');
                var transferAction = containerId === '背包' ? '移入战备箱' : '移入背包';
                node.setAttribute('aria-label', (node.getAttribute('aria-label') || '')
                    + '，可查看物品说明，点击' + transferAction);
                bindOwnedTooltip({
                    node:node,
                    viewId:containerId === '背包' ? 'bag' : 'battlebox',
                    slot:slot,
                    tooltip:this._tooltip,
                    cache:this._tooltipCache,
                    renderBasic:this._renderTooltipBasic,
                    renderRich:this._renderTooltipRich,
                    request:this._requestTooltip
                });
                (function(sourceContainer, sourceSlot, sourceNode) {
                    var reasonNode = ensureReasonNode(sourceNode);
                    self._workbench.EntityTile.bindActivation(sourceNode, {
                        itemName:String(sourceSlot.item && sourceSlot.item.displayName || '未知物品'),
                        label:sourceNode.getAttribute('aria-label') || '',
                        inspectable:function() { return self._interaction.inspectable; },
                        actionable:function() { return self._interaction.actionable; },
                        reason:function() { return self._interaction.reason; },
                        reasonNode:reasonNode,
                        onBlocked:function() { self._ports.toast(self._interaction.reason); },
                        onActivate:function() { self.transfer(sourceContainer, sourceSlot); }
                    });
                    sourceNode.__npcSpaceInteractionRefresh = function() {
                        projectNode(self._workbench, sourceNode, self._interaction, reasonNode);
                        sourceNode.classList.toggle('write-locked', !self._interaction.actionable);
                    };
                    sourceNode.__npcSpaceInteractionRefresh();
                })(containerId, slot, node);
            } else {
                this._workbench.EntityTile.applySemantics(node, {
                    itemName:'空槽', label:node.getAttribute('aria-label') || '', disabled:true
                });
            }
            grid.appendChild(node);
        }
        var meta = this.root.querySelector('[data-space-meta="' + containerId + '"]');
        if (!snapshot) meta.textContent = '同步中';
        else if (containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0) meta.textContent = '未解锁';
        else meta.textContent = slots.filter(function(candidate) { return candidate.occupied; }).length + ' 项';
    };
    SpaceOrganizerPresenter.prototype._projectInteraction = function() {
        var nodes = this.root.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].__npcSpaceInteractionRefresh) nodes[i].__npcSpaceInteractionRefresh();
        }
    };
    SpaceOrganizerPresenter.prototype.transfer = function(containerId, slot) {
        if (!this._interaction.actionable || !slot || !slot.occupied) return false;
        var source = {containerId:containerId, slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease), occupied:true, item:slot.item || null};
        var target = containerId === '背包' ? '战备箱' : '背包';
        var key = containerId + ':' + String(source.slot) + ':' + String(source.expectedLease) + '>' + target;
        if (!this.transferPane.quickTransfer(source, target, {key:key})) {
            this._ports.toast('库存正在处理另一项操作。'); return false;
        }
        this.render(this._state);
        return true;
    };
    SpaceOrganizerPresenter.prototype.destroy = function() {
        if (typeof this._tooltip.releaseTree === 'function') this._tooltip.releaseTree(this.root);
        this.pager.detach();
        this.transferPane.destroy();
        if (this._densityController && typeof this._densityController.unregister === 'function') {
            this._densityController.unregister(this._grids['背包']);
            this._densityController.unregister(this._grids['战备箱']);
        }
        this.secondary.destroy();
        return true;
    };

    function isPlainBagEquipment(viewId, slot) {
        if (viewId !== 'bag' || !slot || !slot.occupied || !slot.item) return false;
        var item = slot.item;
        if (item.itemKind !== 'equipment') return false;
        if (typeof NpcShopRuntime !== 'undefined' && NpcShopRuntime
                && typeof NpcShopRuntime.isPlainProjectedItem === 'function') {
            return NpcShopRuntime.isPlainProjectedItem(item);
        }
        if (Number(item.enhancementLevel || 0) > 1 || Number(item.level || 0) > 1) return false;
        if (item.tierSlotUsed === true || item.tier || item.hasTier || item.upgraded) return false;
        if (Number(item.modSlotUsed || 0) > 0 || Number(item.modCount || 0) > 0) return false;
        if (Array.isArray(item.modSlots) && item.modSlots.length > 0) return false;
        if (Array.isArray(item.mods) && item.mods.length > 0) return false;
        return true;
    }

    function LiveTradeBar(options) {
        options = options || {};
        this._document = options.document || document;
        this._ports = {
            onClear:requirePort(options, 'onClear'),
            onOpenSettlement:requirePort(options, 'onOpenSettlement'),
            onDirectTrade:requirePort(options, 'onDirectTrade')
        };
        this.root = this._document.createElement('footer');
        this.root.className = 'npcshop-live-trade-bar workbench-commit-bar';
        this.root.setAttribute('data-workbench-shell-footer', '');
        this.root.innerHTML = '<div class="npcshop-live-trade-summary" data-live-trade-summary></div>'
            + '<div class="npcshop-live-trade-actions">'
            + '<button type="button" class="workbench-mode-btn npcshop-bar-clear-btn" data-live-clear data-audio-cue="back" hidden>清空</button>'
            + '<button type="button" class="workbench-mode-btn npcshop-checkout-btn" data-live-detail data-audio-cue="open">明细核对</button>'
            + '<button type="button" class="workbench-mode-btn npcshop-bar-commit-btn" data-live-commit data-audio-cue="activate">完成交易</button>'
            + '</div>';
        this._summary = this.root.querySelector('[data-live-trade-summary]');
        this._clearBtn = this.root.querySelector('[data-live-clear]');
        this._detailBtn = this.root.querySelector('[data-live-detail]');
        this._commitBtn = this.root.querySelector('[data-live-commit]');
        this._clearBtn.addEventListener('click', this._ports.onClear);
        this._detailBtn.addEventListener('click', this._ports.onOpenSettlement);
        this._commitBtn.addEventListener('click', this._ports.onDirectTrade);
        if (options.host) options.host.appendChild(this.root);
    }
    function computePurchaseLineTotal(item, quantity, buyRatePermille) {
        var qty = Math.max(1, Math.floor(Number(quantity) || 1));
        var base = item && item.basePrice != null ? Number(item.basePrice) : NaN;
        var rate = buyRatePermille != null ? Number(buyRatePermille) : NaN;
        if (isFinite(base) && base >= 0 && isFinite(rate) && rate >= 0) {
            return Math.floor((base * qty * rate) / 1000);
        }
        return qty * Number(item && item.unitPrice || 0);
    }

    function captureDirectQuote(payload, purchaseIntents, saleIntents, shortcutIntent, state) {
        payload = payload || {};
        var purchases = Array.isArray(payload.purchases) ? payload.purchases : [];
        var sales = Array.isArray(payload.sales) ? payload.sales : [];
        var catalog = state && Array.isArray(state.catalog) ? state.catalog : [];
        var rate = state && state.buyRatePermille != null ? state.buyRatePermille : null;
        var buyLines = {}, buyTotal = 0;
        for (var i = 0; i < purchases.length; i++) {
            var req = purchases[i], key = String(req.catalogIndex);
            var item = (shortcutIntent && shortcutIntent.kind === 'purchase' && String(shortcutIntent.key) === key)
                ? shortcutIntent.intent && shortcutIntent.intent.item
                : (purchaseIntents && purchaseIntents[key] && purchaseIntents[key].item);
            if (!item) {
                for (var c = 0; c < catalog.length; c++) {
                    if (Number(catalog[c].catalogIndex) === Number(req.catalogIndex)) { item = catalog[c]; break; }
                }
            }
            var qty = Math.max(1, Math.floor(Number(req.quantity) || 1));
            var total = computePurchaseLineTotal(item, qty, rate);
            buyLines[key] = {quantity:qty, total:total};
            buyTotal += total;
        }
        var hasBulkSale = false, saleLines = {}, sellTotal = 0, hasUnknownSellPrice = false;
        for (var j = 0; j < sales.length; j++) {
            var sReq = sales[j] || {};
            if (sReq.scope === 'same_name') hasBulkSale = true;
            var src = sReq.source || {};
            var sId = src.containerId === '背包' ? ('bag:' + Number(src.slot)) : ('material:' + String(src.key || ''));
            var sIntent = (shortcutIntent && shortcutIntent.kind === 'sale' && String(shortcutIntent.key) === sId)
                ? shortcutIntent.intent : (saleIntents && saleIntents[sId]);
            var sItem = sIntent && sIntent.item;
            var sQty = Math.max(1, Math.floor(Number(sReq.quantity) || 1));
            var rawSell = sItem && sItem.sellPrice != null ? Number(sItem.sellPrice) : NaN;
            var knownTotal = isFinite(rawSell) && rawSell >= 0 ? Math.floor(rawSell * sQty) : null;
            if (knownTotal == null) hasUnknownSellPrice = true; else sellTotal += knownTotal;
            saleLines[sId] = {scope:String(sReq.scope || 'slot'), quantity:sQty, knownTotal:knownTotal};
        }
        return {purchaseCount:purchases.length, buyLines:buyLines, buyTotal:buyTotal,
            saleCount:sales.length, saleLines:saleLines, sellTotal:sellTotal,
            hasBulkSale:hasBulkSale, hasUnknownSellPrice:hasUnknownSellPrice};
    }

    function describeQuoteDrift(expected, preview) {
        if (!expected || !preview) return '';
        var pLines = Array.isArray(preview.purchaseLines) ? preview.purchaseLines : [];
        var sLines = Array.isArray(preview.saleLines) ? preview.saleLines : [];
        if (pLines.length !== expected.purchaseCount) return '待购清单项数与当前核价不一致，请核对后再确认交易。';
        for (var i = 0; i < pLines.length; i++) {
            var line = pLines[i], exp = expected.buyLines[String(line.catalogIndex)];
            if (!exp || Number(line.quantity) !== exp.quantity) return '待购数量已变化，请核对最新报价后再确认交易。';
            if (Number(line.total) !== exp.total) {
                return '商品报价已变化（原显示 $' + expected.buyTotal.toLocaleString()
                    + ' → 最新 $' + Number(preview.buyTotal || 0).toLocaleString() + '），请核对后再确认交易。';
            }
        }
        if (expected.purchaseCount > 0 && Number(preview.buyTotal || 0) !== expected.buyTotal) {
            return '商品报价已变化（原显示 $' + expected.buyTotal.toLocaleString()
                + ' → 最新 $' + Number(preview.buyTotal || 0).toLocaleString() + '），请核对后再确认交易。';
        }
        if (!expected.hasBulkSale) {
            if (sLines.length !== expected.saleCount) return '待售清单与当前核价不一致，请核对后再确认交易。';
            if (expected.saleCount > 0 && expected.hasUnknownSellPrice) {
                return '出售价格已核定（$' + Number(preview.sellTotal || 0).toLocaleString() + '），请确认后再交易。';
            }
            for (var s = 0; s < sLines.length; s++) {
                var sLine = sLines[s], sExp = expected.saleLines && expected.saleLines[String(sLine.sourceIdentity || '')];
                if (!sExp || String(sLine.scope || 'slot') !== sExp.scope || Number(sLine.quantity) !== sExp.quantity) {
                    return '待售条目已变化，请核对最新报价后再确认交易。';
                }
                if (sExp.knownTotal != null && Number(sLine.total) !== sExp.knownTotal) {
                    return '出售报价已变化（原显示 $' + expected.sellTotal.toLocaleString()
                        + ' → 最新 $' + Number(preview.sellTotal || 0).toLocaleString() + '），请核对后再确认交易。';
                }
            }
            if (expected.saleCount > 0 && !expected.hasUnknownSellPrice && Number(preview.sellTotal || 0) !== expected.sellTotal) {
                return '出售报价已变化（原显示 $' + expected.sellTotal.toLocaleString()
                    + ' → 最新 $' + Number(preview.sellTotal || 0).toLocaleString() + '），请核对后再确认交易。';
            }
        }
        return '';
    }

    LiveTradeBar.prototype.update = function(state) {
        state = state || {};
        var purchases = state.purchases || {};
        var sales = state.sales || {};
        var buyLines = Object.keys(purchases), sellLines = Object.keys(sales);
        var buyCount = 0, buyTotal = 0, sellCount = 0, sellTotal = 0, hasBulk = false;
        for (var i = 0; i < buyLines.length; i++) {
            var p = purchases[buyLines[i]];
            var pq = Math.max(1, Number(p && p.quantity) || 1);
            buyCount += pq;
            buyTotal += computePurchaseLineTotal(p && p.item, pq, state.buyRatePermille);
        }
        for (var j = 0; j < sellLines.length; j++) {
            var s = sales[sellLines[j]];
            var sq = Math.max(1, Number(s && s.quantity) || 1);
            if (s && s.scope === 'same_name') hasBulk = true;
            sellCount += sq;
            var unitSell = Number(s && s.item && (s.item.sellPrice != null ? s.item.sellPrice : s.item.unitPrice) || 0);
            sellTotal += sq * unitSell;
        }
        var totalLines = buyLines.length + sellLines.length;
        if (!totalLines) {
            this._summary.innerHTML = '<span class="npcshop-live-hint">单击商品加购 · 单击背包待售 · 双击快捷交易</span>';
        } else {
            var parts = [];
            if (buyLines.length) parts.push('<span class="npcshop-live-buy">待购 ' + buyCount + ' 件 (-' + buyTotal.toLocaleString() + ' 金币)</span>');
            if (sellLines.length) parts.push('<span class="npcshop-live-sell">待售 ' + sellCount + ' 件' + (hasBulk ? ' · 含同名全售' : '（结算核价）') + '</span>');
            var authTrade = state.preview && (state.preview.buyTotal != null && state.preview.sellTotal != null ? state.preview : state.preview.trade);
            if (authTrade && authTrade.buyTotal != null && authTrade.sellTotal != null) {
                var authNet = Number(authTrade.sellTotal) - Number(authTrade.buyTotal);
                var authSign = authNet >= 0 ? '+' : '−';
                parts.push('<strong class="npcshop-live-net ' + (authNet < 0 ? 'negative' : 'positive') + '">净变动 ' + authSign + Math.abs(authNet).toLocaleString() + ' 金币</strong>');
            } else if (!sellLines.length && buyTotal > 0) {
                parts.push('<strong class="npcshop-live-net negative">净变动 −' + buyTotal.toLocaleString() + ' 金币</strong>');
            }
            this._summary.innerHTML = parts.join('');
        }
        var blocked = !!state.disabled;
        this._clearBtn.hidden = !totalLines;
        this._clearBtn.disabled = blocked || !totalLines;
        this._detailBtn.textContent = totalLines ? '明细核对 (' + totalLines + ')' : '明细核对';
        this._detailBtn.disabled = blocked || !totalLines;
        this._commitBtn.disabled = blocked || !totalLines;
    };
    LiveTradeBar.prototype.destroy = function() {
        this._clearBtn.removeEventListener('click', this._ports.onClear);
        this._detailBtn.removeEventListener('click', this._ports.onOpenSettlement);
        this._commitBtn.removeEventListener('click', this._ports.onDirectTrade);
        if (this.root.parentNode) this.root.parentNode.removeChild(this.root);
    };

    function createOwnedView(options) {
        options = options || {};
        var documentRef = options.document;
        var inventoryUI = options.inventoryUI;
        var workbench = options.workbench;
        var components = options.components;
        var viewId = String(options.viewId || '');
        var title = String(options.title || '');
        var canSell = !!options.canSell;
        var getView = requirePort(options, 'getView');
        var getSaleIntents = requirePort(options, 'getSaleIntents');
        var iconHtml = requirePort(options, 'iconHtml');
        var saleIdentity = requirePort(options, 'saleIdentity');
        var bindOwnedTooltip = requirePort(options, 'bindOwnedTooltip');
        var interaction = requirePort(options, 'interaction');
        var toast = requirePort(options, 'toast');
        var toggleSale = requirePort(options, 'toggleSale');
        var onRemoveSale = typeof options.onRemoveSale === 'function' ? options.onRemoveSale : null;
        var onQuickBulkSale = typeof options.onQuickBulkSale === 'function' ? options.onQuickBulkSale : null;
        var onQuickTrade = typeof options.onQuickTrade === 'function' ? options.onQuickTrade : null;
        var ownedShell = new inventoryUI.OwnedInventoryViewShell({
            containerId:viewId,
            instanceKey:'npcshop:' + viewId,
            itemModel:'owned',
            getItems:function() {
                var view = getView(viewId);
                return view && view.slots ? view.slots : [];
            },
            keyOf:function(slot) {
                return viewId === 'bag' ? slot.physicalSlot : slot.collectionKey;
            },
            renderItem:function(slot) {
                var node = inventoryUI.renderOwnedSlot(viewId === 'bag' ? '背包' : title,
                    slot, {iconHtml:iconHtml, allowDiscard:false});
                if (!slot.occupied) return node;
                node.classList.add('npcshop-owned-card');
                if (canSell) {
                    var intents = getSaleIntents();
                    var identity = saleIdentity(viewId, slot);
                    var intent = intents[identity];
                    var selected = !!intent;
                    node.classList.toggle('selected', selected);
                    node.classList.toggle('item-card-selected', selected);
                    node.setAttribute('aria-pressed', selected ? 'true' : 'false');
                    var marker = documentRef.createElement('span');
                    marker.className = 'item-card-auxiliary item-card-selection-marker npcshop-selection-marker';
                    marker.textContent = selected
                        ? (intent.scope === 'same_name' ? '同名全售' : '待售 ×' + intent.quantity) : '';
                    marker.hidden = !selected;
                    node.appendChild(marker);
                    var removeBtn = documentRef.createElement('button');
                    removeBtn.type = 'button';
                    removeBtn.className = 'npcshop-intent-remove';
                    removeBtn.textContent = '×';
                    removeBtn.setAttribute('aria-label', '取消待售');
                    removeBtn.hidden = !selected;
                    node.appendChild(removeBtn);
                    if (onQuickBulkSale && isPlainBagEquipment(viewId, slot)) {
                        var bulkBtn = documentRef.createElement('button');
                        bulkBtn.type = 'button';
                        bulkBtn.className = 'npcshop-same-name-btn';
                        bulkBtn.textContent = '同名全售';
                        bulkBtn.setAttribute('aria-label', '按同名全售未强化且无插件的基础装备');
                        node.appendChild(bulkBtn);
                    }
                } else {
                    node.classList.add('read-only');
                    node.setAttribute('aria-readonly', 'true');
                }
                return node;
            },
            bindItem:function(node, slot) {
                if (slot && slot.occupied) bindOwnedTooltip(node, viewId, slot);
                var item = slot && slot.item || {};
                var itemName = String(item.displayName || '未知物品');
                var reasonNode = ensureReasonNode(node);
                var removeBtn = node.querySelector('.npcshop-intent-remove');
                if (removeBtn && canSell && slot && slot.occupied && onRemoveSale) {
                    removeBtn.addEventListener('click', function(event) {
                        event.stopPropagation();
                        onRemoveSale(viewId, slot);
                    });
                }
                var bulkBtn = node.querySelector('.npcshop-same-name-btn');
                if (bulkBtn && canSell && slot && slot.occupied && onQuickBulkSale) {
                    bulkBtn.addEventListener('click', function(event) {
                        event.stopPropagation();
                        onQuickBulkSale(slot);
                    });
                }
                if (canSell && slot && slot.occupied && onQuickTrade) {
                    node.addEventListener('dblclick', function(event) {
                        if (event.target && event.target.closest && event.target.closest('button')) return;
                        event.preventDefault();
                        onQuickTrade(viewId, slot, true);
                    });
                    node.addEventListener('contextmenu', function(event) {
                        if (event.target && event.target.closest && event.target.closest('button')) return;
                        event.preventDefault();
                        onQuickTrade(viewId, slot, false);
                    });
                }
                workbench.EntityTile.bindActivation(node, {
                    itemName:itemName,
                    label:node.getAttribute('aria-label') || itemName,
                    selected:slot && slot.occupied && canSell
                        && !!getSaleIntents()[saleIdentity(viewId, slot)],
                    inspectable:!!slot && slot.occupied,
                    actionable:function() {
                        return !!slot && slot.occupied && interaction(viewId).actionable;
                    },
                    reason:function() {
                        return slot && slot.occupied ? interaction(viewId).reason : '';
                    },
                    reasonNode:reasonNode,
                    onBlocked:function() { toast(interaction(viewId).reason); cue('illegal'); },
                    onActivate:canSell && slot && slot.occupied
                        ? function(event) { toggleSale(viewId, slot, event); } : null
                });
                node.__npcOwnedInteractionRefresh = function() {
                    var projection = interaction(viewId);
                    if (!slot || !slot.occupied) {
                        projection = {inspectable:false, actionable:false, reason:''};
                    }
                    projectNode(workbench, node, projection, reasonNode);
                    node.classList.toggle('write-locked', !projection.actionable);
                };
                node.__npcOwnedInteractionRefresh();
            },
            title:title,
            meta:'同步中',
            emptyText:'暂无' + title,
            className:'npcshop-owned-view npcshop-' + viewId + '-view',
            gridClassName:'npcshop-owned-grid',
            allowedSlots:['R'],
            layoutMode:options.layoutMode || 'full',
            densityController:options.densityController
        });
        ownedShell.view.viewId = viewId;
        var pane = new components.OwnedInventoryPane({
            view:ownedShell.view,
            shell:ownedShell,
            getSnapshot:function() { return getView(viewId); },
            keyOf:function(slot) { return slot ? saleIdentity(viewId, slot) : ''; },
            interaction:interaction(viewId),
            onInteractionChange:function() {
                var nodes = ownedShell.view.root.querySelectorAll('.inventory-slot-card');
                for (var index = 0; index < nodes.length; index++) {
                    if (nodes[index].__npcOwnedInteractionRefresh) {
                        nodes[index].__npcOwnedInteractionRefresh();
                    }
                }
            }
        });
        return {view:pane.view, pane:pane};
    }

    function syncOwnedIntentCard(options, viewId, slot, targetNode) {
        if (viewId === 'intelligence') return;
        var view = options.getRightView(viewId);
        var renderer = view && view.ownedInventoryShell && view.ownedInventoryShell.view.renderer;
        if (!renderer || !slot) return;
        var key = String(viewId === 'bag' ? slot.physicalSlot : slot.collectionKey);
        var nodes = targetNode ? [targetNode] : renderer.root.querySelectorAll('[data-workbench-key]');
        var intents = options.getSaleIntents();
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].getAttribute('data-workbench-key') !== key) continue;
            var identity = options.saleIdentity(viewId, slot);
            var intent = intents[identity];
            var selected = !!intent;
            var pane = options.getOwnedPane(viewId);
            if (pane) pane.setSelected(slot, selected);
            nodes[i].classList.toggle('selected', selected);
            nodes[i].classList.toggle('item-card-selected', selected);
            nodes[i].setAttribute('aria-pressed', selected ? 'true' : 'false');
            options.workbench.EntityTile.setSelected(nodes[i], selected);
            var marker = nodes[i].querySelector('.npcshop-selection-marker');
            if (marker) {
                marker.textContent = selected
                    ? (intent.scope === 'same_name' ? '同名全售' : '待售 ×' + intent.quantity) : '';
                marker.hidden = !selected;
            }
            var removeBtn = nodes[i].querySelector('.npcshop-intent-remove');
            if (removeBtn) removeBtn.hidden = !selected;
            return;
        }
    }

    function renderCatalogCard(options, item) {
        var intents = options.getPurchaseIntents();
        var intent = intents[String(item.catalogIndex)];
        var selected = !!intent;
        var atLimit = isFinite(Number(item.maxQuantity)) && Number(item.maxQuantity) <= 0;
        var markerText = item.locked ? '未解锁' : (atLimit ? '已达持有上限'
            : (selected ? '待购 ×' + intent.quantity : ''));
        var lockTitle = atLimit ? '已达持有上限'
            : (item.requiredInfo ? '需要情报：' + item.requiredInfo : '尚未解锁');
        var card = options.workbench.ItemCard.renderCatalog({
            skin:'npcshop', item:item, id:item.catalogIndex,
            iconHtml:options.iconHtml(item.icon, 'kshop-icon'),
            name:item.displayName,
            meta:options.itemFilter.catalogPath(item).map(function(part) {
                return part.label;
            }).join(' · '),
            priceText:'$ ' + Number(item.unitPrice || 0).toLocaleString(),
            locked:item.locked || atLimit,
            lockTitle:lockTitle,
            selected:selected,
            balanceSummary:item.balanceSummary,
            markerText:markerText
        });
        var marker = card.querySelector('.npcshop-selection-marker');
        if (marker) marker.hidden = !markerText;
        var doc = options.document || document;
        if (!item.locked && !atLimit) {
            var removeBtn = doc.createElement('button');
            removeBtn.type = 'button';
            removeBtn.className = 'npcshop-intent-remove';
            removeBtn.textContent = '×';
            removeBtn.setAttribute('aria-label', '取消待购 ' + item.displayName);
            removeBtn.hidden = !selected;
            card.appendChild(removeBtn);
        }
        if (options.components && options.components.ProcurementHighlight) {
            options.components.ProcurementHighlight.decorateCard(
                card, item.procurement, doc);
        }
        return card;
    }

    function syncCatalogIntentCard(options, item, targetNode) {
        var renderer = options.getCatalogRenderer();
        if (!renderer || !item) return;
        var intents = options.getPurchaseIntents();
        var key = String(item.catalogIndex);
        var nodes = targetNode ? [targetNode]
            : renderer.root.querySelectorAll('[data-workbench-key]');
        for (var index = 0; index < nodes.length; index++) {
            if (nodes[index].getAttribute('data-workbench-key') !== key) continue;
            var intent = intents[key];
            var selected = !!intent;
            nodes[index].classList.toggle('selected', selected);
            nodes[index].classList.toggle('item-card-selected', selected);
            nodes[index].setAttribute('aria-pressed', selected ? 'true' : 'false');
            options.workbench.EntityTile.setSelected(nodes[index], selected);
            var marker = nodes[index].querySelector('.npcshop-selection-marker');
            var atLimit = isFinite(Number(item.maxQuantity)) && Number(item.maxQuantity) <= 0;
            var text = item.locked ? '未解锁'
                : (atLimit ? '已达持有上限' : (selected ? '待购 ×' + intent.quantity : ''));
            if (marker) {
                marker.textContent = text;
                marker.hidden = !text;
            }
            var removeBtn = nodes[index].querySelector('.npcshop-intent-remove');
            if (removeBtn) removeBtn.hidden = !selected;
            return;
        }
    }

    function decorateCategoryButtons(toolbar, tree, itemFilter, mode) {
        if (!toolbar) return;
        var buttons = toolbar.querySelectorAll('[data-filter-path]');
        for (var i = 0; i < buttons.length; i++) {
            var path = String(buttons[i].getAttribute('data-filter-path') || '').split('/').filter(Boolean);
            var labels = [], node = tree;
            for (var depth = 0; depth < path.length; depth++) {
                node = itemFilter.nodeAt(node, [path[depth]]);
                if (!node) break;
                labels.push(node.label);
            }
            var legacyPath = mode === 'auto' ? labels : path;
            buttons[i].setAttribute('data-category', mode + ':' + (legacyPath.length ? legacyPath.join(':') : 'all'));
            buttons[i].setAttribute('data-audio-cue', 'select');
        }
    }

    function matchesCategory(state, category, itemFilter, item) {
        var sections = state && state.layout && Array.isArray(state.layout.sections) ? state.layout.sections : [];
        if (category && category.mode === 'combined') {
            var browsePath = category.path || [];
            if (!browsePath.length) return true;
            if (browsePath.length === 1) return browsePath[0] === 'set' ? itemFilter.setPath(item).length > 0 : true;
            if (browsePath[0] === 'category') return itemFilter.matchesPath(item, browsePath.slice(1), function(e) { return itemFilter.catalogPath(e); });
            if (browsePath[0] === 'set') return itemFilter.matchesPath(item, browsePath.slice(1), itemFilter.setPath);
            if (browsePath[0] === 'curated') {
                for (var i = 0; i < sections.length; i++) {
                    if (String(sections[i].id) === String(browsePath[1])) return (sections[i].entries || []).indexOf(Number(item.catalogIndex)) >= 0;
                }
            }
            return false;
        }
        var selected = category && category.mode === 'auto' ? (category.path || []) : [];
        return itemFilter.matchesPath(item, selected, function(e) { return itemFilter.catalogPath(e); });
    }

    function fullBag(snapshots) {
        if (!Array.isArray(snapshots)) return null;
        return snapshots.find(function(snapshot) {
            return snapshot && snapshot.containerId === '背包' && String(snapshot.filterKey || 'all') === 'all'
                && !snapshot.filterSpec && !snapshot.offset && Array.isArray(snapshot.slots);
        }) || null;
    }

    function selectionPayload(shopId, draft) {
        var purchases = [], sales = [];
        Object.keys(draft.purchases).sort(function(a,b) { return Number(a)-Number(b); }).forEach(function(key) {
            var line = draft.purchases[key]; purchases.push({catalogIndex:line.catalogIndex, quantity:line.quantity});
        });
        Object.keys(draft.sales).sort().forEach(function(key) {
            var line = draft.sales[key];
            if (line.scope === 'same_name') sales.push({source:line.source, scope:'same_name', policy:'plain_only'});
            else sales.push({source:line.source, quantity:line.quantity, scope:'slot'});
        });
        return {shopId:shopId, purchases:purchases, sales:sales};
    }

    function requiresTradeReview(payload, preview, sc, saleIntents, isPlain) {
        var sales = payload && Array.isArray(payload.sales) ? payload.sales : [], qty = 0;
        for (var i = 0; i < sales.length; i++) {
            if (sales[i].scope === 'same_name') return true;
            qty += Number(sales[i].quantity || 0);
        }
        var sellTotal = Number(preview && (preview.sellTotal != null ? preview.sellTotal : preview.trade && preview.trade.sellTotal) || 0);
        if (qty > 1 || sellTotal >= 50000) return true;
        var list = sc ? (sc.kind === 'sale' ? [sc.intent] : []) : Object.keys(saleIntents).map(function(k) { return saleIntents[k]; });
        for (var j = 0; j < list.length; j++) {
            var it = list[j] && list[j].item;
            if (it && it.itemKind === 'equipment' && !isPlain(it)) return true;
        }
        return false;
    }

    function rebindSaleIntents(saleIntents, views, isPlainFn) {
        var bag = views && views.bag, material = views && views.material;
        var next = {}, dropped = 0, changed = false;
        Object.keys(saleIntents || {}).forEach(function(oldIdentity) {
            var intent = saleIntents[oldIdentity], slot = null, identity = oldIdentity;
            var previousLease = intent.source && intent.source.expectedLease;
            if (intent.source && intent.source.containerId === '背包' && !bag) {
                next[oldIdentity] = intent;
                return;
            }
            if (intent.source && intent.source.containerId === '背包') {
                var slots = bag && bag.slots ? bag.slots : [];
                for (var i = 0; i < slots.length; i++) {
                    if (!slots[i].occupied || String(slots[i].item && slots[i].item.name) !== String(intent.item && intent.item.name)) continue;
                    if (intent.scope === 'same_name' && isPlainFn(slots[i].item)) {
                        slot = slots[i]; break;
                    }
                    if (intent.scope !== 'same_name'
                            && Number(slots[i].physicalSlot) === Number(intent.source.slot)
                            && String(slots[i].slotLease) === String(intent.source.expectedLease)
                            && Number(slots[i].item.quantity) >= Number(intent.quantity)) {
                        slot = slots[i]; break;
                    }
                }
                if (slot) {
                    intent.maxQuantity = Number(slot.item.quantity);
                    identity = 'bag:' + Number(slot.physicalSlot);
                    intent.identity = identity;
                    intent.source = {containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)};
                }
            } else if (!material) {
                slot = {slotLease:intent.source && intent.source.expectedLease};
            } else {
                var materialSlots = material && material.slots ? material.slots : [];
                for (var j = 0; j < materialSlots.length; j++) {
                    if (String(materialSlots[j].collectionKey) === String(intent.source && intent.source.key)) { slot = materialSlots[j]; break; }
                }
                if (slot && (!slot.occupied || !slot.item || !intent.item || String(slot.item.name) !== String(intent.item.name)
                        || Number(slot.item.quantity) < Number(intent.quantity))) slot = null;
                if (slot) {
                    intent.maxQuantity = Number(slot.item.quantity);
                    intent.source.expectedLease = String(slot.slotLease);
                }
            }
            if (slot && !next[identity]) {
                next[identity] = intent;
                if (oldIdentity !== identity || previousLease !== intent.source.expectedLease) changed = true;
            } else dropped++;
        });
        return {next:next, dropped:dropped, changed:changed || dropped > 0};
    }

    function buildSingleTradePayload(shopId, kind, target) {
        var payload = {shopId:shopId, purchases:[], sales:[]};
        if (kind === 'purchase') {
            if (!target || target.locked || (isFinite(Number(target.maxQuantity)) && Number(target.maxQuantity) <= 0)) return null;
            payload.purchases.push({catalogIndex:Number(target.catalogIndex), quantity:1});
            return payload;
        }
        var vid = target && target.viewId, slot = target && target.slot;
        if (!slot || !slot.occupied || vid === 'intelligence') return null;
        var src = vid === 'bag'
            ? {containerId:'背包', slot:Number(slot.physicalSlot), expectedLease:String(slot.slotLease)}
            : {viewId:'material', key:String(slot.collectionKey), expectedLease:String(slot.slotLease)};
        payload.sales.push({source:src, quantity:1, scope:'slot'});
        return payload;
    }

    function syncAllIntentCards(options) {
        var catalogRenderer = options.getCatalogRenderer();
        var catalogNodes = catalogRenderer ? catalogRenderer.root.querySelectorAll('[data-workbench-key]') : [];
        for (var c = 0; c < catalogNodes.length; c++) {
            syncCatalogIntentCard(options, catalogNodes[c].__workbenchItem, catalogNodes[c]);
        }
        var rightViews = options.rightViews || {};
        for (var viewId in rightViews) {
            var view = rightViews[viewId];
            var renderer = view && view.ownedInventoryShell && view.ownedInventoryShell.view.renderer;
            var slotNodes = renderer ? renderer.root.querySelectorAll('[data-workbench-key]') : [];
            for (var s = 0; s < slotNodes.length; s++) {
                var slot = slotNodes[s].__workbenchItem;
                if (slot && slot.occupied) syncOwnedIntentCard(options, viewId, slot, slotNodes[s]);
            }
        }
    }

    return {
        SettlementPresenter:SettlementPresenter,
        HelpPresenter:HelpPresenter,
        SpaceOrganizerPresenter:SpaceOrganizerPresenter,
        LiveTradeBar:LiveTradeBar,
        decorateCategoryButtons:decorateCategoryButtons,
        matchesCategory:matchesCategory,
        fullBag:fullBag,
        requiresTradeReview:requiresTradeReview,
        selectionPayload:selectionPayload,
        rebindSaleIntents:rebindSaleIntents,
        buildSingleTradePayload:buildSingleTradePayload,
        computePurchaseLineTotal:computePurchaseLineTotal,
        captureDirectQuote:captureDirectQuote,
        describeQuoteDrift:describeQuoteDrift,
        syncAllIntentCards:syncAllIntentCards,
        settlementViewModel:settlementViewModel,
        settlementInspection:settlementInspection,
        spaceStatus:spaceStatus,
        ownedInteraction:ownedInteraction,
        bindCatalogActivation:bindCatalogActivation,
        createOwnedView:createOwnedView,
        syncOwnedIntentCard:syncOwnedIntentCard,
        renderCatalogCard:renderCatalogCard,
        syncCatalogIntentCard:syncCatalogIntentCard,
        ensureReasonNode:ensureReasonNode,
        projectNode:projectNode,
        bindOwnedTooltip:bindOwnedTooltip,
        tooltipBasic:tooltipBasic,
        tooltipRich:tooltipRich,
        errorMessage:errorMessage
    };
});
