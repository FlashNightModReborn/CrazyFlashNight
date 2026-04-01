/**
 * Toast module - replaces GDI+ ToastOverlay
 * Flash HTML subset (<font color>, <BR>) rendered via innerHTML
 */
var Toast = (function() {
    'use strict';

    var container;
    var DISPLAY_MS = 8000;
    var FADE_IN_MS = 200;
    var FADE_OUT_MS = 1200;
    var TOTAL_MS = FADE_IN_MS + DISPLAY_MS + FADE_OUT_MS;

    function init() {
        container = document.getElementById('toast-container');
    }

    function add(rawHtml) {
        if (!container) init();
        var div = document.createElement('div');
        div.className = 'toast-line';
        // Replace <BR> variants with actual line breaks
        var html = rawHtml.replace(/<BR\s*\/?>/gi, '<br>');
        div.innerHTML = html;

        // CSS animation drives the full lifecycle
        div.style.animationDuration = TOTAL_MS + 'ms';
        container.appendChild(div);

        // Trim: keep max ~8 lines
        while (container.children.length > 8) {
            container.removeChild(container.firstChild);
        }

        div.addEventListener('animationend', function() {
            if (div.parentNode) div.parentNode.removeChild(div);
        });
    }

    return { add: add };
})();
