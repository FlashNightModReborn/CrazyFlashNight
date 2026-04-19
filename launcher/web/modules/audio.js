// Web Audio 合成的 UI 音效 + 环境 hum. 无外部音源 — 全部 Oscillator / BufferSource(noise) + ADSR envelope.
// 设计约束: 节制 / 短促 / 低音量; 三条 bus (master → sfx / ambient).
// 自动播放策略: AudioContext 首次 new 可能处于 suspended; 首次用户交互后 BootstrapApp 会调 resume().

(function () {
  'use strict';

  var ctx = null;
  var masterGain = null, sfxGain = null, ambientGain = null;
  var _noiseBuffer = null;              // 1s 白噪声, bandpass/lowpass 后做 click / swish / impact
  var _ambientRunning = false;
  var _ambientSources = [];
  var _sfxEnabled = true;
  var _ambientEnabled = false;
  var _lastHoverMs = 0;
  var HOVER_DEBOUNCE_MS = 45;           // 快速划过多个按钮时避免 spam
  var MASTER_LEVEL = 0.6;               // 整体偏保守, sfx 内部已节制
  var _lastReadyMs = 0;                 // playReady 去抖 (state 快速翻转时只响一次)
  var READY_DEBOUNCE_MS = 2000;

  function initCtx() {
    if (ctx) return ctx;
    var AC = window.AudioContext || window.webkitAudioContext;
    if (!AC) return null;
    try {
      ctx = new AC();
      masterGain = ctx.createGain();
      masterGain.gain.value = MASTER_LEVEL;
      masterGain.connect(ctx.destination);
      sfxGain = ctx.createGain();
      sfxGain.gain.value = 1.0;
      sfxGain.connect(masterGain);
      ambientGain = ctx.createGain();
      ambientGain.gain.value = 0;       // fade-in 时推起
      ambientGain.connect(masterGain);
      _noiseBuffer = makeNoiseBuffer(1.0);
    } catch (e) {
      if (window.console) console.error('[Audio] init failed:', e);
      ctx = null;
    }
    return ctx;
  }

  function resumeIfSuspended() {
    if (!ctx) return;
    if (ctx.state === 'suspended' && ctx.resume) {
      ctx.resume().catch(function (e) {
        if (window.console) console.warn('[Audio] resume failed:', e && e.message);
      });
    }
  }

  function makeNoiseBuffer(durationSec) {
    var sr = ctx.sampleRate;
    var len = Math.floor(sr * durationSec);
    var buf = ctx.createBuffer(1, len, sr);
    var data = buf.getChannelData(0);
    for (var i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    return buf;
  }

  // 简易 ADSR → attack + decay 指数衰减到 0.
  // peak < 0.0001 会撑坏 exponentialRamp, 统一 clamp.
  function applyEnv(gainNode, t0, attack, decay, peak) {
    var p = Math.max(0.0001, peak);
    gainNode.gain.cancelScheduledValues(t0);
    gainNode.gain.setValueAtTime(0.0001, t0);
    gainNode.gain.exponentialRampToValueAtTime(p, t0 + attack);
    gainNode.gain.exponentialRampToValueAtTime(0.0001, t0 + attack + decay);
  }

  // ── 基础 voice 工厂 ──

  function tonePulse(freq, type, attack, decay, peak, freqEnd, destGain) {
    if (!ctx) return;
    var now = ctx.currentTime;
    var o = ctx.createOscillator();
    var g = ctx.createGain();
    o.type = type || 'sine';
    o.frequency.setValueAtTime(freq, now);
    if (freqEnd != null && freqEnd !== freq) {
      o.frequency.exponentialRampToValueAtTime(
        Math.max(10, freqEnd), now + attack + decay);
    }
    applyEnv(g, now, attack, decay, peak);
    o.connect(g);
    g.connect(destGain || sfxGain);
    o.start(now);
    o.stop(now + attack + decay + 0.05);
  }

  function noisePulse(attack, decay, peak, filterType, filterFreqStart, filterFreqEnd, Q, destGain) {
    if (!ctx) return;
    var now = ctx.currentTime;
    var n = ctx.createBufferSource();
    n.buffer = _noiseBuffer;
    var f = ctx.createBiquadFilter();
    f.type = filterType || 'bandpass';
    f.frequency.setValueAtTime(filterFreqStart, now);
    if (filterFreqEnd != null && filterFreqEnd !== filterFreqStart) {
      f.frequency.exponentialRampToValueAtTime(
        Math.max(30, filterFreqEnd), now + attack + decay);
    }
    if (Q != null) f.Q.value = Q;
    var g = ctx.createGain();
    applyEnv(g, now, attack, decay, peak);
    n.connect(f);
    f.connect(g);
    g.connect(destGain || sfxGain);
    n.start(now);
    n.stop(now + attack + decay + 0.05);
  }

  // ── 交互音 ──

  // 光标 hover: 轻微高频 tick. 去抖 45ms 防 spam.
  function playHover() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    var nowMs = Date.now();
    if (nowMs - _lastHoverMs < HOVER_DEBOUNCE_MS) return;
    _lastHoverMs = nowMs;
    tonePulse(1200, 'sine', 0.004, 0.07, 0.03, 1400);
  }

  // 按钮点击: sine body + noise click
  function playClick() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    tonePulse(600, 'sine', 0.003, 0.12, 0.10, 420);
    noisePulse(0.002, 0.04, 0.06, 'bandpass', 2800, 2200, 2.5);
  }

  // 选中 / 切换: 两音 chime (基频 + 完全五度), 微错开
  function playSelect() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    var now = ctx.currentTime;
    // 一音
    tonePulse(440, 'sine', 0.006, 0.32, 0.08);
    // 五度, 40ms 后, 略淡一点
    setTimeout(function () {
      if (!ctx) return;
      var o = ctx.createOscillator();
      var g = ctx.createGain();
      o.type = 'sine';
      o.frequency.value = 660;
      applyEnv(g, ctx.currentTime, 0.008, 0.3, 0.06);
      o.connect(g); g.connect(sfxGain);
      o.start(ctx.currentTime);
      o.stop(ctx.currentTime + 0.4);
    }, 40);
  }

  // 确认启动: 低频 thud + harmonic + 低通 noise impact
  function playConfirm() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    tonePulse(80, 'sine', 0.008, 0.5, 0.22, 120);
    tonePulse(160, 'sine', 0.012, 0.32, 0.08);
    noisePulse(0.002, 0.08, 0.08, 'lowpass', 300, 300, 0.7);
  }

  // 取消 / 返回: 下降 swish
  function playCancel() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    noisePulse(0.008, 0.28, 0.1, 'bandpass', 1600, 600, 3);
  }

  // 错误: 不协和 minor second 双 tap
  function playError() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    tonePulse(220, 'triangle', 0.01, 0.14, 0.11);
    tonePulse(233, 'triangle', 0.01, 0.14, 0.09);
    setTimeout(function () {
      if (!_sfxEnabled || !ctx) return;
      tonePulse(220, 'triangle', 0.01, 0.14, 0.11);
      tonePulse(233, 'triangle', 0.01, 0.14, 0.09);
    }, 170);
  }

  // 就绪 chord: 3 音琶音 (1 八度 + 五度), 带 2s 去抖
  function playReady() {
    if (!_sfxEnabled || !initCtx()) return;
    resumeIfSuspended();
    var nowMs = Date.now();
    if (nowMs - _lastReadyMs < READY_DEBOUNCE_MS) return;
    _lastReadyMs = nowMs;
    [110, 220, 330].forEach(function (f, i) {
      setTimeout(function () {
        if (!_sfxEnabled || !ctx) return;
        tonePulse(f, 'sine', 0.04, 0.85, 0.07);
      }, i * 85);
    });
  }

  // ── 环境 hum ──
  // 55Hz 基频 + 82.5Hz 五度 + 低通白噪声地板, 加 0.3Hz LFO 做呼吸感.
  // fade in 1.5s, fade out 0.8s; setAmbientEnabled 反复切换不串流.
  function startAmbient() {
    if (!_ambientEnabled) return;
    if (_ambientRunning) return;
    if (!initCtx()) return;
    resumeIfSuspended();
    _ambientRunning = true;
    var now = ctx.currentTime;
    // 两层 sine + LFO
    [55, 82.5].forEach(function (f, i) {
      var o = ctx.createOscillator();
      o.type = 'sine';
      o.frequency.value = f;
      var g = ctx.createGain();
      g.gain.value = 0.5;
      o.connect(g);
      g.connect(ambientGain);
      var lfo = ctx.createOscillator();
      lfo.type = 'sine';
      lfo.frequency.value = 0.3 + i * 0.13;
      var lfoAmp = ctx.createGain();
      lfoAmp.gain.value = 0.1;
      lfo.connect(lfoAmp);
      lfoAmp.connect(g.gain);
      o.start(now);
      lfo.start(now);
      _ambientSources.push(o, lfo);
    });
    // 地板白噪声
    var n = ctx.createBufferSource();
    n.buffer = makeNoiseBuffer(2.0);
    n.loop = true;
    var nf = ctx.createBiquadFilter();
    nf.type = 'lowpass';
    nf.frequency.value = 200;
    var ng = ctx.createGain();
    ng.gain.value = 0.12;
    n.connect(nf); nf.connect(ng); ng.connect(ambientGain);
    n.start(now);
    _ambientSources.push(n);
    // fade in
    ambientGain.gain.cancelScheduledValues(now);
    ambientGain.gain.setValueAtTime(0.0001, now);
    ambientGain.gain.linearRampToValueAtTime(0.05, now + 1.5);
  }

  function stopAmbient() {
    if (!_ambientRunning || !ctx) return;
    _ambientRunning = false;
    var now = ctx.currentTime;
    ambientGain.gain.cancelScheduledValues(now);
    ambientGain.gain.setValueAtTime(ambientGain.gain.value, now);
    ambientGain.gain.linearRampToValueAtTime(0, now + 0.8);
    var srcs = _ambientSources.slice();
    _ambientSources.length = 0;
    setTimeout(function () {
      srcs.forEach(function (s) { try { s.stop(); } catch (e) {} });
    }, 900);
  }

  // ── 开关 ──

  function setSfxEnabled(flag) { _sfxEnabled = !!flag; }
  function setAmbientEnabled(flag) {
    var on = !!flag;
    if (_ambientEnabled === on) return;
    _ambientEnabled = on;
    if (on) startAmbient();
    else stopAmbient();
  }

  window.BootstrapAudio = {
    init: initCtx,
    resume: resumeIfSuspended,
    playHover: playHover,
    playClick: playClick,
    playSelect: playSelect,
    playConfirm: playConfirm,
    playCancel: playCancel,
    playError: playError,
    playReady: playReady,
    startAmbient: startAmbient,
    stopAmbient: stopAmbient,
    setSfxEnabled: setSfxEnabled,
    setAmbientEnabled: setAmbientEnabled,
    isSfxEnabled: function () { return _sfxEnabled; },
    isAmbientEnabled: function () { return _ambientEnabled; }
  };
})();
