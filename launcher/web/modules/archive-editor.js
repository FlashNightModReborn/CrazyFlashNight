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

  var _mode = 'simple';     // 'simple' | 'advanced' | 'tree'
  var _rawOnly = false;      // true = 仅高级模式可用
  var _saveDisabled = false; // inconsistent slot 永久禁用保存
  var _idleOk = true;        // 当前是否 Idle
  var _unsubs = [];

  // DOM 引用
  var _bannerEl = null;
  var _modeTabsEl = null;
  var _panelEl = null;
  var _saveBtn = null;
  var _resetBtn = null;
  var _statusEl = null;

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
        '<button class="modal-close" id="ed-close">\u00d7</button>' +
      '</div>' +
      '<div id="ed-banner"></div>' +
      '<div id="ed-mode-tabs" class="mode-tabs"></div>' +
      '<div id="ed-panel"></div>' +
      '<div id="ed-status" style="font-size:11px;color:#888;margin-top:8px"></div>' +
      '<div class="modal-actions">' +
        '<button id="ed-save" class="primary">保存</button>' +
        '<button id="ed-reset-slot" class="danger">清理副本</button>' +
        '<button id="ed-cancel">取消</button>' +
      '</div>';

    _bannerEl = document.getElementById('ed-banner');
    _modeTabsEl = document.getElementById('ed-mode-tabs');
    _panelEl = document.getElementById('ed-panel');
    _saveBtn = document.getElementById('ed-save');
    _resetBtn = document.getElementById('ed-reset-slot');
    _statusEl = document.getElementById('ed-status');

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
    for (var i = 0; i < _unsubs.length; i++) _unsubs[i]();
    _unsubs = [];
    _container = null;
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
      }

      _statusEl.textContent = '';
      renderModes();
      updateButtons();
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
      '<button id="tab-tree">树视图</button>';
    document.getElementById('tab-simple').onclick = function() { switchMode('simple'); };
    document.getElementById('tab-advanced').onclick = function() { switchMode('advanced'); };
    document.getElementById('tab-tree').onclick = function() { switchMode('tree'); };

    if (_mode === 'simple') renderSimple();
    else if (_mode === 'advanced') renderAdvanced();
    else renderTree();

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
    _mode = mode;
    if (mode === 'simple') renderSimple();
    else if (mode === 'advanced') renderAdvanced();
    else renderTree();
    updateTabHighlight();
  }

  function updateTabHighlight() {
    var btns = _modeTabsEl.querySelectorAll('button');
    for (var i = 0; i < btns.length; i++) {
      btns[i].className = btns[i].id === ('tab-' + _mode) ? 'active' : '';
    }
  }

  // ==================== 简易模式 ====================

  function renderSimple() {
    if (!_currentData) { renderAdvanced(); return; }
    var fields = window.ArchiveSchema.fields;
    var html = '<div class="schema-form">';
    for (var i = 0; i < fields.length; i++) {
      var f = fields[i];
      var val = window.ArchiveSchema.getByPath(_currentData, f.path);
      var pathStr = window.ArchiveSchema.pathToString(f.path);
      html += '<label title="' + escHtml(pathStr) + '">' + escHtml(f.label) + '</label>';

      if (f.readonly) {
        html += '<span class="readonly-val">' + escHtml(val != null ? String(val) : '—') + '</span>';
      } else if (f.type === 'enum') {
        html += '<select data-idx="' + i + '">';
        for (var j = 0; j < f.options.length; j++) {
          var sel = (String(val) === f.options[j]) ? ' selected' : '';
          html += '<option value="' + escHtml(f.options[j]) + '"' + sel + '>' + escHtml(f.options[j]) + '</option>';
        }
        html += '</select>';
      } else if (f.type === 'number') {
        var minAttr = (f.min != null) ? ' min="' + f.min + '"' : '';
        var maxAttr = (f.max != null) ? ' max="' + f.max + '"' : '';
        html += '<input type="number" data-idx="' + i + '" value="' + (val != null ? val : 0) + '"' + minAttr + maxAttr + '>';
        var hint = '';
        if (f.min != null) hint += '最小: ' + f.min;
        if (f.max != null) hint += (hint ? ', ' : '') + '最大: ' + f.max;
        if (hint) html += '<span class="hint">' + hint + '</span>';
      } else if (f.type === 'string') {
        var mlAttr = f.maxLength ? ' maxlength="' + f.maxLength + '"' : '';
        html += '<input type="text" data-idx="' + i + '" value="' + escHtml(val != null ? String(val) : '') + '"' + mlAttr + '>';
      }
    }
    html += '</div>';

    // 非白名单字段提示
    html += '<div style="margin-top:16px;color:#666;font-size:11px">' +
            '以上为常用字段。其他字段请切换到"树视图"或"高级模式"编辑。</div>';

    _panelEl.innerHTML = html;

    // 绑定事件
    var inputs = _panelEl.querySelectorAll('input, select');
    for (var k = 0; k < inputs.length; k++) {
      inputs[k].addEventListener('input', onSimpleFieldChange);
      inputs[k].addEventListener('change', onSimpleFieldChange);
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
      statusDiv.textContent = 'JSON 有效 \u2713';
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
        if (msg.warnings) {
          _statusEl.textContent += ' [警告: ' + JSON.stringify(msg.warnings) + ']';
        }
        window.BootstrapApp.refreshList();
        // 延迟关闭
        setTimeout(function() { window.BootstrapApp.closeModal(); }, 800);
      } else {
        _statusEl.textContent = '保存失败: ' + (msg.error || 'unknown');
        _statusEl.style.color = '#e06e6e';
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
          window.BootstrapApp.refreshList();
          setTimeout(function() { window.BootstrapApp.closeModal(); }, 600);
        } else {
          _statusEl.textContent = '清理失败: ' + (msg.error || 'unknown');
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
