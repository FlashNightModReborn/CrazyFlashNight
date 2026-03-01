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

        // 2. 处理weapontype（武器类型限制 - 白名单）
        if (mod.weapontype) {
            mod.weapontypeDict = buildDictFromList(mod.weapontype);
        }

        // 2.5. 处理excludeWeapontype（武器类型排除 - 黑名单）
        if (mod.excludeWeapontype) {
            mod.excludeWeapontypeDict = buildDictFromList(mod.excludeWeapontype);
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

        // 8. 处理excludeBulletTypes（子弹类型排斥）
        // 支持的值: pierce, melee, chain, grenade, explosive, normal, vertical, transparency
        if (mod.excludeBulletTypes) {
            mod.excludeBulletTypeDict = buildDictFromList(mod.excludeBulletTypes);
        }

        // 8.1. 处理requireBulletTypes（子弹类型要求）
        // 要求装备的子弹至少匹配其中一种类型才能安装（与excludeBulletTypes相反）
        if (mod.requireBulletTypes) {
            mod.requireBulletTypeDict = buildDictFromList(mod.requireBulletTypes);
        }

        // 8.5. 处理 installCondition（安装条件表达式）
        if (mod.installCondition) {
            mod.installCondList = processInstallCondition(mod.installCondition);
        }

        // 9. 归一化percentage（百分比值）
        normalizePercentage(mod);

        // 10. 归一化multiplier（独立乘区）
        normalizeMultiplier(mod);

        // 11. 处理和优化useSwitch
        processUseSwitch(mod);

        // 12. 【新增】处理和优化tagSwitch（基于结构的条件加成）
        processTagSwitch(mod);

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
     * 支持 stats 运算符和条件性 provideTags
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

            // 【新增】处理条件性 provideTags
            if (useCase.provideTags) {
                useCase.provideTagDict = buildDictFromList(useCase.provideTags);
                if (_debugMode) {
                    trace("[ModRegistry] useSwitch分支 '" + useCase.name + "' 提供条件性tags: " + useCase.provideTags);
                }
            }
        }

        // 保存处理后的数组形式
        useSwitch.useCases = useCases;
        mod._useSwitchProcessed = true;
    }

    /**
     * 【新增】处理和优化 tagSwitch（基于结构的条件加成）
     * 当宿主装备具备特定结构标签时，提供额外的 stats 加成
     * @private
     */
    private static function processTagSwitch(mod:Object):Void {
        if (mod._tagSwitchProcessed) return; // 已处理过
        if (!mod.stats || !mod.stats.tagSwitch) return;

        var tagSwitch:Object = mod.stats.tagSwitch;

        // 将tag统一转换为数组
        var tagCases:Array;
        if (tagSwitch.tag instanceof Array) {
            tagCases = tagSwitch.tag;
        } else if (tagSwitch.tag) {
            tagCases = [tagSwitch.tag];
        } else {
            tagCases = [];
        }

        // 处理每个tag分支
        for (var i:Number = 0; i < tagCases.length; i++) {
            var tagCase:Object = tagCases[i];

            // 归一化percentage字段
            if (tagCase.percentage) {
                for (var pKey:String in tagCase.percentage) {
                    tagCase.percentage[pKey] *= 0.01;
                }
            }

            // 归一化multiplier字段
            if (tagCase.multiplier) {
                for (var mKey:String in tagCase.multiplier) {
                    tagCase.multiplier[mKey] *= 0.01;
                }
            }

            // 为每个tagCase预构建查找表（优化性能）
            // name属性可以是逗号分隔的多个tag，满足任一即可触发
            if (tagCase.name) {
                tagCase.lookupDict = buildDictFromList(tagCase.name);
            }

            if (_debugMode) {
                trace("[ModRegistry] tagSwitch分支: 当存在 '" + tagCase.name + "' 时触发加成");
            }
        }

        // 保存处理后的数组形式
        tagSwitch.tagCases = tagCases;
        mod._tagSwitchProcessed = true;
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
        _modAvailabilityResults[-128] = "当前弹药与此配件不兼容";
        _modAvailabilityResults[-256] = "装备属性不满足安装条件";
        _modAvailabilityResults[-512] = "当前弹药类型不满足此配件的要求";
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
     * 【重要修复】匹配所有符合条件的useSwitch分支
     * 恢复原始语义：允许多个分支同时生效并叠加
     * @param modData 配件数据
     * @param itemUseLookup 装备的use/weapontype查找表
     * @return 所有匹配的useCase数组，如果没有匹配返回空数组
     */
    public static function matchUseSwitchAll(modData:Object, itemUseLookup:Object):Array {
        var matched:Array = [];

        if (!modData || !modData.stats || !modData.stats.useSwitch) {
            return matched;
        }

        var useCases:Array = modData.stats.useSwitch.useCases;
        if (!useCases || useCases.length == 0) {
            return matched;
        }

        // 遍历所有useCase分支，收集所有匹配的
        for (var i:Number = 0; i < useCases.length; i++) {
            var useCase:Object = useCases[i];
            if (!useCase) continue;

            // 惰性构建 lookupDict：如果缺失则即时解析 name 字段
            // 这确保了动态注入或未经 loadModData 处理的 Mod 也能正常匹配
            var lookupDict:Object = useCase.lookupDict;
            if (!lookupDict) {
                if (useCase.name) {
                    lookupDict = buildDictFromList(useCase.name);
                    useCase.lookupDict = lookupDict; // 缓存以供后续使用
                    if (_debugMode) {
                        trace("[ModRegistry] 惰性构建lookupDict: " + useCase.name);
                    }
                } else {
                    continue; // 没有 name 也没有 lookupDict，跳过
                }
            }

            // 只要有一个key命中就算该分支命中
            var hit:Boolean = false;
            for (var key:String in itemUseLookup) {
                if (lookupDict[key]) {
                    hit = true;
                    if (_debugMode) {
                        trace("[ModRegistry] useSwitch匹配分支: " + useCase.name + " by " + key);
                    }
                    break; // 避免同一useCase被重复加入
                }
            }

            if (hit) {
                matched.push(useCase);
            }
        }

        return matched;
    }

    /**
     * 匹配useSwitch分支（保留原接口用于兼容）
     * @param modData 配件数据
     * @param itemUseLookup 装备的use/weapontype查找表
     * @return 第一个匹配的useCase对象，如果没有匹配返回null
     */
    public static function matchUseSwitch(modData:Object, itemUseLookup:Object):Object {
        var matched:Array = matchUseSwitchAll(modData, itemUseLookup);
        return (matched.length > 0) ? matched[0] : null;
    }

    /**
     * 【新增】匹配所有符合条件的 tagSwitch 分支
     * 基于宿主装备当前的结构标签（presentTags）进行匹配
     * @param modData 配件数据
     * @param presentTags 当前装备具备的结构标签字典
     * @return 所有匹配的tagCase数组，如果没有匹配返回空数组
     */
    public static function matchTagSwitchAll(modData:Object, presentTags:Object):Array {
        var matched:Array = [];

        if (!modData || !modData.stats || !modData.stats.tagSwitch) {
            return matched;
        }

        var tagCases:Array = modData.stats.tagSwitch.tagCases;
        if (!tagCases || tagCases.length == 0) {
            return matched;
        }

        // 遍历所有tagCase分支，收集所有匹配的
        for (var i:Number = 0; i < tagCases.length; i++) {
            var tagCase:Object = tagCases[i];
            if (!tagCase) continue;

            // 惰性构建 lookupDict
            var lookupDict:Object = tagCase.lookupDict;
            if (!lookupDict) {
                if (tagCase.name) {
                    lookupDict = buildDictFromList(tagCase.name);
                    tagCase.lookupDict = lookupDict;
                    if (_debugMode) {
                        trace("[ModRegistry] 惰性构建tagSwitch lookupDict: " + tagCase.name);
                    }
                } else {
                    continue;
                }
            }

            // 只要 presentTags 中有一个 key 命中 lookupDict 就算该分支命中
            var hit:Boolean = false;
            for (var reqTag:String in lookupDict) {
                if (presentTags[reqTag]) {
                    hit = true;
                    if (_debugMode) {
                        trace("[ModRegistry] tagSwitch匹配分支: '" + tagCase.name + "' by tag '" + reqTag + "'");
                    }
                    break;
                }
            }

            if (hit) {
                matched.push(tagCase);
            }
        }

        return matched;
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

    // ==================== installCondition 安装条件系统 ====================

    /**
     * 处理 installCondition 配置，归一化为标准条件组结构
     *
     * XML 示例:
     *   <installCondition scope="base" mode="all">
     *     <cond op="is" path="data.damagetype" value="魔法"/>
     *     <cond op="above" path="data.interval" value="200"/>
     *   </installCondition>
     *
     * 支持的运算符（避开 AS2 关键字 eq/ne/gt/lt/ge/le/not）:
     *   is, isNot, above, atLeast, below, atMost,
     *   oneOf, noneOf, contains, range, exists, missing
     *
     * @param condObj XMLParser 解析后的 installCondition 对象
     * @return 归一化条件组 {scope, mode, conditions:[...]}
     * @private
     */
    private static function processInstallCondition(condObj:Object):Object {
        if (!condObj) return null;

        var result:Object = {
            scope: condObj.scope || "base",
            mode: condObj.mode || "all",
            conditions: []
        };

        // 收集顶层 <cond> 节点（单个为对象，多个为数组）
        var rawConds:Array = normalizeToArray(condObj.cond);

        // 收集顶层 <group> 节点
        var rawGroups:Array = normalizeToArray(condObj.group);

        // 处理每个 <cond>
        for (var i:Number = 0; i < rawConds.length; i++) {
            var c:Object = rawConds[i];
            if (!c || !c.op) continue;

            var processed:Object = {
                type: "cond",
                op: c.op,
                path: c.path || ""
            };

            // 对 oneOf/noneOf 预构建字典以获得 O(1) 查找
            if (c.op == "oneOf" || c.op == "noneOf") {
                processed.value = c.value;
                processed.valueDict = buildDictFromList(String(c.value));
            } else if (c.op == "range") {
                processed.min = Number(c.min);
                processed.max = Number(c.max);
            } else if (c.op != "exists" && c.op != "missing") {
                processed.value = c.value;
            }

            result.conditions.push(processed);
        }

        // 处理嵌套 <group>
        for (var g:Number = 0; g < rawGroups.length; g++) {
            var grp:Object = rawGroups[g];
            if (!grp) continue;

            var subGroup:Object = processInstallCondition(grp);
            if (subGroup && subGroup.conditions.length > 0) {
                subGroup.type = "group";
                result.conditions.push(subGroup);
            }
        }

        if (_debugMode && result.conditions.length > 0) {
            trace("[ModRegistry] installCondition: scope=" + result.scope
                  + ", mode=" + result.mode
                  + ", conditions=" + result.conditions.length);
        }

        return (result.conditions.length > 0) ? result : null;
    }

    /**
     * 将单个对象或数组统一转为数组
     * XMLParser 对单个子节点返回对象，多个返回数组
     * @private
     */
    private static function normalizeToArray(val):Array {
        if (!val) return [];
        if (val instanceof Array) return val;
        return [val];
    }

    /**
     * 按点路径从对象中取值
     * 例如 resolvePathValue(itemData, "data.magicdefence.电")
     * @param obj 目标对象
     * @param path 点分隔路径字符串
     * @return 路径指向的值，不存在返回 undefined
     */
    public static function resolvePathValue(obj:Object, path:String) {
        if (!obj || !path) return undefined;

        var parts:Array = path.split(".");
        var current = obj;

        for (var i:Number = 0; i < parts.length; i++) {
            if (current == undefined || current == null) return undefined;
            current = current[parts[i]];
        }

        return current;
    }

    /**
     * 求值单个条件
     * @param cond 条件对象 {op, path, value, valueDict?, min?, max?}
     * @param itemData 装备数据
     * @return 条件是否满足
     */
    public static function evaluateCondition(cond:Object, itemData:Object):Boolean {
        if (!cond || !cond.op) return false;

        var op:String = cond.op;

        // exists/missing 不需要取值
        if (op == "exists") {
            return resolvePathValue(itemData, cond.path) != undefined;
        }
        if (op == "missing") {
            return resolvePathValue(itemData, cond.path) == undefined;
        }

        var actual = resolvePathValue(itemData, cond.path);

        // 字段不存在：除 exists/missing 外一律判定为不满足
        if (actual == undefined) return false;

        switch (op) {
            case "is":
                // 统一转字符串比较，兼容数字和字符串
                return String(actual) == String(cond.value);

            case "isNot":
                return String(actual) != String(cond.value);

            case "above":
                return Number(actual) > Number(cond.value);

            case "atLeast":
                return Number(actual) >= Number(cond.value);

            case "below":
                return Number(actual) < Number(cond.value);

            case "atMost":
                return Number(actual) <= Number(cond.value);

            case "oneOf":
                return cond.valueDict[String(actual)] == true;

            case "noneOf":
                return cond.valueDict[String(actual)] != true;

            case "contains":
                return String(actual).indexOf(String(cond.value)) >= 0;

            case "range":
                var numActual:Number = Number(actual);
                return numActual >= cond.min && numActual <= cond.max;

            default:
                if (_debugMode) {
                    trace("[ModRegistry] 未知的 installCondition 运算符: " + op);
                }
                return false;
        }
    }

    /**
     * 求值条件组（支持嵌套 group）
     * @param condGroup 条件组对象 {mode, conditions:[...]}
     * @param itemData 装备数据
     * @return 条件组是否满足
     */
    public static function evaluateConditionGroup(condGroup:Object, itemData:Object):Boolean {
        if (!condGroup || !condGroup.conditions) return true;

        var conditions:Array = condGroup.conditions;
        var isAll:Boolean = (condGroup.mode != "any"); // 默认 "all"

        for (var i:Number = 0; i < conditions.length; i++) {
            var item:Object = conditions[i];
            var result:Boolean;

            if (item.type == "group") {
                // 递归求值子 group
                result = evaluateConditionGroup(item, itemData);
            } else {
                result = evaluateCondition(item, itemData);
            }

            if (isAll && !result) return false;   // AND: 遇到 false 立即返回
            if (!isAll && result) return true;     // OR: 遇到 true 立即返回
        }

        // AND: 全部通过返回 true；OR: 全部未通过返回 false
        return isAll;
    }
}
