// [stage-wrap] frame39 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
// [manual semantic split] 2 个 chunk 按“关卡进入与场景建立 / 刷新、回调与场景限制”手工保序；
// 这些边界不是 stage-wrap 的持续自动预算门，后续修改须同时复核源闭包与 SWF codeSize。
import flash.display.*;
import flash.geom.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.camera.*;
import org.flashNight.arki.collision.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.corpse.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.PickUp.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.weather.*;
import org.flashNight.gesh.depth.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.*;

if (_root.__boot == undefined) _root.__boot = {};
// 关卡进入与场景建立。
_root.__boot.f39_1 = function() {
    #include "../逻辑/关卡系统/关卡系统_fs_佣兵刷新系统.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_add2map_加载背景.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_场景转换.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_地图元件.as"
};
// 刷新、回调与场景限制。
_root.__boot.f39_2 = function() {
    #include "../逻辑/关卡系统/关卡系统_lsy_非人形佣兵刷新系统.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_无限过图.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_关卡回调函数.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_后景.as"
    #include "../逻辑/关卡系统/关卡系统_lsy_限制系统.as"
};
_root.__boot.f39_1();
_root.__boot.f39_2();
