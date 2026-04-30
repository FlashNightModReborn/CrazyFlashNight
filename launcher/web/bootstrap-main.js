// Bootstrap main IIFE — launcher ↔ WebView2 protocol + view switcher + welcome flow
// 从 bootstrap.html 抽出，方便读写。所有 DOM id 依赖 bootstrap.html。

(function() {
  'use strict';

  // ── 元素引用 ──
  var logEl = document.getElementById('log');
  var cardsEl = document.getElementById('cards');
  var stateBadge = document.getElementById('state-badge');
  var retryBtn = document.getElementById('btn-retry');
  var cancelLaunchBtn = document.getElementById('btn-cancel-launch');
  var viewWelcome = document.getElementById('view-welcome');
  var viewSlots = document.getElementById('view-slots');
  var welcomeSlotNameEl = document.getElementById('welcome-slot-name');
  var welcomeSlotTimeEl = document.getElementById('welcome-slot-time');
  var btnConfirmStart = document.getElementById('btn-confirm-start');
  var btnSwitchSlot = document.getElementById('btn-switch-slot');
  var chkIntro = document.getElementById('chk-intro');

  // ── Phase D Step D12: launch-in-flight 本地状态 ──
  var _launchInFlight = false;
  function setLaunchInFlight(flag) {
    _launchInFlight = flag;
    if (flag) document.body.classList.add('launch-in-flight');
    else document.body.classList.remove('launch-in-flight');
  }

  // 原版 10 个预设槽位
  var PRESET_SLOTS = [
    'crazyflasher7_saves',  'crazyflasher7_saves1', 'crazyflasher7_saves2',
    'crazyflasher7_saves3', 'crazyflasher7_saves4', 'crazyflasher7_saves5',
    'crazyflasher7_saves6', 'crazyflasher7_saves7', 'crazyflasher7_saves8',
    'crazyflasher7_saves9'
  ];
  var SLOT_NAME_RE = /^[a-zA-Z0-9_-]{1,32}$/;

  var lastSlotsFromLauncher = [];
  var _lastLaunchState = 'Idle';
  var _welcomeSlot = null;        // 当前欢迎页展示的默认槽位对象
  var _introActive = false;       // 片头视频是否正在播
  var _handlers = {};             // onMessage 注册表

  // Phase 2b: UserPrefs 字段, 初次 list_resp 前是未初始化占位 —
  //   lastPlayedSlot: null 表示"没有已记录的上次槽位" (新玩家 / 偏好文件不存在)
  //   introEnabled:   默认 false, 与 Flash 原版"加载片头动画默认关"一致
  // 这俩跟 list_resp 一起从 launcher 推过来.
  var _prefsLastPlayedSlot = null;
  var _prefsIntroEnabled = false;
  var _prefsSfxEnabled = true;
  var _prefsAmbientEnabled = false;
  var _prefsUiFontScale = 1.35;
  var _prefsReceived = false;     // 首个 list_resp 到达前不做任何 config_set (避免 init 时被 onchange 回写 false 覆盖)

  // 字号缩放: 4 档预设 + clamp 范围 (与 C# UserPrefs.ClampFontScale 一致)
  // 基准 1.35 (用户在测试机上反馈旧 1.0 偏小, 1.35 刚好), 预设向上偏移
  var FONT_SCALE_MIN = 0.7;
  var FONT_SCALE_MAX = 1.9;
  var FONT_SCALE_PRESETS = [
    { value: 1.15, label: '紧凑' },  // 紧凑 (大屏/密集布局)
    { value: 1.35, label: '标准' },  // 标准 (默认)
    { value: 1.55, label: '大' },        // 大 (轻松阅读)
    { value: 1.75, label: '超大' }   // 超大 (GPD 掌机 / 高 DPI)
  ];

  function clampFontScale(v) {
    if (typeof v !== 'number' || isNaN(v) || !isFinite(v)) return 1.35;
    if (v < FONT_SCALE_MIN) return FONT_SCALE_MIN;
    if (v > FONT_SCALE_MAX) return FONT_SCALE_MAX;
    return v;
  }

  function applyFontScale(v) {
    v = clampFontScale(v);
    _prefsUiFontScale = v;
    // 写到 :root 上；bootstrap.css 直接以用户选择作为 --fs-scale。
    document.documentElement.style.setProperty('--user-fs-scale', String(v));
  }

  // config_set 的"服务端权威对齐"机制 (Plan A+).
  // 每次 sendConfigSet(key, value, applyFn) 生成独立 requestId, applyFn 按 id 登记、按 id 消费.
  //
  // applyFn(authoritative) 的语义:
  //   无条件把 UI 对齐到参数值 (= resp.currentValue = 服务端真实值).
  //   不是"回滚到本地 prior", 不依赖客户端记忆. 失败/成功都调 applyFn, 成功下通常是
  //   幂等 no-op (optimistic UI 已经对上), 失败下把漂移的 UI 拉回服务端 rollback 后的真值.
  //
  // 协议:
  //   out: {cmd:'config_set', key, value, requestId:N}
  //   in:  {cmd:'config_set_resp', requestId:N, key, ok, error?, currentValue?}
  //   约定: 除未知 key / userPrefs 不可用外, 服务端总是附带 currentValue.
  //
  // 这一层消灭了"连续失败级联导致 UI 停在乐观中间态"的所有场景 —— 即便 optimistic prior
  // 捕获时机错位、响应乱序、多请求并发, UI 最终状态只信服务端, 不信本地记忆.
  var _configSetNextId = 1;
  var _configSetApplies = {};  // Map<requestId, applyFn(authoritative)>

  function sendConfigSet(key, value, applyFn) {
    var reqId = _configSetNextId++;
    if (applyFn) _configSetApplies[reqId] = applyFn;
    send({ cmd: 'config_set', key: key, value: value, requestId: reqId });
    return reqId;
  }

  // 用户在 slot 页主动选择的槽位 + 模式 ('normal' = 加载现有存档 / 'fresh' = 新建或重建).
  // 设置后回到欢迎页, _welcomeSlot 优先使用该槽位; 「确认」按 mode 分发到 start_game / rebuild.
  // null = 未主动选择, 欢迎页走 pickDefaultSlot 默认规则 (lastPlayedSlot / 第一个健康 preset ...).
  var _userSelectedSlot = null;
  var _userSelectedMode = null;

  // ── Web Audio 捷径 (BootstrapAudio 由 modules/audio.js 在 main 之前注入) ──
  // Autoplay policy 下 AudioContext 初始 suspended, 首次用户交互后需手动 resume.
  // audio.js 缺失或无 AudioContext 时 Audio 为 null, 所有调用点需 if (Audio) 守卫.
  var Audio = window.BootstrapAudio || null;

  function playUiCue(name) {
    if (!Audio || !name) return;
    var fn = Audio[name];
    if (typeof fn !== 'function') return;
    try {
      Audio.resume();
      fn.call(Audio);
    } catch (e) {
      logLine('tag-err', '[Audio] cue failed: ' + name + ' ' + e.message);
    }
  }

  // ── 工具 ──
  function logLine(cls, text) {
    var d = new Date(), ts = d.toTimeString().slice(0, 8);
    var span = document.createElement('span');
    span.className = cls;
    span.textContent = '[' + ts + '] ' + text + '\n';
    logEl.appendChild(span);
    logEl.scrollTop = logEl.scrollHeight;
  }

  function send(obj) {
    obj.type = 'bootstrap';
    var json = JSON.stringify(obj);
    logLine('tag-out', '→ ' + json);
    try { window.chrome.webview.postMessage(json); }
    catch (e) { logLine('tag-err', 'postMessage failed: ' + e.message); }
  }

  function escapeHtml(s) {
    if (s == null) return '';
    return String(s).replace(/[&<>"']/g, function(c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  function fmtBytes(n) {
    if (!n) return '';
    if (n < 1024) return n + 'B';
    return (n / 1024).toFixed(1) + 'KB';
  }

  function presetDisplayName(slot) {
    var m = /^crazyflasher7_saves(\d*)$/.exec(slot);
    if (!m) return slot;
    var idx = m[1] === '' ? 0 : parseInt(m[1], 10);
    return '存档 ' + (idx + 1);
  }

  function mergeSlots(fromLauncher) {
    var byName = {};
    for (var i = 0; i < fromLauncher.length; i++) byName[fromLauncher[i].slot] = fromLauncher[i];
    var merged = [];
    for (var j = 0; j < PRESET_SLOTS.length; j++) {
      var slot = PRESET_SLOTS[j];
      var data = byName[slot];
      if (data) { merged.push(data); delete byName[slot]; }
      else merged.push(emptyPlaceholder(slot, true));
    }
    var rest = [];
    for (var key in byName) if (byName.hasOwnProperty(key)) rest.push(byName[key]);
    rest.sort(function(a, b) { return a.slot < b.slot ? -1 : a.slot > b.slot ? 1 : 0; });
    return merged.concat(rest);
  }

  function emptyPlaceholder(slot, isPreset) {
    return {
      slot: slot, corrupt: false, tombstoned: false, inconsistent: false,
      mainProgress: null, size: 0, lastModified: null, __empty: true, __preset: !!isPreset
    };
  }

  // ── 视图切换 ──
  function showWelcome() {
    var changed = viewWelcome.hidden || !viewSlots.hidden;
    viewWelcome.hidden = false;
    viewSlots.hidden = true;
    renderWelcomeSlot();
    if (changed) playUiCue('playTransition');
  }
  function showSlots() {
    var changed = viewSlots.hidden || !viewWelcome.hidden;
    viewWelcome.hidden = true;
    viewSlots.hidden = false;
    if (changed) playUiCue('playTransition');
  }

  // ── 欢迎页默认 slot 选择 ──
  // 2b: 优先 launcher 推来的 lastPlayedSlot, 且该 slot 在当前列表里存在且可用 (非 corrupt/tombstoned/inconsistent)
  // 回退: 第一个"有进度的正常 preset" → 第一个 preset (空槽, 触发新建流程) → 第一个 slot
  function pickDefaultSlot() {
    var slots = mergeSlots(lastSlotsFromLauncher);
    // 0) 用户从 slot 页主动选择的槽位优先. 若 list 刷新后该槽位状态与 mode 不兼容, 清除选择降级.
    if (_userSelectedSlot) {
      for (var x = 0; x < slots.length; x++) {
        if (slots[x].slot !== _userSelectedSlot) continue;
        var sel = slots[x];
        var modeOk = (_userSelectedMode === 'fresh')
          ? !sel.corrupt
          : (!sel.__empty && !sel.corrupt && !sel.tombstoned && !sel.inconsistent);
        if (modeOk) return sel;
        break;
      }
      _userSelectedSlot = null;
      _userSelectedMode = null;
    }
    // 1) 优先 lastPlayedSlot
    if (_prefsLastPlayedSlot) {
      for (var a = 0; a < slots.length; a++) {
        var sa = slots[a];
        if (sa.slot === _prefsLastPlayedSlot && !sa.__empty && !sa.corrupt && !sa.tombstoned && !sa.inconsistent) {
          return sa;
        }
      }
    }
    // 2) 第一个"有进度的正常 preset"
    for (var i = 0; i < slots.length; i++) {
      var s = slots[i];
      if (!s.__empty && !s.corrupt && !s.tombstoned && !s.inconsistent) return s;
    }
    // 3) 第一个 preset (空槽, 新建流程)
    for (var j = 0; j < slots.length; j++) if (slots[j].__preset) return slots[j];
    return slots[0] || null;
  }

  // 当前 effective mode: 用户显式 mode 优先; 未显式时按 slot 状态降级 (空槽 → fresh, 否则 normal).
  function effectiveMode(s) {
    if (_userSelectedMode) return _userSelectedMode;
    if (s && s.__empty) return 'fresh';
    return 'normal';
  }

  function renderWelcomeSlot() {
    var s = pickDefaultSlot();
    _welcomeSlot = s;
    if (!s) {
      welcomeSlotNameEl.textContent = '无可用存档';
      welcomeSlotTimeEl.textContent = '—';
      applyConfirmLabel('normal', null);
      return;
    }
    welcomeSlotNameEl.textContent = presetDisplayName(s.slot);

    var mode = effectiveMode(s);
    var modeHint = '';
    if (mode === 'fresh') {
      modeHint = s.__empty
        ? '<span class="flag fresh-mode">将新建角色</span>'
        : '<span class="flag fresh-mode">将重建 · 原数据丢弃</span>';
    }

    if (s.__empty) {
      welcomeSlotTimeEl.innerHTML = modeHint || '<span class="flag empty">空槽位</span>';
    } else {
      var meta = fmtBytes(s.size);
      if (s.lastModified) meta += ' · ' + s.lastModified.slice(0, 16).replace('T', ' ');
      var flags = '';
      if (s.corrupt)      flags = '<span class="flag corrupt">损坏</span>';
      if (s.tombstoned)   flags = '<span class="flag tombstoned">已删除</span>';
      if (s.inconsistent) flags = '<span class="flag inconsistent">不一致</span>';
      welcomeSlotTimeEl.innerHTML = modeHint + flags + escapeHtml(meta);
    }
    applyConfirmLabel(mode, s);
  }

  // 按 mode + slot 状态调整「确认」按钮文案 (Error 态由 applyState 负责 .retry 样式, 这里不动).
  function applyConfirmLabel(mode, s) {
    if (!btnConfirmStart) return;
    if (_lastLaunchState === 'Error') return;
    if (mode === 'fresh') {
      btnConfirmStart.textContent = (s && s.__empty) ? '新 建 角 色' : '重 建';
    } else {
      btnConfirmStart.textContent = '确 认';
    }
  }

  // 从槽位页主动选择一个槽位, 回到欢迎页. 不直接启动 — 保留用户勾选片头动画的机会.
  // showWelcome() 内部会触发 renderWelcomeSlot → applyConfirmLabel 自动反映 mode.
  function selectSlotAndReturn(slotName, mode) {
    _userSelectedSlot = slotName;
    _userSelectedMode = mode;
    showWelcome();
  }

  // ── 随机背景 ──
  function loadRandomBackground() {
    var bgEl = document.getElementById('bg-photo');
    if (!bgEl) return;
    fetch('assets/bg/manifest.json')
      .then(function(r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function(m) {
        if (!m.backgrounds || !m.backgrounds.length) {
          logLine('tag-err', '[bg] manifest empty');
          return;
        }
        var pick = m.backgrounds[Math.floor(Math.random() * m.backgrounds.length)];
        bgEl.style.backgroundImage = 'url(assets/bg/' + pick + ')';
        logLine('tag-in', '[bg] ' + pick + ' (' + m.backgrounds.length + ' available)');
      })
      .catch(function(err) {
        bgEl.style.backgroundColor = '#0a0c0f';
        logLine('tag-err', '[bg] fetch failed: ' + (err && err.message ? err.message : err));
      });
  }

  // ── 片头视频 / 加载 overlay (Phase 2b-ext: 并行 Flash 加载) ──
  // 两相 overlay:
  //   [video 相] ov.on (无 loading 类): 视频播放, 跳过按钮可见, ESC=跳过→onVideoDone
  //   [loading 相] ov.on.loading: spinner + "启动中", ESC=cancel_launch
  //
  // 关键设计: start_game 在点"确认"的瞬间立即发 (而非视频结束后), 带上:
  //   deferReveal:true          — launcher 到 Ready 时不立即 panel swap
  //   requireFlashReveal:true   — 等 Flash 封面帧 bootstrap_reveal_ready 才 swap
  // 视频播放期间 Flash 并行完成 embed / asset 加载 / AS2 init / 封面渲染.
  // onVideoDone (视频结束/跳过/错误) 时 send reveal_ok: launcher 清 _revealWaitingJs,
  // 若 Flash 也已发过 reveal_ready (通常已到达), 立即 panel swap; 否则等 Flash.
  // Panel swap 让 BootstrapPanel 不可见 → overlay 随之隐藏 (无需 JS 主动 hide).
  //
  // 无片头路径类似: start_game 也带 requireFlashReveal:true (不带 deferReveal),
  // loading spinner 覆盖 Flash 初始化期, 等 Flash 封面帧到达自动 swap.

  function playIntroThenStart(slot, mode) {
    var ov = document.getElementById('intro-ov');
    var vid = document.getElementById('intro-video');
    var skipBtn = document.getElementById('intro-skip');
    _introActive = true;
    document.body.classList.add('intro-playing');
    ov.classList.remove('loading');
    ov.classList.add('on');
    skipBtn.style.display = '';
    try {
      vid.preload = 'auto';
      vid.load();
      vid.currentTime = 0;
    } catch (e) {}
    // 立即 send 启动命令 + defer flags, 让视频播放与 Flash 加载并行.
    // mode='fresh' 走 rebuild (launcher 侧先 DeleteAllSolFiles + ResetSlotSync 再 spawn).
    setLaunchInFlight(true);
    var cmd = (mode === 'fresh') ? 'rebuild' : 'start_game';
    send({ cmd: cmd, slot: slot.slot, deferReveal: true, requireFlashReveal: true });
    var fired = false;
    function onVideoDone(reason) {
      if (fired) return;
      fired = true;
      if (reason) logLine('tag-in', 'intro handoff: ' + reason);
      try { vid.pause(); vid.onended = null; vid.onerror = null; } catch (e) {}
      skipBtn.onclick = null;
      // 切到 loading 相: 视频淡出, spinner 淡入; 若 Flash 已 reveal_ready, 下一刻即 panel swap.
      ov.classList.add('loading');
      send({ cmd: 'reveal_ok' });
    }
    vid.onended = function() { onVideoDone('video_end'); };
    vid.onerror = function(e) {
      var err = (vid.error && vid.error.message) || (e && e.message) || 'unknown';
      logLine('tag-err', 'intro video error: ' + err);
      onVideoDone('video_error');
    };
    skipBtn.onclick = function() { onVideoDone('user_skip'); };
    var p = vid.play();
    if (p && typeof p.then === 'function') {
      p.catch(function(e) {
        logLine('tag-err', 'intro play rejected: ' + (e && e.message || e));
        onVideoDone('play_rejected');
      });
    }
  }

  function showLoadingOverlay() {
    var ov = document.getElementById('intro-ov');
    var skipBtn = document.getElementById('intro-skip');
    _introActive = true;
    document.body.classList.add('intro-playing');
    ov.classList.add('on', 'loading');
    skipBtn.onclick = null;
    skipBtn.style.display = 'none';
  }

  function hideLaunchOverlay() {
    if (!_introActive) return;
    var ov = document.getElementById('intro-ov');
    var vid = document.getElementById('intro-video');
    var skipBtn = document.getElementById('intro-skip');
    _introActive = false;
    try { vid.pause(); vid.onended = null; vid.onerror = null; } catch (e) {}
    ov.classList.remove('on', 'loading');
    document.body.classList.remove('intro-playing');
    skipBtn.onclick = null;
    skipBtn.style.display = '';
    // 复位 flash-ready 样式 (下一 attempt 全新开始)
    skipBtn.classList.remove('flash-ready');
    skipBtn.textContent = '跳 过 · ESC';
  }

  // 所有"无片头" start_game 入口统一封装: loading overlay + 带 requireFlashReveal flag.
  // 欢迎页无片头分支 / 槽位卡片"开始" / "新建角色" 都走这里.
  // requireFlashReveal 让 panel swap 等 Flash 封面帧, 遮掩 Flash 自身初始化期间.
  function initiateLaunch(slotName) {
    if (_launchInFlight) return;
    showLoadingOverlay();
    setLaunchInFlight(true);
    send({ cmd: 'start_game', slot: slotName, requireFlashReveal: true });
  }
  function initiateFreshLaunch(slotName) {
    if (_launchInFlight) return;
    showLoadingOverlay();
    setLaunchInFlight(true);
    send({ cmd: 'rebuild', slot: slotName, requireFlashReveal: true });
  }

  function renderCards(slots) {
    cardsEl.innerHTML = '';
    var merged = mergeSlots(slots || []);
    for (var i = 0; i < merged.length; i++) cardsEl.appendChild(renderCard(merged[i]));
  }

  function renderCard(s) {
    var classes = ['card'];
    if (s.__empty)      classes.push('empty-slot');
    if (s.corrupt)      classes.push('corrupt');
    if (s.tombstoned)   classes.push('tombstoned');
    if (s.inconsistent) classes.push('inconsistent');
    var card = document.createElement('div');
    card.className = classes.join(' ');

    var flags = '';
    if (s.__empty && s.__preset) flags += '<span class="flag empty">空槽位</span>';
    if (s.corrupt)      flags += '<span class="flag corrupt">损坏</span>';
    if (s.tombstoned && !s.inconsistent) flags += '<span class="flag tombstoned">已删除</span>';
    if (s.inconsistent) flags += '<span class="flag inconsistent">不一致</span>';

    var meta = '';
    if (!s.__empty) {
      meta = fmtBytes(s.size);
      if (s.lastModified) meta += ' · ' + s.lastModified.slice(0, 16).replace('T', ' ');
    }

    var displayName = presetDisplayName(s.slot);
    var progressText = s.__empty ? '—' : (s.mainProgress || '—');

    var actions = '';
    if (s.__empty) {
      actions = '<button class="btn-newchar">新建角色</button>';
    } else if (s.inconsistent) {
      actions = '<button class="btn-rebuild">重建</button>'
              + '<button class="btn-edit">编辑</button>'
              + '<button class="btn-export">导出</button>'
              + '<button class="btn-reset danger">清理副本</button>';
    } else if (s.tombstoned) {
      actions = '<button class="btn-rebuild">重建</button>'
              + '<button class="btn-reset danger">清理副本</button>';
    } else if (s.corrupt) {
      actions = '<button class="btn-edit">编辑</button>'
              + '<button class="btn-export">导出</button>'
              + '<button class="btn-delete danger">删除</button>'
              + '<button class="btn-reset danger">清理副本</button>';
    } else {
      actions = '<button class="btn-start primary">选择</button>'
              + '<button class="btn-edit">编辑</button>'
              + '<button class="btn-export">导出</button>'
              + '<button class="btn-delete danger">删除</button>';
    }

    card.innerHTML =
      '<div class="slot">' + escapeHtml(displayName) + '</div>' +
      '<div class="slot-id">' + escapeHtml(s.slot) + '</div>' +
      '<div class="progress">' + escapeHtml(progressText) + '</div>' +
      '<div class="meta">' + flags + meta + '</div>' +
      '<div class="card-actions">' + actions + '</div>';

    var startBtn   = card.querySelector('.btn-start');
    var deleteBtn  = card.querySelector('.btn-delete');
    var rebuildBtn = card.querySelector('.btn-rebuild');
    var newCharBtn = card.querySelector('.btn-newchar');
    var editBtn    = card.querySelector('.btn-edit');
    var exportBtn  = card.querySelector('.btn-export');
    var resetBtn   = card.querySelector('.btn-reset');

    if (startBtn) startBtn.onclick = function() { selectSlotAndReturn(s.slot, 'normal'); };
    if (deleteBtn) deleteBtn.onclick = function() {
      if (confirm('确定删除存档 "' + displayName + '" ?')) send({ cmd: 'delete', slot: s.slot });
    };
    if (rebuildBtn) rebuildBtn.onclick = function() {
      if (confirm('重建存档 "' + displayName + '" (原数据将丢弃)?')) selectSlotAndReturn(s.slot, 'fresh');
    };
    if (newCharBtn) newCharBtn.onclick = function() { selectSlotAndReturn(s.slot, 'fresh'); };
    if (editBtn) editBtn.onclick = function() {
      window.BootstrapApp.openModal('archive-editor', { slot: s.slot, slotMeta: s });
    };
    if (exportBtn) exportBtn.onclick = function() {
      var forceRaw = !!(s.corrupt || s.inconsistent);
      var dn = presetDisplayName(s.slot);
      var ts = new Date().toISOString().slice(0, 10).replace(/-/g, '');
      send({ cmd: 'export', slot: s.slot, defaultName: dn + '_' + ts + '.json', forceRaw: forceRaw });
    };
    if (resetBtn) resetBtn.onclick = function() {
      if (confirm('确定清理 "' + displayName + '" 的 launcher 副本?\n\n此操作仅清理 launcher 侧 JSON 备份和删除标记，不影响 Flash 内部 SOL 存档。'))
        send({ cmd: 'reset', slot: s.slot, confirm: true });
    };
    return card;
  }

  function pickAutoSlotName() {
    var occupied = {};
    for (var i = 0; i < lastSlotsFromLauncher.length; i++) occupied[lastSlotsFromLauncher[i].slot] = true;
    for (var j = 0; j < PRESET_SLOTS.length; j++) if (!occupied[PRESET_SLOTS[j]]) return PRESET_SLOTS[j];
    return 'custom_' + Date.now();
  }

  function handleNewCharacterClick() {
    if (_launchInFlight) return;
    var defaultName = pickAutoSlotName();
    playUiCue('playModalOpen');
    var input = prompt(
      '输入存档名称:\n'
      + '• 留空自动选用: ' + defaultName + '\n'
      + '• 仅允许字母/数字/下划线/短横线, 1-32 字符',
      defaultName);
    if (input == null) { playUiCue('playCancel'); return; }
    var slot = input.trim();
    if (!slot) slot = defaultName;
    if (!SLOT_NAME_RE.test(slot)) { playUiCue('playError'); alert('存档名称不合法: ' + slot); return; }
    for (var k = 0; k < lastSlotsFromLauncher.length; k++) {
      if (lastSlotsFromLauncher[k].slot === slot) {
        var entry = lastSlotsFromLauncher[k];
        if (entry.tombstoned) {
          if (!confirm('此档已删除, 是否重建?')) return;
          selectSlotAndReturn(slot, 'fresh'); return;
        }
        if (!confirm('存档 "' + slot + '" 已存在, 直接加载?')) return;
        selectSlotAndReturn(slot, 'normal'); return;
      }
    }
    selectSlotAndReturn(slot, 'fresh');
  }

  // ── State 广播 ──
  function applyState(state, msg) {
    var prevState = _lastLaunchState;
    _lastLaunchState = state;
    // 音频反馈: Error 进入时 tap, Idle 从非 Idle 回来时恢复 ambient.
    // Ready 不单独播 — flash_ready 消息专门负责 ready 和弦 (更精确的时机).
    if (Audio) {
      if (state === 'Error' && prevState !== 'Error') Audio.playError();
      if (state === 'Idle' && prevState !== 'Idle' && _prefsAmbientEnabled) Audio.startAmbient();
    }
    stateBadge.textContent = state + (msg ? ': ' + msg : '');
    stateBadge.className = 'state-badge';
    if (state === 'Ready')       stateBadge.className += ' ready';
    else if (state === 'Error')  stateBadge.className += ' error';
    else if (state !== 'Idle')   stateBadge.className += ' running';
    retryBtn.style.display = (state === 'Error') ? '' : 'none';
    var launchInProgress = (state === 'Spawning' || state === 'WaitingConnect'
                         || state === 'WaitingHandshake' || state === 'Embedding'
                         || state === 'WaitingGameReady');
    cancelLaunchBtn.style.display = launchInProgress ? '' : 'none';

    // 欢迎页确认按钮在 Error 态切成重试样式
    if (btnConfirmStart) {
      if (state === 'Error') btnConfirmStart.classList.add('retry');
      else btnConfirmStart.classList.remove('retry');
    }

    if (state === 'Idle') {
      setLaunchInFlight(false);
      // 只在 loading 相 (start_game 已发 + 正等 reveal) 才 hide overlay —
      // 视频相期间的 Idle 广播 (不会再出现了, 因为并行路径下 prewarm deadline 在 start_game
      // 发出后自动 cancel; 仍保留保险, 万一 launcher 异常回到 Idle 也能退出 overlay).
      var ovIdle = document.getElementById('intro-ov');
      if (ovIdle && ovIdle.classList.contains('loading')) hideLaunchOverlay();
    } else if (state === 'Ready') {
      // Phase 2b-ext: Ready 广播不再立即 hide overlay. panel swap 被 launcher 按 defer flags
      // gate 住 (_revealWaitingJs / _revealWaitingFlash). 真正 swap 发生时 BootstrapPanel 不可见,
      // overlay 随之自然隐藏, 无需 JS 操心.
      // 注意: 视频相看到 Ready 是正常情况 (Flash 先 Ready 才发 reveal_ready, 视频还在播),
      // JS 不该动 overlay — 继续视频播放.
    } else if (state === 'Error') {
      hideLaunchOverlay();
      // 错误后 welcome 再可见, 确认按钮 .retry 样式 + 顶栏重试按钮
    }
  }

  // ── onMessage 分发 ──
  function dispatchMessage(msg) {
    var cmd = msg.cmd;
    if (!cmd) return;
    var arr = _handlers[cmd];
    if (arr) for (var i = 0; i < arr.length; i++) {
      try { arr[i](msg); } catch (e) { logLine('tag-err', 'handler error [' + cmd + ']: ' + e.message); }
    }
  }

  // ── WebView2 listener ──
  window.chrome.webview.addEventListener('message', function(e) {
    var data = e.data, msg;
    try { msg = (typeof data === 'string') ? JSON.parse(data) : data; }
    catch (err) { logLine('tag-err', 'bad JSON from C#: ' + err.message); return; }
    logLine('tag-in', '← ' + JSON.stringify(msg));

    if (msg.cmd === 'state')            applyState(msg.state, msg.msg);
    else if (msg.cmd === 'list_resp') {
      lastSlotsFromLauncher = msg.slots || [];
      // Phase 2b: 接收 launcher 推的 UserPrefs
      if (typeof msg.lastPlayedSlot === 'string') _prefsLastPlayedSlot = msg.lastPlayedSlot;
      if (typeof msg.introEnabled === 'boolean')  _prefsIntroEnabled   = msg.introEnabled;
      if (typeof msg.sfxEnabled === 'boolean')    _prefsSfxEnabled     = msg.sfxEnabled;
      if (typeof msg.ambientEnabled === 'boolean') _prefsAmbientEnabled = msg.ambientEnabled;
      if (typeof msg.uiFontScale === 'number')    applyFontScale(msg.uiFontScale);
      _prefsReceived = true;
      chkIntro.checked = _prefsIntroEnabled;
      if (Audio) {
        Audio.setSfxEnabled(_prefsSfxEnabled);
        // Ambient 的实际启停: AudioContext suspended 时 startAmbient 是 no-op, 等首次交互时恢复.
        Audio.setAmbientEnabled(_prefsAmbientEnabled);
      }
      renderCards(lastSlotsFromLauncher);
      renderWelcomeSlot();
    }
    else if (msg.cmd === 'config_set_resp') {
      // 按 requestId 取 applyFn (每个请求独立槽位, 连点/乱序都互不覆盖).
      // 取完即删, 无论 ok/fail 都清理, 避免内存泄漏.
      var reqId = (typeof msg.requestId === 'number') ? msg.requestId : null;
      var applyFn = (reqId != null) ? _configSetApplies[reqId] : null;
      if (reqId != null && _configSetApplies.hasOwnProperty(reqId)) delete _configSetApplies[reqId];

      if (!msg.ok) {
        logLine('tag-err', 'config_set failed: key=' + (msg.key || '?') + ' err=' + (msg.error || ''));
        playUiCue('playError');
      }

      // 权威对齐: applyFn 无条件按 currentValue 设 UI, 保持与服务端真实值一致.
      // hasOwnProperty 用来区分"字段缺失" (null/undefined 都通不过 hasOwnProperty) 和"显式 null"
      // (比如 lastPlayedSlot 可以合法地是 null).
      var hasCur = msg && Object.prototype.hasOwnProperty.call(msg, 'currentValue');
      if (applyFn && hasCur) {
        try {
          applyFn(msg.currentValue);
        } catch (e) {
          logLine('tag-err', 'config_set apply failed: ' + e.message + ' (fallback to list)');
          send({ cmd: 'list' });  // 兜底: 让 list_resp 把全量权威状态推回来
        }
      } else if (!msg.ok) {
        // 失败但我们没法 apply (缺 requestId / applyFn / currentValue), 用 list 兜底刷全量.
        // 正常路径不会走这里 — 到这条说明协议对端不匹配或调用方没传 applyFn.
        logLine('tag-err', 'config_set resp missing apply context (reqId=' + reqId + ' hasCurrent=' + hasCur + '), fallback to list');
        send({ cmd: 'list' });
      }
    }
    else if (msg.cmd === 'flash_ready') {
      var sk = document.getElementById('intro-skip');
      sk.classList.add('flash-ready');
      sk.textContent = '进入游戏 · ESC';
      // Flash 封面就绪: 同步响一次就绪和弦, 并关掉环境 hum 让位给 Flash BGM.
      if (Audio) { Audio.playReady(); Audio.stopAmbient(); }
    }
    else if (msg.cmd === 'delete_resp') {
      if (msg.ok) {
        playUiCue('playSuccess');
        send({ cmd: 'list' });
      } else {
        logLine('tag-err', 'delete failed: ' + msg.error);
        playUiCue('playError');
      }
    }
    else if (msg.cmd === 'error')       { logLine('tag-err', msg.code + ': ' + msg.msg); playUiCue('playError'); }
    else if (msg.cmd === 'pong')        logLine('tag-in', 'pong');
    else if (msg.cmd === 'reset_resp')  {
      if (msg.ok) {
        playUiCue('playSuccess');
        send({ cmd: 'list' });
      } else {
        logLine('tag-err', 'reset failed: ' + (msg.error || 'unknown'));
        playUiCue('playError');
      }
    }
    else if (msg.cmd === 'export_resp') {
      if (msg.ok) {
        logLine('tag-in', '导出成功: ' + (msg.path || ''));
        playUiCue('playSuccess');
      } else if (msg.error !== 'cancelled') {
        logLine('tag-err', '导出失败: ' + (msg.error || ''));
        playUiCue('playError');
      }
    }
    else if (msg.cmd === 'import_resp') {
      if (msg.ok) {
        logLine('tag-in', '导入成功: ' + (msg.slot || ''));
        playUiCue('playSuccess');
        send({ cmd: 'list' });
      } else if (msg.error !== 'cancelled') {
        logLine('tag-err', '导入失败: ' + (msg.error || ''));
        playUiCue('playError');
      }
    }
    else if (msg.cmd === 'import_target') handleImportTarget(msg);
    else if (msg.cmd === 'repair_required') {
      // C2-β: launcher 决议 saveDecision="repairable" 时主动推; 立即打开修复卡片让用户处理.
      // 卡片自身会发 repair_detect 拉完整 plan; 这里只负责 modal 入口.
      logLine('tag-in', 'repair_required slot=' + (msg.slot || '?')
        + ' totalFffd=' + (msg.summary && msg.summary.totalFffd) || '?');
      // 隐藏 launch overlay (intro 视频 / loading 圈) — 否则修复卡片会被压在底下.
      hideLaunchOverlay();
      openModal('repair-card', { slot: msg.slot, summary: msg.summary });
    }

    dispatchMessage(msg);
  });

  function handleImportTarget(msg) {
    var sourceData = msg.sourceData;
    var suggestedSlot = msg.suggestedSlot || '';
    playUiCue('playModalOpen');
    var slot = prompt('选择目标存档槽位:\n建议: ' + suggestedSlot + '\n仅允许字母/数字/下划线/短横线, 1-32 字符', suggestedSlot);
    if (slot == null) { playUiCue('playCancel'); return; }
    slot = slot.trim();
    if (!slot) { logLine('tag-err', '导入取消: 未输入槽位名'); playUiCue('playCancel'); return; }
    if (!SLOT_NAME_RE.test(slot)) { playUiCue('playError'); alert('槽位名不合法: "' + slot + '"'); return; }
    var meta = window.BootstrapApp.getSlotMeta(slot);
    if (meta == null) {
      send({ cmd: 'import_commit', slot: slot, data: sourceData });
    } else if (meta.tombstoned || meta.inconsistent) {
      if (confirm('此 slot 已标记删除/不一致，需先清理才能导入。是否自动清理？')) {
        var unsub = window.BootstrapApp.onMessage('reset_resp', function(resp) {
          unsub();
          if (resp.ok) send({ cmd: 'import_commit', slot: slot, data: sourceData });
          else logLine('tag-err', '清理失败: ' + (resp.error || ''));
        });
        send({ cmd: 'reset', slot: slot, confirm: true });
      }
    } else if (meta.corrupt) {
      if (confirm('此存档已损坏，覆盖？')) send({ cmd: 'import_commit', slot: slot, data: sourceData });
    } else {
      if (confirm('存档已存在，覆盖？')) send({ cmd: 'import_commit', slot: slot, data: sourceData });
    }
  }

  // ── Modal 管理 ──
  var _currentModal = null, _currentModule = null, _moduleRegistry = {};

  function openModal(name, initData) {
    if (_currentModal) {
      if (_currentModule && _currentModule.canClose && !_currentModule.canClose()) return;
      closeModal();
    }
    var mod = _moduleRegistry[name];
    if (!mod) { logLine('tag-err', '[Modal] unknown: ' + name); return; }
    _currentModal = name;
    _currentModule = mod;
    var host = document.getElementById('modal-host');
    var content = document.getElementById('modal-content');
    content.innerHTML = '';
    mod.mount(content, initData);
    host.style.display = '';
    playUiCue('playModalOpen');
  }
  function closeModal() {
    if (!_currentModal) return;
    if (_currentModule && _currentModule.unmount) _currentModule.unmount();
    document.getElementById('modal-host').style.display = 'none';
    _currentModal = null;
    _currentModule = null;
  }
  function tryCloseModal() {
    if (!_currentModal) return;
    if (_currentModule && _currentModule.canClose && !_currentModule.canClose()) return;
    closeModal();
  }
  document.getElementById('modal-backdrop').onclick = function() { tryCloseModal(); };
  document.addEventListener('keydown', function(e) {
    if (e.key !== 'Escape') return;
    if (_introActive) {
      var ovEsc = document.getElementById('intro-ov');
      if (ovEsc.classList.contains('loading')) {
        // loading 相: ESC → cancel_launch, 由 Idle 广播回头 hideLaunchOverlay
        if (Audio) Audio.playCancel();
        send({ cmd: 'cancel_launch' });
      } else {
        // 视频相: ESC = 跳过 (=触发跳过按钮, 走 onVideoDone)
        if (Audio) Audio.playCancel();
        var skipBtn = document.getElementById('intro-skip');
        if (skipBtn.onclick) skipBtn.onclick();
      }
      return;
    }
    if (_currentModal) {
      if (Audio) Audio.playCancel();
      tryCloseModal();
      return;
    }
  });

  // ── 全局桥 ──
  window.BootstrapApp = {
    send: function(obj) { send(obj); },
    playUiCue: playUiCue,
    onMessage: function(cmd, handler) {
      if (!_handlers[cmd]) _handlers[cmd] = [];
      _handlers[cmd].push(handler);
      return function unsubscribe() {
        var arr = _handlers[cmd]; if (!arr) return;
        var i = arr.indexOf(handler); if (i >= 0) arr.splice(i, 1);
      };
    },
    getLaunchState: function() { return _lastLaunchState; },
    getSlots: function() { return lastSlotsFromLauncher.slice(); },
    getSlotMeta: function(slot) {
      for (var i = 0; i < lastSlotsFromLauncher.length; i++)
        if (lastSlotsFromLauncher[i].slot === slot) return lastSlotsFromLauncher[i];
      return null;
    },
    refreshList: function() { send({ cmd: 'list' }); },
    openModal: openModal,
    closeModal: closeModal,
    tryCloseModal: tryCloseModal,
    registerModule: function(name, mod) { _moduleRegistry[name] = mod; },
    // 带持久化失败回退的 config_set 发送: revertFn 在 config_set_resp.ok===false 时被调,
    // 用来把前端 UI / 音效引擎等可见状态回滚到请求前, 保持与 C# 端回滚后的内存一致.
    sendConfigSet: function(key, value, revertFn) { sendConfigSet(key, value, revertFn); },
    // 字号缩放 API: 模块 (about.js) 用来读当前值 + 切换预设
    getUiFontScale: function() { return _prefsUiFontScale; },
    getUiFontScalePresets: function() { return FONT_SCALE_PRESETS.slice(); },
    setUiFontScale: function(v) {
      var clamped = clampFontScale(v);
      if (!_prefsReceived) {
        // 首次 list_resp 前不发 config_set; 直接本地应用, 不登记 applyFn
        applyFontScale(clamped);
        return;
      }
      // Optimistic UI: 立刻应用期望值, 让切档手感即时
      applyFontScale(clamped);
      // applyFn 按服务端 currentValue 对齐 — success 下与 clamped 一致 (no-op),
      // failure 下由服务端 rollback 值 (磁盘真实值) 覆盖, 纠正漂移
      sendConfigSet('uiFontScale', clamped, function(authoritative) {
        if (typeof authoritative === 'number') applyFontScale(authoritative);
      });
    }
  };

  // ── Welcome 视图事件 ──
  // Phase 2b: chkIntro 初值由首个 list_resp 推来（默认 false, 和 Flash 原版对齐）; 这里只给个
  // 保守初值, 真正值在 list_resp 回调里 set. onchange 用 config_set 协议落盘.
  chkIntro.checked = false;
  chkIntro.onchange = function() {
    if (!_prefsReceived) return;  // 首个 list_resp 前不发 config_set, 避免冲掉 launcher 侧值
    var desired = chkIntro.checked;
    _prefsIntroEnabled = desired;  // optimistic
    sendConfigSet('introEnabled', desired, function(authoritative) {
      // 服务端权威对齐: success 下 authoritative === desired (no-op), failure 下服务端 rollback 的真值
      if (typeof authoritative === 'boolean') {
        _prefsIntroEnabled = authoritative;
        chkIntro.checked = authoritative;
      }
    });
  };

  btnConfirmStart.onclick = function() {
    // Error 态 → retry 协议 + loading overlay 覆盖等待期
    if (_lastLaunchState === 'Error') {
      showLoadingOverlay();
      send({ cmd: 'retry' });
      return;
    }
    if (_launchInFlight) return;
    var s = _welcomeSlot;
    if (!s) { alert('没有可启动的存档，请点「切换」选择槽位'); return; }
    var mode = effectiveMode(s);
    if (s.corrupt) {
      alert('存档已损坏，无法启动；请点「切换」到槽位页编辑或删除');
      return;
    }
    if (mode === 'normal' && (s.__empty || s.tombstoned || s.inconsistent)) {
      // 这些状态下不应该是 normal 模式 — pickDefaultSlot 已做降级, 这里兜底防御
      alert('当前默认存档处于异常状态，请点「切换」到槽位页处理');
      return;
    }
    if (chkIntro.checked) {
      playIntroThenStart(s, mode);
    } else {
      if (mode === 'fresh') initiateFreshLaunch(s.slot);
      else                  initiateLaunch(s.slot);
    }
  };

  btnSwitchSlot.onclick = showSlots;
  document.getElementById('btn-back-welcome').onclick = showWelcome;
  document.getElementById('briefing-about').onclick = function() { openModal('about', {}); };

  // Topbar 按钮
  document.getElementById('btn-display').onclick = function() { openModal('display', {}); };
  document.getElementById('btn-about').onclick = function() { openModal('about', {}); };
  document.getElementById('btn-fullscreen').onclick = function() {
    if (!document.fullscreenElement) { try { document.documentElement.requestFullscreen(); } catch (e) {} }
    else { try { document.exitFullscreen(); } catch (e) {} }
  };
  document.getElementById('btn-logs').onclick = function() { openModal('diagnostic-log', {}); };

  // Slots 视图工具栏
  document.getElementById('btn-refresh').onclick = function() { send({ cmd: 'list' }); };
  document.getElementById('btn-new').onclick = handleNewCharacterClick;
  document.getElementById('btn-import').onclick = function() { send({ cmd: 'import_start' }); };
  document.getElementById('btn-open-dir').onclick = function() { send({ cmd: 'open_saves_dir' }); };
  retryBtn.onclick = function() { showLoadingOverlay(); send({ cmd: 'retry' }); };
  cancelLaunchBtn.onclick = function() { send({ cmd: 'cancel_launch' }); };

  // ── Audio 初始化 + 全局事件委托 ──
  // 首次用户交互触发 AudioContext.resume (浏览器 autoplay policy).
  // Hover/click 走 document-level delegation: 一次挂钩覆盖所有动态生成的卡片/tabs/modal 按钮.
  function initAudioBindings() {
    if (!Audio) return;
    Audio.init();   // new AudioContext (可能 suspended)
    // 首次交互 → resume + 按 UserPrefs 启动 ambient
    function onFirstInteraction() {
      Audio.resume();
      if (_prefsAmbientEnabled) Audio.startAmbient();
      document.removeEventListener('pointerdown', onFirstInteraction, true);
      document.removeEventListener('keydown', onFirstInteraction, true);
    }
    document.addEventListener('pointerdown', onFirstInteraction, true);
    document.addEventListener('keydown', onFirstInteraction, true);

    // Hover: 所有 <button> + .card 触发, 由 audio.js 内部去抖.
    document.addEventListener('mouseover', function (e) {
      var t = e.target;
      if (!t || !t.closest) return;
      var btn = t.closest('button');
      if (btn) {
        if (btn.disabled) return;
        Audio.playHover();
        return;
      }
      if (t.closest('.card:not(.empty-slot)')) Audio.playHover();
    });

    // Click 分类: primary (btn-go) → confirm; back/cancel/close → cancel;
    //   slot select (start/rebuild/newchar/btn-new) → select; 其他 button → click.
    document.addEventListener('click', function (e) {
      var t = e.target;
      if (!t || !t.closest) return;
      var btn = t.closest('button');
      if (btn && !btn.disabled) {
        if (btn.matches('.btn-go')) { Audio.playConfirm(); return; }
        if (btn.matches('.btn-back, .modal-close, #btn-cancel-launch, .intro-skip')) { Audio.playCancel(); return; }
        if (btn.matches('.btn-start, .btn-rebuild, .btn-newchar, #btn-new, #btn-switch-slot')) { Audio.playSelect(); return; }
        Audio.playClick();
        return;
      }
      var check = t.closest('input[type="checkbox"], input[type="radio"]');
      if (check && !check.disabled) {
        Audio.playSelect();
      }
    });
  }

  // ── 初始化 ──
  loadRandomBackground();
  initAudioBindings();
  showWelcome();   // 默认欢迎视图

  logLine('tag-in', 'Bootstrap loaded');
  send({ cmd: 'list' });
  requestAnimationFrame(function() {
    requestAnimationFrame(function() { send({ cmd: 'ready' }); });
  });
})();
