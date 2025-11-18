import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader extends BaseXMLLoader {
    private static var instance:EquipmentConfigLoader = null;
    private var parsedConfigData:Object = null;  // 缓存解析后的配置数据

    /**
     * 获取单例实例。
     * @return EquipmentConfigLoader 实例。
     */
    public static function getInstance():EquipmentConfigLoader {
        if (instance == null) {
            instance = new EquipmentConfigLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 equipment_config.xml 的相对路径。
     */
    private function EquipmentConfigLoader() {
        super("data/equipment/equipment_config.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现 equipment_config.xml 的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadEquipmentConfig(onLoadHandler, onErrorHandler);
    }

    /**
     * 加载 equipment_config.xml 文件。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadEquipmentConfig(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:EquipmentConfigLoader = this;

        // 如果已经解析过，直接返回缓存的数据
        if (self.parsedConfigData != null) {
            trace("EquipmentConfigLoader: 使用缓存的配置数据");
            if (onLoadHandler != null) onLoadHandler(self.parsedConfigData);
            return;
        }

        // 调用基类的 load 方法
        super.load(function(data:Object):Void {
            trace("EquipmentConfigLoader: 文件加载成功！");
            // trace("EquipmentConfigLoader: 原始数据 = " + ObjectUtil.toString(data));

            // 解析 LevelStatList
            var parsedData:Object = self.parseEquipmentConfig(data);

            // 缓存解析后的数据
            self.parsedConfigData = parsedData;
            // 同时保存到基类的 data 属性
            super.data = parsedData;

            if (onLoadHandler != null) onLoadHandler(parsedData);
        }, function():Void {
            trace("EquipmentConfigLoader: 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 解析装备配置数据，将 LevelStatList 转换为数组。
     * @param data 原始XML解析后的数据对象。
     * @return Object 包含 levelStatList 数组的对象。
     */
    private function parseEquipmentConfig(data:Object):Object {
        var result:Object = {};

        if (data == null || data.EquipmentConfig == null) {
            trace("EquipmentConfigLoader: 数据格式错误，EquipmentConfig节点不存在！");
            return result;
        }

        var config:Object = data.EquipmentConfig;

        // 解析 LevelStatList
        if (config.LevelStatList != null && config.LevelStatList.Level != null) {
            var levelNodes:Object = config.LevelStatList.Level;
            var levelArray:Array = [];

            // 确保 levelNodes 是数组
            if (!(levelNodes instanceof Array)) {
                levelNodes = [levelNodes];
            }

            // XMLParser 对于带属性但内容是纯数字的节点，会直接返回数字值
            // 因此 levelNode 直接就是数值，我们使用数组索引作为等级索引
            for (var i:Number = 0; i < levelNodes.length; i++) {
                var value:Number = Number(levelNodes[i]);
                if (!isNaN(value)) {
                    levelArray[i] = value;
                }
            }

            result.levelStatList = levelArray;
            trace("EquipmentConfigLoader: 成功解析 levelStatList，共 " + levelArray.length + " 个等级");
        } else {
            trace("EquipmentConfigLoader: LevelStatList 节点不存在或为空！");
        }

        return result;
    }

    /**
     * 获取已加载的装备配置数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getEquipmentConfig():Object {
        return this.parsedConfigData;
    }

    /**
     * 覆盖基类的 reload 方法，实现 equipment_config.xml 的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空缓存
        this.parsedConfigData = null;
        // 清空基类数据并重新加载
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回解析后的配置数据。
     * @return Object 解析后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.parsedConfigData;
    }
}


/*
使用示例：

import org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 EquipmentConfigLoader 实例
var equipconfig_loader:EquipmentConfigLoader = EquipmentConfigLoader.getInstance();

// 加载装备配置数据
equipconfig_loader.loadEquipmentConfig(
    function(data:Object):Void {
        trace("主程序：装备配置数据加载成功！");
        trace("配置数据: " + ObjectUtil.toString(data));
        // 传递给 EquipmentUtil
        org.flashNight.arki.item.EquipmentUtil.loadEquipmentConfig(data);
    },
    function():Void {
        trace("主程序：装备配置数据加载失败！");
    }
);

*/
