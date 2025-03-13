/**
 * File: org/flashNight/arki/bullet/BulletComponent/Lifecycle/LifecycleProcessor/ColliderUpdater.as
 */
 
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.component.Collider.*;    // 碰撞系统

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ColliderUpdater implements IColliderUpdater {
    public static var instance:ColliderUpdater = new ColliderUpdater();
    public function ColliderUpdater() { }
    
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    public function updateCollider(target:MovieClip):Boolean {
        if (!target.area && !target.透明检测) {
            target.updateMovement(target);
            return true;
        }
        
        var detectionArea:MovieClip;
        var areaAABB:ICollider = target.aabbCollider;

        if (target.透明检测 && !target.子弹区域area) {
            areaAABB.updateFromTransparentBullet(this);
        } else {
            detectionArea = target.子弹区域area || target.area;
            areaAABB.updateFromBullet(target, detectionArea);
        }
        
        return false; // 返回 false 表示继续后续处理
    }
}
