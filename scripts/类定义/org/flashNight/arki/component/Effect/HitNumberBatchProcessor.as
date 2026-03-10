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
 * - 帧末快速重置：负索引区域不清理引用，下帧覆盖写入，移除 O(forceLength) 的 delete 循环
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
 * @version 1.3
 * @author FlashNight
 * ============================================================================
 */

import org.flashNight.sara.util.*;
import org.flashNight.arki.component.Effect.HitNumberSystem;

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

    // ========================================================================
    // raw 路径专用并行数组（延迟 HTML 构建）
    // ========================================================================

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

    /** 普通请求队列长度（正索引区域） */
    private static var _length:Number = 0;

    /** force 请求队列长度（负索引区域，存储为正数，实际索引为 -1 到 -_forceLength） */
    private static var _forceLength:Number = 0;

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

    /**
     * 获取 fontStart 字符串（懒构建，首次拼接后缓存）
     * @param colorId 颜色 ID（0-10）
     * @param size    字体大小（0-255）
     * @return 格式化的 font 开标签
     */
    private static function getFontStart(colorId:Number, size:Number):String {
        var key:Number = (colorId << 8) | size;
        var s:String = _fontStartCache[key];
        if (s == undefined) {
            s = '<font color="' + COLOR_TABLE[colorId] + '" size="' + size + '">';
            _fontStartCache[key] = s;
        }
        return s;
    }

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
     * 将伤害数字显示请求以原始数据形式加入队列（延迟 HTML 构建路径）
     *
     * 与 enqueue 的区别：不传入预格式化的 HTML，而是存储标量快照，
     * flush 先剔除/丢弃后，仅对存活项调用 buildHtml 构建 HTML。
     *
     * 【注意】仅处理普通请求（damage 永远非 force），force 请求仍走 enqueue()。
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
            // 游戏世界不存在，完整清空队列后返回（可能是场景切换中）
            __clearQueueFull();
            return;
        }

        var sx:Number = gameWorld._xscale * 0.01;
        var gx:Number = gameWorld._x;
        var gy:Number = gameWorld._y;
        var sw:Number = Stage.width;
        var sh:Number = Stage.height;

        // 通过 HitNumberSystem 统一 API 入口，便于后续迁移
        // 第一阶段：HitNumberSystem.spawn 内部只是代理到 _root.打击数字特效内部
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

            // 无条件显示 - 通过 HitNumberSystem 统一入口
            HitNumberSystem.spawn(_ctrls[i], _values[i], x, y, true);
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
                    // 判断路径：_packed[i] !== undefined → raw 路径，否则旧路径
                    var p:Number = _packed[i];
                    if (p !== undefined) {
                        // raw 路径：先剔除后构建 HTML，被丢弃的项零 HTML 成本
                        var html:String = buildHtml(
                            Number(_values[i]), p,
                            _efTexts[i], _efEmojis[i],
                            _efLifeSteals[i], _efShieldAbsorbs[i]
                        );
                        HitNumberSystem.spawn("", html, x, y, false);
                    } else {
                        // 旧路径：预格式化 HTML 直接渲染
                        HitNumberSystem.spawn(_ctrls[i], _values[i], x, y, false);
                    }
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

        // === 阶段6：重置队列（快速路径，不清理负索引引用） ===
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

        // 构建主伤害数字
        // MISS 判断：全局 dodgeStatus=="MISS"（packed bit 9）或 单弹丸 damage<0（联弹分段建模）
        var fontStart:String = getFontStart(colorId, size);
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
     * 内部方法：帧末快速重置队列（高频调用路径）
     *
     * 【优化策略】
     * - 负索引区域：不清理引用，仅重置计数器。下帧 enqueue 时直接覆盖写入。
     *   AS2 弱引用特性允许旧值被覆盖，不会导致内存泄漏。
     * - 正索引区域：设置 length = 0 自动回收。
     *
     * 【性能收益】
     * - 移除每帧 4 × forceLength 次 delete 操作
     * - Boss 战等高 force 场景下显著降低 GC 压力
     *
     * 【注意】
     * 场景切换时应调用 clear() 而非此方法，确保完全释放引用。
     */
    private static function __resetQueue():Void {
        // 正索引区域：利用 length = 0 自动回收
        _ctrls.length = 0;
        _values.length = 0;
        _xs.length = 0;
        _ys.length = 0;

        // raw 路径并行数组
        _packed.length = 0;
        _efTexts.length = 0;
        _efEmojis.length = 0;
        _efLifeSteals.length = 0;
        _efShieldAbsorbs.length = 0;

        // 重置计数器（负索引区域下帧覆盖写入，无需清理引用）
        _length = 0;
        _forceLength = 0;
    }

    /**
     * 内部方法：完整清空队列数据（低频调用路径）
     *
     * 【AS2 数组清理机制】
     * AS2 Array 有两类成员：
     * 1. 数组元素（正索引 0,1,2...）：由 length 属性管理
     * 2. 普通属性（负索引 -1,-2... 或字符串键）：不受 length 影响
     *
     * 此方法遍历清理负索引引用，防止场景切换时内存泄漏。
     */
    private static function __clearQueueFull():Void {
        // 清理负索引区域（force 请求）- 场景切换时必须清理
        for (var i:Number = -_forceLength; i < 0; ++i) {
            delete _ctrls[i];
            delete _values[i];
            delete _xs[i];
            delete _ys[i];
        }

        // 清理正索引区域
        _ctrls.length = 0;
        _values.length = 0;
        _xs.length = 0;
        _ys.length = 0;

        // raw 路径并行数组
        _packed.length = 0;
        _efTexts.length = 0;
        _efEmojis.length = 0;
        _efLifeSteals.length = 0;
        _efShieldAbsorbs.length = 0;

        // 重置计数器
        _length = 0;
        _forceLength = 0;
    }

    /**
     * 清空队列（完整清理）
     *
     * 用于场景切换或游戏重启时调用，确保不会有残留请求。
     * 此方法会遍历清理负索引引用，防止内存泄漏。
     */
    public static function clear():Void {
        __clearQueueFull();
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
