import flash.geom.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.ObjectPool;  // 引入对象池框架

/**
 * 矢量残影渲染器 - 为动态对象创建平滑渐隐的拖尾/残影效果（经过对象池优化）
 * 
 * 功能特性：
 * 1. 支持矢量图形(MovieClip)和自定义路径(Array)两种渲染模式
 * 2. 使用对象池管理机制优化性能，减少频繁创建和销毁 MovieClip 的开销
 * 3. 可配置的残影数量/透明度/持续时间参数
 * 4. 自动渐隐动画与资源回收，并通过对象池实现高效的资源重用
 * 5. 场景切换时主动重置对象池，防止由于父级容器丢失而引起的错误
 *
 * 使用示例：
 * // 绘制多边形残影
 * VectorAfterimageRenderer.instance.drawShape(
 *     [{x:0, y:0}, {x:50, y:30}, {x:30, y:50}], 
 *     0xFF0000, 0x00FF00, 2, 80, 100
 * );
 * 
 * // 复制 MovieClip 并添加残影
 * VectorAfterimageRenderer.instance.drawClip(mc, {brightness:20});
 *
 * // 在场景切换时调用 onSceneChanged 重置内部状态和对象池
 * _root.帧计时器.eventBus.subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged, VectorAfterimageRenderer.instance);
 * 
 * 动态调整接口说明：
 * 该接口允许在运行时调整残影数量，新创建的画布会按照最新配置生效，而
 * 已在渐隐任务中的画布继续使用原有配置完成渐隐，确保视觉平滑过渡与性能稳定。
 */
class org.flashNight.arki.render.VectorAfterimageRenderer {

    // ==================== 静态配置常量 ====================
    
    /** 默认残影数量（初始默认值） */
    private static var DEFAULT_SHADOW_COUNT:Number = 5;
    
    /** 帧间隔基数（控制残影间距） */
    private static var FRAME_INTERVAL:Number = 1;
    
    /** 基础透明度（0-100） */
    private static var BASE_ALPHA:Number = 100;

    /** 单例实例 */
    public static var instance:VectorAfterimageRenderer = new VectorAfterimageRenderer();
    

    // ==================== 成员变量 ====================
    
    /** 画布对象池，用于管理可重用的 MovieClip 画布 */
    private var _canvasPool:ObjectPool;
    
    /** 当前活跃画布（最新绘制、尚未开始渐隐的画布） */
    private var _currentCanvas:MovieClip;
    
    /** 残影总持续时间（毫秒） */
    private var _shadowDuration:Number;
    
    /** 指数衰减因子 */
    private var decayFactor:Number;
    
    /** 渐隐刷新间隔（毫秒） */
    private var _refreshInterval:Number;
    
    /** 当前残影数量 */
    private var _shadowCount:Number;
    

    // ==================== 构造函数 ====================
    
    /**
     * 构造函数 - 初始化渲染系统，并创建画布对象池
     */
    public function VectorAfterimageRenderer() {
        // 使用默认残影数量初始化系统参数
        configureSystem(DEFAULT_SHADOW_COUNT, FRAME_INTERVAL);
        // 初始化画布对象池，父级容器为 _root.gameworld.deadbody
        initCanvasPool();
    }
    
    // ==================== 对象池初始化 ====================
    
    /**
     * 初始化画布对象池，使用 ObjectPool 框架管理 MovieClip 画布的创建与复用
     * 注意：父级容器使用 _root.gameworld.deadbody
     */
    private function initCanvasPool():Void {
        var self = this;
        // 创建一个新的对象池，管理画布(MovieClip)的创建、重置和释放
        _canvasPool = new ObjectPool(
            // createFunc：创建新画布的函数
            function(parent:MovieClip):MovieClip {
                // 从父级容器创建一个空的 MovieClip
                var mc:MovieClip = parent.createEmptyMovieClip("canvas_" + getTimer(), parent.getNextHighestDepth());
                return mc;
            },
            // resetFunc：重置画布的函数，在获取对象时调用，this 指向被重置的画布
            function():Void {
                // 将画布设置为可见并初始化属性
                this._visible = true;
                this._alpha = VectorAfterimageRenderer.BASE_ALPHA;
                this.cycleCount = 0;
                // 移除之前可能存在的渐隐任务
                if (this.fadeTask) {
                    _root.帧计时器.移除任务(this.fadeTask);
                }
                // 设置渐隐任务
                var callback:Function = Delegate.create(self, self.onFadeUpdate);
                this.fadeTask = _root.帧计时器.添加任务(callback, self._refreshInterval, self._shadowCount, this);
            },
            // releaseFunc：释放画布时的自定义清理函数
            function():Void {
                // 移除渐隐任务，并清理画布状态
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
            // 对象池的最大容量
            30,
            // 预加载对象的数量
            5,
            // 是否启用懒加载模式
            true,
            // 是否启用原型模式（此处不启用，因为每个画布需要独立处理渐隐任务）
            false,
            // 原型初始化所需的额外参数（无）
            []
        );
    }
    
    // ==================== 系统配置方法 ====================
    
    /**
     * 配置系统核心参数
     * @param shadowCount 残影数量（建议3-10）
     * @param frameInterval 帧间隔系数（值越大残影间距越大）
     */
    public function configureSystem(shadowCount:Number, frameInterval:Number):Void {
        _shadowCount = shadowCount;
        var frameDuration:Number = _root.帧计时器.每帧毫秒;
        _shadowDuration = frameDuration * shadowCount * frameInterval;
        
        // 计算指数衰减因子
        decayFactor = Math.pow(0.01, 1 / _shadowCount);
        _refreshInterval = _shadowDuration / (shadowCount * shadowCount);
        
        // 更新对象池的最大容量为残影数量的两倍，确保足够的缓冲
        var newMaxPoolSize:Number = Math.ceil(_shadowCount * 2);
        _canvasPool.setPoolCapacity(newMaxPoolSize);
    }
    
    /**
     * 动态调整残影数量
     * @param newShadowCount 新的残影数量配置（建议3-10）
     * @note 此方法只影响后续创建的画布，已经在渐隐中的画布仍使用原有配置完成渐隐
     */
    public function setShadowCount(newShadowCount:Number):Void {
        configureSystem(newShadowCount, FRAME_INTERVAL);
    }
    
    // ==================== 残影绘制方法 ====================
    
    /**
     * 绘制矢量形状残影
     * @param points 顶点数组（至少3个点），格式 [{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     */
    public function drawShape(points:Array, fillColor:Number, lineColor:Number, 
                               lineWidth:Number, fillAlpha:Number, lineAlpha:Number):Void {
        if (!points || points.length < 3) return;
        var canvas:MovieClip = getAvailableCanvas();
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        renderShape(canvas, points, fillColor, fillAlpha);
    }
    
    /**
     * 绘制“混合”形状：部分边使用 lineTo，部分边使用 curveTo
     * @param points 顶点数组（至少3个点），格式 [{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param closePath 是否闭合图形（默认 true，将最后一点与第一点连接）
     */
    public function drawMixedShape(points:Array,
                                   fillColor:Number,
                                   lineColor:Number,
                                   lineWidth:Number,
                                   fillAlpha:Number,
                                   lineAlpha:Number,
                                   closePath:Boolean):Void {
        if (!points || points.length < 3) return;
        var canvas:MovieClip = getAvailableCanvas();
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
     * @param source 源 MovieClip
     * @param colorParams 颜色变换参数（依赖色彩引擎的格式）
     */
    public function drawClip(source:MovieClip, colorParams:Object):Void {
        var canvas:MovieClip = getAvailableCanvas();
        var adjustedColor:ColorTransform = _root.色彩引擎.初级调整颜色(source, colorParams);
        renderMovieClip(source, canvas, adjustedColor);
    }
    
    // ==================== 状态重置方法 ====================
    
    /**
     * 重置渲染器（场景切换时调用）
     * 清空对象池和当前引用，避免内存泄漏，同时重新初始化对象池，
     * 因为在游戏中切换 gameworld 时，父级容器会发生变化。
     */
    public function onSceneChanged():Void {
        // 清空当前的对象池及其所有画布
        if (_canvasPool != undefined) {
            _canvasPool.clearPool();
        }
        _currentCanvas = null;
        // 重新初始化对象池，确保使用新的父级容器 _root.gameworld.deadbody
        initCanvasPool();
    }
    
    /**
     * 重置渲染器（与 reset 方法效果相同，可用于手动重置状态）
     */
    public function reset():Void {
        // 调用 onSceneChanged 以清空旧对象池和画布
        onSceneChanged();
    }
    
    // ==================== 核心渲染逻辑 ====================
    
    /**
     * 渲染 MovieClip 到目标画布
     * @private
     * @param source 源对象
     * @param canvas 目标画布
     * @param colorTransform 颜色变换对象
     */
    private function renderMovieClip(source:MovieClip, canvas:MovieClip, 
                                     colorTransform:ColorTransform):Void {
        canvas.clear();
        var ghost:MovieClip = duplicateClip(source, canvas);
        applyTransformation(source, ghost);
        if (colorTransform) {
            ghost.transform.colorTransform = colorTransform;
        }
    }
    
    /**
     * 复制 MovieClip 实例
     * @private
     * @param source 源对象
     * @param canvas 父级画布
     * @return 复制后的 MovieClip 实例
     */
    private function duplicateClip(source:MovieClip, canvas:MovieClip):MovieClip {
        var depth:Number = canvas.getNextHighestDepth();
        var ghostName:String = "ghost_" + depth;
        source.duplicateMovieClip(ghostName, depth);
        return canvas[ghostName];
    }
    
    /**
     * 应用变换矩阵到目标对象
     * @private
     * @param source 参考源对象
     * @param target 需要变换的目标对象
     * @note 当前实现仅处理位置和缩放，如需完整变换需改进
     */
    private function applyTransformation(source:MovieClip, target:MovieClip):Void {
        var matrix:Matrix = calculateCumulativeMatrix(source);
        target._x = matrix.tx;
        target._y = matrix.ty;
        target._xscale = source._xscale;
        target._yscale = source._yscale;
    }
    
    /**
     * 计算从目标到根容器的累积变换矩阵
     * @private
     * @param target 起始对象
     * @return 累积变换矩阵
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
    
    // ==================== 画布生命周期管理 ====================
    
    /**
     * 获取可用画布（优先返回当前活跃画布，否则从对象池中获取）
     * @private
     * @return 可用的 MovieClip 画布
     */
    private function getAvailableCanvas():MovieClip {
        if (_currentCanvas != null) return _currentCanvas;
        var canvas:MovieClip = _canvasPool.getObject();
        _currentCanvas = canvas;
        return canvas;
    }
    
    /**
     * 渐隐动画更新回调
     * @private
     * @param canvas 正在渐隐的画布
     */
    private function onFadeUpdate(canvas:MovieClip):Void {
        if (canvas.cycleCount == 0 && _currentCanvas == canvas) {
            _currentCanvas = null;
        }
        if (++canvas.cycleCount >= _shadowCount) {
            recycleCanvas(canvas);
        } else {
            // 使用指数衰减更新透明度
            canvas._alpha = Math.round(canvas._alpha * decayFactor);
            // 当透明度降到 0 或以下时提前回收画布
            if (canvas._alpha <= 0) {
                recycleCanvas(canvas);
            }
        }
    }
    
    /**
     * 回收画布到对象池
     * @private
     * @param canvas 需要回收的画布
     */
    private function recycleCanvas(canvas:MovieClip):Void {
        if (canvas.__isDestroyed) return; // 防止重复回收
        
        _root.帧计时器.移除任务(canvas.fadeTask);
        canvas._visible = false;
        canvas.clear();
        
        // 显式检查池是否已满
        if (_canvasPool.isPoolFull()) {
            _canvasPool.releaseObject(canvas);
        } else {
            canvas.__isDestroyed = true;
            canvas.removeMovieClip();
        }
    }
    
    // ==================== 工具方法 ====================
    
    /**
     * 设置画布绘制样式
     * @private
     * @param canvas 目标画布
     * @param lineColor 线条颜色（RGB）
     * @param lineWidth 线宽（像素）
     * @param lineAlpha 线条透明度（0-100）
     */
    private function setupCanvasStyle(canvas:MovieClip, lineColor:Number, 
                                      lineWidth:Number, lineAlpha:Number):Void {
        canvas.lineStyle(lineWidth || 1, lineColor || 0xFF0000, lineAlpha || 100);
    }
    
    /**
     * 渲染填充形状
     * @private
     * @param canvas 目标画布
     * @param points 顶点数组
     * @param fillColor 填充颜色（RGB）
     * @param fillAlpha 填充透明度（0-100）
     */
    private function renderShape(canvas:MovieClip, points:Array, 
                                 fillColor:Number, fillAlpha:Number):Void {
        var len:Number = points.length;
        if (len < 2) return;
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        var i:Number = 1;
        var p0:Object = points[0];
        canvas.moveTo(p0.x, p0.y);
        do {
            var p:Object = points[i % len];
            canvas.lineTo(p.x, p.y);
        } while (++i <= len);
        canvas.endFill();
    }
}
