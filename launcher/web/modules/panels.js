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

    function cancelPendingOpen(notifyHost, reason) {
        if (!_pendingOpen) return null;
        var pending = _pendingOpen;
        _pendingOpen = null;
        if (notifyHost && typeof Bridge !== 'undefined' && Bridge && Bridge.send) {
            Bridge.send({
                type: 'panel',
                cmd: 'close',
                panel: pending.id,
                reason: reason || 'lazy_cancel'
            });
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
        if (_active === id) return;
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
            _pendingOpen = null;
            console.error('[Panels] panel not registered after asset gate: ' + id);
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
        if (!_registry[id]) { console.error('[Panels] panel not registered: ' + id); return; }

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
            // 加载期间被 ESC/backdrop 触发关闭：直接取消挂起
            console.log('[Panels] cancel pending lazy open: ' + _pendingOpen.id);
            cancelPendingOpen(true, 'lazy_user_cancel');
        }
    }

    // C# 指令分发
    Bridge.on('panel_cmd', function(data) {
        console.log('[Panels] panel_cmd received:', JSON.stringify(data));
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
        register: function(id, opts) { _registry[id] = opts; },
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
