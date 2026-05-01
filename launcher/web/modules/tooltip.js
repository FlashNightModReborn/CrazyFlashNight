/**
 * PanelTooltip — 通用面板内 tooltip 模块
 *
 * 提供两种展示模式:
 *   1. hover 模式: showAtMouse / followMouse / hide — 跟随鼠标，鼠标离开即隐藏
 *   2. anchored 模式: showAnchored — 锚定到指定元素，支持 outside-click 关闭 + 自动超时
 *
 * 内容由调用方负责生成 HTML 字符串，本模块只管 DOM、定位和生命周期。
 * 包含 AS2 TextField HTML → 浏览器 HTML 转换工具函数 convertAS2Html()。
 */
var PanelTooltip = (function() {
    'use strict';

    var _el = null;
    var _visible = false;

    // anchored 模式的生命周期句柄
    var _outsideListener = null;
    var _autoTimer = null;

    function init() {
        _el = document.getElementById('panel-tooltip');
    }

    /** 获取 tooltip DOM 元素 */
    function getElement() { return _el; }

    /** 是否正在显示 */
    function isVisible() { return _visible; }

    // ── 内部清理 ──
    function cleanupHandlers() {
        if (_outsideListener) {
            document.removeEventListener('click', _outsideListener);
            _outsideListener = null;
        }
        if (_autoTimer) {
            clearTimeout(_autoTimer);
            _autoTimer = null;
        }
    }

    // ── hover 模式 ──

    /** hover 模式：在鼠标位置显示 tooltip，设置内容 */
    function showAtMouse(html, e) {
        if (!_el) return;
        cleanupHandlers();
        _el.innerHTML = html;
        _el.style.display = 'block';
        _visible = true;
        if (e) positionAtMouse(e);
    }

    /** hover 模式：跟随鼠标移动 */
    function followMouse(e) {
        if (!_el || !_visible) return;
        positionAtMouse(e);
    }

    function positionAtMouse(e) {
        var x = e.clientX + 14, y = e.clientY + 14;
        var tw = _el.offsetWidth, th = _el.offsetHeight;
        var vw = window.innerWidth, vh = window.innerHeight;
        if (x + tw > vw - 8) x = e.clientX - tw - 8;
        if (y + th > vh - 8) y = vh - th - 8;
        _el.style.left = x + 'px';
        _el.style.top = y + 'px';
    }

    // ── anchored 模式 ──

    /**
     * anchored 模式：锚定到指定元素旁显示 tooltip
     * @param {string} html - 内容 HTML
     * @param {Element} anchorEl - 锚定元素
     * @param {Object} [opts] - 选项
     * @param {number} [opts.autoClose=8000] - 自动关闭延迟 ms，0 禁用
     * @param {boolean} [opts.outsideClick=true] - 点击外部关闭
     */
    function showAnchored(html, anchorEl, opts) {
        if (!_el) return;
        opts = opts || {};
        var autoClose = opts.autoClose !== undefined ? opts.autoClose : 8000;
        var outsideClick = opts.outsideClick !== false;

        cleanupHandlers();
        _el.innerHTML = html;
        _el.style.display = 'block';
        _visible = true;

        // 定位：优先放在锚定元素左侧，放不下则右侧
        if (anchorEl) {
            var rect = anchorEl.getBoundingClientRect();
            var tw = _el.offsetWidth || 300;
            var th = _el.offsetHeight || 200;
            var vw = window.innerWidth, vh = window.innerHeight;
            var x = rect.left - tw - 8;
            if (x < 8) x = rect.right + 8;
            var y = rect.top;
            if (y + th > vh - 8) y = vh - th - 8;
            if (y < 8) y = 8;
            _el.style.left = x + 'px';
            _el.style.top = y + 'px';
        }

        // outside-click 关闭
        if (outsideClick) {
            _outsideListener = function(ev) {
                if (_el.contains(ev.target) || (anchorEl && anchorEl.contains(ev.target))) return;
                hide();
            };
            setTimeout(function() {
                if (_outsideListener) document.addEventListener('click', _outsideListener);
            }, 0);
        }

        // 自动关闭
        if (autoClose > 0) {
            _autoTimer = setTimeout(function() { hide(); }, autoClose);
        }
    }

    /**
     * 更新已显示的 tooltip 内容（不改变位置和生命周期）
     * 用于异步数据到达后刷新
     */
    function updateContent(html) {
        if (!_el || !_visible) return;
        _el.innerHTML = html;
    }

    /** 隐藏 tooltip 并清理所有句柄 */
    function hide() {
        cleanupHandlers();
        _visible = false;
        if (_el) _el.style.display = 'none';
    }

    // ── AS2 HTML 转换 ──

    /**
     * 将 AS2 TextField HTML 标记转为浏览器兼容 HTML
     * AS2 使用 <FONT COLOR='#FFCC00'> 等大写标签
     */
    function convertAS2Html(s) {
        if (!s) return '';
        return String(s)
            .replace(/<FONT\b([^>]*)>/gi, function(m, attrs) {
                attrs = attrs || '';
                var style = [];
                var color = /\bCOLOR\s*=\s*(['"])(.*?)\1/i.exec(attrs);
                if (color && /^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?$/.test(color[2])) {
                    style.push('color:' + color[2]);
                }
                var size = /\bSIZE\s*=\s*(['"])(.*?)\1/i.exec(attrs);
                if (size) {
                    var px = parseInt(size[2], 10);
                    if (!isNaN(px) && px > 0 && px <= 96) style.push('font-size:' + px + 'px');
                }
                return style.length ? '<span style="' + style.join(';') + '">' : '<span>';
            })
            .replace(/<\/FONT>/gi, '</span>')
            .replace(/<B>/gi, '<b>').replace(/<\/B>/gi, '</b>')
            .replace(/<I>/gi, '<i>').replace(/<\/I>/gi, '</i>')
            .replace(/<U>/gi, '<u>').replace(/<\/U>/gi, '</u>')
            .replace(/<BR\s*\/?>/gi, '<br>');
    }

    if (document.readyState === 'loading') window.addEventListener('load', init);
    else init();

    return {
        getElement: getElement,
        isVisible: isVisible,
        showAtMouse: showAtMouse,
        followMouse: followMouse,
        showAnchored: showAnchored,
        updateContent: updateContent,
        hide: hide,
        convertAS2Html: convertAS2Html
    };
})();
