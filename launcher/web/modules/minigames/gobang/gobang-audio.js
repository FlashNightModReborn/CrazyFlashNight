/* Gobang · 铁枪会接入台 音频模块
 * 纯 Web Audio 合成，无外部资源。
 * 语汇参考：铁枪武器（电蓝脉冲 / 能源核） + 尸解仙模因（低频共鸣 / 紫雾）
 */
var GobangAudio = (function() {
    "use strict";

    var _ctx = null;
    var _master = null;
    var _muted = false;
    var _storageKey = "cf7.gobang.audio.muted";

    try {
        if (typeof localStorage !== "undefined") {
            _muted = localStorage.getItem(_storageKey) === "1";
        }
    } catch (e) { /* no-op */ }

    function ensureCtx() {
        if (_ctx) return _ctx;
        var AC = typeof window !== "undefined" && (window.AudioContext || window.webkitAudioContext);
        if (!AC) return null;
        try {
            _ctx = new AC();
            _master = _ctx.createGain();
            _master.gain.value = 0.28;
            _master.connect(_ctx.destination);
        } catch (err) {
            _ctx = null;
        }
        return _ctx;
    }

    function unlock() {
        var ctx = ensureCtx();
        if (ctx && ctx.state === "suspended" && typeof ctx.resume === "function") {
            try { ctx.resume(); } catch (e) { /* no-op */ }
        }
    }

    function isMuted() { return _muted; }

    function setMuted(v) {
        _muted = !!v;
        try {
            if (typeof localStorage !== "undefined") {
                localStorage.setItem(_storageKey, _muted ? "1" : "0");
            }
        } catch (e) { /* no-op */ }
    }

    function toggleMuted() {
        setMuted(!_muted);
        return _muted;
    }

    // 单次音素：osc → gain（含 ADSR 包络）→ optional filter → master
    function blip(params) {
        if (_muted) return;
        var ctx = ensureCtx();
        if (!ctx) return;
        var now = ctx.currentTime + (params.delay || 0);
        var dur = params.dur || 0.12;
        var osc = ctx.createOscillator();
        osc.type = params.type || "sine";
        osc.frequency.setValueAtTime(params.f0 || 440, now);
        if (typeof params.f1 === "number") {
            osc.frequency.exponentialRampToValueAtTime(
                Math.max(20, params.f1),
                now + dur
            );
        }
        if (typeof params.detune === "number") {
            osc.detune.setValueAtTime(params.detune, now);
        }

        var gain = ctx.createGain();
        var peak = typeof params.peak === "number" ? params.peak : 0.35;
        gain.gain.setValueAtTime(0.0001, now);
        gain.gain.exponentialRampToValueAtTime(peak, now + Math.min(0.012, dur * 0.2));
        gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);

        var last = osc;
        last.connect(gain);

        if (params.filter) {
            var filt = ctx.createBiquadFilter();
            filt.type = params.filter.type || "bandpass";
            filt.frequency.setValueAtTime(params.filter.f0 || 800, now);
            if (typeof params.filter.f1 === "number") {
                filt.frequency.exponentialRampToValueAtTime(
                    Math.max(20, params.filter.f1),
                    now + dur
                );
            }
            filt.Q.value = params.filter.Q || 4;
            gain.connect(filt);
            filt.connect(_master);
        } else {
            gain.connect(_master);
        }

        osc.start(now);
        osc.stop(now + dur + 0.02);
    }

    // 短促白噪声脉冲（用于落子的"接触感"）
    function noiseBurst(params) {
        if (_muted) return;
        var ctx = ensureCtx();
        if (!ctx) return;
        var dur = params.dur || 0.05;
        var now = ctx.currentTime + (params.delay || 0);
        var bufferSize = Math.max(16, Math.floor(ctx.sampleRate * dur));
        var buf = ctx.createBuffer(1, bufferSize, ctx.sampleRate);
        var data = buf.getChannelData(0);
        var i;
        for (i = 0; i < bufferSize; i += 1) {
            data[i] = (Math.random() * 2 - 1) * (1 - i / bufferSize);
        }
        var src = ctx.createBufferSource();
        src.buffer = buf;

        var gain = ctx.createGain();
        var peak = typeof params.peak === "number" ? params.peak : 0.2;
        gain.gain.setValueAtTime(peak, now);
        gain.gain.exponentialRampToValueAtTime(0.0001, now + dur);

        var filt = ctx.createBiquadFilter();
        filt.type = params.filter || "highpass";
        filt.frequency.value = params.freq || 1600;
        filt.Q.value = params.Q || 1.2;

        src.connect(filt);
        filt.connect(gain);
        gain.connect(_master);
        src.start(now);
        src.stop(now + dur + 0.01);
    }

    /* ============ 事件音色 ============ */

    // 铁枪会锚点落下：电蓝脉冲 + 短金属冲击
    function playerPlace() {
        noiseBurst({ dur: 0.04, peak: 0.22, filter: "highpass", freq: 2400 });
        blip({ type: "square", f0: 1180, f1: 720, dur: 0.07, peak: 0.14,
               filter: { type: "bandpass", f0: 1400, f1: 900, Q: 8 } });
        blip({ type: "sine",   f0: 560,  f1: 280, dur: 0.12, peak: 0.22, delay: 0.01 });
    }

    // 尸解仙模因反制：低频共鸣 + 紫雾回响
    function aiPlace() {
        blip({ type: "sine",     f0: 180, f1: 88,  dur: 0.24, peak: 0.26 });
        blip({ type: "triangle", f0: 360, f1: 176, dur: 0.18, peak: 0.12, delay: 0.02 });
        blip({ type: "sine",     f0: 90,  f1: 66,  dur: 0.30, peak: 0.10, delay: 0.05 });
    }

    // 引擎启动思考：上升滤波扫频（像雷达开始扫描）
    function aiStart() {
        blip({ type: "sawtooth", f0: 240, f1: 520, dur: 0.26, peak: 0.08,
               filter: { type: "bandpass", f0: 400, f1: 1600, Q: 6 } });
    }

    // 禁手 / 非法落子：错误蜂鸣
    function illegal() {
        blip({ type: "sawtooth", f0: 220, f1: 180, dur: 0.10, peak: 0.20,
               filter: { type: "lowpass", f0: 800, Q: 2 } });
        blip({ type: "sawtooth", f0: 330, f1: 240, dur: 0.12, peak: 0.14, delay: 0.06,
               filter: { type: "lowpass", f0: 900, Q: 2 } });
    }

    // 贯穿胜利：上升琶音 + 能源核释放
    function win() {
        var notes = [262, 392, 523, 784]; // C4 G4 C5 G5
        var i;
        for (i = 0; i < notes.length; i += 1) {
            blip({ type: "triangle", f0: notes[i], dur: 0.18, peak: 0.22, delay: i * 0.08 });
            blip({ type: "sine",     f0: notes[i] * 2, dur: 0.14, peak: 0.10, delay: i * 0.08 + 0.01 });
        }
        // 能源核释放余响
        blip({ type: "sine", f0: 1046, f1: 440, dur: 0.45, peak: 0.14, delay: 0.34,
               filter: { type: "bandpass", f0: 1200, f1: 600, Q: 4 } });
    }

    // 失败：虚渊重新封闭的下行钟音
    function lose() {
        var notes = [330, 247, 196, 147]; // E4 B3 G3 D3
        var i;
        for (i = 0; i < notes.length; i += 1) {
            blip({ type: "sine",     f0: notes[i], dur: 0.30, peak: 0.18, delay: i * 0.10 });
            blip({ type: "triangle", f0: notes[i] * 0.5, dur: 0.34, peak: 0.08, delay: i * 0.10 });
        }
    }

    // UI 小 tick（按钮 / 面板开）
    function uiTick() {
        blip({ type: "square", f0: 1800, f1: 1200, dur: 0.04, peak: 0.06,
               filter: { type: "bandpass", f0: 1600, Q: 10 } });
    }

    // 开局涌现：双音合成
    function sessionOpen() {
        blip({ type: "sine",   f0: 330, f1: 660, dur: 0.35, peak: 0.12 });
        blip({ type: "square", f0: 120, f1: 240, dur: 0.28, peak: 0.06, delay: 0.04,
               filter: { type: "lowpass", f0: 800, Q: 1.2 } });
    }

    return {
        unlock: unlock,
        isMuted: isMuted,
        setMuted: setMuted,
        toggleMuted: toggleMuted,
        playerPlace: playerPlace,
        aiPlace: aiPlace,
        aiStart: aiStart,
        illegal: illegal,
        win: win,
        lose: lose,
        uiTick: uiTick,
        sessionOpen: sessionOpen
    };
})();

if (typeof module === "object" && module.exports) {
    module.exports = GobangAudio;
}
