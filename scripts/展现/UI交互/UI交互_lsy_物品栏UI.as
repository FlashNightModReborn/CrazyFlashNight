// 旧物品栏/仓库/商店 renderer 已退役。
// 本文件保留现役领域服务使用的报价与入口门面；药剂输入和原生 HUD 由独立服务负责。
_root.物品UI函数 = new Object();

_root.物品UI函数.计算强化收益 = function(当前总价, 强化等级) {
	if (isNaN(强化等级)) 强化等级 = 1;
	var 每石最大收益 = 强化等级 * 100 + 700;
	var 强化石个数 = Math.pow((强化等级 - 2) * (强化等级 - 1) / 2, 2) + 强化等级 - 1;
	var 最大收益 = 强化石个数 * 每石最大收益;
	var 强化收益 = Math.floor(当前总价 * (Math.pow(强化等级 - 1, 4.2) / 216));
	if (强化收益 > 最大收益) 强化收益 = 最大收益;
	return 强化收益;
};

/**
 * NPC 商店领域仍以 AS2 数据为权威；Web 只消费计算结果。
 */
_root.物品UI函数.计算售卖总价 = function(item, 数量) {
	var result = {
		总价: 0,
		原总价: 0,
		基础价格: 0,
		售卖倍率: 0.25,
		tier价格: 0,
		强化收益: 0
	};

	if (!item || !item.name) return result;
	var itemData = ItemUtil.getRawItemData(item.name);
	if (!itemData || !itemData.price) return result;
	// 61计划的所有单卖/批售共用此报价，强化与档级材料不再产生循环套现收益。
	if (org.flashNight.arki.scene.Cf6Type61Service.isActive()
			&& (itemData.type == "武器" || itemData.type == "防具")) {
		result.基础价格 = Math.floor(Number(itemData.price) * 数量 * 0.25);
		result.总价 = result.基础价格;
		result.原总价 = result.基础价格;
		return result;
	}

	if (_root.主角被动技能.口才 && _root.主角被动技能.口才.启用) {
		result.售卖倍率 += _root.主角被动技能.口才.等级 * 0.025;
	}

	var 单价 = parseInt(itemData.price);
	result.基础价格 = Math.floor(单价 * 数量 * result.售卖倍率);
	result.总价 = result.基础价格;
	result.原总价 = Math.floor(单价 * 数量 * 0.25);

	if (item.value && item.value.tier) {
		var tierMaterialName = EquipmentUtil.tierNameToMaterialDict[item.value.tier];
		if (tierMaterialName) {
			var tierMaterialData = ItemUtil.getRawItemData(tierMaterialName);
			if (tierMaterialData && tierMaterialData.price) {
				var tierPrice = parseInt(tierMaterialData.price);
				if (!isNaN(tierPrice)) {
					result.tier价格 = Math.floor(tierPrice * result.售卖倍率);
					result.总价 += result.tier价格;
					result.原总价 += Math.floor(tierPrice * 0.25);
				}
			}
		}
	}

	if (item.value && item.value.level && item.value.level > 1) {
		result.强化收益 = this.计算强化收益(result.基础价格, item.value.level);
		result.总价 += result.强化收益;
	}
	return result;
};

/**
 * Web 批量售卖的 plain_only 策略判定。
 */
_root.物品UI函数.是否普通物品 = function(item:Object):Boolean {
	if (!item || !item.name) return false;
	var itemData = ItemUtil.getItemData(item.name);
	if (!itemData) return false;
	if (itemData.type != "武器" && itemData.type != "防具") return true;

	var val = item.value;
	if (!val) return true;
	if (val.level != null && val.level != undefined && val.level > 1) return false;
	if (val.tier != null && val.tier != undefined) return false;
	if (val.mods && val.mods.length > 0) return false;
	return true;
};

// 胶囊资格只沿真实手雷弹体与既有扣除回执链进入，不借 source 字符串放行。
_root.物品UI函数.登记胶囊投掷 = function(unit:MovieClip, projectile:MovieClip):Object {
    return org.flashNight.arki.item.NpcCapsuleShopService.registerShot(unit, projectile);
};
_root.物品UI函数.确认胶囊投掷 = function(shot:Object):Boolean {
    return org.flashNight.arki.item.NpcCapsuleShopService.confirmShot(shot);
};
_root.物品UI函数.打开胶囊便携商店 = function(projectile:MovieClip):Boolean {
    var opened:Boolean = org.flashNight.arki.item.NpcCapsuleShopService.openProjectile(projectile);
    if (!opened && typeof _root.发布消息 == "function") _root.发布消息("商店面板暂时不可用");
    return opened;
};

/**
 * 老地图/平板入口只做 shopId 解析；失败时不得再打开 Flash 商店。
 */
_root.物品UI函数.刷新商店图标 = function(NPC物品栏):Boolean {
	var NPC商店服务 = _root.UI系统 == undefined ? undefined : _root.UI系统.NPC商店WebView;
	if (NPC商店服务 != undefined && NPC商店服务.resolveShopIdByCatalog != undefined
			&& _root.gameCommands != undefined && _root.gameCommands["openNpcShop"] != undefined) {
		var NPC商店ID = NPC商店服务.resolveShopIdByCatalog(NPC物品栏);
		if (NPC商店ID != ""
				&& _root.gameCommands["openNpcShop"]({shopId:NPC商店ID, source:"npc_shop_refresh"})) {
			return true;
		}
	}
	if (typeof _root.发布消息 == "function") _root.发布消息("商店面板暂时不可用");
	return false;
};
