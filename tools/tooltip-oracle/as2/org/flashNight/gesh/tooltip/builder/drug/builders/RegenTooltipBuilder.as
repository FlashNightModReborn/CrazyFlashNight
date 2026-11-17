import org.flashNight.gesh.tooltip.builder.drug.IDrugTooltipBuilder;
import org.flashNight.gesh.tooltip.builder.drug.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * RegenTooltipBuilder - 缓释恢复词条 Tooltip 构建器
 *
 * 显示格式（紧凑）：
 * 缓释：500hp/5s 100mp/5s
 * 缓释：10hp/次/5s（perTick模式）
 *
 * @author FlashNight
 * @version 1.2
 */
class org.flashNight.gesh.tooltip.builder.drug.builders.RegenTooltipBuilder
    implements IDrugTooltipBuilder
{
    public function RegenTooltipBuilder() {
    }

    public function getType():String {
        return "regen";
    }

    public function build(effectData:Object):Array {
        var result:Array = [];

        var hp = effectData.hp;
        var mp = effectData.mp;
        var duration:Number = Number(effectData.duration);
        var interval:Number = Number(effectData.interval);
        var mode:String = effectData.mode || "perTick";
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;
        var stack:String = effectData.stack || "refresh";

        if (isNaN(interval) || interval <= 0) interval = 30;
        if (isNaN(duration) || duration <= 0) return result;

        var durationSec:String = DrugTooltipUtil.framesToSeconds(duration);
        var intervalSec:String = DrugTooltipUtil.framesToSeconds(interval);

        var hpStr:String = DrugTooltipUtil.formatValue(hp);
        var mpStr:String = DrugTooltipUtil.formatValue(mp);

        var hpNum:Number = Number(hp);
        var mpNum:Number = Number(mp);

        // 构建紧凑格式：500hp/5s 或 10hp/次/5s
        var parts:Array = [];

        // HP部分
        if (!isNaN(hpNum) && hpNum != 0 || String(hp).indexOf("%") >= 0) {
            var hpText:String;
            if (mode == "total") {
                // total模式：总量/持续时间，如 500hp/5s
                hpText = hpStr + "hp/" + durationSec + "s";
            } else {
                // perTick模式：每次量/间隔/持续时间，如 10hp/1s/5s
                hpText = hpStr + "hp/" + intervalSec + "s/" + durationSec + "s";
            }
            parts.push(DrugTooltipUtil.color(hpText, TooltipConstants.COL_HP));
        }

        // MP部分
        if (!isNaN(mpNum) && mpNum != 0 || String(mp).indexOf("%") >= 0) {
            var mpText:String;
            if (mode == "total") {
                mpText = mpStr + "mp/" + durationSec + "s";
            } else {
                mpText = mpStr + "mp/" + intervalSec + "s/" + durationSec + "s";
            }
            parts.push(DrugTooltipUtil.color(mpText, TooltipConstants.COL_MP));
        }

        if (parts.length == 0) return result;

        // 组合输出：缓释：500hp/5s 100mp/5s
        result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_REGEN + "：", TooltipConstants.COL_HL));
        result.push(parts.join(" "));

        // 炼金标记（仅无炼金时显示）
        var alchemyStr:String = DrugTooltipUtil.alchemyTag(scaleWithAlchemy);
        if (alchemyStr.length > 0) {
            result.push(" ");
            result.push(alchemyStr);
        }

        result.push(DrugTooltipUtil.br());

        // 叠加提示（仅当 stack=refresh 且使用默认ID时）
        if (stack == "refresh" && !effectData.id) {
            result.push(DrugTooltipUtil.color(TooltipConstants.LBL_DRUG_REGEN_OVERRIDE, TooltipConstants.COL_INFO));
            result.push(DrugTooltipUtil.br());
        }

        return result;
    }
}
