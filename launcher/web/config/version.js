// 版本号与 CHANNEL 标签的唯一生产位置.
// 重构期采用 e 常数思路 — 每次阶段性迭代多放一位小数, 越趋近 e=2.71828182845904...
// 表示越接近收敛稳定. 定稿发布时跳出 e 规则用 2.72 宣告稳定.
//
// 修改方法: 只改 APP_META 四个字段, 不用动 HTML / CSS.
// - version:          侧栏 .ver 大字号版本号文本
// - tail:             .ver-tail 的副标 (去掉前缀 "·" 分隔符, 脚本会自动加)
// - channel:          CHANNEL 行右侧值
// - channelClass:     CHANNEL 值的颜色类: "g" = DLS 青 (稳定) / "r" = rust 锈红 (不稳定) / "" = 默认白
//
// 本脚本在 bootstrap.html body 末尾加载, 此时 DOM 已就绪, 直接同步填充, 不走 DOMContentLoaded.

(function () {
  'use strict';

  window.APP_META = {
    version:       '2.718',
    tail:          'UNSTABLE',
    channel:       'DEV',
    channelClass:  'r'
  };

  var m = window.APP_META;

  var vEl = document.getElementById('version-number');
  if (vEl) vEl.textContent = m.version;

  var tEl = document.getElementById('version-tail');
  if (tEl) tEl.textContent = '· ' + m.tail;

  var cEl = document.getElementById('version-channel');
  if (cEl) {
    cEl.textContent = m.channel;
    // 清掉任何旧颜色类 (g/r), 再按当前 channelClass 加
    cEl.classList.remove('g');
    cEl.classList.remove('r');
    if (m.channelClass) cEl.classList.add(m.channelClass);
  }
})();
