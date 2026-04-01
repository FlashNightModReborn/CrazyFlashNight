/**
 * Toast module - replaces GDI+ ToastOverlay
 * Flash HTML subset only: <font color="..."> and <BR>
 * All other tags/attributes are stripped for safety.
 */
var Toast = (function() {
    'use strict';

    var container;
    var DISPLAY_MS = 8000;
    var FADE_IN_MS = 200;
    var FADE_OUT_MS = 1200;
    var TOTAL_MS = FADE_IN_MS + DISPLAY_MS + FADE_OUT_MS;

    // Flash htmlText 白名单：只允许 <font color="..."> 和 <BR>
    // 其他标签和属性全部剥离
    var FONT_OPEN = /<font\s+color\s*=\s*["']?(#[0-9a-fA-F]{3,6})["']?\s*>/gi;
    var FONT_CLOSE = /<\/font\s*>/gi;
    var BR_TAG = /<BR\s*\/?>/gi;
    var ALL_TAGS = /<\/?[^>]+>/g;

    function sanitize(raw) {
        // 1. 提取白名单标签并替换为占位符
        var fonts = [];
        var s = raw.replace(FONT_OPEN, function(m, color) {
            var idx = fonts.length;
            fonts.push('<span style="color:' + color + '">');
            return '\x00F' + idx + '\x00';
        });
        s = s.replace(FONT_CLOSE, function() {
            return '\x00/F\x00';
        });
        s = s.replace(BR_TAG, function() {
            return '\x00BR\x00';
        });

        // 2. 剥离所有剩余 HTML 标签
        s = s.replace(ALL_TAGS, '');

        // 3. 转义剩余文本中的 HTML 特殊字符
        s = s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

        // 4. 还原白名单占位符
        s = s.replace(/\x00F(\d+)\x00/g, function(m, idx) {
            return fonts[parseInt(idx, 10)] || '';
        });
        s = s.replace(/\x00\/F\x00/g, '</span>');
        s = s.replace(/\x00BR\x00/g, '<br>');

        return s;
    }

    function init() {
        container = document.getElementById('toast-container');
    }

    function add(rawHtml) {
        if (!container) init();
        var div = document.createElement('div');
        div.className = 'toast-line';
        div.innerHTML = sanitize(rawHtml);

        div.style.animationDuration = TOTAL_MS + 'ms';
        container.appendChild(div);

        while (container.children.length > 8) {
            container.removeChild(container.firstChild);
        }

        div.addEventListener('animationend', function() {
            if (div.parentNode) div.parentNode.removeChild(div);
        });
    }

    return { add: add };
})();
