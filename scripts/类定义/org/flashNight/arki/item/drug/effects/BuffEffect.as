import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.Buff.*;
import org.flashNight.arki.component.Buff.Component.*;

/**
 * BuffEffect - Buff施加效果词条
 *
 * 通过BuffManager为目标添加属性Buff。
 *
 * XML配置示例:
 * <effect type="buff" property="伤害加成" calc="add" value="50" duration="1800"/>
 * <effect type="buff" property="防御力" calc="multiply" value="1.15" duration="1800" buffId="药剂_防御力"/>
 * <effect type="buff" property="速度" calc="percent" value="0.2" duration="900"/>
 *
 * 参数说明:
 * - property: 目标属性名（必需，如"伤害加成"、"防御力"、"行走X速度"）
 * - calc: 计算类型（必需）
 *   - "add": 加算，result = base * multipliers + value
 *   - "multiply": 乘算，result = base * value
 *   - "percent": 百分比，result = base * (1 + value)
 *   - "override": 覆盖，result = value
 *   - "max": 最小保底，result = max(base, value)
 *   - "min": 最大封顶，result = min(base, value)
 * - value: Buff数值（必需）
 * - duration: 持续帧数（可选，0或不填表示永久/场景有效）
 * - buffId: Buff标识（可选）
 *   - 固定ID: 重复使用会刷新持续时间（如"药剂_防御力"）
 *   - 不填或带时间戳: 允许叠加多个实例
 * - stackable: 是否可叠加（可选，默认false，仅当buffId固定时有效）
 *
 * @author FlashNight
 * @version 1.0
 */
class org.flashNight.arki.item.drug.effects.BuffEffect implements IDrugEffect {

    public function BuffEffect() {
    }

    public function getType():String {
        return "buff";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:Object = ctx.target;

        // 检查buffManager是否存在
        if (!target.buffManager) {
            trace("[BuffEffect] 目标没有buffManager");
            return false;
        }

        var buffManager:BuffManager = target.buffManager;

        // 解析必需参数
        var property:String = effectData.property;
        if (!property || property.length == 0) {
            trace("[BuffEffect] 缺少必要参数: property");
            return false;
        }

        var calc:String = effectData.calc;
        if (!calc || calc.length == 0) {
            trace("[BuffEffect] 缺少必要参数: calc");
            return false;
        }

        var value:Number = Number(effectData.value);
        if (isNaN(value)) {
            trace("[BuffEffect] 无效的value: " + effectData.value);
            return false;
        }

        // 解析可选参数
        var duration:Number = Number(effectData.duration);
        if (isNaN(duration)) duration = 0;

        var buffId:String = effectData.buffId;
        // XMLParser 会把 "true"/"false" 转成 Boolean，需要同时兼容两种情况
        var stackable:Boolean = effectData.stackable === true;

        // 如果没有指定buffId，生成唯一ID
        if (!buffId || buffId.length == 0) {
            buffId = "药剂_" + property + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
        } else if (stackable) {
            // 可叠加时，在固定ID基础上添加时间戳
            buffId = buffId + "_" + getTimer() + "_" + Math.floor(Math.random() * 1000);
        }

        // 映射calc类型到BuffCalculationType
        var calcType:String = mapCalcType(calc);
        if (!calcType) {
            trace("[BuffEffect] 未知的calc类型: " + calc);
            return false;
        }

        // 创建PodBuff
        var podBuff:PodBuff = new PodBuff(property, calcType, value);
        var childBuffs:Array = [podBuff];

        // 创建组件（时限等）
        var components:Array = [];
        if (duration > 0) {
            components.push(new TimeLimitComponent(duration));
        }

        // 创建MetaBuff
        var metaBuff:MetaBuff = new MetaBuff(childBuffs, components, 0);

        // 添加到BuffManager
        buffManager.addBuff(metaBuff, buffId);
        buffManager.update(0); // 立即生效

        return true;
    }

    /**
     * 映射calc字符串到BuffCalculationType
     */
    private function mapCalcType(calc:String):String {
        switch (calc.toLowerCase()) {
            case "add":
                return BuffCalculationType.ADD;
            case "multiply":
                return BuffCalculationType.MULTIPLY;
            case "percent":
                return BuffCalculationType.PERCENT;
            case "override":
                return BuffCalculationType.OVERRIDE;
            case "max":
                return BuffCalculationType.MAX;
            case "min":
                return BuffCalculationType.MIN;
            default:
                return null;
        }
    }
}
