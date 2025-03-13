// 文件路径：org/flashNight/arki/bullet/BulletComponent/Lifecycle/processors/CollisionAndHitProcessor.as

import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.component.StatHandler.*; // 状态处理
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

/**
 * 针对无击中回调的子弹
 */

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.CollisionAndHitNormalProcessor implements ICollisionAndHitProcessor {
    public static var instance:CollisionAndHitNormalProcessor = new CollisionAndHitNormalProcessor();
    public function CollisionAndHitNormalProcessor() {}
    
    public function processCollisionAndHit(
        target:MovieClip,
        unitMap:Array,
        detector:ICollisionDetector,
        targetFilter:ITargetFilter,
        hitResultProcessor:IHitResultProcessor,
        postHitFinalizer:IPostHitFinalizer
    ):Void {
        var hitCount:Number = 0;
        var shouldGeneratePostHitEffect:Boolean = true;
        var areaAABB:ICollider = target.aabbCollider;
        var shooter:MovieClip = target.shooter;

        var len:Number = unitMap.length;
        
        for (var i:Number = 0; i < len; i++) {
            var hitTarget:MovieClip = unitMap[i];
            var zOffset:Number = hitTarget.Z轴坐标 - target.Z轴坐标;
            
            // 目标过滤逻辑
            if (targetFilter.shouldSkipHitTarget(target, hitTarget, zOffset)) {
                continue;
            }

            // 碰撞检测
            var collisionResult:CollisionResult = detector.processCollision(target, hitTarget, zOffset, areaAABB);

            if (!collisionResult.isColliding) {
                if (!collisionResult.isOrdered) break;
                continue;
            }
            
            // 记录命中信息
            target.附加层伤害计算 = 0;
            target.命中对象 = hitTarget;
            hitCount++;
            
            // 计算躲避状态
            var dodgeState:String = (target.伤害类型 == "真伤")
                ? "未躲闪"
                : DodgeHandler.calculateDodgeState(hitTarget, 
                    DodgeHandler.calcDodgeResult(shooter, hitTarget, target.命中率), 
                    target);
            
            // 计算伤害
            var damageResult:DamageResult = DamageCalculator.calculateDamage(
                target, shooter, hitTarget, 
                collisionResult.overlapRatio, 
                dodgeState
            );
            
            // 处理命中结果
            hitResultProcessor.processHitResult(
                target, shooter, hitTarget, 
                collisionResult, damageResult
            );
        }
        
        // 后处理
        postHitFinalizer.finalizePostHitProcessing(
            target, shooter, hitCount, 
            shouldGeneratePostHitEffect
        );
    }
}