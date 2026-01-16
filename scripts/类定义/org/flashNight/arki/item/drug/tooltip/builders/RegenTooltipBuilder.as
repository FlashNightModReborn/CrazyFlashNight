import org.flashNight.arki.item.drug.tooltip.IDrugTooltipBuilder;
import org.flashNight.arki.item.drug.tooltip.DrugTooltipUtil;
import org.flashNight.gesh.tooltip.TooltipConstants;

/**
 * RegenTooltipBuilder - 缓释恢复词条 Tooltip 构建器
 *
 * 显示格式：
 * 缓释：HP+150（5秒），每1秒恢复
 * 缓释：MP+10/次（5秒），每1秒恢复
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.tooltip.builders.RegenTooltipBuilder
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

        // 构建描述文本
        var parts:Array = [];

        // HP部分
        if (!isNaN(hpNum) && hpNum != 0 || String(hp).indexOf("%") >= 0) {
            if (mode == "total") {
                parts.push(DrugTooltipUtil.color("HP+" + hpStr, TooltipConstants.COL_HP));
            } else {
                parts.push(DrugTooltipUtil.color("HP+" + hpStr + "/次", TooltipConstants.COL_HP));
            }
        }

        // MP部分
        if (!isNaN(mpNum) && mpNum != 0 || String(mp).indexOf("%") >= 0) {
            if (mode == "total") {
                parts.push(DrugTooltipUtil.color("MP+" + mpStr, TooltipConstants.COL_MP));
            } else {
                parts.push(DrugTooltipUtil.color("MP+" + mpStr + "/次", TooltipConstants.COL_MP));
            }
        }

        if (parts.length == 0) return result;

        // 组合输出
        result.push(DrugTooltipUtil.color("缓释：", TooltipConstants.COL_HL));
        result.push(parts.join(" "));

        // 时间信息
        result.push("（" + durationSec + "秒），每" + intervalSec + "秒恢复");

        // 炼金标记（仅无炼金时显示）
        var alchemyStr:String = DrugTooltipUtil.alchemyTag(scaleWithAlchemy);
        if (alchemyStr.length > 0) {
            result.push(" ");
            result.push(alchemyStr);
        }

        result.push(DrugTooltipUtil.br());

        // 叠加提示（仅当 stack=refresh 且使用默认ID时）
        if (stack == "refresh" && !effectData.id) {
            result.push(DrugTooltipUtil.color("（覆盖同类缓释）", TooltipConstants.COL_INFO));
            result.push(DrugTooltipUtil.br());
        }

        return result;
    }
}
