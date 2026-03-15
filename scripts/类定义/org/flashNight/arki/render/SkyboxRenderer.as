/**
 * SkyboxRenderer.as
 * 位于：org.flashNight.arki.render
 *
 * 天空盒色彩渲染器 - 在 _root.天空盒 内创建渐变叠加层，
 * 根据时间和天气状态实现色调变化。
 * 订阅 frameEnd 事件，逐帧 lerp 实现平滑过渡。
 *
 * @class SkyboxRenderer
 */
import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.render.SkyboxRenderer {

    // ==================== 渲染层 ====================

    /** 渐变叠加层（_root.天空盒 内 depth=33） */
    private static var _gradientLayer:MovieClip;

    // ==================== 颜色状态 ====================

    private static var _currentR:Number = 0;
    private static var _currentG:Number = 0;
    private static var _currentB:Number = 0;
    private static var _currentAlpha:Number = 0;

    private static var _targetR:Number = 0;
    private static var _targetG:Number = 0;
    private static var _targetB:Number = 0;
    private static var _targetAlpha:Number = 0;

    // ==================== 控制标志 ====================

    /** 性能等级开关（L3 = false） */
    private static var _perfEnabled:Boolean = true;

    /** 天空盒启用状态（室内/禁用天空 = false） */
    private static var _skyEnabled:Boolean = true;

    /** lerp 速度，随性能等级调整 */
    private static var _lerpSpeed:Number = 0.05;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    /** 是否需要重绘（current !== target） */
    private static var _dirty:Boolean = false;

    /** 地面 Y 坐标（root 空间），渐变层不绘制到此值以下，0 = 未设置 */
    private static var _groundY:Number = 0;

    // ==================== 屏幕尺寸 ====================

    // 屏幕尺寸：不再硬编码，_redrawGradient 中直接读 Stage.width/height

    // ==================== 时段色彩表 ====================
    // 每项: [hour, R, G, B, alpha]
    // 相邻项之间线性插值

    private static var _colorTable:Array = [
        // hour, R, G, B, alpha(0-100)
        [0,  10, 10, 46,  60],  // 深夜
        [4,  10, 10, 46,  60],  // 深夜→黎明
        [5, 255,170, 68,  30],  // 黎明
        [7, 255,221,136,  15],  // 日出
        [8,   0,  0,  0,   0],  // 白天开始（透明）
        [16,  0,  0,  0,   0],  // 白天结束（透明）
        [17,255,136, 68,  25],  // 黄昏
        [19,255, 68, 34,  40],  // 日落
        [20, 10, 10, 46,  55],  // 夜晚开始
        [24, 10, 10, 46,  60]   // 午夜（循环回 0）
    ];

    // ==================== 生命周期 ====================

    /**
     * 初始化：创建渐变层 + 订阅 frameEnd。
     */
    public static function initialize():Void {
        if (_initialized) return;

        _createGradientLayer();

        // 订阅 frameEnd
        EventBus.getInstance().subscribe("frameEnd", update, null);

        _initialized = true;
    }

    /**
     * 清理渲染器（场景切换时调用）。
     */
    public static function dispose():Void {
        _currentR = 0; _currentG = 0; _currentB = 0; _currentAlpha = 0;
        _targetR = 0; _targetG = 0; _targetB = 0; _targetAlpha = 0;
        _dirty = false;
        _groundY = 0;
        if (_gradientLayer) {
            _gradientLayer.clear();
            _gradientLayer._visible = false;
        }
    }

    /**
     * 设置地面 Y 坐标（root 空间），渐变层不会绘制到此值以下。
     * 由 WeatherSystem.configureEnvironment 调用，防止地面下方出现色块。
     * @param y root 空间的地面 Y 坐标（通常为 _root.Ymax）
     */
    public static function setGroundY(y:Number):Void {
        _groundY = y;
    }

    /**
     * 设置性能等级（由 PerformanceActuator 调用）。
     * @param level 0-3
     */
    public static function setPerformanceLevel(level:Number):Void {
        _perfEnabled = (level < 3);
        // lerp 速度随等级提升加快（低画质下跳变更快，减少 redraw 次数）
        if (level == 0) _lerpSpeed = 0.05;
        else if (level == 1) _lerpSpeed = 0.08;
        else _lerpSpeed = 0.15;

        if (!_perfEnabled && _gradientLayer) {
            _gradientLayer.clear();
            _gradientLayer._visible = false;
        }
    }

    /**
     * 设置天空盒可见性（由 WeatherSystem.configureEnvironment 调用）。
     * 室内或禁用天空时传 false。
     * @param enabled Boolean
     */
    public static function setSkyEnabled(enabled:Boolean):Void {
        _skyEnabled = enabled;
        if (!enabled && _gradientLayer) {
            _gradientLayer.clear();
            _gradientLayer._visible = false;
        }
    }

    // ==================== 天气/时间驱动 ====================

    /**
     * 设置目标色调（由 WeatherSystem 在 WeatherUpdated 低频事件中调用）。
     * @param timeOfDay 0-24
     * @param weatherCondition "正常" | "雨" | "雪" | "沙尘"
     */
    public static function setTimeAndWeather(timeOfDay:Number, weatherCondition:String):Void {
        // 从时段表插值基础色
        _calcTimeColor(timeOfDay);

        // 天气叠加
        if (weatherCondition == "雨") {
            _targetR = (_targetR + 0x66) >> 1;
            _targetG = (_targetG + 0x66) >> 1;
            _targetB = (_targetB + 0x88) >> 1;
            _targetAlpha += 20;
        } else if (weatherCondition == "沙尘") {
            _targetR = (_targetR + 0xAA) >> 1;
            _targetG = (_targetG + 0x88) >> 1;
            _targetB = (_targetB + 0x44) >> 1;
            _targetAlpha += 25;
        }
        // 雪不额外叠加色调（白色天空由默认天空处理）

        if (_targetAlpha > 100) _targetAlpha = 100;
        _dirty = true;
    }

    // ==================== 逐帧更新 ====================

    /**
     * 每帧调用（frameEnd 订阅）。
     * 仅在 perfEnabled && skyEnabled 时执行 lerp + 重绘。
     */
    public static function update():Void {
        if (!_perfEnabled || !_skyEnabled) return;
        if (!_dirty) return;

        // lerp current → target
        var speed:Number = _lerpSpeed;
        _currentR += (_targetR - _currentR) * speed;
        _currentG += (_targetG - _currentG) * speed;
        _currentB += (_targetB - _currentB) * speed;
        _currentAlpha += (_targetAlpha - _currentAlpha) * speed;

        // 检查是否已收敛（误差 < 1）
        var dr:Number = _targetR - _currentR;
        var dg:Number = _targetG - _currentG;
        var db:Number = _targetB - _currentB;
        var da:Number = _targetAlpha - _currentAlpha;
        if (dr * dr + dg * dg + db * db + da * da < 1) {
            _currentR = _targetR;
            _currentG = _targetG;
            _currentB = _targetB;
            _currentAlpha = _targetAlpha;
            _dirty = false;
        }

        // 重绘
        _redrawGradient();
    }

    // ==================== 内部方法 ====================

    private static function _createGradientLayer():Void {
        var skybox:MovieClip = _root.天空盒;
        if (!skybox) return;
        _gradientLayer = skybox.createEmptyMovieClip("__skyGradient", 33);
        _gradientLayer._visible = false;
    }

    /**
     * 从时段色彩表计算指定时间的目标 RGB + alpha。
     * 相邻时段之间线性插值。
     */
    private static function _calcTimeColor(time:Number):Void {
        var table:Array = _colorTable;
        var len:Number = table.length;

        // 找到 time 所在的区间
        var lo:Number = 0;
        for (var i:Number = 1; i < len; i++) {
            if (table[i][0] > time) {
                lo = i - 1;
                break;
            }
            lo = i;
        }
        var hi:Number = (lo + 1 < len) ? lo + 1 : lo;

        var tLo:Number = table[lo][0];
        var tHi:Number = table[hi][0];
        var t:Number = (tHi > tLo) ? (time - tLo) / (tHi - tLo) : 0;

        _targetR = table[lo][1] + (table[hi][1] - table[lo][1]) * t;
        _targetG = table[lo][2] + (table[hi][2] - table[lo][2]) * t;
        _targetB = table[lo][3] + (table[hi][3] - table[lo][3]) * t;
        _targetAlpha = table[lo][4] + (table[hi][4] - table[lo][4]) * t;
    }

    /**
     * 用 beginFill 绘制纯色半透明矩形覆盖天空盒区域。
     *
     * 坐标空间说明：
     *   渐变层在天空盒本地坐标系中绘制。天空盒有缩放（_yscale）和位移（_y），
     *   需将屏幕可见区域转换到天空盒本地空间。
     *
     *   地面 Y 在天空盒本地空间 = Ymax - 地平线高度（与缩放/相机位置无关），
     *   因为 gameworld 和天空盒共享相同的缩放比例，相机偏移在推导中抵消。
     */
    private static function _redrawGradient():Void {
        if (!_gradientLayer) return;

        var a:Number = _currentAlpha;
        if (a <= 0.5) {
            _gradientLayer._visible = false;
            _gradientLayer.clear();
            return;
        }

        _gradientLayer._visible = true;
        _gradientLayer.clear();

        var r:Number = Math.round(_currentR);
        var g:Number = Math.round(_currentG);
        var b:Number = Math.round(_currentB);
        var color:Number = (r << 16) | (g << 8) | b;

        var sw:Number = Stage.width;
        var sh:Number = Stage.height;

        // 天空盒有缩放和 _y 偏移，将屏幕矩形转换到天空盒本地坐标系
        var parent:MovieClip = _gradientLayer._parent;
        var skyScale:Number = parent._yscale / 100;
        if (skyScale < 0.01) skyScale = 1;
        var invScale:Number = 1 / skyScale;

        var drawTop:Number = -parent._y * invScale;
        var drawRight:Number = sw * invScale;
        var screenBottom:Number = (sh - parent._y) * invScale;
        var drawBottom:Number = screenBottom;

        // 地面裁切：渐变不绘制到地面以下
        // 推导：地面在天空盒本地空间的 Y = Ymax - 地平线高度
        // （gameworld 和天空盒共享缩放比例，相机偏移抵消）
        if (_groundY > 0) {
            var horizonH:Number = parent.地平线高度;
            if (isNaN(horizonH)) horizonH = 0;
            var groundLocal:Number = _groundY - horizonH;
            if (groundLocal < drawBottom) drawBottom = groundLocal;
        }

        // 使用 默认天空 资产的实际边界确定渲染范围
        // 比 gameworld.背景长 推算更准确，直接反映需要遮挡的内容边界
        var sky:MovieClip = parent.默认天空;
        var skyLeft:Number = 0;
        var skyRight:Number = drawRight;
        if (sky && sky._visible) {
            var rect:Object = sky.getRect(parent);
            if (rect.xMin > 0) skyLeft = rect.xMin;
            if (rect.xMax < drawRight) skyRight = rect.xMax;
        }

        // 天空区域：半透明色调叠加（仅覆盖 默认天空 范围内、地面以上）
        // 不需要额外的黑色遮挡层：默认天空 在未被渐变叠加时的自然外观是可接受的
        // （所有非天气地图已验证），色块的根因是渐变画到了不该画的区域
        _gradientLayer.beginFill(color, a);
        _gradientLayer.moveTo(skyLeft, drawTop);
        _gradientLayer.lineTo(skyRight, drawTop);
        _gradientLayer.lineTo(skyRight, drawBottom);
        _gradientLayer.lineTo(skyLeft, drawBottom);
        _gradientLayer.lineTo(skyLeft, drawTop);
        _gradientLayer.endFill();
    }
}
