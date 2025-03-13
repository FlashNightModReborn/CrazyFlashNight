/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/HitResultProcessor.as
 */
 
 
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.neur.Event.*;     // 事件系统

// 不发送kill事件

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.HitResultNormalProcessor implements IHitResultProcessor {
    public static var instance:HitResultNormalProcessor = new HitResultNormalProcessor();
    public function HitResultNormalProcessor() { }
    
    /**
     * 处理命中结果：发布 "hit" 事件，并触发伤害显示
     */
    public function processHitResult(target:MovieClip, shooter:MovieClip, hitTarget:MovieClip, collisionResult:CollisionResult, damageResult:DamageResult):Void {
        hitTarget.dispatcher.publish("hit", hitTarget, shooter, target, collisionResult, damageResult);
        
        
        damageResult.triggerDisplay(hitTarget._x, hitTarget._y);
    }
}
