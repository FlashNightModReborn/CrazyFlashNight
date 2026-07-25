// [stage-wrap] frame2 折叠中间态：帧顶联合头(lint --fold-specific 子集,0 碰撞)
// [manual semantic split] 3 个 chunk 按“基础运行时 / 成长与路由 / 攻击与子系统路由”手工保序；
// 这些边界不是 stage-wrap 的持续自动预算门，后续修改须同时复核源闭包与 SWF codeSize。
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
// 基础运行时：作弊码 / eval / 通用工具 / 调试 / 随机 / 层级。
_root.__boot.f2_1 = function() {
    打印加载内容("加载游戏代码……");

    #include "../引擎/引擎_aka_作弊码.as"
    #include "../引擎/引擎_fs_eval解析器.as"
    #include "../引擎/引擎_fs_常用工具函数.as"
    #include "../引擎/引擎_fs_调试模式.as"
    #include "../引擎/引擎_fs_随机数引擎.as"
    #include "../引擎/引擎_lsy_层级管理器.as"
    #include "../引擎/引擎_lsy_常数.as"
};
// 成长与路由基础：等级 / 技能 / 空中控制 / 基础与技能路由。
_root.__boot.f2_2 = function() {
    #include "../引擎/引擎_lsy_等级与经验值.as"
    #include "../引擎/引擎_lsy_技能系统.as"
    #include "../逻辑/单位函数/单位函数_fs_空中控制器.as"
    #include "../引擎/引擎_fs_路由基础.as"
    #include "../引擎/引擎_fs_技能路由.as"
};
// 攻击与子系统路由：战技 / 兵器 / 空手 / 战宠 / 物品 / 声音 / 基建。
_root.__boot.f2_3 = function() {
    #include "../引擎/引擎_fs_战技路由.as"
    #include "../引擎/引擎_fs_兵器攻击路由.as"
    #include "../引擎/引擎_fs_空手攻击路由.as"
    #include "../引擎/引擎_lsy_战宠系统.as"
    #include "../引擎/引擎_鸡蛋_lsy_物品系统.as"
    #include "../引擎/引擎_lsy_声音系统.as"
    #include "../引擎/引擎_lsy_基建系统.as"
};
_root.__boot.f2_1();
_root.__boot.f2_2();
_root.__boot.f2_3();
