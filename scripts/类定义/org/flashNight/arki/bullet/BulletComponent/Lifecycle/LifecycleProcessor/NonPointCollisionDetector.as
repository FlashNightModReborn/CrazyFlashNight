/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/NonPointCollisionDetector.as
 */
 

import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.NonPointCollisionDetector implements ICollisionDetector {
    public static var instance:NonPointCollisionDetector = new NonPointCollisionDetector();
    public function NonPointCollisionDetector() { }
    
    /**
     * 执行非联弹的碰撞检测
     */
    public function processCollision(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult {
        var unitArea:AABBCollider = hitTarget.aabbCollider;
        if (unitArea) {
            unitArea.updateFromUnitArea(hitTarget);
        }
        return areaAABB.checkCollision(unitArea, zOffset);
    }
}
