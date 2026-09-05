/** Shared-workbench presenter for the map-chest loot transfer pair. No authority state lives here. */
var LootView = (function() {
    'use strict';

    function normalizeInitData(value) {
        if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
        var settlement=value.sourceKind==='stage_settlement';
        var rewardInbox=value.sourceKind==='reward_inbox';
        var allowed = {v:true,panelInstanceId:true,chestSessionId:true,lootContainerId:true,
            containerEpoch:true,displayName:true,capacity:true,columns:true};
        if (settlement) { allowed.sourceKind=true;allowed.report=true; }
        else if (rewardInbox) {
            allowed.sourceKind=true;
            allowed.recoverableRootOperationId=true;
            allowed.recoverableRootStatus=true;
            allowed.recoveryRequired=true;
            allowed.recoveryOnly=true;
            allowed.rootAdmissionEnabled=true;
        }
        var keys = Object.keys(value);
        if (keys.length !== (settlement ? 10 : rewardInbox ? 14 : 8)) return null;
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
            columns:value.columns,
            sourceKind:settlement ? 'stage_settlement'
                : rewardInbox ? 'reward_inbox' : 'map_chest',
            report:settlement ? normalizeSettlementReport(value.report) : null,
            recoverableRootOperationId:rewardInbox
                ? String(value.recoverableRootOperationId || '') : '',
            recoverableRootStatus:rewardInbox
                ? String(value.recoverableRootStatus || '') : 'not_started',
            recoveryRequired:rewardInbox && value.recoveryRequired === true,
            recoveryOnly:rewardInbox && value.recoveryOnly === true,
            rootAdmissionEnabled:rewardInbox
                ? value.rootAdmissionEnabled === true : true
        };
        if (normalized.v !== 1 || !normalized.panelInstanceId || !normalized.chestSessionId
                || !normalized.lootContainerId || !normalized.displayName
                || !positiveInteger(normalized.containerEpoch)
                || !positiveInteger(normalized.capacity) || normalized.capacity > 64
                || !positiveInteger(normalized.columns) || normalized.columns > 8
                || normalized.columns > normalized.capacity
                || settlement && !normalized.report) return null;
        if (rewardInbox) {
            var rootId=normalized.recoverableRootOperationId;
            if (rootId && (!/^[A-Za-z0-9._~-]+$/.test(rootId)||rootId.length>128)
                    || ['not_started','pending','committed','terminal_failure','quarantined']
                        .indexOf(normalized.recoverableRootStatus)<0
                    || (!!rootId)===(normalized.recoverableRootStatus==='not_started')
                    || normalized.recoveryRequired&&!rootId
                    || normalized.recoveryOnly&&!normalized.recoveryRequired
                    || typeof value.recoveryRequired!=='boolean'
                    || typeof value.recoveryOnly!=='boolean'
                    || typeof value.rootAdmissionEnabled!=='boolean') return null;
        }
        return normalized;
    }

    function normalizeSettlementReport(value) {
        var expected={v:true,runId:true,stageName:true,difficulty:true,outcome:true,
            activeFrames:true,totalKills:true,omittedKillTypes:true,
            totalItemGains:true,totalItemLosses:true,omittedItemFlowTypes:true,
            rewardRollOmissions:true,kills:true,itemFlows:true};
        if (!exactKeys(value,expected)||value.v!==1
                ||!safeToken(value.runId,96)||!safeText(value.stageName,96,false)
                ||!safeText(value.difficulty,48,false)
                ||['victory','failure','retreat'].indexOf(value.outcome)<0
                ||!safeWhole(value.activeFrames)||!safeWhole(value.totalKills)
                ||!safeWhole(value.omittedKillTypes)||!safeWhole(value.rewardRollOmissions)
                ||!safeWhole(value.totalItemGains)||!safeWhole(value.totalItemLosses)
                ||!safeWhole(value.omittedItemFlowTypes)
                ||!Array.isArray(value.kills)||value.kills.length>96
                ||!Array.isArray(value.itemFlows)||value.itemFlows.length>96) return null;
        var kills=[],projected=0;
        for (var i=0;i<value.kills.length;i++) {
            var kill=normalizeKill(value.kills[i]);
            if (!kill||projected>Number.MAX_SAFE_INTEGER-kill.count) return null;
            projected+=kill.count;kills.push(kill);
        }
        if (projected>value.totalKills) return null;
        var itemFlows=[],projectedGains=0,projectedLosses=0;
        for (i=0;i<value.itemFlows.length;i++) {
            var flow=normalizeItemFlow(value.itemFlows[i]);
            if (!flow) return null;
            if (flow.direction==='gain') {
                if (projectedGains>Number.MAX_SAFE_INTEGER-flow.count) return null;
                projectedGains+=flow.count;
                if (projectedGains>value.totalItemGains) return null;
            } else {
                if (projectedLosses>Number.MAX_SAFE_INTEGER-flow.count) return null;
                projectedLosses+=flow.count;
                if (projectedLosses>value.totalItemLosses) return null;
            }
            itemFlows.push(flow);
        }
        return {v:1,runId:value.runId,stageName:value.stageName,
            difficulty:value.difficulty,outcome:value.outcome,
            activeFrames:value.activeFrames,totalKills:value.totalKills,
            omittedKillTypes:value.omittedKillTypes,
            totalItemGains:value.totalItemGains,totalItemLosses:value.totalItemLosses,
            omittedItemFlowTypes:value.omittedItemFlowTypes,
            rewardRollOmissions:value.rewardRollOmissions,kills:kills,itemFlows:itemFlows};
    }

    function normalizeItemFlow(value) {
        var expected={direction:true,kind:true,itemKey:true,displayName:true,
            iconName:true,tier:true,source:true,reason:true,count:true};
        var kinds={money:true,kpoint:true,intel:true,material:true,item:true,equip:true};
        if (!exactKeys(value,expected)||(value.direction!=='gain'&&value.direction!=='loss')
                ||!Object.prototype.hasOwnProperty.call(kinds,value.kind)
                ||!safeText(value.itemKey,128,false)
                ||!safeText(value.displayName,96,false)
                ||!safeText(value.iconName,128,true)||!safeText(value.tier,48,true)
                ||!safeText(value.source,48,false)||!safeText(value.reason,64,true)
                ||!safeWhole(value.count)||value.count<1) return null;
        return {direction:value.direction,kind:value.kind,itemKey:value.itemKey,
            displayName:value.displayName,iconName:value.iconName,tier:value.tier,
            source:value.source,reason:value.reason,count:value.count};
    }

    function normalizeKill(value) {
        var expected={key:true,displayName:true,iconName:true,doll:true,
            eliteLevel:true,count:true};
        if (!exactKeys(value,expected)||!safeText(value.key,128,false)
                ||!safeText(value.displayName,96,false)
                ||!safeText(value.iconName,128,true)
                ||!Number.isInteger(value.eliteLevel)||value.eliteLevel<0||value.eliteLevel>16
                ||!safeWhole(value.count)||value.count<1) return null;
        var doll=normalizeDoll(value.doll);
        if (value.doll!==null&&!doll) return null;
        return {key:value.key,displayName:value.displayName,iconName:value.iconName,
            doll:doll,eliteLevel:value.eliteLevel,count:value.count};
    }

    function normalizeDoll(value) {
        if (value===null) return null;
        var names=['face','hair','mask','head','body','leg','hand','foot','neck','gender'];
        var expected={},result={};
        for (var i=0;i<names.length;i++) expected[names[i]]=true;
        if (!exactKeys(value,expected)) return null;
        for (i=0;i<names.length;i++) {
            if (!safeText(value[names[i]],128,true)) return null;
            result[names[i]]=value[names[i]];
        }
        return result;
    }

    function exactKeys(value, expected) {
        if (!value||typeof value!=='object'||Array.isArray(value)) return false;
        var keys=Object.keys(value),expectedKeys=Object.keys(expected);
        if (keys.length!==expectedKeys.length) return false;
        for (var i=0;i<keys.length;i++)
            if (!Object.prototype.hasOwnProperty.call(expected,keys[i])) return false;
        return true;
    }

    function safeText(value,limit,allowEmpty) {
        if (typeof value!=='string'||value.length>limit||!allowEmpty&&!value.length) return false;
        return !/[\u0000-\u001f\u007f]/.test(value);
    }

    function safeToken(value,limit) {
        return safeText(value,limit,false)&&/^[A-Za-z0-9._~:-]+$/.test(value);
    }

    var DOLL_FIELDS=['face','hair','mask','head','body','leg','hand','foot','neck','gender'];

    function safeWhole(value) {
        return Number.isSafeInteger(value)&&value>=0;
    }

    function positiveInteger(value) {
        return typeof value === 'number' && isFinite(value)
            && Math.floor(value) === value && value > 0;
    }

    function interactionForState(state, claimAll, organizerActive) {
        state = state || {};
        if (organizerActive) return {inspectable:true, actionable:false, reason:'正在整理背包并重新核对当前箱子。'};
        if (claimAll) return {inspectable:true, actionable:false, reason:'正在批量领取，请等待游戏确认。'};
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
        this.isSettlement = this.init && this.init.sourceKind === 'stage_settlement';
        this.isRewardInbox = this.init && this.init.sourceKind === 'reward_inbox';
        this.reportPane = null;
        this.reportView = null;
        this.settlementSidePane = null;
        this.settlementSideView = null;
        this.rewardTabButton = null;
        this.materialTabButton = null;
        this.rewardSection = null;
        this.reportSection = null;
        this.reportOutcome = null;
        this.reportStage = null;
        this.reportDifficulty = null;
        this.reportTime = null;
        this.reportKillTotal = null;
        this.killList = null;
        this.killStatus = null;
        this.flowSection = null;
        this.flowList = null;
        this.flowStatus = null;
        this.flowGainTotal = null;
        this.flowLossTotal = null;
        this.materialSection = null;
        this.materialList = null;
        this.materialSearch = null;
        this.materialStatus = null;
        this.materials = null;
        this.materialsBusy = false;
        this.materialsError = '';
        this.rightTab = 'rewards';
        this.inventoryButton = null;
        this.reportDensity = null;
        this.reportDensityToggle = null;
        this.dollPortraitCache = {};
        this.dollPortraitQueue = [];
        this.dollPortraitActive = 0;
        this.portraitSequence = 0;
        this.destroyed = false;
    }

    View.prototype.mount = function(host, mountSession) {
        var self = this;
        this.shell = new Workbench.DualPaneShell({
            profile:'transfer-pair',
            eyebrow:this.isSettlement ? 'θ-FLOOD / SETTLEMENT LINK' : '',
            title:this.init.displayName,
            subtitle:this.isSettlement ? '战报与基地奖励' : '从战利品箱领取物品到背包',
            leftLabel:this.isSettlement ? '行动报告' : '玩家背包',
            rightLabel:this.isSettlement ? '奖励与存量' : '战利品箱',
            flowLabel:this.isSettlement ? '结算' : '只出不进',
            status:'同步中'
        });
        this.shell.getRoot().classList.add('loot-workbench');
        if (this.isSettlement) {
            this.shell.getRoot().classList.add('loot-stage-settlement');
            this.shell.getRoot().setAttribute('data-workbench-skin','terminal');
            var settlementHeader=this.shell.getRoot().querySelector('.workbench-header');
            var settlementBrand=document.createElement('span');
            settlementBrand.className='term-brand-seal loot-settlement-brand';
            settlementBrand.textContent='CF7·ME';
            settlementBrand.setAttribute('aria-hidden','true');
            if (settlementHeader) settlementHeader.insertBefore(
                settlementBrand,settlementHeader.firstChild);
        }
        this.shell.getRoot().setAttribute('data-domain','loot');
        this.shell.getRoot().setAttribute('data-authority-exclusive','loot');
        this.shell.getRoot().style.setProperty('--loot-columns',String(this.init.columns));
        mountSession.defer(function() { if (self.shell) self.shell.destroy(); });
        this.helpAction = new WorkbenchComponents.HelpAction({shell:this.shell,spec:{
            kind:'loot-help',
            ariaLabel:this.isSettlement ? '查看关卡结算帮助' : '查看战利品整理帮助',
            title:this.isSettlement ? '关卡结算帮助' : '战利品整理帮助',
            message:this.isSettlement
                ? '领取奖励\n• 单击或 Enter 可直接领取。\n• Ctrl+A 或底部“全部收取”会批量领取。\n• 左栏合并击杀与物资记录；右栏可切换材料存量。'
                : '领取物品\n• Enter、双击或 Ctrl+单击可直接领取。\n• 空格先选择，再到背包侧确认。\n• Ctrl+A 或底部“全部收取”会批量领取。',
            detail:this.isSettlement
                ? '左栏合并展示击杀与物资记录；右栏可切换待领取奖励和当前材料存量。\n库存整理仍使用原有背包与战备箱界面。普通关闭会保留未领取内容；“放弃剩余”会永久丢弃剩余奖励。'
                : this.isRewardInbox
                    ? '普通关闭会保留未领取内容；待领取恢复批次不提供永久放弃。'
                : '可进入库存整理，在背包与战备箱之间转移或丢弃物品。\n普通关闭会保留未领取内容；“放弃剩余”会永久丢弃剩余奖励。',
            actions:[{id:'close',label:'知道了',primary:true}]
        }});
        mountSession.defer(function() { if (self.helpAction) self.helpAction.destroy(); });

        if (this.isSettlement) {
            this.reportDensity=new Workbench.GridDensityController({
                panelId:'loot-stage-settlement',
                compactClass:'loot-settlement-compact',
                defaultMode:'compact'
            });
            this.reportDensityToggle=this.reportDensity.createToggle();
            this.reportDensityToggle.setAttribute('aria-label','关卡结算布局');
            var densityLabel=this.reportDensityToggle.querySelector('.item-grid-mode-label');
            if (densityLabel) densityLabel.textContent='结算';
            this.shell.addHeaderAction(this.reportDensityToggle);
            mountSession.defer(function() {
                if (self.reportDensity) self.reportDensity.destroy();
                self.reportDensity=null;self.reportDensityToggle=null;
            });
        }

        this.closeButton = document.createElement('button');
        this.closeButton.type = 'button';
        this.closeButton.className = 'workbench-close-btn loot-close-btn';
        this.closeButton.textContent = '×';
        this.closeButton.setAttribute('aria-label',this.isSettlement
            ? '关闭结算并保留未领取的奖励' : '返回游戏并保留未领取的战利品');
        this.closeButton.setAttribute('data-audio-cue','back');
        this.abandonButton = document.createElement('button');
        this.abandonButton.type = 'button';
        this.abandonButton.className = 'workbench-mode-btn loot-abandon-btn';
        this.abandonButton.textContent = '放弃剩余';
        this.abandonButton.setAttribute('aria-label',this.isSettlement
            ? '永久放弃剩余关卡奖励' : '永久放弃箱内剩余战利品');
        this.abandonButton.setAttribute('data-audio-cue','destructive');
        this.abandonButton.hidden = true;
        this.abandonButton.disabled = !!this.isRewardInbox;
        this.reconcileButton = document.createElement('button');
        this.reconcileButton.type = 'button';
        this.reconcileButton.className = 'workbench-mode-btn loot-reconcile-btn';
        this.reconcileButton.textContent = '重新核对';
        this.reconcileButton.setAttribute('aria-label','重新查询上一次领取或关闭的实际结果');
        this.reconcileButton.hidden = true;
        this.reconcileButton.setAttribute('data-header-action','reconcile');
        if (this.isSettlement) {
            this.inventoryButton=document.createElement('button');
            this.inventoryButton.type='button';
            this.inventoryButton.className='workbench-mode-btn loot-inventory-btn';
            this.inventoryButton.textContent='库存整理';
            this.inventoryButton.setAttribute('aria-label','打开背包与战备箱整理页');
            this.inventoryButton.setAttribute('data-header-action','inventory');
            this.shell.addHeaderAction(this.inventoryButton);
        }
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

        this.leftGrid = this.isSettlement ? null : this._createGrid('backpack');
        this.rightGrid = this._createGrid('loot');
        if (this.isSettlement) {
            this.reportPane=this._createReportPane();
            this.settlementSidePane=this._createSettlementSidePane();
            this.reportDensity.register(this.reportPane);
            this.reportDensity.register(this.rightGrid);
            this.reportDensity.register(this.settlementSidePane);
            var reportPane=this.reportPane;
            this.reportView={
                instanceKey:'loot:settlement-report',
                instancePolicy:'singletonByBinding',
                allowedSlots:['L'],
                viewKind:'stage-settlement-report',
                mount:function(container) { container.appendChild(reportPane); },
                unmount:function() {
                    if (reportPane.parentNode) reportPane.parentNode.removeChild(reportPane);
                },
                render:function() { self._renderReport(); }
            };
            var sidePane=this.settlementSidePane;
            var rewardSection=this.rewardSection;
            this.settlementSideView={
                instanceKey:'loot:settlement-side',
                instancePolicy:'singletonByBinding',
                allowedSlots:['R'],
                viewKind:'stage-settlement-side',
                mount:function(container) {
                    container.appendChild(sidePane);
                    self.rightGrid.view.mount(rewardSection);
                },
                unmount:function() {
                    self.rightGrid.view.unmount();
                    if (sidePane.parentNode) sidePane.parentNode.removeChild(sidePane);
                },
                render:function() {
                    self.rightGrid.render();
                    self._renderMaterials();
                }
            };
            if (!this.shell.mountInitial(this.reportView, this.settlementSideView))
                throw new Error('stage settlement workbench views cannot mount');
        } else {
            if (!this.shell.mountInitial(this.leftGrid.view, this.rightGrid.view))
                throw new Error('map loot workbench views cannot mount');
            this.backpackPane = new WorkbenchComponents.OwnedInventoryPane({
                view:this.leftGrid.view,
                root:this.leftGrid.root,
                getSnapshot:function() { var p=self._projection(); return p && p.backpack; },
                syncSnapshot:function() { if (self.leftGrid) self.leftGrid.render(); },
                interaction:this.interaction,
                onInteractionChange:function() { self._projectGridInteractions(); }
            });
        }
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
            status:this.isSettlement ? '正在读取游戏中的奖励状态…'
                : '正在读取游戏中的箱子和背包状态…',
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
            kicker:isLoot ? (this.isSettlement ? '基地奖励' : '战利品箱') : '我的背包',
            meta:isLoot ? (this.isSettlement ? '等待奖励内容' : '等待箱子内容')
                : '领取目标由游戏决定',
            className:isLoot ? 'loot-source-view inventory-owned-view'
                : 'loot-backpack-view inventory-owned-view',
            gridClassName:(isLoot ? 'loot-source-grid' : 'loot-backpack-grid')
                + ' inventory-owned-grid',
            emptyText:isLoot ? (this.isSettlement ? '本次奖励已全部处理' : '箱内已无可领取内容')
                : '当前窗口没有物品',
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
                if (self.isSettlement || !isLoot || !slot || !slot.occupied
                        || !self._canWrite()) return null;
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

    View.prototype._createReportPane = function() {
        var root=document.createElement('section');
        root.className='workbench-view loot-settlement-report';
        root.setAttribute('aria-label','关卡行动报告');
        root.innerHTML=''
            +'<div class="loot-settlement-report-scroll">'
            +'  <section class="loot-settlement-report-section" data-settlement-section="report">'
            +'    <header class="loot-settlement-hero"><div><small>STAGE RECORD</small>'
            +'      <h2 data-settlement-stage></h2><p data-settlement-difficulty></p></div>'
            +'      <strong data-settlement-outcome></strong></header>'
            +'    <div class="loot-settlement-metrics">'
            +'      <div><small>作战时间</small><b data-settlement-time></b><em>关卡帧 / 30 FPS</em></div>'
            +'      <div><small>总击杀</small><b data-settlement-kill-total></b><em>由关卡击杀事实汇总</em></div>'
            +'    </div>'
            +'    <div class="loot-settlement-kill-heading"><div><small>ENEMY RECORD</small>'
            +'      <h3>击杀记录</h3></div><span data-settlement-kill-status></span></div>'
            +'    <div class="loot-settlement-kills" data-settlement-kills></div>'
            +'  </section>'
            +'  <section class="loot-settlement-flow-section" data-settlement-section="flows">'
            +'    <header class="loot-settlement-flow-toolbar"><div><small>ASSET RECORD</small>'
            +'      <h2>物资获得与消耗</h2></div><span data-settlement-flow-status></span></header>'
            +'    <div class="loot-settlement-flow-metrics">'
            +'      <div><small>获得</small><b data-settlement-flow-gain></b></div>'
            +'      <div><small>消耗</small><b data-settlement-flow-loss></b></div>'
            +'    </div>'
            +'    <div class="loot-settlement-flows" data-settlement-flows></div>'
            +'  </section>'
            +'</div>';
        this.reportSection=root.querySelector('[data-settlement-section="report"]');
        this.reportOutcome=root.querySelector('[data-settlement-outcome]');
        this.reportStage=root.querySelector('[data-settlement-stage]');
        this.reportDifficulty=root.querySelector('[data-settlement-difficulty]');
        this.reportTime=root.querySelector('[data-settlement-time]');
        this.reportKillTotal=root.querySelector('[data-settlement-kill-total]');
        this.killList=root.querySelector('[data-settlement-kills]');
        this.killStatus=root.querySelector('[data-settlement-kill-status]');
        this.flowSection=root.querySelector('[data-settlement-section="flows"]');
        this.flowList=root.querySelector('[data-settlement-flows]');
        this.flowStatus=root.querySelector('[data-settlement-flow-status]');
        this.flowGainTotal=root.querySelector('[data-settlement-flow-gain]');
        this.flowLossTotal=root.querySelector('[data-settlement-flow-loss]');
        return root;
    };

    View.prototype._createSettlementSidePane = function() {
        var root=document.createElement('section');
        root.className='workbench-view loot-settlement-side';
        root.setAttribute('aria-label','待领取奖励与材料存量');
        root.innerHTML=''
            +'<div class="loot-settlement-tabs loot-settlement-side-tabs" role="tablist" aria-label="奖励与存量">'
            +'  <button type="button" role="tab" data-settlement-side-tab="rewards">待领取奖励</button>'
            +'  <button type="button" role="tab" data-settlement-side-tab="materials">材料存量</button>'
            +'</div>'
            +'<div class="loot-settlement-side-body">'
            +'  <section class="loot-settlement-reward-section" role="tabpanel" data-settlement-side-section="rewards"></section>'
            +'  <section class="loot-settlement-material-section" role="tabpanel" data-settlement-side-section="materials" hidden>'
            +'    <header class="loot-settlement-material-toolbar"><div><small>MATERIAL ARCHIVE</small>'
            +'      <h2>材料存量</h2></div><input type="search" maxlength="64" '
            +'      placeholder="查找材料" aria-label="查找材料"></header>'
            +'    <p class="loot-settlement-material-status" data-settlement-material-status></p>'
            +'    <div class="loot-settlement-materials" data-settlement-materials></div>'
            +'  </section>'
            +'</div>';
        this.rewardTabButton=root.querySelector('[data-settlement-side-tab="rewards"]');
        this.materialTabButton=root.querySelector('[data-settlement-side-tab="materials"]');
        this.rewardSection=root.querySelector('[data-settlement-side-section="rewards"]');
        this.materialSection=root.querySelector('[data-settlement-side-section="materials"]');
        this.materialSearch=root.querySelector('input[type="search"]');
        this.materialStatus=root.querySelector('[data-settlement-material-status]');
        this.materialList=root.querySelector('[data-settlement-materials]');
        this._selectRightTab('rewards');
        return root;
    };

    View.prototype._renderReport = function() {
        var report=this.init&&this.init.report;
        if (!report||!this.reportSection) return;
        this.reportStage.textContent=report.stageName;
        this.reportDifficulty.textContent='难度 · '+report.difficulty;
        this.reportOutcome.textContent=outcomeLabel(report.outcome);
        this.reportOutcome.setAttribute('data-outcome',report.outcome);
        this.reportTime.textContent=formatStageFrames(report.activeFrames);
        this.reportKillTotal.textContent=String(report.totalKills);
        while (this.killList.firstChild) this.killList.removeChild(this.killList.firstChild);
        if (!report.kills.length) {
            var empty=document.createElement('p');
            empty.className='loot-settlement-empty';
            empty.textContent=report.totalKills ? '没有可展示的敌人类型。' : '本次行动没有记录到击杀。';
            this.killList.appendChild(empty);
        }
        for (var i=0;i<report.kills.length;i++) {
            var kill=report.kills[i],card=document.createElement('article');
            card.className='loot-settlement-kill-card';
            card.setAttribute('aria-label',kill.displayName+'，击杀 '+kill.count+' 个'
                +(kill.eliteLevel>0?'，精英等级 '+kill.eliteLevel:''));
            card.title=kill.displayName+' ×'+kill.count
                +(kill.eliteLevel>0?' · 精英等级 '+kill.eliteLevel:'');
            if (kill.eliteLevel>0) card.setAttribute('data-elite',String(kill.eliteLevel));
            var avatar=document.createElement('div');
            avatar.className='loot-settlement-kill-avatar';
            avatar.setAttribute('aria-hidden','true');
            this._mountKillPortrait(avatar,kill);
            var copy=document.createElement('div');
            copy.className='loot-settlement-kill-copy';
            var name=document.createElement('b');
            name.textContent=kill.displayName;
            var detail=document.createElement('small');
            detail.textContent=kill.eliteLevel>0 ? '精英等级 '+kill.eliteLevel : '普通敌人';
            copy.appendChild(name);copy.appendChild(detail);
            var count=document.createElement('strong');
            count.textContent='×'+kill.count;
            count.setAttribute('aria-label','击杀 '+kill.count+' 个');
            card.appendChild(avatar);card.appendChild(copy);card.appendChild(count);
            this.killList.appendChild(card);
        }
        var notices=[];
        if (report.omittedKillTypes) notices.push('另有 '+report.omittedKillTypes+' 类敌人未展开');
        if (report.rewardRollOmissions) notices.push(report.rewardRollOmissions+' 项奖励配置未进入本轮结算');
        this.killStatus.textContent=notices.join(' · ')||('展示 '+report.kills.length+' 类');

        this.flowGainTotal.textContent='+'+String(report.totalItemGains);
        this.flowLossTotal.textContent='−'+String(report.totalItemLosses);
        while (this.flowList.firstChild) this.flowList.removeChild(this.flowList.firstChild);
        if (!report.itemFlows.length) {
            var flowEmpty=document.createElement('p');
            flowEmpty.className='loot-settlement-empty';
            flowEmpty.textContent='本次行动没有记录到物资获得或消耗。';
            this.flowList.appendChild(flowEmpty);
        }
        for (i=0;i<report.itemFlows.length;i++) {
            var flow=report.itemFlows[i],flowCard=document.createElement('article');
            flowCard.className='loot-settlement-flow-card';
            flowCard.setAttribute('data-direction',flow.direction);
            flowCard.title=flow.displayName+' '+(flow.direction==='gain'?'+':'−')+flow.count
                +' · '+flowSourceLabel(flow.source);
            flowCard.setAttribute('aria-label',flowCard.title);
            var flowIcon=document.createElement('div');
            flowIcon.className='loot-settlement-flow-icon';
            flowIcon.innerHTML=iconHtml(flow.iconName||flow.itemKey,
                'loot-settlement-flow-image');
            var flowCopy=document.createElement('div');
            flowCopy.className='loot-settlement-flow-copy';
            var flowName=document.createElement('b');flowName.textContent=flow.displayName;
            var flowDetail=document.createElement('small');
            flowDetail.textContent=flowSourceLabel(flow.source)
                +(flow.reason?' · '+flow.reason:'');
            flowCopy.appendChild(flowName);flowCopy.appendChild(flowDetail);
            var flowCount=document.createElement('strong');
            flowCount.textContent=(flow.direction==='gain'?'+':'−')+flow.count;
            flowCard.appendChild(flowIcon);flowCard.appendChild(flowCopy);
            flowCard.appendChild(flowCount);this.flowList.appendChild(flowCard);
        }
        this.flowStatus.textContent=report.omittedItemFlowTypes
            ? '另有 '+report.omittedItemFlowTypes+' 类物资事实未展开'
            : '展示 '+report.itemFlows.length+' 类';
    };

    function flowSourceLabel(source) {
        var labels={pickup:'拾取',level_reward:'关卡奖励',quest_reward:'任务奖励',
            achievement_reward:'成就奖励',quest_turn_in:'任务交付',
            inventory_discard:'丢弃',equipment_tuning:'装备调制',loot_box:'战利品',
            consumable_effect:'消耗品',reload:'装填',skill_cost:'技能消耗',
            weapon_cost:'武器消耗',item_use:'使用物品',arena_entry:'竞技场入场',
            arena_reward:'竞技场奖励',player_revive:'复活',unknown:'其他'};
        return labels[source]||source;
    }

    View.prototype._mountKillPortrait = function(container,kill) {
        var self=this;
        while (container.firstChild) container.removeChild(container.firstChild);
        container.setAttribute('data-portrait-source','loading');
        var fallback=document.createElement('span');
        fallback.className='loot-settlement-kill-fallback';
        fallback.setAttribute('aria-hidden','true');
        container.appendChild(fallback);
        var image=document.createElement('img');
        image.className='loot-settlement-kill-portrait';
        image.alt='';image.draggable=false;image.decoding='async';
        container.appendChild(image);

        if (kill&&kill.doll) {
            var token='settlement_doll_'+(++this.portraitSequence);
            container.setAttribute('data-settlement-portrait-request',token);
            container.setAttribute('data-portrait-source','doll-pending');
            this._requestDollPortrait(kill.doll).then(function(dataUrl) {
                if (self.destroyed||!dataUrl
                        ||container.getAttribute('data-settlement-portrait-request')!==token)
                    return;
                image.onload=function() {
                    if (!self.destroyed
                            &&container.getAttribute('data-settlement-portrait-request')===token)
                        container.setAttribute('data-portrait-source','doll');
                };
                image.onerror=function() {
                    image.removeAttribute('src');
                    container.setAttribute('data-portrait-source','fallback');
                };
                image.src=dataUrl;
            });
            return;
        }

        if (kill&&kill.iconName&&typeof EnemyPortraits!=='undefined'
                &&EnemyPortraits&&typeof EnemyPortraits.mount==='function') {
            try {
                EnemyPortraits.mount(container,image,{
                    portraitRef:kill.iconName,
                    consumer:'loot-settlement'
                });
                return;
            } catch (ignorePortrait) {}
        }
        image.remove();
        if (kill&&kill.iconName) {
            var icon=document.createElement('span');
            icon.className='loot-settlement-kill-icon-fallback';
            icon.innerHTML=iconHtml(kill.iconName,'loot-settlement-kill-icon');
            container.appendChild(icon);
            container.setAttribute('data-portrait-source','icon');
            return;
        }
        container.setAttribute('data-portrait-source','fallback');
    };

    View.prototype._requestDollPortrait = function(tuple) {
        var normalized={};
        for (var i=0;i<DOLL_FIELDS.length;i++) {
            var field=DOLL_FIELDS[i],value=tuple&&tuple[field];
            normalized[field]=value==null?'':String(value);
        }
        var key=JSON.stringify(normalized);
        if (Object.prototype.hasOwnProperty.call(this.dollPortraitCache,key))
            return this.dollPortraitCache[key];
        var self=this;
        var promise=new Promise(function(resolve) {
            self.dollPortraitQueue.push({tuple:normalized,resolve:resolve});
            self._drainDollPortraitQueue();
        });
        this.dollPortraitCache[key]=promise;
        return promise;
    };

    View.prototype._drainDollPortraitQueue = function() {
        var self=this;
        while (!this.destroyed&&this.dollPortraitActive<2&&this.dollPortraitQueue.length) {
            (function(entry) {
                self.dollPortraitActive++;
                Promise.resolve().then(function() {
                    if (typeof DollBake==='undefined'||!DollBake
                            ||typeof DollBake.renderTupleDataUrl!=='function') return null;
                    return DollBake.renderTupleDataUrl(entry.tuple);
                }).catch(function() { return null; }).then(function(dataUrl) {
                    self.dollPortraitActive--;
                    entry.resolve(dataUrl);
                    self._drainDollPortraitQueue();
                });
            })(this.dollPortraitQueue.shift());
        }
        if (this.destroyed) {
            while (this.dollPortraitQueue.length)
                this.dollPortraitQueue.shift().resolve(null);
        }
    };

    View.prototype._selectRightTab = function(tab) {
        if (!this.isSettlement) return false;
        this.rightTab=tab==='materials'?'materials':'rewards';
        var materials=this.rightTab==='materials';
        if (this.rewardSection) this.rewardSection.hidden=materials;
        if (this.materialSection) this.materialSection.hidden=!materials;
        if (this.rewardTabButton) {
            this.rewardTabButton.setAttribute('aria-selected',materials?'false':'true');
            this.rewardTabButton.tabIndex=materials?-1:0;
        }
        if (this.materialTabButton) {
            this.materialTabButton.setAttribute('aria-selected',materials?'true':'false');
            this.materialTabButton.tabIndex=materials?0:-1;
        }
        if (materials) this._renderMaterials();
        else if (this.rightGrid) this.rightGrid.render();
        return true;
    };

    View.prototype.setMaterials = function(materials,busy,error) {
        this.materials=Array.isArray(materials)?materials.slice():null;
        this.materialsBusy=!!busy;
        this.materialsError=String(error||'');
        this._renderMaterials();
    };

    View.prototype._renderMaterials = function() {
        if (!this.materialList||!this.materialStatus) return;
        while (this.materialList.firstChild) this.materialList.removeChild(this.materialList.firstChild);
        if (this.materialsBusy) {
            this.materialStatus.textContent='正在从游戏读取当前材料存量…';
            this.materialStatus.setAttribute('data-state','busy');
            return;
        }
        if (this.materialsError) {
            this.materialStatus.textContent=this.materialsError;
            this.materialStatus.setAttribute('data-state','error');
            return;
        }
        if (!this.materials) {
            this.materialStatus.textContent='等待材料存量。';
            this.materialStatus.setAttribute('data-state','idle');
            return;
        }
        var query=String(this.materialSearch&&this.materialSearch.value||'').trim().toLowerCase();
        var visible=[];
        for (var i=0;i<this.materials.length;i++) {
            var material=this.materials[i];
            var searchable=(material.displayName+' '+material.name).toLowerCase();
            if (query ? searchable.indexOf(query)>=0 : material.owned>0) visible.push(material);
        }
        this.materialStatus.textContent=query
            ? '匹配 '+visible.length+' / '+this.materials.length+' 种材料'
            : '持有 '+visible.length+' / '+this.materials.length+' 种材料 · 输入名称可查看零库存';
        this.materialStatus.setAttribute('data-state','ready');
        if (!visible.length) {
            var empty=document.createElement('p');
            empty.className='loot-settlement-empty';
            empty.textContent=query?'没有匹配的材料。':'当前没有材料库存。';
            this.materialList.appendChild(empty);
            return;
        }
        for (i=0;i<visible.length;i++) {
            material=visible[i];
            var card=document.createElement('article');
            card.className='loot-settlement-material-card';
            if (!material.owned) card.classList.add('is-empty');
            var icon=document.createElement('div');
            icon.className='loot-settlement-material-icon';
            icon.innerHTML=iconHtml(material.icon,'loot-settlement-material-image');
            icon.setAttribute('aria-hidden','true');
            var name=document.createElement('b');
            name.textContent=material.displayName;
            name.setAttribute('aria-label',material.displayName);
            var owned=document.createElement('strong');
            owned.textContent=String(material.owned);
            owned.setAttribute('aria-label','持有 '+material.owned);
            card.appendChild(icon);card.appendChild(name);card.appendChild(owned);
            this.materialList.appendChild(card);
        }
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
            if (typeof self.options.onRequestClose === 'function') self.options.onRequestClose('header');
        });
        session.listen(this.abandonButton,'click',function() {
            if (typeof self.options.onRequestAbandon === 'function') self.options.onRequestAbandon();
        });
        session.listen(this.reconcileButton,'click',function() {
            if (typeof self.options.onReconcile === 'function') self.options.onReconcile();
        });
        if (this.inventoryButton) session.listen(this.inventoryButton,'click',function() {
            if (typeof self.options.onOpenOrganizer === 'function') self.options.onOpenOrganizer();
        });
        if (this.rewardTabButton) session.listen(this.rewardTabButton,'click',function() {
            self._selectRightTab('rewards');
        });
        if (this.materialTabButton) session.listen(this.materialTabButton,'click',function() {
            self._selectRightTab('materials');
        });
        if (this.materialSearch) session.listen(this.materialSearch,'input',function() {
            self._renderMaterials();
        });
        session.listen(document,'keydown',function(event) { self._onKeyDown(event); },true);
        this.focusScope = new WorkbenchFocus.FocusScope({
            root:this.shell.getRoot(),
            document:document,
            restoreFocus:false,
            onEscape:function() {
                if (typeof self.options.onRequestClose === 'function') self.options.onRequestClose('escape');
                return false;
            }
        });
        this.focusScope.activate({initialFocus:this.closeButton});
        session.defer(function() {
            if (self.focusScope) self.focusScope.destroy();
            self.focusScope = null;
        });

        if (!this.isSettlement) {
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
        }
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
        this.inventoryButton = null;
        this.reportPane = null;
        this.reportView = null;
        this.settlementSidePane = null;
        this.settlementSideView = null;
        this.rewardTabButton = null;
        this.materialTabButton = null;
        this.rewardSection = null;
        this.reportSection = null;
        this.reportOutcome = null;
        this.reportStage = null;
        this.reportDifficulty = null;
        this.reportTime = null;
        this.reportKillTotal = null;
        this.killList = null;
        this.killStatus = null;
        this.flowSection = null;
        this.flowList = null;
        this.flowStatus = null;
        this.flowGainTotal = null;
        this.flowLossTotal = null;
        this.materialSection = null;
        this.materialList = null;
        this.materialSearch = null;
        this.materialStatus = null;
        this.materials = null;
        this.materialsError = '';
        while (this.dollPortraitQueue.length)
            this.dollPortraitQueue.shift().resolve(null);
        this.dollPortraitCache = {};
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
                ? itemName + (this.isSettlement
                    ? '，按 Enter 或单击领取'
                    : '，按 Enter、双击或 Ctrl+单击领取；空格选择后可在左侧确认')
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
                    if (self.isSettlement || event.ctrlKey || event.metaKey || Number(event.detail) >= 2
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
            renderBasic:function(value){return basicTooltip(value,self.isSettlement);},
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
        if (this.isRewardInbox
                && this.init.rootAdmissionEnabled === false
                && state.phase === 'active'
                && !claimAll
                && !organizerActive) {
            this.interaction={inspectable:true,actionable:false,
                reason:'当前为兼容回滚只读模式，不接纳新的领取事务。'};
        }
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
            ? (this.isSettlement ? '待领取 '+state.remainingCount+' 项奖励'
                : '箱内 '+state.remainingCount+' 个非空槽位')
            : (this.isSettlement ? '等待奖励内容' : '等待箱子内容'));
        this.shell.setMetric('remaining',this.isSettlement?'待领奖励':'剩余槽位',
            state.remainingCount == null ? '—' : state.remainingCount);
        var busy=state.phase==='opening'||state.phase==='write_pending'||!!state.pending
            ||claimAll||organizerActive;
        if (state.phase==='reconcile_required') this.shell.setStatus('需要核对','warning');
        else if (state.phase==='terminal') this.shell.setStatus(
            terminalLabel(state.terminal,this.isSettlement),'ready');
        else if (state.phase==='suspended') this.shell.setStatus(
            this.isSettlement?'已保留未领取奖励':'已保留箱内物品','ready');
        else if (busy) this.shell.setStatus(organizerActive ? '整理背包中'
            : claimAll ? '批量领取中' : '游戏确认中','busy');
        else if (state.phase==='active') this.shell.setStatus(
            this.isSettlement?'结算状态已同步':'箱子状态已同步','ready');
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
            this.abandonButton.hidden=!!this.isRewardInbox
                ||state.phase!=='active'||state.remainingCount<=0;
            this.abandonButton.disabled=!!this.isRewardInbox||busy;
        }
        if (this.inventoryButton) {
            this.inventoryButton.disabled=busy||state.phase!=='active';
            this.inventoryButton.setAttribute('aria-busy',organizerActive?'true':'false');
        }
        if (this.commitBar) this.commitBar.update(
            commitPresentation(
                state,claimAll,organizerActive,this.isSettlement,this.isRewardInbox,
                !this.isRewardInbox || this.init.rootAdmissionEnabled === true));
    };

    View.prototype.hasModal = function() { return !!(this.shell && this.shell.hasModal()); };
    View.prototype.closeModal = function(reason) {
        return this.shell ? this.shell.closeModal(reason || 'cancel') : false;
    };
    View.prototype.openHelp = function(opener) {
        return this.helpAction ? this.helpAction.open(opener) : false;
    };
    View.prototype.openAbandon = function(remainingCount,onAbandon) {
        if (!this.shell || this.isRewardInbox) return false;
        var noun=this.isSettlement?'项关卡奖励':'个非空槽位';
        this.shell.openModal({
            kind:'loot-abandon',
            kicker:'尚有 ' + remainingCount + ' '+noun,
            title:this.isSettlement?'永久放弃剩余关卡奖励？':'永久放弃剩余战利品？',
            message:this.isSettlement
                ? '确认后，游戏会永久标记尚未领取的关卡奖励为放弃。'
                : '确认后，游戏会永久标记箱内尚未领取的内容为放弃。',
            detail:this.isSettlement
                ? '普通关闭会保留同一批奖励，稍后可继续领取；此操作无法撤销。'
                : '普通关闭只返回游戏并保留箱子；此操作无法撤销。',
            closeOnBackdrop:true,
            actions:[
                {id:'cancel',label:'继续领取',primary:true,audioCue:'back'},
                {id:'abandon',label:'永久放弃',danger:true,audioCue:'destructive',onSelect:onAbandon}
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
                {id:'cancel',label:'取消',audioCue:'back'},
                {id:'discard',label:'确认丢弃',danger:true,audioCue:'destructive',onSelect:onDiscard}
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
            hasFocusScope:!!this.focusScope,interaction:this.interaction,
            settlement:this.isSettlement,rightTab:this.rightTab,
            materialCount:this.materials?this.materials.length:null,
            materialsBusy:this.materialsBusy,materialsError:this.materialsError};
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
            if (this.isSettlement&&this.rightTab==='materials') return;
            event.preventDefault();
            if (typeof this.options.onPrimary === 'function') this.options.onPrimary();
        }
    };

    var INVENTORY_CAPACITY_BLOCKS = {target_full:true,inventory_full:true};

    function isInventoryCapacityBlock(error) {
        return Object.prototype.hasOwnProperty.call(
            INVENTORY_CAPACITY_BLOCKS,String(error||''));
    }

    function commitPresentation(
            state,claimAll,organizerActive,isSettlement,isRewardInbox,
            rootAdmissionEnabled) {
        var block=blockMessage(state.blockReason);
        if (state.phase==='reconcile_required') return {
            label:'重新核对',
            status:'上一次操作结果未知。这里只重新查询结果，不会再次领取或放弃。',
            state:'blocked',canCommit:!state.pending,busy:!!state.pending
        };
        if (state.phase==='terminal') return {
            label:'已结束',status:terminalLabel(state.terminal,isSettlement),state:'success',disabled:true
        };
        if (state.phase==='suspended') return {
            label:isSettlement?'关闭结算':isRewardInbox?'关闭待领取':'返回游戏',
            status:isSettlement||isRewardInbox?'游戏已确认保留同一批未领取奖励。'
                :'游戏已确认保留同一箱内的剩余战利品。',
            state:'success',disabled:true
        };
        if (state.phase==='write_pending' && state.pending
                && state.pending.kind==='reward_continue') return {
            label:claimAll?'批量领取中':'领取中',status:'正在领取奖励，请稍候。',
            state:'busy',disabled:true,busy:true
        };
        if (state.phase!=='active') return {
            label:'同步中',status:isSettlement?'正在读取游戏中的关卡奖励快照…'
                :isRewardInbox?'正在读取游戏中的待领取物品快照…'
                :'正在读取游戏中的背包与战利品快照…',
            state:'idle',disabled:true,busy:true
        };
        if (organizerActive) return {
            label:'整理背包中',status:isSettlement
                ? '库存稳定并重新同步当前奖励后才能继续领取。'
                : isRewardInbox
                    ? '库存稳定并重新同步待领取物品后才能继续领取。'
                : '库存稳定并重新同步当前箱子后才能继续领取。',
            state:'busy',disabled:true,busy:true
        };
        if (claimAll) return {
            label:'批量领取中',status:'正在由游戏一次确认一批奖励；不会并发提交。',
            state:'busy',disabled:true,busy:true
        };
        if (state.remainingCount===0) return {
            label:isSettlement?'完成结算':isRewardInbox?'完成领取':'关闭空箱',
            status:isSettlement?'游戏确认奖励已全部处理；完成后结束本次结算。'
                :isRewardInbox?'游戏确认待领取物品已全部处理；完成后关闭领取页。'
                :'游戏确认箱内已空；关闭会结束本次拾取。',
            state:'ready',canCommit:true
        };
        if (isInventoryCapacityBlock(state.blockReason)) return {
            label:'整理背包',
            status:'背包已满。可在当前页面转移背包与战备箱物品，再继续领取。',
            state:'blocked',canCommit:true
        };
        if (isRewardInbox && rootAdmissionEnabled === false) return {
            label:'兼容只读',
            status:'当前回滚模式不接纳新的领取事务；既有根仍可重新核对并安全收束。',
            state:'blocked',disabled:true
        };
        return {
            label:'全部收取',
            status:block||(isSettlement
                ? '剩余 '+state.remainingCount+' 项奖励；关闭会保留，永久放弃请使用顶部危险操作。'
                : isRewardInbox
                    ? '剩余 '+state.remainingCount+' 项待领取物品；关闭会保留，不能永久放弃。'
                : '剩余 '+state.remainingCount
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
    function terminalLabel(value,isSettlement) {
        if (!value) return '会话已结束';
        return value.kind==='CONSUMED'
            ? (isSettlement?'关卡奖励已全部处理':'箱内物品已全部领取')
            : value.kind==='ABANDONED'
                ? (isSettlement?'剩余关卡奖励已明确放弃':'剩余战利品已明确放弃')
                : (isSettlement?'本次关卡结算已失效':'箱子已随场景失效');
    }
    function outcomeLabel(value) {
        return value==='victory'?'任务完成':value==='failure'?'任务失败':'主动撤离';
    }
    function formatStageFrames(value) {
        var frames=Math.max(0,Math.floor(Number(value)||0));
        var hours=Math.floor(frames/108000);
        var minutes=Math.floor(frames/1800)%60;
        var seconds=Math.floor(frames/30)%60;
        var hundredths=Math.floor(frames%30*100/30);
        function pad(number) { return number<10?'0'+number:String(number); }
        return (hours?pad(hours)+':':'')+pad(minutes)+':'+pad(seconds)+'.'+pad(hundredths);
    }
    function basicTooltip(item,isSettlement) {
        return '<div class="kshop-tt-header"><b>'+escapeHtml(item.displayName||'未知物品')+'</b></div>'
            +'<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">来源</span> '
            +(isSettlement?'关卡奖励':'地图资源箱')
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
