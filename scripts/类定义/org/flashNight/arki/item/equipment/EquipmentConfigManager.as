/**
 * EquipmentConfigManager - 装备配置只读管理器
 *
 * 管理所有装备相关的配置数据，提供只读访问接口
 * 从 EquipmentUtil 中提取配置管理职责
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.EquipmentConfigManager {

    // ==================== 配置数据存储 ====================

    // 强化比例数值表
    private static var _levelStatList:Array = [
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

    // 需要保留小数点的属性字典
    private static var _decimalPropDict:Object = {
        weight: 1,
        rout: 1,
        vampirism: 1
    };

    // 进阶名称->进阶数据键字典
    private static var _tierNameToKeyDict:Object = {
        二阶: "data_2",
        三阶: "data_3",
        四阶: "data_4",
        墨冰: "data_ice",
        狱火: "data_fire"
    };

    // 进阶数据键->进阶名称反向字典
    private static var _tierKeyToNameDict:Object = null;

    // 进阶数据键->进阶材料字典
    private static var _tierToMaterialDict:Object = {
        data_2: "二阶复合防御组件",
        data_3: "三阶复合防御组件",
        data_4: "四阶复合防御组件",
        data_ice: "墨冰战术涂料",
        data_fire: "狱火战术涂料"
    };

    // 进阶材料->进阶数据键反向字典
    private static var _materialToTierDict:Object = null;

    // 进阶名称->进阶材料字典
    private static var _tierNameToMaterialDict:Object = null;

    // 进阶材料->进阶名称反向字典
    private static var _tierMaterialToNameDict:Object = null;

    // tierDataList
    private static var _tierDataList:Array = ["data_2", "data_3", "data_4", "data_ice", "data_fire"];

    // 默认进阶数据
    private static var _defaultTierDataDict:Object = {
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

    // 调试模式
    private static var _debugMode:Boolean = false;

    // ==================== 初始化方法 ====================

    /**
     * 加载装备配置数据
     * @param configData 配置数据对象
     */
    public static function loadConfig(configData:Object):Void {
        if (configData == null) {
            if (_debugMode) {
                trace("[EquipmentConfigManager] 配置数据为空！");
            }
            return;
        }

        // 1. 加载 levelStatList
        if (configData.levelStatList != null && configData.levelStatList instanceof Array) {
            _levelStatList = configData.levelStatList;
            if (_debugMode) {
                trace("[EquipmentConfigManager] 成功加载 levelStatList，共 " + _levelStatList.length + " 个等级");
            }
        }

        // 2. 加载 decimalPropDict
        if (configData.decimalPropDict != null) {
            _decimalPropDict = configData.decimalPropDict;
        }

        // 3. 加载 tierNameToKeyDict
        if (configData.tierNameToKeyDict != null) {
            _tierNameToKeyDict = configData.tierNameToKeyDict;
        }

        // 4. 加载 tierToMaterialDict
        if (configData.tierToMaterialDict != null) {
            _tierToMaterialDict = configData.tierToMaterialDict;
        }

        // 5. 加载 defaultTierDataDict
        if (configData.defaultTierDataDict != null) {
            _defaultTierDataDict = configData.defaultTierDataDict;
        }

        // 6. 动态构建 tierDataList
        _tierDataList = [];
        for (var tierKey:String in _tierToMaterialDict) {
            _tierDataList.push(tierKey);
        }

        // 7. 构建反向映射字典
        buildReverseDictionaries();
    }

    /**
     * 构建反向映射字典
     * @private
     */
    private static function buildReverseDictionaries():Void {
        // tierKeyToNameDict: 进阶键 -> 进阶名称
        _tierKeyToNameDict = {};
        for (var tierName:String in _tierNameToKeyDict) {
            var tierKey:String = _tierNameToKeyDict[tierName];
            _tierKeyToNameDict[tierKey] = tierName;
        }

        // materialToTierDict: 进阶材料 -> 进阶键
        _materialToTierDict = {};
        for (var tierKey:String in _tierToMaterialDict) {
            var material:String = _tierToMaterialDict[tierKey];
            _materialToTierDict[material] = tierKey;
        }

        // tierNameToMaterialDict: 进阶名称 -> 进阶材料
        _tierNameToMaterialDict = {};
        for (var tierName:String in _tierNameToKeyDict) {
            var tierKey:String = _tierNameToKeyDict[tierName];
            var material:String = _tierToMaterialDict[tierKey];
            if (material) {
                _tierNameToMaterialDict[tierName] = material;
            }
        }

        // tierMaterialToNameDict: 进阶材料 -> 进阶名称
        _tierMaterialToNameDict = {};
        for (var material:String in _materialToTierDict) {
            var tierKey:String = _materialToTierDict[material];
            var tierName:String = _tierKeyToNameDict[tierKey];
            if (tierName) {
                _tierMaterialToNameDict[material] = tierName;
            }
        }
    }

    // ==================== 只读访问器 ====================

    /**
     * 获取强化等级倍率表
     */
    public static function getLevelStatList():Array {
        return _levelStatList;
    }

    /**
     * 获取指定等级的强化倍率
     */
    public static function getLevelMultiplier(level:Number):Number {
        if (level < 0 || level >= _levelStatList.length) {
            return 1;
        }
        return _levelStatList[level];
    }

    /**
     * 获取最大等级值
     */
    public static function getMaxLevel():Number {
        return _levelStatList.length - 1;
    }

    /**
     * 检查属性是否需要保留小数
     */
    public static function shouldKeepDecimal(prop:String):Boolean {
        return _decimalPropDict[prop] == 1;
    }

    /**
     * 获取小数精度字典
     */
    public static function getDecimalPropDict():Object {
        return _decimalPropDict;
    }

    /**
     * 获取进阶名称到键的映射
     */
    public static function getTierNameToKeyDict():Object {
        return _tierNameToKeyDict;
    }

    /**
     * 根据进阶名称获取进阶键
     */
    public static function getTierKey(tierName:String):String {
        return _tierNameToKeyDict[tierName];
    }

    /**
     * 根据进阶键获取进阶名称
     */
    public static function getTierName(tierKey:String):String {
        return _tierKeyToNameDict[tierKey];
    }

    /**
     * 获取进阶键到材料的映射
     */
    public static function getTierToMaterialDict():Object {
        return _tierToMaterialDict;
    }

    /**
     * 根据进阶键获取材料名称
     */
    public static function getTierMaterial(tierKey:String):String {
        return _tierToMaterialDict[tierKey];
    }

    /**
     * 根据材料名称获取进阶键
     */
    public static function getTierKeyByMaterial(material:String):String {
        return _materialToTierDict[material];
    }

    /**
     * 获取进阶名称到材料的映射
     */
    public static function getTierNameToMaterialDict():Object {
        return _tierNameToMaterialDict;
    }

    /**
     * 根据进阶名称获取材料
     */
    public static function getMaterialByTierName(tierName:String):String {
        return _tierNameToMaterialDict[tierName];
    }

    /**
     * 根据材料获取进阶名称
     */
    public static function getTierNameByMaterial(material:String):String {
        return _tierMaterialToNameDict[material];
    }

    /**
     * 获取所有进阶数据键列表
     */
    public static function getTierDataList():Array {
        return _tierDataList;
    }

    /**
     * 获取默认进阶数据字典
     */
    public static function getDefaultTierDataDict():Object {
        return _defaultTierDataDict;
    }

    /**
     * 获取指定进阶的默认数据
     */
    public static function getDefaultTierData(tierName:String):Object {
        return _defaultTierDataDict[tierName];
    }

    /**
     * 获取完整配置对象（供Calculator使用）
     */
    public static function getFullConfig():Object {
        return {
            levelStatList: _levelStatList,
            decimalPropDict: _decimalPropDict,
            tierNameToKeyDict: _tierNameToKeyDict,
            tierKeyToNameDict: _tierKeyToNameDict,
            tierToMaterialDict: _tierToMaterialDict,
            materialToTierDict: _materialToTierDict,
            tierNameToMaterialDict: _tierNameToMaterialDict,
            tierMaterialToNameDict: _tierMaterialToNameDict,
            tierDataList: _tierDataList,
            defaultTierDataDict: _defaultTierDataDict
        };
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
}