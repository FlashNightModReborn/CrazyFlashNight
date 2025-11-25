import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.EquipmentConfigManager;

/**
 * TierSystem - 进阶系统管理器
 *
 * 管理装备的进阶功能，包括：
 * - 进阶材料可用性检查
 * - 进阶数据应用
 * - 进阶材料查询
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.TierSystem {

    // 调试模式
    private static var _debugMode:Boolean = false;

    /**
     * 获取进阶物品名称
     * @param tier 进阶名称
     * @return 进阶材料名称
     */
    public static function getTierItem(tier:String):String {
        var tierKey:String = EquipmentConfigManager.getTierKey(tier);
        return tierKey ? EquipmentConfigManager.getTierMaterial(tierKey) : null;
    }

    /**
     * 查找所有可用的进阶材料
     * @param item 装备物品对象
     * @return 可用的进阶材料名称数组
     */
    public static function getAvailableTierMaterials(item:BaseItem):Array {
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var list:Array = [];
        var tierDataList:Array = EquipmentConfigManager.getTierDataList();

        // 检查装备自身支持的进阶
        for (var i:Number = 0; i < tierDataList.length; i++) {
            var tierKey:String = tierDataList[i];
            if (rawItemData[tierKey]) {
                var material:String = EquipmentConfigManager.getTierMaterial(tierKey);
                if (material) {
                    list.push(material);
                }
            }
        }

        // 如果没有特定进阶，检查是否为低级防具（可使用默认进阶）
        if (list.length === 0) {
            if (isDefaultTierEligible(rawItemData)) {
                // 添加默认的三个进阶
                var data2Mat:String = EquipmentConfigManager.getTierMaterial("data_2");
                var data3Mat:String = EquipmentConfigManager.getTierMaterial("data_3");
                var data4Mat:String = EquipmentConfigManager.getTierMaterial("data_4");

                if (data2Mat) list.push(data2Mat);
                if (data3Mat) list.push(data3Mat);
                if (data4Mat) list.push(data4Mat);
            }
        }

        if (_debugMode) {
            trace("[TierSystem] 装备 '" + item.name + "' 可用进阶材料: " + list.join(", "));
        }

        return list;
    }

    /**
     * 检查进阶材料是否可用
     * @param item 装备物品对象
     * @param matName 进阶材料名称
     * @return true如果可以使用，false否则
     */
    public static function isTierMaterialAvailable(item:BaseItem, matName:String):Boolean {
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var tierKey:String = EquipmentConfigManager.getTierKeyByMaterial(matName);

        if (!tierKey) {
            if (_debugMode) {
                trace("[TierSystem] 材料 '" + matName + "' 没有对应的进阶键");
            }
            return false;
        }

        // 检查装备是否支持该进阶
        if (rawItemData[tierKey]) {
            return true;
        }

        // 检查是否为默认进阶情况
        if (isDefaultTierEligible(rawItemData)) {
            if (tierKey === "data_2" || tierKey === "data_3" || tierKey === "data_4") {
                return true;
            }
        }

        return false;
    }

    /**
     * 应用进阶数据到装备
     *
     * @param itemData 装备数据（会被修改）
     * @param tier 进阶名称
     * @param config 可选的配置对象，包含 tierNameToKeyDict 和 defaultTierDataDict。
     *               如果不传或为 null，则使用 EquipmentConfigManager 的全局配置。
     *               传入自定义 config 可使此方法成为纯函数，不依赖全局状态。
     */
    public static function applyTierData(itemData:Object, tier:String, config:Object):Void {
        if (!tier) return;

        // 如果未提供 config，使用全局配置（向后兼容）
        var tierNameToKeyDict:Object;
        var defaultTierDataDict:Object;

        if (config != null) {
            // 使用传入的配置（纯函数模式）
            tierNameToKeyDict = config.tierNameToKeyDict;
            defaultTierDataDict = config.defaultTierDataDict;
        } else {
            // 使用全局配置（兼容模式）
            tierNameToKeyDict = EquipmentConfigManager.getTierNameToKeyDict();
            defaultTierDataDict = EquipmentConfigManager.getDefaultTierDataDict();
        }

        // 获取进阶键
        var tierKey:String = tierNameToKeyDict ? tierNameToKeyDict[tier] : null;
        if (!tierKey) {
            if (_debugMode) {
                trace("[TierSystem] 进阶 '" + tier + "' 没有对应的键");
            }
            return;
        }

        // 获取进阶数据：优先使用装备自身的进阶数据
        var tierData:Object = itemData[tierKey];
        if (!tierData) {
            // 使用默认进阶数据
            tierData = defaultTierDataDict ? defaultTierDataDict[tier] : null;
            if (_debugMode && tierData) {
                trace("[TierSystem] 使用默认进阶数据: " + tier);
            }
        }

        if (!tierData) {
            if (_debugMode) {
                trace("[TierSystem] 没有找到进阶数据: " + tier);
            }
            return;
        }

        // 应用进阶数据
        applyTierDataToItem(itemData, tierData, tierKey);

        if (_debugMode) {
            trace("[TierSystem] 已应用进阶 '" + tier + "' 到装备");
        }
    }

    /**
     * 实际应用进阶数据
     * @private
     */
    private static function applyTierDataToItem(itemData:Object, tierData:Object, tierKey:String):Void {
        // 覆盖 data 内的属性
        if (itemData.data && tierData) {
            for (var prop:String in tierData) {
                // 跳过非数据属性
                if (prop == "icon" || prop == "displayname" ||
                    prop == "description" || prop == "skill" || prop == "lifecycle") {
                    continue;
                }
                itemData.data[prop] = tierData[prop];
            }
        }

        // 覆盖顶层属性
        if (tierData.icon !== undefined) {
            itemData.icon = tierData.icon;
        }
        if (tierData.displayname !== undefined) {
            itemData.displayname = tierData.displayname;
        }
        if (tierData.description !== undefined) {
            itemData.description = tierData.description;
        }
        if (tierData.skill !== undefined) {
            // 深度克隆skill对象
            itemData.skill = cloneObject(tierData.skill);
        }
        if (tierData.lifecycle !== undefined) {
            itemData.lifecycle = cloneObject(tierData.lifecycle);
        }

        // 清空已使用的进阶数据
        itemData[tierKey] = null;
    }

    /**
     * 检查装备是否符合默认进阶条件
     * @private
     */
    private static function isDefaultTierEligible(itemData:Object):Boolean {
        // 条件：防具类型，非颈部装备，等级小于10
        return (itemData.type === "防具" &&
                itemData.use !== "颈部装备" &&
                itemData.data &&
                itemData.data.level < 10);
    }

    /**
     * 获取进阶后的装备数据预览（不修改原数据）
     * @param item 装备物品对象
     * @param tierName 进阶名称
     * @return 进阶后的数据预览，如果无法进阶返回null
     */
    public static function getTierPreview(item:BaseItem, tierName:String):Object {
        // 检查是否可以进阶
        var material:String = EquipmentConfigManager.getMaterialByTierName(tierName);
        if (!material || !isTierMaterialAvailable(item, material)) {
            return null;
        }

        // 获取原始数据的副本
        var rawItemData:Object = ItemUtil.getRawItemData(item.name);
        var previewData:Object = cloneObject(rawItemData);

        // 应用进阶（使用全局配置）
        applyTierData(previewData, tierName, null);

        return previewData;
    }

    /**
     * 获取所有进阶选项的信息
     * @param item 装备物品对象
     * @return 进阶信息数组，每个元素包含 {name, material, available}
     */
    public static function getAllTierOptions(item:BaseItem):Array {
        var options:Array = [];
        var tierNameToMaterial:Object = EquipmentConfigManager.getTierNameToMaterialDict();

        for (var tierName:String in tierNameToMaterial) {
            var material:String = tierNameToMaterial[tierName];
            var available:Boolean = isTierMaterialAvailable(item, material);

            options.push({
                name: tierName,
                material: material,
                available: available
            });
        }

        return options;
    }

    /**
     * 简单的对象深度克隆（AS2兼容）
     * @private
     */
    private static function cloneObject(obj:Object):Object {
        if (obj == null || typeof(obj) != "object") {
            return obj;
        }

        var clone:Object = {};
        for (var key:String in obj) {
            if (typeof(obj[key]) == "object") {
                clone[key] = cloneObject(obj[key]);
            } else {
                clone[key] = obj[key];
            }
        }
        return clone;
    }

    /**
     * 设置调试模式
     */
    public static function setDebugMode(value:Boolean):Void {
        _debugMode = value;
    }

    /**
     * 获取调试模式状态
     */
    public static function isDebugMode():Boolean {
        return _debugMode;
    }

    // ==================== 测试方法 ====================

    /**
     * 运行进阶系统测试
     */
    public static function runTests():String {
        var result:String = "\n===== TierSystem 测试 =====\n";

        // 测试1：进阶材料查询
        result += testTierMaterialQuery();

        // 测试2：默认进阶条件
        result += testDefaultTierEligibility();

        // 测试3：进阶数据应用
        result += testTierDataApplication();

        return result;
    }

    private static function testTierMaterialQuery():String {
        // 初始化配置
        EquipmentConfigManager.loadConfig({
            tierNameToKeyDict: {二阶: "data_2"},
            tierToMaterialDict: {data_2: "二阶复合防御组件"}
        });

        var material:String = getTierItem("二阶");
        var passed:Boolean = (material == "二阶复合防御组件");

        return passed ? "✓ 进阶材料查询测试通过\n" : "✗ 进阶材料查询测试失败\n";
    }

    private static function testDefaultTierEligibility():String {
        var testData:Object = {
            type: "防具",
            use: "头部装备",
            data: { level: 5 }
        };

        var eligible:Boolean = isDefaultTierEligible(testData);

        return eligible ? "✓ 默认进阶条件测试通过\n" : "✗ 默认进阶条件测试失败\n";
    }

    private static function testTierDataApplication():String {
        var testItemData:Object = {
            data: {
                level: 10,
                defence: 50
            },
            data_2: {
                level: 15,
                defence: 100,
                displayname: "强化装备"
            }
        };

        // 初始化配置
        EquipmentConfigManager.loadConfig({
            tierNameToKeyDict: {二阶: "data_2"}
        });

        applyTierData(testItemData, "二阶", null);

        var passed:Boolean = (
            testItemData.data.level == 15 &&
            testItemData.data.defence == 100 &&
            testItemData.displayname == "强化装备" &&
            testItemData.data_2 == null
        );

        return passed ? "✓ 进阶数据应用测试通过\n" : "✗ 进阶数据应用测试失败\n";
    }
}