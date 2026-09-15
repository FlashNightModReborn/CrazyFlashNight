import org.flashNight.arki.item.drug.IDrugEffect;
import org.flashNight.arki.item.drug.DrugContext;
import org.flashNight.arki.unit.Action.Shoot.AmmoSupplyService;

/**
 * SupplyAmmoEffect - 弹药补给词条
 *
 * 委托 AmmoSupplyService 按 scope 补满枪械弹药，以"实际补弹实例数 >0"为收益。
 * 服务前置拒绝（换弹在途等）时返回 false，并把拒绝原因与补弹明细挂到 ctx 上，
 * 供 PickupEffectService 汇总反馈文案。
 *
 * XML配置示例:
 * <effect type="supplyAmmo" scope="longgun"/>
 * <effect type="supplyAmmo" scope="pistols"/>
 * <effect type="supplyAmmo" scope="equipped"/>
 * <effect type="supplyAmmo" scope="all"/>
 *
 * 参数说明:
 * - scope: 补弹范围（必需）：longgun/pistols/equipped/all
 */
class org.flashNight.arki.item.drug.effects.SupplyAmmoEffect implements IDrugEffect {

    public function SupplyAmmoEffect() {
    }

    public function getType():String {
        return "supplyAmmo";
    }

    public function execute(context:Object, effectData:Object):Boolean {
        var ctx:DrugContext = DrugContext(context);
        if (!ctx || !ctx.target) return false;

        var scope:String = effectData.scope;
        if (scope == null || scope.length == 0) {
            trace("[SupplyAmmoEffect] 缺少必要参数: scope");
            return false;
        }

        var result:Object = AmmoSupplyService.supply(ctx.target, scope);
        ctx._ammoRejected = result.rejected;
        ctx._ammoSupplyChanged = result.changed;
        ctx._ammoSupplyDetails = result.details;
        if (result.rejected != null) return false;

        return result.changed > 0;
    }
}
