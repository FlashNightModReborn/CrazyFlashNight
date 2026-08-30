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
  var viewCharacterCreate = document.getElementById('view-character-create');
  var welcomeSlotNameEl = document.getElementById('welcome-slot-name');
  var welcomeSlotTimeEl = document.getElementById('welcome-slot-time');
  var btnConfirmStart = document.getElementById('btn-confirm-start');
  var btnSwitchSlot = document.getElementById('btn-switch-slot');
  var chkIntro = document.getElementById('chk-intro');
  var fontPackBox = document.getElementById('welcome-fontpack');
  var fontPackText = document.getElementById('welcome-fontpack-text');
  var fontPackBtn = document.getElementById('welcome-fontpack-install');
  var fontPackCancelBtn = document.getElementById('welcome-fontpack-cancel');
  var fontPackSkip = document.getElementById('welcome-fontpack-skip');
  var fontPackProgressBox = document.getElementById('welcome-fontpack-progress');
  var fontPackBarFill = document.getElementById('welcome-fontpack-bar-fill');
  var fontPackBytesEl = document.getElementById('welcome-fontpack-bytes');

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
  var _characterCreatePrepToken = null; // 建角揭幕租约；只允许当前 openRequestId 解除
  var _handlers = {};             // onMessage 注册表
  // 仅保留启动阶段的小型权威状态，供晚加载的 ESM 消费者补收最新值。
  // 不缓存任意消息，避免长期持有导入数据、诊断结果等大 payload。
  var _replayMessages = {};
  var _renamePending = null;

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
    try {
      window.chrome.webview.postMessage(json);
      return true;
    }
    catch (e) {
      logLine('tag-err', 'postMessage failed: ' + e.message);
      return false;
    }
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

  function slotDisplayName(slot) {
    if (slot && slot.__newEntry) return '新建存档';
    if (slot && typeof slot.displayName === 'string' && slot.displayName.trim()) return slot.displayName.trim();
    return presetDisplayName(slot && slot.slot || '');
  }

  function slotPrimaryName(slot) {
    if (slot && slot.__newEntry) return '新建存档';
    if (slot && typeof slot.characterName === 'string' && slot.characterName.trim()) {
      return slot.characterName.trim();
    }
    return slotDisplayName(slot);
  }

  function shortSlotKey(slotKey) {
    slotKey = String(slotKey || '');
    return slotKey.length <= 12 ? slotKey : slotKey.slice(0, 4) + '…' + slotKey.slice(-6);
  }

  function normalizeSlotDisplayName(value) {
    var runtime = window.BootstrapCharacterCreateRuntime;
    if (!runtime || typeof runtime.normalizeDisplayName !== 'function') return null;
    return runtime.normalizeDisplayName(value);
  }

  function finishRenamePending() {
    if (_renamePending && _renamePending.button && _renamePending.button.isConnected) {
      _renamePending.button.disabled = false;
      _renamePending.button.textContent = '重命名';
    }
    _renamePending = null;
  }

  function renameSlot(slot, button) {
    if (!slot || !slot.slot || slot.__newEntry) return false;
    if (_renamePending) {
      window.BootstrapAlert('已有存档正在重命名，请等待本地服务响应。');
      return false;
    }
    var current = slotDisplayName(slot);
    var input = prompt('重命名存档显示名（允许重名；清空后恢复跟随角色名）', current);
    if (input == null) return false;
    var restoreFollow = input.replace(/^\s+|\s+$/g, '') === '';
    var displayName = restoreFollow ? '' : normalizeSlotDisplayName(input);
    if (!restoreFollow && displayName === null) {
      window.BootstrapAlert('存档显示名无效：去除首尾空白后需为 1–32 个可见 Unicode 文本元素，且不能包含控制字符。');
      playUiCue('playError');
      return false;
    }
    _renamePending = { slotKey:slot.slot, button:button };
    if (button) {
      button.disabled = true;
      button.textContent = '重命名中…';
    }
    if (!send({cmd:'rename_slot', slotKey:slot.slot, displayName:displayName})) {
      finishRenamePending();
      window.BootstrapAlert('无法发送重命名请求。');
      playUiCue('playError');
      return false;
    }
    return true;
  }

  function mergeSlots(fromLauncher) {
    var byName = {};
    for (var i = 0; i < fromLauncher.length; i++) byName[fromLauncher[i].slot] = fromLauncher[i];
    var merged = [];
    for (var j = 0; j < PRESET_SLOTS.length; j++) {
      var slot = PRESET_SLOTS[j];
      var data = byName[slot];
      if (data) {
        var preset = {};
        for (var prop in data) if (data.hasOwnProperty(prop)) preset[prop] = data[prop];
        preset.__preset = true;
        merged.push(preset);
        delete byName[slot];
      }
    }
    var rest = [];
    for (var key in byName) if (byName.hasOwnProperty(key)) rest.push(byName[key]);
    rest.sort(function(a, b) { return a.slot < b.slot ? -1 : a.slot > b.slot ? 1 : 0; });
    return merged.concat(rest, [newCharacterPlaceholder()]);
  }

  function newCharacterPlaceholder() {
    return {
      slot: '', corrupt: false, tombstoned: false, inconsistent: false,
      mainProgress: null, size: 0, lastModified: null, __empty: true, __newEntry: true
    };
  }

  // ── 视图切换 ──
  // A 期翻新: welcome ↔ slots 进出场动画 (CSS: welcome.css 的 .view-enter/.view-leave).
  // 源 view 播完 leave 动画 (animationend, 300ms 定时器兜底) 后才置 hidden;
  // reduced-motion 下 CSS 已关动画, JS 侧同步退化为硬切. 首次加载源 view 已 hidden, 不播动画.
  var _reducedMotion = false;
  try {
    var _rmQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    _reducedMotion = _rmQuery.matches;
    var _rmOnChange = function(e) { _reducedMotion = e.matches; };
    if (typeof _rmQuery.addEventListener === 'function') _rmQuery.addEventListener('change', _rmOnChange);
    else if (typeof _rmQuery.addListener === 'function') _rmQuery.addListener(_rmOnChange);
  } catch (e) {}

  var _viewAnimSeq = 0;   // 递增序号: 连点切换时作废旧动画的落地回调, 避免误 hidden 当前视图
  function switchView(target, source) {
    var seq = ++_viewAnimSeq;
    if (window.BootTooltip) window.BootTooltip.hide();   // C 期: 视图切换时收掉残留 tooltip
    if (window.PanelTooltip) window.PanelTooltip.hide(); // 建角装备注释不得跨顶级视图残留
    viewWelcome.classList.remove('view-enter', 'view-leave');
    viewSlots.classList.remove('view-enter', 'view-leave');
    viewCharacterCreate.classList.remove('view-enter', 'view-leave');
    var animate = !_reducedMotion && source && !source.hidden && target !== source;
    if (!animate) {
      if (source) source.hidden = true;
      target.hidden = false;
      return;
    }
    target.hidden = false;
    target.classList.add('view-enter');
    source.classList.add('view-leave');
    var done = false;
    function finish() {
      if (done || seq !== _viewAnimSeq) return;
      done = true;
      source.hidden = true;
      source.classList.remove('view-leave');
      target.classList.remove('view-enter');
    }
    source.addEventListener('animationend', function h(ev) {
      if (ev.animationName !== 'viewLeave') return;   // 只认离场动画, 忽略子元素冒泡
      source.removeEventListener('animationend', h);
      finish();
    });
    setTimeout(finish, 300);   // 兜底: animationend 丢失也能落地
  }

  function activeView() {
    if (!viewCharacterCreate.hidden) return viewCharacterCreate;
    if (!viewSlots.hidden) return viewSlots;
    return viewWelcome;
  }

  function showWelcome() {
    var source = activeView();
    var changed = source !== viewWelcome;
    renderWelcomeSlot();
    document.body.classList.remove('character-create-active');
    if (changed) playUiCue('playTransition');
    switchView(viewWelcome, source);
  }
  function showSlots() {
    var source = activeView();
    var changed = source !== viewSlots;
    document.body.classList.remove('character-create-active');
    if (changed) playUiCue('playTransition');
    switchView(viewSlots, source);
    loadSlotsPoster();
    if (changed) {
      // C 期: 进入 slots 时清掉旧键盘焦点, 并聚焦卡片容器让方向键有 keydown 冒泡源
      setKbFocus(null);
      try { cardsEl.focus({ preventScroll: true }); } catch (e) { cardsEl.focus(); }
    }
  }

  function showCharacterCreate() {
    var source = activeView();
    document.body.classList.add('character-create-active');
    if (source !== viewCharacterCreate) playUiCue('playTransition');
    switchView(viewCharacterCreate, source);
  }

  function openCharacterCreate(mode, slotKey) {
    if (!window.BootstrapCharacterCreate) return false;
    return window.BootstrapCharacterCreate.open(mode, slotKey);
  }

  // ── A 期翻新: 侧栏真实数据 ──
  // BUILD 块: 从 config/version.js 的 window.APP_META 派生 (v + version + channel / 第二行 tail).
  // 在 WebView2 listener 注册之前尽早调用 — 无宿主环境 (静态预览) 下 listener 注册会 throw,
  // 提前填充保证 BUILD 块仍有真实数据; APP_META 缺失时保留 HTML 占位, 不报错.
  function fillBuildMeta() {
    try {
      var meta = window.APP_META;
      var buildEl = document.getElementById('build-val');
      if (!meta || !buildEl) return;
      buildEl.innerHTML = 'v' + escapeHtml(meta.version || '?')
        + ' &middot; ' + escapeHtml(meta.channel || '?')
        + '<br>' + escapeHtml(meta.tail || '?');
    } catch (e) {}
  }
  fillBuildMeta();

  // ── B 期: slots 页随机通缉令海报装饰 (dungeon-posters/manifest.json) ──
  // 首次调用即 fetch; 之后每次进 slots 幂等重设 (本次启动内海报不跳变).
  // 提前到 WebView2 listener 注册之前调用, 进 slots 页时海报已就绪; 失败静默, 不影响主流程.
  var _slotsPoster = null;
  function loadSlotsPoster() {
    var el = document.getElementById('slots-poster');
    if (!el) return;
    if (_slotsPoster) {
      el.style.backgroundImage = 'url(assets/dungeon-posters/' + _slotsPoster + '.png)';
      return;
    }
    fetch('assets/dungeon-posters/manifest.json')
      .then(function(r) {
        if (!r.ok) throw new Error('HTTP ' + r.status);
        return r.json();
      })
      .then(function(m) {
        if (!m.posters || !m.posters.length) return;
        _slotsPoster = m.posters[Math.floor(Math.random() * m.posters.length)];
        el.style.backgroundImage = 'url(assets/dungeon-posters/' + _slotsPoster + '.png)';
        logLine('tag-in', '[poster] ' + _slotsPoster);
      })
      .catch(function() { /* 海报装饰缺失静默 */ });
  }
  loadSlotsPoster();

  // 随机垫图 + RECON 图窗喂图同样提前到 listener 注册之前 (无宿主静态预览下注册会 throw,
  // 留在初始化段会永远跑不到; 与 loadSlotsPoster 同范式, 纯装饰 fetch 不依赖宿主)
  loadRandomBackground();

  // TRANSMISSION ◎ 点亮: 首个 list_resp → 第 1 行 + DLS SYNC 填健康存档比例;
  // 点「确认」→ 第 2 行; flash_ready (或 state Ready) → 第 3 行.
  // 依赖 window.BootstrapApp.onMessage, 在初始化段 (BootstrapApp 定义之后) 调用; 不可用时空转, 不报错.
  function setTransNodeLit(idx) {
    var el = document.getElementById('trans-node-' + idx);
    if (el) el.classList.add('lit');
  }
  function initTransmissionLights() {
    if (!window.BootstrapApp || typeof window.BootstrapApp.onMessage !== 'function') return;
    var unsubList = window.BootstrapApp.onMessage('list_resp', function(msg) {
      unsubList();
      try {
        var slots = (msg && msg.slots) || [];
        var healthy = 0;
        for (var i = 0; i < slots.length; i++) {
          var s = slots[i];
          if (s && !s.corrupt && !s.tombstoned) healthy++;
        }
        var el = document.getElementById('dls-sync-val');
        if (el) el.textContent = slots.length ? (healthy / slots.length).toFixed(2) : '0.00';
        setTransNodeLit(1);
      } catch (e) {}
    });
    if (btnConfirmStart) btnConfirmStart.addEventListener('click', function() { setTransNodeLit(2); });
    var thirdDone = false;
    function lightThird() { if (thirdDone) return; thirdDone = true; setTransNodeLit(3); }
    window.BootstrapApp.onMessage('flash_ready', lightThird);
    window.BootstrapApp.onMessage('state', function(msg) {
      if (msg && msg.state === 'Ready') lightThird();
    });
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
    // 3) 第一个已存在 preset；没有物理槽位时回退到唯一“新建存档”入口。
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
    welcomeSlotNameEl.textContent = slotPrimaryName(s);

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
  // 抽中的一张图喂给两处: .bg-photo 全屏垫图 (已退为低透明色调底) + 中央 .welcome-card
  // 垫图 (.has-art, 深色罩 82-88% 压文字可读性, 图以质感透出). 卡片缺失时静默跳过.
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
        var cardEl = document.querySelector('.welcome-card');
        if (cardEl) {
          cardEl.classList.add('has-art');
          cardEl.style.backgroundImage =
            'linear-gradient(180deg,rgba(10,14,18,.82) 0%,rgba(4,6,9,.88) 100%),url(assets/bg/' + pick + ')';
        }
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
    document.body.classList.add('intro-playing', 'intro-video');
    ov.classList.remove('loading');
    ov.classList.add('on');
    skipBtn.style.display = '';
    try {
      vid.preload = 'auto';
      vid.load();
      vid.currentTime = 0;
    } catch (e) {}
    // 立即 send 启动命令 + defer flags, 让视频播放与 Flash 加载并行。
    // 新建/重建已由独立建角协议接管，本路径只加载已有存档。
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
      // 片头结束, 恢复背景层栈显示.
      document.body.classList.remove('intro-video');
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
    var loadingText = ov.querySelector('.loading-text');
    var loadingHint = ov.querySelector('.loading-hint');
    _introActive = true;
    document.body.classList.add('intro-playing');
    ov.classList.add('on', 'loading');
    if (loadingText) loadingText.textContent = '启动中';
    if (loadingHint) loadingHint.textContent = 'ESC 取消';
    skipBtn.onclick = null;
    skipBtn.style.display = 'none';
  }

  function beginCharacterCreatePreparation(token) {
    token = String(token || '');
    if (!token) return false;
    _characterCreatePrepToken = token;
    showLoadingOverlay();
    document.body.classList.add('character-create-preparing');
    viewCharacterCreate.setAttribute('inert', '');
    viewCharacterCreate.setAttribute('aria-busy', 'true');
    var ov = document.getElementById('intro-ov');
    var loadingText = ov.querySelector('.loading-text');
    if (loadingText) loadingText.textContent = '正在准备角色';
    var active = document.activeElement;
    if (active && typeof active.blur === 'function') active.blur();
    return true;
  }

  function finishCharacterCreatePreparation(token) {
    token = String(token || '');
    if (!token || token !== _characterCreatePrepToken) return false;
    _characterCreatePrepToken = null;
    document.body.classList.remove('character-create-preparing');
    viewCharacterCreate.removeAttribute('inert');
    viewCharacterCreate.removeAttribute('aria-busy');
    hideLaunchOverlay();
    return true;
  }

  function hideLaunchOverlay() {
    if (!_introActive) return;
    var ov = document.getElementById('intro-ov');
    var vid = document.getElementById('intro-video');
    var skipBtn = document.getElementById('intro-skip');
    _introActive = false;
    try { vid.pause(); vid.onended = null; vid.onerror = null; } catch (e) {}
    ov.classList.remove('on', 'loading');
    document.body.classList.remove('intro-playing', 'intro-video');
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
  function renderCards(slots) {
    cardsEl.innerHTML = '';
    _kbFocusCard = null;   // C 期: 重绘后旧焦点卡已不在 DOM, 清除键盘导航焦点
    var merged = mergeSlots(slots || []);
    for (var i = 0; i < merged.length; i++) cardsEl.appendChild(renderCard(merged[i]));
  }

  function renderCard(s) {
    var classes = ['card'];
    if (s.__empty)      classes.push('empty-slot');
    if (s.corrupt)      classes.push('corrupt');
    if (s.tombstoned)   classes.push('tombstoned');
    if (s.inconsistent) classes.push('inconsistent');
    classes.push('corner-brackets');   // B 期: 四方位 L 角标
    var card = document.createElement('div');
    card.className = classes.join(' ');

    // B 期: 菱形状态标 (配色复用 flag 色; 优先级与下方 flag 显示逻辑一致)
    var gemCls = 'g-ok';
    if (s.__empty)         gemCls = 'g-empty';
    else if (s.corrupt)    gemCls = 'g-corrupt';
    else if (s.inconsistent) gemCls = 'g-incon';
    else if (s.tombstoned) gemCls = 'g-tomb';

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

    var displayName = slotDisplayName(s);
    var primaryName = slotPrimaryName(s);
    var progressParts = [];
    if (!s.__empty && displayName !== primaryName) progressParts.push('存档名 · ' + displayName);
    if (!s.__empty && s.mainProgress) progressParts.push(s.mainProgress);
    var progressText = s.__empty ? '—' : (progressParts.join(' · ') || '—');

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
    if (s.slot && !s.__newEntry) actions += '<button class="btn-rename">重命名</button>';

    card.innerHTML =
      '<div class="card-gem ' + gemCls + '" aria-hidden="true"></div>' +
      '<div class="slot">' + escapeHtml(primaryName) + '</div>' +
      // 卡头/信息区分隔线 (rust-dim + dls 辉光短段, 样式见 welcome.css .card-divider)
      '<div class="card-divider" aria-hidden="true"></div>' +
      '<div class="slot-id mono-num" aria-label="'
        + (s.__newEntry ? '由本地服务自动分配槽位' : '槽位 ' + escapeHtml(s.slot)) + '">'
        + (s.__newEntry ? '槽位 · 自动分配' : '槽位 · ' + escapeHtml(shortSlotKey(s.slot))) + '</div>' +
      '<div class="progress mono-num">' + escapeHtml(progressText) + '</div>' +
      '<div class="meta mono-num">' + flags + meta + '</div>' +
      // 无物理 identity 的新建入口显示「＋」引导符。
      (s.__empty ? '<div class="empty-glyph" aria-hidden="true">＋</div>' : '') +
      '<div class="card-actions">' + actions + '</div>';

    var startBtn   = card.querySelector('.btn-start');
    var deleteBtn  = card.querySelector('.btn-delete');
    var rebuildBtn = card.querySelector('.btn-rebuild');
    var newCharBtn = card.querySelector('.btn-newchar');
    var editBtn    = card.querySelector('.btn-edit');
    var exportBtn  = card.querySelector('.btn-export');
    var resetBtn   = card.querySelector('.btn-reset');
    var renameBtn  = card.querySelector('.btn-rename');

    if (startBtn) startBtn.onclick = function() { selectSlotAndReturn(s.slot, 'normal'); };
    if (deleteBtn) deleteBtn.onclick = function() {
      window.BootstrapConfirm('确定删除存档 "' + displayName + '" ?', { okText: '删除' })
        .then(function(ok) { if (ok) send({ cmd: 'delete', slot: s.slot }); });
    };
    if (rebuildBtn) rebuildBtn.onclick = function() {
      window.BootstrapConfirm('重建存档 "' + displayName + '" （原数据将丢弃）？', { okText: '重建' })
        .then(function(ok) { if (ok) openCharacterCreate('rebuild', s.slot); });
    };
    if (newCharBtn) newCharBtn.onclick = function() { openCharacterCreate('new'); };
    if (editBtn) editBtn.onclick = function() {
      window.BootstrapApp.openModal('archive-editor', { slot: s.slot, slotMeta: s });
    };
    if (exportBtn) exportBtn.onclick = function() {
      var forceRaw = !!(s.corrupt || s.inconsistent);
      var dn = slotDisplayName(s);
      var ts = new Date().toISOString().slice(0, 10).replace(/-/g, '');
      send({ cmd: 'export', slot: s.slot, defaultName: dn + '_' + ts + '.json', forceRaw: forceRaw });
    };
    if (resetBtn) resetBtn.onclick = function() {
      window.BootstrapConfirm('确定清理 "' + displayName + '" 的 launcher 副本？',
        { okText: '清理', detail: '此操作仅清理 launcher 侧 JSON 备份和删除标记，不影响 Flash 内部 SOL 存档。' })
        .then(function(ok) { if (ok) send({ cmd: 'reset', slot: s.slot, confirm: true }); });
    };
    if (renameBtn) renameBtn.onclick = function() { renameSlot(s, renameBtn); };
    return card;
  }

  function handleNewCharacterClick() {
    if (_launchInFlight) return;
    openCharacterCreate('new');
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
      if (!_characterCreatePrepToken && ovIdle && ovIdle.classList.contains('loading')) hideLaunchOverlay();
    } else if (state === 'Ready') {
      // Phase 2b-ext: Ready 广播不再立即 hide overlay. panel swap 被 launcher 按 defer flags
      // gate 住 (_revealWaitingJs / _revealWaitingFlash). 真正 swap 发生时 BootstrapPanel 不可见,
      // overlay 随之自然隐藏, 无需 JS 操心.
      // 注意: 视频相看到 Ready 是正常情况 (Flash 先 Ready 才发 reveal_ready, 视频还在播),
      // JS 不该动 overlay — 继续视频播放.
    } else if (state === 'Error') {
      // 建角遮罩由 exact openRequestId 的 character_create_state/snapshot 收口；
      // 全局 Error 不得误关 cancel/reopen 后的新租约。
      if (!_characterCreatePrepToken) hideLaunchOverlay();
      // 错误后 welcome 再可见, 确认按钮 .retry 样式 + 顶栏重试按钮
    }
  }

  // ── 字体扩展条 ──
  // 启动期通过 fontpack_status 询问 launcher：哪些 group 缺失。
  // 缺失 → 显示一键安装按钮；安装中由 fontpack_progress (push) 驱动进度条 + fontpack_install_resp 切完成/失败态。
  // 取消按钮发 fontpack_cancel；× 按钮 = 本次启动 6h 抑制。
  // 与 intelligence 面板内的 FontPackBanner 共享同一 localStorage 抑制 key。
  var FONTPACK_SUPPRESS_KEY = 'cfn_font_pack_banner_suppressed_until';
  var FONTPACK_SUPPRESS_HOURS = 6;
  var _fontPackMissingGroups = [];   // [{name,label,totalBytes}]
  var _fontPackInstalling = false;
  var _fontPackQueried = false;
  var _fontPackCurrentGroupBytesTotal = 0;
  var _fontPackCurrentGroupName = null;
  var _fontPackCancelRequested = false;

  function fontPackIsSuppressed() {
    try {
      var until = parseInt(window.localStorage.getItem(FONTPACK_SUPPRESS_KEY) || '0', 10);
      return until && Date.now() < until;
    } catch (e) { return false; }
  }
  function fontPackSuppress() {
    try { window.localStorage.setItem(FONTPACK_SUPPRESS_KEY, String(Date.now() + FONTPACK_SUPPRESS_HOURS * 3600 * 1000)); } catch (e) {}
  }
  function fontPackClearSuppress() {
    try { window.localStorage.removeItem(FONTPACK_SUPPRESS_KEY); } catch (e) {}
  }
  function fontPackFmtBytes(b) {
    if (b == null || b <= 0) return '0KB';
    if (b < 1024) return b + 'B';
    if (b < 1024 * 1024) return Math.round(b / 1024) + 'KB';
    return (b / (1024 * 1024)).toFixed(1) + 'MB';
  }
  function fontPackHide() { if (fontPackBox) fontPackBox.hidden = true; }
  function fontPackShow() { if (fontPackBox) fontPackBox.hidden = false; }
  function fontPackSetText(text, cls) {
    if (!fontPackText) return;
    fontPackText.textContent = text;
    fontPackText.className = 'welcome-fontpack-text' + (cls ? ' ' + cls : '');
  }
  function fontPackShowProgress(visible) {
    if (fontPackProgressBox) fontPackProgressBox.hidden = !visible;
  }
  function fontPackSetProgress(downloaded, total) {
    if (!fontPackBarFill || !fontPackBytesEl) return;
    var pct = (total > 0) ? Math.min(100, Math.floor(downloaded * 100 / total)) : 0;
    fontPackBarFill.style.width = pct + '%';
    fontPackBytesEl.textContent = fontPackFmtBytes(downloaded) + ' / ' + fontPackFmtBytes(total) + ' · ' + pct + '%';
  }
  function fontPackSetButtonsForState(state) {
    // state: 'idle' | 'installing' | 'done' | 'failed'
    if (fontPackBtn) {
      if (state === 'idle')           { fontPackBtn.hidden = false; fontPackBtn.textContent = '安装'; fontPackBtn.disabled = false; }
      else if (state === 'installing'){ fontPackBtn.hidden = true; }
      else if (state === 'done')      { fontPackBtn.hidden = true; }
      else if (state === 'failed')    { fontPackBtn.hidden = false; fontPackBtn.textContent = '重试'; fontPackBtn.disabled = false; }
    }
    if (fontPackCancelBtn) {
      fontPackCancelBtn.hidden = (state !== 'installing');
      fontPackCancelBtn.disabled = false;
    }
    if (fontPackSkip) {
      fontPackSkip.hidden = (state === 'installing' || state === 'done');
    }
  }

  function requestFontPackStatus() {
    if (_fontPackQueried) return;
    _fontPackQueried = true;
    if (fontPackIsSuppressed()) { fontPackHide(); return; }
    send({ cmd: 'fontpack_status' });
  }

  function applyFontPackStatus(msg) {
    if (!fontPackBox) {
      logLine('tag-err', 'fontpack: status arrived but DOM missing');
      return;
    }
    if (!msg || msg.ok === false) {
      logLine('tag-err', 'fontpack: status not ok: ' + (msg && msg.error || 'unknown'));
      fontPackHide();
      return;
    }
    var groups = msg.groups || [];
    var missing = [];
    var totalBytes = 0;
    var labels = [];
    for (var i = 0; i < groups.length; i++) {
      var g = groups[i];
      if (g && g.allInstalled === false) {
        missing.push({ name: g.name, label: g.label || g.name, totalBytes: g.totalBytes || 0 });
        totalBytes += g.totalBytes || 0;
        labels.push(g.label || g.name);
      }
    }
    _fontPackMissingGroups = missing;
    if (missing.length === 0) {
      fontPackHide();
      fontPackBox.classList.remove('is-done', 'is-failed');
      return;
    }
    if (fontPackIsSuppressed()) { fontPackHide(); return; }
    fontPackShow();
    fontPackBox.classList.remove('is-done', 'is-failed');
    var bytesStr = fontPackFmtBytes(totalBytes);
    fontPackSetText('字体扩展可选：' + labels.join(' / ') + '（' + bytesStr + '）', null);
    fontPackShowProgress(false);
    fontPackSetButtonsForState('idle');
  }

  function applyFontPackProgress(msg) {
    if (!fontPackBox || !_fontPackInstalling) return;
    var fileBytesDownloaded = Number(msg.fileBytesDownloaded) || 0;
    var fileBytesTotal = Number(msg.fileBytesTotal) || 0;
    var groupBytesDownloaded = Number(msg.groupBytesDownloaded) || 0;
    var groupBytesTotal = Number(msg.groupBytesTotal) || 0;
    if (groupBytesTotal <= 0) groupBytesTotal = _fontPackCurrentGroupBytesTotal;
    // 进度条按 group 累计字节，文字在多文件 group 时附带 (fileIdx/fileTotal)
    var label = '下载中：' + (msg.fileName || '');
    if (Number(msg.fileTotal) > 1) label += ' (' + msg.fileIdx + '/' + msg.fileTotal + ')';
    fontPackSetText(label, 'installing');
    fontPackShowProgress(true);
    fontPackSetProgress(groupBytesDownloaded, groupBytesTotal);
  }

  function applyFontPackInstallResp(msg) {
    if (!fontPackBox) return;
    _fontPackInstalling = false;
    var cancelled = msg && msg.cancelled === true;
    if (cancelled) {
      fontPackSetText('已取消下载', 'cancelled');
      fontPackShowProgress(false);
      fontPackBox.classList.remove('is-done', 'is-failed');
      fontPackSetButtonsForState('idle');
      _fontPackCancelRequested = false;
      return;
    }
    if (msg && msg.ok) {
      fontPackSetText('已安装，下次启动生效', 'done');
      fontPackShowProgress(false);
      fontPackBox.classList.add('is-done');
      fontPackBox.classList.remove('is-failed');
      fontPackSetButtonsForState('done');
      fontPackClearSuppress();
      setTimeout(fontPackHide, 4000);
    } else {
      var failedNames = '';
      if (msg && msg.failed && msg.failed.length) {
        var names = [];
        for (var i = 0; i < msg.failed.length; i++) names.push(msg.failed[i].name);
        failedNames = '（' + names.join(', ') + '）';
      }
      fontPackSetText('安装失败' + failedNames + '，可重试', 'failed');
      fontPackBox.classList.add('is-failed');
      fontPackBox.classList.remove('is-done');
      fontPackSetButtonsForState('failed');
      // 进度条保留在最后位置作为视觉残留，直观告诉玩家哪步断的
    }
  }

  // 已发送但未拿到 resp 的安装请求队列（FIFO 匹配）
  var pendingInstalls = [];

  function startFontPackInstall() {
    logLine('tag-out', 'fontpack: install clicked, missing=' + _fontPackMissingGroups.length
      + ' installing=' + _fontPackInstalling);
    if (_fontPackInstalling || _fontPackMissingGroups.length === 0) {
      logLine('tag-err', 'fontpack: install no-op (already installing or no missing groups)');
      return;
    }
    _fontPackInstalling = true;
    _fontPackCancelRequested = false;
    fontPackBox.classList.remove('is-done', 'is-failed');
    fontPackSetText('准备下载…', 'installing');
    fontPackShowProgress(true);
    fontPackSetProgress(0, _fontPackMissingGroups[0].totalBytes || 0);
    fontPackSetButtonsForState('installing');

    var idx = 0;
    function next() {
      if (idx >= _fontPackMissingGroups.length) return;
      var g = _fontPackMissingGroups[idx++];
      _fontPackCurrentGroupName = g.name;
      _fontPackCurrentGroupBytesTotal = g.totalBytes || 0;
      pendingInstalls.push({ group: g.name, onResp: function(respMsg) {
        if (!respMsg || respMsg.ok === false || respMsg.cancelled) {
          applyFontPackInstallResp(respMsg);
          return;
        }
        if (idx < _fontPackMissingGroups.length) {
          next();
        } else {
          applyFontPackInstallResp(respMsg);
        }
      }});
      send({ cmd: 'fontpack_install', group: g.name });
    }
    next();
  }

  function cancelFontPackInstall() {
    if (!_fontPackInstalling || _fontPackCancelRequested) return;
    _fontPackCancelRequested = true;
    if (fontPackCancelBtn) { fontPackCancelBtn.disabled = true; }
    fontPackSetText('正在取消…', 'cancelled');
    send({ cmd: 'fontpack_cancel' });
  }

  // 启动期一次性诊断：哪些 DOM 元素被绑定。失败 → 可立刻看出 HTML/JS 不匹配
  logLine('tag-in', 'fontpack DOM: box=' + !!fontPackBox + ' btn=' + !!fontPackBtn
    + ' cancel=' + !!fontPackCancelBtn + ' skip=' + !!fontPackSkip
    + ' progress=' + !!fontPackProgressBox + ' bar=' + !!fontPackBarFill);

  if (fontPackBtn) {
    fontPackBtn.addEventListener('click', function() {
      logLine('tag-out', 'fontpack: install button click event fired');
      if (Audio) Audio.playClick && Audio.playClick();
      startFontPackInstall();
    });
  }
  if (fontPackCancelBtn) {
    fontPackCancelBtn.addEventListener('click', function() {
      logLine('tag-out', 'fontpack: cancel button click event fired');
      if (Audio) Audio.playClick && Audio.playClick();
      cancelFontPackInstall();
    });
  }
  if (fontPackSkip) {
    fontPackSkip.addEventListener('click', function() {
      logLine('tag-out', 'fontpack: skip button click event fired');
      fontPackSuppress();
      fontPackHide();
    });
  }

  // ── onMessage 分发 ──
  function dispatchMessage(msg) {
    var cmd = msg.cmd;
    if (!cmd) return;
    if (cmd === 'list_resp' || cmd === 'flash_ready') _replayMessages[cmd] = msg;
    else if (cmd === 'state') {
      _replayMessages.state = msg;
      // flash_ready 只对当前 Ready 周期有效，离开 Ready 后不得向新订阅者重放旧事件。
      if (msg.state !== 'Ready') delete _replayMessages.flash_ready;
    }
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
      // 首次 list_resp 拿到 prefs 后查一次字体扩展状态（幂等：requestFontPackStatus 内部去重）
      requestFontPackStatus();
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
    else if (msg.cmd === 'rename_slot_resp') {
      var pendingSlot = _renamePending && _renamePending.slotKey;
      finishRenamePending();
      if (msg.ok) {
        playUiCue('playSuccess');
        send({ cmd: 'list' });
      } else {
        var renameError = msg.error || '本地服务拒绝了重命名请求';
        logLine('tag-err', 'rename failed: slot=' + (msg.slotKey || pendingSlot || '?') + ' err=' + renameError);
        window.BootstrapAlert('重命名失败：' + renameError);
        playUiCue('playError');
      }
    }
    else if (msg.cmd === 'fontpack_status_resp') {
      applyFontPackStatus(msg);
    }
    else if (msg.cmd === 'fontpack_progress') {
      applyFontPackProgress(msg);
    }
    else if (msg.cmd === 'fontpack_cancel_resp') {
      // 真正的"已取消"态由 fontpack_install_resp(cancelled=true) 接管，这里只是 ack
    }
    else if (msg.cmd === 'fontpack_install_resp') {
      // FIFO 匹配 pending 请求；若没 pending（异常），就直接当作终结态处理
      if (pendingInstalls.length > 0) {
        var p = pendingInstalls.shift();
        try { p.onResp(msg); } catch (e) { logLine('tag-err', 'fontpack handler error: ' + e.message); }
      } else {
        applyFontPackInstallResp(msg);
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
    if (!SLOT_NAME_RE.test(slot)) { playUiCue('playError'); window.BootstrapAlert('槽位名不合法: "' + slot + '"'); return; }
    var meta = window.BootstrapApp.getSlotMeta(slot);
    if (meta == null) {
      send({ cmd: 'import_commit', slot: slot, data: sourceData });
    } else if (meta.tombstoned || meta.inconsistent) {
      window.BootstrapConfirm('此 slot 已标记删除/不一致，需先清理才能导入。是否自动清理？', { okText: '清理' })
        .then(function(ok) {
          if (!ok) return;
          var unsub = window.BootstrapApp.onMessage('reset_resp', function(resp) {
            unsub();
            if (resp.ok) send({ cmd: 'import_commit', slot: slot, data: sourceData });
            else logLine('tag-err', '清理失败: ' + (resp.error || ''));
          });
          send({ cmd: 'reset', slot: slot, confirm: true });
        });
    } else if (meta.corrupt) {
      window.BootstrapConfirm('此存档已损坏，覆盖？', { okText: '覆盖' }).then(function(ok) { if (ok) send({ cmd: 'import_commit', slot: slot, data: sourceData }); });
    } else {
      window.BootstrapConfirm('存档已存在，覆盖？', { okText: '覆盖' }).then(function(ok) { if (ok) send({ cmd: 'import_commit', slot: slot, data: sourceData }); });
    }
  }

  // ── Modal 管理 ──
  var _currentModal = null, _currentModule = null, _moduleRegistry = {};
  var _modalReturnFocus = null, _modalBackgroundState = null;

  function setModalBackgroundInert(active) {
    if (active) {
      if (_modalBackgroundState) return;
      _modalBackgroundState = Array.prototype.slice.call(
        document.querySelectorAll('.topbar, .view, .bottom, #log')
      ).map(function(node) {
        var state = {node:node, ariaHidden:node.getAttribute('aria-hidden')};
        node.inert = true;
        node.setAttribute('aria-hidden', 'true');
        return state;
      });
      return;
    }
    (_modalBackgroundState || []).forEach(function(state) {
      state.node.inert = false;
      if (state.ariaHidden == null) state.node.removeAttribute('aria-hidden');
      else state.node.setAttribute('aria-hidden', state.ariaHidden);
    });
    _modalBackgroundState = null;
  }

  function modalFocusables() {
    var content = document.getElementById('modal-content');
    return Array.prototype.slice.call(content.querySelectorAll(
      'button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), '
      + 'a[href], [tabindex]:not([tabindex="-1"])'
    )).filter(function(node) { return node.getClientRects().length > 0; });
  }

  function focusModalStart() {
    var focusables = modalFocusables();
    var target = focusables[0] || document.getElementById('modal-content');
    try { target.focus({preventScroll:true}); } catch (e) { target.focus(); }
  }

  function trapModalTab(event) {
    if (!_currentModal || event.key !== 'Tab') return false;
    var content = document.getElementById('modal-content');
    var focusables = modalFocusables();
    if (!focusables.length) {
      event.preventDefault();
      content.focus();
      return true;
    }
    var first = focusables[0], last = focusables[focusables.length - 1];
    if (!content.contains(document.activeElement)) {
      event.preventDefault();
      (event.shiftKey ? last : first).focus();
    } else if (event.shiftKey && document.activeElement === first) {
      event.preventDefault();
      last.focus();
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault();
      first.focus();
    }
    return true;
  }

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
    _modalReturnFocus = document.activeElement;
    content.innerHTML = '';
    mod.mount(content, initData);
    var heading = content.querySelector('.modal-header h1, .modal-header h2, .modal-header h3');
    if (heading) {
      if (!heading.id) heading.id = 'bootstrap-modal-title';
      content.setAttribute('aria-labelledby', heading.id);
      content.removeAttribute('aria-label');
    } else {
      content.removeAttribute('aria-labelledby');
      content.setAttribute('aria-label', '启动器对话框');
    }
    host.style.display = '';
    setModalBackgroundInert(true);
    focusModalStart();
    playUiCue('playModalOpen');
  }
  function closeModal() {
    if (!_currentModal) return;
    var returnFocus = _modalReturnFocus;
    if (_currentModule && _currentModule.unmount) _currentModule.unmount();
    document.getElementById('modal-host').style.display = 'none';
    setModalBackgroundInert(false);
    _currentModal = null;
    _currentModule = null;
    _modalReturnFocus = null;
    if (returnFocus && returnFocus.isConnected && typeof returnFocus.focus === 'function') {
      try { returnFocus.focus({preventScroll:true}); } catch (e) { returnFocus.focus(); }
    }
  }
  function tryCloseModal() {
    if (!_currentModal) return;
    if (_currentModule && _currentModule.canClose && !_currentModule.canClose()) return;
    closeModal();
  }
  document.getElementById('modal-backdrop').onclick = function() { tryCloseModal(); };
  document.addEventListener('keydown', function(e) {
    if (trapModalTab(e)) return;
    if (e.key !== 'Escape') return;
    if (_introActive) {
      if (_characterCreatePrepToken) {
        if (window.BootstrapCharacterCreate) window.BootstrapCharacterCreate.handleEscape();
        return;
      }
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
    // ESC 分层: intro → tooltip → modal → 建角内部返回/取消 → slots 返回 welcome
    if (window.PanelTooltip && window.PanelTooltip.isVisible && window.PanelTooltip.isVisible()) {
      window.PanelTooltip.hide();
      return;
    }
    if (window.BootTooltip && window.BootTooltip.isVisible && window.BootTooltip.isVisible()) {
      window.BootTooltip.hide();
      return;   // consumed: 本次 ESC 只关 tooltip, 不继续下落
    }
    if (_currentModal) {
      if (Audio) Audio.playCancel();
      tryCloseModal();
      return;
    }
    if (!viewCharacterCreate.hidden && window.BootstrapCharacterCreate
        && window.BootstrapCharacterCreate.handleEscape()) return;
    if (!viewSlots.hidden) {
      showWelcome();
      return;
    }
  });

  // ── 全局桥 ──
  window.BootstrapApp = {
    send: function(obj) { return send(obj); },
    playUiCue: playUiCue,
    onMessage: function(cmd, handler, options) {
      if (!_handlers[cmd]) _handlers[cmd] = [];
      _handlers[cmd].push(handler);
      if (options && options.replayLatest && _replayMessages[cmd]) {
        try { handler(_replayMessages[cmd]); }
        catch (e) { logLine('tag-err', 'replay handler error [' + cmd + ']: ' + e.message); }
      }
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
    openCharacterCreate: openCharacterCreate,
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

  function initCharacterCreate() {
    if (!window.BootstrapCharacterCreate || !viewCharacterCreate) {
      logLine('tag-err', 'character-create controller missing');
      return;
    }
    window.BootstrapCharacterCreate.init({
      root: document.getElementById('character-create-root'),
      send: send,
      onShow: showCharacterCreate,
      onPrepare: beginCharacterCreatePreparation,
      onReady: finishCharacterCreatePreparation,
      onCancel: function(token) {
        finishCharacterCreatePreparation(token);
        showSlots();
      },
      onLoadDurable: function() {
        showLoadingOverlay();
        setLaunchInFlight(true);
        if (send({cmd:'retry'})) return true;
        setLaunchInFlight(false);
        hideLaunchOverlay();
        return false;
      },
      playUiCue: playUiCue
    });
    window.BootstrapApp.onMessage('character_create_snapshot', function(msg) {
      window.BootstrapCharacterCreate.handleSnapshot(msg);
    });
    window.BootstrapApp.onMessage('character_create_state', function(msg) {
      window.BootstrapCharacterCreate.handleState(msg);
    });
  }
  initCharacterCreate();

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
    if (!s) { window.BootstrapAlert('没有可启动的存档，请点「切换」选择槽位'); return; }
    var mode = effectiveMode(s);
    if (s.corrupt) {
      window.BootstrapAlert('存档已损坏，无法启动；请点「切换」到槽位页编辑或删除');
      return;
    }
    if (mode === 'normal' && (s.__empty || s.tombstoned || s.inconsistent)) {
      // 这些状态下不应该是 normal 模式 — pickDefaultSlot 已做降级, 这里兜底防御
      window.BootstrapAlert('当前默认存档处于异常状态，请点「切换」到槽位页处理');
      return;
    }
    if (mode === 'fresh') {
      openCharacterCreate(s.__empty ? 'new' : 'rebuild', s.__empty ? null : s.slot);
    } else if (chkIntro.checked) {
      playIntroThenStart(s);
    } else {
      initiateLaunch(s.slot);
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

  // ── C 期: 交互语言 (BootTooltip 绑定 + 键盘导航) ──
  function initBootTooltips() {
    var TT = window.BootTooltip;
    if (!TT) return;
    TT.bind(document.getElementById('btn-display'), '显示：字号档位 / 显示偏好');
    TT.bind(document.getElementById('btn-fullscreen'), '全屏：切换窗口全屏');
    TT.bind(document.getElementById('btn-logs'), '日志：查看启动诊断日志');
    TT.bind(document.getElementById('btn-about'), '其他：项目说明 / 作者与致谢 / 版本记录 / 音频');
    TT.bind(retryBtn, '重试：按上次参数重新启动');
    TT.bind(cancelLaunchBtn, '取消启动：中止当前启动流程');
    TT.bind(btnSwitchSlot, '切换：选择其他存档槽位');
    TT.bind(document.querySelector('.chk-intro'), '加载片头动画：启动时播放开场视频');
    TT.bind(document.getElementById('btn-back-welcome'), '返回：回到欢迎页 (ESC)');
    TT.bind(document.getElementById('btn-refresh'), '刷新：重新扫描存档槽位');
    TT.bind(document.getElementById('btn-new'), '新建角色：由本地服务自动分配槽位');
    TT.bind(document.getElementById('btn-import'), '导入存档：从 JSON 备份导入');
    TT.bind(document.getElementById('btn-open-dir'), '打开存档目录：在资源管理器中查看');
    // 卡片操作按钮是动态渲染 — 事件委托按 class 匹配, renderCard 重绘不丢绑定
    if (TT.bindDelegate) TT.bindDelegate(cardsEl, {
      'btn-start': '选择：设为启动存档并返回欢迎页',
      'btn-edit': '编辑：打开存档数据编辑器',
      'btn-export': '导出：备份为 JSON 文件',
      'btn-delete': '删除：删除存档（不可恢复）',
      'btn-rebuild': '重建：清空并重新开始（原数据丢弃）',
      'btn-reset': '清理副本：清除 launcher 侧备份与删除标记',
      'btn-rename': '重命名：修改启动器中的存档显示名（允许重名）',
      'btn-newchar': '新建角色：由本地服务自动分配槽位'
    });
  }

  // 键盘导航: slots 卡片网格方向键移动焦点 + Enter 主操作; welcome 页 Enter = 确认.
  var _kbFocusCard = null;
  function setKbFocus(card) {
    if (_kbFocusCard === card) return;
    if (_kbFocusCard) _kbFocusCard.classList.remove('kb-focus');
    _kbFocusCard = card || null;
    if (_kbFocusCard) {
      _kbFocusCard.classList.add('kb-focus');
      try { _kbFocusCard.scrollIntoView({ block: 'nearest' }); } catch (e) {}
    }
  }
  function kbCardList() {
    var out = [];
    for (var i = 0; i < cardsEl.children.length; i++) {
      var c = cardsEl.children[i];
      if (c.classList && c.classList.contains('card')) out.push(c);
    }
    return out;
  }
  // 列数从实际布局推: 第一行里 offsetTop 相同的卡片数 (auto-fit 网格不暴露列数)
  function kbGridCols(cards) {
    if (cards.length < 2) return 1;
    var top = cards[0].offsetTop;
    for (var i = 0; i < cards.length; i++) {
      if (cards[i].offsetTop !== top) return Math.max(1, i);
    }
    return cards.length;
  }
  function initKeyboardNav() {
    // #cards 在 showSlots 时被聚焦 (tabindex=-1); 卡片按钮 Tab 聚焦时 keydown 也冒泡到这里
    cardsEl.addEventListener('keydown', function(e) {
      // 真实按钮保留浏览器原生键盘语义；容器级方向键/Enter 只处理卡片导航焦点。
      if (e.target && e.target.closest && e.target.closest('button')) return;
      var cards = kbCardList();
      if (!cards.length) return;
      var idx = cards.indexOf(_kbFocusCard);
      var cols = kbGridCols(cards);
      var handled = true;
      if (e.key === 'ArrowRight')     idx = (idx < 0) ? 0 : Math.min(cards.length - 1, idx + 1);
      else if (e.key === 'ArrowLeft') idx = (idx < 0) ? 0 : Math.max(0, idx - 1);
      else if (e.key === 'ArrowDown') idx = (idx < 0) ? 0 : Math.min(cards.length - 1, idx + cols);
      else if (e.key === 'ArrowUp')   idx = (idx < 0) ? 0 : Math.max(0, idx - cols);
      else if (e.key === 'Enter') {
        if (idx < 0) { setKbFocus(cards[0]); e.preventDefault(); return; }
        // 主操作: 选择 / 新建角色; 异常卡 (tombstoned/inconsistent) 回退到重建
        var primary = cards[idx].querySelector('.btn-start, .btn-newchar, .btn-rebuild');
        if (primary) primary.click();
      }
      else handled = false;
      if (!handled) return;
      e.preventDefault();   // 拦下方向键默认滚动, 滚动由 scrollIntoView(nearest) 精细控制
      if (e.key !== 'Enter' && idx >= 0) setKbFocus(cards[idx]);
    });
    // welcome 页: 焦点不在任何可交互元素上 (activeElement 是 body) 时 Enter = 点「确认」
    document.addEventListener('keydown', function(e) {
      if (e.key !== 'Enter') return;
      if (_introActive || _currentModal) return;
      if (viewWelcome.hidden) return;
      var ae = document.activeElement;
      if (ae && ae !== document.body && ae !== document.documentElement) return;
      e.preventDefault();
      if (btnConfirmStart) btnConfirmStart.click();
    });
  }

  // ── 初始化 ──
  // loadRandomBackground 已提前到 WebView2 listener 注册之前调用 (见 loadSlotsPoster 旁), 这里不重复
  initAudioBindings();
  showWelcome();   // 默认欢迎视图
  initTransmissionLights();   // TRANSMISSION ◎ 点亮订阅 (BootstrapApp 已定义; 无宿主环境到不了这里, 内部有防御)
  initBootTooltips();         // C 期: tooltip 绑定 (模块缺失时空转)
  initKeyboardNav();          // C 期: 方向键 / Enter 导航

  logLine('tag-in', 'Bootstrap loaded');
  send({ cmd: 'list' });
  requestAnimationFrame(function() {
    requestAnimationFrame(function() { send({ cmd: 'ready' }); });
  });
})();
