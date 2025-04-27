// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/MissileConfig.as

/**
 * 导弹配置类
 * 用于存储和管理导弹的各种性能参数配置
 * 通过预设配置和自定义参数，使导弹系统具有高度灵活性
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.MissileConfig {
    
    // 初始化参数
    /** 初始速度与最大速度的比例，范围 0-1 */
    public var initialSpeedRatio:Number = 0.5;
    /** 每帧最大旋转角度（度） */
    public var rotationSpeed:Number = 1;
    /** 加速度，单位/帧 */
    public var acceleration:Number = 10;
    
    // 预发射动画参数
    /** 预发射动画帧数范围 */
    public var preLaunchFrames:Object = {min: 10, max: 15};
    /** 预发射抛物线高度范围（单位） */
    public var preLaunchPeakHeight:Object = {min: 20, max: 60};
    /** 水平振幅范围（单位） */
    public var preLaunchHorizAmp:Object = {min: 0, max: 8};
    /** 振荡周期范围（次） */
    public var preLaunchCycles:Object = {min: 1, max: 3};
    /** 旋转抖动时间窗口（0-1之间的归一化时间） */
    public var rotationShakeTime:Object = {start: 0.35, end: 0.45};
    /** 旋转抖动幅度（弧度） */
    public var rotationShakeAmplitude:Number = 0.4;
    
    // 搜索行为参数
    /** 每帧处理的目标数量（性能优化参数） */
    public var searchBatchSize:Number = 8;
    /** 目标搜索范围（单位） */
    public var searchRange:Number = 30;
    
    // 追踪行为参数
    /** 比例导引系数（Proportional Navigation Ratio） */
    public var navigationRatio:Number = 4;
    /** 角度差修正系数（用于平滑转向） */
    public var angleCorrection:Number = 0.1;
    
    /**
     * 构造函数，允许创建自定义配置
     */
    public function MissileConfig() {
        // 默认构造函数，使用默认值
    }
    
    /**
     * 创建标准配置的实例
     * @return MissileConfig 新的配置实例
     */
    public static function create():MissileConfig {
        return new MissileConfig();
    }
    
    /**
     * 创建自定义配置
     * @param settings 配置对象，包含要覆盖的参数
     * @return MissileConfig 配置实例
     */
    public static function createCustom(settings:Object):MissileConfig {
        var config:MissileConfig = new MissileConfig();
        for (var key:String in settings) {
            if (config.hasOwnProperty(key)) {
                config[key] = settings[key];
            }
        }
        return config;
    }
    
    // 预设配置：高速拦截导弹
    public static var INTERCEPTOR:MissileConfig = createCustom({
        initialSpeedRatio: 0.8,
        rotationSpeed: 2,
        acceleration: 15,
        preLaunchFrames: {min: 5, max: 8},
        preLaunchPeakHeight: {min: 10, max: 20},
        navigationRatio: 3,
        angleCorrection: 0.15
    });
    
    // 预设配置：巡航导弹
    public static var CRUISE:MissileConfig = createCustom({
        initialSpeedRatio: 0.3,
        rotationSpeed: 0.5,
        acceleration: 5,
        preLaunchFrames: {min: 15, max: 20},
        preLaunchPeakHeight: {min: 30, max: 80},
        navigationRatio: 5,
        angleCorrection: 0.05,
        searchRange: 50
    });
    
    // 预设配置：多管火箭
    public static var ROCKET:MissileConfig = createCustom({
        initialSpeedRatio: 0.6,
        rotationSpeed: 1.5,
        acceleration: 12,
        preLaunchFrames: {min: 3, max: 5},
        preLaunchPeakHeight: {min: 5, max: 15},
        preLaunchHorizAmp: {min: 10, max: 20},
        navigationRatio: 2,
        angleCorrection: 0.2,
        searchBatchSize: 4
    });
}