import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;

/**
 * BuffDomainEffect - 声明本次药剂的持续效果域。
 *
 * 同一单位在每个域中只保留最近一次使用所注册的持续 Buff。即时恢复、
 * 净化与剧情效果不会被回滚；食品与战斗强化剂分别使用 meal/enhancer 域，
 * 因而形成“一个餐食 + 一个强化剂”的原子槽位。
 *
 * XML配置示例:
 * <effect type="buffDomain" domain="meal"/>
 */
class org.flashNight.arki.item.drug.effects.BuffDomainEffect implements IDrugEffect {

    public function BuffDomainEffect() {
    }

    public function getType():String {
        return "buffDomain";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var domain:String = effectData.domain;
        if (!domain || domain.length == 0) {
            trace("[BuffDomainEffect] 缺少必要参数: domain");
            return false;
        }

        return ctx.beginBuffDomain(domain);
    }
}
