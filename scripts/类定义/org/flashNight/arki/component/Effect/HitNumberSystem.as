/**
 * HitNumberSystem
 * ----------------
 * 打击伤害数字系统（静态类）
 *
 * 【第二阶段：池逻辑迁移】
 * 将 视觉系统_fs_打击数字池.as 中的核心逻辑迁移到此类中，
 * 脚本文件变为薄封装层。
 *
 * 【数据存储】
 * 继续使用全局存储位置，保持与 SWF 时间轴脚本兼容：
 *   - _root.gameworld.可用数字池（池存储）
 *   - _root.gameworld.打击伤害数字原型（原型存储）
 *   - _root.当前打击数字特效总数（权威计数，由 onUnload 减一）
 *   - _root.打击数字坐标偏离（坐标偏移量）
 *
 * 【节流职责】
 * spawn() 不做任何节流判断，节流由调用方负责：
 *   - HitNumberBatchProcessor.flush() 负责批处理路径的节流
 *   - _root.打击数字特效() 负责直接调用路径的节流
 *
 * @version 3.0 - 池逻辑迁移
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

    // ========================================================================
    // 公共 API
    // ========================================================================

    /**
     * 播放一次打击数字特效
     *
     * 【第二阶段实现】
     * 直接操作池逻辑，不再代理到脚本函数。
     * 节流、视野剔除等决策由调用方（HitNumberBatchProcessor）负责。
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
     * 对应原 _root.初始化打击伤害数字池
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
        var offset:Number = _root.打击数字坐标偏离;

        // 应用坐标偏移
        x += _root.随机偏移(offset);
        y += _root.随机偏移(offset);

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
        var offset:Number = _root.打击数字坐标偏离;

        var clip:MovieClip = effectLayer.attachMovie(
            LINKAGE_NAME,
            LINKAGE_NAME + " " + depth,
            depth,
            {
                _x: x + _root.随机偏移(offset),
                _y: y + _root.随机偏移(offset),
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
        // 字符串直接返回（已格式化的 <font> 标签等）
        if (typeof(value) == "string" && String(value).length > 0) {
            return String(value);
        }
        // 数值转字符串，NaN 显示为 "miss"
        if (isNaN(Number(value))) {
            return "miss";
        }
        return String(Math.floor(Number(value)));
    }
}
