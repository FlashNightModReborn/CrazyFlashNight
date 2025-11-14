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
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;

class org.flashNight.gesh.tooltip.builder.ModsBlockBuilder {

    /**
     * 构建配件列表块
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
        // 检查是否有配件
        if (!value.mods || value.mods.length <= 0) {
            return;
        }

        // 标题行
        result.push("<font color='" + TooltipConstants.COL_HL + "'>已安装", value.mods.length, "个配件：</font><BR>");

        // 迭代配件列表
        for (var i:Number = 0; i < value.mods.length; i++) {
            var modName:String = value.mods[i];
            if (!modName) continue; // 跳过空配件名

            var modInfo:Object = EquipmentUtil.modDict[modName];

            // 构建配件显示文本
            result.push("  • ", modName);

            // 检查是否有 tagValue
            if (modInfo && modInfo.tagValue) {
                result.push(" <font color='" + TooltipConstants.COL_INFO + "'>[", modInfo.tagValue, "]</font>");
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
                    result.push(" <font color='" + TooltipConstants.COL_ENHANCE + "'>(", enhancements.join(", "), ")</font>");
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
                    result.push(" <font color='#FF6600'>{", multiplierEnhancements.join(", "), "}</font>");
                }
            }

            // 检查是否有消音属性，添加消音效果简短描述
            if (modInfo && modInfo.override && modInfo.override.silence) {
                var silenceDesc:String = SilenceEffectBuilder.getShortDescription(modInfo.override.silence);
                if (silenceDesc != "") {
                    result.push(" <font color='" + TooltipConstants.COL_SILENCE + "'>[", silenceDesc, "]</font>");
                }
            }

            // 显示useSwitch条件效果提示（仅显示匹配当前装备的条件）
            if (modInfo && modInfo.stats && modInfo.stats.useSwitch && modInfo.stats.useSwitch.useCases) {
                // 构建当前装备的类型列表
                var currentItemTypes:Array = [];
                if (item.use) {
                    var useList:Array = item.use.split(",");
                    for (var ui:Number = 0; ui < useList.length; ui++) {
                        var trimmedUse:String = useList[ui];
                        // 简单的trim实现
                        while (trimmedUse.charAt(0) == " ") trimmedUse = trimmedUse.substring(1);
                        while (trimmedUse.charAt(trimmedUse.length - 1) == " ") trimmedUse = trimmedUse.substring(0, trimmedUse.length - 1);
                        if (trimmedUse.length > 0) currentItemTypes.push(trimmedUse);
                    }
                }
                if (item.weapontype) {
                    var wtList:Array = item.weapontype.split(",");
                    for (var wi:Number = 0; wi < wtList.length; wi++) {
                        var trimmedWT:String = wtList[wi];
                        while (trimmedWT.charAt(0) == " ") trimmedWT = trimmedWT.substring(1);
                        while (trimmedWT.charAt(trimmedWT.length - 1) == " ") trimmedWT = trimmedWT.substring(0, trimmedWT.length - 1);
                        if (trimmedWT.length > 0) {
                            // 避免重复
                            var found:Boolean = false;
                            for (var ci:Number = 0; ci < currentItemTypes.length; ci++) {
                                if (currentItemTypes[ci] == trimmedWT) {
                                    found = true;
                                    break;
                                }
                            }
                            if (!found) currentItemTypes.push(trimmedWT);
                        }
                    }
                }

                var useCases:Array = modInfo.stats.useSwitch.useCases;
                var useSwitchHints:Array = [];

                for (var ucIdx:Number = 0; ucIdx < useCases.length; ucIdx++) {
                    var useCase:Object = useCases[ucIdx];
                    if (!useCase.name) continue;

                    // 检查该分支是否匹配当前装备
                    var branchTypes:Array = useCase.name.split(",");
                    var matched:Boolean = false;
                    for (var bi:Number = 0; bi < branchTypes.length && !matched; bi++) {
                        var trimmedBranch:String = branchTypes[bi];
                        while (trimmedBranch.charAt(0) == " ") trimmedBranch = trimmedBranch.substring(1);
                        while (trimmedBranch.charAt(trimmedBranch.length - 1) == " ") trimmedBranch = trimmedBranch.substring(0, trimmedBranch.length - 1);

                        for (var ti:Number = 0; ti < currentItemTypes.length && !matched; ti++) {
                            if (currentItemTypes[ti] == trimmedBranch) {
                                matched = true;
                            }
                        }
                    }

                    // 只显示匹配的分支效果
                    if (!matched) continue;

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
                                    displayText = "[独立乘区]×" + dispValue;
                                } else {
                                    // 正数：显示为百分比
                                    var mPercent:Number = Math.round(mVal * 100);
                                    displayText = "[独立乘区]×+" + mPercent + "%";
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
                                effects.push(pKey + sign + pPercent + "%");
                                break; // 只显示第一个效果
                            }
                        }
                    }

                    if (effects.length > 0) {
                        // 简化use名称显示
                        var useName:String = useCase.name;
                        if (useName.indexOf(",") != -1) {
                            // 如果有多个use，只显示第一个加"等"
                            var firstUse:String = useName.substring(0, useName.indexOf(","));
                            useName = firstUse + "等";
                        }
                        useSwitchHints.push("对" + useName + ":" + effects.join(","));
                    }
                }

                if (useSwitchHints.length > 0) {
                    result.push(" <font color='#FFCC66'>[", useSwitchHints.join("; "), "]</font>");
                }
            }

            result.push("<BR>");
        }
    }
}
