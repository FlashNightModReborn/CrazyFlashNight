// [stage-wrap] frame41 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
// [manual semantic split] 4 个 chunk 手工保序；物品栏核心与“强化/样品栏”各自独立边界。
// 这里不声明持续的 90000B 自动预算；后续修改须同时复核源闭包与 SWF codeSize。
import flash.display.*;
import flash.filters.*;
import flash.geom.*;
import org.flashNight.arki.achievement.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.cursor.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.key.*;
import org.flashNight.arki.map.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.skill.*;
import org.flashNight.arki.stageSelect.*;
import org.flashNight.arki.task.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.string.*;
import org.flashNight.gesh.text.*;
import org.flashNight.gesh.tooltip.*;
import org.flashNight.neur.Event.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f41_1 = function() {
    #include "../展现/UI交互/UI交互_fs_按键设定.as"
    #include "../展现/UI交互/UI交互_fs_个人信息.as"
    #include "../展现/UI交互/UI交互_fs_玩家信息界面.as"
    #include "../展现/UI交互/UI交互_fs_经济面板.as"
    #include "../展现/UI交互/UI交互_lsy_UI管理.as"
    #include "../展现/UI交互/UI交互_lsy_对话文本.as"
    #include "../逻辑系统分区/商城系统_WebView.as"
    #include "../逻辑系统分区/物品系统_WebView.as"
    #include "../逻辑系统分区/技能系统_WebView.as"
    #include "../逻辑系统分区/地图系统_WebView.as"
    #include "../逻辑系统分区/选关系统_WebView.as"
    #include "../逻辑系统分区/竞技场系统_WebView.as"
    #include "../逻辑系统分区/战宠系统_WebView.as"
    #include "../逻辑系统分区/佣兵系统_WebView.as"
    #include "../逻辑系统分区/任务系统_WebView.as"
    #include "../展现/UI交互/UI交互_lsy_鼠标代理.as"
};
_root.__boot.f41_2 = function() {
    #include "../展现/UI交互/UI交互_lsy_物品栏UI.as"
};
_root.__boot.f41_3 = function() {
    #include "../展现/UI交互/UI交互_lsy_物品栏UI_强化与样品栏.as"
};
_root.__boot.f41_4 = function() {
    #include "../展现/UI交互/UI交互_lsy_任务栏UI.as"
    #include "../展现/UI交互/UI交互_lsy_对话框UI.as"
    #include "../展现/UI交互/UI交互_鸡蛋_fs_aka_物品图标注释.as"
    #include "../展现/UI交互/UI交互_无名氏_改造系统.as"
    #include "../展现/UI交互/UI交互_aka_健身房训练.as"
};
_root.__boot.f41_1();
_root.__boot.f41_2();
_root.__boot.f41_3();
_root.__boot.f41_4();
