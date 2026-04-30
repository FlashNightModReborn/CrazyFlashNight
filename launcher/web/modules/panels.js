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
    // _pendingOpen：lazy 加载期间记录最新 open 请求；中途若被 close/切面板，这里被覆盖或清空，
    //   完成时按当前值决定是否真正打开。避免乱序导致已关闭的面板又被拉起。
    var _pendingOpen = null;

    function init() {
        _container = document.getElementById('panel-container');
        _backdrop  = document.getElementById('panel-backdrop');
        _content   = document.getElementById('panel-content');
        _backdrop.addEventListener('click', function() { triggerRequestClose(); });
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

    function open(id, initData) {
        console.log('[Panels] open called: id=' + id + ', _active=' + _active + ', registered=' + !!_registry[id]);
        var panel = _registry[id];
        if (!panel) { console.error('[Panels] panel not registered: ' + id); return; }

        if (panel._lazy) {
            // 加载中再次请求同一 panel：覆盖最新 initData，借用同一 in-flight promise
            _pendingOpen = { id: id, initData: initData };
            console.log('[Panels] lazy-loading deps for: ' + id);
            LazyLoader.load(panel._deps).then(function() {
                try {
                    panel._registerFn();
                } catch (e) {
                    console.error('[Panels] lazy registerFn threw for ' + id + ':', e);
                    if (_pendingOpen && _pendingOpen.id === id) _pendingOpen = null;
                    return;
                }
                // registerFn 应当已调用 Panels.register(id, {...})，覆盖了 _registry[id]
                var resolved = _registry[id];
                if (!resolved || resolved._lazy) {
                    console.error('[Panels] lazy registerFn did not register panel: ' + id);
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
                if (_pendingOpen && _pendingOpen.id === id) _pendingOpen = null;
            });
            return;
        }

        _doOpen(id, initData);
    }

    function close() {
        // 若 lazy panel 仍在加载，取消挂起的打开
        if (_pendingOpen) _pendingOpen = null;
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
            _pendingOpen = null;
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
        getHitRects: function(pushRect) {
            if (_active && _container && _container.style.display !== 'none') pushRect(_container);
        },
        init: init
    };
})();
