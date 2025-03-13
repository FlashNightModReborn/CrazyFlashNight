/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/PointCollisionDetector.as
 */
 

import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.PointCollisionDetector implements ICollisionDetector {
    public static var instance:PointCollisionDetector = new PointCollisionDetector();
    public function PointCollisionDetector() { }
    
    /**
     * 执行联弹的碰撞检测，先进行 AABB 检测，若碰撞再做多边形检测
     */
    public function processCollision(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult {
        var unitArea:AABBCollider = hitTarget.aabbCollider;
        if (unitArea) {
            unitArea.updateFromUnitArea(hitTarget);
        }
        var collisionResult:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);
        if (collisionResult.isColliding && target.polygonCollider) {
            collisionResult = target.polygonCollider.checkCollision(unitArea, zOffset);
        }
        return collisionResult;
    }
}
