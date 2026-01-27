import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;

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
     * 支持静态 provideTags 和条件性 provideTags（基于 useSwitch）
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

        // 获取配件列表
        var mods:Array = item.value.mods;
        if (!mods) mods = [];

        // 【重构】复用 buildPresentTagsDict 构建 presentTags（单一真源）
        context.presentTags = buildPresentTagsDict(mods, itemData, ModRegistry.getModDict());

        // 构建 slotOccupied（这是 buildTagContext 特有的逻辑）
        for (var i:Number = 0; i < mods.length; i++) {
            var modData:Object = ModRegistry.getModData(mods[i]);
            if (!modData) continue;

            // slotTag占位（传统tag功能）
            if (modData.tagValue) {
                context.slotOccupied[modData.tagValue] = mods[i];
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
     * 构建当前装备的完整 presentTags（公开方法，供外部调用）
     * 包含：装备固有结构 + 配件静态 provideTags + 配件条件性 provideTags
     *
     * 此方法是 presentTags 构建的单一真源，供以下场景使用：
     * - TagManager 内部的可用性检查（requireTags 判定）
     * - EquipmentCalculator 的 tagSwitch 属性计算
     *
     * @param mods 已安装配件名称数组
     * @param itemData 原始物品数据（包含 inherentTags, use, weapontype）
     * @param modRegistry 配件注册表字典
     * @return presentTags 字典（key 为 tag 名称，value 为 true）
     */
    public static function buildPresentTagsDict(mods:Array, itemData:Object, modRegistry:Object):Object {
        var presentTags:Object = {};

        // 构建装备的 use/weapontype 查找表
        var useLookup:Object = ModRegistry.buildItemUseLookup(
            itemData.use || "",
            itemData.weapontype || ""
        );

        // 1. 装备固有结构标签
        if (itemData.inherentTags) {
            var inherentDict:Object = buildTagDict(itemData.inherentTags);
            for (var tag:String in inherentDict) {
                presentTags[tag] = true;
            }
        }

        // 2. 遍历配件，收集 provideTags
        if (!mods) mods = [];
        for (var i:Number = 0; i < mods.length; i++) {
            var modInfo:Object = modRegistry[mods[i]];
            if (!modInfo) continue;

            // 静态 provideTags
            if (modInfo.provideTagDict) {
                for (var st:String in modInfo.provideTagDict) {
                    presentTags[st] = true;

                    if (_debugMode) {
                        trace("[TagManager] 插件 '" + mods[i] + "' 提供静态tag: " + st);
                    }
                }
            }

            // 条件性 provideTags（基于 useSwitch 匹配）
            var matchedCases:Array = ModRegistry.matchUseSwitchAll(modInfo, useLookup);
            if (matchedCases && matchedCases.length > 0) {
                for (var mc:Number = 0; mc < matchedCases.length; mc++) {
                    var useCase:Object = matchedCases[mc];
                    if (useCase.provideTagDict) {
                        for (var ct:String in useCase.provideTagDict) {
                            presentTags[ct] = true;

                            if (_debugMode) {
                                trace("[TagManager] 插件 '" + mods[i] + "' 通过useSwitch('" + useCase.name + "')提供条件性tag: " + ct);
                            }
                        }
                    }
                }
            }
        }

        return presentTags;
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
        var modslot:Number = itemData.data.modslot;
        // 保持原行为：如果 modslot 为 undefined，不进行槽位限制检查
        // 原版中 len >= undefined 返回 false，相当于没有槽位限制
        if (modslot !== undefined && mods.length > 0 && mods.length >= modslot) {
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

        // 检查子弹类型排斥
        if (modData.excludeBulletTypeDict && itemData.data && itemData.data.bullet) {
            var bulletType:String = itemData.data.bullet;
            if (checkBulletTypeExclusion(bulletType, modData.excludeBulletTypeDict)) {
                if (_debugMode) {
                    trace("[TagManager] 插件 '" + modName + "' 与当前弹药类型 '" + bulletType + "' 不兼容");
                }
                return -128; // 弹药类型不兼容
            }
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

        // 惰性计算的装备数据（仅在需要检查子弹类型时才计算）
        var calculatedItemData:Object = undefined;

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

            // 检查子弹类型排斥（需要计算后的数据）
            if (canUse && modData.excludeBulletTypeDict) {
                // 惰性获取计算后的装备数据
                if (calculatedItemData == undefined) {
                    calculatedItemData = item.getData();
                }
                if (calculatedItemData.data && calculatedItemData.data.bullet) {
                    if (checkBulletTypeExclusion(calculatedItemData.data.bullet, modData.excludeBulletTypeDict)) {
                        canUse = false;
                        if (_debugMode) {
                            trace("[TagManager] 过滤掉 '" + modName + "': 弹药类型不兼容");
                        }
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
     * 检查子弹类型是否被排斥
     * @param bulletType 当前装备的子弹类型字符串
     * @param excludeDict 排斥的子弹类型字典（键为类型标识符）
     * @return 如果被排斥返回true，否则返回false
     * @private
     */
    private static function checkBulletTypeExclusion(bulletType:String, excludeDict:Object):Boolean {
        if (!bulletType || !excludeDict) return false;

        // 遍历排斥字典中的每个类型标识符
        for (var typeKey:String in excludeDict) {
            var isExcluded:Boolean = false;

            // 根据类型标识符调用对应的检测方法
            switch (typeKey) {
                case "pierce":
                    isExcluded = BulletTypeUtil.isPierce(bulletType);
                    break;
                case "melee":
                    isExcluded = BulletTypeUtil.isMelee(bulletType);
                    break;
                case "chain":
                    isExcluded = BulletTypeUtil.isChain(bulletType);
                    break;
                case "grenade":
                    isExcluded = BulletTypeUtil.isGrenade(bulletType);
                    break;
                case "explosive":
                    isExcluded = BulletTypeUtil.isExplosive(bulletType);
                    break;
                case "normal":
                    isExcluded = BulletTypeUtil.isNormal(bulletType);
                    break;
                case "vertical":
                    isExcluded = BulletTypeUtil.isVertical(bulletType);
                    break;
                case "transparency":
                    isExcluded = BulletTypeUtil.isTransparency(bulletType);
                    break;
                default:
                    if (_debugMode) {
                        trace("[TagManager] 未知的子弹类型标识符: " + typeKey);
                    }
                    break;
            }

            if (isExcluded) {
                return true;
            }
        }

        return false;
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