/* 终端风确认 / 提示对话框：替代原生 confirm() / alert()。
   与 modal 系统同一外壳、焦点圈定、inert 背景与 ESC 分层纪律；
   危险操作默认焦点不落在确认钮上（首个可聚焦元素是右上 ×，Enter = 关闭 = 取消）。 */
(function () {
  'use strict';
  var active = null;
  var surface = null;
  var scale = null;

  function settle(value) {
    if (!active) return;
    var dialog = active;
    active = null;
    window.BootstrapApp.closeModal();
    dialog.resolve(value);
  }

  function mount(container, data) {
    active = data;
    surface = container;
    var alertOnly = data.alertOnly === true;
    container.classList.add('confirm-dialog-surface');
    if (data.archive) {
      container.classList.add('save-confirm');
      scale = window.PanelScale.attach(container, 1024, 576);
    }
    container.innerHTML =
      '<div class="modal-header term-heading-rule">' +
        '<h2>' + escapeText(data.title || (alertOnly ? '提示' : '确认操作')) + '</h2>' +
        '<button class="modal-close" id="confirm-dialog-close" aria-label="关闭">×</button>' +
      '</div>' +
      '<div class="confirm-dialog">' +
        '<p class="confirm-dialog-message" id="confirm-dialog-message"></p>' +
        '<p class="confirm-dialog-detail" id="confirm-dialog-detail" hidden></p>' +
        (data.field ? '<label id="confirm-field-label"><span></span><input id="confirm-field" type="text"></label>' : '') +
        '<div class="confirm-dialog-actions">' +
          (alertOnly ? '' : '<button type="button" id="confirm-dialog-cancel" class="term-btn">取消</button>') +
          '<button type="button" id="confirm-dialog-ok" class="term-btn'
            + (data.danger === false ? '' : ' confirm-dialog-ok-danger') + '">'
            + escapeText(data.okText || '确定') + '</button>' +
        '</div>' +
      '</div>';
    document.getElementById('confirm-dialog-message').textContent = data.message || '';
    var detail = document.getElementById('confirm-dialog-detail');
    if (data.detail) {
      detail.textContent = data.detail;
      detail.hidden = false;
    }
    var field = document.getElementById('confirm-field');
    if (field) {
      document.querySelector('#confirm-field-label span').textContent = data.field;
      field.value = data.value || '';
      field.addEventListener('keydown', function (event) {
        if (event.key === 'Enter' && !event.isComposing) { event.preventDefault(); settle(field.value); }
      });
    }
    document.getElementById('confirm-dialog-ok').onclick = function () { settle(field ? field.value : true); };
    var cancelBtn = document.getElementById('confirm-dialog-cancel');
    if (cancelBtn) cancelBtn.onclick = function () { settle(data.field ? null : false); };
    document.getElementById('confirm-dialog-close').onclick = function () { settle(data.field ? null : false); };
  }

  // closeModal（ESC / 背景点击 / 被新 modal 顶掉）一律视为取消；settle 幂等。
  function unmount() {
    if (scale) scale.detach();
    scale = null;
    if (surface) surface.classList.remove('confirm-dialog-surface', 'save-confirm');
    surface = null;
    if (active) active.resolve(active.field ? null : false);
    active = null;
  }

  function escapeText(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function open(message, options) {
    return new Promise(function (resolve) {
      var data = Object.assign({}, options, {message:message, resolve:resolve});
      if (!window.BootstrapApp.openModal('confirm-dialog', data)) resolve(data.field ? null : false);
    });
  }

  window.BootstrapPrompt = function (message, options) { return open(message, options); };
  window.BootstrapConfirm = function (message, options) { return open(message, options); };
  window.BootstrapAlert = function (message, options) {
    var data = options || {};
    data.alertOnly = true;
    return open(message, data);
  };
  window.BootstrapApp.registerModule('confirm-dialog', { mount: mount, unmount: unmount });
})();
