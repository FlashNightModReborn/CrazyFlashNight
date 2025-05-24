// 文件路径：org/flashNight/arki/bullet/BulletComponent/Movement/Util/MissileConfig.as

import org.flashNight.gesh.xml.LoadXml.MissileConfigLoader;
import org.flashNight.gesh.object.*;

/**
 * 导弹配置管理器（单例）
 * =================
 * 通过XML文件加载和管理导弹配置参数
 * 
 * 责任：
 *   - 加载并缓存导弹配置数据
 *   - 提供按名称查询配置的接口
 *   - 支持运行时动态更新配置
 *   - 提供默认配置作为后备方案
 * 
 * 典型用法：
 *   var configMgr:MissileConfig = MissileConfig.getInstance();
 *   configMgr.loadConfigs();  // 游戏初始化时调用一次
 *   var config:Object = configMgr.getConfig("interceptor");  // 获取特定配置
 */
class org.flashNight.arki.bullet.BulletComponent.Movement.Util.MissileConfig {
    
    // --------------------------
    // 单例实现
    // --------------------------
    private static var _instance:MissileConfig;
    
    /**
     * 获取配置管理器单例
     * @return MissileConfig 管理器实例
     */
    public static function getInstance():MissileConfig {
        if (_instance == null) {
            _instance = new MissileConfig();
        }
        return _instance;
    }
    
    // --------------------------
    // 成员变量
    // --------------------------
    /** 配置缓存表：{ configName:String -> configObject:Object } */
    private var _configs:Object;
    
    /** 默认配置（备用） */
    private var _defaultConfig:Object = {
        initialSpeedRatio: 0.5,
        rotationSpeed: 1,
        acceleration: 10,
        dragCoefficient: 0.001,
        preLaunchFrames: {min: 10, max: 15},
        preLaunchPeakHeight: {min: 20, max: 60},
        preLaunchHorizAmp: {min: 0, max: 8},
        preLaunchCycles: {min: 1, max: 3},
        rotationShakeTime: {start: 0.35, end: 0.45},
        rotationShakeAmplitude: 0.4,
        searchBatchSize: 8,
        searchRange: 30,
        navigationRatio: 4,
        angleCorrection: 0.1
    };
    
    // --------------------------
    // 构造函数
    // --------------------------
    /**
     * 私有构造函数
     * 请通过 getInstance() 访问
     */
    private function MissileConfig() {
        _configs = { _default: _defaultConfig };
    }
    
    // --------------------------
    // 对外接口
    // --------------------------
    /**
     * 异步加载外部配置文件
     * @param onComplete 成功回调：function(configs:Object):Void
     * @param onError 失败回调：function():Void
     */
    public function loadConfigs(onComplete:Function, onError:Function):Void {
        var loader:MissileConfigLoader = MissileConfigLoader.getInstance();
        var self:MissileConfig = this;
        
        loader.loadConfigs(
            function(configs:Object):Void {
                // 合并到内部缓存，允许外部文件覆盖默认值
                _root.服务器.发布服务器消息("MissileConfig: 配置加载成功。");
                for (var key:String in configs) {
                    self._configs[key] = configs[key];
                }
                if (onComplete != undefined) onComplete(self._configs);
            },
            function():Void {
                // 失败时保持默认配置可用

                _root.服务器.发布服务器消息("MissileConfig: 配置加载失败，已回退到默认配置。");
                if (onError != undefined) onError();
            }
        );
    }
    
    /**
     * 读取指定名称的配置
     * @param configName 配置名称
     * @return 配置对象（若不存在则返回默认配置）
     */
    public function getConfig(configName:String):Object {
        // _root.服务器.发布服务器消息(configName + " " + (_configs[configName] != undefined));
        return _configs[configName] != undefined ? _configs[configName] : _configs["_default"];
    }
    
    /**
     * 运行时动态更新或新增配置
     * @param configName 配置名称
     * @param configObject 配置对象
     */
    public function updateConfig(configName:String, configObject:Object):Void {
        _configs[configName] = configObject;
    }
    
    /**
     * 获取所有配置（只读）
     * @return 配置对象集合
     */
    public function getAllConfigs():Object {
        return _configs;
    }
}