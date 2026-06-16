// [stage-wrap] frame39 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
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
_root.__boot.f39 = function() {
    #include "../逻辑/关卡系统/关卡系统_fs_佣兵刷新系统.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_add2map_加载背景.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_场景转换.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_地图元件.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_非人形佣兵刷新系统.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_无限过图.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_关卡回调函数.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_后景.as"    
    #include "../逻辑/关卡系统/关卡系统_lsy_限制系统.as"
};
_root.__boot.f39();
