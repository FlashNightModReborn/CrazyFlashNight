import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

class org.flashNight.gesh.xml.LoadXml.EquipModListLoader extends BaseXMLLoader {
    private static var instance:EquipModListLoader = null;
    private static var path:String = "data/items/equipment_mods/";
    private var combinedData:Array = null;

    /**
     * 获取单例实例。
     * @return EquipModListLoader 实例。
     */
    public static function getInstance():EquipModListLoader {
        if (instance == null) {
            instance = new EquipModListLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function EquipModListLoader() { 
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现配件数据的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadModData(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadModData(onLoadHandler:Function, onErrorHandler:Function):Void {
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler({mod: this.combinedData});
            return;
        }
        var self:EquipModListLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.items) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.items);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                mergeFn:      ListLoader.concatField("mod"),
                initialValue: []
            }).then(function(result:Object):Void {
                var arr = result;
                self.combinedData = arr;
                trace("EquipModListLoader: 合并后的配件数量 = " + self.combinedData.length);
                if (onLoadHandler != null) {
                    onLoadHandler({mod: self.combinedData});
                }
            }).onCatch(function(reason:Object):Void {
                trace("[EquipModListLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的配件数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getModData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现配件数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的配件数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return {mod: this.combinedData};
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.EquipModListLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 EquipModListLoader 实例
var modListLoader:EquipModListLoader = EquipModListLoader.getInstance();

// 加载配件数据
modListLoader.loadModData(
    function(data:Object):Void {
        trace("主程序：装备配件数据加载成功！");
        trace("主程序：配件总数 = " + data.mod.length);

        // 传递给 EquipmentUtil 进行初始化
        org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    function():Void {
        trace("主程序：装备配件数据加载失败！");
    }
);

*/
