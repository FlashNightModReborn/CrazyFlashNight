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

        // 1. 加载 levelStatList
        if(configData.levelStatList && configData.levelStatList instanceof Array) {
            levelStatList = configData.levelStatList;
            debugLog("加载了 levelStatList，共 " + levelStatList.length + " 个等级");
        }

        // 2. 加载 decimalPropDict
        if(configData.decimalPropDict) {
            decimalPropDict = configData.decimalPropDict;
            // 同步更新 PropertyOperators
            PropertyOperators.setDecimalPropDict(decimalPropDict);
            debugLog("加载了 decimalPropDict");
        }

        // 3. 加载 tierNameToKeyDict 并构建反向字典
        if(configData.tierNameToKeyDict) {
            tierNameToKeyDict = configData.tierNameToKeyDict;
            // 构建反向字典
            tierKeyToNameDict = {};
            for(var name:String in tierNameToKeyDict) {
                tierKeyToNameDict[tierNameToKeyDict[name]] = name;
            }
            debugLog("加载了 tierNameToKeyDict 和构建了反向字典");
        }

        // 4. 加载 tierToMaterialDict 并构建反向字典
        if(configData.tierToMaterialDict) {
            tierToMaterialDict = configData.tierToMaterialDict;

            // 构建反向字典
            materialToTierDict = {};
            for(var tierKey:String in tierToMaterialDict) {
                materialToTierDict[tierToMaterialDict[tierKey]] = tierKey;
            }

            // 从 tierToMaterialDict 动态构建 tierDataList
            tierDataList = [];
            for(var key:String in tierToMaterialDict) {
                tierDataList.push(key);
            }

            debugLog("加载了 tierToMaterialDict，构建了反向字典和 tierDataList");
        }

        // 5. 构建 tierNameToMaterialDict 和 tierMaterialToNameDict
        if(tierNameToKeyDict && tierToMaterialDict) {
            tierNameToMaterialDict = {};
            tierMaterialToNameDict = {};

            for(var tierName:String in tierNameToKeyDict) {
                var dataKey:String = tierNameToKeyDict[tierName];
                var material:String = tierToMaterialDict[dataKey];
                if(material) {
                    tierNameToMaterialDict[tierName] = material;
                    tierMaterialToNameDict[material] = tierName;
                }
            }

            debugLog("构建了 tierNameToMaterialDict 和 tierMaterialToNameDict");
        }

        // 6. 加载 defaultTierDataDict
        if(configData.defaultTierDataDict) {
            defaultTierDataDict = configData.defaultTierDataDict;
            debugLog("加载了 defaultTierDataDict");
        }

        // 同时更新 EquipmentConfigManager（保持兼容性）
        EquipmentConfigManager.loadConfig(configData);
        EquipmentConfigManager.setDebugMode(DEBUG_MODE);

        debugLog("装备配置加载完成");
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

        // 初始化数据结构
        modDict = {};
        modList = [];
        modUseLists = {
            头部装备: [],
            上装装备: [],
            手部装备: [],
            下装装备: [],
            脚部装备: [],
            颈部装备: [],
            长枪: [],
            手枪: [],
            刀: []
        };

        // 处理每个配件数据
        for(var i:Number = 0; i < modData.length; i++){
            var mod:Object = modData[i];
            if(!mod || !mod.name) continue;

            var name:String = mod.name;

            // 1. 处理use列表（装备类型）
            if(mod.use){
                var useArr:Array = mod.use.split(",");
                for(var useIndex:Number = 0; useIndex < useArr.length; useIndex++){
                    var useKey:String = StringUtils.trim(useArr[useIndex]);
                    if(modUseLists[useKey]){
                        modUseLists[useKey].push(name);
                    }
                }
            }

            // 2. 处理weapontype（武器类型限制）
            if(mod.weapontype){
                var typeArr:Array = mod.weapontype.split(",");
                if(typeArr.length > 0){
                    var wdict:Object = {};
                    for(var typeIndex:Number = 0; typeIndex < typeArr.length; typeIndex++){
                        wdict[StringUtils.trim(typeArr[typeIndex])] = true;
                    }
                    mod.weapontypeDict = wdict;
                }
            }

            // 3. 处理grantsWeapontype（授予的武器类型）
            if(mod.grantsWeapontype){
                var grantsArr:Array = mod.grantsWeapontype.split(",");
                if(grantsArr.length > 0){
                    var grantDict:Object = {};
                    for(var grantIndex:Number = 0; grantIndex < grantsArr.length; grantIndex++){
                        grantDict[StringUtils.trim(grantsArr[grantIndex])] = true;
                    }
                    mod.grantsWeapontypeDict = grantDict;
                }
            }

            // 4. 处理detachPolicy（拆卸策略）
            if(!mod.detachPolicy){
                mod.detachPolicy = "single";
            }

            // 5. 处理tag（互斥标签）
            if(mod.tag){
                mod.tagValue = mod.tag;
            }

            // 6. 处理provideTags（提供的结构标签）
            if(mod.provideTags){
                var provideArr:Array = mod.provideTags.split(",");
                if(provideArr.length > 0){
                    var provideDict:Object = {};
                    for(var provideIndex:Number = 0; provideIndex < provideArr.length; provideIndex++){
                        var trimmedTag:String = StringUtils.trim(provideArr[provideIndex]);
                        if(trimmedTag.length > 0){
                            provideDict[trimmedTag] = true;
                        }
                    }
                    mod.provideTagDict = provideDict;
                }
            }

            // 7. 处理requireTags（安装前置要求）
            if(mod.requireTags){
                var requireArr:Array = mod.requireTags.split(",");
                if(requireArr.length > 0){
                    var requireDict:Object = {};
                    for(var requireIndex:Number = 0; requireIndex < requireArr.length; requireIndex++){
                        var trimmedReq:String = StringUtils.trim(requireArr[requireIndex]);
                        if(trimmedReq.length > 0){
                            requireDict[trimmedReq] = true;
                        }
                    }
                    mod.requireTagDict = requireDict;
                }
            }

            // 8. 归一化percentage（百分比值）
            if(!mod._percentageNormalized){
                var percentage:Object = mod.stats ? mod.stats.percentage : null;
                if(percentage){
                    for(var key:String in percentage){
                        percentage[key] *= 0.01;
                    }
                    mod._percentageNormalized = true;
                }
            }

            // 9. 归一化multiplier（独立乘区）
            if(!mod._multiplierNormalized){
                var multiplier:Object = mod.stats ? mod.stats.multiplier : null;
                if(multiplier){
                    for(var mkey:String in multiplier){
                        multiplier[mkey] *= 0.01;
                    }
                    mod._multiplierNormalized = true;
                }
            }

            // 添加到字典和列表
            modList.push(name);
            modDict[name] = mod;
        }

        // 同时更新 ModRegistry（保持兼容性）
        ModRegistry.loadModData(modData);
        ModRegistry.setDebugMode(DEBUG_MODE);

        // 初始化可用性结果
        initializeModAvailabilityResults();

        debugLog("配件数据加载完成，共 " + modList.length + " 个配件");
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
        for(var j:Number = 0; j < useList.length; j++) {
            var modName:String = useList[j];
            var modData:Object = modDict[modName];
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