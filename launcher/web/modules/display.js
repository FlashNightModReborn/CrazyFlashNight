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
              'aria-pressed="' + !!active + '" data-scale="' + p.value.toFixed(2) + '">' +
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
      '<div class="modal-header term-heading-rule">' +
        '<h2>启动设置</h2>' +
        '<button class="modal-close" id="display-close" aria-label="关闭">×</button>' +
      '</div>' +
      '<div class="about-modal display-modal">' +
        '<h3>界面字号</h3>' +
        '<div class="fs-preset-row" id="display-fs-row">' + buildFontScaleButtons(currentScale) + '</div>' +
        '<p class="fs-hint">字号立即生效，也会在下次启动时沿用。</p>' +
        '<h3>启动选项</h3>' +
      '</div>';

    _container.querySelector('.display-modal').appendChild(document.getElementById('display-options'));
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
        var selected = scaleEq(v, current);
        btns[i].classList.toggle('active', selected);
        btns[i].setAttribute('aria-pressed', String(selected));
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
    document.getElementById('display-options-home').appendChild(document.getElementById('display-options'));
    _container = null;
  }

  window.BootstrapApp.registerModule('display', {
    mount: mount,
    unmount: unmount
  });
})();
