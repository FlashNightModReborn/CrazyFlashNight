import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;

/**
 * HealEffect - 恢复效果词条
 *
 * 处理HP/MP恢复，支持单体和群体目标。
 *
 * XML配置示例:
 * <effect type="heal" hp="150" mp="100" target="self" scaleWithAlchemy="true"/>
 * <effect type="heal" hp="300" target="group" scaleWithAlchemy="true"/>
 * <effect type="heal" hp="50%" target="self"/> <!-- 百分比恢复 -->
 *
 * 参数说明:
 * - hp: HP恢复值（数字或百分比字符串如"50%"）
 * - mp: MP恢复值（数字或百分比字符串）
 * - target: "self"(单体，默认) 或 "group"(群体)
 * - scaleWithAlchemy: 是否应用炼金加成（默认true）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.HealEffect implements IDrugEffect {

    public function HealEffect() {
    }

    public function getType():String {
        return "heal";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:String = effectData.target || "self";
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy != "false";

        // 解析HP值
        var hpValue:Number = parseValue(effectData.hp, ctx.target.hp满血值);
        // 解析MP值
        var mpValue:Number = parseValue(effectData.mp, ctx.target.mp满血值);

        // 应用炼金加成
        if (scaleWithAlchemy) {
            hpValue = ctx.calcHPWithAlchemy(hpValue);
            mpValue = ctx.calcMPWithAlchemy(mpValue);
        }

        if (target == "group") {
            // 群体恢复
            return executeGroupHeal(ctx, hpValue, mpValue);
        } else {
            // 单体恢复
            return executeSelfHeal(ctx, hpValue, mpValue);
        }
    }

    /**
     * 解析恢复值（支持百分比）
     */
    private function parseValue(raw, maxValue:Number):Number {
        if (raw == null || raw == undefined) return 0;

        var strValue:String = String(raw);
        if (strValue.indexOf("%") >= 0) {
            // 百分比恢复
            var percent:Number = parseFloat(strValue.replace("%", ""));
            if (isNaN(percent)) return 0;
            return Math.floor(maxValue * percent / 100);
        } else {
            var num:Number = Number(raw);
            return isNaN(num) ? 0 : num;
        }
    }

    /**
     * 执行单体恢复
     */
    private function executeSelfHeal(ctx:DrugContext, hpValue:Number, mpValue:Number):Boolean {
        var target:Object = ctx.target;
        var healed:Boolean = false;

        // HP恢复
        if (hpValue > 0) {
            var maxHP:Number = ctx.getMaxHPWithAlchemy();
            var newHP:Number = target.hp + hpValue;
            if (newHP > maxHP) {
                newHP = maxHP;
            }
            if (newHP > target.hp) {
                target.hp = newHP;
                healed = true;
            }
            _root.玩家信息界面.刷新hp显示();
        }

        // MP恢复
        if (mpValue > 0) {
            var maxMP:Number = target.mp满血值;
            var newMP:Number = target.mp + mpValue;
            if (newMP > maxMP) {
                newMP = maxMP;
            }
            if (newMP > target.mp) {
                target.mp = newMP;
                healed = true;
            }
            _root.玩家信息界面.刷新mp显示();
        }

        return healed || (hpValue == 0 && mpValue == 0);
    }

    /**
     * 执行群体恢复
     */
    private function executeGroupHeal(ctx:DrugContext, hpValue:Number, mpValue:Number):Boolean {
        // 群体HP恢复
        if (hpValue > 0) {
            _root.佣兵集体加血(hpValue);
        }

        // 群体MP恢复
        if (mpValue > 0) {
            _root.佣兵集体回蓝(mpValue);
        }

        return true;
    }
}
