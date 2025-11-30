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

        result.push("<font color='" + TooltipConstants.COL_HL + "'>【按装备类型追加效果】</font><BR>");

        for (var ucIdx = 0; ucIdx < useCases.length; ucIdx++) {
            var useCase = useCases[ucIdx];
            if (!useCase.name) continue;

            result.push("<font color='" + TooltipConstants.COL_INFO + "'>对 " + useCase.name + "：</font><BR>");

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

                result.push(indent, "<FONT COLOR='#FF6600'>", label, " ", displayText, "</FONT> <FONT COLOR='#FF9944'>[独立乘区]</FONT><BR>");
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
                if (key == "damagetype" || key == "magictype" || key == "silence" || key == "slay" || key == "actiontype") continue;
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
                result.push(indent, "<FONT COLOR='", TooltipConstants.COL_HL, "'>[覆盖] </FONT>");
                result.push("动作类型 → ", statsObj.override.actiontype, "<BR>");
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
                    result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 增益上限: +", capValue, "</FONT><BR>");
                } else if (capValue < 0) {
                    result.push(indent, "<FONT COLOR='" + TooltipConstants.COL_INFO + "'>", label, " 减益下限: ", capValue, "</FONT><BR>");
                }
            }
        }

        // 处理 override 中的特殊对象（criticalhit/magicdefence/skillmultipliers/silence）
        if (statsObj.override) {
            if (statsObj.override.criticalhit) {
                result.push(indent, TooltipTextBuilder.quickBuildCriticalHit(statsObj.override.criticalhit));
            }
            if (statsObj.override.magicdefence) {
                result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(statsObj.override.magicdefence, "覆盖"));
            }
            if (statsObj.override.skillmultipliers) {
                result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(statsObj.override.skillmultipliers, "覆盖"));
            }
            // 使用 SilenceEffectBuilder 处理消音效果
            if (statsObj.override.silence) {
                result.push(indent);
                SilenceEffectBuilder.build(result, null, null, statsObj.override, null);
            }
        }

        // 处理 merge 中的特殊对象（magicdefence/skillmultipliers）
        if (statsObj.merge) {
            if (statsObj.merge.magicdefence) {
                result.push(indent, TooltipTextBuilder.quickBuildMagicDefence(statsObj.merge.magicdefence, "合并"));
            }
            if (statsObj.merge.skillmultipliers) {
                result.push(indent, TooltipTextBuilder.quickBuildSkillMultipliers(statsObj.merge.skillmultipliers, "合并"));
            }
        }

        // 显示伤害类型和破击类型（组合显示 damagetype 和 magictype）
        if (statsObj.override && statsObj.override.damagetype) {
            result.push(indent);
            TooltipTextBuilder.quickBuildDamageType(result, statsObj.override);
        }
    }
}
