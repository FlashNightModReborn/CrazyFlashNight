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

    function SettlementPresenter(options) {
        options = options || {};
        this._document = options.document;
        this._components = options.components;
        if (!this._document || !this._components || !options.host) {
            throw new Error('SettlementPresenter requires document, components, and host');
        }
        this._ports = {
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
        this.root.innerHTML = '<header class="npcshop-settlement-header"><button type="button" data-trade-back>← 返回选购</button>'
            + '<div><h2>交易结算</h2><p data-trade-context>价格与容量由游戏实时核算；确认后整单一次生效。</p></div>'
            + '<button type="button" data-trade-help aria-label="商店操作帮助">？</button></header>'
            + '<div class="npcshop-settlement-columns"><section><h3>待购</h3><div class="npcshop-settlement-list" data-purchase-lines></div></section>'
            + '<section><h3>待售</h3><div class="npcshop-settlement-list" data-sale-lines></div></section></div>'
            + '<footer class="npcshop-settlement-summary"><div data-trade-economy></div><span data-trade-error></span>'
            + '<button type="button" data-space-organize hidden>整理空间</button>'
            + '<button type="button" data-trade-commit>确认交易</button></footer>';
        this.secondary = new this._components.SecondaryPage({
            root:this.root, role:'dialog', ariaLabel:'NPC 商店交易结算'
        });
        this.secondary.bindClose(this.root.querySelector('[data-trade-back]'), this._ports.onClose);
        this._helpButton = this.root.querySelector('[data-trade-help]');
        this._helpHandler = this._ports.onHelp;
        this._helpButton.addEventListener('click', this._helpHandler);
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
        var displayName = line.displayName || line.itemName;
        var iconKey = String(line.icon || line.itemName || '');
        if (record.iconKey !== iconKey) {
            record.iconKey = iconKey;
            record.icon.innerHTML = this._ports.iconHtml(iconKey, 'kshop-icon');
        }
        record.name.textContent = displayName;
        record.total.textContent = (kind === 'purchase' ? '-$' : '+$')
            + Number(line.total || 0).toLocaleString();
        var blocked = !!(ui.busy || ui.previewBusy);
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
    };
    SettlementPresenter.prototype._destroyLineRecord = function(record) {
        if (!record) return;
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
        this._helpButton.removeEventListener('click', this._helpHandler);
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
        this.root.innerHTML = '<header class="npcshop-help-header"><button type="button" data-help-back>← 返回商店</button>'
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
        this.secondary.bindClose(this.backButton, requirePort(options, 'onClose'));
        this.secondary.mount(options.host);
    }
    HelpPresenter.prototype.open = function(returnLabel) {
        this.backButton.textContent = returnLabel || '← 返回商店';
        this.secondary.open(); this.backButton.focus(); return true;
    };
    HelpPresenter.prototype.close = function(reason) { return this.secondary.close(reason || 'return'); };
    HelpPresenter.prototype.isActive = function() { return this.secondary.isActive(); };
    HelpPresenter.prototype.destroy = function() { return this.secondary.destroy(); };

    function spaceStatus(state) {
        state = state || {};
        return state.refreshRequired ? '同步失败' : state.busyOwner ? '转移中…' : state.ready ? '点击快速转移' : '同步中…';
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
        this._ports = {
            getWindow:requirePort(options, 'getWindow'), getRequest:requirePort(options, 'getRequest'),
            setWindow:requirePort(options, 'setWindow'), autoTransfer:requirePort(options, 'autoTransfer'),
            onBack:requirePort(options, 'onBack'), onPageResult:requirePort(options, 'onPageResult'),
            onTransferResult:requirePort(options, 'onTransferResult'),
            iconHtml:requirePort(options, 'iconHtml'), toast:requirePort(options, 'toast')
        };
        this._state = {};
        this.root = this._document.createElement('section');
        this.root.className = 'npcshop-space-page';
        this.root.innerHTML = '<header class="npcshop-space-header"><button type="button" data-space-back>← 返回结算</button>'
            + '<div><h2>整理购买空间</h2><p>点击物品即可在背包与战备箱之间快速转移；返回后交易会重新核算。</p></div>'
            + '<span data-space-status>同步中</span></header>'
            + '<div class="npcshop-space-columns"><section><h3>背包 <small data-space-meta="背包"></small></h3><div class="npcshop-space-grid" data-space-grid="背包"></div></section>'
            + '<section><h3>战备箱 <span data-space-pager></span><small data-space-meta="战备箱"></small></h3><div class="npcshop-space-grid battlebox" data-space-grid="战备箱"></div></section></div>';
        this.secondary = new this._components.SecondaryPage({root:this.root, role:'dialog', ariaLabel:'整理购买空间'});
        this.secondary.bindClose(this.root.querySelector('[data-space-back]'), this._ports.onBack);
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
            keyOf:function(slot) { return slot && slot.physicalSlot; },
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
        this.transferPane.setDisabled(!this._state.ready || !!this._state.busyOwner);
        this._renderGrid('背包'); this._renderGrid('战备箱');
        this.pager.setDisabled(!this._state.ready || !!this._state.busyOwner); this.pager.refresh();
        this.root.querySelector('[data-space-status]').textContent = spaceStatus(this._state);
        return true;
    };
    SpaceOrganizerPresenter.prototype._renderGrid = function(containerId) {
        var self = this;
        var grid = this._grids[containerId];
        while (grid.firstChild) grid.removeChild(grid.firstChild);
        var snapshot = this._ports.getWindow(containerId);
        var slots = snapshot && snapshot.slots ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            var node = this._inventoryUI.renderOwnedSlot(containerId, slot, {iconHtml:this._ports.iconHtml, allowDiscard:false});
            if (slot.occupied) {
                node.classList.add('npcshop-space-transferable');
                var transferAction = containerId === '背包' ? '移入战备箱' : '移入背包';
                node.setAttribute('aria-label', (node.getAttribute('aria-label') || '') + '，点击' + transferAction);
                (function(sourceContainer, sourceSlot, sourceNode) {
                    self._workbench.EntityTile.bindActivation(sourceNode, {
                        itemName:String(sourceSlot.item && (sourceSlot.item.displayName || sourceSlot.item.name) || '未知物品'),
                        label:sourceNode.getAttribute('aria-label') || '', disabled:false,
                        onActivate:function() { self.transfer(sourceContainer, sourceSlot); }
                    });
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
    SpaceOrganizerPresenter.prototype.transfer = function(containerId, slot) {
        if (!this._state.ready || this._state.busyOwner || !slot || !slot.occupied) return false;
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
        spaceStatus:spaceStatus
    };
});
