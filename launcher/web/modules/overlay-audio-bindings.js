// Overlay 层 Web Audio 启动 + data-audio-cue 定向分派.
//
// 设计边界:
//   - 不对所有 <button> 做默认 hover/click (overlay 内 notch/jukebox 等按钮不想被顺手加音效).
//   - 只对显式带 data-audio-cue="xxx" 的元素播 cue; 这样每个子面板 (map-panel 先行) 自己决定语义.
//   - 首次 pointerdown/keydown 时 resume AudioContext (浏览器 autoplay policy).
//
// cue 解析走 BootstrapAudio.cue 语义层 (2026-08-15 契约 v1): 旧名别名归一 + 当前面板 profile 抑制.
// 统一抑制条件 (满足任一即静默, 优先于 profile):
//   - el.disabled 或 aria-disabled="true";
//   - 元素或祖先带 data-busy="true" (closest 判定).
// Host 偏好同步: Bridge.on('audioPrefs') → setSfxEnabled/setAmbientEnabled (P0).

(function () {
    'use strict';

    if (!window.BootstrapAudio) return;   // audio.js 未加载, 静默降级

    var A = window.BootstrapAudio;
    var _resumed = false;

    // 语义层分派: 别名归一 + profile 抑制都在 cue() 内完成
    function playCue(name) {
        if (!name || typeof A.cue !== 'function') return;
        A.cue(name);
    }

    // 统一抑制: disabled / aria-disabled / data-busy (元素或祖先)
    function isSuppressed(el) {
        if (el.disabled) return true;
        if (el.getAttribute('aria-disabled') === 'true') return true;
        return !!el.closest('[data-busy="true"]');
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
        if (!el || isSuppressed(el)) return;
        // hover cue: 元素指定 data-audio-hover (覆写) 或默认 'hover'
        var hoverName = el.getAttribute('data-audio-hover');
        playCue(hoverName || 'hover');
    });

    // click cue 走 capture: 某些按钮会在自身 click handler 里立刻切 busy/disabled，
    // 若等到 bubble 再判断抑制，会把本该响的一次 cue 吞掉。
    document.addEventListener('click', function (e) {
        var t = e.target;
        if (!t || !t.closest) return;
        var el = t.closest('[data-audio-cue]');
        if (!el || isSuppressed(el)) return;
        playCue(el.getAttribute('data-audio-cue'));
    }, true);

    // Host → overlay 音频偏好下发 (初始 + config_set 变更广播)
    if (typeof Bridge !== 'undefined' && Bridge && typeof Bridge.on === 'function') {
        Bridge.on('audioPrefs', function (msg) {
            if (!msg) return;
            if (typeof msg.sfxEnabled === 'boolean' && typeof A.setSfxEnabled === 'function') {
                A.setSfxEnabled(msg.sfxEnabled);
            }
            if (typeof msg.ambientEnabled === 'boolean' && typeof A.setAmbientEnabled === 'function') {
                A.setAmbientEnabled(msg.ambientEnabled);
            }
        });
    }
})();
