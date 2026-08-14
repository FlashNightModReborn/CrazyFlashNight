import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;

打印加载内容("加载物品数据……");

// 获取 ItemDataLoader 实例
var ItemDataLoader:ItemDataLoader = ItemDataLoader.getInstance();

// 加载物品数据
ItemDataLoader.loadItemData(
    function(combinedData:Object):Void {
        if (!(combinedData instanceof Array)) {
			_root.__boot.itemDataFailed = true;
			return;
		}
        trace("主程序：物品数据加载成功！");
		_root.发布消息("物品数据加载完毕");
		// equipment-config 与 item-data 同属 S8 并发。先保存 raw payload，
		// 由 BootSequencer 在 config settled 后唯一调用 ItemUtil.loadItemData，
		// 避免 multiTierDict 固化旧 tierDataList。
		_root.__boot.itemDataPayload = combinedData;
		_root.__boot.itemDataLoaded = true;
    },
    function():Void {
        trace("主程序：物品数据加载失败！");
		_root.__boot.itemDataFailed = true;
    }
);
