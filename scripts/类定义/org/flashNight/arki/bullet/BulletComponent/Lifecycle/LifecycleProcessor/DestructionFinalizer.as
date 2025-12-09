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
        // === 宏展开：实例状态标志位 ===
        #include "../macros/STATE_HIT_MAP.as"

        target.updateMovement(target);

        if (target.shouldDestroy(target)) {
            var areaAABB:ICollider = target.aabbCollider;
            if (areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }

            if (isPointSet && target.polygonCollider) {
                target.polygonCollider.getFactory().releaseCollider(target.polygonCollider);
            }

            // 读取实例状态标志位，检测击中地图标志
            var sf:Number = target.stateFlags | 0;
            var hitMap:Boolean = (sf & STATE_HIT_MAP) != 0;

            if (hitMap) {
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
        // === 宏展开：实例状态标志位 ===
        #include "../macros/STATE_HIT_MAP.as"

        target.updateMovement(target);

        if (target.shouldDestroy(target)) {
            var areaAABB:ICollider = target.aabbCollider;
            if (areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }

            // 读取实例状态标志位，检测击中地图标志
            var sf:Number = target.stateFlags | 0;
            var hitMap:Boolean = (sf & STATE_HIT_MAP) != 0;

            if (hitMap) {
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
