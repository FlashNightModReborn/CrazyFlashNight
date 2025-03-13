import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ICollisionDetector {
    /**
     * 执行碰撞检测
     */
    function processCollision(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult;
}