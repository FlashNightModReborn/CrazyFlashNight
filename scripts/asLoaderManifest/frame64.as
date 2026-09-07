import org.flashNight.arki.unit.HeroUtil;

// 加载主角称号配置
HeroUtil.loadHeroConfig(
    function():Void {
        trace("主程序：主角称号配置加载成功！");
        _root.发布消息("主角称号配置加载完毕");
    },
    function():Void {
        trace("主程序：主角称号配置加载失败，使用默认配置！");
    }
);

import org.flashNight.gesh.xml.LoadXml.MaterialDictionaryLoader;

var 材料大全loader:MaterialDictionaryLoader = MaterialDictionaryLoader.getInstance();

材料大全loader.loadMaterialDictionary(
    function(data:Object):Void {
        trace("主程序：材料大全数据加载成功！");
		_root.发布消息("材料数据加载完毕");
		if(!_root.图鉴信息) _root.图鉴信息 = new Object();
		_root.图鉴信息.材料大全 = data.Material;
		_root.__boot.legacyMaterialDictionaryReady = true;
    },
    function():Void {
        trace("主程序：材料大全数据加载失败！");
		_root.__boot.legacyMaterialDictionaryFailed = true;
    }
);

// 地图静态内容由当前 Host 会话提供，S9 等待明确就绪；不存在第二份 AS2 规则。
org.flashNight.arki.map.MapDomainBridge.initialize();
