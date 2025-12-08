import org.flashNight.aven.Proxy.Proxy;

// ============================
// 可选日志开关与工具
// ============================
_root.UI系统 = _root.UI系统 || {};
// _root.UI系统.__LOG_ON = true;
_root.UI系统.__LOG_ON = _root.UI系统.__LOG_ON == true; // 默认关闭日志
_root.UI系统.__log = function(tag:String, msg:String):Void {
  if (_root.UI系统.__LOG_ON) {
    _root.服务器.发布服务器消息("[UI经济] " + tag + " | " + msg);
  }
};

// ============================
// 初始化 UI 系统参数
// ============================
_root.UI系统.经济面板动效 = true;   // 是否启用经济面板动画效果
_root.UI系统.经济面板帧间隔 = 60;   // 动画总帧数
_root.UI系统.经济面板动效占比 = 0.2; // 渐显/渐隐帧比例

// ============================
// 刷新入口：接收 newValue/oldValue，并把 newValue 透传
// ============================
_root.UI系统.金钱刷新 = function(newValue:Number, oldValue:Number):Void {
  _root.UI系统.经济面板刷新(_root.金币图标, "金钱", newValue);
};
_root.UI系统.虚拟币刷新 = function(newValue:Number, oldValue:Number):Void {
  _root.UI系统.经济面板刷新(_root.K点图标, "虚拟币", newValue);
};

// ============================
//
// 变量监视器（使用 watch）
// - 注意：watch 回调在赋值“之前”触发，因此必须把 newValue 透传
//
// ============================
_root.UI系统.设置变量监视 = function(变量名:String, 刷新函数:Function):Void {
  _root.watch(变量名, function(prop:String, oldValue, newValue) {
    _root.UI系统.__log("watch", 变量名 + " old=" + oldValue + " new=" + newValue + " rootBeforeAssign=" + _root[变量名]);

    // NaN 防护（防止出现意外的污染）
    if (typeof(oldValue) == "number" && typeof(newValue) == "number") {
      if (!isNaN(oldValue) && isNaN(newValue)) {
        newValue = oldValue;
      }
    }

    // 仅在发生变化时刷新
    if (oldValue != undefined && oldValue != newValue) {
      刷新函数(newValue, oldValue); // 关键：把新旧值传给刷新入口
    }

    return newValue; // 交还给运行时，完成最终赋值
  });
};

// 启用监视
_root.UI系统.设置变量监视("金钱", _root.UI系统.金钱刷新);
_root.UI系统.设置变量监视("虚拟币", _root.UI系统.虚拟币刷新);

// ============================
// 面板初始化
// ============================
_root.UI系统.初始化面板 = function(面板:MovieClip, 变量:String, 货币:Number):Void {
  面板.上次记录 = 0;
  面板.上次动画值 = 0;
  面板.显示值   = 0;
  面板.变动值   = "";
  面板.目标值   = 货币;

  面板.帧间隔 = _root.UI系统.经济面板帧间隔;
  面板.动效帧 = Math.round(_root.UI系统.经济面板帧间隔 * _root.UI系统.经济面板动效占比);
  面板.结束帧 = 面板.帧间隔 - 面板.动效帧;

  面板.动画帧计数器 = 0;
  if (面板.变动框) 面板.变动框._alpha = 0;

  面板.动画活跃 = true;
  面板.已初始化 = true;
  面板.__变量 = 变量; // 仅用于日志标识

  _root.UI系统.__log("init", 变量 + " 初始货币=" + 货币);

  // 帧推进
  面板.onEnterFrame = function() {
    _root.UI系统.处理动画(this);
  };
};

// ============================
// 动画处理（帧推进）
// ============================
_root.UI系统.处理动画 = function(面板:MovieClip, _忽略:Number):Void {
  面板.动画帧计数器++;

  var 变动框透明度:Number = 100;
  if (面板.动画帧计数器 <= 面板.动效帧) {
    变动框透明度 = (面板.动画帧计数器 / 面板.动效帧) * 100;
  } else if (面板.动画帧计数器 >= 面板.结束帧) {
    变动框透明度 = ((面板.帧间隔 - 面板.动画帧计数器) / 面板.动效帧) * 100;
  }
  变动框透明度 = Math.max(0, Math.min(100, 变动框透明度));
  if (面板.变动框) 面板.变动框._alpha = 变动框透明度;

  if (面板.动画帧计数器 == 1) {
    _root.UI系统.__log("anim-begin", 面板.__变量 + " from=" + 面板.上次记录 + " to=" + 面板.目标值 + " 改变量=" + (面板.目标值 - 面板.上次记录));
  }

  if (面板.动画帧计数器 < 面板.帧间隔) {
    var 改变量:Number = 面板.目标值 - 面板.上次记录;
    var 当前显示值:Number = 面板.上次记录 + (改变量 * (面板.动画帧计数器 / 面板.帧间隔));
    面板.显示值 = Math.round(当前显示值);
  } else {
    面板.显示值 = 面板.目标值;
    面板.变动值 = "";
    面板.动画活跃 = false;
    _root.UI系统.__log("anim-end", 面板.__变量 + " 显示值=" + 面板.显示值);
    delete 面板.onEnterFrame;
  }
};

// ============================
// 经济面板刷新（支持可选覆盖值 currencyOverride）
// ============================
_root.UI系统.经济面板刷新 = function(面板:MovieClip, 变量:String, currencyOverride:Number):Boolean {
  // 面板可能为空：外部监听可据此卸载
  if (!面板) return true;

  var 货币:Number = (currencyOverride != undefined) ? Number(currencyOverride) : Number(_root[变量]);

  // 初始化
  if (!面板.已初始化) {
    _root.UI系统.初始化面板(面板, 变量, 货币);
    return false;
  }

  _root.UI系统.__log("refresh",
    变量 + " override=" + currencyOverride + " readNow=" + _root[变量] +
    " 显示=" + 面板.显示值 + " 目标=" + 面板.目标值 + " 活跃=" + 面板.动画活跃);

  // 播放动画的条件
  if (面板.显示值 != 货币 && _root.UI系统.经济面板动效 && 货币 >= 0) {
    // 重置为新一轮动画
    面板.动画帧计数器 = 0;
    面板.上次记录 = Number(面板.显示值) || 0;

    // 统一的变动值与“上次动画值”语义（稳定显示 +N/-N）
    面板.变动值 = 货币 - 面板.上次记录;
    if (面板.变动值 > 0) 面板.变动值 = "+" + 面板.变动值;
    面板.上次动画值 = 面板.上次记录;

    面板.目标值 = 货币;
    面板.动画活跃 = true;

    // 启动帧推进
    面板.onEnterFrame = function() {
      _root.UI系统.处理动画(this);
    };

    _root.UI系统.__log("start-anim",
      变量 + " from=" + 面板.上次记录 + " to=" + 货币 + " 变动=" + (货币 - 面板.上次记录));
  } else {
    // 不播动画时的直接赋值
    面板.显示值 = 货币;
  }

  return false;
};

// ============================
// 初始刷新（场景切换后触发一遍）
// ============================
_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
  _root.UI系统.金钱刷新(_root["金钱"], undefined);   // 无 override 时同样可工作
  _root.UI系统.虚拟币刷新(_root["虚拟币"], undefined);

  // 防御性兜底：确保等级经验值阈值已设置，并刷新UI
  _root.UI系统.防御性刷新等级经验();
}, null);
