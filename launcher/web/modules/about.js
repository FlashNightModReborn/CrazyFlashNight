// "其他" 弹窗：原版多语言帧的 5 条完整说明 + QQ 群 + 版权 / 致谢
// mount/unmount 契约，经 BootstrapApp.registerModule 注册

(function () {
  'use strict';

  var _container = null;
  var _unsubConfigResp = null;  // config_set_resp 监听器的 unsubscribe fn, unmount 时释放

  // 判断两个缩放值是否算"同一档" (避免浮点精度让按钮高亮漂移)
  function scaleEq(a, b) { return Math.abs(a - b) < 0.001; }

  function buildFontScaleButtons(currentScale) {
    var presets = (window.BootstrapApp && window.BootstrapApp.getUiFontScalePresets)
      ? window.BootstrapApp.getUiFontScalePresets()
      : [];
    var html = '';
    for (var i = 0; i < presets.length; i++) {
      var p = presets[i];
      var active = scaleEq(p.value, currentScale) ? ' active' : '';
      html += '<button type="button" class="fs-preset-btn' + active + '" ' +
              'data-scale="' + p.value.toFixed(2) + '">' +
              p.label + '<span class="fs-preset-x">' + p.value.toFixed(2) + 'x</span>' +
              '</button>';
    }
    return html;
  }

  function mount(containerEl) {
    _container = containerEl;
    // 初始值从 BootstrapAudio 当前状态读 (list_resp 注入后已 apply), fallback 默认 true/false
    var sfxOn = !!(window.BootstrapAudio && window.BootstrapAudio.isSfxEnabled && window.BootstrapAudio.isSfxEnabled());
    if (!window.BootstrapAudio) sfxOn = true;
    var ambOn = !!(window.BootstrapAudio && window.BootstrapAudio.isAmbientEnabled && window.BootstrapAudio.isAmbientEnabled());
    var currentScale = (window.BootstrapApp && window.BootstrapApp.getUiFontScale)
      ? window.BootstrapApp.getUiFontScale() : 1.35;
    _container.innerHTML =
      '<div class="modal-header">' +
        '<h2>ABOUT · 说明 / 版权</h2>' +
        '<button class="modal-close" id="about-close">\u00d7</button>' +
      '</div>' +
      '<div class="about-modal">' +
        '<h3>DOCUMENT</h3>' +
        '<p>1. 本游戏游戏过程中将存储数据在本地，请勿设置禁止储存数据。</p>' +
        '<p>2. 本游戏为无网单机版。无充值系统，无与网络相关的功能。如果要体验完整联机功能，请选择《闪客快打 7 佣兵帝国》网络版。</p>' +
        '<p>3. 然而网络版已经停服，你现在玩到的是玩家重置的单机版 MOD。</p>' +
        '<p>4. 请首先在 Steam 平台购买正版游戏，按照指南覆盖 MOD 文件包。本 MOD 为免费开源项目，如果您不慎支付购买，请保留交易证据并联系我们。</p>' +
        '<p>5. 加入我们的 QQ 群：' +
          '<span class="qq">562130873</span><span class="b">（将满）</span>、' +
          '<span class="qq">149188029</span><span class="b">（将满）</span>、' +
          '<span class="qq">307710279</span>' +
          ' 参与讨论，关注 B 站账号 <span class="qq">黑月雾人</span> 与 <span class="qq">无名氏的低谷</span> 获取最新信息。</p>' +
        '<h3 style="margin-top:18px">DISPLAY · 字号</h3>' +
        '<div class="fs-preset-row" id="about-fs-row">' + buildFontScaleButtons(currentScale) + '</div>' +
        '<p class="fs-hint">GPD 等小屏设备建议选「大」或「超大」; 1080p+ 大屏可用「紧凑」保持高密度布局。</p>' +
        '<h3 style="margin-top:18px">AUDIO</h3>' +
        '<div class="audio-toggles">' +
          '<label class="audio-toggle"><input type="checkbox" id="about-sfx"' + (sfxOn ? ' checked' : '') + '> <span>UI 音效 · hover / click / confirm / error</span></label>' +
          '<label class="audio-toggle"><input type="checkbox" id="about-ambient"' + (ambOn ? ' checked' : '') + '> <span>环境 hum · θ-FLOOD 背景低频</span></label>' +
        '</div>' +
        '<p class="foot">本 MOD 版权归原游戏开发者 <span class="b">AndyLaw</span> 及社区共同所有。特此感谢 <span class="b">FFDec</span> 软件作者在文件编译与版本适配方面给予的支持，以及 AndyLaw 提供改编授权。</p>' +
      '</div>';

    document.getElementById('about-close').onclick = function () {
      window.BootstrapApp.tryCloseModal();
    };

    // 字号预设按钮: 事件委托到 row, 点击切档 + 同步高亮
    var fsRow = document.getElementById('about-fs-row');
    function syncFsHighlight() {
      if (!_container) return;  // 已 unmount
      var current = (window.BootstrapApp && window.BootstrapApp.getUiFontScale)
        ? window.BootstrapApp.getUiFontScale() : 1.35;
      var btns = fsRow.children;
      for (var i = 0; i < btns.length; i++) {
        var v = parseFloat(btns[i].getAttribute('data-scale'));
        if (!isNaN(v) && scaleEq(v, current)) btns[i].classList.add('active');
        else btns[i].classList.remove('active');
      }
    }
    fsRow.onclick = function (ev) {
      var btn = ev.target;
      while (btn && btn !== fsRow && !btn.classList.contains('fs-preset-btn')) btn = btn.parentNode;
      if (!btn || btn === fsRow) return;
      var v = parseFloat(btn.getAttribute('data-scale'));
      if (isNaN(v)) return;
      if (window.BootstrapApp && window.BootstrapApp.setUiFontScale) {
        window.BootstrapApp.setUiFontScale(v);
      }
      // 乐观高亮: 假设 config_set 会成功. 若失败会通过下面的 onMessage 订阅回退.
      var children = fsRow.children;
      for (var i = 0; i < children.length; i++) children[i].classList.remove('active');
      btn.classList.add('active');
    };

    // 监听 config_set_resp: uiFontScale 持久化失败 → bootstrap-main 已把 scale 回退,
    // 这里根据回退后的值同步按钮高亮, 避免 "UI 说选中大档但实际还是标准档" 的幽灵状态.
    if (window.BootstrapApp && window.BootstrapApp.onMessage) {
      _unsubConfigResp = window.BootstrapApp.onMessage('config_set_resp', function(msg) {
        if (msg.key === 'uiFontScale' && !msg.ok) syncFsHighlight();
      });
    }

    // sfx / ambient: 乐观应用 + 服务端权威对齐 (Plan A+).
    // applyFn 接收服务端回的 currentValue, 无条件把 checkbox + BootstrapAudio 对齐过去 —
    // 失败时即便 modal 仍然开着, UI 也能立刻跳回服务端 rollback 后的真实值, 不会"报失败但音效仍响".
    // DOM 查询放在 apply 内部: modal 被关掉/重新 mount 时 element 可能已脱落, 防御空引用.
    function applySfxState(v) {
      if (typeof v !== 'boolean') return;
      var el = document.getElementById('about-sfx');
      if (el) el.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(v);
    }
    function applyAmbientState(v) {
      if (typeof v !== 'boolean') return;
      var el = document.getElementById('about-ambient');
      if (el) el.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(v);
    }
    var sfxChk = document.getElementById('about-sfx');
    sfxChk.onchange = function () {
      var desired = sfxChk.checked;
      if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(desired);  // optimistic
      window.BootstrapApp.sendConfigSet('sfxEnabled', desired, applySfxState);
    };
    var ambChk = document.getElementById('about-ambient');
    ambChk.onchange = function () {
      var desired = ambChk.checked;
      if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(desired);  // optimistic
      window.BootstrapApp.sendConfigSet('ambientEnabled', desired, applyAmbientState);
    };
  }

  function unmount() {
    if (_unsubConfigResp) { _unsubConfigResp(); _unsubConfigResp = null; }
    _container = null;
  }

  window.BootstrapApp.registerModule('about', {
    mount: mount,
    unmount: unmount
  });
})();
