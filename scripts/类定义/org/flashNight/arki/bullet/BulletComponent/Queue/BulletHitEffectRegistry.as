import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Buff.Effect.ToughnessVulnerabilityController;
import org.flashNight.arki.component.Damage.DamageManagerFactory;
import org.flashNight.arki.component.Buff.Effect.FireControlVulnerability;

/** 灰蛊声明式命中入口。普通子弹不调用本类，避免给热路径增加固定开销。 */
class org.flashNight.arki.bullet.BulletComponent.Queue.BulletHitEffectRegistry {
    private static var TOUGHNESS_VULNERABILITY_PRIMER:String = "toughnessVulnerabilityPrimer";
    private static var GRAY_GOO_PRIMER:String = "grayGooPrimer";

    private static function isSupported(behavior:Object):Boolean {
        if (!behavior) return false;
        var type:String = String(behavior.type);
        return type == GRAY_GOO_PRIMER || type == TOUGHNESS_VULNERABILITY_PRIMER;
    }

    /** 在伤害管线选择处理器前，按当前目标层数临时注入击溃/斩杀。 */
    public static function prepare(bullet:Object, shooter:Object, target:Object):Void {
        if (bullet.hitBehavior.type == "titaniumFireControl" || bullet.hitBehavior.type == "titaniumBloodPact") {
            // 引导与献血动作采用独立小额物伤，防止多段继承击溃、毒与固伤。
            bullet.击溃 = bullet.斩杀 = bullet.吸血 = bullet.毒 = 0;
            bullet.nanoToxic = bullet.additionalEffectDamage = 0;
            bullet.实际命中强制击杀 = false;
            bullet.暴击 = null;
            bullet.百分比伤害 = bullet.固伤 = 0;
            bullet.伤害类型 = "物理";
            bullet.霰弹值 = 1;
            var power:Number = bullet.hitBehavior.type == "titaniumFireControl" ? 100 : Number(bullet.hitBehavior.directPower);
            bullet.子弹威力 = isFinite(power) && power > 0 ? power : 0;
            bullet.damageManager = DamageManagerFactory.resolveForBullet(bullet);
            return;
        }
        if (!bullet || !shooter || !target || !isSupported(bullet.hitBehavior)) return;

        if (bullet._grayGooBaseCaptured !== true) {
            bullet._grayGooBaseCrumble = bullet.击溃 > 0 ? bullet.击溃 : 0;
            bullet._grayGooBaseExecute = bullet.斩杀 > 0 ? bullet.斩杀 : 0;
            bullet._grayGooBaseCaptured = true;
        }
        bullet.击溃 = bullet._grayGooBaseCrumble;
        bullet.斩杀 = bullet._grayGooBaseExecute;
        bullet._grayGooPreparedKey = null;
        bullet._grayGooPendingConsume = 0;

        ToughnessVulnerabilityController.prepareBulletForTarget(
            target, shooter, bullet.hitBehavior, bullet
        );

        // DamageManager 在生成时按字段裁剪处理器；动态配给后仅灰蛊子弹重选缓存组合。
        if (DamageManagerFactory.Basic != null) {
            bullet.damageManager = DamageManagerFactory.resolveForBullet(bullet);
        }
    }

    public static function apply(bullet:Object, shooter:Object,
                                 target:Object, damageResult:Object):Boolean {
        if (!bullet || !shooter || !target || !damageResult || damageResult === DamageResult.NULL) {
            return false;
        }
        // 与击溃/斩杀处理器共用同一真实命中判定，保证动态效果结算与层数消费对称。
        if (!DamageResult.hasActualHit(damageResult)) return false;

        var behavior:Object = bullet.hitBehavior;
        if (behavior.type == "titaniumFireControl") return FireControlVulnerability.applyToTarget(target, behavior);
        if (!isSupported(behavior)) return false;
        return ToughnessVulnerabilityController.applyToTarget(
            target, shooter, behavior, bullet
        );
    }
}
