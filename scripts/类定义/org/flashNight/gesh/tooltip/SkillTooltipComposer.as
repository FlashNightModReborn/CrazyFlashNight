import org.flashNight.gesh.tooltip.TooltipLayout;
import org.flashNight.gesh.tooltip.TooltipConstants;
import org.flashNight.gesh.tooltip.TooltipBridge;
import org.flashNight.gesh.tooltip.ItemUseTypes;

/**
 * SkillTooltipComposer - 技能注释组合器
 *
 * 职责：
 * - 封装技能图标注释的智能分栏渲染逻辑
 * - 与 TooltipComposer（物品注释）平行，专门处理技能类型
 * - 复用 TooltipLayout.shouldSplitSmart 统一判定策略
 *
 * 设计原则：
 * - 减少 _root 污染，把逻辑集中到类库
 * - 与物品注释系统保持一致的分栏策略
 * - 便于未来扩展技能专用的注释功能
 *
 * 使用示例：
 * ```actionscript
 * SkillTooltipComposer.renderSkillTooltipSmart("火球术", 简介文本, 描述文本);
 * ```
 */
class org.flashNight.gesh.tooltip.SkillTooltipComposer {

    /**
     * 技能注释智能分栏渲染
     * @param skillName:String 技能名称（用于图标显示）
     * @param introText:String 简介面板内容（基础信息：名称、类型、冷却、消耗等）
     * @param descriptionText:String 描述内容（技能详细说明，独立显示）
     *
     * 分栏策略（使用 TooltipLayout.shouldSplitSmart 统一判定）：
     * - 短内容：合并显示（描述文本并入简介面板底部）
     * - 长内容：分离显示（主框体显示描述，图标面板显示简介）
     */
    public static function renderSkillTooltipSmart(skillName:String, introText:String, descriptionText:String):Void {
        // 保底清理
        TooltipLayout.hideTooltip();

        // 使用统一的智能分栏判定（技能目前不需要自定义 options，传 null 即可）
        var needSplit:Boolean = TooltipLayout.shouldSplitSmart(descriptionText, introText, null);

        if (needSplit) {
            // 长内容策略：分离显示（主框体 + 图标面板）
            var calculatedWidth:Number = TooltipLayout.estimateWidth(descriptionText);
            TooltipLayout.showTooltip(calculatedWidth, descriptionText);
            TooltipLayout.renderIconTooltip(true, skillName, introText, TooltipConstants.BASE_NUM, ItemUseTypes.TYPE_SKILL);
        } else {
            // 短内容策略：合并显示（描述并入简介面板底部）
            var mergedText:String = introText;
            if (descriptionText && descriptionText.length > 0) {
                mergedText += "<BR>" + descriptionText;
            }
            var mergedWidth:Number = TooltipLayout.estimateWidth(mergedText);
            TooltipLayout.renderIconTooltip(true, skillName, mergedText, mergedWidth, ItemUseTypes.TYPE_SKILL);

            // 隐藏主框体（仅显示图标面板）
            TooltipBridge.setTextContent("main", "");
            TooltipBridge.setVisibility("main", false);
            TooltipBridge.setVisibility("mainBg", false);
        }
    }
}
