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
            onAdjust:requirePort(options, 'onAdjust'),
            onPurchaseMax:requirePort(options, 'onPurchaseMax'),
            onBulkSale:requirePort(options, 'onBulkSale'),
            onRemove:requirePort(options, 'onRemove'),
            onPurchaseBounds:requirePort(options, 'onPurchaseBounds'),
            onHelp:requirePort(options, 'onHelp'),
            onGuide:typeof options.onGuide === 'function' ? options.onGuide : noop,
            iconHtml:requirePort(options, 'iconHtml'),
            errorMessage:requirePort(options, 'errorMessage')
        };
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
    SettlementPresenter.prototype.renderLoading = function() {
        this.commitBar.update({label:'核算中…', busy:true, canCommit:false, state:'busy'});
    };
    SettlementPresenter.prototype.renderFailure = function(errorCode) {
        this.commitBar.update({
            label:'无法结算', status:this._ports.errorMessage(errorCode),
            disabled:true, canCommit:false, state:'error'
        });
    };
    SettlementPresenter.prototype.render = function(settlement, intents, ui) {
        if (!settlement) return false;
        intents = intents || {purchases:{}, sales:{}};
        this._renderLines('purchase', settlement.purchaseLines || [], intents.purchases || {});
        this._renderLines('sale', settlement.saleLines || [], intents.sales || {});
        this.root.querySelector('[data-trade-economy]').innerHTML = '<b>购买 -$' + Number(settlement.buyTotal || 0).toLocaleString() + '</b>'
            + '<b>出售 +$' + Number(settlement.sellTotal || 0).toLocaleString() + '</b>'
            + '<strong>结余 $' + Number(settlement.projectedBalance || 0).toLocaleString() + '</strong>'
            + '<small>需 ' + Number(settlement.requiredSlots || 0) + ' 格 / 可用 ' + Number(settlement.availableSlots || 0) + ' 格</small>';
        var vm = settlementViewModel(settlement, ui, this._ports.errorMessage);
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
    SettlementPresenter.prototype._renderLines = function(kind, lines, intents) {
        var self = this;
        var list = this.root.querySelector(kind === 'purchase' ? '[data-purchase-lines]' : '[data-sale-lines]');
        var previousScrollTop = list.scrollTop;
        var previousScrollLeft = list.scrollLeft;
        while (list.firstChild) list.removeChild(list.firstChild);
        if (!lines.length) {
            var empty = this._document.createElement('p');
            empty.className = 'npcshop-settlement-empty'; empty.textContent = '无'; list.appendChild(empty);
            list.scrollTop = previousScrollTop; list.scrollLeft = previousScrollLeft; return;
        }
        lines.forEach(function(line) {
            var identity = kind === 'purchase' ? String(line.catalogIndex) : String(line.sourceIdentity);
            var intent = intents[identity];
            if (!intent) return;
            if (kind === 'purchase') {
                self._ports.onPurchaseBounds(identity, {
                    purchaseLimit:Number(line.purchaseLimit || intent.maxQuantity || 1),
                    maxPurchasable:Math.max(0, Number(line.maxPurchasable || 0))
                });
            }
            var row = self._document.createElement('article'); row.className = 'npcshop-settlement-line';
            var icon = self._document.createElement('span'); icon.className = 'npcshop-card-icon';
            icon.innerHTML = self._ports.iconHtml(line.icon || line.itemName, 'kshop-icon');
            var copy = self._document.createElement('span'); copy.className = 'npcshop-settlement-copy';
            var name = self._document.createElement('b'); name.textContent = line.displayName || line.itemName;
            var total = self._document.createElement('small');
            total.textContent = (kind === 'purchase' ? '-$' : '+$') + Number(line.total || 0).toLocaleString();
            copy.appendChild(name); copy.appendChild(total);
            if (kind === 'purchase') {
                var bound = self._document.createElement('em');
                bound.textContent = '当前最多可购 ' + intent.maxPurchasable + ' / 单笔上限 ' + intent.purchaseLimit;
                copy.appendChild(bound);
            } else if (line.scope === 'same_name') {
                var bulk = self._document.createElement('em');
                bulk.textContent = '同名匹配 ' + Number(line.matchedCount || 0) + ' 格，售出 ' + Number(line.eligibleCount || 0)
                    + ' 格，保护 ' + Number(line.protectedCount || 0) + ' 格';
                copy.appendChild(bulk);
            }
            var stepper = self._document.createElement('span'); stepper.className = 'npcshop-stepper';
            var remove = self._stepButton('×', function() { self._ports.onRemove(kind, identity); }); remove.classList.add('remove');
            if (kind === 'purchase') {
                var minus = self._stepButton('−', function() { self._ports.onAdjust(kind, identity, -1); });
                var quantity = self._document.createElement('b'); quantity.textContent = String(intent.quantity);
                var plus = self._stepButton('+', function() { self._ports.onAdjust(kind, identity, 1); });
                var plusFive = self._stepButton('+5', function() { self._ports.onAdjust(kind, identity, 5); }); plusFive.classList.add('wide');
                var max = self._stepButton('最大', function() { self._ports.onPurchaseMax(identity); }); max.classList.add('wide');
                minus.disabled = intent.quantity <= 1;
                plus.disabled = intent.quantity >= intent.purchaseLimit;
                plusFive.disabled = intent.quantity >= intent.purchaseLimit;
                max.disabled = intent.maxPurchasable < 1 || intent.quantity === intent.maxPurchasable;
                stepper.appendChild(minus); stepper.appendChild(quantity); stepper.appendChild(plus);
                stepper.appendChild(plusFive); stepper.appendChild(max); stepper.appendChild(remove);
            } else if (line.scope === 'same_name') {
                var single = self._stepButton('只售此格', function() { self._ports.onBulkSale(identity, false); }); single.classList.add('wide');
                stepper.appendChild(single); stepper.appendChild(remove);
            } else {
                var saleMinus = self._stepButton('−', function() { self._ports.onAdjust(kind, identity, -1); });
                var saleQuantity = self._document.createElement('b'); saleQuantity.textContent = String(intent.quantity);
                var salePlus = self._stepButton('+', function() { self._ports.onAdjust(kind, identity, 1); });
                saleMinus.disabled = intent.quantity <= 1; salePlus.disabled = intent.quantity >= intent.maxQuantity;
                stepper.appendChild(saleMinus); stepper.appendChild(saleQuantity); stepper.appendChild(salePlus);
                if (line.itemKind === 'equipment') {
                    var all = self._stepButton('同名全售', function() { self._ports.onBulkSale(identity, true); }); all.classList.add('wide');
                    stepper.appendChild(all);
                }
                stepper.appendChild(remove);
            }
            row.appendChild(icon); row.appendChild(copy); row.appendChild(stepper); list.appendChild(row);
        });
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
            + helpCard('02','调整并结算','在结算页用 −、+、+5 或“最大”调整数量，再确认整张订单。','“最多可购”由金币、背包容量和商店限制共同决定。','调整数量','确认交易')
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
