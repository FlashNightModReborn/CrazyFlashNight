import org.flashNight.arki.key.KeyManager;
import org.flashNight.neur.Event.*;

_root.刷新键值设定 = function() {
    // 调用KeyManager的refreshKeySettings方法
    KeyManager.refreshKeySettings(_root.键值设定, _root.获得翻译, _root.按键设定表[0]);
};

_root.获得翻译 = function(str)
{
	return str;
}

_root.键值设定 = [[_root.获得翻译("上键"), "上键", 87], [_root.获得翻译("下键"), "下键", 83], [_root.获得翻译("左键"), "左键", 65], [_root.获得翻译("右键"), "右键", 68], [_root.获得翻译("功能键A"), "A键", 74], [_root.获得翻译("功能键B"), "B键", 75], [_root.获得翻译("功能键C"), "C键", 82], [_root.获得翻译("攻击模式-空手"), "键1", 49], [_root.获得翻译("攻击模式-兵器"), "键2", 50], [_root.获得翻译("攻击模式-手枪"), "键3", 51], [_root.获得翻译("攻击模式-长枪"), "键4", 52], [_root.获得翻译("攻击模式-手雷"), "键5", 53], [_root.获得翻译("快捷物品栏1"), "快捷物品栏键1", 55], [_root.获得翻译("快捷物品栏2"), "快捷物品栏键2", 56], [_root.获得翻译("快捷物品栏3"), "快捷物品栏键3", 57], [_root.获得翻译("快捷物品栏4"), "快捷物品栏键4", 48], [_root.获得翻译("快捷技能栏1"), "快捷技能栏键1", 32], [_root.获得翻译("快捷技能栏2"), "快捷技能栏键2", 85], [_root.获得翻译("快捷技能栏3"), "快捷技能栏键3", 73], [_root.获得翻译("快捷技能栏4"), "快捷技能栏键4", 79], [_root.获得翻译("快捷技能栏5"), "快捷技能栏键5", 80], [_root.获得翻译("快捷技能栏6"), "快捷技能栏键6", 76], [_root.获得翻译("快捷技能栏7"), "快捷技能栏键7", 72], [_root.获得翻译("快捷技能栏8"), "快捷技能栏键8", 71], [_root.获得翻译("快捷技能栏9"), "快捷技能栏键9", 67], [_root.获得翻译("快捷技能栏10"), "快捷技能栏键10", 66], [_root.获得翻译("快捷技能栏11"), "快捷技能栏键11", 78], [_root.获得翻译("快捷技能栏12"), "快捷技能栏键12", 77],  [_root.获得翻译("切换武器键"), "切换武器键", 47], [_root.获得翻译("互动键"), "互动键", 69], [_root.获得翻译("武器技能键"), "武器技能键", 70], [_root.获得翻译("飞行键"), "飞行键", 18],  [_root.获得翻译("武器变形键"), "武器变形键", 81], [_root.获得翻译("奔跑键"), "奔跑键", 16]];
_root.刷新键值设定();

KeyManager.onLongPressL("互动键", 10, function() {
    trace("LongPress_互动键");
}, this);

KeyManager.onDoubleTapL("互动键", 10, function() {
    trace("DoubleTap_互动键");
}, this);


KeyManager.onRepeatL("互动键", 10, function() {
    trace("onRepeat_互动键");
}, this);

KeyManager.onKeyDownL("互动键", function() {
    trace("onKeyDown_互动键");
}, this);

KeyManager.onKeyUpL("互动键", function() {
    trace("onKeyUp_互动键");
}, this);