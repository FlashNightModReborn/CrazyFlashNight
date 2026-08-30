import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * ToughnessBuffTooltipBuilder - 装备 toughness 口径的临时韧性 Tooltip
 *
 * 显示格式（单行）：
 * 药效：装备韧性 +2750（10秒）
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.ToughnessBuffTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function ToughnessBuffTooltipBuilder() {
    }

    public function getType():String {
        return "toughnessBuff";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var value:Number = Number(effectData.value);
        if (isNaN(value) || value <= 0) return result;

        result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL));
        result.push("装备韧性 +" + value);

        var duration:Number = Number(effectData.duration);
        if (!isNaN(duration) && duration > 0) {
            result.push("（" + DrugTooltipUtil.framesToSeconds(duration)
                + TooltipConstants.TIP_DRUG_SECOND + "）");
        }
        result.push(DrugTooltipUtil.br());

        return result;
    }
}
