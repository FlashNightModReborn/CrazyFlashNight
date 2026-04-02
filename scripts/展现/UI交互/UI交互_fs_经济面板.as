// ============================
// 经济面板 — WebView2 UI 数据推送
//
// Flash 端 MovieClip 已移除，动画由 JS currency.js 处理。
// 此文件仅负责：watch 变量 → pushUiState → 帧数据管线 → WebView2
// ============================

_root.UI系统 = _root.UI系统 || {};

// watch 回调 → pushUiState（NaN 防护）
_root.UI系统.金钱刷新 = function(newValue:Number, oldValue:Number):Void {
  var v:Number = Number(newValue);
  if (!isNaN(v)) org.flashNight.arki.render.FrameBroadcaster.pushUiState("g:" + Math.round(v));
};
_root.UI系统.虚拟币刷新 = function(newValue:Number, oldValue:Number):Void {
  var v:Number = Number(newValue);
  if (!isNaN(v)) org.flashNight.arki.render.FrameBroadcaster.pushUiState("k:" + Math.round(v));
};

// 变量监视器
_root.UI系统.设置变量监视 = function(变量名:String, 刷新函数:Function):Void {
  _root.watch(变量名, function(prop:String, oldValue, newValue) {
    if (typeof(oldValue) == "number" && typeof(newValue) == "number") {
      if (!isNaN(oldValue) && isNaN(newValue)) {
        newValue = oldValue;
      }
    }
    if (oldValue != undefined && oldValue != newValue) {
      刷新函数(newValue, oldValue);
    }
    return newValue;
  });
};

// 启用监视
_root.UI系统.设置变量监视("金钱", _root.UI系统.金钱刷新);
_root.UI系统.设置变量监视("虚拟币", _root.UI系统.虚拟币刷新);

// SceneChanged: 推送经济初始快照 + 刷新等级经验
_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
  _root.UI系统.金钱刷新(_root["金钱"], undefined);
  _root.UI系统.虚拟币刷新(_root["虚拟币"], undefined);
  _root.UI系统.防御性刷新等级经验();
}, null);
