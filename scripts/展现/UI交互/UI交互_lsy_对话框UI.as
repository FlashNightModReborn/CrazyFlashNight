
// ===============================
//  对话框 UI 根对象
// ===============================
_root.对话框UI = new Object();

// ===============================
//  滤镜系统（注册表 + 统一入口）
//  —— 默认不加滤镜；当 style="holo" 时启用全息滤镜
// ===============================
_root.对话框UI.默认滤镜 = "none";   // "none" / "holo"
_root.对话框UI.默认滤镜参数 = {
  opacity: 60,       // 整体透明度（0~100）
  linesStep: 3,      // 扫描线间距（像素）
  linesAlpha: 35,    // 扫描线强度
  jitter: false,     // 是否轻微闪烁/刷新感
  glowColor: 0x8BD3FF,
  glowBlur: 8,
  glowStrength: 1.8,
  blueBoost: 120     // 蓝色通道提升
};
_root.对话框UI.当前滤镜风格 = null;   // 本轮/全局覆盖
_root.对话框UI.当前滤镜参数 = null;

// ——内部工具：只建一次扫描线贴图
_root.对话框UI.__ensureHoloInfra = function():Void {
  if (_global.__HOLO_STRIPE__ == undefined) {
    var bd:BitmapData = new BitmapData(2, 2, true, 0x00000000);
    bd.setPixel32(0, 0, 0x77FFFFFF); // 顶部1px半透明线
    bd.setPixel32(1, 0, 0x77FFFFFF);
    _global.__HOLO_STRIPE__ = bd;
  }
};

// ——内部工具：移除目标上所有“本系统”加的效果
_root.对话框UI.__removeAllFilters = function(target:MovieClip):Void {
  if (!target) return;

  // 清除滤镜
  target.filters = [];

  // 清除覆盖的扫描线层
  var lname:String = target._name + "__holoLines";
  var overlay:MovieClip = target._parent ? target._parent[lname] : null;
  if (overlay) {
    delete overlay.onEnterFrame;
    overlay.removeMovieClip();
  }

  // 还原透明度
  target._alpha = 100;
};

// ——内部：应用全息滤镜（封装自你的 demo）
_root.对话框UI.__applyHolo = function(target:MovieClip, opts:Object):Void {
  this.__ensureHoloInfra();

  // 合并参数
  var o:Object = {};
  var d:Object = this.默认滤镜参数;
  for (var k in d) o[k] = d[k];
  if (opts) for (var k2 in opts) o[k2] = opts[k2];

  // 颜色矩阵（向蓝色单色化偏移）
  var r:Number=0.2126, g:Number=0.7152, b:Number=0.0722;
  var cm:Array = [
    r,g,b,0,   0,
    r,g,b,0,   30,
    r,g,b,0,   o.blueBoost,
    0,0,0,1,   0
  ];
  var cmf:ColorMatrixFilter = new ColorMatrixFilter(cm);
  var glow:GlowFilter = new GlowFilter(o.glowColor, 1, o.glowBlur, o.glowBlur, o.glowStrength, 2, false, false);
  target.filters = [cmf, glow];

  // 覆盖层（扫描线）
  var lname:String = target._name + "__holoLines";
  var lines:MovieClip = target._parent[lname];
  if (!lines) lines = target._parent.createEmptyMovieClip(lname, target.getDepth()+1);

  lines.clear();
  lines._x = target._x; lines._y = target._y;
  lines._xscale = target._xscale; lines._yscale = target._yscale;

  var w:Number = target._width, h:Number = target._height;
  var mtx:Matrix = new Matrix();
  mtx.a = 1;
  mtx.d = o.linesStep / 2; // 源纹理高 2px → d=step/2 控制间距

  lines.beginBitmapFill(_global.__HOLO_STRIPE__, mtx, true, true);
  lines.moveTo(0,0); lines.lineTo(w,0); lines.lineTo(w,h); lines.lineTo(0,h); lines.lineTo(0,0);
  lines.endFill();
  lines.blendMode = "screen";
  lines._alpha = Math.min(o.linesAlpha, o.opacity);
  lines.cacheAsBitmap = true;

  // 主体透明度
  target._alpha = o.opacity;

  // 微闪烁（可关）
  if (o.jitter) {
    var t:Number = 0;
    lines.onEnterFrame = function() {
      this._y = target._y + (t & 1); // 上下 1px
      this._alpha = Math.min(o.linesAlpha, o.opacity) - 2 + Math.random()*4;
      t++;
    };
  } else {
    delete lines.onEnterFrame;
  }
};

// ——对外统一入口
_root.对话框UI.应用头像滤镜 = function(target:MovieClip, style:String, opts:Object):Void {
  if (!target) return;

  // 先移除旧效果（风格切换/重复调用都安全）
  this.__removeAllFilters(target);

  var finalStyle:String = (style != null) ? style :
                          (this.当前滤镜风格 != null ? this.当前滤镜风格 : this.默认滤镜);
  var finalOpts:Object  = (opts != null) ? opts :
                          (this.当前滤镜参数 != null ? this.当前滤镜参数 : this.默认滤镜参数);

  switch(finalStyle){
    case "none":
      // 不做事（已清除）
      break;
    case "holo":
      this.__applyHolo(target, finalOpts);
      break;
    default:
      // 未知风格视为 none
      break;
  }
};

// ——简便 API：全局设置或临时切换
_root.对话框UI.setPortraitStyle = function(style:String, opts:Object):Void {
  this.当前滤镜风格 = style;
  this.当前滤镜参数 = opts;
};

// ===============================
//  初始化对话框界面（headless compat）
//  authored 实例（含 AVM1 同路径重绑回来的新实例）只停住隐藏；
//  _root.对话框界面 换绑到 NativeDialogueService 的普通 Object facade。
//  旧 MC renderer 与外部立绘缓存已退役；NPC 头像源函数另随旧平板入口收尾。
// ===============================
_root.对话框UI.初始化对话框界面 = function(对话框界面:MovieClip){
    对话框界面.stop();
    对话框界面._visible = false;
    对话框界面.刷新内容 = function(){};
    对话框界面.打字 = function(){};
    对话框界面.结束打字 = function(){};
    对话框界面.下一句 = function(){};
    // 只做 MC 本地收尾（stop+hide），不回调服务，避免与 cancelActive 的
    // MC 分支互调形成递归；会话级取消由 facade.关闭 / 场景清理负责。
    对话框界面.关闭 = function(){
        this.stop();
        this._visible = false;
    };
    对话框界面.onClose = function(){};

    var svc = _global.org.flashNight.arki.dialogue.NativeDialogueService;
    if (svc != undefined) {
        svc.install();
        svc.ensureCompat();
    }
};

// ===============================
//  NPC 头像刷新（新增：加载完成后应用滤镜；修正 unloadMovie 拼写）
// ===============================
_root.对话框UI.刷新NPC头像 = function(NPC头像框:MovieClip, 名字){
    if(名字 != null){
        NPC头像框.gotoAndStop(2);
        var holder:MovieClip = NPC头像框.头像;
        holder.loadMovie("flashswf/portraits/profiles/" + 名字 + ".png");

        // 等待图片加载完成后应用滤镜
        holder.onEnterFrame = function(){
            var bt:Number = this.getBytesTotal();
            var bl:Number = this.getBytesLoaded();
            if(bt>0 && bl>=bt){
                delete this.onEnterFrame;

                var styleStr:String = (_root.对话框UI.滤镜风格 != undefined) ? _root.对话框UI.滤镜风格 : _root.对话框UI.当前滤镜风格;
                var styleOpt:Object = (_root.对话框UI.滤镜参数 != undefined) ? _root.对话框UI.滤镜参数 : _root.对话框UI.当前滤镜参数;
                _root.对话框UI.应用头像滤镜(this, styleStr, styleOpt);
            }
        };
    }else{
        NPC头像框.gotoAndStop(1);
        if (NPC头像框.头像) {
            _root.对话框UI.__removeAllFilters(NPC头像框.头像); // 新增：清滤镜
            NPC头像框.头像.unloadMovie(); // 修正拼写
        }
    }
};

// ===============================
//  初始化人物立绘（保持原逻辑）
// ===============================
_root.初始化人物立绘 = function(target){
    target.stop();
    target.gotoAndStop(target._parent._parent.人物表情);
};

// ===============================
//  用法提示：
//  1) 通过对话条控制：
//     dialogueInfo[7] = "holo"; dialogueInfo[8] = { opacity:70, jitter:true };
//  2) 代码全局切换：
//     _root.对话框UI.setPortraitStyle("holo", {opacity:70, jitter:true});
//     // 关闭：_root.对话框UI.setPortraitStyle("none");
// ===============================
