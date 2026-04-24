// Display 设置：把字号入口放到顶栏，避免用户为了看清文字去开 Windows 高 DPI 覆盖。

(function () {
  'use strict';

  var _container = null;
  var _unsubConfigResp = null;

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
    var currentScale = (window.BootstrapApp && window.BootstrapApp.getUiFontScale)
      ? window.BootstrapApp.getUiFontScale() : 1.35;

    _container.innerHTML =
      '<div class="modal-header">' +
        '<h2>DISPLAY · 显示</h2>' +
        '<button class="modal-close" id="display-close">×</button>' +
      '</div>' +
      '<div class="about-modal display-modal">' +
        '<h3>FONT SIZE · 字号</h3>' +
        '<div class="fs-preset-row" id="display-fs-row">' + buildFontScaleButtons(currentScale) + '</div>' +
        '<p class="fs-hint">如果觉得启动器文字发虚或太小，优先在这里调大字号；Windows 高 DPI 兼容性覆盖建议保持关闭，或选择“应用程序”。</p>' +
        '<p class="fs-hint">字号会立即生效并保存到用户配置。窗口太小时页面会改为滚动，不再偷偷限制你选择的字号。</p>' +
      '</div>';

    document.getElementById('display-close').onclick = function () {
      window.BootstrapApp.tryCloseModal();
    };

    var fsRow = document.getElementById('display-fs-row');
    function syncFsHighlight() {
      if (!_container || !fsRow) return;
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
      syncFsHighlight();
    };

    if (window.BootstrapApp && window.BootstrapApp.onMessage) {
      _unsubConfigResp = window.BootstrapApp.onMessage('config_set_resp', function(msg) {
        if (msg.key === 'uiFontScale') syncFsHighlight();
      });
    }
  }

  function unmount() {
    if (_unsubConfigResp) {
      _unsubConfigResp();
      _unsubConfigResp = null;
    }
    _container = null;
  }

  window.BootstrapApp.registerModule('display', {
    mount: mount,
    unmount: unmount
  });
})();
