// 通讯终端（AI 聊天终端 · 游戏内嵌面板）
// ------------------------------------------------------------------
// 面板内以 iframe 承载本机 cfn-rag 内嵌服务（127.0.0.1:7077）的聊天页面。
// 打开链：AS2 联络列表 → panel_request('ragchat') → LauncherCommandRouter 的
//   RagTerminalService 异步确保服务就绪并绑定当前存档 → OpenPanel('ragchat', initData)。
// initData：{source, frontend_url, savePath}。frontend_url 已由 Host 按 loopback
//   前缀校验；本面板再按精确 origin 复核，不可信即不加载 iframe（fail-closed）。
// 懒注册：panels-lazy-registry.js 的 registerLazy('ragchat', ['modules/ragchat.js'])。
(function () {
  'use strict';

  if (typeof Panels === 'undefined') return;

  var TRUSTED_ORIGIN = 'http://127.0.0.1:7077';

  var root = null;
  var shell = null;
  var scale = null;
  var statusEl = null;
  var disposers = [];

  Panels.register('ragchat', {
    create: createDOM,
    onOpen: onOpen,
    onRebind: function (element, data) { cleanup(); onOpen(element, data); },
    // ESC / backdrop 与 DOM × 按钮共用：先 Panels.close() 复位 _active，
    // 再通知 Host 走 generic close 回流（恢复 HUD / backdrop / 面板暂停）。
    onRequestClose: closeTerminal,
    onClose: cleanup,
    onForceClose: cleanup
  });

  function closeTerminal() {
    if (window.BootstrapAudio) window.BootstrapAudio.cue('back');  // 语义音效：关闭
    try { Panels.close(); } catch (e) {}
    Bridge.send({ type: 'panel', cmd: 'close', panel: 'ragchat' });
  }

  function listen(node, event, fn) {
    node.addEventListener(event, fn);
    disposers.push(function () { node.removeEventListener(event, fn); });
  }

  function trustedUrl(raw) {
    if (typeof raw !== 'string' || raw === '') return '';
    try {
      var parsed = new URL(raw);
      return parsed.origin === TRUSTED_ORIGIN ? parsed.href : '';
    } catch (e) { return ''; }
  }

  function cleanup() {
    disposers.splice(0).forEach(function (f) { f(); });
    if (scale) scale.detach();
    scale = null; shell = null; statusEl = null;
    // 摘除 iframe → 销毁其浏览上下文，连带断开页面内 SSE / WebSocket
    if (root) root.textContent = '';
  }

  function createDOM() {
    root = document.createElement('div');
    root.className = 'ragchat-panel';
    return root;
  }

  function onOpen(element, data) {
    root = element;
    root.innerHTML =
      '<div class="panel-scale-shell ragchat-shell">' +
        '<header class="ragchat-header">' +
          '<span class="ragchat-title">通讯终端</span>' +
          '<button class="ragchat-close-btn" data-ragchat="close" type="button" title="关闭" aria-label="关闭">关闭</button>' +
        '</header>' +
        '<div class="ragchat-body">' +
          '<p class="ragchat-status" data-ragchat="status"></p>' +
        '</div>' +
      '</div>';
    shell = root.firstElementChild;
    scale = PanelScale.attach(shell, 1024, 576, { onUpdate: function (s) {
      shell.style.left = ((root.clientWidth - 1024 * s) / 2) + 'px';
      shell.style.top = ((root.clientHeight - 576 * s) / 2) + 'px';
    }});
    statusEl = root.querySelector('[data-ragchat="status"]');
    listen(root.querySelector('[data-ragchat="close"]'), 'click', closeTerminal);

    var url = trustedUrl(data && data.frontend_url);
    if (!url) {
      statusEl.textContent = '通讯终端页面地址不可用，请关闭后重试。';
      return;
    }
    statusEl.textContent = '正在载入通讯终端……';
    var frame = document.createElement('iframe');
    frame.className = 'ragchat-frame';
    frame.title = '通讯终端';
    frame.src = url;
    listen(frame, 'load', function () { statusEl.hidden = true; });
    root.querySelector('.ragchat-body').appendChild(frame);
  }
})();
