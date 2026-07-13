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
        // 联弹分段模型不会把“所有段 MISS/直感”回写到 dodgeStatus；必须按分段
        // 统计再守一次，否则零实际命中的链式弹也会挂载 primer。
        if (damageResult.scatterModelEnabled === true &&
            damageResult.actualScatterUsed > 0 &&
            !(damageResult.scatterMissCount < damageResult.actualScatterUsed)) {
            return false;
        }

        var behavior:Object = bullet.hitBehavior;
        if (!behavior || String(behavior.type) != TOUGHNESS_VULNERABILITY_PRIMER) {
            return false;
        }
        return ToughnessVulnerabilityController.applyToTarget(target, shooter, behavior);
    }
}
