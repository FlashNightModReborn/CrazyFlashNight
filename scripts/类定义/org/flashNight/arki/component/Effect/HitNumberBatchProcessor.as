/**
 * ============================================================================
 * HitNumberBatchProcessor - 打击数字批处理器
 * ============================================================================
 *
 * 【系统概述】
 * 本类负责聚合每帧所有伤害数字事件，并一次性送往 Launcher C# reducer。
 * Flash MovieClip 渲染路径已经退役，不再提供 fallback；屏外剔除也只由
 * 掌握统一舞台边界与 100px 缓冲契约的 C# 布局层裁决。
 *
 * 【核心优化】
 * - 入队零临时对象：使用并行数组 + 长度计数，避免每次入队创建 Object
 * - Host 关闭态前置短路：不接收入队、不拼 hn 字符串
 * - 每段先完成定长字段拼接，再用 AVM1 实测更快的裸 `+` 汇入批 payload
 * - 每次 DamageResult.triggerDisplay 分配稳定 BurstId，联弹的虚拟子弹段共享一行
 *
 * 【调用时序】
 * 1. 帧内任意时刻：DamageResult.triggerDisplay() 调用 enqueueRaw() 收集请求
 * 2. 帧末统一处理：frameEnd 事件触发 flush() 批量渲染
 * 3. 场景切换时：调用 clear() 清空队列
 *
 * 【线程/时序约束】
 * - 假定单线程环境，flush() 在帧末统一调用
 * - enqueueRaw() 可在帧内任意时刻调用
 * - 静态工具类，所有 API 为 public static
 *
 * 【数据结构设计】
 * 使用并行数组 + 长度计数，正索引 [0, _length)。
 * Host 关闭时不接收入队；开启时保留全部请求，由 C# 做唯一可见性剔除。
 *
 * 【packed 编码格式】（由 DamageResult.triggerDisplay 打包）
 *
 *   bits  0-8  (9 bits):  _efFlags 效果位掩码
 *     bit 0 (1):    EF_CRUMBLE        — 溃
 *     bit 1 (2):    EF_TOXIC          — 毒
 *     bit 2 (4):    EF_EXECUTE        — 斩
 *     bit 3 (8):    EF_DMG_TYPE_LABEL — 真/魔法属性标签
 *     bit 4 (16):   EF_CRUSH_LABEL    — 破击属性标签
 *     bit 5 (32):   EF_LIFESTEAL      — 吸血
 *     bit 6 (64):   [保留]
 *     bit 7 (128):  isEnemy           — EF_EXECUTE 颜色选择（敌/友）
 *     bit 8 (256):  EF_SHIELD         — 护盾吸收
 *   bit  9        (1 bit):  isMISS（闪避状态）
 *   bits 10-17    (8 bits): damageSize（字体大小，0-255）
 *   bits 18-21    (4 bits): colorId（颜色 ID，索引 COLOR_TABLE，0-10）
 *   bits 22-30    (9 bits): [空闲，可用于未来扩展，如 force 标志]
 *
 * @version 2.0 - 移除遗留 enqueue/force/负索引机制
 * @author FlashNight
 * ============================================================================
 */

import org.flashNight.sara.util.*;
import org.flashNight.arki.render.FrameBroadcaster;

class org.flashNight.arki.component.Effect.HitNumberBatchProcessor {

    // ========================================================================
    // 并行数组存储（零分配设计）
    // ========================================================================

    /** 显示值数组（伤害数值） */
    private static var _values:Array = [];

    /** X 坐标数组（世界坐标） */
    private static var _xs:Array = [];

    /** Y 坐标数组（世界坐标） */
    private static var _ys:Array = [];

    /** packed Number 数组（flags+colorId+size+dodge 编码） */
    private static var _packed:Array = [];

    /** 效果属性文本数组（魔法/破击属性文本，无效果时为 null） */
    private static var _efTexts:Array = [];

    /** 效果 emoji 数组（破击 emoji，无效果时为 null） */
    private static var _efEmojis:Array = [];

    /** 吸血值数组（无吸血时为 0） */
    private static var _efLifeSteals:Array = [];

    /** 盾吸收值数组（无盾时为 0） */
    private static var _efShieldAbsorbs:Array = [];

    /** unitId 数组（来自 hitTarget._name，无 ID 时为空串）。C# overlay 用于 O(1) 同目标合并 */
    private static var _unitIds:Array = [];

    /** 一次 triggerDisplay 的稳定攻击标识；联弹展开段共享同一值。 */
    private static var _burstIds:Array = [];

    /** 该次攻击预计包含的虚拟子弹段数，用于 C# 在段到齐前预留稳定行几何。 */
    private static var _expectedHitCounts:Array = [];

    /** 队列长度 */
    private static var _length:Number = 0;

    /** Host 权威的源头开关。默认关闭，只有当前连接收到 H1 后才开始产出。 */
    private static var _hostEnabled:Boolean = false;

    /** 场景内单调 Burst 序列；Number 精确整数范围足够覆盖单场景生命周期。 */
    private static var _nextBurstSequence:Number = 1;

    /**
     * 协议字段安全发送：null/undefined → 空串
     *
     * 取值域审计（2026-03-30）：
     *   efText:  "真""能""热""冲""电""蚀""原体"（TrueDamageHandle/MagicDamageHandle/UniversalDamageHandle）
     *   efEmoji: "✨""☠"（UniversalDamageHandle:101）
     * 均不含协议分隔符 | ; " \，无需转义。
     */
    private static function safeField(s:String):String {
        if (s == null || s == undefined) return "";
        return s;
    }

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

    /** 为一次 DamageResult.triggerDisplay 分配场景内唯一的攻击标识。 */
    public static function nextBurstId():String {
        var id:String = String(_nextBurstSequence);
        _nextBurstSequence++;
        if (_nextBurstSequence >= 9007199254740000) _nextBurstSequence = 1;
        return id;
    }

    /** Host→Flash H0/H1 快车道入口；关闭时 flush 在任何协议字符串工作前丢弃。 */
    public static function setHostEnabled(enabled:Boolean):Void {
        _hostEnabled = enabled;
        if (!enabled) __resetQueue();
    }

    /** DamageResult.triggerDisplay 的最前置热路短路。 */
    public static function isHostEnabled():Boolean {
        return _hostEnabled;
    }

    /**
     * 将伤害数字显示请求以原始数据形式加入队列
     *
     * 仅收集标量快照，不做渲染操作。调用方已用 isHostEnabled() 前置短路；
     * flush 再对断线/竞态做防御性丢弃。
     *
     * @param damage       伤害数值
     * @param packed       打包的离散状态（_efFlags | isMISS<<9 | size<<10 | colorId<<18）
     * @param efText       效果属性文本（可为 null）
     * @param efEmoji      破击 emoji（可为 null）
     * @param lifeSteal    吸血量（无则 0）
     * @param shieldAbsorb 盾吸收量（无则 0）
     * @param x            世界坐标 X
     * @param y            世界坐标 Y
     * @param unitId       目标 unit 标识（hitTarget._name）
     * @param burstId      一次 triggerDisplay 的攻击标识
     * @param expectedHitCount 该次攻击预计的虚拟子弹段数
     */
    public static function enqueueRaw(
        damage:Number, packed:Number,
        efText:String, efEmoji:String,
        lifeSteal:Number, shieldAbsorb:Number,
        x:Number, y:Number, unitId:String,
        burstId:String, expectedHitCount:Number
    ):Void {
        var idx:Number = _length;
        ++_length;
        _values[idx] = damage;
        _packed[idx] = packed;
        _efTexts[idx] = efText;
        _efEmojis[idx] = efEmoji;
        _efLifeSteals[idx] = lifeSteal;
        _efShieldAbsorbs[idx] = shieldAbsorb;
        _xs[idx] = x;
        _ys[idx] = y;
        _unitIds[idx] = (unitId == null) ? "" : unitId;
        _burstIds[idx] = burstId;
        _expectedHitCounts[idx] = expectedHitCount;
    }

    /**
     * 帧末批量处理所有排队的显示请求
     *
     * Host 关闭、socket 未连接或 gameworld 不存在时直接清空。连接态不提前做可见性裁剪，
     * 并发送 11 字段协议：
     * damage|x|y|packed|efText|efEmoji|lifeSteal|shieldAbsorb|unitId|burstId|expectedHitCount
     */
    public static function flush():Void {
        var n:Number = _length;
        if (n == 0) return;

        var r:Object = _root;
        if (!_hostEnabled || !r.server.isSocketConnected) {
            __resetQueue();
            return;
        }
        if (!r.gameworld) {
            __resetQueue();
            return;
        }

        var i:Number = 0;
        var x:Number;
        var y:Number;
        var entry:String;
        var buf:String = "";
        do {
            x = _xs[i];
            y = _ys[i];
            entry = _values[i] + "|" + x + "|" + y + "|" + _packed[i] + "|";
            entry += safeField(_efTexts[i]) + "|";
            entry += safeField(_efEmojis[i]) + "|";
            entry += _efLifeSteals[i] + "|" + _efShieldAbsorbs[i] + "|";
            entry += _unitIds[i] + "|" + _burstIds[i] + "|" + _expectedHitCounts[i];
            if (i === 0) buf = entry;
            else buf += ";" + entry;
        } while (++i < n);

        FrameBroadcaster.setHnPayload(buf);
        if (debugMode) {
            r.服务器.发布服务器消息(
                "[HitNumberBatch] C# queued:" + n
            );
        }
        __resetQueue();
    }

    /**
     * 帧末快速重置队列
     */
    private static function __resetQueue():Void {
        _values.length = 0;
        _xs.length = 0;
        _ys.length = 0;
        _packed.length = 0;
        _efTexts.length = 0;
        _efEmojis.length = 0;
        _efLifeSteals.length = 0;
        _efShieldAbsorbs.length = 0;
        _unitIds.length = 0;
        _burstIds.length = 0;
        _expectedHitCounts.length = 0;
        _length = 0;
    }

    /**
     * 清空队列（场景切换/重启时调用）
     */
    public static function clear():Void {
        __resetQueue();
        _nextBurstSequence = 1;
    }

    /**
     * 获取当前队列长度（调试用）
     * @return 当前排队的请求数量
     */
    public static function getQueueLength():Number {
        return _length;
    }

    /**
     * 设置调试模式
     * @param enabled 是否启用调试输出
     */
    public static function setDebugMode(enabled:Boolean):Void {
        debugMode = enabled;
    }
}
