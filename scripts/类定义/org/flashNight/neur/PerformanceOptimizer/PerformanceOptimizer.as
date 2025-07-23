import org.flashNight.neur.PerformanceOptimizer.FrameProbe;
import org.flashNight.neur.PerformanceOptimizer.FPSFilter;
import org.flashNight.neur.PerformanceOptimizer.PerformanceController;
import org.flashNight.neur.PerformanceOptimizer.QualityApplier;
import org.flashNight.neur.PerformanceOptimizer.PerformanceAction;

/**
 * 性能优化器门面类
 * 整合帧率采集、平滑、控制和应用的完整性能自适应系统
 */
class org.flashNight.neur.PerformanceOptimizer.PerformanceOptimizer {
    // 核心组件
    private var _probe:FrameProbe;
    private var _filter:FPSFilter;
    private var _controller:PerformanceController;
    private var _applier:QualityApplier;
    
    // 配置参数
    private var _targetFPS:Number;
    private var _enabled:Boolean;
    private var _debugMode:Boolean;
    
    // 状态跟踪
    private var _lastUpdateTime:Number;
    private var _updateCount:Number;
    private var _lastAction:PerformanceAction;
    
    /**
     * 构造函数
     * @param targetFPS 目标帧率
     * @param debugMode 是否启用调试模式
     */
    public function PerformanceOptimizer(targetFPS:Number, debugMode:Boolean) {
        _targetFPS = targetFPS || 26;
        _debugMode = debugMode || false;
        _enabled = true;
        _updateCount = 0;
        _lastUpdateTime = getTimer();
        
        _initializeComponents();
        
        if (_debugMode) {
            trace("[PerformanceOptimizer] 初始化完成，目标FPS: " + _targetFPS);
        }
    }
    
    /**
     * 初始化所有组件
     */
    private function _initializeComponents():Void {
        // 创建帧率采集器
        _probe = new FrameProbe(_targetFPS);
        
        // 创建FPS滤波器（EMA系数0.15，约6帧半衰期）
        _filter = new FPSFilter(0.15, _targetFPS);
        
        // 创建性能控制器（PID参数基于原代码调优）
        _controller = new PerformanceController(_targetFPS, 0.6, 0.05, 0.3);
        
        // 创建画质应用器
        _applier = new QualityApplier(0, 0, 3);
    }
    
    /**
     * 主更新方法，每帧调用
     * 这是外部调用的主要接口
     */
    public function update():Void {
        if (!_enabled) {
            return;
        }
        
        // 采集帧率（可能返回null表示还未到测量间隔）
        var rawFPS:Number = _probe.capture();
        if (rawFPS == null) {
            return; // 还未到测量时间
        }
        
        // 平滑处理
        var smoothFPS:Number = _filter.process(rawFPS);
        
        // 性能控制决策
        var action:PerformanceAction = _controller.compute(smoothFPS);
        
        // 应用画质调整
        _applier.apply(action);
        
        // 更新状态
        _lastAction = action;
        _updateCount++;
        _lastUpdateTime = getTimer();
        
        // 调试输出
        if (_debugMode && action.shouldAdjust()) {
            trace("[PerformanceOptimizer] " + action.toString() + 
                  " Level:" + _applier.getCurrentLevel());
        }
        
        // 更新UI显示（兼容原有界面）
        _updateUI(smoothFPS, _applier.getCurrentLevel());
    }
    
    /**
     * 更新UI显示
     */
    private function _updateUI(fps:Number, level:Number):Void {
        if (_root.玩家信息界面 && _root.玩家信息界面.性能帧率显示器) {
            var display = _root.玩家信息界面.性能帧率显示器;
            if (display.帧率数字) {
                display.帧率数字.text = fps;
            }
        }
        
        // 更新全局性能等级（兼容原有代码）
        if (_root.帧计时器) {
            _root.帧计时器.性能等级 = level;
            _root.帧计时器.实际帧率 = fps;
            
            // 更新测量间隔（基于性能等级）
            var newMeasurementFrames:Number = Math.ceil(_targetFPS * (1 + level * 0.5));
            _probe.setMeasurementFrames(newMeasurementFrames);
        }
    }
    
    /**
     * 重置优化器状态
     * 在场景切换时调用
     */
    public function reset():Void {
        _probe.reset();
        _filter.reset(_targetFPS);
        _controller.reset();
        _applier.reset();
        
        _updateCount = 0;
        _lastUpdateTime = getTimer();
        _lastAction = null;
        
        if (_debugMode) {
            trace("[PerformanceOptimizer] 状态已重置");
        }
    }
    
    /**
     * 启用或禁用优化器
     */
    public function setEnabled(enabled:Boolean):Void {
        _enabled = enabled;
        if (_debugMode) {
            trace("[PerformanceOptimizer] " + (enabled ? "已启用" : "已禁用"));
        }
    }
    
    /**
     * 设置目标帧率
     */
    public function setTargetFPS(targetFPS:Number):Void {
        if (!isNaN(targetFPS) && targetFPS > 0) {
            _targetFPS = targetFPS;
            _controller.setTargetFPS(targetFPS);
            _filter.reset(targetFPS);
            
            if (_debugMode) {
                trace("[PerformanceOptimizer] 目标FPS更新为: " + targetFPS);
            }
        }
    }
    
    /**
     * 设置PID参数
     */
    public function setPIDParams(kp:Number, ki:Number, kd:Number):Void {
        _controller.setPIDParams(kp, ki, kd);
        if (_debugMode) {
            trace("[PerformanceOptimizer] PID参数已更新: kp=" + kp + " ki=" + ki + " kd=" + kd);
        }
    }
    
    /**
     * 强制设置性能等级
     */
    public function forcePerformanceLevel(level:Number):Void {
        _applier.forceSetLevel(level);
        if (_debugMode) {
            trace("[PerformanceOptimizer] 强制设置性能等级: " + level);
        }
    }
    
    /**
     * 获取当前状态信息
     */
    public function getStatus():Object {
        return {
            enabled: _enabled,
            targetFPS: _targetFPS,
            currentLevel: _applier.getCurrentLevel(),
            updateCount: _updateCount,
            lastAction: _lastAction ? _lastAction.toString() : "无",
            isFilterStable: _filter.isStable(),
            measurementProgress: _probe.getMeasurementProgress()
        };
    }
    
    /**
     * 获取详细调试信息
     */
    public function getDebugInfo():Object {
        var status:Object = getStatus();
        status.pidInfo = _controller.getDebugInfo();
        status.filterSampleCount = _filter.getSampleCount();
        status.probeFrames = _probe.getMeasurementFrames();
        return status;
    }
    
    /**
     * 启用或禁用调试模式
     */
    public function setDebugMode(debug:Boolean):Void {
        _debugMode = debug;
    }
    
    /**
     * 检查优化器是否正常工作
     */
    public function isHealthy():Boolean {
        var currentTime:Number = getTimer();
        var timeSinceLastUpdate:Number = currentTime - _lastUpdateTime;
        
        // 如果超过5秒没有更新，认为不健康
        return _enabled && timeSinceLastUpdate < 5000;
    }
    
    /**
     * 获取简化的性能报告（用于UI显示）
     */
    public function getPerformanceReport():String {
        if (!_lastAction) {
            return "性能监控启动中...";
        }
        
        var level:Number = _applier.getCurrentLevel();
        var levelText:String;
        switch (level) {
            case 0: levelText = "高"; break;
            case 1: levelText = "中"; break;
            case 2: levelText = "低"; break;
            default: levelText = "最低"; break;
        }
        
        return "性能等级: " + levelText + " | FPS: " + 
               _lastAction.currentFPS + "/" + _lastAction.targetFPS;
    }
}