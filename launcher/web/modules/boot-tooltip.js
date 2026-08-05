// BootTooltip — 启动引导页 tooltip 层 (C 期交互语言).
// 经典 script IIFE, 挂 window.BootTooltip; 样式在 welcome.css 的 .boot-tooltip 块.
//
// API:
//   BootTooltip.bind(el, textOrFn)            单元素绑定 (hover 300ms 后出现, 元素锚定, 160ms 淡入)
//   BootTooltip.bindDelegate(container, map)  事件委托: container 后代 button 按 class → 文案映射匹配
//   BootTooltip.unbind(el)                    解绑单元素
//   BootTooltip.hide()                        立即隐藏
//   BootTooltip.isVisible()                   当前是否显示中 (bootstrap-main.js ESC 分层消费用)
//
// 锚定策略: 元素下方居中优先, 下方空间不足翻上方, 水平 clamp 在视口内.
// textOrFn 支持函数 → 显示时动态求值 (如按 disabled 状态给文案).
(function () {
  'use strict';

  var DELAY = 300;    // hover 延迟 (ms)
  var OFFSET = 8;     // 锚定间距 (px)

  var layer = null;
  var _currentEl = null;
  var _timer = 0;
  var _bound = [];

  function ensureLayer() {
    if (layer) return layer;
    layer = document.createElement('div');
    layer.className = 'boot-tooltip';
    layer.setAttribute('role', 'tooltip');
    document.body.appendChild(layer);
    return layer;
  }

  function resolveText(textOrFn, el) {
    try {
      var t = (typeof textOrFn === 'function') ? textOrFn(el) : textOrFn;
      return (t == null) ? '' : String(t);
    } catch (e) { return ''; }
  }

  function show(el, textOrFn) {
    var text = resolveText(textOrFn, el);
    if (!text || !el.isConnected) return;
    ensureLayer();
    layer.textContent = text;
    // .on 只切 visibility/opacity, 布局一直在, 量尺寸不受显隐影响
    layer.classList.add('on');
    var r = el.getBoundingClientRect();
    var tw = layer.offsetWidth, th = layer.offsetHeight;
    var x = r.left + r.width / 2 - tw / 2;
    var y = r.bottom + OFFSET;
    if (y + th > window.innerHeight - 4) y = r.top - th - OFFSET;   // 下方放不下翻上方
    if (y < 4) y = 4;
    if (x < 4) x = 4;
    if (x + tw > window.innerWidth - 4) x = window.innerWidth - tw - 4;
    layer.style.left = x + 'px';
    layer.style.top = y + 'px';
  }

  function hide() {
    if (_timer) { clearTimeout(_timer); _timer = 0; }
    _currentEl = null;
    if (layer) layer.classList.remove('on');
  }

  function scheduleShow(el, textOrFn) {
    if (_timer) clearTimeout(_timer);
    _currentEl = el;
    _timer = setTimeout(function () {
      _timer = 0;
      if (_currentEl === el) show(el, textOrFn);
    }, DELAY);
  }

  function bind(el, textOrFn) {
    if (!el) return;
    var entry = { el: el };
    entry.onEnter = function () { scheduleShow(el, textOrFn); };
    entry.onLeave = function () { if (_currentEl === el) hide(); };
    el.addEventListener('mouseenter', entry.onEnter);
    el.addEventListener('mouseleave', entry.onLeave);
    el.addEventListener('mousedown', entry.onLeave);   // 点击即收, 避免残留
    _bound.push(entry);
  }

  function unbind(el) {
    for (var i = _bound.length - 1; i >= 0; i--) {
      var b = _bound[i];
      if (b.el !== el) continue;
      el.removeEventListener('mouseenter', b.onEnter);
      el.removeEventListener('mouseleave', b.onLeave);
      el.removeEventListener('mousedown', b.onLeave);
      _bound.splice(i, 1);
    }
    if (_currentEl === el) hide();
  }

  // 事件委托: 动态渲染的卡片操作按钮, renderCard 重绘不丢绑定
  function bindDelegate(container, classTextMap) {
    if (!container || !classTextMap) return;
    var delegateEl = null;
    container.addEventListener('mouseover', function (e) {
      var btn = (e.target && e.target.closest) ? e.target.closest('button') : null;
      if (!btn || !container.contains(btn) || btn === delegateEl) return;
      var text = null;
      for (var cls in classTextMap) {
        if (classTextMap.hasOwnProperty(cls) && btn.classList.contains(cls)) { text = classTextMap[cls]; break; }
      }
      if (text == null) return;
      delegateEl = btn;
      scheduleShow(btn, text);
    });
    container.addEventListener('mouseout', function (e) {
      if (!delegateEl) return;
      if (e.relatedTarget && delegateEl.contains(e.relatedTarget)) return;
      delegateEl = null;
      hide();
    });
    container.addEventListener('mousedown', function () { delegateEl = null; hide(); });
  }

  // 滚动 / 缩放让锚定位失效, 直接收 (capture 阶段捕获卡片网格内部滚动)
  document.addEventListener('scroll', hide, true);
  window.addEventListener('resize', hide);

  window.BootTooltip = {
    bind: bind,
    bindDelegate: bindDelegate,
    unbind: unbind,
    hide: hide,
    isVisible: function () { return !!(layer && layer.classList.contains('on')); }
  };
})();
