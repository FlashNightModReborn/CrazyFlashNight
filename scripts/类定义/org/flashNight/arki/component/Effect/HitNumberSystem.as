import org.flashNight.arki.component.Effect.HitNumberBatchProcessor;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * HitNumberSystem
 * ----------------
 * 打击伤害数字系统（静态类）
 *
 * 【完整迁移】
 * 将 视觉系统_fs_打击数字池.as 中的所有核心逻辑迁移到此类中，
 * 脚本文件变为纯薄封装层。
 *
 * 【公共 API】
 * - effect(): 对外接口，对应原 _root.打击数字特效，转发到批处理队列
 * - spawn(): 底层渲染，由 HitNumberBatchProcessor.flush() 调用
 * - initPool(): 初始化对象池
 *
 * 【数据存储】
 * 继续使用全局存储位置，保持与 SWF 时间轴脚本兼容：
 *   - _root.gameworld.可用数字池（池存储）
 *   - _root.gameworld.打击伤害数字原型（原型存储）
 *   - _root.当前打击数字特效总数（权威计数，由 onUnload 减一）
 *   - POSITION_OFFSET（坐标偏移量）
 *
 * 【节流职责】
 * - effect(): 转发到 HitNumberBatchProcessor.enqueue()，节流由 flush 统一处理
 * - spawn(): 不做节流，由调用方负责
 *
 * @version 4.0 - 完整迁移
 * @author FlashNight
 */
class org.flashNight.arki.component.Effect.HitNumberSystem {

    // ========================================================================
    // 常量
    // ========================================================================

    /** 默认池大小 */
    private static var DEFAULT_POOL_SIZE:Number = 5;

    /** 库中的 MovieClip 链接名 */
    private static var LINKAGE_NAME:String = "打击伤害数字";

    /** 坐标随机偏移量（像素） */
    public static var POSITION_OFFSET:Number = 60;

    /** 随机数引擎单例引用（避免每次调用 getInstance） */
    private static var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();

    // ========================================================================
    // 公共 API
    // ========================================================================

    /**
     * 打击数字特效对外接口
     *
     * 对应原 _root.打击数字特效，所有外部调用应使用此方法。
     * 加入批处理队列，节流由 flush 统一处理。
     *
     * @param ctrl  控制字符串（效果种类，如"暴击"、"能"等）
     * @param value 数值或已格式化的字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @param force 是否强制显示（必然触发）
     */
    public static function effect(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        HitNumberBatchProcessor.enqueue(ctrl, value, x, y, force);
    }

    /**
     * 播放一次打击数字特效（底层渲染）
     *
     * 直接操作池逻辑，不做任何节流判断。
     * 由 HitNumberBatchProcessor.flush() 调用。
     *
     * @param ctrl  控制字符串（效果种类，如"暴击"、"能"等）
     * @param value 数值或已格式化的字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @param force 是否强制显示（此参数保留用于兼容，当前不影响行为）
     */
    public static function spawn(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        var gw:MovieClip = _root.gameworld;
        if (!gw) return;

        // 池初始化检查
        if (gw.可用数字池 == undefined) {
            initPool(DEFAULT_POOL_SIZE);
        }

        // 获取或创建数字对象
        var clip:MovieClip = acquireClip(ctrl, value, x, y);

        // 更新全局计数（权威计数）
        _root.当前打击数字特效总数++;
    }

    /**
     * 初始化对象池
     *
     * 初始化对象池（spawn() 内自动调用，外部一般无需手动调用）
     * 继续使用 _root.gameworld.可用数字池 存储，保持兼容性。
     *
     * @param poolSize 预创建的空闲特效数量
     */
    public static function initPool(poolSize:Number):Void {
        if (isNaN(poolSize) || poolSize < 0) poolSize = DEFAULT_POOL_SIZE;

        var gw:MovieClip = _root.gameworld;
        if (!gw) return;

        gw.可用数字池 = [];
        _root.当前打击数字特效总数 = 0;

        for (var i:Number = 0; i < poolSize; ++i) {
            var clip:MovieClip = createClip("初始化子弹", 0, 0, 0);
            gw.可用数字池.push(clip);
        }

        // 设置为不可枚举
        _global.ASSetPropFlags(gw, ["可用数字池"], 1, false);
    }

    // ========================================================================
    // 私有方法 - 池操作
    // ========================================================================

    /**
     * 从池中获取或创建一个数字对象
     *
     * 对应原 _root.获取可用数字
     *
     * @param ctrl  控制字符串
     * @param value 数值或字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @return 配置好的 MovieClip
     */
    private static function acquireClip(ctrl:String, value:Object, x:Number, y:Number):MovieClip {
        var gw:MovieClip = _root.gameworld;
        var pool:Array = gw.可用数字池;
        var offset:Number = POSITION_OFFSET;

        // 应用坐标偏移
        x += rng.randomOffset(offset);
        y += rng.randomOffset(offset);

        var clip:MovieClip;

        if (pool.length > 0) {
            // 从池中取出
            clip = MovieClip(pool.pop());
            clip.控制字符串 = ctrl;
            clip._x = x;
            clip._y = y;
            clip.数字 = formatValue(value);
            _root.重置色彩(clip);
        } else {
            // 池空，懒加载创建新的
            clip = getOrCreateClip(ctrl, value, x, y);
        }

        clip._visible = true;
        clip.gotoAndPlay(1);

        return clip;
    }

    /**
     * 通过原型复制创建新的数字对象
     *
     * 对应原 _root.获取或创建打击伤害数字
     * 使用原型模式，通过 duplicateMovieClip 快速创建。
     *
     * @param ctrl  控制字符串
     * @param value 数值或字符串
     * @param x     世界坐标 X（已含偏移）
     * @param y     世界坐标 Y（已含偏移）
     * @return 新创建的 MovieClip
     */
    private static function getOrCreateClip(ctrl:String, value:Object, x:Number, y:Number):MovieClip {
        var gw:MovieClip = _root.gameworld;

        // 懒加载创建原型
        if (!gw.打击伤害数字原型) {
            gw.打击伤害数字原型 = createClip(ctrl, value, x, y);
            _global.ASSetPropFlags(gw, ["打击伤害数字原型"], 1, false);
            gw.打击伤害数字原型._visible = false;
        }

        // 从原型复制
        var effectLayer:MovieClip = gw.效果;
        var depth:Number = effectLayer.getNextHighestDepth();
        var clip:MovieClip = gw.打击伤害数字原型.duplicateMovieClip(
            ctrl + " " + depth, depth
        );

        clip.控制字符串 = ctrl;
        clip._x = x;
        clip._y = y;
        clip.数字 = formatValue(value);
        clip._visible = true;
        clip.gotoAndPlay(1);

        return clip;
    }

    /**
     * 直接创建一个新的数字 MovieClip（通过 attachMovie）
     *
     * 对应原 _root.创建打击伤害数字
     * 用于首次创建原型或池初始化。
     *
     * @param ctrl  控制字符串
     * @param value 数值或字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     * @return 新创建的 MovieClip
     */
    private static function createClip(ctrl:String, value:Object, x:Number, y:Number):MovieClip {
        var gw:MovieClip = _root.gameworld;
        var effectLayer:MovieClip = gw.效果;
        var depth:Number = effectLayer.getNextHighestDepth();
        var offset:Number = POSITION_OFFSET;

        var clip:MovieClip = effectLayer.attachMovie(
            LINKAGE_NAME,
            LINKAGE_NAME + " " + depth,
            depth,
            {
                _x: x + rng.randomOffset(offset),
                _y: y + rng.randomOffset(offset),
                数字: formatValue(value),
                控制字符串: ctrl
            }
        );

        // 绑定 onUnload 回调，更新全局计数
        clip.onUnload = function() {
            _root.当前打击数字特效总数--;
        };

        return clip;
    }

    /**
     * 格式化显示值
     *
     * @param value 数值或字符串
     * @return 格式化后的字符串
     */
    private static function formatValue(value:Object):String {
        if (typeof(value) == "string") {
            return (length(value) > 0) ? String(value) : "miss";
        }
        var n:Number = Number(value);
        if (isNaN(n)) return "miss";
        return String(n | 0);
    }
}
