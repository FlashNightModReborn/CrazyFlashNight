// 文件路径: org/flashNight/arki/render/VectorAfterimageRenderer.as
import flash.geom.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.*;

/**
 * 矢量残影渲染器 - 为动态对象创建平滑渐隐的拖尾/残影效果
 * 
 * 功能特性：
 * 1. 支持矢量图形(MovieClip)和自定义路径(Array)两种渲染模式
 * 2. 自动对象池管理优化性能
 * 3. 可配置的残影数量/透明度/持续时间参数
 * 4. 自动渐隐动画与资源回收
 * 5. 场景切换时可通过 onSceneChanged 方法主动重置状态
 * 
 * 使用示例：
 * // 绘制多边形残影
 * VectorAfterimageRenderer.instance.drawShape(
 *     [{x:0,y:0}, {x:50,y:30}, {x:30,y:50}], 
 *     0xFF0000, 0x00FF00, 2, 80, 100
 * );
 * 
 * // 复制MovieClip并添加残影
 * VectorAfterimageRenderer.instance.drawClip(mc, {brightness:20});
 *
 * // 在场景切换时调用 onSceneChanged 重置内部状态
 * _root.帧计时器.eventBus.subscribe("SceneChanged", VectorAfterimageRenderer.instance.onSceneChanged, VectorAfterimageRenderer.instance);
 */
class org.flashNight.arki.render.VectorAfterimageRenderer {

    // ==================== 静态配置常量 ====================
    
    /** 默认残影数量 */
    private static var DEFAULT_SHADOW_COUNT:Number = 5;
    
    /** 帧间隔基数(控制残影间距) */
    private static var FRAME_INTERVAL:Number = 1;
    
    /** 基础透明度(0-100) */
    private static var BASE_ALPHA:Number = 100;
    
    /** 单例实例 */
    public static var instance:VectorAfterimageRenderer = new VectorAfterimageRenderer();
    

    // ==================== 成员变量 ====================
    
    /** 画布对象池(存储可重用的MovieClip) */
    private var _canvasPool:Array;
    
    /** 当前活跃画布(最新绘制未开始渐隐的画布) */
    private var _currentCanvas:MovieClip;
    
    /** 残影总持续时间(毫秒) */
    private var _shadowDuration:Number;
    
    /** 透明度衰减步长 */
    private var _alphaDecay:Number;
    
    /** 渐隐刷新间隔(毫秒) */
    private var _refreshInterval:Number;
    
    /** 当前残影数量 */
    private var _shadowCount:Number;
    

    // ==================== 公共方法 ====================
    
    /**
     * 构造函数 - 初始化渲染系统
     */
    public function VectorAfterimageRenderer() {
        _canvasPool = [];
        configureSystem(DEFAULT_SHADOW_COUNT, FRAME_INTERVAL);
    }
    
    /**
     * 配置系统核心参数
     * @param shadowCount 残影数量(建议3-10)
     * @param frameInterval 帧间隔系数(值越大残影间距越大)
     */
    public function configureSystem(shadowCount:Number, frameInterval:Number):Void {
        _shadowCount = shadowCount;
        var frameDuration:Number = _root.帧计时器.每帧毫秒;
        _shadowDuration = frameDuration * shadowCount * frameInterval;
        _alphaDecay = BASE_ALPHA / shadowCount;
        _refreshInterval = _shadowDuration / (shadowCount * shadowCount);
    }
    
    /**
     * 绘制矢量形状残影
     * @param points 顶点数组(至少3个点)，格式[{x:Number,y:Number},...]
     * @param fillColor 填充色(RGB)
     * @param lineColor 线条色(RGB)
     * @param lineWidth 线宽(像素)
     * @param fillAlpha 填充透明度(0-100)
     * @param lineAlpha 线条透明度(0-100)
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
     * 
     * 假设用法：点集按顺序排列
     *  - 首尾各用直线连接，中间所有段改用二次贝塞尔曲线进行平滑。
     *  - 如果想要更灵活，比如指定哪些段是直线、哪些段是曲线，可进一步扩展。
     *
     * @param points    顶点数组(至少3个点)，格式[{x:Number,y:Number}, ...]
     * @param fillColor 填充色(RGB)
     * @param lineColor 线条色(RGB)
     * @param lineWidth 线宽(像素)
     * @param fillAlpha 填充透明度(0-100)
     * @param lineAlpha 线条透明度(0-100)
     * @param closePath 是否闭合图形（默认true，会把最后一点与第一点连起来）
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
     * 复制MovieClip并生成残影效果
     * @param source 源MovieClip
     * @param colorParams 颜色变换参数(依赖色彩引擎的格式)
     */
    public function drawClip(source:MovieClip, colorParams:Object):Void {
        var canvas:MovieClip = getAvailableCanvas();
        var adjustedColor:ColorTransform = _root.色彩引擎.初级调整颜色(source, colorParams);
        renderMovieClip(source, canvas, adjustedColor);
    }
    
    /**
     * 重置渲染器(场景切换时调用)
     * 清空对象池和当前引用，避免内存泄漏
     */
    public function reset():Void {
        _canvasPool = [];
        _currentCanvas = null;
    }
    
    /**
     * 【新增方法】当场景发生切换时，由外部事件订阅触发调用此方法，
     * 用于重置所有异常保护相关状态，清理内部画布和任务（降低内部防护带来的性能开销）。
     */
    public function onSceneChanged():Void {
        // 清除对象池中的所有画布及其渐隐任务
        for (var i:Number = 0; i < _canvasPool.length; i++) {
            var canvas:MovieClip = _canvasPool[i];
            if (canvas.fadeTask) {
                _root.帧计时器.移除任务(canvas.fadeTask);
            }
            canvas.removeMovieClip();
        }
        _canvasPool = [];
        // 清除当前活跃画布
        if (_currentCanvas) {
            if (_currentCanvas.fadeTask) {
                _root.帧计时器.移除任务(_currentCanvas.fadeTask);
            }
            _currentCanvas.removeMovieClip();
            _currentCanvas = null;
        }
        // 其他需要重置的状态可在此添加...
    }


    // ==================== 核心渲染逻辑 ====================
    
    /**
     * 渲染MovieClip到目标画布
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
     * 复制MovieClip实例
     * @private
     * @param source 源对象
     * @param canvas 父级画布
     * @return 复制的MovieClip实例
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
     * 获取可用画布(优先从对象池获取)
     * @private
     * @return 可用MovieClip画布
     */
    private function getAvailableCanvas():MovieClip {
        if (_currentCanvas) return _currentCanvas;
        
        var canvas:MovieClip = _canvasPool.length ? 
            MovieClip(_canvasPool.pop()) : 
            createNewCanvas();
            
        _currentCanvas = canvas;
        initActiveCanvas(canvas);
        return canvas;
    }
    
    /**
     * 创建新画布
     * @private
     * @return 新创建的MovieClip画布
     */
    private function createNewCanvas():MovieClip {
        var container:MovieClip = _root.gameworld.deadbody;
        return container.createEmptyMovieClip(
            "canvas_" + getTimer(), 
            container.getNextHighestDepth()
        );
    }
    
    /**
     * 初始化活跃画布状态
     * @private
     * @param canvas 需要初始化的画布
     */
    private function initActiveCanvas(canvas:MovieClip):Void {
        if (!canvas) return;
        
        canvas._visible = true;
        canvas._alpha = BASE_ALPHA;
        canvas.cycleCount = 0;
        
        // 设置渐隐任务
        var callback:Function = Delegate.create(this, onFadeUpdate);
        canvas.fadeTask = _root.帧计时器.添加任务(
            callback, 
            _refreshInterval, 
            _shadowCount, 
            canvas
        );
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
            canvas._alpha -= _alphaDecay;
        }
    }
    
    /**
     * 回收画布到对象池
     * @private
     * @param canvas 需要回收的画布
     */
    private function recycleCanvas(canvas:MovieClip):Void {
        _root.帧计时器.移除任务(canvas.fadeTask);
        canvas._visible = false;
        canvas.clear();
        _canvasPool.push(canvas);
    }
    

    // ==================== 工具方法 ====================
    
    /**
     * 设置画布绘制样式
     * @private
     */
    private function setupCanvasStyle(canvas:MovieClip, lineColor:Number, 
                                    lineWidth:Number, lineAlpha:Number):Void {
        canvas.lineStyle(lineWidth || 1, lineColor || 0xFF0000, lineAlpha || 100);
    }
    
    /**
     * 渲染填充形状
     * @private
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
