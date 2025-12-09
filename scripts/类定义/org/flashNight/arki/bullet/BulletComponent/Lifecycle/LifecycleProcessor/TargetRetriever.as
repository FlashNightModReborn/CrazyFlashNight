import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*; // 目标缓存


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.TargetRetriever implements ITargetRetriever{
    public static var instance:TargetRetriever = new TargetRetriever();
    public function TargetRetriever() { }

    /**
     * 根据发射者及伤害类型获取潜在目标
     *
     * 使用 STATE_FRIENDLY_FIRE 标志位判断是否获取全体目标或仅敌方目标
     */
    public function getPotentialTargets(target:MovieClip):Array {
        // === 宏展开：实例状态标志位 ===
        #include "../macros/STATE_FRIENDLY_FIRE.as"

        var shooter:MovieClip = target.shooter;
        if (shooter == undefined) {
            return []; // 发射者不存在返回空数组
        }

        // 读取实例状态标志位，检测友军伤害标志
        var sf:Number = target.stateFlags | 0;
        var isFriendlyFire:Boolean = (sf & STATE_FRIENDLY_FIRE) != 0;

        if (isFriendlyFire) {
            return TargetCacheManager.getCachedAll(shooter, 1);
        } else {
            return TargetCacheManager.getCachedEnemy(shooter, 1);
        }
    }
}
