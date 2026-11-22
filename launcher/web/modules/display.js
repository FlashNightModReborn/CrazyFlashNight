// Display 设置：集中提供字号、片头、音频、背景动态与字体扩展入口。

(function () {
  'use strict';

  var _container = null;
  var _unsubConfigResp = null;
  var _unsubMotion = null;

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
              '<span class="fs-preset-label">' + p.label + '</span>' +
              '<span class="fs-preset-x">' + p.value.toFixed(2) + 'x</span>' +
              '</button>';
    }
    return html;
  }

  function mount(containerEl) {
    _container = containerEl;
    var currentScale = (window.BootstrapApp && window.BootstrapApp.getUiFontScale)
      ? window.BootstrapApp.getUiFontScale() : 1.35;
    var sfxOn = !!(window.BootstrapAudio && window.BootstrapAudio.isSfxEnabled && window.BootstrapAudio.isSfxEnabled());
    if (!window.BootstrapAudio) sfxOn = true;
    var ambOn = !!(window.BootstrapAudio && window.BootstrapAudio.isAmbientEnabled && window.BootstrapAudio.isAmbientEnabled());
    var motion = window.PM19Motion || null;
    var paused = !!(motion && motion.isPaused());
    var motionDisabled = !!(motion && motion.isFailed());

    _container.innerHTML =
      '<div class="modal-header term-heading-rule">' +
        '<h2>启动设置</h2>' +
        '<button class="modal-close" id="display-close" aria-label="关闭">×</button>' +
      '</div>' +
      '<div class="about-modal display-modal">' +
        '<section class="display-section">' +
          '<h3>界面字号</h3>' +
          '<div class="fs-preset-row" id="display-fs-row">' + buildFontScaleButtons(currentScale) + '</div>' +
          '<p class="fs-hint">字号立即生效，并在下次启动时沿用。</p>' +
        '</section>' +
        '<section class="display-section">' +
          '<h3>音频与动态</h3>' +
          '<div class="display-toggle-grid">' +
            '<label class="audio-toggle"><input type="checkbox" id="display-sfx"' + (sfxOn ? ' checked' : '') + '> <span>UI 交互音效</span></label>' +
            '<label class="audio-toggle"><input type="checkbox" id="display-ambient"' + (ambOn ? ' checked' : '') + '> <span>θ-FLOOD 环境低频</span></label>' +
            '<label class="audio-toggle"><input type="checkbox" id="display-pm19-pause"' + (paused ? ' checked' : '') + (motionDisabled ? ' disabled' : '') + '> <span>暂停背景动态</span></label>' +
          '</div>' +
          '<p class="fs-hint" id="display-motion-note">' + (motion ? motion.getNote() : '背景动态仅本次启动生效。') + '</p>' +
        '</section>' +
        '<section class="display-section" id="display-options-slot">' +
          '<h3>启动选项</h3>' +
        '</section>' +
      '</div>';

    _container.querySelector('#display-options-slot').appendChild(document.getElementById('display-options'));
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

    var sfxChk = document.getElementById('display-sfx');
    var ambChk = document.getElementById('display-ambient');
    var pauseChk = document.getElementById('display-pm19-pause');
    var motionNote = document.getElementById('display-motion-note');

    function applySfx(v) {
      if (typeof v !== 'boolean') return;
      if (sfxChk) sfxChk.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(v);
    }
    function applyAmb(v) {
      if (typeof v !== 'boolean') return;
      if (ambChk) ambChk.checked = v;
      if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(v);
    }
    function syncMotion() {
      var m = window.PM19Motion;
      if (!m) return;
      var pausedNow = m.isPaused();
      var failedNow = m.isFailed();
      if (pauseChk && pauseChk.checked !== pausedNow) pauseChk.checked = pausedNow;
      if (pauseChk && pauseChk.disabled !== failedNow) pauseChk.disabled = failedNow;
      var note = m.getNote();
      if (motionNote && motionNote.textContent !== note) motionNote.textContent = note;
    }

    if (sfxChk) {
      sfxChk.onchange = function () {
        var desired = sfxChk.checked;
        if (window.BootstrapAudio) window.BootstrapAudio.setSfxEnabled(desired);
        window.BootstrapApp.sendConfigSet('sfxEnabled', desired, applySfx);
      };
    }
    if (ambChk) {
      ambChk.onchange = function () {
        var desired = ambChk.checked;
        if (window.BootstrapAudio) window.BootstrapAudio.setAmbientEnabled(desired);
        window.BootstrapApp.sendConfigSet('ambientEnabled', desired, applyAmb);
      };
    }
    if (pauseChk) {
      pauseChk.onchange = function () {
        if (window.PM19Motion) window.PM19Motion.setPaused(pauseChk.checked);
      };
    }
    if (motion && motion.subscribe) {
      _unsubMotion = motion.subscribe(syncMotion);
    }

    if (window.BootstrapApp && window.BootstrapApp.onMessage) {
      _unsubConfigResp = window.BootstrapApp.onMessage('config_set_resp', function(msg) {
        if (msg.key === 'uiFontScale') syncFsHighlight();
        else if (msg.key === 'sfxEnabled' && typeof msg.currentValue === 'boolean') applySfx(msg.currentValue);
        else if (msg.key === 'ambientEnabled' && typeof msg.currentValue === 'boolean') applyAmb(msg.currentValue);
      });
    }
  }

  function unmount() {
    if (_unsubConfigResp) {
      _unsubConfigResp();
      _unsubConfigResp = null;
    }
    if (_unsubMotion) {
      _unsubMotion();
      _unsubMotion = null;
    }
    document.getElementById('display-options-home').appendChild(document.getElementById('display-options'));
    _container = null;
  }

  window.BootstrapApp.registerModule('display', {
    mount: mount,
    unmount: unmount
  });
})();
