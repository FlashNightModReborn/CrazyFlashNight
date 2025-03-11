/**
 * File: org/flashNight/arki/bullet/BulletComponent/Lifecycle/LifecycleProcessor/ColliderUpdater.as
 */

import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.component.Collider.*;    // 碰撞系统

// 非透明子弹使用

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ColliderNormalUpdater implements IColliderUpdater {
    public static var instance:ColliderNormalUpdater = new ColliderNormalUpdater();
    public function ColliderNormalUpdater() { }
    
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    public function updateCollider(target:MovieClip):Boolean {
        if (!target.area) {
            target.updateMovement(target);
            return true;
        }
        
        var areaAABB:ICollider = target.aabbCollider;
        
        areaAABB.updateFromBullet(target, target.子弹区域area || target.area);
        
        return false; // 返回 false 表示继续后续处理
    }
}
