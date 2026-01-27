/**
 * TagSwitchStatsBuilder - TagSwitch 结构条件加成构建器
 *
 * 职责：
 * - 构建 tagSwitch 分支下的详细属性显示
 * - 显示基于结构标签的条件加成效果
 * - 与 UseSwitchStatsBuilder 共享属性块渲染逻辑
 *
 * 设计原则：
 * - 单一职责：专注于 tagSwitch 场景的属性展示
 * - 保持一致性：使用与 useSwitch 相同的格式化规则
 */
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.builder.UseSwitchStatsBuilder;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.tooltip.builder.TagSwitchStatsBuilder {

    /**
     * 构建 tagSwitch 的详细效果展示
     *
     * @param result:Array 输出缓冲区（就地修改）
     * @param stats:Object 包含 tagSwitch 的 stats 对象
     * @return Void（直接修改 result）
     */
    public static function buildDetailed(result:Array, stats:Object):Void {
        if (!stats || !stats.tagSwitch || !stats.tagSwitch.tagCases) {
            return;
        }

        var tagCases:Array = stats.tagSwitch.tagCases;
        if (tagCases.length == 0) {
            return;
        }

        result.push("<font color='" + TooltipConstants.COL_TAG_SWITCH + "'>" + TooltipConstants.LBL_TAG_SWITCH_EFFECT + "</font><BR>");

        for (var tcIdx:Number = 0; tcIdx < tagCases.length; tcIdx++) {
            var tagCase:Object = tagCases[tcIdx];
            if (!tagCase.name) continue;

            // 显示触发条件：当存在 [标签名] 时：
            result.push("<font color='" + TooltipConstants.COL_INFO + "'>" + TooltipConstants.TIP_WHEN_HAS + " " + tagCase.name + " " + TooltipConstants.TIP_TAG_SUFFIX + "：</font><BR>");

            // 使用 UseSwitchStatsBuilder 的统一属性块渲染方法（带缩进）
            UseSwitchStatsBuilder.buildStatBlock(result, tagCase, "  ");
        }
    }
}
