// 装备配置数据
var equipconfig_loader = org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader.getInstance();

equipconfig_loader.loadEquipmentConfig(
    function(data:Object):Void {
		trace("主程序：装备配置数据加载成功！");
		org.flashNight.arki.item.EquipmentUtil.loadEquipmentConfig(data);
    },
    function():Void {
		trace("主程序：装备配置数据加载失败，使用默认值！");
    }
);

// 插件数据
var moddata_loader = org.flashNight.gesh.xml.LoadXml.EquipModListLoader.getInstance();

moddata_loader.loadModData(
    function(data:Object):Void {
		org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
    },
    function():Void {
    }
);
