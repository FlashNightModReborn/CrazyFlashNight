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

    // ==================== 屏幕尺寸 ====================

    private static var SCREEN_W:Number = 800;
    private static var SCREEN_H:Number = 600;

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
        if (_gradientLayer) {
            _gradientLayer.clear();
            _gradientLayer._visible = false;
        }
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

        _gradientLayer.beginFill(color, a);
        _gradientLayer.moveTo(0, 0);
        _gradientLayer.lineTo(SCREEN_W, 0);
        _gradientLayer.lineTo(SCREEN_W, SCREEN_H);
        _gradientLayer.lineTo(0, SCREEN_H);
        _gradientLayer.lineTo(0, 0);
        _gradientLayer.endFill();
    }
}
