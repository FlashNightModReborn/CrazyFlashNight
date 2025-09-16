/**
 * ============================================================================
 * 子弹消除队列处理器
 * ============================================================================
 * 
 * 【系统概述】
 * 本类负责处理游戏中的消弹判定系统，通过队列缓存和批处理机制实现高效的子弹消除。
 * 支持反弹、消除等多种处理模式，使用事件驱动的帧更新机制。
 *
 * 【核心特性】
 * - 队列缓存：帧内入队，帧末批处理
 * - 区域碰撞：基于矩形区域的快速碰撞检测
 * - 方向过滤：支持按子弹飞行方向过滤
 * - Z轴判定：支持3D空间的高度差判定
 * - 敌我识别：根据阵营属性过滤子弹
 *
 * 【设计原则】
 * - 静态工具类模式，全局单例管理
 * - 零分配策略，复用数组对象
 * - 事件驱动，与帧更新系统集成
 *
 * @version 1.0
 * ============================================================================
 */

import org.flashNight.arki.component.Effect.*;
import org.flashNight.neur.Event.*;

class org.flashNight.arki.bullet.BulletComponent.Queue.BulletCancelQueueProcessor {

    // ========================================================================
    // 静态数据存储
    // ========================================================================

    /**
     * 消弹请求队列
     * 存储待处理的消弹请求对象
     */
    private static var queue:Array = [];

    /**
     * 子弹键缓存
     * 用于避免每帧重复枚举子弹容器
     */
    private static var bulletKeyCache:Array = [];

    /**
     * 是否已初始化
     */
    private static var initialized:Boolean = false;

    // ========================================================================
    // 系统初始化方法
    // ========================================================================

    /**
     * 初始化消弹队列处理器
     *
     * 创建队列和缓存，订阅事件监听器。
     * 此方法应在游戏启动时调用一次。
     *
     * @return {Boolean} 初始化是否成功
     */
    public static function initialize():Boolean {
        if (initialized) {
            return true;
        }

        // 使用 EventBus 单例订阅事件
        var eventBus:EventBus = EventBus.getInstance();

        // 订阅帧更新事件
        eventBus.subscribe("frameUpdate", function() {
            BulletCancelQueueProcessor.processQueue();
        }, BulletCancelQueueProcessor);

        // 订阅场景切换事件
        eventBus.subscribe("SceneChanged", function() {
            BulletCancelQueueProcessor.reset();
        }, BulletCancelQueueProcessor);


        initialized = true;
        return true;
    }

    // ========================================================================
    // 系统重置方法
    // ========================================================================

    /**
     * 重置消弹队列处理器
     *
     * 清空队列和缓存，用于场景切换时防止引用旧对象。
     *
     * @return {Boolean} 重置是否成功
     */
    public static function reset():Boolean {
        // 清空队列和缓存
        queue.length = 0;
        bulletKeyCache.length = 0;
        return true;
    }

    // ========================================================================
    // 消弹请求入队方法
    // ========================================================================

    /**
     * 将消弹请求加入队列
     *
     * @param {Object} request 消弹请求对象，包含以下属性：
     *   - 区域定位area {MovieClip} 消弹区域
     *   - shooter {String} 发射者名称（反弹模式用）
     *   - shootZ {Number} 发射者Z轴坐标
     *   - 消弹敌我属性 {Boolean} 是否为敌人
     *   - 消弹方向 {String} "左"/"右"/null
     *   - Z轴攻击范围 {Number} Z轴判定范围
     *   - 反弹 {Boolean} 是否反弹模式
     *   - 强力 {Boolean} 是否强力消除
     */
    public static function enqueue(request:Object):Void {
        if (_root.暂停) return;

        // 最小校验：需要区域定位area
        if (request && request.区域定位area) {
            queue.push(request);
        }
    }

    /**
     * 添加消弹请求（enqueue的别名，与BulletQueueProcessor保持一致）
     */
    public static function add(request:Object):Void {
        enqueue(request);
    }

    // ========================================================================
    // 属性初始化辅助方法
    // ========================================================================

    /**
     * 初始化消弹属性对象
     *
     * 便捷方法，用于构造标准的消弹请求对象。
     *
     * @param {MovieClip} area 消弹区域MovieClip
     * @return {Object} 初始化好的消弹属性对象
     */
    public static function initArea(area:MovieClip):Object {
        var props:Object = {
            shooter: area._parent._parent._name,
            shootZ: area._parent._parent.Z轴坐标,
            消弹敌我属性: area._parent._parent.是否为敌人,
            消弹方向: null,          // 无方向限制；可传 "左" 或 "右"
            Z轴攻击范围: 10,
            区域定位area: area
        };
        return props;
    }

    // ========================================================================
    // 核心处理方法：批量消弹判定
    // ========================================================================

    /**
     * 处理消弹队列
     *
     * 这是消弹系统的核心方法，每帧调用一次。
     * 遍历队列中的所有请求，对每个请求进行区域碰撞检测和处理。
     *
     * 【处理流程】
     * 1. 构建子弹键缓存（避免重复枚举）
     * 2. 遍历队列中的每个消弹请求
     * 3. 对每个请求，扫描所有子弹进行碰撞检测
     * 4. 根据模式（反弹/消除）处理命中的子弹
     * 5. 清空队列，准备下一帧
     *
     * 【性能优化】
     * - 使用缓存避免重复枚举
     * - 早期退出减少无效检测
     * - 复用数组对象，零分配策略
     */
    public static function processQueue():Void {
        if (_root.暂停) return;

        var gw:MovieClip = _root.gameworld;
        if (!gw) return;

        var 子弹容器:Object = gw.子弹区域;
        if (!子弹容器 || queue.length == 0) return;

        // 每帧仅构建一次子弹 key 列表
        var keys:Array = bulletKeyCache;
        var ki:Number = 0;
        for (var k:String in 子弹容器) {
            keys[ki++] = k;
        }
        keys.length = ki; // 截断到本帧长度

        // ========================================================================
        // 宏定义导入（编译时展开）
        // ========================================================================
        #include "../macros/FLAG_MELEE.as"

        // 逐请求处理（合批）
        var qlen:Number = queue.length;

        for (var qi:Number = 0; qi < qlen; qi++) {
            var req:Object = queue[qi];

            // 局部缓存参数
            var 消弹敌我属性:Boolean = req.消弹敌我属性;
            var 消弹方向:String = req.消弹方向;          // "左"/"右"/null
            var shootZ:Number = req.shootZ;
            var Z轴攻击范围:Number = req.Z轴攻击范围;
            var 区域定位area:MovieClip = req.区域定位area;

            // 若区域已被移除或无 getRect，则跳过该请求
            if (!区域定位area || !区域定位area.getRect) continue;

            // 使用"最终位置"求矩形（gameworld 坐标系）
            var R:Object = 区域定位area.getRect(gw);

            // 扫描子弹（用缓存 keys）
            for (var i:Number = 0; i < ki; i++) {
                var b:MovieClip = 子弹容器[keys[i]];
                if (!b) continue;

                // 早退：Z轴范围 / 近战 / 静止
                var zOff:Number = b.Z轴坐标 - shootZ;
                if ((zOff > Z轴攻击范围 || zOff < -Z轴攻击范围) ||
                    (b.flags & FLAG_MELEE) ||
                    b.xmov == 0) continue;

                // 方向过滤（可选）
                var bdir:String = (b.xmov > 0) ? "右" : "左";
                if (消弹方向 && 消弹方向 != bdir) continue;

                // 只处理"敌对子弹"（同侧跳过）
                if (消弹敌我属性 == b.是否为敌人) continue;

                // 注册点 -> gameworld 坐标
                var pt:Object = {x:0, y:0};
                b.localToGlobal(pt);
                gw.globalToLocal(pt);

                // 点 ∈ 矩形（轴对齐）
                if (pt.x < R.xMin || pt.x > R.xMax ||
                    pt.y < R.yMin || pt.y > R.yMax) continue;

                // 命中处理
                if (req.反弹) {
                    handleBounce(b, req.shooter);
                } else {
                    handleCancel(b, req.强力);
                }
            }
        }

        // 清空队列（复用数组对象，零分配）
        queue.length = 0;
    }

    // ========================================================================
    // 子弹处理方法
    // ========================================================================

    /**
     * 处理子弹反弹
     *
     * @param {MovieClip} bullet 要反弹的子弹
     * @param {String} newShooter 新的发射者名称
     */
    private static function handleBounce(bullet:MovieClip, newShooter:String):Void {
        bullet.发射者名 = newShooter;

        // 当前方向（弧度）与速度
        var rad:Number = Math.atan2(bullet.ymov, bullet.xmov);
        var speed:Number = Math.sqrt(bullet.xmov * bullet.xmov + bullet.ymov * bullet.ymov);

        // 随机偏移（±30°）
        var offsetRad:Number = (Math.random() - 0.5) * (Math.PI / 3);
        // 反弹 = 方向 + π，再加一点随机扰动
        var newRad:Number = rad + Math.PI + offsetRad;

        // 更新速度向量与朝向
        bullet.xmov = Math.cos(newRad) * speed;
        bullet.ymov = Math.sin(newRad) * speed;
        bullet._rotation = newRad * 180 / Math.PI;
    }

    /**
     * 处理子弹消除
     *
     * @param {MovieClip} bullet 要消除的子弹
     * @param {Boolean} isPowerful 是否强力消除
     */
    private static function handleCancel(bullet:MovieClip, isPowerful:Boolean):Void {
        #include "../macros/FLAG_PIERCE.as"

        bullet.击中地图 = true;
        EffectSystem.Effect(bullet.击中地图效果, bullet._x, bullet._y);
        bullet.gotoAndPlay("消失");

        if (isPowerful && (bullet.flags & FLAG_PIERCE)) {
            bullet.removeMovieClip();
        }
    }
}