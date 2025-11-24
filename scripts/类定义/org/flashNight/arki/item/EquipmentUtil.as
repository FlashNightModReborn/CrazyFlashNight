import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.*;
import org.flashNight.arki.item.*;
import org.flashNight.arki.item.equipment.*;

/**
 * EquipmentUtil 静态类，存储各种装备数值的计算方法
 *
 * 【重构版本】
 * 此类已重构为薄代理层，实际功能委托给独立的模块：
 * - PropertyOperators: 属性运算
 * - EquipmentCalculator: 数值计算
 * - EquipmentConfigManager: 配置管理
 * - ModRegistry: 配件注册表
 * - TagManager: 标签依赖
 * - TierSystem: 进阶系统
 *
 * 保持原有接口不变，确保向后兼容性
 */
class org.flashNight.arki.item.EquipmentUtil {

    // ==================== 调试模式 ====================

    public static var DEBUG_MODE:Boolean = false;

    private static function debugLog(msg:String):Void {
        if(DEBUG_MODE) {
            _root.服务器.发布服务器消息("[EquipmentUtil] " + msg);
        }
    }

    // ==================== 配置数据代理 ====================

    // 强化比例数值表（代理到 EquipmentConfigManager）
    public static function get levelStatList():Array {
        return EquipmentConfigManager.getLevelStatList();
    }
    public static function set levelStatList(value:Array):Void {
        // 需要重新加载配置
        var config:Object = {levelStatList: value};
        EquipmentConfigManager.loadConfig(config);
    }

    // 获取最大等级值
    public static function getMaxLevel():Number {
        return EquipmentConfigManager.getMaxLevel();
    }

    // 小数精度字典（代理到 EquipmentConfigManager）
    public static function get decimalPropDict():Object {
        return EquipmentConfigManager.getDecimalPropDict();
    }
    public static function set decimalPropDict(value:Object):Void {
        var config:Object = {decimalPropDict: value};
        EquipmentConfigManager.loadConfig(config);
        // 同时更新 PropertyOperators
        PropertyOperators.setDecimalPropDict(value);
    }

    // 进阶名称->进阶数据键字典
    public static function get tierNameToKeyDict():Object {
        return EquipmentConfigManager.getTierNameToKeyDict();
    }
    public static function set tierNameToKeyDict(value:Object):Void {
        var config:Object = {tierNameToKeyDict: value};
        EquipmentConfigManager.loadConfig(config);
    }

    // 进阶数据键->进阶名称反向字典
    public static function get tierKeyToNameDict():Object {
        var dict:Object = {};
        var nameToKey:Object = EquipmentConfigManager.getTierNameToKeyDict();
        for(var name:String in nameToKey) {
            dict[nameToKey[name]] = name;
        }
        return dict;
    }

    // 进阶数据键->进阶材料字典
    public static function get tierToMaterialDict():Object {
        return EquipmentConfigManager.getTierToMaterialDict();
    }
    public static function set tierToMaterialDict(value:Object):Void {
        var config:Object = {tierToMaterialDict: value};
        EquipmentConfigManager.loadConfig(config);
    }

    // 进阶材料->进阶数据键反向字典
    public static function get materialToTierDict():Object {
        var dict:Object = {};
        var tierToMat:Object = EquipmentConfigManager.getTierToMaterialDict();
        for(var tier:String in tierToMat) {
            dict[tierToMat[tier]] = tier;
        }
        return dict;
    }

    // 进阶名称->进阶材料字典
    public static function get tierNameToMaterialDict():Object {
        return EquipmentConfigManager.getTierNameToMaterialDict();
    }

    // 进阶材料->进阶名称反向字典
    public static function get tierMaterialToNameDict():Object {
        var dict:Object = {};
        var nameToMat:Object = EquipmentConfigManager.getTierNameToMaterialDict();
        for(var name:String in nameToMat) {
            dict[nameToMat[name]] = name;
        }
        return dict;
    }

    // tierDataList
    public static function get tierDataList():Array {
        return EquipmentConfigManager.getTierDataList();
    }

    // 默认进阶数据
    public static function get defaultTierDataDict():Object {
        return EquipmentConfigManager.getDefaultTierDataDict();
    }
    public static function set defaultTierDataDict(value:Object):Void {
        var config:Object = {defaultTierDataDict: value};
        EquipmentConfigManager.loadConfig(config);
    }

    // 属性运算符字典
    public static var propertyOperators:Object = {
        add: addProperty,
        multiply: multiplyProperty,
        override: overrideProperty,
        merge: mergeProperty,
        applyCap: applyCapProperty
    };

    // ==================== 配件数据代理 ====================

    public static function get modDict():Object {
        return ModRegistry.getModDict();
    }

    public static function get modList():Array {
        return ModRegistry.getModList();
    }

    public static function get modUseLists():Object {
        return ModRegistry.getModUseLists();
    }

    public static function get modAvailabilityResults():Object {
        return _modAvailabilityResults;
    }

    // 保留原有的可用性结果（兼容性）
    private static var _modAvailabilityResults:Object = initializeModAvailabilityResultsStatic();

    // ==================== 初始化方法 ====================

    /**
     * 加载装备配置数据
     */
    public static function loadEquipmentConfig(configData:Object):Void {
        debugLog("加载装备配置数据...");

        // 委托给 EquipmentConfigManager
        EquipmentConfigManager.loadConfig(configData);

        // 同步调试模式
        EquipmentConfigManager.setDebugMode(DEBUG_MODE);

        // 更新 PropertyOperators 的小数精度配置
        if(configData.decimalPropDict) {
            PropertyOperators.setDecimalPropDict(configData.decimalPropDict);
        }

        debugLog("装备配置加载完成");
    }

    /**
     * 加载配件数据
     */
    public static function loadModData(modData:Array):Void {
        debugLog("加载配件数据...");

        // 委托给 ModRegistry
        ModRegistry.loadModData(modData);

        // 同步调试模式
        ModRegistry.setDebugMode(DEBUG_MODE);

        // 初始化可用性结果（兼容性）
        initializeModAvailabilityResults();

        debugLog("配件数据加载完成，共 " + modData.length + " 个配件");
    }

    /**
     * 静态初始化配件可用性结果（用于变量初始化）
     * @private
     */
    private static function initializeModAvailabilityResultsStatic():Object {
        var results:Object = {};
        results[1] = "可装备";
        results[0] = "配件数据不存在";
        results[-1] = "装备配件槽已满";
        results[-2] = "已装备";
        results[-4] = "配件无法覆盖装备原本的主动战技";
        results[-8] = "同位置插件已装备";
        results[-16] = "缺少前置结构支持";
        results[-32] = "有其他插件依赖此插件";
        results[-64] = "该装备禁止安装此挂点类型的插件";
        return results;
    }

    /**
     * 初始化配件可用性结果描述
     */
    public static function initializeModAvailabilityResults():Void {
        _modAvailabilityResults = initializeModAvailabilityResultsStatic();
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

        // 获取基础可用列表
        var useList:Array = ModRegistry.getModsByUseType(rawItemData.use);
        if(!useList || useList.length == 0) return [];

        // 收集所有已授予的武器类型
        var grantedTypes:Object = {};
        if(rawItemData.weapontype) {
            grantedTypes[rawItemData.weapontype] = true;
        }

        // 添加配件授予的武器类型
        for(var i:Number = 0; i < mods.length; i++) {
            var installedMod:Object = ModRegistry.getModData(mods[i]);
            if(installedMod && installedMod.grantsWeapontypeDict) {
                for(var grantedType:String in installedMod.grantsWeapontypeDict) {
                    grantedTypes[grantedType] = true;
                }
            }
        }

        // 检查每个配件的武器类型要求
        for(var j:Number = 0; j < useList.length; j++) {
            var modName:String = useList[j];
            var modData:Object = ModRegistry.getModData(modName);
            if(!modData) continue;

            var weapontypeDict:Object = modData.weapontypeDict;
            if(!weapontypeDict) {
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
     */
    public static function calculateData(item:BaseItem, itemData:Object):Void {
        debugLog("开始计算装备数据: " + item.name);

        var value:Object = item.value;
        var config:Object = EquipmentConfigManager.getFullConfig();
        var modDict:Object = ModRegistry.getModDict();

        // 先应用进阶数据
        if(value.tier) {
            TierSystem.applyTierData(itemData, value.tier);
        }

        // 使用 EquipmentCalculator 进行计算
        EquipmentCalculator.calculate(itemData, value, config, modDict);

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