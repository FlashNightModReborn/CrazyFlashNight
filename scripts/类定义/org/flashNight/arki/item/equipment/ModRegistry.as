import org.flashNight.gesh.string.StringUtils;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * ModRegistry - 配件注册表管理器
 *
 * 管理所有配件数据，包括加载、归一化和查询
 * 优化了 useSwitch 的性能（O(n^4) -> O(n)）
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.ModRegistry {

    // 配件字典：名称 -> 配件数据
    private static var _modDict:Object = {};

    // 配件名称列表
    private static var _modList:Array = [];

    // 按装备类型分组的配件列表
    private static var _modUseLists:Object = {};

    // 配件可用性结果描述
    private static var _modAvailabilityResults:Object = {};

    // 【方案A实施】displayname反向索引，用于O(1)查找
    // 映射：displayname -> modName
    private static var _displayNameToModName:Object = {};

    // 调试模式
    private static var _debugMode:Boolean = false;

    /**
     * 加载配件数据
     * @param modData 配件数据数组
     */
    public static function loadModData(modData:Array):Void {
        if (!modData || modData.length <= 0) {
            if (_debugMode) {
                trace("[ModRegistry] 没有配件数据需要加载");
            }
            return;
        }

        // 重置数据
        _modDict = {};
        _modList = [];
        _displayNameToModName = {}; // 【方案A实施】重置displayname索引
        _modUseLists = {
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

        // 处理每个配件
        for (var i:Number = 0; i < modData.length; i++) {
            processModData(modData[i]);
        }

        // 初始化可用性结果描述
        initializeAvailabilityResults();

        if (_debugMode) {
            trace("[ModRegistry] 加载完成，共 " + _modList.length + " 个配件");
        }
    }

    /**
     * 处理单个配件数据
     * @private
     */
    private static function processModData(mod:Object):Void {
        if (!mod || !mod.name) return;

        var name:String = mod.name;

        // 1. 处理use列表（装备类型）
        if (mod.use) {
            var useArr:Array = mod.use.split(",");
            for (var useIndex:Number = 0; useIndex < useArr.length; useIndex++) {
                var useKey:String = StringUtils.trim(useArr[useIndex]);
                if (_modUseLists[useKey]) {
                    _modUseLists[useKey].push(name);
                }
            }
        }

        // 2. 处理weapontype（武器类型限制）
        if (mod.weapontype) {
            mod.weapontypeDict = buildDictFromList(mod.weapontype);
        }

        // 3. 处理grantsWeapontype（授予的武器类型）
        if (mod.grantsWeapontype) {
            mod.grantsWeapontypeDict = buildDictFromList(mod.grantsWeapontype);
        }

        // 4. 处理detachPolicy（拆卸策略）
        if (!mod.detachPolicy) {
            mod.detachPolicy = "single";
        }

        // 5. 处理tag（互斥标签）
        if (mod.tag) {
            mod.tagValue = mod.tag;
        }

        // 6. 处理provideTags（提供的结构标签）
        if (mod.provideTags) {
            mod.provideTagDict = buildDictFromList(mod.provideTags);
        }

        // 7. 处理requireTags（安装前置要求）
        if (mod.requireTags) {
            mod.requireTagDict = buildDictFromList(mod.requireTags);
        }

        // 8. 归一化percentage（百分比值）
        normalizePercentage(mod);

        // 9. 归一化multiplier（独立乘区）
        normalizeMultiplier(mod);

        // 10. 处理和优化useSwitch
        processUseSwitch(mod);

        // 添加到注册表
        _modList.push(name);
        _modDict[name] = mod;

        // 【方案A实施】构建displayname反向索引
        // 如果mod有displayname，建立 displayname -> modName 的映射
        if (mod.displayname) {
            _displayNameToModName[mod.displayname] = name;

            if (_debugMode) {
                trace("[ModRegistry] 建立displayname索引: '" + mod.displayname + "' -> '" + name + "'");
            }
        }
    }

    /**
     * 从逗号分隔的字符串构建字典
     * @private
     */
    private static function buildDictFromList(listStr:String):Object {
        var dict:Object = {};
        if (!listStr) return dict;

        var arr:Array = listStr.split(",");
        for (var i:Number = 0; i < arr.length; i++) {
            var trimmed:String = StringUtils.trim(arr[i]);
            if (trimmed.length > 0) {
                dict[trimmed] = true;
            }
        }
        return dict;
    }

    /**
     * 归一化percentage字段（转换为小数）
     * @private
     */
    private static function normalizePercentage(mod:Object):Void {
        if (mod._percentageNormalized) return; // 已处理过

        var percentage:Object = mod.stats ? mod.stats.percentage : null;
        if (percentage) {
            for (var key:String in percentage) {
                percentage[key] *= 0.01;
            }
            mod._percentageNormalized = true;
        }
    }

    /**
     * 归一化multiplier字段（转换为小数）
     * @private
     */
    private static function normalizeMultiplier(mod:Object):Void {
        if (mod._multiplierNormalized) return; // 已处理过

        var multiplier:Object = mod.stats ? mod.stats.multiplier : null;
        if (multiplier) {
            for (var key:String in multiplier) {
                multiplier[key] *= 0.01;
            }
            mod._multiplierNormalized = true;
        }
    }

    /**
     * 处理和优化useSwitch
     * @private
     */
    private static function processUseSwitch(mod:Object):Void {
        if (mod._useSwitchProcessed) return; // 已处理过
        if (!mod.stats || !mod.stats.useSwitch) return;

        var useSwitch:Object = mod.stats.useSwitch;

        // 将use统一转换为数组
        var useCases:Array;
        if (useSwitch.use instanceof Array) {
            useCases = useSwitch.use;
        } else if (useSwitch.use) {
            useCases = [useSwitch.use];
        } else {
            useCases = [];
        }

        // 处理每个use分支
        for (var i:Number = 0; i < useCases.length; i++) {
            var useCase:Object = useCases[i];

            // 归一化percentage字段
            if (useCase.percentage) {
                for (var pKey:String in useCase.percentage) {
                    useCase.percentage[pKey] *= 0.01;
                }
            }

            // 归一化multiplier字段
            if (useCase.multiplier) {
                for (var mKey:String in useCase.multiplier) {
                    useCase.multiplier[mKey] *= 0.01;
                }
            }

            // 为每个useCase预构建查找表（优化性能）
            if (useCase.name) {
                useCase.lookupDict = buildDictFromList(useCase.name);
            }
        }

        // 保存处理后的数组形式
        useSwitch.useCases = useCases;
        mod._useSwitchProcessed = true;
    }

    /**
     * 初始化配件可用性结果描述
     * @private
     */
    private static function initializeAvailabilityResults():Void {
        _modAvailabilityResults = {};
        _modAvailabilityResults[1] = "可装备";
        _modAvailabilityResults[0] = "配件数据不存在";
        _modAvailabilityResults[-1] = "装备配件槽已满";
        _modAvailabilityResults[-2] = "已装备";
        _modAvailabilityResults[-4] = "配件无法覆盖装备原本的主动战技";
        _modAvailabilityResults[-8] = "同位置插件已装备";
        _modAvailabilityResults[-16] = "缺少前置结构支持";
        _modAvailabilityResults[-32] = "有其他插件依赖此插件";
        _modAvailabilityResults[-64] = "该装备禁止安装此挂点类型的插件";
    }

    // ==================== 公共查询接口 ====================

    /**
     * 获取配件数据
     * @param modName 配件名称
     * @return 配件数据对象
     */
    public static function getModData(modName:String):Object {
        return _modDict[modName];
    }

    /**
     * 【方案A实施】通过displayname查找配件数据
     * 使用O(1)反向索引，避免O(n)遍历
     * @param displayName 配件显示名称
     * @return 配件数据对象，如果未找到返回null
     */
    public static function getModDataByDisplayName(displayName:String):Object {
        var modName:String = _displayNameToModName[displayName];
        if (modName) {
            return _modDict[modName];
        }
        return null;
    }

    /**
     * 【方案A实施】获取displayname到modName的映射表
     * @return displayname反向索引对象
     */
    public static function getDisplayNameIndex():Object {
        return _displayNameToModName;
    }

    /**
     * 获取所有配件字典
     */
    public static function getModDict():Object {
        return _modDict;
    }

    /**
     * 获取所有配件名称列表
     */
    public static function getModList():Array {
        return _modList;
    }

    /**
     * 获取指定装备类型的配件列表
     * @param useType 装备类型
     */
    public static function getModsByUseType(useType:String):Array {
        return _modUseLists[useType] || [];
    }

    /**
     * 获取配件使用类型列表字典
     */
    public static function getModUseLists():Object {
        return _modUseLists;
    }

    /**
     * 快速匹配useSwitch（优化后的O(n)算法）
     * @param modData 配件数据
     * @param itemUseLookup 装备的use/weapontype查找表
     * @return 匹配的stats对象，如果没有匹配返回null
     */
    public static function matchUseSwitch(modData:Object, itemUseLookup:Object):Object {
        if (!modData || !modData.stats || !modData.stats.useSwitch) {
            return null;
        }

        var useCases:Array = modData.stats.useSwitch.useCases;
        if (!useCases || useCases.length == 0) {
            return null;
        }

        // 遍历所有useCase分支
        for (var i:Number = 0; i < useCases.length; i++) {
            var useCase:Object = useCases[i];

            // 使用预构建的lookupDict进行O(1)匹配
            if (useCase.lookupDict) {
                for (var key:String in itemUseLookup) {
                    if (useCase.lookupDict[key]) {
                        if (_debugMode) {
                            trace("[ModRegistry] useSwitch匹配: " + key);
                        }
                        return useCase; // 返回匹配的分支stats
                    }
                }
            }
        }

        return null; // 没有匹配
    }

    /**
     * 构建装备的use/weapontype查找表
     * @param itemUse 装备的use属性
     * @param itemWeaponType 装备的weapontype属性
     * @return 查找表对象
     */
    public static function buildItemUseLookup(itemUse:String, itemWeaponType:String):Object {
        var lookup:Object = {};

        // 添加use
        if (itemUse) {
            var useList:Array = itemUse.split(",");
            for (var i:Number = 0; i < useList.length; i++) {
                var trimmedUse:String = StringUtils.trim(useList[i]);
                if (trimmedUse.length > 0) {
                    lookup[trimmedUse] = true;
                }
            }
        }

        // 添加weapontype
        if (itemWeaponType) {
            var weaponList:Array = itemWeaponType.split(",");
            for (var j:Number = 0; j < weaponList.length; j++) {
                var trimmedWeapon:String = StringUtils.trim(weaponList[j]);
                if (trimmedWeapon.length > 0 && !lookup[trimmedWeapon]) {
                    lookup[trimmedWeapon] = true;
                }
            }
        }

        return lookup;
    }

    /**
     * 获取配件可用性结果描述
     * @param code 状态码
     */
    public static function getAvailabilityResult(code:Number):String {
        return _modAvailabilityResults[code] || "未知错误";
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
     * 运行性能测试，比较优化前后的useSwitch匹配速度
     */
    public static function runPerformanceTest():String {
        var result:String = "\n===== ModRegistry useSwitch 性能测试 =====\n";

        // 创建测试数据
        var testMod:Object = {
            name: "测试配件",
            stats: {
                useSwitch: {
                    use: [
                        {name: "头部装备,上装装备", percentage: {defence: 10}},
                        {name: "手枪,长枪", percentage: {power: 15}},
                        {name: "刀", percentage: {damage: 20}}
                    ]
                }
            }
        };

        // 处理测试配件
        processUseSwitch(testMod);

        // 创建测试装备
        var itemUseLookup:Object = buildItemUseLookup("长枪", "狙击枪");

        // 测试优化后的匹配
        var startTime:Number = getTimer();
        var matchCount:Number = 0;

        for (var i:Number = 0; i < 10000; i++) {
            var matched:Object = matchUseSwitch(testMod, itemUseLookup);
            if (matched) matchCount++;
        }

        var endTime:Number = getTimer();
        var duration:Number = endTime - startTime;

        result += "优化后算法测试（10000次匹配）:\n";
        result += "  耗时: " + duration + "ms\n";
        result += "  匹配成功: " + matchCount + " 次\n";
        result += "  平均每次: " + (duration / 10000) + "ms\n";

        return result;
    }

    /**
     * 获取当前时间戳（AS2兼容）
     * @private
     */
    private static function getTimer():Number {
        return new Date().getTime();
    }
}