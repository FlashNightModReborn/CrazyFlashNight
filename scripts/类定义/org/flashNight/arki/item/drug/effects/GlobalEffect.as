import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;

/**
 * GlobalEffect - 全局变量修改词条
 *
 * 修改_root下的全局变量。
 *
 * XML配置示例:
 * <effect type="global" key="地形伤害系数" operation="set" value="0.09"/>
 * <effect type="global" key="某计数器" operation="add" value="1"/>
 * <effect type="global" key="某倍率" operation="multiply" value="0.5"/>
 *
 * 参数说明:
 * - key: _root下的变量名（必需）
 * - operation: 操作类型（默认"set"）
 *   - "set": 设置为指定值
 *   - "add": 增加指定值
 *   - "multiply": 乘以指定值
 * - value: 操作数值（必需）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.GlobalEffect implements IDrugEffect {

    public function GlobalEffect() {
    }

    public function getType():String {
        return "global";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var key:String = effectData.key;
        if (!key || key.length == 0) {
            trace("[GlobalEffect] 缺少必要参数: key");
            return false;
        }

        var value:Number = Number(effectData.value);
        if (isNaN(value)) {
            trace("[GlobalEffect] 无效的value: " + effectData.value);
            return false;
        }

        var operation:String = effectData.operation || "set";

        // 执行操作
        switch (operation) {
            case "set":
                _root[key] = value;
                break;

            case "add":
                var currentAdd:Number = Number(_root[key]);
                if (isNaN(currentAdd)) currentAdd = 0;
                _root[key] = currentAdd + value;
                break;

            case "multiply":
                var currentMul:Number = Number(_root[key]);
                if (isNaN(currentMul)) currentMul = 1;
                _root[key] = currentMul * value;
                break;

            default:
                trace("[GlobalEffect] 未知的operation: " + operation);
                return false;
        }

        return true;
    }
}
