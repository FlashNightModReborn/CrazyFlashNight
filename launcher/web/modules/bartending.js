/** 调酒吧台 — 赛博朋克酒保风格界面（VA-11 Hall-A 纯正硬核调酒模式），独立于合成工作台。
 *  左列：Drinktionary 只读酒单手册——支持「按名称 / 按口味 / 按种类 / 瓶装饮品」四页签浏览，
 *        点选任意酒品翻开其只读配方与风味详情页（不自动代填原料，保留纯正手动调酒体验），
 *        隐藏特调「烈焰摩艾」在首次成功调制或已持有前以机密页呈现。
 *  右列：VA-11 吧台操作台——五色化学提取物分配器（艾德海德/布朗森/德尔塔/弗拉内吉/卡莫特林）、
 *        栏位 1 / 栏位 2 双 10 格（共 20 格）液位矩阵、加冰/陈化开关、
 *        5 秒实时计时摇壶（点击「调制」起摇：<5s 轻摇 Mix，≥5s 剧烈震动变猛摇 Blend，点「停止」开壶揭晓；
 *        或点「直调」免摇开壶）。
 *  开壶揭晓：
 *    - 命中合法配方：在出杯台揭晓酒品并发起 AS2 CraftingRuntime preview，就绪后可点「上酒」commit；
 *    - 配方/手法不成立：触发「吧台险情 · 莫洛托夫雏形（酒手雷）」高危爆燃状态与失误诊断，
 *      严禁端上吧台，玩家可点「重做」无损倾倒重调。 */
var BartendingPanel = (function() {
    'use strict';
    var _host = null;
    var _el = null, _statusEl = null, _listEl = null, _stationEl = null,
        _closeButton = null, _moneyEl = null, _kpointsEl = null,
        _tabsEl = null, _chipsEl = null, _resultEl = null,
        _shakerEl = null, _timerFillEl = null, _shakerStateEl = null,
        _shakerHintEl = null, _shakerKickerEl = null, _mixBtnEl = null;
    var _snapshot = null, _spec = null, _specFailed = false,
        _materials = null, _materialsBusy = false;
    var _filter = {tab:'name', value:''};
    var _inspectedIndex = null;
    var _unlockedSecrets = {};
    var _mix = null;
    var _shaking = false, _shakeElapsedMs = 0, _shakeTimerId = null, _shakeLastTick = 0;
    var _shakeStepAccumMs = 0, _shakeStepCount = 0;
    var _lastPouredSlot = '', _lastPouredCellIndex = -1;
    var _audioLog = [];
    var _revealed = false;
    var _matched = null, _preview = null;
    var _busy = false, _previewBusy = false, _generation = 0;
    var _commitFeedback = null;

    var TOTAL_SLOT_MAX = 20;
    var HARD_SHAKE_MS = 5000;
    var SHAKE_TICK_MS = 100;

    var SLOT_META = {
        '艾德海德': {code:'ADL', tone:'adl', flavorTag:'甜基 · Sweet', baseFreq:330.00, wave:'sine'},
        '布朗森提取物': {code:'BRN', tone:'brn', flavorTag:'苦基 · Bitter', baseFreq:277.18, wave:'triangle'},
        '粉末德尔塔': {code:'PWD', tone:'pwd', flavorTag:'酸基 · Sour', baseFreq:392.00, wave:'sine'},
        '弗拉内吉': {code:'FLN', tone:'fln', flavorTag:'辣基 · Spicy', baseFreq:440.00, wave:'sawtooth'},
        '卡莫特林': {code:'KRM', tone:'krm', flavorTag:'酒精 · Alc', baseFreq:523.25, wave:'triangle'}
    };

    var NAME_GROUPS = ['A–F', 'G–M', 'P–Z'];

    /* ── VA-11 Hall-A 程序化 Web Audio 吧台合成器（致敬原作 SOND 音效表，零外部音频依赖）── */
    var _audioCtx = null, _audioMaster = null, _audioNoiseBuf = null;

    function isSfxEnabled() {
        if (typeof window !== 'undefined' && window.BootstrapAudio
                && typeof window.BootstrapAudio.isSfxEnabled === 'function') {
            return !!window.BootstrapAudio.isSfxEnabled();
        }
        return true;
    }

    function recordAudioCue(effect, detail) {
        _audioLog.push({effect:effect, detail:detail || null});
        if (_audioLog.length > 64) _audioLog.shift();
    }

    function ensureAudioCtx() {
        if (!isSfxEnabled()) return null;
        if (_audioCtx) {
            if (_audioCtx.state === 'suspended' && typeof _audioCtx.resume === 'function') {
                try { _audioCtx.resume(); } catch (e) {}
            }
            return _audioCtx;
        }
        var AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);
        if (!AC) return null;
        try {
            _audioCtx = new AC();
            _audioMaster = _audioCtx.createGain();
            _audioMaster.gain.value = 0.42;
            _audioMaster.connect(_audioCtx.destination);
            var sr = _audioCtx.sampleRate;
            _audioNoiseBuf = _audioCtx.createBuffer(1, sr, sr);
            var ch = _audioNoiseBuf.getChannelData(0);
            for (var i = 0; i < sr; i++) ch[i] = Math.random() * 2 - 1;
        } catch (err) {
            _audioCtx = null;
        }
        return _audioCtx;
    }

    function synthTone(f0, f1, type, attack, decay, peak, delaySec, filterSpec) {
        var ctx = ensureAudioCtx();
        if (!ctx || !_audioMaster) return;
        var t0 = ctx.currentTime + (delaySec || 0);
        var osc = ctx.createOscillator();
        var gain = ctx.createGain();
        osc.type = type || 'sine';
        osc.frequency.setValueAtTime(Math.max(20, f0), t0);
        if (f1 && f1 !== f0) {
            osc.frequency.exponentialRampToValueAtTime(Math.max(20, f1), t0 + attack + decay);
        }
        var p = Math.max(0.0001, peak || 0.12);
        gain.gain.setValueAtTime(0.0001, t0);
        gain.gain.exponentialRampToValueAtTime(p, t0 + Math.max(0.002, attack));
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + attack + decay);
        if (filterSpec) {
            var flt = ctx.createBiquadFilter();
            flt.type = filterSpec.type || 'bandpass';
            flt.frequency.setValueAtTime(filterSpec.f0 || 1200, t0);
            if (filterSpec.f1) {
                flt.frequency.exponentialRampToValueAtTime(Math.max(30, filterSpec.f1), t0 + attack + decay);
            }
            flt.Q.value = filterSpec.Q || 2.5;
            osc.connect(flt);
            flt.connect(gain);
        } else {
            osc.connect(gain);
        }
        gain.connect(_audioMaster);
        osc.start(t0);
        osc.stop(t0 + attack + decay + 0.03);
    }

    function synthNoise(attack, decay, peak, filterType, f0, f1, Q, delaySec) {
        var ctx = ensureAudioCtx();
        if (!ctx || !_audioMaster || !_audioNoiseBuf) return;
        var t0 = ctx.currentTime + (delaySec || 0);
        var src = ctx.createBufferSource();
        src.buffer = _audioNoiseBuf;
        var flt = ctx.createBiquadFilter();
        flt.type = filterType || 'bandpass';
        flt.frequency.setValueAtTime(Math.max(30, f0 || 1200), t0);
        if (f1 && f1 !== f0) {
            flt.frequency.exponentialRampToValueAtTime(Math.max(30, f1), t0 + attack + decay);
        }
        flt.Q.value = Q || 2.0;
        var gain = ctx.createGain();
        var p = Math.max(0.0001, peak || 0.08);
        gain.gain.setValueAtTime(0.0001, t0);
        gain.gain.exponentialRampToValueAtTime(p, t0 + Math.max(0.002, attack));
        gain.gain.exponentialRampToValueAtTime(0.0001, t0 + attack + decay);
        src.connect(flt);
        flt.connect(gain);
        gain.connect(_audioMaster);
        src.start(t0);
        src.stop(t0 + attack + decay + 0.03);
    }

    /** 致敬 addingredient.ogg：五色提取物各自拥有独立基频与波形，并随 1→20 格液位阶梯升调 */
    function playIngredientAdd(slotName, newTotal) {
        recordAudioCue('addingredient', {slot:slotName, total:newTotal});
        var meta = SLOT_META[slotName] || SLOT_META['艾德海德'];
        var stepFactor = Math.pow(2, Math.min(20, Math.max(1, newTotal) - 1) / 18);
        var f0 = meta.baseFreq * stepFactor;
        synthTone(f0, f0 * 1.28, meta.wave, 0.005, 0.085, 0.14, 0,
            meta.wave === 'sawtooth' ? {type:'lowpass', f0:f0 * 3.2, f1:f0 * 1.6, Q:3} : null);
        synthTone(f0 * 1.5, f0 * 1.95, 'sine', 0.004, 0.06, 0.06, 0.015);
        synthNoise(0.002, 0.035, 0.045, 'bandpass', 1800 + newTotal * 70, 2600 + newTotal * 80, 4.0, 0);
    }

    /** 抽出 1 份提取物：下行微吸音 */
    function playIngredientRemove(slotName, newTotal) {
        recordAudioCue('removeingredient', {slot:slotName, total:newTotal});
        var meta = SLOT_META[slotName] || SLOT_META['艾德海德'];
        var stepFactor = Math.pow(2, Math.min(20, Math.max(0, newTotal)) / 18);
        var f0 = meta.baseFreq * stepFactor;
        synthTone(f0 * 1.15, f0 * 0.74, 'sine', 0.004, 0.075, 0.10, 0);
        synthNoise(0.003, 0.04, 0.035, 'bandpass', 1600, 900, 3.0, 0);
    }

    /** 致敬 iceadd.ogg：清脆双冰块落入金属壶壁的高频玻璃/冰晶碰撞音 */
    function playIceToggle(isOn) {
        recordAudioCue('iceadd', {on:isOn});
        if (isOn) {
            synthNoise(0.002, 0.035, 0.08, 'highpass', 3200, 2400, 1.8, 0);
            synthTone(2320, 2480, 'sine', 0.003, 0.09, 0.11, 0);
            synthTone(3480, 3160, 'triangle', 0.003, 0.11, 0.09, 0.052);
            synthTone(1760, 1840, 'sine', 0.004, 0.08, 0.06, 0.095);
        } else {
            synthTone(1680, 920, 'sine', 0.005, 0.09, 0.07, 0);
        }
    }

    /** 致敬 ageadd.ogg：怀表发条微咔哒 + 温暖琥珀五度和弦共鸣 */
    function playAgeToggle(isOn) {
        recordAudioCue('ageadd', {on:isOn});
        if (isOn) {
            synthNoise(0.002, 0.022, 0.05, 'bandpass', 2200, 1900, 5.0, 0);
            synthNoise(0.002, 0.022, 0.04, 'bandpass', 2600, 2200, 5.0, 0.065);
            synthTone(293.66, 296.0, 'triangle', 0.018, 0.24, 0.11, 0.02);
            synthTone(440.00, 444.0, 'sine', 0.024, 0.28, 0.09, 0.05);
        } else {
            synthTone(440.00, 261.63, 'triangle', 0.006, 0.11, 0.08, 0);
        }
    }

    /** 致敬 sound3.ogg：摇壶期间连续律动的液体激荡声 + 冰块撞击金属壁声 */
    function playShakeStep(isHard, stepIndex) {
        recordAudioCue('shaketick', {mode:isHard ? 'hard' : 'light', step:stepIndex});
        var upStroke = (stepIndex % 2) === 0;
        var fStart = isHard ? (upStroke ? 1500 : 2100) : (upStroke ? 980 : 1380);
        var fEnd = isHard ? (upStroke ? 2400 : 1350) : (upStroke ? 1520 : 920);
        var dur = isHard ? 0.052 : 0.075;
        synthNoise(0.004, dur, isHard ? 0.095 : 0.068, 'bandpass', fStart, fEnd, 3.2, 0);
        if (_mix && _mix.ice) {
            var iceFreq = upStroke ? 2750 : 3220;
            synthTone(iceFreq, iceFreq * 0.92, 'sine', 0.002, 0.032, isHard ? 0.055 : 0.038, 0.012);
        }
    }

    /** 致敬 mixdone.ogg：满 5.0 秒跨越至【猛摇 Blend】时的标志性三连音合成器提示音 */
    function playBlendCrossover() {
        recordAudioCue('mixdone_blend', {elapsedMs:_shakeElapsedMs});
        synthTone(587.33, 620, 'triangle', 0.005, 0.11, 0.12, 0);
        synthTone(880.00, 920, 'triangle', 0.005, 0.12, 0.12, 0.055);
        synthTone(1174.66, 1240, 'sine', 0.006, 0.20, 0.14, 0.11);
    }

    /** 致敬 opencan.ogg / mixdone.ogg / explosion.ogg：开壶揭晓的三分支音效 */
    function playRevealSound(matched, isSecretUnlock, hazard) {
        if (matched) {
            if (matched.recipe && matched.recipe.bottled) {
                recordAudioCue('opencan', {recipeId:matched.recipe.recipeId});
                synthNoise(0.002, 0.03, 0.11, 'bandpass', 2800, 1600, 4.5, 0);
                synthTone(1420, 860, 'square', 0.002, 0.035, 0.06, 0.01);
                synthNoise(0.015, 0.22, 0.085, 'highpass', 3000, 4200, 1.2, 0.045);
                synthTone(523.25, 659.25, 'sine', 0.008, 0.18, 0.09, 0.08);
                return;
            }
            recordAudioCue('cocktail_reveal', {
                recipeId:matched.recipe.recipeId,
                secret:!!isSecretUnlock
            });
            // 拔开壶盖啵声 + 酒液倾倒声 + 霓虹和弦
            synthTone(190, 460, 'sine', 0.004, 0.055, 0.12, 0);
            synthNoise(0.01, 0.16, 0.06, 'bandpass', 680, 1320, 3.8, 0.04);
            var notes = isSecretUnlock
                ? [523.25, 659.25, 783.99, 1046.50, 1318.51]
                : [523.25, 659.25, 783.99, 987.77];
            for (var i = 0; i < notes.length; i++) {
                synthTone(notes[i], notes[i] * 1.01, 'sine', 0.008, 0.26, 0.08, 0.06 + i * 0.045);
            }
            return;
        }
        // 调配失败 → 莫洛托夫酒手雷险情（引线滋滋声 + 低频爆燃闷响 + 警报三全音）
        recordAudioCue('molotov_explosion', {code:hazard ? hazard.code : 'unknown'});
        synthTone(115, 36, 'sawtooth', 0.008, 0.34, 0.18, 0, {type:'lowpass', f0:340, f1:80, Q:2.0});
        synthNoise(0.005, 0.28, 0.13, 'bandpass', 1900, 520, 2.2, 0.02);
        synthTone(311.13, 293.66, 'triangle', 0.01, 0.18, 0.10, 0.04);
        synthTone(440.00, 415.30, 'triangle', 0.01, 0.22, 0.09, 0.14);
    }

    /** 致敬 glassserve.ogg：酒杯沿吧台木面滑出 + 冰杯轻碰 + 满足和弦 */
    function playGlassServe() {
        recordAudioCue('glassserve', null);
        synthNoise(0.008, 0.14, 0.075, 'bandpass', 1100, 2200, 2.8, 0);
        synthTone(1960, 2080, 'sine', 0.003, 0.07, 0.08, 0.11);
        var chord = [349.23, 440.00, 523.25, 659.25];
        for (var i = 0; i < chord.length; i++) {
            synthTone(chord[i], chord[i] * 1.02, 'sine', 0.008, 0.28, 0.075, 0.12 + i * 0.04);
        }
    }

    /** 致敬 cancel_sound.ogg：点击「重做」将废液/酒手雷倾倒入吧台水槽的排空声 */
    function playResetDrain() {
        recordAudioCue('reset_drain', null);
        synthNoise(0.006, 0.22, 0.09, 'bandpass', 1500, 320, 2.6, 0);
        synthTone(360, 110, 'sine', 0.006, 0.20, 0.10, 0.02);
    }

    /** 致敬 pageturn.wav：酒单手册 Drinktionary 翻页声 */
    function playPageTurn() {
        recordAudioCue('pageturn', null);
        synthNoise(0.003, 0.055, 0.055, 'bandpass', 2400, 1150, 2.4, 0);
        synthTone(680, 840, 'sine', 0.003, 0.045, 0.04, 0.01);
    }

    function mount(shellEl, deps) {
        _host = deps;
        _generation++;
        stopShakeTimerOnly();
        _snapshot = null; _spec = null; _specFailed = false;
        _materials = null; _materialsBusy = false;
        _filter = {tab:'name', value:''};
        _inspectedIndex = null;
        _unlockedSecrets = {};
        _audioLog = [];
        _matched = null; _preview = null;
        _busy = false; _previewBusy = false; _commitFeedback = null;
        resetMix();
        buildDOM();
        if (shellEl) shellEl.appendChild(_el);
        loadSpec();
        refresh();
    }

    function unmount() {
        _generation++;
        stopShakeTimerOnly();
        if (_el && _el.parentNode) _el.parentNode.removeChild(_el);
        _el = null; _host = null; _snapshot = null; _spec = null; _preview = null;
        _materials = null; _matched = null; _mix = null;
        _shakerEl = null; _timerFillEl = null; _shakerStateEl = null;
        _shakerHintEl = null; _shakerKickerEl = null; _mixBtnEl = null;
        _busy = false; _previewBusy = false; _materialsBusy = false;
    }

    function buildDOM() {
        _el = document.createElement('div');
        _el.className = 'bart-panel';

        var header = document.createElement('header');
        header.className = 'bart-header';
        var brand = document.createElement('div');
        brand.className = 'bart-brand';
        brand.innerHTML = '<span class="bart-kicker">VA-11 HALL-A // 堕落城酒吧</span><h1>调酒</h1>';
        _statusEl = document.createElement('div');
        _statusEl.className = 'bart-status';
        _statusEl.textContent = '同步中';
        var metrics = document.createElement('div');
        metrics.className = 'bart-metrics';
        _moneyEl = document.createElement('span');
        _moneyEl.className = 'bart-metric';
        _kpointsEl = document.createElement('span');
        _kpointsEl.className = 'bart-metric kpoints';
        metrics.appendChild(_moneyEl); metrics.appendChild(_kpointsEl);
        _closeButton = document.createElement('button');
        _closeButton.type = 'button';
        _closeButton.className = 'bart-close';
        _closeButton.textContent = '×';
        _closeButton.setAttribute('aria-label', '关闭调酒吧台');
        _closeButton.setAttribute('data-audio-cue', 'back');
        _closeButton.addEventListener('click', function() {
            if (_host && _host.requestClose) _host.requestClose('header');
        });
        header.appendChild(brand); header.appendChild(_statusEl);
        header.appendChild(metrics); header.appendChild(_closeButton);

        var body = document.createElement('div');
        body.className = 'bart-body';

        var browser = document.createElement('div');
        browser.className = 'bart-browser';
        var bookHead = document.createElement('div');
        bookHead.className = 'bart-book-head';
        var bookTitle = document.createElement('span');
        bookTitle.className = 'bart-book-title';
        bookTitle.textContent = 'DRINKTIONARY · 酒单手册';
        var bookSub = document.createElement('span');
        bookSub.className = 'bart-book-sub';
        bookSub.textContent = '只读翻阅 · 手动调配';
        bookHead.appendChild(bookTitle);
        bookHead.appendChild(bookSub);

        _tabsEl = document.createElement('nav');
        _tabsEl.className = 'bart-tabs';
        _tabsEl.setAttribute('aria-label', '名录筛选');
        _chipsEl = document.createElement('div');
        _chipsEl.className = 'bart-chips';
        _listEl = document.createElement('div');
        _listEl.className = 'bart-list';
        browser.appendChild(bookHead);
        browser.appendChild(_tabsEl);
        browser.appendChild(_chipsEl);
        browser.appendChild(_listEl);

        _stationEl = document.createElement('section');
        _stationEl.className = 'bart-station';

        body.appendChild(browser); body.appendChild(_stationEl);
        _el.appendChild(header); _el.appendChild(body);
        renderAll();
    }

    function renderAll() {
        renderTabs(); renderChips(); renderList(); renderStation();
    }

    /* ── 数据装载 ── */

    function slotNames() {
        return _spec && _spec.ingredientSlots ? _spec.ingredientSlots : [];
    }

    function slotTone(name) {
        return SLOT_META[name] ? SLOT_META[name].tone : 'adl';
    }

    function slotCode(name) {
        return SLOT_META[name] ? SLOT_META[name].code : name.slice(0, 2);
    }

    function slotFlavorTag(name) {
        return SLOT_META[name] ? SLOT_META[name].flavorTag : '';
    }

    function resetMix() {
        stopShakeTimerOnly();
        _shaking = false;
        _shakeElapsedMs = 0;
        _shakeStepAccumMs = 0;
        _shakeStepCount = 0;
        _lastPouredSlot = '';
        _lastPouredCellIndex = -1;
        _revealed = false;
        _mix = {counts:{}, ice:false, aged:false, shake:'none'};
        var names = slotNames();
        for (var i = 0; i < names.length; i++) _mix.counts[names[i]] = 0;
    }

    function loadSpec() {
        var generation = _generation;
        fetch('modules/bartending-spec.json').then(function(response) {
            if (!response.ok) throw new Error('spec http ' + response.status);
            return response.json();
        }).then(function(spec) {
            if (generation !== _generation || !_el) return;
            if (!spec || spec.version !== 1 || !Array.isArray(spec.recipes)
                    || !Array.isArray(spec.ingredientSlots)) {
                _specFailed = true;
            } else {
                _spec = spec;
                var names = slotNames();
                for (var i = 0; i < names.length; i++) {
                    if (_mix.counts[names[i]] === undefined) _mix.counts[names[i]] = 0;
                }
                syncUnlockedSecretsFromSnapshot();
            }
            renderAll();
        }).catch(function() {
            if (generation !== _generation || !_el) return;
            _specFailed = true;
            renderAll();
        });
    }

    function syncUnlockedSecretsFromSnapshot() {
        if (!_spec || !_snapshot || !Array.isArray(_snapshot.recipes)) return;
        for (var i = 0; i < _spec.recipes.length; i++) {
            var r = _spec.recipes[i];
            if (r.book !== '隐藏酒单') continue;
            var snap = snapshotByIndex(r.recipeIndex);
            if (snap && snap.owned && Number(snap.owned.total) > 0) {
                _unlockedSecrets[r.recipeId] = true;
            }
        }
    }

    function isSecretRecipe(recipe) {
        return !!recipe && recipe.book === '隐藏酒单';
    }

    function isSecretUnlocked(recipe) {
        if (!isSecretRecipe(recipe)) return true;
        return !!_unlockedSecrets[recipe.recipeId];
    }

    function refresh() {
        if (_statusEl) {
            _statusEl.textContent = '同步中';
            _statusEl.setAttribute('data-state', 'loading');
        }
        loadMaterials();
        var generation = _generation;
        var callId = _host.request('snapshot', {category:'调酒'}, function(response) {
            if (generation !== _generation || !_el) return;
            if (!response || !response.success) {
                setStatus('读取失败', 'error');
                toast(errorMessage(response && response.error));
                renderStation(); return;
            }
            _snapshot = response;
            syncUnlockedSecretsFromSnapshot();
            applyBalance(response.balance);
            setStatus(response.note || '就绪', 'ready');
            renderAll();
            if (_revealed) evaluateRevealedMix();
        });
        if (!callId) {
            setStatus('发送失败', 'error');
            toast('合成通道不可用，请关闭后重试。');
        }
    }

    function loadMaterials() {
        if (_materialsBusy) return;
        _materialsBusy = true;
        var generation = _generation;
        _host.request('materials', {v:1}, function(response) {
            if (generation !== _generation || !_el) return;
            _materialsBusy = false;
            if (response && response.success && Array.isArray(response.materials)) {
                var index = {};
                for (var i = 0; i < response.materials.length; i++) {
                    var row = response.materials[i];
                    index[row.name] = row;
                }
                _materials = index;
            }
            renderList();
            renderStation();
        });
    }

    /* ── 配方匹配与莫洛托夫（酒手雷）险情诊断 ── */

    function specByIndex(recipeIndex) {
        if (!_spec) return null;
        for (var i = 0; i < _spec.recipes.length; i++) {
            if (Number(_spec.recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _spec.recipes[i];
            }
        }
        return null;
    }

    function snapshotByIndex(recipeIndex) {
        if (!_snapshot || !_snapshot.recipes) return null;
        for (var i = 0; i < _snapshot.recipes.length; i++) {
            if (Number(_snapshot.recipes[i].recipeIndex) === Number(recipeIndex)) {
                return _snapshot.recipes[i];
            }
        }
        return null;
    }

    function totalPoured() {
        if (!_mix) return 0;
        var names = slotNames();
        var sum = 0;
        for (var i = 0; i < names.length; i++) {
            sum += (_mix.counts[names[i]] || 0);
        }
        return sum;
    }

    function mixHasAnyPour() {
        return totalPoured() > 0;
    }

    function karmotrineMatchesRecipe(recipe, kCount) {
        var need = recipe.ingredients || {};
        var declared = recipe.technique || null;
        var authoredK = need['卡莫特林'] || 0;
        var kind = declared ? declared.karmotrine : 'none';
        if (kind === 'required') return kCount === authoredK;
        if (kind === 'optional') return authoredK === 0 && (kCount === 0 || kCount === 1);
        return kCount === 0 && authoredK === 0;
    }

    function baseFourMatchesRecipe(recipe) {
        var slots = slotNames();
        var need = recipe.ingredients || {};
        for (var i = 0; i < slots.length; i++) {
            var name = slots[i];
            if (name === '卡莫特林') continue;
            if ((_mix.counts[name] || 0) !== (need[name] || 0)) return false;
        }
        return true;
    }

    /** 返回 {recipe, technique} 或 null；仅在开壶揭晓 (_revealed) 时生效。 */
    function matchMix() {
        if (!_spec || !_revealed) return null;
        var kCount = _mix.counts['卡莫特林'] || 0;
        for (var r = 0; r < _spec.recipes.length; r++) {
            var recipe = _spec.recipes[r];
            if (!baseFourMatchesRecipe(recipe)) continue;
            if (!karmotrineMatchesRecipe(recipe, kCount)) continue;
            var declared = recipe.technique || null;
            if (declared) {
                if (_mix.shake !== declared.shake) continue;
                if (_mix.ice !== declared.ice) continue;
                if (_mix.aged !== declared.aged) continue;
            }
            var sendKarmotrine = declared && declared.karmotrine === 'optional' ? (kCount === 1) : false;
            return {recipe:recipe,
                technique:declared ? {
                    shake:declared.shake, ice:declared.ice,
                    aged:declared.aged, karmotrine:sendKarmotrine
                } : null};
        }
        return null;
    }

    /** 当开壶后配方不成立 (_revealed && !_matched) 时，诊断为何变成了「莫洛托夫酒手雷」。 */
    function diagnoseMolotov() {
        if (!_spec || !_mix) {
            return {
                code: 'volatile_unknown',
                title: '危险混合物 · 莫洛托夫雏形（酒手雷）',
                reason: '化学提取物反应失控，已变成高度不稳定的燃烧瓶雏形，严禁端给客人！'
            };
        }
        var kCount = _mix.counts['卡莫特林'] || 0;
        var flnCount = _mix.counts['弗拉内吉'] || 0;
        var total = totalPoured();

        // 1. 原料（含卡莫特林）完全匹配某款酒，但摇壶时间 / 冰块 / 陈化手法错误
        for (var r = 0; r < _spec.recipes.length; r++) {
            var recipe = _spec.recipes[r];
            if (!baseFourMatchesRecipe(recipe)) continue;
            if (!karmotrineMatchesRecipe(recipe, kCount)) continue;
            var dec = recipe.technique || {shake:'none', ice:false, aged:false};
            var targetTitle = isSecretUnlocked(recipe) ? ('「' + recipe.title + '」') : '「某款隐藏特调」';

            if (_mix.ice === dec.ice && _mix.aged === dec.aged && _mix.shake !== dec.shake) {
                if (dec.shake === 'none') {
                    return {
                        code: 'shook_unshaken',
                        nearRecipe: recipe.recipeIndex,
                        title: '高危爆燃物 · 莫洛托夫酒手雷（剧烈摩擦起火）',
                        reason: targetTitle + '严禁摇壶！摇晃产生的高热已引燃高浓度卡莫特林，这壶液体现在就是一颗拉了弦的燃烧弹——快点「重做」倒掉！'
                    };
                }
                if (dec.shake === 'light' && _mix.shake === 'hard') {
                    return {
                        code: 'overshaken_blend',
                        nearRecipe: recipe.recipeIndex,
                        title: '过度调和险情 · 莫洛托夫酒手雷（摇制超时 ≥5s）',
                        reason: '摇壶超过 5 秒！原本只需【轻摇 Mix】的' + targetTitle + '被剧烈调和成了冒火星的爆燃浓缩液，再晚停一秒吧台都要炸了！'
                    };
                }
                if (dec.shake === 'hard' && _mix.shake === 'light') {
                    return {
                        code: 'undershaken_mix',
                        nearRecipe: recipe.recipeIndex,
                        title: '分层爆燃险情 · 莫洛托夫酒手雷（摇制不足 5s）',
                        reason: '摇制未满 5 秒！' + targetTitle + '需要【猛摇 Blend（≥5秒）】才能乳化稳定，半生不熟的提取物在壶底分层成了危险的爆燃剂。'
                    };
                }
                if (_mix.shake === 'none') {
                    return {
                        code: 'unshaken_raw',
                        nearRecipe: recipe.recipeIndex,
                        title: '未调和原液 · 莫洛托夫酒手雷（漏摇调酒壶）',
                        reason: '未经摇壶直接开盖！' + targetTitle + '的原始化学提取物尚未中和（需【' + shakeLabel(dec.shake) + '】），直接饮用无异于吞服液态炸药。'
                    };
                }
            }

            var missingSteps = [];
            if (_mix.ice !== dec.ice) missingSteps.push(dec.ice ? '必须【加冰】降温' : '严禁【加冰】');
            if (_mix.aged !== dec.aged) missingSteps.push(dec.aged ? '必须【陈化】稳定' : '严禁【陈化】');
            if (_mix.shake !== dec.shake) missingSteps.push('手法应为【' + shakeLabel(dec.shake) + '】');
            return {
                code: 'wrong_technique',
                nearRecipe: recipe.recipeIndex,
                title: '温差失控 · 莫洛托夫酒手雷（调制工序失误）',
                reason: '原料配比符合' + targetTitle + '，但工序有误（' + missingSteps.join('、') + '）。异常温差引发了剧烈放热反应，这杯酒手雷绝不能端上桌！'
            };
        }

        // 2. 前四种基底匹配，但卡莫特林（酒精）投放量不对
        for (var k = 0; k < _spec.recipes.length; k++) {
            var kRecipe = _spec.recipes[k];
            if (!baseFourMatchesRecipe(kRecipe)) continue;
            var kTarget = isSecretUnlocked(kRecipe) ? ('「' + kRecipe.title + '」') : '「某款特调」';
            var kKind = kRecipe.technique ? kRecipe.technique.karmotrine : 'none';
            if (kKind === 'none' && kCount > 0) {
                return {
                    code: 'karmotrine_forbidden',
                    nearRecipe: kRecipe.recipeIndex,
                    title: '酒精污染险情 · 莫洛托夫酒手雷（误加卡莫特林）',
                    reason: kTarget + '是无醇配方，兑入 ' + kCount + ' 份卡莫特林后发生了排斥沸腾——这瓶刺鼻的酒精手雷只适合扔向敌人，快点「重做」销毁！'
                };
            }
            if (kKind === 'optional' && kCount > 1) {
                return {
                    code: 'karmotrine_overdose',
                    nearRecipe: kRecipe.recipeIndex,
                    title: '高纯度燃爆液 · 莫洛托夫酒手雷（酒精严重过载）',
                    reason: kTarget + '为卡莫特林可选（0 份无醇 / 1 份加醇），投入 ' + kCount + ' 份卡莫特林已超出安全阈值，酒体彻底沦为高挥发燃烧弹！'
                };
            }
            return {
                code: 'karmotrine_mismatch',
                nearRecipe: kRecipe.recipeIndex,
                title: '酒精配比失衡 · 莫洛托夫酒手雷',
                reason: '基底接近' + kTarget + '，但卡莫特林份数不符（当前 ' + kCount + ' 份，配方需 ' + (kRecipe.ingredients['卡莫特林'] || 0) + ' 份），不稳定酒液正在冒出白烟！'
            };
        }

        // 3. 完全未知的狂野化学配比
        var volatileHint = (flnCount >= 3 || kCount >= 4)
            ? '高活性弗拉内吉与卡莫特林正在壶内剧烈沸腾，随时可能炸平吧台！'
            : '五色化学提取物比例失衡，合成出了一瓶冒着黑烟的劣质燃烧剂。';
        return {
            code: 'wild_concoction',
            nearRecipe: null,
            title: '高危化学废液 · 莫洛托夫雏形（酒手雷）',
            reason: '当前投入的 ' + total + ' 份原料不对应任何合法酒品——' + volatileHint + '请立即点「重做」无损倾倒！'
        };
    }

    function evaluateRevealedMix() {
        _matched = matchMix();
        _preview = null;
        var newlyUnlockedSecret = false;
        if (_matched && isSecretRecipe(_matched.recipe) && !_unlockedSecrets[_matched.recipe.recipeId]) {
            _unlockedSecrets[_matched.recipe.recipeId] = true;
            newlyUnlockedSecret = true;
            toast('★ 破译隐藏酒单：「' + _matched.recipe.title + '」已收录至手册！');
        }
        if (_revealed && !_matched && mixHasAnyPour()) {
            playRevealSound(null, false, diagnoseMolotov());
            cue('rejected');
        } else if (_revealed && _matched) {
            playRevealSound(_matched, newlyUnlockedSecret, null);
            cue('activate');
        }
        renderList();
        renderStation();
        if (_matched) requestPreview();
    }

    /* ── 请求：preview / commit ── */

    function requestPreview() {
        if (!_matched || _busy) return;
        _previewBusy = true; renderStation();
        var generation = _generation;
        var recipeIndex = _matched.recipe.recipeIndex;
        var techniqueSig = _matched.technique ? JSON.stringify(_matched.technique) : '';
        var payload = {category:'调酒', recipeIndex:recipeIndex, craftCount:1};
        if (_matched.technique) payload.technique = _matched.technique;
        _host.request('preview', payload, function(response) {
            if (generation !== _generation || !_el) return;
            _previewBusy = false;
            if (!_matched || Number(_matched.recipe.recipeIndex) !== Number(recipeIndex)) return;
            var current = _matched.technique ? JSON.stringify(_matched.technique) : '';
            if (current !== techniqueSig) return;
            if (!response || !response.success) {
                _preview = null;
                _commitFeedback = errorMessage(response && response.error);
            } else {
                _preview = response; _commitFeedback = null;
            }
            renderStation();
        });
    }

    function commit() {
        if (_busy || _previewBusy || !_revealed || !_matched || !_preview
                || !_preview.canCommit || !_preview.craftToken) return;
        _busy = true; _commitFeedback = null; renderStation();
        var generation = _generation;
        var craftedName = _matched.recipe.title;
        _host.request('commit', {category:'调酒',
            expectedCraftToken:_preview.craftToken}, function(response) {
            if (generation !== _generation || !_el) return;
            _busy = false;
            if (response && response.success) {
                toast('已上酒：' + (response.crafted && response.crafted.displayName
                    ? response.crafted.displayName : craftedName));
                playGlassServe();
                cue('success');
                _commitFeedback = null;
                _preview = null;
                resetMix(); _matched = null;
                refresh(); return;
            }
            cue('rejected');
            toast(errorMessage(response && response.error));
            _commitFeedback = errorMessage(response && response.error);
            _preview = null;
            renderStation();
            if (_matched) requestPreview();
        });
    }

    /* ── 交互：投料、加冰/陈化、5 秒实时计时摇壶 ── */

    function unsealIfRevealed() {
        if (_revealed) {
            _revealed = false;
            _mix.shake = 'none';
            _matched = null;
            _preview = null;
        }
    }

    /** 计算某原料最新点亮在 20 格矩阵中的格位索引 */
    function computeNewestCellIndexForSlot(targetSlot) {
        var slots = slotNames();
        var cursor = 0;
        var lastIdx = -1;
        for (var i = 0; i < slots.length; i++) {
            var sName = slots[i];
            var cnt = (_mix && _mix.counts[sName]) || 0;
            if (sName === targetSlot && cnt > 0) {
                lastIdx = cursor + cnt - 1;
            }
            cursor += cnt;
        }
        return lastIdx;
    }

    function setCount(name, next) {
        if (_busy || _shaking) return;
        var value = Math.floor(Number(next));
        if (isNaN(value) || value < 0) value = 0;
        var current = _mix.counts[name] || 0;
        var others = totalPoured() - current;
        var maxAllowed = Math.max(0, TOTAL_SLOT_MAX - others);
        if (value > maxAllowed) value = maxAllowed;
        if (current === value) { renderStation(); return; }
        unsealIfRevealed();
        _mix.counts[name] = value;
        _lastPouredSlot = name;
        var newTotal = totalPoured();
        if (value > current) {
            _lastPouredCellIndex = computeNewestCellIndexForSlot(name);
            playIngredientAdd(name, newTotal);
        } else {
            _lastPouredCellIndex = -1;
            playIngredientRemove(name, newTotal);
        }
        _commitFeedback = null;
        renderList();
        renderStation();
    }

    function toggleOption(field) {
        if (_busy || _shaking) return;
        unsealIfRevealed();
        _lastPouredSlot = '';
        _lastPouredCellIndex = -1;
        _mix[field] = _mix[field] !== true;
        if (field === 'ice') playIceToggle(_mix.ice);
        else if (field === 'aged') playAgeToggle(_mix.aged);
        _commitFeedback = null;
        renderList();
        renderStation();
    }

    function stopShakeTimerOnly() {
        if (_shakeTimerId !== null) {
            clearInterval(_shakeTimerId);
            _shakeTimerId = null;
        }
    }

    function startShake() {
        if (_busy || _shaking) return;
        if (!mixHasAnyPour()) {
            toast('调酒壶为空——请先投放至少 1 份提取物。');
            cue('rejected');
            return;
        }
        _shaking = true;
        _revealed = false;
        _matched = null;
        _preview = null;
        _commitFeedback = null;
        _lastPouredSlot = '';
        _lastPouredCellIndex = -1;
        _shakeElapsedMs = 0;
        _shakeStepAccumMs = 0;
        _shakeStepCount = 0;
        _mix.shake = 'light';
        _shakeLastTick = Date.now();
        playShakeStep(false, _shakeStepCount++);
        stopShakeTimerOnly();
        _shakeTimerId = setInterval(function() {
            if (!_shaking || !_el) { stopShakeTimerOnly(); return; }
            var now = Date.now();
            var delta = now - _shakeLastTick;
            if (delta <= 0 || delta > 2000) delta = SHAKE_TICK_MS;
            _shakeLastTick = now;
            advanceShakeInternal(delta);
        }, SHAKE_TICK_MS);
        renderList();
        renderStation();
    }

    function advanceShakeInternal(deltaMs) {
        if (!_shaking) return;
        var stepMs = Math.max(0, Number(deltaMs) || 0);
        var prevShake = _mix.shake;
        _shakeElapsedMs += stepMs;
        _mix.shake = _shakeElapsedMs >= HARD_SHAKE_MS ? 'hard' : 'light';
        var isHard = _mix.shake === 'hard';
        if (prevShake === 'light' && isHard) {
            playBlendCrossover();
            cue('activate');
        }
        // 连续律动摇壶音效（轻摇每 220ms 一次往复，猛摇每 110ms 倍速激荡）
        var cadenceMs = isHard ? 110 : 220;
        _shakeStepAccumMs += stepMs;
        var maxTicksPerCall = 6;
        while (_shakeStepAccumMs >= cadenceMs && maxTicksPerCall > 0) {
            _shakeStepAccumMs -= cadenceMs;
            playShakeStep(isHard, _shakeStepCount++);
            maxTicksPerCall--;
        }
        if (_shakeStepAccumMs >= cadenceMs) _shakeStepAccumMs = _shakeStepAccumMs % cadenceMs;
        updateShakerLiveDOM();
    }

    function stopShake() {
        if (!_shaking) return;
        stopShakeTimerOnly();
        _shaking = false;
        _mix.shake = _shakeElapsedMs >= HARD_SHAKE_MS ? 'hard' : 'light';
        _revealed = true;
        _commitFeedback = null;
        evaluateRevealedMix();
    }

    function toggleShakeTimer() {
        if (_busy) return;
        if (_shaking) {
            stopShake();
        } else {
            startShake();
        }
    }

    /** 免摇直调开壶（用于烈焰摩艾等 shake === 'none' 的配方，或玩家不摇壶直接揭晓）。 */
    function directReveal() {
        if (_busy) return;
        if (!mixHasAnyPour()) {
            toast('调酒壶为空——请先投放至少 1 份提取物。');
            cue('rejected');
            return;
        }
        stopShakeTimerOnly();
        _shaking = false;
        _shakeElapsedMs = 0;
        _mix.shake = 'none';
        _revealed = true;
        _commitFeedback = null;
        evaluateRevealedMix();
    }

    function resetAll() {
        if (_busy) return;
        playResetDrain();
        resetMix();
        _matched = null; _preview = null; _commitFeedback = null;
        renderList(); renderStation();
    }

    function inspectRecipe(recipeIndex) {
        _inspectedIndex = recipeIndex;
        playPageTurn();
        renderList();
    }

    function closeInspect() {
        _inspectedIndex = null;
        playPageTurn();
        renderList();
    }

    /* ── 渲染：左侧 Drinktionary 只读酒单手册 ── */

    var TABS = [
        {id:'name', label:'按名称'},
        {id:'flavor', label:'按口味'},
        {id:'style', label:'按种类'},
        {id:'bottled', label:'瓶装饮品'}
    ];

    function renderTabs() {
        if (!_tabsEl) return;
        _tabsEl.innerHTML = '';
        for (var i = 0; i < TABS.length; i++) {
            var tab = TABS[i];
            var button = document.createElement('button');
            button.type = 'button';
            button.className = 'bart-tab' + (_filter.tab === tab.id ? ' active' : '');
            button.textContent = tab.label;
            button.setAttribute('aria-pressed', _filter.tab === tab.id ? 'true' : 'false');
            button.addEventListener('click', bindTab(tab.id));
            _tabsEl.appendChild(button);
        }
        function bindTab(id) {
            return function() {
                _filter.tab = id;
                _filter.value = '';
                _inspectedIndex = null;
                playPageTurn();
                renderTabs(); renderChips(); renderList();
            };
        }
    }

    function renderChips() {
        if (!_chipsEl) return;
        _chipsEl.innerHTML = '';
        var options = _filter.tab === 'name' ? NAME_GROUPS
            : _filter.tab === 'flavor' ? (_spec ? _spec.flavors : [])
            : _filter.tab === 'style' ? (_spec ? _spec.styles : []) : null;
        if (!options || !options.length) { _chipsEl.classList.add('hidden'); return; }
        _chipsEl.classList.remove('hidden');
        for (var i = 0; i < options.length; i++) {
            var value = options[i];
            var chip = document.createElement('button');
            chip.type = 'button';
            chip.className = 'bart-chip' + (_filter.value === value ? ' active' : '');
            chip.textContent = value;
            chip.addEventListener('click', bindChip(value));
            _chipsEl.appendChild(chip);
        }
        function bindChip(value) {
            return function() {
                _filter.value = _filter.value === value ? '' : value;
                _inspectedIndex = null;
                playPageTurn();
                renderChips(); renderList();
            };
        }
    }

    function matchesNameGroup(recipe, group) {
        if (!group) return true;
        var en = String(recipe.englishTitle || '').trim().toUpperCase();
        var ch = en ? en.charCodeAt(0) : 0;
        if (group === 'A–F') return ch >= 65 && ch <= 70;
        if (group === 'G–M') return ch >= 71 && ch <= 77;
        if (group === 'P–Z') return ch >= 80 && ch <= 90;
        return true;
    }

    function filteredRecipes() {
        if (!_spec) return [];
        var out = [];
        for (var i = 0; i < _spec.recipes.length; i++) {
            var recipe = _spec.recipes[i];
            var unlocked = isSecretUnlocked(recipe);
            // 未解锁的隐藏酒单不在口味/种类/瓶装/首字母筛选中剧透，仅在「按名称」总览末尾显示机密卡
            if (!unlocked) {
                if (_filter.tab !== 'name' || _filter.value) continue;
                out.push(recipe);
                continue;
            }
            if (_filter.tab === 'name' && _filter.value && !matchesNameGroup(recipe, _filter.value)) continue;
            if (_filter.tab === 'flavor' && _filter.value && recipe.flavor !== _filter.value) continue;
            if (_filter.tab === 'style' && _filter.value && recipe.style !== _filter.value) continue;
            if (_filter.tab === 'bottled' && recipe.bottled !== true) continue;
            out.push(recipe);
        }
        return out;
    }

    function availabilityLabel(recipe) {
        switch (recipe.availability) {
            case 'ready': return '可调';
            case 'infrastructure_locked': return '缺设备';
            case 'level_locked': return '等级不足';
            case 'material_missing': return '缺原料';
            case 'insufficient_money': return '金币不足';
            case 'insufficient_kpoint': return 'K点不足';
            case 'inventory_full': return '栏位不足';
            default: return '暂不可调';
        }
    }

    function shakeLabel(shake) {
        switch (shake) {
            case 'light': return '轻摇';
            case 'hard': return '猛摇';
            default: return '不摇';
        }
    }

    function shakeDetailLabel(shake) {
        switch (shake) {
            case 'light': return '轻摇 Mix (1–4秒)';
            case 'hard': return '猛摇 Blend (≥5秒)';
            default: return '免摇直调 (不摇壶)';
        }
    }

    function renderDrinkPips(recipe) {
        var wrap = document.createElement('span');
        wrap.className = 'bart-drink-pips';
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            var name = slots[i];
            var count = recipe.ingredients && recipe.ingredients[name];
            if (count > 0 || (name === '卡莫特林' && recipe.technique && recipe.technique.karmotrine === 'optional')) {
                var pip = document.createElement('span');
                pip.className = 'bart-pip';
                pip.setAttribute('data-tone', slotTone(name));
                wrap.appendChild(pip);
            }
        }
        return wrap;
    }

    function renderList() {
        if (!_listEl) return;
        _listEl.innerHTML = '';
        if (_inspectedIndex !== null) {
            var inspected = specByIndex(_inspectedIndex);
            if (inspected) {
                _listEl.appendChild(renderDetailView(inspected));
                return;
            }
            _inspectedIndex = null;
        }

        var grid = document.createElement('div');
        grid.className = 'bart-drink-grid';
        var recipes = filteredRecipes();
        if (!_spec) {
            var empty = document.createElement('div');
            empty.className = 'bart-empty';
            empty.textContent = _specFailed ? '酒单规格缺失。' : '载入中…';
            grid.appendChild(empty);
        } else if (!recipes.length) {
            var none = document.createElement('div');
            none.className = 'bart-empty';
            none.textContent = '该分类下没有酒品。';
            grid.appendChild(none);
        }
        for (var i = 0; i < recipes.length; i++) {
            var recipe = recipes[i];
            var unlocked = isSecretUnlocked(recipe);
            var snap = snapshotByIndex(recipe.recipeIndex);
            var card = document.createElement('button');
            card.type = 'button';
            var classes = 'bart-drink'
                + (unlocked ? (snap && snap.availability === 'ready' ? ' is-ready' : ' is-blocked') : ' is-secret')
                + (_matched && _matched.recipe.recipeIndex === recipe.recipeIndex ? ' matched' : '');
            card.className = classes;
            card.setAttribute('data-audio-cue', 'activate');

            var thumb = document.createElement('span');
            thumb.className = 'bart-drink-thumb';
            if (unlocked && snap) {
                thumb.innerHTML = _host.iconHtml(snap.output.icon, 'bart-icon');
            } else if (!unlocked) {
                thumb.textContent = '?';
            }

            var name = document.createElement('span');
            name.className = 'bart-drink-name';
            name.textContent = unlocked ? recipe.title : '??? · 隐藏特调';

            var en = document.createElement('span');
            en.className = 'bart-drink-en';
            en.textContent = unlocked ? (recipe.englishTitle || recipe.recipeId) : 'CLASSIFIED';

            var spec = document.createElement('span');
            spec.className = 'bart-drink-spec';
            if (unlocked) {
                spec.textContent = recipe.flavor + '味 · ' + recipe.style + (recipe.bottled ? ' · 瓶装' : '')
                    + ' · ' + shakeLabel(recipe.technique && recipe.technique.shake);
            } else {
                spec.textContent = '未收录秘方 · 点击查看传闻';
            }

            var state = document.createElement('span');
            state.className = 'bart-drink-state';
            state.textContent = !unlocked ? '待破译'
                : (_matched && _matched.recipe.recipeIndex === recipe.recipeIndex ? '当前壶内命中'
                : (snap ? availabilityLabel(snap) : '同步中'));

            card.appendChild(thumb);
            card.appendChild(name);
            card.appendChild(en);
            if (unlocked) card.appendChild(renderDrinkPips(recipe));
            card.appendChild(spec);
            card.appendChild(state);
            card.addEventListener('click', bindInspect(recipe.recipeIndex));
            grid.appendChild(card);
        }
        _listEl.appendChild(grid);
        function bindInspect(recipeIndex) {
            return function() { inspectRecipe(recipeIndex); };
        }
    }

    function renderDetailView(recipe) {
        var unlocked = isSecretUnlocked(recipe);
        var snap = snapshotByIndex(recipe.recipeIndex);
        var list = filteredRecipes();
        var pos = -1;
        for (var i = 0; i < list.length; i++) {
            if (list[i].recipeIndex === recipe.recipeIndex) { pos = i; break; }
        }

        var detail = document.createElement('div');
        detail.className = 'bart-detail';

        var nav = document.createElement('div');
        nav.className = 'bart-detail-nav';
        var backBtn = document.createElement('button');
        backBtn.type = 'button';
        backBtn.className = 'bart-detail-btn bart-detail-back';
        backBtn.textContent = '← 返回酒单';
        backBtn.setAttribute('data-audio-cue', 'back');
        backBtn.addEventListener('click', closeInspect);

        var pageInfo = document.createElement('span');
        pageInfo.className = 'bart-detail-page';
        pageInfo.textContent = 'NO. ' + String(recipe.recipeIndex + 1) + ' / ' + String(_spec ? _spec.recipes.length : 25);

        var pager = document.createElement('div');
        pager.style.display = 'flex';
        pager.style.gap = '4px';
        var prevBtn = document.createElement('button');
        prevBtn.type = 'button';
        prevBtn.className = 'bart-detail-btn';
        prevBtn.textContent = '‹ 上一款';
        prevBtn.disabled = pos <= 0;
        prevBtn.addEventListener('click', function() {
            if (pos > 0) inspectRecipe(list[pos - 1].recipeIndex);
        });
        var nextBtn = document.createElement('button');
        nextBtn.type = 'button';
        nextBtn.className = 'bart-detail-btn';
        nextBtn.textContent = '下一款 ›';
        nextBtn.disabled = pos < 0 || pos >= list.length - 1;
        nextBtn.addEventListener('click', function() {
            if (pos >= 0 && pos < list.length - 1) inspectRecipe(list[pos + 1].recipeIndex);
        });
        pager.appendChild(prevBtn);
        pager.appendChild(nextBtn);

        nav.appendChild(backBtn);
        nav.appendChild(pageInfo);
        nav.appendChild(pager);
        detail.appendChild(nav);

        var hero = document.createElement('div');
        hero.className = 'bart-detail-hero';
        var thumb = document.createElement('span');
        thumb.className = 'bart-detail-thumb';
        if (unlocked && snap) {
            thumb.innerHTML = _host.iconHtml(snap.output.icon, 'bart-icon');
        } else {
            thumb.textContent = '?';
        }
        var titles = document.createElement('div');
        titles.className = 'bart-detail-titles';
        var titleB = document.createElement('b');
        titleB.className = 'bart-detail-title';
        titleB.textContent = unlocked ? recipe.title : '??? · 隐藏特调';
        var enSpan = document.createElement('span');
        enSpan.className = 'bart-detail-en';
        enSpan.textContent = unlocked ? (recipe.englishTitle || recipe.recipeId).toUpperCase() : 'CLASSIFIED // SECRET DRINK';
        var badges = document.createElement('div');
        badges.className = 'bart-detail-badges';
        if (unlocked) {
            badges.appendChild(makeBadge(recipe.flavor + '味', ''));
            badges.appendChild(makeBadge(recipe.style, ''));
            if (recipe.bottled) badges.appendChild(makeBadge('瓶装饮品', 'is-pink'));
            if (isSecretRecipe(recipe)) badges.appendChild(makeBadge('隐藏酒单', 'is-pink'));
            if (snap) badges.appendChild(makeBadge(availabilityLabel(snap), snap.availability === 'ready' ? 'is-ready' : ''));
        } else {
            badges.appendChild(makeBadge('隐藏酒单 · 待破译', 'is-pink'));
        }
        titles.appendChild(titleB);
        titles.appendChild(enSpan);
        titles.appendChild(badges);
        hero.appendChild(thumb);
        hero.appendChild(titles);
        detail.appendChild(hero);

        if (!unlocked) {
            var secretSec = document.createElement('div');
            secretSec.className = 'bart-detail-section';
            var secHead = document.createElement('div');
            secHead.className = 'bart-detail-sec-title';
            secHead.textContent = '吧台传闻 · 破译线索';
            var rumor = document.createElement('p');
            rumor.className = 'bart-detail-lore';
            rumor.textContent = '不在公开酒单上的传说之作。据老酒客传闻：将五种提取物按「1 : 1 : 2 : 3 : 5」的阶梯比例依次注入壶中，不加冰、不陈化，且严禁摇晃（点「直调」直接开壶），即可重现那座凝视火光的摩艾石像。';
            secretSec.appendChild(secHead);
            secretSec.appendChild(rumor);
            detail.appendChild(secretSec);
            return detail;
        }

        // 配方成分条形图
        var formulaSec = document.createElement('div');
        formulaSec.className = 'bart-detail-section';
        var fTitle = document.createElement('div');
        fTitle.className = 'bart-detail-sec-title';
        fTitle.textContent = '五色提取物配比 · INGREDIENTS';
        formulaSec.appendChild(fTitle);

        var rows = document.createElement('div');
        rows.className = 'bart-formula-rows';
        var slots = slotNames();
        for (var s = 0; s < slots.length; s++) {
            var sName = slots[s];
            var reqCount = (recipe.ingredients && recipe.ingredients[sName]) || 0;
            var isOptK = sName === '卡莫特林' && recipe.technique && recipe.technique.karmotrine === 'optional';
            if (reqCount <= 0 && !isOptK) continue;

            var row = document.createElement('div');
            row.className = 'bart-formula-row';
            var rName = document.createElement('span');
            rName.className = 'bart-formula-name';
            rName.textContent = slotCode(sName) + ' ' + sName;

            var bars = document.createElement('div');
            bars.className = 'bart-formula-bars';
            var segTotal = isOptK ? 1 : reqCount;
            for (var b = 0; b < segTotal; b++) {
                var seg = document.createElement('span');
                seg.className = 'bart-formula-seg' + (isOptK ? ' is-optional' : '');
                seg.setAttribute('data-tone', slotTone(sName));
                bars.appendChild(seg);
            }

            var meta = materialMeta(sName);
            var owned = meta ? Number(meta.owned) : null;
            var countEl = document.createElement('span');
            var enough = isOptK || owned === null || owned >= reqCount;
            countEl.className = 'bart-formula-count ' + (enough ? 'ok' : 'no');
            countEl.textContent = isOptK ? '可选 (0/1)' : ('×' + reqCount + (owned !== null ? ' (存' + owned + ')' : ''));

            row.appendChild(rName);
            row.appendChild(bars);
            row.appendChild(countEl);
            rows.appendChild(row);
        }
        formulaSec.appendChild(rows);
        detail.appendChild(formulaSec);

        // 调制工序
        var techSec = document.createElement('div');
        techSec.className = 'bart-detail-section';
        var tTitle = document.createElement('div');
        tTitle.className = 'bart-detail-sec-title';
        tTitle.textContent = '调制工序 · TECHNIQUE';
        var pills = document.createElement('div');
        pills.className = 'bart-tech-pills';
        var tech = recipe.technique || {shake:'none', ice:false, aged:false};

        var icePill = document.createElement('span');
        icePill.className = 'bart-tech-pill' + (tech.ice ? ' on-ice' : '');
        icePill.textContent = tech.ice ? '❄ 加冰 On the Rocks' : '常温 · 不加冰';

        var agePill = document.createElement('span');
        agePill.className = 'bart-tech-pill' + (tech.aged ? ' on-age' : '');
        agePill.textContent = tech.aged ? '⏳ 陈化 Aged' : '鲜调 · 不陈化';

        var shakePill = document.createElement('span');
        shakePill.className = 'bart-tech-pill on-shake';
        shakePill.textContent = shakeDetailLabel(tech.shake);

        pills.appendChild(icePill);
        pills.appendChild(agePill);
        pills.appendChild(shakePill);
        techSec.appendChild(tTitle);
        techSec.appendChild(pills);
        detail.appendChild(techSec);

        // 酒品风味与描述
        var loreSec = document.createElement('div');
        loreSec.className = 'bart-detail-section';
        var lTitle = document.createElement('div');
        lTitle.className = 'bart-detail-sec-title';
        lTitle.textContent = '酒品风味志 · NOTES';
        var blurbP = document.createElement('p');
        blurbP.className = 'bart-detail-lore';
        blurbP.textContent = recipe.blurb || ('堕落城酒吧特调「' + recipe.title + '」。');
        loreSec.appendChild(lTitle);
        loreSec.appendChild(blurbP);
        if (recipe.effectNote) {
            var effP = document.createElement('p');
            effP.className = 'bart-detail-effect';
            effP.textContent = recipe.effectNote;
            loreSec.appendChild(effP);
        }
        detail.appendChild(loreSec);

        var roNote = document.createElement('div');
        roNote.className = 'bart-detail-readonly-note';
        roNote.textContent = '◆ 纯正 VA-11 手动调酒：请参照上方配方在右侧吧台亲自投料与摇壶 ◆';
        detail.appendChild(roNote);

        return detail;
    }

    function makeBadge(text, extraClass) {
        var b = document.createElement('span');
        b.className = 'bart-badge' + (extraClass ? ' ' + extraClass : '');
        b.textContent = text;
        return b;
    }

    /* ── 渲染：右侧 VA-11 吧台操作台 ── */

    function materialMeta(name) {
        return _materials && _materials[name] ? _materials[name] : null;
    }

    function buildPouredSequence() {
        var seq = [];
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            var name = slots[i];
            var count = (_mix && _mix.counts[name]) || 0;
            for (var c = 0; c < count && seq.length < TOTAL_SLOT_MAX; c++) {
                seq.push({name: name, code: slotCode(name), tone: slotTone(name)});
            }
        }
        return seq;
    }

    function renderMatrixBox(titleText, rightText, seq, startIndex) {
        var box = document.createElement('div');
        box.className = 'bart-matrix-box';
        var head = document.createElement('div');
        head.className = 'bart-matrix-head';
        var left = document.createElement('span');
        left.textContent = titleText;
        var right = document.createElement('span');
        right.textContent = rightText;
        head.appendChild(left);
        head.appendChild(right);

        var grid = document.createElement('div');
        grid.className = 'bart-matrix-grid';
        for (var i = 0; i < 10; i++) {
            var idx = startIndex + i;
            var item = seq[idx] || null;
            var cell = document.createElement('div');
            cell.className = 'bart-cell' + (item ? ' filled' : '')
                + (item && idx === _lastPouredCellIndex ? ' is-newest' : '');
            if (item) {
                cell.setAttribute('data-tone', item.tone);
                cell.textContent = item.code;
            } else {
                cell.textContent = String(idx + 1);
            }
            grid.appendChild(cell);
        }
        box.appendChild(head);
        box.appendChild(grid);
        return box;
    }

    /** 渲染中央三段式赛博调酒壶（壶帽 + 滤网肩部 + 五色分层液位观察窗 + 冰晶/陈化/爆燃微标） */
    function renderShakerVessel(isMolotov) {
        var vessel = document.createElement('div');
        vessel.className = 'bart-shaker-vessel'
            + (_mix && _mix.ice ? ' has-ice' : '')
            + (_mix && _mix.aged ? ' has-aged' : '');

        var cap = document.createElement('span');
        cap.className = 'bart-shaker-cap';
        var neck = document.createElement('span');
        neck.className = 'bart-shaker-neck';

        var body = document.createElement('div');
        body.className = 'bart-shaker-body';
        var win = document.createElement('div');
        win.className = 'bart-shaker-window';

        var stack = document.createElement('div');
        stack.className = 'bart-liquid-stack';
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            var sName = slots[i];
            var cnt = (_mix && _mix.counts[sName]) || 0;
            if (cnt <= 0) continue;
            var layer = document.createElement('div');
            layer.className = 'bart-liquid-layer';
            layer.setAttribute('data-tone', slotTone(sName));
            layer.style.height = Math.round((cnt / TOTAL_SLOT_MAX) * 100) + '%';
            stack.appendChild(layer);
        }
        win.appendChild(stack);

        var badges = document.createElement('div');
        badges.className = 'bart-vessel-badges';
        if (isMolotov) {
            var sparkTag = document.createElement('span');
            sparkTag.className = 'bart-vessel-tag is-spark';
            sparkTag.textContent = '🔥';
            badges.appendChild(sparkTag);
        } else {
            if (_mix && _mix.aged) {
                var ageTag = document.createElement('span');
                ageTag.className = 'bart-vessel-tag is-age';
                ageTag.textContent = '⏳';
                badges.appendChild(ageTag);
            }
            if (_mix && _mix.ice) {
                var iceTag = document.createElement('span');
                iceTag.className = 'bart-vessel-tag is-ice';
                iceTag.textContent = '❄';
                badges.appendChild(iceTag);
            }
        }
        win.appendChild(badges);
        body.appendChild(win);

        vessel.appendChild(cap);
        vessel.appendChild(neck);
        vessel.appendChild(body);
        return vessel;
    }

    function updateShakerLiveDOM() {
        if (!_shakerEl) return;
        var isHard = _shakeElapsedMs >= HARD_SHAKE_MS;
        var pct = Math.min(100, Math.round((_shakeElapsedMs / HARD_SHAKE_MS) * 100));
        _shakerEl.className = 'bart-shaker ' + (_shaking
            ? (isHard ? 'is-shaking-hard state-hard' : 'is-shaking-light state-light')
            : ('state-' + _mix.shake));
        if (_shakerKickerEl) {
            _shakerKickerEl.textContent = _shaking
                ? ('计时 ' + (_shakeElapsedMs / 1000).toFixed(1) + 's / 5.0s')
                : 'SHAKER CONSOLE';
        }
        if (_shakerStateEl) {
            _shakerStateEl.textContent = _shaking
                ? (isHard ? '猛摇 · BLEND' : '轻摇 · MIX')
                : (_mix.shake === 'none' ? '未摇制' : (_mix.shake === 'light' ? '轻摇' : '猛摇'));
        }
        if (_shakerHintEl) {
            _shakerHintEl.textContent = _shaking
                ? (isHard ? '已达 5 秒剧烈调和！点击「停止」开壶' : '未满 5 秒为轻摇 · 点击「停止」开壶')
                : '点「调制」起摇（<5s轻摇 / ≥5s猛摇）';
        }
        if (_timerFillEl) {
            _timerFillEl.style.width = pct + '%';
            if (isHard) _timerFillEl.classList.add('is-hard');
            else _timerFillEl.classList.remove('is-hard');
        }
        if (_mixBtnEl) {
            _mixBtnEl.textContent = _shaking ? '停止' : '调制';
            if (_shaking) _mixBtnEl.classList.add('active');
            else _mixBtnEl.classList.remove('active');
        }
    }

    function renderStation() {
        if (!_stationEl) return;
        _stationEl.innerHTML = '';
        var board = document.createElement('div');
        board.className = 'bart-board';

        // 1. 顶部：五色提取物分配器
        var slotsRow = document.createElement('div');
        slotsRow.className = 'bart-slots';
        var slots = slotNames();
        for (var i = 0; i < slots.length; i++) {
            slotsRow.appendChild(renderSlot(slots[i]));
        }
        board.appendChild(slotsRow);

        // 2. 中部：栏位 1 (01–10) + 中央实时计时摇壶 + 栏位 2 (11–20)
        var seq = buildPouredSequence();
        var pouredCount = seq.length;
        var isMolotov = _revealed && !_matched && pouredCount > 0;

        var console_ = document.createElement('div');
        console_.className = 'bart-console';

        var leftWing = document.createElement('div');
        leftWing.className = 'bart-wing bart-wing-left';
        leftWing.appendChild(renderMatrixBox('栏位 1', '01–10', seq, 0));
        var options = document.createElement('div');
        options.className = 'bart-options';
        options.appendChild(optionButton('ice', '加冰', 'toggle-ice'));
        options.appendChild(optionButton('aged', '陈化', 'toggle-age'));
        leftWing.appendChild(options);
        console_.appendChild(leftWing);

        var shakerZone = document.createElement('div');
        shakerZone.className = 'bart-shaker-zone';

        var shaker = document.createElement('button');
        shaker.type = 'button';
        var shakerCls = 'bart-shaker ';
        if (_shaking) {
            shakerCls += (_shakeElapsedMs >= HARD_SHAKE_MS ? 'is-shaking-hard state-hard' : 'is-shaking-light state-light');
        } else if (isMolotov) {
            shakerCls += 'is-molotov state-' + _mix.shake;
        } else {
            shakerCls += 'state-' + _mix.shake;
        }
        shaker.className = shakerCls;
        shaker.disabled = _busy;

        var vessel = renderShakerVessel(isMolotov);
        var readout = document.createElement('div');
        readout.className = 'bart-shaker-readout';

        var shakeKicker = document.createElement('span');
        shakeKicker.className = 'bart-shaker-kicker';
        shakeKicker.textContent = _shaking
            ? ('计时 ' + (_shakeElapsedMs / 1000).toFixed(1) + 's / 5.0s')
            : (_revealed ? '已开壶揭晓' : ('调酒壶 · ' + pouredCount + '/20 格'));

        var shakeState = document.createElement('span');
        shakeState.className = 'bart-shaker-state';
        shakeState.textContent = _shaking
            ? (_shakeElapsedMs >= HARD_SHAKE_MS ? '猛摇 · BLEND' : '轻摇 · MIX')
            : (isMolotov ? '⚠ 酒手雷险情'
                : (_mix.shake === 'none' ? '未摇制'
                    : (_mix.shake === 'light' ? '轻摇' : '猛摇')));

        var shakeHint = document.createElement('span');
        shakeHint.className = 'bart-shaker-hint';
        shakeHint.textContent = _shaking
            ? (_shakeElapsedMs >= HARD_SHAKE_MS ? '已达 5 秒剧烈调和！点击「停止」开壶' : '未满 5 秒为轻摇 · 点击「停止」开壶')
            : (_revealed ? (isMolotov ? '危险混合物！请点「重做」倾倒' : '调制完成，可点「上酒」出杯')
                : '点「调制」起摇（<5s轻摇 / ≥5s猛摇）');

        readout.appendChild(shakeKicker);
        readout.appendChild(shakeState);
        readout.appendChild(shakeHint);
        shaker.appendChild(vessel);
        shaker.appendChild(readout);
        shaker.addEventListener('click', toggleShakeTimer);

        var timerTrack = document.createElement('div');
        timerTrack.className = 'bart-timer-track';
        var timerFill = document.createElement('div');
        var pct = _shaking ? Math.min(100, Math.round((_shakeElapsedMs / HARD_SHAKE_MS) * 100))
            : (_revealed && _mix.shake === 'hard' ? 100 : (_revealed && _mix.shake === 'light' ? 45 : 0));
        timerFill.className = 'bart-timer-fill' + ((_shaking && _shakeElapsedMs >= HARD_SHAKE_MS) || _mix.shake === 'hard' ? ' is-hard' : '');
        timerFill.style.width = pct + '%';
        timerTrack.appendChild(timerFill);

        _shakerEl = shaker;
        _shakerKickerEl = shakeKicker;
        _shakerStateEl = shakeState;
        _shakerHintEl = shakeHint;
        _timerFillEl = timerFill;

        shakerZone.appendChild(shaker);
        shakerZone.appendChild(timerTrack);
        console_.appendChild(shakerZone);

        var rightWing = document.createElement('div');
        rightWing.className = 'bart-wing bart-wing-right';
        rightWing.appendChild(renderMatrixBox('栏位 2', '容量 ' + pouredCount + '/20', seq, 10));

        var wingActions = document.createElement('div');
        wingActions.className = 'bart-wing-actions';

        var mixBtn = document.createElement('button');
        mixBtn.type = 'button';
        mixBtn.className = 'bart-tech-btn bart-mix-btn' + (_shaking ? ' active' : '');
        mixBtn.textContent = _shaking ? '停止' : '调制';
        mixBtn.disabled = _busy || (!mixHasAnyPour() && !_shaking);
        mixBtn.addEventListener('click', toggleShakeTimer);
        _mixBtnEl = mixBtn;

        var directBtn = document.createElement('button');
        directBtn.type = 'button';
        directBtn.className = 'bart-tech-btn bart-direct-btn' + (_revealed && _mix.shake === 'none' ? ' active' : '');
        directBtn.textContent = '直调';
        directBtn.disabled = _busy || _shaking || !mixHasAnyPour();
        directBtn.setAttribute('title', '不摇晃调酒壶，直接开壶兑出（用于免摇配方）');
        directBtn.addEventListener('click', directReveal);

        wingActions.appendChild(mixBtn);
        wingActions.appendChild(directBtn);
        rightWing.appendChild(wingActions);
        console_.appendChild(rightWing);

        board.appendChild(console_);

        // 3. 出杯揭晓台（正常酒品 vs 莫洛托夫酒手雷险情）
        _resultEl = document.createElement('div');
        _resultEl.className = 'bart-result';
        renderResult();
        board.appendChild(_resultEl);

        // 4. 底部操作栏（重做 + 提示 + 上酒出杯）
        var footer = document.createElement('div');
        footer.className = 'bart-card-footer';

        var redo = document.createElement('button');
        redo.type = 'button';
        redo.className = 'bart-tech-btn redo' + (isMolotov ? ' is-urgent' : '');
        redo.textContent = '重做';
        redo.disabled = _busy;
        redo.addEventListener('click', resetAll);
        footer.appendChild(redo);

        var note = document.createElement('div');
        note.className = 'bart-foot-note';
        note.textContent = footerNote();
        footer.appendChild(note);

        var confirm = document.createElement('button');
        confirm.type = 'button';
        confirm.className = 'bart-confirm';
        confirm.textContent = _busy ? '调制中…' : '上酒';
        var committable = _revealed && !!_matched && !!_preview && _preview.canCommit && !_busy && !_previewBusy;
        confirm.disabled = !committable;
        if (!committable) confirm.setAttribute('aria-disabled', 'true');
        confirm.addEventListener('click', commit);
        footer.appendChild(confirm);

        board.appendChild(footer);
        _stationEl.appendChild(board);
    }

    function molotovSvgHtml() {
        return '<svg viewBox="0 0 32 32" aria-hidden="true">'
            + '<path fill="currentColor" d="M18 2c1.5 2.2 1 4.8-.8 6.4-.7-.9-.9-2.1-.4-3.2-1.8 1.1-2.5 3.2-1.8 5.1H12c-.4-2.8 1.2-5.6 6-8.3z"/>'
            + '<rect x="13" y="10" width="6" height="3" rx="1" fill="currentColor"/>'
            + '<path fill="currentColor" d="M11 14h10l3 5v9a2 2 0 0 1-2 2H10a2 2 0 0 1-2-2v-9l3-5zm2 6v6h6v-6l-3-3-3 3z"/>'
            + '</svg>';
    }

    function renderResult() {
        if (!_resultEl) return;
        _resultEl.innerHTML = '';
        _resultEl.classList.remove('matched');
        _resultEl.classList.remove('is-molotov');

        var head = document.createElement('div');
        head.className = 'bart-result-head';
        var headTitle = document.createElement('span');
        var headMeta = document.createElement('span');
        head.appendChild(headTitle);
        head.appendChild(headMeta);

        var body = document.createElement('div');
        body.className = 'bart-result-body';

        if (_revealed && _matched) {
            _resultEl.classList.add('matched');
            headTitle.textContent = '出杯台 · 调制成功';
            headMeta.textContent = (_matched.recipe.englishTitle || _matched.recipe.recipeId).toUpperCase();

            var snap = snapshotByIndex(_matched.recipe.recipeIndex);
            var thumb = document.createElement('span');
            thumb.className = 'bart-drink-thumb';
            if (snap) thumb.innerHTML = _host.iconHtml(snap.output.icon, 'bart-icon');

            var info = document.createElement('div');
            info.className = 'bart-result-info';
            var name = document.createElement('b');
            var kOpt = _matched.recipe.technique && _matched.recipe.technique.karmotrine === 'optional';
            var kSuffix = kOpt ? (_matched.technique && _matched.technique.karmotrine ? '（加醇版）' : '（无醇版）') : '';
            name.textContent = _matched.recipe.title + kSuffix;

            var state = document.createElement('small');
            state.textContent = _previewBusy ? '正在向吧台核算材料与杯具…'
                : _preview && _preview.canCommit ? ('配方成立！' + (_matched.recipe.blurb || '点击右下角「上酒」完成出杯。'))
                : _preview ? errorMessage(_preview.blockingError)
                : _commitFeedback || '正在核算…';

            info.appendChild(name);
            info.appendChild(state);
            body.appendChild(thumb);
            body.appendChild(info);
        } else if (_revealed && !_matched && mixHasAnyPour()) {
            var hazard = diagnoseMolotov();
            _resultEl.classList.add('is-molotov');
            headTitle.textContent = '⚠ 吧台险情 · 莫洛托夫雏形（酒手雷）';
            headMeta.textContent = 'VOLATILE // 严禁出杯';

            var badge = document.createElement('span');
            badge.className = 'bart-molotov-badge';
            badge.innerHTML = molotovSvgHtml();

            var hInfo = document.createElement('div');
            hInfo.className = 'bart-result-info';
            var hName = document.createElement('b');
            hName.textContent = hazard.title;
            var hDesc = document.createElement('small');
            hDesc.textContent = hazard.reason;
            hInfo.appendChild(hName);
            hInfo.appendChild(hDesc);
            body.appendChild(badge);
            body.appendChild(hInfo);
        } else {
            headTitle.textContent = _shaking ? '调酒壶 · 正在摇制中' : '出杯台 · 待命';
            var mods = [];
            if (_mix && _mix.ice) mods.push('加冰');
            if (_mix && _mix.aged) mods.push('陈化');
            headMeta.textContent = mods.length ? ('已选：' + mods.join(' + ')) : '未加冰 · 未陈化';

            var hint = document.createElement('div');
            hint.className = 'bart-result-hint';
            hint.textContent = !_spec ? (_specFailed ? '酒单规格缺失，无法调配。' : '载入酒单中…')
                : _shaking ? '调酒壶摇晃中……轻摇请于 5 秒内点击「停止」，猛摇请等待满 5 秒后再点击「停止」！'
                : mixHasAnyPour() ? ('已向壶中投入 ' + totalPoured() + ' 份提取物。核对加冰/陈化后，点「调制」起摇或「直调」开壶揭晓。')
                : '翻阅左侧只读酒单，向右侧分配器手动投放原料（上限 20 格），再摇壶调制。';
            body.appendChild(hint);
        }

        _resultEl.appendChild(head);
        _resultEl.appendChild(body);
    }

    function footerNote() {
        if (!_spec) return _specFailed ? '酒单规格缺失。' : '载入中…';
        if (_shaking) return '摇壶计时中——观察中央进度条并在准确时机点击「停止」。';
        if (!_revealed) {
            return mixHasAnyPour()
                ? '待开壶：请点击「调制」起摇后「停止」揭晓，或点「直调」免摇开壶。'
                : '投料阶段不剧透结果；调配失败将产生危险的「酒手雷」，可免费「重做」。';
        }
        if (!_matched) {
            return '当前为高危「酒手雷」险情，不可端给客人——请点左侧「重做」无损倾倒。';
        }
        if (_previewBusy) return '正在核算…';
        if (_commitFeedback) return _commitFeedback;
        if (_preview && _preview.canCommit) return '将出品「' + _matched.recipe.title + '」，点击「上酒」完成。';
        if (_preview) return errorMessage(_preview.blockingError);
        return '正在核算…';
    }

    function renderSlot(name) {
        var meta = materialMeta(name);
        var count = _mix.counts[name] || 0;
        var owned = meta ? Number(meta.owned) : null;
        var total = totalPoured();
        var slot = document.createElement('div');
        slot.className = 'bart-slot' + (count > 0 ? ' filled' : '')
            + (_lastPouredSlot === name ? ' is-pumping' : '')
            + (owned !== null && count > owned ? ' over' : '');
        slot.setAttribute('data-tone', slotTone(name));

        var codeEl = document.createElement('span');
        codeEl.className = 'bart-slot-code';
        codeEl.textContent = slotCode(name);

        var icon = document.createElement('span');
        icon.className = 'bart-slot-icon';
        icon.setAttribute('title', '点击投入 1 份' + name);
        if (meta && meta.icon) icon.innerHTML = _host.iconHtml(meta.icon, 'bart-icon-sm');
        icon.addEventListener('click', function() {
            if (!_busy && !_shaking && total < TOTAL_SLOT_MAX) setCount(name, count + 1);
        });

        var label = document.createElement('span');
        label.className = 'bart-slot-name';
        label.textContent = name;

        var flavorEl = document.createElement('span');
        flavorEl.className = 'bart-slot-flavor';
        flavorEl.textContent = slotFlavorTag(name);

        var stock = document.createElement('span');
        stock.className = 'bart-slot-stock';
        stock.textContent = owned === null ? '…' : '剩余 ' + owned;

        slot.appendChild(codeEl);
        slot.appendChild(icon);
        slot.appendChild(label);
        slot.appendChild(flavorEl);
        slot.appendChild(stock);

        var stepper = document.createElement('div');
        stepper.className = 'bart-slot-count';
        var minus = document.createElement('button');
        minus.type = 'button'; minus.textContent = '−';
        minus.setAttribute('aria-label', '减少一份' + name);
        minus.disabled = _busy || _shaking || count <= 0;
        minus.addEventListener('click', function() { setCount(name, count - 1); });

        var value = document.createElement('span');
        value.className = 'bart-slot-value';
        value.textContent = String(count);

        var plus = document.createElement('button');
        plus.type = 'button'; plus.textContent = '+';
        plus.setAttribute('aria-label', '增加一份' + name);
        plus.disabled = _busy || _shaking || total >= TOTAL_SLOT_MAX;
        plus.addEventListener('click', function() { setCount(name, count + 1); });

        stepper.appendChild(minus); stepper.appendChild(value); stepper.appendChild(plus);
        slot.appendChild(stepper);
        return slot;
    }

    function optionButton(field, label, extraCls) {
        var button = document.createElement('button');
        button.type = 'button';
        button.className = 'bart-tech-btn toggle ' + (extraCls || '')
            + (_mix[field] === true ? ' active' : '');
        button.textContent = label;
        button.setAttribute('aria-pressed', _mix[field] === true ? 'true' : 'false');
        button.disabled = _busy || _shaking;
        button.addEventListener('click', function() { toggleOption(field); });
        return button;
    }

    /* ── 杂项 ── */

    function applyBalance(balance) {
        if (!balance) return;
        _moneyEl.textContent = '金币 ' + _host.formatNumber(balance.money);
        _kpointsEl.textContent = 'K点 ' + _host.formatNumber(balance.kpoints);
    }

    function setStatus(text, state) {
        _statusEl.textContent = text;
        _statusEl.setAttribute('data-state', state);
    }

    function errorMessage(error) {
        var messages = {category_not_found:'未找到调酒分类。', recipe_not_found:'酒单已变化。',
            item_not_found:'未找到该原料或酒品。', level_locked:'角色等级与逆向等级不足。',
            infrastructure_locked:'吧台设备未就绪。',
            material_missing:'所需原料不足。', insufficient_money:'金币不足。',
            insufficient_kpoint:'K 点不足。', inventory_full:'背包空间不足。',
            stale_state:'物品状态已变化，请重新核对。', batch_not_supported:'该酒品只能逐杯调制。',
            technique_mismatch:'调制方式与配方不符，请核对摇法与选项。',
            technique_not_supported:'该配方没有调制方式要求。',
            busy:'吧台正在处理另一份调制。', reconcile_required:'上次提交结果需要重新核对。',
            stale_snapshot:'酒单目录已更新，请重新同步。',
            malformed_response:'回包不完整。', timeout:'调酒响应超时。',
            client_timeout:'调酒响应超时。', disconnected:'连接已断开。'};
        return messages[error] || '调酒操作失败，请重试。';
    }

    function toast(message) { if (_host && _host.toast) _host.toast(message); }
    function cue(name) { if (_host && _host.cue) _host.cue(name); }

    return {
        mount:mount,
        unmount:unmount,
        refresh:refresh,
        advanceShake:function(ms) { advanceShakeInternal(ms); },
        isBusy:function() { return _busy || _previewBusy; },
        debugState:function() { return {
            filter:{tab:_filter.tab, value:_filter.value},
            inspectedIndex:_inspectedIndex,
            mix:_mix ? {
                counts:_mix.counts,
                totalPoured:totalPoured(),
                ice:_mix.ice,
                aged:_mix.aged,
                shake:_mix.shake
            } : null,
            shaking:_shaking,
            shakeElapsedMs:_shakeElapsedMs,
            revealed:_revealed,
            molotov:(_revealed && !_matched && mixHasAnyPour()) ? diagnoseMolotov() : null,
            matched:_matched ? _matched.recipe.recipeIndex : null,
            unlockedSecrets:Object.keys(_unlockedSecrets),
            audioLog:_audioLog.slice(),
            specLoaded:!!_spec, specFailed:_specFailed,
            materialsLoaded:!!_materials,
            busy:_busy, previewBusy:_previewBusy
        }; }
    };
})();
