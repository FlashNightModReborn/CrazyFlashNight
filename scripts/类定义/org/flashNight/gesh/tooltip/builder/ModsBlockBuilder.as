/**
 * ModsBlockBuilder - 配件列表构建器
 * 
 * 职责：
 * - 构建配件列表显示
 * - 使用 EquipmentUtil.modDict 获取配件信息
 * - 处理配件 tagValue 显示
 * 
 * 设计原则：
 * - 无副作用：仅通过 push 修改传入的 result 数组
 * - 使用 TooltipFormatter 统一格式化
 * - 保持与原逻辑完全一致的输出
 */
import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.EquipmentUtil;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.equipment.ModRegistry;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;

class org.flashNight.gesh.tooltip.builder.ModsBlockBuilder {

    /**
     * 构建配件列表块（旧 HTML 输出）
     *
     * 迁移自 TooltipTextBuilder.buildEquipmentStats Line 412-423
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param baseItem:BaseItem 物品实例
     * @param item:Object 物品数据
     * @param value:Object 物品数值对象（包含 mods 数组）
     * @return Void（直接修改 result）
     */
    public static function build(result:Array, baseItem:BaseItem, item:Object, value:Object):Void {
        buildWithRows(result, baseItem, item, value);
    }

    /**
     * 与 build 同源的一次收集：旧 HTML 写入 result，同时返回结构化描述
     * {kind:"attachments", title, rows:[{name, effect}]}，供原生注释框把
     * 「已安装插件」渲染为带图标的独立子框。rows[].effect 仍是受限 HTML
     * 片段（颜色标记），由 NativeTooltipDocument 在文档边界展开为 runs。
     *
     * @return Object|null 无配件时返回 null（result 不变）
     */
    public static function buildWithRows(result:Array, baseItem:BaseItem, item:Object,
            value:Object):Object {
        var collected:Object = collect(baseItem, item, value);
        if (collected == null) return null;

        // 旧路径输出保持逐字节不变：标题行 + "  • 名称" + 数值效果 +
        // （有数值效果时另起一行）覆写/条件效果。
        result.push(collected.titleHtml);
        var rows:Array = collected.rows;
        var attachments:Array = [];
        for (var i:Number = 0; i < rows.length; i++) {
            var row:Object = rows[i];
            result.push("  • ", row.name, row.tagHtml, row.percentageHtml, row.multiplierHtml);
            if (row.overrideParts.length > 0) {
                if (row.hasNumeric) result.push("<BR>    ");
                result.push(row.overrideParts.join(""));
            }
            result.push("<BR>");

            var effect:String = row.tagHtml + row.percentageHtml + row.multiplierHtml;
            if (row.overrideParts.length > 0) {
                effect += " " + row.overrideParts.join("");
            }
            var outRow:Object = {name:row.name, effect:effect};
            if (row.icon != null) outRow.icon = row.icon;
            attachments.push(outRow);
        }

        return {
            kind: "attachments",
            title: TooltipConstants.LBL_INSTALLED_MODS + rows.length
                + TooltipConstants.LBL_MOD_COUNT_SUFFIX,
            rows: attachments
        };
    }

    /**
     * 单遍收集：每个配件一行，效果字符串按旧输出顺序分片保存。
     * 无配件时返回 null。
     */
    private static function collect(baseItem:BaseItem, item:Object, value:Object):Object {
        // 检查是否有配件
        if (value == null || !value.mods || value.mods.length <= 0) {
            return null;
        }

        // 标题行
        var titleHtml:String = "<font color='" + TooltipConstants.COL_HL + "'>"
            + TooltipConstants.LBL_INSTALLED_MODS + value.mods.length
            + TooltipConstants.LBL_MOD_COUNT_SUFFIX + "：</font><BR>";

        // 预取原始子弹类型（未含配件效果），供 bulletSwitch 摘要使用
        var rawItemData:Object = baseItem ? ItemUtil.getItemData(baseItem.name) : null;
        var baseBulletType:String = (rawItemData && rawItemData.data && rawItemData.data.bullet) ? rawItemData.data.bullet : "";
        var itemUseLookup:Object = buildItemUseLookup(item, value);
        var rows:Array = [];

        // 迭代配件列表
        for (var i:Number = 0; i < value.mods.length; i++) {
            var modName:String = value.mods[i];
            if (!modName) continue; // 跳过空配件名

            var modInfo:Object = EquipmentUtil.modDict[modName];
            var row:Object = {
                name: modName,
                icon: null,
                tagHtml: "",
                percentageHtml: "",
                multiplierHtml: "",
                overrideParts: [],
                hasNumeric: false
            };
            // 子框行首图标：插件名与物品名 1:1，取物品数据的 icon 资产键。
            var modItemData:Object = ItemUtil.getItemData(modName);
            if (modItemData != null && modItemData.icon != undefined && modItemData.icon != "") {
                row.icon = String(modItemData.icon);
            }

            // 检查是否有 tagValue
            if (modInfo && modInfo.tagValue) {
                row.tagHtml = " <font color='" + TooltipConstants.COL_INFO + "'>["
                    + modInfo.tagValue + "]</font>";
            }

            // 显示配件提供的百分比增幅（汇总显示 - percentage用圆括号）
            if (modInfo && modInfo.stats && modInfo.stats.percentage) {
                var enhancements:Array = [];
                var percentage:Object = modInfo.stats.percentage;

                // 收集所有百分比属性
                for (var prop:String in percentage) {
                    var percentValue:Number = Number(percentage[prop]);
                    if (!isNaN(percentValue) && percentValue != 0) {
                        var sign:String = percentValue > 0 ? "+" : "";
                        var percent:Number = Math.round(percentValue * 100);
                        enhancements.push(sign + percent + "%");
                    }
                }

                // 如果有增幅，显示在配件名后（圆括号表示加法合并乘区）
                if (enhancements.length > 0) {
                    row.percentageHtml = " <font color='" + TooltipConstants.COL_ENHANCE
                        + "'>(" + enhancements.join(", ") + ")</font>";
                    row.hasNumeric = true;
                }
            }

            // 显示配件提供的独立乘区增幅（multiplier用花括号 + 不同颜色）
            if (modInfo && modInfo.stats && modInfo.stats.multiplier) {
                var multiplierEnhancements:Array = [];
                var multiplier:Object = modInfo.stats.multiplier;

                // 收集所有multiplier属性
                for (var mprop:String in multiplier) {
                    var mValue:Number = Number(multiplier[mprop]);
                    if (!isNaN(mValue) && mValue != 0) {
                        var mtext:String;
                        if (mValue < 0) {
                            // 负数：显示为倍率（如 ×0.65）
                            var multiplierValue:Number = 1 + mValue;  // 1 + (-0.35) = 0.65
                            var displayValue:Number = Math.round(multiplierValue * 100) / 100;  // 保留2位小数
                            mtext = "×" + displayValue;
                        } else {
                            // 正数：显示为百分比（如 ×+15%）
                            var mpercent:Number = Math.round(mValue * 100);
                            mtext = "×+" + mpercent + "%";
                        }
                        multiplierEnhancements.push(mtext);
                    }
                }

                // 如果有增幅，显示在配件名后（花括号表示独立乘区）
                if (multiplierEnhancements.length > 0) {
                    row.multiplierHtml = " <font color='" + TooltipConstants.COL_MULTIPLIER
                        + "'>{" + multiplierEnhancements.join(", ") + "}</font>";
                    row.hasNumeric = true;
                }
            }

            // 收集覆写/条件效果（silence/fireMode/reloadType/useSwitch/bulletSwitch）
            // 若同时存在数值效果，则另起一行显示，避免单行过长
            var overrideEffectParts:Array = [];

            // 检查是否有消音属性，添加消音效果简短描述
            // 修复：从 modInfo.stats.override 读取，而不是 modInfo.override
            if (modInfo && modInfo.stats && modInfo.stats.override && modInfo.stats.override.silence) {
                var silenceDesc:String = SilenceEffectBuilder.getShortDescription(modInfo.stats.override.silence);
                if (silenceDesc != "") {
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_SILENCE + "'>[" + silenceDesc + "]</font>");
                }
            }

            // 检查是否有射击模式修改属性（singleshoot override）
            if (modInfo && modInfo.stats && modInfo.stats.override && modInfo.stats.override.singleshoot != undefined) {
                var singleshootVal:Boolean = (modInfo.stats.override.singleshoot == true || modInfo.stats.override.singleshoot == "true");
                var fireModeDesc:String = singleshootVal ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
                overrideEffectParts.push(" <font color='" + TooltipConstants.COL_HL + "'>[" + TooltipConstants.LBL_FIRE_MODE + ": " + fireModeDesc + "]</font>");
            }

            // 检查是否有装填形式修改属性（reloadType override）
            if (modInfo && modInfo.stats && modInfo.stats.override && modInfo.stats.override.reloadType != undefined) {
                var reloadTypeVal:String = modInfo.stats.override.reloadType;
                var reloadTypeDesc:String = (reloadTypeVal == "tube") ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
                overrideEffectParts.push(" <font color='" + TooltipConstants.COL_HL + "'>[" + TooltipConstants.LBL_RELOAD_TYPE + ": " + reloadTypeDesc + "]</font>");
            }

            // 显示useSwitch条件效果提示（仅显示匹配当前装备的条件）
            if (modInfo && modInfo.stats && modInfo.stats.useSwitch && modInfo.stats.useSwitch.useCases) {
                // 与运行时共用同一匹配器，确保 use:/weapontype: 限定符和 default 语义一致。
                var useCases:Array = ModRegistry.matchUseSwitchAll(modInfo, itemUseLookup);
                var useSwitchHints:Array = [];

                for (var ucIdx:Number = 0; ucIdx < useCases.length; ucIdx++) {
                    var useCase:Object = useCases[ucIdx];
                    // 维持旧摘要密度：default 分支仍由基础数值区表达，不额外加条件标签。
                    if (!useCase || useCase._isDefault || !useCase.name) continue;

                    // 收集此分支的主要效果
                    var effects:Array = [];

                    // 检查multiplier效果
                    if (useCase.multiplier) {
                        for (var mKey:String in useCase.multiplier) {
                            // 跳过内部字段
                            if (ObjectUtil.isInternalKey(mKey)) continue;

                            var mVal:Number = Number(useCase.multiplier[mKey]);
                            if (!isNaN(mVal) && mVal != 0) {
                                var displayText:String;
                                if (mVal < 0) {
                                    // 负数：显示为倍率
                                    var multValue:Number = 1 + mVal;
                                    var dispValue:Number = Math.round(multValue * 100) / 100;
                                    displayText = TooltipConstants.TAG_MULTIPLIER_ZONE + "×" + dispValue;
                                } else {
                                    // 正数：显示为百分比
                                    var mPercent:Number = Math.round(mVal * 100);
                                    displayText = TooltipConstants.TAG_MULTIPLIER_ZONE + "×+" + mPercent + "%";
                                }
                                effects.push(displayText);
                                break; // 只显示第一个效果，避免信息过多
                            }
                        }
                    }

                    // 检查percentage效果（如果没有multiplier效果）
                    if (effects.length == 0 && useCase.percentage) {
                        for (var pKey:String in useCase.percentage) {
                            // 跳过内部字段
                            if (ObjectUtil.isInternalKey(pKey)) continue;

                            var pVal:Number = Number(useCase.percentage[pKey]);
                            if (!isNaN(pVal) && pVal != 0) {
                                var pPercent:Number = Math.round(pVal * 100);
                                var sign:String = pPercent > 0 ? "+" : "";
                                // 使用属性名映射表转换为中文显示名
                                var pLabel:String = TooltipConstants.PROPERTY_DICT[pKey] || pKey;
                                effects.push(pLabel + sign + pPercent + "%");
                                break; // 只显示第一个效果
                            }
                        }
                    }

                    // 声明式命中行为是嵌套 merge 对象，不能走通用 [object Object] 展示。
                    if (useCase.merge && useCase.merge.hitBehavior) {
                        var hitBehaviorSummary:String = UseSwitchStatsBuilder.buildHitBehaviorSummary(useCase.merge.hitBehavior);
                        if (hitBehaviorSummary.length > 0) {
                            effects.push(hitBehaviorSummary);
                        }
                    }

                    if (effects.length > 0) {
                        var useName:String = UseSwitchStatsBuilder.getUseCaseDisplayName(useCase.name);
                        useSwitchHints.push(TooltipConstants.TIP_FOR + useName + ":" + effects.join(","));
                    }
                }

                if (useSwitchHints.length > 0) {
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>[" + useSwitchHints.join("; ") + "]</font>");
                }
            }

            // 显示bulletSwitch条件效果提示（仅显示匹配当前装备子弹类型的分支）
            // 使用预取的原始子弹类型，与 EquipmentCalculator 的判定一致

            if (modInfo && modInfo.stats && modInfo.stats.bulletSwitch && modInfo.stats.bulletSwitch.bulletCases) {
                var matchedCases:Array = ModRegistry.matchBulletSwitchAll(modInfo, baseBulletType);

                if (matchedCases && matchedCases.length > 0) {
                    var bsHints:Array = [];
                    for (var bci:Number = 0; bci < matchedCases.length; bci++) {
                        var bCase:Object = matchedCases[bci];
                        var bEffects:Array = [];

                        // 检查override效果（如split）
                        if (bCase.override) {
                            for (var oKey:String in bCase.override) {
                                if (ObjectUtil.isInternalKey(oKey)) continue;
                                var oLabel:String = TooltipConstants.PROPERTY_DICT[oKey] || oKey;
                                bEffects.push(oLabel + "→" + bCase.override[oKey]);
                                break;
                            }
                        }

                        // 检查percentage效果（如diffusion）
                        if (bEffects.length == 0 && bCase.percentage) {
                            for (var bpKey:String in bCase.percentage) {
                                if (ObjectUtil.isInternalKey(bpKey)) continue;
                                var bpVal:Number = Number(bCase.percentage[bpKey]);
                                if (!isNaN(bpVal) && bpVal != 0) {
                                    var bpPercent:Number = Math.round(bpVal * 100);
                                    var bpSign:String = bpPercent > 0 ? "+" : "";
                                    var bpLabel:String = TooltipConstants.PROPERTY_DICT[bpKey] || bpKey;
                                    bEffects.push(bpLabel + bpSign + bpPercent + "%");
                                    break;
                                }
                            }
                        }

                        if (bEffects.length > 0) {
                            // 判断是 default 分支还是命名分支
                            var bLabel:String;
                            if (bCase._isDefault || !bCase.name) {
                                bLabel = TooltipConstants.TIP_DEFAULT_BRANCH;
                            } else {
                                // 翻译类型名
                                var bNames:Array = bCase.name.split(",");
                                var bDisplayNames:Array = [];
                                for (var bni:Number = 0; bni < bNames.length; bni++) {
                                    var bTrimmed:String = bNames[bni];
                                    while (bTrimmed.charAt(0) == " ") bTrimmed = bTrimmed.substr(1);
                                    while (bTrimmed.charAt(bTrimmed.length - 1) == " ") bTrimmed = bTrimmed.substr(0, bTrimmed.length - 1);
                                    var bCnName:String = TooltipConstants.BULLET_TYPE_NAMES[bTrimmed];
                                    bDisplayNames.push(bCnName ? bCnName : bTrimmed);
                                }
                                bLabel = bDisplayNames.join("/");
                            }
                            bsHints.push(bLabel + ":" + bEffects.join(","));
                        }
                    }

                    if (bsHints.length > 0) {
                        overrideEffectParts.push(" <font color='" + TooltipConstants.COL_BULLET_SWITCH + "'>[" + bsHints.join("; ") + "]</font>");
                    }
                }
            }

            // 显示skillSwitch解析后的当前战技
            if (modInfo && modInfo.skillSwitch) {
                var resolvedSkill:Object = ModRegistry.resolveSkillForUse(modInfo, itemUseLookup);
                if (resolvedSkill && resolvedSkill.skillname) {
                    overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>" + TooltipConstants.LBL_ACTIVE_SKILL + resolvedSkill.skillname + "</font>");
                }
            }

            if (modInfo && modInfo.subweapon) {
                var subweaponName:String = modInfo.subweapon.name ? modInfo.subweapon.name : modName;
                overrideEffectParts.push(" <font color='" + TooltipConstants.COL_USE_SWITCH + "'>" + TooltipConstants.LBL_SUBWEAPON + subweaponName + "</font>");
            }

            row.overrideParts = overrideEffectParts;
            rows.push(row);
        }

        return {titleHtml:titleHtml, rows:rows};
    }

    private static function buildItemUseLookup(item:Object, value:Object):Object {
        var grantedUses:Object = null;

        if (value && value.mods) {
            for (var i:Number = 0; i < value.mods.length; i++) {
                var modInfo:Object = EquipmentUtil.modDict[value.mods[i]];
                if (modInfo && modInfo.grantsUseDict) {
                    if (!grantedUses) grantedUses = {};
                    for (var gu:String in modInfo.grantsUseDict) {
                        grantedUses[gu] = true;
                    }
                }
            }
        }

        return ModRegistry.buildItemUseLookup(
            item && item.use ? item.use : "",
            item && item.weapontype ? item.weapontype : "",
            grantedUses
        );
    }
}
