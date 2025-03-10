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

interface org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ICollisionDetector {
    /**
     * 执行碰撞检测
     */
    function processCollision(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult;
}