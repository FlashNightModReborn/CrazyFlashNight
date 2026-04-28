// Phase 2a: 存档编辑器模块
// mount/unmount/canClose 契约，经 BootstrapApp.registerModule 注册
// 三种模式：简易（白名单表单）/ 高级（raw JSON textarea）/ 树视图
// 支持 raw-only 降级（corrupt / inconsistent / load 后 parse 失败）

(function() {
  'use strict';

  var _container = null;
  var _slot = null;
  var _slotMeta = null;
  var _currentData = null;  // parsed JSON object (null when raw-only)
  var _rawText = '';         // 原始 JSON 字符串
  var _isDirty = false;      // 模型有合法修改

  var _mode = 'simple';     // 'simple' | 'advanced' | 'tree' | 'modified'
  var _rawOnly = false;      // true = 仅高级模式可用
  var _saveDisabled = false; // inconsistent slot 永久禁用保存
  var _idleOk = true;        // 当前是否 Idle
  var _unsubs = [];

  // 危险字段已解锁集合（key = pathToString），unmount 时清空
  var _dangerUnlocked = {};

  // 搜索浮层状态
  var _searchVisible = false;
  var _searchHits = [];
  var _searchHitIdx = -1;
  var _searchKeyHandler = null;
  // advanced 模式当前匹配行的覆盖标尺（用 absolute div 绕过 textarea 失焦后选区不可见的问题）
  var _searchLineMarker = null;
  // 像素级位置（由 textarea 镜像 div 测得，绕过 line-height 估算误差）：
  //   _searchMarkerOffsetTop  = 匹配在 textarea 内容坐标下的 top（不含 scrollTop）
  //   _searchMarkerHeight     = 匹配 sentinel 字符的 boundingClientRect 高度
  var _searchMarkerOffsetTop = -1;
  var _searchMarkerHeight = 0;
  var _searchMarkerScrollHandler = null;

  // DOM 引用
  var _topbarEl = null;
  var _diagBtn = null;
  var _diagStatusEl = null;
  var _bannerEl = null;
  var _modeTabsEl = null;
  var _panelEl = null;
  var _saveBtn = null;
  var _resetBtn = null;
  var _statusEl = null;

  function playUiCue(name) {
    if (window.BootstrapApp && window.BootstrapApp.playUiCue) {
      window.BootstrapApp.playUiCue(name);
    }
  }

  function mount(containerEl, initData) {
    _container = containerEl;
    _slot = initData.slot;
    _slotMeta = initData.slotMeta || {};
    _isDirty = false;

    _rawOnly = false;
    _saveDisabled = false;
    _mode = 'simple';
    _currentData = null;
    _rawText = '';
    _bannerPriority = -1;

    // 检查 Idle
    _idleOk = (window.BootstrapApp.getLaunchState() === 'Idle');

    // 检查 inconsistent → 保存永久禁用
    if (_slotMeta.inconsistent) _saveDisabled = true;

    // 构建 UI 骨架
    var displayName = _slot;
    var m = /^crazyflasher7_saves(\d*)$/.exec(_slot);
    if (m) displayName = '存档 ' + (m[1] === '' ? 1 : parseInt(m[1], 10) + 1);

    _container.innerHTML =
      '<div class="modal-header">' +
        '<h2>存档编辑: ' + escHtml(displayName) + ' <small style="color:#666">(' + escHtml(_slot) + ')</small></h2>' +
        '<button class="modal-close" id="ed-close">×</button>' +
      '</div>' +
      '<div id="ed-topbar" class="editor-topbar">' +
        '<span class="topbar-spacer"></span>' +
        '<span id="ed-diag-status" class="topbar-status"></span>' +
        '<button id="ed-search-toggle" title="搜索 key/value（仅高级/树/已修改 模式可用）">搜索</button>' +
        '<button id="ed-diag-export" title="把当前档 + 日志 + 配置打成 zip 发给开发者">导出诊断包</button>' +
      '</div>' +
      '<div id="ed-banner"></div>' +
      '<div id="ed-mode-tabs" class="mode-tabs"></div>' +
      '<div id="ed-panel" style="position:relative"></div>' +
      '<div id="ed-status" style="font-size:11px;color:#888;margin-top:8px"></div>' +
      '<div class="modal-actions">' +
        '<button id="ed-save" class="primary">保存</button>' +
        '<button id="ed-reset-slot" class="danger">清理副本</button>' +
        '<button id="ed-cancel">取消</button>' +
      '</div>';

    _topbarEl = document.getElementById('ed-topbar');
    _diagBtn = document.getElementById('ed-diag-export');
    _diagStatusEl = document.getElementById('ed-diag-status');
    _bannerEl = document.getElementById('ed-banner');
    _modeTabsEl = document.getElementById('ed-mode-tabs');
    _panelEl = document.getElementById('ed-panel');
    _saveBtn = document.getElementById('ed-save');
    _resetBtn = document.getElementById('ed-reset-slot');
    _statusEl = document.getElementById('ed-status');

    _diagBtn.onclick = onExportDiagnostic;
    // 搜索按钮：显式触发（Ctrl+F 会被 launcher KeyboardHook/HotkeyGuard 全屏热键拦截，到不了 web）
    var searchBtn = document.getElementById('ed-search-toggle');
    if (searchBtn) {
      searchBtn.onclick = function() {
        if (_mode !== 'advanced' && _mode !== 'tree' && _mode !== 'modified') {
          _statusEl.textContent = '搜索仅在 高级/树视图/已修改 模式可用';
          return;
        }
        if (_searchVisible) hideSearchOverlay();
        else showSearchOverlay();
      };
    }
    // Esc 仍保留作为关闭浮层的快捷键（document 级；浮层可见时才生效，不会与 panel 路由冲突）
    _searchKeyHandler = function(e) {
      if (e.key === 'Escape' && _searchVisible) {
        e.preventDefault();
        hideSearchOverlay();
      }
    };
    document.addEventListener('keydown', _searchKeyHandler);

    document.getElementById('ed-close').onclick = function() { window.BootstrapApp.tryCloseModal(); };
    document.getElementById('ed-cancel').onclick = function() { window.BootstrapApp.tryCloseModal(); };
    _saveBtn.onclick = onSave;
    _resetBtn.onclick = onResetSlot;

    // 监听 state 变化
    _unsubs.push(window.BootstrapApp.onMessage('state', function(msg) {
      _idleOk = (msg.state === 'Idle');
      updateButtons();
    }));

    // 初始化 banner（priority 0 = idle hint，Idle 恢复时可被清除）
    if (!_idleOk) {
      showBanner('info', '游戏运行中，编辑器为只读模式', /*priority:*/ 0);
    }

    // 按 slotMeta 决定加载路径
    if (_slotMeta.inconsistent || _slotMeta.corrupt) {
      // 走 load_raw
      loadRaw();
    } else if (!_slotMeta.__empty) {
      // 正常 slot: 走 load
      loadNormal();
    } else {
      showBanner('warn', '空槽位，无数据可编辑');
      _rawOnly = true;
      renderModes();
      updateButtons();
    }
  }

  function unmount() {
    if (_searchKeyHandler) {
      document.removeEventListener('keydown', _searchKeyHandler);
      _searchKeyHandler = null;
    }
    _searchVisible = false;
    _searchHits = [];
    _searchHitIdx = -1;
    _dangerUnlocked = {};
    for (var i = 0; i < _unsubs.length; i++) _unsubs[i]();
    _unsubs = [];
    _container = null;
    _topbarEl = null;
    _diagBtn = null;
    _diagStatusEl = null;
    _bannerEl = null;
    _modeTabsEl = null;
    _panelEl = null;
    _saveBtn = null;
    _resetBtn = null;
    _statusEl = null;
    _currentData = null;
    _rawText = '';
  }

  function hasInvalidInput() {
    if (!_panelEl) return false;
    return _panelEl.querySelectorAll('input.invalid').length > 0;
  }

  function canClose() {
    if (!_isDirty && !hasInvalidInput()) return true;
    return confirm('有未保存更改，放弃？');
  }

  // ==================== 加载 ====================

  function loadNormal() {
    _statusEl.textContent = '加载中...';
    var unsub = window.BootstrapApp.onMessage('load_resp', function(msg) {
      unsub();
      if (!msg.ok) {
        showBanner('error', '加载失败: ' + (msg.error || 'unknown'));
        playUiCue('playError');
        _rawOnly = true;
        renderModes();
        updateButtons();
        return;
      }
      _rawText = msg.data || '';
      try {
        _currentData = JSON.parse(_rawText);
        _rawOnly = false;
        // 检查 schema 版本
        if (_currentData.version !== window.ArchiveSchema.SCHEMA_VERSION) {
          showBanner('warn', '存档版本 ' + (_currentData.version || '?') + ' 与预期 ' + window.ArchiveSchema.SCHEMA_VERSION + ' 不匹配，白名单可能不准确');
        }
      } catch (e) {
        // 降级 raw-only (TOCTOU 防御)
        showBanner('warn', 'JSON 解析失败，降级到高级模式: ' + e.message);
        _rawOnly = true;
        _currentData = null;
      }
      _statusEl.textContent = '';
      renderModes();
      updateButtons();
      playUiCue('playTransition');
    });
    _unsubs.push(unsub);
    window.BootstrapApp.send({ cmd: 'load', slot: _slot });
  }

  function loadRaw() {
    _statusEl.textContent = '加载中...';
    var unsub = window.BootstrapApp.onMessage('load_raw_resp', function(msg) {
      unsub();
      if (!msg.ok) {
        showBanner('error', '加载失败: ' + (msg.error || 'unknown'));
        playUiCue('playError');
        _rawOnly = true;
        renderModes();
        updateButtons();
        return;
      }
      _rawText = msg.data || '';
      _rawOnly = true;
      _currentData = null;

      // 尝试 parse（用于判断是否 corrupt）
      try {
        _currentData = JSON.parse(_rawText);
        // parse 成功但来自 load_raw → 可能是 inconsistent
        // inconsistent: 保存禁用 + banner
        if (_slotMeta.inconsistent) {
          showBanner('warn', '已标记删除，此为残留 JSON 副本。如需保存，请先"重建"走新流程。');
        }
        // corrupt 来自 list 阶段标记，但 parse 成功说明文件可能已修复
        if (_slotMeta.corrupt && !_slotMeta.inconsistent) {
          showBanner('warn', 'JSON 数据可能有问题（被标记为损坏），请检查后保存');
          _rawOnly = false; // corrupt 但 parse 成功 → 可用简易/树
        }
      } catch (e) {
        showBanner('error', 'JSON 解析失败: ' + e.message);
        playUiCue('playError');
      }

      _statusEl.textContent = '';
      renderModes();
      updateButtons();
      playUiCue('playTransition');
    });
    _unsubs.push(unsub);
    window.BootstrapApp.send({ cmd: 'load_raw', slot: _slot });
  }

  // ==================== 模式切换 ====================

  function renderModes() {
    if (_rawOnly && !_currentData) {
      // 纯 raw-only（parse 失败）
      _mode = 'advanced';
      _modeTabsEl.innerHTML = '';
      renderAdvanced();
      return;
    }
    if (_rawOnly && _currentData && _slotMeta.inconsistent) {
      // inconsistent 但 parse 成功 → 仍只给 raw + tree 查看（不给简易，避免误触保存路径）
      _mode = 'advanced';
      _modeTabsEl.innerHTML =
        '<button id="tab-advanced" class="active">高级模式</button>' +
        '<button id="tab-tree">树视图</button>';
      document.getElementById('tab-advanced').onclick = function() { switchMode('advanced'); };
      document.getElementById('tab-tree').onclick = function() { switchMode('tree'); };
      renderAdvanced();
      return;
    }

    // 正常 / corrupt-但-parse-成功
    _modeTabsEl.innerHTML =
      '<button id="tab-simple">简易模式</button>' +
      '<button id="tab-advanced">高级模式</button>' +
      '<button id="tab-tree">树视图</button>' +
      '<button id="tab-modified">已修改</button>';
    document.getElementById('tab-simple').onclick = function() { switchMode('simple'); };
    document.getElementById('tab-advanced').onclick = function() { switchMode('advanced'); };
    document.getElementById('tab-tree').onclick = function() { switchMode('tree'); };
    document.getElementById('tab-modified').onclick = function() { switchMode('modified'); };

    if (_mode === 'simple') renderSimple();
    else if (_mode === 'advanced') renderAdvanced();
    else if (_mode === 'tree') renderTree();
    else if (_mode === 'modified') renderModified();
    else renderSimple();

    updateTabHighlight();
  }

  function switchMode(mode) {
    // 从高级模式切出时，尝试同步 _currentData
    if (_mode === 'advanced' && _currentData) {
      var ta = _panelEl.querySelector('.raw-editor');
      if (ta) {
        try {
          _currentData = JSON.parse(ta.value);
          _rawText = ta.value;
        } catch (e) {
          // parse 失败，不切模式
          alert('JSON 语法错误，请先修正');
          return;
        }
      }
    }
    // 从简易/树切出时，检查是否有未写回的非法输入
    if ((_mode === 'simple' || _mode === 'tree') && _panelEl) {
      var invalids = _panelEl.querySelectorAll('input.invalid');
      if (invalids.length > 0) {
        if (!confirm('有 ' + invalids.length + ' 个字段输入非法（未写入模型），切换模式将丢弃这些输入。继续？')) return;
        // 用户确认丢弃 → 清非法输入标记（模型未被这些输入污染）
    
      }
    }
    // 从简易/树切出时，同步 _rawText
    if ((_mode === 'simple' || _mode === 'tree') && _currentData) {
      _rawText = JSON.stringify(_currentData, null, 2);
    }
    // 切换模式时关闭搜索浮层
    if (_searchVisible) hideSearchOverlay();
    _mode = mode;
    if (mode === 'simple') renderSimple();
    else if (mode === 'advanced') renderAdvanced();
    else if (mode === 'tree') renderTree();
    else if (mode === 'modified') renderModified();
    else renderSimple();
    updateTabHighlight();
  }

  function updateTabHighlight() {
    var btns = _modeTabsEl.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      btns[i].className = btns[i].id === ('tab-' + _mode) ? 'active' : '';
    }
    // 搜索按钮在 simple 模式禁用（卡片化已分组，搜索意义低）
    var searchBtn = document.getElementById('ed-search-toggle');
    if (searchBtn) {
      searchBtn.disabled = (_mode === 'simple');
      searchBtn.title = (_mode === 'simple')
        ? '简易模式不支持搜索（已按分类分卡片）'
        : '搜索 key/value';
    }
  }

  // ==================== 简易模式 ====================

  // 类别 → 提示文案（卡片顶部斜体灰字；可选）
  var CATEGORY_HINTS = {
    system: '音频设置 UI 迁移中，此处为临时入口。',
    danger: '改动会影响存档兼容性，需双击解锁后才能编辑。'
  };

  function renderSimple() {
    if (!_currentData) { renderAdvanced(); return; }
    var groups = window.ArchiveSchema.groupByCategory();
    var orderedKeys = window.ArchiveSchema.orderedCategoryKeys();
    var html = '';

    for (var ci = 0; ci < orderedKeys.length; ci++) {
      var cat = orderedKeys[ci];
      var fields = groups[cat];
      if (!fields || fields.length === 0) continue;

      var catMeta = window.ArchiveSchema.categories[cat] || { label: cat };
      var tagHtml = '';
      if (cat === 'system') tagHtml = '<span class="schema-card-tag system">迁移期临时入口</span>';
      else if (cat === 'danger') tagHtml = '<span class="schema-card-tag danger">危险字段</span>';

      html += '<div class="schema-card cat-' + escHtml(cat) + '">';
      html += '<div class="schema-card-header"><h3>' + escHtml(catMeta.label) + '</h3>' + tagHtml + '</div>';
      if (CATEGORY_HINTS[cat])
        html += '<div class="card-temporary-hint">' + escHtml(CATEGORY_HINTS[cat]) + '</div>';

      html += '<div class="schema-form">';
      for (var i = 0; i < fields.length; i++) {
        html += renderSimpleField(fields[i]);
      }
      html += '</div></div>';
    }

    // 非白名单字段提示
    html += '<div style="margin-top:16px;color:#666;font-size:11px">' +
            '以上为常用字段。其他字段请切换到"树视图"或"高级模式"编辑。</div>';

    _panelEl.innerHTML = html;
    bindSimpleFieldEvents();
  }

  // 单个字段 HTML（按 type / preview / danger 分支）
  function renderSimpleField(f) {
    var idx = window.ArchiveSchema.fields.indexOf(f);  // schema 全局索引（事件回查）
    var val = window.ArchiveSchema.getByPath(_currentData, f.path);
    var pathStr = window.ArchiveSchema.pathToString(f.path);
    var labelHtml = '<label title="' + escHtml(pathStr) + '">' + escHtml(f.label) + '</label>';
    var unlocked = !f.danger || _dangerUnlocked[pathStr];

    // literal: 仅显示常量，不可编辑
    if (f.type === 'literal') {
      return labelHtml + '<span class="readonly-val">' + escHtml(String(f.value)) + '</span>';
    }

    // 系统类：滑杆 + 数字 + 预设 + 试听
    if (f.preview && f.type === 'number') {
      var min = f.min != null ? f.min : 0;
      var max = f.max != null ? f.max : 100;
      var n = (val != null && !isNaN(Number(val))) ? Number(val) : (f.default != null ? f.default : min);
      var html = labelHtml +
        '<div class="audio-row">' +
          '<input type="range" data-idx="' + idx + '" data-role="range" min="' + min + '" max="' + max + '" value="' + n + '">' +
          '<input type="number" data-idx="' + idx + '" data-role="num" class="audio-num" value="' + n + '" min="' + min + '" max="' + max + '">' +
          '<span class="audio-presets">' +
            '<button type="button" class="audio-preset" data-idx="' + idx + '" data-preset="0">静音</button>' +
            '<button type="button" class="audio-preset" data-idx="' + idx + '" data-preset="' + (f.default != null ? f.default : 50) + '">默认</button>' +
            '<button type="button" class="audio-preset" data-idx="' + idx + '" data-preset="' + max + '">最大</button>' +
          '</span>' +
          '<button type="button" class="audio-preview" data-idx="' + idx + '">试听</button>' +
        '</div>';
      if (f.hint) html += '<span class="hint' + (f.hintWarn ? ' warn' : '') + '">' + escHtml(f.hint) + '</span>';
      return html;
    }

    // 危险字段（非系统类）：双击解锁
    if (f.danger) {
      var disabledAttr = unlocked ? '' : ' disabled';
      var lockClass = unlocked ? 'danger-lock unlocked' : 'danger-lock';
      var lockText = unlocked ? '已解锁' : '锁定（双击解锁）';
      var inputHtml = '';
      if (f.type === 'number') {
        var minA = (f.min != null) ? ' min="' + f.min + '"' : '';
        var maxA = (f.max != null) ? ' max="' + f.max + '"' : '';
        inputHtml = '<input type="number" data-idx="' + idx + '" value="' + (val != null ? val : 0) + '"' + minA + maxA + disabledAttr + '>';
      } else if (f.type === 'string') {
        var mlA = f.maxLength ? ' maxlength="' + f.maxLength + '"' : '';
        inputHtml = '<input type="text" data-idx="' + idx + '" value="' + escHtml(val != null ? String(val) : '') + '"' + mlA + disabledAttr + '>';
      } else {
        inputHtml = '<input type="text" data-idx="' + idx + '" value="' + escHtml(val != null ? String(val) : '') + '"' + disabledAttr + '>';
      }
      var html = labelHtml + '<div class="danger-field">' + inputHtml +
        '<button type="button" class="' + lockClass + '" data-danger-path="' + escHtml(pathStr) + '">' + escHtml(lockText) + '</button>' +
        '</div>';
      if (f.hint) html += '<span class="hint warn">' + escHtml(f.hint) + '</span>';
      return html;
    }

    // 其余类型（与 v2 行为一致）
    if (f.readonly) {
      return labelHtml + '<span class="readonly-val">' + escHtml(val != null ? String(val) : '—') + '</span>';
    }
    if (f.type === 'enum') {
      var html2 = labelHtml + '<select data-idx="' + idx + '">';
      for (var j = 0; j < f.options.length; j++) {
        var sel = (String(val) === f.options[j]) ? ' selected' : '';
        html2 += '<option value="' + escHtml(f.options[j]) + '"' + sel + '>' + escHtml(f.options[j]) + '</option>';
      }
      html2 += '</select>';
      return html2;
    }
    if (f.type === 'number') {
      var minA2 = (f.min != null) ? ' min="' + f.min + '"' : '';
      var maxA2 = (f.max != null) ? ' max="' + f.max + '"' : '';
      var html3 = labelHtml + '<input type="number" data-idx="' + idx + '" value="' + (val != null ? val : 0) + '"' + minA2 + maxA2 + '>';
      var hint = '';
      if (f.min != null) hint += '最小: ' + f.min;
      if (f.max != null) hint += (hint ? ', ' : '') + '最大: ' + f.max;
      if (hint) html3 += '<span class="hint">' + hint + '</span>';
      return html3;
    }
    if (f.type === 'string') {
      var mlA2 = f.maxLength ? ' maxlength="' + f.maxLength + '"' : '';
      return labelHtml + '<input type="text" data-idx="' + idx + '" value="' + escHtml(val != null ? String(val) : '') + '"' + mlA2 + '>';
    }
    return labelHtml + '<span class="readonly-val">(unsupported type)</span>';
  }

  function bindSimpleFieldEvents() {
    if (!_panelEl) return;
    // 普通输入
    var inputs = _panelEl.querySelectorAll('input[data-idx], select[data-idx]');
    for (var k = 0; k < inputs.length; k++) {
      var role = inputs[k].getAttribute('data-role');
      if (role === 'range' || role === 'num') {
        inputs[k].addEventListener('input', onAudioRowChange);
      } else {
        inputs[k].addEventListener('input', onSimpleFieldChange);
        inputs[k].addEventListener('change', onSimpleFieldChange);
      }
    }
    // 音频预设按钮
    var presets = _panelEl.querySelectorAll('button.audio-preset');
    for (var p = 0; p < presets.length; p++) {
      presets[p].addEventListener('click', onAudioPresetClick);
    }
    // 音频试听按钮
    var previews = _panelEl.querySelectorAll('button.audio-preview');
    for (var q = 0; q < previews.length; q++) {
      previews[q].addEventListener('click', onAudioPreviewClick);
    }
    // 危险字段解锁
    var locks = _panelEl.querySelectorAll('button.danger-lock');
    for (var r = 0; r < locks.length; r++) {
      locks[r].addEventListener('dblclick', onDangerUnlock);
      // 单击只提示
      locks[r].addEventListener('click', function(e) {
        if (!_dangerUnlocked[e.target.getAttribute('data-danger-path')])
          _statusEl.textContent = '危险字段需双击解锁';
      });
    }
  }

  function onDangerUnlock(e) {
    var pathStr = e.target.getAttribute('data-danger-path');
    if (!pathStr) return;
    if (_dangerUnlocked[pathStr]) {
      delete _dangerUnlocked[pathStr];
    } else {
      if (!confirm('解锁后改动 "' + pathStr + '" 可能让档无法被启动器识别。确定继续？')) return;
      _dangerUnlocked[pathStr] = true;
    }
    renderSimple();
  }

  // 音频行：滑杆 / 数字输入 双向同步
  function onAudioRowChange(e) {
    var idx = parseInt(e.target.getAttribute('data-idx'), 10);
    var field = window.ArchiveSchema.fields[idx];
    if (!field) return;

    var val = Number(e.target.value);
    if (isNaN(val)) return;
    if (field.min != null && val < field.min) val = field.min;
    if (field.max != null && val > field.max) val = field.max;

    // 同步另一个 input
    var pair = _panelEl.querySelectorAll('input[data-idx="' + idx + '"]');
    for (var i = 0; i < pair.length; i++) {
      if (pair[i] !== e.target && Number(pair[i].value) !== val) {
        pair[i].value = val;
      }
    }

    window.ArchiveSchema.setByPath(_currentData, field.path, val);
    _isDirty = true;
    updateButtons();
  }

  function onAudioPresetClick(e) {
    var idx = parseInt(e.target.getAttribute('data-idx'), 10);
    var preset = parseInt(e.target.getAttribute('data-preset'), 10);
    var field = window.ArchiveSchema.fields[idx];
    if (!field) return;

    var pair = _panelEl.querySelectorAll('input[data-idx="' + idx + '"]');
    for (var i = 0; i < pair.length; i++) pair[i].value = preset;
    window.ArchiveSchema.setByPath(_currentData, field.path, preset);
    _isDirty = true;
    updateButtons();
  }

  // 试听：走 bootstrap channel "audio_preview" 命令直调 launcher 的 AudioEngine（ma_bridge_*）
  // launcher 一启动就已 init audio engine 并 preload SFX，因此即使 _idleOk（游戏未运行）也能播。
  // SFX 通道额外触发硬编码常驻 SFX (Button9.wav) 播放。
  function onAudioPreviewClick(e) {
    var idx = parseInt(e.target.getAttribute('data-idx'), 10);
    var field = window.ArchiveSchema.fields[idx];
    if (!field || !field.preview) return;

    var val = Number(window.ArchiveSchema.getByPath(_currentData, field.path));
    if (isNaN(val)) val = 0;

    var channel = null;
    if (field.preview === 'audio.master') channel = 'master';
    else if (field.preview === 'audio.bgm') channel = 'bgm';
    else if (field.preview === 'audio.sfx') channel = 'sfx';
    if (!channel) return;

    // 单次性 ack；监听 audio_preview_resp 给状态提示
    var unsub = window.BootstrapApp.onMessage('audio_preview_resp', function(resp) {
      unsub();
      if (resp.channel !== channel) return;  // 防误捕（理论上不会）
      if (resp.ok) {
        if (channel === 'sfx') {
          _statusEl.textContent = '已试听 SFX（音量 ' + val + '）' + (resp.played ? '' : '（preload 未就绪，仅应用音量）');
        } else {
          _statusEl.textContent = '已应用 ' + field.label + '=' + val;
        }
      } else {
        _statusEl.textContent = '试听失败: ' + (resp.error || 'unknown');
      }
    });
    _unsubs.push(unsub);

    try {
      window.BootstrapApp.send({ cmd: 'audio_preview', channel: channel, value: val });
    } catch (ex) {
      unsub();
      _statusEl.textContent = '试听失败: ' + ex.message;
    }
  }

  function onSimpleFieldChange(e) {
    var idx = parseInt(e.target.getAttribute('data-idx'), 10);
    var field = window.ArchiveSchema.fields[idx];
    if (!field || field.readonly) return;

    var rawVal = e.target.value;
    var valid = true;
    var val;

    if (field.type === 'number') {
      var trimmed = rawVal.replace(/^\s+|\s+$/g, '');
      val = Number(trimmed);
      if (trimmed === '' || isNaN(val) || !isFinite(val)) {
        valid = false;
        e.target.className = 'invalid';
        e.target.title = '无法解析为有效数字';
      } else if ((field.min != null && val < field.min) || (field.max != null && val > field.max)) {
        valid = false;
        e.target.className = 'invalid';
        e.target.title = '超出范围' + (field.min != null ? ' (最小: ' + field.min + ')' : '') + (field.max != null ? ' (最大: ' + field.max + ')' : '');
      } else {
        e.target.className = '';
        e.target.title = '';
      }
    } else if (field.type === 'enum') {
      val = rawVal;
    } else {
      val = rawVal;
      if (field.maxLength && rawVal.length > field.maxLength) {
        valid = false;
        e.target.className = 'invalid';
        e.target.title = '超出最大长度 ' + field.maxLength;
      } else {
        e.target.className = '';
        e.target.title = '';
      }
    }

    if (valid) {
      window.ArchiveSchema.setByPath(_currentData, field.path, val);
      _isDirty = true;
    }
    // invalid 状态由 DOM class 驱动，hasInvalidInput() 实时查询
    updateButtons();
  }

  // ==================== 高级模式 ====================

  function renderAdvanced() {
    var text = _currentData ? JSON.stringify(_currentData, null, 2) : _rawText;
    _panelEl.innerHTML =
      '<div class="raw-toolbar">' +
        '<button id="raw-format">格式化</button>' +
        '<button id="raw-validate">校验 JSON</button>' +
      '</div>' +
      '<textarea class="raw-editor" id="raw-ta">' + escHtml(text) + '</textarea>' +
      '<div id="raw-status" class="raw-status"></div>';

    var ta = document.getElementById('raw-ta');
    var statusDiv = document.getElementById('raw-status');

    ta.addEventListener('input', function() {
      _isDirty = true;
      validateRaw(ta.value, statusDiv);
      updateButtons();
    });

    document.getElementById('raw-format').onclick = function() {
      try {
        var obj = JSON.parse(ta.value);
        ta.value = JSON.stringify(obj, null, 2);
        _currentData = obj;
        _rawText = ta.value;
        validateRaw(ta.value, statusDiv);
      } catch (e) {
        statusDiv.textContent = 'JSON 语法错误: ' + e.message;
        statusDiv.className = 'raw-status err';
      }
    };

    document.getElementById('raw-validate').onclick = function() {
      validateRaw(ta.value, statusDiv);
    };

    validateRaw(text, statusDiv);
  }

  function validateRaw(text, statusDiv) {
    try {
      JSON.parse(text);
      statusDiv.textContent = 'JSON 有效 ✓';
      statusDiv.className = 'raw-status ok';
      return true;
    } catch (e) {
      statusDiv.textContent = 'JSON 语法错误: ' + e.message;
      statusDiv.className = 'raw-status err';
      return false;
    }
  }

  // ==================== 树视图 ====================

  function renderTree() {
    if (!_currentData) { renderAdvanced(); return; }
    _panelEl.innerHTML = '<div class="tree-view" id="tree-root"></div>';
    var root = document.getElementById('tree-root');
    var whitelistPaths = window.ArchiveSchema.getWhitelistPathSet();
    renderTreeNode(root, _currentData, [], whitelistPaths, 0);
  }

  function renderTreeNode(parentEl, value, path, whitelistPaths, depth) {
    if (value === null || value === undefined) {
      appendLeaf(parentEl, path, 'null', 'null');
      return;
    }

    if (Array.isArray(value)) {
      var details = document.createElement('details');
      details.className = 'tree-node';
      if (depth < 1) details.open = true;
      var summary = document.createElement('summary');
      var keyStr = path.length > 0 ? String(path[path.length - 1]) : '(root)';
      summary.textContent = keyStr + ' [Array(' + value.length + ')]';
      appendPathHint(summary, path);
      details.appendChild(summary);

      for (var i = 0; i < value.length; i++) {
        var childPath = path.concat([i]);
        var ps = window.ArchiveSchema.pathToString(childPath);
        if (whitelistPaths[ps]) continue; // 白名单字段跳过（简易模式已覆盖）
        if (value[i] !== null && typeof value[i] === 'object') {
          renderTreeNode(details, value[i], childPath, whitelistPaths, depth + 1);
        } else {
          appendLeaf(details, childPath, value[i], typeOf(value[i]));
        }
      }
      parentEl.appendChild(details);
    } else if (typeof value === 'object') {
      var det = document.createElement('details');
      det.className = 'tree-node';
      if (depth < 1) det.open = true;
      var sum = document.createElement('summary');
      var k = path.length > 0 ? String(path[path.length - 1]) : '(root)';
      var keys = Object.keys(value);
      sum.textContent = k + ' {' + keys.length + ' keys}';
      appendPathHint(sum, path);
      det.appendChild(sum);

      for (var j = 0; j < keys.length; j++) {
        var key = keys[j];
        var cp = path.concat([key]);
        var ps2 = window.ArchiveSchema.pathToString(cp);
        if (whitelistPaths[ps2]) continue;
        if (value[key] !== null && typeof value[key] === 'object') {
          renderTreeNode(det, value[key], cp, whitelistPaths, depth + 1);
        } else {
          appendLeaf(det, cp, value[key], typeOf(value[key]));
        }
      }
      parentEl.appendChild(det);
    } else {
      appendLeaf(parentEl, path, value, typeOf(value));
    }
  }

  function appendLeaf(parentEl, path, value, type) {
    var div = document.createElement('div');
    div.className = 'tree-leaf';
    var keyStr = path.length > 0 ? String(path[path.length - 1]) : '';
    div.innerHTML =
      '<span class="tree-key">' + escHtml(keyStr) + '</span>' +
      '<input type="text" value="' + escHtml(value != null ? String(value) : 'null') + '">' +
      '<span class="tree-type">' + escHtml(type) + '</span>';

    appendPathHint(div, path);

    var input = div.querySelector('input');
    input.addEventListener('change', function() {
      var result = parseLeafValue(input.value, type);
      if (result.valid) {
        input.className = '';
        input.title = '';
        window.ArchiveSchema.setByPath(_currentData, path, result.value);
        _isDirty = true;
      } else {
        // 非法值：标红 + 不写回 _currentData
        input.className = 'invalid';
        input.title = result.error;
      }
      updateButtons();
    });
    parentEl.appendChild(div);
  }

  function appendPathHint(el, path) {
    if (path.length === 0) return;
    var hint = document.createElement('span');
    hint.className = 'tree-path-hint';
    hint.textContent = window.ArchiveSchema.pathToString(path);
    el.appendChild(hint);
  }

  function typeOf(v) {
    if (v === null) return 'null';
    if (v === undefined) return 'undefined';
    if (typeof v === 'number') return 'number';
    if (typeof v === 'boolean') return 'boolean';
    return 'string';
  }

  // 返回 { valid: bool, value: any, error?: string }
  // 非法输入 valid=false，不写回 _currentData
  function parseLeafValue(str, origType) {
    if (origType === 'null') {
      if (str === 'null') return { valid: true, value: null };
      // 用户想填入非 null 值 → 变为字符串（类型升级，合理）
      return { valid: true, value: str };
    }
    if (origType === 'boolean') {
      if (str === 'true') return { valid: true, value: true };
      if (str === 'false') return { valid: true, value: false };
      return { valid: false, error: '布尔字段仅接受 true 或 false' };
    }
    if (origType === 'number') {
      var trimmed = str.replace(/^\s+|\s+$/g, '');
      if (trimmed === '' || trimmed === 'null') return { valid: false, error: '数字字段不能为空' };
      var n = Number(trimmed);
      if (isNaN(n)) return { valid: false, error: '无法解析为数字' };
      if (!isFinite(n)) return { valid: false, error: '数值超出安全范围 (Infinity)' };
      return { valid: true, value: n };
    }
    // string / undefined / 其他
    return { valid: true, value: str };
  }

  // ==================== "已修改" 差异视图 ====================

  // 与 schema field.default 对比；只列出当前值≠default 的字段（含 readonly/literal）
  // 没有 default 的字段忽略（不可恢复）。version literal 也忽略。
  function renderModified() {
    if (!_currentData) { renderAdvanced(); return; }
    var fields = window.ArchiveSchema.fields;
    var rows = [];
    for (var i = 0; i < fields.length; i++) {
      var f = fields[i];
      if (f.default == null) continue;  // 没有默认值无法对比
      if (f.type === 'literal') continue;
      var cur = window.ArchiveSchema.getByPath(_currentData, f.path);
      if (cur === undefined || cur === null) continue;
      // 数字按数值比较；其它按字符串
      var same;
      if (f.type === 'number') same = Number(cur) === Number(f.default);
      else same = String(cur) === String(f.default);
      if (same) continue;
      rows.push({ idx: i, field: f, cur: cur });
    }

    if (rows.length === 0) {
      _panelEl.innerHTML = '<div class="diff-empty">档与白名单字段默认值完全一致。</div>';
      return;
    }

    var html = '<div class="diff-list">';
    html += '<div class="diff-row" style="font-weight:600;color:#bbb;border-bottom:1px solid #444">' +
              '<div>字段</div><div>当前值</div><div>默认值</div><div></div>' +
            '</div>';
    for (var r = 0; r < rows.length; r++) {
      var f2 = rows[r].field;
      var pathStr = window.ArchiveSchema.pathToString(f2.path);
      html += '<div class="diff-row">' +
                '<div><span class="diff-label">' + escHtml(f2.label) + '</span><br>' +
                  '<span class="diff-path">' + escHtml(pathStr) + '</span></div>' +
                '<div class="diff-current">' + escHtml(String(rows[r].cur)) + '</div>' +
                '<div class="diff-default">' + escHtml(String(f2.default)) + '</div>' +
                '<div><button class="diff-restore" data-idx="' + rows[r].idx + '">恢复默认</button></div>' +
              '</div>';
    }
    html += '</div>';
    _panelEl.innerHTML = html;

    var btns = _panelEl.querySelectorAll('button.diff-restore');
    for (var b = 0; b < btns.length; b++) {
      btns[b].addEventListener('click', function(e) {
        var idx = parseInt(e.target.getAttribute('data-idx'), 10);
        var f3 = window.ArchiveSchema.fields[idx];
        if (!f3 || f3.default == null) return;
        if (f3.danger && !_dangerUnlocked[window.ArchiveSchema.pathToString(f3.path)]) {
          alert('该字段为危险字段，请先回到简易模式双击解锁后再恢复。');
          return;
        }
        window.ArchiveSchema.setByPath(_currentData, f3.path, f3.default);
        _isDirty = true;
        renderModified();  // 重渲染（恢复后该行会消失）
        updateButtons();
      });
    }
  }

  // ==================== Ctrl+F 搜索浮层 ====================

  function showSearchOverlay() {
    if (_searchVisible || !_panelEl) return;
    _searchVisible = true;
    var ov = document.createElement('div');
    ov.className = 'editor-search-overlay';
    ov.id = 'ed-search';
    ov.innerHTML =
      '<input type="text" id="ed-search-input" placeholder="搜索 key / value...">' +
      '<span class="search-count" id="ed-search-count">0 / 0</span>' +
      '<button id="ed-search-prev" title="上一处">‹</button>' +
      '<button id="ed-search-next" title="下一处">›</button>' +
      '<button id="ed-search-close" title="关闭 (Esc)">×</button>';
    _panelEl.appendChild(ov);

    var input = document.getElementById('ed-search-input');
    var count = document.getElementById('ed-search-count');

    var debounceTimer = null;
    input.addEventListener('input', function() {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(function() { runSearch(input.value, count); }, 200);
    });
    input.addEventListener('keydown', function(e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        if (e.shiftKey) jumpSearch(-1, count);
        else jumpSearch(1, count);
      }
    });
    document.getElementById('ed-search-prev').onclick = function() { jumpSearch(-1, count); };
    document.getElementById('ed-search-next').onclick = function() { jumpSearch(1, count); };
    document.getElementById('ed-search-close').onclick = hideSearchOverlay;

    input.focus();
  }

  function hideSearchOverlay() {
    _searchVisible = false;
    var ov = document.getElementById('ed-search');
    if (ov && ov.parentNode) ov.parentNode.removeChild(ov);
    clearSearchHighlights();
    clearSearchLineMarker();
    _searchHits = [];
    _searchHitIdx = -1;
  }

  function clearSearchLineMarker() {
    if (_searchLineMarker && _searchLineMarker.parentNode)
      _searchLineMarker.parentNode.removeChild(_searchLineMarker);
    _searchLineMarker = null;
    _searchMarkerOffsetTop = -1;
    _searchMarkerHeight = 0;
    if (_searchMarkerScrollHandler) {
      var tas = _panelEl ? _panelEl.querySelectorAll('textarea.raw-editor') : null;
      if (tas) for (var i = 0; i < tas.length; i++) tas[i].removeEventListener('scroll', _searchMarkerScrollHandler);
      _searchMarkerScrollHandler = null;
    }
  }

  // 像素级测量 textarea 内某 offset 的位置 + 高度。
  // 用 hidden div 镜像 textarea 的字体/换行/padding，把"匹配前的文本"灌进去，
  // 用一个 <span> 在匹配字符位置当 sentinel 取 getBoundingClientRect。
  // 这绕过了 line-height: normal 的不确定性，对 Consolas / 字号缩放也准。
  function measureTextareaMatch(ta, matchOffset, matchLen) {
    var cs = window.getComputedStyle(ta);
    var padLeft = parseFloat(cs.paddingLeft) || 0;
    var padRight = parseFloat(cs.paddingRight) || 0;

    var probe = document.createElement('div');
    probe.style.position = 'absolute';
    probe.style.visibility = 'hidden';
    probe.style.left = '-99999px';
    probe.style.top = '0';
    probe.style.width = (ta.clientWidth - padLeft - padRight) + 'px';
    probe.style.padding = '0';
    probe.style.margin = '0';
    probe.style.border = '0';
    probe.style.boxSizing = 'content-box';
    // 文本渲染相关全部对齐 textarea
    var copyProps = ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle',
      'lineHeight', 'letterSpacing', 'tabSize', 'textTransform',
      'wordBreak', 'wordSpacing', 'overflowWrap'];
    for (var i = 0; i < copyProps.length; i++) {
      probe.style[copyProps[i]] = cs[copyProps[i]];
    }
    probe.style.whiteSpace = 'pre-wrap';
    probe.style.overflowWrap = cs.overflowWrap || 'break-word';

    var beforeMatch = ta.value.substring(0, matchOffset);
    // 把 beforeMatch 直接塞 textContent，再追加一个 sentinel span 包裹 1 个匹配字符
    probe.textContent = beforeMatch;
    var sentinel = document.createElement('span');
    var sentinelChar = ta.value.substring(matchOffset, matchOffset + 1) || '​';
    sentinel.textContent = sentinelChar;
    probe.appendChild(sentinel);

    document.body.appendChild(probe);
    var sentinelRect = sentinel.getBoundingClientRect();
    var probeRect = probe.getBoundingClientRect();
    var top = sentinelRect.top - probeRect.top;
    var height = sentinelRect.height;
    document.body.removeChild(probe);

    return { top: top, height: height };
  }

  function setSearchLineMarker(ta, matchOffset, matchLen) {
    if (!_panelEl || !ta) return;
    var m = measureTextareaMatch(ta, matchOffset, matchLen);
    _searchMarkerOffsetTop = m.top;
    _searchMarkerHeight = m.height;

    if (!_searchLineMarker) {
      _searchLineMarker = document.createElement('div');
      _searchLineMarker.className = 'search-line-marker';
      _panelEl.appendChild(_searchLineMarker);
    }
    if (!_searchMarkerScrollHandler) {
      _searchMarkerScrollHandler = function() { repositionSearchLineMarker(ta); };
      ta.addEventListener('scroll', _searchMarkerScrollHandler);
    }
    repositionSearchLineMarker(ta);
  }

  function repositionSearchLineMarker(ta) {
    if (!_searchLineMarker || _searchMarkerOffsetTop < 0) return;
    var taRect = ta.getBoundingClientRect();
    var panelRect = _panelEl.getBoundingClientRect();
    var cs = window.getComputedStyle(ta);
    var padTop = parseFloat(cs.paddingTop) || 0;
    var padBottom = parseFloat(cs.paddingBottom) || 0;
    var padLeft = parseFloat(cs.paddingLeft) || 0;
    var padRight = parseFloat(cs.paddingRight) || 0;
    var borderTop = parseFloat(cs.borderTopWidth) || 0;
    var borderLeft = parseFloat(cs.borderLeftWidth) || 0;

    var contentTopInPanel = (taRect.top - panelRect.top) + borderTop + padTop;
    var top = contentTopInPanel + _searchMarkerOffsetTop - ta.scrollTop;
    var left = (taRect.left - panelRect.left) + borderLeft + padLeft;
    var width = ta.clientWidth - padLeft - padRight;
    var height = _searchMarkerHeight;

    // 超出 textarea 内容视口则隐藏（避免覆盖到 textarea 之外的 UI）
    var contentBottomInPanel = contentTopInPanel + ta.clientHeight - padTop - padBottom;
    if (top + height < contentTopInPanel || top > contentBottomInPanel) {
      _searchLineMarker.style.opacity = '0';
    } else {
      _searchLineMarker.style.opacity = '1';
      _searchLineMarker.style.left = left + 'px';
      _searchLineMarker.style.top = top + 'px';
      _searchLineMarker.style.width = width + 'px';
      _searchLineMarker.style.height = height + 'px';
    }
  }

  function clearSearchHighlights() {
    if (!_panelEl) return;
    var hits = _panelEl.querySelectorAll('.editor-search-hit, .editor-search-hit-current');
    for (var i = 0; i < hits.length; i++) {
      hits[i].classList.remove('editor-search-hit');
      hits[i].classList.remove('editor-search-hit-current');
    }
  }

  // 在当前面板的可搜索元素里找匹配；advanced 模式 textarea 走文本搜索；tree/modified 走 DOM 节点搜索
  // 注意: advanced 模式输入框打字时只统计 hits, 不主动 focus textarea / 不 setSelectionRange,
  // 否则后续按键会覆盖被选中的 JSON 文本损坏档结构 (issue: 输入"se" 时焦点跳到 JSON 第一处 "se" 并选中, 第三个字符直接覆写选中文本)。
  // 跳转 (focus + 选中 + 滚动到行) 只在用户显式点 ‹ / › 或按 Enter 时发生 (jumpSearch)。
  function runSearch(query, countEl) {
    clearSearchHighlights();
    clearSearchLineMarker();
    _searchHits = [];
    _searchHitIdx = -1;
    if (!query || query.length === 0) {
      countEl.textContent = '0 / 0';
      return;
    }

    if (_mode === 'advanced') {
      var ta = _panelEl.querySelector('textarea.raw-editor');
      if (!ta) return;
      var text = ta.value;
      var lower = query.toLowerCase();
      var pos = 0;
      while (true) {
        var hit = text.toLowerCase().indexOf(lower, pos);
        if (hit < 0) break;
        _searchHits.push({ start: hit, len: query.length });
        pos = hit + Math.max(1, query.length);
      }
      countEl.textContent = _searchHits.length === 0 ? '0 / 0' : ('0 / ' + _searchHits.length);
      // 不抢焦点; 用户点 ‹/› 或按 Enter 才跳转
      return;
    }

    // tree / modified：DOM 节点文本扫描（只看 leaf 文本与 input value）
    var lower2 = query.toLowerCase();
    // tree 模式：自动展开匹配节点
    if (_mode === 'tree') {
      var allDetails = _panelEl.querySelectorAll('details.tree-node');
      for (var d = 0; d < allDetails.length; d++) allDetails[d].open = true;
    }
    var leaves = _panelEl.querySelectorAll('.tree-leaf, .diff-row');
    for (var i2 = 0; i2 < leaves.length; i2++) {
      var leaf = leaves[i2];
      var keyText = (leaf.textContent || '').toLowerCase();
      var inp = leaf.querySelector('input');
      var inpVal = inp ? (inp.value || '').toLowerCase() : '';
      if (keyText.indexOf(lower2) >= 0 || inpVal.indexOf(lower2) >= 0) {
        leaf.classList.add('editor-search-hit');
        _searchHits.push(leaf);
      }
    }
    if (_searchHits.length === 0) {
      countEl.textContent = '0 / 0';
      return;
    }
    _searchHitIdx = 0;
    _searchHits[0].classList.add('editor-search-hit-current');
    _searchHits[0].scrollIntoView({ block: 'nearest' });
    countEl.textContent = '1 / ' + _searchHits.length;
  }

  function jumpSearch(dir, countEl) {
    if (_searchHits.length === 0) return;
    if (_mode === 'advanced') {
      var ta = _panelEl.querySelector('textarea.raw-editor');
      if (!ta) return;
      // 第一次 jump 时 _searchHitIdx==-1, 进位到 0; 之后正常环绕
      if (_searchHitIdx < 0) _searchHitIdx = (dir > 0 ? -1 : 0);
      _searchHitIdx = (_searchHitIdx + dir + _searchHits.length) % _searchHits.length;
      var h = _searchHits[_searchHitIdx];
      ta.focus();
      ta.setSelectionRange(h.start, h.start + h.len);
      // 用镜像 div 像素级测量匹配位置 + 行高（绕过 line-height: normal 估算误差）
      var measure = measureTextareaMatch(ta, h.start, h.len);
      // 让匹配落在视口靠上 1/3 处（浏览器 Find-on-Page 习惯）
      var target = measure.top - (ta.clientHeight / 3);
      ta.scrollTop = Math.max(0, target);
      // 标尺与 setSelectionRange 双保险：textarea 失焦后选区颜色变灰几乎不可见（深色主题尤其），
      // 标尺是 absolute div 叠加，与焦点状态无关，跟随 textarea 内部滚动同步移动。
      // setSearchLineMarker 内会复测一次（保证标尺位置和 scrollTop 后的视口对齐）
      setSearchLineMarker(ta, h.start, h.len);
      countEl.textContent = (_searchHitIdx + 1) + ' / ' + _searchHits.length;
      return;
    }
    // tree / modified
    var prev = _searchHits[_searchHitIdx];
    if (prev) prev.classList.remove('editor-search-hit-current');
    _searchHitIdx = (_searchHitIdx + dir + _searchHits.length) % _searchHits.length;
    var cur = _searchHits[_searchHitIdx];
    cur.classList.add('editor-search-hit-current');
    cur.scrollIntoView({ block: 'nearest' });
    countEl.textContent = (_searchHitIdx + 1) + ' / ' + _searchHits.length;
  }

  // ==================== 诊断包导出 ====================

  function onExportDiagnostic() {
    if (!_diagBtn) return;
    _diagBtn.disabled = true;
    _diagStatusEl.className = 'topbar-status';
    _diagStatusEl.textContent = '打包中...';

    var unsub = window.BootstrapApp.onMessage('diagnostic_resp', function(j) {
      unsub();
      _diagBtn.disabled = false;
      if (j.ok) {
        _diagStatusEl.className = 'topbar-status ok';
        var sizeKB = Math.round((j.zipSize || 0) / 1024);
        var msg = '已生成 ' + (j.zipName || '') + ' (' + sizeKB + ' KB)';
        if (j.warnings && j.warnings.length > 0) msg += ' [' + j.warnings.length + ' 个警告]';
        _diagStatusEl.textContent = msg;
        _diagStatusEl.title = (j.zipPath || '') + (j.warnings && j.warnings.length ? '\n\n警告:\n' + j.warnings.join('\n') : '');
        playUiCue('playSuccess');
      } else {
        _diagStatusEl.className = 'topbar-status err';
        _diagStatusEl.textContent = '导出失败: ' + (j.error || 'unknown');
        playUiCue('playError');
      }
    });
    _unsubs.push(unsub);
    window.BootstrapApp.send({ cmd: 'diagnostic', slot: _slot });
  }

  // ==================== 操作 ====================

  function onSave() {
    if (_saveDisabled || !_idleOk) return;

    var data;
    if (_mode === 'advanced' || (_rawOnly && !_currentData)) {
      // 高级模式: 发原始字符串（C# NormalizeDataToJObject 归一）
      var ta = _panelEl.querySelector('.raw-editor');
      if (ta) {
        if (!validateRaw(ta.value, document.getElementById('raw-status'))) return;
        data = ta.value;
      } else {
        data = _rawText;
      }
    } else {
      // 简易/树模式: 发 object
      data = _currentData;
    }

    // 前端校验（简易模式范围 + 树视图类型校验）
    var invalidInputs = _panelEl.querySelectorAll('input.invalid');
    if (invalidInputs.length > 0) {
      alert('有字段超出允许范围，请修正后再保存');
      return;
    }

    _saveBtn.disabled = true;
    _statusEl.textContent = '保存中...';

    var unsub = window.BootstrapApp.onMessage('save_resp', function(msg) {
      unsub();
      _saveBtn.disabled = false;
      if (msg.ok) {
        _isDirty = false;
        _statusEl.textContent = '保存成功 (' + (msg.size || '?') + ' bytes)';
        playUiCue('playSuccess');
        if (msg.warnings) {
          _statusEl.textContent += ' [警告: ' + JSON.stringify(msg.warnings) + ']';
        }
        window.BootstrapApp.refreshList();
        // 延迟关闭
        setTimeout(function() { window.BootstrapApp.closeModal(); }, 800);
      } else {
        _statusEl.textContent = '保存失败: ' + (msg.error || 'unknown');
        _statusEl.style.color = '#e06e6e';
        playUiCue('playError');
      }
    });
    _unsubs.push(unsub);
    window.BootstrapApp.send({ cmd: 'save', slot: _slot, data: data });
  }

  function onResetSlot() {
    if (!_idleOk) return;
    var displayName = _slot;
    if (confirm('确定清理 "' + displayName + '" 的 launcher 副本？\n\n此操作清理 launcher 侧 JSON 备份和删除标记，不影响 Flash 内部 SOL 存档。')) {
      _statusEl.textContent = '清理中...';
      var unsub = window.BootstrapApp.onMessage('reset_resp', function(msg) {
        unsub();
        if (msg.ok) {
          _isDirty = false;
          _statusEl.textContent = '清理成功';
          playUiCue('playSuccess');
          window.BootstrapApp.refreshList();
          setTimeout(function() { window.BootstrapApp.closeModal(); }, 600);
        } else {
          _statusEl.textContent = '清理失败: ' + (msg.error || 'unknown');
          playUiCue('playError');
        }
      });
      _unsubs.push(unsub);
      window.BootstrapApp.send({ cmd: 'reset', slot: _slot, confirm: true });
    }
  }

  // ==================== UI 更新 ====================

  function updateButtons() {
    if (!_saveBtn) return;
    // 保存按钮: inconsistent 永久禁用 / 非 Idle 禁用 / 高级模式 JSON 无效禁用
    var disabled = _saveDisabled || !_idleOk;

    // 高级模式下检查 JSON 有效性
    if (_mode === 'advanced' && !disabled) {
      var ta = _panelEl ? _panelEl.querySelector('.raw-editor') : null;
      if (ta) {
        try { JSON.parse(ta.value); } catch (e) { disabled = true; }
      }
    }

    // 简易模式 / 树视图下检查 invalid 输入
    if ((_mode === 'simple' || _mode === 'tree') && !disabled && _panelEl) {
      var invalids = _panelEl.querySelectorAll('input.invalid');
      if (invalids.length > 0) disabled = true;
    }

    _saveBtn.disabled = disabled;
    _resetBtn.disabled = !_idleOk;

    // 非 Idle 时追加只读提示（不覆盖已有的 error/warn banner）
    if (!_idleOk) {
      showBanner('info', '游戏运行中，编辑器为只读模式', /*priority:*/ 0);
    } else {
      // Idle 恢复时清除低优先级 idle banner（但保留更重要的 error/warn）
      clearBannerIfPriority(0);
    }
  }

  // banner 优先级：0=idle hint (最低), 1=info, 2=warn, 3=error (最高)
  var _bannerPriority = -1;
  var BANNER_PRIORITY_MAP = { info: 1, warn: 2, error: 3 };

  function showBanner(type, text, priority) {
    if (!_bannerEl) return;
    var p = (priority != null) ? priority : (BANNER_PRIORITY_MAP[type] || 1);
    // 不覆盖更高优先级的 banner
    if (p < _bannerPriority) return;
    _bannerPriority = p;
    _bannerEl.innerHTML = '<div class="modal-banner ' + type + '">' + escHtml(text) + '</div>';
  }

  function clearBannerIfPriority(maxPriority) {
    if (!_bannerEl) return;
    if (_bannerPriority <= maxPriority) {
      _bannerEl.innerHTML = '';
      _bannerPriority = -1;
    }
  }

  function escHtml(s) {
    if (s == null) return '';
    return String(s).replace(/[&<>"']/g, function(c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  // ==================== 注册模块 ====================

  window.BootstrapApp.registerModule('archive-editor', {
    mount: mount,
    unmount: unmount,
    canClose: canClose
  });
})();
