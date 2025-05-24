/**
 * 2) 可动态组装组件的基类
 *    实现了 IBulletLifecycleProcessor 接口，内部持有多种处理器引用
 */
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.component.Collider.*; // 碰撞系统

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BaseBulletLifecycleProcessor implements IBulletLifecycleProcessor {
    // 各个工具类实例
    private var colliderUpdater:IColliderUpdater;
    private var targetRetriever:ITargetRetriever;
    private var targetFilter:ITargetFilter;
    private var nonPointDetector:ICollisionDetector;
    private var pointDetector:ICollisionDetector;
    private var hitResultProcessor:IHitResultProcessor;
    private var postHitFinalizer:IPostHitFinalizer;
    private var destructionFinalizer:IDestructionFinalizer;
    private var collisionHitProcessor:ICollisionAndHitProcessor;

    /**
     * 构造方法：接受所需的处理器组件
     */
    public function BaseBulletLifecycleProcessor(colliderUpdater:IColliderUpdater, targetRetriever:ITargetRetriever, targetFilter:ITargetFilter, nonPointDetector:ICollisionDetector, pointDetector:ICollisionDetector, hitResultProcessor:IHitResultProcessor, postHitFinalizer:IPostHitFinalizer, destructionFinalizer:IDestructionFinalizer, collisionHitProcessor:ICollisionAndHitProcessor) {
        this.colliderUpdater = colliderUpdater;
        this.targetRetriever = targetRetriever;
        this.targetFilter = targetFilter;
        this.nonPointDetector = nonPointDetector;
        this.pointDetector = pointDetector;
        this.hitResultProcessor = hitResultProcessor;
        this.postHitFinalizer = postHitFinalizer;
        this.destructionFinalizer = destructionFinalizer;
        this.collisionHitProcessor = collisionHitProcessor;
    }

    /**
     * 每帧为联弹调用的核心方法
     * @param target:MovieClip 当前子弹实例 (this)
     */
    public function processFrame(target:MovieClip):Void {
        if (colliderUpdater.updateCollider(target)) {
            return;
        }

        var unitMap:Array = targetRetriever.getPotentialTargets(target);
        var isPointSet:Boolean = target._rotation % 180 !== 0;
        var detector:ICollisionDetector = isPointSet ? pointDetector : nonPointDetector;

        collisionHitProcessor.processCollisionAndHit(target, unitMap, detector, targetFilter, hitResultProcessor, postHitFinalizer);

        destructionFinalizer.finalizeDestruction(target, isPointSet);
    }

    /**
     * 非联弹时使用
     * @param target:MovieClip 当前子弹实例 (this)
     */
    public function processFrameWithoutPointCheck(target:MovieClip):Void {
        if (colliderUpdater.updateCollider(target)) {
            return;
        }

        var unitMap:Array = targetRetriever.getPotentialTargets(target);
        collisionHitProcessor.processCollisionAndHit(target, unitMap, nonPointDetector, targetFilter, hitResultProcessor, postHitFinalizer);

        destructionFinalizer.finalizeDestructionWithoutPointCheck(target);
    }
}
