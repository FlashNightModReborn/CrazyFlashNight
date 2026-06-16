// [stage-wrap chunked<70000B] frame36 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数(10 chunk 绕 AVM1 64KB 函数体上限,见 swf-function-sizes 门) + 内联调用。
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.ItemUtil.*;
import org.flashNight.arki.item.drug.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.Melee.*;
import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.Action.Skill.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.weather.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.gesh.object.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.sara.util.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f36_1 = function() {
    打印加载内容("加载逻辑代码……");
    
    #include "../逻辑/单位函数/单位函数_aka_lsy_使用药剂.as"
    #include "../逻辑/单位函数/单位函数_aka_升空函数.as"
    #include "../逻辑/单位函数/单位函数_fs_ai与特效通用函数.as"
};
_root.__boot.f36_2 = function() {
    #include "../逻辑/单位函数/单位函数_fs_aka_玩家模板迁移.as"
};
_root.__boot.f36_3 = function() {
    #include "../逻辑/单位函数/单位函数_fs_玩家装备配置.as"
    #include "../逻辑/单位函数/单位函数_fs_装备生命周期配置.as"
    #include "../逻辑/单位函数/单位函数_fs_装备引用配置.as"
    #include "../逻辑/单位函数/单位函数_fs_佣兵ai.as"
    #include "../逻辑/单位函数/单位函数_fs_佣兵加血加蓝.as"
    #include "../逻辑/单位函数/单位函数_lsy_敌人ai.as"
};
_root.__boot.f36_4 = function() {
    #include "../逻辑/单位函数/单位函数_lsy_敌人模板迁移.as"
};
_root.__boot.f36_5 = function() {
    #include "../逻辑/单位函数/单位函数_lsy_敌人特殊函数.as"
    #include "../逻辑/单位函数/单位函数_lsy_主角射击函数.as"
    #include "../逻辑/单位函数/单位函数_lsy_主角行走状态机.as"
};
_root.__boot.f36_6 = function() {
    #include "../逻辑/单位函数/单位函数_雾人_aka_fs_主动战技.as"
};
_root.__boot.f36_7 = function() {
    #include "../逻辑/单位函数/单位函数_lsy_主角技能.as"
};
_root.__boot.f36_8 = function() {
    #include "../逻辑/单位函数/单位函数_雾人_兵器搓招指令.as"
    #include "../逻辑/单位函数/单位函数_雾人_空手搓招指令.as"
};
_root.__boot.f36_9 = function() {
    #include "../逻辑/单位函数/单位函数_aka_战宠进阶.as"
};
_root.__boot.f36_10 = function() {
    #include "../逻辑/单位函数/单位函数_fs_护盾函数.as"
};
_root.__boot.f36_1();
_root.__boot.f36_2();
_root.__boot.f36_3();
_root.__boot.f36_4();
_root.__boot.f36_5();
_root.__boot.f36_6();
_root.__boot.f36_7();
_root.__boot.f36_8();
_root.__boot.f36_9();
_root.__boot.f36_10();
