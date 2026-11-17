import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * BuffTooltipBuilder - Buff效果词条 Tooltip 构建器
 *
 * 显示格式（单行完整描述）：
 * Buff：伤害加成 +50（60秒）
 * Buff：防御力 ×1.15（60秒）
 * Buff：速度 +20%（30秒）
 *
 * @author FlashNight
 * @version 1.1
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.BuffTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function BuffTooltipBuilder() {
    }

    public function getType():String {
        return "buff";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var property:String = effectData.property;
        var calc:String = effectData.calc;
        var value:Number = Number(effectData.value);
        var duration:Number = Number(effectData.duration);

        if (!property || !calc || isNaN(value)) return result;

        // 格式化数值显示
        var valueStr:String;
        switch (calc.toLowerCase()) {
            case "add":
                valueStr = (value >= 0 ? "+" : "") + value;
                break;
            case "multiply":
                valueStr = "×" + value;
                break;
            case "percent":
                var percentValue:Number = value * 100;
                valueStr = (percentValue >= 0 ? "+" : "") + percentValue + "%";
                break;
            case "override":
                valueStr = "=" + value;
                break;
            case "max":
                valueStr = "≥" + value;
                break;
            case "min":
                valueStr = "≤" + value;
                break;
            default:
                valueStr = String(value);
        }

        // 构建输出
        result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL));
        result.push(property + " " + valueStr);

        // 持续时间
        if (!isNaN(duration) && duration > 0) {
            var durationSec:String = DrugTooltipUtil.framesToSeconds(duration);
            result.push("（" + durationSec + TooltipConstants.TIP_DRUG_SECOND + "）");
        }

        result.push(DrugTooltipUtil.br());

        return result;
    }
}
