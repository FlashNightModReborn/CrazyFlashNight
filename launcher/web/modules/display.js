// Display 设置：集中提供音频、背景动态、Flash 本地存储配额、片头与字体扩展入口。

(function () {
  'use strict';

  var _container = null;
  var _unsubConfigResp = null;
  var _unsubMotion = null;
  var _unsubStorage = null;

  var STORAGE_PRESETS = [
    { limitKb: 100,   label: '100 KB', sub: 'Flash 默认' },
    { limitKb: 1024,  label: '1 MB',   sub: '轻度存档' },
    { limitKb: 10240, label: '10 MB',  sub: '多槽存档' },
    { limitKb: -2,    label: '无限制', sub: '推荐', recommended: true }
  ];

  function limitEq(a, b) {
    return typeof a === 'number' && typeof b === 'number' && Math.abs(a - b) < 0.01;
  }

  function buildStorageButtons() {
    var html = '';
    for (var i = 0; i < STORAGE_PRESETS.length; i++) {
      var p = STORAGE_PRESETS[i];
      html += '<button type="button" class="storage-preset-btn' + (p.recommended ? ' is-recommended' : '') + '" ' +
              'data-limit-kb="' + p.limitKb + '" aria-pressed="false">' +
              '<span class="storage-preset-label">' + p.label + '</span>' +
              '<span class="storage-preset-sub">' + p.sub + '</span>' +
              '</button>';
    }
    return html;
  }

  function mount(containerEl) {
    _container = containerEl;
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
          '<h3>音频与动态</h3>' +
          '<div class="display-toggle-grid">' +
            '<label class="audio-toggle"><input type="checkbox" id="display-sfx"' + (sfxOn ? ' checked' : '') + '> <span>UI 交互音效</span></label>' +
            '<label class="audio-toggle"><input type="checkbox" id="display-ambient"' + (ambOn ? ' checked' : '') + '> <span>θ-FLOOD 环境低频</span></label>' +
            '<label class="audio-toggle"><input type="checkbox" id="display-pm19-pause"' + (paused ? ' checked' : '') + (motionDisabled ? ' disabled' : '') + '> <span>暂停背景动态</span></label>' +
          '</div>' +
          '<p class="fs-hint" id="display-motion-note">' + (motion ? motion.getNote() : '背景动态仅本次启动生效。') + '</p>' +
        '</section>' +
        '<section class="display-section display-storage-section" id="display-storage-section">' +
          '<div class="storage-head">' +
            '<h3>Flash 本地存储</h3>' +
            '<span class="storage-status-pill" id="display-storage-pill" data-tone="muted">检测中…</span>' +
          '</div>' +
          '<div class="storage-usage-row">' +
            '<span class="storage-usage-text" id="display-storage-usage">正在读取本机 Flash 存储配额…</span>' +
          '</div>' +
          '<div class="storage-meter" aria-hidden="true"><div class="storage-meter-fill" id="display-storage-fill"></div></div>' +
          '<div class="storage-preset-row" id="display-storage-row">' + buildStorageButtons() + '</div>' +
          '<p class="fs-hint" id="display-storage-note">调整当前 Windows 用户的 Flash 本地存储上限（#local）；修改后下次启动/建角立即生效。</p>' +
        '</section>' +
        '<section class="display-section" id="display-options-slot">' +
          '<h3>启动选项</h3>' +
        '</section>' +
      '</div>';

    _container.querySelector('#display-options-slot').appendChild(document.getElementById('display-options'));
    document.getElementById('display-close').onclick = function () {
      window.BootstrapApp.tryCloseModal();
    };

    var sfxChk = document.getElementById('display-sfx');
    var ambChk = document.getElementById('display-ambient');
    var pauseChk = document.getElementById('display-pm19-pause');
    var motionNote = document.getElementById('display-motion-note');
    var storagePill = document.getElementById('display-storage-pill');
    var storageUsage = document.getElementById('display-storage-usage');
    var storageFill = document.getElementById('display-storage-fill');
    var storageRow = document.getElementById('display-storage-row');
    var storageNote = document.getElementById('display-storage-note');

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

    function syncStorage(snap) {
      if (!_container) return;
      var app = window.BootstrapApp || {};
      var st = snap && snap.status;
      var busy = !!(snap && snap.busy);
      var err = snap && snap.error;
      var btns = storageRow ? storageRow.querySelectorAll('.storage-preset-btn') : [];

      if (!st) {
        if (storagePill) { storagePill.textContent = '待连接'; storagePill.dataset.tone = 'muted'; }
        if (storageUsage) storageUsage.textContent = '正在读取本机 Flash 存储状态（需新版宿主支持）…';
        if (storageFill) { storageFill.style.width = '0%'; storageFill.dataset.tone = 'muted'; }
        for (var k = 0; k < btns.length; k++) {
          btns[k].disabled = true;
          btns[k].classList.remove('active');
          btns[k].setAttribute('aria-pressed', 'false');
        }
        return;
      }

      var fmtSize = app.formatFlashStorageSize || function (b) { return b + ' B'; };
      var fmtLimit = app.formatFlashStorageLimit || function (s) { return s.unlimited ? '无限制' : s.limitKb + ' KB'; };
      var fmtErr = app.formatFlashStorageError || function (e) { return String(e || ''); };

      var tone = st.status === 'ok'
        ? (st.unlimited ? 'ok' : 'ok')
        : ((st.status === 'exceeded' || st.status === 'blocked') ? 'danger' : 'warn');
      var pillText = st.unlimited
        ? '无限制 · 充裕'
        : (st.status === 'blocked' ? '已禁用 (0 KB)'
          : (st.status === 'exceeded' ? '已达上限'
            : (st.status === 'warning' ? '上限偏低' : '上限 ' + fmtLimit(st))));

      if (storagePill) {
        storagePill.textContent = pillText;
        storagePill.dataset.tone = tone;
      }
      if (storageUsage) {
        var filesTxt = st.usedFiles > 0 ? (' · ' + st.usedFiles + ' 个文件') : '';
        storageUsage.textContent = st.unlimited
          ? ('当前已使用 ' + fmtSize(st.usedBytes) + filesTxt + ' · 上限：无限制')
          : ('当前已使用 ' + fmtSize(st.usedBytes) + ' / ' + fmtLimit(st) + filesTxt);
      }
      if (storageFill) {
        var pct = st.unlimited
          ? 100
          : (st.limitBytes && st.limitBytes > 0
            ? Math.min(100, Math.max(2, Math.round((st.usedBytes / st.limitBytes) * 100)))
            : 100);
        storageFill.style.width = pct + '%';
        storageFill.dataset.tone = st.unlimited ? 'unlimited' : tone;
      }

      var canModify = st.canModifyNow !== false;
      for (var i = 0; i < btns.length; i++) {
        var v = parseFloat(btns[i].getAttribute('data-limit-kb'));
        var selected = st.unlimited ? limitEq(v, -2) : limitEq(v, st.limitKb);
        btns[i].classList.toggle('active', selected);
        btns[i].setAttribute('aria-pressed', String(selected));
        btns[i].disabled = busy || !canModify;
      }

      if (storageNote) {
        storageNote.classList.remove('is-error', 'is-warn');
        if (busy) {
          storageNote.textContent = '正在更新 Flash 本地存储上限并同步空闲预热进程…';
        } else if (err) {
          storageNote.textContent = fmtErr(err);
          storageNote.classList.add('is-error');
        } else if (!canModify) {
          storageNote.textContent = '当前有游戏或建角进程正在运行，请取消返回首页后再调整上限。';
          storageNote.classList.add('is-warn');
        } else {
          storageNote.textContent = '调整当前 Windows 用户的 Flash 本地存储上限（#local）；修改后下次启动/建角立即生效。';
        }
      }
    }

    if (storageRow) {
      storageRow.onclick = function (ev) {
        var btn = ev.target;
        while (btn && btn !== storageRow && !btn.classList.contains('storage-preset-btn')) btn = btn.parentNode;
        if (!btn || btn === storageRow || btn.disabled) return;
        var limitKb = parseFloat(btn.getAttribute('data-limit-kb'));
        if (isNaN(limitKb)) return;
        if (window.BootstrapApp && window.BootstrapApp.setFlashStorageLimit) {
          window.BootstrapApp.setFlashStorageLimit(limitKb);
        }
      };
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
        if (msg.key === 'sfxEnabled' && typeof msg.currentValue === 'boolean') applySfx(msg.currentValue);
        else if (msg.key === 'ambientEnabled' && typeof msg.currentValue === 'boolean') applyAmb(msg.currentValue);
      });
    }

    if (window.BootstrapApp && window.BootstrapApp.onFlashStorageChange) {
      _unsubStorage = window.BootstrapApp.onFlashStorageChange(syncStorage);
      syncStorage(window.BootstrapApp.getFlashStorageState ? window.BootstrapApp.getFlashStorageState() : null);
      if (window.BootstrapApp.refreshFlashStorageStatus) {
        window.BootstrapApp.refreshFlashStorageStatus();
      }
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
    if (_unsubStorage) {
      _unsubStorage();
      _unsubStorage = null;
    }
    document.getElementById('display-options-home').appendChild(document.getElementById('display-options'));
    _container = null;
  }

  window.BootstrapApp.registerModule('display', {
    mount: mount,
    unmount: unmount
  });
})();
