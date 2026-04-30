// C2-β: 存档损坏修复卡片
//
// 触发流程:
//   1. C# 决议 saveDecision="repairable" → bootstrap-main 收到 repair_required → 打开本卡片
//   2. mount() 立即发 cmd=repair_detect 拉完整 plan (含每条 fffd 的候选 + policy 自动决议)
//   3. UI 按 layer 分组渲染: 自动项展示已采纳建议, 人工项给候选下拉/手动输入/丢弃
//   4. 用户点"应用修复" → 收集 patches[] → cmd=repair_apply_manual; 成功后 close modal
//      用户点"强制继续" (二次确认) → cmd=repair_force_continue, 不动存档
//      用户点"返回引导器" → cmd=cancel_launch, 退出本次 launch
//   5. AS2 端收到 task=repair_resolved 后退出 RepairPending, 走 loadFromMydata 进游戏
//
// 协议字段: 与 launcher/src/Guardian/Handlers/RepairCommandHandler.cs 严格对齐.

(function() {
  'use strict';

  var _container = null;
  var _unsubs = [];
  var _slot = null;
  var _plan = null;             // detect 拿到的完整 plan
  var _decisionState = [];      // 每条 decision 的用户选择 [{kind, value}, ...]
  var _resolved = false;        // 已 apply / force / cancel — 允许 close
  // 修复写盘成功 + repair_resolved 已 push 给 AS2 后, 进 awaitingFlash 态等 AS2 真正
  // 应用 cleanedSnapshot 完成 loadAll → state 转到 Ready (asLoader 帧循环放行 + sendReady).
  // 卡片不立即关, 防止用户以为修复未生效就开始加载. fallback timer 30s 兜底.
  var _awaitingFlash = false;
  var _awaitTimeoutId = null;
  var AWAIT_FLASH_TIMEOUT_MS = 30000;

  function mount(containerEl, initData) {
    _container = containerEl;
    _slot = (initData && initData.slot) || '';
    var summary = (initData && initData.summary) || null;
    _resolved = false;

    var summaryHtml = renderSummaryHeader(summary);
    _container.innerHTML =
      '<div class="modal-header">' +
        '<h2>存档异常 · 修复向导</h2>' +
        '<button class="modal-close" id="rc-close" title="返回引导器">×</button>' +
      '</div>' +
      '<div class="rc-body">' +
        '<div class="rc-summary" id="rc-summary">' + summaryHtml + '</div>' +
        '<div class="rc-decisions" id="rc-decisions">' +
          '<p class="rc-loading">正在分析存档可修复项…</p>' +
        '</div>' +
      '</div>' +
      '<div class="rc-footer">' +
        '<button id="rc-apply" class="rc-btn-primary" disabled>应用修复并进入游戏</button>' +
        '<button id="rc-force" class="rc-btn-danger" disabled>强制带损坏继续</button>' +
        '<button id="rc-cancel" class="rc-btn">返回引导器</button>' +
      '</div>';

    document.getElementById('rc-close').onclick = function() { onCancel(); };
    document.getElementById('rc-apply').onclick = onApply;
    document.getElementById('rc-force').onclick = onForce;
    document.getElementById('rc-cancel').onclick = onCancel;

    _unsubs.push(window.BootstrapApp.onMessage('repair_detect_resp', onDetectResp));
    _unsubs.push(window.BootstrapApp.onMessage('repair_apply_manual_resp', onApplyResp));
    _unsubs.push(window.BootstrapApp.onMessage('repair_force_continue_resp', onForceResp));
    _unsubs.push(window.BootstrapApp.onMessage('state', onLaunchState));

    window.BootstrapApp.send({ cmd: 'repair_detect', slot: _slot });
  }

  function unmount() {
    if (_awaitTimeoutId != null) { clearTimeout(_awaitTimeoutId); _awaitTimeoutId = null; }
    for (var i = 0; i < _unsubs.length; i++) _unsubs[i]();
    _unsubs = [];
    _container = null;
    _plan = null;
    _decisionState = [];
    _awaitingFlash = false;
  }

  // 在 apply / force / cancel 真正完成前阻止关闭 (避免 ESC / backdrop 误触留 Flash 在 RepairPending).
  // _awaitingFlash 期间也允许关闭 (用户已点过应用, _resolved=true), state=Ready 到达时自动关.
  function canClose() {
    return _resolved;
  }

  // ─────────────── 渲染 ───────────────

  function renderSummaryHeader(summary) {
    if (!summary) return '<p>检测到存档「' + esc(_slot) + '」存在数据异常。</p>';
    var total = summary.totalFffd || 0;
    var byLayer = summary.byLayer || {};
    return '<p>检测到存档「' + esc(_slot) + '」存在 <b>' + total + '</b> 处数据异常。</p>' +
      '<ul class="rc-bylayer">' +
        '<li>L0 角色名 / 时间戳: <b>' + (byLayer.L0 || 0) + '</b> 项 (人工)</li>' +
        '<li>L1 装备 / 模组: <b>' + (byLayer.L1 || 0) + '</b> 项 (字典对齐)</li>' +
        '<li>L2 任务 / 技能 / 统计: <b>' + (byLayer.L2 || 0) + '</b> 项 (字典对齐 / 丢弃)</li>' +
        '<li>L3 发现表 / 设置: <b>' + (byLayer.L3 || 0) + '</b> 项 (静默丢弃)</li>' +
      '</ul>';
  }

  function onDetectResp(msg) {
    if (!msg || msg.slot !== _slot) return;
    if (!msg.ok) {
      var d = document.getElementById('rc-decisions');
      d.innerHTML = '<p class="rc-error">扫描失败: ' + esc(msg.error || '') + ' — ' + esc(msg.msg || '') + '</p>';
      return;
    }
    _plan = msg.plan || null;
    _decisionState = [];
    renderDecisions();
    document.getElementById('rc-apply').disabled = false;
    document.getElementById('rc-force').disabled = false;
  }

  function renderDecisions() {
    var host = document.getElementById('rc-decisions');
    if (!_plan || !_plan.decisions || _plan.decisions.length === 0) {
      host.innerHTML = '<p class="rc-good">未发现需要修复的项。可直接应用进入游戏。</p>';
      return;
    }

    // 按 layer 分组. 同 layer 内按 spot+path 排序保持稳定.
    var groups = { 'L0': [], 'L1': [], 'L2': [], 'L3': [] };
    var idxMap = []; // decisionState 与 _plan.decisions 同序
    for (var i = 0; i < _plan.decisions.length; i++) {
      var d = _plan.decisions[i];
      groups[d.layer || 'L3'].push({ idx: i, d: d });
      _decisionState.push(initialChoiceFor(d));
      idxMap.push(i);
    }

    var html = '';
    var layerLabel = {
      'L0': 'L0 — 阻塞项 (角色名 / 时间戳)',
      'L1': 'L1 — 装备 / 模组 (字典对齐)',
      'L2': 'L2 — 技能 / 任务 / 统计',
      'L3': 'L3 — 发现表 / 设置'
    };
    var order = ['L0', 'L1', 'L2', 'L3'];
    for (var li = 0; li < order.length; li++) {
      var layer = order[li];
      var arr = groups[layer];
      if (arr.length === 0) continue;
      html += '<section class="rc-group rc-group-' + layer.toLowerCase() + '">';
      html += '<h3>' + esc(layerLabel[layer]) + ' · ' + arr.length + ' 项</h3>';
      html += '<ol class="rc-decision-list">';
      for (var j = 0; j < arr.length; j++) {
        html += renderDecisionRow(arr[j].idx, arr[j].d);
      }
      html += '</ol>';
      html += '</section>';
    }
    host.innerHTML = html;

    // 绑事件 — 每行 select / radio / input 都按 idx 数据属性回写 _decisionState.
    var rows = host.querySelectorAll('.rc-row');
    for (var k = 0; k < rows.length; k++) bindRow(rows[k]);
  }

  function renderDecisionRow(idx, d) {
    var pathLabel = (d.path || []).join(' / ');
    var brokenLabel = esc(String(d.broken == null ? '' : d.broken));
    var spotLabel = (d.spot === 'key') ? '键' : '值';
    var actionTag = autoActionLabel(d.action);
    var rowCls = 'rc-row';
    if (d.action === 'ManualRequired' || d.action === 'PreservePlaceholder') rowCls += ' rc-row-manual';
    var html = '<li class="' + rowCls + '" data-idx="' + idx + '">';
    html += '<div class="rc-row-head">';
    html +=   '<span class="rc-spot">[' + spotLabel + ']</span> ';
    html +=   '<code class="rc-path">' + esc(pathLabel) + '</code>';
    html +=   '<span class="rc-broken" title="原始坏值"> · 坏值: <code>' + brokenLabel + '</code></span>';
    html +=   '<span class="rc-action-tag">' + actionTag + '</span>';
    html += '</div>';

    if (d.action === 'ManualRequired' || d.action === 'PreservePlaceholder') {
      html += renderManualOptions(idx, d);
    } else {
      html += renderAutoConfirm(idx, d);
    }
    html += '</li>';
    return html;
  }

  function autoActionLabel(action) {
    switch (action) {
      case 'FixValue':            return '<span class="rc-tag rc-tag-fix">✓ 自动修值</span>';
      case 'RenameKey':           return '<span class="rc-tag rc-tag-fix">✓ 自动改键</span>';
      case 'DropValue':           return '<span class="rc-tag rc-tag-drop">⊗ 自动丢弃</span>';
      case 'ClearValue':          return '<span class="rc-tag rc-tag-drop">⊗ 自动清空</span>';
      case 'DropKey':             return '<span class="rc-tag rc-tag-drop">⊗ 自动删键</span>';
      case 'PreservePlaceholder': return '<span class="rc-tag rc-tag-manual">? 待人工</span>';
      case 'ManualRequired':      return '<span class="rc-tag rc-tag-manual">! 必须人工</span>';
      default:                    return '<span class="rc-tag">' + esc(action) + '</span>';
    }
  }

  function renderAutoConfirm(idx, d) {
    var v = (d.autoNewValue == null) ? '' : String(d.autoNewValue);
    var src = d.autoSource ? ' <em>(' + esc(d.autoSource) + ')</em>' : '';
    var html = '<div class="rc-row-body rc-auto">';
    if (d.action === 'FixValue' || d.action === 'RenameKey') {
      html += '采纳: <code>' + esc(v) + '</code>' + src;
    } else if (d.action === 'ClearValue') {
      html += '设为空字符串以保留 tuple 形状';
    } else if (d.action === 'DropValue' || d.action === 'DropKey') {
      html += '从父容器中移除该条目';
    }
    html += ' <label class="rc-checkbox-label"><input type="checkbox" class="rc-skip" checked> 应用此项</label>';
    html += '</div>';
    return html;
  }

  function renderManualOptions(idx, d) {
    var html = '<div class="rc-row-body rc-manual">';
    var name = 'rc-choice-' + idx;
    var cands = d.candidates || [];
    if (cands.length > 0) {
      html += '<label class="rc-radio-line"><input type="radio" name="' + name + '" value="cand" data-idx="' + idx + '" checked> 采纳候选: ';
      html += '<select class="rc-cand-select" data-idx="' + idx + '">';
      for (var i = 0; i < cands.length; i++) {
        var c = cands[i];
        html += '<option value="' + i + '">' + esc(c.value) + ' [' + esc(c.source || '') + ', ' + (c.confidence != null ? c.confidence.toFixed(2) : '?') + ']</option>';
      }
      html += '</select></label>';
    }
    var startSelected = cands.length > 0 ? '' : ' checked';
    html += '<label class="rc-radio-line"><input type="radio" name="' + name + '" value="manual" data-idx="' + idx + '"' + startSelected + '> 手动输入: ';
    html += '<input type="text" class="rc-manual-input" data-idx="' + idx + '" placeholder="自定义值"></label>';
    if (d.spot === 'value' || d.action === 'PreservePlaceholder') {
      html += '<label class="rc-radio-line"><input type="radio" name="' + name + '" value="drop" data-idx="' + idx + '"> 丢弃 (设为空 / 删除)</label>';
    } else {
      html += '<label class="rc-radio-line"><input type="radio" name="' + name + '" value="drop_key" data-idx="' + idx + '"> 丢弃整个键 (装备槽位会一并丢失)</label>';
    }
    html += '</div>';
    return html;
  }

  function initialChoiceFor(d) {
    // 默认选择: 自动项保留, 手动项默认走候选 [0] (若有), 否则空白手动等用户输入.
    if (d.action === 'ManualRequired' || d.action === 'PreservePlaceholder') {
      if ((d.candidates || []).length > 0) {
        return { kind: 'cand', candIdx: 0 };
      }
      return { kind: 'manual', value: '' };
    }
    return { kind: 'auto', skip: false };
  }

  function bindRow(row) {
    var idx = parseInt(row.getAttribute('data-idx'), 10);

    // auto: skip checkbox
    var skip = row.querySelector('.rc-skip');
    if (skip) {
      skip.onchange = function() {
        _decisionState[idx] = { kind: 'auto', skip: !skip.checked };
      };
    }

    // manual rows: radio + select + input
    var radios = row.querySelectorAll('input[type="radio"]');
    var sel = row.querySelector('.rc-cand-select');
    var inp = row.querySelector('.rc-manual-input');
    var sync = function() {
      var chosen = null;
      for (var i = 0; i < radios.length; i++) if (radios[i].checked) { chosen = radios[i].value; break; }
      if (chosen === 'cand' && sel) {
        _decisionState[idx] = { kind: 'cand', candIdx: parseInt(sel.value, 10) || 0 };
      } else if (chosen === 'manual' && inp) {
        _decisionState[idx] = { kind: 'manual', value: inp.value };
      } else if (chosen === 'drop') {
        _decisionState[idx] = { kind: 'drop' };
      } else if (chosen === 'drop_key') {
        _decisionState[idx] = { kind: 'drop_key' };
      }
    };
    for (var i = 0; i < radios.length; i++) radios[i].onchange = sync;
    if (sel) sel.onchange = sync;
    if (inp) inp.oninput = sync;
  }

  // ─────────────── apply / force / cancel ───────────────

  function onApply() {
    if (!_plan) return;
    var patches = buildPatches();
    if (patches === null) return;  // build 内部已 alert
    setBusy(true);
    window.BootstrapApp.send({ cmd: 'repair_apply_manual', slot: _slot, patches: patches });
  }

  function onApplyResp(msg) {
    if (!msg || msg.slot !== _slot) return;
    if (!msg.ok) {
      setBusy(false);
      window.BootstrapApp.playUiCue('playError');
      alert('修复应用失败: ' + (msg.error || '') + '\n' + (msg.msg || ''));
      return;
    }
    // 写盘成功 + push 已发. 但游戏端是否真的应用了 cleanedSnapshot 还得看 AS2 跑 loadAll 完成,
    // 状态机过到 Ready 才算闭合. 切到 awaiting 态, 等 onLaunchState(Ready) 回调关卡片.
    window.BootstrapApp.playUiCue('playSuccess');
    enterAwaitingFlashState('修复已写入存档 (' + (msg.applied || 0) + ' 项), 正在等待游戏加载…');
  }

  function onForce() {
    var ok = window.confirm(
      '强制带损坏存档继续会让残留 fffd 直接进入游戏, 后续保存可能继续累积破坏。\n\n' +
      '此选项仅用于"我先把游戏跑起来确认问题, 之后再来修复"的场景。\n\n' +
      '确认强制继续吗?'
    );
    if (!ok) return;
    setBusy(true);
    window.BootstrapApp.send({ cmd: 'repair_force_continue', slot: _slot });
  }

  function onForceResp(msg) {
    if (!msg || msg.slot !== _slot) return;
    if (!msg.ok) {
      setBusy(false);
      window.BootstrapApp.playUiCue('playError');
      alert('强制继续失败: ' + (msg.error || '') + '\n' + (msg.msg || ''));
      return;
    }
    window.BootstrapApp.playUiCue('playSuccess');
    enterAwaitingFlashState('已选择强制带损坏继续, 正在等待游戏加载…');
  }

  function onCancel() {
    var ok = window.confirm('返回引导器会终止本次启动。可以稍后再试。是否确认?');
    if (!ok) return;
    _resolved = true;
    window.BootstrapApp.send({ cmd: 'cancel_launch' });
    window.BootstrapApp.closeModal();
  }

  // ─────────────── patches build ───────────────

  function buildPatches() {
    var patches = [];
    var decisions = _plan.decisions;
    for (var i = 0; i < decisions.length; i++) {
      var d = decisions[i];
      var st = _decisionState[i];
      var p = decisionToPatch(d, st);
      if (p === null) {
        alert('第 ' + (i + 1) + ' 项 (' + (d.path || []).join('.') + ') 配置不完整, 请检查后重试。');
        return null;
      }
      if (p === false) continue;  // 跳过 (用户取消勾选)
      patches.push(p);
    }
    return patches;
  }

  // 返回 patch 对象 / false (跳过) / null (配置错误)
  function decisionToPatch(d, st) {
    if (!st) return false;
    var basePath = d.path || [];
    var spot = d.spot || 'value';

    // 自动项: 按 d.action 直接转换. skip=true 跳过.
    if (st.kind === 'auto') {
      if (st.skip) return false;
      switch (d.action) {
        case 'FixValue':
          return { path: basePath, spot: spot, action: 'FixValue', newValue: d.autoNewValue || '' };
        case 'RenameKey':
          return { path: basePath, spot: spot, action: 'RenameKey', newKey: d.autoNewValue || '' };
        case 'ClearValue':
          return { path: basePath, spot: spot, action: 'ClearValue' };
        case 'DropValue':
          return { path: basePath, spot: spot, action: 'DropValue' };
        case 'DropKey':
          return { path: basePath, spot: spot, action: 'DropKey' };
        default:
          return false;  // PreservePlaceholder / ManualRequired 不会到这条 (initialChoiceFor 已分流)
      }
    }

    // 候选采纳: spot=value → FixValue; spot=key → RenameKey
    if (st.kind === 'cand') {
      var cands = d.candidates || [];
      if (cands.length === 0 || st.candIdx == null || cands[st.candIdx] == null) return null;
      var v = cands[st.candIdx].value;
      if (spot === 'key') {
        return { path: basePath, spot: 'key', action: 'RenameKey', newKey: v };
      }
      return { path: basePath, spot: 'value', action: 'FixValue', newValue: v };
    }

    // 手动输入
    if (st.kind === 'manual') {
      var mv = (st.value == null) ? '' : String(st.value);
      if (mv.length === 0) {
        // 空输入相当于 drop
        if (spot === 'key') return { path: basePath, spot: 'key', action: 'DropKey' };
        return { path: basePath, spot: 'value', action: 'ClearValue' };
      }
      if (spot === 'key') {
        return { path: basePath, spot: 'key', action: 'RenameKey', newKey: mv };
      }
      return { path: basePath, spot: 'value', action: 'FixValue', newValue: mv };
    }

    // 丢弃
    if (st.kind === 'drop') {
      if (spot === 'key') return { path: basePath, spot: 'key', action: 'DropKey' };
      // 数组路径用 DropValue (parent 是 array), 否则 ClearValue 更安全
      var lastSeg = basePath[basePath.length - 1];
      if (lastSeg != null && /^\d+$/.test(lastSeg)) {
        return { path: basePath, spot: 'value', action: 'DropValue' };
      }
      return { path: basePath, spot: 'value', action: 'ClearValue' };
    }
    if (st.kind === 'drop_key') {
      return { path: basePath, spot: 'key', action: 'DropKey' };
    }
    return null;
  }

  // ─────────────── helpers ───────────────

  // 切到"等 AS2 加载"态: 锁住所有按钮, 用 footer 显示进度文字; state=Ready 到达时关闭.
  // _resolved=true 让用户随时能 X 关闭 (用户已经做完决策, 仅是 cosmetic 等待).
  function enterAwaitingFlashState(statusText) {
    _awaitingFlash = true;
    _resolved = true;
    var footer = document.querySelector('.rc-footer');
    if (footer) {
      footer.innerHTML =
        '<span class="rc-await-text">' + esc(statusText) + '</span>' +
        '<button id="rc-await-close" class="rc-btn">先关闭</button>';
      var closeBtn = document.getElementById('rc-await-close');
      if (closeBtn) closeBtn.onclick = function() { window.BootstrapApp.closeModal(); };
    }
    // 顶部 X 按钮也仍可关 (canClose 已 true).
    if (_awaitTimeoutId == null) {
      _awaitTimeoutId = setTimeout(function() {
        _awaitTimeoutId = null;
        // 30s 仍未 Ready: 估计 AS2 出问题或还在加载大档; 让 footer 文字提醒, 不强制关.
        var ftr = document.querySelector('.rc-footer .rc-await-text');
        if (ftr) ftr.textContent = '游戏加载耗时较长, 你可以手动关闭此窗口或继续等待。';
      }, AWAIT_FLASH_TIMEOUT_MS);
    }
  }

  function onLaunchState(msg) {
    if (!_awaitingFlash) return;
    if (msg && msg.state === 'Ready') {
      // AS2 已完成 loadAll → bootstrap_ready 已发出 → 状态机过 Ready → 修复闭环.
      _awaitingFlash = false;
      if (_awaitTimeoutId != null) { clearTimeout(_awaitTimeoutId); _awaitTimeoutId = null; }
      window.BootstrapApp.closeModal();
    } else if (msg && msg.state === 'Error') {
      // AS2 卡死或 game_ready_timeout: 让用户看到原因; canClose 已 true, 用户可手动关.
      var ftr = document.querySelector('.rc-footer .rc-await-text');
      if (ftr) ftr.textContent = '游戏加载失败 (' + esc(msg.msg || 'Error') + ') — 可关闭后重试。';
    }
  }

  function setBusy(busy) {
    var apply = document.getElementById('rc-apply');
    var force = document.getElementById('rc-force');
    var cancel = document.getElementById('rc-cancel');
    if (apply) apply.disabled = busy;
    if (force) force.disabled = busy;
    if (cancel) cancel.disabled = busy;
  }

  function esc(s) {
    if (s == null) return '';
    return String(s).replace(/[&<>"']/g, function(c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  window.BootstrapApp.registerModule('repair-card', {
    mount: mount,
    unmount: unmount,
    canClose: canClose
  });
})();
