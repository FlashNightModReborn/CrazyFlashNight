/**
 * File: org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor/HitResultProcessor.as
 */
 
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.neur.Event.*;     // 事件系统

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.HitResultProcessor implements IHitResultProcessor {
    public static var instance:HitResultProcessor = new HitResultProcessor();
    public function HitResultProcessor() { }
    
    /**
     * 处理命中结果：发布 "hit"、"kill" 事件，并触发伤害显示
     */
    public function processHitResult(target:MovieClip, shooter:MovieClip, hitTarget:MovieClip, collisionResult:CollisionResult, damageResult:DamageResult):Void {
        var dispatcher:EventDispatcher = hitTarget.dispatcher;
        dispatcher.publish("hit", hitTarget, shooter, target, collisionResult, damageResult);
        
        if (!target.近战检测 && !target.爆炸检测 && hitTarget.hp <= 0) {
            dispatcher.publish("kill", hitTarget);
        }
        
        damageResult.triggerDisplay(hitTarget._x, hitTarget._y);
    }
}
