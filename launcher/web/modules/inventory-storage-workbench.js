/**
 * Standalone owned-inventory workbench（背包—仓库 / 背包—战备箱）。
 *
 * This panel never enters the shop lifecycle. InventoryPanelService remains the
 * authority; the Web layer only renders leased windows and emits operation intents.
 */
var InventoryStorageWorkbench = (function() {
    'use strict';
    var _el, _shell, _backpackView, _rightView, _ownedPanes = {}, _tuningView, _pager, _retryButton;
    var _backpackSortControls, _rightSortControls;
    var _quickBarView, _quickDepositButton, _quickWithdrawButton, _quickCommitButton, _quickCancelButton, _quickStatusNode;
    var _broker, _dragControllers = [], _equipmentInspector = null, _tuningScope = null, _state = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _tooltipCache = {}, _tooltipSuppressed = false, _lastBackpackFocus = null;
    var _layoutMode = 'full', _densityController = null, _openGeneration = 0;
    var _profile = 'battlebox';
    var _viewMode = 'storage', _ownerPanel = '', _panelInstanceId = '', _tuningOrigin = false;
    var _rightContainerId = '战备箱';
    var _rightLimit = 40, _renderedWindows = {};
    var _ports = {};
    var _runtimeConfig = (typeof window !== 'undefined' && window.__INVENTORY_WORKBENCH_CONFIG__) || {};
    var _mux = new PanelRuntime.PanelRequestMux({
        send: function(message) { return Bridge.send(message); },
        timeoutMs: _runtimeConfig.requestTimeoutMs,
        sessionNonce: _runtimeConfig.sessionNonce,
        callPrefix: 'inventory-workbench',
        router: PanelRuntime.sharedResponseRouter,
        onProtocolError: function(message) {
            if (typeof console !== 'undefined' && console.warn) console.warn(message);
        },
        validateSession:function(session) {
            return !!session && /^(workbench|crafting|kshop|npcshop)$/.test(String(session.ownerPanel || ''))
                && /^[A-Za-z0-9._~-]{1,128}$/.test(String(session.panelInstanceId || '')); },
        createMessage: function(context) {
            return {type:'panel', domain:'inventory', panel:context.session.ownerPanel,
                panelInstanceId:context.session.panelInstanceId, cmd:context.entry.cmd,
                callId:context.entry.callId, payload:context.payload || {}};
        },
        validateResponse: function(data, entry) {
            return data && data.type === 'panel_resp' && data.domain === 'inventory'
                && data.callId === entry.callId && data.cmd === entry.cmd && data.panel === entry.session.ownerPanel
                && data.panelInstanceId === entry.session.panelInstanceId;
        },
        createSynthetic: function(context) {
            return {type:'panel_resp', domain:'inventory', panel:context.session.ownerPanel,
                panelInstanceId:context.session.panelInstanceId, cmd:context.entry.cmd, callId:context.entry.callId,
                success:false, error:context.error === 'not_sent' ? 'disconnected' : context.error,
                clientSynthetic:true};
        }
    });
    var _coordinator = new InventoryRuntime.InventoryCoordinator({
        request: requestInventory,
        requests: [
            {containerId:'背包', offset:0, limit:50},
            {containerId:'战备箱', offset:0, limit:40}
        ],
        onStateChange:function(state) { _state = state; renderInventories(); refreshControls(); }
    });
    var _quickTransfer = new InventoryWorkbenchQuickTransfer.QuickTransferController({
        rightContainerId:_rightContainerId,
        limit:50,
        getAuthorityState:function() { return _state; },
        getGeneration:function() { return _openGeneration; },
        isGenerationCurrent:function(generation) { return generation === _openGeneration; },
        getSlot:findCurrentSlot,
        slotRef:slotRef,
        autoTransfer:function(source, target, done) { return _coordinator.autoTransfer(source, target, done); },
        onChange:function() {
            clearSelection(); hideTooltip(); renderInventories(); refreshControls();
        },
        onNotice:function(reason) {
            var messages = {
                not_ready:'库存尚未就绪。', in_flight:'请等待当前快速转移完成。',
                deposit_source:'批量存入模式：请点击背包中的物品。',
                withdraw_source:'批量取出模式：请点击' + _rightContainerId + '中的物品。',
                busy:'库存正在处理另一项操作。', already_in_flight:'该物品正在转移，无法取消。',
                queue_full:'批量转移最多选择 50 格。',
                no_mode:'请先选择批量存入或批量取出。',
                nothing_selected:'请先选择至少一件物品。'
            };
            toast(messages[reason] || '库存正在处理另一项操作。');
        },
        onError:function(result) {
            var error = result && result.error;
            if (error === 'target_full') toast('目标容器已满，快速转移已停止。');
            else if (error === 'slot_locked') toast('目标容器尚未解锁，快速转移已停止。');
            else if (result && result.reconciled) toast('库存状态已变化；已重新同步并停止队列。');
            else toast(errorMessage(error));
        }
    });
    function tuningFeatureAvailable() {
        return typeof InventoryTuningScope !== 'undefined'
            && InventoryTuningScope && typeof InventoryTuningScope.Transition === 'function'
            && typeof EquipmentTuningView !== 'undefined'
            && EquipmentTuningView && typeof EquipmentTuningView.create === 'function'
            && typeof EquipmentTuningRuntime !== 'undefined'
            && EquipmentTuningRuntime && typeof EquipmentTuningRuntime.safeToken === 'function';
    }
    function ensureTuningFeature() {
        if (_tuningScope && _tuningView) return true;
        if (!tuningFeatureAvailable()) return false;
        _tuningScope = new InventoryTuningScope.Transition({
            coordinator:_coordinator, initialFocus:_lastBackpackFocus,
            getRoot:function() { return _backpackView && _backpackView.renderer.root; }
        });
        _tuningView = EquipmentTuningView.create({
            instanceKey:'equipment-tuning:' + _profile,
            send:function(message) { return Bridge.send(message); },
            timeoutMs:_runtimeConfig.requestTimeoutMs,
            sessionNonce:_runtimeConfig.sessionNonce,
            beginWrite:function(owner) { return _coordinator.beginExternalWrite(owner); },
            completeWrite:function(operation, needsRefresh, callback) {
                return _coordinator.completeExternalWrite(operation, needsRefresh, callback);
            },
            refreshInventory:function(callback) {
                return _coordinator.debugState().refreshRequired
                    ? _coordinator.retryRefresh(callback) : _coordinator.refresh(callback);
            },
            resolveSlot:function(containerId, physicalSlot) {
                return findCurrentSlot(containerId, physicalSlot);
            },
            onStateChange:function() {
                applyTuningSourceSlotState();
                refreshControls();
            },
            densityController:_densityController,
            loadConversionCandidates:loadTuningConversionCandidates,
            openInspector:openEquipmentInspector,
            closeInspector:closeEquipmentInspector,
            toast:toast
        });
        _tuningScope.attach();
        return true;
    }
    function buildProfileDOM(config, initialView, context) {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required');
        if (!config || !context || !context.shell || !context.root
                || (initialView !== 'storage' && initialView !== 'tuning')) {
            throw new Error('Inventory workbench initData rejected');
        }
        if (_pager) _pager.detach();
        for (var oldDrag = 0; oldDrag < _dragControllers.length; oldDrag++) _dragControllers[oldDrag].cancel();
        if (_broker) _broker.clearSelection();
        disposeInventoryControls();
        disposeOwnedPanes();
        closeEquipmentInspector();
        if (_tuningView) { _tuningView.destroy(); _tuningView = null; }
        if (_tuningScope) { _tuningScope.destroy(); _tuningScope = null; }
        _shell = context.shell; _el = context.root; _ports = context;
        _backpackView = null; _rightView = null; _pager = null;
        _renderedWindows = {}; _lastBackpackFocus = null;
        _backpackSortControls = null; _rightSortControls = null;
        _quickBarView = null;
        _quickDepositButton = null; _quickWithdrawButton = null;
        _quickCommitButton = null; _quickCancelButton = null; _quickStatusNode = null;
        _broker = null; _dragControllers = [];
        _quickTransfer.reset();
        _profile = config.profile; _viewMode = initialView;
        _ownerPanel = String(context.ownerPanel || ''); _panelInstanceId = String(context.panelInstanceId || '');
        _rightContainerId = config.rightContainerId; _rightLimit = config.rightLimit;
        _quickTransfer.configure({rightContainerId:_rightContainerId});
        _densityController = context.densityController || null;
        if (!_densityController) throw new Error('Inventory workbench density controller is required');
        _layoutMode = _densityController.mode;
        if (initialView === 'tuning' && !ensureTuningFeature()) {
            throw new Error('Inventory tuning feature dependencies are unavailable');
        }
        var backpackRequest = {containerId:'背包', offset:0, limit:50, filterKey:'all'};
        if (!_coordinator.configureRequests([
            initialView === 'tuning'
                ? _tuningScope.prepareInitial(backpackRequest, initialView)
                : backpackRequest,
            {containerId:_rightContainerId, offset:0, limit:_rightLimit, filterKey:'all'}
        ])) throw new Error('Inventory workbench request profile rejected: ' + _profile);
        _el.setAttribute('data-inventory-profile', _profile);
        _el.setAttribute('data-workbench-view', _viewMode);
        installQuickTransferActions();
        _el.setAttribute('data-layout-mode', _layoutMode);
        _retryButton = document.createElement('button');
        _retryButton.type = 'button'; _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重试同步'; _retryButton.style.display = 'none';
        _retryButton.addEventListener('click', retryRefresh);
        if (_ports.addHeaderAction) _ports.addHeaderAction(_retryButton);
        _backpackView = createInventoryView('背包', '背包', _layoutMode);
        _backpackView.renderer.root.addEventListener('focusin', function(event) {
            var tile = event.target && event.target.closest ? event.target.closest('[data-workbench-key]') : null;
            if (tile) _lastBackpackFocus = {key:String(tile.getAttribute('data-workbench-key')), role:event.target.closest('.inventory-discard-btn') ? 'discard' : 'tile'};
        });
        _rightView = createInventoryView(_rightContainerId, config.title, _layoutMode);
        _pager = new InventoryUI.InventoryWindowPager({
            containerId:_rightContainerId, containerLabel:config.title, columns:config.pageColumns,
            defaultOffset:0, defaultLimit:_rightLimit, defaultCapacity:config.rightCapacity,
            getSnapshot:function() { return _coordinator.getWindow(_rightContainerId); },
            getRequest:function() { return _coordinator.getRequest(_rightContainerId); },
            shortcutEnabled:shortcutsEnabled,
            onBeforeChange:function() { exitQuickMode(); clearSelection(); hideTooltip(); },
            onRequest:function(offset, limit, callback) {
                return _coordinator.setWindow(_rightContainerId, offset, limit, callback); },
            onResult:function(result) { renderInventories();
                if (!result || !result.success) toast(config.title + '翻页失败，请重试。'); }
        });
        _backpackView.chrome.setToolbar(createInventoryToolbar('背包', null));
        _rightView.chrome.setToolbar(createInventoryToolbar(_rightContainerId, _pager));
        if (_viewMode === 'tuning') _tuningView.openSession(_panelInstanceId);
        if (!_shell.mountInitial(_backpackView, _viewMode === 'tuning' ? _tuningView : _rightView)) {
            throw new Error('Inventory workbench initial view configuration rejected');
        }
        if (_ports.onViewChanged) _ports.onViewChanged(_viewMode);
        installInteractions();
        if (_tuningScope) _tuningScope.attach();
    }
    function switchView(nextView, preferredSlot, callback) {
        var onComplete = typeof callback === 'function' ? callback : function() {};
        var completed = false;
        function complete(success) {
            if (!completed) { completed = true; onComplete(!!success); }
        }
        if (!_tuningOrigin || !_shell || !_rightView
                || (nextView !== 'storage' && nextView !== 'tuning')) return false;
        if (nextView === 'tuning' && !ensureTuningFeature()) {
            toast('装备调制资源尚未就绪。');
            complete(false);
            return false;
        }
        if (_state.busyOwner || _quickTransfer.isBusy()) {
            toast('库存或调制写入尚未完成，请稍候切换。');
            complete(false);
            return false;
        }
        if (_viewMode === 'tuning' && !_tuningView.canClose()) {
            toast('调制请求或对账尚未完成，请稍候切换。');
            complete(false);
            return false;
        }
        if (nextView === _viewMode) {
            var tuningState = _tuningView && _tuningView.debugState();
            var scopeState = _tuningScope && _tuningScope.debugState();
            var ready = nextView === 'storage'
                || tuningState && tuningState.mux && tuningState.mux.active
                || scopeState && scopeState.hasReturnState && finishViewSwitch('tuning');
            if (!ready) toast('无法恢复背包装备调制会话。');
            complete(ready);
            return !!ready;
        }
        if (_viewMode === 'tuning' && nextView === 'storage') {
            var started = _tuningView.detachSession(function(detached) {
                if (!detached) {
                    toast('未能撤销调制令牌，仍停留在调制视图。');
                    complete(false);
                    return;
                }
                if (!_tuningScope.leave(function(result) {
                    if (result && result.success && finishViewSwitch('storage')) {
                        _tuningScope.restore();
                        complete(true);
                        return;
                    }
                    _tuningView.openSession(_panelInstanceId);
                    if (result && result.success) _tuningScope.resume();
                    toast('背包视图恢复失败；保持调制安全态，请重新同步后重试。');
                    complete(false);
                })) {
                    _tuningView.openSession(_panelInstanceId);
                    toast('当前无法恢复背包视图，请稍候重试。');
                    complete(false);
                }
            });
            if (!started) {
                toast('当前无法撤销调制令牌，请稍候重试。');
                complete(false);
            }
            return started;
        }
        var entering = _tuningScope.enter(function(result) {
            if (!result || !result.success) {
                toast('无法载入可调制装备；仍停留在库存视图。');
                complete(false);
                return;
            }
            if (!finishViewSwitch('tuning', preferredSlot)) {
                _tuningScope.leave(function(restored) {
                    if (restored && restored.success) _tuningScope.restore();
                });
                complete(false);
            } else {
                complete(true);
            }
        });
        if (!entering) {
            toast('当前无法切换装备调制，请稍候重试。');
            complete(false);
        }
        return entering;
    }
    function finishViewSwitch(nextView, preferredSlot) {
        exitQuickMode();
        for (var i = 0; i < _dragControllers.length; i++) _dragControllers[i].cancel();
        clearSelection();
        hideTooltip();
        if (nextView === 'tuning') {
            if (!_tuningView.openSession(_panelInstanceId) || !_shell.moveView('R', _tuningView)) {
                _tuningView.closeSession();
                toast('无法建立装备调制会话。');
                return false;
            }
        } else {
            if (!_shell.moveView('R', _rightView)) return false;
        }
        _viewMode = nextView;
        _el.setAttribute('data-workbench-view', _viewMode);
        if (_ports.onViewChanged) _ports.onViewChanged(_viewMode);
        renderInventories();
        refreshControls();
        if (_viewMode === 'tuning') {
            if (preferredSlot && preferredSlot.occupied && preferredSlot.item
                    && preferredSlot.item.itemKind === 'equipment') {
                _tuningView.handleInventorySelection(preferredSlot);
            } else maybeSelectFirstTunable();
        }
        return true;
    }
    function maybeSelectFirstTunable() {
        if (_viewMode !== 'tuning' || !_tuningView || !_state.ready) return false;
        var debug = _tuningView.debugState();
        if (debug.source) return false;
        var snapshot = _coordinator.getWindow('背包');
        var slots = snapshot && snapshot.slots || [];
        for (var i = 0; i < slots.length; i++) {
            if (slots[i].occupied && slots[i].item && slots[i].item.itemKind === 'equipment') {
                return _tuningView.handleInventorySelection(slots[i]);
            }
        }
        return false;
    }
    function loadTuningConversionCandidates(sourceItem, sourceRef, callback) {
        callback = typeof callback === 'function' ? callback : function() {};
        var useName = String(sourceItem && sourceItem.use || '');
        var major = ItemFilter.majorDefinition(sourceItem && sourceItem.majorType).id;
        if (!useName || (major !== 'weapon' && major !== 'armor')) {
            callback({success:false, error:'invalid_equipment'});
            return false;
        }
        return _coordinator.readProjection({
            containerId:'背包', offset:0, limit:50,
            filterKey:major, filterSpec:{branch:'category', major:major, use:useName},
            scope:'equipment'
        }, function(result) {
            if (!result || result.success !== true || !result.snapshot) {
                callback({success:false, error:result && result.error || 'inventory_projection_failed'});
                return;
            }
            var slots = result.snapshot.slots || [], candidates = [];
            for (var i = 0; i < slots.length; i++) {
                var slot = slots[i], item = slot && slot.item;
                if (!slot || !slot.occupied || !item || item.itemKind !== 'equipment'
                        || String(item.use || '') !== useName
                        || (sourceRef && Number(slot.physicalSlot) === Number(sourceRef.slot))) continue;
                candidates.push(slot);
            }
            callback({success:true, candidates:candidates, count:candidates.length});
        });
    }
    function openEquipmentInspector(item, gender, role) {
        if (!_shell || _viewMode !== 'tuning' || !item || (gender !== '男' && gender !== '女')
                || typeof EquipmentInspector === 'undefined' || !EquipmentInspector.open) return false;
        closeEquipmentInspector();
        hideTooltip();
        var controller = null;
        controller = EquipmentInspector.open({
            shell:_shell,
            item:InventoryWorkbenchOwnedView.primitiveProjection(item),
            gender:gender,
            kind:'equipment-inspector',
            kicker:role === 'conversion-target' ? '交换目标检视' : '当前装备检视',
            closeLabel:'返回调制',
            context:'equipment-tuning',
            onClose:function() {
                if (_equipmentInspector === controller) _equipmentInspector = null;
                refreshControls();
            }
        });
        _equipmentInspector = controller;
        refreshControls();
        return !!controller;
    }
    function closeEquipmentInspector() {
        if (!_equipmentInspector) return false;
        var controller = _equipmentInspector;
        _equipmentInspector = null;
        if (controller.close) controller.close();
        else if (controller.destroy) controller.destroy();
        return true;
    }
    function installQuickTransferActions() {
        _quickBarView = InventoryWorkbenchQuickTransfer.createCommandBar({
            document:document,
            rightContainerId:_rightContainerId,
            onMode:setQuickMode,
            onCancel:exitQuickMode,
            onCommit:commitQuickTransfer
        });
        _quickStatusNode = _quickBarView.statusNode;
        _quickDepositButton = _quickBarView.depositButton;
        _quickWithdrawButton = _quickBarView.withdrawButton;
        _quickCancelButton = _quickBarView.cancelButton;
        _quickCommitButton = _quickBarView.commitButton;
        var body = _el && _el.querySelector('.workbench-body');
        if (!body) throw new Error('Inventory quick-transfer bar requires the workbench body');
        body.appendChild(_quickBarView.root);
        updateQuickTransferUI();
    }
    function createInventoryToolbar(containerId, pager) {
        var view = containerId === '背包' ? _backpackView : _rightView;
        var toolbar = InventoryWorkbenchOwnedView.createToolbar({
            document:document, inventoryUI:InventoryUI, containerId:containerId, pager:pager, view:view,
            beforeFilter:function() { exitQuickMode(); clearSelection(); hideTooltip(); },
            setFilter:function(id, key, callback) { return _coordinator.setFilter(id, key, callback); },
            setFilterSpec:function(id, spec, callback) { return _coordinator.setFilterSpec(id, spec, callback); },
            getRequest:function(id) { return _coordinator.getRequest(id); },
            getSnapshot:function(id) { return _coordinator.getWindow(id); },
            render:renderInventories, confirmSort:confirmSort, toast:toast
        });
        if (containerId === '背包') _backpackSortControls = toolbar.controls;
        else _rightSortControls = toolbar.controls;
        return toolbar.root;
    }
    function createInventoryView(containerId, title, layoutMode) {
        var result = InventoryWorkbenchOwnedView.createView({
            inventoryUI:InventoryUI, components:WorkbenchComponents,
            containerId:containerId, title:title, layoutMode:layoutMode,
            densityController:_densityController,
            getSnapshot:function(id) { return _coordinator.getWindow(id); },
            getAuthorityState:function() { return _state; },
            slotRef:slotRef, bindSlot:bindSlot, iconHtml:iconHtml,
            samePhysicalSlot:InventoryRuntime.samePhysicalSlot,
            onInteractionChange:function(id) { reprojectOwnedView(id); }
        });
        _ownedPanes[containerId] = result.pane;
        return result.view;
    }
    function reprojectOwnedView(containerId) {
        var view = containerId === '背包' ? _backpackView : _rightView;
        var nodes = view ? view.root.querySelectorAll('.inventory-slot-card') : [];
        for (var i = 0; i < nodes.length; i++) if (nodes[i].__inventoryInteractionRefresh) nodes[i].__inventoryInteractionRefresh();
    }
    function bindSlot(containerId, node, slot, getInteraction) {
        if (slot.occupied) bindSlotTooltip(node, containerId, slot);
        var itemName = slot.occupied && slot.item
            ? String(slot.item.displayName || '未知物品') : '空槽';
        var reasonNode = InventoryWorkbenchOwnedView.ensureReasonNode(node);
        Workbench.EntityTile.bindActivation(node, {
            itemName:itemName,
            label:node.getAttribute('aria-label') || itemName,
            selected:_broker.isSelectedNode(node),
            inspectable:function() { return getInteraction().inspectable; },
            actionable:function() { return getInteraction().actionable; },
            reason:function() { return getInteraction().reason; },
            reasonNode:reasonNode,
            onBlocked:function() { toast(getInteraction().reason); },
            onActivate:function(event, context) {
                if (consumeDragClick()) return;
                if (_viewMode === 'tuning' && containerId === '背包') {
                    if (_state.busyOwner || _state.refreshRequired) return;
                    if (!slot.occupied || !slot.item || slot.item.itemKind !== 'equipment') {
                        toast('装备调制只接受背包内武器与防具。');
                        return;
                    }
                    clearSelection();
                    _tuningView.handleInventorySelection(slot);
                    return;
                }
                if (handleQuickTransferClick(event, containerId, slot)) return;
                if (_state.busyOwner || _state.refreshRequired) return;
                var view = containerId === '背包' ? _backpackView : _rightView;
                if (_broker.isSelectedNode(node)) clearSelection();
                else if (_broker.debugState().selectedInstanceKey) {
                    _broker.activateSelected(view, {item:slot, node:node}, context.origin);
                } else if (slot.occupied) _broker.select(view, slot, node);
            }
        });
        var discardButton = node.querySelector('.inventory-discard-btn');
        var discardReason = discardButton
            ? InventoryWorkbenchOwnedView.ensureActionReasonNode(discardButton) : null;
        if (discardButton) {
            Workbench.EntityTile.labelAction(discardButton, itemName, '丢弃整槽');
            discardButton.addEventListener('click', function(event) {
                event.stopPropagation();
                var interaction = InventoryWorkbenchOwnedView.authorityInteraction(_state, false);
                if (!interaction.actionable) { toast(interaction.reason); return; }
                confirmDiscard(containerId, slot);
            });
        }
        node.__inventoryInteractionRefresh = function() {
            var interaction = getInteraction();
            InventoryWorkbenchOwnedView.projectNode(Workbench.EntityTile, node, interaction, reasonNode);
            node.classList.toggle('write-locked', !interaction.actionable);
            if (discardButton) InventoryWorkbenchOwnedView.projectNode(Workbench.EntityTile, discardButton,
                InventoryWorkbenchOwnedView.authorityInteraction(_state, false), discardReason);
        };
        node.__inventoryInteractionRefresh();
    }
    function installInteractions() {
        _broker = new Workbench.InteractionBroker({
            onIntent:function(intent) {
                if (!_coordinator.transfer(intent, function(result) {
                    renderInventories();
                    if (result.success) toast(result.operation === 'merge' ? '物品已合并。'
                        : result.operation === 'swap' ? '物品已交换。' : '物品已移动。');
                    else toast(result.reconciled ? '操作失败，库存已刷新。' : errorMessage(result.error));
                })) toast('库存正在处理另一项操作。');
            },
            onReject:function(result) {
                if (result && result.reason === 'same_slot') clearSelection();
            },
            onSelectionChange:function(selection) {
                _tooltipSuppressed = !!selection;
                if (_tooltipSuppressed) hideTooltip();
            }
        });
        _dragControllers = [];
        var views = [_backpackView, _rightView];
        for (var i = 0; i < views.length; i++) installDragForView(views[i]);
    }
    function installDragForView(view) {
        _dragControllers.push(new Workbench.PointerDragController({
            sourceElement:view.renderer.root,
            broker:_broker,
            timeoutMs:_runtimeConfig.dragTimeoutMs || 1400,
            getSource:function(target) {
                if (_viewMode === 'tuning' || _quickTransfer.getMode() || !_state.ready || _state.busyOwner || _state.refreshRequired) return null;
                var hit = view.renderer.itemFromTarget(target);
                if (!hit || !hit.item || !hit.item.occupied) return null;
                return {view:view, item:hit.item, node:hit.node};
            },
            resolveTarget:resolveDropTarget,
            renderGhost:function(source) {
                var item = source.item.item || {};
                var ghost = document.createElement('div');
                ghost.className = 'workbench-drag-ghost inventory-drag-ghost';
                ghost.innerHTML = iconHtml(item.icon || '', 'kshop-row-icon')
                    + '<span>' + escapeHtml(item.displayName || '未知物品') + '</span>';
                return ghost;
            },
            onDragStart:function() { _tooltipSuppressed = true; hideTooltip(); },
            onDragEnd:function() { _tooltipSuppressed = false; }
        }));
    }
    function resolveDropTarget(clientX, clientY) {
        var target = document.elementFromPoint(clientX, clientY);
        var views = [_backpackView, _rightView];
        for (var i = 0; i < views.length; i++) {
            if (!views[i].root.contains(target)) continue;
            var hit = views[i].renderer.itemFromTarget(target);
            if (hit) return {view:views[i], hit:{item:hit.item, node:hit.node}, node:hit.node};
        }
        return null;
    }
    function consumeDragClick() {
        for (var i = 0; i < _dragControllers.length; i++) if (_dragControllers[i].consumeClick()) return true;
        return false;
    }
    function handleQuickTransferClick(event, containerId, slot) {
        return _quickTransfer.acceptClick(event, {
            profile:_profile, viewMode:_viewMode, containerId:containerId, slot:slot
        });
    }
    function setQuickMode(mode) {
        return _quickTransfer.setMode(mode);
    }
    function commitQuickTransfer() { return _quickTransfer.commit(); }
    function exitQuickMode() { return _quickTransfer.exit(); }
    function findCurrentSlot(containerId, physicalSlot) {
        var snapshot = _coordinator.getWindow(containerId);
        var slots = snapshot ? snapshot.slots : [];
        for (var i = 0; i < slots.length; i++) {
            if (Number(slots[i].physicalSlot) === Number(physicalSlot)) return slots[i];
        }
        return null;
    }
    function updateQuickTransferUI() {
        var quick = _quickTransfer.debugState();
        if (_el) {
            if (quick.mode) _el.setAttribute('data-quick-transfer-mode', quick.mode);
            else _el.removeAttribute('data-quick-transfer-mode');
        }
        if (_quickBarView) _quickBarView.update(quick, {visible:_viewMode === 'storage'});
    }
    function applyQuickTransferSlotState() {
        if (!_el) return;
        var nodes = _el.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) {
            nodes[i].classList.remove('quick-transfer-pending', 'quick-transfer-inflight');
        }
        var quick = _quickTransfer.debugState();
        for (var key in quick.entries) {
            var entry = quick.entries[key];
            var view = entry.containerId === '背包' ? _backpackView : _rightView;
            if (!view) continue;
            var node = view.root.querySelector('[data-physical-slot="' + entry.slot + '"]');
            if (!node) continue;
            node.classList.add('quick-transfer-pending');
            if (entry.inflight) node.classList.add('quick-transfer-inflight');
        }
    }
    function renderInventories() {
        if (!_backpackView || !_rightView) return;
        renderView(_backpackView);
        renderView(_rightView);
        if (_pager) _pager.refresh();
        applyQuickTransferSlotState();
        applyTuningSourceSlotState();
    }
    function applyTuningSourceSlotState() {
        if (!_backpackView || typeof EquipmentTuningSourceMarker === 'undefined') return;
        EquipmentTuningSourceMarker.projectInventory(
            _backpackView.root,
            _viewMode === 'tuning' && _tuningView ? _tuningView.debugState() : null
        );
    }
    function renderView(view) {
        var snapshot = _coordinator.getWindow(view.containerId);
        if (_renderedWindows[view.containerId] === snapshot) return false;
        _renderedWindows[view.containerId] = snapshot;
        if (view.ownedInventoryPane) view.ownedInventoryPane.update(
            snapshot, InventoryWorkbenchOwnedView.presentationFor(view.containerId, snapshot));
        return true;
    }
    function refreshControls() {
        if (!_el) return;
        var blocked = !_state.ready || !!_state.busyOwner || !!_state.refreshRequired;
        var slotInteraction = InventoryWorkbenchOwnedView.authorityInteraction(_state, true);
        for (var paneKey in _ownedPanes) _ownedPanes[paneKey].setInteraction(slotInteraction);
        var discardButtons = _el.querySelectorAll('.inventory-discard-btn');
        for (var d = 0; d < discardButtons.length; d++) discardButtons[d].style.display = _viewMode === 'tuning' ? 'none' : '';
        if (_pager) _pager.setDisabled(blocked);
        if (_backpackSortControls) {
            _backpackSortControls.setDisabled(blocked);
            _backpackSortControls.setAuthorityDisabled(blocked || _viewMode === 'tuning');
        }
        if (_rightSortControls) {
            _rightSortControls.setDisabled(blocked);
            var rightSnapshot = _coordinator.getWindow(_rightContainerId);
            _rightSortControls.setAuthorityDisabled(blocked
                || !rightSnapshot || Number(rightSnapshot.accessibleCapacity) <= 0);
        }
        if (_retryButton) _retryButton.style.display = _state.refreshRequired ? '' : 'none';
        var quickBlocked = _viewMode === 'tuning' || !_state.ready || !!_state.refreshRequired
            || (!!_state.busyOwner && _state.busyOwner !== 'inventory.autoTransfer');
        var quickState = _quickTransfer.debugState();
        if (_quickDepositButton) _quickDepositButton.disabled = quickBlocked || quickState.committing;
        if (_quickWithdrawButton) _quickWithdrawButton.disabled = quickBlocked || quickState.committing;
        if (_quickCommitButton) {
            _quickCommitButton.disabled = quickBlocked || !quickState.mode
                || quickState.pending < 1 || quickState.committing;
        }
        if (_ports.refreshHeader) _ports.refreshHeader();
        updateQuickTransferUI();
        if (!_shell) return;
        if (_state.refreshRequired) _shell.setStatus('同步失败', 'warning');
        else if (_state.busyOwner) _shell.setStatus('处理中', 'busy');
        else if (_state.ready) _shell.setStatus('已同步', 'ready');
        else _shell.setStatus('同步中', 'busy');
    }
    function confirmDiscard(containerId, slot) {
        var interaction = InventoryWorkbenchOwnedView.authorityInteraction(_state, false);
        if (_viewMode === 'tuning' || containerId !== '背包' || !slot.occupied
                || !interaction.actionable) { if (interaction.reason) toast(interaction.reason); return; }
        var projection = slot.confirmProjection || slot.item || {};
        _shell.openModal({
            kind:'discard',
            title:'丢弃 ' + String(projection.displayName || '该物品') + '？',
            message:'将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
            detail:'丢弃后无法找回。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'discard', label:'确认丢弃', danger:true, audioCue:'error', onSelect:function() {
                    var current = InventoryWorkbenchOwnedView.authorityInteraction(_state, false);
                    if (!current.actionable) { toast(current.reason); return; }
                    if (!_coordinator.discard(slotRef(containerId, slot), function(result) {
                        renderInventories();
                        toast(result.success ? '物品已丢弃。' : errorMessage(result.error));
                    })) toast('库存正在处理另一项操作。');
                }}
            ]
        });
    }
    function confirmSort(containerId, methodName, label) {
        if (_viewMode === 'tuning' || !_state.ready || _state.busyOwner || _state.refreshRequired) return;
        exitQuickMode();
        methodName = methodName || 'byType';
        label = label || methodName;
        var scope = containerId === '战备箱' ? '当前已解锁区域' : '全部物品';
        _shell.openModal({
            kind:'inventory-sort',
            title:'按' + label + '整理' + containerId + '？',
            message:'将重新排列' + scope + '，并合并可堆叠物品。',
            detail:containerId === '战备箱'
                ? '未解锁的存档保留区不会被读取或移动。' : '原有摆放顺序会改变。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'sort', label:'整理并合并', primary:true, audioCue:'confirm', onSelect:function() {
                    clearSelection();
                    if (!_coordinator.sortAndMerge(containerId, methodName, function(result) {
                        renderInventories();
                        toast(result.success ? containerId + '整理完成。' : containerId + '整理失败，请重试。');
                    })) toast('库存正在处理另一项操作。');
                }}
            ]
        });
    }
    function bindSlotTooltip(node, containerId, slot) {
        var key = containerId + ':' + slot.physicalSlot + ':' + String(slot.slotLease || '');
        var item = slot.item || {};
        PanelTooltip.bindAsyncHover(node, {
            cache: _tooltipCache,
            key: key,
            item: item,
            isSuppressed: function() { return _tooltipSuppressed; },
            renderBasic:function(value) {
                return InventoryWorkbenchOwnedView.basicTooltip(value, escapeHtml);
            },
            renderRich:function(value, data) {
                return InventoryWorkbenchOwnedView.richTooltip(value, data, PanelTooltip);
            },
            fetch: function(_, callback) {
                requestInventory('tooltip', {v:1, source:slotRef(containerId, slot)}, function(response) {
                    if (!isOpen()) return;
                    callback(response);
                });
            }
        });
    }
    function activate(context, requestedView) {
        var generation = ++_openGeneration;
        context = context || {};
        var profileConfig = context.profileConfig, ownerPanel = String(context.ownerPanel || ''),
            panelInstanceId = String(context.panelInstanceId || '');
        if (!profileConfig || (requestedView !== 'storage' && requestedView !== 'tuning')
                || !/^(workbench|crafting|kshop|npcshop)$/.test(ownerPanel)
                || !/^[A-Za-z0-9._~-]{1,128}$/.test(panelInstanceId)) return false;
        _ownerPanel = ownerPanel; _panelInstanceId = panelInstanceId;
        if (requestedView === 'tuning' && !EquipmentTuningRuntime.safeToken(_panelInstanceId)) {
            toast('装备调制缺少 Host 面板实例。');
            return false;
        }
        // battlebox 就是玩家正常装备调制入口，不接受 Host/debug capability 制造无调制分支。
        _tuningOrigin = profileConfig.profile === 'battlebox';
        buildProfileDOM(profileConfig, requestedView, context);
        _quickTransfer.reset();
        _tooltipCache = {};
        if (!_mux.openSession({ownerPanel:_ownerPanel, panelInstanceId:_panelInstanceId})) return false;
        if (_pager) { _pager.detach(); _pager.attach(); }
        clearSelection();
        // 不跨存档记忆剧情容器页码；换到解锁更少的存档时必须从合法首页重新取 lease。
        if (_backpackSortControls) _backpackSortControls.setFilterKey('all');
        if (_rightSortControls) _rightSortControls.setFilterKey('all');
        // Panels 的共享 required-assets 门已保证 Icons manifest 先于任何 panel onOpen 就绪；
        // 这里仅负责 inventory session，避免每个物品面板各自复制一套图标加载竞态。
        openInventory(generation);
        return true;
    }
    function openInventory(generation) {
        // Panels 在 onOpen 返回后才写 active id，因此启动只看本模块 generation；
        // coordinator 的异步回包仍同时校验 generation + isOpen。
        if (generation !== _openGeneration) return;
        _coordinator.open(function(result) {
            if (generation !== _openGeneration || !isOpen()) return;
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
            else maybeSelectFirstTunable();
        });
    }
    function openHelp() {
        if (!_shell) return false;
        return _viewMode === 'tuning' && _tuningView
            ? _tuningView.openHelp(function(spec) { return _shell.openModal(spec); })
            : !!_shell.openModal(InventoryWorkbenchOwnedView.storageHelpSpec(_rightContainerId));
    }
    function cleanup() {
        _openGeneration += 1;
        if (_pager) _pager.detach();
        for (var i = 0; i < _dragControllers.length; i++) _dragControllers[i].cancel();
        clearSelection();
        hideTooltip();
        closeEquipmentInspector();
        _quickTransfer.reset();
        _coordinator.close();
        _mux.closeSession();
        if (_tuningView) { _tuningView.destroy(); _tuningView = null; }
        if (_tuningScope) { _tuningScope.destroy(); _tuningScope = null; }
        disposeInventoryControls();
        disposeOwnedPanes();
        _densityController = null; _renderedWindows = {};
        _ownerPanel = ''; _panelInstanceId = '';
        _ports = {};
        _quickBarView = null;
        _quickDepositButton = null; _quickWithdrawButton = null;
        _quickCommitButton = null; _quickCancelButton = null; _quickStatusNode = null;
        _el = null;
        _shell = null;
    }
    function disposeInventoryControls() {
        if (_backpackSortControls && typeof _backpackSortControls.destroy === 'function') _backpackSortControls.destroy();
        if (_rightSortControls && typeof _rightSortControls.destroy === 'function') _rightSortControls.destroy();
        _backpackSortControls = null;
        _rightSortControls = null;
    }
    function disposeOwnedPanes() {
        for (var key in _ownedPanes) _ownedPanes[key].destroy();
        _ownedPanes = {};
    }
    function prepareExit(reason, callback) {
        callback = typeof callback === 'function' ? callback : function() {};
        if (_state.busyOwner || _quickTransfer.isBusy()) {
            toast(_viewMode === 'tuning' ? '调制写入与对账尚未完成，请稍候关闭。' : '库存写入尚未完成，请稍候关闭。');
            callback(false, 'blocked');
            return false;
        }
        if (_viewMode === 'tuning' && _tuningView && !_tuningView.canClose()) {
            toast('调制请求或对账尚未完成，请稍候关闭。');
            callback(false, 'blocked');
            return false;
        }
        if (reason === 'escape' && exitQuickMode()) {
            callback(false, 'consumed');
            return true;
        }
        exitQuickMode();
        if (_viewMode === 'tuning' && _tuningView) {
            var started = _tuningView.detachSession(function(detached) {
                if (detached) callback(true, 'ready');
                else {
                    toast('未能撤销调制令牌，面板保持打开。');
                    callback(false, 'blocked');
                }
            });
            if (!started) {
                toast('当前无法撤销调制令牌，请稍候重试。');
                callback(false, 'blocked');
            }
            return started;
        }
        callback(true, 'ready');
        return true;
    }
    function prepareLeave(nextView, callback) {
        if (nextView !== 'build') return false;
        return prepareExit('switch', callback);
    }
    function retryRefresh() {
        if (_tuningView && _tuningView.retryInventoryRefresh()) return;
        if (!_coordinator.retryRefresh(function(result) {
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
        })) toast('当前无法重试同步。');
    }
    function beginExternalWrite(owner) {
        return _coordinator.beginExternalWrite(owner);
    }
    function completeExternalWrite(operation, snapshots, callback, needsRefresh) {
        return snapshots ? _coordinator.completeExternalSnapshots(operation, snapshots, callback)
            : _coordinator.completeExternalWrite(operation, !!needsRefresh, callback);
    }
    function refreshExternalInventory(callback) {
        var state = _coordinator.debugState();
        if (state.busyOwner) return false;
        if (!state.refreshRequired) {
            if (callback) callback({success:true, refreshed:false}); return state.opened && state.ready;
        }
        return _coordinator.retryRefresh(function(result) {
            renderInventories(); if (callback) callback(result);
        });
    }
    function requestInventory(cmd, payload, callback) {
        return _mux.request(cmd, payload || {}, {sendError:'not_sent'}, callback);
    }
    function slotRef(containerId, slot) {
        return {
            containerId:containerId,
            slot:Number(slot.physicalSlot),
            expectedLease:String(slot.slotLease),
            occupied:!!slot.occupied,
            item:slot.item || null
        };
    }
    function shortcutsEnabled(event) {
        if (!isOpen() || (_shell && _shell.hasModal())) return false;
        var target = event.target;
        return !(target && target.closest && target.closest('input,textarea,select,[contenteditable="true"],[data-browser-native]'));
    }
    function clearSelection() { if (_broker) _broker.clearSelection(); }
    function hideTooltip() { if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide(); }
    function isOpen() { return _ports.isPanelActive ? _ports.isPanelActive() : false; }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function iconHtml(iconName, cls) {
        return InventoryWorkbenchOwnedView.iconHtml(iconName, cls, typeof Icons === 'undefined' ? null : Icons);
    }
    function errorMessage(error) { return InventoryWorkbenchOwnedView.errorMessage(error); }

    return {
        activate:activate,
        deactivate:cleanup,
        switchView:switchView,
        consumeEscape:function() {
            if (_viewMode === 'tuning' && _tuningView
                    && typeof _tuningView.consumeEscape === 'function'
                    && _tuningView.consumeEscape()) return true;
            return exitQuickMode();
        },
        prepareLeave:prepareLeave,
        prepareClose:prepareExit,
        beginExternalWrite:beginExternalWrite,
        completeExternalWrite:completeExternalWrite,
        refreshExternalInventory:refreshExternalInventory,
        openHelp:openHelp,
        getHeaderState:function() {
            var tuning = _tuningView ? _tuningView.getInteractionProjection() : null;
            return {
                view:_viewMode,
                disabled:!!_state.busyOwner || !!_state.refreshRequired
                    || _viewMode === 'tuning' && tuning && tuning.blocked,
                reason:_viewMode === 'tuning' && tuning && tuning.reason
                    ? tuning.reason
                    : _state.refreshRequired ? '库存同步失败，请先重试同步。'
                        : _state.busyOwner ? '库存操作尚未完成，请稍候。' : ''
            };
        },
        getView:function() { return _viewMode; },
        debugState:function() {
            var right = _coordinator.getWindow(_rightContainerId);
            return {
                profile:_profile, view:_viewMode, hostOwner:_ownerPanel, panelInstanceId:_panelInstanceId,
                rightContainerId:_rightContainerId,
                coordinator:_coordinator.debugState(),
                rightAccessibleCapacity:right ? Number(right.accessibleCapacity) : null,
                battleboxAccessibleCapacity:_profile === 'battlebox' && right ? Number(right.accessibleCapacity) : null,
                tuning:_tuningView ? _tuningView.debugState() : null,
                tuningScope:_tuningScope ? _tuningScope.debugState() : null,
                equipmentInspector:_equipmentInspector && _equipmentInspector.debugState
                    ? _equipmentInspector.debugState() : null,
                modConfirmationMode:typeof EquipmentTuningConfirmation !== 'undefined'
                    && EquipmentTuningConfirmation.shared
                    ? EquipmentTuningConfirmation.shared.read() : 'safe',
                page:_pager ? _pager.getState() : null,
                quickTransfer:_quickTransfer.debugState()
            };
        }
    };
})();
