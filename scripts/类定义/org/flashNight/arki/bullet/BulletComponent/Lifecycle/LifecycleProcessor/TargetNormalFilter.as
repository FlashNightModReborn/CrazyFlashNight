
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.TargetNormalFilter implements ITargetFilter{
    public static var instance:TargetNormalFilter = new TargetNormalFilter();
    public function TargetNormalFilter() {
    }

    /**
     * 根据 Z 轴距离与“防止无限飞”等条件判断是否跳过当前目标
     */
    public function shouldSkipHitTarget(target:MovieClip, hitTarget:MovieClip, zOffset:Number):Boolean {
        if (zOffset * zOffset >= target.zAttackRangeSq) {
            return true;
        }
        if (hitTarget.防止无限飞 == true) {
            return true;
        }
        return false;
    }
}
