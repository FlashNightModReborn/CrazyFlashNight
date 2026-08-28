/** Map-chest loot facade. AS2 owns authority; this file only coordinates runtime, model and view. */
var LootPanel = (function() {
    'use strict';

    var _el, _view, _lifecycle, _mux, _model;
    var _inventoryMux, _inventoryCoordinator, _organizer;
    var _inventoryState = {opened:false,ready:false,busyOwner:null,refreshRequired:false};
    var _organizerActive = false, _organizerReturning = false, _organizerDestroying = false;
    var _init, _identity, _generation = 0, _claimAll = false;
    var _transportInstanceId = '';
    var _claimAllTimer = null, _terminalCloseTimer = null, _closingVisual = false;
    var _claimAllQueue = [], _claimAllBlockedSlots = {}, _claimAllBlockedReason = '';
    var _materials = {items:null,busy:false,error:'',requestedRevision:null,dirty:false};
    var _runtimeConfig = typeof window !== 'undefined' && window.__LOOT_PANEL_CONFIG__ || {};

    Panels.register('loot', {
        create:createDOM,
        onOpen:onOpen,
        onRebind:onRebind,
        onClose:cleanup,
        onRequestClose:requestClose,
        // Panels.close() already performed visual detach before this narrow notification hook.
        onForceClose:function() {
            toast('连接已分离；箱内物品已保留，请重新打开战利品面板。');
        }
    });

    function createDOM() {
        _el = document.createElement('div');
        _el.className = 'panel-scale-shell loot-scale-shell';
        return _el;
    }

    function onOpen(el, initData) {
        cleanup();
        var generation = ++_generation;
        _el = el;
        _transportInstanceId = initData && typeof initData.panelInstanceId === 'string'
            && /^[A-Za-z0-9._~-]+$/.test(initData.panelInstanceId)
            && initData.panelInstanceId.length <= 128 ? initData.panelInstanceId : '';
        _init = LootView.normalizeInitData(initData);
        if (!_init) {
            toast('战利品箱启动身份无效，未读取任何奖励。');
            _terminalCloseTimer = setTimeout(function() {
                if (generation === _generation) finishVisualClose('invalid_init');
            }, 0);
            return;
        }

        _identity = {
            panelInstanceId:_init.panelInstanceId,
            chestSessionId:_init.chestSessionId,
            lootContainerId:_init.lootContainerId,
            containerEpoch:_init.containerEpoch,
            source:_init.sourceKind
        };
        _mux = new LootRuntime.RequestMux({
            identity:_identity,
            send:function(message) { return Bridge.send(message); },
            timeoutMs:_runtimeConfig.requestTimeoutMs,
            sessionNonce:_runtimeConfig.sessionNonce,
            router:PanelRuntime.sharedResponseRouter,
            onProtocolError:function(message) {
                if (typeof console !== 'undefined' && console.warn) console.warn(message);
            }
        });
        _mux.openSession();
        _model = new LootState.Coordinator({
            identity:_identity,
            capacity:_init.capacity,
            backpackLimit:50,
            settlementReport:_init.report,
            request:function(cmd, fields, options, callback) {
                return _mux.request(cmd, fields, options, callback);
            },
            onChange:function() {
                if (generation !== _generation) return;
                render();
                var state = _model && _model.debugState();
                if (state && state.phase === 'terminal') scheduleTerminalClose(generation);
                else if (state && state.phase === 'suspended')
                    scheduleSuspendedClose(generation);
            }
        });
        _view = new LootView.View({
            hostElement:_el,
            init:_init,
            identity:_identity,
            runtimeConfig:_runtimeConfig,
            getProjection:projection,
            canWrite:canWrite,
            isOpen:isOpen,
            toast:toast,
            onClaim:function(slot) { claimSlot(slot); },
            onPrimary:primaryAction,
            onRequestClose:requestClose,
            onRequestAbandon:requestAbandon,
            onReconcile:reconcile,
            onOpenOrganizer:function() { openOrganizer(true); },
            requestTooltip:requestTooltip
        });

        _lifecycle = new WorkbenchLifecycle.PanelLifecycle({
            mount:function(host, mountSession) { _view.mount(host, mountSession); },
            activate:function(context, session) { activate(session, generation); },
            deactivate:function() {
                stopClaimAll();
                if (_view) _view.deactivate();
                if (_model) _model.forceDetach();
            }
        });
        try {
            _lifecycle.mount(_el);
            _lifecycle.activate({generation:generation});
        } catch (error) {
            var failedInstanceId = _transportInstanceId;
            cleanup();
            _transportInstanceId = failedInstanceId;
            toast('战利品工作台无法装载；箱内物品已保留，请重新互动后打开战利品面板。');
            _terminalCloseTimer = setTimeout(function() { finishVisualClose('mount_failed'); }, 0);
        }
    }

    function activate(session, generation) {
        session.defer(function() {
            if (_mux) { _mux.destroy(); _mux=null; }
        });
        session.defer(function() { if (_model) _model.destroy(); });
        _view.activate(session);
        setupOrganizer(session,generation);
        _claimAll = false;
        resetClaimAllOutcome();
        _closingVisual = false;
        _model.open(function(ok,response) {
            if (generation !== _generation) return;
            if (!ok) toast(LootView.errorMessage(response && response.error));
            else requestMaterials();
        });
    }

    function projection() { return _model && _model.projection(); }
    function canWrite() {
        return _model && _model.debugState().phase === 'active' && !_claimAll
            && !_organizerActive && !_organizerReturning;
    }

    function setupOrganizer(session,generation) {
        // Register rollback before constructing any secondary runtime so partial mount failures
        // cannot leave another shared-router handler behind.
        session.defer(destroyOrganizerRuntime);
        _inventoryMux = new LootOrganizer.RequestMux({
            panelInstanceId:_identity.panelInstanceId,
            send:function(message) { return Bridge.send(message); },
            timeoutMs:_runtimeConfig.requestTimeoutMs,
            sessionNonce:String(_runtimeConfig.sessionNonce || 'loot')
                + '.inventory.' + String(generation),
            router:PanelRuntime.sharedResponseRouter,
            onProtocolError:function(message) {
                if (typeof console !== 'undefined' && console.warn) console.warn(message);
            }
        });
        _inventoryMux.openSession();
        _inventoryCoordinator = new InventoryRuntime.InventoryCoordinator({
            request:requestInventory,
            requests:[
                {containerId:'背包',offset:0,limit:50,filterKey:'all'},
                {containerId:'战备箱',offset:0,limit:40,filterKey:'all'}
            ],
            onStateChange:function(state) {
                if (generation !== _generation || _organizerDestroying) return;
                _inventoryState=state;
                renderOrganizer();
                render();
            }
        });
        _organizer = new LootOrganizer.Presenter({
            document:document,
            components:WorkbenchComponents,
            inventoryUI:InventoryUI,
            workbench:Workbench,
            tooltip:PanelTooltip,
            host:_view.getOrganizerHost(),
            getWindow:function(containerId) {
                return _inventoryCoordinator && _inventoryCoordinator.getWindow(containerId);
            },
            getRequest:function(containerId) {
                return _inventoryCoordinator && _inventoryCoordinator.getRequest(containerId);
            },
            setWindow:function(containerId,offset,limit,callback) {
                return _inventoryCoordinator
                    && _inventoryCoordinator.setWindow(containerId,offset,limit,callback);
            },
            autoTransfer:function(source,target,done) {
                return _inventoryCoordinator
                    && _inventoryCoordinator.autoTransfer(source,target,done);
            },
            onRequestDiscard:requestOrganizerDiscard,
            onBack:function() { requestOrganizerReturn(); return false; },
            onHelp:function(event) {
                if (_view) _view.openHelp(event && event.currentTarget);
            },
            onClose:function() { requestOrganizerReturn(true); return false; },
            onRetry:retryOrganizerInventory,
            onPageResult:function(result) {
                if (!result || !result.success) toast('战备箱翻页失败。','error');
            },
            onTransferResult:function(result) {
                if (result && result.success) toast('物品已转移。','success');
                else toast(inventoryErrorMessage(result),'error');
            },
            iconHtml:iconHtml,
            toast:toast
        });
    }

    function requestInventory(cmd,payload,callback) {
        return _inventoryMux ? _inventoryMux.request(cmd,payload || {},callback) : null;
    }

    function organizerState() {
        return {
            opened:!!_inventoryState.opened,
            ready:!!_inventoryState.ready,
            busyOwner:_inventoryState.busyOwner || null,
            refreshRequired:!!_inventoryState.refreshRequired,
            returning:_organizerReturning
        };
    }

    function renderOrganizer() {
        if (_organizer) _organizer.render(organizerState());
    }
    function requestTooltip(slot, callback) {
        if (!_model) return false;
        return _model.tooltip(slot, callback);
    }

    function requestMaterials() {
        var state=_model&&_model.debugState();
        if (!_init||_init.sourceKind!=='stage_settlement'||!_mux||!state
                ||state.phase!=='active') return false;
        if (_materials.busy) {
            _materials.dirty=true;
            return false;
        }
        _materials.busy=true;
        _materials.error='';
        _materials.requestedRevision=state.authorityRevision;
        _materials.dirty=false;
        render();
        var accepted=_mux.request('materials',{
            expectedAuthorityRevision:state.authorityRevision
        },{kind:'materials',singleFlight:true,latestWins:true},function(response) {
            _materials.busy=false;
            var current=_model&&_model.debugState();
            if (_materials.dirty||current&&current.phase==='active'
                    &&current.authorityRevision!==_materials.requestedRevision) {
                _materials.dirty=false;
                requestMaterials();
                return;
            }
            if (response&&response.success&&Array.isArray(response.materials)) {
                _materials.items=response.materials;
                _materials.error='';
            } else {
                _materials.error='材料存量读取失败；奖励领取不受影响。';
            }
            render();
        });
        if (!accepted) {
            _materials.busy=false;
            _materials.error='材料存量暂时无法读取；奖励领取不受影响。';
            render();
            return false;
        }
        return true;
    }

    function claimSlot(slot, quiet) {
        if (!slot || !slot.occupied || !_model || _organizerActive || _organizerReturning
                || _claimAll && !quiet) return false;
        var retainedReason=_claimAllBlockedReason,retainedSlots=_claimAllBlockedSlots;
        resetClaimAllOutcome();
        var accepted=_model.claim(slot,function(success,response){
            if (!success && !quiet) toast(writeFailureMessage(response),'error');
            else if (success) {
                if (!quiet) toast(_init&&_init.sourceKind==='stage_settlement'
                    ? '奖励已由游戏确认领取。' : '战利品已由游戏确认领取。','success');
                requestMaterials();
            }
        });
        if (!accepted) {
            _claimAllBlockedReason=retainedReason;
            _claimAllBlockedSlots=retainedSlots;
            if (!quiet) toast('当前无法领取，请先完成正在进行的操作。');
            render();
        }
        return accepted;
    }

    function startClaimAll() {
        var state=_model&&_model.debugState(),current=projection();
        if (!state||state.phase!=='active'||state.remainingCount<=0||_claimAll
                ||_organizerActive||_organizerReturning) return false;
        var slots=current&&current.loot&&current.loot.slots||[];
        resetClaimAllOutcome();
        for (var i=0;i<slots.length;i++)
            if (slots[i].occupied) _claimAllQueue.push(Number(slots[i].physicalSlot));
        if (!_claimAllQueue.length) return false;
        _claimAll=true;
        if (_view) _view.clearSelection();
        render();
        drainClaimAll();
        return true;
    }
    function claimAllBatchAdvanced(checkpoint) {
        var state=_model&&_model.debugState(),current=projection();
        var applied=state?state.authorityRevision-checkpoint.authorityRevision:0;
        if (!state||state.phase!=='active'||applied<1
                ||applied>checkpoint.physicalSlots.length
                ||state.remainingCount!==checkpoint.remainingCount-applied) return null;
        var slots=current&&current.loot&&current.loot.slots||[];
        var bySlot={},retained=[];
        for (var i=0;i<slots.length;i++) bySlot[String(slots[i].physicalSlot)]=slots[i];
        for (i=0;i<checkpoint.physicalSlots.length;i++) {
            var physicalSlot=checkpoint.physicalSlots[i],slot=bySlot[String(physicalSlot)];
            if (!slot) return null;
            if (slot.occupied) {
                if (slot.slotLease!==checkpoint.slotLeases[i]) return null;
                retained.push(physicalSlot);
            }
        }
        return checkpoint.physicalSlots.length-retained.length===applied
            ? {applied:applied,retained:retained}:null;
    }
    function claimAllBatchCapacityRejected(response,checkpoint) {
        var error=response&&response.error||'';
        var capacityErrors={
            target_full:true,inventory_full:true,capacity_reached:true,cap_reached:true
        };
        if (!response||response.success!==false
                ||!Object.prototype.hasOwnProperty.call(capacityErrors,String(error))
                ||response.authorityRevision!==checkpoint.authorityRevision
                ||response.remainingCount!==checkpoint.remainingCount
                ||String(response.lastAppliedOperationId||'')!==checkpoint.lastAppliedOperationId)
            return false;
        var state=_model&&_model.debugState(),current=projection();
        if (!state||state.phase!=='active'
                ||state.authorityRevision!==checkpoint.authorityRevision
                ||state.remainingCount!==checkpoint.remainingCount) return false;
        var slots=current&&current.loot&&current.loot.slots||[];
        var bySlot={};
        for (var i=0;i<slots.length;i++) bySlot[String(slots[i].physicalSlot)]=slots[i];
        for (i=0;i<checkpoint.physicalSlots.length;i++) {
            var slot=bySlot[String(checkpoint.physicalSlots[i])];
            if (!slot||!slot.occupied||slot.slotLease!==checkpoint.slotLeases[i]) return false;
        }
        return true;
    }
    function findLootSlot(physicalSlot) {
        var current=projection(),slots=current&&current.loot&&current.loot.slots||[];
        for (var i=0;i<slots.length;i++)
            if (Number(slots[i].physicalSlot)===Number(physicalSlot)) return slots[i];
        return null;
    }
    function scheduleClaimAllDrain() {
        _claimAllTimer=setTimeout(function(){
            _claimAllTimer=null;
            drainClaimAll();
        },0);
    }
    function claimAllBlockedCount() { return Object.keys(_claimAllBlockedSlots).length; }
    function claimAllBlocksCoverRemaining(state) {
        var current=projection(),slots=current&&current.loot&&current.loot.slots||[];
        var occupied=0;
        for (var i=0;i<slots.length;i++) {
            if (!slots[i].occupied) continue;
            occupied++;
            if (!Object.prototype.hasOwnProperty.call(
                    _claimAllBlockedSlots,String(slots[i].physicalSlot))) return false;
        }
        return occupied===state.remainingCount&&occupied===claimAllBlockedCount();
    }
    function resetClaimAllOutcome() {
        _claimAllQueue=[];
        _claimAllBlockedSlots={};
        _claimAllBlockedReason='';
    }
    function drainClaimAll() {
        if (!_claimAll||!_model) return;
        var state=_model.debugState();
        if (state.phase==='reconcile_required'||state.phase==='terminal') {
            stopClaimAll();
            return;
        }
        if (state.phase!=='active') return;
        var batch=[];
        while (_claimAllQueue.length&&batch.length<50) {
            var physicalSlot=_claimAllQueue.shift(),candidate=findLootSlot(physicalSlot);
            if (candidate&&candidate.occupied
                    &&!Object.prototype.hasOwnProperty.call(
                        _claimAllBlockedSlots,String(candidate.physicalSlot))) batch.push(candidate);
        }
        if (!batch.length) {
            // “全部收取”是一个完整主动作：最后一批 claim 的权威 ACTIVE 投影已证明
            // remainingCount=0 后，继续提交既有 lootClose(abandon=false)，让 AS2 生成
            // CONSUMED tombstone。视觉层仍只在 terminal 回包后关闭，不能把本地空网格
            // 当成终态，也不能绕过 Host 的 exact close / pause-release 链。
            var blockedCount=claimAllBlockedCount();
            var completedWithBlocks=state.remainingCount>0&&blockedCount>0
                &&claimAllBlocksCoverRemaining(state);
            stopClaimAll(completedWithBlocks);
            if (state.remainingCount===0) commitClose(false);
            else if (completedWithBlocks) {
                requestMaterials();
                toast('已收取所有可放入物品；仍有 '
                +state.remainingCount+' 个物品因背包或容量限制保留。','success');
            } else toast('箱内仍有未遍历物品，已停止全部收取，请人工核对。','error');
            return;
        }
        var checkpoint={
            authorityRevision:state.authorityRevision,
            remainingCount:state.remainingCount,
            physicalSlots:batch.map(function(slot){return Number(slot.physicalSlot);}),
            slotLeases:batch.map(function(slot){return String(slot.slotLease);}),
            lastAppliedOperationId:String(projection().lastAppliedOperationId||'')
        };
        if (!_model.claimBatch(batch,function(success,response){
            if (!success) {
                var error=response&&response.error||'';
                if (claimAllBatchCapacityRejected(response,checkpoint)) {
                    for (var blockedIndex=0;blockedIndex<checkpoint.physicalSlots.length;
                            blockedIndex++) {
                        _claimAllBlockedSlots[String(checkpoint.physicalSlots[blockedIndex])]=
                            String(error);
                    }
                    if (!_claimAllBlockedReason) _claimAllBlockedReason=String(error);
                    scheduleClaimAllDrain();
                    return;
                }
                stopClaimAll();
                if (/^(target_full|inventory_full|capacity_reached|cap_reached)$/.test(String(error)))
                    toast('容量拒绝未满足零写证明，已停止全部收取，请人工核对。','error');
                else toast(writeFailureMessage(response),'error');
                return;
            }
            // A syntactically valid success is insufficient for a batch loop. Require exact
            // authority/remaining deltas and an exact requested-slot projection before issuing
            // another write; otherwise a future protocol drift could replay claims forever.
            var advance=claimAllBatchAdvanced(checkpoint);
            if (!advance) {
                stopClaimAll();
                toast('领取结果没有变化，已停止全部收取，请人工核对。','error');
                return;
            }
            if (advance.retained.length) {
                for (var retainedIndex=0;retainedIndex<advance.retained.length;retainedIndex++) {
                    _claimAllBlockedSlots[String(advance.retained[retainedIndex])]='target_full';
                }
                if (!_claimAllBlockedReason) _claimAllBlockedReason='target_full';
            }
            scheduleClaimAllDrain();
        })) {
            stopClaimAll();
            toast('当前无法继续全部收取，请先完成正在进行的操作。');
        }
    }
    function stopClaimAll(preserveOutcome) {
        _claimAll=false;
        _claimAllQueue=[];
        if (_claimAllTimer!=null) {
            clearTimeout(_claimAllTimer);
            _claimAllTimer=null;
        }
        if (!preserveOutcome) {
            _claimAllBlockedSlots={};
            _claimAllBlockedReason='';
        }
        render();
    }

    function openOrganizer(force) {
        var state=_model&&_model.debugState();
        var capacityBlocked=state&&(LootView.isInventoryCapacityBlock(state.blockReason)
            ||LootView.isInventoryCapacityBlock(_claimAllBlockedReason));
        var settlementAccess=force===true&&_init&&_init.sourceKind==='stage_settlement';
        if (!state||state.phase!=='active'||state.pending||_claimAll
                ||!capacityBlocked&&!settlementAccess
                ||!_organizer||!_inventoryCoordinator) return false;
        if (_organizerActive) return true;
        if (!_organizer.open()) {
            toast('整理背包页面无法打开。');
            return false;
        }
        _organizerActive=true;
        _organizerReturning=false;
        render();
        _inventoryCoordinator.open(function(result) {
            if (!_organizerActive) return;
            renderOrganizer();
            if (!result || !result.success)
                toast('库存同步失败；请重试后再返回战利品。','error');
        });
        return true;
    }

    function retryOrganizerInventory() {
        if (!_organizerActive||!_inventoryCoordinator||_inventoryState.busyOwner
                ||!_inventoryState.refreshRequired||_organizerReturning) return false;
        return _inventoryCoordinator.retryRefresh(function(result) {
            if (!_organizerActive) return;
            if (!result || !result.success) toast('库存同步仍未完成，请重试。','error');
        });
    }

    function requestOrganizerReturn(closePanel) {
        if (!_organizerActive||!_organizer||!_inventoryCoordinator) return false;
        if (_organizerReturning) {
            toast('正在重新核对当前箱子，请稍候。');
            return false;
        }
        if (_inventoryState.busyOwner) {
            toast('库存操作或结果核对仍在进行，完成前不能返回战利品。');
            return false;
        }
        if (_inventoryState.refreshRequired) {
            toast('库存状态尚未重新同步，请先重试。');
            return false;
        }
        if (!_inventoryState.ready) {
            toast('库存尚未同步完成，请稍候。');
            return false;
        }
        _organizerReturning=true;
        renderOrganizer();
        render();
        var accepted=_model&&_model.refresh(function(success,response) {
            if (!_organizerActive) return;
            if (!success) {
                _organizerReturning=false;
                renderOrganizer();
                render();
                var state=_model&&_model.debugState();
                if (state&&state.phase==='active')
                    toast('当前箱子重新同步失败；仍停留在整理页，不会再次提交领取。','error');
                return;
            }
            _claimAllBlockedSlots={};
            _claimAllBlockedReason='';
            _claimAllQueue=[];
            _organizer.close('return');
            _organizerActive=false;
            _organizerReturning=false;
            _inventoryCoordinator.close();
            render();
            requestMaterials();
            toast('库存与当前箱子已重新同步，可以继续领取。','success');
            if (closePanel) requestClose();
        });
        if (!accepted) {
            _organizerReturning=false;
            renderOrganizer();
            render();
            toast('当前箱子暂时无法重新同步；仍停留在整理页。','error');
            return false;
        }
        return true;
    }

    function requestOrganizerDiscard(slot) {
        if (!_organizerActive||_organizerReturning||!_inventoryCoordinator
                ||!_inventoryState.ready||_inventoryState.busyOwner
                ||_inventoryState.refreshRequired||!slot||!slot.occupied) return false;
        return _view.openDiscard(slot,function() {
            if (!_organizerActive||_organizerReturning||!_inventoryCoordinator
                    ||!_inventoryState.ready||_inventoryState.busyOwner
                    ||_inventoryState.refreshRequired) return;
            var source={
                containerId:'背包',slot:Number(slot.physicalSlot),
                expectedLease:String(slot.slotLease)
            };
            if (!_inventoryCoordinator.discard(source,function(result) {
                if (!_organizerActive) return;
                renderOrganizer();
                if (result&&result.success) toast('物品已丢弃。','success');
                else toast(inventoryErrorMessage(result),'error');
            })) toast('库存正在处理另一项操作。');
        });
    }

    function primaryAction() {
        var state=_model&&_model.debugState();
        if (!state) return;
        if (_organizerActive||_organizerReturning) return;
        if (state.phase==='reconcile_required') { reconcile();return; }
        if (state.phase!=='active') return;
        if (state.remainingCount===0) commitClose(false);
        else if (LootView.isInventoryCapacityBlock(state.blockReason)
                ||LootView.isInventoryCapacityBlock(_claimAllBlockedReason)) openOrganizer();
        else startClaimAll();
    }

    function requestClose(reason) {
        if (_view&&_view.hasModal()) { _view.closeModal('cancel');return; }
        if (_organizerActive) { requestOrganizerReturn(reason === 'escape' ? undefined : true);return; } // 契约 §5.5：Esc 只返回战利品视图；×/backdrop/toggle 重同步后直接关面板
        var state=_model&&_model.debugState();
        if (!state||state.phase==='opening') {
            toast('正在读取箱子内容，请稍候。');
            return;
        }
        if (state.phase==='write_pending'||_claimAll) {
            toast('领取或关闭正在由游戏确认，请稍候。');
            return;
        }
        if (state.phase==='reconcile_required') {
            toast('上一次操作结果未知；请先重新核对，再安全返回游戏。');
            return;
        }
        if (state.phase==='terminal') { finishVisualClose('terminal');return; }
        if (state.phase==='suspended') { finishVisualClose('suspended');return; }
        if (state.phase!=='active') return;
        if (state.remainingCount===0) { commitClose(false);return; }
        commitClose(false);
    }

    function requestAbandon() {
        if (_view&&_view.hasModal()) return;
        var state=_model&&_model.debugState();
        if (!state||state.phase!=='active'||state.remainingCount<=0||_claimAll
                ||_organizerActive||_organizerReturning) {
            toast('当前不能永久放弃；请先完成正在进行的操作或结果核对。');
            return;
        }
        if (_view) _view.openAbandon(state.remainingCount,function(){commitClose(true);});
    }

    function commitClose(abandon) {
        if (!_model||!_model.close(abandon,function(success,response){
            if (!success) toast(writeFailureMessage(response),'error');
        })) toast('当前无法结束箱子会话，请先完成结果核对。');
    }
    function writeFailureMessage(response) {
        var state=_model&&_model.debugState();
        if (state&&state.phase==='reconcile_required')
            return '本次操作结果尚未由游戏中的实际结果确认，请先重新核对；不会自动重试。';
        return LootView.errorMessage(response&&response.error);
    }
    function reconcile() {
        if (_organizerActive||_organizerReturning) {
            toast('请先完成库存整理与当前箱子重新同步。');
            return;
        }
        if (!_model||!_model.query(function(success,response){
            if (!success) toast(LootView.errorMessage(response&&response.error||'stale_reconcile'),'error');
            else toast('已取得包含上一次操作的最新状态。','success');
        })) toast('当前没有可执行的结果查询，或查询仍在进行。');
    }
    function render() {
        if (!_view||!_model) return;
        var state=_model.debugState();
        if (_claimAllBlockedReason) state.blockReason=_claimAllBlockedReason;
        state.claimAllBlockedReason=_claimAllBlockedReason;
        state.claimAllBlockedCount=claimAllBlockedCount();
        _view.setMaterials(_materials.items,_materials.busy,_materials.error);
        _view.render(state,projection(),_claimAll,_organizerActive||_organizerReturning);
    }

    function scheduleTerminalClose(generation) {
        scheduleAuthorityClose(generation,'terminal');
    }
    function scheduleSuspendedClose(generation) {
        scheduleAuthorityClose(generation,'suspended');
    }
    function scheduleAuthorityClose(generation,reason) {
        if (_terminalCloseTimer!=null) return;
        _terminalCloseTimer=setTimeout(function(){
            _terminalCloseTimer=null;
            if (generation===_generation) finishVisualClose(reason);
        },0);
    }
    function finishVisualClose(reason) {
        if (_closingVisual) return;
        _closingVisual=true;
        var panelInstanceId=_identity&&_identity.panelInstanceId
            ||_init&&_init.panelInstanceId||_transportInstanceId||'';
        Panels.close();
        var message={type:'panel',cmd:'close',panel:'loot',reason:String(reason||'closed')};
        if (panelInstanceId) message.panelInstanceId=panelInstanceId;
        Bridge.send(message);
    }

    function onRebind(el,initData) { cleanup();onOpen(el,initData); }
    function destroyOrganizerRuntime() {
        if (_organizerDestroying) return;
        _organizerDestroying=true;
        if (_organizer) {
            try { _organizer.destroy(); }
            catch (error) {
                if (typeof console !== 'undefined'&&console.error) console.error(error);
            }
        }
        if (_inventoryCoordinator) _inventoryCoordinator.close();
        if (_inventoryMux) _inventoryMux.destroy();
        _organizer=null;
        _inventoryCoordinator=null;
        _inventoryMux=null;
        _inventoryState={opened:false,ready:false,busyOwner:null,refreshRequired:false};
        _organizerActive=false;
        _organizerReturning=false;
        _organizerDestroying=false;
    }
    function cleanup() {
        _generation++;
        stopClaimAll();
        if (_terminalCloseTimer!=null) {
            clearTimeout(_terminalCloseTimer);
            _terminalCloseTimer=null;
        }
        if (_lifecycle) {
            try { _lifecycle.destroy('panel_close'); }
            catch (error) {
                if (typeof console !== 'undefined' && console.error) console.error(error);
            }
            _lifecycle=null;
        } else {
            destroyOrganizerRuntime();
            if (_model) _model.forceDetach();
            if (_mux) _mux.destroy();
        }
        if (_view) _view.destroy();
        if (_el) while (_el.firstChild) _el.removeChild(_el.firstChild);
        _view=null;
        _mux=null;
        _model=null;
        _identity=null;
        _init=null;
        _transportInstanceId='';
        _closingVisual=false;
        _organizerActive=false;
        _organizerReturning=false;
        _materials={items:null,busy:false,error:'',requestedRevision:null,dirty:false};
        resetClaimAllOutcome();
    }

    function isOpen() {
        return Panels.getActive ? Panels.getActive()==='loot' : Panels.isOpen();
    }
    function toast(message,severity) {
        if (typeof Toast!=='undefined'&&Toast.add) Toast.add(message,severity);
    }
    function iconHtml(name,cls) {
        return typeof Icons!=='undefined'&&Icons.html ? Icons.html(name,cls||'') : '';
    }
    function inventoryErrorMessage(result) {
        var error=result&&result.error||'inventory_failed';
        if (result&&result.refreshError) return '库存写入结果无法重新核对，请重试同步。';
        if (error==='target_full') return '目标容器没有可用空间。';
        if (error==='slot_locked'||error==='stale_lease') return '物品状态已变化，请重新同步。';
        if (error==='client_timeout'||error==='disconnected') return '库存操作结果未知，正在重新核对。';
        return '库存操作未完成，请重试。';
    }

    return {
        debugState:function() {
            var state=_model?_model.debugState():{phase:'closed'};
            var viewState=_view?_view.debugState():{};
            state.claimAll=_claimAll;
            state.claimAllBlockedReason=_claimAllBlockedReason;
            state.claimAllBlockedSlots=Object.keys(_claimAllBlockedSlots).map(Number);
            state.claimAllQueueLength=_claimAllQueue.length;
            state.hasLifecycle=!!_lifecycle;
            state.hasMux=!!_mux;
            state.hasDrag=!!viewState.hasDrag;
            state.organizerActive=_organizerActive;
            state.organizerReturning=_organizerReturning;
            state.inventory=_inventoryCoordinator?_inventoryCoordinator.debugState()
                : {opened:false,ready:false,busyOwner:null,refreshRequired:false};
            state.organizer=_organizer?_organizer.debugState():{active:false};
            state.materials={busy:_materials.busy,error:_materials.error,
                count:_materials.items?_materials.items.length:null,
                requestedRevision:_materials.requestedRevision,dirty:_materials.dirty};
            return state;
        },
        requestClose:requestClose,
        reconcile:reconcile,
        exactInitData:LootView.normalizeInitData
    };
})();
