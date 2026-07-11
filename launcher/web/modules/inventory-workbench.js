/**
 * Standalone owned-inventory workbench（背包—仓库 / 背包—战备箱）。
 *
 * This panel never enters the shop lifecycle. InventoryPanelService remains the
 * authority; the Web layer only renders leased windows and emits operation intents.
 */
var InventoryWorkbench = (function() {
    'use strict';

    var _el, _shellEl, _shell, _backpackView, _rightView, _pager, _retryButton;
    var _backpackSortControls, _rightSortControls;
    var _broker, _dragControllers = [], _scaleHandle = null;
    var _state = {opened:false, ready:false, busyOwner:null, refreshRequired:false};
    var _tooltipCache = {}, _tooltipHovering = null, _tooltipSuppressed = false;
    var _openGeneration = 0;
    var _profile = 'battlebox';
    var _rightContainerId = '战备箱';
    var _rightLimit = 40;
    var _runtimeConfig = (typeof window !== 'undefined' && window.__INVENTORY_WORKBENCH_CONFIG__) || {};
    var _mux = new KShopRequestMux({
        send: function(message) { Bridge.send(message); },
        timeoutMs: _runtimeConfig.requestTimeoutMs,
        sessionNonce: _runtimeConfig.sessionNonce,
        onProtocolError: function(message) {
            if (typeof console !== 'undefined' && console.warn) console.warn(message);
        }
    });
    var _coordinator = new InventoryRuntime.InventoryCoordinator({
        request: requestInventory,
        requests: [
            {containerId:'背包', offset:0, limit:50},
            {containerId:'战备箱', offset:0, limit:40}
        ],
        onStateChange: function(state) {
            _state = state;
            renderInventories();
            refreshControls();
        }
    });

    Panels.register('workbench', {
        create: createDOM,
        onOpen: onOpen,
        onClose: cleanup,
        onRequestClose: closePanel,
        onForceClose: function() { cleanup(); toast('连接断开，物品工作台已关闭'); }
    });

    function createDOM() {
        _shellEl = document.createElement('div');
        _shellEl.className = 'panel-scale-shell kshop-scale-shell inventory-workbench-scale-shell';
        return _shellEl;
    }

    function resolveProfile(initData) {
        var profile = initData && initData.profile === 'warehouse' ? 'warehouse' : 'battlebox';
        return profile === 'warehouse'
            ? {profile:'warehouse', title:'仓库', rightContainerId:'仓库', rightLimit:50, rightCapacity:1200, pageColumns:6}
            : {profile:'battlebox', title:'战备箱', rightContainerId:'战备箱', rightLimit:40, rightCapacity:0, pageColumns:3};
    }

    function buildProfileDOM(config) {
        if (typeof Workbench === 'undefined') throw new Error('Workbench runtime is required');
        if (_pager) _pager.detach();
        for (var oldDrag = 0; oldDrag < _dragControllers.length; oldDrag++) _dragControllers[oldDrag].cancel();
        if (_broker) _broker.clearSelection();
        if (_shell) _shell.destroy();
        while (_shellEl.firstChild) _shellEl.removeChild(_shellEl.firstChild);
        _shell = null;
        _el = null;
        _backpackView = null;
        _rightView = null;
        _pager = null;
        _backpackSortControls = null;
        _rightSortControls = null;
        _broker = null;
        _dragControllers = [];

        _profile = config.profile;
        _rightContainerId = config.rightContainerId;
        _rightLimit = config.rightLimit;
        if (!_coordinator.configureRequests([
            {containerId:'背包', offset:0, limit:50, filterKey:'all'},
            {containerId:_rightContainerId, offset:0, limit:_rightLimit, filterKey:'all'}
        ])) throw new Error('Inventory workbench request profile rejected: ' + _profile);

        _shell = new Workbench.DualPaneShell({
            title:config.title, status:'同步中', leftLabel:'背包', rightLabel:config.title
        });
        _el = _shell.getRoot();
        _el.classList.add('kshop-workbench', 'inventory-workbench-panel');
        _el.setAttribute('data-workbench-skin', 'inventory');
        _el.setAttribute('data-inventory-profile', _profile);

        _retryButton = document.createElement('button');
        _retryButton.type = 'button';
        _retryButton.className = 'workbench-mode-btn warning';
        _retryButton.textContent = '重试同步';
        _retryButton.style.display = 'none';
        _retryButton.addEventListener('click', retryRefresh);
        _shell.addHeaderAction(_retryButton);

        var closeButton = document.createElement('button');
        closeButton.type = 'button';
        closeButton.className = 'workbench-close-btn';
        closeButton.textContent = '×';
        closeButton.setAttribute('aria-label', '关闭' + config.title);
        closeButton.setAttribute('data-audio-cue', 'cancel');
        closeButton.addEventListener('click', closePanel);
        _shell.addHeaderAction(closeButton);

        _backpackView = createInventoryView('背包', '背包');
        _rightView = createInventoryView(_rightContainerId, config.title);
        _backpackView.displaySortMethod = 'physicalSlot';
        _rightView.displaySortMethod = 'physicalSlot';
        _pager = new InventoryUI.InventoryWindowPager({
            containerId:_rightContainerId, containerLabel:config.title, columns:config.pageColumns,
            defaultOffset:0, defaultLimit:_rightLimit, defaultCapacity:config.rightCapacity,
            getSnapshot:function() { return _coordinator.getWindow(_rightContainerId); },
            getRequest:function() { return _coordinator.getRequest(_rightContainerId); },
            shortcutEnabled:shortcutsEnabled,
            onBeforeChange:function() { clearSelection(); hideTooltip(); },
            onRequest:function(offset, limit, callback) {
                return _coordinator.setWindow(_rightContainerId, offset, limit, callback);
            },
            onResult:function(result) {
                renderInventories();
                if (!result || !result.success) toast(config.title + '翻页失败，请重试。');
            }
        });
        _backpackView.chrome.setToolbar(createInventoryToolbar('背包', null));
        _rightView.chrome.setToolbar(createInventoryToolbar(_rightContainerId, _pager));

        if (!_shell.mountInitial(_backpackView, _rightView)) {
            throw new Error('Inventory workbench initial view configuration rejected');
        }
        installInteractions();
        _shellEl.appendChild(_el);
    }

    function createInventoryToolbar(containerId, pager) {
        var toolbar = document.createElement('div');
        toolbar.className = 'inventory-warehouse-toolbar inventory-container-toolbar'
            + (pager ? ' inventory-battlebox-toolbar' : ' inventory-no-pager');
        var view = containerId === '背包' ? _backpackView : _rightView;
        var controls = new InventoryUI.InventorySortControls({
            displayOptions:InventoryUI.displaySortOptions(),
            displayLabel:'查看',
            filterOptions:InventoryUI.categoryFilterOptions(),
            filterLabel:'',
            filterAriaLabel:containerId + '分类筛选',
            authorityOptions:InventoryUI.authoritySortOptions(),
            authorityLabel:'',
            authorityAriaLabel:containerId + '整理方式',
            commitLabel:'整理' + containerId,
            onDisplayChange:function(methodName) {
                view.displaySortMethod = methodName;
                clearSelection();
                renderInventories();
            },
            onFilterChange:function(filterKey) {
                clearSelection();
                hideTooltip();
                if (!_coordinator.setFilter(containerId, filterKey, function(result) {
                    renderInventories();
                    if (!result.success) {
                        var request = _coordinator.getRequest(containerId);
                        controls.setFilterKey(request ? request.filterKey : 'all');
                        toast(containerId + '筛选失败，请重试。');
                    }
                })) {
                    var request = _coordinator.getRequest(containerId);
                    controls.setFilterKey(request ? request.filterKey : 'all');
                }
            },
            onAuthorityCommit:function(methodName, label) {
                confirmSort(containerId, methodName, label);
            }
        });
        if (containerId === '背包') _backpackSortControls = controls;
        else _rightSortControls = controls;
        if (pager) toolbar.appendChild(pager.root);
        toolbar.appendChild(controls.root);
        return toolbar;
    }

    function createInventoryView(containerId, title) {
        var adapter = new Workbench.ContainerViewAdapter({
            instanceKey:'inventory:' + containerId,
            itemModel:'owned',
            getItems:function() {
                var snapshot = _coordinator.getWindow(containerId);
                return snapshot ? snapshot.slots : [];
            },
            keyOf:function(slot) { return slot.physicalSlot; },
            renderItem:function(slot) {
                return InventoryUI.renderOwnedSlot(containerId, slot, {
                    iconHtml:iconHtml,
                    allowDiscard:containerId === '背包'
                });
            },
            bindItem:function(node, slot) { bindSlot(containerId, node, slot); },
            exportOffer:function(slot) {
                if (!slot || !slot.occupied || !_state.ready || _state.busyOwner || _state.refreshRequired) return null;
                return {
                    subjectKind:'ownedSlot',
                    sourceRef:slotRef(containerId, slot),
                    offeredOperations:['inventory.transfer']
                };
            },
            probeAccept:function(offer, hit) {
                var target = hit && hit.item;
                if (!offer || offer.subjectKind !== 'ownedSlot' || !target) return {accepted:false, reason:'unsupported'};
                var targetRef = slotRef(containerId, target);
                if (InventoryRuntime.samePhysicalSlot(offer.sourceRef, targetRef)) return {accepted:false, reason:'same_slot'};
                return {
                    accepted:true,
                    operationId:'inventory.transfer',
                    targetRef:targetRef,
                    hint:target.occupied ? 'merge-or-swap' : 'move'
                };
            }
        });
        var view = new Workbench.GridContainerView({
            adapter:adapter,
            title:title,
            meta:'同步中',
            className:'inventory-owned-view inventory-owned-' + (containerId === '背包' ? 'backpack' : 'warehouse')
                + (containerId === '战备箱' ? ' inventory-owned-battlebox' : ''),
            gridClassName:'inventory-owned-grid',
            emptyText:'正在同步库存…',
            allowedSlots:containerId === '背包' ? ['L'] : ['R']
        });
        view.containerId = containerId;
        return view;
    }

    function bindSlot(containerId, node, slot) {
        if (slot.occupied) {
            node.addEventListener('mouseenter', function(event) { showTooltip(event, containerId, slot); });
            node.addEventListener('mouseleave', hideTooltip);
            node.addEventListener('mousemove', function(event) {
                if (!_tooltipSuppressed) PanelTooltip.followMouse(event);
            });
        }
        node.addEventListener('click', function(event) {
            if (consumeDragClick()) return;
            if (event.target && event.target.closest && event.target.closest('.inventory-discard-btn')) return;
            var view = containerId === '背包' ? _backpackView : _rightView;
            if (_broker.debugState().selectedInstanceKey) _broker.activateSelected(view, {item:slot, node:node}, 'click');
            else if (slot.occupied) _broker.select(view, slot, node);
        });
        var discardButton = node.querySelector('.inventory-discard-btn');
        if (discardButton) discardButton.addEventListener('click', function(event) {
            event.stopPropagation();
            confirmDiscard(containerId, slot);
        });
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
                if (!_state.ready || _state.busyOwner || _state.refreshRequired) return null;
                var hit = view.renderer.itemFromTarget(target);
                if (!hit || !hit.item || !hit.item.occupied) return null;
                return {view:view, item:hit.item, node:hit.node};
            },
            resolveTarget:resolveDropTarget,
            renderGhost:function(source) {
                var item = source.item.item || {};
                var ghost = document.createElement('div');
                ghost.className = 'workbench-drag-ghost inventory-drag-ghost';
                ghost.innerHTML = iconHtml(item.icon || item.name, 'kshop-row-icon')
                    + '<span>' + escapeHtml(item.displayName || item.name || '物品') + '</span>';
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

    function renderInventories() {
        if (!_backpackView || !_rightView) return;
        renderView(_backpackView);
        renderView(_rightView);
        if (_pager) _pager.refresh();
    }

    function renderView(view) {
        var snapshot = _coordinator.getWindow(view.containerId);
        var slots = snapshot ? snapshot.slots : [];
        var filtered = snapshot && String(snapshot.filterKey || 'all') !== 'all';
        if (view.displaySortMethod && typeof InventoryRuntime.displaySortSlots === 'function') {
            slots = InventoryRuntime.displaySortSlots(slots, view.displaySortMethod);
        }
        if (view.containerId === '战备箱') {
            view.renderer.options.emptyText = snapshot && Number(snapshot.accessibleCapacity) <= 0
                ? '战备箱尚未解锁' : filtered ? '当前分类暂无物品' : '本页暂无物品';
        } else {
            view.renderer.options.emptyText = filtered ? '当前分类暂无物品' : '本页暂无物品';
        }
        view.renderer.render(slots);
        if (!snapshot) view.chrome.setMeta('同步中');
        else if (view.containerId === '战备箱' && Number(snapshot.accessibleCapacity) <= 0) view.chrome.setMeta('未解锁');
        else if (view.containerId === '背包') view.chrome.setMeta(countOccupied(slots) + ' / ' + Number(snapshot.accessibleCapacity || snapshot.capacity));
        else view.chrome.setMeta('');
    }

    function refreshControls() {
        if (!_el) return;
        var blocked = !_state.ready || !!_state.busyOwner || !!_state.refreshRequired;
        var nodes = _el.querySelectorAll('.inventory-slot-card');
        for (var i = 0; i < nodes.length; i++) nodes[i].classList.toggle('write-locked', blocked);
        if (_pager) _pager.setDisabled(blocked);
        if (_backpackSortControls) _backpackSortControls.setDisabled(blocked);
        if (_rightSortControls) {
            _rightSortControls.setDisabled(blocked);
            var rightSnapshot = _coordinator.getWindow(_rightContainerId);
            _rightSortControls.setAuthorityDisabled(blocked
                || !rightSnapshot || Number(rightSnapshot.accessibleCapacity) <= 0);
        }
        if (_retryButton) _retryButton.style.display = _state.refreshRequired ? '' : 'none';
        if (!_shell) return;
        if (_state.refreshRequired) _shell.setStatus('同步失败', 'warning');
        else if (_state.busyOwner) _shell.setStatus('处理中', 'busy');
        else if (_state.ready) _shell.setStatus('已同步', 'ready');
        else _shell.setStatus('同步中', 'busy');
    }

    function confirmDiscard(containerId, slot) {
        if (containerId !== '背包' || !slot.occupied || !_state.ready) return;
        var projection = slot.confirmProjection || slot.item || {};
        _shell.openModal({
            kind:'discard',
            title:'丢弃 ' + String(projection.displayName || '该物品') + '？',
            message:'将丢弃整组，共 ' + Number(projection.quantity || 1) + ' 件。',
            detail:'丢弃后无法找回。',
            actions:[
                {id:'cancel', label:'取消', audioCue:'cancel'},
                {id:'discard', label:'确认丢弃', danger:true, audioCue:'error', onSelect:function() {
                    if (!_coordinator.discard(slotRef(containerId, slot), function(result) {
                        renderInventories();
                        toast(result.success ? '物品已丢弃。' : errorMessage(result.error));
                    })) toast('库存正在处理另一项操作。');
                }}
            ]
        });
    }

    function confirmSort(containerId, methodName, label) {
        if (!_state.ready || _state.busyOwner || _state.refreshRequired) return;
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

    function showTooltip(event, containerId, slot) {
        if (_tooltipSuppressed || !slot || !slot.occupied) return;
        var key = containerId + ':' + slot.physicalSlot + ':' + String(slot.slotLease || '');
        _tooltipHovering = key;
        PanelTooltip.showAtMouse(_tooltipCache[key]
            ? buildRichTooltip(slot.item || {}, _tooltipCache[key])
            : buildBasicTooltip(slot.item || {}), event);
        if (_tooltipCache[key]) return;
        requestInventory('tooltip', {v:1, source:slotRef(containerId, slot)}, function(response) {
            if (!isOpen() || !response || response.success !== true) return;
            _tooltipCache[key] = response;
            if (_tooltipHovering === key && !_tooltipSuppressed && PanelTooltip.isVisible()) {
                PanelTooltip.updateContent(buildRichTooltip(slot.item || {}, response));
            }
        });
    }

    function buildBasicTooltip(item) {
        var type = item.majorType || item.use || item.itemKind || '物品';
        return '<div class="kshop-tt-header"><b>' + escapeHtml(item.displayName || item.name || '未知物品') + '</b></div>'
            + '<div class="kshop-tt-divider"></div><span class="kshop-tt-dim">类型</span> ' + escapeHtml(type) + '<br>'
            + (Number(item.quantity) > 1 ? '<span class="kshop-tt-dim">数量</span> ' + Number(item.quantity) + '<br>' : '')
            + (Number(item.enhancementLevel) > 0 ? '<span class="kshop-tt-dim">强化</span> +' + Number(item.enhancementLevel) + '<br>' : '')
            + '<div class="kshop-tt-loading">加载中…</div>';
    }

    function buildRichTooltip(item, data) {
        var iconKey = data.iconName || item.icon || item.name;
        return PanelTooltip.buildItemRichHtml({
            iconHtml:PanelTooltip.dynamicIconHtml(iconKey),
            iconUrl:PanelTooltip.staticIconUrl(iconKey),
            introHTML:data.introHTML || '',
            descHTML:data.descHTML || '',
            rootClass:'kshop-tt-rich-context inventory-owned-tt-context',
            layoutType:PanelTooltip.inferLayoutType(data.itemType || item.majorType || item.use)
        });
    }

    function onOpen(el, initData) {
        var generation = ++_openGeneration;
        buildProfileDOM(resolveProfile(initData));
        if (_scaleHandle) _scaleHandle.detach();
        _scaleHandle = typeof PanelScale !== 'undefined' ? PanelScale.attach(_shellEl, 1024, 576) : null;
        _tooltipCache = {};
        _mux.openSession();
        if (_pager) { _pager.detach(); _pager.attach(); }
        clearSelection();
        // 不跨存档记忆剧情容器页码；换到解锁更少的存档时必须从合法首页重新取 lease。
        _coordinator.resetWindow('背包', 0, 50, 'all');
        _coordinator.resetWindow(_rightContainerId, 0, _rightLimit, 'all');
        if (_backpackSortControls) _backpackSortControls.setFilterKey('all');
        if (_rightSortControls) _rightSortControls.setFilterKey('all');
        // Panels 的共享 required-assets 门已保证 Icons manifest 先于任何 panel onOpen 就绪；
        // 这里仅负责 inventory session，避免每个物品面板各自复制一套图标加载竞态。
        openInventory(generation);
    }

    function openInventory(generation) {
        // Panels 在 onOpen 返回后才写 active id，因此启动只看本模块 generation；
        // coordinator 的异步回包仍同时校验 generation + isOpen。
        if (generation !== _openGeneration) return;
        _coordinator.open(function(result) {
            if (generation !== _openGeneration || !isOpen()) return;
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
        });
    }

    function cleanup() {
        _openGeneration += 1;
        if (_scaleHandle) { _scaleHandle.detach(); _scaleHandle = null; }
        if (_pager) _pager.detach();
        for (var i = 0; i < _dragControllers.length; i++) _dragControllers[i].cancel();
        clearSelection();
        hideTooltip();
        if (_shell) _shell.closeModal();
        _coordinator.close();
        _mux.closeSession();
    }

    function closePanel() {
        if (_shell && _shell.hasModal()) { _shell.closeModal(); return; }
        Panels.close();
        Bridge.send({type:'panel', cmd:'close', panel:'workbench'});
    }

    function retryRefresh() {
        if (!_coordinator.retryRefresh(function(result) {
            renderInventories();
            if (!result.success) toast(errorMessage(result.error));
        })) toast('当前无法重试同步。');
    }

    function requestInventory(cmd, payload, callback) {
        return _mux.request('inventory', cmd, {panel:'workbench', payload:payload || {}}, callback);
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

    function countOccupied(slots) {
        var count = 0;
        for (var i = 0; i < slots.length; i++) if (slots[i].occupied) count++;
        return count;
    }

    function clearSelection() { if (_broker) _broker.clearSelection(); }
    function hideTooltip() { _tooltipHovering = null; if (typeof PanelTooltip !== 'undefined') PanelTooltip.hide(); }
    function isOpen() { return Panels.getActive ? Panels.getActive() === 'workbench' : Panels.isOpen(); }
    function toast(message) { if (typeof Toast !== 'undefined') Toast.add(message); }
    function escapeHtml(value) { return String(value == null ? '' : value).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;'); }
    function iconHtml(iconName, cls) {
        var icon = typeof Icons !== 'undefined' && Icons.html
            ? Icons.html(iconName, cls || 'kshop-icon', ' onerror="this.style.display=\'none\'"') : '';
        return icon || '<div class="' + (cls || 'kshop-icon') + ' kshop-icon-placeholder"></div>';
    }
    function errorMessage(error) {
        if (error === 'slot_locked') return '该容器槽位尚未解锁。';
        if (error === 'stale_state') return '库存已经变化，请重试。';
        if (error === 'client_timeout' || error === 'timeout') return '库存响应超时，请重试。';
        if (error === 'inventory_refresh_failed') return '库存同步失败，请重试。';
        return '操作失败，请重试。';
    }

    Bridge.on('panel_resp', function(data) { _mux.handleResponse(data); });

    return {
        debugState:function() {
            var right = _coordinator.getWindow(_rightContainerId);
            return {
                profile:_profile,
                rightContainerId:_rightContainerId,
                coordinator:_coordinator.debugState(),
                rightAccessibleCapacity:right ? Number(right.accessibleCapacity) : null,
                battleboxAccessibleCapacity:_profile === 'battlebox' && right ? Number(right.accessibleCapacity) : null,
                page:_pager ? _pager.getState() : null
            };
        }
    };
})();
