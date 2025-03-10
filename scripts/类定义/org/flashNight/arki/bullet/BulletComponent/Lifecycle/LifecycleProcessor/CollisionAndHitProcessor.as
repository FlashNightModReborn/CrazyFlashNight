// 文件路径：org/flashNight/arki/bullet/BulletComponent/Lifecycle/processors/CollisionAndHitProcessor.as

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
 * 默认碰撞命中处理器实现
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.LifecycleProcessor.CollisionAndHitProcessor implements ICollisionAndHitProcessor {
    
    public function CollisionAndHitProcessor() {}
    
    public function processCollisionAndHit(
        target:MovieClip,
        unitMap:Array,
        detector:ICollisionDetector,
        targetFilter:ITargetFilter,
        hitResultProcessor:IHitResultProcessor,
        postHitFinalizer:IPostHitFinalizer
    ):Void {
        var hitCount:Number = 0;
        var shouldGeneratePostHitEffect:Boolean = true;
        var areaAABB:ICollider = target.aabbCollider;
        var shooter:MovieClip = target.shooter;

        var len:Number = unitMap.length;
        
        for (var i:Number = 0; i < len; i++) {
            var hitTarget:MovieClip = unitMap[i];
            var zOffset:Number = hitTarget.Z轴坐标 - target.Z轴坐标;
            
            // 目标过滤逻辑
            if (targetFilter.shouldSkipHitTarget(target, hitTarget, zOffset)) {
                continue;
            }

            // 碰撞检测
            var collisionResult:CollisionResult = detector.processCollision(target, hitTarget, zOffset, areaAABB);

            if (!collisionResult.isColliding) {
                if (!collisionResult.isOrdered) break;
                continue;
            }
            
            // 记录命中信息
            target.附加层伤害计算 = 0;
            target.命中对象 = hitTarget;
            hitCount++;

            // 触发回调
            if (target.击中时触发函数) {
                target.击中时触发函数();
            }
            
            // 计算躲避状态
            var dodgeState:String = (target.伤害类型 == "真伤")
                ? "未躲闪"
                : DodgeHandler.calculateDodgeState(hitTarget, 
                    DodgeHandler.calcDodgeResult(shooter, hitTarget, target.命中率), 
                    target);
            
            // 计算伤害
            var damageResult:DamageResult = DamageCalculator.calculateDamage(
                target, shooter, hitTarget, 
                collisionResult.overlapRatio, 
                dodgeState
            );
            
            // 处理命中结果
            hitResultProcessor.processHitResult(
                target, shooter, hitTarget, 
                collisionResult, damageResult
            );
        }
        
        // 后处理
        postHitFinalizer.finalizePostHitProcessing(
            target, shooter, hitCount, 
            shouldGeneratePostHitEffect
        );
    }
}