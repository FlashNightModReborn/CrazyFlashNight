/**
 * File: org/flashNight/arki/bullet/BulletComponent/Lifecycle/LifecycleProcessor/ColliderUpdater.as
 */
 
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

class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.ColliderUpdater implements IColliderUpdater {
    
    public function ColliderUpdater() { }
    
    /**
     * 更新子弹的碰撞器
     * @param target 当前子弹实例
     * @return 如果无需后续处理则返回 true，否则返回 false
     */
    public function updateCollider(target:MovieClip):Boolean {
        if (!target.area && !target.透明检测) {
            target.updateMovement(target);
            return true;
        }
        
        var detectionArea:MovieClip;
        var areaAABB:ICollider = target.aabbCollider;
        var bullet_rotation:Number = target._rotation; // 避免重复访问
        // 计算是否需要联弹检测
        var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
        
        if (target.透明检测 && !target.子弹区域area) {
            areaAABB.updateFromTransparentBullet(this);
        } else {
            detectionArea = target.子弹区域area || target.area;
            areaAABB.updateFromBullet(target, detectionArea);
        }
        
        return false; // 返回 false 表示继续后续处理
    }
}
