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
}
