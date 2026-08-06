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

    function settlementViewModel(settlement, ui, errorMessage) {
        settlement = settlement || {};
        ui = ui || {};
        errorMessage = typeof errorMessage === 'function' ? errorMessage : function(error) { return String(error || ''); };
        var blockingError = settlement.blockingError || '';
        var sales = settlement.saleLines || [];
        var context = '待购和待售都只是清单；点击“确认交易”后整单才会一次生效。';
        if (blockingError === 'inventory_full') {
            context = '背包空间不足：可先整理背包与战备箱，返回后订单会自动重新核算。';
        } else if (sales.some(function(line) { return line.scope === 'same_name'; })) {
            context = '同名全售只出售普通实例，强化、进阶和带插件装备会自动保护。';
        }
        return {
            status:blockingError ? errorMessage(blockingError) : '整单可提交',
            context:context,
            organizeVisible:blockingError === 'inventory_full',
            organizeDisabled:!!(ui.busy || ui.previewBusy || ui.spaceBusy),
            commitBusy:!!(ui.busy || ui.previewBusy),
            canCommit:!!settlement.canCommit,
            commitState:blockingError ? 'blocked' : 'ready'
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
            + '<button type="button" data-trade-back>← 返回选购</button>'
            + '<button type="button" data-trade-help aria-label="商店操作帮助">？</button>'
            + '<button type="button" data-trade-close aria-label="关闭 NPC 商店">×</button></div>'
            + '<div><h2>交易结算</h2><p data-trade-context>价格与容量由游戏实时核算；确认后整单一次生效。</p></div>'
            + '</header>'
            + '<div class="npcshop-settlement-columns"><section><h3>待购</h3><div class="npcshop-settlement-list" data-purchase-lines></div></section>'
            + '<section><h3>待售</h3><div class="npcshop-settlement-list" data-sale-lines></div></section></div>'
            + '<footer class="npcshop-settlement-summary"><div data-trade-economy></div><span data-trade-error></span>'
            + '<button type="button" data-space-organize hidden>整理空间</button>'
            + '<button type="button" data-trade-commit>确认交易</button></footer>';
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
        this._renderLines('purchase', settlement.purchaseLines || [], intents.purchases || {}, ui);
        this._renderLines('sale', settlement.saleLines || [], intents.sales || {}, ui);
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
            + '<button type="button" data-help-back>← 返回商店</button>'
            + '<button type="button" data-help-close aria-label="关闭 NPC 商店">×</button></div>'
            + '<div><h2>商店操作帮助</h2><p>所有选择都可以在确认交易前调整或取消。</p></div></header>'
            + '<div class="npcshop-help-grid">'
            + helpCard('01','选择商品','左侧点击商品加入待购；右侧点击背包或材料加入待售。','此时不会扣钱，也不会移除物品。','待购','待售')
            + helpCard('02','调整并结算','在结算页直接输入数字、拖动滑条，或用 −、+、+5、“最大”调整数量，再确认整张订单。','“最多可购”由金币、背包容量和商店限制共同决定。','调整数量','确认交易')
            + helpCard('03','同名全售','装备待售行可切换为“同名全售”，快速清理重复装备。','只出售普通实例；强化、进阶和带插件装备自动保护。','同名匹配','保护特殊装备')
            + helpCard('04','整理空间','背包不足时进入背包—战备箱整理页，点击物品即可快速转移。','返回后订单自动重算；商品不会直接购买到战备箱。','整理空间','返回重算')
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
        return options.workbench.EntityTile.bindActivation(options.node, {
            itemName:item.displayName,
            label:options.node.getAttribute('aria-label') || '',
            selected:!!options.selected,
            inspectable:true,
            actionable:!item.locked && !atLimit,
            reason:reason,
            reasonNode:options.node.querySelector('.item-card-interaction-reason'),
            onBlocked:function() { options.toast(reason); },
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
            metaHTML:workbench.ItemCard.balanceTooltipMetaHtml(item),
            rootClass:'npcshop-tooltip',
            layoutType:tooltip.inferLayoutType(item.majorType || item.use)
        });
    }

    function errorMessage(error) {
        var messages = {
            shop_not_found:'未找到该 NPC 的商店。', item_not_found:'商品或待售物品已经变化。', locked:'尚未获得所需情报。', insufficient_money:'金币不足。', inventory_full:'背包空间不足。',
            destination_full:'对应收集项已达持有上限。',
            stale_state:'物品状态已经变化。', invalid_price:'商品或售卖价格已经变化。', sell_forbidden:'该容器不允许出售。', insufficient_quantity:'物品数量不足。', duplicate_line:'交易清单包含重复物品。',
            invalid_payload:'交易清单包含无效数据。', invalid_quantity:'购买或出售数量无效。', nothing_to_sell:'没有可批量出售的普通实例。', target_full:'目标容器已满。', slot_locked:'该战备箱槽位尚未解锁。',
            busy:'商店正在处理另一项交易。', reconcile_required:'交易结果需要重新同步。', malformed_response:'交易回包不完整，需要重新核算。', invalid_response:'交易回包无效，需要重新核算。',
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
            onTransferResult:requirePort(options, 'onTransferResult'),
            iconHtml:requirePort(options, 'iconHtml'), toast:requirePort(options, 'toast')
        };
        this._state = {};
        this._interaction = ownedInteraction(this._state);
        this.root = this._document.createElement('section');
        this.root.className = 'npcshop-space-page';
        this.root.innerHTML = '<header class="npcshop-space-header"><button type="button" data-space-back>← 返回结算</button>'
            + '<div><h2>整理购买空间</h2><p>点击物品即可在背包与战备箱之间快速转移；返回后交易会重新核算。</p></div>'
            + '<span data-space-status>同步中</span></header>'
            + '<div class="npcshop-space-columns"><section><h3>背包 <small data-space-meta="背包"></small></h3><div class="npcshop-space-grid" data-space-grid="背包"></div></section>'
            + '<section><h3>战备箱 <span data-space-pager></span><small data-space-meta="战备箱"></small></h3><div class="npcshop-space-grid battlebox" data-space-grid="战备箱"></div></section></div>';
        this.secondary = new this._components.SecondaryPage({root:this.root, role:'dialog', ariaLabel:'整理购买空间'});
        this.secondary.bindBack(this.root.querySelector('[data-space-back]'), this._ports.onBack);
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
    SpaceOrganizerPresenter.prototype.open = function() { return this.secondary.open(); };
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

    return {
        SettlementPresenter:SettlementPresenter,
        HelpPresenter:HelpPresenter,
        SpaceOrganizerPresenter:SpaceOrganizerPresenter,
        settlementViewModel:settlementViewModel,
        settlementInspection:settlementInspection,
        spaceStatus:spaceStatus,
        ownedInteraction:ownedInteraction,
        bindCatalogActivation:bindCatalogActivation,
        ensureReasonNode:ensureReasonNode,
        projectNode:projectNode,
        bindOwnedTooltip:bindOwnedTooltip,
        tooltipBasic:tooltipBasic,
        tooltipRich:tooltipRich,
        errorMessage:errorMessage
    };
});
