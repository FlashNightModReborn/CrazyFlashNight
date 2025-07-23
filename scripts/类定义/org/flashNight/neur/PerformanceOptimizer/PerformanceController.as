import org.flashNight.neur.PerformanceOptimizer.PerformanceAction;

/**
 * 性能控制器
 * 使用PID算法分析帧率与目标的差异，输出性能调整建议
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceController {
    // PID参数
    private var _kp:Number;         // 比例系数
    private var _ki:Number;         // 积分系数  
    private var _kd:Number;         // 微分系数
    private var _targetFPS:Number;  // 目标帧率
    
    // PID状态变量
    private var _prevError:Number;      // 上次误差
    private var _integral:Number;       // 积分累积
    private var _integralMax:Number;    // 积分限幅
    private var _derivativeFilter:Number; // 微分滤波系数
    private var _filteredDerivative:Number; // 滤波后的微分项
    
    // 控制参数
    private var _deadband:Number;       // 死区范围
    private var _outputLimit:Number;    // 输出限幅
    private var _confirmationCounter:Number; // 确认计数器
    private var _confirmationThreshold:Number; // 确认阈值
    private var _lastAdjustment:String; // 上次调整方向
    
    /**
     * 构造函数
     * @param targetFPS 目标帧率
     * @param kp 比例系数
     * @param ki 积分系数
     * @param kd 微分系数
     */
    public function PerformanceController(targetFPS:Number, kp:Number, ki:Number, kd:Number) {
        _targetFPS = targetFPS || 26; // 略低于30帧，留有余量
        _kp = kp || 0.6;
        _ki = ki || 0.05;
        _kd = kd || 0.3;
        
        _integralMax = 3.0;
        _derivativeFilter = 0.2;
        _deadband = 2.0; // ±2FPS内不调整
        _outputLimit = 5.0;
        _confirmationThreshold = 2; // 需要连续2次确认才调整
        
        reset();
    }
    
    /**
     * 计算性能调整动作
     * @param currentFPS 当前平滑后的帧率
     * @return PerformanceAction对象
     */
    public function compute(currentFPS:Number):PerformanceAction {
        // 计算误差（正值表示性能不足，负值表示性能过剩）
        var error:Number = _targetFPS - currentFPS;
        
        // 死区处理
        if (Math.abs(error) < _deadband) {
            _resetConfirmation();
            return new PerformanceAction("STABLE", 0, currentFPS, _targetFPS);
        }
        
        // 积分项处理（抗积分饱和）
        _integral += error;
        _integral = Math.max(-_integralMax, Math.min(_integral, _integralMax));
        
        // 微分项处理（带滤波）
        var derivative:Number = error - _prevError;
        _filteredDerivative = _derivativeFilter * derivative + (1 - _derivativeFilter) * _filteredDerivative;
        
        // PID输出
        var output:Number = _kp * error + _ki * _integral + _kd * _filteredDerivative;
        output = Math.max(-_outputLimit, Math.min(output, _outputLimit));
        
        // 确定趋势和强度
        var trend:String = _determineTrend(output, error);
        var magnitude:Number = _calculateMagnitude(output);
        
        // 确认机制：防止频繁调整
        if (_shouldConfirm(trend)) {
            _confirmationCounter++;
            if (_confirmationCounter < _confirmationThreshold) {
                return new PerformanceAction("STABLE", 0, currentFPS, _targetFPS);
            }
        } else {
            _resetConfirmation();
        }
        
        // 记录状态
        _prevError = error;
        _lastAdjustment = trend;
        
        return new PerformanceAction(trend, magnitude, currentFPS, _targetFPS);
    }
    
    /**
     * 确定调整趋势
     */
    private function _determineTrend(output:Number, error:Number):String {
        var threshold:Number = 0.1;
        
        if (output > threshold) {
            return "UP";    // 需要降低画质提升性能
        } else if (output < -threshold) {
            return "DOWN";  // 可以提升画质
        } else {
            return "STABLE";
        }
    }
    
    /**
     * 计算调整强度（0-1）
     */
    private function _calculateMagnitude(output:Number):Number {
        // 使用Sigmoid函数将输出映射到0-1范围
        var absOutput:Number = Math.abs(output);
        var magnitude:Number = 1 / (1 + Math.exp(-absOutput + 2));
        
        // 确保在合理范围内
        return Math.max(0, Math.min(magnitude, 1));
    }
    
    /**
     * 判断是否需要确认
     */
    private function _shouldConfirm(trend:String):Boolean {
        return trend != "STABLE" && trend != _lastAdjustment;
    }
    
    /**
     * 重置确认状态
     */
    private function _resetConfirmation():Void {
        _confirmationCounter = 0;
    }
    
    /**
     * 重置控制器状态
     */
    public function reset():Void {
        _prevError = 0;
        _integral = 0;
        _filteredDerivative = 0;
        _confirmationCounter = 0;
        _lastAdjustment = "STABLE";
    }
    
    /**
     * 设置PID参数
     */
    public function setPIDParams(kp:Number, ki:Number, kd:Number):Void {
        if (!isNaN(kp) && kp >= 0) _kp = kp;
        if (!isNaN(ki) && ki >= 0) _ki = ki;
        if (!isNaN(kd) && kd >= 0) _kd = kd;
    }
    
    /**
     * 设置目标帧率
     */
    public function setTargetFPS(target:Number):Void {
        if (!isNaN(target) && target > 0) {
            _targetFPS = target;
        }
    }
    
    /**
     * 获取当前PID参数
     */
    public function getPIDParams():Object {
        return {kp: _kp, ki: _ki, kd: _kd, target: _targetFPS};
    }
    
    /**
     * 设置死区范围
     */
    public function setDeadband(deadband:Number):Void {
        if (!isNaN(deadband) && deadband >= 0) {
            _deadband = deadband;
        }
    }
    
    /**
     * 获取控制器状态信息（调试用）
     */
    public function getDebugInfo():Object {
        return {
            prevError: _prevError,
            integral: _integral,
            derivative: _filteredDerivative,
            confirmation: _confirmationCounter,
            lastAdjustment: _lastAdjustment
        };
    }
}