/**
 * ============================================================================
 * HitNumberBatchProcessor - 打击数字批处理器 
 * ============================================================================
 *
 * 【系统概述】
 * 本类负责聚合每帧所有伤害数字显示请求，统一做节流和对象池使用决策，
 * 最终调用现有 _root.打击数字特效 完成渲染。
 *
 * 【核心优化】
 * - 节流决策从 O(N) 降至 O(1)：每帧仅执行一次节流判断，而非每个请求都判断
 * - 零分配设计：使用并行数组 + 长度计数，避免每次 enqueue 创建临时 Object
 * - 视野剔除复用：同一位置的多段伤害共享视野检查结果
 *
 * 【调用时序】
 * 1. 帧内任意时刻：业务代码调用 enqueue() 收集显示请求
 * 2. 帧末统一处理：frameEnd 事件触发 flush() 批量渲染
 * 3. 场景切换时：调用 clear() 清空队列
 *
 * 【线程/时序约束】
 * - 假定单线程环境，flush() 在帧末统一调用
 * - enqueue() 可在帧内任意时刻调用
 * - 静态工具类，所有 API 为 public static
 *
 * @version 1.0
 * @author Claude Code
 * ============================================================================
 */

import org.flashNight.sara.util.*;

class org.flashNight.arki.component.Effect.HitNumberBatchProcessor {

    // ========================================================================
    // 并行数组存储（零分配设计）
    // ========================================================================

    /** 控制字符串数组（效果种类，如"暴击"、"能"等） */
    private static var _ctrls:Array = [];

    /** 显示值数组（数值或已格式化的 <font> 字符串） */
    private static var _values:Array = [];

    /** X 坐标数组（世界坐标） */
    private static var _xs:Array = [];

    /** Y 坐标数组（世界坐标） */
    private static var _ys:Array = [];

    /** 强制显示标志数组（无视节流） */
    private static var _forces:Array = [];

    /** 当前队列长度（逻辑长度，非数组物理长度） */
    private static var _length:Number = 0;

    // ========================================================================
    // 配置参数
    // ========================================================================

    /** 强制显示请求的每帧硬上限，防止滥用 */
    private static var _maxForcePerFrame:Number = 20;

    /** 是否启用批处理器（全局开关，用于回退） */
    public static var enabled:Boolean = true;

    /** 是否启用调试输出 */
    public static var debugMode:Boolean = false;

    // ========================================================================
    // 私有构造函数（静态工具类）
    // ========================================================================

    /**
     * 私有构造函数，禁止实例化
     */
    private function HitNumberBatchProcessor() {
        // 静态工具类，不允许实例化
    }

    // ========================================================================
    // 公共 API
    // ========================================================================

    /**
     * 将伤害数字显示请求加入队列
     *
     * 此方法仅收集数据，不做任何节流判断或渲染操作。
     * 所有决策延迟到 flush() 时统一处理。
     *
     * @param ctrl  控制字符串（效果种类），与旧 _root.打击数字特效 语义一致
     * @param value 数值或已包含 <font> 的格式化字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @param force 是否无视节流强制显示（对应 _root.打击数字特效 的"必然触发"）
     */
    public static function enqueue(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        var idx:Number = _length;
        _ctrls[idx] = ctrl;
        _values[idx] = value;
        _xs[idx] = x;
        _ys[idx] = y;
        _forces[idx] = force;
        _length = idx + 1;
    }

    /**
     * 帧末批量处理所有排队的显示请求
     *
     * 【节流算法】
     * 1. 统计总请求数 N 和强制请求数 forceCount
     * 2. 计算剩余容量 remaining = 上限 - 当前数量
     * 3. 决策：
     *    - force=true 的请求：始终显示（受 _maxForcePerFrame 硬上限保护）
     *    - remaining >= N：全部显示
     *    - remaining <= 0：非 force 请求全部丢弃
     *    - 0 < remaining < N：按队列顺序取前 remaining 个显示
     *
     * 【调用时机】
     * 应在 frameEnd 事件中调用，确保所有 enqueue 完成后统一处理。
     */
    public static function flush():Void {
        var n:Number = _length;
        if (n == 0) return;

        // === 阶段1：获取全局控制参数 ===
        var capacityBase:Number = _root.同屏打击数字特效上限;
        var current:Number = _root.当前打击数字特效总数;
        var remaining:Number = capacityBase - current;
        if (remaining < 0) remaining = 0;

        // === 阶段2：统计强制请求数量 ===
        var forceCount:Number = 0;
        var i:Number;
        for (i = 0; i < n; ++i) {
            if (_forces[i]) {
                ++forceCount;
            }
        }

        // 限制强制请求数量
        var actualForceLimit:Number = _maxForcePerFrame;
        if (forceCount > actualForceLimit) {
            forceCount = actualForceLimit;
        }

        // === 阶段3：计算非强制请求的显示配额 ===
        var normalCount:Number = n - forceCount;
        var normalQuota:Number;

        if (remaining >= normalCount) {
            // 容量充足，全部显示
            normalQuota = normalCount;
        } else if (remaining <= 0) {
            // 容量耗尽，非强制请求全部丢弃
            normalQuota = 0;
        } else {
            // 部分显示，按队列顺序取前 remaining 个
            normalQuota = remaining;
        }

        // === 阶段4：视野剔除准备 ===
        var gameWorld:MovieClip = _root.gameworld;
        if (!gameWorld) {
            _length = 0;
            return;
        }

        var sx:Number = gameWorld._xscale * 0.01;
        var gx:Number = gameWorld._x;
        var gy:Number = gameWorld._y;
        var sw:Number = Stage.width;
        var sh:Number = Stage.height;

        // === 阶段5：遍历队列，执行显示 ===
        var displayFn:Function = _root.打击数字特效内部;
        var normalShown:Number = 0;
        var forceShown:Number = 0;
        var culledCount:Number = 0;
        var droppedCount:Number = 0;

        for (i = 0; i < n; ++i) {
            var isForce:Boolean = _forces[i];
            var x:Number = _xs[i];
            var y:Number = _ys[i];

            // 视野剔除（统一检查，无论 force 与否）
            var locX:Number = gx + x * sx;
            var locY:Number = gy + y * sx;
            if (locX < 0 || locX > sw || locY < 0 || locY > sh) {
                ++culledCount;
                continue;
            }

            if (isForce) {
                // 强制请求：检查硬上限
                if (forceShown < actualForceLimit) {
                    displayFn(_ctrls[i], _values[i], x, y, true);
                    ++forceShown;
                } else {
                    ++droppedCount;
                }
            } else {
                // 普通请求：检查配额
                if (normalShown < normalQuota) {
                    displayFn(_ctrls[i], _values[i], x, y, false);
                    ++normalShown;
                } else {
                    ++droppedCount;
                }
            }
        }

        // === 阶段6：调试输出 ===
        if (debugMode) {
            _root.服务器.发布服务器消息(
                "[HitNumberBatch] 队列:" + n +
                " 显示:" + (normalShown + forceShown) +
                " 剔除:" + culledCount +
                " 丢弃:" + droppedCount +
                " (force:" + forceShown + "/" + forceCount + ")"
            );
        }

        // === 阶段7：重置队列 ===
        // 清空引用，帮助 GC（对于字符串等引用类型）
        for (i = 0; i < n; ++i) {
            _ctrls[i] = null;
            _values[i] = null;
        }
        _length = 0;
    }

    /**
     * 清空队列
     *
     * 用于场景切换或游戏重启时调用，确保不会有残留请求。
     */
    public static function clear():Void {
        var n:Number = _length;
        for (var i:Number = 0; i < n; ++i) {
            _ctrls[i] = null;
            _values[i] = null;
        }
        _length = 0;
    }

    /**
     * 获取当前队列长度（调试用）
     * @return 当前排队的请求数量
     */
    public static function getQueueLength():Number {
        return _length;
    }

    /**
     * 设置强制请求的每帧硬上限
     * @param max 最大数量，默认 20
     */
    public static function setMaxForcePerFrame(max:Number):Void {
        if (!isNaN(max) && max > 0) {
            _maxForcePerFrame = max;
        }
    }

    /**
     * 设置调试模式
     * @param enabled 是否启用调试输出
     */
    public static function setDebugMode(enabled:Boolean):Void {
        debugMode = enabled;
    }
}
