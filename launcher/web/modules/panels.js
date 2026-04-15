/**
 * Panels — 通用面板生命周期管理器
 *
 * 面板注册: Panels.register('kshop', { create, onOpen, onRequestClose })
 * C# 侧通过 Bridge 发送 panel_cmd / panel_esc 消息控制开关
 * 遮罩点击 / ESC 均走 onRequestClose（由面板自己决定是否真正关闭）
 */
var Panels = (function() {
    'use strict';

    var _registry = {};
    var _active = null;
    var _container, _backdrop, _content;

    function init() {
        _container = document.getElementById('panel-container');
        _backdrop  = document.getElementById('panel-backdrop');
        _content   = document.getElementById('panel-content');
        _backdrop.addEventListener('click', function() { triggerRequestClose(); });
    }

    function open(id, initData) {
        console.log('[Panels] open called: id=' + id + ', _active=' + _active + ', registered=' + !!_registry[id]);
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

    function close() {
        if (!_active) return;
        var panel = _registry[_active];
        if (panel && panel._el) panel._el.style.display = 'none';
        _container.style.display = 'none';
        _container.removeAttribute('data-panel');
        _content.removeAttribute('data-panel');
        _active = null;
        setTimeout(function() {
            if (typeof Notch !== 'undefined' && Notch.reportRect) Notch.reportRect();
        }, 50);
    }

    function triggerRequestClose() {
        if (_active && _registry[_active] && _registry[_active].onRequestClose) {
            _registry[_active].onRequestClose();
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
    Bridge.on('panel_esc', triggerRequestClose);

    return {
        register: function(id, opts) { _registry[id] = opts; },
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
