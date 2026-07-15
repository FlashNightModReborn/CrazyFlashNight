import org.flashNight.arki.component.Damage.DamageResult;
import org.flashNight.arki.component.Buff.Effect.ToughnessVulnerabilityController;
import org.flashNight.arki.component.Damage.DamageManagerFactory;

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
            bullet.damageManager = DamageManagerFactory.Basic.getDamageManager(bullet);
        }
    }

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
        if (!isSupported(behavior)) return false;
        return ToughnessVulnerabilityController.applyToTarget(
            target, shooter, behavior, bullet
        );
    }
}
