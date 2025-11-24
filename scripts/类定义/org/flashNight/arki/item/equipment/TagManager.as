import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.ModRegistry;

/**
 * TagManager - 配件标签依赖管理器
 *
 * 处理配件的标签系统，包括：
 * - requireTags: 安装前置要求
 * - provideTags: 提供的结构标签
 * - blockedTags: 装备禁止的标签
 * - tag互斥: 同tag配件不能共存
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.TagManager {

    // 调试模式
    private static var _debugMode:Boolean = false;

    /**
     * 构建标签上下文
     * @param item 装备物品对象
     * @param itemData 原始物品数据（可选）
     * @return 包含presentTags和slotOccupied的上下文对象
     */
    public static function buildTagContext(item:BaseItem, itemData:Object):Object {
        var context:Object = {
            presentTags: {},    // 当前装备具备的结构tag
            slotOccupied: {}    // 哪些slotTag已被占用
        };

        // 如果没有传入itemData，则获取原始数据
        if (!itemData) {
            itemData = ItemUtil.getRawItemData(item.name);
        }

        // 1. 装备固有结构tag
        if (itemData.inherentTags) {
            var inherentDict:Object = buildTagDict(itemData.inherentTags);
            for (var tag:String in inherentDict) {
                context.presentTags[tag] = true;
            }
        }

        // 2. 遍历已安装的插件
        var mods:Array = item.value.mods;
        if (!mods) mods = [];

        for (var i:Number = 0; i < mods.length; i++) {
            var modData:Object = ModRegistry.getModData(mods[i]);
            if (!modData) continue;

            // slotTag占位（传统tag功能）
            if (modData.tagValue) {
                context.slotOccupied[modData.tagValue] = mods[i];
            }

            // provideTags结构提供
            if (modData.provideTagDict) {
                for (var t:String in modData.provideTagDict) {
                    context.presentTags[t] = true;

                    if (_debugMode) {
                        trace("[TagManager] 插件 '" + mods[i] + "' 提供tag: " + t);
                    }
                }
            }
        }

        if (_debugMode) {
            var presentList:Array = [];
            for (var pt:String in context.presentTags) {
                presentList.push(pt);
            }
            trace("[TagManager] 当前装备的presentTags: [" + presentList.join(", ") + "]");
        }

        return context;
    }

    /**
     * 检查配件是否可以安装（标签依赖检查）
     * @param item 装备物品对象
     * @param itemData 原始物品数据
     * @param modName 配件名称
     * @return 状态码
     */
    public static function checkModAvailability(item:BaseItem, itemData:Object, modName:String):Number {
        var mods:Array = item.value.mods || [];
        var modData:Object = ModRegistry.getModData(modName);

        if (!modData) return 0; // 配件不存在

        // 检查槽位
        if (!itemData || !itemData.data) return 0;
        var modslot:Number = itemData.data.modslot || 0;
        if (mods.length > 0 && mods.length >= modslot) {
            return -1; // 槽位已满
        }

        // 检查是否已装备
        for (var i:Number = 0; i < mods.length; i++) {
            if (mods[i] === modName) {
                return -2; // 已装备同名配件
            }
        }

        // 检查tag依赖
        if (modData.requireTagDict) {
            var tagContext:Object = buildTagContext(item, itemData);
            for (var reqTag:String in modData.requireTagDict) {
                if (!tagContext.presentTags[reqTag]) {
                    if (_debugMode) {
                        trace("[TagManager] 插件 '" + modName + "' 需要tag '" + reqTag + "' 但当前装备没有");
                    }
                    return -16; // 缺少前置tag
                }
            }
        }

        // 检查tag互斥
        if (modData.tagValue) {
            for (var j:Number = 0; j < mods.length; j++) {
                var installedModData:Object = ModRegistry.getModData(mods[j]);
                if (installedModData && installedModData.tagValue) {
                    if (installedModData.tagValue === modData.tagValue) {
                        return -8; // 同tag插件已装备
                    }
                }
            }
        }

        // 检查blockedTags
        if (itemData.blockedTags && modData.tagValue) {
            if (!itemData.blockedTagDict) {
                itemData.blockedTagDict = buildTagDict(itemData.blockedTags);
            }
            if (itemData.blockedTagDict[modData.tagValue]) {
                if (_debugMode) {
                    trace("[TagManager] 装备 '" + item.name + "' 禁止安装挂点类型 '" + modData.tagValue + "' 的插件");
                }
                return -64; // 装备禁止该挂点类插件
            }
        }

        // 检查战技冲突
        if (itemData.skill && modData.skill) {
            return -4; // 已有战技
        }

        return 1; // 允许装备
    }

    /**
     * 获取缺少的tag列表
     * @param modName 插件名称
     * @param item 装备物品对象
     * @return 缺少的tag列表
     */
    public static function getMissingTags(modName:String, item:BaseItem):Array {
        var modData:Object = ModRegistry.getModData(modName);
        if (!modData || !modData.requireTagDict) return [];

        var tagContext:Object = buildTagContext(item, null);
        var missingTags:Array = [];

        for (var reqTag:String in modData.requireTagDict) {
            if (!tagContext.presentTags[reqTag]) {
                missingTags.push(reqTag);
            }
        }

        return missingTags;
    }

    /**
     * 获取依赖于指定插件的其他插件
     * @param item 装备物品对象
     * @param modNameToRemove 要移除的插件名称
     * @return 依赖该插件的其他插件列表
     */
    public static function getDependentMods(item:BaseItem, modNameToRemove:String):Array {
        var dependentMods:Array = [];
        var modToRemove:Object = ModRegistry.getModData(modNameToRemove);

        // 如果要移除的插件不提供任何tag，则没有依赖问题
        if (!modToRemove || !modToRemove.provideTagDict) {
            return dependentMods;
        }

        // 构建移除该插件后的tag上下文
        var tempMods:Array = [];
        var mods:Array = item.value.mods || [];
        for (var i:Number = 0; i < mods.length; i++) {
            if (mods[i] !== modNameToRemove) {
                tempMods.push(mods[i]);
            }
        }

        // 创建临时item来计算移除后的tag上下文
        var tempItem:Object = {
            name: item.name,
            value: { mods: tempMods }
        };
        var contextAfterRemoval:Object = buildTagContext(BaseItem(tempItem), null);

        // 检查每个已安装的插件是否还满足依赖
        for (var j:Number = 0; j < mods.length; j++) {
            if (mods[j] === modNameToRemove) continue;

            var installedMod:Object = ModRegistry.getModData(mods[j]);
            if (!installedMod || !installedMod.requireTagDict) continue;

            // 检查该插件的依赖是否还能满足
            for (var reqTag:String in installedMod.requireTagDict) {
                // 如果移除后缺少必需的tag，且这个tag原本是由要移除的插件提供的
                if (!contextAfterRemoval.presentTags[reqTag] && modToRemove.provideTagDict[reqTag]) {
                    dependentMods.push(mods[j]);
                    break;
                }
            }
        }

        if (_debugMode && dependentMods.length > 0) {
            trace("[TagManager] 移除 '" + modNameToRemove + "' 将影响以下插件: " + dependentMods.join(", "));
        }

        return dependentMods;
    }

    /**
     * 检查是否可以安全移除插件
     * @param item 装备物品对象
     * @param modNameToRemove 要移除的插件名称
     * @return 状态码：1=可以移除，-32=有其他插件依赖此插件
     */
    public static function canRemoveMod(item:BaseItem, modNameToRemove:String):Number {
        var dependentMods:Array = getDependentMods(item, modNameToRemove);
        if (dependentMods.length > 0) {
            return -32; // 有其他插件依赖此插件
        }
        return 1; // 可以安全移除
    }

    /**
     * 过滤可用配件列表（基于标签系统）
     * @param availableMods 初步可用的配件列表
     * @param item 装备物品对象
     * @param itemData 原始物品数据
     * @return 过滤后的可用配件列表
     */
    public static function filterAvailableMods(availableMods:Array, item:BaseItem, itemData:Object):Array {
        if (!availableMods || availableMods.length == 0) {
            return [];
        }

        var filtered:Array = [];
        var tagContext:Object = buildTagContext(item, itemData);

        // 处理blockedTags
        var blockedTagDict:Object = null;
        if (itemData.blockedTags) {
            blockedTagDict = buildTagDict(itemData.blockedTags);
        }

        for (var i:Number = 0; i < availableMods.length; i++) {
            var modName:String = availableMods[i];
            var modData:Object = ModRegistry.getModData(modName);
            if (!modData) continue;

            var canUse:Boolean = true;

            // 检查tag依赖
            if (modData.requireTagDict) {
                for (var reqTag:String in modData.requireTagDict) {
                    if (!tagContext.presentTags[reqTag]) {
                        canUse = false;
                        if (_debugMode) {
                            trace("[TagManager] 过滤掉 '" + modName + "': 缺少tag '" + reqTag + "'");
                        }
                        break;
                    }
                }
            }

            // 检查blockedTags
            if (canUse && blockedTagDict && modData.tagValue) {
                if (blockedTagDict[modData.tagValue]) {
                    canUse = false;
                    if (_debugMode) {
                        trace("[TagManager] 过滤掉 '" + modName + "': 挂点类型被禁止");
                    }
                }
            }

            if (canUse) {
                filtered.push(modName);
            }
        }

        return filtered;
    }

    /**
     * 从逗号分隔的字符串构建标签字典
     * @private
     */
    private static function buildTagDict(tagString:String):Object {
        var dict:Object = {};
        if (!tagString) return dict;

        var arr:Array = tagString.split(",");
        for (var i:Number = 0; i < arr.length; i++) {
            var trimmed:String = StringUtils.trim(arr[i]);
            if (trimmed.length > 0) {
                dict[trimmed] = true;
            }
        }
        return dict;
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
     * 运行标签系统测试
     */
    public static function runTests():String {
        var result:String = "\n===== TagManager 测试 =====\n";

        // 测试1：基础标签依赖
        result += testBasicTagDependency();

        // 测试2：标签互斥
        result += testTagExclusion();

        // 测试3：依赖链
        result += testDependencyChain();

        return result;
    }

    private static function testBasicTagDependency():String {
        // 创建测试装备
        var testItem:Object = {
            name: "测试装备",
            value: {
                mods: ["提供结构的插件"]
            }
        };

        // 模拟配件数据
        ModRegistry.loadModData([
            {
                name: "提供结构的插件",
                provideTags: "基础结构,高级结构"
            },
            {
                name: "需要结构的插件",
                requireTags: "基础结构"
            }
        ]);

        var context:Object = buildTagContext(BaseItem(testItem), {});
        var hasTags:Boolean = context.presentTags["基础结构"] == true;

        return hasTags ? "✓ 标签依赖测试通过\n" : "✗ 标签依赖测试失败\n";
    }

    private static function testTagExclusion():String {
        // 创建测试装备
        var testItem:Object = {
            name: "测试装备",
            value: {
                mods: ["占位插件A"]
            }
        };

        var testItemData:Object = {
            data: { modslot: 3 }
        };

        // 模拟配件数据
        ModRegistry.loadModData([
            {
                name: "占位插件A",
                tag: "槽位1"
            },
            {
                name: "占位插件B",
                tag: "槽位1"
            }
        ]);

        var availability:Number = checkModAvailability(BaseItem(testItem), testItemData, "占位插件B");
        var isExcluded:Boolean = (availability == -8);

        return isExcluded ? "✓ 标签互斥测试通过\n" : "✗ 标签互斥测试失败\n";
    }

    private static function testDependencyChain():String {
        // 创建测试装备
        var testItem:Object = {
            name: "测试装备",
            value: {
                mods: ["插件A", "插件B"]
            }
        };

        // 模拟配件数据
        ModRegistry.loadModData([
            {
                name: "插件A",
                provideTags: "结构A"
            },
            {
                name: "插件B",
                requireTags: "结构A"
            }
        ]);

        var dependents:Array = getDependentMods(BaseItem(testItem), "插件A");
        var hasDependent:Boolean = (dependents.length == 1 && dependents[0] == "插件B");

        return hasDependent ? "✓ 依赖链测试通过\n" : "✗ 依赖链测试失败\n";
    }
}