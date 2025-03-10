// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycleProcessor.as

// 1. 核心框架组件 (按包层级排序)
import org.flashNight.arki.bullet.BulletComponent.Attributes.*; // 属性定义优先
import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.bullet.BulletComponent.Init.*;       // 初始化组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;  // 生命周期管理
import org.flashNight.arki.bullet.BulletComponent.Movement.*;   // 移动逻辑
import org.flashNight.arki.bullet.BulletComponent.Shell.*;      // 弹壳组件
import org.flashNight.arki.bullet.BulletComponent.Type.*;       // 类型定义
import org.flashNight.arki.bullet.BulletComponent.Utils.*;      // 工具类

// 2. 子弹工厂（具体类单独导入）
import org.flashNight.arki.bullet.Factory.BulletFactory;

// 3. 其他组件（按功能分类）
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.component.Effect.*;      // 特效组件
import org.flashNight.arki.component.StatHandler.*; // 状态处理
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*; // 处理器组件

// 4. 单位组件
import org.flashNight.arki.unit.UnitComponent.Targetcache.*; // 目标缓存

// 5. 辅助模块（按字母顺序）
import org.flashNight.aven.Proxy.*;     // 代理模式实现
import org.flashNight.gesh.object.*;    // 对象管理
import org.flashNight.naki.Sort.*;      // 排序算法
import org.flashNight.neur.Event.*;     // 事件系统
import org.flashNight.sara.util.*;      // 工具方法

/**
 * 子弹生命周期处理器基类
 * 
 * 提供统一的每帧处理流程，将子弹逻辑拆分为多个步骤：
 *   1. 更新碰撞器
 *   2. 获取潜在目标
 *   3. 碰撞检测与命中处理（内部进一步拆分为目标过滤、检测分支、命中结果处理）
 *   4. 销毁前的后续处理
 * 
 * 重构目标：
 *   - 将 handleCollisionAndHit 内部逻辑拆分为多个粒度更细的方法，
 *     并基于是否联弹（isPointSet）拆分碰撞检测，避免不必要的多边形检测开销，
 *     后续可通过工厂模式装配不同的检测器。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.TransparentLifecycleProcessor {


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
    
    public function TransparentLifecycleProcessor() {
        colliderUpdater = new ColliderUpdater();
        targetRetriever = new TargetRetriever();
        targetFilter = new TargetFilter();
        nonPointDetector = new NonPointCollisionDetector();
        pointDetector = new PointCollisionDetector();
        hitResultProcessor = new HitResultProcessor();
        postHitFinalizer = new PostHitFinalizer();
        destructionFinalizer = new DestructionFinalizer();
        collisionHitProcessor = new CollisionAndHitProcessor();
    }
}
