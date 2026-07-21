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
            onRetry:requirePort(options,'onRetry'),
            onPageResult:requirePort(options,'onPageResult'),
            onTransferResult:requirePort(options,'onTransferResult'),
            iconHtml:requirePort(options,'iconHtml'),
            toast:requirePort(options,'toast')
        };
        this._state = {};
        this.root = this._document.createElement('section');
        this.root.className = 'npcshop-space-page loot-organizer-page';
        this.root.setAttribute('data-loot-organizer','');
        this.root.innerHTML = '<header class="npcshop-space-header">'
            + '<button type="button" data-loot-organizer-back>← 返回战利品</button>'
            + '<div><h2>整理背包</h2><p>点击物品可在背包与战备箱之间转移；返回前会重新同步当前箱子。</p></div>'
            + '<span data-space-status>同步中</span>'
            + '<button type="button" data-loot-organizer-retry hidden>重试同步</button>'
            + '<button type="button" class="workbench-close-btn loot-organizer-close-btn" '
            + 'data-loot-organizer-close aria-label="返回战利品">×</button></header>'
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
        this.secondary.bindClose(this.root.querySelector('[data-loot-organizer-back]'), this._ports.onBack);
        this.secondary.bindClose(this.root.querySelector('[data-loot-organizer-close]'), this._ports.onBack);
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
        this.transferPane = new this._components.OwnedInventoryPane({
            keyOf:function(slot) { return slot && slot.physicalSlot; },
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
        var disabled = !this._state.ready || !!this._state.busyOwner
            || !!this._state.refreshRequired || !!this._state.returning;
        this.transferPane.setDisabled(disabled);
        this._renderGrid('背包');
        this._renderGrid('战备箱');
        this.pager.setDisabled(disabled);
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
                    self._workbench.EntityTile.bindActivation(sourceNode,{
                        itemName:String(sourceSlot.item
                            && (sourceSlot.item.displayName || sourceSlot.item.name) || '未知物品'),
                        label:sourceNode.getAttribute('aria-label') || '',
                        disabled:false,
                        onActivate:function() { self.transfer(sourceContainer,sourceSlot); }
                    });
                })(containerId,slot,node);
                var discardButton = node.querySelector('.inventory-discard-btn');
                if (discardButton) {
                    this._workbench.EntityTile.labelAction(discardButton,
                        String(slot.item && (slot.item.displayName || slot.item.name) || '未知物品'),
                        '丢弃整槽');
                    (function(discardSlot, button) {
                        button.addEventListener('click',function(event) {
                            event.stopPropagation();
                            self._ports.onRequestDiscard(discardSlot);
                        });
                    })(slot,discardButton);
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
    Presenter.prototype.transfer = function(containerId, slot) {
        if (!this._state.ready || this._state.busyOwner || this._state.refreshRequired
                || this._state.returning || !slot || !slot.occupied) return false;
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
        opaque:opaque
    };
});
