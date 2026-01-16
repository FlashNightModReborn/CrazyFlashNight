import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;

/**
 * StateEffect - 状态修改效果词条
 *
 * 修改目标单位的状态值（如淬毒、麻痹值等）。
 *
 * XML配置示例:
 * <effect type="state" key="淬毒" value="70" scaleWithAlchemy="true"/>
 * <effect type="state" key="麻痹值" value="-100" operation="add"/>
 *
 * 参数说明:
 * - key: 状态属性名（如"淬毒"、"麻痹值"）
 * - value: 状态值
 * - operation: "set"(设置，默认) 或 "add"(增加)
 * - scaleWithAlchemy: 是否应用炼金加成（仅淬毒有效，默认true）
 * - alchemyFactor: 炼金加成系数（默认0.07）
 * - alchemyCap: 炼金加成上限（默认2000）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.StateEffect implements IDrugEffect {

    public function StateEffect() {
    }

    public function getType():String {
        return "state";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var key:String = effectData.key;
        if (!key || key.length == 0) {
            trace("[StateEffect] 缺少必要参数: key");
            return false;
        }

        var value:Number = Number(effectData.value);
        if (isNaN(value)) {
            trace("[StateEffect] 无效的value: " + effectData.value);
            return false;
        }

        var operation:String = effectData.operation || "set";
        // XMLParser 会把 "true"/"false" 转成 Boolean，需要同时兼容两种情况
        var scaleWithAlchemy:Boolean = effectData.scaleWithAlchemy !== false;

        // 特殊处理：淬毒的炼金加成
        if (key == "淬毒" && scaleWithAlchemy) {
            var factor:Number = Number(effectData.alchemyFactor);
            var cap:Number = Number(effectData.alchemyCap);
            if (isNaN(factor)) factor = 0.07;
            if (isNaN(cap)) cap = 2000;
            value = ctx.calcWithAlchemy(value, factor, cap);
        }

        // 执行状态修改
        var target:Object = ctx.target;

        if (operation == "add") {
            var currentValue:Number = Number(target[key]);
            if (isNaN(currentValue)) currentValue = 0;
            target[key] = currentValue + value;
        } else {
            // set
            target[key] = value;
        }

        return true;
    }
}
