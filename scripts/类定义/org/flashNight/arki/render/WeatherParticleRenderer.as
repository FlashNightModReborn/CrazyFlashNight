/**
 * WeatherParticleRenderer.as
 * 位于：org.flashNight.arki.render
 *
 * 天气粒子渲染器 - 在 gameworld 内使用 Drawing API 渲染雨/雪/沙尘粒子。
 *
 * 设计要点：
 * - 容器挂在 gameworld 内前景深度（32768），被 UI 自然遮盖
 * - 粒子使用世界空间坐标，跟随场景卷屏
 * - 生成区域根据当前可视窗口 + 卷屏偏移动态计算
 * - 雨滴到达地面（Ymax 附近）时生成溅射效果
 * - 平行数组存储粒子数据，避免对象属性查找开销
 * - 订阅 frameEnd 事件实现逐帧更新
 *
 * @class WeatherParticleRenderer
 */
import org.flashNight.neur.Event.EventBus;

class org.flashNight.arki.render.WeatherParticleRenderer {

    // ==================== 状态 ====================

    /** 渲染容器（gameworld 内前景层） */
    private static var _container:MovieClip;

    /** 是否激活 */
    private static var _active:Boolean = false;

    /** 天气类型 "rain" | "snow" | "dust" | "none" */
    private static var _type:String = "none";

    /** 天气强度 0.0~1.0 */
    private static var _intensity:Number = 0;

    /** 当前性能等级 0-3 */
    private static var _performanceLevel:Number = 0;

    /** 是否已初始化 */
    private static var _initialized:Boolean = false;

    // ==================== 雨滴平行数组 ====================

    private static var _px:Array;    // 世界 X
    private static var _py:Array;    // 世界 Y
    private static var _vx:Array;    // X 速度
    private static var _vy:Array;    // Y 速度
    private static var _life:Array;  // 剩余生命帧
    private static var _size:Array;  // 粒子尺寸
    private static var _depth:Array; // 纵深 0.0(远)~1.0(近)，影响大小/透明度/落点Y
    private static var _count:Number = 0;

    // ==================== 溅射平行数组 ====================

    private static var _spX:Array;      // 溅射世界 X
    private static var _spY:Array;      // 溅射世界 Y
    private static var _spLife:Array;   // 溅射剩余帧
    private static var _spMax:Array;    // 溅射总帧数（用于计算进度）
    private static var _spCount:Number = 0;
    private static var MAX_SPLASHES:Number = 20;

    // ==================== 性能配置 ====================

    /** 各性能等级对应的最大粒子数 [L0, L1, L2, L3]，按天气类型区分 */
    // 雨：每粒子 1 次 lineStyle + moveTo + lineTo，中等开销
    private static var MAX_RAIN_BY_LEVEL:Array = [80, 50, 30, 0];
    // 雪：每粒子 1 次 lineStyle + moveTo + lineTo（短点），低开销，可以更多
    private static var MAX_SNOW_BY_LEVEL:Array = [400, 250, 120, 0];
    // 沙尘：圆点，中等开销
    private static var MAX_DUST_BY_LEVEL:Array = [60, 40, 20, 0];

    /** 获取当前天气类型在当前性能等级下的最大粒子数 */
    private static function _getMaxParticles():Number {
        var lv:Number = _performanceLevel;
        if (_type == "snow") return MAX_SNOW_BY_LEVEL[lv];
        if (_type == "dust") return MAX_DUST_BY_LEVEL[lv];
        return MAX_RAIN_BY_LEVEL[lv];
    }

    /** 屏幕基准尺寸（无缩放时） */
    private static var BASE_W:Number = 800;
    private static var BASE_H:Number = 600;

    // ==================== 地图边界约束 ====================

    /** 地图边界（世界坐标，已含余量） */
    private static var _bndLeft:Number;
    private static var _bndRight:Number;
    private static var _bndBottom:Number;
    private static var _hasBounds:Boolean = false;

    /** 边界余量像素（部分地图碰撞箱较小，需额外扩展） */
    private static var BOUNDS_MARGIN:Number = 150;

    /** 当前帧的缩放补偿（渲染时用于保持屏幕视觉大小恒定） */
    private static var _renderScale:Number = 1;

    // ==================== sin LUT（雪花水平摆动） ====================

    private static var _sinLUT:Array;
    private static var SIN_LUT_SIZE:Number = 64;

    // ==================== 生命周期 ====================

    /**
     * 初始化渲染器：订阅 frameEnd + 初始化 LUT。
     * 容器在每帧 update 中延迟创建（需等 gameworld 存在）。
     */
    public static function initialize():Void {
        if (_initialized) return;

        // 初始化 sin LUT
        _sinLUT = [];
        var step:Number = (Math.PI * 2) / SIN_LUT_SIZE;
        for (var i:Number = 0; i < SIN_LUT_SIZE; i++) {
            _sinLUT[i] = Math.sin(i * step);
        }

        // 初始化平行数组
        _px = []; _py = []; _vx = []; _vy = []; _life = []; _size = []; _depth = [];
        _spX = []; _spY = []; _spLife = []; _spMax = [];
        _count = 0;
        _spCount = 0;

        // 订阅 frameEnd
        EventBus.getInstance().subscribe("frameEnd", update, null);

        _initialized = true;
    }

    /**
     * 清理渲染器状态（场景切换时调用）。
     * 不移除容器（gameworld 被 removeMovieClip 时容器自动销毁）。
     */
    public static function dispose():Void {
        _active = false;
        _count = 0;
        _spCount = 0;
        _type = "none";
        _intensity = 0;
        _container = null; // gameworld 销毁后引用失效，下次 update 重建
        _hasBounds = false;
    }

    /**
     * 设置性能等级（由 PerformanceActuator 调用）。
     * @param level 0-3
     */
    public static function setPerformanceLevel(level:Number):Void {
        _performanceLevel = level;
        if (level >= 3) {
            // L3：暂停渲染但不清除天气状态（_type/_intensity 保留）
            _active = false;
            _count = 0;
            _spCount = 0;
            if (_container) _container.clear();
        } else {
            // 从 L3 恢复：如果之前有天气设置，重新激活
            if (!_active && _type != "none" && _intensity > 0) {
                _active = true;
            }
            var maxP:Number = _getMaxParticles();
            if (_count > maxP) _count = maxP;
        }
    }

    // ==================== 天气控制 ====================

    /**
     * 设置天气类型和强度。
     * 仅存储参数，不立即激活粒子。需在 SceneReady 后调用
     * activateWithBounds() 传入地图边界才会开始渲染。
     * @param type "rain" | "snow" | "dust" | "none"
     * @param intensity 0.0~1.0
     */
    public static function setWeather(type:String, intensity:Number):Void {
        if (type == "none" || type == undefined || intensity <= 0) {
            _active = false;
            _type = "none";
            _intensity = 0;
            _count = 0;
            _spCount = 0;
            if (_container) _container.clear();
            return;
        }
        _type = type;
        _intensity = intensity;
        // 不立即激活，等待 activateWithBounds() 调用
        _count = 0;
        _spCount = 0;
    }

    /**
     * 设置地图边界并激活粒子系统。
     * 在 SceneReady 事件后调用，此时碰撞箱已绘制完毕。
     * 内部自动添加 BOUNDS_MARGIN(150px) 余量，应对碰撞箱偏小的地图。
     * @param xmin 地图左边界（_root.Xmin）
     * @param xmax 地图右边界（_root.Xmax）
     * @param ymin 地图上边界（_root.Ymin）
     * @param ymax 地图下边界（_root.Ymax）
     */
    public static function activateWithBounds(xmin:Number, xmax:Number, ymin:Number, ymax:Number):Void {
        _bndLeft = xmin - BOUNDS_MARGIN;
        _bndRight = xmax + BOUNDS_MARGIN;
        _bndBottom = ymax + BOUNDS_MARGIN;
        _hasBounds = true;
        if (_type != "none" && _intensity > 0) {
            _active = true;
        }
    }

    // ==================== 逐帧更新 ====================

    public static function update():Void {
        if (!_active) return;

        var maxP:Number = _getMaxParticles();
        if (maxP <= 0) return;

        // 延迟创建容器（等 gameworld 就绪）
        var gw:MovieClip = _root.gameworld;
        if (!gw) return;
        if (!_container || _container._parent == undefined) {
            // 前景深度 32768，在效果层(32767)之上，被 UI 自然遮盖
            _container = gw.createEmptyMovieClip("__weatherParticles", 32768);
            _global.ASSetPropFlags(gw, ["__weatherParticles"], 1, false);
        }

        // 计算当前可视区域（世界坐标），适配运镜缩放
        // gwScale>1 放大（可视面积缩小），gwScale<1 缩小（可视面积增大）
        var gwScale:Number = gw._xscale / 100;
        if (gwScale <= 0.01) gwScale = 1;
        var invScale:Number = 1 / gwScale;
        var viewW:Number = Stage.width * invScale;
        var viewH:Number = Stage.height * invScale;
        // 边距：屏幕外扩展一圈，避免卷屏/缩放时边缘突然出现粒子
        var MARGIN:Number = 100 * invScale;
        var gwx:Number = gw._x * invScale;
        var gwy:Number = gw._y * invScale;
        var viewLeft:Number = -gwx - MARGIN;
        var viewTop:Number = -gwy - MARGIN;
        var viewRight:Number = -gwx + viewW + MARGIN;
        var viewBottom:Number = -gwy + viewH;

        // 地图边界裁切：粒子不超出碰撞箱 + 余量范围
        if (_hasBounds) {
            if (viewLeft < _bndLeft) viewLeft = _bndLeft;
            if (viewRight > _bndRight) viewRight = _bndRight;
            if (viewBottom > _bndBottom) viewBottom = _bndBottom;
        }

        // 地面 Y 范围（2.5D 纵深：Ymin=远处，Ymax=近处）
        var groundYmin:Number = _root.Ymin;
        var groundYmax:Number = _root.Ymax;
        if (isNaN(groundYmin) || groundYmin <= 0) groundYmin = viewBottom - 200;
        if (isNaN(groundYmax) || groundYmax <= 0) groundYmax = viewBottom;

        // 目标粒子数：按可视面积与基准面积的比值缩放
        // 放大时可视面积小 → 粒子更少；缩小时可视面积大 → 粒子更多（有上限）
        var areaRatio:Number = (viewW * viewH) / (BASE_W * BASE_H);
        if (areaRatio > 2) areaRatio = 2; // 缩小时不超过 2 倍
        var targetCount:Number = Math.floor(maxP * _intensity * areaRatio);
        if (targetCount < 1) targetCount = 1;

        // ---- 更新现有粒子 ----
        var i:Number;
        for (i = _count - 1; i >= 0; i--) {
            _px[i] += _vx[i];
            _py[i] += _vy[i];
            _life[i]--;

            // 雪花摆动
            if (_type == "snow") {
                _px[i] += _sinLUT[(_life[i] & (SIN_LUT_SIZE - 1))] * 0.5;
            }

            var remove:Boolean = false;

            // 每个粒子有自己的落地 Y（基于纵深）
            var particleGroundY:Number = groundYmin + _depth[i] * (groundYmax - groundYmin);

            // 到达地面 → 生成溅射（仅雨）
            if (_py[i] >= particleGroundY) {
                if (_type == "rain" && _spCount < MAX_SPLASHES) {
                    _spX[_spCount] = _px[i];
                    _spY[_spCount] = particleGroundY;
                    _spLife[_spCount] = 8;
                    _spMax[_spCount] = 8;
                    _spCount++;
                }
                remove = true;
            }

            // 超出可视区域（含边距）或生命耗尽
            if (!remove && (_life[i] <= 0 || _px[i] < viewLeft - 20 || _px[i] > viewRight + 20 || _py[i] > viewBottom + 50)) {
                remove = true;
            }

            if (remove) {
                // swap-and-pop
                _count--;
                if (i < _count) {
                    _px[i] = _px[_count];
                    _py[i] = _py[_count];
                    _vx[i] = _vx[_count];
                    _vy[i] = _vy[_count];
                    _life[i] = _life[_count];
                    _size[i] = _size[_count];
                    _depth[i] = _depth[_count];
                }
            }
        }

        // ---- 更新溅射 ----
        for (i = _spCount - 1; i >= 0; i--) {
            _spLife[i]--;
            if (_spLife[i] <= 0) {
                _spCount--;
                if (i < _spCount) {
                    _spX[i] = _spX[_spCount];
                    _spY[i] = _spY[_spCount];
                    _spLife[i] = _spLife[_spCount];
                    _spMax[i] = _spMax[_spCount];
                }
            }
        }

        // ---- 生成新粒子 ----
        // 雪需要更高生成率来填充（单粒子渲染成本低）
        var spawnPerFrame:Number = (_type == "snow") ? 15 : 3;

        // 如果粒子数远低于目标（<30%），批量填充并随机散布在整个可视区
        // 消除"一波波"的现象
        var fillThreshold:Number = Math.floor(targetCount * 0.3);
        var scatterFill:Boolean = (_count < fillThreshold);

        while (_count < targetCount && spawnPerFrame > 0) {
            _spawn(_count, viewLeft, viewRight, viewTop);
            // 散布模式：随机分布在整个可视高度，并给随机的已消耗生命
            if (scatterFill) {
                _py[_count] = viewTop + Math.random() * (viewBottom - viewTop);
                _life[_count] = Math.floor(Math.random() * _life[_count]);
                if (_life[_count] < 2) _life[_count] = 2;
            }
            _count++;
            spawnPerFrame--;
        }

        // ---- 渲染（invScale 补偿缩放，保持屏幕视觉大小恒定） ----
        _renderScale = invScale;
        _container.clear();
        if (_type == "rain") {
            _renderRain();
            _renderSplashes();
        } else if (_type == "snow") {
            _renderSnow();
        } else if (_type == "dust") {
            _renderDust();
        }
    }

    // ==================== 内部方法 ====================

    /**
     * 在指定索引生成新粒子（世界坐标）。
     * depth 决定纵深位置：0=远处(Ymin)，1=近处(Ymax)。
     * 远处的粒子更小、更慢，近处的更大、更快，产生透视感。
     */
    private static function _spawn(idx:Number, vLeft:Number, vRight:Number, vTop:Number):Void {
        // 纵深：随机 0~1
        var d:Number = Math.random();
        _depth[idx] = d;

        // 纵深缩放系数：远处 0.5，近处 1.2
        var scale:Number = 0.5 + d * 0.7;

        // 在可视区域上方随机位置生成
        _px[idx] = vLeft + Math.random() * (vRight - vLeft);
        _py[idx] = vTop - 10 - Math.random() * 40;

        if (_type == "rain") {
            _vx[idx] = (-1 - Math.random() * 2) * scale;
            _vy[idx] = (12 + Math.random() * 6) * scale;
            _life[idx] = 60 + Math.floor(Math.random() * 30);
            _size[idx] = (10 + Math.random() * 5) * scale;
        } else if (_type == "snow") {
            _vx[idx] = (-0.5 + Math.random() * 1) * scale;
            _vy[idx] = (2 + Math.random() * 3) * scale;
            _life[idx] = 90 + Math.floor(Math.random() * 50);
            _size[idx] = (1.5 + Math.random() * 2) * scale;
        } else {
            _vx[idx] = (-0.5 + Math.random() * 1) * scale;
            _vy[idx] = (0.5 + Math.random() * 1.5) * scale;
            _life[idx] = 100 + Math.floor(Math.random() * 50);
            _size[idx] = (1 + Math.random() * 1) * scale;
        }
    }

    /** 渲染雨：浅蓝色倾斜线段，远处更淡更细 */
    private static function _renderRain():Void {
        // 粒子在世界空间保持固定大小，跟随 gameworld 缩放自然变化
        for (var i:Number = 0; i < _count; i++) {
            var x:Number = _px[i];
            var y:Number = _py[i];
            var len:Number = _size[i];
            var d:Number = _depth[i];
            var alpha:Number = 20 + d * 30;
            var w:Number = (1 + d * 1.5);
            _container.lineStyle(w, 0xAABBDD, alpha);
            _container.moveTo(x, y);
            _container.lineTo(x + _vx[i] * (len / 15), y + len);
        }
    }

    /** 渲染溅射：落地时短暂的水平扩散弧线 */
    private static function _renderSplashes():Void {
        // 粒子在世界空间保持固定大小，跟随 gameworld 缩放自然变化
        for (var i:Number = 0; i < _spCount; i++) {
            var x:Number = _spX[i];
            var y:Number = _spY[i];
            var progress:Number = 1 - (_spLife[i] / _spMax[i]);
            var radius:Number = (3 + progress * 6);
            var alpha:Number = 50 * (1 - progress);

            _container.lineStyle(1, 0xCCDDEE, alpha);
            _container.moveTo(x - radius, y);
            _container.curveTo(x, y - radius * 0.3, x + radius, y);
        }
    }

    /** 渲染雪：白色圆点，尺寸随缩放补偿保持屏幕恒定 */
    private static function _renderSnow():Void {
        // 粒子在世界空间保持固定大小，跟随 gameworld 缩放自然变化
        _container.lineStyle();
        for (var i:Number = 0; i < _count; i++) {
            var x:Number = _px[i];
            var y:Number = _py[i];
            var r:Number = _size[i];
            var alpha:Number = 30 + _depth[i] * 45;
            _container.beginFill(0xFFFFFF, alpha);
            _container.moveTo(x + r, y);
            _container.curveTo(x + r, y + r, x, y + r);
            _container.curveTo(x - r, y + r, x - r, y);
            _container.curveTo(x - r, y - r, x, y - r);
            _container.curveTo(x + r, y - r, x + r, y);
            _container.endFill();
        }
    }

    /** 渲染沙尘：黄棕色微粒，远处更淡 */
    private static function _renderDust():Void {
        // 粒子在世界空间保持固定大小，跟随 gameworld 缩放自然变化
        _container.lineStyle();
        for (var i:Number = 0; i < _count; i++) {
            var x:Number = _px[i];
            var y:Number = _py[i];
            var r:Number = _size[i];
            var alpha:Number = 20 + _depth[i] * 25;
            _container.beginFill(0xAA8844, alpha);
            _container.moveTo(x + r, y);
            _container.curveTo(x + r, y + r, x, y + r);
            _container.curveTo(x - r, y + r, x - r, y);
            _container.curveTo(x - r, y - r, x, y - r);
            _container.curveTo(x + r, y - r, x + r, y);
            _container.endFill();
        }
    }
}
