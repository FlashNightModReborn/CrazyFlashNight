import org.flashNight.neur.Event.*;
import org.flashNight.arki.bullet.BulletComponent.Queue.*;
import org.flashNight.arki.bullet.BulletComponent.Collider.*;

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
            // 旧世界的组与单元体已随世界销毁，重置注册表
            groups = [];
            // 统一帧驱动（类方法内创建的闭包，不受帧脚本 activation object 回收影响）
            layer.onEnterFrame = function():Void {
                ChainUnitManager.tick();
            };
        }
        return layer;
    }

    /**
     * 清空组注册表（场景切换/世界销毁时调用）。
     * 旧层、池与单元体随旧 gameworld 一并销毁，此处仅释放静态引用。
     */
    public static function resetAll():Void {
        groups = [];
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
        if (pool != undefined && pool.length > 0) {
            unit = MovieClip(pool.pop());
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
     * 释放单元体回池（隐藏 + 入自由表，不销毁实例）
     */
    public static function releaseUnit(unit:MovieClip):Void {
        if (unit == undefined || unit.__池键 == undefined) return;
        // 入池重置契约：停住时间轴（隐藏的高水位实例不再逐帧消耗），复用时 gotoAndPlay(1) 重启
        unit.stop();
        unit._visible = false;
        var pools:Object = unit._parent.可用单元体池;
        if (pools == undefined) return; // 层已随世界销毁
        var pool:Array = pools[unit.__池键];
        if (pool == undefined) {
            pool = [];
            pools[unit.__池键] = pool;
        }
        pool.push(unit);
    }

    /**
     * 注册联弹组。组对象契约：
     *   { area:MovieClip, bullet:MovieClip, 单元体列表:Array of {mc,x,y,rot,...}, update:Function(group) }
     */
    public static function registerGroup(group:Object):Void {
        getLayer(); // 确保层与统一 tick 存在
        groups.push(group);
    }

    /**
     * 按子弹 MC 查找组（消失路径显式回收用）
     */
    public static function findGroupByBullet(bullet:MovieClip):Object {
        for (var i:Number = groups.length - 1; i >= 0; i--) {
            if (groups[i].bullet == bullet) return groups[i];
        }
        return null;
    }

    /**
     * 回收整组单元体并注销（swap-with-last + pop）
     */
    public static function removeGroup(group:Object):Void {
        if (group == null || group.__removed) return;
        group.__removed = true;
        var list:Array = group.单元体列表;
        for (var u:Number = 0; u < list.length; u++) {
            releaseUnit(list[u].mc);
        }
        list.length = 0;
        var n:Number = groups.length;
        for (var i:Number = n - 1; i >= 0; i--) {
            if (groups[i] == group) {
                if (i < n - 1) groups[i] = groups[n - 1];
                groups.pop();
                break;
            }
        }
    }

    /** 按子弹 MC 回收组（供消失帧脚本调用，未注册时安全 no-op） */
    public static function removeGroupByBullet(bullet:MovieClip):Void {
        removeGroup(findGroupByBullet(bullet));
    }

    /**
     * 统一帧更新：倒序分发各组 update；失效组兜底回收。
     * 暂停时整体跳过（与旧 per-clip onEnterFrame 行为一致）。
     *
     * 对象化联弹（group.area == null）在此承担 MC 子弹 onEnterFrame 预检查的职责：
     * 边界外标记 STATE_HIT_MAP → 更新 AABB（数据路径）→ 泵入 BulletQueueProcessor。
     * processQueue 由 frameEnd 事件在帧末统一消费，与 MC 子弹的入队时序同构。
     */
    public static function tick():Void {
        if (_root.暂停) return;
        // === 宏展开：实例状态标志位 ===
        #include "../macros/STATE_HIT_MAP.as"
        var xmin:Number = _root.Xmin;
        var xmax:Number = _root.Xmax;
        var ymin:Number = _root.Ymin;
        var ymax:Number = _root.Ymax;

        for (var i:Number = groups.length - 1; i >= 0; i--) {
            var g:Object = groups[i];
            if (g.area == null) {
                // —— 对象化联弹分支 ——
                var b = g.bullet;
                if (b.__chainDead) {
                    removeGroup(g);
                    continue;
                }
                g.update(g);

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
                g.update(g);
            }
        }
    }

    /** 当前活动组数（调试用） */
    public static function getActiveGroupCount():Number {
        return groups.length;
    }
}
