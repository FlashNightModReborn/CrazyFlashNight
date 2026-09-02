import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * ResistanceBuffTooltipBuilder - 七属性全抗临时增益 Tooltip
 *
 * 显示格式（单行）：
 * 药效：全属性抗性 +10（10秒）
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.ResistanceBuffTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function ResistanceBuffTooltipBuilder() {
    }

    public function getType():String {
        return "resistanceBuff";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var value:Number = Number(effectData.value);
        if (isNaN(value) || value <= 0) return result;

        result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL));
        result.push("全属性抗性 +" + value);

        var duration:Number = Number(effectData.duration);
        if (!isNaN(duration) && duration > 0) {
            result.push("（" + DrugTooltipUtil.framesToSeconds(duration)
                + TooltipConstants.TIP_DRUG_SECOND + "）");
        }
        result.push(DrugTooltipUtil.br());

        return result;
    }
}
