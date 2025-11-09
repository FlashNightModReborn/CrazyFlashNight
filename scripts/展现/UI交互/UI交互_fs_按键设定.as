
//_root.互动键 = 69;//e键
//_root.武器技能键 = 70;//f键
//_root.飞行键 = 18;//Alt键
//_root.武器变形键 = 81;//q键盘
//_root.奔跑键 = 16;//shift键盘
import org.flashNight.arki.key.KeyManager;
import org.flashNight.neur.Event.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

_root.刷新键值设定 = function() {
    // 调用KeyManager的refreshKeySettings方法
    KeyManager.refreshKeySettings(_root.键值设定, _root.获得翻译, _root.按键设定表[0]);
};



_root.键值设定 = [
    [_root.获得翻译("上键"), "上键", 87], 
    [_root.获得翻译("下键"), "下键", 83], 
    [_root.获得翻译("左键"), "左键", 65], 
    [_root.获得翻译("右键"), "右键", 68], 
    [_root.获得翻译("功能键A"), "A键", 74], 
    [_root.获得翻译("功能键B"), "B键", 75], 
    [_root.获得翻译("功能键C"), "C键", 82], 
    [_root.获得翻译("攻击模式-空手"), "键1", 49], 
    [_root.获得翻译("攻击模式-兵器"), "键2", 50], 
    [_root.获得翻译("攻击模式-手枪"), "键3", 51], 
    [_root.获得翻译("攻击模式-长枪"), "键4", 52], 
    [_root.获得翻译("攻击模式-手雷"), "键5", 53], 
    [_root.获得翻译("快捷物品栏1"), "快捷物品栏键1", 55], 
    [_root.获得翻译("快捷物品栏2"), "快捷物品栏键2", 56], 
    [_root.获得翻译("快捷物品栏3"), "快捷物品栏键3", 57], 
    [_root.获得翻译("快捷物品栏4"), "快捷物品栏键4", 48], 
    [_root.获得翻译("快捷技能栏1"), "快捷技能栏键1", 32], 
    [_root.获得翻译("快捷技能栏2"), "快捷技能栏键2", 85], 
    [_root.获得翻译("快捷技能栏3"), "快捷技能栏键3", 73], 
    [_root.获得翻译("快捷技能栏4"), "快捷技能栏键4", 79], 
    [_root.获得翻译("快捷技能栏5"), "快捷技能栏键5", 80], 
    [_root.获得翻译("快捷技能栏6"), "快捷技能栏键6", 76], 
    [_root.获得翻译("快捷技能栏7"), "快捷技能栏键7", 72], 
    [_root.获得翻译("快捷技能栏8"), "快捷技能栏键8", 71], 
    [_root.获得翻译("快捷技能栏9"), "快捷技能栏键9", 67], 
    [_root.获得翻译("快捷技能栏10"), "快捷技能栏键10", 66], 
    [_root.获得翻译("快捷技能栏11"), "快捷技能栏键11", 78], 
    [_root.获得翻译("快捷技能栏12"), "快捷技能栏键12", 77],  
    [_root.获得翻译("切换武器键"), "切换武器键", 47], 
    [_root.获得翻译("互动键"), "互动键", 69], 
    [_root.获得翻译("武器技能键"), "武器技能键", 70], 
    [_root.获得翻译("飞行键"), "飞行键", 18], 
    [_root.获得翻译("武器变形键"), "武器变形键", 81], 
    [_root.获得翻译("奔跑键"), "奔跑键", 16], 
    [_root.获得翻译("组合键"), "组合键", 17]
];
_root.默认键值设定 = _root.键值设定;
_root.按键设定表 = [[87, 83, 65, 68, 74, 75, 82, 81, 72, 79, 76, 73]];
_root.刷新键值设定();

_root.keyshow = Delegate.create(KeyManager, KeyManager.getKeyName);
_root.getKeySetting = Delegate.create(KeyManager, KeyManager.getKeySetting)


KeyManager.onRepeat("互动键", 30, function() {
    // _root.发布消息("互动键重复");
    _root.帧计时器.eventBus.publish("interactionKeyDown");
});

KeyManager.onKeyDown("互动键", function() {
    //_root.发布消息("互动键按下");
    _root.帧计时器.eventBus.publish("interactionKeyDown");
});

KeyManager.onKeyUp("互动键", function() {
    // _root.发布消息("互动键松开");
    _root.帧计时器.eventBus.publish("interactionKeyUp");
});

_root.当前玩家总数 = 1;
_root.playerCurrent = 0;

// ============================
// 双击方向键触发奔跑（KeyManager集中实现）
// 可调参数：双击判定帧间隔（默认10帧，约1/6秒@60fps）
// 说明：
// - 双击“左键”或“右键”会在主角 MovieClip 上设置
//   ctrl.doubleTapRunDirection = -1（左） / 1（右）
// - 帧计时器中会将该意图与 Shift 奔跑取 OR，且在松开方向键时自动清零
// ============================
var DOUBLE_TAP_RUN_INTERVAL_FRAMES:Number = 10;

KeyManager.onDoubleTap("左键", DOUBLE_TAP_RUN_INTERVAL_FRAMES, function():Void {
    var ctrl:Object = TargetCacheManager.findHero();
    if (ctrl) {
        ctrl.doubleTapRunDirection = -1;
        // _root.发布消息("检测到双击左键奔跑");
    }
}, this);

KeyManager.onDoubleTap("右键", DOUBLE_TAP_RUN_INTERVAL_FRAMES, function():Void {
    var ctrl:Object = TargetCacheManager.findHero();
    if (ctrl) {
        ctrl.doubleTapRunDirection = 1;
        // _root.发布消息("检测到双击右键奔跑");
    }
}, this);

// 松开对应方向键时，结束双击奔跑意图
KeyManager.onKeyUp("左键", function():Void {
    var ctrl:Object = TargetCacheManager.findHero();
    if (ctrl && ctrl.doubleTapRunDirection == -1) {
        ctrl.doubleTapRunDirection = 0;
        // _root.发布消息("左键松开，结束双击奔跑意图");
    }
}, this);

KeyManager.onKeyUp("右键", function():Void {
    var ctrl:Object = TargetCacheManager.findHero();
    if (ctrl && ctrl.doubleTapRunDirection == 1) {
        ctrl.doubleTapRunDirection = 0;
        // _root.发布消息("右键松开，结束双击奔跑意图");
    }
}, this);


// =============================
// 输入冻结（SceneReady 前屏蔽方向键）
// 未解决问题，姑且屏蔽
// =============================

/*

_root.按键设定 = {};
_root.按键设定.__originalIsDown = Key.isDown;
_root.按键设定.__isDown = function(code:Number):Boolean {
    _root.发布消息("sceneInputReady=" + _root.sceneInputReady);
    if (code == _root.左键 || code == _root.右键 || code == _root.上键 || code == _root.下键) {
        return false;
    }
    return _root.按键设定.__originalIsDown(code);
};

EventBus.getInstance().subscribe("SceneChanged", function():Void { 
    Key.isDown =  _root.按键设定.__isDown;
    _root.发布消息("方向键输入已冻结");
}, null);
EventBus.getInstance().subscribe("SceneReady", function():Void { 
    Key.isDown = _root.按键设定.__originalIsDown;
    _root.发布消息("方向键输入已解冻");
}, null);

*/
