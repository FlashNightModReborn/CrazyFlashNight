/**
 * File: org/flashNight/arki/bullet/BulletComponent/Lifecycle/LifecycleProcessor/ColliderUpdater.as
 */
 
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.component.Collider.*;    // 碰撞系统

// 透明子弹专用

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ColliderTransparentUpdater implements IColliderUpdater {
    public static var instance:ColliderTransparentUpdater = new ColliderTransparentUpdater();
    public function ColliderTransparentUpdater() { }
    
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    public function updateCollider(target:MovieClip):Boolean {
        var detectionArea:MovieClip;
        var areaAABB:ICollider = target.aabbCollider;
        
        // 直接判断子弹区域是否存在（已知 target.透明检测 必为 true）
        if (!target.子弹区域area) {
            areaAABB.updateFromTransparentBullet(this);
        } else {
            // 无需备选逻辑，因为 target.子弹区域area 必定存在
            detectionArea = target.子弹区域area;
            areaAABB.updateFromBullet(target, detectionArea);
        }
        
        return false; // 保持原有逻辑：继续后续处理
    }
}
