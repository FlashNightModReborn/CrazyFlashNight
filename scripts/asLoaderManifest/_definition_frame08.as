// asLoader 定义分段（由 tools/assemble-collapsed-frame.js 生成，勿手改）
// asLoader boot 定义母版（由 tools/assemble-collapsed-frame.js 生成；XFL 消费同源分段，勿手改本文件——改组装器重生成）。
// ▶ 架构导览 + 反直觉点 + 待测项：docs/asLoader-README.md（接手测试先读此文件）。
// 联合头 82 包 + 具体类 9 | live sources 29 | generated stages 6 | BootSequencer.run
// S0/S5/S9 业务、异步/控制行为与 f48 进度文案由 BootSequencer.as 编排。
this._lockroot = false;
this.play();

// === 帧顶跨帧符号（门② 结论：必须时间轴作用域，不可入 staged 函数体） ===
function 打印加载内容(str) {
    _root.加载内容文本.text = str;
}
function onError():Void {
    // 原 f41 空 TODO 死桩；保留同等 benign no-op（f3 载入关卡数据错误回调裸调，经闭包→时间轴解析）
}

// === 联合通配 import 头（82 包；lint --fold-specific 已证把 2 个具体包折入后的 84 包模拟并集仍为 0 碰撞） ===
import flash.display.*;
import flash.filters.*;
import flash.geom.*;
import org.flashNight.arki.achievement.*;
import org.flashNight.arki.audio.*;
import org.flashNight.arki.bullet.BulletComponent.Attributes.*;
import org.flashNight.arki.bullet.BulletComponent.Chain.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Init.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.*;
import org.flashNight.arki.bullet.BulletComponent.Movement.Util.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Shell.*;
import org.flashNight.arki.bullet.BulletComponent.Type.*;
import org.flashNight.arki.bullet.BulletComponent.Utils.*;
import org.flashNight.arki.bullet.Factory.*;
import org.flashNight.arki.camera.*;
import org.flashNight.arki.collision.*;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.component.Damage.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.component.Shield.*;
import org.flashNight.arki.component.StatHandler.*;
import org.flashNight.arki.corpse.*;
import org.flashNight.arki.cursor.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.ItemUtil.*;
import org.flashNight.arki.item.drug.*;
import org.flashNight.arki.item.itemCollection.*;
import org.flashNight.arki.item.itemIcon.*;
import org.flashNight.arki.key.*;
import org.flashNight.arki.map.*;
import org.flashNight.arki.merc.*;
import org.flashNight.arki.render.*;
import org.flashNight.arki.scene.*;
import org.flashNight.arki.skill.*;
import org.flashNight.arki.spatial.animation.*;
import org.flashNight.arki.spatial.move.*;
import org.flashNight.arki.spatial.transform.*;
import org.flashNight.arki.stageSelect.*;
import org.flashNight.arki.task.*;
import org.flashNight.arki.unit.*;
import org.flashNight.arki.unit.Action.Melee.*;
import org.flashNight.arki.unit.Action.PickUp.*;
import org.flashNight.arki.unit.Action.Regeneration.*;
import org.flashNight.arki.unit.Action.Shoot.*;
import org.flashNight.arki.unit.UnitComponent.Deinitializer.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.*;
import org.flashNight.arki.unit.UnitComponent.Dressup.EquipmentUtil.*;
import org.flashNight.arki.unit.UnitComponent.Initializer.*;
import org.flashNight.arki.unit.UnitComponent.Routing.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.weather.*;
import org.flashNight.aven.Coordinator.*;
import org.flashNight.aven.Proxy.*;
import org.flashNight.gesh.arguments.*;
import org.flashNight.gesh.array.*;
import org.flashNight.gesh.depth.*;
import org.flashNight.gesh.json.LoadJson.*;
import org.flashNight.gesh.object.*;
import org.flashNight.gesh.path.*;
import org.flashNight.gesh.pratt.*;
import org.flashNight.gesh.string.*;
import org.flashNight.gesh.text.*;
import org.flashNight.gesh.tooltip.*;
import org.flashNight.gesh.xml.LoadXml.*;
import org.flashNight.naki.DataStructures.*;
import org.flashNight.naki.PseudoRandom.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.naki.Sort.*;
import org.flashNight.neur.Controller.*;
import org.flashNight.neur.Event.*;
import org.flashNight.neur.InputCommand.*;
import org.flashNight.neur.PerformanceOptimizer.*;
import org.flashNight.neur.ScheduleTimer.*;
import org.flashNight.neur.Server.*;
import org.flashNight.neur.StateMachine.*;
import org.flashNight.sara.*;
import org.flashNight.sara.util.*;
// === 会话内新增类的具体 import 白名单（L42 陷阱；FQN 亦可能失败） ===
import org.flashNight.boot.BootSequencer;
import org.flashNight.arki.unit.Action.Skill.DrugInputService;
import org.flashNight.arki.unit.Action.Skill.ManualCooldownService;
import org.flashNight.arki.unit.Action.Skill.QuickSkillInputService;
import org.flashNight.arki.unit.Action.Skill.SkillReleaseGuard;
import org.flashNight.arki.unit.Action.Skill.SkillAttributeCore;
import org.flashNight.arki.unit.Action.Skill.SkillDamageCore;
import org.flashNight.arki.unit.Action.Skill.SkillReloadCore;
import org.flashNight.arki.unit.Action.Skill.WeaponSkillInputService;

// === staged 同步代码函数（仅定义，无内联调用；#include 编译期展开） ===
if (_root.__boot == undefined) _root.__boot = {};
// 基础运行时：作弊码 / eval / 通用工具 / 调试 / 随机 / 层级。
_root.__boot.f37_8 = function() {
    #include "../逻辑/装备函数/枪械射击动画.as"
    #include "../逻辑/装备函数/枪械激光瞄准.as"
    #include "../逻辑/装备函数/装备光源.as"
    #include "../逻辑/装备函数/血色光剑天秤.as"
    #include "../逻辑/装备函数/钛合金套装.as"
    #include "../逻辑/装备函数/火凤套装.as"
    #include "../逻辑/装备函数/统合61套装.as"
    #include "../逻辑/装备函数/剑圣腿甲.as"
    #include "../逻辑/装备函数/剑圣手甲.as"
    #include "../逻辑/装备函数/剑圣装甲鞋.as"
    #include "../逻辑/装备函数/九命猫妖.as"
};
_root.__boot.f38 = function() {
    #include "../逻辑/功能函数/功能函数_fs_兵器攻击检测.as"
    #include "../逻辑/功能函数/功能函数_fs_状态机用函数.as"
    #include "../逻辑/功能函数/功能函数_fs_导弹模板.as"
    #include "../逻辑/功能函数/功能函数_fs_新弹壳系统.as"
    #include "../逻辑/功能函数/功能函数_fs_修改器初始化.as"
};
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
