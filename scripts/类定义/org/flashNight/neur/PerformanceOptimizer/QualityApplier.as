import org.flashNight.neur.PerformanceOptimizer.PerformanceAction;
import org.flashNight.arki.component.Effect.EffectSystem;
import org.flashNight.arki.bullet.BulletComponent.Shell.ShellSystem;
import org.flashNight.arki.corpse.DeathEffectRenderer;
import org.flashNight.arki.render.TrailRenderer;
import org.flashNight.arki.render.ClipFrameRenderer;
import org.flashNight.arki.render.BladeMotionTrailsRenderer;

/**
 * 画质设置应用器
 * 根据性能调整动作执行具体的画质和效果设置
 */
class org.flashNight.neur.PerformanceOptimizer.QualityApplier {
    private var _currentLevel:Number;      // 当前性能等级 0=高 1=中 2=低 3=最低
    private var _minLevel:Number;          // 最低性能等级
    private var _maxLevel:Number;          // 最高性能等级
    private var _originalQuality:String;   // 原始画质设置
    private var _stepSize:Number;          // 每次调整的步长
    private var _lastApplyTime:Number;     // 上次应用时间
    private var _cooldownTime:Number;      // 冷却时间（毫秒）
    
    /**
     * 构造函数
     * @param initialLevel 初始性能等级
     * @param minLevel 最低性能等级（最好画质）
     * @param maxLevel 最高性能等级（最差画质）
     */
    public function QualityApplier(initialLevel:Number, minLevel:Number, maxLevel:Number) {
        _currentLevel = initialLevel || 0;
        _minLevel = minLevel || 0;
        _maxLevel = maxLevel || 3;
        _stepSize = 0.8; // 每次调整的强度
        _cooldownTime = 1000; // 1秒冷却时间
        _lastApplyTime = 0;
        
        // 保存原始画质设置
        _originalQuality = _root._quality || "HIGH";
        
        // 初始化到默认设置
        _applyQualitySettings(_currentLevel);
    }
    
    /**
     * 应用性能调整动作
     * @param action 性能调整动作
     */
    public function apply(action:PerformanceAction):Void {
        if (!action.shouldAdjust()) {
            return;
        }
        
        // 冷却时间检查
        var currentTime:Number = getTimer();
        if (currentTime - _lastApplyTime < _cooldownTime) {
            return;
        }
        
        // 计算新的性能等级
        var newLevel:Number = _calculateNewLevel(action);
        
        // 只有等级真正改变时才应用
        if (Math.round(newLevel) != Math.round(_currentLevel)) {
            _currentLevel = newLevel;
            var discreteLevel:Number = Math.round(_currentLevel);
            discreteLevel = Math.max(_minLevel, Math.min(discreteLevel, _maxLevel));
            
            _applyQualitySettings(discreteLevel);
            _lastApplyTime = currentTime;
            
            // 发布调整事件
            _root.发布消息("性能等级调整: " + discreteLevel + " (FPS: " + 
                          action.currentFPS + "/" + action.targetFPS + ")");
        }
    }
    
    /**
     * 计算新的性能等级
     */
    private function _calculateNewLevel(action:PerformanceAction):Number {
        var adjustment:Number = action.magnitude * _stepSize;
        var newLevel:Number = _currentLevel;
        
        if (action.trend == "UP") {
            // 性能不足，提高性能等级（降低画质）
            newLevel += adjustment;
        } else if (action.trend == "DOWN") {
            // 性能过剩，降低性能等级（提高画质）
            newLevel -= adjustment;
        }
        
        return Math.max(_minLevel, Math.min(newLevel, _maxLevel));
    }
    
    /**
     * 应用具体的画质设置
     * @param level 性能等级
     */
    private function _applyQualitySettings(level:Number):Void {
        switch (level) {
            case 0: // 高画质
                _applyHighQuality();
                break;
            case 1: // 中画质
                _applyMediumQuality();
                break;
            case 2: // 低画质
                _applyLowQuality();
                break;
            default: // 最低画质
                _applyMinimumQuality();
                break;
        }
        
        // 应用渲染器设置
        _applyRendererSettings(level);
    }
    
    /**
     * 高画质设置
     */
    private function _applyHighQuality():Void {
        if (EffectSystem) {
            EffectSystem.maxEffectCount = 20;
            EffectSystem.maxScreenEffectCount = 20;
            EffectSystem.isDeathEffect = true;
            DeathEffectRenderer.isEnabled = true;
            DeathEffectRenderer.enableCulling = false;
        }
        
        _root.面积系数 = 300000;
        _root.同屏打击数字特效上限 = 25;
        _root._quality = _originalQuality;
        
        if (_root.天气系统) {
            _root.天气系统.光照等级更新阈值 = 0.1;
        }
        
        if (ShellSystem && ShellSystem.setMaxShellCountLimit) {
            ShellSystem.setMaxShellCountLimit(25);
        }
        
        _root.发射效果上限 = 15;
        
        if (_root.显示列表 && _root.显示列表.继续播放) {
            _root.显示列表.继续播放(_root.显示列表.预设任务ID);
        }
        
        if (_root.UI系统) {
            _root.UI系统.经济面板动效 = true;
        }
        
        _root.帧计时器.offsetTolerance = 10;
    }
    
    /**
     * 中画质设置
     */
    private function _applyMediumQuality():Void {
        if (EffectSystem) {
            EffectSystem.maxEffectCount = 15;
            EffectSystem.maxScreenEffectCount = 15;
            EffectSystem.isDeathEffect = true;
            DeathEffectRenderer.isEnabled = true;
            DeathEffectRenderer.enableCulling = true;
        }
        
        _root.面积系数 = 450000;
        _root.同屏打击数字特效上限 = 18;
        _root._quality = (_originalQuality === 'LOW') ? _originalQuality : 'MEDIUM';
        
        if (_root.天气系统) {
            _root.天气系统.光照等级更新阈值 = 0.2;
        }
        
        if (ShellSystem && ShellSystem.setMaxShellCountLimit) {
            ShellSystem.setMaxShellCountLimit(18);
        }
        
        _root.发射效果上限 = 10;
        
        if (_root.显示列表 && _root.显示列表.继续播放) {
            _root.显示列表.继续播放(_root.显示列表.预设任务ID);
        }
        
        if (_root.UI系统) {
            _root.UI系统.经济面板动效 = true;
        }
        
        _root.帧计时器.offsetTolerance = 30;
    }
    
    /**
     * 低画质设置
     */
    private function _applyLowQuality():Void {
        if (EffectSystem) {
            EffectSystem.maxEffectCount = 10;
            EffectSystem.maxScreenEffectCount = 10;
            EffectSystem.isDeathEffect = false;
            DeathEffectRenderer.isEnabled = false;
            DeathEffectRenderer.enableCulling = true;
        }
        
        _root.面积系数 = 600000;
        _root.同屏打击数字特效上限 = 12;
        _root._quality = 'LOW';
        
        if (_root.天气系统) {
            _root.天气系统.光照等级更新阈值 = 0.5;
        }
        
        if (ShellSystem && ShellSystem.setMaxShellCountLimit) {
            ShellSystem.setMaxShellCountLimit(12);
        }
        
        _root.发射效果上限 = 5;
        
        if (_root.显示列表 && _root.显示列表.暂停播放) {
            _root.显示列表.暂停播放(_root.显示列表.预设任务ID);
        }
        
        if (_root.UI系统) {
            _root.UI系统.经济面板动效 = false;
        }
        
        _root.帧计时器.offsetTolerance = 50;
    }
    
    /**
     * 最低画质设置
     */
    private function _applyMinimumQuality():Void {
        if (EffectSystem) {
            EffectSystem.maxEffectCount = 0;
            EffectSystem.maxScreenEffectCount = 5;
            EffectSystem.isDeathEffect = false;
            DeathEffectRenderer.isEnabled = false;
            DeathEffectRenderer.enableCulling = true;
        }
        
        _root.面积系数 = 3000000;
        _root.同屏打击数字特效上限 = 10;
        _root._quality = 'LOW';
        
        if (_root.天气系统) {
            _root.天气系统.光照等级更新阈值 = 1;
        }
        
        if (ShellSystem && ShellSystem.setMaxShellCountLimit) {
            ShellSystem.setMaxShellCountLimit(10);
        }
        
        _root.发射效果上限 = 0;
        
        if (_root.显示列表 && _root.显示列表.暂停播放) {
            _root.显示列表.暂停播放(_root.显示列表.预设任务ID);
        }
        
        if (_root.UI系统) {
            _root.UI系统.经济面板动效 = false;
        }
        
        _root.帧计时器.offsetTolerance = 80;
    }
    
    /**
     * 应用渲染器设置
     */
    private function _applyRendererSettings(level:Number):Void {
        if (TrailRenderer && TrailRenderer.getInstance) {
            var trailRenderer = TrailRenderer.getInstance();
            if (trailRenderer.setQuality) {
                trailRenderer.setQuality(level);
            }
        }
        
        if (ClipFrameRenderer && ClipFrameRenderer.setPerformanceLevel) {
            ClipFrameRenderer.setPerformanceLevel(level);
        }
        
        if (BladeMotionTrailsRenderer && BladeMotionTrailsRenderer.setPerformanceLevel) {
            BladeMotionTrailsRenderer.setPerformanceLevel(level);
        }
    }
    
    /**
     * 获取当前性能等级
     */
    public function getCurrentLevel():Number {
        return Math.round(_currentLevel);
    }
    
    /**
     * 强制设置性能等级
     * @param level 目标等级
     */
    public function forceSetLevel(level:Number):Void {
        level = Math.max(_minLevel, Math.min(level, _maxLevel));
        _currentLevel = level;
        _applyQualitySettings(level);
        _lastApplyTime = getTimer();
    }
    
    /**
     * 重置到默认设置
     */
    public function reset():Void {
        _currentLevel = 0;
        _lastApplyTime = 0;
        _applyQualitySettings(0);
    }
    
    /**
     * 设置调整步长
     */
    public function setStepSize(size:Number):Void {
        if (!isNaN(size) && size > 0) {
            _stepSize = size;
        }
    }
    
    /**
     * 设置冷却时间
     */
    public function setCooldownTime(time:Number):Void {
        if (!isNaN(time) && time >= 0) {
            _cooldownTime = time;
        }
    }
}