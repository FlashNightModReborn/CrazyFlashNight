import flash.filters.*;
import flash.geom.Matrix;
import flash.display.BitmapData;

// ===============================
//  对话框 UI 根对象
// ===============================
_root.对话框UI = new Object();

_root.对话框UI.loadPortraitDict = new Object();
_root.对话框UI.loadPortraitList = new Array();

// （可选）兜底错误处理
function onError():Void { /* TODO: 这里写你的错误上报或日志 */ }

// 使用 BaseXMLLoader 导入 list
var portraitLoader = new org.flashNight.gesh.xml.LoadXml.BaseXMLLoader("flashswf/portraits/list.xml");
portraitLoader.load(function(data:Object):Void {
    var portraits = data.portrait;
    for (var i=0; i<portraits.length; i++) {
        _root.对话框UI.loadPortraitDict[data.portrait[i]] = {instance:null, depth:i};
    }
}, function():Void {
    onError();
});

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
//  外部立绘缓存清理（增强：先清滤镜再移除）
// ===============================
_root.对话框UI.清理外部立绘缓存 = function(保留数量){
    if(isNaN(保留数量)) 保留数量 = 3;
    if(保留数量 < 0) 保留数量 = 0;
    if(this.loadPortraitList.length > 保留数量){
        var cutlen = this.loadPortraitList.length - 保留数量;
        for(var i = cutlen - 1; i > -1; i--){
            var portraitInfo = this.loadPortraitDict[this.loadPortraitList[i]];
            if (portraitInfo.instance) {
                _root.对话框UI.__removeAllFilters(portraitInfo.instance); // 新增：先清滤镜
                portraitInfo.instance.removeMovieClip();
                portraitInfo.instance = null;
            }
        }
        this.loadPortraitList.splice(0, cutlen);
        // _root.发布消息("清理",cutlen,"个外部立绘缓存");
    }
};

// ===============================
//  立绘帧名大小写映射（保持原有行为）
// ===============================
_root.对话框UI.立绘大小写字典 = {
    Boy: "boy",
    King: "king",
    Pig: "pig"
};

// ===============================
//  刷新内容（增强：支持 [7]=滤镜风格, [8]=滤镜参数）
// ===============================
_root.对话框UI.刷新内容 = function(){
    var dialogueInfo = 本轮对话内容[对话进度];
    if (dialogueInfo[3] != undefined){
        this._visible = true;
        var 上句人物名字 = 人物名字;
        if (dialogueInfo[0] == "角色名" || dialogueInfo[0] == _root.角色名){
            人物名字 = _root.角色名;
        }else{
            人物名字 = dialogueInfo[0];
        }
        人物称号 = _root.获得翻译(dialogueInfo[1]);
        if (人物称号 == null){
            人物称号 = "";
        }
        this.头像图标帧名 = dialogueInfo[2];
        if (this.头像图标帧名 == null || this.头像图标帧名 == ""){
            this.头像图标帧名 = "无头像";
        }else if(_root.对话框UI.立绘大小写字典[this.头像图标帧名]){
            this.头像图标帧名 = _root.对话框UI.立绘大小写字典[this.头像图标帧名]; // 解决大小写不一致问题
        }
        if (this.头像图标帧名 == "主角模板" && 上句人物名字 != 人物名字){
            肖像.肖像.gotoAndStop("刷新");
        }

        对话内容 = dialogueInfo[3];
        人物表情 = dialogueInfo[4];
        if (人物表情 == null) 人物表情 = "普通";
        if(dialogueInfo[0] == "Andy Law" && _root.立绘类型 && _root.立绘类型 != 1){
            人物表情 = 人物表情 + _root.立绘类型.toString();
        }
        对话对象 = dialogueInfo[5];

        // ——新增：滤镜风格选择（可缺省）
        this.滤镜风格 = dialogueInfo[7]; // "none" / "holo" / 未定义沿用全局
        this.滤镜参数 = dialogueInfo[8]; // 参数对象，可缺省

        // 直接加载立绘 / 从外部文件导入立绘
        if(_root.对话框UI.loadPortraitDict[this.头像图标帧名] != null){
            刷新外部导入立绘();
        }else {
            刷新立绘();
        }

        // 加载对话图片
        对话图片 = dialogueInfo[6];
        if (typeof 对话图片 == "string" && 对话图片 != ""){
            if (对话图片 == "close"){
                _root.图片容器.卸载图片();
            }else{
                _root.图片容器.加载图片(对话图片);
            }
        }

        // 打字机
        打字内容 = "";
        this.onEnterFrame = function(){
            打字(对话内容);
        };
    }else{
        关闭();
    }
};

// ===============================
//  内置立绘刷新（末尾挂滤镜）
// ===============================
_root.对话框UI.刷新立绘 = function(){
    if(this.当前立绘 !== 肖像 && this.当前立绘) this.当前立绘._visible = false;
    this.肖像._visible = true;
    this.当前立绘 = 肖像;

    肖像.gotoAndStop(头像图标帧名);
    肖像.肖像.stop();
    肖像.肖像.gotoAndStop(人物表情);
    肖像.肖像.man.头.头.基本款.gotoAndStop(人物表情);
    肖像.肖像.man.头.头.装扮.gotoAndStop(人物表情);

    // ——应用滤镜（目标可改为 肖像.肖像，视你的美术层级而定）
    var styleStr:String = (this.滤镜风格 != undefined) ? this.滤镜风格 : this.当前滤镜风格;
    var styleOpt:Object = (this.滤镜参数 != undefined) ? this.滤镜参数 : this.当前滤镜参数;
    _root.对话框UI.应用头像滤镜(肖像, styleStr, styleOpt);
};

// ===============================
//  外部导入立绘刷新（就绪后挂滤镜）
// ===============================
_root.对话框UI.刷新外部导入立绘 = function(){
    this.肖像._visible = false;
    var portraitInfo = _root.对话框UI.loadPortraitDict[this.头像图标帧名];
    if(portraitInfo.instance == null){
        portraitInfo.instance = this.外部立绘层.createEmptyMovieClip(this.头像图标帧名, portraitInfo.depth);
        _root.对话框UI.loadPortraitList.push(this.头像图标帧名);
        portraitInfo.instance.loadMovie("flashswf/portraits/" + this.头像图标帧名 + ".swf");
        portraitInfo.instance.onLoad = function(){
            this.gotoAndStop(_root.对话框UI.人物表情 || "普通");
        };
    }
    if(this.当前立绘 !== portraitInfo.instance && this.当前立绘) this.当前立绘._visible = false;
    portraitInfo.instance._visible = true;

    if(portraitInfo.instance._totalframes > 0){
        var 跳转前帧数 = portraitInfo.instance._currentframe;
        portraitInfo.instance.gotoAndStop(人物表情);
        if(portraitInfo.instance._currentframe == 跳转前帧数 && 人物表情 != "普通"){
            portraitInfo.instance.gotoAndStop("普通");
        }

        // ——应用滤镜（外部立绘）
        var styleStr2:String = (this.滤镜风格 != undefined) ? this.滤镜风格 : this.当前滤镜风格;
        var styleOpt2:Object = (this.滤镜参数 != undefined) ? this.滤镜参数 : this.当前滤镜参数;
        _root.对话框UI.应用头像滤镜(portraitInfo.instance, styleStr2, styleOpt2);
    }
    this.当前立绘 = portraitInfo.instance;
};

// ===============================
//  打字/结束打字/下一句/关闭/onClose（保持原逻辑）
// ===============================
_root.对话框UI.打字 = function(fonts){
    if (this.i < length(fonts)){
        this.是否打印完毕 = false;
        打字内容 += fonts.substr(this.i, 1);
        this.i = this.i + 1;
    }
    if (this.i >= length(fonts)){
        结束打字();
    }
};

_root.对话框UI.结束打字 = function(){
    if (!this.是否打印完毕){
        打字内容 = 对话内容;
        delete this.onEnterFrame;
        对话进度++;
        this.是否打印完毕 = true;
        this.i = 0;
    }
};

_root.对话框UI.下一句 = function(){
    if (对话进度 < 对话条数){
        if (this.是否打印完毕){
            刷新内容();
        }else{
            结束打字();
        }
    }else{
        关闭();
    }
};

_root.对话框UI.关闭 = function(){
    this.gotoAndStop("close");
};

_root.对话框UI.onClose = function(){
    this._visible = false;
    本轮对话内容 = [];
    对话条数 = 0;
    人物名字 = null;
    人物表情 = null;
    _root.暂停 = false;
    图片容器.卸载图片();
    // if (结束对话后是否跳转帧){
    //     _root.淡出动画.淡出跳转帧(结束对话后跳转帧);
    //     结束对话后跳转帧 = "";
    //     结束对话后是否跳转帧 = false;
    // }
    if(this.followingEvent && this.followingEvent.name){
        if(this.followingEvent.args){
           _root.gameworld.dispatcher.publish.apply(_root.gameworld.dispatcher, this.followingEvent.args);
        }else{
            _root.gameworld.dispatcher.publish(this.followingEvent.name);
        }
        this.followingEvent = null;
    }
};

// ===============================
//  初始化对话框界面（保持原逻辑）
// ===============================
_root.对话框UI.初始化对话框界面 = function(对话框界面:MovieClip){
    对话框界面.刷新内容 = _root.对话框UI.刷新内容;
    对话框界面.打字 = _root.对话框UI.打字;
    对话框界面.结束打字 = _root.对话框UI.结束打字;
    对话框界面.下一句 = _root.对话框UI.下一句;
    对话框界面.关闭 = _root.对话框UI.关闭;
    对话框界面.onClose = _root.对话框UI.onClose;

    对话框界面.刷新立绘 = _root.对话框UI.刷新立绘;
    对话框界面.刷新外部导入立绘 = _root.对话框UI.刷新外部导入立绘;

    对话框界面.关闭();
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
