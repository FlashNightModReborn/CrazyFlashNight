import org.flashNight.sara.util.*;
import org.flashNight.naki.RandomNumberEngine.*;
import org.flashNight.neur.Server.*;

/**
 * HitNumberSystem
 * ----------------
 * 打击伤害数字池（静态类）
 *
 *  · 负责在屏幕上生成、管理并回收“打击伤害数字”特效 MovieClip。
 *  · 采用对象池与原型 (Prototype) 相结合的懒加载策略：
 *      1) 首次调用时创建隐藏的原型影片剪辑；
 *      2) 通过 duplicateMovieClip 复制原型来快速实例化新特效；
 *      3) 使用数组维护简单对象池，回收后复用以减少 GC 与创建开销。
 *  · 提供与旧版 _root 相关函数等价的公开静态接口，方便平滑迁移。
 *
 *  主要公开静态方法：
 *    — initialize(poolSize:Number = 5):Void          初始化对象池，可多次调用（会重置池）。
 *    — spawn(ctrl:String, value:Number|String, x:Number, y:Number, force:Boolean):Void
 *                                               在 (x,y) 位置播放一次打击数字。
 *    — recycle(clip:MovieClip):Void                手动回收（通常由 onUnload 内部调用）。
 *
 *  使用示例：
 *      HitNumberSystem.initialize(10); // 启动并预建 10 个空闲特效
 *      HitNumberSystem.spawn("暴击", 256, target._x, target._y, false);
 */
class org.flashNight.arki.component.Effect.HitNumberSystem {
    // === 可调参数 ===
    private static var _offset:Number = 60;                // 坐标随机偏移上限
    private static var _maxConcurrent:Number = 30;         // 同屏最大显示数量

    // === 内部状态 ===
    private static var _prototype:MovieClip;               // 隐藏原型
    private static var _pool:Array = [];                   // 可用对象池
    private static var _currentCount:Number = 0;           // 当前在场景中的数量
    private static var _initialized:Boolean = false;       // 是否已初始化

    // ==========================
    // 公共 API
    // ==========================

    /**
     * 初始化对象池（可重复调用以重置池）。
     * @param poolSize 预创建的空闲特效数量，默认 5。
     * @param maxConcurrent 同屏最大并发数量，<=0 则不限制。
     */
    public static function initialize(poolSize:Number, maxConcurrent:Number):Void {
        if (isNaN(poolSize) || poolSize < 0) poolSize = 5;
        if (!isNaN(maxConcurrent) && maxConcurrent > 0) _maxConcurrent = maxConcurrent;

        var gw = _root.gameworld;
        if (!gw) return; // 确保游戏世界已建立

        // 清理旧数据
        _pool = [];
        _currentCount = 0;

        // 创建或确保原型存在
        if (!_prototype) {
            _prototype = createPrototype("打击伤害数字", 0, 0, 0);
            _prototype._visible = false;
        }

        // 预填充池
        for (var i:Number = 0; i < poolSize; ++i) {
            var clip:MovieClip = duplicateFromPrototype("预热" + i);
            clip._visible = false;
            _pool.push(clip);
        }

        _initialized = true;
    }

    /**
     * 设置坐标随机偏移量（像素）。
     */
    public static function setOffset(maxOffset:Number):Void {
        _offset = maxOffset;
    }

    /**
     * 设置同屏最大并发数量。<=0 表示不限制。
     */
    public static function setMaxConcurrent(max:Number):Void {
        _maxConcurrent = max;
    }

    /**
     * 播放一次打击数字特效，相当于旧版 _root.打击数字特效。
     * @param ctrl  控制字符串（颜色/样式标记）
     * @param value 数值或字符串 ("miss")
     * @param x     屏幕坐标 X
     * @param y     屏幕坐标 Y
     * @param force 是否无视并发/成功率限制强制播放
     */
    public static function spawn(ctrl:String, value:Object, x:Number, y:Number, force:Boolean):Void {
        // 自动初始化（懒加载）
        if (!_initialized) initialize(5, _maxConcurrent);

        if (!force && _maxConcurrent > 0 && _currentCount >= _maxConcurrent && !_root.成功率(_maxConcurrent / 5)) {
            return; // 命中限制且未通过随机成功率，直接返回
        }

        var gw = _root.gameworld;
        if (!gw) return;

        var clip:MovieClip;
        if (_pool.length > 0) {
            clip = _pool.pop();
        } else {
            clip = duplicateFromPrototype("动态" + gw.效果.getNextHighestDepth());
        }

        // 重新配置属性
        clip.控制字符串 = ctrl;
        clip.数字 = formatValue(value);
        clip._x = x + _root.随机偏移(_offset);
        clip._y = y + _root.随机偏移(_offset);
        _root.重置色彩(clip);

        clip._visible = true;
        clip.gotoAndPlay(1);

        // 统计与回收绑定
        ++_currentCount;
        clip.onUnload = function() { HitNumberSystem.recycle(this); };
    }

    /**
     * 回收到对象池（供外部或 onUnload 回调调用）。
     */
    public static function recycle(clip:MovieClip):Void {
        if (!clip) return;
        clip._visible = false;
        _pool.push(clip);
        --_currentCount;
    }

    // ==========================
    // 内部帮助函数
    // ==========================

    /**
     * 创建隐藏的原型剪辑，用于后续 duplicateMovieClip。
     */
    private static function createPrototype(ctrl:String, value:Object, x:Number, y:Number):MovieClip {
        var gw = _root.gameworld;
        var effectLayer = gw.效果;
        var depth = effectLayer.getNextHighestDepth();
        var proto = effectLayer.attachMovie("打击伤害数字", "HitNumberProto", depth, { _x:x, _y:y });
        proto._visible = false;
        proto.控制字符串 = ctrl;
        proto.数字 = formatValue(value);
        return proto;
    }

    /**
     * 从隐藏原型复制一个新的剪辑实例。
     */
    private static function duplicateFromPrototype(nameSuffix:String):MovieClip {
        var gw = _root.gameworld;
        var effectLayer = gw.效果;
        var depth = effectLayer.getNextHighestDepth();
        var clip:MovieClip = _prototype.duplicateMovieClip("HitNum " + nameSuffix + " " + depth, depth);
        return clip;
    }

    /**
     * 统一格式化数值显示。
     */
    private static function formatValue(val:Object):String {
        if (typeof(val) == "string" && val.length > 0) return val;
        if (isNaN(val)) return "miss";
        return Math.floor(val).toString();
    }
}
