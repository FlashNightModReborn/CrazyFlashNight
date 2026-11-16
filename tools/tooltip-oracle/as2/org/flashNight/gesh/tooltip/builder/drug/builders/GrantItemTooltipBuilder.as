import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * GrantItemTooltipBuilder - 获得物品词条 Tooltip 构建器
 *
 * 默认隐藏具体物品名（防剧透），除非配置 tooltipSpoiler="true"
 *
 * 显示格式（单行）：
 * - 默认：可能获得额外物品
 * - tooltipSpoiler=true：获得：物品名 x数量（概率%）
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.GrantItemTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function GrantItemTooltipBuilder() {
    }

    public function getType():String {
        return "grantItem";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var name:String = effectData.name;
        var count:Number = Number(effectData.count);
        var chance:Number = Number(effectData.chance);
        var spoiler:Boolean = effectData.tooltipSpoiler === true || effectData.tooltipSpoiler === "true";

        if (!name) return result;
        if (isNaN(count) || count <= 0) count = 1;
        if (isNaN(chance) || chance <= 0 || chance > 1) chance = 1;

        if (spoiler) {
            // 详细显示
            result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_GRANT + "：", TooltipConstants.COL_HL));
            result.push(name);
            if (count > 1) {
                result.push(" x" + count);
            }
            if (chance < 1) {
                result.push("（" + Math.round(chance * 100) + "%" + TooltipConstants.TIP_DRUG_CHANCE + "）");
            }
        } else {
            // 隐藏具体信息
            result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_GRANT_HIDDEN, TooltipConstants.COL_INFO));
        }

        result.push(DrugTooltipUtil.br());

        return result;
    }
}
