import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * ResistanceBuffTooltipBuilder - 属性抗性临时增益/减益 Tooltip
 *
 * 显示格式（每行一条，最多两行）：
 * 药效：全属性抗性 ×2（10秒）
 * 药效：全属性抗性 +5（10秒）
 * 药效：电抗性 ×2.2（10秒）
 * 药效：电抗性 -20（10秒）      ← 负抗性即易伤
 *
 * 与 ResistanceBuffEffect 共用同一套取值约定：value / mult_positive 正负皆可，
 * 0 点与 1 倍率视为未提供。负抗性在伤害侧表现为易伤，Tooltip 直接带负号显示。
 *
 * mult_positive 是倍率（2.2 = ×2.2），与 BuffEffect 的 calc="mult_positive"
 * 同一套语义，同类只取最强的一个。
 *
 * property 指定单一抗性时使用 "<抗性名> + 抗性" 作前缀；内部键"基础"对外
 * 一律显示为"能量"，与装备抗性块（ResistanceBlockBuilder）保持同一套文案。
 *
 * @author FlashNight
 * @version 1.5
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

        // NaN 表示"未提供"；负值与 <1 的倍率均为合法取值（负抗性 = 易伤）。
        // 属性缺失或空串同样算未提供，避免显示成 0 点 / ×0。
        var rawValue:Number = (effectData.value == undefined || effectData.value == "")
            ? NaN : Number(effectData.value);
        var value:Number = NaN;
        if (!isNaN(rawValue) && rawValue != 0) value = rawValue;

        var rawMult:Number = (effectData.mult_positive == undefined || effectData.mult_positive == "")
            ? NaN : Number(effectData.mult_positive);
        var mult:Number = NaN;
        if (!isNaN(rawMult) && rawMult != 1) mult = rawMult;

        if (isNaN(value) && isNaN(mult)) return result;

        var duration:Number = Number(effectData.duration);
        var durationSuffix:String = "";
        if (!isNaN(duration) && duration > 0) {
            durationSuffix = "（" + DrugTooltipUtil.framesToSeconds(duration)
                + TooltipConstants.TIP_DRUG_SECOND + "）";
        }

        var label:String = DrugTooltipUtil.color(
            TooltipConstants.LBL_DRUG_BUFF + "：", TooltipConstants.COL_HL);
        // 显示名：不指定 property 为全属性；指定时"基础"翻译成"能量"
        var property:String = effectData.property;
        var baseName:String = "全属性抗性 ";
        if (property && property.length > 0) {
            var displayName:String = (property == TooltipConstants.TXT_BASE)
                ? TooltipConstants.TXT_ENERGY : property;
            baseName = displayName + TooltipConstants.SUF_RESISTANCE + " ";
        }

        // 乘区倍率行
        if (!isNaN(mult)) {
            result.push(label);
            result.push(baseName + "×" + mult);
            result.push(durationSuffix);
            result.push(DrugTooltipUtil.br());
        }

        // 固定点数行（负值自带负号，显示如"电抗性 -20"，即易伤）
        if (!isNaN(value)) {
            result.push(label);
            result.push(baseName + (value > 0 ? "+" : "") + value);
            result.push(durationSuffix);
            result.push(DrugTooltipUtil.br());
        }

        return result;
    }
}
