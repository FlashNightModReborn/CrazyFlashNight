// 文件路径：org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycleProcessor.as

// 1. 核心框架组件 (按包层级排序)
import org.flashNight.arki.bullet.BulletComponent.Attributes.*; // 属性定义优先
import org.flashNight.arki.bullet.BulletComponent.Collider.*;   // 碰撞组件
import org.flashNight.arki.bullet.BulletComponent.Init.*;       // 初始化组件
import org.flashNight.arki.bullet.BulletComponent.Lifecycle.*; // 生命周期管理
import org.flashNight.arki.bullet.BulletComponent.Movement.*;  // 移动逻辑
import org.flashNight.arki.bullet.BulletComponent.Shell.*;     // 弹壳组件
import org.flashNight.arki.bullet.BulletComponent.Type.*;      // 类型定义
import org.flashNight.arki.bullet.BulletComponent.Utils.*;     // 工具类

// 2. 子弹工厂（具体类单独导入）
import org.flashNight.arki.bullet.Factory.BulletFactory;

// 3. 其他组件（按功能分类）
import org.flashNight.arki.component.Collider.*;    // 碰撞系统
import org.flashNight.arki.component.Damage.*;      // 伤害计算
import org.flashNight.arki.component.Effect.*;      // 特效组件

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
 * 提供一个统一的框架，将子弹在每帧需要执行的逻辑拆分为多个细分步骤，方便子类按需覆写。
 *
 * 目标：
 *  1. 透明检测、碰撞检测、友军伤害等细节，在子类或额外组件中进行定制，而不是在运行时用 if-else 大量分支。
 *  2. 对子弹的更新流程做出一个“模板方法”：基类定义主流程，子类只需覆盖需要改变的环节。
 */
class org.flashNight.arki.bullet.BulletComponent.Lifecycle.BulletLifecycleProcessor {

    /**
     * 每帧调用的核心方法
     * @param target:MovieClip 当前子弹实例 (this)
     */
    public function processFrame(target:MovieClip):Void {
        // 步骤1：若需要，更新碰撞器（含透明/非透明检测）
        this.updateCollider(target);

        // 步骤2：调试绘制，非必要，可以单独拆分以控制性能
        this.debugDraw(target);

        // 步骤3：获取潜在的碰撞目标（友军或敌军等）
        var unitMap:Array = this.getPotentialTargets(target);

        // 步骤4：执行碰撞检测与命中处理（包括击中函数、伤害结算、硬直等）
        this.handleCollisionAndHit(target, unitMap);

        // 步骤5：更新运动（移动/动画/轨迹等）
        this.updateMovement(target);

        // 步骤6：检查销毁条件并执行销毁逻辑（释放碰撞器、移除MC或播放消失动画等）
        this.finalizeDestructionIfNeeded(target);
    }

    // ==================== 粒度更细的抽象/虚方法 ===================== //

    /**
     * [步骤1] 更新碰撞器
     *  - 判断是透明子弹还是普通子弹，选择调用 updateFromTransparentBullet 或 updateFromBullet
     *  - 若启用了联弹检测，需要更新多边形碰撞器 polygonCollider
     *  - 缺省实现：如果 target.透明检测 && !target.子弹区域，则 updateFromTransparentBullet；否则 updateFromBullet
     */
    public function updateCollider(target:MovieClip):Void {
        var areaAABB:ICollider = target.aabbCollider;
        if(!areaAABB) {
            return; // 如果没有碰撞器则跳过
        }

        if (target.透明检测 && !target.子弹区域) {
            areaAABB.updateFromTransparentBullet(target);
        } else {
            var detectionArea:MovieClip = target.子弹区域 || target.area;
            areaAABB.updateFromBullet(target, detectionArea);
        }

        // 如果有联弹检测需求且角度不为0或180，则更新 polygonCollider
        var bullet_rotation:Number = target._rotation;
        var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
        if (isPointSet && target.polygonCollider) {
            var detectionArea2:MovieClip = target.子弹区域 || target.area;
            target.polygonCollider.updateFromBullet(target, detectionArea2);
        }
    }

    /**
     * [步骤2] 调试模式下绘制碰撞区域
     */
    public function debugDraw(target:MovieClip):Void {
        if(_root.调试模式) {
            var detectionArea:MovieClip = target.子弹区域 || target.area;
            if(detectionArea) {
                _root.绘制线框(detectionArea);
            }
        }
    }

    /**
     * [步骤3] 获取潜在碰撞目标
     *  - 判断是友军伤害还是敌军伤害，从而调用不同的 TargetCacheManager 缓存方法
     */
    public function getPotentialTargets(target:MovieClip):Array {
        var shooter:MovieClip = _root.gameworld[target.发射者名];
        if (shooter == undefined) {
            return []; // 发射者不存在的异常情况，返回空数组
        }

        if(target.友军伤害) {
            return TargetCacheManager.getCachedAll(shooter, 1);
        } else {
            return TargetCacheManager.getCachedEnemy(shooter, 1);
        }
    }

    /**
     * [步骤4] 处理碰撞和命中
     *  - 遍历单位列表，判断Z轴距离、像素碰撞等
     *  - 命中后调用击中时触发函数、伤害结算等
     *  - 若为近战且不硬直，则发射者硬直
     *  - 若不穿刺，则播放"消失"动画
     *  - 将命中次数等信息记录在 target 对象上
     */
    public function handleCollisionAndHit(target:MovieClip, unitMap:Array):Void {
        target.击中次数 = 0;
        target.shouldGeneratePostHitEffect = true;

        // 获取主要碰撞器
        var areaAABB:ICollider = target.aabbCollider;
        if(!areaAABB) return;

        // 联弹检测需要的碰撞器
        var bullet_rotation:Number = target._rotation;
        var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);

        var len:Number = unitMap.length;
        for(var i:Number = 0; i < len; i++) {
            var hitTarget:MovieClip = unitMap[i];
            var zOffset:Number = hitTarget.Z轴坐标 - target.Z轴坐标;

            // 判断Z轴距离是否在攻击范围内
            if(Math.abs(zOffset) >= target.Z轴攻击范围) {
                continue;
            }

            // 命中前判定：例如“防止无限飞”或 “目标HP<=0且非近战检测”
            if (hitTarget.防止无限飞 == true && (hitTarget.hp > 0 || target.近战检测)) {
                // 说明目标不接受命中，跳过
                continue;
            }

            // 更新目标单位的 aabbCollider
            var unitArea:AABBCollider = hitTarget.aabbCollider;
            if(unitArea) {
                unitArea.updateFromUnitArea(hitTarget);
            }

            // 检查碰撞
            var collisionResult:CollisionResult = areaAABB.checkCollision(unitArea, zOffset);
            if(!collisionResult.isColliding) {
                // 如果是有序重叠判断 (isOrdered=true) 并且没撞到则继续，否则可以结束
                if(!collisionResult.isOrdered) {
                    break; 
                }
                continue;
            }

            // 若 isPointSet，需要再用 polygonCollider 做更精细判定
            if(isPointSet && target.polygonCollider) {
                collisionResult = target.polygonCollider.checkCollision(unitArea, zOffset);
                if(!collisionResult.isColliding) {
                    continue;
                }
            }

            // 记录碰撞信息
            target.hitTarget = hitTarget;
            target.击中次数++;
            var overlapRatio:Number = collisionResult.overlapRatio;

            // 击中时触发函数
            if(target.击中时触发函数) {
                target.击中时触发函数();
            }

            // 伤害计算和事件派发
            var shooter:MovieClip = _root.gameworld[target.发射者名];
            var dodgeState:String = (target.伤害类型 == "真伤")
                ? "未躲闪"
                : _root.躲闪状态计算(hitTarget, _root.根据命中计算闪避结果(shooter, hitTarget, target.命中率), target);

            var damageResult:DamageResult = DamageCalculator.calculateDamage(target, shooter, hitTarget, overlapRatio, dodgeState);
            hitTarget.dispatcher.publish("hit", hitTarget, shooter, target, collisionResult, damageResult);
            damageResult.triggerDisplay(hitTarget._x, hitTarget._y);

            // 近战检测 + 不硬直=false => 发射者硬直
            if(target.近战检测 && !target.不硬直) {
                shooter.硬直(shooter.man, _root.钝感硬直时间);
            }

            // 若不是穿刺子弹，则子弹碰撞后播放消失动画
            if(!target.穿刺检测) {
                target.gotoAndPlay("消失");
            }
        }
    }

    /**
     * [步骤5] 更新运动逻辑
     * 默认调用 target.updateMovement(target)
     */
    public function updateMovement(target:MovieClip):Void {
        target.updateMovement(target);
    }

    /**
     * [步骤6] 检查是否需要销毁并执行销毁逻辑
     *  - 如果 shouldDestroy 为 true，则释放碰撞器资源、是否击中地图等处理
     *  - 播放 "消失" 动画或直接 removeMovieClip()
     */
    public function finalizeDestructionIfNeeded(target:MovieClip):Void {
        if(!target.shouldDestroy) {
            return; // 若未挂载 shouldDestroy 方法，则无法判断
        }

        if(target.shouldDestroy(target)) {
            // 释放碰撞器
            var areaAABB:ICollider = target.aabbCollider;
            if(areaAABB) {
                areaAABB.getFactory().releaseCollider(areaAABB);
            }
            // 若存在 polygonCollider，亦释放
            var bullet_rotation:Number = target._rotation;
            var isPointSet:Boolean = target.联弹检测 && (bullet_rotation != 0 && bullet_rotation != 180);
            if(isPointSet && target.polygonCollider) {
                target.polygonCollider.getFactory().releaseCollider(target.polygonCollider);
            }

            // 击中地图时
            if(target.击中地图) {
                target.霰弹值 = 1;
                EffectSystem.Effect(target.击中地图效果, target._x, target._y);
                if(target.击中时触发函数) {
                    target.击中时触发函数();
                }
                target.gotoAndPlay("消失");
            } else {
                // 否则直接移除
                target.removeMovieClip();
            }
        }
    }
}
