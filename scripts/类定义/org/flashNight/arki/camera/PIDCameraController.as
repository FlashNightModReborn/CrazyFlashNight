/**
 * PIDCameraController.as - 基于PID控制的高级摄像机控制器
 * 
 * 升级特性：
 * 1. 使用PID控制器替代简单缓动，提供更精确的控制
 * 2. 分别控制缩放、水平滚动、垂直滚动的PID参数
 * 3. 动态参数调整，根据游戏状态自适应
 * 4. 预设配置文件，快速切换不同控制风格
 */

import org.flashNight.neur.Controller.PIDController;

class org.flashNight.arki.camera.PIDCameraController {
    
    // ==================== PID控制器实例 ====================
    private static var zoomPID:PIDController;        // 缩放控制PID
    private static var scrollXPID:PIDController;     // 水平滚动PID  
    private static var scrollYPID:PIDController;     // 垂直滚动PID
    
    // ==================== PID参数预设 ====================
    private static var _pidProfiles:Object;
    private static var _currentProfile:String = "balanced";
    
    // ==================== 状态管理 ====================
    private static var _lastUpdateTime:Number = 0;
    private static var _isInitialized:Boolean = false;
    private static var _debugMode:Boolean = false;
    
    // ==================== 目标值跟踪 ====================
    private static var _targetZoomScale:Number = 1.0;
    private static var _targetScrollX:Number = 0;
    private static var _targetScrollY:Number = 0;
    
    // ==================== 初始化方法 ====================
    
    /**
     * 初始化PID摄像机控制器
     */
    public static function initialize():Void {
        _initializePIDProfiles();
        _createPIDControllers();
        _lastUpdateTime = getTimer();
        _isInitialized = true;
        
        _logDebug("PID Camera Controller initialized");
    }
    
    /**
     * 初始化PID参数预设配置
     */
    private static function _initializePIDProfiles():Void {
        _pidProfiles = {};
        
        // 平衡模式 - 响应速度与平滑度兼顾
        _pidProfiles.balanced = {
            zoom: { kp: 2.0, ki: 0.1, kd: 0.5, integralMax: 100, derivativeFilter: 0.1 },
            scrollX: { kp: 1.5, ki: 0.05, kd: 0.3, integralMax: 500, derivativeFilter: 0.15 },
            scrollY: { kp: 1.2, ki: 0.03, kd: 0.25, integralMax: 300, derivativeFilter: 0.12 }
        };
        
        // 快速响应模式 - 追求快速反应
        _pidProfiles.responsive = {
            zoom: { kp: 3.5, ki: 0.2, kd: 0.8, integralMax: 80, derivativeFilter: 0.08 },
            scrollX: { kp: 2.5, ki: 0.1, kd: 0.6, integralMax: 400, derivativeFilter: 0.1 },
            scrollY: { kp: 2.0, ki: 0.08, kd: 0.5, integralMax: 250, derivativeFilter: 0.09 }
        };
        
        // 平滑模式 - 追求平滑过渡
        _pidProfiles.smooth = {
            zoom: { kp: 1.2, ki: 0.05, kd: 0.3, integralMax: 150, derivativeFilter: 0.2 },
            scrollX: { kp: 0.8, ki: 0.02, kd: 0.2, integralMax: 600, derivativeFilter: 0.25 },
            scrollY: { kp: 0.6, ki: 0.015, kd: 0.15, integralMax: 400, derivativeFilter: 0.2 }
        };
        
        // 电影模式 - 极其平滑，适合过场动画
        _pidProfiles.cinematic = {
            zoom: { kp: 0.8, ki: 0.02, kd: 0.2, integralMax: 200, derivativeFilter: 0.3 },
            scrollX: { kp: 0.5, ki: 0.01, kd: 0.1, integralMax: 800, derivativeFilter: 0.35 },
            scrollY: { kp: 0.4, ki: 0.008, kd: 0.08, integralMax: 500, derivativeFilter: 0.3 }
        };
        
        // 竞技模式 - 快速准确，适合射击类游戏
        _pidProfiles.competitive = {
            zoom: { kp: 4.0, ki: 0.3, kd: 1.0, integralMax: 60, derivativeFilter: 0.05 },
            scrollX: { kp: 3.0, ki: 0.15, kd: 0.8, integralMax: 300, derivativeFilter: 0.08 },
            scrollY: { kp: 2.5, ki: 0.12, kd: 0.7, integralMax: 200, derivativeFilter: 0.06 }
        };
    }
    
    /**
     * 创建PID控制器实例
     */
    private static function _createPIDControllers():Void {
        var profile:Object = _pidProfiles[_currentProfile];
        
        zoomPID = new PIDController(
            profile.zoom.kp, profile.zoom.ki, profile.zoom.kd,
            profile.zoom.integralMax, profile.zoom.derivativeFilter
        );
        
        scrollXPID = new PIDController(
            profile.scrollX.kp, profile.scrollX.ki, profile.scrollX.kd,
            profile.scrollX.integralMax, profile.scrollX.derivativeFilter
        );
        
        scrollYPID = new PIDController(
            profile.scrollY.kp, profile.scrollY.ki, profile.scrollY.kd,
            profile.scrollY.integralMax, profile.scrollY.derivativeFilter
        );
    }
    
    // ==================== 核心更新方法 ====================
    
    /**
     * 更新缩放控制（替代原有的简单缓动）
     * @param currentScale 当前缩放值
     * @param targetScale 目标缩放值  
     * @return Number 新的缩放值
     */
    public static function updateZoomScale(currentScale:Number, targetScale:Number):Number {
        if (!_isInitialized) {
            initialize();
        }
        
        var currentTime:Number = getTimer();
        var deltaTime:Number = (currentTime - _lastUpdateTime) / 1000.0; // 转换为秒
        _lastUpdateTime = currentTime;
        
        // 防止异常的deltaTime
        if (deltaTime <= 0 || deltaTime > 0.1) {
            deltaTime = 1.0 / 60.0; // 默认60FPS
        }
        
        _targetZoomScale = targetScale;
        
        // 使用PID控制器计算输出
        var pidOutput:Number = zoomPID.update(targetScale, currentScale, deltaTime);
        var newScale:Number = currentScale + pidOutput * deltaTime;
        
        // 安全限制
        newScale = Math.max(0.1, Math.min(5.0, newScale));
        
        _logDebug("Zoom PID: current=" + currentScale.toFixed(3) + 
                 ", target=" + targetScale.toFixed(3) + 
                 ", output=" + pidOutput.toFixed(3) + 
                 ", new=" + newScale.toFixed(3));
        
        return newScale;
    }
    
    /**
     * 更新水平滚动控制
     * @param currentX 当前X坐标
     * @param targetX 目标X坐标
     * @return Number X坐标增量
     */
    public static function updateScrollX(currentX:Number, targetX:Number):Number {
        if (!_isInitialized) return 0;
        
        var currentTime:Number = getTimer();
        var deltaTime:Number = (currentTime - _lastUpdateTime) / 1000.0;
        
        if (deltaTime <= 0 || deltaTime > 0.1) {
            deltaTime = 1.0 / 60.0;
        }
        
        _targetScrollX = targetX;
        
        var pidOutput:Number = scrollXPID.update(targetX, currentX, deltaTime);
        
        _logDebug("ScrollX PID: current=" + currentX.toFixed(1) + 
                 ", target=" + targetX.toFixed(1) + 
                 ", output=" + pidOutput.toFixed(3));
        
        return pidOutput * deltaTime;
    }
    
    /**
     * 更新垂直滚动控制
     * @param currentY 当前Y坐标
     * @param targetY 目标Y坐标
     * @return Number Y坐标增量
     */
    public static function updateScrollY(currentY:Number, targetY:Number):Number {
        if (!_isInitialized) return 0;
        
        var currentTime:Number = getTimer();
        var deltaTime:Number = (currentTime - _lastUpdateTime) / 1000.0;
        
        if (deltaTime <= 0 || deltaTime > 0.1) {
            deltaTime = 1.0 / 60.0;
        }
        
        _targetScrollY = targetY;
        
        var pidOutput:Number = scrollYPID.update(targetY, currentY, deltaTime);
        
        _logDebug("ScrollY PID: current=" + currentY.toFixed(1) + 
                 ", target=" + targetY.toFixed(1) + 
                 ", output=" + pidOutput.toFixed(3));
        
        return pidOutput * deltaTime;
    }
    
    // ==================== 配置管理 ====================
    
    /**
     * 切换PID控制预设
     * @param profileName 预设名称："balanced", "responsive", "smooth", "cinematic", "competitive"
     * @return Boolean 是否切换成功
     */
    public static function setProfile(profileName:String):Boolean {
        if (!_pidProfiles[profileName]) {
            _logError("PID profile not found: " + profileName);
            return false;
        }
        
        _currentProfile = profileName;
        
        if (_isInitialized) {
            // 重新创建PID控制器
            _createPIDControllers();
            _logDebug("Switched to PID profile: " + profileName);
        }
        
        return true;
    }
    
    /**
     * 获取当前配置名称
     */
    public static function getCurrentProfile():String {
        return _currentProfile;
    }
    
    /**
     * 获取可用的配置列表
     */
    public static function getAvailableProfiles():Array {
        var profiles:Array = [];
        for (var name:String in _pidProfiles) {
            profiles.push(name);
        }
        return profiles;
    }
    
    /**
     * 动态调整单个PID控制器参数
     * @param controller "zoom", "scrollX", "scrollY"
     * @param kp 比例增益
     * @param ki 积分增益  
     * @param kd 微分增益
     */
    public static function tunePID(controller:String, kp:Number, ki:Number, kd:Number):Boolean {
        var pidController:PIDController;
        
        switch (controller.toLowerCase()) {
            case "zoom":
                pidController = zoomPID;
                break;
            case "scrollx":
                pidController = scrollXPID;
                break;
            case "scrolly":
                pidController = scrollYPID;
                break;
            default:
                _logError("Unknown PID controller: " + controller);
                return false;
        }
        
        if (pidController) {
            pidController.setKp(kp);
            pidController.setKi(ki);
            pidController.setKd(kd);
            _logDebug("Tuned " + controller + " PID: kp=" + kp + ", ki=" + ki + ", kd=" + kd);
            return true;
        }
        
        return false;
    }
    
    /**
     * 重置所有PID控制器状态
     */
    public static function resetAllPID():Void {
        if (zoomPID) zoomPID.reset();
        if (scrollXPID) scrollXPID.reset();
        if (scrollYPID) scrollYPID.reset();
        _logDebug("All PID controllers reset");
    }
    
    /**
     * 根据游戏状态自动调整PID参数
     * @param gameState 游戏状态："combat", "exploration", "cutscene", "menu"
     */
    public static function adaptToGameState(gameState:String):Void {
        switch (gameState.toLowerCase()) {
            case "combat":
                setProfile("competitive");
                break;
            case "exploration":
                setProfile("balanced");
                break;
            case "cutscene":
                setProfile("cinematic");
                break;
            case "menu":
                setProfile("smooth");
                break;
            default:
                _logDebug("Unknown game state, keeping current profile");
        }
    }
    
    // ==================== 调试和监控 ====================
    
    /**
     * 获取PID控制器状态信息
     */
    public static function getPIDStatus():Object {
        if (!_isInitialized) return null;
        
        return {
            profile: _currentProfile,
            targets: {
                zoom: _targetZoomScale,
                scrollX: _targetScrollX,
                scrollY: _targetScrollY
            },
            integrals: {
                zoom: zoomPID.getIntegral(),
                scrollX: scrollXPID.getIntegral(),
                scrollY: scrollYPID.getIntegral()
            },
            controllers: {
                zoom: zoomPID.toString(),
                scrollX: scrollXPID.toString(),
                scrollY: scrollYPID.toString()
            }
        };
    }
    
    /**
     * 设置调试模式
     */
    public static function setDebugMode(enabled:Boolean):Void {
        _debugMode = enabled;
    }
    
    /**
     * 输出性能指标
     */
    public static function getPerformanceMetrics():Object {
        var status:Object = getPIDStatus();
        
        return {
            profileName: _currentProfile,
            maxIntegral: Math.max(
                Math.abs(status.integrals.zoom),
                Math.abs(status.integrals.scrollX),
                Math.abs(status.integrals.scrollY)
            ),
            targetDeviation: {
                zoom: Math.abs(_targetZoomScale - 1.0),
                scrollX: Math.abs(_targetScrollX),
                scrollY: Math.abs(_targetScrollY)
            }
        };
    }
    
    // ==================== 辅助方法 ====================
    
    private static function _logDebug(message:String):Void {
        if (_debugMode) {
            _root.发布消息("[PID Camera DEBUG] " + message);
        }
    }
    
    private static function _logError(message:String):Void {
        _root.发布消息("[PID Camera ERROR] " + message);
    }
}

