import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

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
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadEnemyProperties(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:EnemyPropertiesLoader = this;

        // super.load() 读取 list.xml（保留 BaseXMLLoader 实例缓存）
        super.load(function(data:Object):Void {
            if (!data || !data.items) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.items);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                mergeFn:      ListLoader.dictMerge(),
                initialValue: {}
            }).then(function(result:Object):Void {
                self.combinedData = result;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }).onCatch(function(reason:Object):Void {
                trace("[EnemyPropertiesLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
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
        trace("合并后的数据: " + ObjectUtil.stringify(combinedData));
        // 在此处处理合并后的敌人属性数据
    },
    function():Void {
        trace("主程序：敌人属性数据加载失败！");
    }
);

*/