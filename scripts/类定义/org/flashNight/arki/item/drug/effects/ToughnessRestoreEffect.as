import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.component.StatHandler.ImpactHandler;

/**
 * ToughnessRestoreEffect - 立即恢复完整韧性槽。
 *
 * remainingImpactForce 是当前累计冲击；impactDecayBaseForce 是当前命中
 * 窗口的绝对衰减基线。两者必须一并清零，随后只重算派生显示，不更新
 * lastHitTime，也不撤销已经进入的硬直、击飞或倒地状态。
 */
class org.flashNight.arki.item.drug.effects.ToughnessRestoreEffect implements IDrugEffect {

    public function ToughnessRestoreEffect() {
    }

    public function getType():String {
        return "restoreToughness";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var target:Object = ctx.target;
        target.remainingImpactForce = 0;
        target.impactDecayBaseForce = 0;
        ImpactHandler.refreshImpactDerived(target);
        return true;
    }
}
