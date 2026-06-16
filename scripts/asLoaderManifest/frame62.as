import org.flashNight.gesh.xml.LoadXml.ItemDataLoader;

打印加载内容("加载物品数据……");

// 获取 ItemDataLoader 实例
var ItemDataLoader:ItemDataLoader = ItemDataLoader.getInstance();

// 加载物品数据
ItemDataLoader.loadItemData(
    function(combinedData:Object):Void {
        trace("主程序：物品数据加载成功！");
		_root.发布消息("物品数据加载完毕");
		org.flashNight.arki.item.ItemUtil.loadItemData(combinedData);
    },
    function():Void {
        trace("主程序：物品数据加载失败！");
    }
);