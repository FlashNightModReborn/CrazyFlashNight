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
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycleProcessor {

    /**
     * 每帧调用的核心方法
     * @param target:MovieClip 当前子弹实例 (this)
     */
    public function processFrame(target:MovieClip):Void {
        if (this.updateCollider(target)) {
            return;
        }
        
        var unitMap:Array = this.getPotentialTargets(target);
        this.handleCollisionAndHit(target, unitMap);
        this.finalizeDestructionIfNeeded(target);
    }
    
    /**
     * [步骤1] 更新碰撞器
     * 缺省实现：若 target.透明检测 且未设置子弹区域，则调用 updateFromTransparentBullet，
     * 否则调用 updateFromBullet。这里同时计算是否需要联弹检测（isPointSet）。
     */
    public function updateCollider(target:MovieClip):Boolean {
        if (!target.area && !target.透明检测) {
            target.updateMovement(target);
            return true;
        }
        
        var detectionArea:MovieClip;
        var areaAABB:ICollider = target.aabbCollider;
        var bullet_rotation:Number = target._rotation; // 本地化，避免重复访问
        var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
        
        if (target.透明检测 && !target.子弹区域area) {
            areaAABB.updateFromTransparentBullet(this);
        } else {
            detectionArea = target.子弹区域area || target.area;
            areaAABB.updateFromBullet(target, detectionArea);
        }
        
        return false; // 返回 false 表示继续后续逻辑
    }
    
    /**
     * [步骤3] 获取潜在碰撞目标
     * 根据是否友军伤害从 TargetCacheManager 中获取目标
     */
    public function getPotentialTargets(target:MovieClip):Array {
        var shooter:MovieClip = target.shooter;
        if (shooter == undefined) {
            return []; // 异常情况：发射者不存在时返回空数组
        }
        
        if (target.友军伤害) {
            return TargetCacheManager.getCachedAll(shooter, 1);
        } else {
            return TargetCacheManager.getCachedEnemy(shooter, 1);
        }
    }
    
    /**
     * [步骤4] 处理碰撞和命中
     * 内部拆分为：
     *   - 目标过滤（shouldSkipHitTarget）
     *   - 基于是否联弹的不同，调用对应的碰撞检测处理器
     *   - 命中结果处理（processHitResult）
     *   - 碰撞循环后执行后处理（finalizePostHitProcessing）
     */
    public function handleCollisionAndHit(target:MovieClip, unitMap:Array):Void {
        var hitCount:Number = 0;
        var shouldGeneratePostHitEffect:Boolean = true;
        var areaAABB:ICollider = target.aabbCollider;
        var shooter:MovieClip = target.shooter;
        var bullet_rotation:Number = target._rotation;
        var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
        var len:Number = unitMap.length;
        
        for (var i:Number = 0; i < len; i++) {
            var hitTarget:MovieClip = unitMap[i];
            var zOffset:Number = hitTarget.Z轴坐标 - target.Z轴坐标;
            
            // 目标过滤：距离和“防止无限飞”条件
            if (this.shouldSkipHitTarget(target, hitTarget, zOffset)) {
                continue;
            }
            
            // 根据是否联弹选择不同的碰撞检测逻辑
            var collisionResult:CollisionResult = this.getCollisionResult(target, hitTarget, zOffset, areaAABB, isPointSet);
            if (!collisionResult.isColliding) {
                if (!collisionResult.isOrdered) {
                    break;
                }
                continue;
            }
            
            // 记录命中目标信息
            target.附加层伤害计算 = 0;
            target.命中对象 = hitTarget;
            hitCount++;
            var overlapRatio:Number = collisionResult.overlapRatio;
            
            // 命中时触发回调
            if (target.击中时触发函数) {
                target.击中时触发函数();
            }
            
            // 计算躲避状态
            var dodgeState:String = (target.伤害类型 == "真伤")
                ? "未躲闪"
                : DodgeHandler.calculateDodgeState(hitTarget, DodgeHandler.calcDodgeResult(shooter, hitTarget, target.命中率), target);
            // 计算伤害结果
            var damageResult:DamageResult = DamageCalculator.calculateDamage(target, shooter, hitTarget, overlapRatio, dodgeState);
            // 处理命中结果：事件派发、伤害显示及目标死亡处理
            this.processHitResult(target, shooter, hitTarget, collisionResult, damageResult);
        }
        
        // 碰撞循环后整体处理：动画、硬直、后续特效等
        this.finalizePostHitProcessing(target, shooter, hitCount, shouldGeneratePostHitEffect);
    }
    
    /**
     * 判断是否跳过当前命中目标
     * 条件包括：
     *   - Z轴距离超出攻击范围
     *   - “防止无限飞”标记且目标 HP>0（且非近战检测）的情况
     */
    private function shouldSkipHitTarget(target:MovieClip, hitTarget:MovieClip, zOffset:Number):Boolean {
        if (Math.abs(zOffset) >= target.Z轴攻击范围) {
            return true;
        }
        if (hitTarget.防止无限飞 == true && (hitTarget.hp > 0 || target.近战检测)) {
            return true;
        }
        return false;
    }
    
    /**
     * 根据是否联弹选择不同的碰撞检测处理器
     */
    private function getCollisionResult(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider, isPointSet:Boolean):CollisionResult {
        if (isPointSet) {
            return this.processCollisionForPointSet(target, hitTarget, zOffset, areaAABB);
        } else {
            return this.processCollisionForNonPointSet(hitTarget, zOffset, areaAABB);
        }
    }
    
    /**
     * 非联弹情况下的碰撞检测处理器
     * 仅执行 AABB 碰撞检测，避免额外的多边形检测开销
     */
    private function processCollisionForNonPointSet(hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult {
        var unitArea:AABBCollider = hitTarget.aabbCollider;
        if (unitArea) {
            unitArea.updateFromUnitArea(hitTarget);
        }
        return areaAABB.checkCollision(unitArea, zOffset);
    }
    
    /**
     * 联弹情况下的碰撞检测处理器
     * 在 AABB 检测基础上，若检测到碰撞则进一步执行多边形碰撞检测
     */
    private function processCollisionForPointSet(target:MovieClip, hitTarget:MovieClip, zOffset:Number, areaAABB:ICollider):CollisionResult {
        var unitArea:AABBCollider = hitTarget.aabbCollider;
        if (unitArea) {
            unitArea.updateFromUnitArea(hitTarget);
        }
        var collisionResult:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);
        if (collisionResult.isColliding && target.polygonCollider) {
            collisionResult = target.polygonCollider.checkCollision(unitArea, zOffset);
        }
        return collisionResult;
    }
    
    /**
     * 处理命中结果：发布 hit 消息、检查并发布 kill 消息，并触发伤害显示
     */
    private function processHitResult(target:MovieClip, shooter:MovieClip, hitTarget:MovieClip, collisionResult:CollisionResult, damageResult:DamageResult):Void {
        var dispatcher:EventDispatcher = hitTarget.dispatcher;
        dispatcher.publish("hit", hitTarget, shooter, target, collisionResult, damageResult);
        
        if (!target.近战检测 && !target.爆炸检测 && hitTarget.hp <= 0) {
            dispatcher.publish("kill", hitTarget);
        }
        
        damageResult.triggerDisplay(hitTarget._x, hitTarget._y);
    }
    
    /**
     * 碰撞循环结束后的后处理逻辑
     * 包括：播放消失动画、施加硬直以及触发后续特效
     */
    private function finalizePostHitProcessing(target:MovieClip, shooter:MovieClip, hitCount:Number, shouldGeneratePostHitEffect:Boolean):Void {
        if (hitCount > 0) {
            if (!target.穿刺检测) {
                target.gotoAndPlay("消失");
            }
            if (target.近战检测 && !target.不硬直) {
                shooter.硬直(shooter.man, _root.钝感硬直时间);
            }
            if (shouldGeneratePostHitEffect) {
                EffectSystem.Effect(target.击中后子弹的效果, target._x, target._y, shooter._xscale);
            }
        }
    }
    
    /**
     * [步骤6] 检查是否需要销毁并执行销毁逻辑
     * 若 target.shouldDestroy 为 true，则释放碰撞器资源，
     * 并处理击中地图效果后播放消失动画或直接移除影片剪辑
     */
    public function finalizeDestructionIfNeeded(target:MovieClip):Void {
        target.updateMovement(target);
        
        if (target.shouldDestroy(target)) {
            // 释放主碰撞器
            var areaAABB:ICollider = target.aabbCollider;
            if (areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }
            // 若存在 polygonCollider，则根据联弹情况释放
            var bullet_rotation:Number = target._rotation;
            var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
            if (isPointSet && target.polygonCollider) {
                target.polygonCollider.getFactory().releaseCollider(target.polygonCollider);
            }
            
            // 处理击中地图情况：效果播放、回调触发及动画
            if (target.击中地图) {
                target.霰弹值 = 1;
                EffectSystem.Effect(target.击中地图效果, target._x, target._y);
                if (target.击中时触发函数) {
                    target.击中时触发函数();
                }
                target.gotoAndPlay("消失");
            } else {
                // 否则直接移除影片剪辑
                target.removeMovieClip();
            }
        }
    }
}
