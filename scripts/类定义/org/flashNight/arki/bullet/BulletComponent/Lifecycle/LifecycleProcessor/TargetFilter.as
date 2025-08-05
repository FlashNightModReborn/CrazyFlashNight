
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.TargetFilter implements ITargetFilter{
    public static var instance:TargetFilter = new TargetFilter();
    public function TargetFilter() {
    }

    /**
     * 根据 Z 轴距离与“防止无限飞”等条件判断是否跳过当前目标
     */
    public function shouldSkipHitTarget(target:MovieClip, hitTarget:MovieClip, zOffset:Number):Boolean {
        if (zOffset * zOffset >= target.zAttackRangeSq) {
            return true;
        }                
        
        #include "../macros/FLAG_MELEE.as"
        if (hitTarget.防止无限飞 == true && (target.flags & FLAG_MELEE) != 0) {
            return true;
        }
        return false;
    }
}
