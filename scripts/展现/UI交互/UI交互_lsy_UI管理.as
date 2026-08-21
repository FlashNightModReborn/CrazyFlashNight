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
org.flashNight.arki.ui.HairdresserPanelService.install();
org.flashNight.arki.ui.GameSettingsPanelService.install();

_root.gameCommands["togglePause"] = function() {
    _root.暂停 = !_root.暂停;  // watch 自动 pushUiState("p:0/1")
    System.IME.setEnabled(false);
    if (_root.暂停) {
        _root.最上层发布文字提示(_root.获得翻译("游戏暂停"));
    } else {
        _root.最上层发布文字提示(_root.获得翻译("游戏取消暂停"));
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
    _root.最上层发布文字提示(_root.获得翻译("商城请通过 Launcher SHOP 面板打开"));
};

_root.gameCommands["openHelp"] = function() {
    _root.加载外部UI("flashswf/UI/帮助界面.swf");
};

_root.gameCommands["togglePets"] = function() {
    _root.宠物信息界面.排列宠物图标();
    _root.宠物信息界面._visible = !_root.宠物信息界面._visible;
};

// toggleMercs 已移除：旧 Flash 佣兵信息界面(Symbol 923 簇) 已退役不实例化，且无任何派发方
// （佣兵管理迁 web 战队页）。死命令删除，避免误以为还能切旧面板。

_root.gameCommands["toggleTablet"] = function() {
    if (!_root.平板电脑界面._visible) {
        _root.平板电脑界面.初始化();
    }
};

_root.gameCommands["safeExit"] = function() {
    // 安全退出界面已迁移到 Launcher Web 侧
    // 只触发存盘，sv:1/sv:2/sv:3 分别通知存盘中/成功/失败
    _root.仓库标志 = 0;
    _root.存盘标志 = 0;
    // Plan A: safeExit 必达，绕过 debounce 立即同步落盘
    _root.强制存盘();
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

_root.gameCommands["openMaterialUI"] = function(params) {
    var missingOpenRequestId:Boolean = params == undefined || params == null
        || typeof(params.openRequestId) == "undefined";
    var opened:Boolean = missingOpenRequestId
        ? org.flashNight.arki.item.CraftingPanelService.openMaterialsPanel(
            "nativehud_materials")
        : org.flashNight.arki.item.CraftingPanelService.openMaterialsPanel(
            "nativehud_materials", params.openRequestId);
    if (!opened) {
        _root.发布消息("材料面板暂时不可用");
    }
};

// 设置已迁移为 Host 挂载的 Web Panel；游戏设置与键位仍由 AS2 判定。
// 旧 SWF 仅作不可达归档，不再双路由。
_root.gameCommands["openSettings"] = function():Boolean {
    return org.flashNight.arki.ui.GameSettingsPanelService.openPanel();
};

_root.gameCommands["openJukebox"] = function() {
    _root.发布消息("点歌器已迁移至右上角面板");
};
_root.gameCommands["jukeboxPlay"] = function(params) {
    _root.soundEffectManager.jukeboxPlay(params.title);
};
_root.gameCommands["jukeboxSeek"] = function(params) {
    if (params == null || typeof params != "object") return;
    var expected:Array = ["task", "action", "seconds"];
    var count:Number = 0;
    for (var key:String in params) {
        if (!Object.prototype.hasOwnProperty.call(params, key)) continue;
        var known:Boolean = false;
        for (var i:Number = 0; i < expected.length; i++) {
            if (expected[i] === key) {
                known = true;
                break;
            }
        }
        if (!known) return;
        count++;
    }
    if (count != expected.length
            || !Object.prototype.hasOwnProperty.call(params, "task")
            || !Object.prototype.hasOwnProperty.call(params, "action")
            || !Object.prototype.hasOwnProperty.call(params, "seconds")
            || params.task !== "cmd"
            || params.action !== "jukeboxSeek"
            || typeof params.seconds != "number"
            || (params.seconds - params.seconds) != 0
            || params.seconds < 0
            || params.seconds > 86400) return;
    org.flashNight.arki.audio.AudioBridge.seekBGM(params.seconds, null);
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
_root.gameCommands["audioV2QualificationStimulus"] = function(params) {
    org.flashNight.arki.audio.AudioQualificationStimulus.handle(params);
};
_root.gameCommands["bakeIcons"] = function(params) {
    var maxCount:Number = Number(params.maxCount);
    org.flashNight.arki.item.IconBaker.start(isNaN(maxCount) ? 0 : maxCount);
};
_root.gameCommands["bakeSkillIcons"] = function(params) {
    org.flashNight.arki.item.IconBaker.startSkillIcons();
};

// ============================================================
// 游戏状态通知 → WebView 按钮可见性
// s:0 = 未加载/重置（仅全屏/日志/其他可用）
// s:1 = 游戏已进入（全部按钮可用）
// ============================================================
_root.notifyGameEntered = function() {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("s:1");
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("ga:" + String(_root._bootstrapAttemptId));
};

_root.notifyGameReset = function() {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("s:0");
};

// 暂停状态同步（经 PauseManager 订阅链分发，取代直接 _root.watch）
// 任何新增暂停观察者必须走 PauseManager.subscribe；禁止裸 _root.watch("暂停", ...)（会覆盖 PauseManager 的回调）
org.flashNight.arki.pause.PauseManager.install();
org.flashNight.arki.pause.PauseManager.subscribe(function(newVal, oldVal, tag):Void {
    org.flashNight.arki.render.FrameBroadcaster.pushUiState("p:" + (newVal ? "1" : "0"));
    System.IME.setEnabled(false);
}, null);

// web 面板打开 = 暂停游戏：玩家此时看不到 AS2 画面，游戏不该在背后继续跑（NPC 离场 / 敌人攻击 / 计时推进）。
// C# 任意 OpenPanel → webPanelPause、case "close" → webPanelUnpause。幂等：只持一个 lease，多次 open
// （含 returnTo）不叠加，close 释放。（kshop 另有 "shop" lease，叠加安全：两个 lease 都释放才真正解除暂停。）
if (_root.gameCommands == undefined) _root.gameCommands = {};
_root.gameCommands["webPanelPause"] = function() {
    if (_root._webPanelPauseLease == undefined)
        _root._webPanelPauseLease = org.flashNight.arki.pause.PauseManager.lease(true, "webpanel");
};
_root.gameCommands["webPanelUnpause"] = function() {
    // 非空 loot close(false) 已落 LOOT_SUSPENDED 时，这个 lease 仍属于刚关闭的
    // loot panel。由服务按 exact pending flag 释放并清证明，随后直接返回，绝不触发旧 UI。
    var suspendedRelease:Object =
        org.flashNight.arki.item.LootContainerService.releaseSuspendedPauseForClose();
    if (suspendedRelease != null && suspendedRelease.handled === true) return;
    // loot socket/navigation handoff 由 LootContainerService 原子证明权威 suspend/terminal；
    // Host 的迟到 generic unpause 不得越过仍在重试的本地 transport fence。
    if (org.flashNight.arki.item.LootContainerService.hasPendingTransportDetach()) return;
    // CharacterBuild 的 finalize receipt 不等于 Host visual-close/pause-release proof。
    // generic close 只查询 fence，绝不替 stale build authority 结算或释放当前/后来 lease；
    // 正常 close 与重连 recovery 只能走 Host-only characterBuildRecoverDetach。
    if (org.flashNight.arki.item.CharacterBuildService
            .blocksGenericPauseRelease()) return;
    if (_root._webPanelPauseLease != undefined) {
        org.flashNight.arki.pause.PauseManager.releaseLease(_root._webPanelPauseLease);
        _root._webPanelPauseLease = undefined;
    }
    // loot 正常 terminal 已先在 AS2 落权威终态，但特意保留 lease；只有 Host 收齐
    // exact DOM/native visual-close 证明后调用到这里，才解除暂停。非终态由服务保留
    // Web-only suspend，不存在 Flash UI 通用回退。
};

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
