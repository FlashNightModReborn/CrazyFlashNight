var LockboxAudio = (function() {
    'use strict';

    var _ctx = null;
    var _master = null;
    var _wet = null;
    var _reverb = null;
    var _delay = null;
    var _delayFb = null;
    var _noiseBuffer = null;
    var _enabled = true;
    var _muted = false;
    var _lastTapAt = 0;
    var _ambient = null;
    var _heartbeat = null;
    var _traceBed = null;
    var _voices = [];
    var _voiceSeq = 0;
    var TOKEN_FREQS = [660, 494, 740, 392, 880];
    var MASTER_VOL = 0.32;
    var WET_VOL = 0.35;
    var DELAY_FB_VOL = 0.32;

    function ctx() {
        if (_ctx) return _ctx;
        var Ctor = window.AudioContext || window.webkitAudioContext;
        if (!Ctor) { _enabled = false; return null; }
        try {
            _ctx = new Ctor();
            buildBus();
        } catch (e) {
            _enabled = false;
            return null;
        }
        return _ctx;
    }

    function buildBus() {
        _master = _ctx.createGain();
        _master.gain.value = _muted ? 0.0001 : MASTER_VOL;
        _master.connect(_ctx.destination);

        _wet = _ctx.createGain();
        _wet.gain.value = _muted ? 0.0001 : WET_VOL;
        _wet.connect(_master);

        _delay = _ctx.createDelay(1.0);
        _delay.delayTime.value = 0.22;
        _delayFb = _ctx.createGain();
        _delayFb.gain.value = _muted ? 0.0001 : DELAY_FB_VOL;
        _delay.connect(_delayFb);
        _delayFb.connect(_delay);
        _delay.connect(_wet);

        _reverb = _ctx.createConvolver();
        _reverb.buffer = buildImpulse(1.6, 2.4);
        _reverb.connect(_wet);
    }

    function buildImpulse(seconds, decay) {
        var rate = _ctx.sampleRate;
        var len = Math.floor(rate * seconds);
        var buf = _ctx.createBuffer(2, len, rate);
        for (var ch = 0; ch < 2; ch++) {
            var data = buf.getChannelData(ch);
            for (var i = 0; i < len; i++) {
                var t = i / len;
                data[i] = (Math.random() * 2 - 1) * Math.pow(1 - t, decay);
            }
        }
        return buf;
    }

    function noiseBuffer() {
        if (_noiseBuffer || !_ctx) return _noiseBuffer;
        var size = _ctx.sampleRate * 1.2;
        _noiseBuffer = _ctx.createBuffer(1, size, _ctx.sampleRate);
        var data = _noiseBuffer.getChannelData(0);
        for (var i = 0; i < size; i++) data[i] = Math.random() * 2 - 1;
        return _noiseBuffer;
    }

    function resume() {
        var c = ctx();
        if (c && c.state === 'suspended') {
            try { c.resume(); } catch (e) {}
        }
    }

    function now() { return _ctx ? _ctx.currentTime : 0; }

    function clearTimer(timerId) {
        if (!timerId || typeof window === 'undefined' || !window.clearTimeout) return;
        window.clearTimeout(timerId);
    }

    function removeVoice(entry) {
        if (!entry) return;
        if (entry.timerId) {
            clearTimer(entry.timerId);
            entry.timerId = 0;
        }
        for (var i = _voices.length - 1; i >= 0; i--) {
            if (_voices[i] === entry) {
                _voices.splice(i, 1);
                break;
            }
        }
    }

    function trackVoice(entry, stopAt) {
        entry.id = ++_voiceSeq;
        entry.stopAt = stopAt;
        _voices.push(entry);
        if (typeof window !== 'undefined' && window.setTimeout && _ctx) {
            var ttlMs = Math.max(90, Math.round((stopAt - _ctx.currentTime) * 1000) + 140);
            entry.timerId = window.setTimeout(function() {
                removeVoice(entry);
            }, ttlMs);
        }
        return entry;
    }

    function scheduleGainRamp(gainNode, target, duration) {
        if (!gainNode || !gainNode.gain || !_ctx) return;
        var t = _ctx.currentTime;
        gainNode.gain.cancelScheduledValues(t);
        gainNode.gain.setValueAtTime(Math.max(0.0001, gainNode.gain.value), t);
        gainNode.gain.linearRampToValueAtTime(Math.max(0.0001, target), t + duration);
    }

    function stopNode(node, when) {
        if (!node) return;
        try { node.stop(when); } catch (e) {}
    }

    function stopVoice(entry, hard) {
        if (!entry || entry.stopped) return;
        entry.stopped = true;
        var t = _ctx ? _ctx.currentTime : 0;
        var fade = hard ? 0.02 : 0.06;
        if (entry.gain && entry.gain.gain && _ctx) {
            entry.gain.gain.cancelScheduledValues(t);
            entry.gain.gain.setValueAtTime(Math.max(0.0001, entry.gain.gain.value), t);
            entry.gain.gain.linearRampToValueAtTime(0.0001, t + fade);
        }
        if (entry.osc) entry.osc.onended = null;
        if (entry.src) entry.src.onended = null;
        stopNode(entry.osc, t + fade + 0.02);
        stopNode(entry.src, t + fade + 0.02);
        removeVoice(entry);
    }

    function clearFxTail() {
        // Always restore to full wet/delay levels (mute gates via _master).
        // Earlier code tied restore to _muted, which left the wet bus at 0.0001
        // after a mute→unmute cycle and killed reverb/delay for the rest of the session.
        if (!_ctx || !_wet || !_delayFb) return;
        var t = _ctx.currentTime;
        _wet.gain.cancelScheduledValues(t);
        _wet.gain.setValueAtTime(Math.max(0.0001, _wet.gain.value), t);
        _wet.gain.linearRampToValueAtTime(0.0001, t + 0.03);
        _wet.gain.linearRampToValueAtTime(WET_VOL, t + 0.16);
        _delayFb.gain.cancelScheduledValues(t);
        _delayFb.gain.setValueAtTime(Math.max(0.0001, _delayFb.gain.value), t);
        _delayFb.gain.linearRampToValueAtTime(0.0001, t + 0.03);
        _delayFb.gain.linearRampToValueAtTime(DELAY_FB_VOL, t + 0.16);
    }

    function resetFxImmediate() {
        // Snap the wet/delay bus back to full level without any ramp-down window.
        // Used before scene climaxes (finalizeRun SFX) so the attack isn't dry.
        if (!_ctx || !_wet || !_delayFb) return;
        var t = _ctx.currentTime;
        _wet.gain.cancelScheduledValues(t);
        _wet.gain.setValueAtTime(WET_VOL, t);
        _delayFb.gain.cancelScheduledValues(t);
        _delayFb.gain.setValueAtTime(DELAY_FB_VOL, t);
    }

    function env(gainParam, t0, attack, hold, release, peak) {
        gainParam.cancelScheduledValues(t0);
        gainParam.setValueAtTime(0.0001, t0);
        gainParam.exponentialRampToValueAtTime(Math.max(0.0002, peak), t0 + attack);
        gainParam.setValueAtTime(Math.max(0.0002, peak), t0 + attack + hold);
        gainParam.exponentialRampToValueAtTime(0.0001, t0 + attack + hold + release);
    }

    function tone(freq, opts) {
        if (!_enabled || _muted) return null;
        var c = ctx(); if (!c) return null;
        opts = opts || {};
        var osc = c.createOscillator();
        var g = c.createGain();
        osc.type = opts.type || 'sine';
        var t0 = opts.at || c.currentTime;
        osc.frequency.setValueAtTime(freq, t0);
        if (opts.sweepTo) {
            osc.frequency.exponentialRampToValueAtTime(
                Math.max(20, opts.sweepTo),
                t0 + (opts.sweepMs || 80) / 1000
            );
        }
        if (opts.detune) osc.detune.setValueAtTime(opts.detune, t0);
        var peak = opts.peak || 0.25;
        var attack = (opts.attackMs || 4) / 1000;
        var hold = (opts.holdMs || 30) / 1000;
        var release = (opts.releaseMs || 120) / 1000;
        env(g.gain, t0, attack, hold, release, peak);
        osc.connect(g);
        g.connect(_master);
        if (opts.wet) {
            var sendG = c.createGain();
            sendG.gain.value = opts.wet;
            g.connect(sendG);
            if (opts.delay !== false) sendG.connect(_delay);
            if (opts.reverb) sendG.connect(_reverb);
        }
        osc.start(t0);
        var stopAt = t0 + attack + hold + release + 0.05;
        osc.stop(stopAt);
        var entry = trackVoice({ osc: osc, gain: g }, stopAt);
        osc.onended = function() { removeVoice(entry); };
        return { osc: osc, gain: g };
    }

    function burst(opts) {
        if (!_enabled || _muted) return;
        var c = ctx(); if (!c) return;
        opts = opts || {};
        var t0 = opts.at || c.currentTime;
        var src = c.createBufferSource();
        src.buffer = noiseBuffer();
        var bp = c.createBiquadFilter();
        bp.type = opts.filter || 'bandpass';
        bp.frequency.setValueAtTime(opts.freq || 1800, t0);
        if (opts.sweepTo) bp.frequency.exponentialRampToValueAtTime(Math.max(40, opts.sweepTo), t0 + (opts.sweepMs || 200) / 1000);
        bp.Q.value = opts.q || 1.2;
        var g = c.createGain();
        var peak = opts.peak || 0.22;
        var attack = (opts.attackMs || 2) / 1000;
        var hold = (opts.holdMs || 10) / 1000;
        var release = (opts.releaseMs || 120) / 1000;
        env(g.gain, t0, attack, hold, release, peak);
        src.connect(bp);
        bp.connect(g);
        g.connect(_master);
        if (opts.wet) {
            var sendG = c.createGain();
            sendG.gain.value = opts.wet;
            g.connect(sendG);
            if (opts.delay !== false) sendG.connect(_delay);
            if (opts.reverb) sendG.connect(_reverb);
        }
        src.start(t0);
        var stopAt = t0 + attack + hold + release + 0.05;
        src.stop(stopAt);
        var entry = trackVoice({ src: src, gain: g }, stopAt);
        src.onended = function() { removeVoice(entry); };
    }

    function chord(freqs, opts) {
        for (var i = 0; i < freqs.length; i++) tone(freqs[i], opts);
    }

    function arp(freqs, stepMs, opts) {
        var c = ctx(); if (!c) return;
        var base = c.currentTime;
        for (var i = 0; i < freqs.length; i++) {
            var local = Object.assign({}, opts, { at: base + (i * stepMs) / 1000 });
            tone(freqs[i], local);
        }
    }

    function startAmbient() {
        if (!_enabled || _muted) return;
        var c = ctx(); if (!c) return;
        stopAmbient();
        var t0 = c.currentTime;

        var oscA = c.createOscillator();
        oscA.type = 'sawtooth';
        oscA.frequency.setValueAtTime(55, t0);
        var oscB = c.createOscillator();
        oscB.type = 'sawtooth';
        oscB.frequency.setValueAtTime(55, t0);
        oscB.detune.setValueAtTime(-9, t0);
        var oscC = c.createOscillator();
        oscC.type = 'sine';
        oscC.frequency.setValueAtTime(110, t0);

        var lpf = c.createBiquadFilter();
        lpf.type = 'lowpass';
        lpf.frequency.setValueAtTime(420, t0);
        lpf.Q.value = 4;

        var lfo = c.createOscillator();
        lfo.frequency.value = 0.45;
        var lfoGain = c.createGain();
        lfoGain.gain.value = 140;
        lfo.connect(lfoGain);
        lfoGain.connect(lpf.frequency);

        var g = c.createGain();
        g.gain.setValueAtTime(0.0001, t0);
        g.gain.exponentialRampToValueAtTime(0.05, t0 + 0.8);

        oscA.connect(lpf); oscB.connect(lpf); oscC.connect(lpf);
        lpf.connect(g);
        g.connect(_master);

        oscA.start(t0); oscB.start(t0); oscC.start(t0); lfo.start(t0);
        _ambient = { oscs: [oscA, oscB, oscC, lfo], gain: g, filter: lpf };
    }

    function setAmbientTension(tension) {
        if (!_ambient || !_ctx) return;
        var t = _ctx.currentTime;
        var cutoff = 420 + tension * 1200;
        var vol = 0.05 + tension * 0.07;
        _ambient.filter.frequency.cancelScheduledValues(t);
        _ambient.filter.frequency.linearRampToValueAtTime(cutoff, t + 0.2);
        _ambient.gain.gain.cancelScheduledValues(t);
        _ambient.gain.gain.linearRampToValueAtTime(vol, t + 0.2);
    }

    function stopAmbient() {
        if (!_ambient || !_ctx) return;
        var t = _ctx.currentTime;
        var amb = _ambient;
        _ambient = null;
        amb.gain.gain.cancelScheduledValues(t);
        amb.gain.gain.setValueAtTime(amb.gain.gain.value || 0.05, t);
        amb.gain.gain.exponentialRampToValueAtTime(0.0001, t + 0.4);
        setTimeout(function() {
            try {
                for (var i = 0; i < amb.oscs.length; i++) amb.oscs[i].stop();
            } catch (e) {}
        }, 500);
    }

    function startHeartbeat() {
        if (_heartbeat) return;
        _heartbeat = { lastAt: 0, intensity: 0 };
    }

    function tickHeartbeat(pct) {
        if (!_heartbeat || !_ctx) return;
        var bpm = 60 + pct * 120;
        var period = 60 / bpm;
        var t = _ctx.currentTime;
        if (t - _heartbeat.lastAt < period) return;
        _heartbeat.lastAt = t;
        var freq = 110 + pct * 90;
        tone(freq, { type: 'sine', attackMs: 2, holdMs: 18, releaseMs: 120, peak: 0.12 + pct * 0.1, wet: 0.3, reverb: true });
        tone(freq * 0.5, { type: 'sine', attackMs: 2, holdMs: 30, releaseMs: 160, peak: 0.18 });
    }

    function stopHeartbeat() {
        _heartbeat = null;
    }

    function startTraceBed() {
        if (!_enabled || _muted) return;
        var c = ctx(); if (!c || _traceBed) return;
        var t0 = c.currentTime;

        var carrier = c.createOscillator();
        carrier.type = 'sawtooth';
        carrier.frequency.setValueAtTime(118, t0);
        var sub = c.createOscillator();
        sub.type = 'square';
        sub.frequency.setValueAtTime(59, t0);

        var pitchLfo = c.createOscillator();
        pitchLfo.frequency.setValueAtTime(4.5, t0);
        var pitchAmt = c.createGain();
        pitchAmt.gain.setValueAtTime(2, t0);
        pitchLfo.connect(pitchAmt);
        pitchAmt.connect(carrier.detune);

        var noise = c.createBufferSource();
        noise.buffer = noiseBuffer();
        noise.loop = true;
        var noiseFilter = c.createBiquadFilter();
        noiseFilter.type = 'bandpass';
        noiseFilter.frequency.setValueAtTime(1400, t0);
        noiseFilter.Q.value = 2.8;

        var mainGain = c.createGain();
        mainGain.gain.setValueAtTime(0.0001, t0);
        var noiseGain = c.createGain();
        noiseGain.gain.setValueAtTime(0.0001, t0);
        var sendGain = c.createGain();
        sendGain.gain.setValueAtTime(0.18, t0);

        carrier.connect(mainGain);
        sub.connect(mainGain);
        noise.connect(noiseFilter);
        noiseFilter.connect(noiseGain);
        mainGain.connect(_master);
        noiseGain.connect(_master);
        mainGain.connect(sendGain);
        noiseGain.connect(sendGain);
        sendGain.connect(_delay);

        carrier.start(t0);
        sub.start(t0);
        pitchLfo.start(t0);
        noise.start(t0);

        _traceBed = {
            carrier: carrier,
            sub: sub,
            pitchLfo: pitchLfo,
            pitchAmt: pitchAmt,
            noise: noise,
            noiseFilter: noiseFilter,
            mainGain: mainGain,
            noiseGain: noiseGain,
            sendGain: sendGain
        };
    }

    function setTraceBedIntensity(traceValue) {
        if (!_ctx) return;
        if (_muted || traceValue < 0.72) {
            stopTraceBed();
            return;
        }
        if (!_traceBed) startTraceBed();
        if (!_traceBed) return;

        var t = _ctx.currentTime;
        var scaled = Math.max(0, Math.min(1, (traceValue - 0.72) / 0.28));
        _traceBed.mainGain.gain.cancelScheduledValues(t);
        _traceBed.mainGain.gain.linearRampToValueAtTime(0.024 + scaled * 0.11, t + 0.08);
        _traceBed.noiseGain.gain.cancelScheduledValues(t);
        _traceBed.noiseGain.gain.linearRampToValueAtTime(0.004 + scaled * 0.075, t + 0.08);
        _traceBed.noiseFilter.frequency.cancelScheduledValues(t);
        _traceBed.noiseFilter.frequency.linearRampToValueAtTime(1200 + scaled * 3200, t + 0.08);
        _traceBed.pitchAmt.gain.cancelScheduledValues(t);
        _traceBed.pitchAmt.gain.linearRampToValueAtTime(2 + scaled * 26, t + 0.08);
        _traceBed.carrier.frequency.cancelScheduledValues(t);
        _traceBed.carrier.frequency.linearRampToValueAtTime(118 + scaled * 124, t + 0.08);
        _traceBed.sub.frequency.cancelScheduledValues(t);
        _traceBed.sub.frequency.linearRampToValueAtTime(59 + scaled * 58, t + 0.08);
    }

    function stopTraceBed() {
        if (!_traceBed || !_ctx) return;
        var t = _ctx.currentTime;
        var bed = _traceBed;
        _traceBed = null;
        scheduleGainRamp(bed.mainGain, 0.0001, 0.14);
        scheduleGainRamp(bed.noiseGain, 0.0001, 0.14);
        stopNode(bed.carrier, t + 0.18);
        stopNode(bed.sub, t + 0.18);
        stopNode(bed.pitchLfo, t + 0.18);
        stopNode(bed.noise, t + 0.18);
    }

    var _outroHum = null;
    function startOutroHum(opts) {
        // Dead-air bed after a result: a 40-60Hz hum with filtered vinyl-noise
        // crackle, fades in over 0.8s and out over 4s so it doesn't fight the
        // result SFX tail but still gives the "equipment still powered" feel.
        if (!_enabled || _muted) return;
        var c = ctx(); if (!c) return;
        stopOutroHum();
        opts = opts || {};
        var t0 = c.currentTime;
        var duration = opts.duration || 6.0;
        var tone1 = c.createOscillator();
        tone1.type = 'sine';
        tone1.frequency.setValueAtTime(opts.tone === 'warm' ? 62 : 48, t0);
        var tone2 = c.createOscillator();
        tone2.type = 'sine';
        tone2.frequency.setValueAtTime(opts.tone === 'warm' ? 93 : 72, t0);
        tone2.detune.setValueAtTime(-6, t0);
        var crackle = c.createBufferSource();
        crackle.buffer = noiseBuffer();
        crackle.loop = true;
        var crackleBp = c.createBiquadFilter();
        crackleBp.type = 'bandpass';
        crackleBp.frequency.setValueAtTime(opts.tone === 'warm' ? 2400 : 3200, t0);
        crackleBp.Q.value = 1.6;
        var toneGain = c.createGain();
        toneGain.gain.setValueAtTime(0.0001, t0);
        toneGain.gain.linearRampToValueAtTime(opts.tone === 'warm' ? 0.09 : 0.07, t0 + 0.8);
        toneGain.gain.linearRampToValueAtTime(0.0001, t0 + duration);
        var crackleGain = c.createGain();
        crackleGain.gain.setValueAtTime(0.0001, t0);
        crackleGain.gain.linearRampToValueAtTime(0.02, t0 + 0.8);
        crackleGain.gain.linearRampToValueAtTime(0.0001, t0 + duration);
        tone1.connect(toneGain);
        tone2.connect(toneGain);
        crackle.connect(crackleBp);
        crackleBp.connect(crackleGain);
        toneGain.connect(_master);
        crackleGain.connect(_master);
        var wetSend = c.createGain();
        wetSend.gain.value = 0.2;
        toneGain.connect(wetSend);
        wetSend.connect(_reverb);
        tone1.start(t0);
        tone2.start(t0);
        crackle.start(t0);
        stopNode(tone1, t0 + duration + 0.2);
        stopNode(tone2, t0 + duration + 0.2);
        stopNode(crackle, t0 + duration + 0.2);
        _outroHum = { tone1: tone1, tone2: tone2, crackle: crackle, toneGain: toneGain, crackleGain: crackleGain };
    }

    function stopOutroHum() {
        if (!_outroHum || !_ctx) return;
        var t = _ctx.currentTime;
        var h = _outroHum;
        _outroHum = null;
        scheduleGainRamp(h.toneGain, 0.0001, 0.16);
        scheduleGainRamp(h.crackleGain, 0.0001, 0.16);
        stopNode(h.tone1, t + 0.2);
        stopNode(h.tone2, t + 0.2);
        stopNode(h.crackle, t + 0.2);
    }

    var SFX = {
        tapLegal: function(meta) {
            var t = performance.now();
            if (t - _lastTapAt < 24) return;
            _lastTapAt = t;
            var tokenId = meta && typeof meta.tokenId === 'number' ? meta.tokenId : 0;
            var base = TOKEN_FREQS[tokenId % TOKEN_FREQS.length];
            tone(base, { type: 'triangle', attackMs: 2, holdMs: 12, releaseMs: 100, peak: 0.2, wet: 0.25, reverb: true });
            tone(base * 2, { type: 'sine', attackMs: 2, holdMs: 6, releaseMs: 60, peak: 0.06 });
            burst({ freq: base * 3, q: 8, attackMs: 1, holdMs: 8, releaseMs: 60, peak: 0.04 });
        },
        illegalGrace: function() {
            tone(180, { type: 'square', attackMs: 2, holdMs: 10, releaseMs: 90, peak: 0.16, sweepTo: 120, sweepMs: 90 });
            burst({ freq: 900, q: 0.8, attackMs: 2, holdMs: 8, releaseMs: 80, peak: 0.08 });
        },
        illegalPulse: function() {
            tone(110, { type: 'sawtooth', attackMs: 2, holdMs: 20, releaseMs: 260, peak: 0.3, sweepTo: 48, sweepMs: 260, wet: 0.3 });
            burst({ freq: 600, q: 0.6, attackMs: 2, holdMs: 30, releaseMs: 280, peak: 0.24, sweepTo: 200, sweepMs: 280 });
            tone(55, { type: 'sine', attackMs: 2, holdMs: 40, releaseMs: 200, peak: 0.2 });
        },
        seqMatch: function(meta) {
            var which = meta && meta.which;
            var base = which === 'B' ? 880 : 740;
            var t0 = _ctx ? _ctx.currentTime : 0;
            tone(base, { at: t0, type: 'triangle', attackMs: 2, holdMs: 24, releaseMs: 180, peak: 0.2, wet: 0.45, reverb: true });
            tone(base * 1.5, { at: t0 + 0.05, type: 'sine', attackMs: 2, holdMs: 18, releaseMs: 160, peak: 0.12, wet: 0.45, reverb: true });
            burst({ at: t0, freq: base * 4, q: 8, attackMs: 1, holdMs: 14, releaseMs: 120, peak: 0.08, wet: 0.4, reverb: true });
        },
        mainSolved: function() {
            arp([523, 659, 784, 1047], 55, { type: 'triangle', attackMs: 3, holdMs: 35, releaseMs: 200, peak: 0.2, wet: 0.4, reverb: true });
            tone(131, { type: 'sine', attackMs: 4, holdMs: 80, releaseMs: 320, peak: 0.18 });
        },
        bonusSolved: function() {
            chord([784, 988, 1175, 1568], { type: 'triangle', attackMs: 4, holdMs: 60, releaseMs: 380, peak: 0.14, wet: 0.45, reverb: true });
            burst({ freq: 6000, q: 12, attackMs: 2, holdMs: 20, releaseMs: 180, peak: 0.08, wet: 0.3, reverb: true });
        },
        bonusLock: function() {
            tone(220, { type: 'sawtooth', attackMs: 6, holdMs: 80, releaseMs: 420, peak: 0.2, sweepTo: 110, sweepMs: 460, wet: 0.3 });
            burst({ freq: 2400, q: 4, attackMs: 4, holdMs: 40, releaseMs: 280, peak: 0.12, wet: 0.3, reverb: true });
            tone(330, { type: 'square', attackMs: 4, holdMs: 40, releaseMs: 180, peak: 0.08 });
        },
        finisherArm: function() {
            tone(220, { type: 'sawtooth', attackMs: 8, holdMs: 100, releaseMs: 320, peak: 0.22, sweepTo: 440, sweepMs: 340, wet: 0.4, reverb: true });
            tone(440, { type: 'sine', attackMs: 8, holdMs: 80, releaseMs: 260, peak: 0.12, sweepTo: 660, sweepMs: 280 });
            burst({ freq: 800, q: 1, attackMs: 4, holdMs: 40, releaseMs: 320, peak: 0.15, wet: 0.4, reverb: true });
        },
        inject: function() {
            tone(110, { type: 'sawtooth', attackMs: 4, holdMs: 40, releaseMs: 280, peak: 0.22, sweepTo: 330, sweepMs: 260 });
            tone(55, { type: 'sine', attackMs: 4, holdMs: 100, releaseMs: 320, peak: 0.24 });
            burst({ freq: 1600, q: 2, attackMs: 2, holdMs: 20, releaseMs: 200, peak: 0.14, sweepTo: 4000, sweepMs: 220, wet: 0.4, reverb: true });
        },
        traceTick: function(meta) {
            var level = (meta && meta.level) || 0;
            var freq = 1200 + level * 260;
            tone(freq, { type: 'square', attackMs: 1, holdMs: 6, releaseMs: 60, peak: 0.06 + level * 0.015, wet: 0.35, delay: true });
        },
        traceCritical: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(440, { at: t0, type: 'square', attackMs: 3, holdMs: 40, releaseMs: 140, peak: 0.18, sweepTo: 880, sweepMs: 180, wet: 0.35, reverb: true });
            tone(220, { at: t0 + 0.2, type: 'sawtooth', attackMs: 3, holdMs: 60, releaseMs: 200, peak: 0.2, sweepTo: 110, sweepMs: 220 });
            burst({ at: t0, freq: 3000, q: 6, attackMs: 2, holdMs: 40, releaseMs: 220, peak: 0.1, wet: 0.4, reverb: true });
        },
        traceTerminal: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(330, { at: t0, type: 'sawtooth', attackMs: 4, holdMs: 110, releaseMs: 420, peak: 0.18, sweepTo: 660, sweepMs: 340, wet: 0.4, reverb: true });
            tone(165, { at: t0, type: 'square', attackMs: 2, holdMs: 80, releaseMs: 260, peak: 0.18, sweepTo: 82, sweepMs: 280 });
            tone(1320, { at: t0 + 0.08, type: 'square', attackMs: 1, holdMs: 28, releaseMs: 140, peak: 0.12, wet: 0.35, delay: true });
            tone(1760, { at: t0 + 0.15, type: 'square', attackMs: 1, holdMs: 24, releaseMs: 120, peak: 0.1, wet: 0.35, delay: true });
            burst({ at: t0, freq: 4600, q: 9, attackMs: 1, holdMs: 34, releaseMs: 220, peak: 0.12, wet: 0.45, reverb: true });
        },
        finisherHoldPulse: function(meta) {
            var pct = (meta && meta.pct) || 0;
            var freq = 220 + pct * 660;
            var t0 = _ctx ? _ctx.currentTime : 0;
            tone(freq, { at: t0, type: 'sine', attackMs: 2, holdMs: 14, releaseMs: 110, peak: 0.09 + pct * 0.08, wet: 0.25, reverb: true });
            tone(freq * 2, { at: t0 + 0.018, type: 'triangle', attackMs: 1, holdMs: 10, releaseMs: 90, peak: 0.05 + pct * 0.04, wet: 0.2, delay: true });
        },
        finisherSweetCue: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(988, { at: t0, type: 'triangle', attackMs: 2, holdMs: 26, releaseMs: 200, peak: 0.16, wet: 0.55, reverb: true });
            tone(1480, { at: t0 + 0.03, type: 'sine', attackMs: 1, holdMs: 24, releaseMs: 180, peak: 0.12, wet: 0.55, reverb: true });
            burst({ at: t0, freq: 4200, q: 8, attackMs: 1, holdMs: 20, releaseMs: 180, peak: 0.08, wet: 0.45, reverb: true });
        },
        finisherDanger: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(330, { at: t0, type: 'square', attackMs: 1, holdMs: 20, releaseMs: 160, peak: 0.14, sweepTo: 220, sweepMs: 180, wet: 0.28, delay: true });
            tone(165, { at: t0 + 0.045, type: 'square', attackMs: 1, holdMs: 18, releaseMs: 180, peak: 0.12, sweepTo: 110, sweepMs: 180 });
            burst({ at: t0, freq: 1800, q: 3, attackMs: 1, holdMs: 28, releaseMs: 170, peak: 0.08 });
        },
        finishPerfect: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(41, { at: t0, type: 'sine', attackMs: 8, holdMs: 180, releaseMs: 620, peak: 0.45 });
            tone(55, { at: t0, type: 'sine', attackMs: 6, holdMs: 160, releaseMs: 520, peak: 0.3, sweepTo: 82, sweepMs: 420 });
            tone(220, { at: t0, type: 'sawtooth', attackMs: 4, holdMs: 120, releaseMs: 460, peak: 0.2, detune: -12, wet: 0.5, reverb: true });
            tone(220, { at: t0, type: 'sawtooth', attackMs: 4, holdMs: 120, releaseMs: 460, peak: 0.2, detune: 12, wet: 0.5, reverb: true });
            tone(440, { at: t0, type: 'triangle', attackMs: 4, holdMs: 140, releaseMs: 520, peak: 0.22, wet: 0.45, reverb: true });
            tone(660, { at: t0 + 0.04, type: 'triangle', attackMs: 4, holdMs: 120, releaseMs: 520, peak: 0.18, wet: 0.45, reverb: true });
            tone(880, { at: t0 + 0.08, type: 'triangle', attackMs: 4, holdMs: 120, releaseMs: 560, peak: 0.16, wet: 0.45, reverb: true });
            burst({ at: t0, freq: 6000, q: 0.3, attackMs: 2, holdMs: 60, releaseMs: 520, peak: 0.22, sweepTo: 1800, sweepMs: 560, wet: 0.6, reverb: true });
            burst({ at: t0, freq: 150, q: 0.8, attackMs: 1, holdMs: 10, releaseMs: 240, peak: 0.3 });
            var sparkle = [1319, 1760, 2093, 2637, 3136, 3520];
            for (var i = 0; i < sparkle.length; i++) {
                tone(sparkle[i], { at: t0 + 0.08 + i * 0.06, type: 'sine', attackMs: 2, holdMs: 20, releaseMs: 260, peak: 0.14, wet: 0.6, reverb: true });
            }
            tone(110, { at: t0 + 0.4, type: 'sine', attackMs: 6, holdMs: 140, releaseMs: 680, peak: 0.22, wet: 0.5, reverb: true });
            tone(165, { at: t0 + 0.4, type: 'sine', attackMs: 6, holdMs: 140, releaseMs: 680, peak: 0.2, wet: 0.5, reverb: true });
            tone(220, { at: t0 + 0.4, type: 'sine', attackMs: 6, holdMs: 160, releaseMs: 720, peak: 0.2, wet: 0.5, reverb: true });
        },
        finishGood: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(55, { at: t0, type: 'sine', attackMs: 6, holdMs: 80, releaseMs: 320, peak: 0.28 });
            tone(220, { at: t0, type: 'triangle', attackMs: 4, holdMs: 80, releaseMs: 280, peak: 0.2, wet: 0.4, reverb: true });
            arp([440, 554, 659, 880], 55, { type: 'triangle', attackMs: 3, holdMs: 35, releaseMs: 240, peak: 0.2, wet: 0.45, reverb: true });
            burst({ at: t0, freq: 3200, q: 1, attackMs: 2, holdMs: 40, releaseMs: 280, peak: 0.14, wet: 0.4, reverb: true });
        },
        finishMiss: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(330, { at: t0, type: 'triangle', attackMs: 3, holdMs: 60, releaseMs: 260, peak: 0.22, sweepTo: 220, sweepMs: 280, wet: 0.35, reverb: true });
            tone(82, { at: t0, type: 'sine', attackMs: 4, holdMs: 80, releaseMs: 260, peak: 0.24 });
            burst({ at: t0, freq: 600, q: 0.5, attackMs: 4, holdMs: 60, releaseMs: 240, peak: 0.14 });
        },
        fail: function() {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            tone(196, { at: t0, type: 'sawtooth', attackMs: 4, holdMs: 100, releaseMs: 520, peak: 0.32, sweepTo: 55, sweepMs: 560, wet: 0.4, reverb: true });
            tone(98, { at: t0, type: 'sawtooth', attackMs: 4, holdMs: 100, releaseMs: 520, peak: 0.28, sweepTo: 27, sweepMs: 560 });
            burst({ at: t0, freq: 400, q: 0.4, attackMs: 4, holdMs: 120, releaseMs: 480, peak: 0.25, sweepTo: 80, sweepMs: 520 });
            tone(65, { at: t0 + 0.5, type: 'sine', attackMs: 6, holdMs: 240, releaseMs: 680, peak: 0.3 });
            burst({ at: t0 + 0.1, freq: 2200, q: 0.6, attackMs: 2, holdMs: 20, releaseMs: 160, peak: 0.16, wet: 0.5, reverb: true });
        },
        traceOverload: function(meta) {
            var c = ctx(); if (!c) return;
            var t0 = c.currentTime;
            var success = meta && meta.outcome === 'partial_success';
            tone(36, { at: t0, type: 'sine', attackMs: 2, holdMs: 180, releaseMs: 780, peak: 0.48, wet: 0.45, reverb: true });
            tone(72, { at: t0, type: 'sawtooth', attackMs: 2, holdMs: 140, releaseMs: 620, peak: 0.26, sweepTo: success ? 96 : 34, sweepMs: 520, wet: 0.45, reverb: true });
            tone(240, { at: t0, type: 'square', attackMs: 2, holdMs: 80, releaseMs: 260, peak: 0.18, sweepTo: 960, sweepMs: 220, wet: 0.35, delay: true });
            burst({ at: t0, freq: 140, q: 0.8, attackMs: 1, holdMs: 24, releaseMs: 320, peak: 0.36 });
            burst({ at: t0, freq: 5600, q: 0.45, attackMs: 1, holdMs: 80, releaseMs: 620, peak: 0.25, sweepTo: 800, sweepMs: 700, wet: 0.65, reverb: true });
            var shards = success ? [1175, 1397, 1760, 2093, 2637, 3136] : [988, 880, 784, 659, 523, 392];
            for (var i = 0; i < shards.length; i++) {
                tone(shards[i], {
                    at: t0 + 0.06 + i * 0.05,
                    type: success ? 'triangle' : 'square',
                    attackMs: 2,
                    holdMs: 18,
                    releaseMs: 220,
                    peak: success ? 0.16 : 0.12,
                    wet: 0.5,
                    reverb: true
                });
            }
            if (success) {
                tone(196, { at: t0 + 0.32, type: 'sine', attackMs: 4, holdMs: 160, releaseMs: 720, peak: 0.2, wet: 0.6, reverb: true });
                tone(247, { at: t0 + 0.32, type: 'sine', attackMs: 4, holdMs: 160, releaseMs: 720, peak: 0.18, wet: 0.6, reverb: true });
                tone(392, { at: t0 + 0.32, type: 'triangle', attackMs: 4, holdMs: 140, releaseMs: 680, peak: 0.16, wet: 0.55, reverb: true });
            } else {
                tone(156, { at: t0 + 0.26, type: 'sawtooth', attackMs: 3, holdMs: 140, releaseMs: 520, peak: 0.16, sweepTo: 52, sweepMs: 420, wet: 0.45 });
                tone(104, { at: t0 + 0.34, type: 'sine', attackMs: 3, holdMs: 120, releaseMs: 540, peak: 0.18 });
            }
        }
    };

    function play(name, meta) {
        if (!_enabled || _muted) return;
        resume();
        var fn = SFX[name];
        if (fn) fn(meta);
    }

    function stopAll(hard, opts) {
        // opts.keepFx = true  → don't touch wet/delay bus (use before climax SFX
        //                        so its initial reverb attack isn't swallowed by the
        //                        30ms dip clearFxTail introduces).
        // default behavior  → dip+restore wet/delay to flush echo carryover.
        if (!_ctx) return;
        stopAmbient();
        stopHeartbeat();
        stopTraceBed();
        stopOutroHum();
        var voices = _voices.slice();
        for (var i = 0; i < voices.length; i++) stopVoice(voices[i], hard !== false);
        _voices.length = 0;
        if (opts && opts.keepFx) {
            resetFxImmediate();
        } else {
            clearFxTail();
        }
    }

    function setMuted(m) {
        _muted = !!m;
        if (_muted) {
            stopAll(true);
        }
        if (_master && _ctx) {
            var t = _ctx.currentTime;
            _master.gain.cancelScheduledValues(t);
            _master.gain.setValueAtTime(Math.max(0.0001, _master.gain.value), t);
            _master.gain.linearRampToValueAtTime(_muted ? 0.0001 : MASTER_VOL, t + 0.03);
        }
    }
    function isMuted() { return _muted; }

    return {
        play: play,
        resume: resume,
        setMuted: setMuted,
        isMuted: isMuted,
        startAmbient: startAmbient,
        stopAmbient: stopAmbient,
        setAmbientTension: setAmbientTension,
        setTraceBedIntensity: setTraceBedIntensity,
        stopTraceBed: stopTraceBed,
        startHeartbeat: startHeartbeat,
        tickHeartbeat: tickHeartbeat,
        stopHeartbeat: stopHeartbeat,
        startOutroHum: startOutroHum,
        stopOutroHum: stopOutroHum,
        stopAll: stopAll
    };
})();
