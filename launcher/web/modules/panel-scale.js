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
 * 可选第 4 参 opts：{ minScale, maxScale, onUpdate }。minScale/maxScale 为额外钳制（默认不限）；
 * onUpdate(scale) 在每次计算后以钳制后的原始数值回调，供居中 anchor 等不挂 .panel-scale-shell、
 * 由 JS 自写 transform 的壳体消费（如 stage-select / intelligence）。
 *
 * 设计取舍：tasks/pet/merc 各有自有等价实现（历史先行），本 primitive 供新接入的
 * B 类面板（kshop / jukebox / arena 等）复用，不强迁既有黄金标准面板以免引入耦合回归。
 * 2026-07-17：intelligence 已迁入本 primitive（JS 层 attach/detach），但壳体几何保留本地
 * 1404×790 画布（阅读面板非 1024×576 工作台几何），不挂 .panel-scale-shell 类。
 * 2026-08-16：stage-select 已接入（JS 层 attach + minScale 0.45 / maxScale=dev 1.35、runtime 不限
 * + onUpdate 回写居中 transform 与 --stage-select-scale；壳体保留居中 translate(-50%,-50%)
 * anchor，不挂 .panel-scale-shell 类——该类的 top/left:0 + origin top left 与其全屏居中形态冲突）。
 */
var PanelScale = (function () {
    'use strict';

    var NOOP_HANDLE = { update: function () {}, detach: function () {} };

    function attach(shellEl, designW, designH, opts) {
        if (!shellEl || !designW || !designH) return NOOP_HANDLE;
        opts = opts || {};
        var minScale = (typeof opts.minScale === 'number' && opts.minScale > 0) ? opts.minScale : 0;
        var maxScale = (typeof opts.maxScale === 'number' && opts.maxScale > 0) ? opts.maxScale : Infinity;
        var onUpdate = (typeof opts.onUpdate === 'function') ? opts.onUpdate : null;

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
            if (minScale && scale < minScale) scale = minScale;
            if (scale > maxScale) scale = maxScale;
            shellEl.style.setProperty('--panel-scale', scale.toFixed(4));
            if (onUpdate) onUpdate(scale);
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
