import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * PurifyTooltipBuilder - 净化效果词条 Tooltip 构建器
 *
 * 显示格式（单行）：
 * 净化度：50
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.PurifyTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function PurifyTooltipBuilder() {
    }

    public function getType():String {
        return "purify";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var value:Number = Number(effectData.value);
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;

        if (isNaN(value) || value <= 0) return result;

        result.push(TooltipConstants.LBL_CLEAN + "：" + value);
        result.push(DrugTooltipUtil.alchemyTag(scaleWithAlchemy));
        result.push(DrugTooltipUtil.br());

        return result;
    }
}
