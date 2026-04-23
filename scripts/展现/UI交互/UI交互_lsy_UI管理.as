_root.加载外部UI = function(url){
    _root.通用UI层.外部导入UI界面._visible = true;
    if(url != _root.通用UI层.外部UIURL){
        _root.通用UI层.外部UIURL = url;
        _root.通用UI层.外部导入UI界面._x = 0;
        _root.通用UI层.外部导入UI界面._y = 0;
        _root.通用UI层.外部导入UI界面._xscale = 100;
        _root.通用UI层.外部导入UI界面._yscale = 100;
        _root.通用UI层.外部导入UI界面.loadMovie(url);
    }
}

_root.从库中加载外部UI = function(identifier){
    var UI = _root.通用UI层[identifier];
    if(UI != null){
        UI._visible = true;
        return UI;
    }
    if(!_root.通用UI层.外部UI列表) _root.通用UI层.外部UI列表 = [];
    UI = _root.通用UI层.attachMovie(identifier,identifier,_root.通用UI层.getNextHighestDepth());
    _root.通用UI层.外部UI列表.push(UI);
    return UI;

}

_root.卸载外部UI = function(){
    _root.通用UI层.外部UIURL = null;
    _root.通用UI层.外部导入UI界面.unloadMovie();
    for(var i = 0; i<_root.通用UI层.外部UI列表.length; i++){
        _root.通用UI层.外部UI列表[i].removeMovieClip();
    }
    _root.通用UI层.外部UI列表 = null;
}


//全屏UI层管理
_root.从库中加载全屏UI = function(identifier){
    if(_root.全屏UI层.当前UI != null) _root.卸载全屏UI();
    _root.全屏UI层.当前UI = _root.全屏UI层.attachMovie(identifier, identifier, 0);
    return _root.全屏UI层.当前UI;
}

_root.卸载全屏UI = function(){
    _root.全屏UI层.当前UI.removeMovieClip();
    _root.全屏UI层.当前UI = null;
    _root.全屏UI层.引导界面.unloadMovie();
}

_root.加载引导界面 = function(filename){
    _root.全屏UI层.引导界面._visible = true;
    _root.全屏UI层.引导界面._alpha = 100;
    _root.全屏UI层.引导界面.loadMovie("flashswf/UI/引导界面合集/" + filename + ".swf");
}

// ============================================================
// C#→AS2 游戏命令注册
// ============================================================
if (_root.gameCommands == undefined) _root.gameCommands = {};

_root.gameCommands["togglePause"] = function() {
    _root.暂停 = !_root.暂停;  // watch 自动 pushUiState("p:0/1")
    System.IME.setEnabled(false);
    if (_root.暂停) {
        _root.最上层发布文字提示(_root.获得翻译("游戏暂停"));
    } else {
        _root.最上层发布文字提示(_root.获得翻译("游戏取消暂停"));
    }
};

_root.gameCommands["warehouse"] = function() {
    if (_root.仓库名称 != "后勤战备箱") {
        _root.仓库名称 = "后勤战备箱";
        _root.物品UI函数.刷新仓库图标(_root.物品栏.战备箱, 0);
    }
};

_root.gameCommands["toggleSettings"] = function() {
    if (_root.修改工具界面._visible || _root.isChallengeMode()) {
        _root.修改工具界面._visible = false;
    } else {
        _root.修改工具界面._visible = true;
    }
};

_root.gameCommands["openShop"] = function() {
    _root.商城主mc = _root.从库中加载全屏UI("shopMainMC");
};

_root.gameCommands["openHelp"] = function() {
    _root.加载外部UI("flashswf/UI/帮助界面.swf");
};

_root.gameCommands["togglePets"] = function() {
    _root.宠物信息界面.排列宠物图标();
    _root.宠物信息界面._visible = !_root.宠物信息界面._visible;
};

_root.gameCommands["toggleMercs"] = function() {
    _root.佣兵信息界面._visible = !_root.佣兵信息界面._visible;
};

_root.gameCommands["toggleTablet"] = function() {
    if (!_root.平板电脑界面._visible) {
        _root.平板电脑界面.初始化();
    }
};

_root.gameCommands["safeExit"] = function() {
    // 安全退出界面已迁移到 Launcher Web 侧
    // 只触发存盘，sv:1/sv:2 通知 Launcher 面板状态
    _root.仓库标志 = 0;
    _root.存盘标志 = 0;
    _root.自动存盘();
};

_root.gameCommands["openTaskMap"] = function() {
    // 旧地图入口已被 WebView 面板取代，统一转发到 openWebMap
    if (_root.gameCommands["openWebMap"] != undefined) {
        _root.gameCommands["openWebMap"]({ source: "as2_task_map_cmd" });
    }
};

// ============================================================
// 右上角地图 HUD 状态桥：mm=模式，mh=当前热点
// mm: 0 hidden / 1 base / 2 outdoor / 3 combat_reserved
// ============================================================
if (_root.__mapHudStateBridgeInstalled != true) {
    _root.__mapHudStateBridgeInstalled = true;
    _root.__mapHudStateBridge = {
        lastMode: null,
        lastHotspotId: null
    };

    _root.__resolveMapHudMode = function():String {
        var hotspotId:String;
        var pageId:String;
        var currentLabel:String = String(_root._currentlabel || "");
        if (_root.当前为战斗地图 == true) return "3";

        hotspotId = String(org.flashNight.arki.map.MapHotspotResolver.resolveCurrent() || "");
        if (hotspotId != "") {
            pageId = String(org.flashNight.arki.map.MapPanelCatalog.resolvePageId(hotspotId) || "");
            if (pageId == "base") return "1";
            if (pageId == "faction" || pageId == "defense" || pageId == "school") return "2";
        }

        if (currentLabel == "基地地图") return "1";
        if (currentLabel == "外部地图") return "2";
        return "0";
    };

    _root.__pushMapHudState = function(force:Boolean):Void {
        var bridge:Object = _root.__mapHudStateBridge;
        var mode:String = _root.__resolveMapHudMode();
        var hotspotId:String = "";
        if (mode != "0") {
            hotspotId = String(org.flashNight.arki.map.MapHotspotResolver.resolveCurrent() || "");
        }

        if (!force && bridge.lastMode == mode && bridge.lastHotspotId == hotspotId) {
            return;
        }

        org.flashNight.arki.render.FrameBroadcaster.pushUiState("mm:" + mode);
        org.flashNight.arki.render.FrameBroadcaster.pushUiState("mh:" + hotspotId);
        bridge.lastMode = mode;
        bridge.lastHotspotId = hotspotId;
    };

    _root.帧计时器.eventBus.subscribe("frameEnd", function():Void {
        _root.__pushMapHudState(false);
    }, null);

    _root.帧计时器.eventBus.subscribe("SceneChanged", function():Void {
        _root.__mapHudStateBridge.lastMode = null;
        _root.__mapHudStateBridge.lastHotspotId = null;
        _root.__pushMapHudState(true);
    }, null);
}

_root.gameCommands["openTaskUI"] = function() {
    _root.从库中加载全屏UI("任务栏界面");
};

_root.gameCommands["openEquipUI"] = function() {
    _root.物品栏界面._visible = true;
    _root.物品栏界面.gotoAndStop(_root.物品栏界面.界面);
};

_root.gameCommands["openSettings"] = function() {
    _root.系统设置界面._visible = !_root.系统设置界面._visible;
};

_root.gameCommands["openJukebox"] = function() {
    _root.发布消息("点歌器已迁移至右上角面板");
};
_root.gameCommands["jukeboxPlay"] = function(params) {
    _root.soundEffectManager.jukeboxPlay(params.title);
};
_root.gameCommands["jukeboxStop"] = function() {
    _root.soundEffectManager.jukeboxStop();
};
_root.gameCommands["jukeboxOverride"] = function(params) {
    _root.soundEffectManager.setJukeboxOverride(params.value == true || params.value == "true");
};
_root.gameCommands["jukeboxTrackEnd"] = function() {
    _root.soundEffectManager.jukeboxTrackEnd();
};
_root.gameCommands["jukeboxTrueRandom"] = function(params) {
    _root.soundEffectManager.setTrueRandom(params.value == true || params.value == "true");
};
_root.gameCommands["jukeboxPlayMode"] = function(params) {
    _root.soundEffectManager.setPlayMode(params.value);
};
_root.gameCommands["setGlobalVolume"] = function(params) {
    if (!isNaN(params.value)) _root.soundEffectManager.setGlobalVolume(Number(params.value));
};
_root.gameCommands["setBGMVolume"] = function(params) {
    if (!isNaN(params.value)) _root.soundEffectManager.setBGMVolume(Number(params.value));
};
_root.gameCommands["bakeIcons"] = function(params) {
    var maxCount:Number = Number(params.maxCount);
    org.flashNight.arki.item.IconBaker.start(isNaN(maxCount) ? 0 : maxCount);
};

// ============================================================
// 游戏状态通知 → WebView 按钮可见性
// s:0 = 未加载/重置（仅全屏/日志/其他可用）
// s:1 = 游戏已进入（全部按钮可用）
// ============================================================
_root.notifyGameEntered = function() {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("s:1");
};

_root.notifyGameReset = function() {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("s:0");
};

// 暂停状态同步
_root.watch("暂停", function(prop, oldVal, newVal) {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("p:" + (newVal ? "1" : "0"));
    System.IME.setEnabled(false);
    return newVal;
});

// 主线任务进度 → 控制按钮可见性
_root.watch("主线任务进度", function(prop, oldVal, newVal) {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("q:" + newVal);
    return newVal;
});

// SceneChanged: 推送所有 UI 状态初始值
_root.帧计时器.eventBus.subscribe("SceneChanged", function() {
    var fb = org.flashNight.arki.render.FrameBroadcaster;
    // 经济值可能在存档加载前为 undefined，防御性检查
    var gold:Number = Number(_root.金钱);
    var kpoint:Number = Number(_root.虚拟币);
    if (!isNaN(gold)) fb.pushUiState("g:" + Math.round(gold));
    if (!isNaN(kpoint)) fb.pushUiState("k:" + Math.round(kpoint));
    fb.pushUiState("p:" + (_root.暂停 ? "1" : "0"));
    fb.pushUiState("q:" + _root.主线任务进度);
}, null);

_root.最上层发布文字提示 = function(消息){
    if (_root.server.isSocketConnected) {
        // Launcher 在线 → 走 N-prefix 快车道 → Web overlay 游戏通知
        _root.server.sendSocketMessage("Ngame|ffd700|" + 消息);
    } else {
        // Launcher 不在线（CS6 测试 / socket 断线）→ Flash 本地队列
        _root.全屏UI层.文字提示列表.push(消息);
        if(_root.全屏UI层.getActiveTextCount() == 0){
            _root.全屏UI层.tickCount = 0;
        }
    }
}
