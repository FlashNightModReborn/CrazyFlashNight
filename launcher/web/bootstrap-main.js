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
  var _prefsReceived = false;     // 首个 list_resp 到达前不做任何 config_set (避免 init 时被 onchange 回写 false 覆盖)

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
    logLine('tag-out', '\u2192 ' + json);
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
    return '\u5b58\u6863 ' + (idx + 1);
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
    viewWelcome.hidden = false;
    viewSlots.hidden = true;
    renderWelcomeSlot();
  }
  function showSlots() {
    viewWelcome.hidden = true;
    viewSlots.hidden = false;
  }

  // ── 欢迎页默认 slot 选择 ──
  // 2b: 优先 launcher 推来的 lastPlayedSlot, 且该 slot 在当前列表里存在且可用 (非 corrupt/tombstoned/inconsistent)
  // 回退: 第一个"有进度的正常 preset" → 第一个 preset (空槽, 触发新建流程) → 第一个 slot
  function pickDefaultSlot() {
    var slots = mergeSlots(lastSlotsFromLauncher);
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

  function renderWelcomeSlot() {
    var s = pickDefaultSlot();
    _welcomeSlot = s;
    if (!s) {
      welcomeSlotNameEl.textContent = '\u65e0\u53ef\u7528\u5b58\u6863';
      welcomeSlotTimeEl.textContent = '\u2014';
      return;
    }
    welcomeSlotNameEl.textContent = s.__preset ? presetDisplayName(s.slot) : s.slot;
    if (s.__empty) {
      welcomeSlotTimeEl.innerHTML = '<span class="flag empty">\u7a7a\u69fd\u4f4d \u00b7 \u5c06\u65b0\u5efa\u89d2\u8272</span>';
    } else {
      var meta = fmtBytes(s.size);
      if (s.lastModified) meta += ' \u00b7 ' + s.lastModified.slice(0, 16).replace('T', ' ');
      var flags = '';
      if (s.corrupt)      flags = '<span class="flag corrupt">\u635f\u574f</span>';
      if (s.tombstoned)   flags = '<span class="flag tombstoned">\u5df2\u5220\u9664</span>';
      if (s.inconsistent) flags = '<span class="flag inconsistent">\u4e0d\u4e00\u81f4</span>';
      welcomeSlotTimeEl.innerHTML = flags + escapeHtml(meta);
    }
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

  function playIntroThenStart(slot) {
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
    // 立即 send start_game + defer flags, 让视频播放与 Flash 加载并行.
    setLaunchInFlight(true);
    send({ cmd: 'start_game', slot: slot.slot, deferReveal: true, requireFlashReveal: true });
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
    skipBtn.textContent = '\u8df3 \u8fc7 \u00b7 ESC';
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
    if (s.__empty && s.__preset) flags += '<span class="flag empty">\u7a7a\u69fd\u4f4d</span>';
    if (s.corrupt)      flags += '<span class="flag corrupt">\u635f\u574f</span>';
    if (s.tombstoned && !s.inconsistent) flags += '<span class="flag tombstoned">\u5df2\u5220\u9664</span>';
    if (s.inconsistent) flags += '<span class="flag inconsistent">\u4e0d\u4e00\u81f4</span>';

    var meta = '';
    if (!s.__empty) {
      meta = fmtBytes(s.size);
      if (s.lastModified) meta += ' \u00b7 ' + s.lastModified.slice(0, 16).replace('T', ' ');
    }

    var displayName = s.__preset ? presetDisplayName(s.slot) : s.slot;
    var progressText = s.__empty ? '\u2014' : (s.mainProgress || '\u2014');

    var actions = '';
    if (s.__empty) {
      actions = '<button class="btn-newchar">\u65b0\u5efa\u89d2\u8272</button>';
    } else if (s.inconsistent) {
      actions = '<button class="btn-rebuild">\u91cd\u5efa</button>'
              + '<button class="btn-edit">\u7f16\u8f91</button>'
              + '<button class="btn-export">\u5bfc\u51fa</button>'
              + '<button class="btn-reset danger">\u6e05\u7406\u526f\u672c</button>';
    } else if (s.tombstoned) {
      actions = '<button class="btn-rebuild">\u91cd\u5efa</button>'
              + '<button class="btn-reset danger">\u6e05\u7406\u526f\u672c</button>';
    } else if (s.corrupt) {
      actions = '<button class="btn-edit">\u7f16\u8f91</button>'
              + '<button class="btn-export">\u5bfc\u51fa</button>'
              + '<button class="btn-delete danger">\u5220\u9664</button>'
              + '<button class="btn-reset danger">\u6e05\u7406\u526f\u672c</button>';
    } else {
      actions = '<button class="btn-start">\u5f00\u59cb</button>'
              + '<button class="btn-edit">\u7f16\u8f91</button>'
              + '<button class="btn-export">\u5bfc\u51fa</button>'
              + '<button class="btn-delete danger">\u5220\u9664</button>';
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

    if (startBtn) startBtn.onclick = function() { initiateLaunch(s.slot); };
    if (deleteBtn) deleteBtn.onclick = function() {
      if (confirm('\u786e\u5b9a\u5220\u9664\u5b58\u6863 "' + displayName + '" ?')) send({ cmd: 'delete', slot: s.slot });
    };
    if (rebuildBtn) rebuildBtn.onclick = function() {
      if (confirm('\u91cd\u5efa\u5b58\u6863 "' + displayName + '" (\u539f\u6570\u636e\u5c06\u4e22\u5f03)?')) initiateFreshLaunch(s.slot);
    };
    if (newCharBtn) newCharBtn.onclick = function() { initiateFreshLaunch(s.slot); };
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
      if (confirm('\u786e\u5b9a\u6e05\u7406 "' + displayName + '" \u7684 launcher \u526f\u672c?\n\n\u6b64\u64cd\u4f5c\u4ec5\u6e05\u7406 launcher \u4fa7 JSON \u5907\u4efd\u548c\u5220\u9664\u6807\u8bb0\uff0c\u4e0d\u5f71\u54cd Flash \u5185\u90e8 SOL \u5b58\u6863\u3002'))
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
    var input = prompt(
      '\u8f93\u5165\u5b58\u6863\u540d\u79f0:\n'
      + '\u2022 \u7559\u7a7a\u81ea\u52a8\u9009\u7528: ' + defaultName + '\n'
      + '\u2022 \u4ec5\u5141\u8bb8\u5b57\u6bcd/\u6570\u5b57/\u4e0b\u5212\u7ebf/\u77ed\u6a2a\u7ebf, 1-32 \u5b57\u7b26',
      defaultName);
    if (input == null) return;
    var slot = input.trim();
    if (!slot) slot = defaultName;
    if (!SLOT_NAME_RE.test(slot)) { alert('\u5b58\u6863\u540d\u79f0\u4e0d\u5408\u6cd5: ' + slot); return; }
    for (var k = 0; k < lastSlotsFromLauncher.length; k++) {
      if (lastSlotsFromLauncher[k].slot === slot) {
        var entry = lastSlotsFromLauncher[k];
        if (entry.tombstoned) {
          if (!confirm('\u6b64\u6863\u5df2\u5220\u9664, \u662f\u5426\u91cd\u5efa?')) return;
          initiateFreshLaunch(slot); return;
        }
        if (!confirm('\u5b58\u6863 "' + slot + '" \u5df2\u5b58\u5728, \u76f4\u63a5\u52a0\u8f7d?')) return;
        initiateLaunch(slot); return;
      }
    }
    initiateFreshLaunch(slot);
  }

  // ── State 广播 ──
  function applyState(state, msg) {
    _lastLaunchState = state;
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
    logLine('tag-in', '\u2190 ' + JSON.stringify(msg));

    if (msg.cmd === 'state')            applyState(msg.state, msg.msg);
    else if (msg.cmd === 'list_resp') {
      lastSlotsFromLauncher = msg.slots || [];
      // Phase 2b: 接收 launcher 推的 UserPrefs
      if (typeof msg.lastPlayedSlot === 'string') _prefsLastPlayedSlot = msg.lastPlayedSlot;
      if (typeof msg.introEnabled === 'boolean')  _prefsIntroEnabled   = msg.introEnabled;
      _prefsReceived = true;
      chkIntro.checked = _prefsIntroEnabled;
      renderCards(lastSlotsFromLauncher);
      renderWelcomeSlot();
    }
    else if (msg.cmd === 'config_set_resp') {
      if (!msg.ok) logLine('tag-err', 'config_set failed: key=' + (msg.key || '?') + ' err=' + (msg.error || ''));
    }
    else if (msg.cmd === 'flash_ready') {
      var sk = document.getElementById('intro-skip');
      sk.classList.add('flash-ready');
      sk.textContent = '进入游戏 · ESC';
    }
    else if (msg.cmd === 'delete_resp') { if (msg.ok) send({ cmd: 'list' }); else logLine('tag-err', 'delete failed: ' + msg.error); }
    else if (msg.cmd === 'error')       logLine('tag-err', msg.code + ': ' + msg.msg);
    else if (msg.cmd === 'pong')        logLine('tag-in', 'pong');
    else if (msg.cmd === 'reset_resp')  { if (msg.ok) send({ cmd: 'list' }); else logLine('tag-err', 'reset failed: ' + (msg.error || 'unknown')); }
    else if (msg.cmd === 'export_resp') {
      if (msg.ok) logLine('tag-in', '\u5bfc\u51fa\u6210\u529f: ' + (msg.path || ''));
      else if (msg.error !== 'cancelled') logLine('tag-err', '\u5bfc\u51fa\u5931\u8d25: ' + (msg.error || ''));
    }
    else if (msg.cmd === 'import_resp') {
      if (msg.ok) { logLine('tag-in', '\u5bfc\u5165\u6210\u529f: ' + (msg.slot || '')); send({ cmd: 'list' }); }
      else if (msg.error !== 'cancelled') logLine('tag-err', '\u5bfc\u5165\u5931\u8d25: ' + (msg.error || ''));
    }
    else if (msg.cmd === 'import_target') handleImportTarget(msg);

    dispatchMessage(msg);
  });

  function handleImportTarget(msg) {
    var sourceData = msg.sourceData;
    var suggestedSlot = msg.suggestedSlot || '';
    var slot = prompt('\u9009\u62e9\u76ee\u6807\u5b58\u6863\u69fd\u4f4d:\n\u5efa\u8bae: ' + suggestedSlot + '\n\u4ec5\u5141\u8bb8\u5b57\u6bcd/\u6570\u5b57/\u4e0b\u5212\u7ebf/\u77ed\u6a2a\u7ebf, 1-32 \u5b57\u7b26', suggestedSlot);
    if (slot == null) return;
    slot = slot.trim();
    if (!slot) { logLine('tag-err', '\u5bfc\u5165\u53d6\u6d88: \u672a\u8f93\u5165\u69fd\u4f4d\u540d'); return; }
    if (!SLOT_NAME_RE.test(slot)) { alert('\u69fd\u4f4d\u540d\u4e0d\u5408\u6cd5: "' + slot + '"'); return; }
    var meta = window.BootstrapApp.getSlotMeta(slot);
    if (meta == null) {
      send({ cmd: 'import_commit', slot: slot, data: sourceData });
    } else if (meta.tombstoned || meta.inconsistent) {
      if (confirm('\u6b64 slot \u5df2\u6807\u8bb0\u5220\u9664/\u4e0d\u4e00\u81f4\uff0c\u9700\u5148\u6e05\u7406\u624d\u80fd\u5bfc\u5165\u3002\u662f\u5426\u81ea\u52a8\u6e05\u7406\uff1f')) {
        var unsub = window.BootstrapApp.onMessage('reset_resp', function(resp) {
          unsub();
          if (resp.ok) send({ cmd: 'import_commit', slot: slot, data: sourceData });
          else logLine('tag-err', '\u6e05\u7406\u5931\u8d25: ' + (resp.error || ''));
        });
        send({ cmd: 'reset', slot: slot, confirm: true });
      }
    } else if (meta.corrupt) {
      if (confirm('\u6b64\u5b58\u6863\u5df2\u635f\u574f\uff0c\u8986\u76d6\uff1f')) send({ cmd: 'import_commit', slot: slot, data: sourceData });
    } else {
      if (confirm('\u5b58\u6863\u5df2\u5b58\u5728\uff0c\u8986\u76d6\uff1f')) send({ cmd: 'import_commit', slot: slot, data: sourceData });
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
        send({ cmd: 'cancel_launch' });
      } else {
        // 视频相: ESC = 跳过 (=触发跳过按钮, 走 onVideoDone)
        var skipBtn = document.getElementById('intro-skip');
        if (skipBtn.onclick) skipBtn.onclick();
      }
      return;
    }
    if (_currentModal) { tryCloseModal(); return; }
  });

  // ── 全局桥 ──
  window.BootstrapApp = {
    send: function(obj) { send(obj); },
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
    registerModule: function(name, mod) { _moduleRegistry[name] = mod; }
  };

  // ── Welcome 视图事件 ──
  // Phase 2b: chkIntro 初值由首个 list_resp 推来（默认 false, 和 Flash 原版对齐）; 这里只给个
  // 保守初值, 真正值在 list_resp 回调里 set. onchange 用 config_set 协议落盘.
  chkIntro.checked = false;
  chkIntro.onchange = function() {
    if (!_prefsReceived) return;  // 首个 list_resp 前不发 config_set, 避免冲掉 launcher 侧值
    _prefsIntroEnabled = chkIntro.checked;
    send({ cmd: 'config_set', key: 'introEnabled', value: chkIntro.checked });
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
    if (!s) { alert('\u6ca1\u6709\u53ef\u542f\u52a8\u7684\u5b58\u6863\uff0c\u8bf7\u70b9\u300c\u5207\u6362\u300d\u9009\u62e9\u69fd\u4f4d'); return; }
    // 空 preset 需走新建流程（不能直接 start_game 一个空槽）
    if (s.__empty) {
      showSlots();
      return;
    }
    if (s.corrupt || s.tombstoned || s.inconsistent) {
      alert('\u5f53\u524d\u9ed8\u8ba4\u5b58\u6863\u5904\u4e8e\u5f02\u5e38\u72b6\u6001\uff0c\u8bf7\u70b9\u300c\u5207\u6362\u300d\u5bfc\u5230\u69fd\u4f4d\u9875\u5904\u7406');
      return;
    }
    if (chkIntro.checked) playIntroThenStart(s);
    else initiateLaunch(s.slot);
  };

  btnSwitchSlot.onclick = showSlots;
  document.getElementById('btn-back-welcome').onclick = showWelcome;
  document.getElementById('briefing-about').onclick = function() { openModal('about', {}); };

  // Topbar 按钮
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

  // ── 初始化 ──
  loadRandomBackground();
  showWelcome();   // 默认欢迎视图

  logLine('tag-in', 'Bootstrap loaded');
  send({ cmd: 'list' });
  requestAnimationFrame(function() {
    requestAnimationFrame(function() { send({ cmd: 'ready' }); });
  });
})();
