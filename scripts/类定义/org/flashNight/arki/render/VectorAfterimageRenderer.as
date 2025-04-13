import flash.geom.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.ObjectPool;

/**
 * 矢量残影渲染器（极致复用版）
 * 
 * 此版本通过单一对象池管理所有画布，并在取用时根据指定的残影数量(shadowCount)
 * 对画布进行初始化（包括计算残影持续时间、指数衰减因子、刷新间隔等参数），
 * 实现不同配置间的极致复用与高效资源利用，同时保留与旧接口的兼容性。
 * 
 * 功能特性：
 * 1. 支持矢量图形(MovieClip)和自定义路径(Array)两种残影渲染模式
 * 2. 单一对象池管理所有画布，支持多种残影配置动态切换
 * 3. 每个画布在获取时根据指定的残影数量自动计算配置参数（残影持续时间、衰减因子、刷新间隔）
 * 4. 智能画布复用：同一配置下若存在当前活跃画布则优先复用，降低对象池访问次数
 * 5. 渐隐动画完成后自动回收画布资源，确保内存和性能最优
 * 6. 与原有接口兼容，默认残影数量可通过 configureSystem/setShadowCount 动态调整
 * 
 * 使用示例：
 * // 使用默认残影数量绘制多边形残影
 * VectorAfterimageRenderer.instance.drawShape(
 *     [{x:0, y:0}, {x:50, y:30}, {x:30, y:50}],
 *     0xFF0000, 0x00FF00, 2, 80, 100
 * );
 * 
 * // 指定残影数量为8来绘制多边形残影
 * VectorAfterimageRenderer.instance.drawShape(
 *     [{x:0, y:0}, {x:50, y:30}, {x:30, y:50}],
 *     0xFF0000, 0x00FF00, 2, 80, 100, 8
 * );
 *
 * // 复制 MovieClip 并添加残影效果，使用默认残影数量
 * VectorAfterimageRenderer.instance.drawClip(mc, {brightness:20});
 *
 * // 场景切换时调用 onSceneChanged 重置所有内部状态和对象池
 * _root.帧计时器.eventBus.subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged, VectorAfterimageRenderer.instance);
 */
class org.flashNight.arki.render.VectorAfterimageRenderer {

    // ==================== 静态配置常量 ====================
    
    /** 默认残影数量（初始默认值，建议3-10） */
    private static var DEFAULT_SHADOW_COUNT:Number = 5;
    
    /** 基础透明度（0-100） */
    private static var BASE_ALPHA:Number = 100;
    
    /** 单例实例 */
    public static var instance:VectorAfterimageRenderer = new VectorAfterimageRenderer();

    // ==================== 成员变量 ====================
    
    /** 单一对象池，管理所有 MovieClip 画布 */
    private var _canvasPool:ObjectPool;
    
    /**
     * 当前活跃画布集合（以 shadowCount 为键），记录各配置下正在使用的画布，
     * 用于智能复用（同一配置下优先复用已有画布）。
     */
    private var _currentCanvasByConfig:Object;
    
    /**
     * 配置参数字典，键为各残影数量(shadowCount)配置，
     * 值为 { shadowDuration, decayFactor, refreshInterval } 对象
     */
    private var _config:Object;
    
    /** 默认残影数量，当调用接口时未传入 shadowCount 则使用该值 */
    private var _defaultShadowCount:Number;
    
    
    // ==================== 构造函数 ====================
    
    /**
     * 构造函数 - 初始化默认配置并创建共享对象池
     */
    public function VectorAfterimageRenderer() {
        _defaultShadowCount = DEFAULT_SHADOW_COUNT;
        _config = {};
        // 预先计算默认配置参数
        var frameDuration:Number = _root.帧计时器.每帧毫秒;
        var shadowDuration:Number = frameDuration * _defaultShadowCount;
        var decayFactor:Number = Math.pow(0.01, 1 / _defaultShadowCount);
        var refreshInterval:Number = shadowDuration / (_defaultShadowCount * _defaultShadowCount);
        _config[_defaultShadowCount] = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
        initCanvasPool();
    }
    
    // ==================== 对象池初始化 ====================
    
    /**
     * 初始化画布对象池
     * 使用单一对象池管理所有画布，父级容器为 _root.gameworld.deadbody
     */
    private function initCanvasPool():Void {
        var self = this;
        _canvasPool = new ObjectPool(
            // createFunc：创建新的 MovieClip 画布
            function(parent:MovieClip):MovieClip {
                var mc:MovieClip = parent.createEmptyMovieClip("canvas_" + getTimer(), parent.getNextHighestDepth());
                return mc;
            },
            // resetFunc：本例不作特殊重置，取用后会通过 initializeCanvas 手动初始化
            function():Void {},
            // releaseFunc：释放画布时的自定义清理函数
            function():Void {
                if (this.fadeTask) {
                    _root.帧计时器.移除任务(this.fadeTask);
                }
                this._visible = false;
                if (this.clear != undefined) {
                    this.clear();
                }
            },
            // 父级影片剪辑，用于创建画布的容器
            _root.gameworld.deadbody,
            // 对象池最大容量
            30,
            // 预加载对象数量
            5,
            // 是否启用懒加载
            true,
            // 是否启用原型模式（不启用，因为每个画布需独立初始化渐隐任务）
            false,
            // 额外参数
            []
        );
        _currentCanvasByConfig = {};
    }
    
    // ==================== 系统配置方法 ====================
    
    /**
     * 配置默认残影数量
     * @param shadowCount 默认残影数量，后续绘制调用时若未指定则使用该值（建议3-10）
     */
    public function configureSystem(shadowCount:Number):Void {
        _defaultShadowCount = shadowCount;
        if (_config[shadowCount] == undefined) {
            var frameDuration:Number = _root.帧计时器.每帧毫秒;
            var shadowDuration:Number = frameDuration * shadowCount;
            var decayFactor:Number = Math.pow(0.01, 1 / shadowCount);
            var refreshInterval:Number = shadowDuration / (shadowCount * shadowCount);
            _config[shadowCount] = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
        }
    }
    
    /**
     * 动态调整默认残影数量
     * @param newShadowCount 新的默认残影数量配置（建议3-10），此参数只影响后续创建的画布，
     *                       已经在渐隐过程中的画布继续采用原有配置完成动画
     */
    public function setShadowCount(newShadowCount:Number):Void {
        configureSystem(newShadowCount);
    }
    
    // ==================== 残影绘制方法 ====================
    
    /**
     * 绘制矢量形状残影
     * @param points 顶点数组（至少包含3个点），格式：[{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param shadowCount (可选) 残影数量配置，不传则使用默认值
     */
    public function drawShape(points:Array, fillColor:Number, lineColor:Number, 
                               lineWidth:Number, fillAlpha:Number, lineAlpha:Number, shadowCount:Number):Void {
        if (!points || points.length < 3) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        renderShape(canvas, points, fillColor, fillAlpha);
    }
    
    /**
     * 绘制混合形状（部分边直线，部分边曲线）
     * @param points 顶点数组（至少包含3个点），格式：[{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param closePath 是否闭合图形（默认 true）
     * @param shadowCount (可选) 残影数量配置，不传则使用默认值
     */
    public function drawMixedShape(points:Array,
                                   fillColor:Number,
                                   lineColor:Number,
                                   lineWidth:Number,
                                   fillAlpha:Number,
                                   lineAlpha:Number,
                                   closePath:Boolean,
                                   shadowCount:Number):Void {
        if (!points || points.length < 3) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        canvas.moveTo(points[0].x, points[0].y);
        canvas.lineTo(points[1].x, points[1].y);
        var len:Number = points.length;
        for (var i:Number = 1; i < len - 2; i++) {
            var curr:Object = points[i];
            var next:Object = points[i+1];
            var cpx:Number = (curr.x + next.x) / 2;
            var cpy:Number = (curr.y + next.y) / 2;
            canvas.curveTo(curr.x, curr.y, cpx, cpy);
        }
        canvas.lineTo(points[len - 1].x, points[len - 1].y);
        if (closePath == undefined || closePath == true) {
            canvas.lineTo(points[0].x, points[0].y);
        }
        canvas.endFill();
    }
    
    /**
     * 复制 MovieClip 并生成残影效果
     * @param source 源 MovieClip 对象
     * @param colorParams 颜色调整参数（依赖色彩引擎格式）
     * @param shadowCount (可选) 残影数量配置，不传则使用默认值
     */
    public function drawClip(source:MovieClip, colorParams:Object, shadowCount:Number):Void {
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        var adjustedColor:ColorTransform = _root.色彩引擎.初级调整颜色(source, colorParams);
        renderMovieClip(source, canvas, adjustedColor);
    }
    
    // ==================== 状态重置方法 ====================
    
    /**
     * 重置渲染器状态（用于场景切换或手动重置）
     * 清空所有对象池中画布及当前活跃画布，避免内存泄漏，并重新初始化父容器下的新对象池
     */
    public function onSceneChanged():Void {
        if (_canvasPool != undefined) {
            _canvasPool.clearPool();
        }
        _currentCanvasByConfig = {};
        initCanvasPool();
    }
    
    /**
     * 重置渲染器，与 onSceneChanged 效果一致
     */
    public function reset():Void {
        onSceneChanged();
    }
    
    // ==================== 画布生命周期管理与复用 ====================
    
    /**
     * 根据指定的残影数量，从对象池中获取一个可用画布，并初始化其状态
     * @param shadowCount 需要使用的残影数量配置
     * @return 初始化后的 MovieClip 画布
     */
    private function getAvailableCanvas(shadowCount:Number):MovieClip {
        if (_currentCanvasByConfig[shadowCount] != undefined && _currentCanvasByConfig[shadowCount] != null) {
            return _currentCanvasByConfig[shadowCount];
        }
        var canvas:MovieClip = _canvasPool.getObject();
        initializeCanvas(canvas, shadowCount);
        _currentCanvasByConfig[shadowCount] = canvas;
        return canvas;
    }
    
    /**
     * 初始化画布，将其配置为指定残影数量，设置初始属性及渐隐任务
     * @param canvas 目标 MovieClip 画布对象
     * @param shadowCount 指定的残影数量配置
     */
    private function initializeCanvas(canvas:MovieClip, shadowCount:Number):Void {
        canvas._visible = true;
        canvas._alpha = BASE_ALPHA;
        canvas.cycleCount = 0;
        canvas.shadowCount = shadowCount;
        
        // 获取或生成当前配置的参数
        var configObj:Object = _config[shadowCount];
        if (configObj == undefined) {
            var frameDuration:Number = _root.帧计时器.每帧毫秒;
            var shadowDuration:Number = frameDuration * shadowCount;
            var decayFactor:Number = Math.pow(0.01, 1 / shadowCount);
            var refreshInterval:Number = shadowDuration / (shadowCount * shadowCount);
            configObj = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
            _config[shadowCount] = configObj;
        }
        
        // 移除之前可能存在的渐隐任务
        if (canvas.fadeTask) {
            _root.帧计时器.移除任务(canvas.fadeTask);
        }
        // 添加渐隐任务，通过 Delegate 绑定 onFadeUpdate 方法，并传入当前配置的刷新间隔
        var callback:Function = Delegate.create(this, onFadeUpdate);
        canvas.fadeTask = _root.帧计时器.添加任务(callback, configObj.refreshInterval, shadowCount, canvas);
    }
    
    /**
     * 渐隐动画回调
     * 每次调用更新画布透明度，并根据配置判断是否完成渐隐回收
     * @param canvas 当前正在渐隐的 MovieClip 画布对象
     */
    private function onFadeUpdate(canvas:MovieClip):Void {
        var configObj:Object = _config[canvas.shadowCount];
        // 若画布仍是当前活跃画布，则首次渐隐时解除绑定（允许后续绘制获取新画布）
        if (canvas.cycleCount == 0 && _currentCanvasByConfig[canvas.shadowCount] == canvas) {
            _currentCanvasByConfig[canvas.shadowCount] = null;
        }
        canvas.cycleCount++;
        if (canvas.cycleCount >= canvas.shadowCount) {
            recycleCanvas(canvas);
        } else {
            canvas._alpha = Math.round(canvas._alpha * configObj.decayFactor);
            if (canvas._alpha <= 0) {
                recycleCanvas(canvas);
            }
        }
    }
    
    /**
     * 回收画布，将其从当前使用中移除，并放回对象池或销毁（当池已满时）
     * @param canvas 需要回收的 MovieClip 画布对象
     */
    private function recycleCanvas(canvas:MovieClip):Void {
        if (canvas.__isDestroyed) return; // 防止重复回收
        _root.帧计时器.移除任务(canvas.fadeTask);
        canvas._visible = false;
        if (canvas.clear != undefined) {
            canvas.clear();
        }
        if (_currentCanvasByConfig[canvas.shadowCount] == canvas) {
            _currentCanvasByConfig[canvas.shadowCount] = null;
        }
        if (_canvasPool.isPoolFull()) {
            _canvasPool.releaseObject(canvas);
        } else {
            canvas.__isDestroyed = true;
            canvas.removeMovieClip();
        }
    }
    
    // ==================== 工具方法 ====================
    
    /**
     * 设置画布的绘制样式，例如线条宽度、颜色及透明度
     * @param canvas 目标 MovieClip 画布对象
     * @param lineColor 线条颜色（RGB）
     * @param lineWidth 线条宽度（像素）
     * @param lineAlpha 线条透明度（0-100）
     */
    private function setupCanvasStyle(canvas:MovieClip, lineColor:Number, lineWidth:Number, lineAlpha:Number):Void {
        canvas.lineStyle(lineWidth || 1, lineColor || 0xFF0000, lineAlpha || 100);
    }
    
    /**
     * 绘制填充形状
     * @param canvas 目标 MovieClip 画布对象
     * @param points 顶点数组（格式：[{x:Number, y:Number}, ...]）
     * @param fillColor 填充颜色（RGB）
     * @param fillAlpha 填充透明度（0-100）
     */
    private function renderShape(canvas:MovieClip, points:Array, fillColor:Number, fillAlpha:Number):Void {
        var len:Number = points.length;
        if (len < 2) return;
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        var i:Number = 1;
        var p0:Object = points[0];
        canvas.moveTo(p0.x, p0.y);
        do {
            var p:Object = points[i % len];
            canvas.lineTo(p.x, p.y);
            i++;
        } while (i <= len);
        canvas.endFill();
    }
    
    /**
     * 复制 MovieClip 并生成残影效果
     * 同时应用源对象的变换矩阵与颜色变换
     * @param source 源 MovieClip 对象
     * @param canvas 目标 MovieClip 画布对象
     * @param colorTransform 颜色变换对象
     */
    private function renderMovieClip(source:MovieClip, canvas:MovieClip, colorTransform:ColorTransform):Void {
        canvas.clear();
        var ghost:MovieClip = duplicateClip(source, canvas);
        applyTransformation(source, ghost);
        if (colorTransform) {
            ghost.transform.colorTransform = colorTransform;
        }
    }
    
    /**
     * 复制 MovieClip 实例
     * @param source 源 MovieClip 对象
     * @param canvas 父级画布对象
     * @return 复制后的 MovieClip 实例
     */
    private function duplicateClip(source:MovieClip, canvas:MovieClip):MovieClip {
        var depth:Number = canvas.getNextHighestDepth();
        var ghostName:String = "ghost_" + depth;
        source.duplicateMovieClip(ghostName, depth);
        return canvas[ghostName];
    }
    
    /**
     * 应用变换矩阵，将源 MovieClip 的位置和缩放应用到目标 MovieClip，
     * 不含旋转等其它变换（如有需要可进行扩展）
     * @param source 源 MovieClip 对象
     * @param target 目标 MovieClip 对象
     */
    private function applyTransformation(source:MovieClip, target:MovieClip):Void {
        var matrix:Matrix = calculateCumulativeMatrix(source);
        target._x = matrix.tx;
        target._y = matrix.ty;
        target._xscale = source._xscale;
        target._yscale = source._yscale;
    }
    
    /**
     * 计算从当前 MovieClip 到根容器 _root.gameworld.deadbody 的累积变换矩阵
     * @param target 起始 MovieClip 对象
     * @return 累积后的 Matrix 对象
     */
    private function calculateCumulativeMatrix(target:MovieClip):Matrix {
        var matrix:Matrix = new Matrix();
        var current:MovieClip = target;
        while (current && current != _root.gameworld.deadbody) {
            matrix.concat(current.transform.matrix);
            current = current._parent;
        }
        return matrix;
    }
}
