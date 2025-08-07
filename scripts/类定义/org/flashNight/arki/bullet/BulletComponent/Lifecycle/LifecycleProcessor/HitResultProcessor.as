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

        // 使用宏展开+位掩码优化技术进行近战和爆炸检测
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        
        // 创建近战和爆炸的组合掩码（编译时计算：1 | 32 = 33）
        var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;
        
        // 一次位运算替代两次检测：非近战且非爆炸
        if ((target.flags & MELEE_EXPLOSIVE_MASK) === 0 && hitTarget.hp <= 0) {
            dispatcher.publish("kill", hitTarget);
        }
        
        damageResult.triggerDisplay(hitTarget._x, hitTarget._y);
    }
}
