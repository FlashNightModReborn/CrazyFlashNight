/**
 * GameWorldOverlayRenderer.as
 * 位于：org.flashNight.arki.render
 *
 * gameworld 内前景色调叠加渲染器 - 用于室内氛围灯光、毒气、警报等效果。
 *
 * 与 SkyboxRenderer 的区别：
 * - SkyboxRenderer 挂在 _root.天空盒（gameworld 后面），室内不可见
 * - 本渲染器挂在 gameworld 内部（depth 32769，在天气粒子之上），室内外均可用
 *
 * 设计要点：
 * - 半透明色块覆盖当前可视区域，逐帧跟随相机
 * - 目标颜色 + alpha 通过 lerp 平滑过渡
 * - 订阅 frameEnd 事件实现逐帧更新
 * - 性能等级 L3 时自动禁用
 *
 * @class GameWorldOverlayRenderer
 */
import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.render.GameWorldOverlayRenderer {

    // ==================== 渲染层 ====================

    /** 叠加层容器（gameworld 内，depth 32769） */
    private static var _container:MovieClip;

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

    /** lerp 速度 */
    private static var _lerpSpeed:Number = 0.05;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    /** 是否需要重绘 */
    private static var _dirty:Boolean = false;

    /** 渲染模式："flat"(均匀色块) | "radial"(径向光源) */
    private static var _mode:String = "flat";

    /** 静态复用 Matrix */
    private static var _gradMatrix:Object;

    /** H11: Math.sin 缓存引用（脉冲每帧调用） */
    private static var _msin:Function = Math.sin;

    // ==================== 脉冲闪烁 ====================

    private static var _pulseEnabled:Boolean = false;
    private static var _pulseSpeed:Number = 0.08;
    private static var _pulseMin:Number = 5;
    private static var _pulseMax:Number = 20;
    private static var _pulsePhase:Number = 0;
    /** 脉冲基准 alpha（setOverlay 传入的值，脉冲在此基础上调制） */
    private static var _baseAlpha:Number = 0;

    // ==================== 生命周期 ====================

    /**
     * 初始化：订阅 frameEnd。
     * 容器在 update 中延迟创建（需等 gameworld 存在）。
     */
    public static function initialize():Void {
        if (_initialized) return;
        EventBus.getInstance().subscribe("frameEnd", update, null);
        _initialized = true;
    }

    /**
     * 清理状态（场景切换时调用）。
     */
    public static function dispose():Void {
        _currentR = 0; _currentG = 0; _currentB = 0; _currentAlpha = 0;
        _targetR = 0; _targetG = 0; _targetB = 0; _targetAlpha = 0;
        _dirty = false;
        _container = null;
        _pulseEnabled = false;
        _pulsePhase = 0;
        _baseAlpha = 0;
        _mode = "flat";
    }

    /**
     * 设置性能等级（由 PerformanceActuator 调用）。
     * @param level 0-3
     */
    public static function setPerformanceLevel(level:Number):Void {
        _perfEnabled = (level < 3);
        if (level == 0) _lerpSpeed = 0.05;
        else if (level == 1) _lerpSpeed = 0.08;
        else _lerpSpeed = 0.15;

        if (!_perfEnabled && _container) {
            _container.clear();
            _container._visible = false;
        }
    }

    // ==================== 色调控制 ====================

    /**
     * 设置目标色调叠加。
     * @param r     红色分量 0-255
     * @param g     绿色分量 0-255
     * @param b     蓝色分量 0-255
     * @param alpha 透明度 0-100
     */
    public static function setOverlay(r:Number, g:Number, b:Number, alpha:Number):Void {
        _targetR = r;
        _targetG = g;
        _targetB = b;
        _baseAlpha = alpha;
        _targetAlpha = alpha;
        if (_targetAlpha > 100) _targetAlpha = 100;
        _dirty = true;
    }

    /**
     * 设置脉冲闪烁参数（警报灯效果）。
     * @param enabled   是否启用脉冲
     * @param speed     脉冲速度（弧度/帧，0.08 ≈ 2.4秒周期）
     * @param minAlpha  最低 alpha
     * @param maxAlpha  最高 alpha
     */
    public static function setPulse(enabled:Boolean, speed:Number, minAlpha:Number, maxAlpha:Number):Void {
        _pulseEnabled = enabled;
        if (enabled) {
            _pulseSpeed = speed;
            _pulseMin = minAlpha;
            _pulseMax = maxAlpha;
            _pulsePhase = 0;
            _dirty = true;
        }
    }

    /**
     * 设置渲染模式。
     * @param mode "flat" 均匀色块 | "radial" 径向光源（中心亮边缘暗）
     */
    public static function setMode(mode:String):Void {
        _mode = mode;
        if (_currentAlpha > 0) _dirty = true;
    }

    /**
     * 清除色调叠加（淡出到透明，同时关闭脉冲）。
     */
    public static function clearOverlay():Void {
        _targetR = 0;
        _targetG = 0;
        _targetB = 0;
        _targetAlpha = 0;
        _baseAlpha = 0;
        _pulseEnabled = false;
        _dirty = true;
    }

    // ==================== 逐帧更新 ====================

    public static function update():Void {
        if (!_perfEnabled) return;

        // 脉冲模式：用 sin 调制目标 alpha
        if (_pulseEnabled) {
            _targetAlpha = _pulseMin + (_pulseMax - _pulseMin) * (0.5 + 0.5 * _msin(_pulsePhase));
            _pulsePhase += _pulseSpeed;
            _dirty = true;
        }

        // lerp current → target（仅在颜色未收敛时执行）
        if (_dirty) {
            var speed:Number = _lerpSpeed;
            _currentR += (_targetR - _currentR) * speed;
            _currentG += (_targetG - _currentG) * speed;
            _currentB += (_targetB - _currentB) * speed;
            _currentAlpha += (_targetAlpha - _currentAlpha) * speed;

            // 收敛检测
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
        }

        // 重绘：只要 overlay 可见就每帧执行（跟随相机滚动）
        // _dirty 仅控制颜色 lerp，不控制重绘频率
        _redraw();
    }

    // ==================== 内部方法 ====================

    private static function _redraw():Void {
        var a:Number = _currentAlpha;

        // 延迟创建容器
        var gw:MovieClip = _root.gameworld;
        if (!gw) return;
        if (!_container || _container._parent == undefined) {
            _container = gw.createEmptyMovieClip("__gwOverlay", 32769);
            _global.ASSetPropFlags(gw, ["__gwOverlay"], 1, false);
        }

        // H01: 容器引用局部化（后续 10+ 次 Drawing API 调用）
        var c:MovieClip = _container;

        if (a <= 0.5) {
            c._visible = false;
            c.clear();
            return;
        }

        c._visible = true;
        c.clear();

        // 计算可视区域（gameworld 本地坐标系）
        var gwScale:Number = gw._xscale / 100;
        if (gwScale < 0.01) gwScale = 1;
        var inv:Number = 1 / gwScale;

        var x0:Number = -gw._x * inv;
        var y0:Number = -gw._y * inv;
        var x1:Number = x0 + Stage.width * inv;
        var y1:Number = y0 + Stage.height * inv;

        var cr:Number = Math.round(_currentR);
        var cg:Number = Math.round(_currentG);
        var cb:Number = Math.round(_currentB);
        var color:Number = (cr << 16) | (cg << 8) | cb;

        var w:Number = x1 - x0;
        var h:Number = y1 - y0;

        if (_mode === "radial") {
            // 径向光源：中心亮（alpha*1.8）→ 边缘暗（alpha*0.3）
            // 产生"光源照射"感而非均匀色块
            if (!_gradMatrix) _gradMatrix = new flash.geom.Matrix();
            _gradMatrix.createGradientBox(w, h, 0, x0, y0);
            var centerA:Number = a * 1.8;
            if (centerA > 100) centerA = 100;
            var edgeA:Number = a * 0.3;
            c.beginGradientFill("radial", [color, color], [centerA, edgeA], [0, 255], _gradMatrix);
        } else {
            c.beginFill(color, a);
        }
        c.moveTo(x0, y0);
        c.lineTo(x1, y0);
        c.lineTo(x1, y1);
        c.lineTo(x0, y1);
        c.lineTo(x0, y0);
        c.endFill();
    }
}
