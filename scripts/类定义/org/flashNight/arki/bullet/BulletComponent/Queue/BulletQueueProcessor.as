// ============================================================================
// 子弹队列处理器（轻量版，静态上下文复用版）
// ----------------------------------------------------------------------------
// 功能：协调子弹的有序处理，在帧尾触发排序和执行
// 变更：
// 1) 将循环内"命中后的大段业务"提取为静态函数 handleHitCtx(ctx)
// 2) ctx 采用静态上下文对象（零分配，基于帧末同步处理特性）
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
    public static var fakeUnits:Object; // 按阵营分类用于查询缓存的假单位

    // =========================
    // 统一终止控制位（类级静态）
    // =========================
    private static var KF_REASON_UNIT_HIT:Number     = 1 << 0;
    private static var KF_REASON_PIERCE_LIMIT:Number = 1 << 1;

    private static var KF_MODE_VANISH:Number         = 1 << 8;
    private static var KF_MODE_REMOVE:Number         = 1 << 9;

    // 预计算的组合常量
    private static var KF_PIERCE_LIMIT_REMOVE:Number = (1 << 1) | (1 << 9);

    // =========================
    // 静态上下文对象（零分配，同步处理无需环形池）
    // =========================
    private static var _hitContext:HitContext = new HitContext();

    /**
     * 初始化处理器
     */
    public static function initialize():Boolean {
        activeQueues = {};
        fakeUnits = {}; // 初始化 fakeUnits 对象

        var fractions:Array = FactionManager.getAllFactions();
        for (var i:Number = 0; i < fractions.length; i++) {
            var key:String = fractions[i];
            activeQueues[key] = new BulletQueue();
            fakeUnits[key] = FactionManager.createFactionUnit(key, "queue");
        }
        activeQueues["all"] = new BulletQueue(); // 友伤队列
        fakeUnits["all"] = FactionManager.createFactionUnit("all", "queue");

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
            var detectionArea:MovieClip = this.area;
            // 纯运动弹：无区域的非透明子弹
            if (!detectionArea) {
                this.updateMovement(this);
                return false;
            }

            var areaAABB:AABBCollider = this.aabbCollider;
            areaAABB.updateFromBullet(this, detectionArea);
            // 有区域的非透明子弹：进入执行段
            BulletQueueProcessor.add(this);
            return true;
        };
    }

    public static function processQueue():Void {
        // 内联展开 executeLogic 以消除高频函数调用开销
        // sortByLeftBoundary 和 clear 保留函数调用以维持可维护性（仅调用4次）
        #include "../macros/FLAG_CHAIN.as"
        #include "../macros/FLAG_MELEE.as"
        #include "../macros/FLAG_PIERCE.as"
        #include "../macros/FLAG_EXPLOSIVE.as"
        
        // 批处理前的通用初始化
        var gameWorld:MovieClip = _root.gameworld;
        var debugMode:Boolean = _root.调试模式;
        var MELEE_EXPLOSIVE_MASK:Number = FLAG_MELEE | FLAG_EXPLOSIVE;
        var PIERCE_LIMIT_REMOVE:Number = KF_PIERCE_LIMIT_REMOVE;
        var MODE_VANISH:Number = KF_MODE_VANISH;
        // HitContext 静态常量缓存（避免循环内类属性查找）
        var HC_FLAG_NORMAL_KILL:Number = HitContext.FLAG_NORMAL_KILL;
        var HC_FLAG_SHOULD_STUN:Number = HitContext.FLAG_SHOULD_STUN;
        var HC_FLAG_IS_PIERCE:Number = HitContext.FLAG_IS_PIERCE;
        
        // ================================================================
        // 统一变量声明区域（性能热点优化：避免循环内重复var声明开销）
        // ================================================================

        // ---- 队列上下文管理变量 ----
        var key:String;                     // 当前处理的阵营键名（如"player", "enemy", "all"等）
        var q:BulletQueue;                  // 当前阵营的子弹队列实例
        var n:Number;                       // 队列中子弹数量（用于空队列早退判断）

        // ---- 已排序子弹数据 ----
        var sortedArr:Array;                // 按左边界排序后的子弹数组引用
        var sortedLength:Number;            // 排序数组长度快照（避免重复length查询）

        // ---- 目标缓存系统 ----
        var cache:SortedUnitCache;          // 排序后的单位缓存对象
        var fakeUnit:Object;                // 阵营代理单位（用于查询缓存键）

        // ---- 双指针扫描线算法缓冲区 ----
        var unitMap:Array;                  // 目标单位映射数组
        var unitRightKeys:Array;            // 目标单位右边界键值数组（用于扫描优化）
        var unitLeftKeys:Array;             // 目标单位左边界键值数组（用于碰撞窗口计算）
        var bulletLeftKeys:Array;           // 子弹左边界键值数组
        var bulletRightKeys:Array;          // 子弹右边界键值数组
        var sweepIndex:Number;              // 扫描线当前索引位置

        // ---- 单发子弹循环状态 ----
        var idx:Number;                     // 子弹数组遍历索引
        var bullet:MovieClip;               // 当前处理的子弹实例
        var flags:Number;                   // 子弹类型标志位（联弹、近战、穿透等）
        var areaAABB:AABBCollider;          // 子弹的AABB碰撞检测器
        var isPointSet:Boolean;             // 是否需要精确多边形碰撞检测（旋转联弹）
        var rot:Number;                     // 子弹旋转角度（仅联弹需要）
        var bulletZOffset:Number;           // 子弹Z轴坐标
        var bulletZRange:Number;            // 子弹Z轴攻击范围
        var killFlags:Number;               // 子弹终止标志位（命中、穿透上限等）
        var shooter:MovieClip;              // 子弹发射者实例
        var queryLeft:Number;               // 子弹左边界查询坐标
        var startIndex:Number;              // 目标扫描起始索引
        var len:Number;                     // 目标数组长度（循环边界）
        var ii:Number;                      // 内层目标遍历索引
        var hitTarget:MovieClip;            // 当前命中的目标单位
        var zOffset:Number;                 // Z轴偏移量（子弹与目标的高度差）
        var unitArea:AABBCollider;          // 目标单位的AABB碰撞检测器
        var bulletRight:Number;             // 子弹右边界（用于早期截断优化）

        // ---- 碰撞检测临时变量 ----
        var collisionResult:CollisionResult; // 碰撞检测结果对象
        // overlapRatio 从 collisionResult.overlapRatio 直接获取，无需单独存储
        var polygonCollider:ICollider;      // 多边形碰撞检测器（精确检测用）

        // ---- 子弹类型预计算标志 ----
        var ctxFlags:Number;                // HitContext的位标志组合
        var isUpdatePolygon:Boolean;        // 多边形碰撞器是否已更新（避免重复更新）
        
        // ================================================================
        // 主处理循环：按阵营遍历所有活动队列
        // ================================================================
        for (key in activeQueues) {
            q = activeQueues[key];

            // ---- 空队列优化：早期退出避免无效计算 ----
            n = q.getCount();
            if (n == 0) continue;

            // ---- 子弹排序：按左边界排序以优化扫描线算法 ----
            // _root.服务器.发布服务器消息(key + " : " + q.toString()); // 调试输出当前队列状态

            q.sortByLeftBoundary();

            // ---- 获取排序后数据：避免重复方法调用的性能开销 ----
            sortedArr = q.getBulletsReference();        // 排序后子弹数组的直接引用
            sortedLength = sortedArr.length;            // 长度快照，避免.length属性重复查询

            // ---- 阵营单位获取：用于目标缓存查询 ----
            fakeUnit = fakeUnits[key];

            // ---- 目标缓存获取：根据阵营类型选择合适的缓存策略 ----
            if(key == "all") {
                // 友伤模式：获取所有单位（包括友军）
                cache = TargetCacheManager.acquireAllCache(fakeUnit, 1);
            } else {
                // 敌对模式：仅获取敌方单位
                cache = TargetCacheManager.acquireEnemyCache(fakeUnit, 1);
            }

            // ---- 双指针扫描线数据准备：核心优化算法的数据基础 ----
            unitMap = cache.data;                       // 目标单位实例数组
            unitRightKeys = cache.rightValues;          // 目标右边界数组（用于扫描线推进）
            unitLeftKeys = cache.leftValues;            // 目标左边界数组（用于碰撞窗口判断）
            len = unitMap.length;                       // 目标遍历边界（整个队列处理期间不变）
            bulletLeftKeys = q.getLeftKeysRef();        // 子弹左边界数组（查询起点）
            bulletRightKeys = q.getRightKeysRef();      // 子弹右边界数组（截断终点）
            sweepIndex = 0;                             // 扫描线索引重置

            // ================================================================
            // 子弹逐发处理循环：内联executeLogic以消除函数调用开销
            // 核心优化：完全内联，无函数调用，最小化栈帧切换成本
            // ================================================================
            for (idx = 0; idx < sortedLength; idx++) {
                bullet = sortedArr[idx];

                // ---- 子弹属性缓存：减少对象属性查找的哈希开销 ----
                flags = bullet.flags;                   // 子弹类型标志位（一次查询，多处使用）
                areaAABB = bullet.aabbCollider;         // AABB碰撞检测器缓存

                // ---- 精确碰撞检测需求判断：延迟获取旋转角度避免不必要的getter调用 ----
                isPointSet = (flags & FLAG_CHAIN) != 0; // 先判断是否为联弹
                if (isPointSet) {
                    rot = bullet._rotation;              // 仅联弹需要获取旋转角度（避免getter开销）
                    isPointSet = rot != 0 && rot != 180; // 只有旋转的联弹才需要多边形检测
                }

                // ---- Z轴检测参数缓存：高频使用的坐标数据 ----
                bulletZOffset = bullet.Z轴坐标;          // 子弹Z轴坐标
                bulletZRange = bullet.Z轴攻击范围;       // Z轴攻击范围

                // ---- 子弹终止控制初始化：统一的生命周期管理 ----
                killFlags = 0;                         // 重置终止标志位（单出口设计）

                // ---- 调试渲染：开发阶段的可视化辅助 ----
                if (debugMode) {
                    AABBRenderer.renderAABB(areaAABB, 0, "line", bulletZRange);
                }

                // ---- 发射者获取：用于友伤判断和效果触发 ----
                shooter = gameWorld[bullet.发射者名];

                // ---- 扫描线算法：双指针优化的碰撞检测窗口计算 ----
                queryLeft = bulletLeftKeys[idx];        // 当前子弹左边界
                // 推进扫描线：跳过所有右边界小于子弹左边界的目标
                // 循环展开优化：每次跳4个，减少循环判断开销
                while (sweepIndex + 3 < len && unitRightKeys[sweepIndex + 3] < queryLeft) {
                    sweepIndex += 4;
                    // _root.服务器.发布服务器消息("快速推进4步至索引 " + sweepIndex); // 调试输出
                }
                // 处理剩余的0-3个元素
                while (sweepIndex < len && unitRightKeys[sweepIndex] < queryLeft) {
                    ++sweepIndex;
                }
                startIndex = sweepIndex;                // 记录有效检测的起始索引
                bulletRight = bulletRightKeys[idx];     // 提前获取子弹右边界

                // ---- 空窗口快判：O(1)时间复杂度，避免无效循环开销 ----
                // 如果没有任何目标在子弹的横向范围内，直接跳过
                if (startIndex >= len || bulletRight < unitLeftKeys[startIndex]) {
                    bullet.updateMovement(bullet);
                    continue;  // 直接进入下一发子弹的处理
                }

                // ---- 击中后效果标志：确保命中时能正确触发效果 ----
                bullet.shouldGeneratePostHitEffect = true;

                // ---- 子弹类型预计算：避免内层循环重复位运算 ----
                // 直接计算context flags，避免中间布尔变量
                ctxFlags = 0;
                if ((flags & MELEE_EXPLOSIVE_MASK) == 0) ctxFlags |= HC_FLAG_NORMAL_KILL;  // 普通击杀
                if ((flags & FLAG_MELEE) != 0 && !bullet.不硬直) ctxFlags |= HC_FLAG_SHOULD_STUN;  // 硬直
                if ((flags & FLAG_PIERCE) != 0) ctxFlags |= HC_FLAG_IS_PIERCE;  // 穿透

                // ---- 多边形更新控制：避免同一子弹重复更新碰撞器 ----
                isUpdatePolygon = false;

                // ----------- 命中循环（带右边界截断） -----------
                for (ii = startIndex; ii < len && unitLeftKeys[ii] <= bulletRight; ++ii) {
                    hitTarget = unitMap[ii];  // 只读取目标，延迟写入

                    // Z 轴粗判（避免Math.abs函数调用开销）
                    zOffset = bulletZOffset - hitTarget.Z轴坐标;
                    if (zOffset >= bulletZRange || zOffset <= -bulletZRange) continue;

                    if (hitTarget.hp > 0 && hitTarget.防止无限飞 != true) {
                        unitArea = hitTarget.aabbCollider;

                        // AABB 检测（无序早退交由右边界截断处理）
                        collisionResult = areaAABB.checkCollision(unitArea, zOffset);
                        if (!collisionResult.isColliding) {
                            continue;
                        }

                        // 仅在需要时才更新多边形碰撞体
                        if (isPointSet) {
                            if(!isUpdatePolygon) {
                                polygonCollider = bullet.polygonCollider;
                                if(!polygonCollider) {
                                    // 对于导弹联弹，可能会因为空中旋转而没有预创建碰撞体
                                    // 这里进行懒创建并更新
                                    polygonCollider = bullet.polygonCollider = ColliderFactoryRegistry.getFactory(ColliderFactoryRegistry.PolygonFactory).createFromBullet(bullet, bullet.子弹区域area || bullet.area);
                                }
                                // 更新碰撞器（创建时已包含更新，但既有碰撞器需要更新）
                                polygonCollider.updateFromBullet(bullet, bullet.子弹区域area || bullet.area);
                                isUpdatePolygon = true;
                            } else {
                                // 后续命中直接使用已更新的碰撞器
                                polygonCollider = bullet.polygonCollider;
                            }

                            collisionResult = polygonCollider.checkCollision(unitArea, zOffset);

                            // 如果更精确的多边形检测都没有碰撞，则跳过这个目标
                            if (!collisionResult.isColliding) {
                                continue;
                            }
                        }

                        // 确认命中后才写入hitTarget，避免无效的哈希表操作
                        bullet.hitTarget = hitTarget;

                        if (debugMode) {
                            AABBRenderer.renderAABB(areaAABB, zOffset, "thick");
                            AABBRenderer.renderAABB(unitArea, zOffset, "filled");
                        }

                        // ---------- 命中后的业务处理（静态 ctx 复用） ----------
                        killFlags |= handleHitCtx(_hitContext.fill(
                            bullet,
                            shooter,
                            hitTarget,
                            collisionResult,
                            ctxFlags)  // 使用预计算的flags
                        );
                    }
                    
                    // 穿刺上限：设置终止标志并结束循环
                    if (bullet.pierceLimit && bullet.pierceLimit < bullet.hitCount) {
                        killFlags |= PIERCE_LIMIT_REMOVE;
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
                    if (bullet.polygonCollider) {
                        bullet.polygonCollider.getFactory().releaseCollider(bullet.polygonCollider);
                    }
                    
                    if (bullet.击中地图) {
                        bullet.霰弹值 = 1;
                        EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
                        if (bullet.击中时触发函数) bullet.击中时触发函数();
                        bullet.gotoAndPlay("消失");
                    } else {
                        if ((killFlags & MODE_VANISH) != 0) {
                            bullet.gotoAndPlay("消失");
                        } else {
                            bullet.removeMovieClip();
                        }
                    }
                }
            }
            // === 内联 executeLogic 遍历结束 ===
            
            // 清空队列（仅调用一次，保留函数调用）
            q.clear();
        }
    }


    // =========================================================================
    // 命中后处理：只做业务与事件分发，返回需要并入的 killFlags 增量
    // 注意：不做收尾/销毁/碰撞器回收，不改写 shouldDestroy
    // =========================================================================
    private static function handleHitCtx(ctx:HitContext):Number {
        var bullet:MovieClip  = ctx.bullet;
        var shooter:MovieClip = ctx.shooter;
        var target:MovieClip  = ctx.target;
        var collisionResult:CollisionResult = ctx.collisionResult;
        var ctxFlags:Number = ctx.flags;  // 缓存flags，避免重复属性访问

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
            bullet, shooter, target, collisionResult.overlapRatio, dodgeState
        );

        // --- 事件分发 ---
        var dispatcher:EventDispatcher = target.dispatcher;
        dispatcher.publish("hit", target, shooter, bullet, collisionResult, damageResult);

        if (target.hp <= 0) {
            // 直接进行位运算判断事件名
            dispatcher.publish((ctxFlags & HitContext.FLAG_NORMAL_KILL) != 0 ? "kill" : "death", target);
            shooter.dispatcher.publish("enemyKilled", target, bullet);
        }

        // --- 表现触发 ---
        damageResult.triggerDisplay(target._x, target._y);

        // --- 终止意图：近战硬直 或 非穿刺 命中即"消失" ---
        var deltaFlags:Number = 0;
        if ((ctxFlags & HitContext.FLAG_IS_PIERCE) == 0) {  // 非穿透
            if ((ctxFlags & HitContext.FLAG_SHOULD_STUN) != 0) {  // 应该硬直
                shooter.硬直(shooter.man, _root.钝感硬直时间);
            }
            deltaFlags |= (KF_REASON_UNIT_HIT | KF_MODE_VANISH);
        }

        return deltaFlags;
    }
}
