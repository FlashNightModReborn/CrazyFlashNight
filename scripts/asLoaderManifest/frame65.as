import org.flashNight.gesh.xml.LoadXml.InformationDictionaryLoader;

var 情报信息loader:InformationDictionaryLoader = InformationDictionaryLoader.getInstance();

情报信息loader.loadInformationDictionary(
    function(data:Object):Void {
        trace("主程序：情报信息数据加载成功！");
		_root.发布消息("情报数据加载完毕");
		if(!_root.图鉴信息) _root.图鉴信息 = new Object();
		_root.图鉴信息.情报信息 = new Object();
		_root.图鉴信息.情报显示位置表 = new Object();
		for(var i = 0; i < data.Item.length; i++){
			var item = data.Item[i];
			var info = item.Information;
			if(isNaN(info.length)){
				item.Information = [info];
			}
			_root.图鉴信息.情报信息[item.Name] = item;
			_root.图鉴信息.情报显示位置表[item.Index] = item.Name;
		}
    },
    function():Void {
        trace("主程序：情报信息数据加载失败！");
    }
);