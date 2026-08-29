// 版本号与 CHANNEL 标签的唯一生产位置.
// 主线尚未进入下一阶段，因此产品版本继续保持 2.x；历史小版本并没有连续的语义规则。
// 当前 E 阶段用 e=2.71828182845904... 的展开作为 AS2 权威迁移期间的发包标识：
// 只有形成面向玩家的稳定发包节点时才追加一位，普通开发提交沿用阶段号并由 CHANNEL 区分。
// 待 AS2 权威彻底转移后再冻结最终 2.x 标识，具体末位以届时发布记录为准。
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
