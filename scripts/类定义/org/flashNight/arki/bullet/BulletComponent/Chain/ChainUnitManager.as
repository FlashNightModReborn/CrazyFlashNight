import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;
// ⚠ 同包类也必须显式 import：Flash CS6 常驻会话对"同包隐式解析"使用陈旧的包索引，
// 会对会话期间新建的同包类报"无法加载类或接口"；显式 import 走新鲜扫描（实测 2026-06-13）
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainGroup;
import org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitData;

/**
 * ChainUnitManager —— 联弹单元体共享层 / 对象池 / 统一帧更新管理器（P2 池化改造核心）
 *
 * 背景：旧实现中联弹单元体作为子弹 MC 的子剪辑频繁 attachMovie/removeMovieClip，
 * 且每发联弹挂一个 onEnterFrame 闭包。本类将全部视觉单元体收敛到
 * gameworld.子弹区域.联弹单元体层 下按 linkage 池化复用，并以单一 onEnterFrame 统一驱动各组更新。
 *
 * 架构契约（与 战斗系统_fs_联弹管理.as 协作）：
 * • 模拟留在子弹本地坐标系：组状态（单元体 x/y/rot）由帧脚本按旧公式逐式等价演算；
 *   本类只负责层/池/组注册/tick 分发，渲染映射由帧脚本的 渲染组 完成
 * • area 子剪辑仍是碰撞代理（包围盒由本地极值更新），碰撞管线零改动
 * • teardown 双保险：消失路径显式 removeGroupByBullet + tick 检测 area/bullet 失效兜底
 * • gameworld 重建：层/池随世界销毁，getLayer 懒建新层并重置组注册表
 */
class org.flashNight.arki.bullet.BulletComponent.Chain.ChainUnitManager {

    /** 共享层实例名（位于 gameworld.子弹区域 下） */
    private static var LAYER_NAME:String = "联弹单元体层";

    /** 共享层深度：远高于子弹 count 深度段，且处于 removeMovieClip 可移除区间内 */
    private static var LAYER_DEPTH:Number = 1048000;

    /** 活动联弹组注册表 */
    private static var groups:Array = [];

    /** 单元体实例命名自增计数 */
    private static var unitCounter:Number = 0;

    /** SceneChanged 订阅标记（仅订阅一次） */
    private static var sceneHooked:Boolean = false;

    /**
     * 单元体数据对象自由表（{mc,x,y,rot,sin,cos,…} 包装对象池化复用）。
     * 高射速武器每秒生成数百个单元体，逐次 {} 字面量分配（~350ns + GC 压力）
     * 在稳态下完全可避免；池上限即历史同屏单元体峰值，量级与 MC 池一致。
     * 纯对象无场景引用（mc 字段在回收时置 null），可安全跨 gameworld 复用。
     */
    private static var dataPool:Array = [];

    /** 无效对象联弹诊断限流：每个场景最多记录 8 次异常。 */
    private static var invalidChainLogCount:Number = 0;

    /**
     * 获取（懒建）共享单元体层。
     * gameworld 重建后旧层随世界销毁，下次调用自动重建新层并重置组注册表。
     * @return MovieClip 共享层；子弹区域不存在时返回 null
     */
    public static function getLayer():MovieClip {
        var zone:MovieClip = _root.gameworld.子弹区域;
        if (zone == undefined) return null;
        var layer:MovieClip = zone[LAYER_NAME];
        if (layer == undefined) {
            // 场景切换时主动清空组注册表，避免静态表跨场景持有旧 gameworld/旧池引用
            if (!sceneHooked) {
                sceneHooked = true;
                EventBus.getInstance().subscribe("SceneChanged", function():Void {
                    ChainUnitManager.resetAll();
                }, ChainUnitManager);
            }
            layer = zone.createEmptyMovieClip(LAYER_NAME, LAYER_DEPTH);
            layer.可用单元体池 = {};
            // 旧世界的组与单元体 MC 已随世界销毁，重置注册表（数据对象回收入池）
            resetAll();
            // 统一帧驱动（类方法内创建的闭包，不受帧脚本 activation object 回收影响）
            layer.onEnterFrame = function():Void {
                ChainUnitManager.tick();
            };
        }
        return layer;
    }

    /**
     * 清空组注册表（场景切换/世界销毁时调用）。
     * 旧层、池与单元体 MC 随旧 gameworld 一并销毁（仅断引用，不入 MC 池）；
     * 活动组中的 ChainUnitData 数据对象为纯对象、无场景绑定，必须回收进静态
     * dataPool 兑现"跨 gameworld 复用"契约——否则每次带活动联弹过图都白白
     * 丢弃并在新场景重新分配同量数据对象（复审发现）。
     * 组标记 __removed，防任何残存引用经 removeGroup 二次回池污染自由表。
     */
    public static function resetAll():Void {
        org.flashNight.arki.render.ChainVisualBridge.resetScene();
        invalidChainLogCount = 0;
        var gs:Array = groups;
        var gn:Number = gs.length;
        var pool:Array = dataPool;
        var pn:Number = pool.length;
        var g:ChainGroup;
        var list:Array;
        var d:ChainUnitData;
        var n:Number;
        for (var i:Number = 0; i < gn; i++) {
            g = gs[i];
            g.__removed = true;
            list = g.单元体列表;
            n = list.length;
            for (var u:Number = 0; u < n; u++) {
                d = list[u];
                d.mc = null;
                pool[pn++] = d;
            }
            list.length = 0;
        }
        gs.length = 0;   // 截断（~69ns）而非新建数组（~550ns + GC，H21）
    }

    /**
     * 从池中获取指定子弹种类的单元体（池空则创建新实例）
     * @param 子弹种类 联弹单元体后缀名（linkage = "单元体-" + 子弹种类）
     * @return MovieClip 单元体；共享层不可用时返回 null
     */
    public static function acquireUnit(子弹种类:String):MovieClip {
        var layer:MovieClip = getLayer();
        if (layer == null) return null;
        var linkage:String = "单元体-" + 子弹种类;
        var pool:Array = layer.可用单元体池[linkage];
        var unit:MovieClip;
        var n:Number;
        // 手动 length 出栈（~104ns）替代 pop()（~185ns，且 pop 返回 Object 需显式 cast）
        if (pool != undefined && (n = pool.length) > 0) {
            unit = pool[--n];
            pool.length = n;
            // 复用重置契约：与全新 attachMovie 等价——从第 1 帧开始播放
            // （多帧单元体如 单元体-铁枪能量子弹，不得从入池时的任意帧续播）
            unit.gotoAndPlay(1);
        } else {
            unit = layer.attachMovie(linkage, "u" + (unitCounter++), layer.getNextHighestDepth());
            unit.__池键 = linkage;
        }
        unit._visible = true;
        return unit;
    }

    /**
     * 获取单元体数据对象（自由表命中则复用，未命中新建实例）。
     * 调用方（联弹系统.生成单元体）负责复位全部业务字段——
     * 池化对象会携带前世状态，渲染影子字段（v/wr）必须强制重置。
     */
    public static function acquireUnitData():ChainUnitData {
        var p:Array = dataPool;
        var n:Number = p.length;
        if (n > 0) {
            var u:ChainUnitData = p[--n];
            p.length = n;
            return u;
        }
        return new ChainUnitData();
    }

    /**
     * 释放单元体数据对象回自由表（mc 引用置 null，不持有已死 MC）。
     * 索引直写（~135ns）替代 push()（~273ns）。
     */
    public static function releaseUnitData(u:ChainUnitData):Void {
        u.mc = null;
        u.nativeLive = false;
        u.aggregatePrev = null;
        u.aggregateNext = null;
        var p:Array = dataPool;
        p[p.length] = u;
    }

    /**
     * 释放单元体回池（隐藏 + 入自由表，不销毁实例）
     */
    public static function releaseUnit(unit:MovieClip):Void {
        var key:String = unit.__池键;   // 属性预读（H01：下文使用 ≥2 次）
        if (unit == undefined || key == undefined) return;
        // 入池重置契约：停住时间轴（隐藏的高水位实例不再逐帧消耗），复用时 gotoAndPlay(1) 重启
        unit.stop();
        unit._visible = false;
        var pools:Object = unit._parent.可用单元体池;
        if (pools == undefined) return; // 层已随世界销毁
        var pool:Array = pools[key];
        if (pool == undefined) {
            pool = [];
            pools[key] = pool;
        }
        pool[pool.length] = unit;
    }

    /**
     * 注册联弹组（ChainGroup 实例；索引直写替代 push）
     */
    public static function registerGroup(group:ChainGroup):Void {
        getLayer(); // 确保层与统一 tick 存在
        var gs:Array = groups;
        gs[gs.length] = group;
    }

    /**
     * 按子弹 MC 查找组（消失路径显式回收用）
     */
    public static function findGroupByBullet(bullet):ChainGroup {
        var gs:Array = groups;
        for (var i:Number = gs.length - 1; i >= 0; i--) {
            var g:ChainGroup = gs[i];
            if (g.bullet == bullet) return g;
        }
        return null;
    }

    /**
     * 回收整组单元体并注销（swap-with-last + length 截断；MC 与数据对象分别回池）。
     * TimSort 式惯语：长度/池游标预读到局部，pool[pn++] 索引直写（StoreRegister
     * 副作用快速路径）替代逐次 push 方法调用。
     */
    public static function removeGroup(group:ChainGroup):Void {
        if (group == null || group.__removed) return;
        org.flashNight.arki.render.ChainVisualBridge.releaseGroup(group);
        group.__removed = true;
        var list:Array = group.单元体列表;
        var pool:Array = dataPool;
        var n:Number = list.length;
        var pn:Number = pool.length;
        var d:ChainUnitData;
        for (var u:Number = 0; u < n; u++) {
            d = list[u];
            releaseUnit(d.mc);
            d.mc = null;
            pool[pn++] = d;
        }
        list.length = 0;
        var gs:Array = groups;
        var gn:Number = gs.length;
        for (var i:Number = gn - 1; i >= 0; i--) {
            if (gs[i] == group) {
                var last:Number = gn - 1;
                if (i < last) gs[i] = gs[last];
                gs.length = last;
                break;
            }
        }
    }

    /** 按子弹 MC 回收组（供消失帧脚本调用，未注册时安全 no-op） */
    public static function removeGroupByBullet(bullet):Void {
        removeGroup(findGroupByBullet(bullet));
    }

    /**
     * 统一帧更新：倒序分发各组 update；失效组兜底回收。
     * 暂停时整体跳过（与旧 per-clip onEnterFrame 行为一致）。
     *
     * 对象化联弹（group.isObject，由 对象联弹初始化 标记）在此承担 MC 子弹
     * onEnterFrame 预检查的职责：
     * 边界外标记 STATE_HIT_MAP → 更新 AABB（数据路径）→ 泵入 BulletQueueProcessor。
     * processQueue 由 frameEnd 事件在帧末统一消费，与 MC 子弹的入队时序同构。
     *
     * ⚠ 分支判别用显式 isObject 标记而非 area == null：MC 壳组的 area 被直删
     * （REMOVE 消弹 / 超射程 priority-4 removeMovieClip）后是悬挂 MC 引用，
     * 其与 null 的 loose equality 在 AVM1 中无可靠语义；若误入对象分支，
     * __chainDead 恒为 undefined → 组永不注销且每帧向碰撞队列泵入死子弹。
     * 悬挂 MC 的属性访问（_parent == undefined）才是可靠的失效检测。
     */
    public static function tick():Void {
        if (_root.暂停) return;
        // === 宏展开：实例状态标志位 ===
        #include "../macros/STATE_HIT_MAP.as"
        var xmin:Number = _root.Xmin;
        var xmax:Number = _root.Xmax;
        var ymin:Number = _root.Ymin;
        var ymax:Number = _root.Ymax;
        var gs:Array = groups;   // 静态成员局部化（H01）
        var f:Function;          // 更新函数以 f(g) 形态调用：组更新函数均不依赖 this，
                                 // CallFunction(~485ns) 替代 g.update(g) 的 CallMethod(~1340ns)

        for (var i:Number = gs.length - 1; i >= 0; i--) {
            var g:ChainGroup = gs[i];
            if (g.isObject) {
                // —— 对象化联弹分支 ——
                var b = g.bullet;
                if (b.__chainDead) {
                    removeGroup(g);
                    continue;
                }
                f = g.update;
                f(g);

                // 与 MC 子弹预检查同构：越界标记击中地图（由队列单出口收尾处理）
                var x:Number = b._x;
                var y:Number = b.Z轴坐标;
                if (x < xmin || x > xmax || y < ymin || y > ymax) {
                    b.stateFlags |= STATE_HIT_MAP;
                }

                // 数据路径更新 AABB 后泵入碰撞队列
                var aabb:AABBCollider = b.aabbCollider;
                aabb.updateFromChainObject(b);
                // BulletQueue 会拒收无效左右边界；任意边界无效时对象联弹可能不再移动或回收。
                // 在同一边界将其完整销毁，避免错误发射点永久占住可见单元体。
                if (((aabb.left - aabb.left) + (aabb.right - aabb.right)
                    + (aabb.top - aabb.top) + (aabb.bottom - aabb.bottom)) != 0) {
                    if (invalidChainLogCount < 8) {
                        invalidChainLogCount++;
                        org.flashNight.neur.Server.ServerManager.getInstance().sendServerMessage(
                            "[ChainBulletInvalidAABB] frame=" + _root.帧计时器.当前帧数
                            + " type=" + b.子弹种类 + " x=" + b._x + " y=" + b._y
                            + " vx=" + b.xmov + " vy=" + b.ymov);
                    }
                    b.removeMovieClip();
                    continue;
                }
                BulletQueueProcessor.add(b);
            } else {
                // —— MC 壳联弹分支 ——
                if (g.area._parent == undefined || g.bullet._parent == undefined) {
                    removeGroup(g);
                    continue;
                }
                f = g.update;
                f(g);
            }
        }
    }

    /** 当前活动组数（调试用） */
    public static function getActiveGroupCount():Number {
        return groups.length;
    }

    /** 能力撤销时恢复仍存活的原 Flash 单元体，不重建联弹业务对象。 */

    /** 影子采样只读当前可见单元体；联弹业务更新与显示所有权不受影响。 */
    /** AS2 战斗边界用的精确懒推进成本计数；focused suite 读取，生产不分配。 */
    public static var aggregateAddOperations:Number = 0;

    /**
     * 精确重复执行 value += delta。仅在同一个 IEEE-754 binade 内跳过等步长段：
     * 两次实加先稳定 half-ULP tie 的偶数尾位；端点、下一步差量均核对。
     * 跨零/跨 binade/极小极大值执行原加法，不把逐步舍入替换成 n*delta。
     */
    public static function repeatAdd(value:Number, delta:Number, count:Number):Number {
        if (!isFinite(value) || !isFinite(delta)) return value + delta;
        var next:Number, step:Number, magnitude:Number, low:Number, high:Number;
        var skip:Number, candidate:Number, edge:Number, candidateMagnitude:Number;
        while (count > 0) {
            value += delta;
            aggregateAddOperations++;
            count--;
            if (count < 2) continue;
            next = value + delta;
            aggregateAddOperations++;
            step = next - value;
            value = next;
            count--;
            if (step == 0) return value;
            magnitude = value < 0 ? -value : value;
            if (!(magnitude > 1e-280 && magnitude < 1e280)) continue;
            low = Math.pow(2, Math.floor(Math.log(magnitude) / 0.6931471805599453));
            while (low > magnitude) low *= 0.5;
            while (!(magnitude < low * 2)) low *= 2;
            high = low * 2;
            skip = count;
            candidate = value + step * skip;
            candidateMagnitude = candidate < 0 ? -candidate : candidate;
            if (!(candidateMagnitude > low && candidateMagnitude < high && ((candidate > 0) == (value > 0)))) {
                edge = step > 0 ? (value > 0 ? high : -low) : (value > 0 ? low : -high);
                skip = Math.floor((edge - value) / step) - 2;
                if (skip > count) skip = count;
                if (!(skip > 0)) continue;
                candidate = value + step * skip;
                candidateMagnitude = candidate < 0 ? -candidate : candidate;
            }
            if (candidateMagnitude > low && candidateMagnitude < high
                && ((candidate > 0) == (value > 0))
                && (value + delta) - value == step && (candidate + delta) - candidate == step) {
                value = candidate;
                count -= skip;
            }
        }
        return value;
    }

    /** 每次实际游戏更新递增一次；暂停和 FrameBroadcaster 重发不推进。 */
    public static function beginNativeStep(group:ChainGroup, advance:Number, advanceX:Boolean):Void {
        if (!group.nativeGroupOwned) return;
        if (group.aggregate) {
            var existing:Array = group.aggregateRuns;
            var previous:Object = existing[existing.length - 1];
            if (advance < 0 || !isFinite(advance)) {
                disableAggregate(group);
            } else if (existing.length > 255
                && (previous.advance != advance || previous.advanceX != advanceX)) {
                // 历史段超限：全体物化到当前 tip 后压缩为单段新基准，
                // 聚合继续服役而非永久退出——run 每次实际切换至多物化一轮。
                var units:Array = group.单元体列表;
                var un:Number = units.length;
                for (var u:Number = 0; u < un; u++) {
                    var ud:ChainUnitData = units[u];
                    materializeUnit(group, ud);
                    ud.aggregateRun = 0;
                    ud.aggregateOffset = 0;
                }
                existing.length = 0;
                existing[0] = {advance:advance, advanceX:advanceX, count:0};
            }
        }
        group.nativeStep++;
        group.nativeAdvance = advance;
        group.nativeAdvanceX = advanceX;
        if (!group.aggregate) return;
        var runs:Array = group.aggregateRuns;
        var n:Number = runs.length;
        var run:Object = runs[n - 1];
        if (n > 0 && run.advance == advance && run.advanceX == advanceX) {
            run.count++;
        } else {
            runs[n] = {advance:advance, advanceX:advanceX, count:1};
        }
    }

    public static function initializeAggregateUnit(group:ChainGroup, unit:ChainUnitData):Void {
        var runs:Array = group.aggregateRuns;
        var n:Number = runs.length;
        unit.aggregateRun = n > 0 ? n - 1 : 0;
        unit.aggregateOffset = n > 0 ? runs[n - 1].count : 0;
    }

    /** 所有坐标读取前补齐跳过的恒速段，字段只在真实需要时写入。 */
    public static function materializeUnit(group:ChainGroup, unit:ChainUnitData):Void {
        var runs:Array = group.aggregateRuns;
        var n:Number = runs.length;
        if (n == 0) return;
        var index:Number = unit.aggregateRun;
        var offset:Number = unit.aggregateOffset;
        var run:Object;
        var count:Number;
        var x:Number = unit.x;
        var y:Number = unit.y;
        while (index < n) {
            run = runs[index];
            count = run.count - offset;
            if (count > 0) {
                y = repeatAdd(y, run.advance * unit.sin, count);
                if (run.advanceX) x = repeatAdd(x, run.advance * unit.cos, count);
            }
            index++;
            offset = 0;
        }
        unit.x = x;
        unit.y = y;
        unit.aggregateRun = n - 1;
        unit.aggregateOffset = runs[n - 1].count;
        group.aggregateVisits++;
    }

    public static function disableAggregate(group:ChainGroup):Void {
        if (!group.aggregate) return;
        var units:Array = group.单元体列表;
        for (var i:Number = 0; i < units.length; i++) materializeUnit(group, units[i]);
        group.aggregate = false;
        group.aggregateRuns.length = 0;
        group.aggregateSorted.length = 0;
        group.aggregateMin = null;
        group.aggregateMax = null;
    }

    private static function compareSin(a:ChainUnitData, b:ChainUnitData):Number {
        return a.sin - b.sin;
    }

    public static function prepareHorizontalAggregate(group:ChainGroup):Void {
        if (!group.aggregate) return;
        var list:Array = group.单元体列表;
        var sorted:Array = list.slice();
        var count:Number = sorted.length;
        var unit:ChainUnitData;
        for (var i:Number = 0; i < count; i++) list[i].aggregateIndex = i;
        sorted.sort(compareSin);
        for (i = 0; i < count; i++) {
            unit = sorted[i];
            unit.aggregatePrev = i > 0 ? sorted[i - 1] : null;
            unit.aggregateNext = i + 1 < count ? sorted[i + 1] : null;
        }
        group.aggregateMin = sorted[0];
        group.aggregateMax = sorted[count - 1];
    }

    private static function compareIndexDescending(a:ChainUnitData, b:ChainUnitData):Number {
        return b.aggregateIndex - a.aggregateIndex;
    }

    /** 同时维护旧 swap-with-last 序与 sin 双链；不扫描其余存活单元。 */
    private static function removeAggregateUnit(group:ChainGroup, unit:ChainUnitData):Void {
        var before:ChainUnitData = unit.aggregatePrev;
        var after:ChainUnitData = unit.aggregateNext;
        if (before != null) before.aggregateNext = after;
        else group.aggregateMin = after;
        if (after != null) after.aggregatePrev = before;
        else group.aggregateMax = before;
        var list:Array = group.单元体列表;
        var last:Number = list.length - 1;
        var index:Number = unit.aggregateIndex;
        if (index < last) {
            var moved:ChainUnitData = list[last];
            moved.aggregateIndex = index;
            list[index] = moved;
        }
        list.length = last;
        org.flashNight.arki.render.ChainVisualBridge.removeUnit(group, unit);
        releaseUnitData(unit);
    }

    /**
     * 同龄横向齐射：正推进下 sin 排序与逐次加法 y 排序相同。
     * 衰竭删除是旧倒序循环的必删前缀；首次不满足后，减小霰弹只会进一步
     * 抬高阈值，余下只需处理触地者。双链取触地区间，按旧 index 倒序删除。
     * 稳态 O(1)，事件 O(k log k)，k 为真正删除数；不把衰竭帧退回全表扫描。
     */
    public static function updateHorizontalAggregate(group:ChainGroup, advance:Number):Boolean {
        if (!group.aggregate) return false;
        var b = group.bullet;
        var list:Array = group.单元体列表;
        if (list.length == 0) return false;
        var sv:Number = b.霰弹值;
        var originalSv:Number = sv;
        var decay:Number = group.衰竭计数器 + (sv + b.子弹散射度) / 25;
        group.衰竭计数器 = decay;
        while (list.length > 1 && decay >= -sv) {
            removeAggregateUnit(group, list[list.length - 1]);
            sv--;
        }
        var minUnit:ChainUnitData = group.aggregateMin;
        var maxUnit:ChainUnitData = group.aggregateMax;
        materializeUnit(group, minUnit);
        if (maxUnit != minUnit) materializeUnit(group, maxUnit);
        var cosV:Number = group.余弦值;
        var py:Number = b._y;
        var hitZ:Number = b.Z轴坐标;
        var unit:ChainUnitData = cosV < 0 ? minUnit : maxUnit;
        if (list.length > 1 && unit.y * cosV + py > hitZ) {
            // 重用 scratch；只枚举真正触地的成员与一个边界失败者。
            var victims:Array = group.aggregateSorted;
            victims.length = 0;
            while (unit != null) {
                materializeUnit(group, unit);
                if (!(unit.y * cosV + py > hitZ)) break;
                victims[victims.length] = unit;
                unit = cosV < 0 ? unit.aggregateNext : unit.aggregatePrev;
            }
            victims.sort(compareIndexDescending);
            for (var i:Number = 0; i < victims.length && list.length > 1; i++) {
                removeAggregateUnit(group, victims[i]);
                sv--;
            }
            victims.length = 0;
            minUnit = group.aggregateMin;
            maxUnit = group.aggregateMax;
            materializeUnit(group, minUnit);
            if (maxUnit != minUnit) materializeUnit(group, maxUnit);
        }
        if (sv != originalSv) b.霰弹值 = sv;
        group.盒y = minUnit.y;
        var height:Number = maxUnit.y - minUnit.y;
        group.盒高 = height > group.最小盒高 ? height : group.最小盒高;
        return true;
    }

    /**
     * 纵向填满后 X 冻结。只在可证明不换边界的窗口内跳过内部单元；
     * 追近者用每步 1e-7 的保守舍入界（坐标与未来64步限制在1e7内）缩短窗口。
     * 角度/速度变化、交叉临界、补弹事件均重建；不扩大战斗包围盒。
     */
    public static function updateVerticalAggregate(group:ChainGroup):Void {
        var advance:Number = group.nativeAdvance;
        var list:Array = group.单元体列表;
        var count:Number = list.length;
        var minUnit:ChainUnitData = group.aggregateMin;
        var maxUnit:ChainUnitData = group.aggregateMax;
        var unit:ChainUnitData;
        if (group.aggregateSafe > 0 && advance == group.aggregateAdvance) {
            materializeUnit(group, minUnit);
            if (maxUnit != minUnit) materializeUnit(group, maxUnit);
            group.aggregateSafe--;
        } else {
            var minY:Number = Infinity;
            var maxY:Number = -Infinity;
            for (var i:Number = 0; i < count; i++) {
                unit = list[i];
                materializeUnit(group, unit);
                if (unit.y < minY || (unit.y == minY && unit.sin < minUnit.sin)) {
                    minY = unit.y; minUnit = unit;
                }
                if (unit.y > maxY || (unit.y == maxY && unit.sin > maxUnit.sin)) {
                    maxY = unit.y; maxUnit = unit;
                }
            }
            // 当前边界同时拥有极端 sin 时，IEEE 单调性保证永不被反超；
            // 无须每64帧重扫。只有真实追近者才使用有限认证窗口。
            var safe:Number = 2147483647;
            var limit:Number;
            var minDelta:Number = advance * minUnit.sin;
            var maxDelta:Number = advance * maxUnit.sin;
            var delta:Number;
            var magnitude:Number = minY < 0 ? -minY : minY;
            var maxMagnitude:Number = maxY < 0 ? -maxY : maxY;
            if (maxMagnitude > magnitude) magnitude = maxMagnitude;
            var bounded:Boolean = magnitude + advance * 66 < 10000000;
            if (advance < 0 || !isFinite(advance)) safe = 0;
            for (i = 0; i < count && safe > 0; i++) {
                unit = list[i];
                delta = advance * unit.sin;
                if (unit.sin < minUnit.sin) {
                    if (!bounded) { safe = 0; break; }
                    if (safe > 64) safe = 64;
                    limit = Math.floor((unit.y - minY) / (minDelta - delta + 0.0000001)) - 2;
                    if (limit < safe) safe = limit;
                }
                if (unit.sin > maxUnit.sin) {
                    if (!bounded) { safe = 0; break; }
                    if (safe > 64) safe = 64;
                    limit = Math.floor((maxY - unit.y) / (delta - maxDelta + 0.0000001)) - 2;
                    if (limit < safe) safe = limit;
                }
            }
            group.aggregateSafe = safe > 0 ? safe : 0;
            group.aggregateAdvance = advance;
            group.aggregateMin = minUnit;
            group.aggregateMax = maxUnit;
        }
        group.盒y = minUnit.y;
        var height:Number = maxUnit.y - minUnit.y;
        group.盒高 = height > group.最小盒高 ? height : group.最小盒高;
    }

    /** 撤销能力的同一调用内创建可见 MC；不新增随机采样、不改玩法状态。 */
}
