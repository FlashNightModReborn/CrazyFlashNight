import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * ToughnessRestoreTooltipBuilder - 完整恢复韧性槽 Tooltip
 *
 * 显示格式（单行）：
 * 韧性：立即恢复至满
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.ToughnessRestoreTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function ToughnessRestoreTooltipBuilder() {
    }

    public function getType():String {
        return "restoreToughness";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        result.push(DrugTooltipUtil.color("韧性：", TooltipConstants.COL_HL));
        result.push("立即恢复至满");
        result.push(DrugTooltipUtil.br());

        return result;
    }
}
