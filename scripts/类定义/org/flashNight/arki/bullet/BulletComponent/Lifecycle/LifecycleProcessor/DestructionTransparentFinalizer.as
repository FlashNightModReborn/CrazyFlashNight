/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/DestructionFinalizer.as
 */

import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.DestructionTransparentFinalizer implements IDestructionFinalizer {
    public static var instance:DestructionTransparentFinalizer = new DestructionTransparentFinalizer();
    public function DestructionTransparentFinalizer() { }
    
    /**
     * 执行销毁前的检查与后续处理
     */
    public function finalizeDestruction(target:MovieClip, isPointSet:Boolean):Void {
        var areaAABB:ICollider = target.aabbCollider;
        if (areaAABB) {
            areaAABB.getFactory().releaseCollider(areaAABB);
        }
        
        if (isPointSet && target.polygonCollider) {
            target.polygonCollider.getFactory().releaseCollider(target.polygonCollider);
        }
        
        if (target.击中时触发函数) {
            target.击中时触发函数();
        }
    }

    /**
     * 执行销毁前的检查与后续处理，不检查pointset
     */
    public function finalizeDestructionWithoutPointCheck(target:MovieClip):Void {
        var areaAABB:ICollider = target.aabbCollider;
        if (areaAABB) {
            areaAABB.getFactory().releaseCollider(areaAABB);
        }
        
        if (target.击中时触发函数) {
            target.击中时触发函数();
        }
    }
}
