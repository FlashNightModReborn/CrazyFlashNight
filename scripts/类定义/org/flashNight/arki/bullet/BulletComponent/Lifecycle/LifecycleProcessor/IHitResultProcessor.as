import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.neur.Event.*;     // 事件系统


interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.IHitResultProcessor {
    /**
     * 处理命中结果：发布 "hit"、"kill" 事件，并触发伤害显示
     */
    function processHitResult(target:MovieClip, shooter:MovieClip, hitTarget:MovieClip, collisionResult:CollisionResult, damageResult:DamageResult):Void;
}