import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * StateTooltipBuilder - 状态修改词条 Tooltip 构建器
 *
 * 显示格式（每个状态一行）：
 * - 淬毒：剧毒性：70（特殊颜色）
 * - 其他状态：状态名：值
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.StateTooltipBuilder
    implements IDrugTooltipBuilder
{
    /** 状态键显示名映射 */
    private static var _stateKeyDisplayMap:Object = {
        淬毒: null  // null表示使用特殊处理
    };

    public function StateTooltipBuilder() {
    }

    public function getType():String {
        return "state";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var key:String = effectData.key;
        var value:Number = Number(effectData.value);
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;

        if (!key || isNaN(value)) return result;

        // 淬毒特殊处理
        if (key == "淬毒") {
            result.push(DrugTooltipUtil.color(
                TooltipConstants.LBL_POISON + "：" + value,
                TooltipConstants.COL_POISON
            ));
            result.push(DrugTooltipUtil.alchemyTag(scaleWithAlchemy));
            result.push(DrugTooltipUtil.br());
            return result;
        }

        // 其他状态通用显示
        var displayName:String = _stateKeyDisplayMap[key];
        if (displayName == undefined) {
            displayName = key;
        }

        result.push(displayName + "：" + value);
        result.push(DrugTooltipUtil.alchemyTag(scaleWithAlchemy));
        result.push(DrugTooltipUtil.br());

        return result;
    }
}
