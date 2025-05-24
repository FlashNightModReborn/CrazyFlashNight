import org.flashNight.gesh.xml.LoadXml.BaseXMLLoader;
import org.flashNight.gesh.object.ObjectUtil;

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
     * 解析 list.xml 文件，根据其中内容，解析并合并其中的 XML 数据。
     * @param onLoadHandler 加载成功后的回调函数，接收合并后的数据作为参数。
     * @param onErrorHandler 加载失败后的回调函数。
     */
    public function loadItemData(onLoadHandler:Function, onErrorHandler:Function):Void {
        var self:ItemDataLoader = this;

        // 加载 list.xml 文件
        super.load(function(data:Object):Void {
            // trace("ItemDataLoader: list.xml 文件加载成功！");
            // trace("ItemDataLoader: list.xml 数据 = " + ObjectUtil.toString(data));

            if (!data || !data.items || !(data.items instanceof Array)) {
                // trace("ItemDataLoader: list.xml 数据结构不正确！");
                if (onErrorHandler != null) onErrorHandler();
                return;
            }

            var childXmlPaths:Array = data.items;
            // trace("ItemDataLoader: 需要加载的子 XML 文件列表 = " + ObjectUtil.toString(childXmlPaths));

            self.combinedData = [];

            // 开始加载子 XML 文件
            self.loadChildXmlFiles(childXmlPaths, 0, function():Void {
                // 将合并后的数据保存到基类的 data 属性中
                super.data = self.combinedData;

                // trace("ItemDataLoader: 所有子 XML 文件加载并合并成功！");
                // trace("ItemDataLoader: 合并后的数据 = " + ObjectUtil.toString(self.combinedData));
                if (onLoadHandler != null) onLoadHandler(self.combinedData);
            }, function():Void {
                // trace("ItemDataLoader: 加载子 XML 文件失败！");
                if (onErrorHandler != null) onErrorHandler();
            });
        }, function():Void {
            // trace("ItemDataLoader: list.xml 文件加载失败！");
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
        var self:ItemDataLoader = this;

        if (index >= paths.length) {
            // 所有文件加载完成
            onComplete();
            return;
        }

        var xmlFileName:String = paths[index];
        var xmlFilePath:String = path + xmlFileName;
        // trace("ItemDataLoader: 准备加载子 XML 文件 = " + xmlFilePath);

        var loader:BaseXMLLoader = new BaseXMLLoader(xmlFilePath);

        loader.load(function(childData:Object):Void {
            // trace("ItemDataLoader: 子 XML 文件加载成功 = " + xmlFilePath);
            // trace("ItemDataLoader: 子 XML 数据 = " + ObjectUtil.toString(childData));

            // 假设 childData.item 中的物品数据，合并到 combinedData 中
            self.combinedData = self.combinedData.concat(childData.item);

            // 递归加载下一个文件
            self.loadChildXmlFiles(paths, index + 1, onComplete, onError);
        }, function():Void {
            // trace("ItemDataLoader: 子 XML 文件加载失败 = " + xmlFilePath);
            onError();
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
		for(var i in combinedData){
			var itemData = combinedData[i];
			itemDataDict[itemData.name] = itemData;
			itemNamesByID[itemData.id] = itemData.name;
			itemDataArray.push(itemData);
			if(itemData.id > maxID) maxID = itemData.id;
			if(itemData.use =="情报") informationMaxValueDict[itemData.name] = itemData.maxvalue;
		}
		itemDataArray = org.flashNight.naki.Sort.QuickSort.adaptiveSort(itemDataArray, function(a, b) {
            return a.id - b.id; // Numeric comparison
        });
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