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
        var self:MissileConfigLoader = this;
        
        this.load(function(data:Object):Void {
            var parsedConfigs:Object = {};
            
            // XMLParser 解析后，结果结构是：
            // { config: [ { name: "default", initialSpeedRatio: 0.5, ... }, ... ] }
            // 注意：同名节点会被转换为数组
            
            // 确认是否有 config 节点
            if (data.config != undefined) {
                // 处理 config 节点，可能是单个对象或数组
                var configNodes = data.config;
                
                // 如果不是数组，转换为数组以统一处理
                if (!(configNodes instanceof Array)) {
                    configNodes = [configNodes];
                }
                
                // 遍历所有配置节点
                for (var i:Number = 0; i < configNodes.length; i++) {
                    var configNode:Object = configNodes[i];
                    if (configNode.name != undefined) {
                        parsedConfigs[configNode.name] = self.parseConfigNode(configNode);
                    }
                }
            }
            
            self.configs = parsedConfigs;
            if (onLoadHandler != null) onLoadHandler(self.configs);
            
        }, function():Void {
            _root.服务器.发布服务器消息("MissileConfigLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 解析单个配置节点
     * @param node 配置节点对象
     * @return Object 解析后的配置对象
     */
    private function parseConfigNode(node:Object):Object {
        var config:Object = {};
        
        // 直接从节点复制属性，XMLParser 已经做了类型转换
        config.initialSpeedRatio = node.initialSpeedRatio;
        config.rotationSpeed = node.rotationSpeed;
        config.acceleration = node.acceleration;
        config.dragCoefficient = node.dragCoefficient;
        config.rotationShakeAmplitude = node.rotationShakeAmplitude;
        config.searchBatchSize = node.searchBatchSize;
        config.searchRange = node.searchRange;
        config.navigationRatio = node.navigationRatio;
        config.angleCorrection = node.angleCorrection;

        // 处理嵌套对象属性
        if (node.preLaunchFrames != undefined) {
            config.preLaunchFrames = {
                min: node.preLaunchFrames.min,
                max: node.preLaunchFrames.max
            };
        }

        if (node.preLaunchPeakHeight != undefined) {
            config.preLaunchPeakHeight = {
                min: node.preLaunchPeakHeight.min,
                max: node.preLaunchPeakHeight.max
            };
        }

        if (node.preLaunchHorizAmp != undefined) {
            config.preLaunchHorizAmp = {
                min: node.preLaunchHorizAmp.min,
                max: node.preLaunchHorizAmp.max
            };
        }

        if (node.preLaunchCycles != undefined) {
            config.preLaunchCycles = {
                min: node.preLaunchCycles.min,
                max: node.preLaunchCycles.max
            };
        }

        if (node.rotationShakeTime != undefined) {
            config.rotationShakeTime = {
                start: node.rotationShakeTime.start,
                end: node.rotationShakeTime.end
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