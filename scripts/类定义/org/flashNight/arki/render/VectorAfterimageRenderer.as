import flash.geom.*;
import org.flashNight.neur.Event.*;
import org.flashNight.sara.util.* ;
import org.flashNight.neur.ScheduleTimer.EnhancedCooldownWheel;

/**
 * 矢量残影渲染器（极致复用版）
 * 
 * 此类实现了两个主要优化方向：
 * 1. 合并形状绘制：提供批量绘制接口，通过合并多个形状的点集，
 *    只调用一次 beginFill/endFill，降低绘制开销。
 * 2. 最小化事件监听器：利用统一任务管理，对所有画布的渐隐动画进行处理，
 *    采用 EnhancedCooldownWheel 增强时间轮进行任务调度，提供更精确的时间管理。
 * 
 * 功能特性：
 * - 支持 MovieClip 残影、混合形状残影（部分直线部分曲线）和自定义路径残影的绘制。
 * - 单一对象池管理多个绘图画布，支持不同残影数量配置动态切换与复用。
 * - 每个画布根据指定残影数量自动计算残影持续时间、衰减因子、刷新间隔等参数。
 * - 渐隐动画完成后自动回收画布，确保内存利用与性能最优。
 * 
 * 使用示例：
 * // 绘制单个形状残影（使用默认残影数量）
 * VectorAfterimageRenderer.instance.drawShape(
 *     [{x:0, y:0}, {x:50, y:30}, {x:30, y:50}],
 *     0xFF0000, 0x00FF00, 2, 80, 100
 * );
 * 
 * // 批量合并多个形状进行绘制
 * var shape1:Array = [{x:0, y:0}, {x:30, y:20}, {x:20, y:40}];
 * var shape2:Array = [{x:40, y:40}, {x:60, y:60}, {x:50, y:80}];
 * VectorAfterimageRenderer.instance.drawShapes(
 *     [shape1, shape2],
 *     0x00FF00, 0x0000FF, 1, 70, 100, 5
 * );
 * 
 * // 绘制混合形状残影（部分直线，部分曲线）
 * VectorAfterimageRenderer.instance.drawMixedShape(
 *     [{x:0, y:0}, {x:50, y:10}, {x:80, y:50}, {x:30, y:80}],
 *     0xFFFF00, 0xFF00FF, 2, 80, 100, true, 5
 * );
 * 
 * // 复制 MovieClip 并添加残影效果，使用默认残影数量
 * VectorAfterimageRenderer.instance.drawClip(mc, {brightness:20});
 * 
 * // 场景切换时调用 onSceneChanged 重置所有状态和对象池
 * // 注意：已替换为 EnhancedCooldownWheel 时间轮，无需额外事件订阅
 */
class org.flashNight.arki.render.VectorAfterimageRenderer {

    // ==================== 静态配置常量 ====================
    
    /** 默认残影数量（初始默认值，建议 3-10） */
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
     * 用于智能复用（同一配置下优先复用已有画布）
     */
    private var _currentCanvasByConfig:Object;
    
    /**
     * 配置参数字典，键为各残影数量(shadowCount)配置，
     * 值为 { shadowDuration, decayFactor, refreshInterval } 对象
     */
    private var _config:Object;
    
    /** 默认残影数量（当调用接口时若未传入 shadowCount 则使用该值） */
    private var _defaultShadowCount:Number;
    
    /** 存储所有参与渐隐动画的画布（便于后续统一处理） */
    private var _fadingCanvases:Array;

    // ==================== 构造函数 ====================
    
    /**
     * 构造函数 - 初始化默认配置参数、对象池及渐隐画布集合
     */
    public function VectorAfterimageRenderer() {
        _defaultShadowCount = DEFAULT_SHADOW_COUNT;
        _config = {};
        _fadingCanvases = [];
        
        // 预先计算默认配置参数
        var frameDuration:Number = EnhancedCooldownWheel.I().每帧毫秒;
        
        // 防御NaN
        if (isNaN(frameDuration) || frameDuration <= 0) {
            frameDuration = 33.33; // 30fps下约1帧
        }
        
        var shadowDuration:Number = frameDuration * _defaultShadowCount;
        var decayFactor:Number = Math.pow(0.01, 1 / _defaultShadowCount);
        var refreshInterval:Number = shadowDuration / (_defaultShadowCount * _defaultShadowCount);
        
        // 防御refreshInterval的NaN
        if (isNaN(refreshInterval) || refreshInterval < 1) {
            refreshInterval = 33.33;
        }
        refreshInterval = Math.max(1, Math.round(refreshInterval));
        
        _config[_defaultShadowCount] = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
        
        // 初始化对象池
        initCanvasPool();
    }
    
    // ==================== 对象池初始化 ====================
    
    /**
     * 初始化画布对象池
     * 使用单一对象池管理所有画布，父级容器为 _root.gameworld.deadbody
     */
    private function initCanvasPool():Void {
        _canvasPool = new ObjectPool(
            // createFunc：创建新的 MovieClip 画布
            function(parent:MovieClip):MovieClip {
                var mc:MovieClip = parent.createEmptyMovieClip("canvas_" + getTimer(), parent.getNextHighestDepth());
                return mc;
            },
            // resetFunc：取用时无特殊重置操作，由 initializeCanvas 方法完成初始化
            function():Void {},
            // releaseFunc：释放画布时执行的清理操作
            function():Void {
                if (this.fadeTask) {
                    EnhancedCooldownWheel.I().移除任务(this.fadeTask);
                }
                this._visible = false;
                if (this.clear != undefined) {
                    this.clear();
                }
            },
            // 父级容器为 _root.gameworld.deadbody
            _root.gameworld.deadbody,
            // 对象池最大容量
            30,
            // 预加载对象数量
            5,
            // 是否启用懒加载
            true,
            // 是否启用原型模式（关闭，因为每个画布需单独初始化渐隐任务）
            false,
            // 额外参数
            []
        );
        _currentCanvasByConfig = {};
    }
    
    // ==================== 系统配置方法 ====================
    
    /**
     * 配置默认残影数量
     * @param shadowCount 默认残影数量，后续调用绘制接口时若未传入，则使用该值（建议 3-10）
     */
    public function configureSystem(shadowCount:Number):Void {
        _defaultShadowCount = shadowCount;
        if (_config[shadowCount] == undefined) {
            var frameDuration:Number = EnhancedCooldownWheel.I().每帧毫秒;
            var shadowDuration:Number = frameDuration * shadowCount;
            var decayFactor:Number = Math.pow(0.01, 1 / shadowCount);
            var refreshInterval:Number = shadowDuration / (shadowCount * shadowCount);
            _config[shadowCount] = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
        }
    }
    
    /**
     * 动态调整默认残影数量
     * @param newShadowCount 新的默认残影数量配置（建议 3-10），此参数只影响新创建画布，
     *                       已处渐隐过程中的画布依旧按照原配置完成动画
     */
    public function setShadowCount(newShadowCount:Number):Void {
        configureSystem(newShadowCount);
    }
    
    // ==================== 残影绘制方法 ====================
    
    /**
     * 合并多个形状并绘制
     * @param shapes 多个形状的点集合数组，每个数组代表一个形状
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param shadowCount (可选) 残影数量配置，若未传入则采用默认值
     */
    public function drawShapes(shapes:Array, fillColor:Number, lineColor:Number, 
                            lineWidth:Number, fillAlpha:Number, lineAlpha:Number, shadowCount:Number):Void {
        var len:Number = shapes.length;
        if (len == 0) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        
        // 合并所有形状的点集
        var mergedPoints:Array = [];
        
        var i:Number = 0;
        do {
            mergedPoints = mergedPoints.concat(shapes[i]);
        } while (++i < len);
        
        renderShape(canvas, mergedPoints, fillColor, fillAlpha);
    }
    
    /**
     * 绘制单个矢量形状残影
     * @param points 顶点数组（至少包含 3 个点），格式：[{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param shadowCount (可选) 残影数量配置，若未传入则使用默认值
     */
    public function drawShape(points:Array, fillColor:Number, lineColor:Number, 
                               lineWidth:Number, fillAlpha:Number, lineAlpha:Number, shadowCount:Number):Void {
        if (points.length < 3) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        renderShape(canvas, points, fillColor, fillAlpha);
    }
    
    /**
     * 绘制混合形状残影（部分直线，部分曲线）
     * 该方法在绘制时先执行直线连接，再根据连续点生成曲线插值，
     * 最后根据需要决定是否闭合路径。
     * @param points 顶点数组（至少包含 3 个点），格式：[{x:Number, y:Number}, ...]
     * @param fillColor 填充色（RGB）
     * @param lineColor 线条色（RGB）
     * @param lineWidth 线宽（像素）
     * @param fillAlpha 填充透明度（0-100）
     * @param lineAlpha 线条透明度（0-100）
     * @param closePath 是否闭合图形（布尔值，默认 true）
     * @param shadowCount (可选) 残影数量配置，若未传入则使用默认值
     */
    public function drawMixedShape(points:Array, fillColor:Number, lineColor:Number, 
                                    lineWidth:Number, fillAlpha:Number, lineAlpha:Number, closePath:Boolean, shadowCount:Number):Void {
        var len:Number = points.length - 2;
        
        if (points == undefined || len < 1) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        // 若 closePath 参数未传入，则默认闭合路径
        if (closePath == undefined) closePath = true;
        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);

        var tempPoint:Vector = points[0];
        
        // 开始填充绘制
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        canvas.moveTo(tempPoint.x, tempPoint.y);
        // 先绘制前两点直线

        tempPoint = points[1];
        canvas.lineTo(tempPoint.x, tempPoint.y);  
        
        var nextTempPoint:Vector;
        var cpx:Number;
        var cpy:Number;

        // 对中间点采用曲线插值绘制
        for (var i:Number = 1; i < len; i++) {
            tempPoint = points[i];
            nextTempPoint = points[i + 1];
            cpx = (tempPoint.x + nextTempPoint.x) / 2;
            cpy = (tempPoint.y + nextTempPoint.y) / 2;

            canvas.curveTo(tempPoint.x, tempPoint.y, cpx, cpy);
        }
        // 绘制最后一段直线
        tempPoint = points[++len];
        canvas.lineTo(tempPoint.x, tempPoint.y);

        // 根据 closePath 参数判断是否闭合路径
        if (closePath) {
            tempPoint = points[0];
            canvas.lineTo(tempPoint.x, tempPoint.y);
        }
        canvas.endFill();
    }

    /**
     * 批量绘制多个混合形状残影（部分直线，部分曲线）
     * 
     * 该方法支持一次性绘制多个混合形状，通过减少画布创建和样式设置的次数来优化性能。
     * 每个形状的绘制逻辑与 drawMixedShape 一致：首尾段使用直线连接，中间点通过曲线插值绘制。
     * 
     * @param shapes 多个形状的点集合数组，每个子数组代表一个形状，例如 [[{x:0, y:0}, {x:50, y:10}], [{x:60, y:60}, {x:80, y:80}]]
     * @param fillColor 填充颜色（RGB 值，例如 0xFF0000）
     * @param lineColor 线条颜色（RGB 值，例如 0x00FF00）
     * @param lineWidth 线条宽度（单位：像素，默认 1）
     * @param fillAlpha 填充透明度（0-100，默认 100）
     * @param lineAlpha 线条透明度（0-100，默认 100）
     * @param closePath 是否闭合每个形状的路径（布尔值，默认 true）
     * @param shadowCount 可选的残影数量配置，若未传入则使用默认值 _defaultShadowCount
     */
    public function drawMixedShapes(shapes:Array, fillColor:Number, lineColor:Number, 
                                    lineWidth:Number, fillAlpha:Number, lineAlpha:Number, 
                                    closePath:Boolean, shadowCount:Number):Void {
        var shapesLen:Number = shapes.length;

        if (shapes == undefined || shapesLen == 0) return;
        if (shadowCount == undefined) shadowCount = _defaultShadowCount;
        if (closePath == undefined) closePath = true;

        var canvas:MovieClip = getAvailableCanvas(shadowCount);
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        
        var i:Number = 0, j:Number, points:Array, len:Number;
        var tempPoint:Vector, nextTempPoint:Vector, cpx:Number, cpy:Number;
        
        // 使用 do...while 优化外层循环
        do {
            points = shapes[i];
            len = points.length - 2;
            
            // 仅处理有效形状
            if (points != undefined && len >= 1) {
                canvas.beginFill(fillColor || 0, fillAlpha || 100);
                tempPoint = points[0];
                canvas.moveTo(tempPoint.x, tempPoint.y);
                tempPoint = points[1];
                canvas.lineTo(tempPoint.x, tempPoint.y);

                // 曲线段保持原 for 循环
                for (j = 1; j < len; j++) {
                    tempPoint = points[j];
                    nextTempPoint = points[j + 1];
                    cpx = (tempPoint.x + nextTempPoint.x) * 0.5;
                    cpy = (tempPoint.y + nextTempPoint.y) * 0.5;
                    canvas.curveTo(tempPoint.x, tempPoint.y, cpx, cpy);
                }

                tempPoint = points[++len];
                canvas.lineTo(tempPoint.x, tempPoint.y);
                
                if (closePath) {
                    // 修正闭合路径：连接到起始点
                    tempPoint = points[0];
                    canvas.lineTo(tempPoint.x, tempPoint.y);
                }
                canvas.endFill();
            }
        } while (++i < shapesLen);
    }



    
    /**
     * 复制 MovieClip 并生成残影效果
     * 同时应用源对象的变换矩阵和颜色变换（依赖色彩引擎）
     * @param source 源 MovieClip 对象
     * @param colorParams 颜色调整参数对象
     * @param shadowCount (可选) 残影数量配置，若未传入则采用默认值
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
     * 清空对象池中的画布和当前活跃画布，避免内存泄漏，并重新初始化对象池
     */
    public function onSceneChanged():Void {
        if (_canvasPool != undefined) {
            _canvasPool.clearPool();
        }
        _currentCanvasByConfig = {};
        // 重新初始化对象池
        initCanvasPool();
        // 清空渐隐画布集合
        _fadingCanvases = [];
    }
    
    /**
     * 重置渲染器，与 onSceneChanged 效果一致
     */
    public function reset():Void {
        onSceneChanged();
    }
    
    // ==================== 画布生命周期管理与复用 ====================
    
    /**
     * 从对象池中获取一个可用画布，并初始化指定残影数量
     * @param shadowCount 残影数量配置
     * @return 已初始化的 MovieClip 画布
     */
    private function getAvailableCanvas(shadowCount:Number):MovieClip {
        if (_currentCanvasByConfig[shadowCount] != undefined && _currentCanvasByConfig[shadowCount] != null) {
            return _currentCanvasByConfig[shadowCount];
        }
        var canvas:MovieClip = _canvasPool.getObject();
        initializeCanvas(canvas, shadowCount);
        _currentCanvasByConfig[shadowCount] = canvas;
        // 添加到渐隐管理数组中（便于全局统一管理）
        _fadingCanvases.push(canvas);
        return canvas;
    }
    
    /**
     * 初始化画布，将其配置为指定残影数量，并注册渐隐任务
     * @param canvas 目标 MovieClip 画布对象
     * @param shadowCount 指定的残影数量配置
     */
    private function initializeCanvas(canvas:MovieClip, shadowCount:Number):Void {
        canvas._visible = true;
        canvas._alpha = BASE_ALPHA;
        canvas.cycleCount = 0;
        canvas.shadowCount = shadowCount;
        
        // 获取或生成当前残影配置参数
        var configObj:Object = _config[shadowCount];
        if (configObj == undefined) {
            var frameDuration:Number = EnhancedCooldownWheel.I().每帧毫秒;
            var shadowDuration:Number = frameDuration * shadowCount;
            var decayFactor:Number = Math.pow(0.01, 1 / shadowCount);
            var refreshInterval:Number = shadowDuration / (shadowCount * shadowCount);
            // 防御NaN和过小值
            if (isNaN(refreshInterval) || refreshInterval < 1) {
                refreshInterval = 33.33; // 兜底为约1帧
            }
            refreshInterval = Math.max(1, Math.round(refreshInterval));
            configObj = { shadowDuration: shadowDuration, decayFactor: decayFactor, refreshInterval: refreshInterval };
            _config[shadowCount] = configObj;
        }
        
        // 移除之前可能存在的渐隐任务
        if (canvas.fadeTask) {
            EnhancedCooldownWheel.I().移除任务(canvas.fadeTask);
        }
        // 绑定 onFadeUpdate 方法，添加渐隐任务（使用增强时间轮替换原帧计时器）
        var callback:Function = Delegate.create(this, onFadeUpdate);
        canvas.fadeTask = EnhancedCooldownWheel.I().添加任务(callback, configObj.refreshInterval, shadowCount, canvas);
    }
    
    /**
     * 渐隐动画回调：更新画布透明度，判断是否结束渐隐并回收画布
     * @param canvas 当前参与渐隐的 MovieClip 画布对象
     */
    private function onFadeUpdate(canvas:MovieClip):Void {
        var configObj:Object = _config[canvas.shadowCount];
        // 若为首次渐隐，解除当前活跃画布绑定，允许后续继续使用新画布
        if (canvas.cycleCount == 0 && _currentCanvasByConfig[canvas.shadowCount] == canvas) {
            _currentCanvasByConfig[canvas.shadowCount] = null;
        }
        canvas.cycleCount++;
        // 如果达到指定次数或透明度过低，则回收画布
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
     * 回收画布：从当前使用中移除画布并放回对象池或销毁（当池满时）
     * @param canvas 需要回收的 MovieClip 画布对象
     */
    private function recycleCanvas(canvas:MovieClip):Void {
        if (canvas.__isDestroyed) return; // 防止重复回收
        EnhancedCooldownWheel.I().移除任务(canvas.fadeTask);
        canvas._visible = false;
        if (canvas.clear != undefined) {
            canvas.clear();
        }
        // 移除当前活跃画布绑定
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
     * 设置画布绘制样式（线条宽度、颜色、透明度）
     * @param canvas 目标 MovieClip 画布对象
     * @param lineColor 线条颜色（RGB）
     * @param lineWidth 线宽（像素）
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
        var tempPoint:Vector = points[0];
        canvas.moveTo(tempPoint.x, tempPoint.y);
        do {
            tempPoint = points[i % len];
            canvas.lineTo(tempPoint.x, tempPoint.y);
            i++;
        } while (i <= len);
        canvas.endFill();
    }
    
    /**
     * 复制 MovieClip 并生成残影效果，同时应用变换矩阵和颜色变换
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
     * @return 返回复制后的 MovieClip 实例
     */
    private function duplicateClip(source:MovieClip, canvas:MovieClip):MovieClip {
        var depth:Number = canvas.getNextHighestDepth();
        var ghostName:String = "ghost_" + depth;
        // duplicateMovieClip 只能复制到源所在容器，此处复制后将副本移入 canvas 下
        source.duplicateMovieClip(ghostName, depth);
        var ghost:MovieClip = source._parent[ghostName];
        ghost.swapDepths(canvas.getNextHighestDepth());
        ghost._parent = canvas;
        return ghost;
    }
    
    /**
     * 应用变换矩阵，将源 MovieClip 的位置和缩放赋给目标 MovieClip（旋转等变换可扩展）
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
     * @return 返回累计后的 Matrix 对象
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
