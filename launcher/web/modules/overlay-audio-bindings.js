// Overlay 层 Web Audio 启动 + data-audio-cue 定向分派.
//
// 设计边界:
//   - 不对所有 <button> 做默认 hover/click (overlay 内 notch/jukebox 等按钮不想被顺手加音效).
//   - 只对显式带 data-audio-cue="xxx" 的元素播 cue; 这样每个子面板 (map-panel 先行) 自己决定语义.
//   - 首次 pointerdown/keydown 时 resume AudioContext (浏览器 autoplay policy).
//
// cue 名字直接对应 BootstrapAudio.playXxx —— hover/click/select/transition/confirm/cancel/error/modalOpen/ready/success.

(function () {
    'use strict';

    if (!window.BootstrapAudio) return;   // audio.js 未加载, 静默降级

    var A = window.BootstrapAudio;
    var _resumed = false;

    function cueFn(name) {
        if (!name) return null;
        var fn = A['play' + name.charAt(0).toUpperCase() + name.slice(1)];
        return typeof fn === 'function' ? fn : null;
    }

    function resumeOnce() {
        if (_resumed) return;
        _resumed = true;
        if (A.init) A.init();
        if (A.resume) A.resume();
    }

    document.addEventListener('pointerdown', resumeOnce, true);
    document.addEventListener('keydown', resumeOnce, true);

    document.addEventListener('mouseover', function (e) {
        var t = e.target;
        if (!t || !t.closest) return;
        var el = t.closest('[data-audio-cue]');
        if (!el || el.disabled) return;
        // hover cue: 元素指定 data-audio-hover (覆写) 或默认 'hover'
        var hoverName = el.getAttribute('data-audio-hover');
        var fn = cueFn(hoverName || 'hover');
        if (fn) fn();
    });

    document.addEventListener('click', function (e) {
        var t = e.target;
        if (!t || !t.closest) return;
        var el = t.closest('[data-audio-cue]');
        if (!el || el.disabled) return;
        var fn = cueFn(el.getAttribute('data-audio-cue'));
        if (fn) fn();
    });
})();
