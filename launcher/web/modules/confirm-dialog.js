/* 终端风确认 / 提示对话框：替代原生 confirm() / alert()。
   与 modal 系统同一外壳、焦点圈定、inert 背景与 ESC 分层纪律；
   危险操作默认焦点不落在确认钮上（首个可聚焦元素是右上 ×，Enter = 关闭 = 取消）。 */
(function () {
  'use strict';
  var _resolver = null;

  function settle(ok) {
    var resolver = _resolver;
    _resolver = null;
    if (!resolver) return;
    window.BootstrapApp.closeModal();
    resolver(ok);
  }

  function mount(container, initData) {
    var data = initData || {};
    var alertOnly = data.alertOnly === true;
    container.classList.add('confirm-dialog-surface');
    container.innerHTML =
      '<div class="modal-header term-heading-rule">' +
        '<h2>' + escapeText(data.title || (alertOnly ? '提示' : '确认操作')) + '</h2>' +
        '<button class="modal-close" id="confirm-dialog-close" aria-label="关闭">×</button>' +
      '</div>' +
      '<div class="confirm-dialog">' +
        '<p class="confirm-dialog-message" id="confirm-dialog-message"></p>' +
        '<p class="confirm-dialog-detail" id="confirm-dialog-detail" hidden></p>' +
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
    document.getElementById('confirm-dialog-ok').onclick = function () { settle(true); };
    var cancelBtn = document.getElementById('confirm-dialog-cancel');
    if (cancelBtn) cancelBtn.onclick = function () { settle(false); };
    document.getElementById('confirm-dialog-close').onclick = function () { settle(false); };
  }

  // closeModal（ESC / 背景点击 / 被新 modal 顶掉）一律视为取消；settle 幂等。
  function unmount() { settle(false); }

  function escapeText(value) {
    return String(value == null ? '' : value)
      .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }

  function open(message, options) {
    var data = options || {};
    data.message = message;
    return new Promise(function (resolve) {
      if (_resolver) _resolver(false);   // 防御：上一框未闭环被顶掉时不留悬空 Promise
      _resolver = resolve;
      window.BootstrapApp.openModal('confirm-dialog', data);
    });
  }

  window.BootstrapConfirm = function (message, options) { return open(message, options); };
  window.BootstrapAlert = function (message, options) {
    var data = options || {};
    data.alertOnly = true;
    return open(message, data);
  };
  window.BootstrapApp.registerModule('confirm-dialog', { mount: mount, unmount: unmount });
})();
