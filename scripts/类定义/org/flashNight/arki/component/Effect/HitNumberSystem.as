import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * HitNumberSystem
 * ----------------
 * 打击伤害数字系统（静态类）
 *
 * 【公共 API】
 * - spawn(): 底层渲染，由 HitNumberBatchProcessor.flush() 调用
 * - initPool(): 初始化对象池
 *
 * 【数据存储】
 * 继续使用全局存储位置，保持与 SWF 时间轴脚本兼容：
 *   - _root.gameworld.可用数字池（池存储）
 *   - _root.gameworld._hitNumProto（原型存储）
 *   - _root.当前打击数字特效总数（权威计数，由 SWF 时间轴末帧 -= 1）
 *   - POSITION_OFFSET（坐标偏移量）
 *
 * 【初始化时机】
 * - initPool() 在 SceneChanged 事件中调用，确保每个场景开始时池已就绪
 * - spawn() 热路径不再做 null 检查
 *
 * 【坐标偏移职责】
 * - 偏移仅在 acquireClip() 中施加一次
 * - createClip() 不再施加偏移，接收的坐标即最终坐标
 *
 * @version 5.0 - 移除遗留 effect() 入口，spawn/initPool 为唯一公共 API
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
     * 播放一次打击数字特效（底层渲染）
     *
     * 直接操作池逻辑，不做任何节流判断。
     * 由 HitNumberBatchProcessor.flush() 调用。
     *
     * @param ctrl  控制字符串（SWF 时间轴用于 switch 分支，正常显示传空串即可）
     * @param value 已格式化的 HTML 字符串
     * @param x     世界坐标 X
     * @param y     世界坐标 Y
     */
    public static function spawn(ctrl:String, value:Object, x:Number, y:Number):Void {
        var r:Object = _root;
        var gw:MovieClip = r.gameworld;
        if (!gw) return;

        // 获取或创建数字对象
        var clip:MovieClip = acquireClip(ctrl, value, x, y);

        // 更新全局计数（权威计数）
        r.当前打击数字特效总数++;
    }

    /**
     * 初始化对象池
     *
     * 在 SceneChanged 事件中调用，确保场景开始时池已就绪。
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
            clip.数字 = value;
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
        if (!gw._hitNumProto) {
            gw._hitNumProto = createClip(ctrl, value, x, y);
            _global.ASSetPropFlags(gw, ["_hitNumProto"], 1, false);
            gw._hitNumProto._visible = false;
        }

        // 从原型复制
        var effectLayer:MovieClip = gw.效果;
        var depth:Number = effectLayer.getNextHighestDepth();
        var clip:MovieClip = gw._hitNumProto.duplicateMovieClip(
            ctrl + " " + depth, depth
        );

        clip.控制字符串 = ctrl;
        clip._x = x;
        clip._y = y;
        clip.数字 = value;
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

        var clip:MovieClip = effectLayer.attachMovie(
            LINKAGE_NAME,
            LINKAGE_NAME + " " + depth,
            depth,
            {
                _x: x,
                _y: y,
                数字: value,
                控制字符串: ctrl
            }
        );

        // 绑定 onUnload 回调，更新全局计数
        clip.onUnload = function() {
            _root.当前打击数字特效总数--;
        };

        return clip;
    }
}
