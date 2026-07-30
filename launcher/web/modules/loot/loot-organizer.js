/** In-place loot inventory organizer. The tracked Host panel remains `loot`. */
(function(root, factory) {
    'use strict';
    var shared = typeof module !== 'undefined' && module.exports
        ? require('../panel-runtime.js') : root && root.PanelRuntime;
    var api = factory(shared);
    if (typeof module !== 'undefined' && module.exports) module.exports = api;
    if (root) root.LootOrganizer = api;
})(typeof window !== 'undefined' ? window : globalThis, function(PanelRuntime) {
    'use strict';

    if (!PanelRuntime || !PanelRuntime.PanelRequestMux) throw new Error('PanelRuntime is required');

    var COMMANDS = {snapshot:true, autoTransfer:true, discard:true};

    function opaque(value) {
        value = typeof value === 'string' ? value.trim() : '';
        return value && value.length <= 128 && /^[A-Za-z0-9._~-]+$/.test(value) ? value : '';
    }

    /** Inventory-domain mux scoped to the current Web loot instance. */
    function RequestMux(options) {
        options = options || {};
        var panelInstanceId = opaque(options.panelInstanceId);
        if (!panelInstanceId) throw new Error('valid loot panelInstanceId is required');
        this.panelInstanceId = panelInstanceId;
        this._mux = new PanelRuntime.PanelRequestMux({
            send:options.send,
            timeoutMs:options.timeoutMs,
            sessionNonce:options.sessionNonce,
            setTimer:options.setTimer,
            clearTimer:options.clearTimer,
            callPrefix:'loot-inventory',
            router:options.router || PanelRuntime.sharedResponseRouter,
            validateSession:function(session) {
                return session && session.panelInstanceId === panelInstanceId;
            },
            createMessage:function(context) {
                return {
                    type:'panel', domain:'inventory', panel:'loot',
                    panelInstanceId:panelInstanceId,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    payload:context.payload || {}
                };
            },
            validateResponse:function(data, entry) {
                return !!data && data.type === 'panel_resp' && data.domain === 'inventory'
                    && data.cmd === entry.cmd && data.callId === entry.callId
                    && data.panel === 'loot'
                    && data.panelInstanceId === panelInstanceId;
            },
            createSynthetic:function(context) {
                return {
                    type:'panel_resp', domain:'inventory', panel:'loot',
                    panelInstanceId:panelInstanceId,
                    cmd:context.entry.cmd, callId:context.entry.callId,
                    success:false,
                    error:context.error === 'not_sent' ? 'disconnected' : context.error,
                    clientSynthetic:true
                };
            },
            onProtocolError:options.onProtocolError
        });
    }

    RequestMux.prototype.openSession = function() {
        return this._mux.openSession({panelInstanceId:this.panelInstanceId});
    };
    RequestMux.prototype.request = function(cmd, payload, callback) {
        cmd = String(cmd || '');
        if (!Object.prototype.hasOwnProperty.call(COMMANDS,cmd)) return null;
        return this._mux.request(cmd, payload || {}, {
            kind:cmd,
            singleFlight:cmd === 'snapshot',
            write:cmd !== 'snapshot',
            sendError:'not_sent'
        }, callback);
    };
    RequestMux.prototype.destroy = function() { this._mux.destroy(); };
    RequestMux.prototype.debugState = function() { return this._mux.debugState(); };

    function requirePort(options, name) {
        if (typeof options[name] !== 'function') throw new Error('Loot organizer port is required: ' + name);
        return options[name];
    }

    function statusText(state) {
        state = state || {};
        if (state.returning) return '重新核对箱子…';
        if (state.refreshRequired) return '库存同步失败';
        if (state.busyOwner) return state.busyOwner === 'bootstrap' ? '读取库存…' : '转移中…';
        return state.ready ? '点击物品快速转移' : '等待库存同步';
    }

    function interactionForState(state) {
        state = state || {};
        if (state.returning) return {inspectable:true, actionable:false, reason:'正在重新核对当前箱子。'};
        if (state.refreshRequired) return {inspectable:true, actionable:false, reason:'库存同步失败，请先重试。'};
        if (!state.ready) return {inspectable:true, actionable:false, reason:'库存正在同步，请稍候。'};
        if (state.busyOwner) return {inspectable:true, actionable:false, reason:'库存正在处理另一项操作。'};
        return {inspectable:true, actionable:true, reason:''};
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

    function Presenter(options) {
        options = options || {};
        if (!options.document || !options.components || !options.inventoryUI
                || !options.workbench || !options.host) {
            throw new Error('Loot organizer requires presentation adapters and host');
        }
        this._document = options.document;
        this._components = options.components;
        this._inventoryUI = options.inventoryUI;
        this._workbench = options.workbench;
        this._ports = {
            getWindow:requirePort(options,'getWindow'),
            getRequest:requirePort(options,'getRequest'),
            setWindow:requirePort(options,'setWindow'),
            autoTransfer:requirePort(options,'autoTransfer'),
            onRequestDiscard:requirePort(options,'onRequestDiscard'),
            onBack:requirePort(options,'onBack'),
            onHelp:requirePort(options,'onHelp'),
            onClose:requirePort(options,'onClose'),
            onRetry:requirePort(options,'onRetry'),
            onPageResult:requirePort(options,'onPageResult'),
            onTransferResult:requirePort(options,'onTransferResult'),
            iconHtml:requirePort(options,'iconHtml'),
            toast:requirePort(options,'toast')
        };
        this._state = {};
        this._interaction = interactionForState(this._state);
        this.root = this._document.createElement('section');
        this.root.className = 'npcshop-space-page loot-organizer-page';
        this.root.setAttribute('data-loot-organizer','');
        this.root.innerHTML = '<header class="npcshop-space-header"><div class="workbench-secondary-actions">'
            + '<button type="button" data-loot-organizer-back>← 返回战利品</button>'
            + '<button type="button" data-loot-organizer-help aria-label="查看战利品整理帮助">?</button>'
            + '<button type="button" data-loot-organizer-close aria-label="关闭战利品面板">×</button></div>'
            + '<div><h2>整理背包</h2><p>点击物品可在背包与战备箱之间转移；返回前会重新同步当前箱子。</p></div>'
            + '<span data-space-status>同步中</span>'
            + '<button type="button" data-loot-organizer-retry hidden>重试同步</button></header>'
            + '<div class="npcshop-space-columns">'
            + '<section><h3>背包 <small data-space-meta="背包"></small></h3>'
            + '<div class="npcshop-space-grid" data-space-grid="背包"></div></section>'
            + '<section><h3>战备箱 <span data-space-pager></span>'
            + '<small data-space-meta="战备箱"></small></h3>'
            + '<div class="npcshop-space-grid battlebox" data-space-grid="战备箱"></div></section>'
            + '</div>';
        this.secondary = new this._components.SecondaryPage({
            root:this.root, role:'dialog', ariaLabel:'整理战利品领取空间'
        });
        this.secondary.bindBack(this.root.querySelector('[data-loot-organizer-back]'), this._ports.onBack);
        this.secondary.bindHelp(this.root.querySelector('[data-loot-organizer-help]'), this._ports.onHelp);
        this.secondary.bindClose(this.root.querySelector('[data-loot-organizer-close]'), this._ports.onClose);
        var self = this;
        this.retryButton = this.root.querySelector('[data-loot-organizer-retry]');
        this.retryButton.addEventListener('click', function(event) {
            event.preventDefault();
            self._ports.onRetry();
        });
        this._grids = {
            '背包':this.root.querySelector('[data-space-grid="背包"]'),
            '战备箱':this.root.querySelector('[data-space-grid="战备箱"]')
        };
        this.pager = new this._inventoryUI.InventoryWindowPager({
            containerId:'战备箱', containerLabel:'战备箱', columns:5,
            defaultOffset:0, defaultLimit:40, defaultCapacity:0,
            getSnapshot:function() { return self._ports.getWindow('战备箱'); },
            getRequest:function() { return self._ports.getRequest('战备箱'); },
            shortcutEnabled:function() { return self.isActive(); },
            onRequest:function(offset, limit, callback) {
                return self._ports.setWindow('战备箱',offset,limit,callback);
            },
            onResult:function(result) {
                self.render(self._state);
                self._ports.onPageResult(result);
            }
        });
        this.root.querySelector('[data-space-pager]').appendChild(this.pager.root);
        this.pager.attach();
        this.inventoryBody = this.root.querySelector('.npcshop-space-columns');
        this.transferPane = new this._components.OwnedInventoryPane({
            // Inventory synchronization only governs the two inventory columns.
            // Back / Help / Close remain independent page actions while inventory
            // writes are busy or waiting for a refresh.
            root:this.inventoryBody,
            keyOf:function(slot) { return slot && slot.physicalSlot; },
            interaction:this._interaction,
            onInteractionChange:function(projection) {
                self._interaction = projection;
                self._projectInteraction();
            },
            onQuickTransfer:function(transfer, done) {
                return self._ports.autoTransfer(transfer.source,transfer.target,done);
            },
            onQuickTransferResult:function(result) {
                self._ports.onTransferResult(result);
                self.render(self._state);
            }
        });
        this.secondary.mount(options.host);
    }

    Presenter.prototype.open = function(context) { return this.secondary.open(context || {}); };
    Presenter.prototype.close = function(reason) { return this.secondary.close(reason || 'return'); };
    Presenter.prototype.isActive = function() { return this.secondary.isActive(); };
    Presenter.prototype.render = function(state) {
        if (!this.isActive()) return false;
        this._state = state || {};
        this.transferPane.setInteraction(interactionForState(this._state));
        this._renderGrid('背包');
        this._renderGrid('战备箱');
        this.pager.setDisabled(!this._interaction.actionable);
        this.pager.refresh();
        this.root.querySelector('[data-space-status]').textContent = statusText(this._state);
        this.retryButton.hidden = !this._state.refreshRequired;
        this.retryButton.disabled = !!this._state.busyOwner || !!this._state.returning;
        this.root.setAttribute('aria-busy', this._state.busyOwner || this._state.returning ? 'true' : 'false');
        return true;
    };
    Presenter.prototype._renderGrid = function(containerId) {
        var self = this, grid = this._grids[containerId];
        while (grid.firstChild) grid.removeChild(grid.firstChild);
        var snapshot = this._ports.getWindow(containerId);
        var slots = snapshot && snapshot.slots ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            var slot = slots[i];
            var node = this._inventoryUI.renderOwnedSlot(containerId,slot,{
                iconHtml:this._ports.iconHtml, allowDiscard:containerId === '背包'
            });
            if (slot.occupied) {
                node.classList.add('npcshop-space-transferable','loot-organizer-transferable');
                var action = containerId === '背包' ? '移入战备箱' : '移入背包';
                node.setAttribute('aria-label',(node.getAttribute('aria-label') || '') + '，点击' + action);
                (function(sourceContainer, sourceSlot, sourceNode) {
                    var reasonNode = ensureReasonNode(sourceNode);
                    self._workbench.EntityTile.bindActivation(sourceNode,{
                        itemName:String(sourceSlot.item
                            && (sourceSlot.item.displayName || sourceSlot.item.name) || '未知物品'),
                        label:sourceNode.getAttribute('aria-label') || '',
                        inspectable:function() { return self._interaction.inspectable; },
                        actionable:function() { return self._interaction.actionable; },
                        reason:function() { return self._interaction.reason; },
                        reasonNode:reasonNode,
                        onBlocked:function() { self._ports.toast(self._interaction.reason); },
                        onActivate:function() { self.transfer(sourceContainer,sourceSlot); }
                    });
                    sourceNode.__lootOrganizerInteractionRefresh = function() {
                        projectNode(self._workbench,sourceNode,self._interaction,reasonNode);
                        sourceNode.classList.toggle('write-locked',!self._interaction.actionable);
                    };
                    sourceNode.__lootOrganizerInteractionRefresh();
                })(containerId,slot,node);
                var discardButton = node.querySelector('.inventory-discard-btn');
                if (discardButton) {
                    this._workbench.EntityTile.labelAction(discardButton,
                        String(slot.item && (slot.item.displayName || slot.item.name) || '未知物品'),
                        '丢弃整槽');
                    (function(discardSlot, button) {
                        button.addEventListener('click',function(event) {
                            event.stopPropagation();
                            if (!self._interaction.actionable) {
                                self._ports.toast(self._interaction.reason);
                                return;
                            }
                            self._ports.onRequestDiscard(discardSlot);
                        });
                    })(slot,discardButton);
                    projectNode(this._workbench,discardButton,this._interaction,
                        node.querySelector('.workbench-entity-lock-reason'));
                }
            } else {
                this._workbench.EntityTile.applySemantics(node,{
                    itemName:'空槽', label:node.getAttribute('aria-label') || '', disabled:true
                });
            }
            grid.appendChild(node);
        }
        var meta = this.root.querySelector('[data-space-meta="' + containerId + '"]');
        if (!snapshot) meta.textContent = '同步中';
        else if (containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0)
            meta.textContent = '未解锁';
        else meta.textContent = slots.filter(function(candidate) { return candidate.occupied; }).length + ' 项';
    };
    Presenter.prototype._projectInteraction = function() {
        var nodes = this.root.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) {
            if (nodes[i].__lootOrganizerInteractionRefresh) nodes[i].__lootOrganizerInteractionRefresh();
            var discard = nodes[i].querySelector('.inventory-discard-btn');
            var reason = nodes[i].querySelector('.workbench-entity-lock-reason');
            if (discard && reason) projectNode(this._workbench,discard,this._interaction,reason);
        }
    };
    Presenter.prototype.transfer = function(containerId, slot) {
        if (!this._interaction.actionable || !slot || !slot.occupied) return false;
        var source = {
            containerId:containerId, slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease), occupied:true, item:slot.item || null
        };
        var target = containerId === '背包' ? '战备箱' : '背包';
        var key = containerId + ':' + source.slot + ':' + source.expectedLease + '>' + target;
        if (!this.transferPane.quickTransfer(source,target,{key:key})) {
            this._ports.toast('库存正在处理另一项操作。');
            return false;
        }
        this.render(this._state);
        return true;
    };
    Presenter.prototype.debugState = function() {
        return {
            active:this.isActive(),
            status:statusText(this._state),
            interaction:this._interaction,
            transfer:this.transferPane.debugState().quickTransfer
        };
    };
    Presenter.prototype.destroy = function() {
        this.pager.detach();
        this.transferPane.destroy();
        this.secondary.destroy();
        return true;
    };

    return {
        RequestMux:RequestMux,
        Presenter:Presenter,
        statusText:statusText,
        interactionForState:interactionForState,
        opaque:opaque
    };
});
