/**
 * UseSwitchStatsBuilder - UseSwitch 条件效果构建器
 *
 * 职责：
 * - 构建 useSwitch 分支下的详细属性显示
 * - 统一处理顶层 stats 和 useCase 分支的属性渲染逻辑
 * - 管理特殊属性（slay/silence/damagetype）的专用 builder 调用
 *
 * 设计原则：
 * - 消除重复：将 TooltipTextBuilder 中的 useSwitch 逻辑抽取到此处
 * - 单一职责：专注于 useSwitch 场景的属性展示
 * - 保持一致性：使用与顶层 stats 相同的格式化规则
 */
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipFormatter;
import org.flashNight.gesh.tooltip.builder.SlayEffectBuilder;
import org.flashNight.gesh.tooltip.builder.SilenceEffectBuilder;
import org.flashNight.gesh.tooltip.TooltipTextBuilder;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder {

    /**
     * 构建 useSwitch 的详细效果展示
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param stats:Object 包含 useSwitch 的 stats 对象
     * @return Void（直接修改 result）
     */
    public static function buildDetailed(result:Array, stats:Object):Void {
        if (!stats || !stats.useSwitch || !stats.useSwitch.useCases) {
            return;
        }

        var useCases = stats.useSwitch.useCases;
        if (useCases.length == 0) {
            return;
        }

        result.push("<font color='" + TooltipConstants.COL_HL + "'>" + TooltipConstants.LBL_USE_SWITCH_EFFECT + "</font><BR>");

        for (var ucIdx = 0; ucIdx < useCases.length; ucIdx++) {
            var useCase = useCases[ucIdx];
            if (!useCase.name) continue;

            result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_FOR + " " + useCase.name + "：</font><BR>");

            // 【新增】显示条件性 provideTags
            if (useCase.provideTagDict) {
                var condTags:Array = [];
                for (var pTag:String in useCase.provideTagDict) {
                    if (ObjectUtil.isInternalKey(pTag)) continue;
                    condTags.push(pTag);
                }
                if (condTags.length > 0) {
                    result.push("  <font color='" + TooltipConstants.COL_COND_PROVIDE + "'>" + TooltipConstants.LBL_COND_PROVIDE_TAGS + "：</font>", condTags.join(", "), "<BR>");
                }
            }

            // 使用统一的属性块渲染方法（带缩进）
            buildStatBlock(result, useCase, "  ");
        }
    }

    /**
     * 构建统一的属性块（可被顶层 stats 和 useCase 共用）
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param statsObj:Object 包含 percentage/multiplier/flat/override/merge/cap 的对象
     * @param indent:String 缩进字符串（如 "  " 或 ""）
     * @return Void（直接修改 result）
     */
    public static function buildStatBlock(result:Array, statsObj:Object, indent:String):Void {
        // 显示 percentage 加成
        if (statsObj.percentage) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.percentage);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                result.push(indent);
                TooltipFormatter.statLine(result, "multiply", key, statsObj.percentage[key], null);
            }
        }

        // 显示 multiplier 独立乘区
        if (statsObj.multiplier) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.multiplier);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                var mValue = statsObj.multiplier[key];
                var label = TooltipConstants.PROPERTY_DICT[key];
                if (!label) label = key;

                var displayText:String;
                if (mValue < 0) {
                    // 负数：显示为倍率
                    var multiplierValue = 1 + mValue;
                    var displayValue = Math.round(multiplierValue * 100) / 100;
                    displayText = "×" + displayValue;
                } else {
                    // 正数：显示为百分比
                    var percentDisplay = Math.round(mValue * 100);
                    displayText = "×+" + percentDisplay + "%";
                }

                result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_MULTIPLIER + "'>", label, " ", displayText, "</FONT> <FONT COLOR='" + TooltipConstants.COL_MULTIPLIER_HINT + "'>" + TooltipConstants.TAG_MULTIPLIER_ZONE + "</FONT><BR>");
            }
        }

        // 显示 flat 加成
        if (statsObj.flat) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.flat);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                // 跳过 slay，使用专门的 SlayEffectBuilder 显示
                if (key == "slay") continue;
                result.push(indent);
                TooltipFormatter.statLine(result, "add", key, statsObj.flat[key], null);
            }
            // 使用 SlayEffectBuilder 处理斩杀线属性
            if (statsObj.flat.slay) {
                result.push(indent);
                SlayEffectBuilder.buildFlat(result, statsObj.flat.slay);
            }
        }

        // 显示 override 覆盖
        if (statsObj.override) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.override);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                // 跳过特殊属性，它们需要专门的 builder 处理
                // actiontype 是根层属性，也需要单独处理
                // singleshoot 需要转换为全自动/半自动显示
                // reloadType 需要转换为整匣换弹/逐发装填显示
                if (key == "damagetype" || key == "magictype" || key == "silence" || key == "slay" || key == "actiontype" || key == "singleshoot" || key == "reloadType") continue;
                result.push(indent);
                TooltipFormatter.statLine(result, "override", key, statsObj.override[key], null);
            }

            // 使用 SlayEffectBuilder 处理斩杀线属性
            if (statsObj.override.slay) {
                result.push(indent);
                SlayEffectBuilder.buildOverride(result, statsObj.override.slay);
            }

            // 显示 actiontype 覆盖（根层属性需要特殊处理）
            if (statsObj.override.actiontype) {
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                result.push(TooltipConstants.LBL_ACTION_TYPE, " → ", statsObj.override.actiontype, "<BR>");
            }
        }

        // 显示 merge 合并
        if (statsObj.merge) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.merge);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                // 跳过嵌套对象，它们需要特殊处理
                if (key == "magicdefence" || key == "skillmultipliers") continue;
                result.push(indent);
                TooltipFormatter.statLine(result, "merge", key, statsObj.merge[key], null);
            }
        }

        // 显示 cap 上限
        if (statsObj.cap) {
            var sortedList = TooltipTextBuilder.getSortedAttrList(statsObj.cap);
            for (var i = 0; i < sortedList.length; i++) {
                var key = sortedList[i];
                var capValue = statsObj.cap[key];
                var label = TooltipConstants.PROPERTY_DICT[key];
                if (!label) label = key;

                if (capValue > 0) {
                    result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " " + TooltipConstants.TIP_CAP_UPPER + ": +", capValue, "</FONT><BR>");
                } else if (capValue < 0) {
                    result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " " + TooltipConstants.TIP_CAP_LOWER + ": ", capValue, "</FONT><BR>");
                }
            }
        }

        // 处理 override 中的特殊对象（criticalhit/magicdefence/skillmultipliers/silence）
        if (statsObj.override) {
            if (statsObj.override.criticalhit) {
                result.push(indent, TooltipTextBuilder.quickBuildCriticalHit(statsObj.override.criticalhit));
            }
            if (statsObj.override.magicdefence) {
                result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(statsObj.override.magicdefence, TooltipConstants.TXT_OVERRIDE));
            }
            if (statsObj.override.skillmultipliers) {
                result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(statsObj.override.skillmultipliers, TooltipConstants.TXT_OVERRIDE));
            }
            // 使用 SilenceEffectBuilder 处理消音效果
            if (statsObj.override.silence) {
                result.push(indent);
                SilenceEffectBuilder.build(result, null, null, statsObj.override, null);
            }
            // 处理射击模式覆盖（singleshoot）
            if (statsObj.override.singleshoot != undefined) {
                var singleshootVal:Boolean = (statsObj.override.singleshoot == true || statsObj.override.singleshoot == "true");
                var fireModeDesc:String = singleshootVal ? TooltipConstants.TIP_FIRE_MODE_SEMI : TooltipConstants.TIP_FIRE_MODE_AUTO;
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                result.push(TooltipConstants.LBL_FIRE_MODE, " → ", fireModeDesc, "<BR>");
            }
            // 处理装填形式覆盖（reloadType）
            if (statsObj.override.reloadType != undefined) {
                var reloadTypeVal:String = statsObj.override.reloadType;
                var reloadTypeDesc:String = (reloadTypeVal == "tube") ? TooltipConstants.TIP_RELOAD_TYPE_TUBE : TooltipConstants.TIP_RELOAD_TYPE_MAG;
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>" + TooltipConstants.TAG_OVERRIDE + " </FONT>");
                result.push(TooltipConstants.LBL_RELOAD_TYPE, " → ", reloadTypeDesc, "<BR>");
            }
        }

        // 处理 merge 中的特殊对象（magicdefence/skillmultipliers）
        if (statsObj.merge) {
            if (statsObj.merge.magicdefence) {
                result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(statsObj.merge.magicdefence, TooltipConstants.TXT_MERGE));
            }
            if (statsObj.merge.skillmultipliers) {
                result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(statsObj.merge.skillmultipliers, TooltipConstants.TXT_MERGE));
            }
        }

        // 显示伤害类型和破击类型（组合显示 damagetype 和 magictype）
        if (statsObj.override && statsObj.override.damagetype) {
            result.push(indent);
            TooltipTextBuilder.quickBuildDamageType(result, statsObj.override);
        }
    }
}
