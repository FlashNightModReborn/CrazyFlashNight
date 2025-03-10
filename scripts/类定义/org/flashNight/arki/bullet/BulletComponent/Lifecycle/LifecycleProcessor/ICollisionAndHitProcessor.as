// 文件路径：org/flashNight/arki/bullet/BulletComponent/Lifecycle/ICollisionAndHitProcessor.as
import org.flashNight.arki.bullet.BulletComponent.Attributes.*; // 属性定义优先
import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.bullet.BulletComponent.Init.*;       // 初始化组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*;    // 生命周期管理
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
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.*;

// 4. 单位组件
import org.flashNight.arki.unit.UnitComponent.Targetcache.*; // 目标缓存

// 5. 辅助模块（按字母顺序）
import org.flashNight.aven.Proxy.*;     // 代理模式实现
import org.flashNight.gesh.object.*;    // 对象管理
import org.flashNight.naki.Sort.*;      // 排序算法
import org.flashNight.neur.Event.*;     // 事件系统
import org.flashNight.sara.util.*;      // 工具方法
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