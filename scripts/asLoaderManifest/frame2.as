// [stage-wrap] frame2 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
//   + staged 函数 + 内联调用。
import org.flashNight.arki.audio.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.pratt.*;
import org.flashNight.gesh.string.*;
import org.flashNight.naki.PseudoRandom.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.ScheduleTimer.*;

if (_root.__boot == undefined) _root.__boot = {};
_root.__boot.f2 = function() {
    打印加载内容("加载游戏代码……");

    #include "../引擎/引擎_aka_作弊码.as"
    #include "../引擎/引擎_fs_eval解析器.as"
    #include "../引擎/引擎_fs_常用工具函数.as"
    #include "../引擎/引擎_fs_调试模式.as"
    #include "../引擎/引擎_fs_随机数引擎.as"
    #include "../引擎/引擎_lsy_层级管理器.as"
    #include "../引擎/引擎_lsy_常数.as"
    #include "../引擎/引擎_lsy_等级与经验值.as"
     #include "../引擎/引擎_lsy_技能系统.as"
     #include "../逻辑/单位函数/单位函数_fs_空中控制器.as"
     #include "../引擎/引擎_fs_路由基础.as"
     #include "../引擎/引擎_fs_技能路由.as"
     #include "../引擎/引擎_fs_战技路由.as"
    #include "../引擎/引擎_fs_兵器攻击路由.as"
    #include "../引擎/引擎_fs_空手攻击路由.as"
    #include "../引擎/引擎_lsy_战宠系统.as"
    #include "../引擎/引擎_鸡蛋_lsy_物品系统.as"
    #include "../引擎/引擎_lsy_声音系统.as"
    #include "../引擎/引擎_lsy_基建系统.as"
};
_root.__boot.f2();
