/**
 * Currency — 经济面板（金钱 + K点）
 * 接收 UiData: Ucurrency|{id}|{value}|{delta}
 * 渲染：滚动数字 + 变动浮动文字
 */
var Currency = (function() {
    'use strict';

    var panels = {}; // id -> {el, valueEl, deltaEl, current, target, animId}
    var ANIM_DURATION = 600; // ms

    function init() {
        initPanel('gold', document.getElementById('currency-gold'));
        initPanel('kpoint', document.getElementById('currency-kpoint'));

        // 新格式（帧数据 KV）: g=gold, k=kpoint（JS 自算 delta）
        UiData.on('g', function(val, oldVal) {
            var newV = parseInt(val, 10) || 0;
            var oldV = (oldVal != null) ? (parseInt(oldVal, 10) || 0) : newV;
            update('gold', newV, newV - oldV);
        });
        UiData.on('k', function(val, oldVal) {
            var newV = parseInt(val, 10) || 0;
            var oldV = (oldVal != null) ? (parseInt(oldVal, 10) || 0) : newV;
            update('kpoint', newV, newV - oldV);
        });

        // 旧格式兼容（U 前缀 Ucurrency|id|value|delta）
        UiData.onLegacy('currency', function(fields) {
            var id = fields[0];
            var value = parseInt(fields[1], 10) || 0;
            var delta = parseInt(fields[2], 10) || 0;
            update(id, value, delta);
        });
    }

    function initPanel(id, el) {
        if (!el) return;
        var valueEl = el.querySelector('.currency-value');
        var deltaEl = el.querySelector('.currency-delta');
        panels[id] = {
            el: el,
            valueEl: valueEl,
            deltaEl: deltaEl,
            current: 0,
            target: 0,
            animId: null
        };
    }

    function update(id, value, delta) {
        var p = panels[id];
        if (!p) return;

        var from = p.target; // animate from last target, not current display
        p.target = value;

        // Animate counting
        if (p.animId) cancelAnimationFrame(p.animId);
        var startTime = null;
        var startVal = from;

        function tick(now) {
            if (!startTime) startTime = now;
            var elapsed = now - startTime;
            var t = Math.min(elapsed / ANIM_DURATION, 1);
            // ease-out cubic
            var eased = 1 - Math.pow(1 - t, 3);
            p.current = Math.round(startVal + (value - startVal) * eased);
            p.valueEl.textContent = formatNumber(p.current);

            if (t < 1) {
                p.animId = requestAnimationFrame(tick);
            } else {
                p.animId = null;
                p.current = value;
                p.valueEl.textContent = formatNumber(value);
            }
        }
        p.animId = requestAnimationFrame(tick);

        // Delta float text
        if (delta !== 0) {
            showDelta(p, delta);
        }
    }

    function showDelta(p, delta) {
        var el = p.deltaEl;
        if (!el) return;
        el.textContent = (delta > 0 ? '+' : '') + formatNumber(delta);
        el.className = 'currency-delta ' + (delta > 0 ? 'delta-up' : 'delta-down');
        // Restart animation by re-triggering reflow
        el.style.animation = 'none';
        el.offsetHeight; // force reflow
        el.style.animation = '';
    }

    function formatNumber(n) {
        // Simple thousands separator
        var s = String(Math.abs(n));
        var result = '';
        for (var i = s.length - 1, c = 0; i >= 0; i--, c++) {
            if (c > 0 && c % 3 === 0) result = ',' + result;
            result = s.charAt(i) + result;
        }
        return n < 0 ? '-' + result : result;
    }

    window.addEventListener('load', init);
    return {};
})();
