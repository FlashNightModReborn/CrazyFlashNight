/**
 * ============================================================================
 * HitNumberBatchProcessor - 打击数字批处理器
 * ============================================================================
 *
 * 【系统概述】
 * 本类负责聚合每帧所有伤害数字显示请求，统一做节流和对象池使用决策，
 * 最终调用 HitNumberSystem.spawn() 完成渲染。
 *
 * 【核心优化】
 * - 节流决策从 O(N) 降至 O(1)：每帧仅执行一次节流判断，而非每个请求都判断
 * - 零分配设计：使用并行数组 + 长度计数，避免每次入队创建临时 Object
 * - 延迟 HTML 构建：flush 先剔除/丢弃后，仅对存活项调用 buildHtml
 * - 全局开关前置短路：开关关闭时跳过全部视野计算
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
 * 所有请求统一受节流控制，视野外请求被剔除。
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
import org.flashNight.arki.component.Effect.HitNumberSystem;
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

    /** 队列长度 */
    private static var _length:Number = 0;

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

    // ========================================================================
    // 配置参数
    // ========================================================================

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
    // 延迟 HTML 构建：颜色查表 + 静态片段缓存
    // ========================================================================

    /** 颜色 ID → 颜色字符串查表（索引即 _dmgColorId） */
    public static var COLOR_TABLE:Array = [
        "#FFFFFF", "#FF0000", "#FFCC00", "#660033", "#4A0099",
        "#AC99FF", "#0099FF", "#7F0000", "#7F6A00", "#FF7F7F", "#FFE770"
    ];

    /** 预缓存的静态 HTML 片段（避免重复拼接） */
    private static var FRAG_CRUMBLE:String       = '<font color="#FF3333" size="20"> 溃</font>';
    private static var FRAG_TOXIC:String         = '<font color="#66dd00" size="20"> 毒</font>';
    private static var FRAG_EXECUTE_ENEMY:String = '<font color="#660033" size="20"> 斩</font>';
    private static var FRAG_EXECUTE_ALLY:String  = '<font color="#4A0099" size="20"> 斩</font>';
    private static var FRAG_LIFESTEAL_PRE:String = '<font color="#bb00aa" size="15"> 汲:';
    private static var FRAG_SHIELD_PRE:String    = '<font color="#00CED1" size="18"> 🛡';
    private static var FRAG_CRUSH_PRE:String     = '<font color="#66bcf5" size="20"> ';
    private static var FONT_END:String           = '</font>';

    /** fontStart 懒缓存：key = (colorId << 8) | size → '<font color="X" size="Y">' */
    private static var _fontStartCache:Object = {};

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
     * 将伤害数字显示请求以原始数据形式加入队列（延迟 HTML 构建）
     *
     * 仅收集标量快照，不做任何节流判断或渲染操作。
     * flush 先剔除/丢弃后，仅对存活项调用 buildHtml 构建 HTML。
     *
     * @param damage       伤害数值
     * @param packed       打包的离散状态（_efFlags | isMISS<<9 | size<<10 | colorId<<18）
     * @param efText       效果属性文本（可为 null）
     * @param efEmoji      破击 emoji（可为 null）
     * @param lifeSteal    吸血量（无则 0）
     * @param shieldAbsorb 盾吸收量（无则 0）
     * @param x            世界坐标 X
     * @param y            世界坐标 Y
     */
    public static function enqueueRaw(
        damage:Number, packed:Number,
        efText:String, efEmoji:String,
        lifeSteal:Number, shieldAbsorb:Number,
        x:Number, y:Number
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
    }

    /**
     * 帧末批量处理所有排队的显示请求
     *
     * 【处理流程】
     * 1. 全局开关预读 + 短路（开关关闭 → 立即返回）
     * 2. 视野剔除准备
     * 3. 遍历队列：视野剔除 + 配额控制 + buildHtml + spawn
     *
     * 【节流算法】
     * 1. 计算剩余容量 remaining = 上限 - 当前数量
     * 2. 决策：
     *    - remaining >= count：全部显示
     *    - remaining <= 0：全部丢弃
     *    - 0 < remaining < count：按队列顺序取前 remaining 个显示
     *
     * 【防御性处理】
     * - _root.是否打击数字特效：由引擎常数保证初始化，无需 undefined 检查
     * - 若 _root.同屏打击数字特效上限 未初始化，使用 DEFAULT_CAPACITY (25)
     * - 若 _root.当前打击数字特效总数 未初始化，使用 DEFAULT_CURRENT (0)
     * - 若 _root.gameworld 不存在，直接清空队列返回
     *
     * 【调用时机】
     * 应在 frameEnd 事件中调用，确保所有 enqueueRaw 完成后统一处理。
     */
    public static function flush():Void {
        var n:Number = _length;
        if (n == 0) return;

        var r:Object = _root;

        // === 阶段1：全局开关预读 + 短路 ===
        if (!r.是否打击数字特效) {
            if (debugMode) {
                r.服务器.发布服务器消息(
                    "[HitNumberBatch] global:OFF, normal:" + n + " 全部丢弃"
                );
            }
            __resetQueue();
            return;
        }

        // === 阶段2：视野剔除准备 ===
        var gameWorld:MovieClip = r.gameworld;
        if (!gameWorld) {
            __resetQueue();
            return;
        }

        var sx:Number = gameWorld._xscale * 0.01;
        var gx:Number = gameWorld._x;
        var gy:Number = gameWorld._y;
        var sw:Number = Stage.width;
        var sh:Number = Stage.height;

        // === 阶段2.5：C# overlay 路径 ===
        // socket 连接时，序列化 hn 数据写入 FrameBroadcaster 数据槽
        // cam 广播 + 消息发送由 FrameBroadcaster.send() 统一处理
        if (r.server.isSocketConnected) {
            var buf:String = "";
            var shown2:Number = 0;
            var i:Number;
            var x:Number;
            var y:Number;
            var locX:Number;
            var locY:Number;

            i = 0;
            do {
                x = _xs[i];
                y = _ys[i];
                locX = gx + x * sx;
                locY = gy + y * sx;
                if (locX < 0 || locX > sw || locY < 0 || locY > sh) {
                    // 视口外，跳过
                } else {
                    if (buf.length > 0) buf += ";";
                    buf += _values[i] + "|" + x + "|" + y + "|" + _packed[i] + "|";
                    buf += safeField(_efTexts[i]) + "|";
                    buf += safeField(_efEmojis[i]) + "|";
                    buf += _efLifeSteals[i] + "|" + _efShieldAbsorbs[i];
                    ++shown2;
                }
            } while (++i < n);

            // 写入 FrameBroadcaster 数据槽（不直接发送消息）
            FrameBroadcaster.setHnPayload(buf);

            if (debugMode) {
                r.服务器.发布服务器消息(
                    "[HitNumberBatch] C# path: shown:" + shown2 + "/" + n
                );
            }
            __resetQueue();
            return;
        }

        // === 阶段3：Flash fallback 路径（原有逻辑）===
        // 获取全局控制参数（带防御性处理）
        var capacityBase:Number = r.同屏打击数字特效上限;
        if (isNaN(capacityBase) || capacityBase <= 0) {
            capacityBase = DEFAULT_CAPACITY;
        }

        var current:Number = r.当前打击数字特效总数;
        if (isNaN(current) || current < 0) {
            current = DEFAULT_CURRENT;
        }

        var remaining:Number = capacityBase - current;
        if (remaining < 0) remaining = 0;

        var quota:Number = (remaining >= n) ? n : remaining;

        var shown:Number = 0;
        var culled:Number = 0;
        var dropped:Number = 0;

        i = 0;
        do {
            x = _xs[i];
            y = _ys[i];

            // 视野剔除
            locX = gx + x * sx;
            locY = gy + y * sx;
            if (locX < 0 || locX > sw || locY < 0 || locY > sh) {
                ++culled;
            } else if (shown < quota) {
                // 配额内：构建 HTML 并渲染
                var html:String = buildHtml(
                    Number(_values[i]), _packed[i],
                    _efTexts[i], _efEmojis[i],
                    _efLifeSteals[i], _efShieldAbsorbs[i]
                );
                HitNumberSystem.spawn("", html, x, y);
                ++shown;
            } else {
                // 配额已满，剩余项不再逐个遍历
                dropped = n - shown - culled;
                break;
            }
        } while (++i < n);

        // === 阶段4：调试输出 ===
        if (debugMode) {
            r.服务器.发布服务器消息(
                "[HitNumberBatch] shown:" + shown + "/" + n +
                "(剔除" + culled + ",丢弃" + dropped + ")"
            );
        }

        // === 阶段5：重置队列 ===
        __resetQueue();
    }

    /**
     * 从 packed Number + 标量槽构建完整 HTML 字符串
     *
     * 仅在 flush 存活项上调用，被 culling/quota 丢弃的项永远不执行此函数。
     *
     * packed 编码：
     *   bits 0-8:   _efFlags（9 bits）
     *   bit  9:     isMISS
     *   bits 10-17: damageSize（0-255）
     *   bits 18-21: colorId（0-15）
     *
     * @param damage       伤害数值
     * @param packed       打包的离散状态
     * @param efText       效果属性文本（可为 null）
     * @param efEmoji      破击 emoji（可为 null）
     * @param lifeSteal    吸血量
     * @param shieldAbsorb 盾吸收量
     * @return 完整的 HTML 格式字符串
     */
    public static function buildHtml(
        damage:Number, packed:Number,
        efText:String, efEmoji:String,
        lifeSteal:Number, shieldAbsorb:Number
    ):String {
        // 解包离散状态
        var flags:Number    = packed & 511;         // bits 0-8
        var isMISS:Boolean  = ((packed >> 9) & 1) != 0;
        var size:Number     = (packed >> 10) & 255; // bits 10-17
        var colorId:Number  = (packed >> 18) & 15;  // bits 18-21

        // 构建主伤害数字（fontStart 内联：避免热路径函数调用开销）
        var key:Number = (colorId << 8) | size;
        var fontStart:String = _fontStartCache[key];
        if (fontStart == undefined) {
            fontStart = '<font color="' + COLOR_TABLE[colorId] + '" size="' + size + '">';
            _fontStartCache[key] = fontStart;
        }
        // MISS 判断：全局 dodgeStatus=="MISS"（packed bit 9）或 单弹丸 damage<0（联弹分段建模）
        var html:String;
        if (isMISS || damage < 0) {
            html = fontStart + "MISS" + FONT_END;
        } else {
            html = fontStart + (damage | 0) + FONT_END;
        }

        // 无效果快速路径
        if (flags == 0) return html;

        // 按处理链执行顺序拼接效果片段
        // （Universal → NanoToxic → LifeSteal → Crumble → Execute → Shield）
        // bit 3: EF_DMG_TYPE_LABEL（Universal - 颜色 = damageColor，文本 = efText）
        if ((flags & 8) != 0) {
            html += '<font color="' + COLOR_TABLE[colorId] + '" size="20"> ' + efText + FONT_END;
        }
        // bit 4: EF_CRUSH_LABEL（Universal - 固定色 #66bcf5，emoji + text）
        if ((flags & 16) != 0) {
            html += FRAG_CRUSH_PRE + efEmoji + efText + FONT_END;
        }
        // bit 1: EF_TOXIC（NanoToxic）
        if ((flags & 2) != 0) {
            html += FRAG_TOXIC;
        }
        // bit 5: EF_LIFESTEAL（LifeSteal）
        if ((flags & 32) != 0) {
            html += FRAG_LIFESTEAL_PRE + lifeSteal + FONT_END;
        }
        // bit 0: EF_CRUMBLE（Crumble）
        if ((flags & 1) != 0) {
            html += FRAG_CRUMBLE;
        }
        // bit 2: EF_EXECUTE（Execute - bit 7 isEnemy 选择颜色）
        if ((flags & 4) != 0) {
            html += ((flags & 128) != 0) ? FRAG_EXECUTE_ENEMY : FRAG_EXECUTE_ALLY;
        }
        // bit 8: EF_SHIELD
        if ((flags & 256) != 0) {
            html += FRAG_SHIELD_PRE + shieldAbsorb + FONT_END;
        }

        return html;
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
        _length = 0;
    }

    /**
     * 清空队列（场景切换/重启时调用）
     */
    public static function clear():Void {
        __resetQueue();
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
