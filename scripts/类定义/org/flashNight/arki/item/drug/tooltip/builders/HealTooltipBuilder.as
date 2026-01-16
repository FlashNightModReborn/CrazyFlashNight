import org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder;
import org.flashNight.arki.item.drug.tooltip.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * HealTooltipBuilder - 即时恢复词条 Tooltip 构建器
 *
 * 显示格式：
 * - HP+150 / MP+100（单体）
 * - HP+300（对友军生效）
 * - HP+50%（百分比原样显示）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.builders.HealTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function HealTooltipBuilder() {
    }

    public function getType():String {
        return "heal";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var hp = effectData.hp;
        var mp = effectData.mp;
        var target:String = effectData.target || "self";
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;

        var hpStr:String = DrugTooltipUtil.formatValue(hp);
        var mpStr:String = DrugTooltipUtil.formatValue(mp);

        var hpNum:Number = Number(hp);
        var mpNum:Number = Number(mp);

        // HP 显示
        if (!isNaN(hpNum) && hpNum != 0 || String(hp).indexOf("%") >= 0) {
            result.push(DrugTooltipUtil.color("HP+" + hpStr, TooltipConstants.COL_HP));
            result.push(DrugTooltipUtil.alchemyTag(scaleWithAlchemy));
            result.push(DrugTooltipUtil.br());
        }

        // MP 显示
        if (!isNaN(mpNum) && mpNum != 0 || String(mp).indexOf("%") >= 0) {
            result.push(DrugTooltipUtil.color("MP+" + mpStr, TooltipConstants.COL_MP));
            result.push(DrugTooltipUtil.alchemyTag(scaleWithAlchemy));
            result.push(DrugTooltipUtil.br());
        }

        // 群体效果提示
        if (target == "group") {
            result.push(DrugTooltipUtil.color(TooltipConstants.TIP_ALLY_EFFECT, TooltipConstants.COL_HL));
            result.push(DrugTooltipUtil.br());
        }

        return result;
    }
}
