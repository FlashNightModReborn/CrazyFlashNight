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
    var _container, _backdrop, _content;
    // 所有生产 Panel 共用的最低资源门：物品 / 装备 / 奖励图标 manifest。
    // icons.js 本身是 boot 脚本，但 manifest 是异步加载；若不在生命周期层拦住首次 open，
    // 新迁移面板很容易在 Icons.html() 仍为空时完成第一次渲染。
    var _requiredAssetsState = 'idle';
    var _requiredAssetsQueue = [];
    // _pendingOpen：required-assets / lazy 加载期间记录最新 open 请求；中途若被 close/切面板，
    //   这里被覆盖或清空。完成时按当前值决定是否真正打开，避免已关闭面板被异步拉起。
    var _pendingOpen = null;

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
        if (notifyHost && typeof Bridge !== 'undefined' && Bridge && Bridge.send) {
            var closeMessage = {
                type: 'panel',
                cmd: 'close',
                panel: pending.id
            };
            if (pending.id === 'skills') {
                // skills close 是独立的四键 exact envelope。即使面板尚未完成 lazy
                // 注册，也要用 Host 下发的实例撤销教师 capability，不能夹带 reason。
                closeMessage.panelInstanceId = String(pending.initData && pending.initData.panelInstanceId || '');
            } else {
                closeMessage.reason = reason || 'lazy_cancel';
                if (pending.id === 'loot') {
                    // loot 由 Host 的 tracked panelInstanceId 持有暂停租约。即使依赖尚未
                    // 加载完成，取消也必须携带 exact instance，供 Host 只做视觉解绑；
                    // 缺失或过期实例会由 Host fail closed，绝不能退回普通 close/unpause。
                    closeMessage.panelInstanceId = String(
                        pending.initData && pending.initData.panelInstanceId || '');
                }
            }
            Bridge.send(closeMessage);
        }
        return pending;
    }

    function init() {
        _container = document.getElementById('panel-container');
        _backdrop  = document.getElementById('panel-backdrop');
        _content   = document.getElementById('panel-content');
        _backdrop.addEventListener('click', function() { triggerRequestClose(); });
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
            var activePanel = _registry[id];
            if (activePanel && activePanel.onRebind) activePanel.onRebind(activePanel._el, initData);
            return;
        }
        if (_active) close();
        var panel = _registry[id];
        if (!panel) { console.error('[Panels] panel not registered: ' + id); return; }
        if (!panel._el) {
            panel._el = panel.create(_content);
            _content.appendChild(panel._el);
        }
        panel._el.style.display = '';
        _container.style.display = '';
        _container.setAttribute('data-panel', id);
        _content.setAttribute('data-panel', id);
        if (panel.onOpen) panel.onOpen(panel._el, initData);
        _active = id;
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    function openAfterRequiredAssets(id) {
        var pending = _pendingOpen;
        if (!pending || pending.id !== id) return;
        var panel = _registry[id];
        if (!panel) {
            console.error('[Panels] panel not registered after asset gate: ' + id);
            // tracked loot 可能已经被 Host 标记为 OpenPosted 并持有统一 pause。这里不能
            // 静默清 pending；必须携 exact panelInstanceId 回告视觉解绑。普通 panel 保持
            // 既有清理语义，避免把本修复扩张成其他协议的行为变化。
            if (id === 'loot') cancelPendingOpen(true, 'mount_failed');
            else _pendingOpen = null;
            return;
        }

        if (panel._lazy) {
            console.log('[Panels] lazy-loading deps for: ' + id);
            LazyLoader.load(panel._deps).then(function() {
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
            }).catch(function(err) {
                console.error('[Panels] lazy load failed for ' + id + ':', err);
                if (_pendingOpen && _pendingOpen.id === id) cancelPendingOpen(true, 'lazy_load_failed');
            });
            return;
        }

        _pendingOpen = null;
        _doOpen(id, pending.initData);
    }

    function open(id, initData) {
        console.log('[Panels] open called: id=' + id + ', _active=' + _active + ', registered=' + !!_registry[id]);
        if (!_registry[id]) {
            console.error('[Panels] panel not registered: ' + id);
            if (id === 'loot') {
                // Host 的 tracked open 已经携带 exact identity；registry 缺失仍须走统一
                // pending-cancel 路径发五键 close，否则 Host 会永远停在 OpenPosted/pause。
                _pendingOpen = { id: id, initData: initData };
                cancelPendingOpen(true, 'mount_failed');
            }
            return;
        }

        // Most panels intentionally keep same-name open as a no-op. Stateful panels that
        // receive a new Host capability/session (skills manage <-> trainer) opt into an
        // explicit rebind hook so the existing pause lease and DOM host stay in place.
        if (_active === id) {
            var activePanel = _registry[id];
            if (activePanel && activePanel.onRebind) activePanel.onRebind(activePanel._el, initData);
            return;
        }

        // 同一字段同时覆盖“资源门等待”和“lazy 依赖等待”的最新请求；close / 切 panel
        // 都能沿用既有取消语义，不会在 manifest 到达后把已关闭面板重新拉起。
        _pendingOpen = { id: id, initData: initData };
        ensureRequiredAssets(function() { openAfterRequiredAssets(id); });
    }

    function close() {
        // 若 lazy panel 仍在加载，取消挂起的打开
        if (_pendingOpen) cancelPendingOpen(false, 'panel_close');
        if (!_active) return;
        var panel = _registry[_active];
        if (panel && panel._el) panel._el.style.display = 'none';
        _container.style.display = 'none';
        _container.removeAttribute('data-panel');
        _content.removeAttribute('data-panel');
        _active = null;
        // onClose：任何关闭路径（C# close / finishClose / 切换面板）都要触发，
        // 用于 observer/listener/rAF 清理。onForceClose 仍在 force_close 分支额外触发，
        // 语义窄化为"C# 强关时的状态复位"。
        if (panel && panel.onClose) panel.onClose();
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    function triggerRequestClose() {
        if (_active && _registry[_active] && _registry[_active].onRequestClose) {
            _registry[_active].onRequestClose();
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

    function isLockboxS0OpenLog(data) {
        var initData = data && data.initData;
        if (!data || data.cmd !== 'open' || data.panel !== 'lockbox' || !initData) return false;
        return initData.source === 'as2-chest-s0'
            || initData.fixture === 'insurance-safe-s0-v1'
            || Object.prototype.hasOwnProperty.call(initData, '__lockboxChestS0')
            || (Object.prototype.hasOwnProperty.call(initData, 'capability')
                && Object.prototype.hasOwnProperty.call(initData, 'connectionGeneration')
                && Object.prototype.hasOwnProperty.call(initData, 'gameProcessId')
                && Object.prototype.hasOwnProperty.call(initData, 'documentEpoch')
                && Object.prototype.hasOwnProperty.call(initData, 'flowHandle')
                && Object.prototype.hasOwnProperty.call(initData, 'panelInstanceId'));
    }

    function isLootOpenLog(data) {
        return !!(data && data.cmd === 'open' && data.panel === 'loot' && data.initData);
    }

    function safePanelCommandLog(data) {
        var redactS0InitData = isLockboxS0OpenLog(data);
        var redactLootInitData = isLootOpenLog(data);
        var redactWholeInitData = redactS0InitData || redactLootInitData;
        if (!data || !data.initData || (!redactWholeInitData
                && !Object.prototype.hasOwnProperty.call(data.initData, 'capability'))) {
            return JSON.stringify(data);
        }
        var safe = {};
        var key;
        for (key in data) {
            if (Object.prototype.hasOwnProperty.call(data, key)) safe[key] = data[key];
        }
        // S0（含 browser-host-shim）和 loot 的完整 identity 都整段固定成常量，避免
        // 未来新增字段再次形成日志旁路。普通 panel 仍保留逐字段日志语义。
        safe.initData = redactWholeInitData ? '[redacted]' : {};
        if (redactWholeInitData) return JSON.stringify(safe);
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
            var panel = _active ? _registry[_active] : null;
            close();
            if (panel && panel.onForceClose) panel.onForceClose();
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
    Bridge.on('panel_esc', triggerRequestClose);

    return {
        register: register,
        installRegistrationDecorator: installRegistrationDecorator,
        registerLazy: function(id, deps, registerFn) {
            // 占位 entry：open() 命中 _lazy 分支后会先 load deps、再让 registerFn 覆盖 _registry[id]
            _registry[id] = { _lazy: true, _deps: deps, _registerFn: registerFn };
        },
        open: open,
        close: close,
        isOpen: function() { return _active !== null; },
        getActive: function() { return _active; },
        requiredAssetsReady: function() { return _requiredAssetsState === 'ready'; },
        getHitRects: function(pushRect) {
            if (_active && _container && _container.style.display !== 'none') pushRect(_container);
        },
        init: init
    };
})();
