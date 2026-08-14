// 装备配置数据
var equipconfig_loader = org.flashNight.gesh.xml.LoadXml.EquipmentConfigLoader.getInstance();

    equipconfig_loader.loadEquipmentConfig(
        function(data:Object):Void {
		if (data == null || typeof data != "object") {
			_root.__boot.equipmentConfigSettled = true;
			return;
		}
		trace("主程序：装备配置数据加载成功！");
		org.flashNight.arki.item.EquipmentUtil.loadEquipmentConfig(data);
		_root.__boot.equipmentConfigSettled = true;
    },
    function():Void {
		trace("主程序：装备配置数据加载失败，使用默认值！");
		// 保持现役 fallback：失败不阻断 boot，但 item projection 必须等到
		// 已明确落入默认配置分支后再执行。
		_root.__boot.equipmentConfigSettled = true;
    }
);

// 插件数据
var moddata_loader = org.flashNight.gesh.xml.LoadXml.EquipModListLoader.getInstance();

    moddata_loader.loadModData(
        function(data:Object):Void {
			if (data == null || !(data.mod instanceof Array)) {
				_root.__boot.equipmentModFailed = true;
				return;
			}
            org.flashNight.arki.item.EquipmentUtil.loadModData(data.mod);
			if (org.flashNight.arki.item.EquipmentUtil.modDict == undefined
					|| !(org.flashNight.arki.item.EquipmentUtil.modList instanceof Array)) {
				_root.__boot.equipmentModFailed = true;
				return;
			}
			_root.__boot.equipmentModReady = true;
        },
        function():Void {
			_root.__boot.equipmentModFailed = true;
        }
    );
