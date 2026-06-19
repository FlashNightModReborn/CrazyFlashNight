// 动画测试面板（CUTSCENE · beta） —— issue #7 bug2 方案探索
// ------------------------------------------------------------------
// 目的：用 Ruffle 在 WebView 内播放 flashswf/movies/ 下的过场 SWF，验证
//   ① Ruffle 在本机（低压平板）对各过场资产的兼容性 / 保真度
//   ② 播放性能（卡顿与否 → 决定该资产直接 Ruffle 还是渲成 mp4）
// 定位：测试版。入口在游戏内刘海屏「其他」下拉菜单（与 选关测试 / 角斗场测试 同列）。
//
// 接入：notch「其他」按钮 data-key=CUTSCENE_TEST → LauncherCommandRouter 走 OpenPanel("cutscene-test")
//   → panels.js 调本 panel onOpen（与 stage-select / arena 等测试面板同口径）。
// 数据：cfn-assets.local/movies/*.swf（WebOverlayForm 已映射 cfn-assets.local → flashswf/）。
// Ruffle：cfn-assets.local/_ruffle/ruffle.js（约 29MB wasm，懒加载——仅首次播放时拉取）。
//   Ruffle 与 SWF 同源（均 cfn-assets.local），无跨域 fetch。
// 懒注册：panels-lazy-registry.js 里 registerLazy('cutscene-test', ['modules/cutscene-test.js'])。
(function () {
  'use strict';

  if (typeof Panels === 'undefined') return;

  var ASSETS = 'https://cfn-assets.local';
  var RUFFLE_SRC = ASSETS + '/_ruffle/ruffle.js';

  // flashswf/movies/ 全量快照（2026-06-20，31 项）。测试版手维护；新增过场需同步此表。
  var MOVIES = [
    'bigmovie1.swf', 'bigmovie2.swf', 'bigmovie3.swf', 'bigmovie4.swf',
    'FakeStageClear.swf',
    'movie_avp_1_3.swf', 'movie_avp_1_5.swf', 'movie_avp_1_7.swf', 'movie_avp_1_14.swf',
    'movie_gk_1_1.swf', 'movie_gk_8_2.swf', 'movie_gk_9_4.swf', 'movie_gk_11_4.swf',
    'movie_gk_15_5.swf', 'movie_gk_17_1.swf', 'movie_gk_21_4.swf', 'movie_gk_21_5.swf',
    'movie_gk_22_5.swf', 'movie_gk_24_1.swf',
    'movieone.swf',
    '前线基地过场动画.swf', '将军死亡_军阀前线基地.swf',
    '电子战过场.swf', '故障转场.swf', '黑色渐隐过场.swf',
    '堕落城深处尸体堆.swf', '尸母巢穴巨型尸母.swf',
    '异形卵巢_avp1_13.swf', '异形卵巢_avp1_14.swf',
    '月面暗道控制拉杆.swf', '月面暗门.swf'
  ];

  var _el = null;
  var _stageEl = null, _statusEl = null;
  var _player = null;        // 当前 Ruffle player 元素
  var _rufflePromise = null; // ruffle.js 加载 promise（懒加载，仅一次）

  Panels.register('cutscene-test', {
    create: createDOM,
    onOpen: onOpen,
    // ESC / backdrop / × 三入口共用：先 Panels.close() 复位 _active，再通知 C# 走 resume 序列
    onRequestClose: closeLocally,
    onClose: cleanup,
    onForceClose: cleanup
  });

  function closeLocally() {
    try { Panels.close(); } catch (e) {}
    if (typeof Bridge !== 'undefined') Bridge.send({ type: 'panel', cmd: 'close', panel: 'cutscene-test' });
  }

  function loadRuffle() {
    if (window.RufflePlayer && window.RufflePlayer.newest) return Promise.resolve();
    if (_rufflePromise) return _rufflePromise;
    _rufflePromise = new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = RUFFLE_SRC;
      s.onload = function () { resolve(); };
      s.onerror = function () {
        _rufflePromise = null; // 允许重试
        reject(new Error('Ruffle 运行时加载失败：' + RUFFLE_SRC));
      };
      document.head.appendChild(s);
    });
    return _rufflePromise;
  }

  function destroyPlayer() {
    if (_player && typeof _player.remove === 'function') {
      try { _player.remove(); } catch (e) {}
    }
    _player = null;
  }

  function setActive(listEl, btn) {
    var all = listEl.getElementsByTagName('button');
    for (var i = 0; i < all.length; i++) all[i].style.background = '#1c1c20';
    if (btn) btn.style.background = '#33333a';
  }

  function play(file) {
    destroyPlayer();
    var t0 = (window.performance && performance.now) ? performance.now() : 0;
    _statusEl.textContent = '加载 Ruffle 运行时…（首次约 29MB wasm，请稍候）';
    loadRuffle().then(function () {
      var ruffle = window.RufflePlayer.newest();
      _player = ruffle.createPlayer();
      _player.style.width = '100%';
      _player.style.height = '100%';
      _stageEl.innerHTML = '';
      _stageEl.appendChild(_player);
      var dt = t0 ? Math.round(performance.now() - t0) : 0;
      _statusEl.textContent = '▶ ' + file + (dt ? '（运行时就绪 ' + dt + 'ms）' : '');
      var r = _player.load({
        url: ASSETS + '/movies/' + encodeURIComponent(file),
        autoplay: 'on',
        contextMenu: 'off'
      });
      if (r && typeof r.catch === 'function') {
        r.catch(function (e) {
          _statusEl.textContent = '✗ 播放失败：' + file + ' — ' + (e && e.message ? e.message : e);
        });
      }
    }).catch(function (e) {
      _statusEl.textContent = '✗ ' + (e && e.message ? e.message : String(e));
    });
  }

  function createDOM() {
    _el = document.createElement('div');
    _el.id = 'cutscene-test-panel';
    _el.style.cssText = 'position:absolute;inset:0;display:flex;flex-direction:column;' +
      'background:#161618;color:#cfcfd4;font-family:Consolas,monospace;overflow:hidden';
    _el.innerHTML =
      '<div style="display:flex;align-items:center;justify-content:space-between;padding:8px 12px;' +
        'border-bottom:1px solid #2a2a30;background:#1c1c20">' +
        '<span style="font-size:14px">动画测试 · CUTSCENE <span style="color:#c8902a;font-size:12px">beta</span></span>' +
        '<button id="ct-close" style="background:none;border:none;color:#9a9aa0;font-size:20px;cursor:pointer;line-height:1">×</button>' +
      '</div>' +
      '<div style="flex:1;min-height:0;display:flex;gap:10px;padding:10px;box-sizing:border-box">' +
        '<div id="ct-list" style="width:230px;flex:0 0 230px;overflow:auto;border:1px solid #2a2a30;border-radius:6px;padding:4px;background:#131315"></div>' +
        '<div style="flex:1;min-width:0;display:flex;flex-direction:column;gap:6px">' +
          '<div id="ct-stage" style="flex:1;background:#000;border:1px solid #2a2a30;border-radius:6px;overflow:hidden;display:flex;align-items:center;justify-content:center;color:#666;font-size:13px">← 选择左侧过场，用 Ruffle 播放</div>' +
          '<div id="ct-status" style="font-size:12px;line-height:1.6;color:#9a9aa0;min-height:20px"></div>' +
          '<div style="font-size:11px;line-height:1.5;color:#6a6a70">测试版 · 数据 flashswf/movies/ · 验证 Ruffle 兼容性与性能。卡顿/画面异常的资产 → 标为「转 mp4」候选。后续 mp4/WebM 路径在此面板接 &lt;video&gt;。</div>' +
        '</div>' +
      '</div>';

    var listEl = _el.querySelector('#ct-list');
    _stageEl = _el.querySelector('#ct-stage');
    _statusEl = _el.querySelector('#ct-status');

    for (var i = 0; i < MOVIES.length; i++) {
      (function (file) {
        var b = document.createElement('button');
        b.textContent = file.replace(/\.swf$/i, '');
        b.title = file;
        b.style.cssText = 'display:block;width:100%;text-align:left;margin:2px 0;padding:5px 7px;' +
          'font:12px Consolas,monospace;background:#1c1c20;color:#cfcfd4;border:1px solid #2a2a30;' +
          'border-radius:4px;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap';
        b.onclick = function () { setActive(listEl, b); play(file); };
        listEl.appendChild(b);
      })(MOVIES[i]);
    }

    _el.querySelector('#ct-close').onclick = closeLocally;
    return _el;
  }

  function onOpen() {
    // 列表静态，无需重建；播放区保持上次状态由 cleanup 复位。
  }

  function cleanup() {
    destroyPlayer();
    if (_stageEl) _stageEl.innerHTML = '← 选择左侧过场，用 Ruffle 播放';
    if (_statusEl) _statusEl.textContent = '';
  }
})();
