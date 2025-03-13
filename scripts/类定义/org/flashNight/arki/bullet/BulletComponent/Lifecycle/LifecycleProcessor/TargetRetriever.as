import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*; // 目标缓存


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.TargetRetriever implements ITargetRetriever{
    public static var instance:TargetRetriever = new TargetRetriever();
    public function TargetRetriever() { }
    
    /**
     * 根据发射者及伤害类型获取潜在目标
     */
    public function getPotentialTargets(target:MovieClip):Array {
        var shooter:MovieClip = target.shooter;
        if (shooter == undefined) {
            return []; // 发射者不存在返回空数组
        }
        
        if (target.友军伤害) {
            return TargetCacheManager.getCachedAll(shooter, 1);
        } else {
            return TargetCacheManager.getCachedEnemy(shooter, 1);
        }
    }
}
