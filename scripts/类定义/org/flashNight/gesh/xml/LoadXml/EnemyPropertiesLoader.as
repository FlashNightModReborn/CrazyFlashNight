import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

class org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader extends BaseXMLLoader {
    private static var instance:EnemyPropertiesLoader = null;
    private static var path:String = "data/enemy_properties/";
    private var combinedData:Object = null;

    /**
     * 获取单例实例。
     * @return EnemyPropertiesLoader 实例。
     */
    public static function getInstance():EnemyPropertiesLoader {
        if (instance == null) {
            instance = new EnemyPropertiesLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function EnemyPropertiesLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现敌人属性的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadEnemyProperties(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadEnemyProperties(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:EnemyPropertiesLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            // trace("EnemyPropertiesLoader: list.xml 文件加载成功！");
            // trace("EnemyPropertiesLoader: list.xml 数据 = " + ObjectUtil.toString(data));

            if (!data || !data.items || !(data.items instanceof Array)) {
                // trace("EnemyPropertiesLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            var childXmlPaths:Array = data.items;
            // trace("EnemyPropertiesLoader: 需要加载的子 XML 文件列表 = " + ObjectUtil.toString(childXmlPaths));

            self.combinedData = {};

            // 开始加载子 XML 文件
            self.loadChildXmlFiles(childXmlPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = self.combinedData;

                // trace("EnemyPropertiesLoader: 所有子 XML 文件加载并合并成功！");
                // trace("EnemyPropertiesLoader: 合并后的数据 = " + ObjectUtil.toString(self.combinedData));
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }, function():Void {
                // trace("EnemyPropertiesLoader: 加载子 XML 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            // trace("EnemyPropertiesLoader: list.xml 文件加载失败！");
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 递归加载子 XML 文件并合并数据。
     * @param paths 子 XML 文件路径数组。
     * @param index 当前加载的文件索引。
     * @param onComplete 所有文件加载完成的回调函数。
     * @param onError 加载失败的回调函数。
     */
    private function loadChildXmlFiles(paths:Array, index:Number, onComplete:Function, onError:Function):Void {
        var self:EnemyPropertiesLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var xmlFileName:String = paths[index];
        var xmlFilePath:String = path + xmlFileName;
        // trace("EnemyPropertiesLoader: 准备加载子 XML 文件 = " + xmlFilePath);

        var loader:BaseXMLLoader = new BaseXMLLoader(xmlFilePath);

        loader.load(function(childData:Object):Void {
            // trace("EnemyPropertiesLoader: 子 XML 文件加载成功 = " + xmlFilePath);
            // trace("EnemyPropertiesLoader: 子 XML 数据 = " + ObjectUtil.toString(childData));

            // 假设 childData 包含多个敌人属性，直接合并到 combinedData 中
            for (var enemyName:String in childData) {
                if (childData.hasOwnProperty(enemyName)) {
                    // trace("EnemyPropertiesLoader: 合并敌人数据，敌人名称 = " + enemyName);
                    self.combinedData[enemyName] = childData[enemyName];
                }
            }

            // 递归加载下一个文件
            self.loadChildXmlFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            // trace("EnemyPropertiesLoader: 子 XML 文件加载失败 = " + xmlFilePath);
            onError();
        });
    }

    /**
     * 获取已加载的敌人属性数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getEnemyPropertiesData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现敌人属性数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的敌人属性数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.EnemyPropertiesLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 EnemyPropertiesLoader 实例
var enemyPropertiesLoader:EnemyPropertiesLoader = EnemyPropertiesLoader.getInstance();

// 加载敌人属性数据
enemyPropertiesLoader.loadEnemyProperties(
    function(combinedData:Object):Void {
        trace("主程序：敌人属性数据加载成功！");
        trace("合并后的数据: " + ObjectUtil.toString(combinedData));
        // 在此处处理合并后的敌人属性数据
    },
    function():Void {
        trace("主程序：敌人属性数据加载失败！");
    }
);

*/