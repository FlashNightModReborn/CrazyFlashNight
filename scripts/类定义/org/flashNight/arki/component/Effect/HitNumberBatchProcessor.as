/**
 * ============================================================================
 * HitNumberBatchProcessor - 打击数字批处理器
 * ============================================================================
 *
 * 【系统概述】
 * 本类负责聚合每帧所有伤害数字显示请求，统一做节流和对象池使用决策，
 * 最终调用现有 _root.打击数字特效内部 完成渲染。
 *
 * 【核心优化】
 * - 节流决策从 O(N) 降至 O(1)：每帧仅执行一次节流判断，而非每个请求都判断
 * - 零分配设计：使用并行数组 + 长度计数，避免每次 enqueue 创建临时 Object
 * - 视野剔除复用：同一位置的多段伤害共享视野检查结果
 * - 负索引隔离：force 请求使用负索引存储，与普通请求完全隔离
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
 * 【数据结构设计】
 * 使用负索引技巧将 force 请求与普通请求分离：
 * - 普通请求：索引 0, 1, 2, ... (_length - 1)
 * - force 请求：索引 -1, -2, -3, ... (-_forceLength)
 *
 * 优势：
 * - force 请求无条件执行，不受任何节流限制
 * - 普通请求独立节流，不被 force 请求挤占配额
 * - flush 时先处理 force（负索引），再处理普通（正索引）
 * - 遍历起点清晰：从 -_forceLength 到 _length - 1
 *
 * 【语义说明】
 * - force（必然触发）参数：无条件显示，仅受视野剔除影响
 *   与旧 _root.打击数字特效 的"必然触发"语义完全一致
 *
 * - 批处理路径尊重 _root.是否打击数字特效 全局开关
 *   当该开关为 false 时，普通请求全部丢弃，force 请求仍然显示
 *
 * @version 1.2
 * @author FlashNight
 * ============================================================================
 */

import org.flashNight.sara.util.*;

class org.flashNight.arki.component.Effect.HitNumberBatchProcessor {

    // ========================================================================
    // 并行数组存储（零分配设计 + 负索引隔离）
    // ========================================================================
    //
    // 数据布局示意：
    //   索引: ... -3  -2  -1  |  0   1   2  ...
    //   类型:    force区域    |    普通区域
    //
    // - 普通请求写入正索引 [0, _length)
    // - force 请求写入负索引 [-_forceLength, -1]
    // - AS2 数组支持负索引，但不计入 length 属性
    // ========================================================================

    /** 控制字符串数组（效果种类，如"暴击"、"能"等） */
    private static var _ctrls:Array = [];

    /** 显示值数组（数值或已格式化的 <font> 字符串） */
    private static var _values:Array = [];

    /** X 坐标数组（世界坐标） */
    private static var _xs:Array = [];

    /** Y 坐标数组（世界坐标） */
    private static var _ys:Array = [];

    /** 普通请求队列长度（正索引区域） */
    private static var _length:Number = 0;

    /** force 请求队列长度（负索引区域，存储为正数，实际索引为 -1 到 -_forceLength） */
    private static var _forceLength:Number = 0;

    // ========================================================================
    // 配置参数
    // ========================================================================

    /** 是否启用批处理器（全局开关，用于回退到立即渲染模式） */
    public static var enabled:Boolean = true;

    /** 是否启用调试输出 */
    public static var debugMode:Boolean = false;

    // ========================================================================
    // 默认值常量（用于防御性处理未初始化的全局变量）
    // ========================================================================

    /** 默认同屏打击数字特效上限（当 _root.同屏打击数字特效上限 未初始化时使用） */
    private static var DEFAULT_CAPACITY:Number = 25;

    /** 默认当前计数（当 _root.当前打击数字特效总数 未初始化时使用） */
    private static var DEFAULT_CURRENT:Number = 0;

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
     * 【负索引隔离】
     * - force=false：写入正索引 [0, _length)，受节流控制
     * - force=true：写入负索引 [-_forceLength, -1]，无条件显示
     *
     * @param ctrl  控制字符串（效果种类），与旧 _root.打击数字特效 语义一致
     * @param value 数值或已包含 <font> 的格式化字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @param force 是否无视节流强制显示（对应 _root.打击数字特效 的"必然触发"）
     */
    public static function enqueue(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        var idx:Number;
        if (force) {
            // force 请求：写入负索引区域
            // _forceLength: 1 -> idx = -1
            // _forceLength: 2 -> idx = -2
            ++_forceLength;
            idx = -_forceLength;
        } else {
            // 普通请求：写入正索引区域
            idx = _length;
            ++_length;
        }
        _ctrls[idx] = ctrl;
        _values[idx] = value;
        _xs[idx] = x;
        _ys[idx] = y;
    }

    /**
     * 帧末批量处理所有排队的显示请求
     *
     * 【处理流程】
     * 1. 先处理 force 请求（负索引区域）：无条件显示，仅受视野剔除影响
     * 2. 再处理普通请求（正索引区域）：受节流控制
     *
     * 【节流算法（仅对普通请求）】
     * 1. 检查全局开关 _root.是否打击数字特效
     * 2. 计算剩余容量 remaining = 上限 - 当前数量
     * 3. 决策：
     *    - remaining >= normalCount：全部显示
     *    - remaining <= 0：全部丢弃
     *    - 0 < remaining < normalCount：按队列顺序取前 remaining 个显示
     *
     * 【防御性处理】
     * - 若 _root.同屏打击数字特效上限 未初始化，使用 DEFAULT_CAPACITY (25)
     * - 若 _root.当前打击数字特效总数 未初始化，使用 DEFAULT_CURRENT (0)
     * - 若 _root.gameworld 不存在，直接清空队列返回
     *
     * 【调用时机】
     * 应在 frameEnd 事件中调用，确保所有 enqueue 完成后统一处理。
     */
    public static function flush():Void {
        var nNormal:Number = _length;
        var nForce:Number = _forceLength;

        // 空队列快速返回
        if (nNormal == 0 && nForce == 0) return;

        // === 阶段1：视野剔除准备 ===
        var gameWorld:MovieClip = _root.gameworld;
        if (!gameWorld) {
            // 游戏世界不存在，清空队列后返回
            __clearQueue();
            return;
        }

        var sx:Number = gameWorld._xscale * 0.01;
        var gx:Number = gameWorld._x;
        var gy:Number = gameWorld._y;
        var sw:Number = Stage.width;
        var sh:Number = Stage.height;

        var displayFn:Function = _root.打击数字特效内部;
        var forceShown:Number = 0;
        var forceCulled:Number = 0;
        var i:Number;
        var x:Number;
        var y:Number;
        var locX:Number;
        var locY:Number;

        // === 阶段2：处理 force 请求（负索引区域，无条件显示） ===
        // 遍历索引：-nForce, -nForce+1, ..., -1
        for (i = -nForce; i < 0; ++i) {
            x = _xs[i];
            y = _ys[i];

            // 视野剔除（force 请求也要剔除视野外的）
            locX = gx + x * sx;
            locY = gy + y * sx;
            if (locX < 0 || locX > sw || locY < 0 || locY > sh) {
                ++forceCulled;
                continue;
            }

            // 无条件显示
            displayFn(_ctrls[i], _values[i], x, y, true);
            ++forceShown;
        }

        // === 阶段3：检查全局显示开关（仅影响普通请求） ===
        var globalEnabled:Boolean = _root.是否打击数字特效;
        // 防御性处理：undefined 视为 true（默认启用）
        if (globalEnabled == undefined) {
            globalEnabled = true;
        }

        var normalShown:Number = 0;
        var normalCulled:Number = 0;
        var normalDropped:Number = 0;

        // === 阶段4：处理普通请求（正索引区域，受节流控制） ===
        if (nNormal > 0 && globalEnabled) {
            // 获取全局控制参数（带防御性处理）
            var capacityBase:Number = _root.同屏打击数字特效上限;
            if (isNaN(capacityBase) || capacityBase <= 0) {
                capacityBase = DEFAULT_CAPACITY;
            }

            var current:Number = _root.当前打击数字特效总数;
            if (isNaN(current) || current < 0) {
                current = DEFAULT_CURRENT;
            }

            var remaining:Number = capacityBase - current;
            if (remaining < 0) remaining = 0;

            // 计算普通请求的显示配额
            var normalQuota:Number;
            if (remaining >= nNormal) {
                normalQuota = nNormal;
            } else {
                normalQuota = remaining;
            }

            // 遍历正索引区域
            for (i = 0; i < nNormal; ++i) {
                x = _xs[i];
                y = _ys[i];

                // 视野剔除
                locX = gx + x * sx;
                locY = gy + y * sx;
                if (locX < 0 || locX > sw || locY < 0 || locY > sh) {
                    ++normalCulled;
                    continue;
                }

                // 检查配额
                if (normalShown < normalQuota) {
                    displayFn(_ctrls[i], _values[i], x, y, false);
                    ++normalShown;
                } else {
                    ++normalDropped;
                }
            }
        } else if (nNormal > 0) {
            // 全局开关关闭，普通请求全部丢弃
            normalDropped = nNormal;
        }

        // === 阶段5：调试输出 ===
        if (debugMode) {
            _root.服务器.发布服务器消息(
                "[HitNumberBatch] force:" + forceShown + "/" + nForce +
                "(剔除" + forceCulled + ")" +
                " normal:" + normalShown + "/" + nNormal +
                "(剔除" + normalCulled + ",丢弃" + normalDropped + ")" +
                " global:" + (globalEnabled ? "ON" : "OFF")
            );
        }

        // === 阶段6：重置队列 ===
        __clearQueue();
    }

    /**
     * 内部方法：清空队列数据
     *
     * 【AS2 数组清理机制】
     * AS2 Array 有两类成员：
     * 1. 数组元素（正索引 0,1,2...）：由 length 属性管理
     *    - 设置 length = 0 会自动删除所有 >= 0 的数组元素
     * 2. 普通属性（负索引 -1,-2... 或字符串键）：不受 length 影响
     *    - 需要手动 delete 或赋 null 清理
     *
     * 因此：
     * - 正索引区域：直接设 length = 0 即可自动回收
     * - 负索引区域：必须手动遍历清理（因为是字符串键 "-1", "-2"...）
     */
    private static function __clearQueue():Void {
        // 清理负索引区域（force 请求）- 必须手动清理
        // 负索引在 AS2 中是字符串键，不受 length 管理
        for (var i:Number = -_forceLength; i < 0; ++i) {
            delete _ctrls[i];
            delete _values[i];
            delete _xs[i];
            delete _ys[i];
        }

        // 清理正索引区域（普通请求）- 利用 length = 0 自动回收
        _ctrls.length = 0;
        _values.length = 0;
        _xs.length = 0;
        _ys.length = 0;

        // 重置计数器
        _length = 0;
        _forceLength = 0;
    }

    /**
     * 清空队列
     *
     * 用于场景切换或游戏重启时调用，确保不会有残留请求。
     */
    public static function clear():Void {
        __clearQueue();
    }

    /**
     * 获取当前普通请求队列长度（调试用）
     * @return 当前排队的普通请求数量
     */
    public static function getQueueLength():Number {
        return _length;
    }

    /**
     * 获取当前 force 请求队列长度（调试用）
     * @return 当前排队的 force 请求数量
     */
    public static function getForceQueueLength():Number {
        return _forceLength;
    }

    /**
     * 设置调试模式
     * @param enabled 是否启用调试输出
     */
    public static function setDebugMode(enabled:Boolean):Void {
        debugMode = enabled;
    }
}
