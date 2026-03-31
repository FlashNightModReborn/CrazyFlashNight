import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;
import org.flashNight.aven.Promise.ListLoader;

class org.flashNight.gesh.xml.LoadXml.ItemDataLoader extends BaseXMLLoader {
    private static var instance:ItemDataLoader = null;
    private static var path:String = "data/items/";
    private var combinedData:Array = null;

    /**
     * 获取单例实例。
     * @return ItemDataLoader 实例。
     */
    public static function getInstance():ItemDataLoader {
        if (instance == null) {
            instance = new ItemDataLoader();
        }
        return instance;
    }

    /**
     * 构造函数，指定 list.xml 的相对路径。
     */
    private function ItemDataLoader() {
        super(path + "list.xml");
    }

    /**
     * 覆盖基类的 load 方法，实现物品数据的加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function load(onLoadHandler:Function, onErrorHandler:Function):Void {
        this.loadItemData(onLoadHandler, onErrorHandler);
    }

    /**
     * 解析 list.xml 文件，根据其中内容，并行加载并合并子 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadItemData(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 子文件合并结果缓存：load() 幂等，reload() 清缓存后重跑
        if (this.combinedData != null) {
            if (onLoadHandler != null) onLoadHandler(this.combinedData);
            return;
        }
        var self:ItemDataLoader = this;

        super.load(function(data:Object):Void {
            if (!data || !data.items) {
                if (onErrorHandler != null) onErrorHandler();
                return;
            }
            var entries:Array = ListLoader.normalizeToArray(data.items);

            ListLoader.loadChildren({
                entries:      entries,
                basePath:     path,
                mergeFn:      ListLoader.concatField("item"),
                initialValue: []
            }).then(function(result:Object):Void {
                var arr = result;
                self.combinedData = arr;
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }).onCatch(function(reason:Object):Void {
                trace("[ItemDataLoader] " + reason);
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            if (onErrorHandler != null) onErrorHandler();
        });
    }

    /**
     * 获取已加载的物品数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getItemDataData():Object {
        return this.combinedData;
    }

    /**
     * 覆盖基类的 reload 方法，实现物品数据的重新加载逻辑。
     * @param onLoadHandler 加载成功后的回调函数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function reload(onLoadHandler:Function, onErrorHandler:Function):Void {
        // 清空现有数据
        this.combinedData = null;
        super.reload(onLoadHandler, onErrorHandler);
    }

    /**
     * 覆盖基类的 getData 方法，确保返回合并后的物品数据。
     * @return Object 合并后的数据对象，如果尚未加载，则返回 null。
     */
    public function getData():Object {
        return this.combinedData;
    }
}



/*

import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;
import org.flashNight.gesh.object.ObjectUtil;

// 获取 ItemDataLoader 实例
var ItemDataLoader:ItemDataLoader = ItemDataLoader.getInstance();

// 加载物品数据
ItemDataLoader.loadItemData(
    function(combinedData:Object):Void {
        trace("主程序：物品数据加载成功！");
        // 在此处处理合并后的物品数据
		var itemDataDict = new Object();
		var itemDataArray = new Array();
		var itemNamesByID = new Object();
		var maxID = 0;
		var informationMaxValueDict = new Object();

		// 自动生成ID：完全忽略XML中的ID配置
		var autoIncrementID = 1;

		for(var i in combinedData){
			var itemData = combinedData[i];

			// 自动分配ID（忽略XML中的ID）
			itemData.id = autoIncrementID++;

			itemDataDict[itemData.name] = itemData;
			itemNamesByID[itemData.id] = itemData.name;
			itemDataArray.push(itemData);
			if(itemData.id > maxID) maxID = itemData.id;
			if(itemData.use =="情报") informationMaxValueDict[itemData.name] = itemData.maxvalue;
		}

		// 由于for...in遍历是反序的，需要反转数组以保持XML中的正序
		// 这样可以通过调整XML中物品的位置来直观控制显示顺序
		itemDataArray.reverse();

		org.flashNight.arki.item.ItemUtil.itemDataDict = itemDataDict;
		org.flashNight.arki.item.ItemUtil.itemDataArray = itemDataArray;
		org.flashNight.arki.item.ItemUtil.itemNamesByID = itemNamesByID;
		org.flashNight.arki.item.ItemUtil.maxID = maxID;
		org.flashNight.arki.item.ItemUtil.informationMaxValueDict = informationMaxValueDict;
		_root.物品属性列表 = itemDataDict;
        _root.物品属性数组 = itemDataArray;
		_root.id物品名对应表 = itemNamesByID;
		_root.物品最大id = maxID;
    },
    function():Void {
        trace("主程序：物品数据加载失败！");
    }
);

*/