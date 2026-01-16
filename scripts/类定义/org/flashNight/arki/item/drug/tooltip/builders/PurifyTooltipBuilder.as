import org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder;
import org.flashNight.arki.item.drug.tooltip.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * PurifyTooltipBuilder - 净化效果词条 Tooltip 构建器
 *
 * 显示格式：
 * 净化度：50（炼金加成）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.builders.PurifyTooltipBuilder
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
