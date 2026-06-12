/**
 * PanelScale — 共享「固定设计画布 + 整体等比缩放」primitive（沉浸全屏化 2026-06-11）
 *
 * 把一个固定 designW×designH 的 shell 元素，按其父容器（通常 #panel-content = 全 anchor 16:9）
 * 等比缩放铺满：scale = Math.min(parentW/designW, parentH/designH)，写入 shell 的 --panel-scale。
 * 因 anchor 恒 16:9，设计画布若也是 16:9（如 1024×576），两路相等、零 letterbox、无损铺满。
 *
 * 配套 CSS：shell 需带 .panel-scale-shell（position:absolute; top/left:0; transform:scale(var(--panel-scale));
 * transform-origin:top left; width/height 由 --pss-w/--pss-h 提供，本模块会设置）。
 *
 * 用法：
 *   var handle = PanelScale.attach(shellEl, 1024, 576);   // onOpen
 *   handle.detach();                                       // onClose（务必，避免 resize/ResizeObserver 泄漏）
 *
 * 设计取舍：tasks/pet/merc/intelligence 各有自有等价实现（历史先行），本 primitive 供新接入的
 * B 类面板（stage-select / kshop / jukebox / arena 等）复用，不强迁既有黄金标准面板以免引入耦合回归。
 */
var PanelScale = (function () {
    'use strict';

    var NOOP_HANDLE = { update: function () {}, detach: function () {} };

    function attach(shellEl, designW, designH) {
        if (!shellEl || !designW || !designH) return NOOP_HANDLE;

        shellEl.style.setProperty('--pss-w', designW + 'px');
        shellEl.style.setProperty('--pss-h', designH + 'px');

        var ro = null;

        function update() {
            var parent = shellEl.parentElement;
            var w = parent ? (parent.clientWidth || parent.offsetWidth || 0) : 0;
            var h = parent ? (parent.clientHeight || parent.offsetHeight || 0) : 0;
            if (!w || !h) return;
            var scale = Math.min(w / designW, h / designH);
            if (!isFinite(scale) || scale <= 0) scale = 1;
            shellEl.style.setProperty('--panel-scale', scale.toFixed(4));
        }

        function schedule() {
            if (typeof requestAnimationFrame === 'function') requestAnimationFrame(update);
            else setTimeout(update, 0);
        }

        window.addEventListener('resize', schedule);
        if (typeof ResizeObserver !== 'undefined') {
            ro = new ResizeObserver(schedule);
            ro.observe(shellEl);
            if (shellEl.parentElement) ro.observe(shellEl.parentElement);
        }
        update();

        return {
            update: update,
            detach: function () {
                window.removeEventListener('resize', schedule);
                if (ro) { ro.disconnect(); ro = null; }
            }
        };
    }

    return { attach: attach };
})();

if (typeof window !== 'undefined') window.PanelScale = PanelScale;
if (typeof module !== 'undefined' && module.exports) module.exports = PanelScale;
