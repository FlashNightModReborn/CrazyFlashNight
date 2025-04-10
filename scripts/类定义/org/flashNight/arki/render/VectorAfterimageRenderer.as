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
        var canvas:MovieClip = getAvailableCanvas();
        if (!points || points.length < 3) return;
        
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
        // 获取可用画布
        var canvas:MovieClip = getAvailableCanvas();
        if (!canvas || !points || points.length < 3) {
            return;
        }
        
        // 设置线条样式
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        // 开始填充
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        
        // 移动到第一个点
        canvas.moveTo(points[0].x, points[0].y);

        // 1) 首段：直接用 lineTo 连到第二个点
        canvas.lineTo(points[1].x, points[1].y);
        
        // 2) 中间段：用二次贝塞尔曲线（curveTo）连接
        //    - 这里的示例做法：从 points[1] 到 points[len-2]，都通过 curveTo 进行光滑过渡
        //    - 给出一种简单的控制点计算方式：使用相邻点的中点或其它插值算法
        var len:Number = points.length;
        var i:Number;
        for (i = 1; i < len - 2; i++) {
            var curr:Object = points[i];
            var next:Object = points[i+1];
            
            // 简单控制点：取 (curr.x + next.x)/2, (curr.y + next.y)/2
            // 作为 curveTo 的 (controlX, controlY, anchorX, anchorY) 里的「controlX, controlY」
            // 也可用更高级的算法(如Catmull-Rom)来自定义更平滑的控制点。
            var cpx:Number = (curr.x + next.x) / 2;
            var cpy:Number = (curr.y + next.y) / 2;
            
            // curveTo(controlX, controlY, anchorX, anchorY)
            canvas.curveTo(curr.x, curr.y, cpx, cpy);
        }
        
        // 3) 末段：线到倒数第一个点 -> 再线到最后一个点(或者直接 lineTo 最后一个点)
        //    这里演示“末段也是线”：
        canvas.lineTo(points[len - 1].x, points[len - 1].y);
        
        // 4) 是否闭合图形
        if (closePath == undefined || closePath == true) {
            canvas.lineTo(points[0].x, points[0].y);
        }
        
        // 结束填充
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
     * @note 自动处理容器变更和对象回收
     */
    private function getAvailableCanvas():MovieClip {
        // 检查容器一致性
        var newContainer:MovieClip = getCurrentContainer();
        if (_currentCanvas && _currentCanvas._parent != newContainer) {
            recycleCanvas(_currentCanvas);
            _currentCanvas = null;
        }
        
        // 返回当前活跃画布(如果可用)
        if (_currentCanvas) return _currentCanvas;
        
        // 从对象池获取或创建新画布
        var canvas:MovieClip = _canvasPool.length ? 
            MovieClip(_canvasPool.pop()) : 
            createNewCanvas();
            
        // 验证画布父容器
        if(canvas._parent != newContainer) {
            canvas.removeMovieClip();
            canvas = createNewCanvas();
        }
        
        // 初始化新画布
        _currentCanvas = canvas;
        initActiveCanvas(canvas);
        return canvas;
    }
    
    /**
     * 获取当前容器引用
     * @private
     * @return 当前有效的容器MovieClip
     * @throws 当容器不存在时输出错误日志
     */
    private function getCurrentContainer():MovieClip {
        if (_root.gameworld && _root.gameworld.deadbody) {
            return _root.gameworld.deadbody;
        } else {
            trace("错误: _root.gameworld.deadbody 不存在");
            return null;
        }
    }
    
    /**
     * 创建新画布
     * @private
     * @return 新创建的MovieClip画布
     */
    private function createNewCanvas():MovieClip {
        var container:MovieClip = getCurrentContainer();
        if (!container) return null;
        
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
        
        if (!canvas.fadeTask) {
            trace("警告: 渐隐任务添加失败，检查 _root.帧计时器");
        }
    }
    
    /**
     * 渐隐动画更新回调
     * @private
     * @param canvas 正在渐隐的画布
     */
    private function onFadeUpdate(canvas:MovieClip):Void {
        if (!canvas) return;
        
        // 首次更新时释放当前画布引用
        if (canvas.cycleCount == 0 && _currentCanvas == canvas) {
            _currentCanvas = null;
        }
        
        // 检查是否完成所有渐隐周期
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
        var p0:Vector = points[0];
        var prev:Vector = p0;
        canvas.moveTo(prev.x, prev.y);

        do {
            var p:Vector = points[i % len]; // 包括闭合那一笔
            canvas.lineTo(p.x, p.y);
        } while (++i <= len); // i = len 时，p = points[0]，闭合
        canvas.endFill();
    }
}