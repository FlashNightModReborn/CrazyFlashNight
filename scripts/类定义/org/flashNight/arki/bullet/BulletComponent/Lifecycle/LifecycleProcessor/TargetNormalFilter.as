
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.TargetNormalFilter implements ITargetFilter{

    public function TargetNormalFilter() {
    }

    /**
     * 根据 Z 轴距离与“防止无限飞”等条件判断是否跳过当前目标
     */
    public function shouldSkipHitTarget(target:MovieClip, hitTarget:MovieClip, zOffset:Number):Boolean {
        if (Math.abs(zOffset) >= target.Z轴攻击范围) {
            return true;
        }
        if (hitTarget.防止无限飞 == true && (hitTarget.hp > 0)) {
            return true;
        }
        return false;
    }
}
