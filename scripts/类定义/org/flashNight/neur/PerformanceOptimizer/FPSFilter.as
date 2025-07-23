/**
 * 帧率平滑滤波器
 * 使用指数移动平均(EMA)算法平滑帧率数据，减少瞬时波动的影响
 */
class org.flashNight.neur.PerformanceOptimizer.FPSFilter {
    private var _alpha:Number;          // EMA平滑系数 (0-1)
    private var _smoothedFPS:Number;    // 当前平滑后的FPS值
    private var _initialized:Boolean;   // 是否已初始化
    private var _sampleCount:Number;    // 样本计数
    
    /**
     * 构造函数
     * @param alpha EMA平滑系数，值越小越平滑，推荐0.1-0.3
     * @param initialFPS 初始FPS值
     */
    public function FPSFilter(alpha:Number, initialFPS:Number) {
        _alpha = (alpha > 0 && alpha <= 1) ? alpha : 0.15;
        _smoothedFPS = initialFPS || 30;
        _initialized = false;
        _sampleCount = 0;
    }
    
    /**
     * 处理新的帧率样本
     * @param rawFPS 原始帧率值
     * @return 平滑后的帧率值
     */
    public function process(rawFPS:Number):Number {
        // 输入验证
        if (isNaN(rawFPS) || rawFPS <= 0) {
            return _smoothedFPS;
        }
        
        // 异常值检测和处理
        rawFPS = _clampFPS(rawFPS);
        
        if (!_initialized) {
            // 首次初始化，直接使用输入值
            _smoothedFPS = rawFPS;
            _initialized = true;
        } else {
            // 应用EMA滤波
            var effectiveAlpha:Number = _getEffectiveAlpha(rawFPS);
            _smoothedFPS = effectiveAlpha * rawFPS + (1 - effectiveAlpha) * _smoothedFPS;
        }
        
        _sampleCount++;
        return _smoothedFPS;
    }
    
    /**
     * 获取有效的alpha值，根据FPS变化幅度动态调整
     */
    private function _getEffectiveAlpha(rawFPS:Number):Number {
        var diff:Number = Math.abs(rawFPS - _smoothedFPS);
        var changeMagnitude:Number = diff / _smoothedFPS;
        
        // 变化幅度大时增加响应性，变化小时增加平滑性
        if (changeMagnitude > 0.3) {
            return Math.min(_alpha * 2, 0.5); // 快速响应大变化
        } else if (changeMagnitude < 0.1) {
            return _alpha * 0.5; // 对小变化更平滑
        }
        
        return _alpha;
    }
    
    /**
     * 限制FPS值在合理范围内
     */
    private function _clampFPS(fps:Number):Number {
        // 限制在1-120之间，超出这个范围通常是测量错误
        return Math.max(1, Math.min(fps, 120));
    }
    
    /**
     * 获取当前平滑后的FPS值
     */
    public function getSmoothedFPS():Number {
        return _smoothedFPS;
    }
    
    /**
     * 设置新的平滑系数
     * @param alpha 新的平滑系数
     */
    public function setAlpha(alpha:Number):Void {
        if (alpha > 0 && alpha <= 1) {
            _alpha = alpha;
        }
    }
    
    /**
     * 获取当前平滑系数
     */
    public function getAlpha():Number {
        return _alpha;
    }
    
    /**
     * 重置滤波器状态
     * @param initialFPS 新的初始FPS值
     */
    public function reset(initialFPS:Number):Void {
        _smoothedFPS = initialFPS || 30;
        _initialized = false;
        _sampleCount = 0;
    }
    
    /**
     * 获取样本计数
     */
    public function getSampleCount():Number {
        return _sampleCount;
    }
    
    /**
     * 检查滤波器是否已稳定（有足够样本）
     */
    public function isStable():Boolean {
        return _sampleCount >= 10;
    }
}