// asLoader 单帧 boot 帧 CDATA（由 tools/assemble-collapsed-frame.js 生成；asLoader.xml 单关键帧 #include 之，勿手改本文件——改组装器重生成）。
// ▶ 架构导览 + 反直觉点 + 待测项：docs/asLoader-README.md（接手测试先读此文件）。
// 联合头 82 包 | staged fN 13 | loader-fire fN 16 | s0..s9 分组 + BootSequencer.run
// 异步/控制帧(f4握手/f5,6 await/f7→s5_parseTask/f26 最终化2 队列/f75 craft/f91 handoff) 由 BootSequencer.as 编排。
this._lockroot = false;
this.stop();

// === 帧顶跨帧符号（门② 结论：必须时间轴作用域，不可入 staged 函数体） ===
function 打印加载内容(str) {
    _root.加载内容文本.text = str;
}
function onError():Void {
    // 原 f41 空 TODO 死桩；保留同等 benign no-op（f3 载入关卡数据错误回调裸调，经闭包→时间轴解析）
}

// === 联合通配 import 头（收集去重；lint --fold-specific 已证 82 超集 0 碰撞，子集亦 0） ===
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
import org.flashNight.arki.unit.Action.Skill.*;
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
import org.flashNight.boot.BootSequencer;   // 显式 import（L42 陷阱：CS6 会话缓存对会话内新类需显式 import，FQN 亦可能失败）

// === staged 同步代码函数（仅定义，无内联调用；#include 编译期展开） ===
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
_root.__boot.f3 = function() {
    打印加载内容("加载通信代码……");

    #include "../通信/通信_fs_lsy_XML数据解析.as"
    #include "../通信/通信_fs_本地服务器.as"
    #include "../通信/通信_fs_帧计时器.as"
    #include "../通信/通信_lsy_原版存档系统.as"
    #include "../通信/通信_lsy_存档迁移.as"
    #include "../通信/通信_fs_bootstrap.as"
    #include "../通信/通信_鸡蛋_XML与JSON解析.as"
    #include "../通信/通信_鸡蛋_任务系统.as"
    #include "../通信/通信_aka_Agent联动.as"
};
_root.__boot.f9 = function() {
    打印加载内容("加载佣兵数据……");

    #include "../逻辑系统分区/系统文件/逻辑系统分区_初始化.as"
};
_root.__boot.f10 = function() {
    //#include "../逻辑系统分区/任务系统_兼容.as"
    #include "../逻辑系统分区/佣兵系统_兼容.as"
    //#include "../逻辑系统分区/关卡系统_兼容.as"
    #include "../逻辑系统分区/兵种系统_兼容.as"
    #include "../逻辑系统分区/商城系统_兼容.as"
    #include "../逻辑系统分区/商店系统_兼容.as"
    //#include "../逻辑系统分区/物品系统_兼容.as"
};
_root.__boot.f18 = function() {
    #include "../逻辑系统分区/系统文件/逻辑系统分区_最终化1.as"
};
_root.__boot.f32 = function() {
    打印加载内容("加载逻辑代码……");

    #include "../逻辑系统分区/系统文件/逻辑系统分区_最终化3.as"
};
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
_root.__boot.f37_1 = function() {
    #include "../逻辑/装备函数/通用装备函数.as"
    // ========== 集中管理的import语句 ==========
    // 所有装备函数文件共享的类库引用

    // ========== 装备函数文件include列表 ==========
    #include "../逻辑/装备函数/外观类挂载.as"
    #include "../逻辑/装备函数/红外夜视仪.as"
    #include "../逻辑/装备函数/电感切割刃.as"
    #include "../逻辑/装备函数/炎魔斩new.as"
    #include "../逻辑/装备函数/烬灭裁决.as"
    #include "../逻辑/装备函数/死者之手.as"

    #include "../逻辑/装备函数/双面雷神.as"

    #include "../逻辑/装备函数/雷铁斩斧.as"
    #include "../逻辑/装备函数/牙狼剑.as"
};
_root.__boot.f37_2 = function() {
    #include "../逻辑/装备函数/公社爆燃钻矛.as"

    #include "../逻辑/装备函数/RPG.as"
    #include "../逻辑/装备函数/PF98A.as"
    #include "../逻辑/装备函数/RPG28.as"
    #include "../逻辑/装备函数/RShG4.as"
    #include "../逻辑/装备函数/RShG4Я.as"

    #include "../逻辑/装备函数/光刀狮子.as"
    #include "../逻辑/装备函数/光斧金牛.as"
    #include "../逻辑/装备函数/光剑天秤.as"
    #include "../逻辑/装备函数/光刃摩羯.as"

    #include "../逻辑/装备函数/斩马刀.as"
};
_root.__boot.f37_3 = function() {
    #include "../逻辑/装备函数/烈焰斩马刀.as"

    #include "../逻辑/装备函数/键盘镰刀.as"
};
_root.__boot.f37_4 = function() {
    #include "../逻辑/装备函数/吉他喷火.as"
};
_root.__boot.f37_5 = function() {
    #include "../逻辑/装备函数/主唱光剑.as"
    #include "../逻辑/装备函数/火药燃气液压打桩机.as"
    #include "../逻辑/装备函数/刀口触发特效.as"
    #include "../逻辑/装备函数/XM25.as"
    #include "../逻辑/装备函数/XM556_Microgun.as"
    #include "../逻辑/装备函数/XM556-OC-Overlord.as"
    #include "../逻辑/装备函数/XM556_H_Stinger.as"
    #include "../逻辑/装备函数/NEGEV.as"
    #include "../逻辑/装备函数/M249.as"
    #include "../逻辑/装备函数/Jackhammer.as"
    #include "../逻辑/装备函数/G11.as"
    #include "../逻辑/装备函数/G111.as"
};
_root.__boot.f37_6 = function() {
    #include "../逻辑/装备函数/G1111.as"
    #include "../逻辑/装备函数/XM214-CageFrame.as"
    #include "../逻辑/装备函数/M134.as"
    #include "../逻辑/装备函数/M134暴力版.as"
    #include "../逻辑/装备函数/wa90变形款.as"
    #include "../逻辑/装备函数/镜之虎彻.as"
    #include "../逻辑/装备函数/铁枪.as"
    #include "../逻辑/装备函数/黑铁的剑.as"
    #include "../逻辑/装备函数/僵尸割草机.as"
    #include "../逻辑/装备函数/混凝土切割机.as"
    #include "../逻辑/装备函数/MACSIII.as"
};
_root.__boot.f37_7 = function() {
    #include "../逻辑/装备函数/等离子切割机.as"
    #include "../逻辑/装备函数/杀戮风暴.as"
    #include "../逻辑/装备函数/Six12_Matryoshka.as"

    #include "../逻辑/装备函数/P90.as"
    #include "../逻辑/装备函数/AR57.as"

    #include "../逻辑/装备函数/GM6_LYNX.as"

    #include "../逻辑/装备函数/Mark3.as"
    #include "../逻辑/装备函数/毒液蜘蛛侠.as"
    #include "../逻辑/装备函数/贯空天盖手套.as"

    #include "../逻辑/装备函数/喷气背包.as"

    #include "../逻辑/装备函数/剑圣胸甲.as"
    #include "../逻辑/装备函数/剑圣头部装甲.as"
};
_root.__boot.f37_8 = function() {
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
};
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
_root.__boot.f40 = function() {
    #include "../逻辑/战斗系统/战斗系统_aka_特殊闪避计算函数.as"
    #include "../逻辑/战斗系统/战斗系统_fs_lsy_aka_重写子弹生成逻辑.as"
    #include "../逻辑/战斗系统/战斗系统_fs_冲击力系统.as"
    #include "../逻辑/战斗系统/战斗系统_fs_减伤系统.as"
    #include "../逻辑/战斗系统/战斗系统_fs_联弹管理.as"
    #include "../逻辑/战斗系统/战斗系统_lsy_消弹判定.as"
};
_root.__boot.f41_1 = function() {
    #include "../展现/UI交互/UI交互_fs_按键设定.as"
    #include "../展现/UI交互/UI交互_fs_个人信息.as"
    #include "../展现/UI交互/UI交互_fs_玩家信息界面.as"
    #include "../展现/UI交互/UI交互_fs_经济面板.as"
    #include "../展现/UI交互/UI交互_lsy_UI管理.as"
    #include "../展现/UI交互/UI交互_lsy_对话文本.as"
    #include "../逻辑系统分区/商城系统_WebView.as"
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
    #include "../展现/UI交互/UI交互_lsy_任务栏UI.as"
    #include "../展现/UI交互/UI交互_lsy_对话框UI.as"
    #include "../展现/UI交互/UI交互_lsy_佣兵系统UI.as"
    #include "../展现/UI交互/UI交互_鸡蛋_fs_aka_物品图标注释.as"
    #include "../展现/UI交互/UI交互_无名氏_改造系统.as"
    #include "../展现/UI交互/UI交互_aka_健身房训练.as"
};
_root.__boot.f42 = function() {
    #include "../展现/视觉系统/视觉系统_fs_打击数字池.as"
    #include "../展现/视觉系统/视觉系统_fs_画面效果控制生成.as"
    #include "../展现/视觉系统/视觉系统_fs_天气系统.as"
    #include "../展现/视觉系统/视觉系统_fs_绘图处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_效果处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_光照处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_刀光处理引擎.as"
    #include "../展现/视觉系统/视觉系统_fs_显示列表引擎.as"
};

// === loader-fire 函数（import 已提升至联合头） ===
_root.__boot.f53 = function() {
    _root.加载并配置子弹映射("data/items/bullets_cases.xml");
};
_root.__boot.f54 = function() {
    _root.加载并配置发型库("data/items/hairstyle.xml");
};
_root.__boot.f55 = function() {
    _root.色彩引擎.加载并配置色彩预设("data/environment/color_engine_preset.xml");
};
_root.__boot.f56 = function() {
    _root.加载并配置宠物信息("data/merc/pets.xml");
};
_root.__boot.f58 = function() {
    org.flashNight.gesh.xml.LoadXml.SkillDataLoader.getInstance().load(null, null);
};
_root.__boot.f59 = function() {
    _root.加载过场背景与文本("data/stages/loading_data.xml");
};
_root.__boot.f62 = function() {
    打印加载内容("加载物品数据……");

    // 获取 ItemDataLoader 实例
    var ItemDataLoader:ItemDataLoader = ItemDataLoader.getInstance();

    // 加载物品数据
    ItemDataLoader.loadItemData(
        function(combinedData:Object):Void {
            trace("主程序：物品数据加载成功！");
            _root.发布消息("物品数据加载完毕");
            org.flashNight.arki.item.ItemUtil.loadItemData(combinedData);
        },
        function():Void {
            trace("主程序：物品数据加载失败！");
        }
    );
};
_root.__boot.f63 = function() {
    //import org.flashNight.gesh.object.ObjectUtil;

    // 获取 EnemyPropertiesLoader 实例
    var enemyPropertiesLoader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();

    // 加载敌人属性数据
    enemyPropertiesLoader.loadEnemyProperties(
        function(combinedData:Object):Void {
            trace("主程序：敌人属性数据加载成功！");
            _root.发布消息("敌人属性数据加载完毕");
            //trace("合并后的数据: " + ObjectUtil.toString(combinedData));
            // 在此处处理合并后的敌人属性数据
            _root.敌人属性表 = combinedData;
        },
        function():Void {
            trace("主程序：敌人属性数据加载失败！");
        }
    );
};
_root.__boot.f64 = function() {
    // 加载主角称号配置
    HeroUtil.loadHeroConfig(
        function():Void {
            trace("主程序：主角称号配置加载成功！");
            _root.发布消息("主角称号配置加载完毕");
        },
        function():Void {
            trace("主程序：主角称号配置加载失败，使用默认配置！");
        }
    );

    var 材料大全loader:MaterialDictionaryLoader = MaterialDictionaryLoader.getInstance();

    材料大全loader.loadMaterialDictionary(
        function(data:Object):Void {
            trace("主程序：材料大全数据加载成功！");
            _root.发布消息("材料数据加载完毕");
            if(!_root.图鉴信息) _root.图鉴信息 = new Object();
            _root.图鉴信息.材料大全 = data.Material;
        },
        function():Void {
            trace("主程序：材料大全数据加载失败！");
        }
    );

    // ── 地图面板配置 ──（拓扑收束后，2026-06）
    //   两路独立填充 + 一路依赖链：
    //   A) AvatarVisibility ← data/map/map_panel.xml (MapAvatarVisibilityLoader async)
    //        瘦身后 map_panel.xml 只剩 <avatar_visibility>；失败/缺失 = 空表（默认全可见），仅影响头像门控，不阻塞。
    //   B) Catalog (groups/hotspots) ← DataQueryService("map_catalog") async
    //        真相源 = launcher/web/modules/map-panel-data.js，build.ps1 Step 1c 派生为 data/map/map_catalog.json。
    //        **Catalog 是导航权威：query/结构校验任一失败 = 硬报错 + 地图面板不可用，绝不静默降级。**
    //   C) Registry (task_npcs + aliases) ← DataQueryService("task_npc_registry") async
    //        真相源同上，build.ps1 Step 1b 派生为 data/map/task_npc_registry.json。
    //        依赖 Catalog.HOTSPOT_PAGES → 必须在 Catalog ready 之后（嵌在 B 成功回调内）。
    //        失败语义：静默降级（任务红点列表为空），不阻塞游戏进入；错误走 _root.服务器.发布服务器消息 留痕。

    // A) 头像可见性（独立、可降级）
    var mapAvatarLoader:MapAvatarVisibilityLoader = MapAvatarVisibilityLoader.getInstance();
    mapAvatarLoader.load(
        function(data:Object):Void {
            if (!MapPanelCatalog.applyAvatarVisibilityFromXml(data)) {
                trace("主程序：地图头像可见性解析失败，降级为默认全可见。");
            } else {
                trace("主程序：地图头像可见性加载成功。");
            }
        },
        function():Void {
            // 加载失败 = 空表 = 默认全可见，不阻塞
            trace("主程序：地图头像可见性文件加载失败，降级为默认全可见。");
        }
    );

    // B) 导航拓扑 Catalog（导航权威、失败硬报错）→ C) 任务 NPC 注册表（依赖 Catalog）
    //   ⚠ 时序：catalog 现经 socket（DataQueryService）取，而非旧版本的本地文件（MapPanelLoader）。
    //   sendTaskWithCallback 在 socket 未连接时**立即**回 {success:false,error:"socket not connected"}（不排队）。
    //   本 boot 帧在 socket 建连之前就可能执行 → 必须先等 socket 就绪再发 query，否则 catalog 空 →
    //   地图只剩 base 页（旧版 task_npc_registry 之所以没踩雷，是因为它嵌在 MapPanelLoader 文件加载回调里，
    //   文件加载的异步延迟恰好把 socket 等到了 connected——文件源没了这层缓冲就暴露出来）。
    var doMapCatalogQuery:Function = function():Void {
        DataQueryService.query("map_catalog", null, function(resp:Object):Void {
            if (resp == null || !resp.success) {
                var errMsg:String = (resp != null && resp.error != undefined) ? String(resp.error) : "no response";
                trace("主程序：map_catalog query 失败，地图面板不可用: " + errMsg);
                _root.发布消息("[错误] 地图配置加载失败，地图面板不可用: " + errMsg);
                if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                    _root.服务器.发布服务器消息("[MapPanelCatalog] map_catalog query 失败: " + errMsg);
                }
                return;
            }
            if (!MapPanelCatalog.applyFromCatalogJson(resp.result)) {
                trace("主程序：map_catalog 结构不合法，地图面板不可用。");
                _root.发布消息("[错误] 地图配置结构不合法，地图面板不可用");
                if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                    _root.服务器.发布服务器消息("[MapPanelCatalog] applyFromCatalogJson 校验失败（详情见上方留痕）");
                }
                return;
            }
            trace("主程序：地图面板 Catalog 加载成功，发起 task_npc_registry query…");
            DataQueryService.query("task_npc_registry", null, function(resp2:Object):Void {
                if (resp2 == null || !resp2.success) {
                    var errMsg2:String = (resp2 != null && resp2.error != undefined) ? String(resp2.error) : "no response";
                    if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                        _root.服务器.发布服务器消息("[MapTaskNpcRegistry] query 失败: " + errMsg2);
                    }
                    return;
                }
                if (!MapTaskNpcRegistry.applyFromQuery(resp2.result)) {
                    if (_root.服务器 != undefined && _root.服务器.发布服务器消息 != undefined) {
                        _root.服务器.发布服务器消息("[MapTaskNpcRegistry] applyFromQuery 校验失败（详情见上方留痕）");
                    }
                    return;
                }
                trace("主程序：地图任务 NPC 注册表加载完毕");
                _root.发布消息("地图配置加载完毕");
            });
        });
    };

    // socket 就绪即查；未就绪则等待（最多 ~10s），到点仍未就绪也发 query 让其走正常失败报错路径。
    // ⚠ 生命周期：本帧（asLoader 帧 64）在帧 91 会 this.removeMovieClip() 自卸载。绝不能在这里用
    //   setInterval + 帧本地闭包轮询——闭包捕获的帧本地变量随时间轴销毁，interval 泄漏且永不触发 query
    //   （静默击穿 catalog 的“硬报错”设计）。改用 DataQueryService.whenAvailable：tick clip 挂 _root、
    //   等待状态在方法 activation 内，asLoader 卸载后等待门与回调仍存活。详见 DataQueryService.whenAvailable。
    DataQueryService.whenAvailable(10000, doMapCatalogQuery);
};
_root.__boot.f65 = function() {
    var 情报信息loader:InformationDictionaryLoader = InformationDictionaryLoader.getInstance();

    情报信息loader.loadInformationDictionary(
        function(data:Object):Void {
            trace("主程序：情报信息数据加载成功！");
            _root.发布消息("情报数据加载完毕");
            if(!_root.图鉴信息) _root.图鉴信息 = new Object();
            _root.图鉴信息.情报信息 = new Object();
            _root.图鉴信息.情报显示位置表 = new Object();
            for(var i = 0; i < data.Item.length; i++){
                var item = data.Item[i];
                var info = item.Information;
                if(isNaN(info.length)){
                    item.Information = [info];
                }
                _root.图鉴信息.情报信息[item.Name] = item;
                _root.图鉴信息.情报显示位置表[item.Index] = item.Name;
            }
        },
        function():Void {
            trace("主程序：情报信息数据加载失败！");
        }
    );
};
_root.__boot.f66 = function() {
    // 获取 StageInfoLoader 实例
    var StageInfoLoader:StageInfoLoader = StageInfoLoader.getInstance();

    // 加载关卡信息
    StageInfoLoader.loadStageInfo(
        function(combinedData:Object):Void {
            trace("主程序：关卡信息加载成功！");
            _root.发布消息("关卡信息加载完毕");
            _root.StageInfoDict = combinedData;
        },
        function():Void {
            trace("主程序：关卡信息加载失败！");
        }
    );
};
_root.__boot.f67 = function() {
    var stage_env_loader:StageEnvironmentLoader = StageEnvironmentLoader.getInstance();

    stage_env_loader.loadStageEnvironment(
        function(data:Object):Void {
            trace("主程序：关卡环境数据加载成功！");
            _root.配置关卡环境数据(data);
        },
        function():Void {
            trace("主程序：关卡环境数据加载失败！");
        }
    );
};
_root.__boot.f68 = function() {
    var scene_env_loader:SceneEnvironmentLoader = SceneEnvironmentLoader.getInstance();

    scene_env_loader.loadSceneEnvironment(
        function(data:Object):Void {
            trace("主程序：场景环境数据加载成功！");
            _root.配置场景环境数据(data);
        },
        function():Void {
            trace("主程序：场景环境数据加载失败！");
        }
    );
};
_root.__boot.f69 = function() {
    打印加载内容("加载基建数据……");

    var infra_loader = org.flashNight.gesh.xml.LoadXml.InfrastructureLoader.getInstance();

    infra_loader.loadInfrastructure(
        function(data:Object):Void {
            trace("主程序：基建项目数据加载成功！");
            var infrastructureDict = {};
            var infrastructureList = data.Infrastructure;
            for(var i=0; i<data.Infrastructure.length; i++){
                var project = infrastructureList[i];
                if(project.Level != null){
                    project.Level = org.flashNight.gesh.object.ObjectUtil.toArray(project.Level);
                    for(var j = 0; j < project.Level.length; j++){
                        var lvl = project.Level[j];
                        if(isNaN(lvl.Price)) lvl.Price = 0;
                        if(lvl.Material != null){
                            lvl.Material = org.flashNight.gesh.object.ObjectUtil.toArray(lvl.Material);
                        }
                        if(lvl.Skill != null){
                            lvl.Skill = org.flashNight.gesh.object.ObjectUtil.toArray(lvl.Skill);
                        }
                    }
                }
                infrastructureDict[project.Name] = project;
            }
            if(_root.基建系统 == null) _root.基建系统 = new Object();
            _root.基建系统.dict = infrastructureDict;
            _root.基建系统.nameList = infrastructureList;
        },
        function():Void {
            trace("主程序：基建项目数据加载失败！");
        }
    );
};
_root.__boot.f70 = function() {
    var equipconfig_loader = org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader.getInstance();

    equipconfig_loader.loadEquipmentConfig(
        function(data:Object):Void {
            trace("主程序：装备配置数据加载成功！");
            org.flashNight.arki.item.EquipmentUtil.loadEquipmentConfig(data);
        },
        function():Void {
            trace("主程序：装备配置数据加载失败，使用默认值！");
        }
    );

    // 插件数据
    var moddata_loader = org.flashNight.gesh.xml.LoadXml.EquipModListLoader.getInstance();

    moddata_loader.loadModData(
        function(data:Object):Void {
            org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
        },
        function():Void {
        }
    );
};
_root.__boot.f74 = function() {
    var npcskillloader = org.flashNight.gesh.json.LoadJson.NPCSkillLoader.getInstance();
    npcskillloader.loadNPCSkills(
        function(data:Object):Void {
            trace("主程序：NPC技能数据加载成功！");
            _root.NPC技能表 = data;
        },
        function():Void {
            trace("主程序：NPC技能数据加载失败！");
        }
    );
};

// === stage 分组函数（BootSequencer 按序 + 异步门调度） ===
_root.__boot.s0_init = function() {
    org.flashNight.gesh.init.GlobalInitializer.initialize();   // 原 f1
};
_root.__boot.s1_syncCode = function() {
    _root.__boot.f2(); _root.__boot.f3();                       // 引擎 + 通信(建 _root._bootstrap)
};
_root.__boot.s5_parseTask = function(host) {                    // 原 f7（this→host：rawTaskData 在 BootSequencer.host 上）
    org.flashNight.arki.task.TaskUtil.ParseTaskData(host.rawTaskData, host.rawTextData);
    host.rawTaskData = null;
    host.rawTextData = null;
    var guideLoader = org.flashNight.gesh.json.LoadJson.ProgressGuideLoader.getInstance();
    guideLoader.loadGuideData(
        function(data:Object):Void { org.flashNight.arki.task.TaskUtil.ParseGuideData(data); },
        function():Void {}
    );
};
_root.__boot.s6_pre = function() {
    _root.__boot.f9(); _root.__boot.f10(); _root.__boot.f18();  // 建_root.loaders + 兼容×4 push + 最终化1 跑 preloaders
};
_root.__boot.s6_post = function() {
    _root.__boot.f32();                                          // 最终化3 跑 loaderkillers + 删三队列
};
_root.__boot.s7_syncLogic = function() {
    _root.__boot.f36_1(); _root.__boot.f36_2(); _root.__boot.f36_3(); _root.__boot.f36_4(); _root.__boot.f36_5(); _root.__boot.f36_6(); _root.__boot.f36_7(); _root.__boot.f36_8(); _root.__boot.f36_9(); _root.__boot.f36_10(); _root.__boot.f37_1(); _root.__boot.f37_2(); _root.__boot.f37_3(); _root.__boot.f37_4(); _root.__boot.f37_5(); _root.__boot.f37_6(); _root.__boot.f37_7(); _root.__boot.f37_8(); _root.__boot.f38(); _root.__boot.f39(); _root.__boot.f40(); _root.__boot.f41_1(); _root.__boot.f41_2(); _root.__boot.f41_3(); _root.__boot.f42();   // 单位函数/装备/功能/关卡/战斗/UI交互/视觉
    打印加载内容("加载杂项数据……");                              // 原 f48
    _root.__boot.f53(); _root.__boot.f54(); _root.__boot.f55(); _root.__boot.f56(); _root.__boot.f58(); _root.__boot.f59();   // 子弹/发型/色彩/宠物/技能/过场
};
_root.__boot.s8_fanout = function() {
    _root.__boot.f62(); _root.__boot.f63(); _root.__boot.f64(); _root.__boot.f65(); _root.__boot.f66(); _root.__boot.f67(); _root.__boot.f68(); _root.__boot.f69(); _root.__boot.f70(); _root.__boot.f74();   // fire-and-forget：物品/敌人属性/称号+材料+地图/情报/关卡/环境×2/基建/装备配置/NPC技能
};
_root.__boot.s9_onCrafting = function(data) {                   // 原 f75 cb：建改装清单 + ItemObtainIndex
    var craftingDict = {};
    for (var category in data) {
        var list = data[category];
        for (var i = 0; i < list.length; i++) {
            var item = list[i];
            craftingDict[item.name] = item;
            if (isNaN(item.value)) item.value = 1;
        }
    }
    _root.改装清单 = data;
    _root.改装清单对象 = craftingDict;
    var obtainIndex = org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance();
    obtainIndex.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);
};

// === 启动状态机（tick 挂 _root，自删后回调可达） ===
BootSequencer.run(this);
