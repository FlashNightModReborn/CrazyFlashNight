/**
 * Panels — 通用面板生命周期管理器
 *
 * 面板注册（同步）: Panels.register('kshop', { create, onOpen, onRequestClose })
 * 面板注册（懒加载）: Panels.registerLazy('kshop', ['modules/kshop.js'], function() {
 *     // 在该回调里调用 Panels.register('kshop', {...}) 注入实际 spec
 * });
 * C# 侧通过 Bridge 发送 panel_cmd / panel_esc 消息控制开关
 * 遮罩点击 / ESC 均走 onRequestClose（由面板自己决定是否真正关闭）
 */
var Panels = (function() {
    'use strict';

    var _registry = {};
    // Dev/runtime integrations that must attach before a lazy panel is first opened can
    // decorate its registration without forcing the panel into the boot bundle.  A decorator
    // is applied both to an already-resolved spec and to future register() calls.
    var _registrationDecorators = {};
    var _active = null;
    var _activePanelInstanceId = null;
    var _container, _backdrop, _content;
    // 所有生产 Panel 共用的最低资源门：物品 / 装备 / 奖励图标 manifest。
    // icons.js 本身是 boot 脚本，但 manifest 是异步加载；若不在生命周期层拦住首次 open，
    // 新迁移面板很容易在 Icons.html() 仍为空时完成第一次渲染。
    var _requiredAssetsState = 'idle';
    var _requiredAssetsQueue = [];
    // _pendingOpen：required-assets / lazy 加载期间记录最新 open 请求；中途若被 close/切面板，
    //   这里被覆盖或清空。完成时按当前值决定是否真正打开，避免已关闭面板被异步拉起。
    var _pendingOpen = null;

    function readPanelInstanceId(initData) {
        var value = initData && initData.panelInstanceId;
        return typeof value === 'string' && value ? value : '';
    }

    function panelCloseMessage(id, initData, reason) {
        var closeMessage = {type:'panel', cmd:'close', panel:id};
        if (id === 'skills') {
            closeMessage.panelInstanceId = readPanelInstanceId(initData);
            return closeMessage;
        }
        if (id === 'loot' || id === 'workbench') {
            closeMessage.reason = reason || 'lazy_cancel';
            closeMessage.panelInstanceId = readPanelInstanceId(initData);
        }
        return closeMessage;
    }

    function hostOwnsPanelMount(id, initData) {
        return id === 'loot' || id === 'workbench' || id === 'skills'
            || id === 'crafting' || id === 'kshop';
    }

    function safeBridgeSend(message, context) {
        if (typeof Bridge === 'undefined' || !Bridge || !Bridge.send) return false;
        try {
            return Bridge.send(message);
        } catch (e) {
            console.error('[Panels] Bridge.send threw during ' + context + ':', e);
            return false;
        }
    }

    function safeCleanupCallback(panel, callbackName, context) {
        if (!panel || typeof panel[callbackName] !== 'function') return;
        try {
            panel[callbackName]();
        } catch (e) {
            console.error('[Panels] ' + callbackName + ' threw during ' + context + ':', e);
        }
    }

    function sendMountFailureClose(id, initData, reason) {
        if (!hostOwnsPanelMount(id, initData)) return;
        safeBridgeSend(
            panelCloseMessage(id, initData, reason || 'mount_failed'),
            'mount failure close for ' + id);
    }

    function applyRegistrationDecorators(id, opts) {
        var decorators = _registrationDecorators[id];
        if (!decorators || !decorators.length) return opts;
        var resolved = opts;
        for (var i = 0; i < decorators.length; i++) {
            var next = decorators[i](resolved);
            if (next) resolved = next;
        }
        return resolved;
    }

    function register(id, opts) {
        _registry[id] = applyRegistrationDecorators(id, opts);
    }

    function installRegistrationDecorator(id, decorator) {
        if (typeof id !== 'string' || !id || typeof decorator !== 'function') return false;
        if (!_registrationDecorators[id]) _registrationDecorators[id] = [];
        if (_registrationDecorators[id].indexOf(decorator) >= 0) return true;
        _registrationDecorators[id].push(decorator);
        var existing = _registry[id];
        if (existing && !existing._lazy) _registry[id] = decorator(existing) || existing;
        return true;
    }

    function cancelPendingOpen(notifyHost, reason) {
        if (!_pendingOpen) return null;
        var pending = _pendingOpen;
        _pendingOpen = null;
        if (notifyHost) {
            safeBridgeSend(
                panelCloseMessage(pending.id, pending.initData, reason),
                'pending open cancel for ' + pending.id);
        }
        return pending;
    }

    function init() {
        _container = document.getElementById('panel-container');
        _backdrop  = document.getElementById('panel-backdrop');
        _content   = document.getElementById('panel-content');
        _backdrop.addEventListener('click', function() { triggerRequestClose('backdrop'); });
        // 尽早预热；open() 仍会等待该门完成，因此即使 C# 紧接 ready 下发 open 也不会抢跑。
        ensureRequiredAssets();
    }

    function finishRequiredAssets() {
        if (_requiredAssetsState === 'ready') return;
        _requiredAssetsState = 'ready';
        var queue = _requiredAssetsQueue.slice();
        _requiredAssetsQueue = [];
        for (var i = 0; i < queue.length; i++) {
            try { queue[i](); }
            catch (e) { console.error('[Panels] required asset callback failed:', e); }
        }
    }

    function ensureRequiredAssets(callback) {
        if (_requiredAssetsState === 'ready') {
            if (typeof callback === 'function') callback();
            return;
        }
        if (typeof callback === 'function') _requiredAssetsQueue.push(callback);
        if (_requiredAssetsState === 'loading') return;
        _requiredAssetsState = 'loading';
        if (typeof Icons === 'undefined' || !Icons || typeof Icons.load !== 'function') {
            // 不把整个 overlay 永久锁死；这是 boot 清单错误，记录后让面板以缺图 fallback 继续。
            console.error('[Panels] required Icons loader is unavailable');
            finishRequiredAssets();
            return;
        }
        try {
            // Icons.load 在成功和失败（空 map fallback）两条路径都会回调。
            Icons.load(finishRequiredAssets);
        } catch (e) {
            console.error('[Panels] required Icons manifest load threw:', e);
            finishRequiredAssets();
        }
    }

    function _doOpen(id, initData) {
        if (_active === id) {
            _activePanelInstanceId = readPanelInstanceId(initData);
            var activePanel = _registry[id];
            var rebindAccepted = true;
            try {
                if (activePanel && activePanel.onRebind) {
                    rebindAccepted = activePanel.onRebind(
                        activePanel._el, initData) !== false;
                }
            } catch (e) {
                rebindAccepted = false;
                console.error('[Panels] panel rebind threw for ' + id + ':', e);
            }
            if (!rebindAccepted) {
                rejectPanelMount(id, activePanel, initData);
            }
            return;
        }
        if (_active) close();
        var panel = _registry[id];
        if (!panel) {
            console.error('[Panels] panel not registered: ' + id);
            rejectPanelMount(id, null, initData);
            return;
        }
        if (!panel._el) {
            try {
                var created = panel.create(_content);
                // Production DOM must be an Element. Test adapters may omit nodeType, but
                // still have to expose the Element-style display surface used below.
                if (!created || !created.style
                        || (created.nodeType != null && Number(created.nodeType) !== 1)) {
                    throw new Error('panel create returned a non-Element');
                }
                _content.appendChild(created);
                panel._el = created;
            } catch (e) {
                console.error('[Panels] panel create threw for ' + id + ':', e);
                rejectPanelMount(id, panel, initData);
                return;
            }
        }
        panel._el.style.display = '';
        _container.style.display = '';
        _container.setAttribute('data-panel', id);
        _content.setAttribute('data-panel', id);
        var mountAccepted = true;
        try {
            if (panel.onOpen) {
                mountAccepted = panel.onOpen(panel._el, initData) !== false;
            }
        } catch (e) {
            mountAccepted = false;
            console.error('[Panels] panel mount threw for ' + id + ':', e);
        }
        if (!mountAccepted) {
            rejectPanelMount(id, panel, initData);
            return;
        }
        _active = id;
        _activePanelInstanceId = readPanelInstanceId(initData);
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    function rejectPanelMount(id, panel, initData) {
        if (_pendingOpen && _pendingOpen.id === id) _pendingOpen = null;
        if (panel && panel._el) panel._el.style.display = 'none';
        // A Host command can arrive before Panels.init() (or expose a missing
        // registry during boot). Failing that mount must still send the exact
        // tracked close envelope without dereferencing an unbound DOM host.
        if (_container) {
            _container.style.display = 'none';
            _container.removeAttribute('data-panel');
        }
        if (_content) _content.removeAttribute('data-panel');
        _active = null;
        _activePanelInstanceId = null;
        safeCleanupCallback(panel, 'onClose', 'rejected mount for ' + id);
        sendMountFailureClose(id, initData, 'mount_failed');
    }

    function rejectActiveMount(id, panelInstanceId) {
        if (_active !== id || !panelInstanceId
                || _activePanelInstanceId !== String(panelInstanceId)) return false;
        rejectPanelMount(id, _registry[id], {
            panelInstanceId:String(panelInstanceId)
        });
        return true;
    }

    function openAfterRequiredAssets(id) {
        var pending = _pendingOpen;
        if (!pending || pending.id !== id) return;
        var panel = _registry[id];
        if (!panel) {
            console.error('[Panels] panel not registered after asset gate: ' + id);
            // Host-owned panel 已持有视觉/pause owner；registry 缺失也必须按该 owner
            // 的精确 close envelope fail closed。纯 Web panel 保留静默清 pending。
            if (hostOwnsPanelMount(id, pending.initData)) {
                if (_active) close(true);
                rejectPanelMount(id, null, pending.initData);
            }
            else _pendingOpen = null;
            return;
        }

        if (panel._lazy) {
            console.log('[Panels] lazy-loading deps for: ' + id);
            try {
                var lazyLoad = typeof LazyLoader !== 'undefined' && LazyLoader
                    && typeof LazyLoader.load === 'function'
                    ? LazyLoader.load(panel._deps) : null;
                if (!lazyLoad || typeof lazyLoad.then !== 'function') {
                    throw new Error('LazyLoader.load returned a non-thenable');
                }
                var lazyChain = lazyLoad.then(function() {
                try {
                    panel._registerFn();
                } catch (e) {
                    console.error('[Panels] lazy registerFn threw for ' + id + ':', e);
                    if (_pendingOpen && _pendingOpen.id === id) cancelPendingOpen(true, 'lazy_register_failed');
                    return;
                }
                // registerFn 应当已调用 Panels.register(id, {...})，覆盖了 _registry[id]
                var resolved = _registry[id];
                if (!resolved || resolved._lazy) {
                    console.error('[Panels] lazy registerFn did not register panel: ' + id);
                    if (_pendingOpen && _pendingOpen.id === id) cancelPendingOpen(true, 'lazy_register_missing');
                    return;
                }
                // 检查 pending：可能在加载期间被 close 或切到别的 panel
                var pending = _pendingOpen;
                if (pending && pending.id === id) {
                    _pendingOpen = null;
                    _doOpen(id, pending.initData);
                } else {
                    console.log('[Panels] lazy load done but no longer pending: ' + id);
                }
                });
                if (!lazyChain || typeof lazyChain.catch !== 'function') {
                    throw new Error('LazyLoader.load.then returned a non-catchable chain');
                }
                lazyChain.catch(function(err) {
                    console.error('[Panels] lazy load failed for ' + id + ':', err);
                    if (_pendingOpen && _pendingOpen.id === id) cancelPendingOpen(true, 'lazy_load_failed');
                });
            } catch (err) {
                console.error('[Panels] lazy load failed for ' + id + ':', err);
                if (_pendingOpen && _pendingOpen.id === id) cancelPendingOpen(true, 'lazy_load_failed');
            }
            return;
        }

        _pendingOpen = null;
        _doOpen(id, pending.initData);
    }

    function open(id, initData) {
        console.log('[Panels] open called: id=' + id + ', _active=' + _active + ', registered=' + !!_registry[id]);
        if (!_registry[id]) {
            console.error('[Panels] panel not registered: ' + id);
            if (hostOwnsPanelMount(id, initData)) {
                // Host-owned panel 的 registry 缺失必须清掉任何旧视觉并按 incoming
                // owner fail closed；close shape 由 panel/owner 决定。
                if (_active) close();
                _pendingOpen = { id:id, initData:initData };
                rejectPanelMount(id, null, initData);
            }
            return;
        }

        // Most panels intentionally keep same-name open as a no-op. Stateful panels that
        // receive a new Host capability/session (skills manage <-> trainer) opt into an
        // explicit rebind hook so the existing pause lease and DOM host stay in place.
        if (_active === id) {
            // This command is newer than any still-loading switch. Retire that stale intent
            // before rebind so its late lazy completion cannot overwrite the latest panel.
            if (_pendingOpen) cancelPendingOpen(false, 'superseded_by_rebind');
            _doOpen(id, initData);
            return;
        }

        // 同一字段同时覆盖“资源门等待”和“lazy 依赖等待”的最新请求；close / 切 panel
        // 都能沿用既有取消语义，不会在 manifest 到达后把已关闭面板重新拉起。
        _pendingOpen = { id: id, initData: initData };
        ensureRequiredAssets(function() { openAfterRequiredAssets(id); });
    }

    function close(preservePendingOpen) {
        // 若 lazy panel 仍在加载，取消挂起的打开
        if (_pendingOpen && !preservePendingOpen) cancelPendingOpen(false, 'panel_close');
        if (!_active) return;
        var panel = _registry[_active];
        if (panel && panel._el) panel._el.style.display = 'none';
        _container.style.display = 'none';
        _container.removeAttribute('data-panel');
        _content.removeAttribute('data-panel');
        _active = null;
        _activePanelInstanceId = null;
        // onClose：任何关闭路径（C# close / finishClose / 切换面板）都要触发，
        // 用于 observer/listener/rAF 清理。onForceClose 仍在 force_close 分支额外触发，
        // 语义窄化为"C# 强关时的状态复位"。
        // 视觉与 owner 状态已经先归零；单个旧 panel 的清理异常不能中断
        // incoming panel 的 mount，也不能把 Panels 留在半 active 状态。
        safeCleanupCallback(panel, 'onClose', 'ordinary close');
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    function triggerRequestClose(reason) {
        if (_active && _registry[_active] && _registry[_active].onRequestClose) {
            _registry[_active].onRequestClose(reason || 'close');
        } else if (_pendingOpen) {
            // Loot 尚未完成 required-assets/lazy mount 时没有 authorityRevision/closeLease，
            // 因而不能把 ESC/backdrop 伪装成故障解绑，也不能猜测普通 close 写入。保持
            // pending；依赖完成后由已挂载的 LootPanel 统一提交 non-abandon suspend intent。
            if (_pendingOpen.id === 'loot') {
                console.log('[Panels] ignore close intent while loot lazy open is pending');
                return;
            }
            // 其他通用面板保留既有加载期取消行为。
            console.log('[Panels] cancel pending lazy open: ' + _pendingOpen.id);
            cancelPendingOpen(true, 'lazy_user_cancel');
        }
    }

    function isLootOpenLog(data) {
        return !!(data && data.cmd === 'open' && data.panel === 'loot' && data.initData);
    }

    function safePanelCommandLog(data) {
        var redactLootInitData = isLootOpenLog(data);
        if (!data || !data.initData || (!redactLootInitData
                && !Object.prototype.hasOwnProperty.call(data.initData, 'capability'))) {
            return JSON.stringify(data);
        }
        var safe = {};
        var key;
        for (key in data) {
            if (Object.prototype.hasOwnProperty.call(data, key)) safe[key] = data[key];
        }
        // Loot 的完整权威载荷整段固定成常量，避免未来新增字段形成日志旁路。
        // 普通 panel 仍保留逐字段日志语义，并单独隐藏 capability。
        safe.initData = redactLootInitData ? '[redacted]' : {};
        if (redactLootInitData) return JSON.stringify(safe);
        for (key in data.initData) {
            if (!Object.prototype.hasOwnProperty.call(data.initData, key)) continue;
            safe.initData[key] = key === 'capability' ? '[redacted]' : data.initData[key];
        }
        return JSON.stringify(safe);
    }

    // C# 指令分发
    Bridge.on('panel_cmd', function(data) {
        console.log('[Panels] panel_cmd received:', safePanelCommandLog(data));
        if (data.cmd === 'open') open(data.panel, data.initData);
        else if (data.cmd === 'close') close();
        else if (data.cmd === 'force_close') {
            var targetsWorkbench = data && data.panel === 'workbench';
            var activeWorkbench = _active === 'workbench';
            var activeCapabilityWorkbench = activeWorkbench;
            var pendingWorkbench = _pendingOpen && _pendingOpen.id === 'workbench';
            // A generic Host disconnect still belongs to an already-mounted ordinary panel.
            // close() also cancels any pending replacement so it cannot reopen after the fault.
            if (!targetsWorkbench && _active && !activeCapabilityWorkbench) {
                var ordinaryPanel = _registry[_active];
                close();
                safeCleanupCallback(
                    ordinaryPanel, 'onForceClose', 'generic force close');
                return;
            }
            if (targetsWorkbench) {
                var exactInstance = data && typeof data.panelInstanceId === 'string'
                    ? data.panelInstanceId : '';
                var pendingInstance = pendingWorkbench
                    ? readPanelInstanceId(_pendingOpen.initData) : '';
                var activeExact = !!exactInstance && activeWorkbench && !!_activePanelInstanceId
                    && exactInstance === _activePanelInstanceId;
                var pendingExact = !!exactInstance && pendingWorkbench && !!pendingInstance
                    && exactInstance === pendingInstance;
                var validReason = data && typeof data.reason === 'string' && !!data.reason;
                // capability-bound workbench 不接受无目标广播。旧实例的延迟强关也不能
                // 清掉已经 rebind/mount 的 replacement。
                if (!validReason || (!activeExact && !pendingExact)) return;
                if (pendingExact) cancelPendingOpen(false, 'force_close');
                // A targeted failure of the pending workbench replacement also invalidates an
                // ordinary panel that is still mounted underneath the switch.
                if (!activeExact && _active && !activeWorkbench) {
                    var replacedOrdinaryPanel = _registry[_active];
                    close();
                    safeCleanupCallback(
                        replacedOrdinaryPanel,
                        'onForceClose',
                        'targeted pending workbench force close');
                    return;
                }
                if (!activeExact) return;
                var exactPanel = _registry[_active];
                // 保留不同实例的 pending replacement；只关闭 exact active instance。
                close(true);
                safeCleanupCallback(
                    exactPanel, 'onForceClose', 'exact workbench force close');
                return;
            }
            // A generic fault normally cannot close a capability-bound workbench. During an
            // in-flight switch to an ordinary panel, however, it must cancel that replacement
            // and clear the old mounted workbench as one failed transition.
            if (activeCapabilityWorkbench) {
                if (!_pendingOpen || pendingWorkbench) return;
                var switchingWorkbenchPanel = _registry[_active];
                cancelPendingOpen(false, 'force_close');
                close();
                safeCleanupCallback(
                    switchingWorkbenchPanel,
                    'onForceClose',
                    'workbench replacement force close');
                return;
            }
            if (pendingWorkbench) return;
            var panel = _active ? _registry[_active] : null;
            close();
            safeCleanupCallback(panel, 'onForceClose', 'fallback force close');
        }
    });
    Bridge.on('panel_viewport_set', function(data) {
        var w = Number(data && data.w) || 0;
        var h = Number(data && data.h) || 0;
        if (w > 0) document.documentElement.style.setProperty('--panel-w', w + 'px');
        if (h > 0) document.documentElement.style.setProperty('--panel-h', h + 'px');
        if (typeof OverlayViewportMetrics !== 'undefined' && OverlayViewportMetrics) {
            if (OverlayViewportMetrics.report) OverlayViewportMetrics.report('panel_viewport_set');
            if (OverlayViewportMetrics.schedule) OverlayViewportMetrics.schedule('panel_viewport_set');
        }
    });
    Bridge.on('panel_esc', function() { triggerRequestClose('escape'); });

    return {
        register: register,
        installRegistrationDecorator: installRegistrationDecorator,
        registerLazy: function(id, deps, registerFn) {
            // 占位 entry：open() 命中 _lazy 分支后会先 load deps、再让 registerFn 覆盖 _registry[id]
            _registry[id] = { _lazy: true, _deps: deps, _registerFn: registerFn };
        },
        open: open,
        close: close,
        rejectActiveMount: rejectActiveMount,
        isOpen: function() { return _active !== null; },
        getActive: function() { return _active; },
        requiredAssetsReady: function() { return _requiredAssetsState === 'ready'; },
        getHitRects: function(pushRect) {
            if (_active && _container && _container.style.display !== 'none') pushRect(_container);
        },
        init: init
    };
})();
