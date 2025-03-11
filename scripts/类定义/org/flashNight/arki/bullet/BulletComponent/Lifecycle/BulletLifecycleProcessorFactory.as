import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*; // 各种处理器接口及实现

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycleProcessorFactory {

    /**
     * 根据传入的子弹 target 实例的属性，组装并返回一个合适的子弹生命周期处理器
     * @param target:MovieClip 子弹实例
     * @return IBulletLifecycleProcessor
     */
    public static function createBulletLifecycleProcessor(target:MovieClip):IBulletLifecycleProcessor {

        var colliderUpdater:IColliderUpdater;
        var targetRetriever:ITargetRetriever;
        var targetFilter:ITargetFilter;
        var nonPointDetector:ICollisionDetector;
        var pointDetector:ICollisionDetector;
        var hitResultProcessor:IHitResultProcessor;
        var postHitFinalizer:IPostHitFinalizer;
        var destructionFinalizer:IDestructionFinalizer;
        var collisionHitProcessor:ICollisionAndHitProcessor;

        if (target.透明检测) {
            colliderUpdater = new ColliderTransparentUpdater();
        }
        else {
            colliderUpdater = new ColliderUpdater();
        }

        if(target.友军伤害) {
            targetRetriever = new TargetALLRetriever();
        }
        else {
            targetRetriever = new TargetEnemyRetriever();
        }

        if(target.近战检测) {
            targetFilter = new TargetALLRetriever();
        }
        else {
            targetFilter = new TargetEnemyRetriever();
        }

        // 1. 准备可能使用到的组件实现，之后视情况选用。
        var nonPointDetector:ICollisionDetector     = new NonPointCollisionDetector();
        var pointDetector:ICollisionDetector        = new PointCollisionDetector();
        var hitResultProcessor:IHitResultProcessor  = new HitResultProcessor(); 
        // 如果不需要触发 kill事件，可换成 new HitResultNormalProcessor();

        // 2. 根据 bullet 属性选择碰撞更新器 & 销毁处理器 & 命中后处理器
        var colliderUpdater:IColliderUpdater;
        var destructionFinalizer:IDestructionFinalizer;
        var postHitFinalizer:IPostHitFinalizer;
        
        if (target.透明检测) {
            // 针对透明子弹的逻辑
            colliderUpdater       = new ColliderTransparentUpdater();
            destructionFinalizer = new DestructionTransparentFinalizer();
            // 如果透明子弹命中后处理逻辑也不同，可使用相应的实现
            // 例如：postHitFinalizer = new PostHitTransparentFinalizer();
            // 若实际没有特殊差异，可继续用默认实现
            postHitFinalizer     = new PostHitFinalizer(); 
        } else {
            // 普通子弹
            colliderUpdater       = new ColliderUpdater();
            destructionFinalizer = new DestructionFinalizer();
            postHitFinalizer     = new PostHitFinalizer();
        }

        // 3. 根据是否需要触发“击中时触发函数”等区分 CollisionAndHitProcessor
        var collisionHitProcessor:ICollisionAndHitProcessor;
        if (target.击中时触发函数 != null) {
            // 如果此子弹需要在击中时执行自定义回调，则用完整实现
            collisionHitProcessor = new CollisionAndHitProcessor();
        } else {
            // 如果不需要额外的回调或事件
            collisionHitProcessor = new CollisionAndHitNormalProcessor();
        }

        // 4. 根据子弹 / 发射者属性，选择目标检索器
        var targetRetriever:ITargetRetriever;
        if (target.友军伤害) {
            // 友军伤害时，检索全部单位
            targetRetriever = new TargetALLRetriever();
        } else {
            // 默认只检索敌方单位
            targetRetriever = new TargetEnemyRetriever();
        }

        // 5. 根据子弹是否近战检测等特性决定目标过滤器
        var targetFilter:ITargetFilter;
        if (target.近战检测) {
            // 近战过滤逻辑，可能允许跳过某些 “防止无限飞”
            targetFilter = new TargetFilter();
        } else {
            // 正常过滤器
            targetFilter = new TargetNormalFilter();
        }

        // 6. 最后组合所有组件，构建并返回 “动态子弹生命周期处理器” 基类实例
        var processor:IBulletLifecycleProcessor = new BaseBulletLifecycleProcessor(
            colliderUpdater,
            targetRetriever,
            targetFilter,
            nonPointDetector,
            pointDetector,
            hitResultProcessor,
            postHitFinalizer,
            destructionFinalizer,
            collisionHitProcessor
        );

        return processor;
    }
}
