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
    public static var activeQueues:Object; // 按阵营分类的活动队列
    
    /**
     * 初始化处理器
     */
    public static function initialize():Boolean {
        activeQueues = {};

        var fractions:Array = FactionManager.getAllFactions();

        for(var i:Number = 0; i < fractions.length; i++) {
            activeQueues[fractions[i]] = new BulletQueue();
        }

        activeQueues["all"] = new BulletQueue(); // 友伤队列

        return true;
    }

    public static function add(bullet:Object):Void {
        activeQueues[bullet.友军伤害 ?  "all" : 
            FactionManager.getFactionFromUnit(_root.gameworld[bullet.发射者名])
        ].add(bullet);
    }

    /**
     * 透明子弹专用的预检查方法
     * 透明子弹总是进入执行段，无需额外检查
     * 
     * @param bullet 透明子弹对象
     * @return Void
     */
    public static function preCheckTransparent(bullet):Void {
        var areaAABB:AABBCollider = bullet.aabbCollider;
        var detectionArea:MovieClip = bullet.子弹区域area;

        if (detectionArea) {
            areaAABB.updateFromBullet(bullet, detectionArea);
        } else {
            areaAABB.updateFromTransparentBullet(bullet);
        }
        // 透明子弹直接进入执行段
        BulletQueueProcessor.add(bullet);
    }
    
    /**
     * 非透明子弹专用的优化预检查工厂
     * 返回根据 area 属性决定是否进入执行段的特化函数
     * 
     * @param bullet 非透明子弹对象
     * @return Function 特化的帧处理函数
     */
    public static function createNormalPreCheck(bullet:MovieClip):Function {
        // 非透明子弹：根据 area 决定
        return function():Boolean {
            var bullet:MovieClip = this;
            var detectionArea:MovieClip = bullet.area;
            // 纯运动弹：无区域的非透明子弹
            if (!detectionArea) {
                bullet.updateMovement(bullet); 
                /*
                _root.服务器.发布服务器消息(
                    "BulletQueueProcessor: pure motion bullet skipped: " +
                    bullet._name +
                    " at (" + bullet._x + "," + bullet._y + ")" +
                    bullet._currentFrame + " " + detectionArea + " " + bullet.aabbCollider
                );
                */
                return false;
            }

            var areaAABB:AABBCollider = bullet.aabbCollider;
            areaAABB.updateFromBullet(bullet, detectionArea);
            // 有区域的非透明子弹：进入执行段
            BulletQueueProcessor.add(bullet);
            return true;
        };
    }

    public static function processQueue():Void {
        // 使用优化的 processAndClear 方法，内联展开减少函数调用开销
        for (var key:String in activeQueues) {
            var q:BulletQueue = activeQueues[key];
            q.processAndClear(executeLogic);
        }
    }

    /**
     * 执行子弹的主要逻辑（碰撞检测、伤害计算等）
     * @param bullet 子弹实例
     */
    public static function executeLogic(bullet:MovieClip):Void {
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"

        // 复用第一段的可选缓存；若无则即时计算
        var flags:Number = bullet.flags;

        var areaAABB:AABBCollider = bullet.aabbCollider;
        var detectionArea:MovieClip = bullet.子弹区域area || bullet.area;

        var rot:Number = bullet._rotation;
        var isPointSet:Boolean = ((flags & FLAG_CHAIN) != 0) && (rot != 0 && rot != 180);
        var bulletZOffset:Number = bullet.Z轴坐标;
        var bulletZRange:Number  = bullet.Z轴攻击范围;

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

        var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;
        
        // 预计算标志位检查结果，避免循环中重复计算
        var isMeleeExplosive:Boolean = (flags & MELEE_EXPLOSIVE_MASK) === 0;
        var isMelee:Boolean = (flags & FLAG_MELEE) != 0;
        var isPierce:Boolean = (flags & FLAG_PIERCE) != 0;

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
                if (hitTarget.hp <= 0) {
                    dispatcher.publish(isMeleeExplosive ? "kill" : "death", hitTarget);
                    shooter.dispatcher.publish("enemyKilled", hitTarget, bullet);
                }

                damageResult.triggerDisplay(hitTarget._x, hitTarget._y);

                // 近战硬直 / 非穿刺消失
                if (isMelee && !bullet.不硬直) {
                    shooter.硬直(shooter.man, _root.钝感硬直时间);
                } else if (!isPierce) {
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