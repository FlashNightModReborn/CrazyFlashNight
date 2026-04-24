// Phase 2a: 诊断日志模块
// mount/unmount 契约，经 BootstrapApp.registerModule 注册

(function() {
  'use strict';

  var _container = null;
  var _unsubs = [];
  var _autoTimer = null;
  var _lines = 200;

  function mount(containerEl, initData) {
    _container = containerEl;
    _autoTimer = null;

    _container.innerHTML =
      '<div class="modal-header">' +
        '<h2>诊断日志</h2>' +
        '<button class="modal-close" id="diag-close">×</button>' +
      '</div>' +
      '<div class="diag-log-toolbar">' +
        '<button id="diag-refresh">刷新</button>' +
        '<label><input type="checkbox" id="diag-auto"> 自动刷新 (5s)</label>' +
        '<label>行数: <select id="diag-lines">' +
          '<option value="100">100</option>' +
          '<option value="200" selected>200</option>' +
          '<option value="500">500</option>' +
          '<option value="2000">2000</option>' +
        '</select></label>' +
        '<span id="diag-total" style="color:#666;font-size:11px;margin-left:auto"></span>' +
      '</div>' +
      '<pre class="diag-log-pre" id="diag-pre">加载中...</pre>';

    document.getElementById('diag-close').onclick = function() { window.BootstrapApp.tryCloseModal(); };
    document.getElementById('diag-refresh').onclick = function() { fetchLogs(); };
    document.getElementById('diag-auto').onchange = function() {
      if (this.checked) {
        startAutoRefresh();
      } else {
        stopAutoRefresh();
      }
    };
    document.getElementById('diag-lines').onchange = function() {
      _lines = parseInt(this.value, 10) || 200;
      fetchLogs();
    };

    // 监听 logs_resp
    _unsubs.push(window.BootstrapApp.onMessage('logs_resp', onLogsResp));

    fetchLogs();
  }

  function unmount() {
    stopAutoRefresh();
    for (var i = 0; i < _unsubs.length; i++) _unsubs[i]();
    _unsubs = [];
    _container = null;
  }

  function fetchLogs() {
    window.BootstrapApp.send({ cmd: 'logs', lines: _lines });
  }

  function onLogsResp(msg) {
    var pre = document.getElementById('diag-pre');
    var totalSpan = document.getElementById('diag-total');
    if (!pre) return;

    var lines = msg.lines || [];
    var total = msg.total || 0;

    totalSpan.textContent = '显示 ' + lines.length + ' / ' + total + ' 行';

    // 简单语法高亮
    var html = '';
    for (var i = 0; i < lines.length; i++) {
      html += highlightLine(lines[i]) + '\n';
    }
    pre.innerHTML = html;
    pre.scrollTop = pre.scrollHeight;
  }

  function highlightLine(line) {
    var escaped = escHtml(line);
    // 高亮 [Tag] 部分
    escaped = escaped.replace(/\[([A-Za-z_]+)\]/g, function(m, tag) {
      if (/error|fail|exception/i.test(tag)) return '<span class="log-err">' + m + '</span>';
      if (/warn/i.test(tag)) return '<span class="log-warn">' + m + '</span>';
      return '<span class="log-tag">' + m + '</span>';
    });
    return escaped;
  }

  function startAutoRefresh() {
    stopAutoRefresh();
    _autoTimer = setInterval(function() { fetchLogs(); }, 5000);
  }

  function stopAutoRefresh() {
    if (_autoTimer) { clearInterval(_autoTimer); _autoTimer = null; }
  }

  function escHtml(s) {
    if (s == null) return '';
    return String(s).replace(/[&<>"']/g, function(c) {
      return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c];
    });
  }

  window.BootstrapApp.registerModule('diagnostic-log', {
    mount: mount,
    unmount: unmount
  });
})();
