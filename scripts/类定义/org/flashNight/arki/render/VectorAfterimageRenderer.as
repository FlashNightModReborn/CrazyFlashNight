// 文件路径: org/flashNight/arki/render/VectorAfterimageRenderer.as
import flash.geom.*;
import org.flashNight.neur.Event.*;

class org.flashNight.arki.render.VectorAfterimageRenderer {

    // 基本配置参数
    private static var DEFAULT_SHADOW_COUNT:Number = 5;
    private static var FRAME_INTERVAL:Number = 1;
    private static var BASE_ALPHA:Number = 100;
    
    // 对象池管理
    private var _canvasPool:Array;
    
    // 当前使用的画布（未开始渐隐的部分）
    private var _currentCanvas:MovieClip;
    
    // 运行时参数
    private var _shadowDuration:Number;
    private var _alphaDecay:Number;
    private var _refreshInterval:Number;
    private var _shadowCount:Number;
    
    public function VectorAfterimageRenderer() {
        _canvasPool = [];
        configureSystem(DEFAULT_SHADOW_COUNT, FRAME_INTERVAL);
    }
    
    // 配置核心参数（可运行时动态调整）
    public function configureSystem(shadowCount:Number, frameInterval:Number):Void {
        _shadowCount = shadowCount;
        var frameDuration:Number = _root.帧计时器.每帧毫秒;
        _shadowDuration = frameDuration * shadowCount * frameInterval;
        _alphaDecay = BASE_ALPHA / shadowCount;
        _refreshInterval = _shadowDuration / (shadowCount * shadowCount);
    }
    
    // 主绘制接口
    public function drawShape(points:Array, fillColor:Number, lineColor:Number, 
                             lineWidth:Number, fillAlpha:Number, lineAlpha:Number):Void {
        var canvas:MovieClip = getAvailableCanvas();
        if (!points || points.length < 3) return;
        
        setupCanvasStyle(canvas, lineColor, lineWidth, lineAlpha);
        renderShape(canvas, points, fillColor, fillAlpha);
        // 渐隐任务已在 getAvailableCanvas 中设置，无需额外调用
    }
    
    public function drawClip(source:MovieClip, colorParams:Object):Void {
        var canvas:MovieClip = getAvailableCanvas();
        var adjustedColor:ColorTransform = _root.色彩引擎.初级调整颜色(source, colorParams);
        renderMovieClip(source, canvas, adjustedColor);
    }

    // 核心渲染逻辑
    private function renderMovieClip(source:MovieClip, canvas:MovieClip, colorTransform:ColorTransform):Void {
        canvas.clear();
        var ghost:MovieClip = duplicateClip(source, canvas);
        applyTransformation(source, ghost);
        if (colorTransform) {
            ghost.transform.colorTransform = colorTransform;
        }
    }
    
    private function duplicateClip(source:MovieClip, canvas:MovieClip):MovieClip {
        var depth:Number = canvas.getNextHighestDepth();
        var ghostName:String = "ghost_" + depth;
        source.duplicateMovieClip(ghostName, depth);
        return canvas[ghostName];
    }
    
    private function applyTransformation(source:MovieClip, target:MovieClip):Void {
        var matrix:Matrix = calculateCumulativeMatrix(source);
        target._x = matrix.tx;
        target._y = matrix.ty;
        target._xscale = source._xscale;
        target._yscale = source._yscale;
    }
    
    // 矩阵计算
    private function calculateCumulativeMatrix(target:MovieClip):Matrix {
        var matrix:Matrix = new Matrix();
        var current:MovieClip = target;
        while (current && current != _root.gameworld) {
            matrix.concat(current.transform.matrix);
            current = current._parent;
        }
        return matrix;
    }
    
    // 画布生命周期管理
    private function getAvailableCanvas():MovieClip {
        // 检查当前画布是否依旧挂载在最新的 _root.gameworld.deadbody 下
        var newContainer:MovieClip = getCurrentContainer();
        if (_currentCanvas) {
            if (_currentCanvas._parent != newContainer) {
                // 若不匹配，回收旧的画布，并清空当前画布引用
                recycleCanvas(_currentCanvas);
                _currentCanvas = null;
            }
        }
        
        if (_currentCanvas) {
            return _currentCanvas;
        }
        
        var canvas:MovieClip;
        if (_canvasPool.length) {
            canvas = MovieClip(_canvasPool.pop());
            // 同样要判断：如果 canvas 的父级和当前容器不一致，则丢弃重新创建
            if(canvas._parent != newContainer) {
                canvas.removeMovieClip();
                canvas = createNewCanvas();
            }
        } else {
            canvas = createNewCanvas();
        }
        // 将新画布设为当前画布并初始化渐隐任务
        _currentCanvas = canvas;
        initActiveCanvas(canvas);
        return canvas;
    }
    
    // 获取当前最新的容器引用
    private function getCurrentContainer():MovieClip {
        if (_root.gameworld && _root.gameworld.deadbody) {
            return _root.gameworld.deadbody;
        } else {
            trace("错误: _root.gameworld.deadbody 不存在");
            return null;
        }
    }
    
    private function createNewCanvas():MovieClip {
        var container:MovieClip = getCurrentContainer();
        if (!container) return null;
        
        var canvas:MovieClip = container.createEmptyMovieClip("canvas_" + getTimer(), container.getNextHighestDepth());
        canvas.clear();
        return canvas;
    }
    
    private function initActiveCanvas(canvas:MovieClip):Void {
        if (!canvas) return;
        canvas._visible = true;
        canvas._alpha = BASE_ALPHA;
        canvas.cycleCount = 0;
        
        var callback:Function = Delegate.create(this, onFadeUpdate);
        canvas.fadeTask = _root.帧计时器.添加任务(
            callback, 
            _refreshInterval, 
            _shadowCount, 
            canvas  // 将 canvas 作为附加参数传入
        );
        
        if (!canvas.fadeTask) {
            trace("警告: 渐隐任务添加失败，检查 _root.帧计时器");
        }
    }
    
    // 渐隐动画处理
    private function onFadeUpdate(canvas:MovieClip):Void {
        if (!canvas) return;
        
        // 初始更新时清除 _currentCanvas 引用，以便新绘制能申请新 canvas
        if (canvas.cycleCount == 0 && _currentCanvas == canvas) {
            _currentCanvas = null;
        }
        
        if (++canvas.cycleCount >= _shadowCount) {
            recycleCanvas(canvas);
        } else {
            canvas._alpha -= _alphaDecay;
        }
    }
    
    private function recycleCanvas(canvas:MovieClip):Void {
        _root.帧计时器.移除任务(canvas.fadeTask);
        canvas._visible = false;
        canvas.clear();
        // 在回收时canvas 纳入到新的池中
        _canvasPool.push(canvas);
    }
    
    // 工具方法
    private function setupCanvasStyle(canvas:MovieClip, lineColor:Number, lineWidth:Number, lineAlpha:Number):Void {
        canvas.lineStyle(lineWidth || 1, lineColor || 0xFF0000, lineAlpha || 100);
    }
    
    private function renderShape(canvas:MovieClip, points:Array, fillColor:Number, fillAlpha:Number):Void {
        canvas.beginFill(fillColor || 0, fillAlpha || 100);
        drawPath(canvas, points);
        canvas.endFill();
    }
    
    private function drawPath(canvas:MovieClip, points:Array):Void {
        canvas.moveTo(points[0].x, points[0].y);
        for (var i:Number = 1; i < points.length; i++) {
            canvas.lineTo(points[i].x, points[i].y);
        }
        canvas.lineTo(points[0].x, points[0].y);
    }
    
    // 对外提供的重置方法，当 gameworld 重载时，可主动调用以清理旧引用
    public function reset():Void {
        _canvasPool = [];
        _currentCanvas = null;
    }
}
