import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Buff.Effect.ToughnessVulnerabilityController;

/** 命中结算后的声明式行为入口。普通子弹不调用本类，避免给热路径增加固定开销。 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry {
    private static var TOUGHNESS_VULNERABILITY_PRIMER:String = "toughnessVulnerabilityPrimer";

    public static function apply(bullet:Object, shooter:Object,
                                 target:Object, damageResult:Object):Boolean {
        if (!bullet || !shooter || !target || !damageResult || damageResult === DamageResult.NULL) {
            return false;
        }
        if (damageResult.dodgeStatus == "MISS" || damageResult.dodgeStatus == "躲闪") {
            return false;
        }

        var behavior:Object = bullet.hitBehavior;
        if (!behavior || String(behavior.type) != TOUGHNESS_VULNERABILITY_PRIMER) {
            return false;
        }
        return ToughnessVulnerabilityController.applyToTarget(target, shooter, behavior);
    }
}
