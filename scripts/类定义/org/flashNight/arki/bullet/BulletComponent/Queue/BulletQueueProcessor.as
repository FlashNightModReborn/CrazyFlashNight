// ============================================================================
// 子弹队列处理器（轻量版）
// ----------------------------------------------------------------------------
// 功能：协调子弹的有序处理，在帧尾触发排序和执行
// ============================================================================

import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.component.Collider.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;  
import org.flashNight.arki.component.Damage.*;     
import org.flashNight.arki.component.*;
import org.flashNight.arki.component.Effect.*;
import org.flashNight.arki.unit.UnitComponent.Targetcache.*;
import org.flashNight.arki.render.*;
import org.flashNight.sara.util.*;      
import org.flashNight.neur.Event.*;     
import org.flashNight.arki.component.StatHandler.*;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletQueueProcessor {
    public static var queue:BulletQueue;
    
    /**
     * 初始化处理器
     */
    public static function initialize():Boolean {
        queue = new BulletQueue();
        return true;
    }

    public static function preCheck(bullet:Object):Boolean {
        // 仅用到透明标志即可完成早退判定
        #include "../macros/FLAG_TRANSPARENCY.as"

        // 局部化 flags，避免后续频繁取属性
        var flags:Number = bullet.flags;

        // 提前做一次位运算（可选缓存到实例，供第二段直接复用，减少一次位运算）
        var isTransparent:Boolean = (flags & FLAG_TRANSPARENCY) != 0;

        // 纯运动弹：无区域且不透明 → 只做位移更新，跳过后续所有重逻辑
        if (!bullet.area && !isTransparent) {
            bullet.updateMovement(bullet);
            // _root.服务器.发布服务器消息(false + "子弹纯运动更新 " + bullet);
            return false; // 不进入执行段
        }

        // 进入执行段（碰撞与结算）
        queue.add(bullet);
        //_root.服务器.发布服务器消息(true + "子弹进入执行段" + bullet + ":" + queue.getCount());
        // _root.服务器.发布服务器消息(queue.toString() + " 子弹进入执行段 " + bullet);
        return true;
    }
    
    /**
     * 优化版函数工厂：根据子弹类型返回特化的处理函数
     * 在绑定时一次性确定子弹类型，避免每帧重复检测
     * 
     * 分支消除策略：
     * - 创建时检测透明标志，返回对应的特化函数
     * - 透明子弹：总是需要进入执行段
     * - 非透明子弹：根据 area 属性决定是否进入执行段
     * 
     * @param bullet 子弹对象，用于预先检测类型
     * @return Function 特化的帧处理函数
     */
    public static function createOptimizedPreCheck(bullet:Object):Function {
        // 在闭包外部捕获静态引用
        var queueRef:BulletQueue = queue;
        
        // 编译时宏展开
        #include "../macros/FLAG_TRANSPARENCY.as"
        
        // 创建时一次性检测透明标志
        var isTransparent:Boolean = (bullet.flags & FLAG_TRANSPARENCY) != 0;
        
        // 根据透明标志返回不同的特化函数
        if (isTransparent) {
            // 透明子弹：总是进入执行段
            return function():Boolean {
                queueRef.add(this);
                return true;
            };
        } else {
            // 非透明子弹：根据 area 决定
            return function():Boolean {
                var bullet:Object = this;
                
                // 纯运动弹：无区域的非透明子弹
                if (!bullet.area) {
                    bullet.updateMovement(bullet);
                    return false;
                }
                
                // 有区域的非透明子弹：进入执行段
                queueRef.add(bullet);
                return true;
            };
        }
    }

    public static function processQueue():Void {
        // 空队列早退优化：根据性能分析，约41%的调用是空队列
        if (queue.getCount() == 0) {
            return;
        }
        
        // _root.服务器.发布服务器消息(queue.toString() + " 发射的子弹进入执行段");
        queue.forEachSorted(executeLogic);
        queue.clear();
    }

    /**
     * 执行子弹的主要逻辑（碰撞检测、伤害计算等）
     * @param bullet 子弹实例
     */
    public static function executeLogic(bullet:MovieClip):Void {
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_TRANSPARENCY.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"

        // 复用第一段的可选缓存；若无则即时计算
        var flags:Number = bullet.flags;
        var isTransparent:Boolean = (flags & FLAG_TRANSPARENCY) != 0;

        var areaAABB:AABBCollider = bullet.aabbCollider;
        var detectionArea:MovieClip = null;

        var rot:Number = bullet._rotation;
        var isPointSet:Boolean = ((flags & FLAG_CHAIN) != 0) && (rot != 0 && rot != 180);
        var bulletZOffset:Number = bullet.Z轴坐标;
        var bulletZRange:Number  = bullet.Z轴攻击范围;

        // 更新碰撞体（保持与原实现一致）
        if (isTransparent && !bullet.子弹区域area) {
            areaAABB.updateFromTransparentBullet(bullet);
        } else {
            detectionArea = bullet.子弹区域area || bullet.area;
            areaAABB.updateFromBullet(bullet, detectionArea);
        }

        if (_root.调试模式) {
            // 画当前AABB + Z轴上下边界线
            AABBRenderer.renderAABB(areaAABB, 0, "line", bulletZRange);
        }

        // 取目标集（友伤/敌方）
        var gameWorld:MovieClip = _root.gameworld;
        var shooter:MovieClip = gameWorld[bullet.发射者名];
        var rangeResult:Object = bullet.友军伤害
            ? TargetCacheManager.getCachedAllFromIndex(shooter, 1, areaAABB)
            : TargetCacheManager.getCachedEnemyFromIndex(shooter, 1, areaAABB);

        var unitMap:Array = rangeResult.data;
        var startIndex:Number = rangeResult.startIndex;

        bullet.shouldGeneratePostHitEffect = true;

        var len:Number = unitMap.length;
        var i:Number;
        var hitTarget:MovieClip;
        var zOffset:Number;
        var unitArea:AABBCollider;
        var collisionResult:CollisionResult;
        var overlapRatio:Number;
        var overlapCenter:Vector;

        for (i = startIndex; i < len; ++i) {
            hitTarget = bullet.hitTarget = unitMap[i];

            // Z 轴粗判
            zOffset = bulletZOffset - hitTarget.Z轴坐标;
            if (Math.abs(zOffset) >= bulletZRange) continue;

            if (hitTarget.hp > 0 && hitTarget.防止无限飞 != true) {
                unitArea = hitTarget.aabbCollider;

                // AABB 检测（可能早退）
                collisionResult = areaAABB.checkCollision(unitArea, zOffset);
                if (!collisionResult.isColliding) {
                    if (collisionResult.isOrdered) continue;
                    break;
                }

                // 仅在需要时才更新多边形碰撞体
                if (isPointSet) {
                    bullet.polygonCollider.updateFromBullet(bullet, detectionArea);
                    collisionResult = bullet.polygonCollider.checkCollision(unitArea, zOffset);
                }

                if (_root.调试模式) {
                    AABBRenderer.renderAABB(areaAABB, zOffset, "thick");
                    AABBRenderer.renderAABB(unitArea, zOffset, "filled");
                }

                overlapRatio  = collisionResult.overlapRatio;
                overlapCenter = collisionResult.overlapCenter;

                // 命中处理
                bullet.hitCount++;
                bullet.附加层伤害计算 = 0;
                bullet.命中对象 = hitTarget;

                var dodgeState = (bullet.伤害类型 == "真伤") ? "未躲闪" :
                    DodgeHandler.calculateDodgeState(
                        hitTarget,
                        DodgeHandler.calcDodgeResult(shooter, hitTarget, bullet.命中率),
                        bullet
                    );

                if (bullet.击中时触发函数) bullet.击中时触发函数();

                var damageResult:DamageResult = DamageCalculator.calculateDamage(
                    bullet, shooter, hitTarget, overlapRatio, dodgeState
                );

                var dispatcher:EventDispatcher = hitTarget.dispatcher;
                dispatcher.publish("hit", hitTarget, shooter, bullet, collisionResult, damageResult);

                // kill/death 分发（按原注释保持行为）
                var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;
                if (hitTarget.hp <= 0) {
                    dispatcher.publish((flags & MELEE_EXPLOSIVE_MASK) === 0 ? "kill" : "death", hitTarget);
                    shooter.dispatcher.publish("enemyKilled", hitTarget, bullet);
                }

                damageResult.triggerDisplay(hitTarget._x, hitTarget._y);

                // 近战硬直 / 非穿刺消失
                if ((flags & FLAG_MELEE) && !bullet.不硬直) {
                    shooter.硬直(shooter.man, _root.钝感硬直时间);
                } else if ((flags & FLAG_PIERCE) == 0) {
                    bullet.gotoAndPlay("消失");
                }
            }

            // 穿刺上限
            if (bullet.pierceLimit && bullet.pierceLimit < bullet.hitCount) {
                bullet.shouldDestroy = function():Boolean { return true; };
                break;
            }
        }

        // 命中后效果
        if (bullet.hitCount > 0 && bullet.shouldGeneratePostHitEffect) {
            EffectSystem.Effect(bullet.击中后子弹的效果, bullet._x, bullet._y, shooter._xscale);
        }

        // 与原实现一致：执行段末尾做一次位移更新
        bullet.updateMovement(bullet);

        // 销毁判定与后续
        if (bullet.shouldDestroy(bullet)) {
            areaAABB.getFactory().releaseCollider(areaAABB);
            if (isPointSet) {
                bullet.polygonCollider.getFactory().releaseCollider(bullet.polygonCollider);
            }

            if (bullet.击中地图) {
                bullet.霰弹值 = 1;
                EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
                if (bullet.击中时触发函数) bullet.击中时触发函数();
                bullet.gotoAndPlay("消失");
            } else {
                bullet.removeMovieClip();
            }
            return;
        }
    }
}