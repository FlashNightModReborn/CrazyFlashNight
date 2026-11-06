// asLoader 定义分段（由 tools/assemble-collapsed-frame.js 生成，勿手改）
// asLoader boot 定义母版（由 tools/assemble-collapsed-frame.js 生成；XFL 消费同源分段，勿手改本文件——改组装器重生成）。
// ▶ 架构导览 + 反直觉点 + 待测项：docs/asLoader-README.md（接手测试先读此文件）。
// 联合头 82 包 + 具体类 9 | live sources 29 | generated stages 6 | BootSequencer.run
// S0/S5/S9 业务、异步/控制行为与 f48 进度文案由 BootSequencer.as 编排。
this._lockroot = false;
this.stop();

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
    #include "../逻辑系统分区/经脉系统_WebView.as"
    #include "../展现/UI交互/UI交互_lsy_鼠标代理.as"
};
_root.__boot.f41_2 = function() {
    #include "../展现/UI交互/UI交互_lsy_物品栏UI.as"
};
_root.__boot.f41_3 = function() {
};
_root.__boot.f41_4 = function() {
    #include "../展现/UI交互/UI交互_lsy_任务栏UI.as"
    #include "../展现/UI交互/UI交互_lsy_对话框UI.as"
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
            if (!(combinedData instanceof Array)) {
                _root.__boot.itemDataFailed = true;
                return;
            }
            trace("主程序：物品数据加载成功！");
            _root.发布消息("物品数据加载完毕");
            // equipment-config 与 item-data 同属 S8 并发。先保存 raw payload，
            // 由 BootSequencer 在 config settled 后唯一调用 ItemUtil.loadItemData，
            // 避免 multiTierDict 固化旧 tierDataList。
            _root.__boot.itemDataPayload = combinedData;
            _root.__boot.itemDataLoaded = true;
        },
        function():Void {
            trace("主程序：物品数据加载失败！");
            _root.__boot.itemDataFailed = true;
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
            if (combinedData == null || typeof combinedData != "object") {
                _root.__boot.enemyPropertiesFailed = true;
                return;
            }
            trace("主程序：敌人属性数据加载成功！");
            _root.发布消息("敌人属性数据加载完毕");
            //trace("合并后的数据: " + ObjectUtil.toString(combinedData));
            // 在此处处理合并后的敌人属性数据
            _root.敌人属性表 = combinedData;
            _root.__boot.enemyPropertiesReady = true;
        },
        function():Void {
            trace("主程序：敌人属性数据加载失败！");
            _root.__boot.enemyPropertiesFailed = true;
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
            _root.__boot.legacyMaterialDictionaryReady = true;
        },
        function():Void {
            trace("主程序：材料大全数据加载失败！");
            _root.__boot.legacyMaterialDictionaryFailed = true;
        }
    );

    // 地图静态内容由当前 Host 会话提供，S9 等待明确就绪；不存在第二份 AS2 规则。
    org.flashNight.arki.map.MapDomainBridge.initialize();
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
            if (data == null || typeof data != "object") {
                _root.__boot.equipmentConfigSettled = true;
                return;
            }
            trace("主程序：装备配置数据加载成功！");
            org.flashNight.arki.item.EquipmentUtil.loadEquipmentConfig(data);
            _root.__boot.equipmentConfigSettled = true;
        },
        function():Void {
            trace("主程序：装备配置数据加载失败，使用默认值！");
            // 保持现役 fallback：失败不阻断 boot，但 item projection 必须等到
            // 已明确落入默认配置分支后再执行。
            _root.__boot.equipmentConfigSettled = true;
        }
    );

    // 插件数据
    var moddata_loader = org.flashNight.gesh.xml.LoadXml.EquipModListLoader.getInstance();

        moddata_loader.loadModData(
            function(data:Object):Void {
                if (data == null || !(data.mod instanceof Array)) {
                    _root.__boot.equipmentModFailed = true;
                    return;
                }
                org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
                if (org.flashNight.arki.item.EquipmentUtil.modDict == undefined
                        || !(org.flashNight.arki.item.EquipmentUtil.modList instanceof Array)) {
                    _root.__boot.equipmentModFailed = true;
                    return;
                }
                _root.__boot.equipmentModReady = true;
            },
            function():Void {
                _root.__boot.equipmentModFailed = true;
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

// === 由 BOOT_SOURCES 派生的纯装配 stage（业务条件归 BootSequencer） ===
_root.__boot.s1_syncCode = function() {
    // engine-core (frame2)
    _root.__boot.f2_1();
    _root.__boot.f2_2();
    _root.__boot.f2_3();
    // communication-bootstrap (frame3)
    _root.__boot.f3_1();
    _root.__boot.f3_2();
};
_root.__boot.s6_pre = function() {
    // loader-queue-init (frame9)
    _root.__boot.f9();
    // legacy-system-compatibility (frame10)
    _root.__boot.f10();
    // preloader-fire (frame18)
    _root.__boot.f18();
};
_root.__boot.s6_post = function() {
    // loader-cleanup (frame32)
    _root.__boot.f32();
};
_root.__boot.s7_syncLogic = function() {
    // unit-functions (frame36)
    _root.__boot.f36_1();
    _root.__boot.f36_2();
    _root.__boot.f36_3();
    _root.__boot.f36_4();
    _root.__boot.f36_5();
    _root.__boot.f36_6();
    _root.__boot.f36_7();
    _root.__boot.f36_8();
    _root.__boot.f36_12();
    _root.__boot.f36_13();
    _root.__boot.f36_9();
    _root.__boot.f36_11();
    _root.__boot.f36_10();
    // equipment-functions (frame37)
    _root.__boot.f37_1();
    _root.__boot.f37_2();
    _root.__boot.f37_3();
    _root.__boot.f37_4();
    _root.__boot.f37_5();
    _root.__boot.f37_6();
    _root.__boot.f37_7();
    _root.__boot.f37_8();
    // feature-functions (frame38)
    _root.__boot.f38();
    // stage-functions (frame39)
    _root.__boot.f39_1();
    _root.__boot.f39_2();
    // combat-functions (frame40)
    _root.__boot.f40();
    // ui-interaction (frame41)
    _root.__boot.f41_1();
    _root.__boot.f41_2();
    _root.__boot.f41_3();
    _root.__boot.f41_4();
    // visual-system (frame42)
    _root.__boot.f42();
};
_root.__boot.s7_miscLoaders = function() {
    // bullet-mappings (frame53)
    _root.__boot.f53();
    // hairstyles (frame54)
    _root.__boot.f54();
    // color-presets (frame55)
    _root.__boot.f55();
    // pets (frame56)
    _root.__boot.f56();
    // skill-data (frame58)
    _root.__boot.f58();
    // loading-scenes (frame59)
    _root.__boot.f59();
};
_root.__boot.s8_fanout = function() {
    // item-data (frame62)
    _root.__boot.f62();
    // enemy-properties (frame63)
    _root.__boot.f63();
    // hero-material-map-data (frame64)
    _root.__boot.f64();
    // information-data (frame65)
    _root.__boot.f65();
    // stage-data (frame66)
    _root.__boot.f66();
    // stage-environment (frame67)
    _root.__boot.f67();
    // scene-environment (frame68)
    _root.__boot.f68();
    // infrastructure-data (frame69)
    _root.__boot.f69();
    // equipment-config (frame70)
    _root.__boot.f70();
    // npc-skills (frame74)
    _root.__boot.f74();
};

// === 启动状态机（tick 挂 _root，自删后回调可达） ===
BootSequencer.run(this);
