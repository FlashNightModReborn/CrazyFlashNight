var craftinglistloader = org.flashNight.gesh.json.LoadJson.CraftingListLoader.getInstance();

//暂停外置大脑以等待任务数据加载完毕
this.stop();
var asloader = this;

craftinglistloader.loadCraftingList(
    function(data:Object):Void {
		trace("主程序：合成表数据加载成功！");
		var carftingDict = {};
		for(var category in data){
			var list = data[category];
			for(var i = 0; i < list.length; i++){
				var item = list[i];
				carftingDict[item.name] = item;
				if(isNaN(item.value)) item.value = 1;
			}
		}
		_root.改装清单 = data;
		_root.改装清单对象 = carftingDict;

		// 构建物品获取方式索引
		// 此时 _root.shops 和 _root.kshop_list 已由商城系统_兼容.as 加载完毕
		var obtainIndex = org.flashNight.arki.item.obtain.ItemObtainIndex.getInstance();
		obtainIndex.buildIndex(_root.改装清单, _root.shops, _root.kshop_list);

		asloader.play();
    },
    function():Void {
        trace("主程序：合成表数据加载失败！");
    }
);