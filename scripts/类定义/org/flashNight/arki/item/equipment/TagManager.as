import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.EquipmentCalculator;
import org.flashNight.arki.item.equipment.EquipmentLifecyclePolicy;
import org.flashNight.arki.bullet.BulletComponent.Type.BulletTypeUtil;

/**
 * TagManager - 配件标签依赖管理器
 *
 * 处理配件的标签系统，包括：
 * - requireTags / useSwitch.requireTags: 全局或按装备类型生效的安装前置要求
 * - provideTags: 提供的结构标签
 * - blockedTags: 装备禁止的标签
 * - allowedModTags: 可选的挂点白名单；未标注时沿用原规则，标注后未列出/无tag均拒绝
 * - tag互斥: 同tag配件不能共存
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.TagManager {

    // 调试模式
    private static var _debugMode:Boolean = false;

    /** null 表示未限制；空白/畸形显式白名单产生空集合，不能退回开放安装。 */
    private static function allowedModTagDict(itemData:Object):Object {
        if (itemData.allowedModTags === undefined) return null;
        if (typeof itemData.allowedModTags != "string") return {};
        return buildTagDict(itemData.allowedModTags);
    }

    private static function matchesAllowedModTags(modData:Object, allowed:Object):Boolean {
        return allowed == null || (typeof modData.tagValue == "string" && allowed[modData.tagValue] === true);
    }

    /**
     * 构建标签上下文
     * 支持静态 provideTags 和条件性 provideTags（基于 useSwitch）
     * @param item 装备物品对象
     * @param itemData 原始物品数据（可选）
     * @return 包含 presentTags 的上下文对象
     */
    public static function buildTagContext(item:BaseItem, itemData:Object):Object {
        var context:Object = {
            presentTags: {}    // 当前装备具备的结构tag
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
    public static function buildPresentTagsDict(mods:Array, itemData:Object, modRegistry:Object, useLookup:Object):Object {
        var presentTags:Object = {};

        // 构建装备的 use/weapontype 查找表
        if (!useLookup) useLookup = buildUseLookupForMods(mods, itemData, modRegistry);

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
     * @param itemData 当前完整物品属性
     * @param modName 配件名称
     * @return 状态码
     */
    public static function checkModAvailability(item:BaseItem, itemData:Object, modName:String, state:Object):Number {
        var mods:Array = item.value.mods || [];
        var modData:Object = ModRegistry.getModData(modName);
        if (!modData) return ModRegistry.isInvalidHitBehaviorMod(modName) ? -1024 : 0;
        if (!itemData || !itemData.data) return 0;
        var modslot:Number = itemData.data.modslot;
        if (modslot !== undefined && mods.length >= modslot) return -1;
        for (var i:Number = 0; i < mods.length; i++) if (mods[i] === modName) return -2;
        if (!state || state.item !== item) state = createModState(item, itemData);
        if (!matchesModType(modData, state) || !matchesAllowedModTags(modData, state.allowedTags)) return -64;
        if (!matchesRequiredTags(modData, state)) return -16;
        if (modData.tagValue) {
            for (var j:Number = 0; j < mods.length; j++) {
                var installedModData:Object = state.dict[mods[j]];
                if (installedModData && installedModData.tagValue === modData.tagValue) return -8;
            }
        }
        if (!matchesBlockedTags(modData, state)) return -64;
        var itemUseLookup:Object = state.useLookup;
        var resolvedModSkill:Object = ModRegistry.resolveSkillForUse(modData, itemUseLookup);
        var resolvedModSubweapon:Object = modData.subweapon;
        if (resolvedModSkill || resolvedModSubweapon) {
            if (itemData.subweapon) {
                return -4; // 长枪副武器占用共享特殊槽
            }
            if (isSkillReplaceableLocked(itemData)) {
                return -4; // 战技声明处标记为不可更换
            }
            if (itemData.skill) {
                if (!resolvedModSkill) {
                    return -4; // 副武器插件不覆盖本体战技，不能与已有战技共存
                }
                if (itemData.skill.skillname == undefined) {
                    return -4; // <skill> 非战技定义（说明文本），不能被覆盖
                }
            }
            for (var specialIndex:Number = 0; specialIndex < mods.length; specialIndex++) {
                var installedSpecialMod:Object = ModRegistry.getModData(mods[specialIndex]);
                if (!installedSpecialMod) continue;
                if (installedSpecialMod.subweapon || ModRegistry.resolveSkillForUse(installedSpecialMod, itemUseLookup)) {
                    return -4;
                }
            }
        }

        if (modData.lifecycle != undefined && !EquipmentLifecyclePolicy.isIndependentLifecycle(modData.lifecycle)) return -1024;
        if (!matchesHitBehavior(modData, modName, state)) return -1024;
        var bulletResult:Number = checkBulletConstraints(modData, state);
        if (bulletResult != 1) return bulletResult;
        if (!matchesInstallCondition(modData, state)) return -256;
        return 1;
    }

    /**
     * 获取缺少的tag列表
     * @param modName 插件名称
     * @param item 装备物品对象
     * @return 缺少的tag列表
     */
    public static function getMissingTags(modName:String, item:BaseItem):Array {
        var modData:Object = ModRegistry.getModData(modName);
        if (!modData) return [];

        var itemData:Object = ItemUtil.getRawItemData(item.name) || {};
        var mods:Array = item.value.mods || [];
        var useLookup:Object = buildUseLookupForMods(mods, itemData, ModRegistry.getModDict());
        var requiredTagDict:Object = ModRegistry.resolveRequiredTagsForUse(modData, useLookup);
        var tagContext:Object = buildTagContext(item, itemData);
        var missingTags:Array = [];

        for (var reqTag:String in requiredTagDict) {
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
        var result:Array = [];
        if (!ModRegistry.getModData(modNameToRemove)) return result;
        var mods:Array = item.value.mods || [];
        var remaining:Array = [];
        for (var i:Number = 0; i < mods.length; i++) if (mods[i] !== modNameToRemove) remaining.push(mods[i]);
        var raw:Object = ItemUtil.getRawItemData(item.name);
        var dict:Object = ModRegistry.getModDict();
        var before:Object = createStructureState(raw, mods, dict);
        var after:Object = createStructureState(raw, remaining, dict);
        for (i = 0; i < remaining.length; i++) {
            var mod:Object = dict[remaining[i]];
            if (mod && losesDependency(mod, before, after)) result.push(remaining[i]);
        }
        return result;
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
    public static function filterAvailableMods(availableMods:Array, item:BaseItem, itemData:Object, state:Object):Array {
        if (itemData.data.modslot === 0 || !availableMods || availableMods.length == 0) return [];
        if (!state || state.item !== item) state = createModState(item, undefined);
        var filtered:Array = [];
        for (var i:Number = 0; i < availableMods.length; i++) {
            var name:String = availableMods[i];
            var mod:Object = state.dict[name];
            // 展示保留满槽、同名、同 tag 与特殊槽占用项，安装策略单独编排。
            if (!mod || !matchesModType(mod, state) || !matchesAllowedModTags(mod, state.allowedTags)
                    || !matchesRequiredTags(mod, state) || !matchesBlockedTags(mod, state)
                    || checkBulletConstraints(mod, state) != 1 || !matchesInstallCondition(mod, state)
                    || !matchesHitBehavior(mod, name, state)) continue;
            filtered.push(name);
        }
        return filtered;
    }

    /**
     * 判断装备自带战技是否被声明处标记为不可更换。
     *
     * 标记形态是战技声明处的一个子元素：
     * <code>&lt;skillLocked&gt;true&lt;/skillLocked&gt;</code>。
     * 战技可能声明在装备根的 <skill>，也可能只声明在 lifecycle 的
     * attr_N/skill 或 attr_N/init/initParam/skill_M 中；标记写在战技声明处，
     * 因此两处都要看。
     *
     * **未声明该子元素的战技默认可更换**（可被「战技插件」覆盖）：这里用
     * 严格 === true 判定，缺省解析出来是 undefined，不等于 true，所以
     * 不需要给默认值，缺省即隐式「可更换」。
     *
     * @private
     */
    private static function isSkillReplaceableLocked(itemData:Object):Boolean {
        var rootSkill:Object = itemData.skill;
        // 注意必须是 === true：undefined（未声明）与 ""（空元素写法）都不算锁定
        if (rootSkill && rootSkill.skillLocked === true) {
            return true;
        }

        var lifecycle:Object = itemData.lifecycle;
        if (!lifecycle || typeof lifecycle != "object") return false;

        for (var attrName:String in lifecycle) {
            var attr:Object = lifecycle[attrName];
            if (!attr || typeof attr != "object") continue;

            var attrSkill:Object = attr.skill;
            if (attrSkill && attrSkill.skillLocked === true) {
                return true;
            }

            var init:Object = attr.init;
            var params:Object = init ? init.initParam : null;
            if (!params) continue;
            for (var paramName:String in params) {
                var paramSkill:Object = params[paramName];
                if (paramSkill && paramSkill.skillLocked === true) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * 根据装备本体与已安装配件的 grantsUse，构建类型查找表。
     * @private
     */
    private static function buildUseLookupForMods(mods:Array, itemData:Object, modRegistry:Object):Object {
        var grantedUses:Object = null;
        if (!mods) mods = [];
        if (!itemData) itemData = {};
        if (!modRegistry) modRegistry = ModRegistry.getModDict();

        for (var i:Number = 0; i < mods.length; i++) {
            var modInfo:Object = modRegistry[mods[i]];
            if (!modInfo || !modInfo.grantsUseDict) continue;
            if (!grantedUses) grantedUses = {};
            for (var grantedUse:String in modInfo.grantsUseDict) {
                grantedUses[grantedUse] = true;
            }
        }

        return ModRegistry.buildItemUseLookup(
            itemData.use || "",
            itemData.weapontype || "",
            grantedUses
        );
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
     * 检查子弹类型是否匹配指定的类型标识符
     * 公共方法，供 checkBulletTypeExclusion/checkBulletTypeRequirement 以及
     * ModRegistry.matchBulletSwitchAll 共用
     * @param bulletType 子弹种类字符串（如"穿刺子弹"）
     * @param typeKey 类型标识符（如"pierce"）
     * @return 如果匹配返回true
     */
    public static function checkBulletTypeMatch(bulletType:String, typeKey:String):Boolean {
        switch (typeKey) {
            case "pierce":
                return BulletTypeUtil.isPierce(bulletType);
            case "melee":
                return BulletTypeUtil.isMelee(bulletType);
            case "chain":
                return BulletTypeUtil.isChain(bulletType);
            case "grenade":
                return BulletTypeUtil.isGrenade(bulletType);
            case "explosive":
                return BulletTypeUtil.isExplosive(bulletType);
            case "normal":
                return BulletTypeUtil.isNormal(bulletType);
            case "vertical":
                return BulletTypeUtil.isVertical(bulletType);
            case "transparency":
                return BulletTypeUtil.isTransparency(bulletType);
            default:
                if (_debugMode) {
                    trace("[TagManager] 未知的子弹类型标识符: " + typeKey);
                }
                return false;
        }
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

        for (var typeKey:String in excludeDict) {
            if (checkBulletTypeMatch(bulletType, typeKey)) {
                return true;
            }
        }

        return false;
    }

    /**
     * 检查子弹类型是否满足要求（与排斥相反）
     * @param bulletType 当前装备的子弹类型字符串
     * @param requireDict 要求的子弹类型字典（键为类型标识符）
     * @return 如果满足要求（至少匹配一种）返回true，否则返回false
     * @private
     */
    private static function checkBulletTypeRequirement(bulletType:String, requireDict:Object):Boolean {
        if (!bulletType || !requireDict) return true;

        for (var typeKey:String in requireDict) {
            if (checkBulletTypeMatch(bulletType, typeKey)) {
                return true;
            }
        }

        return false;
    }

    /** 一次同步请求内的状态；不序列化、不存档、不跨请求缓存。 */
    public static function createModState(item:BaseItem, current:Object):Object {
        var state:Object = createStructureState(ItemUtil.getRawItemData(item.name),
            item.value.mods || [], ModRegistry.getModDict());
        state.item = item;
        state.current = current;
        return state;
    }

    private static function createStructureState(raw:Object, mods:Array, dict:Object):Object {
        if (!raw) raw = {};
        var uses:Object = buildTagDict(raw.use || "");
        var weapons:Object = {};
        if (raw.weapontype) weapons[raw.weapontype] = true;
        var grantedUses:Object = {};
        for (var i:Number = 0; i < mods.length; i++) {
            var mod:Object = dict[mods[i]];
            for (var useKey:String in mod.grantsUseDict) {
                uses[useKey] = true;
                grantedUses[useKey] = true;
            }
            for (var weaponKey:String in mod.grantsWeapontypeDict) weapons[weaponKey] = true;
        }
        var lookup:Object = ModRegistry.buildItemUseLookup(raw.use || "", raw.weapontype || "", grantedUses);
        return {raw:raw, mods:mods, dict:dict, uses:uses, weapons:weapons, useLookup:lookup,
            presentTags:buildPresentTagsDict(mods, raw, dict, lookup),
            allowedTags:allowedModTagDict(raw), blockedTags:buildTagDict(raw.blockedTags || "")};
    }

    /** 安装资格与 useSwitch lookup 分开：授予枪种不会扩大条件分支。 */
    public static function matchesModType(mod:Object, state:Object):Boolean {
        var useMatched:Boolean = false;
        for (var useKey:String in mod.useDict) {
            if (state.uses[useKey]) { useMatched = true; break; }
        }
        if (!useMatched) return false;
        if (state.raw.use != "手枪" && state.raw.use != "长枪") return true;
        for (var blocked:String in mod.excludeWeapontypeDict) {
            if (state.weapons[blocked]) return false;
        }
        if (!mod.weapontypeDict) return true;
        for (var allowed:String in mod.weapontypeDict) {
            if (state.weapons[allowed]) return true;
        }
        return false;
    }

    private static function matchesRequiredTags(mod:Object, state:Object):Boolean {
        var required:Object = ModRegistry.resolveRequiredTagsForUse(mod, state.useLookup);
        for (var tag:String in required) if (!state.presentTags[tag]) return false;
        return true;
    }

    private static function matchesBlockedTags(mod:Object, state:Object):Boolean {
        return !mod.tagValue || !state.blockedTags[mod.tagValue];
    }

    private static function currentData(state:Object):Object {
        if (state.current === undefined) state.current = state.item.getData();
        return state.current;
    }

    private static function baseData(state:Object):Object {
        if (state.base === undefined) state.base = EquipmentCalculator.calculateBaseData(state.item.name, state.item.value);
        return state.base;
    }

    private static function checkBulletConstraints(mod:Object, state:Object):Number {
        if (!mod.excludeBulletTypeDict && !mod.requireBulletTypeDict) return 1;
        var current:Object = currentData(state);
        if (!current || !current.data) return 0;
        var bullet:String = current.data.bullet;
        if (bullet && mod.excludeBulletTypeDict && checkBulletTypeExclusion(bullet, mod.excludeBulletTypeDict)) return -128;
        if (bullet && mod.requireBulletTypeDict && !checkBulletTypeRequirement(bullet, mod.requireBulletTypeDict)) return -512;
        return 1;
    }

    private static function matchesInstallCondition(mod:Object, state:Object):Boolean {
        if (!mod.installCondList) return true;
        var data:Object = mod.installCondList.scope == "current" ? currentData(state) : baseData(state);
        return data != null && ModRegistry.evaluateConditionGroup(mod.installCondList, data);
    }

    private static function matchesHitBehavior(mod:Object, modName:String, state:Object):Boolean {
        if (!mod._hasHitBehavior && !mod.grantsUseDict && state.mods.length == 0) return true;
        var base:Object = baseData(state);
        if (!base || !base.data) return false;
        var candidates:Array = state.mods.concat([modName]);
        var lookup:Object = mod.grantsUseDict
            ? buildUseLookupForMods(candidates, state.raw, state.dict) : state.useLookup;
        return ModRegistry.validateHitBehaviorProvision(candidates,
            base.data.hitBehavior != undefined, state.dict, lookup).valid;
    }

    private static function losesDependency(mod:Object, before:Object, after:Object):Boolean {
        if (matchesModType(mod, before) && !matchesModType(mod, after)) return true;
        var oldRequired:Object = ModRegistry.resolveRequiredTagsForUse(mod, before.useLookup);
        var required:Object = ModRegistry.resolveRequiredTagsForUse(mod, after.useLookup);
        for (var tag:String in required) {
            if (!after.presentTags[tag] && (before.presentTags[tag] || !oldRequired[tag])) return true;
        }
        return false;
    }

    /** 只拒绝本操作新造成的保留项失效，不清洗历史非法状态。 */
    public static function hasNewInvalidModDependencies(item:BaseItem, afterMods:Array):Boolean {
        var raw:Object = ItemUtil.getRawItemData(item.name);
        var dict:Object = ModRegistry.getModDict();
        var before:Object = createStructureState(raw, item.value.mods, dict);
        var after:Object = createStructureState(raw, afterMods, dict);
        var oldNames:Object = {};
        for (var i:Number = 0; i < item.value.mods.length; i++) oldNames[item.value.mods[i]] = true;
        for (i = 0; i < afterMods.length; i++) {
            var mod:Object = dict[afterMods[i]];
            if (oldNames[afterMods[i]] && mod && losesDependency(mod, before, after)) return true;
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
