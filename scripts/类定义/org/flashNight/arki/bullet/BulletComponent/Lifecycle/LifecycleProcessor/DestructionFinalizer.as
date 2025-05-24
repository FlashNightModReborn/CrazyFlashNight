/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/DestructionFinalizer.as
 */
 

import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;


class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.DestructionFinalizer implements IDestructionFinalizer {
    public static var instance:DestructionFinalizer = new DestructionFinalizer();
    public function DestructionFinalizer() { }
    
    /**
     * 执行销毁前的检查与后续处理
     */
    public function finalizeDestruction(target:MovieClip, isPointSet:Boolean):Void {
        target.updateMovement(target);
        
        if (target.shouldDestroy(target)) {
            var areaAABB:ICollider = target.aabbCollider;
            if (areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }
            
            if (isPointSet && target.polygonCollider) {
                target.polygonCollider.getFactory().releaseCollider(target.polygonCollider);
            }
            
            if (target.击中地图) {
                target.霰弹值 = 1;
                EffectSystem.Effect(target.击中地图效果, target._x, target._y);
                if (target.击中时触发函数) {
                    target.击中时触发函数();
                }
                target.gotoAndPlay("消失");
            } else {
                target.removeMovieClip();
            }
        }
    }
    /**
     * 执行销毁前的检查与后续处理，不检查pointset
     */
    public function finalizeDestructionWithoutPointCheck(target:MovieClip):Void {
        target.updateMovement(target);
        
        if (target.shouldDestroy(target)) {
            var areaAABB:ICollider = target.aabbCollider;
            if (areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }
            
            if (target.击中地图) {
                target.霰弹值 = 1;
                EffectSystem.Effect(target.击中地图效果, target._x, target._y);
                if (target.击中时触发函数) {
                    target.击中时触发函数();
                }
                target.gotoAndPlay("消失");
            } else {
                target.removeMovieClip();
            }
        }
    }
}
