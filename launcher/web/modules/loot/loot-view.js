/** Shared-workbench presenter for the map-chest loot transfer pair. No authority state lives here. */
var LootView = (function() {
    'use strict';

    function normalizeInitData(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
        var allowed = {v:true,panelInstanceId:true,chestSessionId:true,lootContainerId:true,
            containerEpoch:true,displayName:true,capacity:true,columns:true};
        var keys = Object.keys(value);
        if (keys.length !== 8) return null;
        for (var i = 0; i < keys.length; i++)
            if (!Object.prototype.hasOwnProperty.call(allowed,keys[i])) return null;

        function bounded(name, limit) {
            return typeof value[name] === 'string' && value[name].trim()
                && value[name].length <= limit ? value[name] : '';
        }
        function opaque(name) {
            var result = bounded(name, 128);
            return result && /^[A-Za-z0-9._~-]+$/.test(result) ? result : '';
        }

        var normalized = {
            v:value.v,
            panelInstanceId:opaque('panelInstanceId'),
            chestSessionId:opaque('chestSessionId'),
            lootContainerId:opaque('lootContainerId'),
            containerEpoch:value.containerEpoch,
            displayName:bounded('displayName',80),
            capacity:value.capacity,
            columns:value.columns
        };
        if (normalized.v !== 1 || !normalized.panelInstanceId || !normalized.chestSessionId
                || !normalized.lootContainerId || !normalized.displayName
                || !positiveInteger(normalized.containerEpoch)
                || !positiveInteger(normalized.capacity) || normalized.capacity > 64
                || !positiveInteger(normalized.columns) || normalized.columns > 8
                || normalized.columns > normalized.capacity) return null;
        return normalized;
    }

    function positiveInteger(value) {
        return typeof value === 'number' && isFinite(value)
            && Math.floor(value) === value && value > 0;
    }

    function interactionForState(state, claimAll, organizerActive) {
        state = state || {};
        if (organizerActive) return {inspectable:true, actionable:false, reason:'正在整理背包并重新核对当前箱子。'};
        if (claimAll) return {inspectable:true, actionable:false, reason:'正在逐项领取，请等待游戏确认。'};
        if (state.phase === 'reconcile_required') return {inspectable:true, actionable:false, reason:'上一次操作结果未知，请先重新核对。'};
        if (state.phase === 'opening') return {inspectable:true, actionable:false, reason:'正在读取箱子内容。'};
        if (state.phase === 'write_pending' || state.pending) return {inspectable:true, actionable:false, reason:'领取正在由游戏确认。'};
        if (state.phase !== 'active') return {inspectable:true, actionable:false, reason:'当前箱子不可领取。'};
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

    function projectNode(node, projection, reasonNode) {
        return Workbench.EntityTile.projectInteraction(node, {
            inspectable:projection.inspectable, actionable:projection.actionable,
            reason:projection.reason, reasonNode:reasonNode
        });
    }

    function View(options) {
        options = options || {};
        this.options = options;
        this.init = options.init;
        this.identity = options.identity;
        this.runtimeConfig = options.runtimeConfig || {};
        this.shell = null;
        this.leftGrid = null;
        this.rightGrid = null;
        this.backpackPane = null;
        this.lootPane = null;
        this.commitBar = null;
        this.helpAction = null;
        this.closeButton = null;
        this.abandonButton = null;
        this.reconcileButton = null;
        this.broker = null;
        this.drag = null;
        this.focusScope = null;
        this.scaleHandle = null;
        this.tooltipCache = {};
        this.tooltipScope = null;
        this.tooltipSuppressed = false;
        this.interaction = interactionForState({}, false, false);
        this.destroyed = false;
    }

    View.prototype.mount = function(host, mountSession) {
        var self = this;
        this.shell = new Workbench.DualPaneShell({
            profile:'transfer-pair',
            title:this.init.displayName,
            subtitle:'从战利品箱领取物品到背包',
            leftLabel:'玩家背包',
            rightLabel:'战利品箱',
            flowLabel:'只出不进',
            status:'同步中'
        });
        this.shell.getRoot().classList.add('loot-workbench');
        this.shell.getRoot().setAttribute('data-domain','loot');
        this.shell.getRoot().setAttribute('data-authority-exclusive','loot');
        this.shell.getRoot().style.setProperty('--loot-columns',String(this.init.columns));
        mountSession.defer(function() { if (self.shell) self.shell.destroy(); });
        this.helpAction = new WorkbenchComponents.HelpAction({shell:this.shell,spec:{
            kind:'loot-help',
            ariaLabel:'查看战利品整理帮助',
            title:'战利品整理帮助',
            message:'领取物品\n• Enter、双击或 Ctrl+单击可直接领取。\n• 空格先选择，再到背包侧确认。\n• Ctrl+A 或底部“全部收取”会逐项领取。',
            detail:'空间不足时可进入整理页，在背包与战备箱之间转移物品。\n普通关闭会保留未领取内容并返回游戏；“放弃剩余”会永久丢弃箱内剩余内容。',
            actions:[{id:'close',label:'知道了',primary:true}]
        }});
        mountSession.defer(function() { if (self.helpAction) self.helpAction.destroy(); });

        this.closeButton = document.createElement('button');
        this.closeButton.type = 'button';
        this.closeButton.className = 'workbench-close-btn loot-close-btn';
        this.closeButton.textContent = '×';
        this.closeButton.setAttribute('aria-label','返回游戏并保留未领取的战利品');
        this.closeButton.setAttribute('data-audio-cue','cancel');
        this.abandonButton = document.createElement('button');
        this.abandonButton.type = 'button';
        this.abandonButton.className = 'workbench-mode-btn loot-abandon-btn';
        this.abandonButton.textContent = '放弃剩余';
        this.abandonButton.setAttribute('aria-label','永久放弃箱内剩余战利品');
        this.abandonButton.setAttribute('data-audio-cue','error');
        this.abandonButton.hidden = true;
        this.reconcileButton = document.createElement('button');
        this.reconcileButton.type = 'button';
        this.reconcileButton.className = 'workbench-mode-btn loot-reconcile-btn';
        this.reconcileButton.textContent = '重新核对';
        this.reconcileButton.setAttribute('aria-label','重新查询上一次领取或关闭的实际结果');
        this.reconcileButton.hidden = true;
        this.reconcileButton.setAttribute('data-header-action','reconcile');
        this.abandonButton.setAttribute('data-header-action','abandon');
        this.closeButton.setAttribute('data-header-action','close');
        this.shell.addHeaderAction(this.reconcileButton);
        this.shell.addHeaderAction(this.abandonButton);
        this.shell.addHeaderAction(this.closeButton);

        this.broker = new Workbench.InteractionBroker({
            onIntent:function(intent) {
                if (!intent || intent.operationId !== 'loot.claim'
                        || !intent.sourceRef
                        || intent.sourceRef.containerId !== self.identity.lootContainerId
                        || !intent.targetRef || intent.targetRef.containerId !== '背包') {
                    self.rejectDirection();
                    return;
                }
                if (typeof self.options.onClaim === 'function')
                    self.options.onClaim(self.findLootSlot(intent.sourceRef.slot));
            },
            onReject:function(result) {
                if (result && result.reason !== 'nothing_selected' && result.reason !== 'same_slot')
                    self.rejectDirection();
            },
            onSelectionChange:function(selection) {
                self.tooltipSuppressed = !!selection;
                if (self.tooltipSuppressed) hideTooltip();
            }
        });

        this.leftGrid = this._createGrid('backpack');
        this.rightGrid = this._createGrid('loot');
        this.shell.mountInitial(this.leftGrid.view, this.rightGrid.view);
        this.backpackPane = new WorkbenchComponents.OwnedInventoryPane({
            view:this.leftGrid.view,
            root:this.leftGrid.root,
            getSnapshot:function() { var p=self._projection(); return p && p.backpack; },
            syncSnapshot:function() { if (self.leftGrid) self.leftGrid.render(); },
            interaction:this.interaction,
            onInteractionChange:function() { self._projectGridInteractions(); }
        });
        this.lootPane = new WorkbenchComponents.OwnedInventoryPane({
            view:this.rightGrid.view,
            root:this.rightGrid.root,
            getSnapshot:function() { var p=self._projection(); return p && p.loot; },
            syncSnapshot:function() { if (self.rightGrid) self.rightGrid.render(); },
            interaction:this.interaction,
            onInteractionChange:function() { self._projectGridInteractions(); }
        });
        mountSession.defer(function() { if (self.backpackPane) self.backpackPane.destroy(); });
        mountSession.defer(function() { if (self.lootPane) self.lootPane.destroy(); });

        this.commitBar = new WorkbenchComponents.CommitBar({
            className:'loot-commit-bar',
            label:'同步中',
            status:'正在读取游戏中的箱子和背包状态…',
            disabled:true,
            onCommit:function() {
                if (typeof self.options.onPrimary === 'function') self.options.onPrimary();
            }
        });
        this.commitBar.root.setAttribute('data-workbench-shell-footer', '');
        this.commitBar.mount(this.shell.getRoot());
        mountSession.defer(function() { if (self.commitBar) self.commitBar.destroy(); });
        host.appendChild(this.shell.getRoot());
    };

    View.prototype._createGrid = function(kind) {
        var self = this, isLoot = kind === 'loot';
        return new Workbench.ItemGrid({
            instanceKey:'loot:' + kind,
            instancePolicy:'singletonByBinding',
            itemModel:'owned',
            title:isLoot ? this.init.displayName : '背包',
            kicker:isLoot ? '战利品箱' : '我的背包',
            meta:isLoot ? '等待箱子内容' : '领取目标由游戏决定',
            className:isLoot ? 'loot-source-view inventory-owned-view'
                : 'loot-backpack-view inventory-owned-view',
            gridClassName:(isLoot ? 'loot-source-grid' : 'loot-backpack-grid')
                + ' inventory-owned-grid',
            emptyText:isLoot ? '箱内已无可领取内容' : '当前窗口没有物品',
            getItems:function() {
                var projection=self._projection();
                var snapshot=projection && (isLoot ? projection.loot : projection.backpack);
                return snapshot && snapshot.slots || [];
            },
            keyOf:function(slot) { return String(slot.physicalSlot); },
            renderItem:function(slot) {
                var node=InventoryUI.renderOwnedSlot(
                    isLoot ? self.identity.lootContainerId : '背包',slot,
                    {iconHtml:iconHtml,allowDiscard:false});
                node.classList.add(isLoot ? 'loot-source-slot' : 'loot-backpack-slot');
                if (slot.targetDomain) node.setAttribute('data-target-domain',slot.targetDomain);
                return node;
            },
            bindItem:function(node,slot) { self._bindSlot(kind,node,slot); },
            exportOffer:function(slot) {
                if (!isLoot || !slot || !slot.occupied || !self._canWrite()) return null;
                return {subjectKind:'loot-entry',sourceRef:self._slotRef(slot)};
            },
            probeAccept:function(offer) {
                if (isLoot || !offer || offer.subjectKind !== 'loot-entry'
                        || !offer.sourceRef
                        || offer.sourceRef.containerId !== self.identity.lootContainerId
                        || !self._canWrite()) return {accepted:false,reason:'direction_forbidden'};
                return {accepted:true,operationId:'loot.claim',targetRef:{containerId:'背包'}};
            }
        });
    };

    View.prototype.activate = function(session) {
        var self = this;
        if (this.tooltipScope) this.tooltipScope.dispose();
        this.tooltipScope = typeof PanelTooltip !== 'undefined' && PanelTooltip.createScope
            ? PanelTooltip.createScope('loot-workbench', {profile:'dense-inspect'}) : null;
        var activeTooltipScope = this.tooltipScope;
        session.defer(function() {
            if (activeTooltipScope) activeTooltipScope.dispose();
            if (self.tooltipScope === activeTooltipScope) self.tooltipScope = null;
        });
        this.scaleHandle = typeof PanelScale !== 'undefined'
            ? PanelScale.attach(this.options.hostElement,1024,576) : null;
        session.defer(function() {
            if (self.scaleHandle) self.scaleHandle.detach();
            self.scaleHandle = null;
        });
        session.listen(this.closeButton,'click',function() {
            if (typeof self.options.onRequestClose === 'function') self.options.onRequestClose();
        });
        session.listen(this.abandonButton,'click',function() {
            if (typeof self.options.onRequestAbandon === 'function') self.options.onRequestAbandon();
        });
        session.listen(this.reconcileButton,'click',function() {
            if (typeof self.options.onReconcile === 'function') self.options.onReconcile();
        });
        session.listen(document,'keydown',function(event) { self._onKeyDown(event); },true);
        this.focusScope = new WorkbenchFocus.FocusScope({
            root:this.shell.getRoot(),
            document:document,
            restoreFocus:false,
            onEscape:function() {
                if (typeof self.options.onRequestClose === 'function') self.options.onRequestClose();
                return false;
            }
        });
        this.focusScope.activate({initialFocus:this.closeButton});
        session.defer(function() {
            if (self.focusScope) self.focusScope.destroy();
            self.focusScope = null;
        });

        this.drag = new Workbench.PointerDragController({
            sourceElement:this.rightGrid.renderer.root,
            broker:this.broker,
            timeoutMs:this.runtimeConfig.dragTimeoutMs || 1400,
            getSource:function(target) {
                if (!self._canWrite()) return null;
                var hit=self.rightGrid.renderer.itemFromTarget(target);
                return hit && hit.item && hit.item.occupied
                    ? {view:self.rightGrid.view,item:hit.item,node:hit.node} : null;
            },
            resolveTarget:function(clientX,clientY) {
                var target=document.elementFromPoint(clientX,clientY);
                if (!self.leftGrid.root.contains(target)) return null;
                var hit=self.leftGrid.renderer.itemFromTarget(target);
                return {view:self.leftGrid.view,hit:hit || {},
                    node:hit ? hit.node : self.leftGrid.renderer.root};
            },
            renderGhost:function(source) {
                var item=source.item.item || {},node=document.createElement('div');
                node.className='workbench-drag-ghost inventory-drag-ghost loot-drag-ghost';
                node.innerHTML=iconHtml(item.icon || '','inventory-owned-icon')
                    + '<span>' + escapeHtml(item.displayName || '战利品') + '</span>';
                return node;
            },
            onDragStart:function() { self.tooltipSuppressed=true;hideTooltip(); },
            onDragEnd:function() { self.tooltipSuppressed=false; }
        });
        session.defer(function() {
            if (self.drag) self.drag.destroy();
            self.drag = null;
        });
        this.tooltipCache = {};
        this.tooltipSuppressed = false;
    };

    View.prototype.deactivate = function() {
        if (this.broker) this.broker.clearSelection();
        this.tooltipSuppressed = false;
        hideTooltip();
    };

    View.prototype.destroy = function() {
        if (this.destroyed) return;
        this.destroyed = true;
        this.deactivate();
        if (this.tooltipScope) { this.tooltipScope.dispose(); this.tooltipScope = null; }
        this.shell = null;
        this.leftGrid = null;
        this.rightGrid = null;
        this.backpackPane = null;
        this.lootPane = null;
        this.commitBar = null;
        this.helpAction = null;
        this.closeButton = null;
        this.abandonButton = null;
        this.reconcileButton = null;
        this.broker = null;
        this.drag = null;
        this.focusScope = null;
        this.scaleHandle = null;
        this.tooltipCache = {};
    };

    View.prototype._bindSlot = function(kind,node,slot) {
        var self=this,isLoot=kind==='loot',item=slot.item || {};
        var itemName=slot.occupied ? String(item.displayName || '未知物品') : '空槽';
        var reasonNode=ensureReasonNode(node);
        Workbench.EntityTile.bindActivation(node,{
            itemName:itemName,
            label:isLoot && slot.occupied
                ? itemName + '，按 Enter、双击或 Ctrl+单击领取；空格选择后可在左侧确认'
                : itemName + (isLoot ? '' : '，战利品只能领取到此侧，不能放回箱子'),
            selected:function(){return self.broker && self.broker.isSelectedNode(node);},
            inspectable:function(){return self._tileInteraction(kind,slot).inspectable;},
            actionable:function(){return self._tileInteraction(kind,slot).actionable;},
            reason:function(){return self._tileInteraction(kind,slot).reason;},
            reasonNode:reasonNode,
            onBlocked:function(){self._toast(self._tileInteraction(kind,slot).reason);},
            onActivate:function(event,context){
                if (self.drag && self.drag.consumeClick()) return;
                if (isLoot) {
                    if (event.ctrlKey || event.metaKey || Number(event.detail) >= 2
                            || context.origin === 'keyboard' && event.key === 'Enter') {
                        if (typeof self.options.onClaim === 'function') self.options.onClaim(slot);
                        return;
                    }
                    if (self.broker.isSelectedNode(node)) self.broker.clearSelection();
                    else self.broker.select(self.rightGrid.view,slot,node);
                    return;
                }
                if (self.broker.debugState().selectedInstanceKey)
                    self.broker.activateSelected(self.leftGrid.view,{item:slot,node:node},context.origin);
            }
        });
        node.__lootInteractionRefresh=function(){
            var projection=self._tileInteraction(kind,slot);
            projectNode(node,projection,reasonNode);
            node.classList.toggle('write-locked',!projection.actionable);
        };
        node.__lootInteractionRefresh();
        if (isLoot && slot.occupied) this._bindTooltip(node,slot);
    };

    View.prototype._tileInteraction = function(kind,slot) {
        if (kind === 'loot' && (!slot || !slot.occupied))
            return {inspectable:false,actionable:false,reason:''};
        if (!this.interaction.actionable) return this.interaction;
        return this.interaction;
    };
    View.prototype._projectGridInteractions = function() {
        var nodes=this.shell ? this.shell.getRoot().querySelectorAll(
            '.loot-source-slot,.loot-backpack-slot') : [];
        for (var i=0;i<nodes.length;i++)
            if (nodes[i].__lootInteractionRefresh) nodes[i].__lootInteractionRefresh();
    };

    View.prototype._bindTooltip = function(node,slot) {
        if (typeof PanelTooltip === 'undefined' || !PanelTooltip.bindAsyncHover) return;
        var self=this,item=slot.item || {},key='loot:' + slot.physicalSlot + ':' + slot.slotLease;
        var tooltipBinder=this.tooltipScope || PanelTooltip;
        tooltipBinder.bindAsyncHover(node,{
            profile:'dense-inspect',
            cache:this.tooltipCache,
            key:key,
            item:item,
            isSuppressed:function(){return self.tooltipSuppressed;},
            renderBasic:function(value){return basicTooltip(value);},
            renderRich:function(value,response){return richTooltip(value,response && response.tooltip);},
            fetch:function(_,callback){
                var accepted=typeof self.options.requestTooltip === 'function'
                    && self.options.requestTooltip(slot,function(response){
                        if (self._isOpen()) callback(response && response.success ? response : null);
                    });
                if (!accepted) callback(null);
            }
        });
    };

    View.prototype.render = function(state,projection,claimAll,organizerActive) {
        if (!this.shell || !state) return;
        this.interaction=interactionForState(state,claimAll,organizerActive);
        if (this.backpackPane) this.backpackPane.setInteraction(this.interaction);
        if (this.lootPane) this.lootPane.setInteraction(this.interaction);
        if (this.broker) this.broker.clearSelection();
        if (this.tooltipScope && this.tooltipScope.releaseTree) {
            if (this.leftGrid) this.tooltipScope.releaseTree(this.leftGrid.root);
            if (this.rightGrid) this.tooltipScope.releaseTree(this.rightGrid.root);
        }
        if (this.backpackPane) this.backpackPane.update(projection && projection.backpack || null,{});
        if (this.lootPane) this.lootPane.update(projection && projection.loot || null,{});
        if (this.leftGrid) this.leftGrid.chrome.setMeta(projection && projection.backpack
            ? '窗口 '+(projection.backpack.offset+1)+'–'
                +(projection.backpack.offset+projection.backpack.limit)+' / '+projection.backpack.capacity
            : '等待背包内容');
        if (this.rightGrid) this.rightGrid.chrome.setMeta(projection && projection.loot
            ? '箱内 '+state.remainingCount+' 个非空槽位' : '等待箱子内容');
        this.shell.setMetric('remaining','剩余槽位',state.remainingCount == null ? '—' : state.remainingCount);
        var busy=state.phase==='opening'||state.phase==='write_pending'||!!state.pending
            ||claimAll||organizerActive;
        if (state.phase==='reconcile_required') this.shell.setStatus('需要核对','warning');
        else if (state.phase==='terminal') this.shell.setStatus(terminalLabel(state.terminal),'ready');
        else if (state.phase==='suspended') this.shell.setStatus('已保留箱内物品','ready');
        else if (busy) this.shell.setStatus(organizerActive ? '整理背包中'
            : claimAll ? '逐项领取中' : '游戏确认中','busy');
        else if (state.phase==='active') this.shell.setStatus('箱子状态已同步','ready');
        else this.shell.setStatus('等待连接','idle');
        this.shell.setFlowState(state.phase==='reconcile_required' ? 'reject'
            : busy ? 'pending' : state.phase==='active' ? 'accept' : 'idle');
        if (this.reconcileButton) {
            this.reconcileButton.hidden=state.phase!=='reconcile_required';
            this.reconcileButton.disabled=!!state.pending;
        }
        if (this.closeButton) {
            // Do not use the native disabled state here.  A close intent while a write or
            // claim-all is pending must still reach LootPanel.requestClose(), which explains
            // that the game is confirming the current operation without issuing another write.
            // Keeping a real button also preserves focus plus native Enter/Space activation.
            this.closeButton.disabled=false;
            this.closeButton.setAttribute('aria-disabled',busy?'true':'false');
            this.closeButton.setAttribute('aria-busy',busy?'true':'false');
        }
        if (this.abandonButton) {
            this.abandonButton.hidden=state.phase!=='active'||state.remainingCount<=0;
            this.abandonButton.disabled=busy;
        }
        if (this.commitBar) this.commitBar.update(
            commitPresentation(state,claimAll,organizerActive));
    };

    View.prototype.hasModal = function() { return !!(this.shell && this.shell.hasModal()); };
    View.prototype.closeModal = function(reason) {
        return this.shell ? this.shell.closeModal(reason || 'cancel') : false;
    };
    View.prototype.openHelp = function(opener) {
        return this.helpAction ? this.helpAction.open(opener) : false;
    };
    View.prototype.openAbandon = function(remainingCount,onAbandon) {
        if (!this.shell) return false;
        this.shell.openModal({
            kind:'loot-abandon',
            kicker:'尚有 ' + remainingCount + ' 个非空槽位',
            title:'永久放弃剩余战利品？',
            message:'确认后，游戏会永久标记箱内尚未领取的内容为放弃。',
            detail:'普通关闭只返回游戏并保留箱子；此操作无法撤销。',
            closeOnBackdrop:true,
            actions:[
                {id:'cancel',label:'继续领取',primary:true,audioCue:'cancel'},
                {id:'abandon',label:'永久放弃',danger:true,audioCue:'error',onSelect:onAbandon}
            ]
        });
        return true;
    };
    View.prototype.openDiscard = function(slot,onDiscard) {
        if (!this.shell || !slot || !slot.occupied) return false;
        var projection=slot.confirmProjection||slot.item||{};
        this.shell.openModal({
            kind:'discard',
            title:'丢弃 '+String(projection.displayName||'该物品')+'？',
            message:'将丢弃整组，共 '+Number(projection.quantity||1)+' 件。',
            detail:'丢弃后无法找回。',
            actions:[
                {id:'cancel',label:'取消',audioCue:'cancel'},
                {id:'discard',label:'确认丢弃',danger:true,audioCue:'error',onSelect:onDiscard}
            ]
        });
        return true;
    };
    View.prototype.clearSelection = function() { if (this.broker) this.broker.clearSelection(); };
    View.prototype.getOrganizerHost = function() {
        return this.shell ? this.shell.getRoot() : null;
    };
    View.prototype.findLootSlot = function(physicalSlot) {
        var projection=this._projection(),slots=projection&&projection.loot&&projection.loot.slots||[];
        for (var i=0;i<slots.length;i++)
            if (Number(slots[i].physicalSlot)===Number(physicalSlot)) return slots[i];
        return null;
    };
    View.prototype.rejectDirection = function() {
        if (this.shell) this.shell.setFlowState('reject');
        this._toast('战利品只允许从箱子领取到背包，不能放回或交换。');
    };
    View.prototype.debugState = function() {
        return {hasShell:!!this.shell,hasDrag:!!this.drag,
            hasFocusScope:!!this.focusScope,interaction:this.interaction};
    };

    View.prototype._projection = function() {
        return typeof this.options.getProjection === 'function' ? this.options.getProjection() : null;
    };
    View.prototype._canWrite = function() {
        return typeof this.options.canWrite === 'function' && this.options.canWrite();
    };
    View.prototype._isOpen = function() {
        return typeof this.options.isOpen === 'function' && this.options.isOpen();
    };
    View.prototype._toast = function(message) {
        if (typeof this.options.toast === 'function') this.options.toast(message);
    };
    View.prototype._slotRef = function(slot) {
        var projection=this._projection();
        return {
            containerId:this.identity.lootContainerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            expectedContainerVersion:projection&&projection.loot
                ? Number(projection.loot.containerVersion) : 0
        };
    };
    View.prototype._onKeyDown = function(event) {
        if (!this._isOpen() || this.hasModal()) return;
        var target=event.target;
        if (target&&target.closest&&target.closest(
                'input,textarea,select,[contenteditable="true"],[data-browser-native]')) return;
        if ((event.ctrlKey||event.metaKey)&&String(event.key).toLowerCase()==='a') {
            event.preventDefault();
            if (typeof this.options.onPrimary === 'function') this.options.onPrimary();
        }
    };

    var INVENTORY_CAPACITY_BLOCKS = {target_full:true,inventory_full:true};

    function isInventoryCapacityBlock(error) {
        return Object.prototype.hasOwnProperty.call(
            INVENTORY_CAPACITY_BLOCKS,String(error||''));
    }

    function commitPresentation(state,claimAll,organizerActive) {
        var block=blockMessage(state.blockReason);
        if (state.phase==='reconcile_required') return {
            label:'重新核对',
            status:'上一次操作结果未知。这里只重新查询结果，不会再次领取或放弃。',
            state:'blocked',canCommit:!state.pending,busy:!!state.pending
        };
        if (state.phase==='terminal') return {
            label:'已结束',status:terminalLabel(state.terminal),state:'success',disabled:true
        };
        if (state.phase==='suspended') return {
            label:'返回游戏',status:'游戏已确认保留同一箱内的剩余战利品。',
            state:'success',disabled:true
        };
        if (state.phase!=='active') return {
            label:'同步中',status:'正在读取游戏中的背包与战利品快照…',
            state:'idle',disabled:true,busy:true
        };
        if (organizerActive) return {
            label:'整理背包中',status:'库存稳定并重新同步当前箱子后才能继续领取。',
            state:'busy',disabled:true,busy:true
        };
        if (claimAll) return {
            label:'逐项领取中',status:'按游戏确认的顺序逐项领取；不会并发提交。',
            state:'busy',disabled:true,busy:true
        };
        if (state.remainingCount===0) return {
            label:'关闭空箱',status:'游戏确认箱内已空；关闭会结束本次拾取。',
            state:'ready',canCommit:true
        };
        if (isInventoryCapacityBlock(state.blockReason)) return {
            label:'整理背包',
            status:'背包已满。可在当前页面转移背包与战备箱物品，再继续领取。',
            state:'blocked',canCommit:true
        };
        return {
            label:'全部收取',
            status:block||('剩余 '+state.remainingCount
                +' 个非空槽位；关闭只返回游戏，永久放弃请使用顶部危险操作。'),
            state:block?'blocked':'ready',canCommit:true
        };
    }

    function blockMessage(error) {
        var map={
            target_full:'背包已满，当前物品保持不变。',
            inventory_full:'背包已满，当前物品保持不变。',
            capacity_reached:'目标容量不足，当前物品保持不变。',
            cap_reached:'目标资产已达上限，整格未领取。',
            stale_lease:'箱内状态已变化，请重新核对。',
            stale_state:'箱内状态已变化，请重新核对。',
            reconcile_required:'上一次操作结果未知，必须先向游戏查询实际结果。'
        };
        var key=String(error||'');
        return Object.prototype.hasOwnProperty.call(map,key) ? map[key] : '';
    }
    function errorMessage(error) {
        var fallback={
            disconnected:'与游戏桥接已断开，未猜测领取结果。',
            client_timeout:'等待游戏响应超时，没有再次提交操作。',
            malformed_response:'游戏响应不完整，已暂停操作并等待重新核对。',
            stale_reconcile:'查询结果仍未包含上一次操作，请重试。',
            busy:'游戏正在处理另一项操作。'
        },key=String(error||'');
        return blockMessage(error)||(Object.prototype.hasOwnProperty.call(fallback,key)
            ? fallback[key] : '操作未被游戏确认，请重试或重新核对。');
    }
    function terminalLabel(value) {
        if (!value) return '会话已结束';
        return value.kind==='CONSUMED' ? '箱内物品已全部领取'
            : value.kind==='ABANDONED' ? '剩余战利品已明确放弃' : '箱子已随场景失效';
    }
    function basicTooltip(item) {
        return '<div class="kshop-tt-header"><b>'+escapeHtml(item.displayName||'未知物品')+'</b></div>'
            +'<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">来源</span> 地图资源箱'
            +'<div class="kshop-tt-loading">读取物品说明…</div>';
    }
    function richTooltip(item,data) {
        data=data||{};
        if (typeof PanelTooltip==='undefined'||!PanelTooltip.buildItemRichHtml)
            return basicTooltip(item);
        var iconKey=data.iconName||item.icon||'';
        return PanelTooltip.buildItemRichHtml({
            iconHtml:PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:PanelTooltip.staticIconUrl(iconKey),
            introHTML:data.introHTML||'',
            descHTML:data.descHTML||'',
            rootClass:'kshop-tt-rich-context loot-tooltip-context',
            layoutType:PanelTooltip.inferLayoutType(data.itemType||item.majorType||item.use)
        });
    }
    function iconHtml(name,cls) {
        var html=typeof Icons!=='undefined'&&Icons.html
            ? Icons.html(name,cls||'inventory-owned-icon',
                ' onerror="this.style.display=\'none\'"') : '';
        return html||'<span class="'+(cls||'inventory-owned-icon')
            +' kshop-icon-placeholder"></span>';
    }
    function hideTooltip() {
        if (typeof PanelTooltip!=='undefined'&&PanelTooltip.hide) PanelTooltip.hide();
    }
    function escapeHtml(value) {
        return String(value==null?'':value).replace(/&/g,'&amp;')
            .replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    return {
        View:View,
        normalizeInitData:normalizeInitData,
        commitPresentation:commitPresentation,
        interactionForState:interactionForState,
        isInventoryCapacityBlock:isInventoryCapacityBlock,
        blockMessage:blockMessage,
        errorMessage:errorMessage,
        terminalLabel:terminalLabel
    };
})();
