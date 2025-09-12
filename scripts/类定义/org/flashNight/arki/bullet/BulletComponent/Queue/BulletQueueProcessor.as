// ============================================================================
// 子弹队列处理器（轻量版，环形池 ctx 复用版）
// ----------------------------------------------------------------------------
// 功能：协调子弹的有序处理，在帧尾触发排序和执行
// 变更：
// 1) 将循环内“命中后的大段业务”提取为静态函数 handleHitCtx(ctx)
// 2) ctx 采用微型环形池（0分配，天然抗浅层可重入/嵌套回调）
// 3) 统一终止控制保持：仅设置 killFlags，末尾单出口收尾
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

    // =========================
    // 统一终止控制位（类级静态）
    // =========================
    private static var KF_REASON_UNIT_HIT:Number     = 1 << 0;
    private static var KF_REASON_PIERCE_LIMIT:Number = 1 << 1;

    private static var KF_MODE_VANISH:Number         = 1 << 8;
    private static var KF_MODE_REMOVE:Number         = 1 << 9;

    // =========================
    // 环形池：上下文对象（零分配）
    // =========================
    private static var _ctxPool:Array  = [ {}, {}, {}, {} ]; // 4个足够覆盖浅层可重入
    private static var _ctxMask:Number = 3; // mod 4
    private static var _ctxTop:Number  = 0;

    private static function borrowCtx():Object {
        var i:Number = _ctxTop;
        _ctxTop = (i + 1) & _ctxMask;
        var ctx:Object = _ctxPool[i];

        // 预设字段，避免形状抖动（不要在运行时增删键）
        ctx.bullet = null;
        ctx.shooter = null;
        ctx.target = null;
        ctx.collisionResult = null;
        ctx.overlapRatio = 0;
        ctx.isNormalBullet = false;
        ctx.isMelee = false;
        ctx.isPierce = false;

        return ctx;
    }

    /**
     * 初始化处理器
     */
    public static function initialize():Boolean {
        activeQueues = {};

        var fractions:Array = FactionManager.getAllFactions();
        for (var i:Number = 0; i < fractions.length; i++) {
            activeQueues[fractions[i]] = new BulletQueue();
        }
        activeQueues["all"] = new BulletQueue(); // 友伤队列

        return true;
    }

    public static function add(bullet:Object):Void {
        activeQueues[
            bullet.友军伤害 ? "all" :
            FactionManager.getFactionFromUnit(_root.gameworld[bullet.发射者名])
        ].add(bullet);
    }

    /**
     * 透明子弹专用的预检查方法
     * 透明子弹总是进入执行段，无需额外检查
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
     */
    public static function createNormalPreCheck(bullet:MovieClip):Function {
        // 非透明子弹：根据 area 决定
        return function():Boolean {
            var bullet:MovieClip = this;
            var detectionArea:MovieClip = bullet.area;
            // 纯运动弹：无区域的非透明子弹
            if (!detectionArea) {
                bullet.updateMovement(bullet);
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
     * 单出口收尾 + 位标志终止控制
     */
    public static function executeLogic(bullet:MovieClip):Void {
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"

        // ------- 局部快取（AS2 性能友好）-------
        var flags:Number = bullet.flags;

        var areaAABB:AABBCollider = bullet.aabbCollider;
        var detectionArea:MovieClip = bullet.子弹区域area || bullet.area;

        var rot:Number = bullet._rotation;
        var isPointSet:Boolean = ((flags & FLAG_CHAIN) != 0) && (rot != 0 && rot != 180);

        var bulletZOffset:Number = bullet.Z轴坐标;
        var bulletZRange:Number  = bullet.Z轴攻击范围;

        // 统一终止控制（位标志 & 单出口）
        var killFlags:Number = 0;

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

        // 循环局部
        var len:Number = unitMap.length;
        var i:Number;
        var hitTarget:MovieClip;
        var zOffset:Number;
        var unitArea:AABBCollider;
        var collisionResult:CollisionResult;
        var overlapRatio:Number;

        var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;

        // 预计算标志位检查结果，避免循环中重复计算
        var isNormalBullet:Boolean = (flags & MELEE_EXPLOSIVE_MASK) == 0;  // 非近战非爆炸的普通子弹
        var isMelee:Boolean        = (flags & FLAG_MELEE) != 0;
        var isPierce:Boolean       = (flags & FLAG_PIERCE) != 0;

        // ----------- 命中循环 -----------
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
                    
                    // 如果更精确的多边形检测都没有碰撞，则跳过这个目标
                    if (!collisionResult.isColliding) {
                        continue;
                    }
                }

                if (_root.调试模式) {
                    AABBRenderer.renderAABB(areaAABB, zOffset, "thick");
                    AABBRenderer.renderAABB(unitArea, zOffset, "filled");
                }

                overlapRatio  = collisionResult.overlapRatio;

                // ---------- 命中后的业务处理（环形池 ctx 复用） ----------
                var ctx:Object = borrowCtx();
                ctx.bullet = bullet;
                ctx.shooter = shooter;
                ctx.target  = hitTarget;
                ctx.collisionResult = collisionResult;
                ctx.overlapRatio = overlapRatio;
                ctx.isNormalBullet = isNormalBullet;
                ctx.isMelee  = isMelee;
                ctx.isPierce = isPierce;

                killFlags |= handleHitCtx(ctx);
            }

            // 穿刺上限：设置终止标志并结束循环
            if (bullet.pierceLimit && bullet.pierceLimit < bullet.hitCount) {
                killFlags |= KF_REASON_PIERCE_LIMIT | KF_MODE_REMOVE;
                break;
            }
        }

        // 命中后效果（一次性）
        if (bullet.hitCount > 0 && bullet.shouldGeneratePostHitEffect) {
            EffectSystem.Effect(bullet.击中后子弹的效果, bullet._x, bullet._y, shooter._xscale);
        }

        // 与原实现一致：执行段末尾做一次位移更新
        bullet.updateMovement(bullet);

        // ---------------- 单出口收尾 ----------------
        if (killFlags != 0 || bullet.shouldDestroy(bullet)) {
            // 回收碰撞体
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
                if ((killFlags & KF_MODE_VANISH) != 0) {
                    bullet.gotoAndPlay("消失");
                } else {
                    bullet.removeMovieClip();
                }
            }
            return;
        }
    }

    // =========================================================================
    // 命中后处理：只做业务与事件分发，返回需要并入的 killFlags 增量
    // 注意：不做收尾/销毁/碰撞器回收，不改写 shouldDestroy
    // =========================================================================
    private static function handleHitCtx(ctx:Object):Number {
        var bullet:MovieClip  = ctx.bullet;
        var shooter:MovieClip = ctx.shooter;
        var target:MovieClip  = ctx.target;
        var overlapRatio:Number = ctx.overlapRatio;

        // --- 命中计数与上下文填充（保持与原实现一致） ---
        bullet.hitCount++;
        bullet.附加层伤害计算 = 0;
        bullet.命中对象 = target;

        // --- 闪避/命中状态 ---
        var dodgeState:String = (bullet.伤害类型 == "真伤") ? "未躲闪" :
            DodgeHandler.calculateDodgeState(
                target,
                DodgeHandler.calcDodgeResult(shooter, target, bullet.命中率),
                bullet
            );

        if (bullet.击中时触发函数) bullet.击中时触发函数();

        // --- 计算伤害 ---
        var damageResult:DamageResult = DamageCalculator.calculateDamage(
            bullet, shooter, target, overlapRatio, dodgeState
        );

        // --- 事件分发 ---
        var dispatcher:EventDispatcher = target.dispatcher;
        dispatcher.publish("hit", target, shooter, bullet, ctx.collisionResult, damageResult);

        if (target.hp <= 0) {
            dispatcher.publish(ctx.isNormalBullet ? "kill" : "death", target);
            shooter.dispatcher.publish("enemyKilled", target, bullet);
        }

        // --- 表现触发 ---
        damageResult.triggerDisplay(target._x, target._y);

        // --- 终止意图：近战硬直 或 非穿刺 命中即“消失” ---
        var deltaFlags:Number = 0;
        if (!ctx.isPierce) {
            if (ctx.isMelee && !bullet.不硬直) {
                shooter.硬直(shooter.man, _root.钝感硬直时间);
            }
            deltaFlags |= (KF_REASON_UNIT_HIT | KF_MODE_VANISH);
        }

        return deltaFlags;
    }
}
