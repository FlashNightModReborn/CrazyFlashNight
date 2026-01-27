import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.string.StringUtils;
import org.flashNight.arki.item.equipment.PropertyOperators;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.arki.item.equipment.TierSystem;

/** 
 * EquipmentCalculator - 装备数值纯计算类
 *
 * 提供装备数值计算的纯函数实现，无副作用，便于测试
 * 输入：itemData, value, config, modRegistry
 * 输出：计算后的新 data
 *
 * ============================================================================
 * 性能优化说明 (2024-12-25)
 * ============================================================================
 *
 * 【方法选择指南】
 * - calculateInPlace: 就地计算，调用方负责克隆。用于已克隆数据的场景（如BaseItem.getData）
 * - calculatePure: 纯函数版本，内部克隆。用于预览/测试或需要保留原始数据的场景
 * - calculate: 兼容旧接口，内部调用calculatePure
 *
 * 【性能收益】
 * - 消除冗余克隆: ItemUtil.getItemData已克隆，使用calculateInPlace避免二次克隆（节省~48ms/批次）
 * - 延迟baseData克隆: 仅当存在cap修改器时才克隆（节省~12ms/批次，视装备配置）
 *
 * @author 重构自 EquipmentUtil
 */
class org.flashNight.arki.item.equipment.EquipmentCalculator {

    /**
     * 就地计算装备数据（高性能版本）
     * 直接修改传入的itemData，不进行克隆
     *
     * 【重要】调用方必须确保传入的itemData是可修改的副本！
     * 典型用法：配合 ItemUtil.getItemData()（已返回克隆数据）使用
     *
     * 【性能优势】
     * - 省去 calculatePure 中的深度克隆（约48ms/批次）
     * - 延迟 baseData 克隆，仅在需要时执行（约12ms/批次）
     *
     * @param itemData 物品数据（会被直接修改）
     * @param value 装备值对象 {level, tier, mods}
     * @param config 配置数据（必须包含 tierNameToKeyDict, defaultTierDataDict, levelStatList）
     * @param modRegistry 配件注册表
     * @return 修改后的itemData（与传入的是同一对象）
     */
    public static function calculateInPlace(itemData:Object, value:Object, config:Object, modRegistry:Object):Object {
        var data:Object = itemData.data;

        // Step 1: 应用进阶数据
        if (value.tier) {
            TierSystem.applyTierData(itemData, value.tier, config);
            // applyTierData 可能修改了 data 引用指向的对象，需要重新获取
            data = itemData.data;
        }

        // 若没有强化和插件则直接返回
        if (value.level < 2 && (!value.mods || value.mods.length <= 0)) {
            return itemData;
        }

        // Step 2: 构建基础强化倍率
        var baseMultiplier:Object = buildBaseMultiplier(value.level, config.levelStatList);

        // Step 3: 累积配件修改器
        // 【扩展】传入完整 itemData 以支持 tagSwitch（基于结构的条件加成）
        var modifiers:Object = accumulateModifiers(value.mods, itemData, modRegistry);

        // Step 4: 按顺序应用所有运算符
        applyOperatorsInOrder(data, baseMultiplier, modifiers);

        // Step 5: 替换战技
        // 使用 cloneFast：skill 是配件定义的简单对象，无循环引用
        if (modifiers.skill) {
            itemData.skill = ObjectUtil.cloneFast(modifiers.skill);
        }

        // Step 6: 应用根层属性覆盖（actiontype等定义在item根层而非item.data中的属性）
        applyRootLevelOverrides(itemData, modifiers.overrider);

        return itemData;
    }

    /**
     * 计算装备数据（纯函数版本）
     * 不修改原始数据，返回新的计算结果
     *
     * 此方法是完全独立的纯函数，包含完整的计算流程（含进阶应用）。
     * 所有配置从 config 参数读取，不依赖全局状态，可直接用于预览/测试。
     *
     * 【重要】config 参数必须包含完整的进阶配置，否则 tier 不会被应用：
     *   - tierNameToKeyDict: 进阶名称到数据键的映射（如 {二阶: "data_2"}）
     *   - defaultTierDataDict: 默认进阶数据（当装备自身无进阶数据时使用）
     *   - levelStatList: 强化等级倍率数组（用于强化计算）
     *
     * 【与线上流程的差异】
     *   - 线上流程（EquipmentUtil.calculateData）使用 EquipmentConfigManager 全局配置
     *   - 本方法仅使用传入的 config，不会回退到全局配置
     *   - 若需与线上结果一致，请传入 EquipmentConfigManager.getFullConfig()
     *
     * 【测试/预览用法】
     *   var cfg = EquipmentConfigManager.getFullConfig();
     *   var result = EquipmentCalculator.calculatePure(itemData, value, cfg, modDict);
     *
     * 【性能说明】
     * 此方法会进行深度克隆以保证纯函数语义。若调用方已持有克隆数据，
     * 建议使用 calculateInPlace 以获得更好的性能。
     *
     * @param itemData 原始物品数据（不会被修改）
     * @param value 装备值对象 {level, tier, mods}
     * @param config 配置数据（必须包含 tierNameToKeyDict, defaultTierDataDict, levelStatList）
     * @param modRegistry 配件注册表
     * @return 计算后的新数据对象
     */
    public static function calculatePure(itemData:Object, value:Object, config:Object, modRegistry:Object):Object {
        // 深度克隆，避免修改原始数据
        var newItemData:Object = ObjectUtil.clone(itemData);
        // 委托给就地计算版本
        return calculateInPlace(newItemData, value, config, modRegistry);
    }

    /**
     * 构建基础强化倍率
     * @private
     */
    private static function buildBaseMultiplier(level:Number, levelStatList:Array):Object {
        if (level <= 1 || !levelStatList) return {};

        var maxLevel:Number = levelStatList.length - 1;
        if (level > maxLevel) level = maxLevel;

        var levelMultiplier:Number = levelStatList[level];
        return {
            power: levelMultiplier,
            defence: levelMultiplier,
            damage: levelMultiplier,
            force: levelMultiplier,
            punch: levelMultiplier,
            knifepower: levelMultiplier,
            gunpower: levelMultiplier,
            hp: levelMultiplier,
            mp: levelMultiplier
        };
    }

    /**
     * 累积配件的各种修改器（优化版本）
     * 支持 useSwitch（基于装备类型）和 tagSwitch（基于结构标签）
     * @private
     */
    private static function accumulateModifiers(mods:Array, itemData:Object, modRegistry:Object):Object {
        var adder:Object = {};
        var multiplier:Object = {};
        var overrider:Object = {};
        var merger:Object = {};
        var capper:Object = {};
        var multiplierZone:Object = {};
        var skill:Object = null;

        var itemUse:String = itemData.use || "";
        var itemWeaponType:String = itemData.weapontype || "";

        // 【方案A实施】使用ModRegistry.buildItemUseLookup（单一真源）
        var useLookup:Object = ModRegistry.buildItemUseLookup(itemUse, itemWeaponType);

        // 【新增】第一轮：收集所有 presentTags（装备固有 + 配件静态 + 配件条件性）
        // 这样 tagSwitch 可以基于完整的结构信息进行判断
        var presentTags:Object = buildPresentTags(mods, itemData, useLookup, modRegistry);

        // 第二轮：遍历配件，累积修改器
        for (var i:Number = 0; i < mods.length; i++) {
            var modInfo:Object = modRegistry[mods[i]];
            if (!modInfo) continue;

            // 1. 先应用基础stats（词条主体 - 无条件生效）
            applyStatsToAccumulators(modInfo.stats, adder, multiplier, overrider, merger, capper, multiplierZone);

            // 2. 应用所有匹配的useSwitch分支（基于装备类型的条件词条）
            var matchedUseCases:Array = ModRegistry.matchUseSwitchAll(modInfo, useLookup);
            if (matchedUseCases && matchedUseCases.length > 0) {
                for (var mc:Number = 0; mc < matchedUseCases.length; mc++) {
                    applyStatsToAccumulators(
                        matchedUseCases[mc],
                        adder, multiplier, overrider, merger, capper, multiplierZone
                    );
                }
            }

            // 3. 【新增】应用所有匹配的tagSwitch分支（基于结构标签的条件加成）
            var matchedTagCases:Array = ModRegistry.matchTagSwitchAll(modInfo, presentTags);
            if (matchedTagCases && matchedTagCases.length > 0) {
                for (var tc:Number = 0; tc < matchedTagCases.length; tc++) {
                    applyStatsToAccumulators(
                        matchedTagCases[tc],
                        adder, multiplier, overrider, merger, capper, multiplierZone
                    );
                }
            }

            // 查找战技
            if (!skill && modInfo.skill) {
                skill = modInfo.skill;
            }
        }

        return {
            adder: adder,
            multiplier: multiplier,
            overrider: overrider,
            merger: merger,
            capper: capper,
            multiplierZone: multiplierZone,
            skill: skill
        };
    }

    /**
     * 【新增】构建当前装备的完整 presentTags
     * 包含：装备固有结构 + 配件静态 provideTags + 配件条件性 provideTags
     * @private
     */
    private static function buildPresentTags(mods:Array, itemData:Object, useLookup:Object, modRegistry:Object):Object {
        var presentTags:Object = {};

        // 1. 装备固有结构标签
        if (itemData.inherentTags) {
            var inherentArr:Array = itemData.inherentTags.split(",");
            for (var j:Number = 0; j < inherentArr.length; j++) {
                var tag:String = StringUtils.trim(inherentArr[j]);
                if (tag.length > 0) {
                    presentTags[tag] = true;
                }
            }
        }

        // 2. 遍历配件，收集 provideTags
        for (var i:Number = 0; i < mods.length; i++) {
            var modInfo:Object = modRegistry[mods[i]];
            if (!modInfo) continue;

            // 静态 provideTags
            if (modInfo.provideTagDict) {
                for (var st:String in modInfo.provideTagDict) {
                    presentTags[st] = true;
                }
            }

            // 条件性 provideTags（基于 useSwitch）
            var matchedCases:Array = ModRegistry.matchUseSwitchAll(modInfo, useLookup);
            if (matchedCases && matchedCases.length > 0) {
                for (var mc:Number = 0; mc < matchedCases.length; mc++) {
                    var useCase:Object = matchedCases[mc];
                    if (useCase.provideTagDict) {
                        for (var ct:String in useCase.provideTagDict) {
                            presentTags[ct] = true;
                        }
                    }
                }
            }
        }

        return presentTags;
    }

    // 【方案A实施】buildUseLookup和matchUseCase已移至ModRegistry
    // 这些函数已被删除，统一使用ModRegistry的实现避免重复
    // ModRegistry.buildItemUseLookup - 构建use/weapontype查找表
    // ModRegistry.matchUseSwitch - 匹配useSwitch分支

    /**
     * 将stats应用到累积器
     * @private
     */
    private static function applyStatsToAccumulators(stats:Object, adder:Object, multiplier:Object,
                                                      overrider:Object, merger:Object, capper:Object,
                                                      multiplierZone:Object):Void {
        if (!stats) return;

        // 应用各种修改器
        if (stats.flat) PropertyOperators.add(adder, stats.flat, 0);
        if (stats.percentage) PropertyOperators.add(multiplier, stats.percentage, 1);
        if (stats.override) PropertyOperators.override(overrider, stats.override);
        if (stats.merge) PropertyOperators.merge(merger, stats.merge);
        if (stats.cap) PropertyOperators.add(capper, stats.cap, 0);

        // 独立乘区处理
        if (stats.multiplier) {
            for (var key:String in stats.multiplier) {
                var p:Number = stats.multiplier[key];
                if (isNaN(p)) continue;

                var factor:Number = 1 + p;
                if (factor < 0.01) factor = 0.01;

                if (!multiplierZone[key]) {
                    multiplierZone[key] = factor;
                } else {
                    multiplierZone[key] *= factor;
                }
            }
        }
    }

    /**
     * 按照固定顺序应用所有运算符
     *
     * 【性能优化】延迟克隆baseData
     * - 仅当存在cap修改器时才进行克隆（节省约12ms/批次）
     * - 检测capper是否为空对象的开销远小于深度克隆
     *
     * @private
     */
    private static function applyOperatorsInOrder(data:Object, baseMultiplier:Object, modifiers:Object):Void {
        // 构建最终倍率（增量形式合并）
        var finalMultiplier:Object = {};

        // 基础倍率转增量
        for (var key:String in baseMultiplier) {
            var baseValue:Number = Number(baseMultiplier[key]);
            if (!isNaN(baseValue)) {
                finalMultiplier[key] = baseValue - 1;
            }
        }

        // 配件百分比累加
        if (modifiers.multiplier) {
            for (var modKey:String in modifiers.multiplier) {
                var modValue:Number = Number(modifiers.multiplier[modKey]);
                if (!isNaN(modValue)) {
                    var increment:Number = modValue - 1;
                    if (!isNaN(finalMultiplier[modKey])) {
                        finalMultiplier[modKey] += increment;
                    } else {
                        finalMultiplier[modKey] = increment;
                    }
                }
            }
        }

        // 还原为倍率
        for (var finalKey:String in finalMultiplier) {
            finalMultiplier[finalKey] = 1 + finalMultiplier[finalKey];
        }

        // 【优化】延迟克隆：仅当存在cap修改器时才保存基础属性副本
        var hasCapper:Boolean = false;
        var capper:Object = modifiers.capper;
        for (var capKey:String in capper) {
            hasCapper = true;
            break;
        }
        // 使用 cloneFast：data 是扁平的数值对象，无循环引用
        var baseData:Object = hasCapper ? ObjectUtil.cloneFast(data) : null;

        // 按顺序应用运算符
        PropertyOperators.multiply(data, finalMultiplier);               // 1. 百分比乘法
        if (modifiers.multiplierZone) {
            PropertyOperators.multiply(data, modifiers.multiplierZone);  // 2. 独立乘区
        }
        PropertyOperators.add(data, modifiers.adder, 0);                 // 3. 固定值加成
        // 使用 cloneFast：overrider 是配件定义的简单对象，无循环引用
        PropertyOperators.override(data, ObjectUtil.cloneFast(modifiers.overrider)); // 4. 覆盖值
        PropertyOperators.merge(data, modifiers.merger);                 // 5. 深度合并

        // 【优化】仅当baseData存在时应用cap
        if (baseData) {
            PropertyOperators.applyCap(data, capper, baseData);          // 6. 上限限制
        }
    }

    /**
     * 需要应用到根层的属性列表
     * 这些属性定义在 item.xxx 而非 item.data.xxx 中
     * @private
     */
    private static var ROOT_LEVEL_PROPERTIES:Array = ["actiontype"];

    /**
     * 应用根层属性覆盖
     * 处理定义在装备根层（如actiontype）而非data层的属性覆盖
     * @private
     * @param itemData 装备数据对象（会被修改）
     * @param overrider 覆盖器对象
     */
    private static function applyRootLevelOverrides(itemData:Object, overrider:Object):Void {
        if (!overrider) return;

        for (var i:Number = 0; i < ROOT_LEVEL_PROPERTIES.length; i++) {
            var prop:String = ROOT_LEVEL_PROPERTIES[i];
            if (overrider[prop] !== undefined) {
                itemData[prop] = overrider[prop];
            }
        }
    }

    /**
     * 兼容旧接口：修改原始数据
     *
     * 【注意】此方法会克隆后再计算，适用于需要保护原始数据的场景。
     * 如果调用方已持有克隆数据，请直接使用 calculateInPlace 以获得更好性能。
     *
     * @param itemData 原始物品数据（会被修改）
     * @param value 装备值对象
     * @param config 配置数据
     * @param modRegistry 配件注册表
     */
    public static function calculate(itemData:Object, value:Object, config:Object, modRegistry:Object):Void {
        // 调用纯函数版本
        var newData:Object = calculatePure(itemData, value, config, modRegistry);

        // 将结果写回原始对象
        for (var key:String in newData) {
            itemData[key] = newData[key];
        }
    }
}
