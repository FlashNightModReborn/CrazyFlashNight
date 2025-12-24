import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.equipment.*;

/**
 * EquipmentUtil - 装备系统兼容层与静态缓存
 *
 * 【架构说明】
 * 此类现在作为"兼容层 + 静态缓存"运作：
 * - 兼容层：保持原有的静态属性接口，确保旧代码无需修改即可运行
 * - 静态缓存：维护配置数据的静态副本，提供快速访问
 *
 * 【实际逻辑分布】
 * 核心业务逻辑已委托给专门的模块（权威实现）：
 * - EquipmentConfigManager: 配置数据的权威管理（等级倍率、进阶配置等）
 * - ModRegistry: 配件注册表的权威管理（配件数据、使用限制等）
 * - TagManager: 标签系统的权威管理（依赖检查、互斥规则等）
 * - EquipmentCalculator: 数值计算的权威实现（属性计算、加成处理等）
 * - PropertyOperators: 属性运算的权威实现（加法、乘法、覆盖等）
 * - TierSystem: 进阶系统的权威实现（进阶材料、进阶逻辑等）
 *
 * 【数据同步策略】
 * - loadEquipmentConfig/loadModData 时同时更新静态缓存和委托模块
 * - 静态属性供旧代码直接访问，委托模块供新功能扩展使用
 * - 反向字典在加载时一次性构建并缓存，避免重复计算
 *
 * @author 原始版本 + 重构优化
 */
class org.flashNight.arki.item.EquipmentUtil {

    // ==================== 调试模式 ====================

    public static var DEBUG_MODE:Boolean = false;

    private static function debugLog(msg:String):Void {
        if(DEBUG_MODE) {
            _root.服务器.发布服务器消息("[EquipmentUtil] " + msg);
        }
    }

    // ==================== 配置数据 ====================

    // 强化比例数值表
    // 原公式为 delta = 1 + 0.01 * (level - 1) * (level + 4)
    // 现在从XML配置文件加载，如果加载失败则使用以下默认值
    public static var levelStatList:Array = [
        1,
        1,    // Lv1
        1.06, // Lv2
        1.14, // Lv3
        1.24, // Lv4
        1.36, // Lv5
        1.5,  // Lv6
        1.66, // Lv7
        1.84, // Lv8
        2.04, // Lv9
        2.26, // Lv10
        2.5,  // Lv11
        2.76, // Lv12
        3.04  // Lv13
    ];

    /**
     * 获取最大等级值（基于levelStatList长度）
     * @return 最大等级值
     */
    public static function getMaxLevel():Number {
        return levelStatList.length - 1;
    }

    // 数值计算中需要保留小数点的属性字典，目前逻辑为在字典中的属性保留1位小数，否则去尾取整
    // 现在从XML配置文件加载，如果加载失败则使用以下默认值
    public static var decimalPropDict:Object = {
        weight: 1,
        rout: 1,
        vampirism: 1
    };

    // 进阶名称->进阶数据键字典
    // 现在从XML配置文件加载，如果加载失败则使用以下默认值
    public static var tierNameToKeyDict:Object = {
        二阶: "data_2",
        三阶: "data_3",
        四阶: "data_4",
        墨冰: "data_ice",
        狱火: "data_fire"
    };

    // 进阶数据键->进阶名称反向字典
    public static var tierKeyToNameDict:Object;

    // 进阶数据键->进阶材料字典
    // 现在从XML配置文件加载，如果加载失败则使用以下默认值
    public static var tierToMaterialDict:Object = {
        data_2: "二阶复合防御组件",
        data_3: "三阶复合防御组件",
        data_4: "四阶复合防御组件",
        data_ice: "墨冰战术涂料",
        data_fire: "狱火战术涂料"
    };

    // 进阶材料->进阶数据键反向字典
    public static var materialToTierDict:Object;

    // 进阶名称->进阶材料字典
    public static var tierNameToMaterialDict:Object;

    // 进阶材料->进阶名称反向字典
    public static var tierMaterialToNameDict:Object;

    // tierDataList 现在通过 tierToMaterialDict 动态构建，不再硬编码
    public static var tierDataList:Array = ["data_2", "data_3", "data_4", "data_ice", "data_fire"];

    // 默认进阶数据
    // 现在从XML配置文件加载，如果加载失败则使用以下默认值
    public static var defaultTierDataDict:Object = {
        二阶: {
            level: 12,
            defence: 80,
            hp: 50,
            mp: 50,
            damage: 15
        },
        三阶: {
            level: 25,
            defence: 180,
            hp: 80,
            mp: 80,
            damage: 35
        },
        四阶: {
            level: 35,
            defence: 255,
            hp: 100,
            mp: 100,
            damage: 60
        }
    };

    // 属性运算符字典
    public static var propertyOperators:Object = {
        add: addProperty,
        multiply: multiplyProperty,
        override: overrideProperty,
        merge: mergeProperty,
        applyCap: applyCapProperty
    };

    // ==================== 配件数据 ====================

    // 配件字典
    public static var modDict:Object;

    // 配件列表
    public static var modList:Array;

    // 配件使用类型列表
    public static var modUseLists:Object;

    // 配件可用性结果描述
    public static var modAvailabilityResults:Object;

    // ==================== 初始化方法 ====================

    /**
     * 加载装备配置数据
     *
     * @param configData 配置数据对象，包含：
     *   - levelStatList: 强化等级倍率数组
     *   - decimalPropDict: 小数精度配置
     *   - tierNameToKeyDict: 进阶名称到键的映射
     *   - tierToMaterialDict: 进阶键到材料的映射
     *   - defaultTierDataDict: 默认进阶数据
     *
     * 注意：此方法是幂等的，可以安全地多次调用
     */
    public static function loadEquipmentConfig(configData:Object):Void {
        if(configData == null) {
            debugLog("loadEquipmentConfig: 配置数据为空！");
            return;
        }

        debugLog("加载装备配置数据...");

        // 【修复】先设置调试模式，确保加载过程中的日志能正确输出
        EquipmentConfigManager.setDebugMode(DEBUG_MODE);

        // 【方案A实施】加载到EquipmentConfigManager（单一真源）
        EquipmentConfigManager.loadConfig(configData);

        // 【方案A实施】从ConfigManager获取引用，而非复制数据
        // 这样EquipmentUtil的静态字段指向ConfigManager中的同一份对象
        levelStatList = EquipmentConfigManager.getLevelStatList();
        decimalPropDict = EquipmentConfigManager.getDecimalPropDict();
        tierNameToKeyDict = EquipmentConfigManager.getTierNameToKeyDict();
        tierToMaterialDict = EquipmentConfigManager.getTierToMaterialDict();
        defaultTierDataDict = EquipmentConfigManager.getDefaultTierDataDict();

        // 获取反向字典（ConfigManager已构建好）
        tierKeyToNameDict = EquipmentConfigManager.getTierKeyToNameDict();
        materialToTierDict = EquipmentConfigManager.getMaterialToTierDict();
        tierNameToMaterialDict = EquipmentConfigManager.getTierNameToMaterialDict();
        tierMaterialToNameDict = EquipmentConfigManager.getTierMaterialToNameDict();
        tierDataList = EquipmentConfigManager.getTierDataList();

        // 同步更新 PropertyOperators（使用共享的引用）
        PropertyOperators.setDecimalPropDict(decimalPropDict);

        debugLog("装备配置加载完成（引用共享模式）");
    }

    /**
     * 加载配件数据
     */
    public static function loadModData(modData:Array):Void {
        if(modData == null){
            debugLog("loadModData: 传入数据为null");
            return;
        }

        if(modData.length <= 0) {
            debugLog("loadModData: 没有配件数据需要加载");
            return;
        }

        debugLog("加载配件数据...");

        // 【修复】先设置调试模式，确保加载过程中的日志能正确输出
        ModRegistry.setDebugMode(DEBUG_MODE);

        // 【方案A实施】加载到ModRegistry（单一真源）
        // ModRegistry会处理所有数据归一化、字典构建、useSwitch处理等
        ModRegistry.loadModData(modData);

        // 【方案A实施】从ModRegistry获取引用，而非复制数据
        // 这样EquipmentUtil的静态字段指向ModRegistry中的同一份对象
        modDict = ModRegistry.getModDict();
        modUseLists = ModRegistry.getModUseLists();
        modList = ModRegistry.getModList();

        // 初始化可用性结果（这个保持本地，因为它是静态描述文本）
        initializeModAvailabilityResults();

        debugLog("配件数据加载完成（引用共享模式），共 " + modList.length + " 个配件");
    }

    /**
     * 初始化配件可用性结果描述
     */
    public static function initializeModAvailabilityResults():Void {
        modAvailabilityResults = {};
        modAvailabilityResults[1] = "可装备";
        modAvailabilityResults[0] = "配件数据不存在";
        modAvailabilityResults[-1] = "装备配件槽已满";
        modAvailabilityResults[-2] = "已装备";
        modAvailabilityResults[-4] = "配件无法覆盖装备原本的主动战技";
        modAvailabilityResults[-8] = "同位置插件已装备";
        modAvailabilityResults[-16] = "缺少前置结构支持";
        modAvailabilityResults[-32] = "有其他插件依赖此插件";
        modAvailabilityResults[-64] = "该装备禁止安装此挂点类型的插件";
        modAvailabilityResults[-128] = "当前弹药与此配件不兼容";
    }

    // ==================== 进阶系统代理 ====================

    /**
     * 获取进阶物品
     */
    public static function getTierItem(tier:String):String {
        return TierSystem.getTierItem(tier);
    }

    /**
     * 查找所有可用的进阶材料
     */
    public static function getAvailableTierMaterials(item:BaseItem):Array {
        return TierSystem.getAvailableTierMaterials(item);
    }

    /**
     * 查找进阶插件是否能合法装备
     */
    public static function isTierMaterialAvailable(item:BaseItem, matName:String):Boolean {
        return TierSystem.isTierMaterialAvailable(item, matName);
    }

    // ==================== 配件系统代理 ====================

    /**
     * 查找所有可用的配件材料
     */
    public static function getAvailableModMaterials(item:BaseItem):Array {
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var list:Array = [];
        var mods:Array = item.value.mods;

        // 获取基础可用列表 - 使用静态属性 modUseLists
        var useList:Array = modUseLists[rawItemData.use];
        if(!useList || useList.length == 0) return [];

        // 收集所有已授予的武器类型
        var grantedTypes:Object = {};
        if(rawItemData.weapontype) {
            grantedTypes[rawItemData.weapontype] = true;
        }

        // 添加配件授予的武器类型 - 使用静态属性 modDict
        for(var i:Number = 0; i < mods.length; i++) {
            var installedMod:Object = modDict[mods[i]];
            if(installedMod && installedMod.grantsWeapontypeDict) {
                for(var grantedType:String in installedMod.grantsWeapontypeDict) {
                    grantedTypes[grantedType] = true;
                }
            }
        }

        // 检查每个配件的武器类型要求 - 使用静态属性 modDict
        // 只对手枪和长枪考虑weapontype限制
        var checkWeaponType:Boolean = (rawItemData.use == "手枪" || rawItemData.use == "长枪");

        for(var j:Number = 0; j < useList.length; j++) {
            var modName:String = useList[j];
            var modData:Object = modDict[modName];
            if(!modData) continue;

            // 如果不是手枪/长枪，跳过weapontype检查
            if(!checkWeaponType) {
                list.push(modName);
                continue;
            }

            // 1. 先检查黑名单（excludeWeapontype）
            var excludeDict:Object = modData.excludeWeapontypeDict;
            if(excludeDict) {
                var isExcluded:Boolean = false;
                for(var excludedType:String in excludeDict) {
                    if(grantedTypes[excludedType]) {
                        isExcluded = true;
                        break;
                    }
                }
                if(isExcluded) continue; // 被排除，跳过此配件
            }

            // 2. 再检查白名单（weapontype）
            var weapontypeDict:Object = modData.weapontypeDict;
            if(!weapontypeDict) {
                // 无白名单限制，且未被黑名单排除，允许
                list.push(modName);
            } else {
                // 检查武器类型匹配
                var canUse:Boolean = false;
                for(var requiredType:String in weapontypeDict) {
                    if(grantedTypes[requiredType]) {
                        canUse = true;
                        break;
                    }
                }
                if(canUse) {
                    list.push(modName);
                }
            }
        }

        // 使用 TagManager 进行进一步过滤
        list = TagManager.filterAvailableMods(list, item, rawItemData);

        return list;
    }

    /**
     * 查找配件插件是否能合法装备
     */
    public static function isModMaterialAvailable(item:BaseItem, itemData:Object, matName:String):Number {
        return TagManager.checkModAvailability(item, itemData, matName);
    }

    /**
     * 获取缺少的tag列表
     */
    public static function getMissingTags(modName:String, item:BaseItem):Array {
        return TagManager.getMissingTags(modName, item);
    }

    /**
     * 获取依赖于指定插件的其他插件
     */
    public static function getDependentMods(item:BaseItem, modNameToRemove:String):Array {
        return TagManager.getDependentMods(item, modNameToRemove);
    }

    /**
     * 检查是否可以安全移除插件
     */
    public static function canRemoveMod(item:BaseItem, modNameToRemove:String):Number {
        return TagManager.canRemoveMod(item, modNameToRemove);
    }

    // ==================== 核心计算代理 ====================

    /**
     * 计算装备经过进阶、强化与配件之后的最终数值
     *
     * 【性能优化 2024-12-25】
     * - 使用 calculateInPlace 替代 calculate，避免冗余克隆
     * - 调用方（BaseItem.getData）通过 ItemUtil.getItemData 获取的数据已经是克隆
     * - 因此这里可以安全地就地修改，节省约48ms/批次的深度克隆开销
     *
     * 注意：EquipmentCalculator.calculateInPlace 内部会处理 tier 应用，
     * 此处不再单独调用 TierSystem.applyTierData，避免重复应用。
     */
    public static function calculateData(item:BaseItem, itemData:Object):Void {
        debugLog("开始计算装备数据: " + item.name);

        var value:Object = item.value;
        var config:Object = EquipmentConfigManager.getFullConfig();
        var modDict:Object = ModRegistry.getModDict();

        // 【优化】使用 calculateInPlace 就地计算，避免二次克隆
        // itemData 已由 ItemUtil.getItemData() 克隆，可安全修改
        EquipmentCalculator.calculateInPlace(itemData, value, config, modDict);

        debugLog("装备数据计算完成");
    }

    // ==================== 属性运算代理 ====================

    /**
     * 输入2个存放装备属性的Object对象，将后者每个属性的值增加到前者
     */
    public static function addProperty(prop:Object, addProp:Object, initValue:Number):Void {
        PropertyOperators.add(prop, addProp, initValue);
    }

    /**
     * 输入2个存放装备属性的Object对象，将后者每个属性的值对前者相乘
     */
    public static function multiplyProperty(prop:Object, multiProp:Object):Void {
        PropertyOperators.multiply(prop, multiProp);
    }

    /**
     * 输入2个存放装备属性的Object对象，将后者的每个属性覆盖前者
     */
    public static function overrideProperty(prop:Object, overProp:Object):Void {
        PropertyOperators.override(prop, overProp);
    }

    /**
     * 深度合并属性对象
     */
    public static function mergeProperty(prop:Object, mergeProp:Object):Void {
        PropertyOperators.merge(prop, mergeProp);
    }

    /**
     * 应用属性上限过滤
     */
    public static function applyCapProperty(prop:Object, capProp:Object, baseProp:Object):Void {
        PropertyOperators.applyCap(prop, capProp, baseProp);
    }

    // ==================== 兼容性方法 ====================

    /**
     * 构建反向映射字典（为了兼容性保留）
     * @private
     */
    private static function buildReverseDictionaries():Void {
        // 这个方法现在由 EquipmentConfigManager 内部处理
        // 保留空实现以确保兼容性
    }

    // ==================== 测试方法 ====================

    /**
     * 运行重构后的测试套件
     */
    public static function runTests():String {
        return EquipmentTestSuite.runAllTests();
    }

    /**
     * 快速测试并输出结果
     */
    public static function quickTest():Void {
        EquipmentTestSuite.quickTest();
    }

    // ==================== 版本信息 ====================

    /**
     * 获取版本信息
     */
    public static function getVersion():String {
        return "2.0.0-refactored";
    }

    /**
     * 获取重构信息
     */
    public static function getRefactoringInfo():String {
        var info:String = "\n===== EquipmentUtil 重构信息 =====\n";
        info += "版本: 2.0.0\n";
        info += "状态: 代理模式\n";
        info += "模块:\n";
        info += "  - PropertyOperators: 属性运算\n";
        info += "  - EquipmentCalculator: 数值计算\n";
        info += "  - EquipmentConfigManager: 配置管理\n";
        info += "  - ModRegistry: 配件注册表\n";
        info += "  - TagManager: 标签依赖\n";
        info += "  - TierSystem: 进阶系统\n";
        info += "优化:\n";
        info += "  - useSwitch: O(n^4) -> O(n)\n";
        info += "  - 职责分离，提高可维护性\n";
        info += "  - 纯函数设计，便于测试\n";
        info += "================================\n";
        return info;
    }
}