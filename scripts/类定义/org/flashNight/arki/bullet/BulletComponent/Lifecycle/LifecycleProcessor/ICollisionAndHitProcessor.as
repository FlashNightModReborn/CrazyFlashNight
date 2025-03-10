// 文件路径：org/flashNight/arki/bullet/BulletComponent/Lifecycle/ICollisionAndHitProcessor.as
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.component.StatHandler.*; // 状态处理
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

/**
 * 碰撞命中处理器接口
 */
interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ICollisionAndHitProcessor {
    
    /**
     * 执行完整的碰撞检测与命中处理流程
     * @param target 子弹实例
     * @param unitMap 潜在目标集合
     * @param detector 碰撞检测器
     * @param targetFilter 目标过滤器
     * @param hitResultProcessor 命中结果处理器
     * @param postHitFinalizer 命中后处理
     */
    function processCollisionAndHit(
        target:MovieClip,
        unitMap:Array,
        detector:ICollisionDetector,
        targetFilter:ITargetFilter,
        hitResultProcessor:IHitResultProcessor,
        postHitFinalizer:IPostHitFinalizer
    ):Void;
}