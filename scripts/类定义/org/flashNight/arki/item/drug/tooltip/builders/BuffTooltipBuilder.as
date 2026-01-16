import org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder;
import org.flashNight.arki.item.drug.tooltip.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * BuffTooltipBuilder - Buff效果词条 Tooltip 构建器
 *
 * 显示格式：
 * Buff：伤害加成 +50（60秒）
 * Buff：防御力 ×1.15（60秒）
 * Buff：速度 +20%（30秒）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.builders.BuffTooltipBuilder
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
        result.push(DrugTooltipUtil.color("Buff：", TooltipConstants.COL_HL));
        result.push(property + " " + valueStr);

        // 持续时间
        if (!isNaN(duration) && duration > 0) {
            var durationSec:String = DrugTooltipUtil.framesToSeconds(duration);
            result.push("（" + durationSec + "秒）");
        }

        result.push(DrugTooltipUtil.br());

        return result;
    }
}
