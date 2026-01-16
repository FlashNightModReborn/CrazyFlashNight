import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.item.ItemUtil;

/**
 * GrantItemEffect - 获得物品词条
 *
 * 使玩家获得指定物品。
 *
 * XML配置示例:
 * <effect type="grantItem" name="幻层残响" count="1"/>
 * <effect type="grantItem" name="神秘碎片" count="3" chance="0.5"/>
 *
 * 参数说明:
 * - name: 物品名称（必需）
 * - count: 获得数量（默认1）
 * - chance: 获得概率，0-1之间（默认1，即100%）
 *
 * 注意:
 * - 执行成功后会在context中设置_grantSuccess=true
 * - 可配合MessageEffect的condition="grantSuccess"使用
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.GrantItemEffect implements IDrugEffect {

    public function GrantItemEffect() {
    }

    public function getType():String {
        return "grantItem";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);

        var itemName:String = effectData.name;
        if (!itemName || itemName.length == 0) {
            trace("[GrantItemEffect] 缺少必要参数: name");
            return false;
        }

        var count:Number = Number(effectData.count);
        if (isNaN(count) || count <= 0) count = 1;

        var chance:Number = Number(effectData.chance);
        if (isNaN(chance)) chance = 1;

        // 概率判定
        if (chance < 1 && Math.random() > chance) {
            // 概率未触发，不算失败
            ctx["_grantSuccess"] = false;
            return true;
        }

        // 获得物品
        var success:Boolean = ItemUtil.singleAcquire(itemName, count);

        // 记录结果到上下文（供MessageEffect使用）
        ctx["_grantSuccess"] = success;

        return true;
    }
}
