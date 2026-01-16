import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;

/**
 * MessageEffect - 消息发布词条
 *
 * 向玩家显示消息提示。
 *
 * XML配置示例:
 * <effect type="message" text="你感到精力充沛！"/>
 * <effect type="message" text="获得了神秘物品" condition="grantSuccess"/>
 *
 * 参数说明:
 * - text: 要显示的消息文本（必需）
 * - condition: 显示条件（可选）
 *   - 无或空: 总是显示
 *   - "grantSuccess": 配合GrantItemEffect，仅在获得物品成功时显示
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.MessageEffect implements IDrugEffect {

    public function MessageEffect() {
    }

    public function getType():String {
        return "message";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);

        var text:String = effectData.text;
        if (!text || text.length == 0) {
            trace("[MessageEffect] 缺少必要参数: text");
            return false;
        }

        var condition:String = effectData.condition;

        // 检查条件
        if (condition == "grantSuccess") {
            // 检查上下文中的grantSuccess标记
            if (ctx["_grantSuccess"] != true) {
                return true; // 条件不满足，但不算失败
            }
        }

        // 发布消息
        _root.发布消息(text);

        return true;
    }
}
