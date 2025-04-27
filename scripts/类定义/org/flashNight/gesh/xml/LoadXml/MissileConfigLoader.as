// 文件路径：org/flashNight/gesh/xml/LoadXml/MissileConfigLoader.as

import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

/**
 * 导弹配置加载器（单例）
 * =====================
 * 负责从XML文件加载导弹配置数据
 * 
 * 职责：
 *   - 加载并解析missileConfigs.xml文件
 *   - 将XML数据转换为配置对象
 *   - 提供配置数据的访问接口
 * 
 * 备注：
 *   - 继承自BaseXMLLoader基类
 *   - XML文件位置：data/items/missileConfigs.xml
 */
class org.flashNight.gesh.xml.LoadXml.MissileConfigLoader extends BaseXMLLoader {
    private static var instance:MissileConfigLoader = null;
    private var configs:Object = null;

    /**
     * 获取单例实例
     * @return MissileConfigLoader 实例
     */
    public static function getInstance():MissileConfigLoader {
        if (instance == null) {
            instance = new MissileConfigLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 missileConfigs.xml 的相对路径
     */
    private function MissileConfigLoader() {
        super("data/items/missileConfigs.xml");
    }

    /**
     * 加载 missileConfigs.xml 文件
     * @param onLoadHandler 加载成功后的回调函数，接收解析后的配置对象
     * @param onErrorHandler 加载失败后的回调函数
     */
    public function loadConfigs(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.load(function(data:Object):Void {
            var configNodes:Object = data.config;
            var parsedConfigs:Object = {};
            
            for (var key:String in configNodes) {
                var configNode:Object = configNodes[key];
                parsedConfigs[configNode.name] = parseConfigNode(configNode);
            }
            
            this.configs = parsedConfigs;
            if (onLoadHandler != null) onLoadHandler(this.configs);
            
        }, function():Void {
            _root.服务器.发布服务器消息("MissileConfigLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 解析单个配置节点
     * @param node XML节点
     * @return Object 解析后的配置对象
     */
    private function parseConfigNode(node:Object):Object {
        var config:Object = {};
        
        // 解析基础数值属性
        config.initialSpeedRatio = Number(node.initialSpeedRatio) || 0.5;
        config.rotationSpeed = Number(node.rotationSpeed) || 1;
        config.acceleration = Number(node.acceleration) || 10;
        config.dragCoefficient = Number(node.dragCoefficient) || 0.001;
        config.rotationShakeAmplitude = Number(node.rotationShakeAmplitude) || 0.4;
        config.searchBatchSize = Number(node.searchBatchSize) || 8;
        config.searchRange = Number(node.searchRange) || 30;
        config.navigationRatio = Number(node.navigationRatio) || 4;
        config.angleCorrection = Number(node.angleCorrection) || 0.1;

        // 解析复杂对象属性
        if (node.preLaunchFrames) {
            config.preLaunchFrames = {
                min: Number(node.preLaunchFrames.min) || 10,
                max: Number(node.preLaunchFrames.max) || 15
            };
        }

        if (node.preLaunchPeakHeight) {
            config.preLaunchPeakHeight = {
                min: Number(node.preLaunchPeakHeight.min) || 20,
                max: Number(node.preLaunchPeakHeight.max) || 60
            };
        }

        if (node.preLaunchHorizAmp) {
            config.preLaunchHorizAmp = {
                min: Number(node.preLaunchHorizAmp.min) || 0,
                max: Number(node.preLaunchHorizAmp.max) || 8
            };
        }

        if (node.preLaunchCycles) {
            config.preLaunchCycles = {
                min: Number(node.preLaunchCycles.min) || 1,
                max: Number(node.preLaunchCycles.max) || 3
            };
        }

        if (node.rotationShakeTime) {
            config.rotationShakeTime = {
                start: Number(node.rotationShakeTime.start) || 0.35,
                end: Number(node.rotationShakeTime.end) || 0.45
            };
        }

        return config;
    }

    /**
     * 获取已加载的配置数据
     * @return Object 配置对象，如果尚未加载，则返回 null
     */
    public function getConfigs():Object {
        return this.configs;
    }
}